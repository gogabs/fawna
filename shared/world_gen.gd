class_name WorldGen
extends RefCounted
## Gera o mundo a partir de uma semente.
##
## A mesma semente e a mesma coordenada sempre geram o mesmo lugar, no servidor
## e em todos os clientes. Por isso o servidor só precisa guardar o que os
## jogadores mudaram; o resto é recalculado.

enum Biome { BOSQUE, PRADARIA }
enum Thing { NADA, ARVORE, RIACHO, ARBUSTO, VILA }

const SIZE := 32  # MVP: mapa 32x32. O mundo infinito vem depois.

const BIOME_NAMES := {
	Biome.BOSQUE: "bosque de micélio",
	Biome.PRADARIA: "pradaria de girassóis",
}

## Com preposição, para frases como "Você está no bosque".
const BIOME_IN := {
	Biome.BOSQUE: "no bosque de micélio",
	Biome.PRADARIA: "na pradaria de girassóis",
}

const THING_NAMES := {
	Thing.ARVORE: "árvore",
	Thing.RIACHO: "riacho",
	Thing.ARBUSTO: "arbusto de sementes",
	Thing.VILA: "vila",
}

## Coisas que não deixam passar.
const BLOCKING := [Thing.ARVORE, Thing.RIACHO]

## Posições no mundo são contínuas, medidas em casas (1 casa = 1,5 m). A casa
## (x, y) cobre de x a x+1 e de y a y+1; norte é y negativo.
const METERS_PER_CELL := 1.5
const PLAYER_RADIUS := 0.3  # casas
const NO_CELL := Vector2i(-9999, -9999)

var world_seed: int
var _biome_noise := FastNoiseLite.new()
var _water_noise := FastNoiseLite.new()


func _init(new_seed: int) -> void:
	world_seed = new_seed
	_biome_noise.seed = new_seed
	_biome_noise.frequency = 0.06
	_water_noise.seed = new_seed + 7919
	_water_noise.frequency = 0.03


static func center() -> Vector2i:
	return Vector2i(SIZE / 2, SIZE / 2)


static func cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x), floori(pos.y))


static func cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell) + Vector2(0.5, 0.5)


## Ponto central da vila.
static func village_point() -> Vector2:
	return cell_center(center())


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < SIZE and cell.y < SIZE


func biome_at(cell: Vector2i) -> Biome:
	var value := _biome_noise.get_noise_2d(cell.x, cell.y)
	return Biome.BOSQUE if value < 0.0 else Biome.PRADARIA


func thing_at(cell: Vector2i) -> Thing:
	if not in_bounds(cell):
		return Thing.NADA
	# A vila fica no centro e o entorno dela é sempre livre.
	var distance_to_center := (cell - center()).length()
	if cell == center():
		return Thing.VILA
	if distance_to_center < 3.0:
		return Thing.NADA
	# Água: uma faixa do ruído de água (vira riachos e lagoas).
	if absf(_water_noise.get_noise_2d(cell.x, cell.y)) < 0.05:
		return Thing.RIACHO
	var roll := _cell_random(cell)
	match biome_at(cell):
		Biome.BOSQUE:
			if roll < 0.22:
				return Thing.ARVORE
			if roll < 0.26:
				return Thing.ARBUSTO
		Biome.PRADARIA:
			if roll < 0.04:
				return Thing.ARVORE
			if roll < 0.12:
				return Thing.ARBUSTO
	return Thing.NADA


func is_passable(cell: Vector2i) -> bool:
	return in_bounds(cell) and not BLOCKING.has(thing_at(cell))


## A primeira casa que impede uma criatura de ficar em "pos" (um círculo de
## raio "radius"), ou NO_CELL se o lugar está livre. Fora do mapa também
## bloqueia (e thing_at devolve NADA para essas casas: "fim do caminho").
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


## Número entre 0 e 1, fixo para cada célula e semente.
func _cell_random(cell: Vector2i) -> float:
	var h := hash([world_seed, cell.x, cell.y])
	return float(h & 0xFFFF) / 65535.0
