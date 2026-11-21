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
## Senha do personagem, escolhida em Opções e guardada neste PC. O servidor
## registra a senha na primeira vez que o nome entra; depois só entra quem
## souber.
var password := ""
## Aviso para o menu principal mostrar numa caixa (por que a pessoa voltou
## para o menu). Vazio = nada a avisar. Quem mostra o limpa.
var menu_notice := ""
## Segundos sem entrar no mundo até desistir de conectar.
const CONNECT_TIMEOUT := 30.0
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
## Opções do 3D (ver WorldView3D): sombras, suavização de bordas (0 = desligada,
## 2 ou 4 amostras) e brilho nas luzes. Os padrões são o preset "Mais desempenho".
var shadows := false
var msaa := 0
var glow := false
const PRESET_NAMES := ["Desativados", "Mais desempenho", "Melhores gráficos"]
## Depuração (menu "Depuração", ver DebugTools): ligada com --debug num
## servidor de testes. Num jogo hospedado pelo menu ela vale só para quem hospeda.
var debug := false
var world_seed := 0
var seed_from_cmdline := false
## Onde o servidor salva o mundo. --novo-mundo ignora o save existente.
var save_path := "user://mundo.json"
var new_world := false
## Só para testes e depuração (servidor): hora inicial do mundo (0 a 24, -1 = a salva)
## e duração do dia em segundos (0 = a normal). Ver DayCycle.
var day_hour := -1.0
var day_seconds := 0.0
## Só para testes (servidor): dia do mundo em que começar (-1 = o salvo); decide em que
## estação está e onde passa a faixa do anel.
var day_start := -1

## Comandos automáticos para testes (ex.: --auto=N,N,L,ARREDORES,SAIR).
var auto_commands: PackedStringArray = []

var _lan_announcer: LanDiscovery


func _ready() -> void:
	world_seed = randi()
	load_settings()
	apply_vsync()
	apply_fps_limit(false)
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
	password = config.get_value("jogador", "senha", password)
	vsync = config.get_value("video", "vsync", vsync)
	graphics_off = config.get_value("video", "sem_graficos", graphics_off)
	shadows = config.get_value("video", "sombras", shadows)
	msaa = config.get_value("video", "antisserrilhamento", msaa)
	glow = config.get_value("video", "brilho", glow)
	vertical_nav = config.get_value("controles", "navegacao_vertical", vertical_nav)


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("jogador", "nome", player_name)
	config.set_value("jogador", "senha", password)
	config.set_value("video", "vsync", vsync)
	config.set_value("video", "sem_graficos", graphics_off)
	config.set_value("video", "sombras", shadows)
	config.set_value("video", "antisserrilhamento", msaa)
	config.set_value("video", "brilho", glow)
	config.set_value("controles", "navegacao_vertical", vertical_nav)
	config.save(SETTINGS_PATH)


## O preset que as opções de vídeo formam (0 Desativados, 1 Mais desempenho,
## 2 Melhores gráficos) ou -1 se foram mexidas uma a uma (Personalizado).
func graphics_preset() -> int:
	if graphics_off:
		return 0
	if not shadows and msaa == 0 and not glow:
		return 1
	if shadows and msaa == 2 and glow:
		return 2
	return -1


func set_graphics_preset(preset: int) -> void:
	graphics_off = preset == 0
	shadows = preset == 2
	msaa = 2 if preset == 2 else 0
	glow = preset == 2


func graphics_preset_name() -> String:
	var preset := graphics_preset()
	return PRESET_NAMES[preset] if preset >= 0 else "Personalizado"


func apply_vsync() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)


## Teto de quadros por segundo, aplicado por código (além do project.godot, que
## já pede 60): o 3D sem teto esquentava o computador de quem joga. Sem
## gráficos dentro do jogo não há nada para ver, então o teto cai.
const FPS_LIMIT := 60
const FPS_LIMIT_NO_GRAPHICS := 20


func apply_fps_limit(in_game: bool) -> void:
	_fps_target = FPS_LIMIT_NO_GRAPHICS if (graphics_off and in_game) else FPS_LIMIT
	# Depuração: --fps-teto=N troca o teto (0 = sem teto) e --sem-limitador
	# desliga o limitador manual, para comparar o que segura melhor o FPS.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--fps-teto="):
			_fps_target = int(arg.get_slice("=", 1))
	# No Godot 4.7 atribuir o valor que já está (o 60 do project.godot) não liga
	# o teto: é preciso passar por 0 antes (medido no PC do Gabs: 60 sozinho
	# dava 1.700 FPS; 0 e depois 60 dá 60).
	Engine.max_fps = 0
	Engine.max_fps = _fps_target


## Limitador manual: no Windows do Gabs o teto do motor (Engine.max_fps) não
## segurou (790 FPS no menu), então, se o quadro acabou antes da hora, dorme o
## resto. Se o motor já segura, o quadro já dura o suficiente e isto não faz
## nada. O servidor sem tela fica de fora.
var _last_frame_usec := 0
var _fps_target := FPS_LIMIT


func _process(_delta: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if _fps_target <= 0 or "--sem-limitador" in OS.get_cmdline_user_args():
		return
	var target := int(1000000.0 / _fps_target)
	var spent := Time.get_ticks_usec() - _last_frame_usec
	# Só age quando o quadro foi bem mais curto que o teto (o teto do motor
	# não está segurando). Dormir por diferenças pequenas atrapalhava o teto
	# do motor e, no Windows, dava quadros de 23 ms (43 FPS) em vez de 16.
	if spent < target * 0.85:
		OS.delay_usec(target - spent)
	_last_frame_usec = Time.get_ticks_usec()


## Só vale dentro do jogo (game.gd liga ao entrar e desfaz ao sair): os menus
## nativos precisam de quadros para o leitor de tela receber o foco.
func apply_graphics(in_game: bool) -> void:
	apply_fps_limit(in_game)
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


## O servidor aceita pedidos de depuração? (Só o servidor pergunta.)
func debug_available() -> bool:
	return is_server() and (debug or mode == Mode.HOST)


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
			"--debug":
				debug = true
			"--port":
				port = int(value)
			"--name":
				player_name = value
			"--senha":
				password = value
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
			"--dia-inicial":
				day_start = int(value)
			"--auto":
				auto_commands = value.split(",", false)
	# Linha de comando e testes não passam pelo menu, então não exigem nome.
	if mode != Mode.NONE and player_name.is_empty():
		player_name = "Criatura"
	if mode != Mode.NONE and password.is_empty():
		password = "teste"
	# Sem tela, só faz sentido rodar como servidor dedicado ou em teste.
	if DisplayServer.get_name() == "headless" and mode == Mode.NONE:
		mode = Mode.SERVER
