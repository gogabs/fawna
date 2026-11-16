class_name WorldGen
extends RefCounted
## Gera o mundo a partir de uma semente.
##
## A mesma semente e a mesma coordenada sempre geram o mesmo lugar, no servidor
## e em todos os clientes. Por isso o servidor só precisa guardar o que os
## jogadores mudaram; o resto é recalculado.
##
## O mundo é dividido em regiões grandes (REGION_SIZE casas de lado), cada uma
## com uma única característica: bosque, pradaria, lagoa ou bambuzal. Dentro
## delas, as coisas nascem em lugares que fazem sentido (arbustos na orla do
## bosque, bambu na orla do bambuzal e na beira da água), e só são calculadas quando
## alguém chega perto (em pedaços de CHUNK casas, guardados em cache). Cada
## região tem um ponto de encontro, e trilhas de terra ligam os pontos das
## regiões vizinhas. A Origem fica no ponto de encontro da região (0, 0).

enum Biome { BOSQUE, PRADARIA, LAGOA, BAMBUZAL }
enum Thing { NADA, RIACHO, ARBUSTO, ORIGEM, TRILHA, PONTE, LAGO, BAMBU, ARGILA, ARBUSTO_FRUTAS, PEDRAS }

const REGION_SIZE := 48  # casas (72 m)
const CHUNK := 16
const WORLD_LIMIT := 4096  # casas a partir da Origem; além disso, fim do caminho
const ORIGIN_CLEAR_RADIUS := 3.0
const ORIGIN_DRY_RADIUS := 10.0  # sem riachos colados na Origem
const TRAIL_HALF_WIDTH := 1.6  # casas: trilhas com uns 4,8 m de largura
const TRAIL_VERGE := 1.2  # casas além da trilha em que nada nasce (acostamento)
const LAKE_RADIUS := 9.0  # casas, antes da ondulação da margem
const TRAIL_STEP := 0.5  # casas entre os pontos da linha de uma trilha
const TRAIL_SWAY := 4.0  # casas que a trilha se afasta da reta, no máximo
const TRAIL_SWAY_EASE := 10.0  # casas, perto das pontas, em que a curva some
## Frequência do ruído que curva as trilhas: baixa, para cada trilha fazer no
## máximo uma ou duas curvas longas e suaves entre regiões, em vez de
## serpentear.
const TRAIL_BEND_FREQUENCY := 0.012
const TRAIL_CELL := 1  # na máscara de trilhas de um pedaço
const TRAIL_EDGE := 2
const TRAIL_SIDE := 3

const BIOME_NAMES := {
	Biome.BOSQUE: "bosque de micélio",
	Biome.PRADARIA: "pradaria de girassóis",
	Biome.LAGOA: "lagoa das vitórias-régias",
	Biome.BAMBUZAL: "bambuzal",
}

## Com preposição, para frases como "Você está no bosque".
const BIOME_IN := {
	Biome.BOSQUE: "no bosque de micélio",
	Biome.PRADARIA: "na pradaria de girassóis",
	Biome.LAGOA: "na lagoa das vitórias-régias",
	Biome.BAMBUZAL: "no bambuzal",
}

const THING_NAMES := {
	Thing.RIACHO: "riacho",
	Thing.ARBUSTO: "arbusto com gravetos",
	Thing.ORIGEM: "Origem",
	Thing.TRILHA: "trilha",
	Thing.PONTE: "ponte",
	Thing.LAGO: "lagoa",
	Thing.BAMBU: "touceira de bambu",
	Thing.ARGILA: "argila",
	Thing.ARBUSTO_FRUTAS: "arbusto com frutas",
	Thing.PEDRAS: "pedras",
}

## Coisas que não deixam passar.
const BLOCKING := [Thing.RIACHO, Thing.LAGO, Thing.BAMBU]
## Chão por onde se anda: não são "coisas" para a fala listar.
const GROUND := [Thing.NADA, Thing.TRILHA, Thing.PONTE]

## Posições no mundo são contínuas, medidas em casas (1 casa = 1,5 m). A casa
## (x, y) cobre de x a x+1 e de y a y+1; norte é y negativo.
const METERS_PER_CELL := 1.5
const PLAYER_RADIUS := 0.3  # casas
const NO_CELL := Vector2i(-9999999, -9999999)

## Quanto de cada região é de cada tipo.
const BIOME_WEIGHTS := {Biome.BOSQUE: 0.4, Biome.PRADARIA: 0.37, Biome.LAGOA: 0.14, Biome.BAMBUZAL: 0.09}

## Onde nascem os recursos coletáveis (shared/harvest.gd). Em vez de espalhados
## por igual, cada um tem o seu lugar, para dar para aprender onde procurar:
##
## - Arbustos (gravetos para lenha ou, raros, frutas) crescem na orla: a faixa
##   em que um bioma fechado (FOREST_BIOMES) encosta num aberto (OPEN_BIOMES).
##   Mais cheios do lado de dentro da mata, e ainda alguns passos campo adentro.
##   Longe da orla só há um ou outro arbusto perdido.
## - Bambu cresce em dois lugares: no bambuzal, com as touceiras fechando a orla
##   e mais ralas no miolo (para dar para andar lá dentro), e na beira da água,
##   em moitas ao longo das margens das lagoas e dos riachos.
##
## Biomas novos só precisam entrar em FOREST_BIOMES ou OPEN_BIOMES para ganhar
## a orla de arbustos.
const FOREST_BIOMES := [Biome.BOSQUE]
const OPEN_BIOMES := [Biome.PRADARIA, Biome.LAGOA]
## Até quantas casas da divisa entre biomas a orla é procurada.
const EDGE_REACH := 4
## Orla do lado da mata: BUSH_FOREST_BAND casas, de BUSH_EDGE_CHANCE (por casa)
## bem na divisa até BUSH_EDGE_FADE no fim da faixa.
const BUSH_FOREST_BAND := 4.0
const BUSH_EDGE_CHANCE := 0.25
const BUSH_EDGE_FADE := 0.09
## Orla do lado do campo: mais estreita e mais rala.
const BUSH_OPEN_BAND := 2.0
const BUSH_OPEN_EDGE_CHANCE := 0.12
## Arbustos perdidos, longe de qualquer orla.
const BUSH_STRAY_CHANCE := {Biome.BOSQUE: 0.002, Biome.PRADARIA: 0.004, Biome.LAGOA: 0.004}
## Bambuzal: orla de BAMBOO_BAND casas, de BAMBOO_EDGE_CHANCE na divisa até
## BAMBOO_EDGE_FADE; no miolo, BAMBOO_INSIDE_CHANCE.
const BAMBOO_BAND := 4.0
const BAMBOO_EDGE_CHANCE := 0.16
const BAMBOO_EDGE_FADE := 0.07
const BAMBOO_INSIDE_CHANCE := 0.025
## Bambu na beira da água: só onde o ruído das moitas deixa (mais ou menos
## metade das margens), para formar moitas com espaços entre elas. Na lagoa, de
## BAMBOO_LAKE_FROM a BAMBOO_LAKE_TO casas além da margem (a argila fica mais
## perto da água); no riacho, até BAMBOO_STREAM_BANK no ruído dos riachos.
const BAMBOO_WATER_CHANCE := 0.11
const BAMBOO_LAKE_FROM := 1.0
const BAMBOO_LAKE_TO := 4.5
const BAMBOO_STREAM_BANK := 0.05
const BAMBOO_GROVE_FREQUENCY := 0.06
## Fração dos arbustos que dá frutas em vez de gravetos: são raros (uns poucos
## por região).
const FRUIT_BUSH_CHANCE := 0.07
## Argila: só na beira da água. Chance por casa na margem das lagoas (até
## CLAY_BANK casas além da água) e na beira dos riachos.
const CLAY_BANK := 2.5
const CLAY_LAKE_CHANCE := 0.07
const CLAY_STREAM_CHANCE := 0.05
## Pedras soltas: espalhadas pelo mundo todo, bem mais comuns na beira da
## água (riachos e lagoas), onde dão mais pedras pequenas (Harvest). Só nascem
## em casas que ficariam vazias, então o resto do mundo de cada semente não muda.
const STONE_CHANCE := 0.004
const STONE_WATER_CHANCE := 0.03
const WATERSIDE_LAKE_BANK := 3.0  # casas além da margem da lagoa
const WATERSIDE_STREAM_BANK := 0.07  # no ruído dos riachos
const STREAM_WIDTH := 0.02  # no ruído dos riachos
const STREAM_BANK := 0.05

var world_seed: int
var _warp_noise := FastNoiseLite.new()  # entorta bordas de regiões
var _trail_noise := FastNoiseLite.new()  # curva as trilhas, devagar
var _stream_noise := FastNoiseLite.new()  # riachos finos entre regiões
var _lake_noise := FastNoiseLite.new()  # margem ondulada das lagoas
var _grove_noise := FastNoiseLite.new()  # moitas de bambu na beira da água
var _chunks := {}  # Vector2i (pedaço) -> [Thing de cada casa, Biome de cada casa]
var _regions := {}  # Vector2i (região) -> Biome
var _trail_lines := {}  # [região, vizinha] -> PackedVector2Array
## Casas ocupadas por construções (marco, fogueira): não deixam passar.
## Quem mantém é Builds; aqui só a colisão consulta. Vector2i -> id da obra.
var built := {}


func _init(new_seed: int) -> void:
	world_seed = new_seed
	_warp_noise.seed = new_seed
	_warp_noise.frequency = 0.04
	_trail_noise.seed = new_seed + 3571
	_trail_noise.frequency = TRAIL_BEND_FREQUENCY
	_trail_noise.fractal_type = FastNoiseLite.FRACTAL_NONE  # sem zigue-zague miúdo
	_stream_noise.seed = new_seed + 7919
	_stream_noise.frequency = 0.007
	_stream_noise.fractal_type = FastNoiseLite.FRACTAL_NONE  # riachos longos e suaves
	_lake_noise.seed = new_seed + 104729
	_lake_noise.frequency = 0.15
	_grove_noise.seed = new_seed + 15485863
	_grove_noise.frequency = BAMBOO_GROVE_FREQUENCY
	_grove_noise.fractal_type = FastNoiseLite.FRACTAL_NONE


static func center() -> Vector2i:
	return Vector2i.ZERO


static func cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x), floori(pos.y))


static func cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell) + Vector2(0.5, 0.5)


## Ponto central da Origem.
static func origin_point() -> Vector2:
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
	if region != Vector2i.ZERO:  # a Origem fica sempre numa pradaria
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


## Ponto de encontro da região: onde as trilhas se cruzam. Na região da
## Origem, é a própria Origem; nas outras, um ponto perto do centro.
func region_landmark(region: Vector2i) -> Vector2:
	var middle := Vector2(region) * REGION_SIZE + Vector2(0.5, 0.5)
	if region == Vector2i.ZERO:
		return origin_point()
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
	return in_bounds(cell) and not BLOCKING.has(thing_at(cell)) and not built.has(cell)


func is_trail(cell: Vector2i) -> bool:
	var thing := thing_at(cell)
	return thing == Thing.TRILHA or thing == Thing.PONTE or thing == Thing.ORIGEM


func _generate_chunk(chunk: Vector2i) -> Array:
	var things := PackedByteArray()
	var biomes := PackedByteArray()
	things.resize(CHUNK * CHUNK)
	biomes.resize(CHUNK * CHUNK)
	var origin := chunk * CHUNK
	var segments := _segments_near(origin + Vector2i.ONE * (CHUNK / 2))
	var trails := _trail_mask(origin, segments)
	var around := _biomes_around(origin)
	for y in CHUNK:
		for x in CHUNK:
			var cell := origin + Vector2i(x, y)
			things[y * CHUNK + x] = _compute_thing(cell, trails[y * CHUNK + x], around, x, y)
			biomes[y * CHUNK + x] = around[(y + EDGE_REACH) * AROUND_SIDE + x + EDGE_REACH]
	return [things, biomes]


func _compute_thing(cell: Vector2i, trail: int, around: PackedByteArray, x: int, y: int) -> Thing:
	if cell == center():
		return Thing.ORIGEM
	var p := cell_center(cell)
	# O entorno da Origem é sempre livre.
	if p.distance_to(origin_point()) < ORIGIN_CLEAR_RADIUS:
		return Thing.NADA
	var region := region_of(cell)
	var biome := region_biome(region)
	var water := _is_water(cell, region, biome)
	if trail == TRAIL_CELL:
		return Thing.PONTE if water != Thing.NADA else Thing.TRILHA
	if water != Thing.NADA:
		return Thing.PONTE if trail == TRAIL_EDGE else water
	# Na beira da trilha não nasce nada (nem bambu, nem arbusto, nem argila):
	# a trilha fica limpa e fácil de seguir.
	if trail != 0:
		return Thing.NADA
	var roll := _random([cell.x, cell.y])
	var bamboo := _bamboo_chance(cell, region, biome, around, x, y)
	if roll < bamboo:
		return Thing.BAMBU
	if roll < bamboo + _bush_chance(biome, around, x, y):
		if cell_random(cell, "fruta") < FRUIT_BUSH_CHANCE:
			return Thing.ARBUSTO_FRUTAS
		return Thing.ARBUSTO
	if _is_clay(cell, region, biome):
		return Thing.ARGILA
	var stone_chance := STONE_WATER_CHANCE if is_waterside(cell) else STONE_CHANCE
	if cell_random(cell, "pedra") < stone_chance:
		return Thing.PEDRAS
	return Thing.NADA


# --- Orlas: onde nascem arbustos e bambu ---------------------------------------

const AROUND_SIDE := CHUNK + 2 * EDGE_REACH
static var _edge_offsets: Array[Vector2i] = []  # vizinhas até EDGE_REACH, da mais perto à mais longe


## Bioma de cada casa do pedaço e de uma moldura de EDGE_REACH casas em volta
## dele: é o que _edge_distance consulta, sem refazer a conta a cada casa.
func _biomes_around(origin: Vector2i) -> PackedByteArray:
	var around := PackedByteArray()
	around.resize(AROUND_SIDE * AROUND_SIDE)
	for y in AROUND_SIDE:
		for x in AROUND_SIDE:
			around[y * AROUND_SIDE + x] = region_biome(region_of(origin + Vector2i(x - EDGE_REACH, y - EDGE_REACH)))
	return around


## Distância (em casas) da casa (x, y) do pedaço até a casa mais próxima cujo
## bioma está em "kinds" (ou, com "outside", fora de "kinds"). INF se não há
## nenhuma a até EDGE_REACH casas: a casa está longe da orla.
static func _edge_distance(around: PackedByteArray, x: int, y: int, kinds: Array, outside := false) -> float:
	if _edge_offsets.is_empty():
		for dy in range(-EDGE_REACH, EDGE_REACH + 1):
			for dx in range(-EDGE_REACH, EDGE_REACH + 1):
				if (dx != 0 or dy != 0) and dx * dx + dy * dy <= EDGE_REACH * EDGE_REACH:
					_edge_offsets.append(Vector2i(dx, dy))
		_edge_offsets.sort_custom(func(a: Vector2i, b: Vector2i): return a.length_squared() < b.length_squared())
	var base := (y + EDGE_REACH) * AROUND_SIDE + x + EDGE_REACH
	# Atalho: quase todas as casas ficam longe de qualquer divisa. Se as oito
	# pontas da vizinhança têm o bioma daqui, não há orla por perto.
	var here := around[base]
	var uniform := true
	for far: int in [EDGE_REACH, -EDGE_REACH, EDGE_REACH * AROUND_SIDE, -EDGE_REACH * AROUND_SIDE,
			3 * AROUND_SIDE + 3, 3 * AROUND_SIDE - 3, -3 * AROUND_SIDE + 3, -3 * AROUND_SIDE - 3]:
		if around[base + far] != here:
			uniform = false
			break
	if uniform:
		return INF
	for offset in _edge_offsets:
		if kinds.has(around[base + offset.y * AROUND_SIDE + offset.x]) != outside:
			return offset.length()
	return INF


## Chance de um arbusto nascer na casa: alta na orla entre mata e campo, quase
## nenhuma longe dela.
func _bush_chance(biome: Biome, around: PackedByteArray, x: int, y: int) -> float:
	if FOREST_BIOMES.has(biome):
		var distance := _edge_distance(around, x, y, OPEN_BIOMES)
		if distance <= BUSH_FOREST_BAND:
			return lerpf(BUSH_EDGE_CHANCE, BUSH_EDGE_FADE, (distance - 1.0) / (BUSH_FOREST_BAND - 1.0))
	elif OPEN_BIOMES.has(biome):
		if _edge_distance(around, x, y, FOREST_BIOMES) <= BUSH_OPEN_BAND:
			return BUSH_OPEN_EDGE_CHANCE
	return BUSH_STRAY_CHANCE.get(biome, 0.0)


## Chance de uma touceira de bambu nascer na casa: na orla e no miolo do
## bambuzal, e em moitas na beira das lagoas e dos riachos.
func _bamboo_chance(cell: Vector2i, region: Vector2i, biome: Biome, around: PackedByteArray, x: int, y: int) -> float:
	if biome == Biome.BAMBUZAL:
		var distance := _edge_distance(around, x, y, [Biome.BAMBUZAL], true)
		if distance <= BAMBOO_BAND:
			return lerpf(BAMBOO_EDGE_CHANCE, BAMBOO_EDGE_FADE, (distance - 1.0) / (BAMBOO_BAND - 1.0))
		return BAMBOO_INSIDE_CHANCE
	if _grove_noise.get_noise_2d(cell.x, cell.y) < 0.0:
		return 0.0
	if biome == Biome.LAGOA:
		var shore := _lake_shore(cell, region)
		if shore >= BAMBOO_LAKE_FROM and shore < BAMBOO_LAKE_TO:
			return BAMBOO_WATER_CHANCE
	if cell_center(cell).distance_to(origin_point()) >= ORIGIN_DRY_RADIUS \
			and absf(_stream_noise.get_noise_2d(cell.x, cell.y)) < BAMBOO_STREAM_BANK:
		return BAMBOO_WATER_CHANCE
	return 0.0


## Quantas casas a casa está além da margem da lagoa da região (negativo:
## dentro da água).
func _lake_shore(cell: Vector2i, region: Vector2i) -> float:
	var lake_center := Vector2(region) * REGION_SIZE + Vector2(0.5, 0.5)
	var radius := LAKE_RADIUS * (1.0 + 0.3 * _lake_noise.get_noise_2d(cell.x, cell.y))
	return cell_center(cell).distance_to(lake_center) - radius


## A casa fica perto de um riacho ou da margem de uma lagoa? (As pedras daqui
## são mais miúdas, roladas pela água.)
func is_waterside(cell: Vector2i) -> bool:
	var region := region_of(cell)
	if region_biome(region) == Biome.LAGOA:
		var lake_center := Vector2(region) * REGION_SIZE + Vector2(0.5, 0.5)
		var distance := cell_center(cell).distance_to(lake_center)
		var radius := LAKE_RADIUS * (1.0 + 0.3 * _lake_noise.get_noise_2d(cell.x, cell.y))
		if distance < radius + WATERSIDE_LAKE_BANK:
			return true
	if cell_center(cell).distance_to(origin_point()) < ORIGIN_DRY_RADIUS:
		return false
	return absf(_stream_noise.get_noise_2d(cell.x, cell.y)) < WATERSIDE_STREAM_BANK


## Barro na beira da água: margem das lagoas e beira dos riachos.
func _is_clay(cell: Vector2i, region: Vector2i, biome: Biome) -> bool:
	var roll := cell_random(cell, "argila")
	if biome == Biome.LAGOA and roll < CLAY_LAKE_CHANCE:
		var lake_center := Vector2(region) * REGION_SIZE + Vector2(0.5, 0.5)
		var distance := cell_center(cell).distance_to(lake_center)
		var radius := LAKE_RADIUS * (1.0 + 0.3 * _lake_noise.get_noise_2d(cell.x, cell.y))
		if distance < radius + CLAY_BANK:
			return true
	if roll < CLAY_STREAM_CHANCE and cell_center(cell).distance_to(origin_point()) >= ORIGIN_DRY_RADIUS:
		return absf(_stream_noise.get_noise_2d(cell.x, cell.y)) < STREAM_BANK
	return false


func _is_water(cell: Vector2i, region: Vector2i, biome: Biome) -> Thing:
	if biome == Biome.LAGOA:
		# Uma lagoa redonda, de margem ondulada, um pouco ao lado do ponto
		# de encontro (as trilhas chegam até ela e a atravessam por pontes).
		var lake_center := Vector2(region) * REGION_SIZE + Vector2(0.5, 0.5)
		var distance := cell_center(cell).distance_to(lake_center)
		var radius := LAKE_RADIUS * (1.0 + 0.3 * _lake_noise.get_noise_2d(cell.x, cell.y))
		if distance < radius:
			return Thing.LAGO
	# Riachos finos e raros, que cortam as regiões (mas não a Origem).
	if cell_center(cell).distance_to(origin_point()) < ORIGIN_DRY_RADIUS:
		return Thing.NADA
	if absf(_stream_noise.get_noise_2d(cell.x, cell.y)) < STREAM_WIDTH:
		return Thing.RIACHO
	return Thing.NADA


# --- Trilhas -------------------------------------------------------------------

## Trechos de trilha que podem passar perto de uma casa: os que ligam o ponto
## de encontro de cada região às vizinhas leste e sul, nas regiões em volta.
## Cada trecho é a linha (trail_line) de uma região à vizinha.
func _segments_near(cell: Vector2i) -> Array:
	var segments := []
	var here := Vector2i(roundi(float(cell.x) / REGION_SIZE), roundi(float(cell.y) / REGION_SIZE))
	for ry in range(here.y - 2, here.y + 2):
		for rx in range(here.x - 2, here.x + 2):
			var region := Vector2i(rx, ry)
			segments.append(trail_line(region, region + Vector2i.RIGHT))
			segments.append(trail_line(region, region + Vector2i.DOWN))
	return segments


## Caminho da trilha entre os pontos de encontro de duas regiões vizinhas, como
## uma linha de pontos (em casas), do ponto de "from" ao de "to". Em terra, a
## trilha serpenteia em volta da reta; sobre a água, vira uma ponte reta, da
## última margem seca até a próxima. Os pontos são o que o caminho de fato
## percorre, então servem para achar rotas e marcar as curvas.
func trail_line(from: Vector2i, to: Vector2i) -> PackedVector2Array:
	var key := [from, to]
	if _trail_lines.has(key):
		return _trail_lines[key]
	var reverse := [to, from]
	if _trail_lines.has(reverse):
		var flipped := (_trail_lines[reverse] as PackedVector2Array).duplicate()
		flipped.reverse()
		return flipped
	var line := _build_trail_line(from, to)
	_trail_lines[key] = line
	return line


func _build_trail_line(from: Vector2i, to: Vector2i) -> PackedVector2Array:
	var a := region_landmark(from)
	var b := region_landmark(to)
	var length := a.distance_to(b)
	var steps := maxi(1, ceili(length / TRAIL_STEP))
	var side := (b - a).normalized().orthogonal()
	# Pontos da trilha serpenteando, e se cada um cai na água.
	var points := PackedVector2Array()
	var wet := []
	for i in steps + 1:
		var t := float(i) / steps
		var s := a.lerp(b, t)
		# A curva some perto das pontas, para todas as trilhas de uma região
		# se encontrarem bem no ponto de encontro.
		# Suave (smoothstep), para não virar uma quina onde a curva começa.
		var ease := smoothstep(0.0, 1.0, minf(t, 1.0 - t) * length / TRAIL_SWAY_EASE)
		var p := s + side * _trail_noise.get_noise_2d(s.x, s.y) * TRAIL_SWAY * ease
		points.append(p)
		wet.append(_is_water_at(cell_of(p)))
	# Sobre a água, só ficam as margens: a ponte é a reta entre elas.
	var line := PackedVector2Array()
	for i in points.size():
		if not wet[i] or i == 0 or i == points.size() - 1:
			line.append(points[i])
	return line


func _is_water_at(cell: Vector2i) -> bool:
	var region := region_of(cell)
	return _is_water(cell, region, region_biome(region)) != Thing.NADA


## Marca, numa máscara do pedaço, as casas da trilha (TRAIL_CELL: o centro fica
## a até TRAIL_HALF_WIDTH da linha), as casas que uma criatura andando bem na
## linha encostaria (TRAIL_EDGE: água ali vira ponte, para que seguir a linha
## nunca esbarre em nada) e o acostamento (TRAIL_SIDE: até TRAIL_VERGE casas
## além da trilha), onde não nasce nada.
func _trail_mask(origin: Vector2i, segments: Array) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(CHUNK * CHUNK)
	var reach := TRAIL_HALF_WIDTH + TRAIL_VERGE + 1.0
	var pad := ceili(reach)
	var low := Vector2(origin) - Vector2.ONE * reach
	var high := Vector2(origin + Vector2i.ONE * CHUNK) + Vector2.ONE * reach
	for line: PackedVector2Array in segments:
		for i in line.size() - 1:
			var p: Vector2 = line[i]
			var q: Vector2 = line[i + 1]
			if maxf(p.x, q.x) < low.x or minf(p.x, q.x) > high.x or maxf(p.y, q.y) < low.y or minf(p.y, q.y) > high.y:
				continue
			var x0 := maxi(origin.x, floori(minf(p.x, q.x)) - pad)
			var x1 := mini(origin.x + CHUNK - 1, floori(maxf(p.x, q.x)) + pad)
			var y0 := maxi(origin.y, floori(minf(p.y, q.y)) - pad)
			var y1 := mini(origin.y + CHUNK - 1, floori(maxf(p.y, q.y)) + pad)
			for y in range(y0, y1 + 1):
				for x in range(x0, x1 + 1):
					var index := (y - origin.y) * CHUNK + (x - origin.x)
					if mask[index] == TRAIL_CELL:
						continue
					var c := Vector2(x + 0.5, y + 0.5)
					var distance := c.distance_to(Geometry2D.get_closest_point_to_segment(c, p, q))
					if distance <= TRAIL_HALF_WIDTH:
						mask[index] = TRAIL_CELL
					elif _cell_to_segment(Vector2i(x, y), p, q) <= PLAYER_RADIUS + 0.05:
						mask[index] = TRAIL_EDGE
					elif distance <= TRAIL_HALF_WIDTH + TRAIL_VERGE and mask[index] == 0:
						mask[index] = TRAIL_SIDE
	return mask


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


## Distância entre o quadrado de uma casa e o trecho de p a q (zero se ele
## passa por dentro da casa).
static func _cell_to_segment(cell: Vector2i, p: Vector2, q: Vector2) -> float:
	var rect := Rect2(Vector2(cell), Vector2.ONE)
	if rect.has_point(p) or rect.has_point(q):
		return 0.0
	var corners := [rect.position, rect.position + Vector2(1, 0), rect.end, rect.position + Vector2(0, 1)]
	var best := INF
	for i in 4:
		var c: Vector2 = corners[i]
		var d: Vector2 = corners[(i + 1) % 4]
		if Geometry2D.segment_intersects_segment(p, q, c, d) != null:
			return 0.0
		best = minf(best, c.distance_to(Geometry2D.get_closest_point_to_segment(c, p, q)))
	for e: Vector2 in [p, q]:
		best = minf(best, e.distance_to(Vector2(clampf(e.x, rect.position.x, rect.end.x), clampf(e.y, rect.position.y, rect.end.y))))
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

## Número entre 0 e 1, fixo para cada casa, rótulo e semente (ex.: a dureza
## de uma touceira de bambu).
func cell_random(cell: Vector2i, tag: String) -> float:
	return _random([cell.x, cell.y, tag])


## Número entre 0 e 1, fixo para cada chave e semente.
func _random(key: Array) -> float:
	var h := hash([world_seed] + key)
	return float(h & 0xFFFF) / 65535.0


func _warp(p: Vector2, amount: float) -> Vector2:
	return Vector2(_warp_noise.get_noise_2d(p.x, p.y), _warp_noise.get_noise_2d(p.x + 500.0, p.y - 500.0)) * amount
