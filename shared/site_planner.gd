class_name SitePlanner
extends RefCounted
## Onde construir uma construção grande, sem precisar ver o terreno.
##
## O lugar se escolhe por âncoras, nesta ordem:
##   1. Quadrantes da região (nordeste, noroeste, sudeste, sudoeste), mais as
##      construções que já existem nela. Cada um diz o que tem: obstáculos que
##      não dá para tirar (lago, riacho, mar, charco), obstáculos que dá para
##      arrancar (árvores, arbustos, bambu) e a maior área contínua livre.
##      Os quadrantes vêm da região, não do marco, que pode estar na borda.
##   2. Dentro de um quadrante: os 4 cantos dele e o redor de cada obstáculo
##      intransponível (ao norte, ao sul, a leste e a oeste dele).
##      Dentro de uma construção: ao norte, ao sul, a leste e a oeste dela, com
##      a distância de caminhar entre as duas (Builds.SPACING).
##   3. O tamanho (da menor à maior que cabe) e a porta (norte, sul, leste, oeste).
##
## Uma âncora é um canto fixo e uma direção (dx, dy, cada uma 1 ou -1): a
## construção cresce a partir do canto, nessa direção.
##
## Tudo aqui só lê o mundo e as obras (cliente e servidor calculam igual).

## Maior lado que se procura (em casas) ao medir uma área.
const SCAN := 14
## Quantas casas, no máximo, se anda na diagonal procurando uma casa válida
## quando o canto da âncora está ocupado.
const PIN_STEPS := 6

const WATER_NAMES := {
	WorldGen.Thing.LAGO: "lago", WorldGen.Thing.RIACHO: "riacho", WorldGen.Thing.RIO: "rio", WorldGen.Thing.VAU: "vau",
	WorldGen.Thing.MAR: "mar", WorldGen.Thing.CHARCO: "charco",
}
const CLEAR_NAMES := {
	WorldGen.Thing.ARVORE: "árvores", WorldGen.Thing.BAMBU: "bambu",
	WorldGen.Thing.ARBUSTO: "arbustos", WorldGen.Thing.ARBUSTO_FRUTAS: "arbustos",
}
## Como a fala diz o que acabou de ser arrancado.
const CLEAR_THING_TEXT := {
	WorldGen.Thing.ARVORE: "a árvore", WorldGen.Thing.BAMBU: "a touceira de bambu",
	WorldGen.Thing.ARBUSTO: "o arbusto", WorldGen.Thing.ARBUSTO_FRUTAS: "o arbusto com frutas",
}
const QUADRANTS := {
	"nordeste": Vector2i(1, -1), "noroeste": Vector2i(-1, -1),
	"sudeste": Vector2i(1, 1), "sudoeste": Vector2i(-1, 1),
}


## Caixa (em casas) de um quadrante da região.
static func quadrant_box(region: Vector2i, quadrant: String) -> Rect2i:
	var half := WorldGen.REGION_SIZE / 2
	var center := region * WorldGen.REGION_SIZE
	var dir: Vector2i = QUADRANTS[quadrant]
	var x := center.x if dir.x > 0 else center.x - half
	var y := center.y if dir.y > 0 else center.y - half
	return Rect2i(x, y, half, half)


## O quadrado de lado "size" com um canto em "corner", crescendo em "dir".
static func rect_for(corner: Vector2i, dir: Vector2i, size: int) -> Rect2i:
	var x := corner.x if dir.x > 0 else corner.x - size + 1
	var y := corner.y if dir.y > 0 else corner.y - size + 1
	return Rect2i(x, y, size, size)


## Metros de um número de casas, para falar: 6 casas, "9 metros".
static func meters_text(cells: int) -> String:
	var meters := float(cells) * WorldGen.METERS_PER_CELL
	var text := str(snappedf(meters, 0.1))
	if text.ends_with(".0"):
		text = text.trim_suffix(".0")
	return text.replace(".", ",")


static func area_text(area: Vector2i) -> String:
	return "%s por %s metros" % [meters_text(area.x), meters_text(area.y)]


# --- Quadrantes e estruturas -------------------------------------------------------

## Os 4 quadrantes da região, na ordem nordeste, noroeste, sudeste, sudoeste.
## Cada um: { "id", "name", "box", "water": [nomes], "clear": [nomes],
## "area": Vector2i (casas, só chão livre), "area_loose": Vector2i (com o que dá
## para arrancar), "fits": cabe a menor construção grande?, "text" }.
static func quadrants(builds: Builds, region: Vector2i, min_size := 3) -> Array:
	var out := []
	for id: String in QUADRANTS:
		var box := quadrant_box(region, id)
		var water := {}
		var clear := {}
		var grid := []  # linhas de status por casa
		for y in range(box.position.y, box.end.y):
			var row := []
			for x in range(box.position.x, box.end.x):
				var cell := Vector2i(x, y)
				var status := builds.cell_status(cell, region)
				row.append(status)
				if status == Builds.WATER:
					water[WATER_NAMES.get(builds.world.thing_at(cell), "água")] = true
				elif status == Builds.CLEARABLE:
					clear[CLEAR_NAMES.get(builds.world.thing_at(cell), "mata")] = true
			grid.append(row)
		var strict := _largest_rect(grid_to_free(grid, false))
		var loose := _largest_rect(grid_to_free(grid, true))
		var quadrant := {"id": id, "name": id.capitalize(), "box": box, "water": water.keys(), "clear": clear.keys(),
			"area": strict, "area_loose": loose, "fits": maxi(loose.x, 0) >= min_size and maxi(loose.y, 0) >= min_size}
		quadrant["text"] = quadrant_text(quadrant)
		out.append(quadrant)
	return out


## Converte os status em verdadeiro/falso (pode construir?).
static func grid_to_free(grid: Array, allow_clear: bool) -> Array:
	return grid.map(func(row): return row.map(func(status): return status == Builds.FREE or (allow_clear and status == Builds.CLEARABLE)))


## "Nordeste, nenhum obstáculo", "Noroeste, lago, área de 12 por 9 metros
## construível" ou "Sudeste, lago e árvores, área de 9 por 9 metros com
## obstáculos a limpar".
static func quadrant_text(quadrant: Dictionary) -> String:
	var obstacles: Array = quadrant["water"] + quadrant["clear"]
	if obstacles.is_empty():
		if not quadrant["fits"]:
			return "%s, sem espaço para construir" % quadrant["name"]
		return "%s, nenhum obstáculo" % quadrant["name"]
	if not quadrant["fits"]:
		return "%s, %s, sem espaço para construir" % [quadrant["name"], _list_text(obstacles)]
	if not quadrant["clear"].is_empty():
		return "%s, %s, área de %s com obstáculos a limpar" % [quadrant["name"], _list_text(obstacles), area_text(quadrant["area_loose"])]
	return "%s, %s, área de %s construível" % [quadrant["name"], _list_text(obstacles), area_text(quadrant["area"])]


## "lago", "lago e árvores", "lago, riacho e árvores".
static func _list_text(items: Array) -> String:
	if items.size() == 1:
		return items[0]
	return ", ".join(items.slice(0, -1)) + " e " + items[-1]


## Maior retângulo de casas "true" (largura, altura), em casas; (0, 0) se não há.
static func _largest_rect(free: Array) -> Vector2i:
	var rows := free.size()
	if rows == 0:
		return Vector2i.ZERO
	var cols: int = free[0].size()
	var heights := []
	heights.resize(cols)
	heights.fill(0)
	var best := Vector2i.ZERO
	var best_area := 0
	for r in rows:
		for c in cols:
			heights[c] = int(heights[c]) + 1 if free[r][c] else 0
		for c in cols:
			var low := int(heights[c])
			for c2 in range(c, cols):
				low = mini(low, int(heights[c2]))
				if low == 0:
					break
				var width := c2 - c + 1
				if width * low > best_area:
					best_area = width * low
					best = Vector2i(width, low)
	return best


# --- Âncoras ---------------------------------------------------------------------------

## As âncoras de um quadrante: os 4 cantos e o redor de cada obstáculo
## intransponível. Cada uma: { "corner", "dir", "name", "area", "area_loose",
## "square", "square_loose", "text" } (áreas em casas, medidas a partir do
## canto; "square" é o maior lado de construção que cabe, só em chão livre).
## Só entram as que comportam o menor tamanho com limpeza.
static func quadrant_anchors(builds: Builds, region: Vector2i, quadrant: Dictionary, min_size := 3) -> Array:
	var box: Rect2i = quadrant["box"]
	var candidates := []
	var last := box.end - Vector2i.ONE
	var corners := [
		["Canto noroeste", Vector2i(box.position.x, box.position.y), Vector2i(1, 1)],
		["Canto nordeste", Vector2i(last.x, box.position.y), Vector2i(-1, 1)],
		["Canto sudoeste", Vector2i(box.position.x, last.y), Vector2i(1, -1)],
		["Canto sudeste", Vector2i(last.x, last.y), Vector2i(-1, -1)],
	]
	var half := WorldGen.REGION_SIZE / 2
	var center := region * WorldGen.REGION_SIZE
	for entry in corners:
		var corner: Vector2i = entry[1]
		var outer := absi(corner.x - center.x) >= half - 1 and absi(corner.y - center.y) >= half - 1
		candidates.append([entry[0] + (" da região" if outer else " do quadrante"), corner, entry[2]])
	# O redor de cada tipo de obstáculo intransponível.
	var boxes := {}
	for y in range(box.position.y, box.end.y):
		for x in range(box.position.x, box.end.x):
			var cell := Vector2i(x, y)
			if builds.cell_status(cell, region) != Builds.WATER:
				continue
			var name: String = WATER_NAMES.get(builds.world.thing_at(cell), "água")
			if not boxes.has(name):
				boxes[name] = Rect2i(cell, Vector2i.ONE)
			else:
				boxes[name] = (boxes[name] as Rect2i).expand(cell)
	for name: String in boxes:
		var bb: Rect2i = boxes[name]
		var bend := bb.end - Vector2i.ONE
		candidates.append(["Ao norte do %s" % name, Vector2i(bb.position.x, bb.position.y - 1), Vector2i(1, -1)])
		candidates.append(["Ao sul do %s" % name, Vector2i(bb.position.x, bend.y + 1), Vector2i(1, 1)])
		candidates.append(["A leste do %s" % name, Vector2i(bend.x + 1, bb.position.y), Vector2i(1, 1)])
		candidates.append(["A oeste do %s" % name, Vector2i(bb.position.x - 1, bb.position.y), Vector2i(-1, 1)])
	var out := []
	for entry in candidates:
		var anchor := measure(builds, region, entry[1], entry[2], entry[0])
		if not anchor.is_empty() and int(anchor["square_loose"]) >= min_size:
			out.append(anchor)
	return out


## As âncoras ao redor de uma construção: ao norte, ao sul, a leste e a oeste
## dela, deixando Builds.SPACING casas para andar entre as duas.
static func building_anchors(builds: Builds, build: Dictionary, min_size := 3) -> Array:
	var size := int(build["size"])
	var low: Vector2i = build["cell"]
	var high := low + Vector2i(size - 1, size - 1)
	var gap := Builds.SPACING + 1
	var title := builds.title_of(int(build["id"]))
	var article := "d" + str(Crafting.BUILDS[build["kind"]]["article"]) + " " + title.left(1).to_lower() + title.substr(1)
	var candidates := [
		["Ao norte %s" % article, Vector2i(low.x, low.y - gap), Vector2i(1, -1)],
		["Ao sul %s" % article, Vector2i(low.x, high.y + gap), Vector2i(1, 1)],
		["A leste %s" % article, Vector2i(high.x + gap, low.y), Vector2i(1, 1)],
		["A oeste %s" % article, Vector2i(low.x - gap, low.y), Vector2i(-1, 1)],
	]
	var out := []
	for entry in candidates:
		var anchor := measure(builds, build["region"], entry[1], entry[2], entry[0])
		if not anchor.is_empty() and int(anchor["square_loose"]) >= min_size:
			out.append(anchor)
	return out


## Mede o que cabe a partir de um canto, andando na diagonal (até PIN_STEPS
## casas) se o canto em si não serve. {} se nada serve.
static func measure(builds: Builds, region: Vector2i, corner: Vector2i, dir: Vector2i, name: String) -> Dictionary:
	var pinned := corner
	var status := builds.cell_status(pinned, region)
	var steps := 0
	while status != Builds.FREE and status != Builds.CLEARABLE and steps < PIN_STEPS:
		pinned += dir
		status = builds.cell_status(pinned, region)
		steps += 1
	if status != Builds.FREE and status != Builds.CLEARABLE:
		return {}
	# Altura livre de cada coluna a partir do canto.
	var strict_heights := []
	var loose_heights := []
	for dx in SCAN:
		var strict := 0
		var loose := 0
		var strict_open := true
		for dy in SCAN:
			var cell := pinned + Vector2i(dx * dir.x, dy * dir.y)
			var cell_status := builds.cell_status(cell, region)
			if cell_status == Builds.FREE:
				loose += 1
				if strict_open:
					strict += 1
			elif cell_status == Builds.CLEARABLE:
				loose += 1
				strict_open = false
			else:
				break
		strict_heights.append(strict)
		loose_heights.append(loose)
	var anchor := {"corner": pinned, "dir": dir, "name": name}
	var strict_best := _anchored_best(strict_heights)
	var loose_best := _anchored_best(loose_heights)
	anchor["area"] = strict_best[0]
	anchor["area_loose"] = loose_best[0]
	anchor["square"] = strict_best[1]
	anchor["square_loose"] = loose_best[1]
	var with_clear: bool = Vector2i(anchor["area"]) != Vector2i(anchor["area_loose"])
	anchor["text"] = "%s, área de %s %s" % [name, area_text(anchor["area_loose"] if with_clear else anchor["area"]),
		"com obstáculos" if with_clear else "construível"]
	return anchor


## De uma lista de alturas por coluna: [maior retângulo (largura, altura),
## maior lado de quadrado] ancorados no começo da lista.
static func _anchored_best(heights: Array) -> Array:
	var best_rect := Vector2i.ZERO
	var best_area := 0
	var best_square := 0
	var low := 1 << 30
	for i in heights.size():
		low = mini(low, int(heights[i]))
		if low <= 0:
			break
		var width := i + 1
		if width * low > best_area:
			best_area = width * low
			best_rect = Vector2i(width, low)
		if mini(width, low) > best_square:
			best_square = mini(width, low)
	return [best_rect, best_square]


## Os tamanhos que se pode escolher numa âncora, do menor ao maior: cada um
## { "size", "needs_clearing" (parte do terreno tem o que arrancar) }.
static func sizes_for(anchor: Dictionary, limits: Dictionary) -> Array:
	var out := []
	var most := mini(int(limits["max"]), int(anchor["square_loose"]))
	for size in range(int(limits["min"]), most + 1):
		out.append({"size": size, "needs_clearing": size > int(anchor["square"])})
	return out
