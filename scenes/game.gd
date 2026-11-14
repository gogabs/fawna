extends Node
## Cena do jogo. Existe igual no servidor e nos clientes (mesmo caminho na
## árvore, /root/Game), porque é por ela que passam as chamadas de rede.
##
## Fluxo:
##   cliente conecta -> pede para entrar (request_join)
##   servidor responde com a semente e os jogadores (welcome)
##   cliente anda sozinho e manda a posição (request_move_to)
##   servidor confere e avisa todos (player_moved), ou corrige (move_corrected)
##
## Primeira pessoa: W/S andam para frente e para trás, A/D de lado, Q/E giram
## 45°. Posições são contínuas, em casas (1 casa = 1,5 m). As setas não movem:
## operam o menu flutuante (FloatingMenu), onde fica o Caminheiro.

const WALK_SPEED := 1.8  # casas por segundo (cerca de 2,7 m/s; antes 1,5)
const BACK_FACTOR := 0.6  # andar de costas é mais devagar
## Ritmo dos passos: quantos passos por segundo enquanto a criatura anda.
## Os passos seguem o relógio, como uma animação, e não a distância andada.
## Para deixar mais rápido ou mais lento, mude só este número (3,3 é o ritmo escolhido pelo Gabs).
const STEPS_PER_SECOND := 3.3
const STEP_INTERVAL := 1.0 / STEPS_PER_SECOND
## Ao começar a andar, o primeiro passo sai na hora, a menos que o último
## tenha sido há bem pouco (toques rápidos na tecla não viram rajada).
const STEP_RESTART := 0.6 * STEP_INTERVAL
## Outra criatura conta como andando se a posição dela mudou há menos que
## isto (a posição chega a cada 0,1 s, às vezes com atraso).
const OTHER_WALK_GRACE := 0.25
## Foley de movimento (roupa de algodão e tornozeleira de conchas, que toda
## criatura usa). Tudo segue o mesmo relógio dos passos: a tornozeleira fica
## num tornozelo só, então soa a cada dois passos; cada farfalhar dura cerca
## de um segundo, então entra a cada três passos e um emenda no outro.
const ANKLET_EVERY := 2
const RUSTLE_EVERY := 3
const RUSTLE_FIRST := 2  # o som de início cobre os primeiros passos
const MIN_WALK_FOR_STOP := 0.2  # toques curtos na tecla não fazem som de parada
## Volumes do foley em relação aos passos (0 dB). Bem baixos, de propósito.
const TURN_RUSTLE_DB := -4.0
const START_STOP_DB := -4.0
const RUSTLE_DB := -16.0
const ANKLET_DB := -5.0
const SEND_INTERVAL := 0.1  # segundos entre envios da posição
const TURN_REPEAT := 0.2  # segurando Q/E, gira a cada tanto
const BUMP_SOUND_COOLDOWN := 0.45
const BUMP_SPEECH_COOLDOWN := 1.5
const COLLECT_REACH := 1.4  # casas, do centro da criatura ao centro da coisa
const HEARING_RADIUS := 8.0  # passos de outras criaturas são ouvidos até aqui
const SAVE_INTERVAL := 10.0  # segundos entre salvamentos, se algo mudou
const BED_VOLUME_DB := -22.0  # fundo do bioma
## Vento: forte nas trilhas e na beira da lagoa (lugares abertos), fraco no
## mato da pradaria e quase nada dentro do bosque.
const WIND_OPEN_DB := -12.0
const WIND_FIELD_DB := -24.0
const WIND_SHELTER_DB := -36.0
const WIND_LAKE_RADIUS := 4
const TRAIL_NOTICE_MS := 4000  # sair e voltar à trilha logo depois não repete o aviso
const MENU_ACTIONS := {
	"menu_cima": "cima", "menu_baixo": "baixo", "menu_esquerda": "esquerda", "menu_direita": "direita",
}

@onready var view: GameView = $View
@onready var sfx: AudioStreamPlayer = $Sfx
@onready var audio: SpatialAudio = $SpatialAudio
@onready var birds: Node = $Birds

var state: WorldState  # só no servidor
var _dirty := false
var _save_timer := 0.0

# Lado do cliente (inclusive quem hospeda)
var world: WorldGen
var my_id := 0
var players := {}  # id -> { "name", "pos": Vector2 }
var inventory := {}
var _pos := Vector2.ZERO  # posição local (o servidor confere)
var _heading := 0  # 0 norte, 1 nordeste... (Compass)
var _cell := WorldGen.NO_CELL
var _step_clock := STEP_INTERVAL  # segundos desde o último passo
var _walking := false
var _walk_time := 0.0  # segundos andando sem parar
var _step_count := 0  # passos desde que começou a andar (para o foley)
var _send_timer := 0.0
var _last_sent := Vector2.INF
var _turn_cooldown := 0.0
var _bump_sound_cooldown := 0.0
var _bump_speech_cooldown := 0.0
var _last_bump_thing := -1
var _others_step := {}  # id -> {"clock": s desde o último passo, "idle": s sem se mexer, "count": passos desde que começou}
var _auto_target: Variant = null  # testes: anda sozinho até este ponto
var _last_trail_notice := -100000
var _bed: AudioStreamPlayer  # ambiente de fundo do bioma
var _bed_biome := -1
var _wind: AudioStreamPlayer  # vento dos lugares abertos
var _wind_tween: Tween
var _caminheiro: Caminheiro
var _menu: FloatingMenu
## Vozes dos sons da própria criatura (passos, coleta...). Um passo novo vai
## para uma voz livre em vez de reiniciar a que ainda está tocando, então o
## fim do passo anterior não é cortado e os dois se sobrepõem naturalmente.
var _sfx_voices: Array[AudioStreamPlayer] = []


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	var err := Net.start()
	if err != OK:
		Speech.say("Não foi possível iniciar a conexão (erro %d)." % err)
		_back_to_menu()
		return

	if Net.is_server():
		_load_or_create_world()
	if Net.mode == Net.Mode.HOST:
		request_join.rpc_id(1, Net.player_name)
	elif Net.mode == Net.Mode.CLIENT:
		Speech.say("Conectando a %s..." % Net.address)


func _exit_tree() -> void:
	_save_world()
	Sounds.clear()
	BirdSongs.clear()


func _process(delta: float) -> void:
	if state != null:
		_save_timer += delta
		if _save_timer >= SAVE_INTERVAL:
			_save_timer = 0.0
			_save_world()
	if world == null or not players.has(my_id):
		return
	_turn_cooldown = maxf(_turn_cooldown - delta, 0.0)
	_bump_sound_cooldown = maxf(_bump_sound_cooldown - delta, 0.0)
	_bump_speech_cooldown = maxf(_bump_speech_cooldown - delta, 0.0)
	var before := _pos
	_walk(_wanted_motion() * delta)
	_step_clock += delta
	_tick_my_steps(_pos != before, delta)
	_tick_other_steps(delta)
	if _caminheiro != null:
		_caminheiro.update(_pos, delta)
	_send_timer += delta
	if _send_timer >= SEND_INTERVAL and _pos != _last_sent:
		_send_timer = 0.0
		_last_sent = _pos
		request_move_to.rpc_id(1, _pos)


func _unhandled_input(event: InputEvent) -> void:
	if world == null or not event.is_pressed():
		return
	# Setas: menu flutuante, sempre ativo.
	for action: String in MENU_ACTIONS:
		if event.is_action(action):
			if not event.is_echo() and _menu != null:
				Speech.say(_menu.press(MENU_ACTIONS[action]))
			get_viewport().set_input_as_handled()
			return
	# Girar aceita a tecla segurada (repetição), com um intervalo.
	for action: String in ["girar_esquerda", "girar_direita"]:
		if event.is_action(action):
			if _turn_cooldown <= 0.0 or not event.is_echo():
				_turn(-1 if action == "girar_esquerda" else 1)
			get_viewport().set_input_as_handled()
			return
	if event.is_echo():
		return
	if event.is_action("interagir"):
		_interact()
	elif event.is_action("inventario"):
		_say_inventory()
	elif event.is_action("ajuda"):
		_say_help()
	elif event.is_action("ouvir_arredores"):
		_say_surroundings()
	elif event.is_action("onde_estou"):
		Speech.say(Narrator.where_am_i(world, _pos, _heading))
	elif event.is_action("direcao"):
		Speech.say("Olhando para o %s." % Compass.name_of(_heading))
	elif event.is_action("quem_esta_aqui"):
		_say_who()
	elif event.is_action("repetir_fala"):
		Speech.repeat_last()
	else:
		return
	get_viewport().set_input_as_handled()


# --- Rede: pedidos dos clientes (executados no servidor) ---------------------

@rpc("any_peer", "call_local", "reliable")
func request_join(player_name: String) -> void:
	if not multiplayer.is_server():
		return
	var id := _sender_id()
	if state.players.has(id):
		return
	var pos := state.add_player(id, player_name)
	var accepted_name: String = state.players[id]["name"]
	print("[servidor] %s (peer %d) entrou em %s" % [accepted_name, id, pos])
	welcome.rpc_id(id, state.world.world_seed, state.snapshot(), state.inventory_of(id))
	for other_id in state.players:
		if other_id != id:
			player_joined.rpc_id(other_id, id, accepted_name, pos)


@rpc("any_peer", "call_local", "unreliable_ordered")
func request_move_to(pos: Vector2) -> void:
	if not multiplayer.is_server():
		return
	var id := _sender_id()
	var result := state.move_to(id, pos)
	if result["ok"]:
		player_moved.rpc(id, result["pos"])
	elif state.players.has(id):
		move_corrected.rpc_id(id, result["pos"])


@rpc("any_peer", "call_local", "reliable")
func request_collect(cell: Vector2i) -> void:
	if not multiplayer.is_server():
		return
	var id := _sender_id()
	var result := state.collect(id, cell)
	if result["ok"]:
		_dirty = true
		inventory_changed.rpc_id(id, state.inventory_of(id), "coletou", result["item"])
		for other_id in state.players:
			if other_id != id:
				player_collected.rpc_id(other_id, id, result["item"])
	elif state.players.has(id):
		action_failed.rpc_id(id, result["reason"], result.get("item", ""))


# --- Rede: avisos do servidor (executados nos clientes) ----------------------

@rpc("authority", "call_local", "reliable")
func welcome(world_seed: int, snapshot: Dictionary, my_inventory: Dictionary) -> void:
	my_id = multiplayer.get_unique_id()
	world = WorldGen.new(world_seed)
	players = snapshot
	inventory = my_inventory
	_pos = players[my_id]["pos"]
	_heading = 0
	_cell = WorldGen.cell_of(_pos)
	view.setup(world, players, my_id)
	view.heading = _heading
	audio.setup(world)
	audio.set_heading(_heading, false)
	birds.start_client(audio)
	_setup_caminheiro()
	Music.start()
	_update_listener()
	_update_biome_bed()
	_update_wind()
	var me: Dictionary = players[my_id]
	var others := players.size() - 1
	var company := "Você está só por enquanto." if others == 0 else \
		"Há mais %d criatura%s no mundo." % [others, "" if others == 1 else "s"]
	Speech.say("Boas-vindas ao Fawna, %s. %s %s Aperte H para ouvir os comandos." % [
		me["name"], Narrator.where_am_i(world, _pos, _heading), company])
	_run_auto_commands()


@rpc("authority", "call_local", "reliable")
func inventory_changed(new_inventory: Dictionary, verb: String, item: String) -> void:
	if world == null:
		return
	inventory = new_inventory
	if verb.is_empty():
		return
	_play(Sounds.pickup(item))
	var total := int(inventory.get(item, 0))
	var what := "Você %s %s." % [verb, Economy.item_text(item, 1)]
	Speech.say("%s Agora tem %d." % [what, total])


@rpc("authority", "call_local", "reliable")
func action_failed(reason: String, detail: String) -> void:
	if world == null:
		return
	match reason:
		"nada":
			Speech.say("Não há nada para coletar aqui. Chegue bem perto de uma árvore, de um arbusto ou da água.")
		"cheio":
			Speech.say("Você já carrega o máximo de %s." % Economy.ITEM_NAMES[detail][1])
		_:
			pass  # "devagar", "longe": ignora em silêncio


@rpc("authority", "call_local", "reliable")
func player_joined(id: int, player_name: String, pos: Vector2) -> void:
	if world == null:
		return
	players[id] = {"name": player_name, "pos": pos}
	view.queue_redraw()
	_play(Sounds.chime())
	Speech.say("%s chegou ao mundo." % player_name, false)


@rpc("authority", "call_local", "reliable")
func player_left(id: int) -> void:
	if world == null or not players.has(id):
		return
	var player_name: String = players[id]["name"]
	players.erase(id)
	_others_step.erase(id)
	view.queue_redraw()
	Speech.say("%s saiu do mundo." % player_name, false)


## Posição confirmada pelo servidor. A própria criatura já andou localmente,
## então só as outras são atualizadas aqui.
@rpc("authority", "call_local", "unreliable_ordered")
func player_moved(id: int, pos: Vector2) -> void:
	if world == null or not players.has(id) or id == my_id:
		return
	var old_pos: Vector2 = players[id]["pos"]
	players[id]["pos"] = pos
	view.queue_redraw()
	if old_pos.distance_to(pos) < 0.01:
		return
	var steps: Dictionary = _others_step.get(id, {"clock": STEP_INTERVAL, "idle": INF, "count": 0})
	if steps["idle"] >= OTHER_WALK_GRACE and steps["clock"] >= STEP_RESTART:
		steps["clock"] = 0.0  # começou a andar: primeiro passo na hora
		steps["count"] = 0
		_play_other(pos, Sounds.move_start(), START_STOP_DB)
		_play_other_step(pos, 0)
	steps["idle"] = 0.0
	_others_step[id] = steps


## Outra criatura coletou algo: o som sai de onde ela está.
@rpc("authority", "call_local", "reliable")
func player_collected(id: int, item: String) -> void:
	if world == null or not players.has(id) or id == my_id:
		return
	var pos: Vector2 = players[id]["pos"]
	if pos.distance_to(_pos) <= HEARING_RADIUS:
		audio.play_at_point(pos, Sounds.pickup(item))


## O servidor recusou a posição (rápido demais ou dentro de algo): volta.
@rpc("authority", "call_local", "reliable")
func move_corrected(pos: Vector2) -> void:
	if world == null:
		return
	_set_pos(pos)
	_last_sent = pos


# --- Mundo salvo (servidor) --------------------------------------------------

func _load_or_create_world() -> void:
	if not Net.new_world:
		state = WorldSave.load_state(Net.save_path)
	if state != null and Net.seed_from_cmdline and state.world.world_seed != Net.world_seed:
		print("[servidor] --seed diferente do mundo salvo; usando o mundo salvo (use --novo-mundo para recomeçar)")
	if state == null:
		state = WorldState.new(Net.world_seed)
		print("[servidor] mundo novo criado")
	else:
		print("[servidor] mundo carregado de %s" % ProjectSettings.globalize_path(Net.save_path))
	birds.start_server(state.world)
	print("[servidor] mundo único no ar, porta %d, semente %d" % [Net.port, state.world.world_seed])
	_dirty = true
	_save_world()


func _save_world() -> void:
	if state == null or not _dirty:
		return
	if WorldSave.save_state(state, Net.save_path):
		_dirty = false


# --- Conexão -----------------------------------------------------------------

func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		print("[servidor] peer %d conectou" % id)


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server() or not state.players.has(id):
		return
	print("[servidor] %s (peer %d) saiu" % [state.players[id]["name"], id])
	state.remove_player(id)
	birds.forget_peer(id)
	player_left.rpc(id)


func _on_connected_to_server() -> void:
	request_join.rpc_id(1, Net.player_name)


func _on_connection_failed() -> void:
	Speech.say("Não foi possível conectar ao servidor.")
	_back_to_menu()


func _on_server_disconnected() -> void:
	Speech.say("A conexão com o servidor caiu.")
	_back_to_menu()


func _back_to_menu() -> void:
	Net.stop()
	if DisplayServer.get_name() == "headless":
		get_tree().quit(1)
		return
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")


# --- Lado do jogador ---------------------------------------------------------

## Para onde as teclas mandam andar agora (em casas por segundo, no mundo).
func _wanted_motion() -> Vector2:
	if _auto_target != null:
		var to_target: Vector2 = _auto_target - _pos
		if to_target.length() < 0.1:
			_auto_target = null
			return Vector2.ZERO
		return to_target.normalized() * minf(WALK_SPEED, to_target.length() * 10.0)
	var ahead := Input.get_axis("andar_tras", "andar_frente")
	var side := Input.get_axis("passo_esquerda", "passo_direita")
	if ahead == 0.0 and side == 0.0:
		return Vector2.ZERO
	var motion := Compass.forward(_heading) * ahead + Compass.right(_heading) * side
	var speed := WALK_SPEED * (BACK_FACTOR if ahead < 0.0 else 1.0)
	return motion.normalized() * speed


## Anda com colisão: se bater de frente, tenta deslizar ao longo do
## obstáculo; se não der para andar nada, esbarra.
func _walk(motion: Vector2) -> void:
	if motion == Vector2.ZERO:
		return
	var target := _pos + motion
	if world.is_free(target):
		_set_pos(target)
		return
	var moved := false
	for part in [Vector2(motion.x, 0.0), Vector2(0.0, motion.y)]:
		if part != Vector2.ZERO and world.is_free(_pos + part):
			_set_pos(_pos + part)
			moved = true
	if not moved:
		_bump(target)


## Passos da própria criatura: seguem o relógio enquanto ela anda, num ritmo
## fixo, como uma animação. Parou, os passos param. O foley de movimento
## (início, farfalhar, conchas e parada) vai junto, no mesmo relógio.
func _tick_my_steps(moved: bool, delta: float) -> void:
	if not moved:
		if _walking and _walk_time >= MIN_WALK_FOR_STOP:
			_play(Sounds.move_stop(), true, START_STOP_DB)
		_walking = false
		return
	if not _walking:
		_walking = true
		_walk_time = 0.0
		if _step_clock >= STEP_RESTART:
			_step_clock = 0.0
			_step_count = 0
			_play(Sounds.move_start(), true, START_STOP_DB)
			_play_my_step()
		return
	_walk_time += delta
	if _step_clock >= STEP_INTERVAL:
		_step_clock = fmod(_step_clock, STEP_INTERVAL)
		_step_count += 1
		_play_my_step()


func _play_my_step() -> void:
	var cell := WorldGen.cell_of(_pos)
	_play(Sounds.footstep(world.biome_at(cell), world.thing_at(cell)), true)
	for sound: Array in _step_foley(_step_count):
		_play(sound[0], true, sound[1])


## Foley que acompanha o passo número n desde que a criatura começou a andar
## (n = 0 é o primeiro). Vale para ela e para as outras: [[som, volume], ...].
func _step_foley(n: int) -> Array:
	var sounds := []
	if n % ANKLET_EVERY == 0:
		sounds.append([Sounds.anklet(), ANKLET_DB])
	if n >= RUSTLE_FIRST and (n - RUSTLE_FIRST) % RUSTLE_EVERY == 0:
		sounds.append([Sounds.cloth_rustle(), RUSTLE_DB])
	return sounds


## Passos das outras criaturas: no mesmo ritmo, enquanto a posição delas muda.
func _tick_other_steps(delta: float) -> void:
	for id: int in _others_step:
		var steps: Dictionary = _others_step[id]
		steps["clock"] += delta
		var was_walking: bool = steps["idle"] < OTHER_WALK_GRACE
		steps["idle"] += delta
		if not players.has(id):
			continue
		if was_walking and steps["idle"] >= OTHER_WALK_GRACE:
			# Parou (a posição não muda há um tempinho): som de parada.
			if steps["count"] > 0:
				_play_other(players[id]["pos"], Sounds.move_stop(), START_STOP_DB)
		elif was_walking and steps["clock"] >= STEP_INTERVAL:
			steps["clock"] = fmod(steps["clock"], STEP_INTERVAL)
			steps["count"] += 1
			_play_other_step(players[id]["pos"], steps["count"])


func _set_pos(new_pos: Vector2) -> void:
	_pos = new_pos
	players[my_id]["pos"] = new_pos
	audio.move_listener(new_pos)
	view.queue_redraw()
	var cell := WorldGen.cell_of(new_pos)
	if cell != _cell:
		var old_cell := _cell
		_cell = cell
		_announce_arrival(old_cell, cell)
		_update_biome_bed()
		_update_wind()


## Esbarrou: o som vem de onde está o obstáculo, e a fala diz o que é.
func _bump(target: Vector2) -> void:
	var cell := world.blocker_at(target)
	var thing := world.thing_at(cell) if cell != WorldGen.NO_CELL else WorldGen.Thing.NADA
	if _bump_sound_cooldown <= 0.0:
		_bump_sound_cooldown = BUMP_SOUND_COOLDOWN
		var where := WorldGen.cell_center(cell) if thing != WorldGen.Thing.NADA else target
		audio.play_at_point(where, Sounds.bump(thing))
	if _bump_speech_cooldown <= 0.0 or thing != _last_bump_thing:
		_bump_speech_cooldown = BUMP_SPEECH_COOLDOWN
		_last_bump_thing = thing
		Speech.say("Fim do caminho." if thing == WorldGen.Thing.NADA else WorldGen.THING_NAMES[thing])


## Gira 45° (step -1 para a esquerda, 1 para a direita), com o clique da
## bússola soando na nova direção.
func _turn(step: int) -> void:
	_turn_cooldown = TURN_REPEAT
	_heading = posmod(_heading + step, Compass.STEPS)
	audio.play_compass(_heading)
	_play(Sounds.turn_rustle(), true, TURN_RUSTLE_DB)
	audio.set_heading(_heading)
	view.heading = _heading
	view.queue_redraw()


func _announce_arrival(old_cell: Vector2i, cell: Vector2i) -> void:
	var biome := world.biome_at(cell)
	if old_cell != WorldGen.NO_CELL and biome != world.biome_at(old_cell):
		Speech.say(WorldGen.BIOME_NAMES[biome])
	var thing := world.thing_at(cell)
	var old_thing := world.thing_at(old_cell) if old_cell != WorldGen.NO_CELL else WorldGen.Thing.NADA
	if thing == WorldGen.Thing.TRILHA or thing == WorldGen.Thing.PONTE:
		# Trilhas serpenteiam: só avisa ao entrar nelas (ou numa ponte), sem
		# repetir a cada beirada.
		var now := Time.get_ticks_msec()
		if thing != old_thing and (thing == WorldGen.Thing.PONTE or now - _last_trail_notice > TRAIL_NOTICE_MS):
			if old_thing != WorldGen.Thing.TRILHA or thing == WorldGen.Thing.PONTE:
				Speech.say(WorldGen.THING_NAMES[thing], false)
		_last_trail_notice = now
	elif thing != WorldGen.Thing.NADA:
		Speech.say(WorldGen.THING_NAMES[thing], false)


## Espaço: coleta o que estiver ao alcance, dando preferência ao que está à
## frente.
func _interact() -> void:
	var target := _collect_target()
	if target != WorldGen.NO_CELL:
		request_collect.rpc_id(1, target)
	else:
		action_failed("nada", "")


func _collect_target() -> Vector2i:
	var best := WorldGen.NO_CELL
	var best_score := INF
	var here := WorldGen.cell_of(_pos)
	var ahead := Compass.forward(_heading)
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var cell := here + Vector2i(dx, dy)
			if not Economy.COLLECT.has(world.thing_at(cell)):
				continue
			var offset := WorldGen.cell_center(cell) - _pos
			var distance := offset.length()
			if distance > COLLECT_REACH:
				continue
			var score := distance - (0.6 if distance > 0.01 and ahead.dot(offset / distance) > 0.5 else 0.0)
			if score < best_score:
				best_score = score
				best = cell
	return best


func _say_inventory() -> void:
	if Economy.items_text(inventory) == "nada":
		Speech.say("Você ainda não tem nada. Aperte Espaço perto de árvores, arbustos ou água para coletar.")
	else:
		Speech.say("Você tem %s." % Economy.items_text(inventory))


func _say_help() -> void:
	Speech.say("W e S: andar para frente e para trás. A e D: passo para o lado. Q e E: girar. Setas: menu flutuante, com o Caminheiro; esquerda e direita escolhem, seta para cima confirma e seta para baixo volta. A cada giro, a bússola dá um clique: agudo no norte, grave no sul, médio no leste e no oeste, abafado nas diagonais. F: para onde estou olhando. Espaço: coletar. I: inventário. Tab: ouvir os arredores. C: onde estou. P: quem está no mundo. R: repetir a última fala. Trilhas de terra ligam a Origem às outras regiões do mundo; o Tab diz onde fica a mais próxima.")


func _say_surroundings() -> void:
	var others := []
	for id in players:
		if id != my_id:
			others.append(players[id])
	Speech.say(Narrator.surroundings(world, _pos, _heading, others))


func _say_who() -> void:
	var names: PackedStringArray = []
	for id in players:
		var player_name: String = players[id]["name"]
		names.append(player_name + (" (você)" if id == my_id else ""))
	Speech.say("No mundo: %s." % ", ".join(names))


const SFX_VOICES := 8


## Toca um som da própria criatura. vary dá a passos uma leve variação de
## altura e volume, para dois passos iguais seguidos não soarem idênticos.
func _play(stream: AudioStream, vary := false, volume_db := 0.0) -> void:
	if stream == null:
		return
	if _sfx_voices.is_empty():
		_sfx_voices.append(sfx)
		for i in SFX_VOICES - 1:
			var voice := AudioStreamPlayer.new()
			voice.name = "Sfx_%d" % (i + 1)
			add_child(voice)
			_sfx_voices.append(voice)
	var voice: AudioStreamPlayer = null
	for candidate in _sfx_voices:
		if not candidate.playing:
			voice = candidate
			break
	if voice == null:  # todas tocando: reaproveita a que começou primeiro
		voice = _sfx_voices.pop_front()
		_sfx_voices.append(voice)
	voice.stream = stream
	voice.pitch_scale = randf_range(0.94, 1.06) if vary else 1.0
	voice.volume_db = volume_db + (randf_range(-1.5, 0.0) if vary else 0.0)
	voice.play()


## Passos de outras criaturas soam na posição delas (com HRTF, se instalado),
## com o mesmo foley de roupa e conchas da própria criatura.
func _play_other_step(pos: Vector2, n: int) -> void:
	if pos.distance_to(_pos) > HEARING_RADIUS:
		return
	var cell := WorldGen.cell_of(pos)
	_play_other(pos, Sounds.footstep(world.biome_at(cell), world.thing_at(cell)))
	for sound: Array in _step_foley(n):
		_play_other(pos, sound[0], sound[1])


func _play_other(pos: Vector2, stream: AudioStream, volume_db := 0.0) -> void:
	if stream != null and pos.distance_to(_pos) <= HEARING_RADIUS:
		audio.play_at_point(pos, stream, volume_db, true, true)


## Troca o ambiente de fundo quando a criatura muda de bioma, com um fade.
func _update_biome_bed() -> void:
	var biome := world.biome_at(WorldGen.cell_of(_pos))
	if biome == _bed_biome:
		return
	_bed_biome = biome
	var stream := Sounds.biome_bed(biome)
	if stream == null:
		return
	var old := _bed
	_bed = AudioStreamPlayer.new()
	_bed.stream = stream
	_bed.volume_db = -40.0
	add_child(_bed)
	_bed.play(randf() * stream.get_length())
	var tween := create_tween().set_parallel()
	tween.tween_property(_bed, "volume_db", BED_VOLUME_DB, 1.5)
	if old != null:
		tween.tween_property(old, "volume_db", -40.0, 1.5)
		tween.chain().tween_callback(old.queue_free)


## O vento sobe nas trilhas e perto da lagoa, e cai dentro do bosque.
func _update_wind() -> void:
	if not Net.has_local_player() or DisplayServer.get_name() == "headless":
		return
	if _wind == null:
		var stream := Sounds.open_wind()
		if stream == null:
			return
		_wind = AudioStreamPlayer.new()
		_wind.stream = stream
		_wind.volume_db = -60.0
		add_child(_wind)
		_wind.play(randf() * stream.get_length())
	var cell := WorldGen.cell_of(_pos)
	var target := WIND_FIELD_DB
	if world.is_trail(cell) or _near_lake(cell):
		target = WIND_OPEN_DB
	elif world.biome_at(cell) == WorldGen.Biome.BOSQUE:
		target = WIND_SHELTER_DB
	if _wind_tween != null:
		_wind_tween.kill()
	_wind_tween = create_tween()
	_wind_tween.tween_property(_wind, "volume_db", target, 2.5)


func _near_lake(cell: Vector2i) -> bool:
	var r := WIND_LAKE_RADIUS
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if world.thing_at(cell + Vector2i(dx, dy)) == WorldGen.Thing.LAGO:
				return true
	return false


func _update_listener() -> void:
	audio.move_listener(_pos)


func _sender_id() -> int:
	var id := multiplayer.get_remote_sender_id()
	return id if id != 0 else multiplayer.get_unique_id()



# --- Caminheiro e menu das setas ---------------------------------------------

func _setup_caminheiro() -> void:
	_caminheiro = Caminheiro.new()
	_caminheiro.name = "Caminheiro"
	add_child(_caminheiro)
	_caminheiro.setup(world, audio)
	_caminheiro.arrived.connect(_on_caminheiro_arrived)
	_caminheiro.lost.connect(func(): Speech.say("O cristal do Caminheiro se apagou: não achou caminho daqui."))
	_caminheiro.beacon_reached.connect(func(_p): view.queue_redraw())
	view.caminheiro = _caminheiro
	_menu = FloatingMenu.new(_menu_root)
	_menu.sound.connect(_on_menu_sound)


func _menu_root() -> Array:
	return [{"label": "Caminheiro", "open": _caminheiro_items}]


## Destinos do Caminheiro. Por enquanto, só a Origem.
func _caminheiro_items() -> Array:
	var items := [{"label": "Origem", "run": _track.bind(WorldGen.origin_point(), "Origem")}]
	if _caminheiro.active:
		items.append({"label": "Apagar o cristal", "run": _stop_tracking})
	return items


func _track(destination: Vector2, place_name: String) -> String:
	if _pos.distance_to(destination) <= Caminheiro.ARRIVE_RADIUS:
		_caminheiro.stop()
		return "Você já está na %s." % place_name
	if not _caminheiro.start(_pos, destination, place_name):
		return "O cristal do Caminheiro não achou caminho até a %s." % place_name
	view.queue_redraw()
	var meters := Compass.meters(_caminheiro.estimated_length())
	return "O cristal do Caminheiro brilha azul, rumo à %s, a uns %s pelas trilhas. Siga as batidas do coração." % [place_name, meters]


func _stop_tracking() -> String:
	_caminheiro.stop()
	view.queue_redraw()
	return "O cristal do Caminheiro se apagou."


func _on_caminheiro_arrived(place_name: String) -> void:
	_play(Sounds.chime())
	view.queue_redraw()
	Speech.say("Você chegou à %s. O cristal do Caminheiro se apaga." % place_name)


func _on_menu_sound(kind: String) -> void:
	match kind:
		"mover":
			_play(Sounds.ui_move())
		"abrir":
			_play(Sounds.ui_open())
		"confirmar":
			_play(Sounds.ui_confirm())
		"fechar":
			_play(Sounds.ui_close())


# --- Testes automáticos ------------------------------------------------------

## Só para testes: anda sozinho até um ponto (ou desiste depois de um tempo).
func _auto_walk(target: Vector2, timeout := 6.0) -> void:
	_auto_target = target
	var deadline := Time.get_ticks_msec() + int(timeout * 1000)
	while _auto_target != null and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_auto_target = null


func _run_auto_commands() -> void:
	if Net.auto_commands.is_empty():
		return
	for command in Net.auto_commands:
		await get_tree().create_timer(0.4).timeout
		match command:
			"N", "S", "L", "O":  # anda 1 casa nessa direção do mapa
				var dirs := {"N": Vector2.UP, "S": Vector2.DOWN, "L": Vector2.RIGHT, "O": Vector2.LEFT}
				await _auto_walk(_pos + dirs[command])
			"FRENTE":
				await _auto_walk(_pos + Compass.forward(_heading))
			"GIRAR_D":
				_turn(1)
			"GIRAR_E":
				_turn(-1)
			"DIRECAO":
				Speech.say("Olhando para o %s." % Compass.name_of(_heading))
			"ARREDORES":
				_say_surroundings()
			"ONDE":
				Speech.say(Narrator.where_am_i(world, _pos, _heading))
			"QUEM":
				_say_who()
			"PASSAROS":
				print("[teste] pássaros por perto: %d" % birds.bird_count())
			"ESPERAR":
				await get_tree().create_timer(1.0).timeout
			"ESPACO":
				_interact()
			"INV":
				_say_inventory()
			"MENU_CIMA", "MENU_BAIXO", "MENU_ESQUERDA", "MENU_DIREITA":
				Speech.say(_menu.press(command.trim_prefix("MENU_").to_lower()))
			"SEGUIR":  # segue o Caminheiro até ele se apagar (ou desistir)
				var deadline := Time.get_ticks_msec() + 120000
				while _caminheiro.active and Time.get_ticks_msec() < deadline:
					await _auto_walk(_caminheiro.current_beacon(), 20.0)
					await get_tree().process_frame
			"ORIGEM":
				await _auto_walk(WorldGen.origin_point())
			"SAIR":
				Net.stop()
				get_tree().quit()
