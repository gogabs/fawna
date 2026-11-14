class_name Aviary
extends RefCounted
## Os pássaros do mundo. A simulação roda só no servidor; os clientes só
## recebem os acontecimentos (apareceu, cantou, voou, sumiu) e tocam os sons.
##
## Cada pássaro é uma entidade com posição própria. Eles vivem em grupos: um
## sabiá sozinho é um grupo de um, um casal de rolinhas é um grupo de dois e
## um bando de carriças é um grupo de quatro a sete. O grupo decide quando
## trocar de poleiro (e voa junto); cada pássaro canta por conta própria,
## só quando está pousado.
##
## Os pássaros só existem perto de alguém: ao chegar num pedaço do mundo, ele
## ganha os seus (sempre os mesmos para a mesma semente), e quando ninguém
## está por perto eles somem. Chegar perto demais assusta: o pássaro (ou o
## bando inteiro) foge para um poleiro longe de quem chegou.

enum Species { SABIA, CARRICA, ROLINHA }

## Dados de cada espécie. Distâncias em casas, tempos em segundos, alturas
## em metros.
const SPECIES := {
	Species.SABIA: {
		"name": "sabiá-da-névoa",
		"perches": [WorldGen.Thing.ARVORE],
		"group": [1, 1],
		"song_every": [7.0, 18.0],  # entre um canto e outro
		"stay": [25.0, 70.0],  # tempo num poleiro antes de mudar
		"speed": 5.0,  # casas por segundo
		"height": [3.5, 5.5],
		"flee": 2.0,  # chega a essa distância e ele foge
		"hop": [5.0, 13.0],  # distância de um voo normal
		"songs": 4,
	},
	Species.CARRICA: {
		"name": "carriça-do-cardo",
		"perches": [WorldGen.Thing.ARBUSTO, WorldGen.Thing.ARVORE],
		"group": [4, 7],
		"song_every": [4.0, 12.0],
		"stay": [14.0, 40.0],
		"speed": 7.0,
		"height": [0.6, 1.3],
		"flee": 2.6,
		"hop": [4.0, 11.0],
		"songs": 4,
	},
	Species.ROLINHA: {
		"name": "rolinha-do-junco",
		"perches": [WorldGen.Thing.ARVORE, WorldGen.Thing.ARBUSTO],
		"group": [1, 2],
		"song_every": [10.0, 26.0],
		"stay": [40.0, 100.0],
		"speed": 4.5,
		"height": [2.5, 4.0],
		"flee": 2.2,
		"hop": [5.0, 12.0],
		"songs": 3,
	},
}

## O que nasce em cada pedaço (CHUNK casas) de cada bioma: [espécie, chance
## de ter um grupo, quantos grupos no máximo].
const SPAWNS := {
	WorldGen.Biome.BOSQUE: [[Species.SABIA, 0.55, 1], [Species.CARRICA, 0.15, 1]],
	WorldGen.Biome.PRADARIA: [[Species.CARRICA, 0.4, 1], [Species.SABIA, 0.1, 1]],
	WorldGen.Biome.LAGOA: [[Species.ROLINHA, 0.7, 1], [Species.CARRICA, 0.25, 1]],
}

const CHUNK := WorldGen.CHUNK
const ACTIVE_CHUNKS := 2  # pedaços em volta de alguém que têm pássaros
const KEEP_CHUNKS := 3  # longe disso de todo mundo, os pássaros somem
const HOME_RADIUS := 13.0  # um grupo não se afasta mais que isso de casa
const HEARING := 32.0  # casas: até onde um jogador fica sabendo de um pássaro
const SYNC_INTERVAL_MS := 500
const STAGGER := 0.5  # segundos: os membros de um bando não saem todos juntos
const SPREAD := 2.5  # casas: os membros pousam perto do alvo do bando
const PER_PERCH := 3  # quantos membros de um bando cabem num arbusto

var world: WorldGen

## id -> pássaro: { id, group, species, pitch, songs, pos, height, cell,
## flying, from, to, from_h, to_h, start_ms, end_ms, next_song_ms,
## watchers: { peer: true } }
var birds := {}
## id -> grupo: { id, species, chunk, home, members, leave_ms }
var groups := {}

var _chunks := {}  # pedaço -> [ids de grupo]
var _next_id := 1
var _last_sync_ms := -SYNC_INTERVAL_MS
var _rng := RandomNumberGenerator.new()


func _init(the_world: WorldGen) -> void:
	world = the_world
	_rng.seed = world.world_seed + 31337


## Passo da simulação. "players" é id -> posição (Vector2, em casas).
## Devolve a lista de mensagens para os clientes: [peer, tipo, argumentos],
## com tipo "appear", "gone", "sing" ou "fly".
func update(now_ms: int, players: Dictionary) -> Array:
	var out := []
	_update_chunks(players, out)
	var near := _players_by_chunk(players)
	for group_id in groups.keys():
		_update_group(groups[group_id], now_ms, near, out)
	if now_ms - _last_sync_ms >= SYNC_INTERVAL_MS:
		_last_sync_ms = now_ms
		_sync_watchers(now_ms, players, out)
	return out


## Um jogador saiu: esquece que ele sabia destes pássaros.
func forget_peer(peer: int) -> void:
	for bird in birds.values():
		bird["watchers"].erase(peer)


## Onde o pássaro está agora (em casas), voando ou pousado.
func position_of(bird: Dictionary, now_ms: int) -> Vector2:
	if not bird["flying"]:
		return bird["pos"]
	return (bird["from"] as Vector2).lerp(bird["to"], _progress(bird, now_ms))


## Ponto do mundo em 3D (metros), como o áudio espacial usa.
static func to_3d(point: Vector2, height: float) -> Vector3:
	return Vector3(point.x * WorldGen.METERS_PER_CELL, height, point.y * WorldGen.METERS_PER_CELL)


static func species_name(species: int) -> String:
	return SPECIES[species]["name"]


# --- Pedaços com pássaros ------------------------------------------------------

func _update_chunks(players: Dictionary, out: Array) -> void:
	var wanted := {}
	var keep := {}
	for id in players:
		var here := _chunk_of(players[id])
		for dy in range(-KEEP_CHUNKS, KEEP_CHUNKS + 1):
			for dx in range(-KEEP_CHUNKS, KEEP_CHUNKS + 1):
				var chunk := here + Vector2i(dx, dy)
				keep[chunk] = true
				if absi(dx) <= ACTIVE_CHUNKS and absi(dy) <= ACTIVE_CHUNKS:
					wanted[chunk] = true
	for chunk in _chunks.keys():
		if not keep.has(chunk):
			for group_id in _chunks[chunk]:
				_remove_group(group_id, out)
			_chunks.erase(chunk)
	for chunk in wanted:
		if not _chunks.has(chunk):
			_chunks[chunk] = _spawn_chunk(chunk)


## Cria os grupos de um pedaço. Usa um sorteio fixo por pedaço, para quem
## volta ao mesmo lugar encontrar os mesmos pássaros.
func _spawn_chunk(chunk: Vector2i) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world.world_seed, chunk.x, chunk.y, "passaros"])
	var origin := chunk * CHUNK
	var middle := WorldGen.cell_center(origin + Vector2i.ONE * (CHUNK / 2))
	var biome := world.biome_at(WorldGen.cell_of(middle))
	var created := []
	for entry in SPAWNS.get(biome, []):
		var species: int = entry[0]
		for n in int(entry[2]):
			if rng.randf() >= float(entry[1]):
				continue
			var perches := _perches_in_chunk(origin, species)
			if perches.is_empty():
				break
			var home: Vector2i = perches[rng.randi() % perches.size()]
			var group_id := _spawn_group(species, chunk, home, rng)
			if group_id >= 0:
				created.append(group_id)
	return created


func _spawn_group(species: int, chunk: Vector2i, home: Vector2i, rng: RandomNumberGenerator) -> int:
	var data: Dictionary = SPECIES[species]
	var size := rng.randi_range(data["group"][0], data["group"][1])
	var home_point := WorldGen.cell_center(home)
	var spots := _member_spots(species, home_point, size, rng)
	if spots.is_empty():
		return -1
	var group := {
		"id": _next_id, "species": species, "chunk": chunk, "home": home_point,
		"members": [], "leave_ms": 0,
	}
	_next_id += 1
	for i in size:
		var spot: Array = spots[i % spots.size()]
		var bird := {
			"id": _next_id, "group": group["id"], "species": species,
			# Cada indivíduo tem a voz um pouco mais grave ou aguda, e os
			# seus cantos preferidos.
			"pitch": rng.randf_range(0.92, 1.08),
			"songs": _favorite_songs(species, rng),
			"pos": spot[0], "height": spot[1], "cell": spot[2],
			"flying": false, "from": spot[0], "to": spot[0], "from_h": spot[1], "to_h": spot[1],
			"start_ms": 0, "end_ms": 0,
			"next_song_ms": -1,  # sorteado no primeiro passo
			"watchers": {},
		}
		_next_id += 1
		birds[bird["id"]] = bird
		group["members"].append(bird["id"])
	group["leave_ms"] = -1
	groups[group["id"]] = group
	return group["id"]


func _remove_group(group_id: int, out: Array) -> void:
	if not groups.has(group_id):
		return
	for bird_id in groups[group_id]["members"]:
		var bird: Dictionary = birds[bird_id]
		for peer in bird["watchers"]:
			out.append([peer, "gone", [bird_id]])
		birds.erase(bird_id)
	groups.erase(group_id)


# --- Comportamento -------------------------------------------------------------

func _update_group(group: Dictionary, now_ms: int, near: Dictionary, out: Array) -> void:
	var data: Dictionary = SPECIES[group["species"]]
	if int(group["leave_ms"]) < 0:
		group["leave_ms"] = now_ms + _seconds(data["stay"], 0.3)
	var all_landed := true
	var threat := Vector2.INF
	for bird_id in group["members"]:
		var bird: Dictionary = birds[bird_id]
		if bird["flying"]:
			if now_ms >= int(bird["end_ms"]):
				_land(bird)
			else:
				all_landed = false
				continue
		if threat == Vector2.INF:
			threat = _threat_near(bird["pos"], float(data["flee"]), near)
		if int(bird["next_song_ms"]) < 0:
			bird["next_song_ms"] = now_ms + _seconds(data["song_every"], 0.0, 0.2)
		elif now_ms >= int(bird["next_song_ms"]):
			bird["next_song_ms"] = now_ms + _seconds(data["song_every"])
			var song: int = bird["songs"][_rng.randi() % bird["songs"].size()]
			for peer in bird["watchers"]:
				out.append([peer, "sing", [bird_id, song]])
	if not all_landed:
		return
	if threat != Vector2.INF:
		_move_group(group, now_ms, threat, out)
	elif now_ms >= int(group["leave_ms"]):
		_move_group(group, now_ms, Vector2.INF, out)


## Leva o grupo para outro poleiro. Com "threat", foge para longe dele.
func _move_group(group: Dictionary, now_ms: int, threat: Vector2, out: Array) -> void:
	var data: Dictionary = SPECIES[group["species"]]
	group["leave_ms"] = now_ms + _seconds(data["stay"])
	var leader: Dictionary = birds[group["members"][0]]
	var target := _pick_target(group, leader["pos"], threat)
	if target == WorldGen.NO_CELL:
		return
	var spots := _member_spots(group["species"], WorldGen.cell_center(target), group["members"].size(), _rng)
	if spots.is_empty():
		return
	var startled := threat != Vector2.INF
	for i in group["members"].size():
		var bird: Dictionary = birds[group["members"][i]]
		var spot: Array = spots[i % spots.size()]
		var delay := 0.0 if i == 0 else _rng.randf_range(0.05, STAGGER * (0.5 if startled else 1.0))
		_fly(bird, spot, now_ms + int(delay * 1000.0), float(data["speed"]) * (1.25 if startled else 1.0))
		var args := [bird["id"], to_3d(bird["from"], bird["from_h"]), to_3d(bird["to"], bird["to_h"]),
			delay, (int(bird["end_ms"]) - int(bird["start_ms"])) / 1000.0, 0.0, startled]
		for peer in bird["watchers"]:
			out.append([peer, "fly", args])


func _fly(bird: Dictionary, spot: Array, start_ms: int, speed: float) -> void:
	bird["flying"] = true
	bird["from"] = bird["pos"]
	bird["from_h"] = bird["height"]
	bird["to"] = spot[0]
	bird["to_h"] = spot[1]
	bird["cell"] = spot[2]
	var distance: float = (bird["from"] as Vector2).distance_to(spot[0])
	bird["start_ms"] = start_ms
	bird["end_ms"] = start_ms + int((0.4 + distance / speed) * 1000.0)


func _land(bird: Dictionary) -> void:
	bird["flying"] = false
	bird["pos"] = bird["to"]
	bird["height"] = bird["to_h"]
	# Logo depois de pousar, ainda não canta: se ajeita primeiro.
	var data: Dictionary = SPECIES[bird["species"]]
	bird["next_song_ms"] = int(bird["end_ms"]) + _seconds(data["song_every"], 0.0, 0.5)


## Para onde o grupo vai. Normalmente um poleiro a uma distância de voo
## curta, sem se afastar demais de casa; fugindo, o mais longe possível de
## quem assustou.
func _pick_target(group: Dictionary, from: Vector2, threat: Vector2) -> Vector2i:
	var data: Dictionary = SPECIES[group["species"]]
	var candidates := _perches_near(group["home"], HOME_RADIUS, data["perches"])
	var best := WorldGen.NO_CELL
	var best_score := -INF
	for cell: Vector2i in candidates:
		var point := WorldGen.cell_center(cell)
		var hop := point.distance_to(from)
		if hop < 2.0:
			continue
		var score: float
		if threat != Vector2.INF:
			score = point.distance_to(threat) - 0.3 * hop
		else:
			var lo: float = data["hop"][0]
			var hi: float = data["hop"][1]
			score = _rng.randf() - (0.0 if hop >= lo and hop <= hi else 1.0)
		if score > best_score:
			best_score = score
			best = cell
	return best


## Onde cada membro pousa: [ponto, altura, casa]. Um bando se espalha pelos
## poleiros perto do alvo, uns poucos em cada arbusto.
func _member_spots(species: int, target: Vector2, count: int, rng: RandomNumberGenerator) -> Array:
	var data: Dictionary = SPECIES[species]
	var cells := _perches_near(target, SPREAD if count > 1 else 0.8, data["perches"])
	if cells.is_empty():
		return []
	cells.sort_custom(func(a, b): return WorldGen.cell_center(a).distance_to(target) < WorldGen.cell_center(b).distance_to(target))
	var spots := []
	for i in count:
		var cell: Vector2i = cells[mini(i / PER_PERCH, cells.size() - 1)]
		var jitter := Vector2(rng.randf_range(-0.35, 0.35), rng.randf_range(-0.35, 0.35))
		var height := rng.randf_range(data["height"][0], data["height"][1])
		if world.thing_at(cell) == WorldGen.Thing.ARBUSTO:
			height = minf(height, 1.3)
		spots.append([WorldGen.cell_center(cell) + jitter, height, cell])
	return spots


func _perches_near(center: Vector2, radius: float, kinds: Array) -> Array:
	var found := []
	var here := WorldGen.cell_of(center)
	var r := ceili(radius)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var cell := here + Vector2i(dx, dy)
			if kinds.has(world.thing_at(cell)) and WorldGen.cell_center(cell).distance_to(center) <= radius:
				found.append(cell)
	return found


func _perches_in_chunk(origin: Vector2i, species: int) -> Array:
	var kinds: Array = SPECIES[species]["perches"]
	var found := []
	for y in CHUNK:
		for x in CHUNK:
			var cell := origin + Vector2i(x, y)
			# Só o poleiro preferido serve de casa (o primeiro da lista).
			if world.thing_at(cell) == kinds[0]:
				found.append(cell)
	return found


func _favorite_songs(species: int, rng: RandomNumberGenerator) -> Array:
	var total: int = SPECIES[species]["songs"]
	var songs := []
	for i in total:
		songs.append(i)
	# Cada um canta só alguns dos cantos da espécie, sempre os mesmos.
	for i in range(total - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = songs[i]
		songs[i] = songs[j]
		songs[j] = tmp
	return songs.slice(0, maxi(2, total - 1))


# --- Quem está perto -----------------------------------------------------------

func _players_by_chunk(players: Dictionary) -> Dictionary:
	var by_chunk := {}
	for id in players:
		var chunk := _chunk_of(players[id])
		if not by_chunk.has(chunk):
			by_chunk[chunk] = []
		by_chunk[chunk].append(players[id])
	return by_chunk


## O jogador mais perto que "radius" de um ponto, ou Vector2.INF.
func _threat_near(point: Vector2, radius: float, near: Dictionary) -> Vector2:
	var here := _chunk_of(point)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			for pos: Vector2 in near.get(here + Vector2i(dx, dy), []):
				if pos.distance_to(point) <= radius:
					return pos
	return Vector2.INF


## Avisa cada jogador dos pássaros que entraram ou saíram do seu alcance.
func _sync_watchers(now_ms: int, players: Dictionary, out: Array) -> void:
	for bird in birds.values():
		var here := position_of(bird, now_ms)
		var watchers: Dictionary = bird["watchers"]
		for peer in watchers.keys():
			if not players.has(peer) or (players[peer] as Vector2).distance_to(here) > HEARING + 4.0:
				watchers.erase(peer)
				if players.has(peer):
					out.append([peer, "gone", [bird["id"]]])
		for peer in players:
			if watchers.has(peer) or (players[peer] as Vector2).distance_to(here) > HEARING:
				continue
			watchers[peer] = true
			out.append([peer, "appear", appear_args(bird, now_ms)])


## Tudo o que um cliente precisa para começar a ouvir um pássaro:
## [id, espécie, tom, de, para, segundos até sair, duração do voo, quanto do
## voo já passou]. Pousado, "de" e "para" são o mesmo ponto.
func appear_args(bird: Dictionary, now_ms: int) -> Array:
	var from := to_3d(bird["pos"], bird["height"])
	var to := from
	var delay := 0.0
	var duration := 0.0
	var elapsed := 0.0
	if bird["flying"]:
		from = to_3d(bird["from"], bird["from_h"])
		to = to_3d(bird["to"], bird["to_h"])
		delay = maxf((int(bird["start_ms"]) - now_ms) / 1000.0, 0.0)
		duration = (int(bird["end_ms"]) - int(bird["start_ms"])) / 1000.0
		elapsed = maxf((now_ms - int(bird["start_ms"])) / 1000.0, 0.0)
	return [bird["id"], bird["species"], bird["pitch"], from, to, delay, duration, elapsed]


# --- Ajudantes -----------------------------------------------------------------

static func _chunk_of(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / CHUNK), floori(point.y / CHUNK))


func _progress(bird: Dictionary, now_ms: int) -> float:
	var span := maxi(int(bird["end_ms"]) - int(bird["start_ms"]), 1)
	return clampf(float(now_ms - int(bird["start_ms"])) / span, 0.0, 1.0)


## Milissegundos sorteados entre [mínimo, máximo] segundos, multiplicados
## por "scale" (com um piso "floor" do mínimo).
func _seconds(span: Array, floor_factor := 1.0, scale := 1.0) -> int:
	var lo: float = span[0] * floor_factor * scale
	var hi: float = span[1] * scale
	return int(_rng.randf_range(lo, hi) * 1000.0)
