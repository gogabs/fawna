extends Node
## Testes do Caminheiro: rotas pelas trilhas, beacons, menu das setas.
## Rodar (precisa ser uma cena, para os autoloads existirem):
##   godot --headless --path . res://tests/test_caminheiro.tscn

var _failures := 0


func _ready() -> void:
	_test_routes_reach_origin()
	_test_off_trail_goes_to_nearest_trail_first()
	_test_walk_following_beacons()
	_test_replan_when_lost()
	_test_menu()
	if _failures == 0:
		print("OK: todos os testes passaram")
	get_tree().quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FALHOU: " + message)


func _free_point(world: WorldGen, p: Vector2) -> Vector2:
	while not world.is_free(p):
		p += Vector2(1.0, 0.3)
	return p


## De vários lugares, em várias sementes, a rota termina na Origem, e dá para
## ir em linha reta de cada beacon ao próximo sem esbarrar.
func _test_routes_reach_origin() -> void:
	for world_seed in range(5):
		var world := WorldGen.new(world_seed)
		var rng := RandomNumberGenerator.new()
		rng.seed = world_seed
		for k in 4:
			var from := _free_point(world, Vector2(rng.randf_range(-120, 120), rng.randf_range(-120, 120)))
			var finder := Wayfinder.new(world)
			_check(finder.plan(from, WorldGen.origin_point()), "deveria achar rota de %s (semente %d)" % [from, world_seed])
			var route := finder.full_route()
			_check(not route.is_empty() and route[-1] == WorldGen.origin_point(), "a rota deveria terminar na Origem (de %s)" % from)
			var previous := from
			var on_trail := 0
			for point in route:
				_check(finder._line_is_clear(previous, point), "trecho %s -> %s deveria ser livre" % [previous, point])
				_check(previous.distance_to(point) <= Wayfinder.MAX_SEGMENT + 0.01, "beacons deveriam ficar a no máximo %d casas" % Wayfinder.MAX_SEGMENT)
				if world.is_trail(WorldGen.cell_of(point)):
					on_trail += 1
				previous = point
			# Quase todos os beacons ficam em cima de trilha (o resto é a
			# chegada até a trilha e a clareira da Origem).
			_check(route.size() < 5 or on_trail >= route.size() * 0.75, "a rota deveria seguir as trilhas (%d de %d beacons)" % [on_trail, route.size()])


func _test_off_trail_goes_to_nearest_trail_first() -> void:
	var world := WorldGen.new(3)
	var from := Vector2.INF
	for y in range(30, 80):
		for x in range(30, 80):
			var cell := Vector2i(x, y)
			if world.is_free(WorldGen.cell_center(cell)) and not world.is_trail(cell) and world.nearest_trail(WorldGen.cell_center(cell), 3) == WorldGen.NO_CELL:
				from = WorldGen.cell_center(cell)
				break
		if from != Vector2.INF:
			break
	_check(from != Vector2.INF, "deveria haver um lugar fora da trilha")
	var finder := Wayfinder.new(world)
	var path := finder.nearest_trail_path(from)
	_check(not path.is_empty() and world.is_trail(path[-1]), "deveria achar o caminho até uma trilha")
	finder.plan(from, WorldGen.origin_point())
	var entry := WorldGen.cell_center(path[-1])
	_check(finder.full_route().has(entry), "a rota deveria passar pela entrada da trilha mais próxima")


## Uma criatura que só anda rumo ao beacon atual (com colisão) chega à Origem.
func _test_walk_following_beacons() -> void:
	for world_seed in [0, 7]:
		var world := WorldGen.new(world_seed)
		var pos := _free_point(world, Vector2(70, -55))
		var guide := Caminheiro.new()
		guide.setup(world, null)
		var reached := []
		var arrived := []
		guide.beacon_reached.connect(func(p): reached.append(p))
		guide.arrived.connect(func(place): arrived.append(place))
		_check(guide.start(pos, WorldGen.origin_point(), "Origem"), "o Caminheiro deveria acender")
		var steps := 0
		while guide.active and steps < 20000:
			steps += 1
			var beacon: Vector2 = guide.current_beacon()
			pos = _walk(world, pos, (beacon - pos).normalized() * 0.15)
			guide.update(pos, 0.1)
		_check(arrived == ["Origem"], "deveria chegar à Origem seguindo os beacons (semente %d, parou em %s)" % [world_seed, pos])
		_check(reached.size() >= 3, "deveria passar por vários beacons (%d)" % reached.size())
		_check(not guide.active, "o cristal se apaga no destino")
		guide.free()


func _test_replan_when_lost() -> void:
	var world := WorldGen.new(1)
	var guide := Caminheiro.new()
	guide.setup(world, null)
	var from := _free_point(world, Vector2(-60, 40))
	guide.start(from, WorldGen.origin_point(), "Origem")
	var first: Vector2 = guide.current_beacon()
	var lost := _free_point(world, from + Vector2(0, 30))
	guide.update(lost, 0.1)
	_check(guide.active, "perdido, o Caminheiro continua aceso")
	_check(guide.current_beacon() != first, "longe da rota, o caminho deveria ser traçado de novo")
	guide.free()


func _test_menu() -> void:
	var ran := []
	var lit := [false]
	var root := func() -> Array:
		return [{"label": "Caminheiro", "open": func() -> Array:
			var items := [{"label": "Origem", "run": func(): ran.append("Origem"); lit[0] = true; return "rumo à Origem"}]
			if lit[0]:
				items.append({"label": "Apagar o cristal", "run": func(): lit[0] = false; return "apagou"})
			return items}]
	var menu := FloatingMenu.new(root)
	_check(menu.press("direita") == "Caminheiro", "com uma opção só, a navegação repete o nome")
	_check(menu.press("cima") == "Caminheiro. Origem", "cima entra no Caminheiro")
	_check(menu.depth() == 2, "deveria estar no submenu")
	_check(menu.press("cima") == "rumo à Origem" and ran == ["Origem"], "cima na Origem acende o cristal")
	_check(menu.depth() == 1, "depois de executar, volta ao começo")
	menu.press("cima")
	_check(menu.press("direita") == "Apagar o cristal, 2 de 2", "aceso, aparece a opção de apagar")
	_check(menu.press("baixo") == "Caminheiro", "baixo volta")
	_check(menu.press("baixo").begins_with("Menu das setas"), "baixo no começo diz onde está")


## Anda com o mesmo deslize do jogo (scenes/game.gd, _walk).
func _walk(world: WorldGen, pos: Vector2, motion: Vector2) -> Vector2:
	if world.is_free(pos + motion):
		return pos + motion
	for part in [Vector2(motion.x, 0.0), Vector2(0.0, motion.y)]:
		if world.is_free(pos + part):
			pos += part
	return pos
