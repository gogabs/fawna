extends Node
## Fome e frio na rede. Este nó existe igual no servidor e nos clientes
## (/root/Game/Survival), porque é por ele que passam as chamadas de rede.
##
## No servidor, a cada STEP_SECONDS, passa o corpo de cada criatura (Body.step)
## olhando a estação, a noite, o bioma, o fogo, o abrigo, a tocha e a água, e
## conta quem está zerado há tempo demais para desfalecer. No cliente, guarda
## as duas reservas, fala a frase quando uma piora de limiar e toca os sons do
## corpo (barriga, tremor) de vez em quando, mais seguido quanto pior.

const STEP_SECONDS := 1.0
## O servidor manda as reservas a cada tanto, e na hora em que um limiar muda.
const SEND_SECONDS := 5.0
## Sons do corpo: intervalo, em segundos, entre um e outro, por nível (1 a 3).
const SOUND_GAPS := [[50.0, 90.0], [22.0, 40.0], [9.0, 16.0]]
const BODY_DB := -10.0  # baixos: o corpo fala baixo
const WARM_DB := -12.0
const FAINT_SECONDS := 2.5  # do apagar até acordar no ponto seguro

# Servidor
var _step := 0.0
var _since_send := {}  # peer -> segundos desde o último envio
var _sent_levels := {}  # peer -> [nível da fome, nível do calor] enviados

# Cliente
var food := Body.START
var warmth := Body.START
var _known := false  # já chegou a primeira notícia do servidor
var _levels := [0, 0]
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
	var fire := false
	for spot: Vector2 in game.horrors._lit_fires(state.builds):
		if spot.distance_to(pos) <= Body.FIRE_REACH:
			fire = true
			break
	if state.world.thing_at(cell) == WorldGen.Thing.VAU:
		state.wet_left[peer] = Body.WET_SECONDS
	return {
		"season": DayCycle.season_of(game.daytime.world_day()),
		"night": game.daytime.is_night(),
		"biome": state.world.biome_at(cell),
		"fire": fire,
		"shelter": shelter,
		"torch": state.torch_left(peer) > 0.0,
		"wet": float(state.wet_left.get(peer, 0.0)) > 0.0,
		"species": state.species_of(peer),
		"day_seconds": game.daytime.day_seconds,
	}


func _server_step(seconds: float) -> void:
	var state: WorldState = get_parent().state
	for peer: int in state.players.keys():
		var entry := state.body_of(peer)
		var levels := Body.step(entry, seconds, context_of(peer))
		if state.wet_left.has(peer):
			state.wet_left[peer] = float(state.wet_left[peer]) - seconds
			if float(state.wet_left[peer]) <= 0.0:
				state.wet_left.erase(peer)
		var empty := float(entry["food"]) <= 0.0 or float(entry["warmth"]) <= 0.0
		state.faint_clock[peer] = float(state.faint_clock.get(peer, 0.0)) + seconds if empty else 0.0
		if empty and float(state.faint_clock[peer]) >= Body.FAINT_SECONDS:
			_faint(peer)
			continue
		var pair := [int(levels["food"]), int(levels["warmth"])]
		_since_send[peer] = float(_since_send.get(peer, 0.0)) + seconds
		if pair != _sent_levels.get(peer, []) or float(_since_send[peer]) >= SEND_SECONDS:
			send_to(peer)


## Manda as reservas a quem é dono delas.
func send_to(peer: int) -> void:
	var state: WorldState = get_parent().state
	if not state.players.has(peer):
		return
	var entry := state.body_of(peer)
	_since_send[peer] = 0.0
	_sent_levels[peer] = [Body.level_of(entry["food"]), Body.level_of(entry["warmth"])]
	body_state.rpc_id(peer, float(entry["food"]), float(entry["warmth"]))


func forget_peer(peer: int) -> void:
	_since_send.erase(peer)
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
	ate.rpc_id(id, item)
	send_to(id)


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
	_known = true


@rpc("authority", "call_local", "reliable")
func ate(item: String) -> void:
	_play(BodySounds.eat(), BODY_DB)
	Speech.say("Você come %s." % Body.FOODS.get(item, {}).get("eat", Economy.names_of(item)[0]), false)


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
