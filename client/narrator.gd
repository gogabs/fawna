class_name Narrator
extends RefCounted
## Transforma o estado do mundo em frases curtas para a fala.
## Regra: primeiro o que importa, depois o detalhe.

const SURROUNDINGS_RADIUS := 5
const SURROUNDINGS_MAX_ITEMS := 6


static func steps(n: int) -> String:
	return "1 passo" if n == 1 else "%d passos" % n


## Ex.: Vector2i(1, -2) -> "2 ao norte e 1 a leste". Norte é y negativo.
static func direction(offset: Vector2i) -> String:
	var parts: PackedStringArray = []
	if offset.y < 0:
		parts.append("%d ao norte" % -offset.y)
	elif offset.y > 0:
		parts.append("%d ao sul" % offset.y)
	if offset.x > 0:
		parts.append("%d a leste" % offset.x)
	elif offset.x < 0:
		parts.append("%d a oeste" % -offset.x)
	if parts.is_empty():
		return "aqui"
	return " e ".join(parts)


static func where_am_i(world: WorldGen, pos: Vector2, heading: int) -> String:
	var cell := WorldGen.cell_of(pos)
	var biome: String = WorldGen.BIOME_IN[world.biome_at(cell)]
	match world.thing_at(cell):
		WorldGen.Thing.TRILHA:
			biome = "numa trilha, " + biome
		WorldGen.Thing.PONTE:
			biome = "numa ponte, " + biome
	var facing := "olhando para o %s" % Compass.name_of(heading)
	var to_village := WorldGen.village_point() - pos
	if to_village.length() <= WorldState.VILLAGE_REACH:
		return "Você está na vila, %s, %s." % [biome, facing]
	return "Você está %s, %s. A vila fica %s." % [biome, facing, Compass.describe(to_village, heading)]


## Lista o que está por perto, do mais próximo ao mais distante, em relação
## a para onde a criatura olha. De cada tipo de coisa, só a mais próxima; e,
## se não estiver numa trilha, onde fica a trilha mais próxima.
static func surroundings(world: WorldGen, pos: Vector2, heading: int, others: Array) -> String:
	var found := []
	var here := WorldGen.cell_of(pos)
	var r := SURROUNDINGS_RADIUS
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var cell := here + Vector2i(dx, dy)
			var thing := world.thing_at(cell)
			if not WorldGen.GROUND.has(thing):
				found.append({"name": WorldGen.THING_NAMES[thing], "offset": WorldGen.cell_center(cell) - pos})
	for other in others:
		var offset: Vector2 = other["pos"] - pos
		if offset.length() <= r:
			found.append({"name": other["name"], "offset": offset})
	found.sort_custom(func(a, b): return a["offset"].length() < b["offset"].length())
	var lines: PackedStringArray = []
	var seen := {}
	for item in found:
		if seen.has(item["name"]) or lines.size() >= SURROUNDINGS_MAX_ITEMS:
			continue
		seen[item["name"]] = true
		lines.append("%s, %s" % [item["name"], Compass.describe(item["offset"], heading)])
	if not world.is_trail(here):
		var trail := world.nearest_trail(pos)
		if trail != WorldGen.NO_CELL:
			lines.append("trilha mais próxima, %s" % Compass.describe(WorldGen.cell_center(trail) - pos, heading))
	if lines.is_empty():
		return "Nada por perto. Você está %s." % WorldGen.BIOME_IN[world.biome_at(here)]
	return ". ".join(lines) + "."


static func garden_status(garden: Dictionary) -> String:
	var stage := int(garden.get("stage", 0))
	if stage >= Economy.GARDEN_STAGES.size():
		return "A %s está completa." % Economy.GARDEN_NAME
	var missing := Economy.stage_missing(stage, garden.get("delivered", {}))
	var next_name: String = Economy.GARDEN_STAGES[stage]["name"]
	return "A %s precisa de %s para virar %s." % [Economy.GARDEN_NAME, Economy.items_text(missing), next_name]
