extends SceneTree
## Testes do forno: colado no abrigo, etapas com secagem, fogo, receitas
## (broa, ensopado, assar tudo, queimar o pote) e o calor dentro do abrigo.
## Rodar: godot --headless --path . --script res://tests/test_oven.gd

var _failures := 0


func _init() -> void:
	_test_recipes_plan()
	_test_placement_and_cooking()
	_test_warmth()
	if _failures == 0:
		print("OK: todos os testes passaram")
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FALHOU: " + message)


## Canto noroeste de um quadrado livre de "side" casas perto do centro.
func _free_square(world: WorldGen, side: int) -> Vector2i:
	var origin := WorldGen.cell_of(WorldGen.center_point())
	for r in range(2, 80):
		for dx in range(-r, r + 1):
			for dy in [-r, r]:
				var corner := origin + Vector2i(dx, dy)
				var ok := true
				for y in side:
					for x in side:
						var cell := corner + Vector2i(x, y)
						if world.thing_at(cell) != WorldGen.Thing.NADA or not world.is_passable(cell) \
								or world.region_of(cell) != world.region_of(corner):
							ok = false
							break
					if not ok:
						break
				if ok:
					return corner
	return WorldGen.NO_CELL


## Um abrigo 4x4 pronto, com a porta ao sul, com uma casa de folga em volta.
func _shelter(state: WorldState) -> Dictionary:
	var corner := _free_square(state.world, 8)
	var origin := corner + Vector2i(2, 2)
	var build := state.builds._new_build(900, "abrigo", origin, 4, "sul")
	build["done"] = true
	build["stage"] = Crafting.stage_count("abrigo")
	state.builds._add(build)
	return state.builds.get_build(900)


func _test_recipes_plan() -> void:
	var bag := {"milho": 4}
	_check(Cooking.plan(bag, "broa")["missing"].is_empty(), "3 espigas bastam para a broa")
	_check(int(Cooking.plan(bag, "broa")["take"]["milho"]) == 3, "a broa leva 3 espigas")
	_check(not Cooking.plan({"milho": 2}, "broa")["missing"].is_empty(), "2 espigas não bastam")
	# Ensopado: a cenoura pedida pelo nome sai primeiro; o grupo pega as outras.
	var stew := {"raiz_cenoura": 2, "raiz_batata": 1, "cogumelo_pardo": 1, "pote": 1}
	var planned := Cooking.plan(stew, "ensopado")
	_check(planned["missing"].is_empty(), "2 cenouras, 1 batata e 1 cogumelo com pote fazem ensopado: %s" % [planned])
	_check(int(planned["take"].get("raiz_cenoura", 0)) == 2 and int(planned["take"].get("raiz_batata", 0)) == 1, "usa as duas cenouras e a batata")
	stew.erase("pote")
	_check(Cooking.plan(stew, "ensopado")["missing"].has("pote"), "sem pote, sem ensopado")
	_check(Cooking.plan({"raiz_batata": 3, "cogumelo_orelha": 1, "pote": 1}, "ensopado")["missing"].has("raiz_cenoura"), "sem cenoura, sem ensopado")
	# Assar tudo: toda raiz e todo milho, de uma vez.
	var roast := Cooking.plan({"raiz_batata": 2, "raiz_cara": 1, "milho": 3, "frutas_amora": 4}, "assar")
	_check(roast["take"].size() == 3 and not roast["take"].has("frutas_amora"), "assar pega raízes e milho, não frutas")
	var made := Cooking.makes("assar", roast["take"])
	_check(int(made.get("raiz_assada", 0)) == 3 and int(made.get("milho_assado", 0)) == 3, "vira 3 raízes assadas e 3 milhos assados")
	_check(not Cooking.plan({"frutas_amora": 1}, "assar")["missing"].is_empty(), "nada para assar")
	_check(Cooking.plan({"pote_cru": 1}, "pote")["missing"].is_empty(), "o pote cru se queima")
	# Comida nova.
	_check(float(Body.food_info("broa")["keeps"]) > float(Body.food_info("milho_assado")["keeps"]), "a broa dura mais que o milho assado")
	_check(float(Body.food_info("ensopado")["warmth"]) > float(Body.food_info("raiz_assada")["warmth"]), "o ensopado aquece mais que a raiz assada")
	_check(Crafting.recipe("pote_cru")["materials"] == {"argila": 3}, "o pote cru leva 3 argilas")
	_check(Crafting.agree("forno", "acesa") == "aceso" and Crafting.agree("fogueira", "acesa") == "acesa", "concordância do forno")


func _test_placement_and_cooking() -> void:
	var state := WorldState.new(173)
	var shelter := _shelter(state)
	_check(not shelter.is_empty(), "achou lugar para o abrigo")
	var origin: Vector2i = shelter["cell"]
	var builds := state.builds
	# Longe do abrigo: precisa encostar.
	_check(builds.refusal("forno", origin + Vector2i(-2, 1)) == "encostar", "longe da parede não serve")
	# Dentro do abrigo não serve.
	_check(builds.refusal("forno", origin + Vector2i(1, 1)) == "lugar", "dentro do abrigo não serve")
	# Na diagonal do canto não encosta.
	_check(builds.refusal("forno", origin + Vector2i(-1, -1)) == "encostar", "na diagonal do canto não encosta")
	# Na frente da porta (sul, meio) não serve.
	var door := Builds.door_cell(origin, 4, "sul")
	_check(builds.refusal("forno", door + Vector2i(0, 1)) == "encostar", "na frente da porta não serve")
	# Colado na parede oeste: serve.
	var spot := origin + Vector2i(-1, 1)
	_check(builds.refusal("forno", spot) == "", "colado na parede oeste serve: " + builds.refusal("forno", spot))
	# Abrigo em obra não recebe forno.
	shelter["done"] = false
	_check(builds.refusal("forno", spot) == "encostar", "abrigo em obra não recebe forno")
	shelter["done"] = true
	# Uma fogueira não pode ficar colada.
	_check(builds.refusal("fogueira", spot) == "perto", "a fogueira continua longe das obras")
	state.add_player(2, "Lua")
	state.players[2]["pos"] = WorldGen.cell_center(spot) + Vector2(-1.1, 0)
	var started := state.start_build(2, "forno", spot)
	_check(started["ok"], "começa o forno: %s" % [started])
	var id := int(started.get("id", -1))
	_check(builds.refusal("forno", origin + Vector2i(4, 1)) == "ja_tem", "um forno por abrigo")
	_check(int(builds.host_of(id).get("id", -1)) == 900, "o forno sabe em que abrigo está")
	# Etapas: base, cúpula (seca), madeira.
	var inv := state.inventory_of(2)
	for item: String in Crafting.total_materials("forno"):
		inv[item] = int(Crafting.total_materials("forno")[item])
	var guard := 0
	var dried_seen := false
	var t := Builds.now()
	while not builds.get_build(id)["done"] and guard < 200:
		guard += 1
		t += 1.0
		var result := builds.work(id, inv, t)
		if result.get("dry", 0.0) > 0.0:
			dried_seen = true
	_check(builds.get_build(id)["done"], "o forno fica pronto (%d ações)" % guard)
	_check(dried_seen, "a cúpula de argila precisa secar")
	_check(builds.fuel_left(id, t) > 0.0, "a madeira da última etapa vira combustível")
	_check(builds.spoken_name(id, t) == "forno apagado", "nome falado: " + builds.spoken_name(id, t))
	for i in Crafting.SPARKS_TO_LIGHT:
		builds.work(id, inv, t)
	_check(builds.is_lit(id, t), "o forno acende")
	_check(builds.spoken_name(id, t) == "forno aceso", "nome falado aceso: " + builds.spoken_name(id, t))
	_check(builds.status_text(id, t).begins_with("Forno aceso"), "texto do forno aceso: " + builds.status_text(id, t))
	# Cozinhar (o fogo vale pelo relógio de verdade).
	builds.get_build(id)["burn_until"] = Builds.now() + 600.0
	inv.clear()
	inv["milho"] = 3
	inv["pote_cru"] = 1
	state.players[2]["pos"] = WorldGen.cell_center(spot) + Vector2(-6.0, 0)
	_check(state.cook_start(2, "broa")["reason"] == "sem_forno", "longe do forno não cozinha")
	state.players[2]["pos"] = WorldGen.cell_center(spot) + Vector2(-1.1, 0)
	var cook := state.cook_start(2, "broa")
	_check(cook["ok"], "cozinha a broa: %s" % [cook])
	_check(not inv.has("milho"), "o milho sai da bolsa na hora")
	_check(state.cook_start(2, "pote")["reason"] == "ocupado", "uma coisa de cada vez")
	var made := state.cook_finish(2)
	_check(int(made.get("broa", 0)) == 1 and int(inv.get("broa", 0)) == 1, "a broa entra na bolsa no fim")
	_check(state.cook_start(2, "pote")["ok"], "queima o pote")
	state.cook_finish(2)
	_check(int(inv.get("pote", 0)) == 1 and not inv.has("pote_cru"), "o pote queimado fica na bolsa")
	inv["raiz_cenoura"] = 1
	inv["raiz_mandioca"] = 2
	inv["cogumelo_orelha"] = 1
	_check(state.cook_start(2, "ensopado")["ok"], "faz o ensopado no pote")
	state.cook_finish(2)
	_check(int(inv.get("ensopado", 0)) == 1 and int(inv.get("pote", 0)) == 1, "o ensopado sai e o pote fica")
	_check(state.cook_start(2, "ensopado")["reason"] == "faltam", "sem ingredientes, não faz de novo")
	# Forno apagado não cozinha.
	builds.get_build(id)["burn_until"] = 0.0
	inv["milho"] = 3
	_check(state.cook_start(2, "broa")["reason"] == "sem_forno", "forno apagado não cozinha")
	# Salva e carrega: continua colado no abrigo.
	var copy := Builds.new(state.world)
	copy.load_save(builds.to_save())
	_check(int(copy.host_of(id).get("id", -1)) == 900, "depois de carregar, o forno segue colado")


func _test_warmth() -> void:
	var cold := {"season": 2, "night": true, "biome": WorldGen.Biome.BOSQUE, "day_seconds": 1800.0}
	var shelter := cold.duplicate()
	shelter["shelter"] = true
	var oven := shelter.duplicate()
	oven["oven"] = true
	var a := {"food": 100.0, "warmth": 10.0}
	var b := {"food": 100.0, "warmth": 10.0}
	Body.step(a, 60.0, shelter)
	Body.step(b, 60.0, oven)
	_check(float(b["warmth"]) > float(a["warmth"]), "o forno aceso aquece o abrigo mais depressa")
	Body.step(a, 1800.0 * 3.0, shelter)
	Body.step(b, 1800.0 * 3.0, oven)
	_check(float(a["warmth"]) == Body.SHELTER_CAP and float(b["warmth"]) == Body.OVEN_CAP, "abrigo sozinho para em %d, com forno em %d" % [Body.SHELTER_CAP, Body.OVEN_CAP])
