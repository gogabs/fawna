extends SceneTree
## Testes das plantas por categoria (Plants): espécies, onde nascem, o que dão,
## a fala para quem é e quem não é Forrageador, frutas e raízes na Bolsa e a
## raiz que só sai da rama.
## Rodar: godot --headless --path . --script res://tests/test_plants.gd

const SEARCH := 160

var _failures := 0


func _init() -> void:
	_test_names()
	_test_species_and_placement()
	_test_yield_and_speech()
	_test_digging()
	_test_winter_and_rama()
	_test_migration_and_food()
	_test_new_plants()
	if _failures == 0:
		print("OK: todos os testes passaram")
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FALHOU: " + message)


## Primeira casa (do centro para fora) com esta coisa e com uma vizinha livre:
## [casa livre ao lado, casa da coisa]. "species" filtra pela espécie.
func _find(world: WorldGen, thing: WorldGen.Thing, species := "") -> Array:
	for r in range(1, SEARCH):
		for y in range(-r, r + 1):
			for x in [-r, r]:
				for cell in [Vector2i(x, y), Vector2i(y, x)]:
					if world.thing_at(cell) != thing:
						continue
					if not species.is_empty() and Plants.species_at(world, cell) != species:
						continue
					for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
						if world.is_passable(cell + d) and world.is_free(WorldGen.cell_center(cell + d)):
							return [cell + d, cell]
	return []


func _test_names() -> void:
	_check(Economy.base_of("frutas_amora") == "frutas" and Economy.base_of("raiz_cara") == "raiz", "espécie tem grupo")
	_check(Economy.base_of("raiz_assada") == "raiz_assada", "raiz assada não é espécie de raiz")
	_check(Economy.item_text("frutas_amora", 2) == "2 amoras", "fala a espécie: %s" % Economy.item_text("frutas_amora", 2))
	_check(Economy.item_text("raiz_cara", 1) == "1 cará", "um cará")
	var bag := {"frutas_amora": 2, "frutas_pitanga": 1, "raiz_batata": 3}
	_check(Bag.entries(bag) == [["frutas", 3], ["raiz", 3]], "Bolsa agrupa: %s" % [Bag.entries(bag)])
	_check(Bag.entry_label("frutas", 3, bag) == "Fruta, 2 amoras, 1 pitanga", "rótulo: %s" % Bag.entry_label("frutas", 3, bag))
	_check(Bag.keys_of(bag, "frutas") == ["frutas_amora", "frutas_pitanga"], "chaves do grupo")
	_check(Bag.count(bag, "raiz") == 3, "conta o grupo")
	_check(Body.eat_text("frutas_amora") == "uma amora", "come uma amora")
	_check(Body.eat_text("raiz_cara") == "um cará cru", "come um cará cru: %s" % Body.eat_text("raiz_cara"))
	_check(Body.eat_text("raiz_assada") == "uma raiz assada, ainda quente", "raiz assada mantém a frase")
	_check(Body.roast_of("raiz_mandioca") == "raiz_assada" and Body.roast_of("frutas_amora").is_empty(), "toda raiz assa, fruta não")
	_check(Body.keeps("raiz_mandioca") < Body.keeps("raiz_batata"), "mandioca crua estraga antes")


func _test_species_and_placement() -> void:
	var world := WorldGen.new(42)
	var seen := {}
	var open_fruit := true
	var water_fruit := false
	for y in range(-SEARCH, SEARCH, 2):
		for x in range(-SEARCH, SEARCH, 2):
			var cell := Vector2i(x, y)
			var thing := world.thing_at(cell)
			var species := Plants.species_at(world, cell)
			if not species.is_empty():
				seen[species] = true
			if thing == WorldGen.Thing.ARBUSTO_FRUTAS:
				if world.cover_of(world.region_of(cell)) != WorldGen.Cover.ABERTA:
					open_fruit = false
				if world.is_waterside(cell):
					water_fruit = true
			if thing == WorldGen.Thing.RAMA:
				_check(WorldGen.ROOT_PLANT_BIOMES.has(world.biome_at(cell)), "rama só no campo, no brejo e no bosque")
	_check(open_fruit, "arbusto de fruta só no campo aberto")
	_check(not water_fruit, "na beira da água o arbusto é de fibra")
	for species in ["amora", "pitanga", "embira", "batata", "mandioca", "cipo", "maracuja", "castanheira"]:
		_check(seen.has(species), "deveria haver %s perto do centro" % species)
	# A espécie é fixa pela casa e pela semente.
	var other := WorldGen.new(42)
	var bush: Vector2i = _find(world, WorldGen.Thing.ARBUSTO_FRUTAS)[1]
	_check(Plants.species_at(world, bush) == Plants.species_at(other, bush), "mesma semente, mesma espécie")
	_check(Plants.root_species(WorldGen.Biome.PRADARIA) == "batata" and Plants.root_species(WorldGen.Biome.BREJO) == "cara"
		and Plants.root_species(WorldGen.Biome.BOSQUE) == "mandioca", "raiz por bioma")


func _test_yield_and_speech() -> void:
	var world := WorldGen.new(42)
	var harvest := Harvest.new(world)
	var bush: Vector2i = _find(world, WorldGen.Thing.ARBUSTO_FRUTAS)[1]
	var species := Plants.species_at(world, bush)
	_check(harvest.spoken_name(bush) == "arbusto", "quem não é Forrageador vê só arbusto")
	harvest.knows_plants = true
	_check(harvest.spoken_name(bush) == Plants.name_of(species), "o Forrageador vê a espécie: %s" % harvest.spoken_name(bush))
	harvest.knows_plants = false
	var got := harvest.take(bush, 1000.0)
	var fruit := Economy.sized("frutas", str(Plants.SPECIES[species]["fruit"]))
	_check(got["ok"] and got["item"] == "frutas" and got["parts"] == {fruit: 2}, "o arbusto dá a fruta da espécie: %s" % got)
	_check(Economy.collected_text("frutas", 2, got["parts"]).ends_with(Economy.names_of(fruit)[1]), "a coleta diz a espécie")
	var fiber: Vector2i = _find(world, WorldGen.Thing.ARBUSTO)[1]
	got = harvest.take(fiber, 1000.0)
	_check(got["ok"] and got["item"] == "fibra", "arbusto de fibra dá fibra")
	var vine := _find(world, WorldGen.Thing.CIPO, "cipo")
	got = harvest.take(vine[1], 1000.0)
	_check(got["ok"] and got["item"] == "cipo", "cipó dá cipó")
	_check(harvest.spoken_name(_find(world, WorldGen.Thing.CIPO)[1]) in ["trepadeira", ""], "trepadeira para quem não conhece")
	var grass: Vector2i = _find(world, WorldGen.Thing.FIBRA, "capim")[1]
	_check(harvest.spoken_name(grass) == "capim" and Plants.species_at(world, grass) == "capim", "a fibra solta é capim")
	got = harvest.take(grass, 1000.0)
	_check(got["ok"] and got["item"] == "fibra", "capim dá fibra")
	_check(Plants.category_name("batata") == "rama" and Plants.with_article("batata") == "o pé de batata"
		and Plants.with_article("embira") == "a embira", "categoria e artigo")
	var passion := _find(world, WorldGen.Thing.CIPO, "maracuja")
	got = harvest.take(passion[1], 1000.0)
	_check(got["ok"] and got["parts"] == {"frutas_maracuja": 1}, "maracujá dá maracujá: %s" % got)


func _test_digging() -> void:
	var state := WorldState.new(42)
	state.add_player(1, "Lua")
	var spot := _find(state.world, WorldGen.Thing.RAMA)
	_check(not spot.is_empty(), "deveria haver uma rama")
	state.players[1]["pos"] = WorldGen.cell_center(spot[0])
	_check(state.dig_roots(1, spot[1])["reason"] == "sem_enxada", "sem enxada não cava")
	state.inventory_of(1)["enxada"] = 1
	state.equip(1, "enxada")
	_check(state.collect(1, spot[1])["reason"] == "cavar", "com a mão, a rama manda cavar")
	var far: Vector2i = spot[0] + Vector2i(30, 30)
	state.players[1]["pos"] = WorldGen.cell_center(far)
	if state.world.thing_at(far) == WorldGen.Thing.NADA:
		_check(state.dig_roots(1, far)["reason"] == "terreno", "terra sem rama não dá raiz")
	state.players[1]["pos"] = WorldGen.cell_center(spot[0])
	for i in Body.ROOT_DIG_HITS - 1:
		_check(state.dig_roots(1, spot[1])["reason"] == "cavando", "golpe %d ainda cavando" % (i + 1))
	var result := state.dig_roots(1, spot[1])
	var item := Plants.root_item(Plants.species_at(state.world, spot[1]))
	_check(result["ok"] and result["item"] == item and int(state.inventory_of(1).get(item, 0)) == Body.ROOT_AMOUNT,
		"no último golpe a raiz sai: %s" % [state.inventory_of(1)])
	_check(not state.harvest.is_available(spot[1]), "a rama cavada some até rebrotar")


func _test_winter_and_rama() -> void:
	var state := WorldState.new(42)
	state.add_player(1, "Lua")
	var spot := _find(state.world, WorldGen.Thing.ARBUSTO_FRUTAS)
	state.players[1]["pos"] = WorldGen.cell_center(spot[0])
	state.day_n = int(DayCycle.season_start_day(2))
	_check(state.season() == 2, "Longa Escuridão")
	_check(state.collect(1, spot[1])["reason"] == "sem_frutas", "no inverno o pé de fruta não dá nada")
	state.day_n = int(DayCycle.season_start_day(0))
	_check(state.collect(1, spot[1])["ok"], "na Coroada dá")


func _test_migration_and_food() -> void:
	var state := WorldState.from_save({"seed": 42, "inventories": {"Lua": {"frutas": 3, "raiz": 2, "raiz_assada": 1}}})
	_check(state.inventories["Lua"] == {"frutas_amora": 3, "raiz_batata": 2, "raiz_assada": 1}, "saves antigos: %s" % [state.inventories["Lua"]])
	state.add_player(1, "Lua")
	state.body_of(1)["food"] = 50.0
	_check(state.eat(1, "frutas_amora")["ok"], "come amora")
	_check(state.roast(1, "raiz_batata", 2, [state.players[1]["pos"]])["ok"], "assa batata")
	_check(int(state.inventory_of(1).get("raiz_assada", 0)) == 3, "batata assada vira raiz assada")


func _test_new_plants() -> void:
	var world := WorldGen.new(42)
	var harvest := Harvest.new(world)
	var mushroom := _find(world, WorldGen.Thing.COGUMELO)
	_check(not mushroom.is_empty(), "deveria haver cogumelo")
	_check(harvest.spoken_name(mushroom[1]) == "cogumelo", "quem não conhece vê cogumelo")
	var got := harvest.take(mushroom[1], 1000.0)
	_check(got["ok"] and got["item"] == "cogumelo" and Economy.base_of(got["parts"].keys()[0]) == "cogumelo", "cogumelo dá cogumelo da espécie: %s" % got)
	_check(Body.is_food(got["parts"].keys()[0]), "cogumelo se come")
	var corn := _find(world, WorldGen.Thing.FIBRA, "milho")
	_check(not corn.is_empty(), "deveria haver capim de milho no campo")
	_check(harvest.spoken_name(corn[1]) == "capim", "o milho é capim para quem não conhece")
	got = harvest.take(corn[1], 1000.0)
	_check(got["ok"] and got["item"] == "milho" and int(got["amount"]) == 2, "milho dá 2 espigas")
	_check(harvest.regrow_time(corn[1]) == 1800.0, "o milho volta devagar")
	_check(Body.roast_of("milho") == "milho_assado" and Body.eat_text("milho_assado") == "uma espiga assada, ainda quente", "milho assa")
	var carrot := _find(world, WorldGen.Thing.RAMA, "cenoura")
	_check(not carrot.is_empty(), "deveria haver rama de cenoura")
	_check(Plants.root_item("cenoura") == "raiz_cenoura" and Body.eat_text("raiz_cenoura") == "uma cenoura", "cenoura crua não é \"crua\"")
	var entry := {"food": 50.0}
	for i in 5:
		Body.eat(entry, "raiz_cenoura")
	_check(not entry.has("raw"), "cenoura não enjoa")
	# No inverno, nem milho nem cogumelo.
	var state := WorldState.new(42)
	state.add_player(1, "Lua")
	state.day_n = int(DayCycle.season_start_day(2))
	var spot := _find(state.world, WorldGen.Thing.COGUMELO)
	state.players[1]["pos"] = WorldGen.cell_center(spot[0])
	_check(state.collect(1, spot[1])["reason"] == "sem_frutas", "sem cogumelo na Longa Escuridão")
