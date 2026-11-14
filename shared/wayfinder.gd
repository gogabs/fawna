class_name Wayfinder
extends RefCounted
## Acha rotas pelas trilhas, estradas e pontes até um destino.
##
## É a parte lógica do Caminheiro (o cristal que brilha azul na direção que o
## coração manda): não toca som nem fala, só devolve "beacons", os pontos
## onde a rota faz curva. Quem usa vai de beacon em beacon.
##
## Como funciona:
##   1. Se a criatura está fora de uma trilha, o primeiro trecho é o caminho
##      mais rápido (desviando do que bloqueia) até a trilha mais próxima.
##   2. Entre as regiões, a rota segue o grafo de pontos de encontro
##      (WorldGen.region_landmark e trail_neighbors), o caminho mais curto.
##   3. Cada trecho entre pontos de encontro é traçado casa a casa (A*) por
##      cima das trilhas. Sair da trilha custa caro, mas é permitido, para
##      atravessar trechos sem trilha (como a clareira em volta da vila).
##   4. O caminho casa a casa é simplificado: sobram só as curvas, e trechos
##      retos muito longos ganham beacons no meio.
##
## Os trechos são traçados aos poucos (um por vez), para um destino distante
## não travar o jogo: next_beacon() calcula o próximo quando precisa.

const OFF_TRAIL_COST := 4.0  # andar fora da trilha custa 4x mais
const DIAGONAL := 1.41421356
const LEG_MARGIN := 16  # casas em volta de cada trecho onde o A* procura
const WIDE_MARGIN := 40  # se não achou, tenta de novo com mais folga
const TRAIL_SEARCH_RADIUS := 20  # casas: até onde procura uma trilha próxima
const SIMPLIFY_TOLERANCE := 0.9  # casas: desvio que ainda conta como reta
const MAX_SEGMENT := 20.0  # casas (30 m) no máximo entre dois beacons
const CLEAR_RADIUS := 0.2  # folga ao conferir se uma reta passa livre

var world: WorldGen
var destination := Vector2.ZERO
## Distância aproximada (em casas) da rota inteira, contada no começo.
var estimated_length := 0.0

var _beacons: Array[Vector2] = []  # já traçados, ainda não alcançados
var _targets: Array[Vector2] = []  # próximos pontos de encontro até o destino
var _cursor := Vector2.ZERO  # onde termina o que já foi traçado


func _init(new_world: WorldGen) -> void:
	world = new_world


## Planeja a rota de "from" até "to". Devolve false se não há rota.
func plan(from: Vector2, to: Vector2) -> bool:
	destination = to
	_beacons.clear()
	_targets.clear()
	_cursor = from
	estimated_length = 0.0
	if from.distance_to(to) <= MAX_SEGMENT * 0.5 and _line_is_clear(from, to):
		_beacons.append(to)
		estimated_length = from.distance_to(to)
		return true
	# 1. Fora da trilha: primeiro, até a trilha mais próxima.
	if not world.is_trail(WorldGen.cell_of(from)):
		var path := nearest_trail_path(from)
		if path.size() > 0:
			var entry := WorldGen.cell_center(path[path.size() - 1])
			var points := simplify(path, from, entry)
			_beacons.append_array(points)
			estimated_length += _length(from, points)
			_cursor = entry
	# 2. Rota entre regiões.
	var regions := region_route(world.region_of(WorldGen.cell_of(_cursor)), world.region_of(WorldGen.cell_of(to)))
	var last := _cursor
	for i in range(1, regions.size()):
		var landmark := world.region_landmark(regions[i])
		if landmark.distance_to(to) > 2.0:
			_targets.append(landmark)
			estimated_length += last.distance_to(landmark)
			last = landmark
	_targets.append(to)
	estimated_length += last.distance_to(to)
	return _extend()


func is_done() -> bool:
	return _beacons.is_empty() and _targets.is_empty()


## O beacon atual (o próximo ponto a alcançar), traçando mais se precisar.
func current() -> Variant:
	if _beacons.is_empty() and not _extend():
		return null
	return _beacons[0] if not _beacons.is_empty() else null


## Alcançou o beacon atual: passa para o próximo. Devolve o novo beacon, ou
## null se chegou ao destino.
func next_beacon() -> Variant:
	if not _beacons.is_empty():
		_beacons.remove_at(0)
	return current()


## Os beacons já traçados (para a tela e para os testes).
func pending() -> Array[Vector2]:
	return _beacons.duplicate()


## Traça a rota inteira de uma vez (testes e depuração).
func full_route() -> Array[Vector2]:
	while not _targets.is_empty():
		if not _extend():
			break
	return _beacons.duplicate()


## Traça o próximo trecho, até o próximo ponto de encontro.
func _extend() -> bool:
	while not _targets.is_empty():
		var target := _reachable(_targets.pop_front())
		var path := cell_path(_cursor, target)
		if path.is_empty():
			return false
		var points := simplify(path, _cursor, target)
		_cursor = target
		if not points.is_empty():
			_beacons.append_array(points)
			return true
	return not _beacons.is_empty()


## Um ponto de encontro pode cair na água ou numa árvore (a trilha passa
## perto dele, mas não exatamente nele): usa a trilha mais próxima.
func _reachable(target: Vector2) -> Vector2:
	if world.is_passable(WorldGen.cell_of(target)):
		return target
	var trail := world.nearest_trail(target, 4)
	return WorldGen.cell_center(trail) if trail != WorldGen.NO_CELL else target


# --- Busca ---------------------------------------------------------------------

## Caminho mais rápido (casas, a primeira é a de "from") até a trilha mais
## próxima, desviando do que bloqueia. Vazio se não há trilha por perto.
func nearest_trail_path(from: Vector2) -> Array[Vector2i]:
	var start := WorldGen.cell_of(from)
	var heap := _Heap.new()
	var cost := {start: 0.0}
	var came := {}
	heap.push(start, 0.0)
	while not heap.is_empty():
		var cell: Vector2i = heap.pop()
		if world.is_trail(cell) and world.thing_at(cell) != WorldGen.Thing.VILA:
			return _rebuild(came, cell)
		for step in _neighbors(cell):
			var next: Vector2i = step[0]
			if absi(next.x - start.x) > TRAIL_SEARCH_RADIUS or absi(next.y - start.y) > TRAIL_SEARCH_RADIUS:
				continue
			var new_cost: float = cost[cell] + step[1]
			if new_cost < cost.get(next, INF):
				cost[next] = new_cost
				came[next] = cell
				heap.push(next, new_cost)
	return []


## Caminho casa a casa (A*) de "from" até "to", preferindo trilhas.
func cell_path(from: Vector2, to: Vector2) -> Array[Vector2i]:
	for margin in [LEG_MARGIN, WIDE_MARGIN]:
		var path := _astar(WorldGen.cell_of(from), WorldGen.cell_of(to), margin)
		if not path.is_empty():
			return path
	return []


func _astar(start: Vector2i, goal: Vector2i, margin: int) -> Array[Vector2i]:
	var low := Vector2i(mini(start.x, goal.x), mini(start.y, goal.y)) - Vector2i.ONE * margin
	var high := Vector2i(maxi(start.x, goal.x), maxi(start.y, goal.y)) + Vector2i.ONE * margin
	var heap := _Heap.new()
	var cost := {start: 0.0}
	var came := {}
	var closed := {}
	heap.push(start, 0.0)
	while not heap.is_empty():
		var cell: Vector2i = heap.pop()
		if cell == goal:
			return _rebuild(came, cell)
		if closed.has(cell):
			continue
		closed[cell] = true
		for step in _neighbors(cell):
			var next: Vector2i = step[0]
			if next.x < low.x or next.y < low.y or next.x > high.x or next.y > high.y:
				continue
			var weight: float = step[1] * (1.0 if world.is_trail(next) else OFF_TRAIL_COST)
			var new_cost: float = cost[cell] + weight
			if new_cost < cost.get(next, INF):
				cost[next] = new_cost
				came[next] = cell
				heap.push(next, new_cost + Vector2(next - goal).length())
	return []


## Vizinhas passáveis em 8 direções: [casa, distância]. Na diagonal, só se
## as duas casas do lado também forem livres (não corta quina de árvore).
func _neighbors(cell: Vector2i) -> Array:
	var result := []
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var next := cell + Vector2i(dx, dy)
			if not world.is_passable(next):
				continue
			if dx != 0 and dy != 0:
				if not world.is_passable(cell + Vector2i(dx, 0)) or not world.is_passable(cell + Vector2i(0, dy)):
					continue
				result.append([next, DIAGONAL])
			else:
				result.append([next, 1.0])
	return result


static func _rebuild(came: Dictionary, cell: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [cell]
	while came.has(cell):
		cell = came[cell]
		path.push_front(cell)
	return path


## Caminho mais curto entre regiões, de ponto de encontro em ponto de
## encontro (Dijkstra). Inclui a região de partida e a de chegada.
func region_route(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var low := Vector2i(mini(from.x, to.x), mini(from.y, to.y)) - Vector2i.ONE
	var high := Vector2i(maxi(from.x, to.x), maxi(from.y, to.y)) + Vector2i.ONE
	var heap := _Heap.new()
	var cost := {from: 0.0}
	var came := {}
	heap.push(from, 0.0)
	while not heap.is_empty():
		var region: Vector2i = heap.pop()
		if region == to:
			return _rebuild(came, region)
		var here := world.region_landmark(region)
		for next in world.trail_neighbors(region):
			if next.x < low.x or next.y < low.y or next.x > high.x or next.y > high.y:
				continue
			var new_cost: float = cost[region] + here.distance_to(world.region_landmark(next))
			if new_cost < cost.get(next, INF):
				cost[next] = new_cost
				came[next] = region
				heap.push(next, new_cost)
	return [from]


# --- Simplificação -------------------------------------------------------------

## Reduz um caminho casa a casa às curvas. Devolve os beacons depois de
## "from", sempre terminando em "to".
func simplify(path: Array[Vector2i], from: Vector2, to: Vector2) -> Array[Vector2]:
	var points: Array[Vector2] = [from]
	for i in range(1, path.size() - 1):
		points.append(WorldGen.cell_center(path[i]))
	points.append(to)
	var keep := {0: true, points.size() - 1: true}
	_douglas_peucker(points, 0, points.size() - 1, keep)
	var indices := keep.keys()
	indices.sort()
	var result: Array[Vector2] = []
	var previous := from
	for k in range(1, indices.size()):
		var point: Vector2 = points[indices[k]]
		# Retas compridas ganham beacons no meio, para o batimento não ficar
		# longe demais.
		var pieces := ceili(previous.distance_to(point) / MAX_SEGMENT)
		for j in range(1, pieces):
			result.append(previous.lerp(point, float(j) / pieces))
		result.append(point)
		previous = point
	return result


func _douglas_peucker(points: Array[Vector2], first: int, last: int, keep: Dictionary) -> void:
	if last - first < 2:
		return
	var worst := -1
	var worst_distance := -1.0
	for i in range(first + 1, last):
		var closest := Geometry2D.get_closest_point_to_segment(points[i], points[first], points[last])
		var distance := points[i].distance_to(closest)
		if distance > worst_distance:
			worst_distance = distance
			worst = i
	if worst_distance <= SIMPLIFY_TOLERANCE and _line_is_clear(points[first], points[last]):
		return
	if worst_distance <= SIMPLIFY_TOLERANCE:
		worst = (first + last) / 2  # reta bloqueada: divide no meio
	keep[worst] = true
	_douglas_peucker(points, first, worst, keep)
	_douglas_peucker(points, worst, last, keep)


## Dá para ir em linha reta de "a" a "b" sem esbarrar em nada?
func _line_is_clear(a: Vector2, b: Vector2) -> bool:
	var samples := ceili(a.distance_to(b) / 0.25)
	for i in range(1, samples):
		if not world.is_free(a.lerp(b, float(i) / samples), CLEAR_RADIUS):
			return false
	return true


static func _length(from: Vector2, points: Array[Vector2]) -> float:
	var total := 0.0
	var previous := from
	for point in points:
		total += previous.distance_to(point)
		previous = point
	return total


## Fila de prioridade simples (heap binário), menor prioridade primeiro.
class _Heap:
	var _items: Array = []  # [prioridade, valor]

	func is_empty() -> bool:
		return _items.is_empty()

	func push(value: Variant, priority: float) -> void:
		_items.append([priority, value])
		var i := _items.size() - 1
		while i > 0:
			var parent := (i - 1) / 2
			if _items[parent][0] <= _items[i][0]:
				break
			var swap = _items[parent]
			_items[parent] = _items[i]
			_items[i] = swap
			i = parent

	func pop() -> Variant:
		var top = _items[0][1]
		var last = _items.pop_back()
		if not _items.is_empty():
			_items[0] = last
			var i := 0
			var count := _items.size()
			while true:
				var smallest := i
				for child in [2 * i + 1, 2 * i + 2]:
					if child < count and _items[child][0] < _items[smallest][0]:
						smallest = child
				if smallest == i:
					break
				var swap = _items[smallest]
				_items[smallest] = _items[i]
				_items[i] = swap
				i = smallest
		return top
