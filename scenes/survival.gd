extends Node
## Fome e frio na rede. Este nó existe igual no servidor e nos clientes
## (/root/Game/Survival), porque é por ele que passam as chamadas de rede.
##
## No servidor, a cada STEP_SECONDS, passa o corpo de cada criatura (Body.step)
## olhando a estação, a noite, o bioma, o fogo, o abrigo, a tocha e a água, e
## conta quem está zerado há tempo demais para desfalecer. No cliente, guarda
## as duas reservas, fala a frase quando uma piora de limiar e toca os sons do
## corpo (barriga, tremor) de vez em quando, mais seguido quanto pior.
##
## Barra sonora (ideia do Gabs): a cada 20 pontos que uma reserva cruza, para
## baixo ou para cima, um toque soa no estéreo, da direita (cheia) para a
## esquerda (vazia). A fome tem um toque, o calor outro. A barra visual fica no
## canto da tela (BodyBars).

const STEP_SECONDS := 1.0
## O servidor manda as reservas a cada tanto, e na hora em que um limiar muda.
const SEND_SECONDS := 5.0
## Sons do corpo: intervalo, em segundos, entre um e outro, por nível (1 a 3).
const SOUND_GAPS := [[50.0, 90.0], [22.0, 40.0], [9.0, 16.0]]
const BODY_DB := -10.0  # baixos: o corpo fala baixo
const WARM_DB := -12.0
const FAINT_SECONDS := 2.5  # do apagar até acordar no ponto seguro
const PING_DB := -4.0  # toque da barra sonora (era -8; Gabs pediu um pouco mais alto)
const PING_GAP := 0.35  # fome e calor mudando juntos: um toque depois do outro

# Servidor
var _step := 0.0
var _since_send := {}  # peer -> segundos desde o último envio
var _sent_levels := {}  # peer -> marcas enviadas (Body.level_of e Body.bar_step de cada reserva)
var _sent_soon := {}  # peer -> comida para passar já enviada (Body.spoiling_soon)

# Cliente
var food := Body.START
var warmth := Body.START
var _known := false  # já chegou a primeira notícia do servidor
var _levels := [0, 0]
var _bar_steps := [0, 0]
## Comida da bolsa para passar (item -> quantidade), para a Bolsa dizer.
var spoiling := {}
## O que a criatura veste ("manto" ou "") e o que há no pote selado (item -> n).
var worn := ""
var jar := {}  # posição de cada reserva na barra sonora (Body.bar_step)
var _bars: BodyBars
var _sound_wait := [0.0, 0.0]
var _out := false  # desfalecida: não anda até acordar
var _was_fire := false
var _fire_check := 0.0
var _rng := RandomNumberGenerator.new()


func _process(delta: float) -> void:
	var game := get_parent()
	if game.state != null:
		_step += delta
		if _step >= STEP_SECONDS:
			_server_step(_step)
			_step = 0.0
	if _known and game.world != null and not _out:
		_client_sounds(delta)


# --- Servidor ------------------------------------------------------------------

## O que cerca a criatura agora, para Body.step.
func context_of(peer: int) -> Dictionary:
	var game := get_parent()
	var state: WorldState = game.state
	var pos: Vector2 = state.players[peer]["pos"]
	var cell := WorldGen.cell_of(pos)
	var build: Dictionary = state.builds.at(cell)
	var shelter := not build.is_empty() and Crafting.is_large(str(build["kind"])) \
		and bool(build.get("done", false)) and Builds.inside(build, pos)
	# Só a fogueira aquece em volta, mais quanto mais madeira tem; o forno é
	# fechado e aquece o abrigo colado.
	var fire := false
	var fire_fuel := 0.0
	for other: Dictionary in state.builds.all():
		if other["kind"] == "fogueira" and state.builds.is_lit(int(other["id"])) \
				and WorldGen.cell_center(other["cell"]).distance_to(pos) <= Body.FIRE_REACH:
			fire = true
			fire_fuel = maxf(fire_fuel, state.builds.fuel_left(int(other["id"])) / Crafting.MAX_FUEL)
	var oven := shelter and state.builds.warm_oven(int(build["id"]))
	if state.world.thing_at(cell) == WorldGen.Thing.VAU:
		state.wet_left[peer] = Body.WET_SECONDS
	return {
		"season": DayCycle.season_of(game.daytime.world_day()),
		"night": game.daytime.is_night(),
		"biome": state.world.biome_at(cell),
		"fire": fire,
		"fire_fuel": fire_fuel,
		"shelter": shelter,
		"oven": oven,
		"cloak": state.worn_of(peer) == "manto",
		"torch": state.torch_left(peer) > 0.0,
		"wet": float(state.wet_left.get(peer, 0.0)) > 0.0,
		"species": state.species_of(peer),
		"day_seconds": game.daytime.day_seconds,
	}


func _server_step(seconds: float) -> void:
	var state: WorldState = get_parent().state
	for peer: int in state.players.keys():
		var entry := state.body_of(peer)
		var ctx := context_of(peer)
		var levels := Body.step(entry, seconds, ctx)
		_age_food(peer, seconds, ctx)
		if state.wet_left.has(peer):
			state.wet_left[peer] = float(state.wet_left[peer]) - seconds
			if float(state.wet_left[peer]) <= 0.0:
				state.wet_left.erase(peer)
		var empty := float(entry["food"]) <= 0.0 or float(entry["warmth"]) <= 0.0
		state.faint_clock[peer] = float(state.faint_clock.get(peer, 0.0)) + seconds if empty else 0.0
		if empty and float(state.faint_clock[peer]) >= Body.FAINT_SECONDS:
			_faint(peer)
			continue
		var marks := _marks_of(entry)
		_since_send[peer] = float(_since_send.get(peer, 0.0)) + seconds
		if marks != _sent_levels.get(peer, []) or float(_since_send[peer]) >= SEND_SECONDS:
			send_to(peer)


## O tempo passa na comida da bolsa: o que estraga vira comida estragada.
func _age_food(peer: int, seconds: float, ctx: Dictionary) -> void:
	var game := get_parent()
	var state: WorldState = game.state
	var days := seconds / float(ctx["day_seconds"]) * Body.spoil_factor(int(ctx["season"]), int(ctx["biome"]))
	var spoiled := state.age_food(peer, days)
	if not spoiled.is_empty():
		game._dirty = true
		game.inventory_changed.rpc_id(peer, state.inventory_of(peer), "", "")
		food_spoiled.rpc_id(peer, spoiled)
	var soon := Body.spoiling_soon(state.lots_of(peer))
	if soon != _sent_soon.get(peer, {}):
		_sent_soon[peer] = soon
		spoiling_state.rpc_id(peer, soon)


## Manda as reservas a quem é dono delas.
func send_to(peer: int) -> void:
	var state: WorldState = get_parent().state
	if not state.players.has(peer):
		return
	var entry := state.body_of(peer)
	_since_send[peer] = 0.0
	_sent_levels[peer] = _marks_of(entry)
	body_state.rpc_id(peer, float(entry["food"]), float(entry["warmth"]))


## A roupa vestida e o pote selado, para a Bolsa e o Equipamento.
func send_stash(peer: int) -> void:
	var state: WorldState = get_parent().state
	if state.players.has(peer):
		stash_state.rpc_id(peer, state.worn_of(peer), state.jar_of(peer))


## O que, ao mudar, faz o servidor mandar na hora: os limiares falados e as
## posições da barra sonora.
func _marks_of(entry: Dictionary) -> Array:
	return [Body.level_of(entry["food"]), Body.level_of(entry["warmth"]),
		Body.bar_step(entry["food"]), Body.bar_step(entry["warmth"])]


func forget_peer(peer: int) -> void:
	_since_send.erase(peer)
	_sent_soon.erase(peer)
	_sent_levels.erase(peer)


## A fome ou o frio venceram: a criatura apaga e acorda no ponto seguro mais
## próximo (o mesmo do Calado), perde metade dos recursos da bolsa e volta com
## a reserva vazia em Body.REVIVE.
func _faint(peer: int) -> void:
	var game := get_parent()
	var state: WorldState = game.state
	var entry := state.body_of(peer)
	var cause := "food" if float(entry["food"]) <= 0.0 else "warmth"
	for key: String in ["food", "warmth"]:
		entry[key] = maxf(float(entry[key]), Body.REVIVE)
	state.faint_clock[peer] = 0.0
	var spot: Vector2 = game.horrors.rescue_spot(peer)
	var lost := state.strip_half_resources(peer)
	state.teleport(peer, spot)
	if not lost.is_empty():
		game._dirty = true
		game.inventory_changed.rpc_id(peer, state.inventory_of(peer), "", "")
	game.player_moved.rpc(peer, spot)
	fainted.rpc_id(peer, spot, cause, not lost.is_empty())
	send_to(peer)
	print("[servidor] %s desfaleceu (%s): levado a %s, perdeu %s" % [state.players[peer]["name"], cause, spot, lost])


## Bolsa > comida > Comer.
@rpc("any_peer", "call_local", "reliable")
func request_eat(item: String) -> void:
	if not multiplayer.is_server():
		return
	var game := get_parent()
	var id: int = game._sender_id()
	var result: Dictionary = game.state.eat(id, item)
	if not result["ok"]:
		if game.state.players.has(id):
			eat_refused.rpc_id(id, str(result["reason"]), item)
		return
	game._dirty = true
	game.inventory_changed.rpc_id(id, game.state.inventory_of(id), "", "")
	ate.rpc_id(id, item, str(result["event"]))
	send_to(id)


## Bolsa > raiz > Assar: na fogueira acesa ao lado.
@rpc("any_peer", "call_local", "reliable")
func request_roast(item: String, amount: int) -> void:
	if not multiplayer.is_server():
		return
	var game := get_parent()
	var id: int = game._sender_id()
	var result: Dictionary = game.state.roast(id, item, amount, game.horrors._lit_fires(game.state.builds))
	if not result["ok"]:
		if game.state.players.has(id):
			roast_refused.rpc_id(id, str(result["reason"]))
		return
	game._dirty = true
	game.inventory_changed.rpc_id(id, game.state.inventory_of(id), "", "")
	roasted.rpc_id(id, str(result["into"]), int(result["amount"]))


## Espaço no forno aceso > uma receita (Cooking). Os ingredientes saem já; o
## que ela faz entra na bolsa depois dos segundos da receita.
@rpc("any_peer", "call_local", "reliable")
func request_cook(recipe: String) -> void:
	if not multiplayer.is_server():
		return
	var game := get_parent()
	var id: int = game._sender_id()
	var result: Dictionary = game.state.cook_start(id, recipe)
	if not result["ok"]:
		if game.state.players.has(id):
			cook_refused.rpc_id(id, str(result["reason"]), Cooking.missing_text(result.get("missing", {})))
		return
	game._dirty = true
	game.inventory_changed.rpc_id(id, game.state.inventory_of(id), "", "")
	cook_started.rpc_id(id, recipe, float(result["seconds"]))
	get_tree().create_timer(float(result["seconds"])).timeout.connect(_finish_cook.bind(id, recipe))


func _finish_cook(id: int, recipe: String) -> void:
	var game := get_parent()
	var made: Dictionary = game.state.cook_finish(id)
	if made.is_empty() or not game.state.players.has(id):
		return
	game._dirty = true
	game.inventory_changed.rpc_id(id, game.state.inventory_of(id), "", "")
	cooked.rpc_id(id, recipe, made)
	send_to(id)


## Bolsa > manto > Vestir; Equipamento > manto > Tirar.
@rpc("any_peer", "call_local", "reliable")
func request_wear(item: String) -> void:
	_stash_action("vestiu", func(state: WorldState, id: int): return state.wear(id, item))


@rpc("any_peer", "call_local", "reliable")
func request_take_off() -> void:
	_stash_action("tirou", func(state: WorldState, id: int): return state.take_off(id))


## Bolsa > pote selado > Guardar / Tirar.
@rpc("any_peer", "call_local", "reliable")
func request_jar_store(item: String, amount: int) -> void:
	_stash_action("guardou", func(state: WorldState, id: int): return state.jar_store(id, item, amount))


@rpc("any_peer", "call_local", "reliable")
func request_jar_take(item: String, amount: int) -> void:
	_stash_action("tirou_pote", func(state: WorldState, id: int): return state.jar_take(id, item, amount))


## Espaço no secador > Pendurar / Recolher.
@rpc("any_peer", "call_local", "reliable")
func request_rack_hang(build_id: int, item: String, amount: int) -> void:
	_rack_action(build_id, "pendurou", func(state: WorldState, id: int): return state.rack_hang(id, build_id, item, amount))


@rpc("any_peer", "call_local", "reliable")
func request_rack_gather(build_id: int) -> void:
	_rack_action(build_id, "recolheu", func(state: WorldState, id: int): return state.rack_gather(id, build_id))


func _stash_action(event: String, action: Callable) -> void:
	if not multiplayer.is_server():
		return
	var game := get_parent()
	var id: int = game._sender_id()
	var result: Dictionary = action.call(game.state, id)
	if not game.state.players.has(id):
		return
	if not result["ok"]:
		stash_refused.rpc_id(id, str(result["reason"]))
		return
	game._dirty = true
	game.inventory_changed.rpc_id(id, game.state.inventory_of(id), "", "")
	send_stash(id)
	stash_done.rpc_id(id, event, str(result.get("item", "")), int(result.get("amount", 1)))


func _rack_action(build_id: int, event: String, action: Callable) -> void:
	if not multiplayer.is_server():
		return
	var game := get_parent()
	var id: int = game._sender_id()
	var result: Dictionary = action.call(game.state, id)
	if not game.state.players.has(id):
		return
	if not result["ok"]:
		rack_refused.rpc_id(id, str(result["reason"]), float(result.get("left", 0.0)))
		return
	game._dirty = true
	game.inventory_changed.rpc_id(id, game.state.inventory_of(id), "", "")
	game.build_changed.rpc(game.state.builds.info(build_id), "secador", id, {})
	rack_done.rpc_id(id, event, result.get("items", {}), int(result.get("amount", 0)), float(result.get("seconds", 0.0)))


## J com a enxada na terra à frente, fora de obra: cava atrás de raízes.
@rpc("any_peer", "call_local", "reliable")
func request_dig(cell: Vector2i) -> void:
	if not multiplayer.is_server():
		return
	var game := get_parent()
	var id: int = game._sender_id()
	if game.state.riding.has(id):
		return  # montado, não cava
	var result: Dictionary = game.state.dig_roots(id, cell)
	if not game.state.players.has(id):
		return
	if result["ok"]:
		game._dirty = true
		var left_over: Dictionary = result["left_over"]
		game.inventory_changed.rpc_id(id, game.state.inventory_of(id), "desenterrou", "raiz", int(result["amount"]), {result["item"]: int(result["amount"])}, {}, result["kept"], left_over)
		game.resource_changed.rpc(result["cell"], game.state.harvest.info(result["cell"]), "coleta", id)
		if not left_over.is_empty():
			game.ground_changed.rpc(result["pile_cell"], game.state.ground.items_at(result["pile_cell"]), "sobrou", id, left_over)
	dug.rpc_id(id, str(result.get("reason", "")))


# --- Cliente -------------------------------------------------------------------

## As reservas chegaram. Na primeira vez (ao entrar), só guarda; depois, fala a
## frase de cada reserva que piorou de limiar.
@rpc("authority", "call_local", "reliable")
func body_state(new_food: float, new_warmth: float) -> void:
	food = new_food
	warmth = new_warmth
	var levels := [Body.level_of(food), Body.level_of(warmth)]
	if _known and not _out:
		for i in 2:
			if levels[i] > _levels[i]:
				Speech.say(Body.line("food" if i == 0 else "warmth", levels[i]), false)
				_play(BodySounds.growl() if i == 0 else BodySounds.shiver(), BODY_DB)
				_sound_wait[i] = _gap(levels[i])
	for i in 2:
		if levels[i] > 0 and _levels[i] == 0:
			_sound_wait[i] = _gap(levels[i])
	_levels = levels
	var steps := [Body.bar_step(food), Body.bar_step(warmth)]
	if _known and not _out:
		var delay := 0.0
		for i in 2:
			if steps[i] != _bar_steps[i]:
				_ping("food" if i == 0 else "warmth", steps[i], delay)
				delay += PING_GAP
	_bar_steps = steps
	_known = true
	_show_bars()


@rpc("authority", "call_local", "reliable")
func ate(item: String, event := "comeu") -> void:
	_play(BodySounds.eat(), BODY_DB)
	var text := "Você come %s." % Body.eat_text(item)
	if event == "enjoou":
		text += " O estômago revira: crua demais. Melhor assar na fogueira."
	Speech.say(text, false)


## Comida da bolsa estragou: diz o quê, de uma vez.
@rpc("authority", "call_local", "reliable")
func food_spoiled(items: Dictionary) -> void:
	var total := 0
	for item: String in items:
		total += int(items[item])
	Speech.say("%s %s." % [Economy.items_text(items).left(1).to_upper() + Economy.items_text(items).substr(1), "estragou" if total == 1 else "estragaram"], false)


@rpc("authority", "call_local", "reliable")
func spoiling_state(soon: Dictionary) -> void:
	spoiling = soon


@rpc("authority", "call_local", "reliable")
func roasted(into: String, amount: int) -> void:
	_play(BodySounds.roast(), BODY_DB)
	Speech.say("Você assa no fogo e fica com %s." % Economy.item_text(into, amount), false)


@rpc("authority", "call_local", "reliable")
func stash_state(new_worn: String, new_jar: Dictionary) -> void:
	worn = new_worn
	jar = new_jar
	get_parent()._sync_menu.call_deferred()


@rpc("authority", "call_local", "reliable")
func stash_done(event: String, item: String, amount: int) -> void:
	match event:
		"vestiu":
			Speech.say("Você veste o manto de fibra. Ele segura o calor, perto do fogo e longe dele.", false)
		"tirou":
			Speech.say("Você tira o manto e o guarda na bolsa.", false)
		"guardou":
			Speech.say("Você guarda %s no pote selado. Ali não estraga." % Economy.item_text(item, amount), false)
		"tirou_pote":
			Speech.say("Você tira %s do pote selado." % Economy.item_text(item, amount), false)


@rpc("authority", "call_local", "reliable")
func stash_refused(reason: String) -> void:
	match reason:
		"ja_veste":
			Speech.say("Você já veste um manto.")
		"sem_pote":
			Speech.say("Você não tem um pote selado.")
		"cheio":
			Speech.say("O pote selado está cheio: cabem %d em cada pote." % WorldState.JAR_CAPACITY)
		"nao_e_comida":
			Speech.say("Só comida vai no pote selado.")
		_:
			Speech.say("Não deu.")


@rpc("authority", "call_local", "reliable")
func rack_done(event: String, items: Dictionary, amount: int, seconds: float) -> void:
	if event == "recolheu":
		Speech.say("Você recolhe do varal %s." % Economy.items_text(items), false)
	else:
		Speech.say("Você pendura %d no varal. Seca em uns %s%s." % [amount, Builds._minutes_text(seconds),
			", com o calor da fogueira" if seconds < Builds.DRY_SECONDS else ""], false)


@rpc("authority", "call_local", "reliable")
func rack_refused(reason: String, left: float) -> void:
	match reason:
		"cheio":
			Speech.say("O varal está cheio: cabem %d." % Builds.RACK_CAPACITY)
		"nada":
			Speech.say("Não há nada pendurado.")
		"secando":
			Speech.say("Nada secou ainda. A primeira fica pronta em uns %s." % Builds._minutes_text(left))
		"longe":
			Speech.say("Chegue mais perto do secador.")
		"nao_seca":
			Speech.say("No varal só secam frutas e cogumelos.")
		_:
			Speech.say("Não deu.")


@rpc("authority", "call_local", "reliable")
func cook_started(recipe: String, seconds: float) -> void:
	Speech.say(str(Cooking.RECIPES.get(recipe, {}).get("say", "Você põe no forno.")), false)
	var steps := maxi(1, int(seconds / 2.0))
	for i in steps:
		get_tree().create_timer(1.0 + 2.0 * i).timeout.connect(_play.bind(BodySounds.roast(), BODY_DB))


@rpc("authority", "call_local", "reliable")
func cooked(recipe: String, made: Dictionary) -> void:
	var text := Economy.items_text(made)
	if recipe == "pote":
		Speech.say("O pote saiu do forno duro e vermelho: agora é um pote de argila. Com ele se faz ensopado.", false)
	else:
		Speech.say("Saiu do forno: %s. Está na bolsa." % text, false)


@rpc("authority", "call_local", "reliable")
func cook_refused(reason: String, detail: String) -> void:
	match reason:
		"sem_forno":
			Speech.say("Para cozinhar, chegue perto de um forno aceso.")
		"ocupado":
			Speech.say("Ainda há algo seu no forno. Espere sair.")
		"faltam":
			Speech.say("Falta %s na sua bolsa." % detail if not detail.is_empty() else "Faltam ingredientes na sua bolsa.")
		_:
			Speech.say("Isso não se faz no forno.")


@rpc("authority", "call_local", "reliable")
func roast_refused(reason: String) -> void:
	match reason:
		"sem_fogo":
			Speech.say("Para assar, chegue perto de uma fogueira acesa.")
		"sem_item":
			Speech.say("Acabou.")
		_:
			Speech.say("Isso não se assa.")


## Resposta da enxada na terra: o som da terra sempre; fala só quando há o que dizer.
@rpc("authority", "call_local", "reliable")
func dug(reason: String) -> void:
	_play(BodySounds.dig(), BODY_DB + 4.0)
	match reason:
		"terreno":
			Speech.say("Não há rama ao alcance. A raiz só sai de uma rama.")


@rpc("authority", "call_local", "reliable")
func eat_refused(reason: String, _item: String) -> void:
	match reason:
		"cheio":
			Speech.say("Você está de barriga cheia.")
		"sem_item":
			Speech.say("Acabou.")
		_:
			Speech.say("Isso não se come.")


## Apagou de fome ou de frio: o som se fecha, a criatura é levada e acorda
## no ponto seguro.
@rpc("authority", "call_local", "reliable")
func fainted(spot: Vector2, cause: String, lost_something := false) -> void:
	var game := get_parent()
	if game.world == null or _out:
		return
	_out = true
	_play(BodySounds.faint(), 0.0)
	await get_tree().create_timer(FAINT_SECONDS).timeout
	game._set_pos(spot)
	game._last_sent = spot
	_out = false
	var text := "A fome vence você, e tudo escurece. Você acorda em outro lugar, fraco, com o estômago doendo." if cause == "food" \
		else "O frio vence você, e tudo escurece. Você acorda em outro lugar, ainda tremendo."
	if lost_something:
		text += " A bolsa está mais leve."
	Speech.say(text)


## Um toque da barra sonora, depois de "delay" segundos.
func _ping(kind: String, step: int, delay: float) -> void:
	if DisplayServer.get_name() == "headless":
		print("[barra] %s na posição %d" % [kind, step])
		return
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	_play(BodySounds.ping(kind, step), PING_DB)


## A barra visual, criada na primeira notícia (só quem tem tela).
func _show_bars() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if _bars == null:
		_bars = BodyBars.new()
		_bars.name = "BarrasDoCorpo"
		add_child(_bars)
	_bars.show_values(food, warmth)


## Desfalecida: não anda até acordar.
func is_out() -> bool:
	return _out


## Quanto da velocidade de andar vale agora (abatida: mais devagar).
func speed_factor() -> float:
	return Body.speed_factor({"food": food, "warmth": warmth})


## Terceiro toque do C.
func status_text() -> String:
	return Body.status_text({"food": food, "warmth": warmth})


func _gap(level: int) -> float:
	var gap: Array = SOUND_GAPS[clampi(level - 1, 0, SOUND_GAPS.size() - 1)]
	return _rng.randf_range(gap[0], gap[1])


func _client_sounds(delta: float) -> void:
	for i in 2:
		if _levels[i] <= 0:
			continue
		_sound_wait[i] -= delta
		if _sound_wait[i] <= 0.0:
			_sound_wait[i] = _gap(_levels[i])
			_play(BodySounds.growl() if i == 0 else BodySounds.shiver(), BODY_DB)
	# Chegando perto do fogo com frio: um suspiro.
	_fire_check += delta
	if _fire_check < 1.0:
		return
	_fire_check = 0.0
	var game := get_parent()
	var fire := false
	if game.builds != null:
		for build: Dictionary in game.builds.all():
			if build["kind"] == "fogueira" and game.builds.is_lit(int(build["id"])) \
					and WorldGen.cell_center(build["cell"]).distance_to(game._pos) <= Body.FIRE_REACH:
				fire = true
				break
	if fire and not _was_fire and _levels[1] >= 1:
		_play(BodySounds.warm_sigh(), WARM_DB)
	_was_fire = fire


func _play(stream: AudioStream, volume_db: float) -> void:
	if stream == null or DisplayServer.get_name() == "headless":
		return
	get_parent()._play(stream, false, volume_db)
