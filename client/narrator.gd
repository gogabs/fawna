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


static func where_am_i(world: WorldGen, pos: Vector2i) -> String:
	var biome: String = WorldGen.BIOME_IN[world.biome_at(pos)]
	var to_village := WorldGen.center() - pos
	if to_village == Vector2i.ZERO:
		return "Você está na vila, %s." % biome
	return "Você está %s. A vila fica %s." % [biome, direction(to_village)]


## Lista o que está por perto, do mais próximo ao mais distante.
static func surroundings(world: WorldGen, pos: Vector2i, others: Array) -> String:
	var found := []
	var r := SURROUNDINGS_RADIUS
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var offset := Vector2i(dx, dy)
			if offset == Vector2i.ZERO:
				continue
			var thing := world.thing_at(pos + offset)
			if thing != WorldGen.Thing.NADA:
				found.append({"name": WorldGen.THING_NAMES[thing], "offset": offset})
	for other in others:
		var offset: Vector2i = other["pos"] - pos
		if absi(offset.x) <= r and absi(offset.y) <= r:
			found.append({"name": other["name"], "offset": offset})
	if found.is_empty():
		return "Nada por perto. Você está %s." % WorldGen.BIOME_IN[world.biome_at(pos)]
	found.sort_custom(func(a, b): return _distance(a["offset"]) < _distance(b["offset"]))
	var lines: PackedStringArray = []
	for item in found.slice(0, SURROUNDINGS_MAX_ITEMS):
		lines.append("%s, %s" % [item["name"], direction(item["offset"])])
	return ". ".join(lines) + "."


static func _distance(offset: Vector2i) -> int:
	return absi(offset.x) + absi(offset.y)
