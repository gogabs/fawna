class_name Caminheiro
extends Node
## O Caminheiro: um pequeno cristal que brilha azul na direção que o coração
## manda. Rastreia um lugar do mapa (por enquanto, só a vila).
##
## A rota vem do Wayfinder, como uma fila de beacons (as curvas do caminho
## pelas trilhas, estradas e pontes). Enquanto está aceso:
##   - o beacon atual bate como um coração, um tambor bem abafado que vem da
##     direção dele, a 70 batidas por minuto;
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
	for player in _beat_players:
		player.stop()


## Distância aproximada até o destino, pelas trilhas, contada ao acender.
func estimated_length() -> float:
	return _finder.estimated_length


## O beacon atual e os próximos já traçados (para a tela e os testes).
func route() -> Array[Vector2]:
	return _finder.pending() if active else ([] as Array[Vector2])


func current_beacon() -> Variant:
	return _beacon


## Chamado a cada quadro com a posição da criatura.
func update(pos: Vector2, delta: float) -> void:
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
	var player := _beat_players[_next_beat]
	_next_beat = (_next_beat + 1) % _beat_players.size()
	var direction := (beacon - pos).normalized()
	player.position = SpatialAudio.point_to_3d(pos + direction * BEAT_DISTANCE)
	player.volume_db = BEAT_DB + _gain()
	player.stop()
	player.play()


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
