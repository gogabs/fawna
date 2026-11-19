class_name Hydrology
extends RefCounted
## Bacias hidrográficas: de onde a água vem e para onde vai.
##
## Tudo é decidido por região (as mesmas regiões grandes do WorldGen) e é
## determinístico pela semente:
##  1. Cada região de terra tem uma altitude (a "terra" do clima, mais uma
##     pequena variação) e escoa para a vizinha mais baixa entre as 8 em volta.
##     Como sempre desce, nunca há ciclo: a água chega ao mar ou a um ponto sem
##     saída (uma bacia fechada).
##  2. Cada região dá uma vazão própria (chuva), maior onde é úmido. A vazão de
##     uma região soma a dela e a de todas as que escoam para ela.
##     Montanhas (as regiões mais altas) quase sempre têm nascente própria.
##  3. Onde a vazão passa de SPRING_Q existe rio. A primeira região rio abaixo
##     em que isso acontece é a nascente: o rio começa ali, com largura zero, e
##     vai alargando conforme as vazões se somam (afluentes viram um rio só).
##  4. Bacia fechada que recebe água vira lago, maior quanto maior a vazão.
##     Lagos não têm saída.
## O traçado de um rio vai do ponto de água de uma região ao da região para onde
## ela escoa, serpenteando, como as trilhas.

const SPRING_Q := 2.4  # vazão mínima para haver rio
const LAKE_Q := 1.0  # vazão mínima para uma bacia fechada virar lago
const UP_DEPTH := 8  # quantas regiões rio acima entram na soma da vazão
const NODE_SPREAD := 10.0  # casas: o ponto de água foge assim do meio da região
const SWAY := 6.0  # casas que o rio se afasta da reta, no máximo
const SWAY_FREQUENCY := 0.02
const SWAY_EASE := 10.0  # casas, perto das pontas, em que a curva some
const POINT_STEP := 1.0  # casas entre os pontos da linha de um rio
const MOUTH_REACH := 0.7  # fração do caminho até o meio da região de mar
const WIDTH_MIN := 1.0  # casas: largura de um riacho recém-nascido
const WIDTH_GAIN := 2.8  # casas por raiz da vazão acima de SPRING_Q
const WIDTH_MAX := 15.0  # casas (uns 22 m)
const LAKE_RADIUS_MIN := 6.0
const LAKE_RADIUS_BASE := 4.0
const LAKE_RADIUS_GAIN := 2.4
const LAKE_RADIUS_MAX := 18.0
const HEIGHT_ROUGHNESS := 0.2  # desempata regiões de altura igual
const RUNOFF_BASE := 0.9
const RUNOFF_HUMIDITY := 0.5
const RUNOFF_MAX := 1.5
const MOUNTAIN_SPRING_CHANCE := 0.85  # montanha com nascente própria
## Brejo (pântano): onde a água se acumula devagar.
const DELTA_Q := 5.0  # vazão da região para um rio grande abrir foz em brejo
const BASIN_HUMIDITY := -0.2  # bacia plana sem lago vira brejo se for minimamente úmida
const RIM_Q := 6.0  # vazão do lago para ele ter orla de brejo nas regiões vizinhas
const RIM_HUMIDITY := 0.1
const RIM_CHANCE := 0.6
const NO_DRAIN := Vector2i(1 << 30, 1 << 30)  # sem saída: bacia fechada
const NEIGHBORS: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0),
	Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]

var _world_ref: WeakRef
var _sway_noise := FastNoiseLite.new()
var _climate := {}  # região -> Vector3
var _heights := {}  # região -> float
var _drains := {}  # região -> região para onde escoa (ou NO_DRAIN)
var _flows := {}  # [região, profundidade] -> float
var _rivers := {}  # região -> [pontos, larguras] (ou vazio, se não há rio)
var _world: WorldGen:
	get:
		return _world_ref.get_ref()


func _init(world: WorldGen, noise_seed: int) -> void:
	_world_ref = weakref(world)
	_sway_noise.seed = noise_seed
	_sway_noise.frequency = SWAY_FREQUENCY
	_sway_noise.fractal_type = FastNoiseLite.FRACTAL_NONE


# --- Terreno -------------------------------------------------------------------

func _climate_of(region: Vector2i) -> Vector3:
	if not _climate.has(region):
		_climate[region] = _world.region_climate(region)
	return _climate[region]


func is_sea(region: Vector2i) -> bool:
	return _climate_of(region).x < WorldGen.SEA_LEVEL


## Altitude da região. O mar é o fundo de tudo; a região da Origem é o alto de
## tudo, para que nenhum rio chegue nela.
func height(region: Vector2i) -> float:
	if _heights.has(region):
		return _heights[region]
	var value: float
	if region == Vector2i.ZERO:
		value = 10.0
	elif is_sea(region):
		value = -10.0
	else:
		value = _climate_of(region).x + (_world.region_random(region, "altura") - 0.5) * 2.0 * HEIGHT_ROUGHNESS
	_heights[region] = value
	return value


## Região para onde esta escoa: a vizinha mais baixa, se for mais baixa que ela.
## NO_DRAIN se não há (bacia fechada). O mar não escoa para lugar nenhum.
func drain(region: Vector2i) -> Vector2i:
	if _drains.has(region):
		return _drains[region]
	var target := NO_DRAIN
	if not is_sea(region):
		var lowest := height(region)
		for offset in NEIGHBORS:
			var other: Vector2i = region + offset
			if height(other) < lowest:
				lowest = height(other)
				target = other
	_drains[region] = target
	return target


## Chuva da região (quanto de água ela mesma acrescenta). O mar e a Origem não.
func runoff(region: Vector2i) -> float:
	if region == Vector2i.ZERO or is_sea(region):
		return 0.0
	if _climate_of(region).x > WorldGen.MOUNTAIN_LEVEL \
			and _world.region_random(region, "nascente") < MOUNTAIN_SPRING_CHANCE:
		return SPRING_Q + 0.3  # a montanha tem nascente: sozinha já dá um rio
	var wet := clampf(RUNOFF_BASE + _climate_of(region).z * RUNOFF_HUMIDITY, 0.25, RUNOFF_MAX)
	return wet * (0.7 + 0.6 * _world.region_random(region, "chuva"))


## Vazão que passa pela região: a dela mais a das regiões que escoam para ela,
## olhando até UP_DEPTH regiões rio acima.
func discharge(region: Vector2i, depth := UP_DEPTH) -> float:
	var key := [region, depth]
	if _flows.has(key):
		return _flows[key]
	var total := runoff(region)
	if depth > 0:
		for offset in NEIGHBORS:
			var other: Vector2i = region + offset
			if not is_sea(other) and drain(other) == region:
				total += discharge(other, depth - 1)
	_flows[key] = total
	return total


func is_lake(region: Vector2i) -> bool:
	return not is_sea(region) and drain(region) == NO_DRAIN and discharge(region) >= LAKE_Q


func has_river(region: Vector2i) -> bool:
	return not is_sea(region) and drain(region) != NO_DRAIN and discharge(region) >= SPRING_Q


## Alguma região rio acima tem rio? Se não, esta é a da nascente.
func is_headwater(region: Vector2i) -> bool:
	for offset in NEIGHBORS:
		var other: Vector2i = region + offset
		if drain(other) == region and has_river(other):
			return false
	return true


static func width_for(flow: float) -> float:
	return clampf(WIDTH_MIN + WIDTH_GAIN * sqrt(maxf(flow - SPRING_Q, 0.0)), WIDTH_MIN, WIDTH_MAX)


func lake_radius(region: Vector2i) -> float:
	return clampf(LAKE_RADIUS_BASE + LAKE_RADIUS_GAIN * sqrt(discharge(region)), LAKE_RADIUS_MIN, LAKE_RADIUS_MAX)


# --- Traçado -------------------------------------------------------------------

static func _middle(region: Vector2i) -> Vector2:
	return Vector2(region) * WorldGen.REGION_SIZE + Vector2(0.5, 0.5)


## Ponto da região por onde a água passa. No lago é o meio dele.
func water_point(region: Vector2i) -> Vector2:
	if is_lake(region):
		return _middle(region)
	var offset := Vector2(_world.region_random(region, "agua_x") - 0.5, _world.region_random(region, "agua_y") - 0.5)
	return _middle(region) + offset * 2.0 * NODE_SPREAD


## Centro do lago da região, ou o meio dela se não há lago.
func lake_center(region: Vector2i) -> Vector2:
	return _middle(region)


## Linha do rio que sai desta região: [pontos (casas), largura em cada ponto].
## Vazio se a região não tem rio. O rio vai do ponto de água da região até o da
## vizinha para onde escoa (ao lago, o meio dele; ao mar, um trecho para dentro).
func river_line(region: Vector2i) -> Array:
	if _rivers.has(region):
		return _rivers[region]
	var line := []
	if has_river(region):
		line = _build_river(region)
	_rivers[region] = line
	return line


func _build_river(region: Vector2i) -> Array:
	var target := drain(region)
	var a := water_point(region)
	var b: Vector2
	var width_start := width_for(discharge(region))
	var width_end := width_start
	if is_sea(target):
		b = a.lerp(_middle(target), MOUTH_REACH)
	else:
		b = water_point(target)
		if has_river(target):
			width_end = maxf(width_start, width_for(discharge(target)))
	var headwater := is_headwater(region)
	var length := a.distance_to(b)
	var steps := maxi(1, ceili(length / POINT_STEP))
	var side := (b - a).normalized().orthogonal()
	var points := PackedVector2Array()
	var widths := PackedFloat32Array()
	for i in steps + 1:
		var t := float(i) / steps
		var s := a.lerp(b, t)
		var ease := smoothstep(0.0, 1.0, minf(t, 1.0 - t) * length / SWAY_EASE)
		points.append(s + side * _sway_noise.get_noise_2d(s.x, s.y) * SWAY * ease)
		var width := lerpf(width_start, width_end, t)
		if headwater:
			width *= smoothstep(0.0, 0.5, t)
		widths.append(width)
	return [points, widths]


# --- Brejo ---------------------------------------------------------------------

## A região é um pântano pela água? Três casos: a foz de um rio grande no mar
## (delta), uma bacia fechada plana, que não acumula água para virar lago, e a
## orla baixa de um lago grande. A Origem, o mar, as montanhas e os lagos em si
## ficam de fora; o resto do brejo vem do clima (WorldGen._pick_biome).
func is_wetland(region: Vector2i) -> bool:
	if region == Vector2i.ZERO or is_sea(region) or _climate_of(region).x > WorldGen.MOUNTAIN_LEVEL or is_lake(region):
		return false
	var humidity := _climate_of(region).z
	if drain(region) == NO_DRAIN:
		return humidity > BASIN_HUMIDITY
	if has_river(region) and discharge(region) >= DELTA_Q:
		for offset in NEIGHBORS:
			if is_sea(region + offset):
				return true
	if humidity > RIM_HUMIDITY and _world.region_random(region, "orla_brejo") < RIM_CHANCE:
		for offset: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var other: Vector2i = region + offset
			if is_lake(other) and discharge(other) >= RIM_Q and height(region) <= height(other) + 0.3:
				return true
	return false
