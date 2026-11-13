extends Node
## Cena do jogo. Existe igual no servidor e nos clientes (mesmo caminho na
## árvore, /root/Game), porque é por ela que passam as chamadas de rede.
##
## Fluxo:
##   cliente conecta -> pede para entrar (request_join)
##   servidor responde com a semente e os jogadores (welcome)
##   cliente pede para andar (request_move) -> servidor valida e avisa todos

const MOVE_REPEAT_SECONDS := 0.18
const HEARING_RADIUS := 8  # passos de outras criaturas são ouvidos até aqui

@onready var view: GameView = $View
@onready var sfx: AudioStreamPlayer = $Sfx
@onready var audio: SpatialAudio = $SpatialAudio

var state: WorldState  # só no servidor

# Lado do cliente (inclusive quem hospeda)
var world: WorldGen
var my_id := 0
var players := {}  # id -> { "name", "pos" }
var _waiting_move := false
var _move_cooldown := 0.0


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
		state = WorldState.new(Net.world_seed)
		print("[servidor] mundo único no ar, porta %d, semente %d" % [Net.port, Net.world_seed])
	if Net.mode == Net.Mode.HOST:
		request_join.rpc_id(1, Net.player_name)
	elif Net.mode == Net.Mode.CLIENT:
		Speech.say("Conectando a %s..." % Net.address)


func _process(delta: float) -> void:
	_move_cooldown = maxf(_move_cooldown - delta, 0.0)
	if world == null:
		return
	for action in ["mover_norte", "mover_sul", "mover_oeste", "mover_leste"]:
		if Input.is_action_pressed(action):
			_try_step(_action_dir(action))
			break


func _unhandled_input(event: InputEvent) -> void:
	if world == null or not event.is_pressed() or event.is_echo():
		return
	if event.is_action("ouvir_arredores"):
		_say_surroundings()
	elif event.is_action("onde_estou"):
		Speech.say(Narrator.where_am_i(world, _my_pos()))
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
	welcome.rpc_id(id, Net.world_seed, state.snapshot())
	for other_id in state.players:
		if other_id != id:
			player_joined.rpc_id(other_id, id, accepted_name, pos)


@rpc("any_peer", "call_local", "reliable")
func request_move(dir: Vector2i) -> void:
	if not multiplayer.is_server():
		return
	var id := _sender_id()
	var result := state.try_move(id, dir)
	if result["ok"]:
		player_moved.rpc(id, result["pos"])
	elif state.players.has(id):
		move_blocked.rpc_id(id, result["thing"])


# --- Rede: avisos do servidor (executados nos clientes) ----------------------

@rpc("authority", "call_local", "reliable")
func welcome(world_seed: int, snapshot: Dictionary) -> void:
	my_id = multiplayer.get_unique_id()
	world = WorldGen.new(world_seed)
	players = snapshot
	view.setup(world, players, my_id)
	audio.setup(world)
	_update_listener()
	var me: Dictionary = players[my_id]
	var others := players.size() - 1
	var company := "Você está só por enquanto." if others == 0 else \
		"Há mais %d criatura%s no mundo." % [others, "" if others == 1 else "s"]
	Speech.say("Boas-vindas ao Fawna, %s. %s %s Setas para andar, Tab para ouvir os arredores, C para saber onde está, P para saber quem está no mundo, R para repetir." % [
		me["name"], Narrator.where_am_i(world, me["pos"]), company])
	_run_auto_commands()


@rpc("authority", "call_local", "reliable")
func player_joined(id: int, player_name: String, pos: Vector2i) -> void:
	if world == null:
		return
	players[id] = {"name": player_name, "pos": pos}
	view.queue_redraw()
	_play(SoundBank.chime())
	Speech.say("%s chegou ao mundo." % player_name, false)


@rpc("authority", "call_local", "reliable")
func player_left(id: int) -> void:
	if world == null or not players.has(id):
		return
	var player_name: String = players[id]["name"]
	players.erase(id)
	view.queue_redraw()
	Speech.say("%s saiu do mundo." % player_name, false)


@rpc("authority", "call_local", "reliable")
func player_moved(id: int, pos: Vector2i) -> void:
	if world == null or not players.has(id):
		return
	var old_pos: Vector2i = players[id]["pos"]
	players[id]["pos"] = pos
	view.queue_redraw()
	if id == my_id:
		_waiting_move = false
		_update_listener()
		_play(SoundBank.footstep(world.biome_at(pos)))
		_announce_arrival(old_pos, pos)
	else:
		_play_other_step(pos)


@rpc("authority", "call_local", "reliable")
func move_blocked(thing: int) -> void:
	if world == null:
		return
	_waiting_move = false
	_play(SoundBank.bump())
	if thing == WorldGen.Thing.NADA:
		Speech.say("Fim do caminho.")
	else:
		Speech.say(WorldGen.THING_NAMES[thing])


# --- Conexão -----------------------------------------------------------------

func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		print("[servidor] peer %d conectou" % id)


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server() or not state.players.has(id):
		return
	print("[servidor] %s (peer %d) saiu" % [state.players[id]["name"], id])
	state.remove_player(id)
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

func _try_step(dir: Vector2i) -> void:
	if _waiting_move or _move_cooldown > 0.0:
		return
	_waiting_move = true
	_move_cooldown = MOVE_REPEAT_SECONDS
	request_move.rpc_id(1, dir)


func _announce_arrival(old_pos: Vector2i, pos: Vector2i) -> void:
	var biome := world.biome_at(pos)
	if biome != world.biome_at(old_pos):
		Speech.say(WorldGen.BIOME_NAMES[biome])
	var thing := world.thing_at(pos)
	if thing != WorldGen.Thing.NADA:
		Speech.say(WorldGen.THING_NAMES[thing], false)


func _say_surroundings() -> void:
	var others := []
	for id in players:
		if id != my_id:
			others.append(players[id])
	Speech.say(Narrator.surroundings(world, _my_pos(), others))


func _say_who() -> void:
	var names: PackedStringArray = []
	for id in players:
		var player_name: String = players[id]["name"]
		names.append(player_name + (" (você)" if id == my_id else ""))
	Speech.say("No mundo: %s." % ", ".join(names))


func _play(stream: AudioStream) -> void:
	sfx.stream = stream
	sfx.play()


## Passos de outras criaturas soam na posição delas (com HRTF, se instalado).
func _play_other_step(pos: Vector2i) -> void:
	var offset := pos - _my_pos()
	if absi(offset.x) + absi(offset.y) > HEARING_RADIUS:
		return
	audio.play_at(pos, SoundBank.footstep(world.biome_at(pos)))


func _update_listener() -> void:
	audio.move_listener(_my_pos())


func _my_pos() -> Vector2i:
	return players[my_id]["pos"] if players.has(my_id) else WorldGen.center()


func _sender_id() -> int:
	var id := multiplayer.get_remote_sender_id()
	return id if id != 0 else multiplayer.get_unique_id()


static func _action_dir(action: String) -> Vector2i:
	match action:
		"mover_norte":
			return Vector2i.UP
		"mover_sul":
			return Vector2i.DOWN
		"mover_oeste":
			return Vector2i.LEFT
	return Vector2i.RIGHT


# --- Testes automáticos ------------------------------------------------------

func _run_auto_commands() -> void:
	if Net.auto_commands.is_empty():
		return
	for command in Net.auto_commands:
		await get_tree().create_timer(0.4).timeout
		match command:
			"N", "S", "L", "O":
				var dirs := {"N": Vector2i.UP, "S": Vector2i.DOWN, "L": Vector2i.RIGHT, "O": Vector2i.LEFT}
				_waiting_move = false
				_move_cooldown = 0.0
				_try_step(dirs[command])
			"ARREDORES":
				_say_surroundings()
			"ONDE":
				Speech.say(Narrator.where_am_i(world, _my_pos()))
			"QUEM":
				_say_who()
			"ESPERAR":
				await get_tree().create_timer(1.0).timeout
			"SAIR":
				Net.stop()
				get_tree().quit()
