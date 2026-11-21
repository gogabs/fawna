class_name WorldGen
extends RefCounted
## Gera o mundo a partir de uma semente.
##
## A mesma semente e a mesma coordenada sempre geram o mesmo lugar, no servidor
## e em todos os clientes. Por isso o servidor só precisa guardar o que os
## jogadores mudaram; o resto é recalculado.
##
## O mundo é dividido em regiões grandes (REGION_SIZE casas de lado), cada uma
## com um único bioma. Os biomas vêm de um "clima" que muda devagar pelo mundo
## (temperatura, umidade e altura da terra), então regiões vizinhas costumam
## ser parecidas: bosques ao lado de bosques, o frio junto do frio, mares que
## se estendem por várias regiões. Algumas regiões têm uma feição que não
## muda o bioma, como as clareiras no meio das florestas. Dentro delas, as
## coisas são espalhadas de forma procedural, e só são calculadas quando
## alguém chega perto (em pedaços de CHUNK casas, guardados em cache). Cada
## região tem um ponto de encontro, e trilhas de terra ligam os pontos das
## regiões vizinhas. Quem entra pela primeira vez nasce no ponto de encontro
## da região (0, 0).

enum Biome { BOSQUE, PRADARIA, LAGOA, MAR, FLORESTA_GELADA, DESERTO_GELADO, BAMBUZAL, BREJO, MONTANHA }
## Feição de uma região: algo que muda o lugar sem mudar o bioma. Uma clareira
## continua sendo bosque (ou floresta gelada), só que aberta.
enum Feature { NENHUMA, CLAREIRA }
## Cobertura: o jeito mais simples de perguntar "aqui é mata fechada, campo
## aberto ou água?", juntando bioma e feição. É o que serve para achar as
## bordas entre floresta e campo (border_distance).
enum Cover { FECHADA, ABERTA, AGUA }
enum Thing { NADA, RIACHO, ARBUSTO, TRILHA, PONTE, LAGO, BAMBU, ARGILA, ARBUSTO_FRUTAS, PEDRAS, MAR, CHARCO, ARVORE, CIPO, FIBRA, SILEX, VAU, RIO }

const REGION_SIZE := 48  # casas (72 m)
const CHUNK := 16
const WORLD_LIMIT := 4096  # casas a partir do centro; além disso, fim do caminho
const TRAIL_HALF_WIDTH := 1.6  # casas: trilhas com uns 4,8 m de largura
const TRAIL_VERGE := 1.2  # casas além da trilha em que nada nasce (acostamento)
const TRAIL_STEP := 0.5  # casas entre os pontos da linha de uma trilha
const TRAIL_SWAY := 4.0  # casas que a trilha se afasta da reta, no máximo
const TRAIL_SWAY_EASE := 10.0  # casas, perto das pontas, em que a curva some
## Frequência do ruído que curva as trilhas: baixa, para cada trilha fazer no
## máximo uma ou duas curvas longas e suaves entre regiões, em vez de
## serpentear.
const TRAIL_BRIDGE_SEARCH := 12.0  # casas: até onde procurar uma travessia reta
const TRAIL_BRIDGE_EASE := 8  # pontos da linha (4 casas) soltos de cada lado da ponte
const TRAIL_BRIDGE_GAP := 6.0  # casas de terra entre duas águas que a mesma ponte atravessa
const TRAIL_BRIDGE_SPECK := 2.5  # casas: água menor que isso não ganha travessia
const TRAIL_DETOUR_MARGIN := 14  # casas em volta do trecho em que se procura a volta por terra
const TRAIL_BEND_FREQUENCY := 0.012
const TRAIL_CELL := 1  # na máscara de trilhas de um pedaço
const TRAIL_EDGE := 2
const TRAIL_SIDE := 3

const BIOME_NAMES := {
	Biome.BOSQUE: "bosque de micélio",
	Biome.PRADARIA: "pradaria de girassóis",
	Biome.LAGOA: "lagoa das vitórias-régias",
	Biome.MAR: "beira do mar",
	Biome.FLORESTA_GELADA: "floresta gelada",
	Biome.DESERTO_GELADO: "deserto gelado",
	Biome.BAMBUZAL: "bambuzal",
	Biome.BREJO: "brejo",
	Biome.MONTANHA: "montanha",
}

## Com preposição, para frases como "Você está no bosque".
const BIOME_IN := {
	Biome.BOSQUE: "no bosque de micélio",
	Biome.PRADARIA: "na pradaria de girassóis",
	Biome.LAGOA: "na lagoa das vitórias-régias",
	Biome.MAR: "na beira do mar",
	Biome.FLORESTA_GELADA: "na floresta gelada",
	Biome.DESERTO_GELADO: "no deserto gelado",
	Biome.BAMBUZAL: "no bambuzal",
	Biome.BREJO: "no brejo",
	Biome.MONTANHA: "na montanha",
}

## "clareira do bosque": a floresta em volta de uma clareira.
const BIOME_OF := {
	Biome.BOSQUE: "do bosque de micélio",
	Biome.FLORESTA_GELADA: "da floresta gelada",
	Biome.BAMBUZAL: "do bambuzal",
}

## Biomas de mata fechada (onde cabem clareiras) e o único que é só água.
## Os outros são campo aberto. Ver cover_of.
const FOREST_BIOMES := [Biome.BOSQUE, Biome.FLORESTA_GELADA, Biome.BAMBUZAL]
const COLD_BIOMES := [Biome.FLORESTA_GELADA, Biome.DESERTO_GELADO]

const THING_NAMES := {
	Thing.RIACHO: "riacho",
	Thing.VAU: "vau",
	Thing.RIO: "rio",
	Thing.ARBUSTO: "arbusto",
	Thing.TRILHA: "trilha",
	Thing.PONTE: "ponte",
	Thing.LAGO: "lagoa",
	Thing.BAMBU: "touceira de bambu",
	Thing.ARGILA: "argila",
	Thing.ARBUSTO_FRUTAS: "arbusto",
	Thing.PEDRAS: "pedras",
	Thing.MAR: "mar",
	Thing.CHARCO: "charco",
	Thing.ARVORE: "árvore",
	Thing.CIPO: "cipó",
	Thing.FIBRA: "fibra vegetal",
	Thing.SILEX: "sílex",
}

## Coisas que não deixam passar.
const BLOCKING := [Thing.RIACHO, Thing.RIO, Thing.LAGO, Thing.BAMBU, Thing.MAR, Thing.CHARCO, Thing.ARVORE]
## Água, de qualquer tipo.
const WATER := [Thing.RIACHO, Thing.VAU, Thing.RIO, Thing.LAGO, Thing.MAR, Thing.CHARCO]
## Chão por onde se anda: não são "coisas" para a fala listar.
const GROUND := [Thing.NADA, Thing.TRILHA, Thing.PONTE]

## Posições no mundo são contínuas, medidas em casas (1 casa = 1,5 m). A casa
## (x, y) cobre de x a x+1 e de y a y+1; norte é y negativo.
const METERS_PER_CELL := 1.5
const PLAYER_RADIUS := 0.3  # casas
const NO_CELL := Vector2i(-9999999, -9999999)

## Onde nascem os recursos coletáveis (shared/harvest.gd). Em vez de espalhados
## por igual, cada um tem o seu lugar, para dar para aprender onde procurar:
##
## - Arbustos (gravetos para lenha ou, raros, frutas) crescem na orla: a faixa
##   em que a mata fechada (Cover.FECHADA: bosque, floresta gelada, bambuzal)
##   encosta em campo aberto (Cover.ABERTA: pradaria, clareira, lagoa, brejo,
##   deserto gelado). Mais cheios do lado de dentro da mata, e ainda alguns
##   passos campo adentro. Longe da orla só há um ou outro arbusto perdido.
## - Bambu cresce em dois lugares: no bambuzal, onde é denso e fechado (toda
##   casa fora das trilhas é uma touceira: só se passa pelas trilhas ou abrindo
##   caminho com o machado, ver Harvest), e na beira da água, em moitas ao longo
##   das margens das lagoas, dos riachos e dos charcos do brejo.
##
## Biomas novos só precisam ter uma Cover (cover_of) para ganhar a orla.
## Até quantas casas da divisa entre regiões a orla é procurada.
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
const BUSH_STRAY_CHANCE := {
	Biome.BOSQUE: 0.002, Biome.PRADARIA: 0.004, Biome.LAGOA: 0.004, Biome.FLORESTA_GELADA: 0.004,
	Biome.DESERTO_GELADO: 0.002, Biome.BAMBUZAL: 0.002, Biome.BREJO: 0.008, Biome.MONTANHA: 0.003,
}
## Bambuzal: orla de BAMBOO_BAND casas, de BAMBOO_EDGE_CHANCE na divisa até
## BAMBOO_EDGE_FADE; no miolo, BAMBOO_INSIDE_CHANCE. Todas em 1,0: o bambuzal é
## uma parede contínua, sem frestas por onde uma criatura caiba.
const BAMBOO_BAND := 4.0
const BAMBOO_EDGE_CHANCE := 1.0
const BAMBOO_EDGE_FADE := 1.0
const BAMBOO_INSIDE_CHANCE := 1.0
## Bambu na beira da água: só onde o ruído das moitas deixa (mais ou menos
## metade das margens), para formar moitas com espaços entre elas. Nos lagos e
## rios, de BAMBOO_LAKE_FROM a BAMBOO_LAKE_TO casas além da margem (a argila fica
## mais perto da água); no brejo, na beira lamacenta dos charcos.
const BAMBOO_WATER_CHANCE := 0.11
const BAMBOO_LAKE_FROM := 1.0
const BAMBOO_LAKE_TO := 4.5
const BAMBOO_GROVE_FREQUENCY := 0.06
## Classe de cada casa para achar orlas (_biomes_around): mata, campo, água
## e bambuzal (que também é mata).
const EDGE_FOREST := 0
const EDGE_OPEN := 1
const EDGE_WATER := 2
const EDGE_GROVE := 3

## Clima: três ruídos lentos, medidos em regiões, decidem o bioma de cada
## uma. Como mudam devagar, as vizinhas saem parecidas.
##   terra: abaixo de SEA_LEVEL é mar; logo acima, se for úmido, é brejo;
##   temperatura: abaixo de COLD_LEVEL é o frio (floresta ou deserto gelado);
##   umidade: lado úmido dá mata (bosque, floresta gelada), lado seco dá
##   campo (pradaria, deserto gelado).
## CLIMATE_FREQUENCY é o tamanho das manchas: 0,09 dá zonas de clima com
## umas 5 a 6 regiões de largura.
const CLIMATE_FREQUENCY := 0.09
const SEA_LEVEL := -0.8
const MOUNTAIN_LEVEL := 0.95  # terra acima disso é montanha (uns 7% das regiões)
const MARSH_SHORE := 0.1  # faixa de terra baixa, acima do mar, que vira brejo
const MARSH_HUMIDITY := 0.9  # ou qualquer lugar úmido assim
const COLD_LEVEL := -0.55
const BAMBOO_LEVEL := 0.5  # no ruído próprio do bambuzal, dentro das matas
## Perto do centro do mundo o clima é sempre ameno e de terra firme: o frio e o mar
## ficam para quem se afasta. Até HOME_CALM regiões, terra e temperatura são
## as de casa; de lá até HOME_REACH vão se soltando. A umidade se solta logo
## (HOME_HUMID_REACH), para já haver bosque e campo ao redor do centro.
const HOME_CALM := 1.5
const HOME_REACH := 4.5
const HOME_HUMID_REACH := 2.0
const HOME_CLIMATE := Vector3(0.45, 0.35, -0.12)  # terra, temperatura, umidade
## Rios e lagos vêm das bacias hidrográficas (Hydrology). A margem do lago
## ondula com o ruído por LAKE_WOBBLE. Um rio de até VAU_WIDTH casas de largura
## é um vau, que se atravessa a pé; até STREAM_WIDTH é riacho e, acima disso,
## rio: esses bloqueiam, e as trilhas passam por ponte.
const LAKE_WOBBLE := 0.3
const VAU_WIDTH := 2.0
const STREAM_WIDTH := 6.0
const RIVER_MIN_WIDTH := 1.2  # casas: o mais fino que um rio se desenha
const WATER_REACH := 2  # regiões em volta do pedaço em que se procura água
const NO_WATER := 99.0  # "distância da margem" de quem está longe de qualquer água
## Clareiras: só no meio da floresta (pelo menos CLEARING_FOREST_AROUND das 4
## vizinhas também são mata do mesmo tipo de clima).
const CLEARING_CHANCE := 0.3
const CLEARING_FOREST_AROUND := 3
## Praia: faixa de areia, andável, entre a terra e a água do mar (casas,
## antes da ondulação). O mar em si não se atravessa.
const BEACH_WIDTH := 5.0
## Charcos do brejo: poças onde o ruído das margens passa deste nível.
const POOL_LEVEL := 0.3
const POOL_BANK := 0.12  # no mesmo ruído: a beira lamacenta da poça
const POOL_WET_BONUS := 0.12  # perto de rio ou lago, o nível baixa: mais poças
const POOL_WET_REACH := 8.0  # casas da margem
const STONE_WASTE_CHANCE := 0.012  # o deserto gelado é pedregoso
const STONE_MOUNTAIN_CHANCE := 0.02  # e a montanha mais ainda
## Árvores: o bosque é uma mata fechada. Em cada casa fora das trilhas há essa
## chance de ter uma árvore; derrubar a árvore deixa a casa livre para sempre.
const TREE_CHANCE := 0.72
## Fração dos arbustos que dá frutas em vez de gravetos: são raros (uns poucos
## por região).
const FRUIT_BUSH_CHANCE := 0.07
## Argila: só na beira da água. Chance por casa na margem das lagoas (até
## CLAY_BANK casas além da água) e na beira dos riachos.
const CLAY_BANK := 2.5
const CLAY_WATER_CHANCE := 0.07
## Pedras soltas: espalhadas pelo mundo todo, bem mais comuns na beira da
## água (riachos e lagoas), onde dão mais pedras pequenas (Harvest). Só nascem
## em casas que ficariam vazias, então o resto do mundo de cada semente não muda.
const STONE_CHANCE := 0.004
const STONE_WATER_CHANCE := 0.03
## Cipó e fibra vegetal: chance por casa vazia de mata fechada. O bosque é
## denso (as árvores ocupam a maior parte), então a chance é maior que na
## floresta gelada, que é aberta entre as árvores (FROZEN_FOREST_SCALE).
const VINE_CHANCE := 0.03
const FIBER_CHANCE := 0.04
const FROZEN_FOREST_SCALE := 0.2
## Sílex: nódulos soltos nos campos (por bioma) e, mais comuns, na beira da água.
const FLINT_CHANCE := {Biome.PRADARIA: 0.003, Biome.DESERTO_GELADO: 0.006, Biome.MONTANHA: 0.006}
const FLINT_WATER_CHANCE := 0.008
const WATERSIDE_BANK := 3.0  # casas além da margem da água

var world_seed: int
var _warp_noise := FastNoiseLite.new()  # entorta bordas de regiões
var _trail_noise := FastNoiseLite.new()  # curva as trilhas, devagar
var _hydro: Hydrology  # bacias: rios e lagos
var _water_chunks := {}  # Vector2i (pedaço) -> [margem de cada casa, tipo de água de cada casa]
var _lake_noise := FastNoiseLite.new()  # margem ondulada das lagoas
var _grove_noise := FastNoiseLite.new()  # moitas de bambu na beira da água
var _chunks := {}  # Vector2i (pedaço) -> [Thing de cada casa, Biome de cada casa]
var _climate_noise := FastNoiseLite.new()  # clima, medido em regiões
var _regions := {}  # Vector2i (região) -> Biome
var _features := {}  # Vector2i (região) -> Feature
var _landmarks := {}  # Vector2i (região) -> ponto de encontro
var _trail_lines := {}  # [região, vizinha] -> PackedVector2Array
## Casas ocupadas por construções (marco, fogueira): não deixam passar.
## Quem mantém é Builds; aqui só a colisão consulta. Vector2i -> id da obra.
var built := {}
## Casas de recursos que bloqueiam mas foram derrubadas ou recolhidas e deixam
## passar (árvores caídas, bambu aberto, ver Harvest). Quem mantém é Harvest;
## aqui só a colisão consulta. Vector2i -> true.
var cleared := {}
## Casas de coisas (árvores, arbustos, bambu) que uma obra arrancou de vez:
## viram chão livre. Quem mantém é Builds; Vector2i -> true.
var removed := {}


func _init(new_seed: int) -> void:
	world_seed = new_seed
	_warp_noise.seed = new_seed
	_warp_noise.frequency = 0.04
	_trail_noise.seed = new_seed + 3571
	_trail_noise.frequency = TRAIL_BEND_FREQUENCY
	_trail_noise.fractal_type = FastNoiseLite.FRACTAL_NONE  # sem zigue-zague miúdo
	_hydro = Hydrology.new(self, new_seed + 7919)
	_lake_noise.seed = new_seed + 104729
	_lake_noise.frequency = 0.15
	_grove_noise.seed = new_seed + 15485863
	_grove_noise.frequency = BAMBOO_GROVE_FREQUENCY
	_grove_noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	_climate_noise.seed = new_seed + 15485863
	_climate_noise.frequency = CLIMATE_FREQUENCY
	_climate_noise.fractal_octaves = 2


static func center() -> Vector2i:
	return Vector2i.ZERO


static func cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x), floori(pos.y))


static func cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell) + Vector2(0.5, 0.5)


## Ponto central do mundo (o ponto de encontro da região 0, 0), onde nasce
## quem entra pela primeira vez. Não é um lugar: nada o marca no mapa.
static func center_point() -> Vector2:
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
	var biome := _pick_biome(region)
	_regions[region] = biome
	return biome


## Clima de uma região: (terra, temperatura, umidade), cada um entre -1 e 1
## mais ou menos. Perto do centro, puxado para o clima de casa.
func region_climate(region: Vector2i) -> Vector3:
	var x := float(region.x)
	var y := float(region.y)
	var wild := Vector3(
		_climate_noise.get_noise_2d(x, y),
		_climate_noise.get_noise_2d(x + 1000.0, y - 1000.0),
		_climate_noise.get_noise_2d(x - 2000.0, y + 3000.0)) * 2.0
	var far := Vector2(region).length()
	var free := smoothstep(HOME_CALM, HOME_REACH, far)
	var humid_free := smoothstep(0.0, HOME_HUMID_REACH, far)
	return Vector3(
		lerpf(HOME_CLIMATE.x, wild.x, free),
		lerpf(HOME_CLIMATE.y, wild.y, free),
		lerpf(HOME_CLIMATE.z, wild.z, humid_free))


func _pick_biome(region: Vector2i) -> Biome:
	if region == Vector2i.ZERO:  # o centro do mundo fica sempre numa pradaria
		return Biome.PRADARIA
	var climate := region_climate(region)
	var land := climate.x
	var heat := climate.y
	var humidity := climate.z
	if land < SEA_LEVEL:
		return Biome.MAR
	if land > MOUNTAIN_LEVEL:
		return Biome.MONTANHA
	if heat < COLD_LEVEL:
		return Biome.FLORESTA_GELADA if humidity > 0.0 else Biome.DESERTO_GELADO
	if humidity > MARSH_HUMIDITY or (land < SEA_LEVEL + MARSH_SHORE and humidity > 0.0) or _hydro.is_wetland(region):
		return Biome.BREJO
	if _hydro.is_lake(region):
		return Biome.LAGOA
	if humidity > 0.0:
		var bamboo := _climate_noise.get_noise_2d(region.x * 2.0 + 5000.0, region.y * 2.0 + 5000.0) * 2.0
		return Biome.BAMBUZAL if bamboo > BAMBOO_LEVEL else Biome.BOSQUE
	return Biome.PRADARIA


## Feição da região. Hoje só há clareiras: regiões de bosque ou de floresta
## gelada, cercadas de mata, onde quase nada cresce.
func region_feature(region: Vector2i) -> Feature:
	if _features.has(region):
		return _features[region]
	var feature := Feature.NENHUMA
	var biome := region_biome(region)
	if (biome == Biome.BOSQUE or biome == Biome.FLORESTA_GELADA) and _random([region.x, region.y, "clareira"]) < CLEARING_CHANCE:
		var around := 0
		for next: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var other := region_biome(region + next)
			if FOREST_BIOMES.has(other) and COLD_BIOMES.has(other) == COLD_BIOMES.has(biome):
				around += 1
		if around >= CLEARING_FOREST_AROUND:
			feature = Feature.CLAREIRA
	_features[region] = feature
	return feature


## Mata fechada, campo aberto ou água? Clareiras contam como abertas.
func cover_of(region: Vector2i) -> Cover:
	var biome := region_biome(region)
	if biome == Biome.MAR:
		return Cover.AGUA
	if FOREST_BIOMES.has(biome) and region_feature(region) == Feature.NENHUMA:
		return Cover.FECHADA
	return Cover.ABERTA


func cover_at(cell: Vector2i) -> Cover:
	return cover_of(region_of(cell))


func feature_at(cell: Vector2i) -> Feature:
	return region_feature(region_of(cell))


## A casa fica em mata fechada (bosque, floresta gelada ou bambuzal, fora das
## clareiras)?
func is_forest(cell: Vector2i) -> bool:
	return cover_at(cell) == Cover.FECHADA


## A casa fica em campo aberto (pradaria, clareira, deserto gelado, lagoa,
## brejo)?
func is_open(cell: Vector2i) -> bool:
	return cover_at(cell) == Cover.ABERTA


## Nome do lugar para a fala: o bioma, ou "clareira" quando for uma.
func place_name(cell: Vector2i) -> String:
	if feature_at(cell) == Feature.CLAREIRA:
		return "clareira"
	return BIOME_NAMES[biome_at(cell)]


## O mesmo, com preposição: "no bosque de micélio", "numa clareira da
## floresta gelada".
func place_in(cell: Vector2i) -> String:
	var biome := biome_at(cell)
	if feature_at(cell) == Feature.CLAREIRA:
		return "numa clareira " + BIOME_OF[biome]
	return BIOME_IN[biome]


# --- Bordas entre regiões ------------------------------------------------------

## Distância (em casas) da casa até a região vizinha mais próxima cuja
## cobertura está em "covers", olhando as 8 vizinhas; INF se nenhuma delas
## serve. A própria região não conta. É assim que se acha a borda entre a
## floresta e o campo, por exemplo: numa casa de mata fechada,
## border_distance(casa, [Cover.ABERTA]) < 4 quer dizer "a até 4 casas de uma
## clareira, pradaria ou outro campo". Barato: não gera pedaços do mundo.
func border_distance(cell: Vector2i, covers: Array) -> float:
	return _border_distance(cell, func(region: Vector2i) -> bool: return covers.has(cover_of(region)))


## O mesmo, escolhendo as vizinhas pelo bioma.
func border_distance_to_biomes(cell: Vector2i, biomes: Array) -> float:
	return _border_distance(cell, func(region: Vector2i) -> bool: return biomes.has(region_biome(region)))


func _border_distance(cell: Vector2i, matches: Callable) -> float:
	# As mesmas contas de region_of, para a borda cair no mesmo lugar.
	var p := Vector2(cell) + _warp(Vector2(cell), 5.0)
	var u := p / REGION_SIZE + Vector2(0.5, 0.5)
	var region := Vector2i(floori(u.x), floori(u.y))
	var inside := (u - Vector2(region)) * REGION_SIZE  # de 0 a REGION_SIZE
	var best := INF
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var gap_x: float = 0.0 if dx == 0 else (inside.x if dx < 0 else REGION_SIZE - inside.x)
			var gap_y: float = 0.0 if dy == 0 else (inside.y if dy < 0 else REGION_SIZE - inside.y)
			var distance := Vector2(gap_x, gap_y).length()
			if distance < best and matches.call(region + Vector2i(dx, dy)):
				best = distance
	return best


# --- Casas ---------------------------------------------------------------------

func biome_at(cell: Vector2i) -> Biome:
	if not in_bounds(cell):
		return region_biome(region_of(cell))
	return _chunk_data(cell)[1][_chunk_index(cell)] as Biome


## Ponto de encontro da região: onde as trilhas se cruzam. Na região
## (0, 0), é o centro do mundo; nas outras, um ponto perto do centro da região.
## Nunca fica na água: se o sorteio cair num lago ou rio, o ponto vai para a
## terra firme mais próxima, para as trilhas não terminarem em cima de uma ponte.
func region_landmark(region: Vector2i) -> Vector2:
	if _landmarks.has(region):
		return _landmarks[region]
	var point := _raw_landmark(region)
	if region != Vector2i.ZERO and region_biome(region) != Biome.MAR and not _dry_around(point):
		point = _nearest_dry_point(point)
	_landmarks[region] = point
	return point


func _raw_landmark(region: Vector2i) -> Vector2:
	var middle := Vector2(region) * REGION_SIZE + Vector2(0.5, 0.5)
	if region == Vector2i.ZERO:
		return center_point()
	var spread := REGION_SIZE * 0.25
	var offset := Vector2(_random([region.x, region.y, "px"]) - 0.5, _random([region.x, region.y, "py"]) - 0.5)
	return middle + offset * 2.0 * spread


## Terra firme no ponto e numa casa em volta (cabe a trilha sem molhar).
func _dry_around(point: Vector2) -> bool:
	for offset: Vector2 in [Vector2.ZERO, Vector2(2, 0), Vector2(-2, 0), Vector2(0, 2), Vector2(0, -2)]:
		if _is_water_at(cell_of(point + offset)):
			return false
	return true


func _nearest_dry_point(point: Vector2) -> Vector2:
	for radius in range(1, 61):
		var best := Vector2.INF
		var best_distance := INF
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var candidate := Vector2(floorf(point.x) + dx + 0.5, floorf(point.y) + dy + 0.5)
				var distance := candidate.distance_to(point)
				if distance < best_distance and _dry_around(candidate):
					best = candidate
					best_distance = distance
		if best != Vector2.INF:
			return best
	return point


## Regiões ligadas por trilha a esta (as 4 vizinhas). É a base para achar
## caminhos: ir de ponto de encontro em ponto de encontro.
## As trilhas não entram no mar: uma região de mar não tem vizinhas, e
## ninguém a tem como vizinha.
func trail_neighbors(region: Vector2i) -> Array[Vector2i]:
	var linked: Array[Vector2i] = []
	for next: Vector2i in [region + Vector2i.UP, region + Vector2i.DOWN, region + Vector2i.LEFT, region + Vector2i.RIGHT]:
		if has_trail(region, next):
			linked.append(next)
	return linked


## Existe trilha entre estas duas regiões vizinhas? Só entre regiões de terra.
func has_trail(from: Vector2i, to: Vector2i) -> bool:
	return region_biome(from) != Biome.MAR and region_biome(to) != Biome.MAR


# --- Coisas --------------------------------------------------------------------

func thing_at(cell: Vector2i) -> Thing:
	if not in_bounds(cell) or removed.has(cell):
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
	return in_bounds(cell) and not built.has(cell) and (cleared.has(cell) or not BLOCKING.has(thing_at(cell)))


func is_trail(cell: Vector2i) -> bool:
	var thing := thing_at(cell)
	return thing == Thing.TRILHA or thing == Thing.PONTE


func _generate_chunk(chunk: Vector2i) -> Array:
	var things := PackedByteArray()
	var biomes := PackedByteArray()
	things.resize(CHUNK * CHUNK)
	biomes.resize(CHUNK * CHUNK)
	var origin := chunk * CHUNK
	var segments := _segments_near(origin + Vector2i.ONE * (CHUNK / 2))
	var trails := _trail_mask(origin, segments)
	var around := _edge_classes(origin)
	for y in CHUNK:
		for x in CHUNK:
			var cell := origin + Vector2i(x, y)
			things[y * CHUNK + x] = _compute_thing(cell, trails[y * CHUNK + x], around, x, y)
			biomes[y * CHUNK + x] = region_biome(region_of(cell))
	return [things, biomes]


func _compute_thing(cell: Vector2i, trail: int, around: PackedByteArray, x: int, y: int) -> Thing:
	var p := cell_center(cell)
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
	if biome == Biome.BOSQUE and cell_random(cell, "arvore") < TREE_CHANCE:
		return Thing.ARVORE
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
	if biome == Biome.DESERTO_GELADO:
		stone_chance = maxf(stone_chance, STONE_WASTE_CHANCE)
	elif biome == Biome.MONTANHA:
		stone_chance = maxf(stone_chance, STONE_MOUNTAIN_CHANCE)
	if cell_random(cell, "pedra") < stone_chance:
		return Thing.PEDRAS
	# Cipó e fibra só crescem nas matas fechadas; o sílex, nos campos e na beira
	# da água. Todos só ocupam casas que ficariam vazias, então o resto do mundo
	# de cada semente não muda.
	if cover_of(region) == Cover.FECHADA:
		var forest_scale := 1.0 if biome == Biome.BOSQUE else FROZEN_FOREST_SCALE
		if cell_random(cell, "cipo") < VINE_CHANCE * forest_scale:
			return Thing.CIPO
		if cell_random(cell, "fibra") < FIBER_CHANCE * forest_scale:
			return Thing.FIBRA
	var flint_chance: float = FLINT_CHANCE.get(biome, 0.0)
	if is_waterside(cell):
		flint_chance = maxf(flint_chance, FLINT_WATER_CHANCE)
	if flint_chance > 0.0 and cell_random(cell, "silex") < flint_chance:
		return Thing.SILEX
	return Thing.NADA


# --- Orlas: onde nascem arbustos e bambu ---------------------------------------

const AROUND_SIDE := CHUNK + 2 * EDGE_REACH
static var _edge_offsets: Array[Vector2i] = []  # vizinhas até EDGE_REACH, da mais perto à mais longe


## Classe (EDGE_*) de cada casa do pedaço e de uma moldura de EDGE_REACH casas
## em volta dele: é o que _edge_distance consulta, sem refazer a conta a cada casa.
func _edge_classes(origin: Vector2i) -> PackedByteArray:
	var around := PackedByteArray()
	around.resize(AROUND_SIDE * AROUND_SIDE)
	for y in AROUND_SIDE:
		for x in AROUND_SIDE:
			var region := region_of(origin + Vector2i(x - EDGE_REACH, y - EDGE_REACH))
			var kind := EDGE_OPEN
			match cover_of(region):
				Cover.FECHADA:
					kind = EDGE_GROVE if region_biome(region) == Biome.BAMBUZAL else EDGE_FOREST
				Cover.AGUA:
					kind = EDGE_WATER
			around[y * AROUND_SIDE + x] = kind
	return around


## Distância (em casas) da casa (x, y) do pedaço até a casa mais próxima cuja
## classe está em "kinds" (ou, com "outside", fora de "kinds"). INF se não há
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
	# pontas da vizinhança são iguais a esta, não há orla por perto.
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
	var here := around[(y + EDGE_REACH) * AROUND_SIDE + x + EDGE_REACH]
	if here == EDGE_FOREST:
		var distance := _edge_distance(around, x, y, [EDGE_OPEN])
		if distance <= BUSH_FOREST_BAND:
			return lerpf(BUSH_EDGE_CHANCE, BUSH_EDGE_FADE, (distance - 1.0) / (BUSH_FOREST_BAND - 1.0))
	elif here == EDGE_OPEN:
		if _edge_distance(around, x, y, [EDGE_FOREST, EDGE_GROVE]) <= BUSH_OPEN_BAND:
			return BUSH_OPEN_EDGE_CHANCE
	return BUSH_STRAY_CHANCE.get(biome, 0.0)


## Chance de uma touceira de bambu nascer na casa: na orla e no miolo do
## bambuzal, e em moitas na beira das lagoas, dos riachos e dos charcos.
func _bamboo_chance(cell: Vector2i, region: Vector2i, biome: Biome, around: PackedByteArray, x: int, y: int) -> float:
	if biome == Biome.BAMBUZAL:
		var distance := _edge_distance(around, x, y, [EDGE_GROVE], true)
		if distance <= BAMBOO_BAND:
			return lerpf(BAMBOO_EDGE_CHANCE, BAMBOO_EDGE_FADE, (distance - 1.0) / (BAMBOO_BAND - 1.0))
		return BAMBOO_INSIDE_CHANCE
	if biome == Biome.MAR or _grove_noise.get_noise_2d(cell.x, cell.y) < 0.0:
		return 0.0
	var shore := water_shore(cell)
	if shore >= BAMBOO_LAKE_FROM and shore < BAMBOO_LAKE_TO:
		return BAMBOO_WATER_CHANCE
	if biome == Biome.BREJO and _lake_noise.get_noise_2d(cell.x, cell.y) > _pool_level(cell) - POOL_BANK:
		return BAMBOO_WATER_CHANCE
	return 0.0


## A casa fica perto de um riacho ou da margem de uma lagoa? (As pedras daqui
## são mais miúdas, roladas pela água.)
func is_waterside(cell: Vector2i) -> bool:
	var biome := region_biome(region_of(cell))
	if biome == Biome.MAR:
		return true  # praia
	if biome == Biome.BREJO and _lake_noise.get_noise_2d(cell.x, cell.y) > _pool_level(cell) - POOL_BANK:
		return true
	return water_shore(cell) < WATERSIDE_BANK


## Barro na beira da água: margem dos lagos e dos rios, e beira dos charcos.
func _is_clay(cell: Vector2i, _region: Vector2i, biome: Biome) -> bool:
	if biome == Biome.MAR:
		return false  # na praia, só areia
	var roll := cell_random(cell, "argila")
	if roll >= CLAY_WATER_CHANCE:
		return false
	var shore := water_shore(cell)
	if shore >= 0.0 and shore < CLAY_BANK:
		return true
	return biome == Biome.BREJO and _lake_noise.get_noise_2d(cell.x, cell.y) > _pool_level(cell) - POOL_BANK


## Nível do ruído acima do qual há charco: mais baixo (mais poças) perto da água
## corrente, onde o brejo alaga.
func _pool_level(cell: Vector2i) -> float:
	return POOL_LEVEL - POOL_WET_BONUS if water_shore(cell) < POOL_WET_REACH else POOL_LEVEL


func _is_water(cell: Vector2i, _region: Vector2i, biome: Biome) -> Thing:
	if biome == Biome.MAR:
		return Thing.NADA if is_beach(cell) else Thing.MAR
	if biome == Biome.BREJO and _lake_noise.get_noise_2d(cell.x, cell.y) > _pool_level(cell):
		return Thing.CHARCO
	# Rios e lagos, das bacias. O centro do mundo não recebe água (ver Hydrology.height).
	return _hydro_water(cell)


## Distância (em casas) da casa até a margem da água dos rios e lagos: negativa
## dentro da água, NO_WATER longe de qualquer uma. Não conta mar nem charcos.
func water_shore(cell: Vector2i) -> float:
	return _water_chunk(cell)[0][_chunk_index(cell)]


## Que água (rio, lago) há na casa, vinda das bacias.
func _hydro_water(cell: Vector2i) -> Thing:
	var data := _water_chunk(cell)
	var index := _chunk_index(cell)
	if data[0][index] >= 0.0:
		return Thing.NADA
	if data[1][index] == 0:
		return Thing.LAGO
	var width: float = data[1][index]
	if width <= VAU_WIDTH:
		return Thing.VAU
	return Thing.RIACHO if width <= STREAM_WIDTH else Thing.RIO


## [margem, largura] de cada casa do pedaço da casa: a margem é a distância até
## a água mais próxima (negativa dentro dela); a largura, do rio mais perto (0
## se o mais perto é um lago). Guardado em cache.
func _water_chunk(cell: Vector2i) -> Array:
	var chunk := Vector2i(floori(float(cell.x) / CHUNK), floori(float(cell.y) / CHUNK))
	if not _water_chunks.has(chunk):
		_water_chunks[chunk] = _compute_water_chunk(chunk)
	return _water_chunks[chunk]


func _compute_water_chunk(chunk: Vector2i) -> Array:
	var shore := PackedFloat32Array()
	var width := PackedFloat32Array()
	shore.resize(CHUNK * CHUNK)
	shore.fill(NO_WATER)
	width.resize(CHUNK * CHUNK)
	var origin := chunk * CHUNK
	var box := Rect2(Vector2(origin), Vector2(CHUNK, CHUNK))
	var middle := Vector2(origin) + Vector2(CHUNK, CHUNK) * 0.5
	var here := Vector2i(roundi(middle.x / REGION_SIZE), roundi(middle.y / REGION_SIZE))
	for ry in range(here.y - WATER_REACH, here.y + WATER_REACH + 1):
		for rx in range(here.x - WATER_REACH, here.x + WATER_REACH + 1):
			var region := Vector2i(rx, ry)
			if _hydro.is_lake(region):
				_stamp_lake(region, box, origin, shore, width)
			var line := _hydro.river_line(region)
			if not line.is_empty():
				_stamp_river(line[0], line[1], box, origin, shore, width)
	return [shore, width]


func _stamp_lake(region: Vector2i, box: Rect2, origin: Vector2i, shore: PackedFloat32Array, width: PackedFloat32Array) -> void:
	var center := _hydro.lake_center(region)
	var radius := _hydro.lake_radius(region)
	var reach := radius * (1.0 + LAKE_WOBBLE) + WATERSIDE_BANK + 1.0
	if box.grow(reach).has_point(center) == false:
		return
	for y in CHUNK:
		for x in CHUNK:
			var cell := origin + Vector2i(x, y)
			var edge := cell_center(cell).distance_to(center) - radius * (1.0 + LAKE_WOBBLE * _lake_noise.get_noise_2d(cell.x, cell.y))
			if edge < shore[y * CHUNK + x]:
				shore[y * CHUNK + x] = edge
				width[y * CHUNK + x] = 0.0


func _stamp_river(points: PackedVector2Array, widths: PackedFloat32Array, box: Rect2, origin: Vector2i, shore: PackedFloat32Array, width: PackedFloat32Array) -> void:
	for i in points.size():
		var p := points[i]
		var half := maxf(widths[i], RIVER_MIN_WIDTH) * 0.5  # nem a nascente some entre as casas
		var reach := half + WATERSIDE_BANK + 1.0
		if not box.grow(reach).has_point(p):
			continue
		var x0 := maxi(floori(p.x - reach) - origin.x, 0)
		var x1 := mini(ceili(p.x + reach) - origin.x, CHUNK - 1)
		var y0 := maxi(floori(p.y - reach) - origin.y, 0)
		var y1 := mini(ceili(p.y + reach) - origin.y, CHUNK - 1)
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				var edge := cell_center(origin + Vector2i(x, y)).distance_to(p) - half
				if edge < shore[y * CHUNK + x]:
					shore[y * CHUNK + x] = edge
					width[y * CHUNK + x] = maxf(widths[i], 0.001)


## Praia: a faixa de areia de uma região de mar que encosta em terra firme.
## A largura ondula um pouco, para a costa não ser uma régua.
func is_beach(cell: Vector2i) -> bool:
	if region_biome(region_of(cell)) != Biome.MAR:
		return false
	var width := BEACH_WIDTH * (1.0 + 0.5 * _lake_noise.get_noise_2d(cell.x * 0.3, cell.y * 0.3))
	return border_distance(cell, [Cover.FECHADA, Cover.ABERTA]) < width


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
			for next: Vector2i in [region + Vector2i.RIGHT, region + Vector2i.DOWN]:
				if has_trail(region, next):
					segments.append(trail_line(region, next))
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
	# Sobre a água a trilha vira ponte: um trecho reto, sempre norte-sul ou
	# leste-oeste, nunca na diagonal.
	var line := PackedVector2Array()
	var i := 0
	while i < points.size():
		if not wet[i] or i == 0 or i == points.size() - 1:
			line.append(points[i])
			i += 1
			continue
		var last := i
		while last + 1 < points.size() - 1 and wet[last + 1]:
			last += 1
		if i == 1 and wet[0]:
			# Ponto de encontro na água: a ponte sai dele em linha reta.
			var from_landmark := _crossing_to_landmark(points[last + 1], points[0])
			if not from_landmark.is_empty():
				var skip := maxi(0, mini(TRAIL_BRIDGE_EASE, points.size() - 2 - (last + 1)))
				while skip > 0 and (_wet_length(from_landmark[0], points[last + 1 + skip]) > 0.0 or wet[last + 1 + skip]):
					skip -= 1
				line.append_array(from_landmark)
				i = last + 1 + skip
				continue
		var bridge := _straight_crossing(points[i - 1], points[last + 1])
		if bridge.is_empty() and points[i - 1].distance_to(points[last + 1]) > TRAIL_BRIDGE_SPECK:
			# Lago de borda torta: a trilha contorna pela terra até uma ponte reta.
			bridge = _detour_crossing(points[i - 1], points[last + 1])
		if bridge.is_empty():
			# Um respingo de água de uma ou duas casas: a trilha passa reto, é
			# só uma casa de ponte. Se for maior, cai no L (raro).
			if points[i - 1].distance_to(points[last + 1]) > TRAIL_BRIDGE_SPECK:
				bridge = _orthogonal_bridge(points[i - 1], points[last + 1])
			line.append_array(bridge)
			i = last + 1
			continue
		# A trilha em terra se curva até a ponte: solta uns pontos antes e
		# depois, para a mudança de direção ser aberta e não uma quina.
		var before := mini(TRAIL_BRIDGE_EASE, line.size() - 1)
		var after := maxi(0, mini(TRAIL_BRIDGE_EASE, points.size() - 2 - (last + 1)))
		while before > 0 and (_wet_length(line[line.size() - 1 - before], bridge[0]) > 0.0 or _is_water_at(cell_of(line[line.size() - 1 - before]))):
			before -= 1
		while after > 0 and (_wet_length(bridge[bridge.size() - 1], points[last + 1 + after]) > 0.0 or wet[last + 1 + after]):
			after -= 1
		line.resize(line.size() - before)
		line.append_array(bridge)
		i = last + 1 + after
	return line


## Travessia reta: em vez de manter as margens onde a diagonal da trilha
## tocou a água, procura perto dali uma linha só leste-oeste ou só norte-sul
## que cruze a água, pelo lugar mais estreito, e a trilha em terra faz a curva
## até lá. Devolve as duas margens da nova ponte, ou nada se não achar uma
## (margem de chegada na água, ou volta em terra que molhasse).
func _straight_crossing(from: Vector2, to: Vector2) -> PackedVector2Array:
	if _is_water_at(cell_of(to)):
		return _crossing_to_landmark(from, to)
	var best := PackedVector2Array()
	var best_score := INF
	var middle := (from + to) * 0.5
	for horizontal in [true, false]:
		var lo := (minf(from.y, to.y) if horizontal else minf(from.x, to.x)) - TRAIL_BRIDGE_SEARCH
		var hi := (maxf(from.y, to.y) if horizontal else maxf(from.x, to.x)) + TRAIL_BRIDGE_SEARCH
		var scan_lo := (minf(from.x, to.x) if horizontal else minf(from.y, to.y)) - TRAIL_BRIDGE_SEARCH
		var scan_hi := (maxf(from.x, to.x) if horizontal else maxf(from.y, to.y)) + TRAIL_BRIDGE_SEARCH
		var across := lo
		while across <= hi:
			# Água mais perto do meio do trecho, nesta fileira. Águas separadas por
			# uma faixa curta de terra contam como uma só: a ponte passa direto.
			var wet_start := NAN
			var wet_end := NAN
			var best_gap := INF
			var run_start := NAN
			var run_end := NAN
			var along := scan_lo
			var target := middle.x if horizontal else middle.y
			while along <= scan_hi + TRAIL_BRIDGE_GAP + TRAIL_STEP:
				var q := Vector2(along, across) if horizontal else Vector2(across, along)
				var wet := along <= scan_hi and _is_water_at(cell_of(q))
				if wet:
					if is_nan(run_start):
						run_start = along
					run_end = along
				elif not is_nan(run_start) and (along - run_end > TRAIL_BRIDGE_GAP or along > scan_hi):
					var centre := (run_start + run_end) * 0.5
					if absf(centre - target) < best_gap:
						best_gap = absf(centre - target)
						wet_start = run_start
						wet_end = run_end + TRAIL_STEP
					run_start = NAN
				along += TRAIL_STEP
			if not is_nan(wet_start):
				var a := Vector2(wet_start - 1.0, across) if horizontal else Vector2(across, wet_start - 1.0)
				var b := Vector2(wet_end + 0.5, across) if horizontal else Vector2(across, wet_end + 0.5)
				# Da margem de lá para cá: a ponte segue no sentido da trilha.
				if from.distance_to(a) > from.distance_to(b):
					var swap := a
					a = b
					b = swap
				var width := a.distance_to(b)
				var score := width + from.distance_to(a) + b.distance_to(to) + width * 0.0
				if score < best_score and _wet_length(from, a) == 0.0 and _wet_length(b, to) == 0.0 and not _is_water_at(cell_of(a)) and not _is_water_at(cell_of(b)):
					best_score = score
					best = PackedVector2Array([a, b])
			across += TRAIL_STEP
	return best


## Ponto de encontro na água: a ponte chega nele em linha reta, pela fileira
## ou pela coluna dele, vinda da margem mais próxima de "from". Devolve a
## margem de partida (a ponte vai dela até o ponto de encontro) ou nada.
func _crossing_to_landmark(from: Vector2, landmark: Vector2) -> PackedVector2Array:
	var best := PackedVector2Array()
	var best_length := INF
	for step: Vector2 in [Vector2(signf(from.x - landmark.x), 0.0), Vector2(0.0, signf(from.y - landmark.y))]:
		if step == Vector2.ZERO:
			continue
		var pos := landmark
		var walked := 0.0
		while walked <= TRAIL_BRIDGE_SEARCH * 2.0:
			if not _is_water_at(cell_of(pos)):
				var bank := pos + step
				if walked < best_length and _wet_length(from, bank) == 0.0:
					best_length = walked
					best = PackedVector2Array([bank])
				break
			pos += step * TRAIL_STEP
			walked += TRAIL_STEP
	return best


## Lago em que nenhuma reta sai direto de uma margem e chega na outra: acha, na
## terra em volta, a ponte reta (fileira ou coluna) que dá o menor caminho total
## de "from" até "to", contornando a água pela terra. Devolve os pontos entre
## os dois (volta em terra, as duas pontas da ponte, volta em terra), ou nada.
func _detour_crossing(from: Vector2, to: Vector2) -> PackedVector2Array:
	var lo := Vector2i(floori(minf(from.x, to.x)), floori(minf(from.y, to.y))) - Vector2i.ONE * TRAIL_DETOUR_MARGIN
	var hi := Vector2i(floori(maxf(from.x, to.x)), floori(maxf(from.y, to.y))) + Vector2i.ONE * TRAIL_DETOUR_MARGIN
	var water := {}
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			water[Vector2i(x, y)] = _is_water_at(Vector2i(x, y))
	var start := cell_of(from)
	var goal := cell_of(to)
	var from_map := _flood_dry(start, water)
	var to_map := _flood_dry(goal, water)
	var best_score := INF
	var best_a := Vector2i.ZERO
	var best_b := Vector2i.ZERO
	for horizontal in [true, false]:
		var outer_lo := lo.y if horizontal else lo.x
		var outer_hi := hi.y if horizontal else hi.x
		var inner_lo := lo.x if horizontal else lo.y
		var inner_hi := hi.x if horizontal else hi.y
		for outer in range(outer_lo, outer_hi + 1):
			var run_start := -999999
			for inner in range(inner_lo, inner_hi + 2):
				var cell := Vector2i(inner, outer) if horizontal else Vector2i(outer, inner)
				var is_wet: bool = inner <= inner_hi and water[cell]
				if is_wet:
					if run_start == -999999:
						run_start = inner
					continue
				if run_start == -999999:
					continue
				var before := Vector2i(run_start - 1, outer) if horizontal else Vector2i(outer, run_start - 1)
				var after := Vector2i(inner, outer) if horizontal else Vector2i(outer, inner)
				run_start = -999999
				if not water.has(before) or water[before] or inner > inner_hi:
					continue
				for pair: Array in [[before, after], [after, before]]:
					var near: Vector2i = pair[0]
					var far: Vector2i = pair[1]
					if from_map.has(near) and to_map.has(far):
						var score: float = from_map[near][1] + to_map[far][1] + near.distance_to(far)
						if score < best_score:
							best_score = score
							best_a = near
							best_b = far
	if best_score == INF:
		return PackedVector2Array()
	var result := _simplify_path(from, _chain(from_map, best_a, true))
	if result.is_empty() or result[result.size() - 1] != cell_center(best_a):
		result.append(cell_center(best_a))
	var back := _simplify_path(cell_center(best_b), _chain(to_map, best_b, false))
	result.append(cell_center(best_b))
	if back.size() > 1:
		back.resize(back.size() - 1)  # a última é a casa de "to", que a linha já tem
		result.append_array(back)
	return result


## Terra firme alcançável a partir de "start" (8 vizinhos), dentro de "water":
## Vector2i -> [casa anterior, passos].
func _flood_dry(start: Vector2i, water: Dictionary) -> Dictionary:
	var seen := {start: [start, 0.0]}
	var queue: Array[Vector2i] = [start]
	var head := 0
	while head < queue.size():
		var cell := queue[head]
		head += 1
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var next := cell + Vector2i(dx, dy)
				if (dx == 0 and dy == 0) or seen.has(next) or not water.has(next) or water[next]:
					continue
				seen[next] = [cell, (seen[cell][1] as float) + Vector2(dx, dy).length()]
				queue.append(next)
	return seen


## Casas do caminho de "cell" de volta até a origem do mapa, na ordem de ida
## (se "reverse") ou de volta.
func _chain(map: Dictionary, cell: Vector2i, reverse: bool) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [cell]
	while map[cell][0] != cell:
		cell = map[cell][0]
		cells.append(cell)
	if reverse:
		cells.reverse()
	return cells


## Alisa o caminho em casas: do ponto "origin", pula direto para a casa mais
## longe que ainda se alcança em linha reta sem molhar.
func _simplify_path(origin: Vector2, cells: Array[Vector2i],) -> PackedVector2Array:
	var result := PackedVector2Array()
	var at := origin
	var index := 0
	while index < cells.size() - 1:
		var far := index + 1
		for k in range(cells.size() - 1, index, -1):
			if _wet_length(at, cell_center(cells[k])) == 0.0:
				far = k
				break
		at = cell_center(cells[far])
		index = far
		result.append(at)
	return result


## Ponte ortogonal entre a última margem seca "from" e a próxima "to" (ou o
## ponto de encontro, se ele estiver na água): um trecho leste-oeste e outro
## norte-sul, em L, com a quina onde houver mais água. Devolve a quina a
## acrescentar à linha entre as duas, ou nada se os dois já estão alinhados.
func _orthogonal_bridge(from: Vector2, to: Vector2) -> PackedVector2Array:
	if is_equal_approx(from.x, to.x) or is_equal_approx(from.y, to.y):
		return PackedVector2Array()
	var east_west_first := Vector2(to.x, from.y)
	var north_south_first := Vector2(from.x, to.y)
	var first := east_west_first
	if absf(to.x - from.x) < absf(to.y - from.y):
		first = north_south_first
	# A quina que deixa mais da ponte sobre a água, e menos sobre a terra.
	var wet_a := _wet_length(from, east_west_first) + _wet_length(east_west_first, to)
	var wet_b := _wet_length(from, north_south_first) + _wet_length(north_south_first, to)
	if wet_a > wet_b:
		first = east_west_first
	elif wet_b > wet_a:
		first = north_south_first
	return PackedVector2Array([first])


## Quanto da reta de "a" a "b" passa sobre a água, em casas (aproximado).
func _wet_length(a: Vector2, b: Vector2) -> float:
	var steps := maxi(1, ceili(a.distance_to(b) / TRAIL_STEP))
	var wet := 0
	for i in steps + 1:
		if _is_water_at(cell_of(a.lerp(b, float(i) / steps))):
			wet += 1
	return wet * a.distance_to(b) / steps


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


## O ponto livre mais perto de "pos" (procura em anéis de meia casa). Devolve
## o próprio "pos" se já está livre ou se não achou nada num raio de 4 casas.
func nearest_free(pos: Vector2) -> Vector2:
	if is_free(pos):
		return pos
	var best := pos
	var best_distance := INF
	for ring in range(1, 8):
		for dx in range(-ring, ring + 1):
			for dy in range(-ring, ring + 1):
				var point := pos + Vector2(dx, dy) * 0.5
				var distance := point.distance_to(pos)
				if distance < best_distance and is_free(point):
					best_distance = distance
					best = point
		if best_distance < INF:
			break
	return best


# --- Aleatório fixo ------------------------------------------------------------

## Número entre 0 e 1, fixo para cada casa, rótulo e semente (ex.: a dureza
## de uma touceira de bambu).
func cell_random(cell: Vector2i, tag: String) -> float:
	return _random([cell.x, cell.y, tag])


## Número entre 0 e 1, fixo para cada chave e semente.
## Sorteio fixo de uma região, por assunto (ver Hydrology).
func region_random(region: Vector2i, tag: String) -> float:
	return _random([region.x, region.y, tag])


func _random(key: Array) -> float:
	var h := hash([world_seed] + key)
	return float(h & 0xFFFF) / 65535.0


func _warp(p: Vector2, amount: float) -> Vector2:
	return Vector2(_warp_noise.get_noise_2d(p.x, p.y), _warp_noise.get_noise_2d(p.x + 500.0, p.y - 500.0)) * amount
