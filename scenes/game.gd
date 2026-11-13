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
const SAVE_INTERVAL := 10.0  # segundos entre salvamentos, se algo mudou

@onready var view: GameView = $View
@onready var sfx: AudioStreamPlayer = $Sfx
@onready var audio: SpatialAudio = $SpatialAudio

var state: WorldState  # só no servidor
var _dirty := false
var _save_timer := 0.0

# Lado do cliente (inclusive quem hospeda)
var world: WorldGen
var my_id := 0
var players := {}  # id -> { "name", "pos" }
var inventory := {}
var garden := {}
var _waiting_move := false
var _move_cooldown := 0.0
var _facing := Vector2i.UP  # última direção em que tentou andar
var _village_menu := false
var _minigame: Minigame = null
var _bed: AudioStreamPlayer  # ambiente de fundo do bioma
var _bed_biome := -1


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


func _process(delta: float) -> void:
	_move_cooldown = maxf(_move_cooldown - delta, 0.0)
	if state != null:
		_save_timer += delta
		if _save_timer >= SAVE_INTERVAL:
			_save_timer = 0.0
			_save_world()
	if world == null or _minigame != null or _village_menu:
		return
	for action in ["mover_norte", "mover_sul", "mover_oeste", "mover_leste"]:
		if Input.is_action_pressed(action):
			_try_step(_action_dir(action))
			break


func _unhandled_input(event: InputEvent) -> void:
	if world == null or _minigame != null or not event.is_pressed() or event.is_echo():
		return
	if _village_menu:
		_village_menu_input(event)
		get_viewport().set_input_as_handled()
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
	welcome.rpc_id(id, state.world.world_seed, state.snapshot(), state.inventory_of(id), state.garden)
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


@rpc("any_peer", "call_local", "reliable")
func request_collect(cell: Vector2i) -> void:
	if not multiplayer.is_server():
		return
	var id := _sender_id()
	var result := state.collect(id, cell)
	if result["ok"]:
		_dirty = true
		inventory_changed.rpc_id(id, state.inventory_of(id), "coletou", result["item"])
	elif state.players.has(id):
		action_failed.rpc_id(id, result["reason"], result.get("item", ""))


@rpc("any_peer", "call_local", "reliable")
func request_craft(recipe_name: String, success: bool) -> void:
	if not multiplayer.is_server():
		return
	var id := _sender_id()
	var result := state.craft(id, recipe_name, success)
	if result["ok"]:
		_dirty = true
		inventory_changed.rpc_id(id, state.inventory_of(id), "fez", result["item"])
	elif state.players.has(id) and result["reason"] == "faltam":
		action_failed.rpc_id(id, "faltam", recipe_name)


@rpc("any_peer", "call_local", "reliable")
func request_contribute() -> void:
	if not multiplayer.is_server():
		return
	var id := _sender_id()
	if not state.players.has(id) or state.players[id]["pos"] != WorldGen.center():
		return
	var result := state.contribute(id)
	if result["given"].is_empty():
		action_failed.rpc_id(id, "nada_para_horta", "")
		return
	_dirty = true
	var who: String = state.players[id]["name"]
	print("[servidor] %s entregou %s para a horta" % [who, Economy.items_text(result["given"])])
	inventory_changed.rpc_id(id, state.inventory_of(id), "", "")
	garden_changed.rpc(state.garden, id, who, result["given"], result["completed_stage"])
	_save_world()


# --- Rede: avisos do servidor (executados nos clientes) ----------------------

@rpc("authority", "call_local", "reliable")
func welcome(world_seed: int, snapshot: Dictionary, my_inventory: Dictionary, garden_state: Dictionary) -> void:
	my_id = multiplayer.get_unique_id()
	world = WorldGen.new(world_seed)
	players = snapshot
	inventory = my_inventory
	garden = garden_state
	view.setup(world, players, my_id)
	audio.setup(world)
	audio.set_village_level(int(garden.get("stage", 0)))
	Music.set_level(int(garden.get("stage", 0)))
	Music.start()
	_update_listener()
	_update_biome_bed()
	var me: Dictionary = players[my_id]
	var others := players.size() - 1
	var company := "Você está só por enquanto." if others == 0 else \
		"Há mais %d criatura%s no mundo." % [others, "" if others == 1 else "s"]
	Speech.say("Boas-vindas ao Fawna, %s. %s %s %s Aperte H para ouvir os comandos." % [
		me["name"], Narrator.where_am_i(world, me["pos"]), company, Narrator.garden_status(garden)])
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
			Speech.say("Não há nada para coletar aqui. Fique sobre um arbusto ou de frente para uma árvore ou para a água.")
		"cheio":
			Speech.say("Você já carrega o máximo de %s." % Economy.ITEM_NAMES[detail][1])
		"faltam":
			Speech.say("Faltam recursos para %s." % detail)
		"nada_para_horta":
			var missing := Economy.stage_missing(int(garden.get("stage", 0)), garden.get("delivered", {}))
			Speech.say("Você não tem o que a horta precisa agora: %s." % Economy.items_text(missing))
		_:
			pass  # "devagar", "longe": ignora em silêncio


@rpc("authority", "call_local", "reliable")
func garden_changed(garden_state: Dictionary, contributor_id: int, contributor_name: String, given: Dictionary, completed_stage: int) -> void:
	if world == null:
		return
	garden = garden_state
	var who := "Você" if contributor_id == my_id else contributor_name
	var text := "%s entregou %s para a %s." % [who, Economy.items_text(given), Economy.GARDEN_NAME]
	if completed_stage >= 0:
		_play(Sounds.fanfare())
		audio.set_village_level(int(garden["stage"]))
		Music.set_level(int(garden["stage"]))
		var stage_name: String = Economy.GARDEN_STAGES[completed_stage]["name"]
		var helpers: Array = garden.get("contributors", [])
		text += " A %s cresceu: agora é %s! Obrigado a %s." % [Economy.GARDEN_NAME, stage_name, ", ".join(PackedStringArray(helpers))]
		if int(garden["stage"]) < Economy.GARDEN_STAGES.size():
			text += " " + Narrator.garden_status(garden)
	else:
		text += " " + Narrator.garden_status(garden)
	Speech.say(text, contributor_id == my_id)


@rpc("authority", "call_local", "reliable")
func player_joined(id: int, player_name: String, pos: Vector2i) -> void:
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
		_play(Sounds.footstep(world.biome_at(pos)))
		_announce_arrival(old_pos, pos)
		_update_biome_bed()
	else:
		_play_other_step(pos)


@rpc("authority", "call_local", "reliable")
func move_blocked(thing: int) -> void:
	if world == null:
		return
	_waiting_move = false
	_play(Sounds.bump(thing))
	if thing == WorldGen.Thing.NADA:
		Speech.say("Fim do caminho.")
	else:
		Speech.say(WorldGen.THING_NAMES[thing])


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
	_facing = dir
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


## Espaço: na vila abre o menu; fora dela, coleta o que estiver por perto
## (primeiro onde está, depois à frente, depois ao redor).
func _interact() -> void:
	var pos := _my_pos()
	if pos == WorldGen.center():
		_open_village_menu()
		return
	var candidates := [pos, pos + _facing, pos + Vector2i.UP, pos + Vector2i.DOWN, pos + Vector2i.LEFT, pos + Vector2i.RIGHT]
	for cell: Vector2i in candidates:
		if Economy.COLLECT.has(world.thing_at(cell)):
			request_collect.rpc_id(1, cell)
			return
	action_failed("nada", "")


func _open_village_menu() -> void:
	_village_menu = true
	_play(Sounds.ui_open())
	Speech.say("Vila. 1: carpintaria, 2 madeiras viram 1 tábua. 2: jardinagem, 1 semente e 1 balde de água viram 1 muda. 3: entregar para a horta. 4: como está a horta. Esc para sair.")


func _village_menu_input(event: InputEvent) -> void:
	if event.is_action("ui_cancel"):
		_village_menu = false
		_play(Sounds.ui_close())
		Speech.say("Saiu do menu da vila.")
		return
	if not event is InputEventKey:
		return
	match (event as InputEventKey).physical_keycode:
		KEY_1, KEY_KP_1:
			_start_craft("carpintaria")
		KEY_2, KEY_KP_2:
			_start_craft("jardinagem")
		KEY_3, KEY_KP_3:
			_village_menu = false
			request_contribute.rpc_id(1)
		KEY_4, KEY_KP_4:
			Speech.say(Narrator.garden_status(garden))
		_:
			if event.is_action("inventario"):
				_say_inventory()


func _start_craft(recipe_name: String) -> void:
	var inputs: Dictionary = Economy.RECIPES[recipe_name]["inputs"]
	var missing := {}
	for item in inputs:
		var lacking: int = inputs[item] - int(inventory.get(item, 0))
		if lacking > 0:
			missing[item] = lacking
	if not missing.is_empty():
		Speech.say("Para %s faltam %s." % [recipe_name, Economy.items_text(missing)])
		return
	_village_menu = false
	var game: Minigame = CarpentryMinigame.new() if recipe_name == "carpintaria" else GardeningMinigame.new()
	_minigame = game
	add_child(game)
	game.finished.connect(_on_minigame_finished.bind(recipe_name))
	if not Net.auto_commands.is_empty():
		game._finish(true)  # testes automáticos pulam o minigame
		return
	game.start()


func _on_minigame_finished(success: bool, recipe_name: String) -> void:
	_minigame = null
	request_craft.rpc_id(1, recipe_name, success)


func _say_inventory() -> void:
	if Economy.items_text(inventory) == "nada":
		Speech.say("Você ainda não tem nada. Aperte Espaço perto de árvores, arbustos ou água para coletar.")
	else:
		Speech.say("Você tem %s." % Economy.items_text(inventory))


func _say_help() -> void:
	Speech.say("W, A, S e D, ou as setas: andar para norte, oeste, sul e leste. Espaço: coletar, ou abrir o menu quando estiver na vila. I: inventário. Tab: ouvir os arredores. C: onde estou. P: quem está no mundo. R: repetir a última fala. A vila fica no centro do mundo.")


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
	audio.play_at(pos, Sounds.footstep(world.biome_at(pos)))


## Troca o ambiente de fundo quando a criatura muda de bioma, com um fade.
func _update_biome_bed() -> void:
	var biome := world.biome_at(_my_pos())
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
	tween.tween_property(_bed, "volume_db", -16.0, 1.5)
	if old != null:
		tween.tween_property(old, "volume_db", -40.0, 1.5)
		tween.chain().tween_callback(old.queue_free)


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

## Só para testes: pede passos até chegar na vila (sem obstáculos no entorno).
func _walk_to_village_now() -> void:
	while _my_pos() != WorldGen.center():
		var d := WorldGen.center() - _my_pos()
		var dir := Vector2i(signi(d.x), 0) if d.x != 0 else Vector2i(0, signi(d.y))
		_waiting_move = false
		_move_cooldown = 0.0
		_try_step(dir)
		await get_tree().create_timer(0.3).timeout

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
			"ESPACO":
				_interact()
			"INV":
				_say_inventory()
			"CARPINTARIA":
				_start_craft("carpintaria")
			"JARDINAGEM":
				_start_craft("jardinagem")
			"HORTA":
				request_contribute.rpc_id(1)
			"VILA":
				_village_menu = false
				await _walk_to_village_now()
			"SAIR":
				Net.stop()
				get_tree().quit()
