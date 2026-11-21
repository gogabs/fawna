class_name Horrors
extends RefCounted
## Os horrores do mundo. A simulação roda só no servidor; os clientes só
## recebem onde cada um está e cuidam do som.
##
## Por enquanto há um só: o Calado. Ele não faz som, ele apaga o som. Só rola
## de noite (DayCycle.is_night): com a primeira luz do amanhecer ele recua e
## some, e de dia ninguém o atrai. Surge
## atrás de quem fica exposto em qualquer bioma (menos o mar), em trilha ou não, longe do fogo,
## e vem devagar pelas costas. Os pássaros fogem e se calam por onde ele
## passa. Quem vira de frente para ele o faz parar; encarado por um tempo,
## ele recua. Só a chama de uma fogueira acesa o espanta (um dia, a tocha); trilha e companhia não protegem.
## Quem ele alcança é levado ao ponto seguro mais próximo (fogueira acesa,
## povoado; sem nenhum por perto, o cruzamento de trilhas mais próximo) e perde o que carregava na bolsa de recursos; o
## equipamento fica. Armas não o afetam (as tochas virão depois).

enum Mode { STALK, HELD, RETREAT }

## Distâncias em casas, tempos em segundos.
const SPAWN_DISTANCE := 20.0  # nasce a essa distância, às costas do alvo
const STALK_SPEED := 1.1  # mais lento que a criatura (1,8): dá para se afastar andando
const RETREAT_SPEED := 2.6
const CATCH_RANGE := 1.2  # chegando a essa distância, ele alcançou
const SIGHT := 22.0  # até onde encarar o segura
## Encarar: o alvo olha para ele dentro deste ângulo. Os giros são de 45°,
## então 30° para cada lado garantem que sempre há uma direção que serve.
const FACING_COS := 0.866
const STARE_SECONDS := 6.0  # encarado por esse tempo (somado), ele recua
const TORCH_SAFE := 5.0  # tocha acesa na mão: espanta a até 7,5 m
const FIRE_SAFE := 8.0  # fogueira acesa a até 12 m do alvo (ou dele) o espanta
const GIVE_UP_DISTANCE := 45.0
const RESTALK_MAX := 70.0  # mais longe que isso (um salto), ele desiste de vez
const GONE_DISTANCE := 30.0  # recuando, some quando fica longe assim de todos
const RETREAT_MAX := 20.0  # ou depois desse tempo
const HEARING := 30.0  # até onde um jogador fica sabendo dele
## Quanto tempo exposto (sem fogueira acesa por perto, em qualquer bioma menos o mar) até
## ele aparecer, e o sossego depois de uma visita.
const EXPOSURE := [60.0, 150.0]
const COOLDOWN := [240.0, 480.0]
## Abafamento do mundo: começa a PRESENCE_FAR casas e é total a PRESENCE_NEAR.
const PRESENCE_FAR := 18.0
const PRESENCE_NEAR := 4.0
## Pássaros: a essa distância dele não cantam; mais perto, fogem.
## Luz do anel (só de noite, dentro da faixa): ele demora mais para aparecer,
## vem mais devagar e precisa chegar mais perto para alcançar. Nunca o impede.
const RING_APPEAR_SLOW := 0.5
const RING_SPEED_SLOW := 0.3
const RING_CATCH_SHRINK := 0.4
const HUSH_RADIUS := 16.0
const SCARE_RADIUS := 9.0

var world: WorldGen

## id -> { id, target, pos: Vector2, mode, stare, wait, retreat_s, watchers }
var horrors := {}

var _next_id := 1
var _last_ms := -1
var _exposure := {}  # peer -> segundos exposto
var _need := {}  # peer -> segundos de exposição até ele aparecer
var _rest_until := {}  # peer -> ms: antes disso ele não volta
var _rng := RandomNumberGenerator.new()
var _night := true  # do último passo
var _lights := {}  # peer -> 0 a 1: quanto a luz do anel pega o jogador
var _rate := 1.0  # ritmo da aparição, com a estação (ver DayCycle.calado_rate)


func _init(the_world: WorldGen) -> void:
	world = the_world
	_rng.seed = world.world_seed + 4099


## Passo da simulação. "players" é id -> { "pos": Vector2, "heading": int };
## "fires" são os pontos (Vector2, em casas) das fogueiras acesas.
## Devolve mensagens para os clientes: [peer, tipo, argumentos], com tipo
## "at" ([id, posição, modo]), "gone" ([id]) ou "caught" ([id]): este último
## só vai ao alvo, que foi alcançado (o Calado some e descansa).
func update(now_ms: int, players: Dictionary, fires: Array, night := true, lights := {}, rate := 1.0) -> Array:
	var out := []
	_night = night
	_lights = lights
	_rate = rate
	if not night:
		# Clareou: o que ainda caçava recua, como se a luz o espantasse.
		for horror in horrors.values():
			if horror["mode"] != Mode.RETREAT:
				horror["mode"] = Mode.RETREAT
	var delta := 0.0 if _last_ms < 0 else clampf((now_ms - _last_ms) / 1000.0, 0.0, 1.0)
	_last_ms = now_ms
	for id in horrors.keys():
		_update_horror(horrors[id], delta, now_ms, players, fires, out)
	for peer in players:
		_update_exposure(peer, delta, now_ms, players, fires)
	for peer in _exposure.keys():
		if not players.has(peer):
			forget_peer(peer)
	_sync_watchers(players, out)
	return out


## Um jogador saiu.
func forget_peer(peer: int) -> void:
	_exposure.erase(peer)
	_need.erase(peer)
	_rest_until.erase(peer)
	for horror in horrors.values():
		horror["watchers"].erase(peer)


## Onde estão os horrores agora, para os pássaros se calarem.
func points() -> Array:
	var found := []
	for horror in horrors.values():
		found.append(horror["pos"])
	return found


## O horror que persegue este jogador, ou {}.
func hunting(peer: int) -> Dictionary:
	for horror in horrors.values():
		if horror["target"] == peer:
			return horror
	return {}


## Uma das três direções de trás (traseira esquerda, trás, traseira direita),
## sorteada, para o jogador ter que procurar por ele.
func _rear_direction(heading: int) -> Vector2:
	return Compass.forward(heading + 4 + _rng.randi_range(-1, 1))


## Barulho feito por este jogador (batidas de pedra): soma "seconds" ao tempo
## exposto, então o Calado pode chegar mais cedo. Não vale durante o sossego
## depois de uma visita, nem com um já atrás dele.
func hear_noise(peer: int, seconds: float) -> void:
	if not _night or not hunting(peer).is_empty() or Time.get_ticks_msec() < int(_rest_until.get(peer, 0)):
		return
	if not _need.has(peer):
		_need[peer] = _rng.randf_range(EXPOSURE[0], EXPOSURE[1])
	_exposure[peer] = float(_exposure.get(peer, 0.0)) + seconds


## Faz o Calado aparecer atrás de um jogador (testes e, um dia, eventos).
## Devolve o id, ou -1 se o jogador não existe ou já tem um atrás de si.
func summon(peer: int, players: Dictionary, distance := SPAWN_DISTANCE) -> int:
	if not players.has(peer) or not hunting(peer).is_empty():
		return -1
	var player: Dictionary = players[peer]
	var behind := _rear_direction(int(player.get("heading", 0)))
	var horror := {
		"id": _next_id, "target": peer, "pos": (player["pos"] as Vector2) + behind * distance,
		"mode": Mode.STALK, "stare": 0.0, "wait": 0.0, "retreat_s": 0.0, "watchers": {},
	}
	_next_id += 1
	horrors[horror["id"]] = horror
	_exposure[peer] = 0.0
	_need.erase(peer)
	return horror["id"]


## Quanto o Calado pesa sobre o som a uma distância: 0 (longe) a 1 (ao lado).
static func presence_at(distance: float) -> float:
	var x := clampf((PRESENCE_FAR - distance) / (PRESENCE_FAR - PRESENCE_NEAR), 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


## O jogador está olhando para este ponto?
static func is_facing(player_pos: Vector2, heading: int, point: Vector2) -> bool:
	var offset := point - player_pos
	if offset.length() < 0.01:
		return true
	return Compass.forward(heading).dot(offset.normalized()) >= FACING_COS


## Há fogueira acesa a até FIRE_SAFE deste ponto?
## Cada item de "fires" é um Vector2 (fogueira, alcance FIRE_SAFE) ou um
## Vector3 (x, y, alcance: uma tocha acesa na mão de alguém).
static func fire_near(point: Vector2, fires: Array) -> bool:
	for fire in fires:
		var at: Vector2 = Vector2(fire.x, fire.y)
		var reach: float = float(fire.z) if fire is Vector3 else FIRE_SAFE
		if at.distance_to(point) <= reach:
			return true
	return false


## O ponto seguro mais próximo de "from": algum dos "shelters" (pontos, em
## casas, de fogueiras acesas e povoados) ou, quando não há nenhum mais perto
## que o cruzamento de trilhas da região de "from", esse cruzamento.
static func nearest_shelter(world: WorldGen, from: Vector2, shelters: Array) -> Vector2:
	var best := world.region_landmark(world.region_of(WorldGen.cell_of(from)))
	for point: Vector2 in shelters:
		if point.distance_to(from) < best.distance_to(from):
			best = point
	return best


## Onde o alvo reaparece: um ponto livre perto de "point", fora das casas em
## "blocked" (construções). Se não achar, o próprio ponto.
static func landing_spot(world: WorldGen, point: Vector2, blocked: Array) -> Vector2:
	for radius in [1.6, 2.4, 3.2]:
		for i in 8:
			var spot: Vector2 = point + Vector2.from_angle(PI * 0.5 + TAU * i / 8.0) * radius
			if world.is_free(spot) and not blocked.has(WorldGen.cell_of(spot)):
				return spot
	return point


# --- Comportamento -------------------------------------------------------------

func _update_horror(horror: Dictionary, delta: float, now_ms: int, players: Dictionary, fires: Array, out: Array) -> void:
	var pos: Vector2 = horror["pos"]
	if horror["mode"] == Mode.RETREAT:
		horror["retreat_s"] = float(horror["retreat_s"]) + delta
		var away := _away_from_players(pos, players)
		horror["pos"] = pos + away * RETREAT_SPEED * delta
		if float(horror["retreat_s"]) >= RETREAT_MAX or _nearest_player(horror["pos"], players) >= GONE_DISTANCE:
			_remove(horror, now_ms, out)
		return
	var peer: int = horror["target"]
	if not players.has(peer):
		_remove(horror, now_ms, out)
		return
	var target: Vector2 = players[peer]["pos"]
	var distance := pos.distance_to(target)
	if distance > GIVE_UP_DISTANCE:
		# Ele é mais lento que a criatura: quem anda sem parar o deixa para trás.
		# Se ela segue exposta, ele ressurge atrás dela, em vez de
		# sumir e só voltar depois do sossego. Só desiste de um salto muito
		# grande, ou se a criatura ficou a salvo (mar, fogueira).
		if distance <= RESTALK_MAX and _exposed(peer, players, fires):
			var behind := _rear_direction(int(players[peer].get("heading", 0)))
			horror["pos"] = target + behind * SPAWN_DISTANCE
			horror["stare"] = 0.0
			horror["mode"] = Mode.STALK
			return
		_remove(horror, now_ms, out)
		return
	if fire_near(target, fires) or fire_near(pos, fires):
		horror["mode"] = Mode.RETREAT
		return
	var watched := distance <= SIGHT and is_facing(target, int(players[peer].get("heading", 0)), pos)
	if watched:
		horror["stare"] = float(horror["stare"]) + delta
	if float(horror["stare"]) >= STARE_SECONDS:
		horror["mode"] = Mode.RETREAT
		return
	if watched:
		horror["mode"] = Mode.HELD
		return
	horror["mode"] = Mode.STALK
	var light := float(_lights.get(peer, 0.0))
	var step := minf(STALK_SPEED * (1.0 - RING_SPEED_SLOW * light) * delta, distance)
	horror["pos"] = pos + (target - pos).normalized() * step
	if (horror["pos"] as Vector2).distance_to(target) <= CATCH_RANGE * (1.0 - RING_CATCH_SHRINK * light):
		out.append([peer, "caught", [horror["id"]]])
		_remove(horror, now_ms, out)


func _remove(horror: Dictionary, now_ms: int, out: Array) -> void:
	for peer in horror["watchers"]:
		out.append([peer, "gone", [horror["id"]]])
	var peer: int = horror["target"]
	_rest_until[peer] = now_ms + int(_rng.randf_range(COOLDOWN[0], COOLDOWN[1]) * 1000.0)
	_exposure[peer] = 0.0
	horrors.erase(horror["id"])


## Conta o tempo que cada jogador passa exposto e faz o Calado aparecer.
func _update_exposure(peer: int, delta: float, now_ms: int, players: Dictionary, fires: Array) -> void:
	if not hunting(peer).is_empty():
		return
	if not _night or not _exposed(peer, players, fires) or now_ms < int(_rest_until.get(peer, 0)):
		_exposure[peer] = maxf(float(_exposure.get(peer, 0.0)) - delta * 2.0, 0.0)
		return
	if not _need.has(peer):
		_need[peer] = _rng.randf_range(EXPOSURE[0], EXPOSURE[1])
	_exposure[peer] = float(_exposure.get(peer, 0.0)) + delta * _rate * (1.0 - RING_APPEAR_SLOW * float(_lights.get(peer, 0.0)))
	if float(_exposure[peer]) >= float(_need[peer]):
		summon(peer, players)


func _exposed(peer: int, players: Dictionary, fires: Array) -> bool:
	var pos: Vector2 = players[peer]["pos"]
	var cell := WorldGen.cell_of(pos)
	if world.biome_at(cell) == WorldGen.Biome.MAR:
		return false
	return not fire_near(pos, fires)


func _nearest_player(point: Vector2, players: Dictionary) -> float:
	var best := INF
	for peer in players:
		best = minf(best, (players[peer]["pos"] as Vector2).distance_to(point))
	return best


## Direção para longe de quem estiver mais perto.
func _away_from_players(point: Vector2, players: Dictionary) -> Vector2:
	var nearest := Vector2.INF
	for peer in players:
		var pos: Vector2 = players[peer]["pos"]
		if nearest == Vector2.INF or pos.distance_to(point) < nearest.distance_to(point):
			nearest = pos
	if nearest == Vector2.INF or nearest.distance_to(point) < 0.01:
		return Vector2.UP
	return (point - nearest).normalized()


## Manda a posição a quem está ao alcance e avisa quem saiu dele.
func _sync_watchers(players: Dictionary, out: Array) -> void:
	for horror in horrors.values():
		var pos: Vector2 = horror["pos"]
		var watchers: Dictionary = horror["watchers"]
		for peer in watchers.keys():
			if not players.has(peer) or (players[peer]["pos"] as Vector2).distance_to(pos) > HEARING + 4.0:
				watchers.erase(peer)
				if players.has(peer):
					out.append([peer, "gone", [horror["id"]]])
		for peer in players:
			if not watchers.has(peer) and (players[peer]["pos"] as Vector2).distance_to(pos) > HEARING:
				continue
			watchers[peer] = true
			out.append([peer, "at", [horror["id"], pos, horror["mode"]]])
