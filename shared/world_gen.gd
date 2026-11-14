class_name WorldGen
extends RefCounted
## Gera o mundo a partir de uma semente.
##
## A mesma semente e a mesma coordenada sempre geram o mesmo lugar, no servidor
## e em todos os clientes. Por isso o servidor só precisa guardar o que os
## jogadores mudaram; o resto é recalculado.
##
## O mundo é dividido em regiões grandes (REGION_SIZE casas de lado), cada uma
## com uma única característica: bosque, pradaria ou lagoa. Dentro delas, as
## coisas são espalhadas de forma procedural, e só são calculadas quando
## alguém chega perto (em pedaços de CHUNK casas, guardados em cache). Cada
## região tem um ponto de encontro, e trilhas de terra ligam os pontos das
## regiões vizinhas. A vila fica no ponto de encontro da região (0, 0).

enum Biome { BOSQUE, PRADARIA, LAGOA }
enum Thing { NADA, ARVORE, RIACHO, ARBUSTO, VILA, TRILHA, PONTE, LAGO }

const REGION_SIZE := 48  # casas (72 m)
const CHUNK := 16
const WORLD_LIMIT := 4096  # casas a partir da vila; além disso, fim do caminho
const VILLAGE_CLEAR_RADIUS := 3.0
const VILLAGE_DRY_RADIUS := 10.0  # sem riachos colados na vila
const TRAIL_HALF_WIDTH := 0.8  # casas: trilhas com uns 2,4 m de largura
const LAKE_RADIUS := 9.0  # casas, antes da ondulação da margem

const BIOME_NAMES := {
	Biome.BOSQUE: "bosque de micélio",
	Biome.PRADARIA: "pradaria de girassóis",
	Biome.LAGOA: "lagoa das vitórias-régias",
}

## Com preposição, para frases como "Você está no bosque".
const BIOME_IN := {
	Biome.BOSQUE: "no bosque de micélio",
	Biome.PRADARIA: "na pradaria de girassóis",
	Biome.LAGOA: "na lagoa das vitórias-régias",
}

const THING_NAMES := {
	Thing.ARVORE: "árvore",
	Thing.RIACHO: "riacho",
	Thing.ARBUSTO: "arbusto de sementes",
	Thing.VILA: "vila",
	Thing.TRILHA: "trilha",
	Thing.PONTE: "ponte",
	Thing.LAGO: "lagoa",
}

## Coisas que não deixam passar.
const BLOCKING := [Thing.ARVORE, Thing.RIACHO, Thing.LAGO]
## Chão por onde se anda: não são "coisas" para a fala listar.
const GROUND := [Thing.NADA, Thing.TRILHA, Thing.PONTE]

## Posições no mundo são contínuas, medidas em casas (1 casa = 1,5 m). A casa
## (x, y) cobre de x a x+1 e de y a y+1; norte é y negativo.
const METERS_PER_CELL := 1.5
const PLAYER_RADIUS := 0.3  # casas
const NO_CELL := Vector2i(-9999999, -9999999)

## Quanto de cada região é de cada tipo, e o que nasce em cada uma
## (chance por casa).
const BIOME_WEIGHTS := {Biome.BOSQUE: 0.45, Biome.PRADARIA: 0.4, Biome.LAGOA: 0.15}
const DENSITY := {
	Biome.BOSQUE: {Thing.ARVORE: 0.09, Thing.ARBUSTO: 0.012},
	Biome.PRADARIA: {Thing.ARVORE: 0.008, Thing.ARBUSTO: 0.03},
	Biome.LAGOA: {Thing.ARVORE: 0.02, Thing.ARBUSTO: 0.02},
}

var world_seed: int
var _warp_noise := FastNoiseLite.new()  # entorta bordas de regiões e trilhas
var _stream_noise := FastNoiseLite.new()  # riachos finos entre regiões
var _lake_noise := FastNoiseLite.new()  # margem ondulada das lagoas
var _chunks := {}  # Vector2i (pedaço) -> [Thing de cada casa, Biome de cada casa]
var _regions := {}  # Vector2i (região) -> Biome


func _init(new_seed: int) -> void:
	world_seed = new_seed
	_warp_noise.seed = new_seed
	_warp_noise.frequency = 0.04
	_stream_noise.seed = new_seed + 7919
	_stream_noise.frequency = 0.007
	_stream_noise.fractal_type = FastNoiseLite.FRACTAL_NONE  # riachos longos e suaves
	_lake_noise.seed = new_seed + 104729
	_lake_noise.frequency = 0.15


static func center() -> Vector2i:
	return Vector2i.ZERO


static func cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x), floori(pos.y))


static func cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell) + Vector2(0.5, 0.5)


## Ponto central da vila.
static func village_point() -> Vector2:
	return cell_center(center())


func in_bounds(cell: Vector2i) -> bool:
	return absi(cell.x) <= WORLD_LIMIT and absi(cell.y) <= WORLD_LIMIT


# --- Regiões -------------------------------------------------------------------

## Região de uma casa. As bordas são levemente entortadas, para não serem
## retas demais, mas as regiões continuam sendo "quadradões".
func region_of(cell: Vector2i) -> Vector2i:
	var p := Vector2(cell) + _warp(Vector2(cell), 5.0)
	return Vector2i(floori(p.x / REGION_SIZE + 0.5), floori(p.y / REGION_SIZE + 0.5))


func region_biome(region: Vector2i) -> Biome:
	if _regions.has(region):
		return _regions[region]
	var biome := Biome.PRADARIA
	if region != Vector2i.ZERO:  # a vila fica sempre numa pradaria
		var roll := _random([region.x, region.y, "bioma"])
		var total := 0.0
		for b in BIOME_WEIGHTS:
			total += BIOME_WEIGHTS[b]
			if roll < total:
				biome = b
				break
	_regions[region] = biome
	return biome


func biome_at(cell: Vector2i) -> Biome:
	if not in_bounds(cell):
		return region_biome(region_of(cell))
	return _chunk_data(cell)[1][_chunk_index(cell)] as Biome


## Ponto de encontro da região: onde as trilhas se cruzam. Na região da vila,
## é a própria vila; nas outras, um ponto perto do centro.
func region_landmark(region: Vector2i) -> Vector2:
	var middle := Vector2(region) * REGION_SIZE + Vector2(0.5, 0.5)
	if region == Vector2i.ZERO:
		return village_point()
	var spread := REGION_SIZE * 0.25
	var offset := Vector2(_random([region.x, region.y, "px"]) - 0.5, _random([region.x, region.y, "py"]) - 0.5)
	return middle + offset * 2.0 * spread


## Regiões ligadas por trilha a esta (as 4 vizinhas). É a base para achar
## caminhos: ir de ponto de encontro em ponto de encontro.
func trail_neighbors(region: Vector2i) -> Array[Vector2i]:
	return [region + Vector2i.UP, region + Vector2i.DOWN, region + Vector2i.LEFT, region + Vector2i.RIGHT]


# --- Coisas --------------------------------------------------------------------

func thing_at(cell: Vector2i) -> Thing:
	if not in_bounds(cell):
		return Thing.NADA
	return _chunk_data(cell)[0][_chunk_index(cell)] as Thing


## [coisas, biomas] do pedaço que contém a casa, gerado na primeira vez.
func _chunk_data(cell: Vector2i) -> Array:
	var chunk := Vector2i(floori(float(cell.x) / CHUNK), floori(float(cell.y) / CHUNK))
	if not _chunks.has(chunk):
		_chunks[chunk] = _generate_chunk(chunk)
	return _chunks[chunk]


static func _chunk_index(cell: Vector2i) -> int:
	return posmod(cell.y, CHUNK) * CHUNK + posmod(cell.x, CHUNK)


func is_passable(cell: Vector2i) -> bool:
	return in_bounds(cell) and not BLOCKING.has(thing_at(cell))


func is_trail(cell: Vector2i) -> bool:
	var thing := thing_at(cell)
	return thing == Thing.TRILHA or thing == Thing.PONTE or thing == Thing.VILA


func _generate_chunk(chunk: Vector2i) -> Array:
	var things := PackedByteArray()
	var biomes := PackedByteArray()
	things.resize(CHUNK * CHUNK)
	biomes.resize(CHUNK * CHUNK)
	var origin := chunk * CHUNK
	var segments := _segments_near(origin + Vector2i.ONE * (CHUNK / 2))
	for y in CHUNK:
		for x in CHUNK:
			var cell := origin + Vector2i(x, y)
			things[y * CHUNK + x] = _compute_thing(cell, segments)
			biomes[y * CHUNK + x] = region_biome(region_of(cell))
	return [things, biomes]


func _compute_thing(cell: Vector2i, segments: Array) -> Thing:
	if cell == center():
		return Thing.VILA
	var p := cell_center(cell)
	# O entorno da vila é sempre livre.
	if p.distance_to(village_point()) < VILLAGE_CLEAR_RADIUS:
		return Thing.NADA
	var region := region_of(cell)
	var biome := region_biome(region)
	var water := _is_water(cell, region, biome)
	if _on_trail(p, segments):
		return Thing.PONTE if water != Thing.NADA else Thing.TRILHA
	if water != Thing.NADA:
		return water
	var roll := _random([cell.x, cell.y])
	var chances: Dictionary = DENSITY[biome]
	var total := 0.0
	for thing in chances:
		total += chances[thing]
		if roll < total:
			return thing
	return Thing.NADA


func _is_water(cell: Vector2i, region: Vector2i, biome: Biome) -> Thing:
	if biome == Biome.LAGOA:
		# Uma lagoa redonda, de margem ondulada, um pouco ao lado do ponto
		# de encontro (as trilhas chegam até ela e a atravessam por pontes).
		var lake_center := Vector2(region) * REGION_SIZE + Vector2(0.5, 0.5)
		var distance := cell_center(cell).distance_to(lake_center)
		var radius := LAKE_RADIUS * (1.0 + 0.3 * _lake_noise.get_noise_2d(cell.x, cell.y))
		if distance < radius:
			return Thing.LAGO
	# Riachos finos e raros, que cortam as regiões (mas não a vila).
	if cell_center(cell).distance_to(village_point()) < VILLAGE_DRY_RADIUS:
		return Thing.NADA
	if absf(_stream_noise.get_noise_2d(cell.x, cell.y)) < 0.02:
		return Thing.RIACHO
	return Thing.NADA


# --- Trilhas -------------------------------------------------------------------

## Trechos de trilha (pares de pontos) que podem passar perto de uma casa: os
## que ligam o ponto de encontro de cada região às vizinhas leste e sul, nas
## regiões em volta.
func _segments_near(cell: Vector2i) -> Array:
	var segments := []
	var here := Vector2i(roundi(float(cell.x) / REGION_SIZE), roundi(float(cell.y) / REGION_SIZE))
	for ry in range(here.y - 2, here.y + 2):
		for rx in range(here.x - 2, here.x + 2):
			var region := Vector2i(rx, ry)
			var a := region_landmark(region)
			segments.append([a, region_landmark(region + Vector2i.RIGHT)])
			segments.append([a, region_landmark(region + Vector2i.DOWN)])
	return segments


## A casa está numa trilha? As trilhas são retas entortadas por ruído, para
## serpentear como um caminho de verdade.
func _on_trail(p: Vector2, segments: Array) -> bool:
	var q := p + _warp(p, 2.5)
	for seg in segments:
		var closest := Geometry2D.get_closest_point_to_segment(q, seg[0], seg[1])
		if q.distance_to(closest) <= TRAIL_HALF_WIDTH:
			return true
	return false


## Trilha mais próxima de um ponto, procurando até "radius" casas. Devolve a
## casa ou NO_CELL.
func nearest_trail(pos: Vector2, radius := 8) -> Vector2i:
	var here := cell_of(pos)
	var best := NO_CELL
	var best_distance := INF
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var cell := here + Vector2i(dx, dy)
			var thing := thing_at(cell)
			if thing != Thing.TRILHA and thing != Thing.PONTE:
				continue
			var distance := cell_center(cell).distance_to(pos)
			if distance < best_distance:
				best = cell
				best_distance = distance
	return best


# --- Colisão -------------------------------------------------------------------

## A primeira casa que impede uma criatura de ficar em "pos" (um círculo de
## raio "radius"), ou NO_CELL se o lugar está livre. Além do limite do mundo
## também bloqueia (e thing_at devolve NADA lá: "fim do caminho").
func blocker_at(pos: Vector2, radius := PLAYER_RADIUS) -> Vector2i:
	var min_cell := cell_of(pos - Vector2.ONE * radius)
	var max_cell := cell_of(pos + Vector2.ONE * radius)
	var best := NO_CELL
	var best_distance := INF
	for y in range(min_cell.y, max_cell.y + 1):
		for x in range(min_cell.x, max_cell.x + 1):
			var cell := Vector2i(x, y)
			if is_passable(cell):
				continue
			var closest := Vector2(clampf(pos.x, x, x + 1), clampf(pos.y, y, y + 1))
			var distance := pos.distance_to(closest)
			if distance < radius and distance < best_distance:
				best = cell
				best_distance = distance
	return best


func is_free(pos: Vector2, radius := PLAYER_RADIUS) -> bool:
	return blocker_at(pos, radius) == NO_CELL


# --- Aleatório fixo ------------------------------------------------------------

## Número entre 0 e 1, fixo para cada chave e semente.
func _random(key: Array) -> float:
	var h := hash([world_seed] + key)
	return float(h & 0xFFFF) / 65535.0


func _warp(p: Vector2, amount: float) -> Vector2:
	return Vector2(_warp_noise.get_noise_2d(p.x, p.y), _warp_noise.get_noise_2d(p.x + 500.0, p.y - 500.0)) * amount
