class_name Narrator
extends RefCounted
## Transforma o estado do mundo em frases curtas para a fala.
## Regra: primeiro o que importa, depois o detalhe.

const SURROUNDINGS_RADIUS := 5
const SURROUNDINGS_MAX_ITEMS := 6


## Junta preposição e artigo: ("a", "a Origem") -> "à Origem";
## ("em", "o bambu") -> "no bambu"; ("até", "as pedras") -> "até as pedras".
static func contract(prep: String, place: String) -> String:
	var cut := place.find(" ")
	var article := place.left(cut) if cut > 0 else ""
	var rest := place.substr(cut + 1) if cut > 0 else place
	var table: Dictionary = {
		"a": {"a": "à", "o": "ao", "as": "às", "os": "aos"},
		"em": {"a": "na", "o": "no", "as": "nas", "os": "nos"},
	}.get(prep, {})
	if table.has(article):
		return "%s %s" % [table[article], rest]
	return "%s %s" % [prep, place]


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
	var biome := world.place_in(cell)
	match world.thing_at(cell):
		WorldGen.Thing.TRILHA:
			biome = "numa trilha, " + biome
		WorldGen.Thing.PONTE:
			biome = "numa ponte, " + biome
	var facing := "olhando para o %s" % Compass.name_of(heading)
	return "Você está %s, %s." % [biome, facing]


## A primeira fala do C: onde a criatura pisa e para onde olha. "Pisando em uma
## trilha, no bosque de micélio, olhando para o leste." Sem nada de especial no
## chão, só o lugar: "No bosque de micélio, olhando para o leste."
static func stepping_on(world: WorldGen, pos: Vector2, heading: int) -> String:
	var cell := WorldGen.cell_of(pos)
	var place := world.place_in(cell)
	var facing := "olhando para o %s" % Compass.name_of(heading)
	match world.thing_at(cell):
		WorldGen.Thing.TRILHA:
			return "Pisando em uma trilha, %s, %s." % [place, facing]
		WorldGen.Thing.PONTE:
			return "Pisando em uma ponte, %s, %s." % [place, facing]
	return "%s, %s." % [place.substr(0, 1).to_upper() + place.substr(1), facing]


## Lista o que está por perto, do mais próximo ao mais distante, em relação
## a para onde a criatura olha. De cada tipo de coisa, só a mais próxima; e,
## se não estiver numa trilha, onde fica a trilha mais próxima.
## Recursos já colhidos (harvest) ficam de fora, ou viram só "arbusto"; um
## bambu já derrubado é anunciado como tal.
static func surroundings(world: WorldGen, pos: Vector2, heading: int, others: Array, harvest: Harvest = null, ground: Ground = null) -> String:
	var found := []
	var here := WorldGen.cell_of(pos)
	var r := SURROUNDINGS_RADIUS
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var cell := here + Vector2i(dx, dy)
			var thing := world.thing_at(cell)
			if WorldGen.GROUND.has(thing):
				continue
			var thing_name: String = WorldGen.THING_NAMES[thing] if harvest == null else harvest.spoken_name(cell)
			if thing_name.is_empty():
				continue
			found.append({"name": thing_name, "offset": WorldGen.cell_center(cell) - pos})
	if ground != null:
		for pile_cell: Vector2i in ground.cells():
			var pile_offset := WorldGen.cell_center(pile_cell) - pos
			if pile_offset.length() <= r:
				found.append({"name": "itens no chão", "offset": pile_offset})
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
		return "Nada por perto. Você está %s." % world.place_in(here)
	return ". ".join(lines) + "."
