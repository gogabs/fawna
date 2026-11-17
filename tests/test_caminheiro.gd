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
	_test_resources()
	_test_contract()
	_test_menu_stay()
	_test_menu_open_at()
	_test_region_change()
	_test_facing()
	if _failures == 0:
		print("OK: todos os testes passaram")
	get_tree().quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FALHOU: " + message)


func _free_point(world: WorldGen, p: Vector2) -> Vector2:
	# No bosque (mata fechada) só vale ponto na trilha: o resto são clareiras
	# isoladas, de onde não há rota a pé.
	while not world.is_free(p) or (world.biome_at(WorldGen.cell_of(p)) == WorldGen.Biome.BOSQUE and not world.is_trail(WorldGen.cell_of(p))):
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
			# Quase todos os beacons (70%) ficam em cima de trilha (o resto é a
			# chegada até a trilha e a clareira da Origem).
			_check(route.size() < 5 or on_trail >= route.size() * 0.7, "a rota deveria seguir as trilhas (%d de %d beacons) de %s semente %d bioma %s" % [on_trail, route.size(), from, world_seed, world.biome_at(WorldGen.cell_of(from))])


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


## Menu Recursos: o cristal leva até o coletável mais próximo de cada tipo,
## e a criatura chega perto o bastante para coletar (ou golpear o bambu).
func _test_resources() -> void:
	var GameScript: GDScript = load("res://scenes/game.gd")
	var world := WorldGen.new(220)
	var harvest := Harvest.new(world)
	var start := _free_point(world, WorldGen.origin_point() + Vector2(0, 1.5))
	for entry: Array in GameScript.CAMINHEIRO_RESOURCES:
		var cell: Vector2i = GameScript.nearest_collectable(world, harvest, start, entry[1], GameScript.RESOURCE_SEARCH_RADIUS)
		if entry[0] == "Frutas" and cell == WorldGen.NO_CELL:
			continue  # frutas são raras: pode não haver nenhuma no raio
		_check(cell != WorldGen.NO_CELL, "%s: deveria haver um por perto" % entry[0])
		if cell == WorldGen.NO_CELL:
			continue
		var guide := Caminheiro.new()
		guide.setup(world, null)
		var arrived := []
		guide.arrived.connect(func(place): arrived.append(place))
		_check(guide.start(start, GameScript.resource_destination(world, cell, start), entry[2]), "%s: o cristal deveria acender" % entry[0])
		var pos := start
		var steps := 0
		while guide.active and steps < 20000:
			steps += 1
			var beacon: Vector2 = guide.current_beacon()
			pos = _walk(world, pos, (beacon - pos).normalized() * 0.15)
			guide.update(pos, 0.1)
		var gap := pos.distance_to(WorldGen.cell_center(cell))
		_check(arrived == [entry[2]], "%s: deveria chegar (parou em %s)" % [entry[0], pos])
		_check(gap <= 3.1, "%s: chega a até 3 casas do recurso (%.1f)" % [entry[0], gap])
		guide.free()
	# O que já foi recolhido não conta.
	var stones: Vector2i = GameScript.nearest_collectable(world, harvest, start, [WorldGen.Thing.PEDRAS], 72)
	harvest.take(stones)
	var next: Vector2i = GameScript.nearest_collectable(world, harvest, start, [WorldGen.Thing.PEDRAS], 72)
	_check(next != stones, "pedras recolhidas não são destino")


## Destinos com "stay": o foco fica no lugar depois de escolher, e as opções
## de cima são recarregadas ao voltar (aparece "Apagar o cristal").
func _test_menu_stay() -> void:
	var lit := [""]
	var targets := func() -> Array:
		return [
			{"label": "Bambu", "run": func(): lit[0] = "" if lit[0] == "Bambu" else "Bambu"; return "bambu " + lit[0], "stay": true},
			{"label": "Pedras", "run": func(): lit[0] = "" if lit[0] == "Pedras" else "Pedras"; return "pedras " + lit[0], "stay": true},
		]
	var root := func() -> Array:
		return [{"label": "Caminheiro", "open": func() -> Array:
			var items := [{"label": "Recursos", "open": targets}]
			if lit[0] != "":
				items.append({"label": "Apagar o cristal", "run": func(): lit[0] = ""; return "apagou"})
			return items}]
	var menu := FloatingMenu.new(root)
	menu.press("cima")
	menu.press("cima")
	menu.press("direita")
	_check(menu.press("cima") == "pedras Pedras" and menu.depth() == 3, "escolher um recurso deixa o foco no lugar")
	_check(menu.current_label() == "Pedras", "o foco continua em Pedras")
	_check(menu.press("cima") == "pedras " and lit[0] == "", "escolher de novo o mesmo destino apaga")
	menu.press("cima")
	_check(menu.press("baixo") == "Recursos, 1 de 2", "voltando, o nível de cima é recarregado com Apagar o cristal")


func _test_contract() -> void:
	_check(Narrator.contract("a", "a Origem") == "à Origem", "à Origem")
	_check(Narrator.contract("a", "o bambu") == "ao bambu", "ao bambu")
	_check(Narrator.contract("em", "as pedras") == "nas pedras", "nas pedras")
	_check(Narrator.contract("a", "Lua") == "a Lua", "sem artigo, só a preposição")


## Anda com o mesmo deslize do jogo (scenes/game.gd, _walk).
func _walk(world: WorldGen, pos: Vector2, motion: Vector2) -> Vector2:
	if world.is_free(pos + motion):
		return pos + motion
	for part in [Vector2(motion.x, 0.0), Vector2(0.0, motion.y)]:
		if world.is_free(pos + part):
			pos += part
	return pos


## De frente: o beacon a no máximo 22,5° do rumo para onde a criatura olha,
## então sempre há um dos 8 rumos de frente para ele.
func _test_facing() -> void:
	var pos := Vector2(10, 10)
	_check(Caminheiro.is_facing(pos, pos + Vector2(0, -5), Compass.forward(0)), "beacon ao norte, olhando ao norte: de frente")
	_check(Caminheiro.is_facing(pos, pos + Vector2(1, -5), Compass.forward(0)), "beacon 11° a leste do norte: de frente")
	_check(not Caminheiro.is_facing(pos, pos + Vector2(3, -5), Compass.forward(0)), "beacon 31° a leste do norte: fora de frente")
	_check(not Caminheiro.is_facing(pos, pos + Vector2(0, 5), Compass.forward(0)), "beacon atrás: fora de frente")
	_check(not Caminheiro.is_facing(pos, pos + Vector2(0, -5), Vector2.ZERO), "sem direção: nunca de frente")
	for k in 72:
		var target := pos + Vector2.from_angle(k * TAU / 72.0) * 6.0
		var facing := 0
		for heading in Compass.STEPS:
			if Caminheiro.is_facing(pos, target, Compass.forward(heading)):
				facing += 1
		_check(facing >= 1 and facing <= 2, "algum rumo dos 8 deveria ficar de frente (ângulo %d)" % (k * 5))


## O Espaço num marco abre o menu direto na escolha do nome: duas listas.
func _test_menu_open_at() -> void:
	var chosen := [""]
	var adjectives := func(noun: String) -> Array:
		return [{"label": noun + " Sombrio", "run": func(): chosen[0] = noun + " Sombrio"; return ""},
			{"label": noun + " Antigo", "run": func(): chosen[0] = noun + " Antigo"; return ""}]
	var nouns := func() -> Array:
		return [{"label": "Vale", "open": adjectives.bind("Vale")}, {"label": "Refúgio", "open": adjectives.bind("Refúgio")}]
	var menu := FloatingMenu.new(func() -> Array: return [{"label": "Caminheiro", "info": "x"}, {"label": "Bolsa", "info": "y"}])
	menu.press("direita")
	_check(menu.open_at("Nome do povoado, primeira palavra", nouns) == "Nome do povoado, primeira palavra. Vale, 1 de 2", "abre na lista de substantivos")
	_check(menu.press("direita") == "Refúgio, 2 de 2", "esquerda e direita passam pelos substantivos")
	_check(menu.press("cima") == "Refúgio. Refúgio Sombrio, 1 de 2", "confirmar mostra os adjetivos já com o substantivo")
	_check(menu.press("baixo") == "Refúgio, 2 de 2", "baixo volta aos substantivos")
	menu.press("cima")
	menu.press("direita")
	menu.press("cima")
	_check(chosen[0] == "Refúgio Antigo" and menu.depth() == 1, "confirmar o adjetivo escolhe o nome e fecha o menu")
	menu.open_at("Nome do povoado, primeira palavra", nouns)
	_check(menu.press("baixo") == "Caminheiro, 1 de 2", "baixo na primeira lista desiste e volta ao menu das setas")


## Mudança de região: só conta uma casa para dentro da região nova, para o
## som não repetir em quem anda em cima da divisa.
func _test_region_change() -> void:
	var GameScript: GDScript = load("res://scenes/game.gd")
	var world := WorldGen.new(173)
	var cell := WorldGen.cell_of(WorldGen.origin_point())
	var region := world.region_of(cell)
	var border := cell
	while world.region_of(border + Vector2i(1, 0)) == region:
		border += Vector2i(1, 0)
	_check(not GameScript.region_changed(world, region, border), "na última casa da região, nada muda")
	_check(not GameScript.region_changed(world, region, border + Vector2i(1, 0)), "a primeira casa da vizinha ainda não conta")
	_check(GameScript.region_changed(world, region, border + Vector2i(2, 0)), "a segunda, sim")
	_check(SoundBank.region_change().get_length() > 0.5, "o som de mudança de região existe")
