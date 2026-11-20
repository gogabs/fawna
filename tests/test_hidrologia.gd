extends SceneTree
## Testes das bacias hidrográficas: rios e lagos fazem sentido.
## Rodar: godot --headless --path . --script res://tests/test_hidrologia.gd

var _failures := 0


func _init() -> void:
	_test_rivers_end_in_sea_or_lake()
	_test_springs_and_width()
	_test_mountains()
	_test_water_in_cells()
	_test_origin_dry()
	if _failures == 0:
		print("OK: hidrologia")
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FALHOU: " + message)


## Toda água escoa para uma região mais baixa e chega ao mar ou a um lago.
func _test_rivers_end_in_sea_or_lake() -> void:
	var world := WorldGen.new(42)
	var hydro: Hydrology = world._hydro
	var rivers := 0
	var lakes := 0
	for y in range(-25, 26):
		for x in range(-25, 26):
			var region := Vector2i(x, y)
			if hydro.is_lake(region):
				lakes += 1
			if not hydro.has_river(region):
				continue
			rivers += 1
			var here := region
			var steps := 0
			while hydro.has_river(here) and steps < 200:
				var next := hydro.drain(here)
				_check(hydro.height(next) < hydro.height(here), "a água só desce")
				here = next
				steps += 1
			_check(hydro.is_sea(here) or hydro.is_lake(here), "o rio termina no mar ou num lago (%s)" % [region])
	_check(rivers > 100, "há rios (%d)" % rivers)
	_check(lakes > 10, "há lagos (%d)" % lakes)


## O rio nasce com largura zero e só alarga rio abaixo; nunca passa do máximo.
func _test_springs_and_width() -> void:
	var world := WorldGen.new(42)
	var hydro: Hydrology = world._hydro
	var springs := 0
	var widest := 0.0
	for y in range(-25, 26):
		for x in range(-25, 26):
			var region := Vector2i(x, y)
			var line := hydro.river_line(region)
			if line.is_empty():
				continue
			var widths: PackedFloat32Array = line[1]
			for width in widths:
				widest = maxf(widest, width)
			if hydro.is_headwater(region):
				springs += 1
				_check(widths[0] == 0.0, "a nascente começa com largura zero")
			var drain := hydro.drain(region)
			if hydro.has_river(drain):
				_check(hydro.discharge(drain) >= hydro.discharge(region), "a vazão só cresce rio abaixo")
	_check(springs > 20, "há nascentes (%d)" % springs)
	_check(widest <= Hydrology.WIDTH_MAX + 0.01, "largura máxima respeitada")
	_check(widest > 6.0, "algum rio é largo (%.1f)" % widest)


## Montanhas quase sempre têm nascente própria.
func _test_mountains() -> void:
	var world := WorldGen.new(42)
	var hydro: Hydrology = world._hydro
	var mountains := 0
	var with_river := 0
	for y in range(-40, 41):
		for x in range(-40, 41):
			var region := Vector2i(x, y)
			if world.region_biome(region) == WorldGen.Biome.MONTANHA:
				mountains += 1
				if hydro.has_river(region):
					with_river += 1
	_check(mountains > 20, "há montanhas (%d)" % mountains)
	_check(with_river > mountains * 0.6, "montanhas têm nascentes (%d de %d)" % [with_river, mountains])


## Vau se atravessa; riacho e rio bloqueiam; ponte cobre a água na trilha.
func _test_water_in_cells() -> void:
	var world := WorldGen.new(42)
	var count := {}
	for y in range(-600, 600, 2):
		for x in range(-600, 600, 2):
			var thing := world.thing_at(Vector2i(x, y))
			count[thing] = int(count.get(thing, 0)) + 1
	for thing: WorldGen.Thing in [WorldGen.Thing.VAU, WorldGen.Thing.RIACHO, WorldGen.Thing.RIO, WorldGen.Thing.LAGO]:
		_check(int(count.get(thing, 0)) > 0, "existe %s" % WorldGen.THING_NAMES[thing])
	_check(not WorldGen.BLOCKING.has(WorldGen.Thing.VAU), "vau não bloqueia")
	_check(WorldGen.BLOCKING.has(WorldGen.Thing.RIACHO) and WorldGen.BLOCKING.has(WorldGen.Thing.RIO), "riacho e rio bloqueiam")


func _test_origin_dry() -> void:
	var world := WorldGen.new(42)
	var hydro: Hydrology = world._hydro
	_check(not hydro.has_river(Vector2i.ZERO) and not hydro.is_lake(Vector2i.ZERO), "o centro do mundo não tem rio nem lago")
	for y in range(-8, 9):
		for x in range(-8, 9):
			_check(not WorldGen.WATER.has(world.thing_at(Vector2i(x, y))), "o ponto de partida fica seco")
