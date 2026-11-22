extends Node
## Testes do Caminheiro: rotas pelas trilhas, beacons, menu das setas.
## Rodar (precisa ser uma cena, para os autoloads existirem):
##   godot --headless --path . res://tests/test_caminheiro.tscn

var _failures := 0


func _ready() -> void:
	_test_routes_reach_origin()
	_test_prefers_direct()
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
	_test_beat_openness()
	_test_steering()
	_test_search_radius()
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


## De vários lugares, em várias sementes, a rota termina no Centro, e dá para
## ir em linha reta de cada beacon ao próximo sem esbarrar.
func _test_routes_reach_origin() -> void:
	for world_seed in range(5):
		var world := WorldGen.new(world_seed)
		var rng := RandomNumberGenerator.new()
		rng.seed = world_seed
		for k in 4:
			var from := _free_point(world, Vector2(rng.randf_range(-120, 120), rng.randf_range(-120, 120)))
			var finder := Wayfinder.new(world)
			_check(finder._plan_trails(from, WorldGen.center_point()), "deveria achar rota de %s (semente %d)" % [from, world_seed])
			var route := finder.full_route()
			_check(not route.is_empty() and route[-1] == WorldGen.center_point(), "a rota deveria terminar no Centro (de %s)" % from)
			var previous := from
			var on_trail := 0
			for point in route:
				_check(finder._line_is_clear(previous, point), "trecho %s -> %s deveria ser livre" % [previous, point])
				_check(previous.distance_to(point) <= Wayfinder.MAX_SEGMENT + 0.01, "beacons deveriam ficar a no máximo %d casas" % Wayfinder.MAX_SEGMENT)
				if world.is_trail(WorldGen.cell_of(point)):
					on_trail += 1
				previous = point
			# Quase todos os beacons (60%) ficam em cima de trilha (o resto é a
			# chegada até a trilha e a clareira do centro).
			_check(route.size() < 5 or on_trail >= route.size() * 0.6, "a rota deveria seguir as trilhas (%d de %d beacons) de %s semente %d bioma %s" % [on_trail, route.size(), from, world_seed, world.biome_at(WorldGen.cell_of(from))])


## Com caminho direto livre e bem mais curto, o Caminheiro vai direto; a
## rota nunca fica mais de 10% (ou 6 casas) acima da trilha, e toda rota
## continua livre de obstáculos de beacon em beacon.
func _test_prefers_direct() -> void:
	var direct_used := 0
	var trail_used := 0
	for world_seed in range(5):
		var world := WorldGen.new(world_seed)
		var rng := RandomNumberGenerator.new()
		rng.seed = 100 + world_seed
		for k in 6:
			var from := _free_point(world, Vector2(rng.randf_range(-120, 120), rng.randf_range(-120, 120)))
			var to := _free_point(world, from + Vector2(rng.randf_range(-70, 70), rng.randf_range(-70, 70)))
			var finder := Wayfinder.new(world)
			if not finder.plan(from, to):
				continue
			var route := finder.full_route()
			_check(not route.is_empty() and route[-1].distance_to(to) < 6.0, "a rota deveria chegar ao destino")
			var previous := from
			for point in route:
				_check(finder._line_is_clear(previous, point), "trecho %s -> %s deveria ser livre" % [previous, point])
				previous = point
			var trails := Wayfinder.new(world)
			if trails._plan_trails(from, to):
				var trail_length := Wayfinder._length(from, trails.full_route())
				var length := Wayfinder._length(from, route)
				_check(length <= trail_length + 0.01, "a rota escolhida não pode ser mais longa que a das trilhas (%f > %f)" % [length, trail_length])
				if absf(length - trail_length) < 0.01:
					trail_used += 1
				else:
					direct_used += 1
	_check(direct_used > 0, "algumas rotas deveriam ir direto, sem trilha")
	# Em campo aberto e a poucos passos, vai em linha reta.
	var open_world := WorldGen.new(3)
	var start := _free_point(open_world, Vector2(10, 10))
	var finder2 := Wayfinder.new(open_world)
	var goal := start + Vector2(8, 0)
	if open_world.is_free(goal) and finder2._line_is_clear(start, goal):
		finder2.plan(start, goal)
		var route2 := finder2.full_route()
		_check(route2.size() == 1 and route2[0] == goal, "rota curta e livre vai direto")


func _test_off_trail_goes_to_nearest_trail_first() -> void:
	var world := WorldGen.new(3)
	var from := Vector2.INF
	for y in range(-100, 100):
		for x in range(-100, 100):
			var cell := Vector2i(x, y)
			if world.is_free(WorldGen.cell_center(cell)) and not world.is_trail(cell) and world.nearest_trail(WorldGen.cell_center(cell), 3) == WorldGen.NO_CELL \
					and world.biome_at(cell) != WorldGen.Biome.BOSQUE and world.biome_at(cell) != WorldGen.Biome.BAMBUZAL:
				from = WorldGen.cell_center(cell)
				break
		if from != Vector2.INF:
			break
	_check(from != Vector2.INF, "deveria haver um lugar fora da trilha")
	var finder := Wayfinder.new(world)
	var path := finder.nearest_trail_path(from)
	_check(not path.is_empty() and world.is_trail(path[-1]), "deveria achar o caminho até uma trilha")
	finder._plan_trails(from, WorldGen.center_point())
	var entry := WorldGen.cell_center(path[-1])
	_check(finder.full_route().has(entry), "a rota deveria passar pela entrada da trilha mais próxima")


## Uma criatura que só anda rumo ao beacon atual (com colisão) chega ao Centro.
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
		_check(guide.start(pos, WorldGen.center_point(), "Centro"), "o Caminheiro deveria acender")
		var steps := 0
		while guide.active and steps < 20000:
			steps += 1
			var beacon: Vector2 = guide.current_beacon()
			pos = _walk(world, pos, (beacon - pos).normalized() * 0.15)
			guide.update(pos, 0.1)
		_check(arrived == ["Centro"], "deveria chegar ao Centro seguindo os beacons (semente %d, parou em %s)" % [world_seed, pos])
		_check(reached.size() >= 3, "deveria passar por vários beacons (%d)" % reached.size())
		_check(not guide.active, "o cristal se apaga no destino")
		guide.free()


func _test_replan_when_lost() -> void:
	var world := WorldGen.new(1)
	var guide := Caminheiro.new()
	guide.setup(world, null)
	var from := _free_point(world, Vector2(-60, 40))
	guide.start(from, WorldGen.center_point(), "Centro")
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
			var items := [{"label": "Centro", "run": func(): ran.append("Centro"); lit[0] = true; return "rumo ao Centro"}]
			if lit[0]:
				items.append({"label": "Apagar o cristal", "run": func(): lit[0] = false; return "apagou"})
			return items}]
	var menu := FloatingMenu.new(root)
	_check(menu.press("direita") == "Caminheiro", "com uma opção só, a navegação repete o nome")
	_check(menu.press("cima") == "Caminheiro. Centro", "cima entra no Caminheiro")
	_check(menu.depth() == 2, "deveria estar no submenu")
	_check(menu.press("cima") == "rumo ao Centro" and ran == ["Centro"], "cima no Centro acende o cristal")
	_check(menu.depth() == 2, "depois de executar, o menu continua onde está")
	_check(menu.press("direita") == "Apagar o cristal, 2 de 2", "aceso, aparece a opção de apagar")
	_check(menu.press("baixo") == "Caminheiro", "baixo volta")
	var limits := [0]
	menu.sound.connect(func(kind: String): limits[0] += 1 if kind == "limite" else 0)
	_check(menu.press("baixo") == "" and limits[0] == 1, "baixo no começo só toca o som de limite")


## Menu Recursos: o cristal leva até o coletável mais próximo de cada tipo,
## e a criatura chega perto o bastante para coletar (ou golpear o bambu).
func _test_resources() -> void:
	var GameScript: GDScript = load("res://scenes/game.gd")
	var world := WorldGen.new(220)
	var harvest := Harvest.new(world)
	var start := _free_point(world, WorldGen.center_point() + Vector2(0, 1.5))
	for entry: Array in GameScript.CAMINHEIRO_RESOURCES:
		var cell: Vector2i = GameScript.nearest_collectable(world, harvest, start, entry[1], GameScript.RESOURCE_SEARCH_RADIUS)
		if entry[0] == "Cogumelos":
			_check(cell == WorldGen.NO_CELL, "Cogumelos ainda não acha nada")
			continue
		if entry[0] in ["Árvores", "Trepadeiras", "Ramas", "Capim", "Argila"] and cell == WorldGen.NO_CELL:
			continue  # árvores e trepadeiras só nascem na mata; ramas, fibra e argila dependem do lugar: pode não haver nenhuma no raio
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
	# Forrageador: por espécie, só a espécie pedida.
	for species: String in Plants.ORDER:
		var found: Vector2i = GameScript.nearest_collectable(world, harvest, start, [species], 72)
		if found != WorldGen.NO_CELL:
			_check(Plants.species_at(world, found) == species, "%s: acha só essa espécie" % species)
	var fruit: Vector2i = GameScript.nearest_collectable(world, harvest, start, ["amora", "pitanga", "baga", "maracuja"], 72)
	_check(fruit != WorldGen.NO_CELL and Plants.is_fruit(Plants.species_at(world, fruit)), "Frutas leva a uma planta de fruta")
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
	_check(Narrator.contract("a", "o Centro") == "ao Centro", "ao Centro")
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
		return [{"label": noun + " Sombrio", "run": func(): chosen[0] = noun + " Sombrio"; return "", "close": true},
			{"label": noun + " Antigo", "run": func(): chosen[0] = noun + " Antigo"; return "", "close": true}]
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
	var cell := WorldGen.cell_of(WorldGen.center_point())
	var region := world.region_of(cell)
	var border := cell
	while world.region_of(border + Vector2i(1, 0)) == region:
		border += Vector2i(1, 0)
	_check(not GameScript.region_changed(world, region, border), "na última casa da região, nada muda")
	_check(not GameScript.region_changed(world, region, border + Vector2i(1, 0)), "a primeira casa da vizinha ainda não conta")
	_check(GameScript.region_changed(world, region, border + Vector2i(2, 0)), "a segunda, sim")
	_check(SoundBank.region_change().get_length() > 0.5, "o som de mudança de região existe")


## A batida abre de atrás (abafada) até a frente (normal), e o estéreo alarga
## sem mexer na frente nem no atrás.
func _test_beat_openness() -> void:
	_check(is_equal_approx(Caminheiro.openness_at(0.0), 1.0), "de frente, batida normal")
	_check(is_equal_approx(Caminheiro.openness_at(22.5), 1.0), "na borda da frente, ainda normal")
	_check(is_equal_approx(Caminheiro.openness_at(180.0), 0.0), "atrás, bem abafada")
	var previous := 1.0
	for off in range(23, 181, 4):
		var value := Caminheiro.openness_at(off)
		_check(value <= previous + 0.0001, "a abertura só diminui ao virar para trás (%d°)" % off)
		previous = value
	var forward := Vector2(0, -1)
	_check(Caminheiro.widen_direction(forward, forward).distance_to(forward) < 0.0001, "frente não muda")
	_check(Caminheiro.widen_direction(forward, -forward).distance_to(-forward) < 0.0001, "atrás não muda")
	var side := Vector2(1, -1).normalized()
	var wide := Caminheiro.widen_direction(forward, side)
	_check(absf(forward.angle_to(wide)) > absf(forward.angle_to(side)), "45° vira mais de 45°")
	_check(sign(forward.angle_to(wide)) == sign(forward.angle_to(side)), "continua do mesmo lado")
	for k in 8:
		var angle := k * PI / 4.0 - PI + 0.1
		var dir := forward.rotated(angle)
		var widened := Caminheiro.widen_direction(forward, dir)
		_check(absf(angle_difference(dir.angle(), widened.angle())) < deg_to_rad(10.0), "ampliação pequena (%f)" % angle)


## A direção do som gira aos poucos (como um carro) e o ponto à frente abre as esquinas.
func _test_steering() -> void:
	var east := Vector2(1, 0)
	var north := Vector2(0, -1)
	_check(Caminheiro.steer_toward(Vector2.ZERO, north, 0.1).distance_to(north) < 0.0001, "sem direção atual, vai direto")
	var step := deg_to_rad(Caminheiro.TURN_RATE_DEG) / 60.0
	var heading := east
	var last_angle := 0.0
	var frames := 0
	while heading.distance_to(north) > 0.0001 and frames < 1000:
		var next := Caminheiro.steer_toward(heading, north, step)
		_check(absf(heading.angle_to(next)) <= step + 0.0001, "nenhum quadro gira mais que o limite")
		heading = next
		frames += 1
	_check(frames > 130 and frames < 140, "90° leva ~2,25 s a 40°/s (%d quadros)" % frames)
	var behind := Caminheiro.steer_toward(east, -east, step)
	_check(absf(east.angle_to(behind)) <= step + 0.0001, "virar 180° também é gradual")
	var route: Array = [Vector2(2, 0), Vector2(2, -10)]
	_check(Caminheiro.lookahead_point(Vector2.ZERO, route, 1.0).distance_to(Vector2(1, 0)) < 0.0001, "ponto à frente no primeiro trecho")
	_check(Caminheiro.lookahead_point(Vector2.ZERO, route, 4.0).distance_to(Vector2(2, -2)) < 0.0001, "ponto à frente passa a esquina")
	_check(Caminheiro.lookahead_point(Vector2.ZERO, route, 50.0).distance_to(Vector2(2, -10)) < 0.0001, "rota curta: o último ponto")


## O Caminheiro e o radar enxergam meia região (36 m), cruzando o limite de região.
func _test_search_radius() -> void:
	var GameScript: GDScript = load("res://scenes/game.gd")
	_check(GameScript.RESOURCE_SEARCH_RADIUS * 1.5 == 36.0, "raio de busca: 36 m")
	var world := WorldGen.new(42)
	var crossed := 0
	for k in 60:
		var pos := Vector2(k * 37.0 - 900.0, k * 53.0 - 700.0)
		for entry: Array in GameScript.CAMINHEIRO_RESOURCES:
			var cell: Vector2i = GameScript.nearest_collectable(world, null, pos, entry[1], GameScript.RESOURCE_SEARCH_RADIUS)
			if cell == WorldGen.NO_CELL:
				continue
			_check(WorldGen.cell_center(cell).distance_to(pos) <= GameScript.RESOURCE_SEARCH_RADIUS + 1.0, "%s: dentro do raio" % entry[0])
			if world.region_of(cell) != world.region_of(WorldGen.cell_of(pos)):
				crossed += 1
	_check(crossed > 0, "acha recursos na região vizinha (%d)" % crossed)
