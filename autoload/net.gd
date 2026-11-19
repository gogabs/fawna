extends Node
## Configuração da conexão e criação do peer de rede.
##
## O mesmo projeto roda de três jeitos:
##   - SERVER: servidor dedicado, sem jogador local (ex.: godot --headless -- --server)
##   - HOST: alguém hospeda pelo próprio jogo; é servidor e jogador ao mesmo tempo
##   - CLIENT: entra num servidor (dedicado ou hospedado por alguém)
## Em todos os casos existe um único mundo compartilhado, sem salas.

enum Mode { NONE, SERVER, HOST, CLIENT }

const DEFAULT_PORT := 7350
## Servidor de testes do Gabs (rede da VPN).
const DEFAULT_ADDRESS := "26.127.36.156"
const SETTINGS_PATH := "user://config.cfg"
const MAX_PLAYERS := 128

var mode := Mode.NONE
var address := DEFAULT_ADDRESS
var port := DEFAULT_PORT
## Vazio até a pessoa escolher o nome em Opções: sem nome não dá para entrar.
var player_name := ""
## VSync desligado por padrão: com ele, o leitor de tela pode receber o foco
## com segundos de atraso (ver scenes/main.gd). Escolhido em Opções.
var vsync := false
## Navegação dos menus (flutuante, Caminheiro, pilhas, principal e opções).
## Horizontal (padrão): Esquerda/Direita navegam, Baixo volta, Cima confirma.
## Vertical: Cima/Baixo navegam, Esquerda volta, Direita confirma.
var vertical_nav := false
## Gráficos desligados: dentro do jogo, para de desenhar (a janela fica parada;
## som e fala continuam) e gasta bem menos processador. Escolhido em Opções.
var graphics_off := false
var world_seed := 0
var seed_from_cmdline := false
## Onde o servidor salva o mundo. --novo-mundo ignora o save existente.
var save_path := "user://mundo.json"
var new_world := false
## Só para testes e depuração (servidor): hora inicial do mundo (0 a 24, -1 = a salva)
## e duração do dia em segundos (0 = a normal). Ver DayCycle.
var day_hour := -1.0
var day_seconds := 0.0

## Comandos automáticos para testes (ex.: --auto=N,N,L,ARREDORES,SAIR).
var auto_commands: PackedStringArray = []

var _lan_announcer: LanDiscovery


func _ready() -> void:
	world_seed = randi()
	load_settings()
	apply_vsync()
	_parse_cmdline()


## Nome e opções escolhidos em Opções ficam salvos entre sessões.
func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	player_name = config.get_value("jogador", "nome", player_name)
	# "Criatura" era o nome padrão das versões antigas, gravado sem a pessoa escolher.
	if player_name == "Criatura":
		player_name = ""
	vsync = config.get_value("video", "vsync", vsync)
	graphics_off = config.get_value("video", "sem_graficos", graphics_off)
	vertical_nav = config.get_value("controles", "navegacao_vertical", vertical_nav)


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("jogador", "nome", player_name)
	config.set_value("video", "vsync", vsync)
	config.set_value("video", "sem_graficos", graphics_off)
	config.set_value("controles", "navegacao_vertical", vertical_nav)
	config.save(SETTINGS_PATH)


func apply_vsync() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)


## Só vale dentro do jogo (game.gd liga ao entrar e desfaz ao sair): os menus
## nativos precisam de quadros para o leitor de tela receber o foco.
func apply_graphics(in_game: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	RenderingServer.render_loop_enabled = not (graphics_off and in_game)


## Aceita "ip" ou "ip:porta".
func set_server(text: String) -> void:
	var clean := text.strip_edges()
	if clean.is_empty():
		clean = DEFAULT_ADDRESS
	if clean.contains(":"):
		port = int(clean.get_slice(":", 1))
		clean = clean.get_slice(":", 0)
	else:
		port = DEFAULT_PORT
	address = clean


func server_text() -> String:
	return address if port == DEFAULT_PORT else "%s:%d" % [address, port]


func is_server() -> bool:
	return mode == Mode.SERVER or mode == Mode.HOST


func has_local_player() -> bool:
	return mode == Mode.HOST or mode == Mode.CLIENT


## Cria o peer conforme o modo. Devolve OK ou um código de erro.
func start() -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err: Error
	if is_server():
		err = peer.create_server(port, MAX_PLAYERS)
	else:
		err = peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	if is_server():
		_announce_on_lan()
	return OK


## Quem hospeda responde, na rede local, a quem procura jogos privados.
func _announce_on_lan() -> void:
	if DisplayServer.get_name() == "headless" and mode != Mode.SERVER:
		return
	_lan_announcer = LanDiscovery.new()
	add_child(_lan_announcer)
	_lan_announcer.start_announcing()


func stop() -> void:
	if _lan_announcer != null:
		_lan_announcer.queue_free()
		_lan_announcer = null
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	mode = Mode.NONE


func _parse_cmdline() -> void:
	for arg in OS.get_cmdline_user_args():
		var key := arg
		var value := ""
		if arg.contains("="):
			key = arg.get_slice("=", 0)
			value = arg.substr(key.length() + 1)
		match key:
			"--server":
				mode = Mode.SERVER
			"--host":
				mode = Mode.HOST
			"--join":
				mode = Mode.CLIENT
				if not value.is_empty():
					address = value
			"--port":
				port = int(value)
			"--name":
				player_name = value
			"--seed":
				world_seed = int(value)
				seed_from_cmdline = true
			"--mundo":
				save_path = value
			"--novo-mundo":
				new_world = true
			"--hora":
				day_hour = float(value)
			"--dia":
				day_seconds = float(value)
			"--auto":
				auto_commands = value.split(",", false)
	# Linha de comando e testes não passam pelo menu, então não exigem nome.
	if mode != Mode.NONE and player_name.is_empty():
		player_name = "Criatura"
	# Sem tela, só faz sentido rodar como servidor dedicado ou em teste.
	if DisplayServer.get_name() == "headless" and mode == Mode.NONE:
		mode = Mode.SERVER
