class_name LanDiscovery
extends Node
## Descoberta de jogos na rede local, por broadcast UDP.
##
## Quem hospeda (ou roda um servidor dedicado) cria um LanDiscovery em modo
## anunciante: ele escuta na porta DISCOVERY_PORT e responde a quem perguntar.
## Quem procura cria um em modo busca: manda a pergunta por broadcast (e
## também para o endereço de difusão de cada rede do computador) e avisa, pelo
## sinal found, de cada resposta que chegar.
##
## Mensagens (texto):
##   pergunta: "FAWNA?"
##   resposta: "FAWNA!|versão|porta do jogo|nome de quem hospeda"

signal found(address: String, port: int, host_name: String, version: String)

const DISCOVERY_PORT := 7355
const QUERY := "FAWNA?"
const REPLY := "FAWNA!"
const QUERY_INTERVAL := 1.0

var _udp := PacketPeerUDP.new()
var _announcing := false
var _timer := 0.0
var _seen := {}


## Passa a responder às perguntas dos vizinhos. Devolve false se a porta está ocupada.
func start_announcing() -> bool:
	_announcing = true
	_udp.set_broadcast_enabled(true)
	var err := _udp.bind(DISCOVERY_PORT, "*")
	if err != OK:
		push_warning("LanDiscovery: porta %d indisponível (erro %d)" % [DISCOVERY_PORT, err])
		_announcing = false
		return false
	return true


## Começa a procurar. Já manda a primeira pergunta e repete a cada segundo.
func start_searching() -> void:
	_announcing = false
	_seen.clear()
	_udp.set_broadcast_enabled(true)
	_timer = QUERY_INTERVAL
	_send_query()


func stop() -> void:
	_udp.close()
	_seen.clear()


func _exit_tree() -> void:
	_udp.close()


func _process(delta: float) -> void:
	if not _udp.is_bound() and _announcing:
		return
	if not _announcing:
		_timer -= delta
		if _timer <= 0.0:
			_timer = QUERY_INTERVAL
			_send_query()
	while _udp.get_available_packet_count() > 0:
		var text := _udp.get_packet().get_string_from_utf8()
		var ip := _udp.get_packet_ip()
		var port := _udp.get_packet_port()
		if _announcing:
			if text == QUERY:
				_udp.set_dest_address(ip, port)
				_udp.put_packet(_reply_text().to_utf8_buffer())
		else:
			_handle_reply(text, ip)


func _reply_text() -> String:
	var who := Net.player_name if Net.mode == Net.Mode.HOST else "Servidor"
	return "%s|%s|%d|%s" % [REPLY, Updater.current_version(), Net.port, who.replace("|", " ")]


func _handle_reply(text: String, ip: String) -> void:
	var parts := text.split("|")
	if parts.size() < 4 or parts[0] != REPLY:
		return
	var port := int(parts[2])
	var key := "%s:%d" % [ip, port]
	if _seen.has(key):
		return
	_seen[key] = true
	found.emit(ip, port, parts[3], parts[1])


func _send_query() -> void:
	var data := QUERY.to_utf8_buffer()
	for target in broadcast_targets():
		_udp.set_dest_address(target, DISCOVERY_PORT)
		_udp.put_packet(data)


## Difusão geral, mais a difusão de cada rede /24 do computador (o
## 255.255.255.255 sozinho às vezes só sai por uma das placas de rede).
static func broadcast_targets() -> PackedStringArray:
	var targets := PackedStringArray(["255.255.255.255"])
	for address in IP.get_local_addresses():
		var p := address.split(".")
		if p.size() != 4 or address.begins_with("127.") or address.begins_with("169.254."):
			continue
		var target := "%s.%s.%s.255" % [p[0], p[1], p[2]]
		if not targets.has(target):
			targets.append(target)
	return targets
