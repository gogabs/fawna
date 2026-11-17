class_name Caminheiro
extends Node
## O Caminheiro: um pequeno cristal que brilha azul na direção que o coração
## manda. Rastreia um lugar do mapa (por enquanto, só a Origem).
##
## A rota vem do Wayfinder, como uma fila de beacons (as curvas do caminho
## pelas trilhas, estradas e pontes). Enquanto está aceso:
##   - o beacon atual bate como um coração, um tambor bem abafado que vem da
##     direção dele, a 70 batidas por minuto;
##   - de frente para ele, a batida ganha uma camada de brilho de cristal por
##     cima; fora de frente, a batida soa um pouco mais baixa;
##   - ao chegar num beacon, um woosh sai de perto da criatura e voa na
##     direção do próximo, e as batidas recomeçam de lá;
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
const BEAT_BEHIND_DB := -7.0  # bem atrás, a batida cai e fica abafada; abre até o normal conforme vira para a frente
const LAYER_DB := -17.0  # camada de cristal, bem baixinha: só uma cor por cima da batida, de frente
const LAYER_FADE_DB := -9.0  # a camada entra mais baixa na borda da zona de frente
const LAYER_ZONE_DEG := 45.0  # a camada começa a surgir a partir daqui e chega ao volume cheio em FACING_TOLERANCE_DEG
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
const WOOSH_DB := -8.0
const WOOSH_FROM := 0.6  # casas à frente da criatura, rumo ao próximo beacon
const WOOSH_TO := 7.0
const WOOSH_SECONDS := 0.75
const PAUSE_AFTER_WOOSH := 0.45  # silêncio antes da primeira batida do novo beacon

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
## A camada de cristal, também em rodízio, na mesma posição da batida.
var _layer_players: Array[AudioStreamPlayer3D] = []
var _forward := Vector2.ZERO  # para onde a criatura olha (zero: não se sabe)
var _woosh_player: AudioStreamPlayer3D
var _woosh_tween: Tween


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
		var layer_stream := Sounds.heartbeat_layer()
		if layer_stream != null:
			for i in 2:
				var player := audio.make_far_voice(BEAT_DISTANCE + 6.0)
				if player != null:
					player.name = "Caminheiro_camada_%d" % i
					player.stream = layer_stream
					_layer_players.append(player)
		_woosh_player = audio.make_far_voice(WOOSH_TO + 6.0)
		if _woosh_player != null:
			_woosh_player.name = "Caminheiro_woosh"
			_woosh_player.stream = Sounds.woosh()


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
	_woosh(pos, _beacon)
	_beat_timer = WOOSH_SECONDS + PAUSE_AFTER_WOOSH


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


func _beat(pos: Vector2, beacon: Vector2) -> void:
	if _beat_players.is_empty():
		return
	var index := _next_beat
	_next_beat = (_next_beat + 1) % _beat_players.size()
	var direction := (beacon - pos).normalized()
	var openness := 1.0
	var off := 0.0
	if _forward != Vector2.ZERO:
		off = absf(rad_to_deg(_forward.angle_to(direction)))
		openness = openness_at(off)
		direction = widen_direction(_forward, direction)
	var where := SpatialAudio.point_to_3d(pos + direction * BEAT_DISTANCE)
	var player := _beat_players[index]
	player.position = where
	player.stream = Sounds.heartbeat_level(roundi(openness * (BEAT_LEVELS - 1)))
	player.volume_db = BEAT_DB + _gain() + (1.0 - openness) * BEAT_BEHIND_DB
	player.stop()
	player.play()
	if _forward != Vector2.ZERO and off <= LAYER_ZONE_DEG and index < _layer_players.size():
		var layer := _layer_players[index]
		layer.position = where
		var near := 1.0 - clampf((off - FACING_TOLERANCE_DEG) / (LAYER_ZONE_DEG - FACING_TOLERANCE_DEG), 0.0, 1.0)
		layer.volume_db = LAYER_DB + _gain() + (1.0 - near) * LAYER_FADE_DB
		layer.stop()
		layer.play()


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


## O woosh sai de perto da criatura e voa rumo ao próximo beacon.
func _woosh(pos: Vector2, next: Vector2) -> void:
	if _woosh_player == null:
		return
	var direction := (next - pos).normalized()
	if _woosh_tween != null:
		_woosh_tween.kill()
	_woosh_player.position = SpatialAudio.point_to_3d(pos + direction * WOOSH_FROM)
	_woosh_player.volume_db = WOOSH_DB + _gain()
	_woosh_player.stop()
	_woosh_player.play()
	_woosh_tween = create_tween()
	_woosh_tween.tween_property(_woosh_player, "position", SpatialAudio.point_to_3d(pos + direction * WOOSH_TO), WOOSH_SECONDS) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)


func _gain() -> float:
	return SpatialAudio.HRTF_GAIN_DB if _audio != null and _audio.using_hrtf else 0.0
