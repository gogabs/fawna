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
## Volume dos passos (da própria criatura e das outras). Um pouco abaixo do
## arquivo original, para os passos não dominarem o ambiente.
const FOOTSTEP_DB := -3.0
## Foley de movimento (roupa de algodão e tornozeleira de conchas, que toda
## criatura usa). Tudo segue o mesmo relógio dos passos: a tornozeleira fica
## num tornozelo só, então soa a cada dois passos; cada farfalhar dura cerca
## de um segundo, então entra a cada três passos e um emenda no outro.
const ANKLET_EVERY := 2
const RUSTLE_EVERY := 3
const RUSTLE_FIRST := 2  # o som de início cobre os primeiros passos
const MIN_WALK_FOR_STOP := 0.2  # toques curtos na tecla não fazem som de parada
## Volumes do foley em relação aos passos (0 dB). Baixos, mas sem sumir
## debaixo dos passos: na 0.3.0 as conchas ficavam 13 dB e o farfalhar 16 dB
## abaixo deles, e não se ouvia nenhum dos dois.
const TURN_RUSTLE_DB := -4.0
const START_STOP_DB := -4.0
const RUSTLE_DB := -12.0
const ANKLET_DB := 0.0
const SEND_INTERVAL := 0.1  # segundos entre envios da posição
const TURN_REPEAT := 0.2  # segurando Q/E, gira a cada tanto
const BUMP_SOUND_COOLDOWN := 0.45
const BUMP_SPEECH_COOLDOWN := 1.5
const COLLECT_REACH := 1.4  # casas, do centro da criatura ao centro da coisa
## O bambu bloqueia a passagem, então o centro dele fica um pouco mais longe.
const STRIKE_REACH := 1.5
const TREE_FALL_REACH := 3.0  # a queda de uma árvore se ouve a 3x HEARING_RADIUS
const HARVEST_CHECK := 2.0  # segundos entre conferências do que rebrotou
const HEARING_RADIUS := 8.0  # passos de outras criaturas são ouvidos até aqui
const SAVE_INTERVAL := 10.0  # segundos entre salvamentos, se algo mudou
const BED_VOLUME_DB := -22.0  # fundo do bioma
## Vento: forte nas trilhas e na beira da lagoa (lugares abertos), fraco no
## mato da pradaria e quase nada dentro do bosque.
const WIND_OPEN_DB := -12.0
const WIND_FIELD_DB := -24.0
const WIND_SHELTER_DB := -36.0
## Escutar com atenção (segurar Tab): o vento, o fundo do bioma e a música
## baixam, e os sons dos recursos sobem. Um toque curto no Tab continua
## falando os arredores.
const FOCUS_HOLD := 0.35  # segundos segurando até virar escuta
const FOCUS_DUCK_DB := -14.0
const FOCUS_FADE := 0.4
const WIND_LAKE_RADIUS := 4
const SWING_COOLDOWN := 0.45  # segundos entre golpes do machado (J)
const SWING_TO_HIT := 0.12  # do sopro do golpe até a lâmina bater
const BUILD_REACH := 1.8  # casas: trabalhar numa obra (o servidor aceita até 1,9)
const BURN_CHECK := 2.0  # segundos entre conferências de fogueiras que apagaram
const CRAFT_KNOCKS := 3  # batidas ao fabricar uma arma
const REGION_CHANGE_DB := -4.0  # o sopro ao passar de uma região para outra (a -14 sumia sob o vento)
## Ao esbarrar de viés, o deslize que ainda conta como andar, em fração do passo.
const BUMP_SLIDE_MIN := 0.5
const TRAIL_NOTICE_MS := 4000  # sair e voltar à trilha logo depois não repete o aviso
const BAMBUZAL_CLOSED := "Bambuzal fechado. Siga a trilha, ou empunhe o machado para abrir caminho."
const BAMBUZAL_CLOSED_WIELDING := "Bambuzal fechado. Golpeie com J para abrir caminho, ou siga a trilha."
const MENU_ACTIONS := {
	"menu_cima": "cima", "menu_baixo": "baixo", "menu_esquerda": "esquerda", "menu_direita": "direita",
}

@onready var view: GameView = $View
@onready var sfx: AudioStreamPlayer = $Sfx
@onready var audio: SpatialAudio = $SpatialAudio
@onready var birds: Node = $Birds
@onready var horrors: Node = $Horrors

var state: WorldState  # só no servidor
var _dirty := false
var _save_timer := 0.0

# Lado do cliente (inclusive quem hospeda)
var world: WorldGen
var my_id := 0
var _server_version := ""  # vem do servidor ao entrar; vazio: servidor antigo, que não manda
var players := {}  # id -> { "name", "pos": Vector2 }
var inventory := {}  # a bolsa: item -> quantidade (ver Bag)
var wielded := ""  # o que a criatura tem nas mãos ("" = mãos livres)
var _swing_cooldown := 0.0
var harvest: Harvest  # espelho do que já foi colhido ou golpeado (o servidor manda)
var _harvest_timer := 0.0
var _server_harvest_timer := 0.0
var builds: Builds  # espelho das construções (o servidor manda)
var ground: Ground  # espelho dos itens soltos no chão (o servidor manda)
var _burn_timer := 0.0  # servidor: fogueiras que apagaram
var _pos := Vector2.ZERO  # posição local (o servidor confere)
var _heading := 0  # 0 norte, 1 nordeste... (Compass)
var _cell := WorldGen.NO_CELL
var _region := Vector2i.ZERO  # região em que a criatura está (para o som de mudança)
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
var _bed_tween: Tween
var _tab_down_ms := -1  # quando o Tab foi apertado (-1: solto)
var _focus := false  # escutando com atenção
var _focus_changed_now := false  # o vento acompanha a escuta mais rápido
var _caminheiro: Caminheiro
var _tracked_resource := WorldGen.NO_CELL  # recurso que o cristal procura (NO_CELL: um lugar)
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
		_server_harvest_timer += delta
		if _server_harvest_timer >= HARVEST_CHECK:
			_server_harvest_timer = 0.0
			# Bambu que rebrota sob uma criatura espera (Harvest.prune).
			var where := []
			for id in state.players:
				where.append(state.players[id]["pos"])
			if not state.harvest.prune(-1.0, where).is_empty():
				_dirty = true
		_burn_timer += delta
		if _burn_timer >= BURN_CHECK:
			_burn_timer = 0.0
			for build_id: int in state.builds.burn_out():
				_dirty = true
				build_changed.rpc(state.builds.info(build_id), "apagou", 0, {})
	if world == null or not players.has(my_id):
		return
	_turn_cooldown = maxf(_turn_cooldown - delta, 0.0)
	_bump_sound_cooldown = maxf(_bump_sound_cooldown - delta, 0.0)
	_bump_speech_cooldown = maxf(_bump_speech_cooldown - delta, 0.0)
	_swing_cooldown = maxf(_swing_cooldown - delta, 0.0)
	var before := _pos
	_walk(_wanted_motion() * delta)
	_step_clock += delta
	_tick_my_steps(_pos != before, delta)
	_tick_other_steps(delta)
	_harvest_timer += delta
	if _harvest_timer >= HARVEST_CHECK:
		_harvest_timer = 0.0
		var occupants := []
		for id in players:
			occupants.append(players[id]["pos"])
		if not harvest.prune(-1.0, occupants).is_empty():
			audio.refresh_resources()
	if _tab_down_ms >= 0 and not _focus and Time.get_ticks_msec() - _tab_down_ms >= int(FOCUS_HOLD * 1000.0):
		_set_focus(true)
	if _caminheiro != null:
		_caminheiro.update(_pos, delta, Compass.forward(_heading))
	_send_timer += delta
	if _send_timer >= SEND_INTERVAL and _pos != _last_sent:
		_send_timer = 0.0
		_last_sent = _pos
		request_move_to.rpc_id(1, _pos)


func _unhandled_input(event: InputEvent) -> void:
	if world != null and event.is_action("ouvir_arredores") and not event.is_echo():
		_on_listen_key(event.is_pressed())
		get_viewport().set_input_as_handled()
		return
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
	elif event.is_action("golpear"):
		_swing()
	elif event.is_action("ajuda"):
		_say_help()
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
	server_version.rpc_id(id, Updater.current_version())
	welcome.rpc_id(id, state.world.world_seed, state.snapshot(), state.inventory_of(id))
	equipment_changed.rpc_id(id, state.inventory_of(id), state.wielding(id), "", "")
	harvest_snapshot.rpc_id(id, state.harvest.snapshot())
	build_snapshot.rpc_id(id, state.builds.snapshot())
	ground_snapshot.rpc_id(id, state.ground.snapshot())
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


## Para onde a criatura olha. O servidor só usa isso para os horrores, que
## param quando são encarados.
@rpc("any_peer", "call_local", "reliable")
func request_heading(heading: int) -> void:
	if not multiplayer.is_server():
		return
	state.set_heading(_sender_id(), heading)


@rpc("any_peer", "call_local", "reliable")
func request_collect(cell: Vector2i) -> void:
	if not multiplayer.is_server():
		return
	var id := _sender_id()
	var result := state.collect(id, cell)
	if result["ok"]:
		_dirty = true
		var kept: Dictionary = result.get("kept", {})
		var left_over: Dictionary = result.get("left_over", {})
		inventory_changed.rpc_id(id, state.inventory_of(id), "coletou", result["item"], int(result["amount"]), result.get("parts", {}), result.get("extras", {}), kept, left_over)
		if not left_over.is_empty():
			ground_changed.rpc(result["pile_cell"], state.ground.items_at(result["pile_cell"]), "sobrou", id, left_over)
		resource_changed.rpc(cell, state.harvest.info(cell), "coleta", id)
		for other_id in state.players:
			if other_id != id:
				player_collected.rpc_id(other_id, id, result["item"])
	elif state.players.has(id):
		var detail := str(result.get("hits_left", "")) if result["reason"] == "golpear" else str(result.get("item", ""))
		action_failed.rpc_id(id, result["reason"], detail)


## Bolsa > item > Jogar: larga itens da bolsa no chão, onde a criatura está.
@rpc("any_peer", "call_local", "reliable")
func request_drop(item: String, amount: int) -> void:
	if not multiplayer.is_server():
		return
	var id := _sender_id()
	var result := state.drop(id, item, amount)
	if not result["ok"]:
		if state.players.has(id) and result["reason"] == "nao_tem":
			action_failed.rpc_id(id, "nao_tem", item)
		return
	_dirty = true
	inventory_changed.rpc_id(id, state.inventory_of(id), "", "")
	ground_changed.rpc(result["cell"], state.ground.items_at(result["cell"]), "largou", id, {item: int(result["amount"])})


## Espaço perto de um monte no chão: pega o que couber na carga.
@rpc("any_peer", "call_local", "reliable")
func request_pick_up(cell: Vector2i) -> void:
	if not multiplayer.is_server():
		return
	var id := _sender_id()
	var result := state.pick_up(id, cell)
	if not result["ok"]:
		if state.players.has(id) and result["reason"] == "cheio":
			action_failed.rpc_id(id, "cheio", "")
		return
	_dirty = true
	inventory_changed.rpc_id(id, state.inventory_of(id), "", "")
	ground_changed.rpc(cell, state.ground.items_at(cell), "pegou", id, result["taken"])


## Um golpe de machado num bambu (tecla J, com o machado empunhado). Quem
## liga a tecla confere aqui, no servidor, se o machado está empunhado.
@rpc("any_peer", "call_local", "reliable")
func request_strike(cell: Vector2i) -> void:
	if not multiplayer.is_server():
		return
	var id := _sender_id()
	# Só golpeia quem tem o machado nas mãos (o servidor confere).
	if state.wielding(id) != "machado":
		return
	_tell_others_handled(id, "golpeou")
	var result := state.strike(id, cell)
	if result["ok"]:
		_dirty = true
		resource_changed.rpc(cell, state.harvest.info(cell), "queda" if result["felled"] else "golpe", id)
	# Golpe em bambu já caído ou já recolhido: só o som do machado, sem fala.


@rpc("any_peer", "call_local", "reliable")
func request_equip(item: String) -> void:
	if not multiplayer.is_server():
		return
	var id := _sender_id()
	var result := state.equip(id, item)
	if not result["ok"]:
		if state.players.has(id):
			action_failed.rpc_id(id, result["reason"], result.get("item", ""))
		return
	_dirty = true
	equipment_changed.rpc_id(id, state.inventory_of(id), state.wielding(id), "empunhou", item)
	_tell_others_handled(id, "empunhou")


@rpc("any_peer", "call_local", "reliable")
func request_stow() -> void:
	if not multiplayer.is_server():
		return
	var id := _sender_id()
	var result := state.stow(id)
	if not result["ok"]:
		if state.players.has(id):
			action_failed.rpc_id(id, result["reason"], "")
		return
	_dirty = true
	equipment_changed.rpc_id(id, state.inventory_of(id), state.wielding(id), "guardou", result["item"])
	_tell_others_handled(id, "guardou")


## Golpe no ar, sem nada ao alcance: só soa, para quem está perto ouvir.
## O golpe que acerta o bambu é o request_strike.
@rpc("any_peer", "call_local", "reliable")
func request_swing() -> void:
	if not multiplayer.is_server():
		return
	var id := _sender_id()
	if state.wielding(id).is_empty():
		return
	_tell_others_handled(id, "golpeou")


## Fabricar > Construções > Iniciar à frente: começa uma obra na casa à
## frente da criatura.
@rpc("any_peer", "call_local", "reliable")
func request_build_start(kind: String, cell: Vector2i) -> void:
	if not multiplayer.is_server():
		return
	var id := _sender_id()
	var result := state.start_build(id, kind, cell)
	if not result["ok"]:
		if state.players.has(id):
			action_failed.rpc_id(id, "obra_" + result["reason"], "")
		return
	_dirty = true
	build_changed.rpc(state.builds.info(result["id"]), "iniciada", id, {})


## Espaço perto de uma obra: deposita, bate, acende ou alimenta o fogo.
@rpc("any_peer", "call_local", "reliable")
func request_build_work(build_id: int) -> void:
	if not multiplayer.is_server():
		return
	var id := _sender_id()
	var result := state.work_build(id, build_id)
	if not result["ok"]:
		if not state.players.has(id):
			return
		var detail := ""
		if result["reason"] == "faltam":
			detail = Crafting.missing_text(result["missing"])
		elif result["reason"] == "pronta":
			detail = state.builds.status_text(build_id)
		action_failed.rpc_id(id, "obra_" + result["reason"], detail)
		return
	_dirty = true
	if result["event"] in ["deposito", "abasteceu", "alimentou"]:
		equipment_changed.rpc_id(id, state.inventory_of(id), state.wielding(id), "", "")
	var extra := {}
	for key in ["deposited", "missing", "work_left", "next", "item", "sparks_left"]:
		if result.has(key):
			extra[key] = result[key]
	build_changed.rpc(state.builds.info(build_id), result["event"], id, extra)


## Espaço num marco pronto, com uma fogueira na mesma região: o nome do
## povoado, escolhido nas duas listas (índices em SettlementNames).
@rpc("any_peer", "call_local", "reliable")
func request_name_settlement(build_id: int, noun_index: int, adjective_index: int) -> void:
	if not multiplayer.is_server():
		return
	var id := _sender_id()
	var result := state.name_settlement(id, build_id, noun_index, adjective_index)
	if not result["ok"]:
		if state.players.has(id):
			action_failed.rpc_id(id, "nome_" + result["reason"], str(result.get("name", "")))
		return
	_dirty = true
	print("[servidor] %s fundou o povoado %s" % [state.players[id]["name"], result["name"]])
	build_changed.rpc(state.builds.info(build_id), "nomeado", id, {})


## Fabricar > Armas: faz uma arma com o que está na bolsa.
@rpc("any_peer", "call_local", "reliable")
func request_craft(weapon: String) -> void:
	if not multiplayer.is_server():
		return
	var id := _sender_id()
	var result := state.craft(id, weapon)
	if not result["ok"]:
		if state.players.has(id):
			var detail := Crafting.missing_text(result["missing"]) if result["reason"] == "faltam" else str(result.get("item", ""))
			action_failed.rpc_id(id, "arma_" + result["reason"], "%s|%s" % [weapon, detail])
		return
	_dirty = true
	crafted.rpc_id(id, state.inventory_of(id), weapon)
	_tell_others_handled(id, "fabricou")


func _tell_others_handled(id: int, verb: String) -> void:
	for other_id in state.players:
		if other_id != id:
			player_handled.rpc_id(other_id, id, verb)


# --- Rede: avisos do servidor (executados nos clientes) ----------------------

## Versão do servidor, mandada logo antes do welcome. Servidor e jogo em
## versões diferentes geram mundos diferentes (ex.: o jogo acha um arbusto com
## gravetos onde o servidor não vê nada para coletar), então quem joga é
## avisado. Servidor anterior à 0.5.1 não manda a versão: o aviso sai igual.
@rpc("authority", "call_local", "reliable")
func server_version(version: String) -> void:
	_server_version = version


func _warn_version_mismatch() -> void:
	var mine := Updater.current_version()
	if _server_version == mine or multiplayer.is_server():
		return
	var theirs := _server_version if not _server_version.is_empty() else "anterior à %s" % mine
	print("[rede] servidor na versão %s, jogo na %s" % [theirs, mine])
	Speech.say("Atenção: o servidor está numa versão diferente da sua (servidor %s, jogo %s). Coletar e outras ações podem falhar até o servidor ser atualizado." % [theirs, mine], false)


@rpc("authority", "call_local", "reliable")
func welcome(world_seed: int, snapshot: Dictionary, my_inventory: Dictionary) -> void:
	my_id = multiplayer.get_unique_id()
	world = WorldGen.new(world_seed)
	players = snapshot
	inventory = my_inventory
	_pos = players[my_id]["pos"]
	_heading = 0
	_cell = WorldGen.cell_of(_pos)
	_region = world.region_of(_cell)
	harvest = Harvest.new(world)
	builds = Builds.new(world)
	ground = Ground.new()
	view.setup(world, players, my_id)
	view.heading = _heading
	audio.setup(world, harvest)
	audio.set_heading(_heading, false)
	birds.start_client(audio)
	horrors.start_client(audio)
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
	_warn_version_mismatch()
	_run_auto_commands()


## O que já foi colhido ou golpeado por perto, para quem acabou de entrar.
@rpc("authority", "call_local", "reliable")
func harvest_snapshot(data: Dictionary) -> void:
	if world == null:
		return
	harvest.apply_snapshot(data)
	audio.refresh_resources()


## Os itens que já estão no chão, para quem acabou de entrar.
@rpc("authority", "call_local", "reliable")
func ground_snapshot(data: Dictionary) -> void:
	if world == null:
		return
	ground.apply_snapshot(data)
	audio.set_piles(ground.cells())


## O monte de uma casa mudou. event: "largou" e "pegou" (alguém mexeu no
## monte) ou "sobrou" (não coube na carga ao coletar). O som sai do monte;
## quem agiu ouve também a fala. "moved" é o que mudou de lugar.
@rpc("authority", "call_local", "reliable")
func ground_changed(cell: Vector2i, items: Dictionary, event: String, by_id: int, moved: Dictionary) -> void:
	if world == null:
		return
	ground.apply_pile(cell, items)
	audio.set_piles(ground.cells())
	var where := WorldGen.cell_center(cell)
	var near := where.distance_to(_pos) <= HEARING_RADIUS
	if near and event != "pegou":
		audio.play_at_point(where, Sounds.drop_item(), 0.0, true, true)
	elif near and by_id != my_id:
		audio.play_at_point(where, Sounds.stow(), 0.0, true, true)
	if by_id != my_id:
		return
	match event:
		"largou":
			Speech.say("Você largou %s no chão. %s." % [Economy.items_text(moved), Bag.load_label(inventory, wielded)])
		"pegou":
			_play(Sounds.pickup(Economy.base_of(moved.keys()[0])))
			var rest := "" if items.is_empty() else " Ficou %s no chão: a carga não aguenta." % Economy.items_text(items)
			Speech.say("Você pegou %s. %s.%s" % [Economy.items_text(moved), Bag.load_label(inventory, wielded), rest])
		"sobrou":
			pass  # quem coletou já ouviu o que ficou no chão (inventory_changed)


## O que há no monte desta casa, para a fala.
func _pile_text(cell: Vector2i) -> String:
	return Economy.items_text(ground.items_at(cell))


## Um recurso mudou: golpe num bambu, bambu derrubado ou algo recolhido. O
## som sai de onde está o recurso; quem agiu ouve também a fala.
@rpc("authority", "call_local", "reliable")
func resource_changed(cell: Vector2i, data: Dictionary, event: String, by_id: int) -> void:
	if world == null:
		return
	harvest.apply_info(cell, data)
	var where := WorldGen.cell_center(cell)
	var near := where.distance_to(_pos) <= HEARING_RADIUS
	var tree := world.thing_at(cell) == WorldGen.Thing.ARVORE
	match event:
		"golpe":
			if near:
				audio.play_at_point(where, Sounds.tree_knock() if tree else Sounds.bamboo_knock(), 0.0, true, true)
				# Nos últimos golpes o tronco range: avisa que falta pouco.
				if tree and harvest.hits_left(cell) <= Harvest.CREAK_HITS:
					audio.play_at_point(where, Sounds.tree_creak(), 0.0, true, true)
		"queda":
			# A queda de uma árvore se ouve de mais longe.
			var reach := HEARING_RADIUS * (TREE_FALL_REACH if tree else 1.0)
			if where.distance_to(_pos) <= reach:
				audio.play_at_point(where, Sounds.tree_knock() if tree else Sounds.bamboo_knock(), 0.0, true, true)
				audio.play_at_point(where, Sounds.tree_fall() if tree else Sounds.bamboo_fall())
			if by_id == my_id:
				Speech.say("A árvore caiu. A passagem está aberta. Aperte Espaço para recolher a madeira e a lenha." if tree \
						else "O bambu caiu. Aperte Espaço para recolher.")
	audio.refresh_resources()


## As construções que já existem, para quem acabou de entrar.
@rpc("authority", "call_local", "reliable")
func build_snapshot(data: Array) -> void:
	if world == null:
		return
	builds.apply_snapshot(data)
	_refresh_fires()


## Uma construção mudou. O som sai da obra (para quem está perto); quem agiu
## ouve também a fala. event: ver Builds.work, mais "iniciada" e "apagou".
@rpc("authority", "call_local", "reliable")
func build_changed(data: Dictionary, event: String, by_id: int, extra: Dictionary) -> void:
	if world == null:
		return
	builds.apply_info(data)
	var build_id := int(data["id"])
	var build := builds.get_build(build_id)
	var where := WorldGen.cell_center(build["cell"])
	var near := where.distance_to(_pos) <= HEARING_RADIUS
	var mine := by_id == my_id
	var title := builds.title_of(build_id)
	var stream: AudioStream = {
		"iniciada": Sounds.build_deposit(), "deposito": Sounds.build_deposit(), "trabalho": Sounds.build_knock(),
		"etapa": Sounds.build_stage(), "pronta": Sounds.build_done(), "faisca": Sounds.fire_spark(),
		"acesa": Sounds.fire_ignite(), "abasteceu": Sounds.fire_feed(), "alimentou": Sounds.fire_feed(),
		"apagou": Sounds.fire_out(), "nomeado": Sounds.build_done(),
	}.get(event)
	if near and stream != null:
		audio.play_at_point(where, stream, 0.0, true, event in ["trabalho", "faisca", "deposito"])
	_refresh_fires()
	if event == "apagou":
		if where.distance_to(_pos) <= HEARING_RADIUS * 1.5:
			Speech.say("A fogueira apagou: acabou a lenha.", false)
		return
	if not mine:
		return
	match event:
		"iniciada":
			var what := ("um " if Crafting.BUILDS[build["kind"]]["article"] == "o" else "uma ") + Crafting.build_name(build["kind"])
			Speech.say("Você começou %s à frente. %s Espaço perto da obra deposita o que você tiver na bolsa. O Caminheiro sabe voltar aqui, em Construções." % [
				what, builds.status_text(build_id).trim_prefix(title + " em obra. ")])
		"deposito":
			var put := "Você colocou %s." % Crafting.materials_text(extra.get("deposited", {}))
			var missing: Dictionary = extra.get("missing", {})
			if missing.is_empty():
				var left := builds.work_left(build_id)
				Speech.say("%s Materiais completos. Espaço para trabalhar: %d batida%s." % [put, left, "" if left == 1 else "s"])
			else:
				Speech.say("%s %s." % [put, Crafting.missing_text(missing).left(1).to_upper() + Crafting.missing_text(missing).substr(1)])
		"etapa":
			var missing := builds.stage_missing(build_id)
			Speech.say("Etapa concluída. Agora %s: %s." % [extra.get("next", ""),
				Crafting.missing_text(missing) if not missing.is_empty() else "Espaço para trabalhar"])
		"pronta":
			if build["kind"] == "marco":
				Speech.say("O marco está pronto. %s" % (
					"Espaço nele para dar nome ao povoado." if builds.can_name(build_id) else
					"Com uma fogueira nesta região, o lugar vira um povoado."))
			else:
				var minutes := ceili(builds.fuel_left(build_id) / 60.0)
				Speech.say("A fogueira está pronta, com lenha para uns %d minuto%s. Espaço bate as pedras para acender.%s" % [
					minutes, "" if minutes == 1 else "s",
					" Com o marco desta região, o lugar já pode virar um povoado: Espaço no marco para dar o nome." if builds.has_unnamed_marco(build["region"]) else ""])
		"nomeado":
			Speech.say("Este povoado agora se chama %s. Ele aparece em Locais, no Caminheiro." % build["name"])
		"acesa":
			var minutes := ceili(builds.fuel_left(build_id) / 60.0)
			Speech.say("A fogueira pegou fogo, com lenha para uns %d minuto%s. Espaço põe mais lenha." % [minutes, "" if minutes == 1 else "s"])
		"abasteceu", "alimentou":
			var minutes := ceili(builds.fuel_left(build_id) / 60.0)
			Speech.say("Você pôs uma %s. Lenha para uns %d minuto%s." % [
				Crafting.material_text(extra.get("item", ""), 1).trim_prefix("1 "), minutes, "" if minutes == 1 else "s"])


## Uma arma ficou pronta e foi para a bolsa.
@rpc("authority", "call_local", "reliable")
func crafted(new_bag: Dictionary, weapon: String) -> void:
	if world == null:
		return
	inventory = new_bag
	for i in CRAFT_KNOCKS:
		get_tree().create_timer(0.3 * i).timeout.connect(_play.bind(Sounds.build_knock(), true))
	get_tree().create_timer(0.3 * CRAFT_KNOCKS).timeout.connect(_play.bind(Sounds.build_stage()))
	Speech.say("Você fabricou %s %s. Está na bolsa: empunhe pela Bolsa, no menu das setas." % [
		"uma" if Crafting.WEAPONS[weapon]["article"] == "a" else "um", Crafting.weapon_name(weapon)])


@rpc("authority", "call_local", "reliable")
func inventory_changed(new_inventory: Dictionary, verb: String, item: String, amount := 1, parts := {}, extras := {}, kept := {}, left_over := {}) -> void:
	if world == null:
		return
	inventory = new_inventory
	if verb.is_empty():
		return
	_play(Sounds.pickup(item))
	var total := Bag.count(inventory, item)
	if left_over.is_empty():
		var what := "Você %s %s." % [verb, Economy.haul_text(item, amount, parts, extras)]
		# Com dois tipos de item (madeira e lenha da árvore), o total de um só
		# confundiria: a Bolsa diz quanto há de cada.
		Speech.say(what if not extras.is_empty() else "%s Agora tem %d." % [what, total])
	elif kept.is_empty():
		Speech.say("Sua carga está no limite: %s ficou no chão." % Economy.items_text(left_over))
	else:
		Speech.say("Você %s %s. Agora tem %d. Carga no limite: %s ficou no chão." % [
			verb, Economy.items_text(kept), total, Economy.items_text(left_over)])


## A bolsa e as mãos mudaram. verb: "empunhou", "guardou" ou "" (só
## sincroniza, ex.: ao entrar no mundo).
@rpc("authority", "call_local", "reliable")
func equipment_changed(new_bag: Dictionary, new_wielded: String, verb: String, item: String) -> void:
	if world == null:
		return
	inventory = new_bag
	wielded = new_wielded
	match verb:
		"empunhou":
			_play(Sounds.wield())
			Speech.say("Você empunha %s. %s" % [Bag.with_article(item), Bag.WIELDABLE.get(item, "")])
		"guardou":
			_play(Sounds.stow())
			Speech.say("Você guardou %s na bolsa." % Bag.with_article(item))


## Outra criatura empunhou, guardou ou golpeou: o som sai de onde ela está.
@rpc("authority", "call_local", "reliable")
func player_handled(id: int, verb: String) -> void:
	if world == null or not players.has(id) or id == my_id:
		return
	var stream: AudioStream = {"empunhou": Sounds.wield(), "guardou": Sounds.stow(), "golpeou": Sounds.axe_swing(),
		"fabricou": Sounds.build_knock()}.get(verb)
	_play_other(players[id]["pos"], stream)


@rpc("authority", "call_local", "reliable")
func action_failed(reason: String, detail: String) -> void:
	if world == null:
		return
	match reason:
		"golpear":
			Speech.say("Ainda está de pé. Empunhe o machado e golpeie com J.")
		"cheio":
			Speech.say("Sua carga está no limite, %d de %d. Jogue algo fora pela Bolsa, no menu das setas." % [Bag.load_of(inventory, wielded), Bag.CAPACITY])
		"nao_tem":
			Speech.say("Não há %s na sua bolsa." % Bag.spoken_name(detail))
		"nao_empunha":
			Speech.say("Não dá para empunhar %s." % Bag.spoken_name(detail))
		"maos_livres":
			Speech.say("Suas mãos já estão livres.")
		"obra_lugar":
			Speech.say("Não dá para construir aí à frente. Procure chão livre, fora da trilha, da água, dos recursos e da Origem.")
		"obra_perto":
			Speech.say("Há outra construção colada nesse lugar.")
		"obra_regiao":
			Speech.say("Esta região já tem um marco.")
		"obra_ocupado":
			Speech.say("Tem alguém nesse lugar.")
		"obra_faltam":
			Speech.say("Para esta etapa %s, e não há nada disso na sua bolsa." % detail)
		"obra_pronta":
			Speech.say(detail)
		"obra_sem_lenha":
			Speech.say("A fogueira está sem lenha, e não há lenha na sua bolsa.")
		"obra_sem_lenha_bolsa":
			Speech.say("Não há lenha na sua bolsa para pôr no fogo.")
		"obra_cheia":
			Speech.say("A fogueira já está cheia de lenha.")
		"nome_repetido":
			Speech.say("Já existe um povoado chamado %s. Escolha outro nome." % detail)
		"nome_longe":
			Speech.say("Você se afastou do marco.")
		"nome_ja_tem_nome":
			Speech.say("Este povoado já tem nome.")
		"nome_sem_fogueira":
			Speech.say("Falta uma fogueira pronta nesta região.")
		"arma_faltam":
			var parts := detail.split("|")
			Speech.say("Para %s %s." % [Crafting.weapon_name(parts[0]), parts[1] if parts.size() > 1 else ""])
		"arma_cheio":
			Speech.say("Você já carrega o máximo de %s." % Crafting.WEAPONS[detail.split("|")[0]]["name"][1])
		_:
			pass  # "nada", "colhido", "devagar", "longe": ignora em silêncio


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
	horrors.start_server(state.world)
	print("[servidor] mundo único no ar, versão %s, porta %d, semente %d" % [Updater.current_version(), Net.port, state.world.world_seed])
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
	horrors.forget_peer(id)
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
	var slid := Vector2.ZERO
	for part in [Vector2(motion.x, 0.0), Vector2(0.0, motion.y)]:
		if part != Vector2.ZERO and world.is_free(_pos + part):
			_set_pos(_pos + part)
			slid += part
	# Quase de frente contra o obstáculo, o deslize é só um raspão: conta como
	# esbarrão (som e fala), senão a criatura emperra em silêncio.
	if slid.length() < motion.length() * BUMP_SLIDE_MIN:
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
		_step_clock = _next_step_clock(_step_clock)
		_step_count += 1
		_play_my_step()


func _play_my_step() -> void:
	var cell := WorldGen.cell_of(_pos)
	_play(Sounds.footstep(world.biome_at(cell), world.thing_at(cell)), true, FOOTSTEP_DB)
	for sound: Array in _step_foley(_step_count):
		_play(sound[0], true, sound[1])


## Relógio depois de tocar um passo. Num quadro normal, guarda a sobra para o
## próximo passo cair no tempo certo. Depois de um engasgo (um quadro longo),
## o fmod jogava fora os passos perdidos e o ritmo ficava lento e irregular;
## agora o atraso vira no máximo meio intervalo, então o próximo passo vem um
## pouco mais cedo e o ritmo se recupera sem rajada de passos.
static func _next_step_clock(clock: float) -> float:
	return minf(clock - STEP_INTERVAL, STEP_INTERVAL * 0.5)


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
			steps["clock"] = _next_step_clock(steps["clock"])
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
		_notice_region(cell)
		_announce_arrival(old_cell, cell)
		_update_biome_bed()
		_update_wind()


## Mudou de região: um sopro baixinho, sem fala. Só conta quando a criatura
## já está uma casa para dentro da região nova, para não repetir o som em
## quem anda bem em cima da divisa.
func _notice_region(cell: Vector2i) -> void:
	if not region_changed(world, _region, cell):
		return
	_region = world.region_of(cell)
	_play(Sounds.region_change(), false, REGION_CHANGE_DB)


## A casa está em outra região que não "region", e nenhuma das quatro casas
## coladas nela ainda é de "region"?
static func region_changed(the_world: WorldGen, region: Vector2i, cell: Vector2i) -> bool:
	if the_world.region_of(cell) == region:
		return false
	for offset: Vector2i in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]:
		if the_world.region_of(cell + offset) == region:
			return false
	return true


## Esbarrou: o som vem de onde está o obstáculo, e a fala diz o que é.
func _bump(target: Vector2) -> void:
	var cell := world.blocker_at(target)
	var thing := world.thing_at(cell) if cell != WorldGen.NO_CELL else WorldGen.Thing.NADA
	var build := builds.at(cell) if cell != WorldGen.NO_CELL else {}
	if not build.is_empty():
		if _bump_sound_cooldown <= 0.0:
			_bump_sound_cooldown = BUMP_SOUND_COOLDOWN
			audio.play_at_point(WorldGen.cell_center(cell), Sounds.bump(thing))
		if _bump_speech_cooldown <= 0.0 or _last_bump_thing != -2 - int(build["id"]):
			_bump_speech_cooldown = BUMP_SPEECH_COOLDOWN
			_last_bump_thing = -2 - int(build["id"])
			Speech.say(builds.spoken_name(int(build["id"])).left(1).to_upper() + builds.spoken_name(int(build["id"])).substr(1))
		return
	# Bambuzal fechado: bate de leve nos colmos e explica como seguir.
	var wall := thing == WorldGen.Thing.BAMBU and world.biome_at(cell) == WorldGen.Biome.BAMBUZAL
	if _bump_sound_cooldown <= 0.0:
		_bump_sound_cooldown = BUMP_SOUND_COOLDOWN
		var where := WorldGen.cell_center(cell) if thing != WorldGen.Thing.NADA else target
		if wall:
			audio.play_at_point(where, Sounds.bamboo_knock(), -4.0, true, true)
		else:
			audio.play_at_point(where, Sounds.bump(thing))
	if _bump_speech_cooldown <= 0.0 or thing != _last_bump_thing:
		_bump_speech_cooldown = BUMP_SPEECH_COOLDOWN
		_last_bump_thing = thing
		if wall:
			Speech.say(BAMBUZAL_CLOSED_WIELDING if wielded == "machado" else BAMBUZAL_CLOSED)
		elif thing == WorldGen.Thing.NADA:
			Speech.say("Fim do caminho.")
		elif thing == WorldGen.Thing.ARVORE:
			Speech.say("Mata fechada. Siga a trilha ou abra caminho com o machado.")
		else:
			Speech.say(WorldGen.THING_NAMES[thing])


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
	request_heading.rpc_id(1, _heading)


func _announce_arrival(old_cell: Vector2i, cell: Vector2i) -> void:
	# Fala o lugar novo ao trocar de bioma, e também ao entrar numa clareira
	# ou sair dela (o bioma é o mesmo, o lugar não).
	var place := world.place_name(cell)
	if old_cell != WorldGen.NO_CELL and place != world.place_name(old_cell):
		Speech.say(place)
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
	elif thing != WorldGen.Thing.NADA and not harvest.spoken_name(cell).is_empty():
		Speech.say(harvest.spoken_name(cell), false)
	if ground.has_pile(cell):
		Speech.say("No chão: %s. Espaço pega." % _pile_text(cell), false)


## Espaço: coleta o que estiver ao alcance, dando preferência ao que está à
## frente.
func _interact() -> void:
	var target := _collect_target()
	var build := _build_target()
	var pile := ground.nearest(_pos, COLLECT_REACH)
	# O que está mais perto vence; empate: obra, depois monte, depois recurso.
	var build_distance := INF if build.is_empty() else _pos.distance_to(WorldGen.cell_center(build["cell"]))
	var pile_distance := INF if pile == WorldGen.NO_CELL else _pos.distance_to(WorldGen.cell_center(pile))
	var target_distance := INF if target == WorldGen.NO_CELL else _pos.distance_to(WorldGen.cell_center(target))
	if build_distance <= pile_distance and build_distance <= target_distance and not build.is_empty():
		if builds.can_name(int(build["id"])):
			# Marco pronto com fogueira na região: abre a escolha do nome.
			Speech.say(_menu.open_at("Nome do povoado, primeira palavra", _name_nouns.bind(int(build["id"]))))
		else:
			request_build_work.rpc_id(1, int(build["id"]))
	elif pile_distance <= target_distance and pile != WorldGen.NO_CELL:
		request_pick_up.rpc_id(1, pile)
	elif target != WorldGen.NO_CELL:
		request_collect.rpc_id(1, target)


## O recurso que o Espaço recolhe: o mais perto, com preferência para o que
## está à frente e para o que dá para recolher agora (um bambu de pé ou algo
## já colhido só é escolhido se não houver outro, para a fala explicar).
func _collect_target() -> Vector2i:
	return _nearest_resource(COLLECT_REACH, func(cell: Vector2i):
		return Harvest.is_source(world.thing_at(cell)), true)


## A construção mais perto ao alcance do Espaço, com preferência para a que
## está à frente, ou {}.
func _build_target() -> Dictionary:
	var best := {}
	var best_score := INF
	var ahead := Compass.forward(_heading)
	for build: Dictionary in builds.all():
		var offset := WorldGen.cell_center(build["cell"]) - _pos
		var distance := offset.length()
		if distance > BUILD_REACH:
			continue
		var score := distance - (0.6 if distance > 0.01 and ahead.dot(offset / distance) > 0.5 else 0.0)
		if score < best_score:
			best_score = score
			best = build
	return best


## A casa onde uma construção nova começa: a que está logo à frente.
func _front_cell() -> Vector2i:
	var ahead := Compass.forward(_heading)
	var cell := WorldGen.cell_of(_pos + ahead * 1.1)
	if cell == WorldGen.cell_of(_pos):
		cell = WorldGen.cell_of(_pos + ahead * 1.6)
	return cell


## A touceira de bambu que a tecla J golpeia: a mais perto à frente. Devolve
## NO_CELL se não houver nenhuma ao alcance (o golpe vai no ar).
func _strike_target() -> Vector2i:
	return _nearest_resource(STRIKE_REACH, func(cell: Vector2i):
		return Harvest.needs_tool(world.thing_at(cell)), false)


func _nearest_resource(reach: float, accepts: Callable, prefer_ready: bool) -> Vector2i:
	var best := WorldGen.NO_CELL
	var best_score := INF
	var here := WorldGen.cell_of(_pos)
	var ahead := Compass.forward(_heading)
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var cell := here + Vector2i(dx, dy)
			if not accepts.call(cell):
				continue
			var offset := WorldGen.cell_center(cell) - _pos
			var distance := offset.length()
			if distance > reach:
				continue
			var score := distance - (0.6 if distance > 0.01 and ahead.dot(offset / distance) > 0.5 else 0.0)
			if prefer_ready and not harvest.is_ready(cell):
				score += 10.0
			elif not prefer_ready and not harvest.is_available(cell):
				score += 10.0
			if score < best_score:
				best_score = score
				best = cell
	return best


func _say_inventory() -> void:
	var hands := "Mãos livres." if wielded.is_empty() else "Nas mãos: %s." % Bag.spoken_name(wielded)
	var labels: PackedStringArray = []
	for entry: Array in Bag.entries(inventory):
		labels.append(Bag.entry_label(entry[0], entry[1], inventory))
	if labels.is_empty():
		Speech.say("Bolsa vazia. %s" % hands)
	else:
		Speech.say("Na bolsa: %s. %s" % ["; ".join(labels), hands])


## J: golpeia com o que estiver nas mãos (por enquanto, só o machado).
func _swing() -> void:
	if wielded.is_empty():
		Speech.say("Suas mãos estão livres. Empunhe o machado pela Bolsa, no menu das setas.")
		return
	if _swing_cooldown > 0.0:
		return
	_swing_cooldown = SWING_COOLDOWN
	_play(Sounds.axe_swing(), true)
	if wielded != "machado":
		# Armas ainda não acertam nada (os horrores virão): só o golpe no ar.
		request_swing.rpc_id(1)
		return
	# Com bambu ao alcance, o golpe acerta (o som do colmo e a fala vêm do
	# servidor); senão, é só o machado cortando o ar.
	var target := _strike_target()
	if target != WorldGen.NO_CELL:
		# A lâmina batendo, logo depois do golpe no ar (o colmo soa pelo servidor).
		get_tree().create_timer(SWING_TO_HIT).timeout.connect(_play.bind(Sounds.axe_hit(), true))
		request_strike.rpc_id(1, target)
	else:
		request_swing.rpc_id(1)


func _say_help() -> void:
	Speech.say("W e S: andar para frente e para trás. A e D: passo para o lado. Q e E: girar. Setas: menu flutuante, com o Caminheiro; esquerda e direita escolhem, seta para cima confirma e seta para baixo volta. A cada giro, a bússola dá um clique: agudo no norte, grave no sul, médio no leste e no oeste, abafado nas diagonais. F: para onde estou olhando. Espaço: coletar gravetos ou frutas de um arbusto, argila, pedras ou um bambu derrubado, ou pegar itens do chão. A carga tem limite: pela Bolsa, no menu das setas, dá para jogar itens no chão. J: golpear com o machado, depois de empunhá-lo pela Bolsa, no menu das setas. Fabricar, no menu das setas: começar um marco ou uma fogueira à frente, ou fazer uma arma. Espaço perto de uma obra deposita materiais e trabalha nela; numa fogueira pronta, bate as pedras para acender ou põe lenha. Um marco e uma fogueira na mesma região fazem um povoado: Espaço no marco pronto abre as listas para escolher o nome, e o povoado passa a aparecer em Locais, no Caminheiro. Construções, no Caminheiro, mostra as da região em que você está. Tab: ouvir os arredores; segure o Tab para escutar com atenção, com o vento e a música mais baixos e os recursos mais altos. Se os pássaros fugirem e o mundo for ficando abafado, algo vem atrás de você: segure o Tab para ouvir de onde vem a respiração e gire até ficar de frente para ela, que então se cala. Encarado, ele para e acaba indo embora; fogueira acesa e companhia também o afastam. C: onde estou. P: quem está no mundo. R: repetir a última fala. Trilhas de terra ligam a Origem às outras regiões do mundo; o Tab diz onde fica a mais próxima.")


## Tab: um toque curto fala os arredores; segurado, escuta com atenção até
## soltar.
func _on_listen_key(pressed: bool) -> void:
	if pressed:
		_tab_down_ms = Time.get_ticks_msec()
		return
	if _tab_down_ms < 0:
		return
	_tab_down_ms = -1
	if _focus:
		_set_focus(false)
	else:
		_say_surroundings()


func _set_focus(on: bool) -> void:
	if _focus == on:
		return
	_focus = on
	_focus_changed_now = true
	audio.set_resource_focus(on, FOCUS_FADE)
	Music.set_duck(FOCUS_DUCK_DB if on else 0.0, FOCUS_FADE)
	if _bed != null:
		if _bed_tween != null:
			_bed_tween.kill()
		_bed_tween = create_tween()
		_bed_tween.tween_property(_bed, "volume_db", _bed_target_db(), FOCUS_FADE)
	_update_wind()
	_focus_changed_now = false


func _bed_target_db() -> float:
	return BED_VOLUME_DB + (FOCUS_DUCK_DB if _focus else 0.0)


func _say_surroundings() -> void:
	var others := []
	for id in players:
		if id != my_id:
			others.append(players[id])
	Speech.say(Narrator.surroundings(world, _pos, _heading, others, harvest, ground))


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
	_play_other(pos, Sounds.footstep(world.biome_at(cell), world.thing_at(cell)), FOOTSTEP_DB)
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
	if _bed_tween != null:
		_bed_tween.kill()
	_bed_tween = create_tween()
	_bed_tween.tween_property(_bed, "volume_db", _bed_target_db(), 1.5)
	var tween := create_tween()
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
	var biome := world.biome_at(cell)
	# O mar e o deserto gelado são descampados: o vento não dá trégua.
	if world.is_trail(cell) or _near_lake(cell) or biome == WorldGen.Biome.MAR or biome == WorldGen.Biome.DESERTO_GELADO:
		target = WIND_OPEN_DB
	elif world.is_forest(cell):
		target = WIND_SHELTER_DB  # numa clareira o vento volta a entrar
	if _focus:
		target += FOCUS_DUCK_DB
	if _wind_tween != null:
		_wind_tween.kill()
	_wind_tween = create_tween()
	_wind_tween.tween_property(_wind, "volume_db", target, FOCUS_FADE if _focus_changed_now else 2.5)


func _near_lake(cell: Vector2i) -> bool:
	var r := WIND_LAKE_RADIUS
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var thing := world.thing_at(cell + Vector2i(dx, dy))
			if thing == WorldGen.Thing.LAGO or thing == WorldGen.Thing.MAR:
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
	return [
		{"label": "Caminheiro", "open": _caminheiro_items},
		{"label": "Bolsa", "open": _bag_items, "empty": "vazia, capacidade %d" % Bag.CAPACITY,
			"open_sound": "bolsa", "move_sound": "bolsa_mexer", "close_sound": "bolsa_fechar"},
		{"label": "Equipamento", "open": _equipment_items, "empty": "mãos livres"},
		{"label": "Fabricar", "open": _craft_root},
	]


## Itens da bolsa, agrupados ("Argila, 2"; "Pedra, 3 grandes, 1 pequena"), e no
## fim a carga. Cada item abre um submenu: com tamanhos, um item por tamanho;
## cada um com Jogar 1, Jogar tudo e, nas ferramentas e armas, Empunhar.
func _bag_items() -> Array:
	var items := []
	for entry: Array in Bag.entries(inventory):
		var item: String = entry[0]
		var label := Bag.entry_label(item, entry[1], inventory)
		var keys := Bag.keys_of(inventory, item)
		if keys.size() == 1 and keys[0] == item:
			items.append({"label": label, "open": _bag_item_actions.bind(item)})
		else:
			items.append({"label": label, "open": _bag_sizes.bind(item)})
	if not items.is_empty():
		items.append({"label": Bag.load_label(inventory, wielded),
			"info": "%s. Cabem mais %d de peso." % [Bag.load_label(inventory, wielded), Bag.free_space(inventory, wielded)]})
	return items


## Os tamanhos de um item da bolsa ("Pedra grande, 3"), cada um com suas ações.
func _bag_sizes(base: String) -> Array:
	var items := []
	for key: String in Bag.keys_of(inventory, base):
		items.append({"label": "%s, %d" % [Bag.display_name(key), int(inventory[key])], "open": _bag_item_actions.bind(key)})
	return items


func _bag_item_actions(item: String) -> Array:
	var amount := int(inventory.get(item, 0))
	var actions := []
	if Bag.can_wield(item):
		actions.append({"label": "Empunhar", "run": _equip.bind(item)})
	actions.append({"label": "Jogar 1", "run": _drop.bind(item, 1)})
	if amount > 1:
		actions.append({"label": "Jogar tudo, %d" % amount, "run": _drop.bind(item, amount)})
	return actions


## Jogar passa pelo servidor; a resposta (ground_changed) é que fala e toca.
func _drop(item: String, amount: int) -> String:
	request_drop.rpc_id(1, item, amount)
	return ""


## O que está nas mãos, com o botão Guardar.
func _equipment_items() -> Array:
	if wielded.is_empty():
		return []
	return [{"label": Bag.display_name(wielded), "open": _equipment_actions}]


func _equipment_actions() -> Array:
	return [{"label": "Guardar", "run": _stow}]


## Empunhar e guardar passam pelo servidor; a resposta (equipment_changed)
## é que fala e toca o som.
func _equip(item: String) -> String:
	request_equip.rpc_id(1, item)
	return ""


func _stow() -> String:
	request_stow.rpc_id(1)
	return ""


## Recursos que o Caminheiro sabe achar: rótulo no menu, coisas do mundo que
## contam e como se fala do destino (com artigo, para "rumo ao bambu").
const CAMINHEIRO_RESOURCES := [
	["Bambu", [WorldGen.Thing.BAMBU], "o bambu"],
	["Lenha", [WorldGen.Thing.ARBUSTO], "a lenha"],
	["Madeira", [WorldGen.Thing.ARVORE], "a árvore"],
	["Pedras", [WorldGen.Thing.PEDRAS], "as pedras"],
	["Argila", [WorldGen.Thing.ARGILA], "a argila"],
	["Frutas", [WorldGen.Thing.ARBUSTO_FRUTAS], "as frutas"],
]
## Até onde (em casas, em linha reta) o Caminheiro procura um recurso: uma
## região e meia para cada lado.
const RESOURCE_SEARCH_RADIUS := 72


## Menu do Caminheiro: Locais (lugares do mapa) e Recursos (leva ao coletável
## mais próximo de cada tipo). A fabricação pendura aqui a categoria
## Construções.
func _caminheiro_items() -> Array:
	var items := [
		{"label": "Locais", "open": _caminheiro_places},
		{"label": "Recursos", "open": _caminheiro_resources},
		{"label": "Construções", "open": _caminheiro_builds, "empty": "nenhuma nesta região"},
		{"label": "Itens no chão", "run": _track_pile, "stay": true},
	]
	if _caminheiro.active:
		items.append({"label": "Apagar o cristal", "run": _stop_tracking})
	return items


## Lugares do mapa: a Origem e os povoados, pelo nome que cada um recebeu,
## do mais perto ao mais longe ("Clareira Esquecida, 40 metros"). Um lugar só
## vira local quando é um povoado com nome (marco e fogueira na mesma região).
func _caminheiro_places() -> Array:
	var items := [{"label": "Origem", "run": _track.bind(WorldGen.origin_point(), "a Origem"), "stay": true}]
	var marcos := builds.settlements()
	marcos.sort_custom(func(a, b): return _pos.distance_squared_to(WorldGen.cell_center(a["cell"])) < _pos.distance_squared_to(WorldGen.cell_center(b["cell"])))
	for build: Dictionary in marcos:
		var meters := Compass.meters(_pos.distance_to(WorldGen.cell_center(build["cell"])))
		items.append({"label": "%s, %s" % [build["name"], meters],
			"run": _track.bind(_approach_point(build["cell"]), "o povoado " + build["name"]), "stay": true})
	return items


## Acende o cristal rumo ao monte de itens mais próximo.
func _track_pile() -> String:
	var cell := ground.nearest(_pos, float(RESOURCE_SEARCH_RADIUS))
	if cell == WorldGen.NO_CELL:
		return "Não há itens no chão por perto."
	return _track(WorldGen.cell_center(cell), "os itens no chão", cell)


func _caminheiro_resources() -> Array:
	var items := []
	for entry: Array in CAMINHEIRO_RESOURCES:
		items.append({"label": entry[0], "run": _track_resource.bind(entry[1], entry[2]), "stay": true})
	return items


## Acende o cristal rumo ao recurso coletável mais próximo destes tipos.
func _track_resource(things: Array, place: String) -> String:
	var cell := nearest_collectable(world, harvest, _pos, things, RESOURCE_SEARCH_RADIUS)
	if cell == WorldGen.NO_CELL:
		return "Não há %s por perto." % place.substr(place.find(" ") + 1)
	return _track(resource_destination(world, cell, _pos), place, cell)


## A casa do recurso coletável mais próximo (em linha reta), entre as coisas
## pedidas, que esteja lá agora (não recolhido). NO_CELL se não houver
## nenhum no raio.
static func nearest_collectable(the_world: WorldGen, the_harvest: Harvest, pos: Vector2, things: Array, radius: int) -> Vector2i:
	var here := WorldGen.cell_of(pos)
	var best := WorldGen.NO_CELL
	var best_distance := INF
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy > radius * radius:
				continue
			var cell := here + Vector2i(dx, dy)
			if not things.has(the_world.thing_at(cell)):
				continue
			if the_harvest != null and not the_harvest.is_available(cell):
				continue
			var distance := WorldGen.cell_center(cell).distance_squared_to(pos)
			if distance < best_distance:
				best_distance = distance
				best = cell
	return best


## Para onde o cristal leva, para chegar a um recurso: o próprio recurso, se
## dá para pisar nele; senão (o bambu bloqueia), a casa livre ao lado mais
## perto de quem vem.
static func resource_destination(the_world: WorldGen, cell: Vector2i, from: Vector2) -> Vector2:
	var center := WorldGen.cell_center(cell)
	if the_world.is_free(center):
		return center
	var best := center
	var best_distance := INF
	for offset in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
		var spot := WorldGen.cell_center(cell + offset)
		if the_world.is_free(spot) and spot.distance_to(from) < best_distance:
			best_distance = spot.distance_to(from)
			best = spot
	return best


## place vem com artigo ("a Origem", "o bambu"), para a fala juntar direito.
## resource: a casa do recurso, quando o destino é um recurso.
## Escolher de novo o destino que já está aceso apaga o cristal.
func _track(destination: Vector2, place: String, resource := WorldGen.NO_CELL) -> String:
	if _caminheiro.active and _caminheiro.place_name == place:
		return _stop_tracking()
	_tracked_resource = resource
	if _pos.distance_to(destination) <= Caminheiro.ARRIVE_RADIUS:
		_caminheiro.stop()
		_tracked_resource = WorldGen.NO_CELL
		return "Você já está %s." % Narrator.contract("em", place)
	if not _caminheiro.start(_pos, destination, place):
		return "O cristal do Caminheiro não achou caminho até %s." % place
	view.queue_redraw()
	var meters := Compass.meters(_caminheiro.estimated_length())
	return "O cristal do Caminheiro brilha azul, rumo %s, a uns %s. Siga as batidas do coração." % [Narrator.contract("a", place), meters]


func _stop_tracking() -> String:
	_caminheiro.stop()
	_tracked_resource = WorldGen.NO_CELL
	view.queue_redraw()
	return "O cristal do Caminheiro se apagou."


func _on_caminheiro_arrived(place: String) -> void:
	_play(Sounds.chime())
	view.queue_redraw()
	var where := ""
	if _tracked_resource != WorldGen.NO_CELL:
		where = ", " + Compass.describe(WorldGen.cell_center(_tracked_resource) - _pos, _heading)
		_tracked_resource = WorldGen.NO_CELL
	Speech.say("Você chegou %s%s." % [Narrator.contract("a", place), where])


## Construções no Caminheiro, da mais perto à mais longe: "Fogueira acesa,
## 20 metros". Só as da região em que a criatura está (marcos, fogueiras e
## obras em andamento). O cristal leva até uma casa livre colada na obra.
func _caminheiro_builds() -> Array:
	var list := builds.in_region(world.region_of(WorldGen.cell_of(_pos)))
	list.sort_custom(func(a, b): return _pos.distance_squared_to(WorldGen.cell_center(a["cell"])) < _pos.distance_squared_to(WorldGen.cell_center(b["cell"])))
	var items := []
	for build: Dictionary in list:
		var spoken := builds.spoken_name(int(build["id"]))
		var meters := Compass.meters(_pos.distance_to(WorldGen.cell_center(build["cell"])))
		var place: String = Crafting.BUILDS[build["kind"]]["article"] + " " + spoken
		items.append({"label": "%s, %s" % [spoken.left(1).to_upper() + spoken.substr(1), meters],
			"run": _track.bind(_approach_point(build["cell"]), place), "stay": true})
	return items


## Um ponto livre colado numa casa ocupada (a obra), o mais perto de quem está
## indo.
func _approach_point(cell: Vector2i) -> Vector2:
	var best := WorldGen.cell_center(cell)
	var best_distance := INF
	for offset: Vector2i in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
		var point := WorldGen.cell_center(cell + offset)
		if not world.is_free(point):
			continue
		var distance := point.distance_to(_pos)
		if distance < best_distance:
			best_distance = distance
			best = point
	return best


## Fabricar: construções (feitas no mundo, em etapas) e armas (na hora).
func _craft_root() -> Array:
	return [
		{"label": "Construções", "open": _build_kinds},
		{"label": "Armas", "open": _weapon_kinds},
	]


func _build_kinds() -> Array:
	var items := []
	for kind: String in Crafting.BUILD_ORDER:
		items.append({"label": Crafting.build_title(kind), "open": _build_actions.bind(kind)})
	return items


func _build_actions(kind: String) -> Array:
	return [
		{"label": "Iniciar à frente", "run": _start_build.bind(kind)},
		{"label": "Materiais", "info": Crafting.build_summary(kind)},
	]


## O lugar é a casa que está à frente quando a criatura escolhe Iniciar.
func _start_build(kind: String) -> String:
	request_build_start.rpc_id(1, kind, _front_cell())
	return ""


## Nome do povoado, primeira lista: os substantivos sorteados para este marco.
func _name_nouns(build_id: int) -> Array:
	var items := []
	for noun: int in SettlementNames.options(world.world_seed, build_id)["nouns"]:
		items.append({"label": SettlementNames.noun(noun), "open": _name_adjectives.bind(build_id, noun)})
	return items


## Segunda lista: os adjetivos, já junto do substantivo escolhido ("Clareira
## Esquecida"). Confirmar manda o nome ao servidor.
func _name_adjectives(build_id: int, noun: int) -> Array:
	var items := []
	for adjective: int in SettlementNames.options(world.world_seed, build_id)["adjectives"]:
		items.append({"label": SettlementNames.compose(noun, adjective),
			"run": _name_settlement.bind(build_id, noun, adjective)})
	return items


func _name_settlement(build_id: int, noun: int, adjective: int) -> String:
	request_name_settlement.rpc_id(1, build_id, noun, adjective)
	return ""


func _weapon_kinds() -> Array:
	var items := []
	for weapon: String in Crafting.WEAPON_ORDER:
		items.append({"label": Crafting.weapon_title(weapon), "open": _weapon_actions.bind(weapon)})
	return items


func _weapon_actions(weapon: String) -> Array:
	var materials: Dictionary = Crafting.WEAPONS[weapon]["materials"]
	var missing := Crafting.missing(inventory, materials)
	var info := "Precisa de %s." % Crafting.materials_text(materials)
	if not missing.is_empty():
		info += " Na sua bolsa %s." % Crafting.missing_text(missing)
	return [
		{"label": "Fabricar", "run": _craft.bind(weapon)},
		{"label": "Materiais", "info": info},
	]


func _craft(weapon: String) -> String:
	request_craft.rpc_id(1, weapon)
	return ""


## Põe o crepitar nas fogueiras acesas.
func _refresh_fires() -> void:
	var cells := []
	for build: Dictionary in builds.all():
		if builds.is_lit(int(build["id"])):
			cells.append(build["cell"])
	audio.set_lit_fires(cells)


func _on_menu_sound(kind: String) -> void:
	match kind:
		"mover":
			_play(Sounds.ui_move())
		"abrir":
			_play(Sounds.ui_open())
		"bolsa":
			_play(Sounds.bag_open())
		"bolsa_mexer":
			_play(Sounds.bag_rummage())
		"bolsa_fechar":
			_play(Sounds.bag_close())
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
		if command.begins_with("TP_") and state != null:  # testes, só quem hospeda: TP_x_y leva para a casa (x, y)
			var xy := command.split("_")
			_set_pos(WorldGen.cell_center(Vector2i(int(xy[1]), int(xy[2]))))
			state.players[my_id]["pos"] = _pos
			_cell = WorldGen.cell_of(_pos)
			_region = world.region_of(_cell)
			continue
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
			"CALADO":  # testes, só quem hospeda: o Calado aparece 12 casas atrás
				print("[teste] calado chamado: %d" % horrors.summon(my_id, 12.0))
			"CALADO_ONDE":
				print("[teste] calado a %.1f casas, abafamento %.2f" % [horrors.nearest_distance(), horrors.presence()])
			"ESPERAR":
				await get_tree().create_timer(1.0).timeout
			"ESPACO":
				_interact()
			"INV":
				_say_inventory()
			"EMPUNHAR":
				_equip("machado")
			"GUARDAR":
				_stow()
			"GOLPEAR":
				_swing()
			"MENU_CIMA", "MENU_BAIXO", "MENU_ESQUERDA", "MENU_DIREITA":
				Speech.say(_menu.press(command.trim_prefix("MENU_").to_lower()))
			"SEGUIR":  # segue o Caminheiro até ele se apagar (ou desistir)
				var deadline := Time.get_ticks_msec() + 120000
				while _caminheiro.active and Time.get_ticks_msec() < deadline:
					await _auto_walk(_caminheiro.current_beacon(), 20.0)
					await get_tree().process_frame
			"ORIGEM":
				await _auto_walk(WorldGen.origin_point())
			"KIT":  # testes, só quem hospeda: materiais para construir e fabricar
				if state != null:
					var inv := state.inventory_of(my_id)
					for item: String in ["pedra_grande", "pedra_media", "pedra_pequena", "lenha_media", "lenha_pequena", "bambu", "madeira"]:
						inv[item] = int(inv.get(item, 0)) + 10
					equipment_changed(inv, state.wielding(my_id), "", "")
			"LIVRE":  # testes: vai até um chão livre e fica de frente para ele (norte)
				var here := WorldGen.cell_of(_pos)
				var spot := WorldGen.NO_CELL
				for r in range(2, 30):
					for dx in range(-r, r + 1):
						for dy in range(-r, r + 1):
							var c := here + Vector2i(dx, dy)
							if spot == WorldGen.NO_CELL and builds.refusal("fogueira", c).is_empty() \
									and world.is_free(WorldGen.cell_center(c + Vector2i(0, 1))):
								spot = c
					if spot != WorldGen.NO_CELL:
						break
				if spot != WorldGen.NO_CELL:
					await _auto_walk(WorldGen.cell_center(spot + Vector2i(0, 1)), 30.0)
					while _heading != 0:
						_turn(1)
			"MARCO", "FOGUEIRA":
				_start_build(command.to_lower())
			"OBRA":  # Espaço várias vezes, devagar
				for i in 12:
					_interact()
					await get_tree().create_timer(0.35).timeout
			"JOGAR":  # testes: larga uma pedra grande (do KIT) no chão
				_drop("pedra_grande", 1)
			"JOGAR_TUDO":
				_drop("pedra_grande", 99)
			"LANCA", "CLAVA":
				_craft(command.to_lower())
			"SAIR":
				Net.stop()
				get_tree().quit()
