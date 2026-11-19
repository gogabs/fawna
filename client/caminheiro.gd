class_name Caminheiro
extends Node
## O Caminheiro: um pequeno cristal que brilha azul na direção que o coração
## manda. Rastreia um lugar do mapa (por enquanto, só a Origem).
##
## A rota vem do Wayfinder, como uma fila de beacons (as curvas do caminho
## pelas trilhas, estradas e pontes). Enquanto está aceso:
##   - o beacon atual bate como um coração, um tambor bem abafado que vem da
##     direção dele, a 70 batidas por minuto;
##   - de frente para ele, cada pancada é precedida por uma "suga" (um ruído
##     escuro ao contrário, que sobe e some suave); fora de frente, a batida
##     fica mais baixa e abafada, e abre até o normal perto da frente;
##   - a direção do som é contínua: ela nunca pula. Aponta para um ponto da rota
##     um pouco à frente, e gira devagar até lá, como um carro fazendo a curva,
##     seja numa esquina da rota, ao trocar de beacon ou ao traçar de novo;
##   - no destino, o cristal se apaga.
## Se a criatura se afasta muito da rota, o caminho é traçado de novo.

signal beacon_reached(pos: Vector2)
signal arrived(place_name: String)
signal lost  # longe da rota e sem caminho de onde está: o cristal se apagou

const ARRIVE_RADIUS := 1.6  # casas (2,4 m): chegou ao beacon
const OFF_ROUTE_DISTANCE := 9.0  # casas longe da rota: traça de novo
const BEAT_DISTANCE := 1.0  # casas: a batida soa a 1,5 m (sem perder volume com a distância), na direção do beacon
const BEAT_INTERVAL := 60.0 / 70.0  # 70 batidas por minuto
const BEAT_DB := 2.0  # o arquivo já vem forte; mais que isso distorce
const BEAT_BEHIND_DB := -14.0  # bem atrás, a batida cai e fica abafada; abre até o normal conforme vira para a frente
const SUCK_DB := -12.0  # a suga, escura e baixinha, só de frente
## A batida começa isto depois da suga (a suga termina na primeira pancada);
## vale para todas as batidas, de frente ou não, para o ritmo não mudar ao virar.
const SUCK_LEAD := 0.15
## Abertura da batida: de frente (até FACING_TOLERANCE_DEG) é o timbre e o
## volume normais; daí até CLOSED_DEG, vai abafando e baixando; além, fica no
## mais abafado.
const CLOSED_DEG := 135.0
const BEAT_LEVELS := 4  # arquivos de batida do mais abafado ao normal
## Alarga o estéreo: o ângulo do som em relação ao rumo da criatura é
## ampliado até ~30% perto do centro (a rota em si não muda).
const STEREO_WIDEN := 0.15
## De frente: o beacon está a no máximo isto do rumo para onde a criatura
## olha. A criatura gira de 45 em 45 graus, então metade do giro (22,5°) é a
## menor tolerância que sempre deixa um rumo de frente: é o rumo certo dos 8.
const FACING_TOLERANCE_DEG := 22.5
## O som aponta para este ponto da rota, a tantas casas à frente da criatura
## (e não para o beacon em si), então as esquinas da rota são abertas em curva.
const LOOKAHEAD := 4.0
## Velocidade máxima de giro da direção do som, em graus por segundo.
const TURN_RATE_DEG := 40.0

var active := false
var place_name := ""

var _world: WorldGen
var _audio: SpatialAudio
var _finder: Wayfinder
var _beacon: Variant = null  # Vector2 do beacon atual
var _previous := Vector2.ZERO  # de onde a criatura saiu rumo ao beacon atual
var _beat_timer := 0.0
## Duas fontes para a batida, em rodízio: o reverb da batida (já no arquivo)
## dura mais que o intervalo, e reiniciar a mesma fonte cortaria a cauda.
var _beat_players: Array[AudioStreamPlayer3D] = []
var _next_beat := 0
## A suga, também em rodízio, na mesma posição da batida.
var _layer_players: Array[AudioStreamPlayer3D] = []
var _forward := Vector2.ZERO  # para onde a criatura olha (zero: não se sabe)
## Direção a seguir que o som indica agora (zero: ainda não definida). Só gira
## aos poucos, com no máximo TURN_RATE_DEG por segundo.
var _heading := Vector2.ZERO


## As duas fontes de som ficam criadas desde o começo e são reaproveitadas:
## o Steam Audio às vezes deixa mudas as fontes criadas na hora.
func setup(world: WorldGen, audio: SpatialAudio) -> void:
	_world = world
	_audio = audio
	_finder = Wayfinder.new(world)
	if audio != null:
		for i in 2:
			var player := audio.make_far_voice(BEAT_DISTANCE + 6.0)
			if player != null:
				player.name = "Caminheiro_batida_%d" % i
				player.stream = Sounds.heartbeat()
				_beat_players.append(player)
		var layer_stream := Sounds.heartbeat_suck()
		if layer_stream != null:
			for i in 2:
				var player := audio.make_far_voice(BEAT_DISTANCE + 6.0)
				if player != null:
					player.name = "Caminheiro_suga_%d" % i
					player.stream = layer_stream
					_layer_players.append(player)


## Acende o cristal rumo a um lugar. Devolve false se não achou caminho.
func start(from: Vector2, destination: Vector2, new_place_name: String) -> bool:
	if not _finder.plan(from, destination):
		stop()
		return false
	active = true
	place_name = new_place_name
	_previous = from
	_beacon = _finder.current()
	_beat_timer = 0.15
	_heading = Vector2.ZERO  # a primeira direção vem direto, sem girar de lugar nenhum
	return _beacon != null


func stop() -> void:
	active = false
	_beacon = null
	for player in _beat_players + _layer_players:
		player.stop()


## Distância aproximada até o destino, pelas trilhas, contada ao acender.
func estimated_length() -> float:
	return _finder.estimated_length


## O beacon atual e os próximos já traçados (para a tela e os testes).
func route() -> Array[Vector2]:
	return _finder.pending() if active else ([] as Array[Vector2])


func current_beacon() -> Variant:
	return _beacon


## Chamado a cada quadro com a posição da criatura e para onde ela olha
## (Compass.forward). Sem a direção, a batida soa sempre como de frente,
## sem a camada.
func update(pos: Vector2, delta: float, forward := Vector2.ZERO) -> void:
	_forward = forward
	if not active or _beacon == null:
		return
	_skip_ahead(pos)
	var beacon: Vector2 = _beacon
	if pos.distance_to(beacon) <= ARRIVE_RADIUS:
		_reach(pos)
		return
	if _off_route(pos):
		_replan(pos)
		return
	_steer(pos, delta)
	_follow_heading(pos)
	_beat_timer -= delta
	if _beat_timer <= 0.0:
		# Soma em vez de reiniciar: a sobra do quadro não se perde, então um
		# quadro longo não atrasa as batidas seguintes (70 bpm certinhos).
		_beat_timer = maxf(_beat_timer + BEAT_INTERVAL, BEAT_INTERVAL * 0.5)
		_beat(pos, beacon)


func _reach(pos: Vector2) -> void:
	var reached: Vector2 = _beacon
	_previous = reached
	beacon_reached.emit(reached)
	_beacon = _finder.next_beacon()
	if _beacon == null:
		var name_reached := place_name
		stop()
		arrived.emit(name_reached)
		return


## Se a criatura cortou caminho e já está num beacon mais adiante, pula para ele.
func _skip_ahead(pos: Vector2) -> void:
	var pending := _finder.pending()
	for i in range(1, mini(pending.size(), 5)):
		if pos.distance_to(pending[i]) <= ARRIVE_RADIUS:
			for j in i:
				_previous = _finder.current()
				_finder.next_beacon()
			_beacon = _finder.current()
			return


func _off_route(pos: Vector2) -> bool:
	var closest := Geometry2D.get_closest_point_to_segment(pos, _previous, _beacon)
	return pos.distance_to(closest) > OFF_ROUTE_DISTANCE


func _replan(pos: Vector2) -> void:
	var destination := _finder.destination
	if not _finder.plan(pos, destination):
		stop()
		lost.emit()
		return
	_previous = pos
	_beacon = _finder.current()
	_beat_timer = 0.3


## Gira _heading rumo ao ponto à frente na rota, com a velocidade limitada.
func _steer(pos: Vector2, delta: float) -> void:
	var target := (lookahead_point(pos, [_beacon] + _finder.pending().slice(1), LOOKAHEAD) - pos)
	if target.length() < 0.001:
		return
	_heading = steer_toward(_heading, target.normalized(), deg_to_rad(TURN_RATE_DEG) * delta)


## Para onde o som aponta, a "abertura" da batida e o estéreo ampliado, a
## partir da direção atual e de para onde a criatura olha.
func _sound_direction() -> Vector2:
	if _forward == Vector2.ZERO:
		return _heading
	return widen_direction(_forward, _heading)


func _openness() -> float:
	if _forward == Vector2.ZERO:
		return 1.0
	return openness_at(absf(rad_to_deg(_forward.angle_to(_heading))))


## A cada quadro, leva as fontes (e o volume da batida, que depende de para
## onde se olha) para a direção atual, sem esperar a próxima batida: o som
## acompanha a curva mesmo no meio da cauda.
func _follow_heading(pos: Vector2) -> void:
	if _heading == Vector2.ZERO:
		return
	var where := SpatialAudio.point_to_3d(pos + _sound_direction() * BEAT_DISTANCE)
	var volume := BEAT_DB + _gain() + (1.0 - _openness()) * BEAT_BEHIND_DB
	for player in _beat_players:
		player.position = where
		player.volume_db = volume
	for player in _layer_players:
		player.position = where


func _beat(pos: Vector2, beacon: Vector2) -> void:
	if _beat_players.is_empty():
		return
	if _heading == Vector2.ZERO:
		_heading = (beacon - pos).normalized()
	var index := _next_beat
	_next_beat = (_next_beat + 1) % _beat_players.size()
	var off := 0.0
	var openness := _openness()
	if _forward != Vector2.ZERO:
		off = absf(rad_to_deg(_forward.angle_to(_heading)))
	_follow_heading(pos)
	var player := _beat_players[index]
	player.stream = Sounds.heartbeat_level(roundi(openness * (BEAT_LEVELS - 1)))
	# A batida entra depois da suga.
	get_tree().create_timer(SUCK_LEAD).timeout.connect(func():
		if active:
			player.stop()
			player.play())
	if _forward != Vector2.ZERO and off <= FACING_TOLERANCE_DEG + 0.0001 and index < _layer_players.size():
		var layer := _layer_players[index]
		layer.volume_db = SUCK_DB + _gain()
		layer.stop()
		layer.play()


## Gira "current" rumo a "target" (ambos unitários) no máximo "max_angle"
## radianos. Sem direção atual (zero), vai direto.
static func steer_toward(current: Vector2, target: Vector2, max_angle: float) -> Vector2:
	if current == Vector2.ZERO:
		return target
	var angle := current.angle_to(target)
	return current.rotated(clampf(angle, -max_angle, max_angle)).normalized()


## O ponto da rota (pos -> points em ordem) a "distance" casas de caminho a
## partir de pos; se a rota acaba antes, o último ponto.
static func lookahead_point(pos: Vector2, points: Array, distance: float) -> Vector2:
	var from := pos
	var left := distance
	for point: Vector2 in points:
		var leg := from.distance_to(point)
		if leg >= left:
			return from.lerp(point, left / leg)
		left -= leg
		from = point
	return from


## Quão aberta soa a batida (0 = bem atrás, abafada; 1 = de frente, normal),
## para um desvio de "off" graus do rumo da criatura.
static func openness_at(off: float) -> float:
	var t := clampf((off - FACING_TOLERANCE_DEG) / (CLOSED_DEG - FACING_TOLERANCE_DEG), 0.0, 1.0)
	return 1.0 - t * t * (3.0 - 2.0 * t)


## Direção do som com o ângulo em relação a "forward" ampliado (mais estéreo):
## ângulo + STEREO_WIDEN * sen(2 * ângulo), que não muda a frente nem o atrás.
static func widen_direction(forward: Vector2, direction: Vector2) -> Vector2:
	var angle := forward.angle_to(direction)
	return forward.rotated(angle + STEREO_WIDEN * sin(2.0 * angle))


## A criatura, olhando para forward, está de frente para o beacon?
static func is_facing(pos: Vector2, beacon: Vector2, forward: Vector2) -> bool:
	if forward == Vector2.ZERO or pos.distance_to(beacon) < 0.001:
		return false
	var off := absf(forward.angle_to(beacon - pos))
	return off <= deg_to_rad(FACING_TOLERANCE_DEG) + 0.0001


func _gain() -> float:
	return SpatialAudio.HRTF_GAIN_DB if _audio != null and _audio.using_hrtf else 0.0
