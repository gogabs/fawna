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
const SIDE_FACTOR := 0.8  # o passo para o lado também
## Ritmo dos passos: quantos passos por segundo enquanto a criatura anda.
## Os passos seguem o relógio, como uma animação, e não a distância andada.
## Para deixar mais rápido ou mais lento, mude só este número (3,3 é o ritmo escolhido pelo Gabs).
const STEPS_PER_SECOND := 3.3
const STEP_INTERVAL := 1.0 / STEPS_PER_SECOND
## O ritmo dos passos acompanha a velocidade, sem cair abaixo desta fração.
const MIN_STEP_RATE := 0.3
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
const WHERE_STEPS := 2  # falas do C: posição, céu
const BED_VOLUME_DB := -22.0  # fundo do bioma
## Vento: forte nas trilhas e na beira da lagoa (lugares abertos), fraco no
## mato da pradaria e quase nada dentro do bosque.
const WIND_OPEN_DB := -12.0
const WIND_FIELD_DB := -24.0
const WIND_SHELTER_DB := -36.0
const WIND_FADE := 2.5  # segundos para o vento mudar de volume
const WIND_LAKE_RADIUS := 4
const SWING_COOLDOWN := 0.45  # segundos entre golpes do machado (J)
const SWING_TO_HIT := 0.12  # do sopro do golpe até a lâmina bater
const BUILD_REACH := 1.8  # casas: trabalhar numa obra (o servidor aceita até 1,9)
const TORCH_NOISE_SECONDS := 8.0  # cada batida de pedra conta como tanto tempo exposto para o Calado
const BURN_CHECK := 2.0  # segundos entre conferências de fogueiras que apagaram
const CRAFT_KNOCKS := 3  # batidas ao fabricar uma arma
const CRAFT_TOOL_KNOCK := 0.55  # segundos entre as batidas de cada passo de uma ferramenta
const REGION_CHANGE_DB := -4.0  # o sopro ao passar de uma região para outra (a -14 sumia sob o vento)
## Ao esbarrar de viés, o deslize que ainda conta como andar, em fração do passo.
const BUMP_SLIDE_MIN := 0.5
const MENU_LIMIT_DB := -6.0  # o toque de limite ao voltar na raiz do menu
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
@onready var daytime: Node = $Daytime

var state: WorldState  # só no servidor
var _dirty := false
var _save_timer := 0.0

# Lado do cliente (inclusive quem hospeda)
var world: WorldGen
var _connect_waited := 0.0
var my_id := 0
var _server_version := ""  # vem do servidor ao entrar; vazio: servidor antigo, que não manda
var players := {}  # id -> { "name", "pos": Vector2 }
var inventory := {}  # a bolsa: item -> quantidade (ver Bag)
var wielded := ""  # o que a criatura tem nas mãos ("" = mãos livres)
var offhand := ""  # a segunda peça de equipamento, na mão não dominante (a tocha)
var torch_bearers: Array = []  # ids de quem leva uma tocha acesa (o servidor manda)
var _striking := false  # riscando a tocha: Espaço bate a pedra
var _torch_ends := 0.0  # hora (Unix) em que a tocha acesa se apaga; 0 = apagada
var _swing_cooldown := 0.0
var harvest: Harvest  # espelho do que já foi colhido ou golpeado (o servidor manda)
var _harvest_timer := 0.0
var _server_harvest_timer := 0.0
var builds: Builds  # espelho das construções (o servidor manda)
var _dry_notice_ms := 0
var ground: Ground  # espelho dos itens soltos no chão (o servidor manda)
var _burn_timer := 0.0  # servidor: fogueiras que apagaram
var _pos := Vector2.ZERO  # posição local (o servidor confere)
var _where_step := 0  # qual fala do C vem agora (ver _say_where)
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
var _caminheiro: Caminheiro
var _tracked_resource := WorldGen.NO_CELL  # recurso que o cristal procura (NO_CELL: um lugar)
var _tracked_destination := Vector2.ZERO  # para onde o cristal leva (vale com ele aceso)
## O último recurso pedido ao Caminheiro (coisas do mundo e nome com artigo),
## que o Tab usa para achar o mais próximo. Continua valendo com o cristal
## apagado.
var _menu: FloatingMenu
## Vozes dos sons da própria criatura (passos, coleta...). Um passo novo vai
## para uma voz livre em vez de reiniciar a que ainda está tocando, então o
## fim do passo anterior não é cortado e os dois se sobrepõem naturalmente.
var _sfx_voices: Array[AudioStreamPlayer] = []


func _ready() -> void:
	Net.apply_graphics(true)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	var err := Net.start()
	if err != OK:
		_back_to_menu("Não foi possível iniciar a conexão (erro %d)." % err)
		return

	if Net.is_server():
		_load_or_create_world()
	if Net.mode == Net.Mode.HOST:
		request_join.rpc_id(1, Net.player_name, Net.password)
	elif Net.mode == Net.Mode.CLIENT:
		Speech.say("Conectando a %s..." % Net.address)


func _exit_tree() -> void:
	Net.apply_graphics(false)
	_save_world()
	Sounds.clear()
	BirdSongs.clear()


func _process(delta: float) -> void:
	# Quem não consegue entrar em 30 s volta ao menu, em vez de ficar parado.
	if Net.mode == Net.Mode.CLIENT and world == null:
		_connect_waited += delta
		if _connect_waited >= Net.CONNECT_TIMEOUT:
			_back_to_menu("Não foi possível conectar ao servidor: sem resposta em %d segundos. Confira o endereço e a conexão e tente de novo." % int(Net.CONNECT_TIMEOUT))
			return
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
		if not state.striking.is_empty():
			for striker: int in state.expire_strikes():
				torch_striking.rpc_id(striker, "cancelou", "demora")
		_burn_timer += delta
		if _burn_timer >= BURN_CHECK:
			_burn_timer = 0.0
			for build_id: int in state.builds.burn_out():
				_dirty = true
				build_changed.rpc(state.builds.info(build_id), "apagou", 0, {})
			var burned := state.expire_torches()
			for torch_id: int in burned:
				_dirty = true
				offhand_changed.rpc_id(torch_id, state.inventory_of(torch_id), "", 0.0, "queimou", "tocha")
			if not burned.is_empty():
				_broadcast_torches()
			for id in state.players:
				state.builds.touch(state.owner_key(id))
			for closed: Dictionary in state.builds.close_votes():
				_dirty = true
				build_changed.rpc(state.builds.info(int(closed["marco"])), closed["event"], 0,
					{"target": int(closed["target"]), "target_name": state.builds.spoken_name(int(closed["target"]))})
			for build_id: int in state.builds.dried():
				_dirty = true
				build_changed.rpc(state.builds.info(build_id), "secou", 0, {})
	if world == null or not players.has(my_id):
		return
	_turn_cooldown = maxf(_turn_cooldown - delta, 0.0)
	_bump_sound_cooldown = maxf(_bump_sound_cooldown - delta, 0.0)
	_bump_speech_cooldown = maxf(_bump_speech_cooldown - delta, 0.0)
	_swing_cooldown = maxf(_swing_cooldown - delta, 0.0)
	var before := _pos
	var motion := _wanted_motion()
	_walk(motion * delta)
	# O ritmo dos passos acompanha a velocidade: de costas, de lado ou sobrecarregado, mais lento.
	_step_clock += delta * clampf(motion.length() / WALK_SPEED, MIN_STEP_RATE, 1.0)
	_tick_my_steps(_pos != before, delta)
	_tick_other_steps(delta)
	_update_torch_sounds()
	_harvest_timer += delta
	if _harvest_timer >= HARVEST_CHECK:
		_harvest_timer = 0.0
		var occupants := []
		for id in players:
			occupants.append(players[id]["pos"])
		if not harvest.prune(-1.0, occupants).is_empty():
			audio.refresh_resources()
	if _caminheiro != null:
		_caminheiro.update(_pos, delta, Compass.forward(_heading))
	_send_timer += delta
	if _send_timer >= SEND_INTERVAL and _pos != _last_sent:
		_send_timer = 0.0
		_last_sent = _pos
		request_move_to.rpc_id(1, _pos)


## C é circular: o primeiro toque diz onde a criatura pisa e para onde olha; o
## seguinte, o momento do dia e o anel; e assim por diante, sem relógio de espera
## (daqui para frente cabe o clima como mais um passo).
func _say_where() -> void:
	var step := _where_step % WHERE_STEPS
	_where_step = step + 1
	match step:
		0:
			Speech.say(Narrator.stepping_on(world, _pos, _heading))
		_:
			Speech.say(daytime.sky_text())


## Onde a criatura está (casas), para quem precisa saber de fora.
func my_position() -> Vector2:
	return _pos


func _unhandled_input(event: InputEvent) -> void:
	if world != null and event.is_action_pressed("ouvir_arredores") and not event.is_echo():
		_say_radar()
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
	elif event.is_action("atalho_bolsa"):
		_open_shortcut("Bolsa")
	elif event.is_action("atalho_caminheiro"):
		_open_shortcut("Caminheiro")
	elif event.is_action("ajuda"):
		_say_help()
	elif event.is_action("onde_estou"):
		_say_where()
	elif event.is_action("hora"):
		Speech.say(daytime.describe())
	elif event.is_action("direcao"):
		Speech.say("Olhando para o %s." % Compass.name_of(_heading))
	elif event.is_action("quem_esta_aqui"):
		_say_who()
	elif event.is_action("repetir_fala"):
		Speech.repeat_last()
	else:
		return
	get_viewport().set_input_as_handled()


## I e V: abrem direto a Bolsa ou o Caminheiro no menu das setas.
func _open_shortcut(label: String) -> void:
	if _menu != null:
		Speech.say(_menu.open_root(label))


# --- Rede: pedidos dos clientes (executados no servidor) ---------------------

@rpc("any_peer", "call_local", "reliable")
func request_join(player_name: String, password: String) -> void:
	if not multiplayer.is_server():
		return
	var id := _sender_id()
	if state.players.has(id):
		return
	var login := state.login(player_name, password)
	if not login["ok"]:
		print("[servidor] peer %d recusado (%s)" % [id, login["reason"]])
		join_refused.rpc_id(id, login["reason"])
		return
	if login["created"]:
		# Senha nova: grava já, para uma queda do servidor não perder o dono do nome.
		_dirty = true
		print("[servidor] senha registrada para %s" % player_name.strip_edges().left(24))
	var pos := state.add_player(id, player_name)
	var accepted_name: String = state.players[id]["name"]
	print("[servidor] %s (peer %d) entrou em %s" % [accepted_name, id, pos])
	server_version.rpc_id(id, Updater.current_version())
	welcome.rpc_id(id, state.world.world_seed, state.snapshot(), state.inventory_of(id))
	daytime.sync_to(id)
	equipment_changed.rpc_id(id, state.inventory_of(id), state.wielding(id), "", "")
	offhand_changed.rpc_id(id, state.inventory_of(id), state.offhand_of(id), state.torch_left(id), "", "")
	torches_changed.rpc_id(id, state.lit_torch_ids())
	harvest_snapshot.rpc_id(id, state.harvest.snapshot())
	build_snapshot.rpc_id(id, state.builds.snapshot())
	ground_snapshot.rpc_id(id, state.ground.snapshot())
	for other_id in state.players:
		if other_id != id:
			player_joined.rpc_id(other_id, id, accepted_name, pos)
	_save_world()


## O servidor não deixou entrar: a pessoa volta ao menu com o motivo.
@rpc("authority", "call_local", "reliable")
func join_refused(reason: String) -> void:
	var text := "O servidor não deixou você entrar."
	match reason:
		"errada":
			text = "Senha errada para esse nome. Confira a senha nas Opções."
		"curta":
			text = "A senha precisa ter pelo menos %d caracteres. Defina nas Opções." % Credentials.MIN_LENGTH
		"devagar":
			text = "Senha errada demais. Espere uns segundos e tente de novo."
		"ja_conectado":
			text = "Essa criatura já está no mundo."
	_back_to_menu(text)


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
func request_pick_up(cell: Vector2i, only := "") -> void:
	if not multiplayer.is_server():
		return
	var id := _sender_id()
	var result := state.pick_up(id, cell, only)
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


## Um golpe de faca no tronco de uma árvore (tecla J, com a faca empunhada):
## algumas vezes faz a resina escorrer; demais seca a árvore (Resin).
@rpc("any_peer", "call_local", "reliable")
func request_tap(cell: Vector2i) -> void:
	if not multiplayer.is_server():
		return
	var id := _sender_id()
	if state.wielding(id) != "faca":
		return
	_tell_others_handled(id, "golpeou")
	var result := state.tap_tree(id, cell)
	if not result["ok"]:
		if state.players.has(id) and result["reason"] == "seca":
			resin_tapped.rpc(cell, "seca", id)
		return
	_dirty = true
	resin_tapped.rpc(cell, result["event"], id)


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
	if result.get("slot", "") == "offhand":
		offhand_changed.rpc_id(id, state.inventory_of(id), state.offhand_of(id), 0.0, "empunhou", item)
	else:
		equipment_changed.rpc_id(id, state.inventory_of(id), state.wielding(id), "empunhou", item)
	_tell_others_handled(id, "empunhou")


## Equipamento > Tocha > Guardar (só com a tocha apagada).
@rpc("any_peer", "call_local", "reliable")
func request_stow_offhand() -> void:
	if not multiplayer.is_server():
		return
	var id := _sender_id()
	var result := state.stow_offhand(id)
	if not result["ok"]:
		if state.players.has(id):
			action_failed.rpc_id(id, result["reason"], result.get("item", ""))
		return
	_dirty = true
	offhand_changed.rpc_id(id, state.inventory_of(id), state.offhand_of(id), 0.0, "guardou", result["item"])
	_tell_others_handled(id, "guardou")


## Equipamento > Tocha > Acender: perto de uma fogueira acesa.
@rpc("any_peer", "call_local", "reliable")
func request_light_torch() -> void:
	if not multiplayer.is_server():
		return
	var id := _sender_id()
	var result := state.light_torch(id)
	if not result["ok"]:
		if state.players.has(id):
			action_failed.rpc_id(id, "tocha_" + result["reason"], "")
		return
	if result.get("started", false):
		# Sem fogueira: o jogador risca faíscas com Espaço (request_spark).
		torch_striking.rpc_id(id, "comecou", str(result["method"]))
		return
	_dirty = true
	offhand_changed.rpc_id(id, state.inventory_of(id), state.offhand_of(id), float(result["seconds"]), "acendeu", "tocha")
	_broadcast_torches()
	_tell_others_handled(id, "fabricou")


## Espaço enquanto se risca a tocha: uma batida de faca ou sílex na pedra.
@rpc("any_peer", "call_local", "reliable")
func request_spark() -> void:
	if not multiplayer.is_server():
		return
	var id := _sender_id()
	var result := state.strike_spark(id)
	match result["event"]:
		"faisca":
			horrors.hear_noise(id, TORCH_NOISE_SECONDS)
			_tell_others_handled(id, "faisca")
		"acendeu":
			_dirty = true
			horrors.hear_noise(id, TORCH_NOISE_SECONDS)
			offhand_changed.rpc_id(id, state.inventory_of(id), state.offhand_of(id), float(result["seconds"]), "acendeu", "tocha")
			_broadcast_torches()
			_tell_others_handled(id, "faisca")
		"cancelada":
			torch_striking.rpc_id(id, "cancelou", str(result.get("why", "demora")))


## O servidor avisa quem risca a tocha: "comecou" (detail: o método) ou
## "cancelou" (detail: o motivo).
@rpc("authority", "call_local", "reliable")
func torch_striking(what: String, detail: String) -> void:
	if world == null:
		return
	if what == "comecou":
		_striking = true
		Speech.say("Risque com Espaço, num ritmo constante, sem parar. %s" % (
			"Faca na pedra." if detail == "faca" else "Sílex na pedra."))
		return
	_striking = false
	if detail == "sem_material":
		Speech.say("Faltou material: você não tem mais o que precisa para riscar. Acendimento cancelado.")
	else:
		Speech.say("Você parou de riscar. Acendimento cancelado.")


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
	# Quem andou para dentro da casa antes de a obra chegar é levado para fora.
	for entry in state.eject_from_walls(result["id"]):
		move_corrected.rpc_id(int(entry[0]), entry[1])
		player_moved.rpc(int(entry[0]), entry[1])


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
		elif result["reason"] == "pronta" or result["reason"] == "preparo":
			detail = state.builds.status_text(build_id)
		elif result["reason"] == "porta_longe":
			detail = str(result["side"])
		elif result["reason"] == "canto":
			var names: PackedStringArray = []
			for post: int in result["posts"]:
				names.append(Builds.post_name(post))
			detail = ", ".join(names)
		action_failed.rpc_id(id, "obra_" + result["reason"], detail)
		return
	_dirty = true
	if result["event"] in ["deposito", "abasteceu", "alimentou", "silex"]:
		equipment_changed.rpc_id(id, state.inventory_of(id), state.wielding(id), "", "")
	var extra := {}
	for key in ["deposited", "missing", "work_left", "next", "item", "sparks_left", "post", "post_left", "slow", "counted", "dry", "walls", "open"]:
		if result.has(key):
			extra[key] = result[key]
	build_changed.rpc(state.builds.info(build_id), result["event"], id, extra)
	if result.get("walls", false):
		# As paredes subiram: quem estava no meio delas é levado para fora.
		for entry in state.eject_from_walls(build_id):
			move_corrected.rpc_id(int(entry[0]), entry[1])
			player_moved.rpc(int(entry[0]), entry[1])


## Fabricar > Construções > (grande) > âncora, tamanho e porta: começa uma
## construção grande no terreno escolhido. "origin" é o canto noroeste.
@rpc("any_peer", "call_local", "reliable")
func request_site_start(kind: String, origin: Vector2i, size: int, entrance: String) -> void:
	if not multiplayer.is_server():
		return
	var id := _sender_id()
	var result := state.start_site(id, kind, origin, size, entrance)
	if not result["ok"]:
		if state.players.has(id):
			action_failed.rpc_id(id, "obra_" + result["reason"], kind)
		return
	_dirty = true
	build_changed.rpc(state.builds.info(result["id"]), "iniciada", id, {})


## J com o machado (limpar) ou a enxada (capinar) no terreno de uma obra grande.
@rpc("any_peer", "call_local", "reliable")
func request_prep(build_id: int, cell: Vector2i) -> void:
	if not multiplayer.is_server():
		return
	var id := _sender_id()
	_tell_others_handled(id, "golpeou")
	var result := state.prep_build(id, build_id, cell)
	if not result["ok"]:
		if state.players.has(id) and result["reason"] in ["ferramenta", "fase"]:
			action_failed.rpc_id(id, "preparo_" + result["reason"], str(result.get("tool", "")))
		return
	_dirty = true
	var extra := {"cell": result["cell"]}
	for key in ["left", "cells_left", "next", "drop", "thing", "cleared"]:
		if result.has(key):
			extra[key] = result[key]
	if result.has("pile"):
		ground_changed.rpc(result["cell"], result["pile"], "caiu", id, result["drop"])
	build_changed.rpc(state.builds.info(build_id), result["event"], id, extra)


## J com o machado numa obra (parede, canto, casa do marco ou da fogueira): vários
## golpes desmontam. O que volta cai no chão dentro do terreno.
@rpc("any_peer", "call_local", "reliable")
func request_wreck(build_id: int, cell: Vector2i) -> void:
	if not multiplayer.is_server():
		return
	var id := _sender_id()
	_tell_others_handled(id, "golpeou")
	var result := state.wreck_build(id, build_id, cell)
	if not result["ok"]:
		if state.players.has(id) and result["reason"] in ["ferramenta", "povoado", "acesa", "nao_dono", "votacao"]:
			action_failed.rpc_id(id, "desmontar_" + result["reason"], str(result.get("tool", "")))
		return
	_dirty = true
	if result["event"] == "golpe":
		build_struck.rpc(build_id, cell, int(result["hits_left"]), int(result["total"]), bool(result["first"]), id)
		return
	for pile_cell: Vector2i in result["piles"]:
		ground_changed.rpc(pile_cell, result["piles"][pile_cell], "sobrou", id, {})
	build_demolished.rpc(build_id, cell, str(result["title"]), str(result["kind"]), result["back"], id)


## No marco do povoado: propor derrubar uma construção, ou votar numa proposta.
@rpc("any_peer", "call_local", "reliable")
func request_wreck_propose(marco_id: int, target_id: int) -> void:
	if not multiplayer.is_server():
		return
	var id := _sender_id()
	_finish_vote(id, marco_id, state.propose_wreck(id, marco_id, target_id))


@rpc("any_peer", "call_local", "reliable")
func request_wreck_vote(marco_id: int, target_id: int, yes: bool) -> void:
	if not multiplayer.is_server():
		return
	var id := _sender_id()
	_finish_vote(id, marco_id, state.vote_wreck(id, marco_id, target_id, yes))


func _finish_vote(id: int, marco_id: int, result: Dictionary) -> void:
	if not result["ok"]:
		if state.players.has(id):
			var detail := ""
			if result["reason"] == "espera":
				detail = Builds._days_text(float(result["wait"]))
			action_failed.rpc_id(id, "votar_" + result["reason"], detail)
		return
	_dirty = true
	var extra := {"target": int(result["target"]), "target_name": state.builds.spoken_name(int(result["target"]))}
	build_changed.rpc(state.builds.info(marco_id), result["event"], id, extra)


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


## No menu do abrigo: virar dono dele (um abrigo comporta 1 dono, 2 se grande).
@rpc("any_peer", "call_local", "reliable")
func request_claim(build_id: int) -> void:
	if not multiplayer.is_server():
		return
	var id := _sender_id()
	_finish_owner(id, build_id, state.claim_build(id, build_id), "dono")


## E deixar de ser dono.
@rpc("any_peer", "call_local", "reliable")
func request_release(build_id: int) -> void:
	if not multiplayer.is_server():
		return
	var id := _sender_id()
	_finish_owner(id, build_id, state.release_build(id, build_id), "sem_dono")


func _finish_owner(id: int, build_id: int, result: Dictionary, event: String) -> void:
	if not result["ok"]:
		if state.players.has(id) and result["reason"] != "desconhecida":
			action_failed.rpc_id(id, "dono_" + result["reason"], state.builds.title_of(build_id))
		return
	_dirty = true
	print("[servidor] %s %s do %s" % [state.players[id]["name"], "virou dono" if event == "dono" else "deixou de ser dono", state.builds.title_of(build_id)])
	build_changed.rpc(state.builds.info(build_id), event, id, {})


## Espaço longe da porta de um armazém ou abrigo pronto: guarda itens da bolsa.
@rpc("any_peer", "call_local", "reliable")
func request_store(build_id: int, item: String, amount: int) -> void:
	if not multiplayer.is_server():
		return
	var id := _sender_id()
	_finish_storage(id, build_id, state.store_in_build(id, build_id, item, amount), "guardou")


## O contrário: pega do estoque para a bolsa.
@rpc("any_peer", "call_local", "reliable")
func request_fetch(build_id: int, item: String, amount: int) -> void:
	if not multiplayer.is_server():
		return
	var id := _sender_id()
	_finish_storage(id, build_id, state.fetch_from_build(id, build_id, item, amount), "pegou_estoque")


func _finish_storage(id: int, build_id: int, result: Dictionary, event: String) -> void:
	if not result["ok"]:
		if state.players.has(id) and result["reason"] in ["nao_aceita", "nao_tem", "cheio", "carga", "nao_guarda", "nao_dono"]:
			action_failed.rpc_id(id, "estoque_" + result["reason"], "%s|%s" % [result.get("item", ""), state.builds.title_of(build_id)])
		return
	_dirty = true
	equipment_changed.rpc_id(id, state.inventory_of(id), state.wielding(id), "", "")
	build_changed.rpc(state.builds.info(build_id), event, id, {"item": result["item"], "amount": result["amount"]})


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
	daytime.start_client()
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
	_sync_menu.call_deferred()
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
			Speech.say("Você largou %s no chão. %s." % [Economy.items_text(moved), Bag.load_label(inventory, wielded, offhand)])
		"pegou":
			_play(Sounds.pickup(Economy.base_of(moved.keys()[0])))
			var rest := "" if items.is_empty() else " Ficou %s no chão: a carga não aguenta." % Economy.items_text(items)
			Speech.say("Você pegou %s. %s.%s" % [Economy.items_text(moved), Bag.load_label(inventory, wielded, offhand), rest])
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


## Um golpe de faca numa árvore: o som sai do tronco e quem golpeou ouve os
## avisos (a resina em si vem por inventory_changed).
@rpc("authority", "call_local", "reliable")
func resin_tapped(cell: Vector2i, event: String, by_id: int) -> void:
	if world == null:
		return
	var where := WorldGen.cell_center(cell)
	if where.distance_to(_pos) <= HEARING_RADIUS:
		audio.play_at_point(where, Sounds.tree_knock(), 0.0, true, true)
		if event in ["range", "secou", "seca"]:
			audio.play_at_point(where, Sounds.tree_creak(), 0.0, true, true)
	if by_id != my_id:
		return
	match event:
		"descanso":
			Speech.say("A resina ainda não voltou: a árvore precisa descansar. Mais golpes só a machucam.")
		"escorre":
			Speech.say("A resina começa a escorrer. Pare de golpear: ela leva cerca de um minuto para secar, e então Espaço recolhe.")
		"range":
			Speech.say("O tronco range. Pare, ou a árvore seca.")
		"secou":
			Speech.say("A árvore secou. Não dá mais resina.")
		"seca":
			Speech.say("Esta árvore está seca. Não dá mais resina.")


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
	_unstick()
	var build_id := int(data["id"])
	var build := builds.get_build(build_id)
	# O som sai de onde a coisa acontece: a casa golpeada, o canteiro ou, nas
	# construções grandes, o ponto do terreno mais perto de quem ouve.
	var where := Builds.nearest_point(build, _pos)
	if extra.has("cell"):
		where = WorldGen.cell_center(extra["cell"])
	elif extra.has("post"):
		where = WorldGen.cell_center(Builds.post_cell(build, int(extra["post"])))
	if event == "porta":
		where = WorldGen.cell_center(Builds.door_cell(build["cell"], int(build["size"]), str(build["entrance"])))
	var near := where.distance_to(_pos) <= HEARING_RADIUS
	var mine := by_id == my_id
	var title := builds.title_of(build_id)
	var stream: AudioStream = {
		"iniciada": Sounds.build_deposit(), "deposito": Sounds.build_deposit(), "trabalho": Sounds.build_knock(),
		"etapa": Sounds.build_stage(), "pronta": Sounds.build_done(), "faisca": Sounds.fire_spark(),
		"acesa": Sounds.fire_ignite(), "abasteceu": Sounds.fire_feed(), "alimentou": Sounds.fire_feed(),
		"apagou": Sounds.fire_out(), "nomeado": Sounds.build_done(),
		"limpando": Sounds.build_knock(), "limpo": Sounds.build_stage(), "capinando": Sounds.build_knock(),
		"capinado": Sounds.build_deposit(), "fase": Sounds.build_stage(), "secou": Sounds.build_stage(),
		"porta": Sounds.door(bool(extra.get("open", true))) if event == "porta" else null,
		"guardou": Sounds.build_deposit(), "pegou_estoque": Sounds.build_deposit(),
		"dono": Sounds.build_stage(), "sem_dono": Sounds.build_deposit(),
	}.get(event)
	if near and stream != null:
		audio.play_at_point(where, stream, 0.0, true, event in ["trabalho", "faisca", "deposito", "limpando", "capinando"])
	if event == "secou":
		if near:
			Speech.say("A argila secou: a obra volta a render por inteiro.", false)
		return
	_refresh_fires()
	if event in ["votacao_aberta", "votacao_aprovada", "votacao_rejeitada"]:
		_say_vote_event(build, event, by_id, str(extra.get("target_name", "")))
		return
	if event == "voto":
		if mine:
			Speech.say("Voto registrado. %s" % builds.vote_text(build_id, int(extra["target"])), false)
		return
	if event == "apagou":
		if where.distance_to(_pos) <= HEARING_RADIUS * 1.5:
			Speech.say("A fogueira apagou: acabou a lenha.", false)
		return
	if not mine:
		return
	match event:
		"iniciada":
			var what := ("um " if Crafting.BUILDS[build["kind"]]["article"] == "o" else "uma ") + Crafting.build_name(build["kind"])
			if Crafting.is_large(build["kind"]):
				var size := int(build["size"])
				Speech.say("Você marcou o terreno d%s %s, %d por %d casas, com a porta para o %s. %s O Caminheiro leva ao que falta, em Construções." % [
					Crafting.BUILDS[build["kind"]]["article"], Crafting.build_name(build["kind"]), size, size, build["entrance"],
					_capital(builds.status_text(build_id).trim_prefix(title + " em obra, "))])
			else:
				Speech.say("Você começou %s à frente. %s Espaço perto da obra deposita o que você tiver na bolsa. O Caminheiro sabe voltar aqui, em Construções." % [
					what, builds.status_text(build_id).trim_prefix(title + " em obra. ")])
		"porta":
			Speech.say("A porta d%s %s está %s." % [Crafting.BUILDS[build["kind"]]["article"], Crafting.build_name(build["kind"]),
				"aberta" if extra.get("open", true) else "fechada"])
		"limpando", "capinando":
			pass  # só o som do golpe; a fala vem quando a casa fica pronta
		"limpo":
			var thing := int(extra.get("thing", 0))
			var drop: Dictionary = extra.get("drop", {})
			Speech.say("Você arrancou %s. %s%s" % [
				SitePlanner.CLEAR_THING_TEXT.get(thing, "o que havia ali"),
				"Caiu no chão: %s. Espaço pega. " % Economy.items_text(drop) if not drop.is_empty() else "",
				"Faltam %d casas a limpar." % int(extra.get("cells_left", 0)) if int(extra.get("cells_left", 0)) > 0 else ""])
		"capinado":
			var left := int(extra.get("cells_left", 0))
			Speech.say("Casa capinada. %s" % ("Falta%s %d." % ["" if left == 1 else "m", left] if left > 0 else ""))
		"fase":
			if extra.get("next", "") == "capina":
				Speech.say("Terreno limpo. Agora a capina: empunhe a enxada pela Bolsa e golpeie a grama de cada casa com J. %s" % (
					"" if Bag.count(inventory, "enxada") + (1 if wielded == "enxada" else 0) > 0 else "Você ainda não tem uma: ela se fabrica em Fabricar, Ferramentas."))
			else:
				Speech.say("Terreno pronto. %s" % builds.status_text(build_id).trim_prefix(title + " em obra. "))
		"dono":
			Speech.say("Agora %s é seu. %s." % [Crafting.build_name(build["kind"]), _capital(Builds.owners_text(build))], false)
			_sync_menu.call_deferred()
		"sem_dono":
			Speech.say("Você deixou de ser dono d%s %s. %s." % [Crafting.BUILDS[build["kind"]]["article"], Crafting.build_name(build["kind"]), _capital(Builds.owners_text(build))], false)
			_sync_menu.call_deferred()
		"guardou", "pegou_estoque":
			var what := Crafting.material_text(str(extra["item"]), int(extra["amount"]))
			Speech.say("%s %s %s. %s." % ["Guardou" if event == "guardou" else "Pegou", what,
				"no " + Crafting.build_name(build["kind"]) if event == "guardou" else "do " + Crafting.build_name(build["kind"]),
				Builds.stock_label(build, _my_key())], false)
			_sync_menu.call_deferred()
		"deposito":
			var put := "Você colocou %s." % Crafting.materials_text(extra.get("deposited", {}))
			var missing: Dictionary = extra.get("missing", {})
			if missing.is_empty():
				var left := builds.work_left(build_id)
				Speech.say("%s Materiais completos. Espaço para trabalhar: %d batida%s." % [put, left, "" if left == 1 else "s"])
			else:
				Speech.say("%s %s." % [put, Crafting.missing_text(missing).left(1).to_upper() + Crafting.missing_text(missing).substr(1)])
		"trabalho":
			if not bool(extra.get("counted", true)):
				if Time.get_ticks_msec() - _dry_notice_ms > 8000:
					_dry_notice_ms = Time.get_ticks_msec()
					Speech.say("A argila ainda seca: trabalhar agora rende metade.")
			elif int(extra.get("post_left", 1)) == 0:
				Speech.say("O canto %s terminou a sua parte." % Builds.post_name(int(extra.get("post", 0))))
		"etapa":
			var missing := builds.stage_missing(build_id)
			var dry := float(extra.get("dry", 0.0))
			Speech.say("Etapa concluída. %s%sAgora %s: %s." % [
				"As paredes subiram: a porta fica ao %s. " % builds.get_build(build_id)["entrance"] if extra.get("walls", false) else "",
				"A argila precisa secar uns %s; dá para trabalhar antes, mas rende metade. " % Builds._minutes_text(dry) if dry > 0.0 else "",
				extra.get("next", ""), Crafting.missing_text(missing) if not missing.is_empty() else "Espaço para trabalhar"])
		"pronta":
			if build["kind"] == "marco":
				Speech.say("O marco está pronto. %s" % (
					"Espaço nele para dar nome ao povoado." if builds.can_name(build_id) else
					"Com uma fogueira nesta região, o lugar vira um povoado."))
			elif Crafting.is_large(build["kind"]):
				Speech.say("%s está pront%s: %d por %d casas, com a porta para o %s.%s" % [
					Crafting.build_title(build["kind"]), Crafting.BUILDS[build["kind"]]["article"], int(build["size"]), int(build["size"]), build["entrance"],
					" " + Builds.furniture_hint(build) if Crafting.has_furniture(build["kind"]) else ""])
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
		"silex":
			Speech.say("Você pôs um sílex na fogueira. Agora Espaço bate as pedras para acender.")
		"abasteceu", "alimentou":
			var minutes := ceili(builds.fuel_left(build_id) / 60.0)
			Speech.say("Você pôs uma %s. Lenha para uns %d minuto%s." % [
				Crafting.material_text(extra.get("item", ""), 1).trim_prefix("1 "), minutes, "" if minutes == 1 else "s"])


## Um golpe de machado numa obra que está sendo desmontada. Soa onde bateu;
## quem bateu ouve, no primeiro golpe, quantos faltam.
@rpc("authority", "call_local", "reliable")
func build_struck(build_id: int, cell: Vector2i, hits_left: int, total: int, first: bool, by_id: int) -> void:
	if world == null:
		return
	var where := WorldGen.cell_center(cell)
	if where.distance_to(_pos) <= HEARING_RADIUS:
		audio.play_at_point(where, Sounds.build_knock(), 0.0, true, true)
	if by_id == my_id and first:
		Speech.say("Você começa a desmontar %s. Uns %d golpes de machado." % [builds.spoken_name(build_id), total])


## A obra veio abaixo: sai do mundo e o que sobrou está no chão, dentro do terreno.
@rpc("authority", "call_local", "reliable")
func build_demolished(build_id: int, cell: Vector2i, title: String, kind: String, back: Dictionary, by_id: int) -> void:
	if world == null:
		return
	var where := WorldGen.cell_center(cell)
	builds.remove_build(build_id)
	_unstick()
	_refresh_fires()
	_sync_menu.call_deferred()
	if where.distance_to(_pos) <= HEARING_RADIUS:
		audio.play_at_point(where, Sounds.build_stage(), 0.0, true, true)
	if by_id != my_id:
		return
	var left := "" if back.is_empty() else " Sobrou no chão, dentro do terreno: %s." % Economy.items_text(back)
	var article: String = Crafting.BUILDS[kind]["article"] if Crafting.BUILDS.has(kind) else "o"
	Speech.say("Você desmontou %s %s.%s" % [article, Crafting.build_name(kind), left])


## Aviso de votação no marco, só para os membros do povoado (ou quem agiu).
func _say_vote_event(marco: Dictionary, event: String, by_id: int, target: String) -> void:
	if by_id != my_id and not marco.get("voters", []).has(_my_key()):
		return
	var where: String = marco["name"] if not str(marco["name"]).is_empty() else "do povoado"
	match event:
		"votacao_aberta":
			Speech.say("Votação aberta no marco %s: derrubar %s. Espaço no marco para votar." % [where, target])
		"votacao_aprovada":
			Speech.say("Votação aprovada: %s pode ser derrubado com o machado." % target)
		"votacao_rejeitada":
			Speech.say("Votação encerrada sem maioria: %s fica de pé." % target)


## Uma arma ficou pronta e foi para a bolsa.
@rpc("authority", "call_local", "reliable")
func crafted(new_bag: Dictionary, weapon: String) -> void:
	if world == null:
		return
	_sync_menu.call_deferred()
	inventory = new_bag
	var recipe := Crafting.recipe(weapon)
	var done_text := "Você fabricou %s %s. Está na bolsa: empunhe pela Bolsa, no menu das setas." % [
		"uma" if recipe["article"] == "a" else "um", Crafting.weapon_name(weapon)]
	if not Crafting.is_tool_recipe(weapon):
		for i in CRAFT_KNOCKS:
			get_tree().create_timer(0.3 * i).timeout.connect(_play.bind(Sounds.build_knock(), true))
		get_tree().create_timer(0.3 * CRAFT_KNOCKS).timeout.connect(_play.bind(Sounds.build_stage()))
		Speech.say(done_text)
		return
	# Ferramenta: dá trabalho. Cada passo tem as suas batidas e a sua fala; a
	# ferramenta já está na bolsa, mas só se anuncia no fim.
	var clock := 0.0
	for step: Dictionary in recipe["steps"]:
		get_tree().create_timer(clock).timeout.connect(Speech.say.bind(step["say"], false))
		for i in int(step["knocks"]):
			get_tree().create_timer(clock + 0.9 + CRAFT_TOOL_KNOCK * i).timeout.connect(_play.bind(Sounds.build_knock(), true))
		clock += 0.9 + CRAFT_TOOL_KNOCK * int(step["knocks"]) + 0.5
		get_tree().create_timer(clock - 0.4).timeout.connect(_play.bind(Sounds.build_stage()))
	get_tree().create_timer(clock + 0.2).timeout.connect(Speech.say.bind(done_text, true))


@rpc("authority", "call_local", "reliable")
func inventory_changed(new_inventory: Dictionary, verb: String, item: String, amount := 1, parts := {}, extras := {}, kept := {}, left_over := {}) -> void:
	if world == null:
		return
	_sync_menu.call_deferred()
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
	_sync_menu.call_deferred()
	inventory = new_bag
	wielded = new_wielded
	match verb:
		"empunhou":
			_play(Sounds.wield())
			Speech.say("Você empunha %s. %s" % [Bag.with_article(item), Bag.WIELDABLE.get(item, "")])
		"guardou":
			_play(Sounds.stow())
			Speech.say("Você guardou %s na bolsa." % Bag.with_article(item))


## Quem leva uma tocha acesa mudou (acendeu, queimou, entrou no mundo).
@rpc("authority", "call_local", "reliable")
func torches_changed(ids: Array) -> void:
	torch_bearers = ids


func _broadcast_torches() -> void:
	torches_changed.rpc(state.lit_torch_ids())


## A mão não dominante mudou (a tocha). "lit_left": segundos de tocha acesa.
## verb: "empunhou", "guardou", "acendeu", "queimou" ou "" (só sincroniza).
@rpc("authority", "call_local", "reliable")
func offhand_changed(new_bag: Dictionary, new_offhand: String, lit_left: float, verb: String, item: String) -> void:
	if world == null:
		return
	_sync_menu.call_deferred()
	inventory = new_bag
	offhand = new_offhand
	_torch_ends = Time.get_unix_time_from_system() + lit_left if lit_left > 0.0 else 0.0
	match verb:
		"empunhou":
			_play(Sounds.wield())
			Speech.say("Você empunha %s na mão não dominante. %s" % [Bag.with_article(item), Bag.WIELDABLE.get(item, "")])
		"guardou":
			_play(Sounds.stow())
			Speech.say("Você guardou %s na bolsa." % Bag.with_article(item))
		"acendeu":
			_striking = false
			_play(Sounds.fire_ignite())
			Speech.say("A tocha acende. Ela queima por uns %d minutos e afasta o Calado." % ceili(lit_left / 60.0))
		"queimou":
			_play(Sounds.stow())
			Speech.say("A tocha queimou até o fim e virou cinza.")


## Outra criatura empunhou, guardou ou golpeou: o som sai de onde ela está.
@rpc("authority", "call_local", "reliable")
func player_handled(id: int, verb: String) -> void:
	if world == null or not players.has(id) or id == my_id:
		return
	var stream: AudioStream = {"empunhou": Sounds.wield(), "guardou": Sounds.stow(), "golpeou": Sounds.axe_swing(),
		"fabricou": Sounds.build_knock(), "faisca": Sounds.fire_spark()}.get(verb)
	_play_other(players[id]["pos"], stream)


@rpc("authority", "call_local", "reliable")
func action_failed(reason: String, detail: String) -> void:
	if world == null:
		return
	match reason:
		"arvore":
			Speech.say(detail)
		"tocha_acesa":
			Speech.say("Tocha acesa não se guarda nem se troca: ela queima até o fim.")
		"tocha_sem_fogo", "tocha_sem_material":
			Speech.say("Para acender a tocha, chegue perto de uma fogueira acesa, ou precisa de faca ou sílex, e de uma pedra pequena.")
		"tocha_ja_acesa":
			Speech.say("A tocha já está acesa.")
		"tocha_sem_tocha":
			Speech.say("Você não tem uma tocha na mão não dominante.")
		"golpear":
			Speech.say("Ainda está de pé. Empunhe o machado e golpeie com J.")
		"cheio":
			Speech.say("Você não consegue levar mais, %d de %d no limite absoluto. Jogue algo fora pela Bolsa, no menu das setas." % [Bag.load_of(inventory, wielded, offhand), Bag.MAX_LOAD])
		"nao_tem":
			Speech.say("Não há %s na sua bolsa." % Bag.spoken_name(detail))
		"nao_empunha":
			Speech.say("Não dá para empunhar %s." % Bag.spoken_name(detail))
		"maos_livres":
			Speech.say("Suas mãos já estão livres.")
		"obra_lugar":
			Speech.say("Não dá para construir aí à frente. Procure chão livre, fora da trilha, da água e dos recursos.")
		"obra_perto":
			Speech.say("Há outra construção, a água, a trilha ou um recurso nesse lugar, ou perto demais: entre uma obra e outra ficam sempre 2 casas livres.")
		"obra_regiao":
			Speech.say("Esta região já tem um marco.")
		"obra_ocupado":
			Speech.say("Tem alguém nesse lugar.")
		"obra_faltam":
			Speech.say("Para esta etapa %s, e não há nada disso na sua bolsa." % detail)
		"obra_pronta":
			Speech.say(detail)
		"obra_preparo":
			Speech.say(detail)
		"obra_porta_longe":
			pass  # Espaço longe da porta não faz nada.
		"obra_canto":
			Speech.say("Aqui não há mais o que fazer. Vá a um canto que ainda tem batidas: %s." % detail)
		"obra_sem_povoado":
			Speech.say("Obras grandes só se começam num povoado: falta um marco com nome nesta região.")
		"obra_agua":
			Speech.say("Esse terreno pega água. Escolha outro lugar.")
		"obra_tamanho", "obra_entrada":
			Speech.say("Esse tamanho ou essa porta não serve.")
		"obra_regiao_longe":
			Speech.say("Só dá para marcar o terreno de uma obra na região em que você está.")
		"desmontar_povoado":
			Speech.say("O marco só se desmonta quando não resta outra construção no povoado. Desmonte as outras antes.")
		"desmontar_votacao":
			Speech.say("Esta construção é do povoado: só se derruba depois que os membros aprovam em votação no marco.")
		"votar_nao_membro":
			Speech.say("Só membros votam: dono de abrigo neste povoado há 7 dias, e ativo.")
		"votar_alvo":
			Speech.say("Esta construção não vai a votação.")
		"votar_ja_votando":
			Speech.say("Já há votação sobre esta construção.")
		"votar_ja_aprovada":
			Speech.say("Esta construção já foi aprovada para derrubar.")
		"votar_ja_propos":
			Speech.say("Você já tem uma proposta em votação.")
		"votar_espera":
			Speech.say("Você poderá propor outra votação daqui a %s." % detail)
		"votar_ja_votou":
			Speech.say("Você já votou nesta proposta.")
		"votar_sem_votacao", "votar_nao_marco", "votar_desconhecida":
			Speech.say("Essa votação não existe mais.")
		"votar_longe":
			Speech.say("Chegue perto do marco para votar.")
		"desmontar_nao_dono":
			Speech.say("Só o dono derruba esta construção.")
		"desmontar_acesa":
			Speech.say("A fogueira está acesa. Espere apagar para desmontá-la.")
		"desmontar_ferramenta":
			Speech.say("Para desmontar uma obra, empunhe o machado.")
		"preparo_ferramenta":
			Speech.say("Para esta fase, empunhe %s pela Bolsa." % Bag.with_article(detail) if not detail.is_empty() else "Empunhe a ferramenta certa.")
		"preparo_fase":
			pass
		"obra_sem_silex":
			Speech.say("A fogueira apagada pede um sílex, e não há nenhum na sua bolsa.")
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
		"dono_fora":
			Speech.say("Entre no abrigo para isso.")
		"dono_lotada":
			Speech.say("%s já tem todos os donos." % detail)
		"dono_ja_dono":
			Speech.say("Você já é dono deste abrigo.")
		"dono_ja_tem_outro":
			Speech.say("Você já é dono de outro abrigo. Deixe de ser dono dele antes.")
		"dono_nao_dono":
			Speech.say("Você não é dono deste abrigo.")
		"dono_nao_pronta", "dono_sem_dono":
			Speech.say("Este lugar não tem dono.")
		"estoque_nao_aceita":
			var parts := detail.split("|")
			Speech.say("%s não guarda %s." % [parts[1], Bag.spoken_name(parts[0])])
		"estoque_nao_guarda":
			Speech.say("Aqui não se guarda nada.")
		"estoque_nao_dono":
			Speech.say("O armário é só dos donos.")
		"estoque_nao_tem":
			Speech.say("Não há isso aí.")
		"estoque_cheio":
			Speech.say("%s está cheio: não cabe mais %s." % [detail.split("|")[1], Bag.spoken_name(detail.split("|")[0])])
		"estoque_carga":
			Speech.say("Você não consegue levar mais, %d de %d no limite absoluto. Guarde ou jogue algo antes de pegar mais." % [Bag.load_of(inventory, wielded, offhand), Bag.MAX_LOAD])
		"arma_faltam":
			var parts := detail.split("|")
			Speech.say("Para %s %s." % [Crafting.weapon_name(parts[0]), parts[1] if parts.size() > 1 else ""])
		"arma_sem_bancada":
			Speech.say("Isso só se faz na bancada de uma oficina: chegue junto dela e aperte Espaço.")
		"arma_cheio":
			Speech.say("Você já carrega o máximo de %s." % Crafting.recipe(detail.split("|")[0])["name"][1])
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
	# Velocidade dela, estimada pelo que andou entre duas posições: os passos seguem o mesmo ritmo.
	var now := Time.get_ticks_msec()
	var dt := float(now - int(steps.get("last_ms", 0))) / 1000.0
	if steps["idle"] < OTHER_WALK_GRACE and dt >= 0.03 and dt <= 0.5:
		var rate := clampf(old_pos.distance_to(pos) / dt / WALK_SPEED, MIN_STEP_RATE, 1.0)
		steps["rate"] = lerpf(float(steps.get("rate", 1.0)), rate, 0.3)
	steps["last_ms"] = now
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
	daytime.start_server(state)
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
	request_join.rpc_id(1, Net.player_name, Net.password)


func _on_connection_failed() -> void:
	_back_to_menu("Não foi possível conectar ao servidor. Confira o endereço e a conexão e tente de novo.")


func _on_server_disconnected() -> void:
	_back_to_menu("A conexão com o servidor caiu.")


## Volta ao menu principal; com message, o menu mostra o aviso numa caixa.
func _back_to_menu(message := "") -> void:
	if not message.is_empty():
		print("[cliente] voltando ao menu: %s" % message)
	Net.menu_notice = message
	Net.stop()
	if DisplayServer.get_name() == "headless":
		get_tree().quit(1)
		return
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")


# --- Lado do jogador ---------------------------------------------------------

## Para onde as teclas mandam andar agora (em casas por segundo, no mundo).
func _wanted_motion() -> Vector2:
	if horrors.is_caught():
		return Vector2.ZERO
	if _auto_target != null:
		var to_target: Vector2 = _auto_target - _pos
		if to_target.length() < 0.1:
			_auto_target = null
			return Vector2.ZERO
		return to_target.normalized() * minf(WALK_SPEED * Bag.speed_factor(inventory, wielded, offhand), to_target.length() * 10.0)
	var ahead := Input.get_axis("andar_tras", "andar_frente")
	var side := Input.get_axis("passo_esquerda", "passo_direita")
	if ahead == 0.0 and side == 0.0:
		return Vector2.ZERO
	# Cada direção tem o seu fator; na diagonal as partes se somam, sem passar da frente.
	var motion := Compass.forward(_heading) * ahead * (BACK_FACTOR if ahead < 0.0 else 1.0) \
			+ Compass.right(_heading) * side * SIDE_FACTOR
	if motion.length() > 1.0:
		motion = motion.normalized()
	return motion * WALK_SPEED * Bag.speed_factor(inventory, wielded, offhand)


## Se a criatura ficou dentro de algo sólido (uma obra que chegou enquanto ela
## andava para a casa), sai para o ponto livre mais perto e avisa o servidor.
func _unstick() -> void:
	if world == null or world.is_free(_pos):
		return
	_set_pos(world.nearest_free(_pos))
	_last_sent = Vector2.INF


## Anda com colisão: se bater de frente, tenta deslizar ao longo do
## obstáculo; se não der para andar nada, esbarra.
func _walk(motion: Vector2) -> void:
	if motion == Vector2.ZERO:
		return
	var target := _pos + motion
	if world.is_free(target):
		_set_pos(target)
		return
	_unstick()
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


## Dentro de uma construção grande de paredes de pé: o chão é de terra batida.
func _indoors(cell: Vector2i) -> bool:
	var build := builds.at(cell)
	return not build.is_empty() and Crafting.is_large(build["kind"]) and Builds.walls_up(build)


func _play_my_step() -> void:
	var cell := WorldGen.cell_of(_pos)
	_play(Sounds.footstep(world.biome_at(cell), world.thing_at(cell), _indoors(cell)), true, FOOTSTEP_DB)
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
		steps["clock"] += delta * float(steps.get("rate", 1.0))
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
	_announce_site(old_cell, cell)
	if ground.has_pile(cell):
		Speech.say("No chão: %s. Espaço pega." % _pile_text(cell), false)


## Espaço: coleta o que estiver ao alcance, dando preferência ao que está à
## frente.
func _interact() -> void:
	if _striking:
		# Riscando a tocha: cada Espaço é uma batida (o som sai já, a cadência vale no servidor).
		_play(Sounds.fire_spark())
		request_spark.rpc_id(1)
		return
	var target := _collect_target()
	var build := _build_target()
	var pile := ground.nearest(_pos, COLLECT_REACH)
	# O que está mais perto vence; empate: obra, depois monte, depois recurso.
	var build_distance := INF if build.is_empty() else Builds.reach_distance(build, _pos)
	var pile_distance := INF if pile == WorldGen.NO_CELL else _pos.distance_to(WorldGen.cell_center(pile))
	var target_distance := INF if target == WorldGen.NO_CELL else _pos.distance_to(WorldGen.cell_center(target))
	# No preparo de um terreno (limpeza, capina) o Espaço não tem o que fazer na
	# obra: o que caiu no chão ali dentro vem primeiro.
	if not build.is_empty() and Crafting.is_large(build["kind"]) and not build["done"] \
			and builds.phase_of(int(build["id"])) != "obra" and (pile != WorldGen.NO_CELL or target != WorldGen.NO_CELL):
		build_distance = INF
	if build_distance <= pile_distance and build_distance <= target_distance and not build.is_empty():
		if builds.can_name(int(build["id"])):
			# Marco pronto com fogueira na região: abre a escolha do nome.
			Speech.say(_menu.open_at("Nome do povoado, primeira palavra", _name_nouns.bind(int(build["id"]))))
		elif build["kind"] == "marco" and build["done"] and not str(build["name"]).is_empty():
			# O marco do povoado: de onde partem as obras grandes.
			Speech.say(_menu.open_at("Povoado %s" % build["name"], _marco_root.bind(int(build["id"]))))
		elif Builds.has_furniture(build) and not Builds.furniture_near(build, _pos).is_empty():
			# Oficina: junto da bancada abre as receitas; junto das prateleiras, o armazenamento.
			if Builds.furniture_near(build, _pos) == "bancada":
				Speech.say(_menu.open_at("Bancada de trabalho", _bench_root))
			else:
				Speech.say(_menu.open_at(Builds.stock_label(build), _storage_root.bind(int(build["id"]))))
		elif Builds.stores(build) and not Builds.has_furniture(build) and Builds.inside(build, _pos):
			# Armazém e abrigo: lá dentro, o Espaço abre o armazenamento. Fora, só a porta responde.
			Speech.say(_menu.open_at(Builds.stock_label(build), _storage_root.bind(int(build["id"]))))
		elif Crafting.is_large(build["kind"]) and not build["done"] and builds.phase_of(int(build["id"])) != "obra":
			Speech.say(builds.status_text(int(build["id"])))
		else:
			request_build_work.rpc_id(1, int(build["id"]))
	elif pile != WorldGen.NO_CELL and (pile_distance <= target_distance or harvest.is_ready(target)):
		# O jogador escolhe o que pegar: um monte vira bagunça rápido. O
		# recurso coletável ao alcance entra na lista como mais um item, em
		# vez de o jogo adivinhar qual dos dois o Espaço quis.
		Speech.say(_menu.open_at("Pilha no chão", _pile_pick_items.bind(pile, target)))
	elif target != WorldGen.NO_CELL:
		request_collect.rpc_id(1, target)


## O recurso que o Espaço recolhe: o mais perto, com preferência para o que
## está à frente e para o que dá para recolher agora (um bambu de pé ou algo
## já colhido só é escolhido se não houver outro, para a fala explicar).
func _collect_target() -> Vector2i:
	return _nearest_resource(COLLECT_REACH, func(cell: Vector2i):
		return Harvest.is_source(world.thing_at(cell)) and builds.at(cell).is_empty(), true)


## A construção mais perto ao alcance do Espaço, com preferência para a que
## está à frente, ou {}.
func _build_target() -> Dictionary:
	var best := {}
	var best_score := INF
	var ahead := Compass.forward(_heading)
	for build: Dictionary in builds.all():
		var offset := Builds.nearest_point(build, _pos) - _pos
		var distance := Builds.reach_distance(build, _pos)
		if distance > BUILD_REACH:
			continue
		var score := distance - (0.6 if offset.length() > 0.01 and ahead.dot(offset / offset.length()) > 0.5 else 0.0)
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
		return Harvest.needs_tool(world.thing_at(cell)) and builds.at(cell).is_empty(), false)


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


## O crepitar das tochas acesas: a sua, na mão esquerda (a não dominante),
## e as dos outros, onde eles estão.
func _update_torch_sounds() -> void:
	var points := []
	if _torch_ends > Time.get_unix_time_from_system() and not offhand.is_empty():
		var left := Compass.forward(_heading).rotated(-PI / 2.0)
		points.append(_pos + left * 0.4)
	for id: int in torch_bearers:
		if id != my_id and players.has(id):
			points.append(players[id]["pos"])
	audio.set_torches(points)


func _say_inventory() -> void:
	var hands := "Mãos livres." if wielded.is_empty() else "Nas mãos: %s." % Bag.spoken_name(wielded)
	if not offhand.is_empty():
		hands += " Na mão não dominante: %s, %s." % [Bag.spoken_name(offhand), "acesa" if _torch_ends > Time.get_unix_time_from_system() else "apagada"]
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
	# No terreno de uma obra grande, o machado limpa e a enxada capina.
	if wielded == "machado" or wielded == "enxada":
		var prep := builds.prep_target(_pos, Compass.forward(_heading), STRIKE_REACH, wielded)
		if not prep.is_empty():
			get_tree().create_timer(SWING_TO_HIT).timeout.connect(_play.bind(Sounds.axe_hit(), true))
			request_prep.rpc_id(1, int(prep["id"]), prep["cell"])
			return
	if wielded == "machado":
		# Sem bambu à frente, o machado desmonta a obra ao alcance (paredes,
		# cantos, marco, fogueira): muitos golpes, ver Builds.wreck_hits.
		var wreck := builds.wreck_target(_pos, Compass.forward(_heading), STRIKE_REACH)
		if not wreck.is_empty() and _strike_target() == WorldGen.NO_CELL:
			get_tree().create_timer(SWING_TO_HIT).timeout.connect(_play.bind(Sounds.axe_hit(), true))
			request_wreck.rpc_id(1, int(wreck["id"]), wreck["cell"])
			return
	if wielded == "faca":
		# A faca só serve para sangrar o tronco de uma árvore.
		var tree := _nearest_resource(STRIKE_REACH, func(cell: Vector2i):
			return world.thing_at(cell) == WorldGen.Thing.ARVORE and builds.at(cell).is_empty() \
					and harvest.is_available(cell) and harvest.hits_left(cell) > 0, false)
		if tree != WorldGen.NO_CELL:
			get_tree().create_timer(SWING_TO_HIT).timeout.connect(_play.bind(Sounds.axe_hit(), true))
			request_tap.rpc_id(1, tree)
		else:
			request_swing.rpc_id(1)
		return
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
	Speech.say("W e S: andar para frente e para trás. A e D: passo para o lado. Q e E: girar. Setas: menu flutuante, com o Caminheiro. I abre a Bolsa e V abre o Caminheiro direto. " + MenuNav.help() + " A cada giro, a bússola dá um clique: agudo no norte, grave no sul, médio no leste e no oeste, abafado nas diagonais. F: para onde estou olhando. C: onde estou; apertando de novo, o momento do dia e onde o anel está em relação a você (e assim, em ciclo). T: o período do dia e a estação. O mundo anoitece e amanhece, e o Calado só ronda de noite, com mais dificuldade sob a luz do anel. Espaço: coletar gravetos ou frutas de um arbusto, argila, pedras ou um bambu derrubado, ou pegar itens do chão. A carga plena é 24; acima disso você anda mais devagar, até o limite de 36. Pela Bolsa, no menu das setas, dá para jogar itens no chão. J: golpear com o machado, depois de empunhá-lo pela Bolsa, no menu das setas. A tocha vai na mão não dominante, sem tirar o que está na principal: em Equipamento, Acender acende na hora perto de uma fogueira acesa; longe de uma, com uma pedra pequena e uma faca (de graça) ou um sílex (que se gasta), você risca com Espaço, num ritmo constante, de 5 a 9 batidas, e parar por um segundo cancela; o barulho pode atrair o Calado. Acesa, ela afasta o Calado enquanto queima. Com a faca bruta de sílex empunhada, J no tronco de uma árvore, poucas vezes, faz a resina escorrer; depois de uns instantes, Espaço recolhe. Espaço numa árvore de pé conta como ela está. Golpes demais secam a árvore. Fabricar, no menu das setas: começar um marco ou uma fogueira à frente, ou fazer uma arma. Espaço perto de uma obra deposita materiais e trabalha nela; numa fogueira pronta, bate as pedras para acender ou põe lenha; para reacendê-la depois que apaga, Espaço põe a lenha e 1 sílex, e então acende. Um marco e uma fogueira na mesma região fazem um povoado: Espaço no marco pronto abre as listas para escolher o nome, e o povoado passa a aparecer em Locais, no Caminheiro. Espaço no marco de um povoado abre as obras grandes: escolha o quadrante da região (ou o lado de uma construção), o canto ou o redor de um lago, o tamanho e a porta. O terreno se prepara primeiro: com o machado empunhado, J arranca árvores, bambus e arbustos; com a enxada, que se fabrica em Fabricar, Ferramentas, J capina a grama de cada casa. Depois, cada etapa se divide em 4 cantos, e a argila do chão precisa secar. Construções, no Caminheiro, mostra as que estão a até 36 metros e leva ao que falta. Tab: radar. Diz para onde o cristal do Caminheiro leva e a distância, e depois o recurso mais próximo de cada tipo e as construções que há a até 24 metros, do mais perto ao mais longe. Se os pássaros fugirem e o mundo for ficando abafado, algo vem atrás de você: ouça de onde vem a respiração dele e gire até ficar de frente para ela, que então se cala; ou corra. Encarado, ele para e acaba indo embora; só a chama de uma fogueira acesa o afasta. P: quem está no mundo. R: repetir a última fala. Trilhas de terra ligam as regiões do mundo;")


## Tab: radar. Diz o alvo do Caminheiro e a distância até ele (se o cristal
## estiver aceso) e, depois, o recurso coletável mais perto de cada tipo e as
## construções que há no raio do radar, do mais perto ao mais longe.
func _say_radar() -> void:
	var parts := PackedStringArray()
	if _caminheiro.active:
		parts.append("Caminheiro, rumo %s: %s." % [Narrator.contract("a", _caminheiro.place_name), Compass.describe(_tracked_destination - _pos, _heading)])
	var found := []  # [distância, rótulo, deslocamento]
	for entry: Array in CAMINHEIRO_RESOURCES:
		var cell := nearest_collectable(world, harvest, _pos, entry[1], RADAR_RADIUS)
		if cell == WorldGen.NO_CELL or (_caminheiro.active and cell == _tracked_resource):
			continue
		var offset := WorldGen.cell_center(cell) - _pos
		found.append([offset.length(), entry[0], offset])
	for build: Dictionary in builds.all():
		var distance := Builds.reach_distance(build, _pos)
		if distance > RADAR_RADIUS:
			continue
		var spoken := builds.spoken_name(int(build["id"]))
		found.append([distance, spoken.left(1).to_upper() + spoken.substr(1), WorldGen.cell_center(build["cell"]) - _pos])
	found.sort_custom(func(a, b): return a[0] < b[0])
	for item: Array in found:
		parts.append("%s: %s." % [item[1], Compass.describe(item[2], _heading)])
	if found.is_empty():
		parts.append("Não há recursos nem construções por perto.")
	Speech.say(" ".join(parts))


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
	_play_other(pos, Sounds.footstep(world.biome_at(cell), world.thing_at(cell), _indoors(cell)), FOOTSTEP_DB)
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
	_bed_tween.tween_property(_bed, "volume_db", BED_VOLUME_DB, 1.5)
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
	if _wind_tween != null:
		_wind_tween.kill()
	_wind_tween = create_tween()
	_wind_tween.tween_property(_wind, "volume_db", target, WIND_FADE)


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
		{"label": "Bolsa", "open": _bag_items, "empty": "vazia, carga plena %d" % Bag.CAPACITY,
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
		items.append({"label": Bag.load_label(inventory, wielded, offhand),
			"info": "%s. Cabem mais %d de peso, mas acima de %d você anda mais devagar, até metade da velocidade com %d." % [Bag.load_label(inventory, wielded, offhand), Bag.free_space(inventory, wielded, offhand), Bag.CAPACITY, Bag.MAX_LOAD]})
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
	if amount <= 0:
		return actions  # o item acabou: o menu devolve o foco ao pai
	if Bag.can_wield(item):
		actions.append({"label": "Empunhar", "run": _equip.bind(item)})
	actions.append({"label": "Jogar 1", "run": _drop.bind(item, 1)})
	if amount > 1:
		actions.append({"label": "Jogar tudo, %d" % amount, "run": _drop.bind(item, amount)})
	return actions


## A bolsa, as mãos ou o chão mudaram: atualiza o menu das setas. Se o item
## em foco acabou, o foco sobe ao menu pai mais próximo que ainda exista e a
## nova posição é falada, sem cortar o que já estava sendo dito. Chamado
## adiado, para entrar depois da fala do próprio aviso.
func _sync_menu() -> void:
	if _menu != null:
		Speech.say(_menu.sync(), false)


## Jogar passa pelo servidor; a resposta (ground_changed) é que fala e toca.
func _drop(item: String, amount: int) -> String:
	request_drop.rpc_id(1, item, amount)
	return ""


## O que está nas mãos, com o botão Guardar.
func _equipment_items() -> Array:
	var items := []
	if not wielded.is_empty():
		items.append({"label": Bag.display_name(wielded), "open": _equipment_actions})
	if not offhand.is_empty():
		var lit := _torch_ends > Time.get_unix_time_from_system()
		items.append({"label": "%s, mão não dominante%s" % [Bag.display_name(offhand), ", acesa" if lit else ", apagada"],
			"open": _offhand_actions})
	return items


func _offhand_actions() -> Array:
	if offhand.is_empty():
		return []
	var left := _torch_ends - Time.get_unix_time_from_system()
	if left > 0.0:
		return [{"label": "Acesa", "info": "Queima por mais uns %d minuto%s e afasta o Calado. Tocha acesa não se guarda." % [
			ceili(left / 60.0), "" if ceili(left / 60.0) == 1 else "s"]}]
	return [
		{"label": "Acender", "run": _light_torch},
		{"label": "Guardar", "run": _stow_offhand},
	]


func _light_torch() -> String:
	request_light_torch.rpc_id(1)
	return ""


func _stow_offhand() -> String:
	request_stow_offhand.rpc_id(1)
	return ""


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
	["Cipó", [WorldGen.Thing.CIPO], "o cipó"],
	["Fibra vegetal", [WorldGen.Thing.FIBRA], "a fibra vegetal"],
	["Sílex", [WorldGen.Thing.SILEX], "o sílex"],
]
## Até onde (em casas, em linha reta) o Caminheiro enxerga:
## meia região para cada lado (24 casas, 36 m), então vale para tudo que está
## na região de agora ou na vizinha, sem depender de limites de região.
const RESOURCE_SEARCH_RADIUS := WorldGen.REGION_SIZE / 2
## O radar (Tab) enxerga menos: 16 casas (24 m).
const RADAR_RADIUS := 16


## Menu do Caminheiro: Locais (lugares do mapa) e Recursos (leva ao coletável
## mais próximo de cada tipo). A fabricação pendura aqui a categoria
## Construções.
func _caminheiro_items() -> Array:
	var items := [
		{"label": "Locais", "open": _caminheiro_places},
		{"label": "Recursos", "open": _caminheiro_resources},
		{"label": "Construções", "open": _caminheiro_builds, "empty": "nenhuma por perto"},
		{"label": "Itens no chão", "open": _caminheiro_piles, "empty": "nenhum por perto"},
	]
	if _caminheiro.active:
		items.append({"label": "Apagar o cristal", "run": _stop_tracking})
	return items


## Lugares do mapa: os povoados, pelo nome que cada um recebeu,
## do mais perto ao mais longe ("Clareira Esquecida, 40 metros"). Um lugar só
## vira local quando é um povoado com nome (marco e fogueira na mesma região).
func _caminheiro_places() -> Array:
	var items := []
	var marcos := builds.settlements()
	marcos.sort_custom(func(a, b): return _pos.distance_squared_to(WorldGen.cell_center(a["cell"])) < _pos.distance_squared_to(WorldGen.cell_center(b["cell"])))
	for build: Dictionary in marcos:
		var meters := Compass.meters(_pos.distance_to(WorldGen.cell_center(build["cell"])))
		items.append({"label": "%s, %s" % [build["name"], meters],
			"run": _track.bind(_approach_point(build["cell"]), "o povoado " + build["name"]), "stay": true})
	items.append_array(_neighbor_region_items())
	return items


## As regiões vizinhas de terra (as ligadas por trilha à de agora), com o
## bioma e a distância até o ponto de encontro de cada uma.
func _neighbor_region_items() -> Array:
	var items := []
	var region := world.region_of(WorldGen.cell_of(_pos))
	var names := {Vector2i.UP: "ao norte", Vector2i.RIGHT: "a leste", Vector2i.DOWN: "ao sul", Vector2i.LEFT: "a oeste"}
	for step: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		var next := region + step
		if not world.has_trail(region, next):
			continue
		var landmark := world.region_landmark(next)
		var meters := Compass.meters(_pos.distance_to(landmark))
		items.append({"label": "Região %s, %s, %s" % [names[step], world.place_name(WorldGen.cell_of(landmark)), meters],
			"run": _track.bind(landmark, "a região %s" % names[step])})
	return items


## Os montes da região de agora, do mais perto ao mais longe, para escolher
## qual rastrear: "Pilha com pedras e lenhas, 12 metros".
func _caminheiro_piles() -> Array:
	var items := []
	var cells: Array = ground.cells().filter(func(c: Vector2i): return WorldGen.cell_center(c).distance_to(_pos) <= RESOURCE_SEARCH_RADIUS)
	cells.sort_custom(func(a, b): return _pos.distance_squared_to(WorldGen.cell_center(a)) < _pos.distance_squared_to(WorldGen.cell_center(b)))
	for cell: Vector2i in cells:
		var what := _pile_name(cell)
		var meters := Compass.meters(_pos.distance_to(WorldGen.cell_center(cell)))
		items.append({"label": "%s, %s" % [what.left(1).to_upper() + what.substr(1), meters],
			"run": _track.bind(WorldGen.cell_center(cell), "a " + what, cell), "stay": true})
	return items


## "pilha com pedras e lenhas": só o que há nela, sem quantidades nem tamanhos.
func _pile_name(cell: Vector2i) -> String:
	var bases := []
	for key: String in ground.items_at(cell):
		var name: String = Economy.names_of(Economy.base_of(key))[1]
		if not bases.has(name):
			bases.append(name)
	if bases.is_empty():
		return "pilha vazia"
	var text: String = bases[0] if bases.size() == 1 else ", ".join(bases.slice(0, -1)) + " e " + bases[-1]
	return "pilha com " + text


## O que pegar da pilha à frente: cada item dela (e tudo o que couber).
## `resource`: o recurso coletável ao alcance (ou NO_CELL), que entra no fim.
func _pile_pick_items(cell: Vector2i, resource := WorldGen.NO_CELL) -> Array:
	var items := []
	var pile := ground.items_at(cell)
	if pile.size() > 1:
		items.append({"label": "Tudo que couber", "run": _pick_from.bind(cell, "")})
	for key: String in pile:
		items.append({"label": Economy.item_text(key, int(pile[key])), "run": _pick_from.bind(cell, key)})
	if resource != WorldGen.NO_CELL and harvest.is_ready(resource):
		items.append({"label": _resource_pick_label(resource), "run": _collect_resource.bind(resource)})
	return items


## "Argila no chão", "Bambu derrubado": o recurso como item da lista da pilha.
func _resource_pick_label(cell: Vector2i) -> String:
	var text := harvest.spoken_name(cell)
	var thing := world.thing_at(cell)
	if thing in [WorldGen.Thing.ARGILA, WorldGen.Thing.PEDRAS, WorldGen.Thing.SILEX, WorldGen.Thing.CIPO, WorldGen.Thing.FIBRA]:
		text += " no chão"
	return text[0].to_upper() + text.substr(1)


func _collect_resource(cell: Vector2i) -> String:
	request_collect.rpc_id(1, cell)
	return ""


func _pick_from(cell: Vector2i, key: String) -> String:
	request_pick_up.rpc_id(1, cell, key)
	return ""


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


## place vem com artigo ("o povoado Tal", "o bambu"), para a fala juntar direito.
## resource: a casa do recurso, quando o destino é um recurso.
## Escolher de novo o destino que já está aceso apaga o cristal.
func _track(destination: Vector2, place: String, resource := WorldGen.NO_CELL) -> String:
	if _caminheiro.active and _caminheiro.place_name == place:
		return _stop_tracking()
	_tracked_resource = resource
	_tracked_destination = destination
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
	var list: Array = builds.all().filter(func(b: Dictionary): return Builds.reach_distance(b, _pos) <= RESOURCE_SEARCH_RADIUS)
	list.sort_custom(func(a, b): return Builds.reach_distance(a, _pos) < Builds.reach_distance(b, _pos))
	var items := []
	for build: Dictionary in list:
		var spoken := builds.spoken_name(int(build["id"]))
		var meters := Compass.meters(Builds.reach_distance(build, _pos))
		var place: String = Crafting.BUILDS[build["kind"]]["article"] + " " + spoken
		items.append({"label": "%s, %s" % [spoken.left(1).to_upper() + spoken.substr(1), meters],
			"run": _track.bind(_approach_point(_build_goal_cell(build)), place), "stay": true})
	return items


## Para onde o Caminheiro leva numa obra: na limpeza e na capina, a casa que
## ainda falta mais perto; nas etapas de uma obra grande, o canto com batidas
## pendentes mais perto; nas demais, a própria casa.
func _build_goal_cell(build: Dictionary) -> Vector2i:
	var best: Vector2i = build["cell"]
	var best_distance := INF
	if not build["done"] and str(build["phase"]) != "obra":
		for cell: Vector2i in build["prep"]:
			var distance := WorldGen.cell_center(cell).distance_to(_pos)
			if distance < best_distance:
				best_distance = distance
				best = cell
		return best
	if not build["done"] and Builds.post_count(build) > 1:
		for i in Builds.post_count(build):
			if builds.post_left(int(build["id"]), i) <= 0 or not builds.stage_missing(int(build["id"])).is_empty():
				continue
			var cell := Builds.post_cell(build, i)
			var distance := WorldGen.cell_center(cell).distance_to(_pos)
			if distance < best_distance:
				best_distance = distance
				best = cell
		if best_distance < INF:
			return best
	if Builds.post_count(build) > 1:
		if build["done"]:
			return Builds.door_cell(build["cell"], int(build["size"]), str(build["entrance"]))
		return WorldGen.cell_of(Builds.nearest_point(build, _pos))
	return best


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
		{"label": "Ferramentas", "open": _tool_kinds},
	]


## A bancada de uma oficina: as receitas que só se fazem nela (Crafting.WORKSHOP_ORDER).
func _bench_root() -> Array:
	var items := []
	for recipe: String in Crafting.WORKSHOP_ORDER:
		items.append({"label": Crafting.weapon_title(recipe), "open": _weapon_actions.bind(recipe)})
	if items.is_empty():
		items.append({"label": "Ainda sem receitas", "info": "A bancada ainda não tem receitas."})
	return items


func _build_kinds() -> Array:
	var items := []
	for kind: String in Crafting.BUILD_ORDER:
		items.append({"label": Crafting.build_title(kind), "open": _build_actions.bind(kind)})
	return items


func _build_actions(kind: String) -> Array:
	if Crafting.is_large(kind):
		return [
			{"label": "Escolher o lugar", "open": _site_quadrants.bind(kind)},
			{"label": "Materiais", "info": "Obra grande, só em povoado, de %d a %d casas de lado (recomendado %d). Primeiro se limpa o terreno com o machado e se capina com a enxada; depois, %s Cada etapa se divide em 4 cantos." % [
				int(Crafting.BUILDS[kind]["size"]["min"]), int(Crafting.BUILDS[kind]["size"]["max"]),
				int(Crafting.BUILDS[kind]["size"]["default"]), Crafting.build_summary(kind).left(1).to_lower() + Crafting.build_summary(kind).substr(1)]},
		]
	return [
		{"label": "Iniciar à frente", "run": _start_build.bind(kind)},
		{"label": "Materiais", "info": Crafting.build_summary(kind)},
	]


## O lugar é a casa que está à frente quando a criatura escolhe Iniciar.
func _start_build(kind: String) -> String:
	request_build_start.rpc_id(1, kind, _front_cell())
	return ""


## Armazenamento de uma construção pronta: guardar da bolsa e pegar do estoque,
## só do que ela aceita (Crafting.STORAGE).
func _my_key() -> String:
	return WorldState.owner_key_of_name(Net.player_name)


func _storage_root(build_id: int) -> Array:
	var build := builds.get_build(build_id)
	if build.is_empty():
		return []
	var items := []
	if Builds.has_owners(build):
		var mine := Builds.is_owner(build, _my_key())
		items.append({"label": "Deixar de ser dono" if mine else "Ser dono do %s" % Crafting.build_name(build["kind"]),
			"run": (_owner_release if mine else _owner_claim).bind(build_id)})
		items.append({"label": _capital(Builds.owners_text(build)), "info": "%s, %d por %d casas: %s." % [
			Crafting.build_title(build["kind"]), int(build["size"]), int(build["size"]), Builds.owners_text(build)]})
	var key := _my_key()
	var title: String = Crafting.build_title(build["kind"])
	if not Builds.may_use_stock(build, key):
		items.append({"label": "Armário só dos donos", "info": "Cada dono tem o seu armário de %s neste lugar; só ele abre." % Crafting.STORAGE[build["kind"]]["label"]})
		return items
	if not Builds.can_store(build):
		if Builds.stock_load(build, key) > 0:
			items.append({"label": "Pegar do armário", "open": _storage_take_items.bind(build_id)})
		items.append({"label": "Sem armário", "info": "%s de %d por %d casas não tem armário: só os de %s casas de lado têm. %s" % [
			title, int(build["size"]), int(build["size"]), " e ".join(Crafting.STORAGE[build["kind"]]["sizes"].map(str)),
			"Dá para pegar o que sobrou." if Builds.stock_load(build, key) > 0 else ""]})
		return items
	return items + [
		{"label": "Guardar da bolsa", "open": _storage_put_items.bind(build_id)},
		{"label": "Pegar do estoque", "open": _storage_take_items.bind(build_id)},
		{"label": Builds.stock_label(build, key), "info": "%s guarda %s%s. %s. %s" % [
			title, Crafting.STORAGE[build["kind"]]["label"], ", um armário para cada dono" if Builds.personal(build) else "",
			Builds.stock_label(build, key), Bag.load_label(inventory, wielded)]},
	]


## A resposta do servidor (build_changed) é que fala.
func _owner_claim(build_id: int) -> String:
	request_claim.rpc_id(1, build_id)
	return ""


func _owner_release(build_id: int) -> String:
	request_release.rpc_id(1, build_id)
	return ""


func _storage_put_items(build_id: int) -> Array:
	var build := builds.get_build(build_id)
	var items := []
	if build.is_empty():
		return items
	var keys := inventory.keys()
	keys.sort_custom(func(a, b): return Bag.display_name(a).naturalnocasecmp_to(Bag.display_name(b)) < 0)
	for key: String in keys:
		if int(inventory[key]) > 0 and Builds.accepts(build, key):
			items.append({"label": "%s, %d" % [Bag.display_name(key), int(inventory[key])], "open": _storage_amounts.bind(build_id, key, true)})
	if items.is_empty():
		items.append({"label": "Nada na bolsa que caiba aqui", "info": "Este lugar guarda só %s." % Crafting.STORAGE[build["kind"]]["label"]})
	return items


func _storage_take_items(build_id: int) -> Array:
	var build := builds.get_build(build_id)
	var items := []
	if build.is_empty():
		return items
	var stock := Builds.stock_of(build, _my_key())
	var keys: Array = stock.keys()
	keys.sort_custom(func(a, b): return Bag.display_name(a).naturalnocasecmp_to(Bag.display_name(b)) < 0)
	for key: String in keys:
		items.append({"label": "%s, %d" % [Bag.display_name(key), int(stock[key])], "open": _storage_amounts.bind(build_id, key, false)})
	if items.is_empty():
		items.append({"label": "Vazio", "info": "Não há nada guardado aqui."})
	return items


func _storage_amounts(build_id: int, item: String, putting: bool) -> Array:
	var build := builds.get_build(build_id)
	var amount := int(inventory.get(item, 0)) if putting else int(Builds.stock_of(build, _my_key()).get(item, 0))
	var actions := []
	if amount <= 0:
		return actions
	var verb := "Guardar" if putting else "Pegar"
	actions.append({"label": "%s 1" % verb, "run": _storage_move.bind(build_id, item, 1, putting)})
	if amount > 5:
		actions.append({"label": "%s 5" % verb, "run": _storage_move.bind(build_id, item, 5, putting)})
	if amount > 1:
		actions.append({"label": "%s tudo, %d" % [verb, amount], "run": _storage_move.bind(build_id, item, amount, putting)})
	return actions


## A resposta do servidor (build_changed) é que fala e toca.
func _storage_move(build_id: int, item: String, amount: int, putting: bool) -> String:
	if putting:
		request_store.rpc_id(1, build_id, item, amount)
	else:
		request_fetch.rpc_id(1, build_id, item, amount)
	return ""


## Espaço no marco do povoado: obras grandes e votações para derrubar.
func _marco_root(marco_id: int) -> Array:
	var marco := builds.get_build(marco_id)
	var voters: Array = marco.get("voters", [])
	var count: int = marco.get("votes", []).size()
	return [
		{"label": "Obras", "open": _site_kinds},
		{"label": "Votações para derrubar%s" % (", %d aberta%s" % [count, "" if count == 1 else "s"] if count > 0 else ""), "open": _vote_root.bind(marco_id)},
		{"label": "Membros", "info": "%d membro%s ativo%s neste povoado: dono de abrigo há 7 dias e ativo nos últimos 30. %s" % [
			voters.size(), "" if voters.size() == 1 else "s", "" if voters.size() == 1 else "s",
			"Você é membro." if voters.has(_my_key()) else "Você não é membro."]},
	]


func _vote_root(marco_id: int) -> Array:
	var marco := builds.get_build(marco_id)
	var items := []
	for vote: Dictionary in marco.get("votes", []):
		items.append({"label": builds.vote_text(marco_id, int(vote["target"])).trim_suffix("."), "open": _vote_actions.bind(marco_id, int(vote["target"]))})
	items.append({"label": "Propor derrubar uma construção", "open": _vote_targets.bind(marco_id)})
	return items


func _vote_actions(marco_id: int, target_id: int) -> Array:
	return [
		{"label": "Votar a favor", "run": _cast_vote.bind(marco_id, target_id, true), "close": true},
		{"label": "Votar contra", "run": _cast_vote.bind(marco_id, target_id, false), "close": true},
		{"label": "Situação", "info": builds.vote_text(marco_id, target_id)},
	]


func _vote_targets(marco_id: int) -> Array:
	var marco := builds.get_build(marco_id)
	var items := []
	if marco.is_empty():
		return items
	for build: Dictionary in builds.in_region(marco["region"]):
		if not Builds.votable(build):
			continue
		var title := builds.title_of(int(build["id"]))
		if bool(build["approved"]):
			items.append({"label": "%s, já aprovada para derrubar" % title, "info": "%s já foi aprovada: qualquer um pode derrubar com o machado." % title})
		else:
			items.append({"label": title, "run": _propose_wreck.bind(marco_id, int(build["id"])), "close": true})
	if items.is_empty():
		items.append({"label": "Nada a propor", "info": "Não há construções comuns neste povoado. Abrigo com dono é derrubado pelo dono."})
	return items


func _propose_wreck(marco_id: int, target_id: int) -> String:
	request_wreck_propose.rpc_id(1, marco_id, target_id)
	return ""


func _cast_vote(marco_id: int, target_id: int, yes: bool) -> String:
	request_wreck_vote.rpc_id(1, marco_id, target_id, yes)
	return ""


## Obras do povoado (Espaço no marco): as construções grandes.
func _site_kinds() -> Array:
	var items := []
	for kind: String in Crafting.BUILD_ORDER:
		if Crafting.is_large(kind):
			items.append({"label": Crafting.build_title(kind), "open": _site_quadrants.bind(kind)})
	return items


## Primeiro nível: os 4 quadrantes da região e as construções que já há nela.
func _site_quadrants(kind: String) -> Array:
	var region := world.region_of(WorldGen.cell_of(_pos))
	if not builds.has_settlement(region):
		return [{"label": "Falta um povoado nesta região", "info": "Obras grandes só se começam num povoado: um marco e uma fogueira prontos na região, e o marco com nome."}]
	var min_size := int(Crafting.BUILDS[kind]["size"]["min"])
	var items := []
	for quadrant: Dictionary in SitePlanner.quadrants(builds, region, min_size):
		if quadrant["fits"]:
			items.append({"label": quadrant["text"], "open": _site_anchors.bind(kind, quadrant["id"])})
		else:
			items.append({"label": quadrant["text"], "info": "%s. Não cabe uma obra de %d por %d casas." % [quadrant["text"], min_size, min_size]})
	for build: Dictionary in builds.in_region(region):
		var title := builds.title_of(int(build["id"]))
		items.append({"label": "%s, construção" % title, "open": _site_building_anchors.bind(kind, int(build["id"]))})
	return items


## Segundo nível, num quadrante: os cantos dele e o redor dos obstáculos.
func _site_anchors(kind: String, quadrant_id: String) -> Array:
	var region := world.region_of(WorldGen.cell_of(_pos))
	var min_size := int(Crafting.BUILDS[kind]["size"]["min"])
	var quadrant := {}
	for candidate: Dictionary in SitePlanner.quadrants(builds, region, min_size):
		if candidate["id"] == quadrant_id:
			quadrant = candidate
	var items := []
	for anchor: Dictionary in SitePlanner.quadrant_anchors(builds, region, quadrant, min_size):
		items.append({"label": anchor["text"], "open": _site_sizes.bind(kind, anchor)})
	return items


## Segundo nível, numa construção: os quatro lados dela.
func _site_building_anchors(kind: String, build_id: int) -> Array:
	var build := builds.get_build(build_id)
	var items := []
	if build.is_empty():
		return items
	for anchor: Dictionary in SitePlanner.building_anchors(builds, build, int(Crafting.BUILDS[kind]["size"]["min"])):
		items.append({"label": anchor["text"], "open": _site_sizes.bind(kind, anchor)})
	return items


## Tamanho: o recomendado primeiro, depois os outros que cabem.
func _site_sizes(kind: String, anchor: Dictionary) -> Array:
	var limits: Dictionary = Crafting.BUILDS[kind]["size"]
	var sizes := SitePlanner.sizes_for(anchor, limits)
	sizes.sort_custom(func(a, b):
		return absi(int(a["size"]) - int(limits["default"])) * 2 + (1 if a["size"] > limits["default"] else 0) \
				< absi(int(b["size"]) - int(limits["default"])) * 2 + (1 if b["size"] > limits["default"] else 0))
	var items := []
	for entry: Dictionary in sizes:
		var size := int(entry["size"])
		items.append({"label": "%d por %d casas, %s por %s metros%s%s" % [size, size, SitePlanner.meters_text(size), SitePlanner.meters_text(size),
				", recomendado" if size == int(limits["default"]) else "", ", com limpeza do terreno" if entry["needs_clearing"] else ""],
			"open": _site_entrances.bind(kind, anchor, size)})
	return items


## Por fim, o lado da porta; escolher começa a obra.
func _site_entrances(kind: String, anchor: Dictionary, size: int) -> Array:
	var items := [{"label": "Materiais", "info": Crafting.build_summary(kind, size)}]
	for side: String in ["norte", "sul", "leste", "oeste"]:
		items.append({"label": "Porta ao %s" % side, "run": _start_site.bind(kind, anchor, size, side), "close": true})
	return items


func _start_site(kind: String, anchor: Dictionary, size: int, entrance: String) -> String:
	var origin := SitePlanner.rect_for(anchor["corner"], anchor["dir"], size).position
	request_site_start.rpc_id(1, kind, origin, size, entrance)
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
			"run": _name_settlement.bind(build_id, noun, adjective), "close": true})
	return items


func _name_settlement(build_id: int, noun: int, adjective: int) -> String:
	request_name_settlement.rpc_id(1, build_id, noun, adjective)
	return ""


func _weapon_kinds() -> Array:
	var items := []
	for weapon: String in Crafting.WEAPON_ORDER:
		items.append({"label": Crafting.weapon_title(weapon), "open": _weapon_actions.bind(weapon)})
	return items


func _tool_kinds() -> Array:
	var items := []
	for tool: String in Crafting.TOOL_ORDER:
		items.append({"label": Crafting.weapon_title(tool), "open": _weapon_actions.bind(tool)})
	return items


func _weapon_actions(weapon: String) -> Array:
	var materials: Dictionary = Crafting.recipe(weapon)["materials"]
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
		"limite":  # voltar já na raiz do menu: nada mais para voltar
			_play(Sounds.ui_limit(), false, MENU_LIMIT_DB)


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
			"RADAR":
				_say_radar()
			"ONDE":
				_say_where()
			"QUEM":
				_say_who()
			"PASSAROS":
				print("[teste] pássaros por perto: %d" % birds.bird_count())
			"CALADO":  # testes, só quem hospeda: o Calado aparece 12 casas atrás
				print("[teste] calado chamado: %d" % horrors.summon(my_id, 12.0))
			"IR_MEIO_DIA", "IR_ENTARDECER", "IR_GRILOS", "IR_NOITE", "IR_MEIA_NOITE", "IR_CORO", "IR_DIA":  # testes, só quem hospeda: vai para um momento (DayCycle.MOMENTS)
				if Net.is_server():
					Speech.say(daytime.jump_to(command.trim_prefix("IR_").to_lower()))
			"IR_ANEL_ALTO", "IR_LUZ_DESCENDO", "IR_ANEL_BAIXO", "IR_LUZ_SUBINDO":  # testes, só quem hospeda: vai para o começo de uma estação
				if Net.is_server():
					Speech.say(daytime.jump_to_season(["IR_ANEL_ALTO", "IR_LUZ_DESCENDO", "IR_ANEL_BAIXO", "IR_LUZ_SUBINDO"].find(command)))
			"NOITE", "DIA":  # testes, só quem hospeda: muda a hora do mundo (meia-noite ou meio-dia)
				if daytime != null and Net.is_server():
					daytime.set_hour(0.0 if command == "NOITE" else 12.0)
			"HORA":
				Speech.say(daytime.describe())
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
			"CENTRO":
				await _auto_walk(WorldGen.center_point())
			"KIT":  # testes, só quem hospeda: materiais para construir e fabricar
				if state != null:
					var inv := state.inventory_of(my_id)
					for item: String in ["pedra_grande", "pedra_media", "pedra_pequena", "lenha_media", "lenha_pequena", "bambu", "madeira", "silex", "cipo", "fibra", "resina"]:
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
			"LANCA", "CLAVA", "ENXADA", "FACA", "TOCHA":
				_craft(command.to_lower())
			"POVOADO":  # testes, só quem hospeda: um marco com nome e uma fogueira prontos aqui perto
				_test_settlement()
			"MENU_OBRAS":  # testes: abre a escolha de obras do povoado
				Speech.say(_menu.open_at("Obras do povoado", _site_kinds))
			"ABRIGO":  # testes: escolhe a primeira âncora com espaço e começa um abrigo 4x4 com a porta ao sul
				_test_site()
			"ABRIGOS":  # testes, só quem hospeda: povoado e quatro abrigos prontos (3, 4, 5 e 6 casas) aqui perto
				_test_shelters()
			"PREPARO":  # testes: limpa e capina o terreno da obra, casa a casa, pelo servidor
				await _test_prepare()
			"SAIR":
				Net.stop()
				get_tree().quit()


## Teste: um povoado e quatro abrigos prontos, de 3, 4, 5 e 6 casas, em volta de
## quem hospeda. Os donos e o armário se validam entrando em cada um.
func _test_shelters() -> void:
	if state == null:
		return
	if not state.builds.has_settlement(world.region_of(WorldGen.cell_of(_pos))):
		_test_settlement()
	var here := WorldGen.cell_of(_pos)
	var region := world.region_of(here)
	for size in [3, 4, 5, 6]:
		var placed := false
		for r in range(5, 60, 2):
			for dx in range(-r, r + 1, 2):
				for dy in [-r, r]:
					for spot: Vector2i in [here + Vector2i(dx, dy), here + Vector2i(dy, dx)]:
						if placed or not state.builds.site_refusal("abrigo", spot, size, "sul").is_empty():
							continue
						var made: Dictionary = state.builds.start_site("abrigo", spot, size, "sul")
						var build: Dictionary = state.builds.get_build(int(made["id"]))
						build["done"] = true
						build["phase"] = "obra"
						build["stage"] = Crafting.stage_count("abrigo")
						build["prep"] = {}
						build["removed"] = Builds.footprint_cells(spot, size)
						state.builds._register_walls(build)
						print("[teste] abrigo %dx%d em %s" % [size, size, spot])
						placed = true
			if placed:
				break
	build_snapshot.rpc(state.builds.snapshot())


## Teste: um marco com nome e uma fogueira prontos perto de quem hospeda.
func _test_settlement() -> void:
	if state == null:
		return
	var here := WorldGen.cell_of(_pos)
	var spots := []
	for r in range(3, 20):
		for dx in range(-r, r + 1):
			for dy in [-r, r]:
				var cell := here + Vector2i(dx, dy)
				if state.builds.refusal("fogueira", cell).is_empty() and world.region_of(cell) == world.region_of(here):
					spots.append(cell)
		if spots.size() >= 30:
			break
	var marco: int = state.builds.start("marco", spots[0])["id"]
	state.builds.get_build(marco)["done"] = true
	state.builds.get_build(marco)["name"] = "Vale Calmo"
	for cell: Vector2i in spots:
		if state.builds.refusal("fogueira", cell).is_empty():
			state.builds.get_build(int(state.builds.start("fogueira", cell)["id"]))["done"] = true
			break
	build_snapshot.rpc(state.builds.snapshot())


## Teste: começa um abrigo 4x4 na primeira âncora que comporta.
func _test_site() -> void:
	var region := world.region_of(WorldGen.cell_of(_pos))
	for quadrant: Dictionary in SitePlanner.quadrants(builds, region):
		for anchor: Dictionary in SitePlanner.quadrant_anchors(builds, region, quadrant):
			if int(anchor["square_loose"]) >= 4:
				print("[teste] âncora: ", anchor["text"])
				_start_site("abrigo", anchor, 4, "sul")
				return


## Teste: a cada rodada, vai à primeira casa de preparo, empunha a ferramenta da
## fase e golpeia até a casa ficar pronta.
func _test_prepare() -> void:
	for round in 120:
		var target := {}
		for build: Dictionary in builds.all():
			if not build["done"] and str(build["phase"]) != "obra":
				target = build
				break
		if target.is_empty():
			return
		var tool: String = Crafting.PREP_TOOLS[target["phase"]]
		if wielded != tool:
			if state != null and Bag.count(inventory, tool) <= 0:
				state.inventory_of(my_id)[tool] = 1
				equipment_changed(state.inventory_of(my_id), state.wielding(my_id), "", "")
			request_equip.rpc_id(1, tool)
			await get_tree().create_timer(0.3).timeout
			continue
		var cell: Vector2i = (target["prep"] as Dictionary).keys()[0]
		_set_pos(WorldGen.cell_center(cell) + Vector2(0.3, 0.0))
		state.players[my_id]["pos"] = _pos
		for i in 14:
			if state != null:
				state._last_strike.erase(my_id)
			request_prep.rpc_id(1, int(target["id"]), cell)
			await get_tree().create_timer(0.08).timeout
			if not (builds.get_build(int(target["id"]))["prep"] as Dictionary).has(cell):
				break


func _capital(text: String) -> String:
	return text.left(1).to_upper() + text.substr(1)


## "sudeste da obra" (ou "centro da obra"); pronta, "sudeste do abrigo".
func _sector_phrase(build: Dictionary, sector: String) -> String:
	if build["done"] or Builds.walls_up(build):
		return "%s d%s %s" % [sector, Crafting.BUILDS[build["kind"]]["article"], Crafting.build_name(build["kind"])]
	return "%s da obra" % sector


## Entrar no terreno de uma obra grande é anunciado, como entrar numa trilha:
## "Terreno do abrigo, obra em fase de limpeza" ou "Dentro do abrigo". Só ao
## entrar (ou ao passar de uma obra a outra), sem repetir a cada casa.
func _announce_site(old_cell: Vector2i, cell: Vector2i) -> void:
	var build := builds.at(cell)
	if build.is_empty() or not Crafting.is_large(build["kind"]):
		return
	var old_build := builds.at(old_cell) if old_cell != WorldGen.NO_CELL else {}
	var at_door := Builds.walls_up(build) and cell == Builds.door_cell(build["cell"], int(build["size"]), str(build["entrance"]))
	var old_door := not old_build.is_empty() and Builds.walls_up(old_build) \
			and old_cell == Builds.door_cell(old_build["cell"], int(old_build["size"]), str(old_build["entrance"]))
	var same_build: bool = not old_build.is_empty() and old_build["id"] == build["id"]
	var sector := Builds.sector_name(build, cell)
	# Dentro da mesma obra e zona, só fala ao passar de uma parte a outra.
	if same_build and old_door == at_door:
		if sector != Builds.sector_name(build, old_cell) and not at_door:
			Speech.say(_capital(_sector_phrase(build, sector)) + ".", false)
		return
	var id := int(build["id"])
	var name: String = Crafting.build_name(build["kind"])
	var article: String = Crafting.BUILDS[build["kind"]]["article"]
	if at_door:
		Speech.say("Porta d%s %s." % [article, name], false)
	elif build["done"] or Builds.walls_up(build):
		Speech.say("Dentro d%s %s, %s." % [article, name, sector], false)
	else:
		Speech.say("Terreno d%s %s, %s. %s." % [article, name, builds.spoken_name(id).trim_prefix(name + ", ").trim_prefix(name + " "), _capital(_sector_phrase(build, sector))], false)
