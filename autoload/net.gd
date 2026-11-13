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
var player_name := "Criatura"
var world_seed := 0
var seed_from_cmdline := false
## Onde o servidor salva o mundo. --novo-mundo ignora o save existente.
var save_path := "user://mundo.json"
var new_world := false

## Comandos automáticos para testes (ex.: --auto=N,N,L,ARREDORES,SAIR).
## Com eles, os minigames terminam sozinhos com sucesso.
var auto_commands: PackedStringArray = []


func _ready() -> void:
	world_seed = randi()
	load_settings()
	_parse_cmdline()


## Nome e servidor escolhidos em Opções ficam salvos entre sessões.
func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	player_name = config.get_value("jogador", "nome", player_name)
	var server: String = config.get_value("conexao", "servidor", "")
	if not server.is_empty():
		set_server(server)


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("jogador", "nome", player_name)
	config.set_value("conexao", "servidor", server_text())
	config.save(SETTINGS_PATH)


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
	return OK


func stop() -> void:
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
			"--auto":
				auto_commands = value.split(",", false)
	# Sem tela, só faz sentido rodar como servidor dedicado ou em teste.
	if DisplayServer.get_name() == "headless" and mode == Mode.NONE:
		mode = Mode.SERVER
