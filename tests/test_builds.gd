extends SceneTree
## Testes da fabricação: construções em etapas (marco, fogueira), fogo e armas.
## Rodar: godot --headless --path . --script res://tests/test_builds.gd

var _failures := 0


func _init() -> void:
	_test_marco_stages()
	_test_refusals()
	_test_fire()
	_test_weapons()
	_test_save_round_trip()
	_test_network_mirror()
	_test_texts()
	_test_settlements()
	_test_name_lists()
	_test_region_lists()
	if _failures == 0:
		print("OK: todos os testes passaram")
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FALHOU: " + message)


## Uma casa livre (chão sem nada) perto da Origem, com espaço em volta.
func _free_cell(world: WorldGen, skip := 0) -> Vector2i:
	var origin := WorldGen.cell_of(WorldGen.origin_point())
	var found := 0
	for r in range(4, 40):
		for dx in range(-r, r + 1):
			for dy in [-r, r]:
				var cell := origin + Vector2i(dx, dy)
				var ok := true
				for oy in range(-1, 2):
					for ox in range(-1, 2):
						if world.thing_at(cell + Vector2i(ox, oy)) != WorldGen.Thing.NADA:
							ok = false
				if ok:
					if found == skip:
						return cell
					found += 1
	return WorldGen.NO_CELL


func _state_with_player(cell: Vector2i) -> WorldState:
	var state := WorldState.new(173)
	state.add_player(2, "Lua")
	state.players[2]["pos"] = WorldGen.cell_center(cell) + Vector2(0, 1.1)
	return state


func _work(state: WorldState, build_id: int) -> Dictionary:
	state._last_build.erase(2)  # sem esperar o intervalo entre batidas
	return state.work_build(2, build_id)


func _test_marco_stages() -> void:
	var probe := WorldGen.new(173)
	var cell := _free_cell(probe)
	var state := _state_with_player(cell)
	var started := state.start_build(2, "marco", cell)
	_check(started["ok"], "começa um marco em chão livre à frente")
	var id: int = started["id"]
	_check(not state.world.is_passable(cell), "a obra ocupa a casa e não deixa passar")
	var inv := state.inventory_of(2)
	var result := _work(state, id)
	_check(not result["ok"] and result["reason"] == "faltam", "sem pedras, Espaço diz o que falta")
	_check(int(result["missing"].get("pedra_grande", 0)) == 3, "a base pede 3 pedras grandes")
	inv["pedra_grande"] = 2
	result = _work(state, id)
	_check(result["ok"] and result["event"] == "deposito" and int(result["deposited"]["pedra_grande"]) == 2, "deposita o que tem")
	_check(not inv.has("pedra_grande"), "e as pedras saem da bolsa")
	_check(int(result["missing"]["pedra_grande"]) == 1, "ainda falta uma")
	inv["pedra_grande"] = 5
	result = _work(state, id)
	_check(int(inv["pedra_grande"]) == 4, "deposita só o que falta, nem uma pedra a mais")
	for i in 2:
		result = _work(state, id)
		_check(result["event"] == "trabalho", "batidas da base")
	result = _work(state, id)
	_check(result["event"] == "etapa" and result["next"] == "o corpo", "a base termina na terceira batida")
	inv["pedra_media"] = 2
	inv["pedra_pequena"] = 1
	_work(state, id)
	_work(state, id)
	result = _work(state, id)
	_check(result["event"] == "etapa", "o corpo termina")
	_work(state, id)
	result = _work(state, id)
	_check(result["event"] == "pronta", "o topo termina e o marco fica pronto")
	_check(state.builds.marked_regions().is_empty(), "marco pronto sem nome ainda não é um local")
	result = _work(state, id)
	_check(not result["ok"] and result["reason"] == "pronta", "marco pronto não pede mais nada")
	_check(Crafting.total_materials("marco") == {"pedra_grande": 3, "pedra_media": 2, "pedra_pequena": 1}, "marco custa 3 grandes, 2 médias e 1 pequena")


func _test_refusals() -> void:
	var probe := WorldGen.new(173)
	var cell := _free_cell(probe)
	var state := _state_with_player(cell)
	_check(state.start_build(2, "marco", cell + Vector2i(0, 9))["reason"] == "longe", "não começa longe")
	_check(state.start_build(2, "marco", WorldGen.cell_of(WorldGen.origin_point()))["reason"] in ["longe", "lugar"], "não começa na Origem")
	_check(state.start_build(2, "marco", WorldGen.cell_of(state.players[2]["pos"]))["reason"] == "ocupado", "não constrói em cima de alguém")
	_check(state.start_build(2, "marco", cell)["ok"], "começa o primeiro")
	_check(state.builds.refusal("fogueira", cell + Vector2i(1, 0)) == "perto", "não cola outra obra")
	var far := cell + Vector2i(4, 0)
	if state.world.region_of(far) == state.world.region_of(cell) and state.world.thing_at(far) == WorldGen.Thing.NADA:
		_check(state.builds.refusal("marco", far) == "regiao", "um marco por região")
		_check(state.builds.refusal("fogueira", far) == "", "fogueiras podem ser várias")
	var water := Vector2i.ZERO
	for y in range(-60, 60):
		for x in range(-60, 60):
			if probe.thing_at(Vector2i(x, y)) == WorldGen.Thing.RIACHO or probe.thing_at(Vector2i(x, y)) == WorldGen.Thing.LAGO:
				water = Vector2i(x, y)
	_check(state.builds.refusal("fogueira", water) == "lugar", "não constrói na água")


func _test_fire() -> void:
	var probe := WorldGen.new(173)
	var cell := _free_cell(probe)
	var state := _state_with_player(cell)
	var id: int = state.start_build(2, "fogueira", cell)["id"]
	var inv := state.inventory_of(2)
	for item in ["pedra_media", "pedra_pequena", "lenha_media", "lenha_pequena"]:
		inv[item] = 10
	var result := {}
	for i in 20:
		result = _work(state, id)
		if result.get("event", "") == "pronta":
			break
	_check(result.get("event", "") == "pronta", "a fogueira fica pronta")
	var builds := state.builds
	var expected := 2 * Crafting.FUEL_SECONDS["lenha_media"] + 3 * Crafting.FUEL_SECONDS["lenha_pequena"]
	_check(is_equal_approx(builds.fuel_left(id), expected), "a lenha da última etapa é o primeiro combustível")
	_check(not builds.is_lit(id), "pronta, mas apagada")
	var t := Builds.now()
	result = builds.work(id, inv, t)
	_check(not result["ok"] and result["reason"] == "sem_silex", "sem sílex, não dá para acender")
	inv["silex"] = 2
	for i in Crafting.SPARKS_TO_LIGHT - 1:
		result = builds.work(id, inv, t)
		_check(result["event"] == "faisca", "batidas de pedra soltam faíscas")
	result = builds.work(id, inv, t)
	_check(result["event"] == "acesa" and builds.is_lit(id, t), "acende na quarta batida")
	_check(int(inv.get("silex", 0)) == 1, "acender gasta 1 sílex")
	var lenha_before := int(inv["lenha_media"])
	result = builds.work(id, inv, t)
	_check(result["event"] == "alimentou" and int(inv["lenha_media"]) == lenha_before - 1, "acesa, Espaço põe uma lenha média")
	_check(is_equal_approx(builds.fuel_left(id, t), expected + Crafting.FUEL_SECONDS["lenha_media"]), "e ela queima mais tempo")
	var out_at := t + builds.fuel_left(id, t) + 1.0
	_check(builds.burn_out(t + 10.0).is_empty(), "não apaga antes da hora")
	_check(builds.burn_out(out_at) == [id] and not builds.is_lit(id, out_at), "apaga quando a lenha acaba")
	inv.erase("lenha_media")
	inv.erase("lenha_pequena")
	result = builds.work(id, inv, out_at)
	_check(not result["ok"] and result["reason"] == "sem_lenha", "apagada e sem lenha, avisa")
	inv["lenha_pequena"] = 1
	inv["silex"] = 1
	result = builds.work(id, inv, out_at)
	_check(result["event"] == "abasteceu" and is_equal_approx(builds.fuel_left(id, out_at), Crafting.FUEL_SECONDS["lenha_pequena"]), "lenha numa fogueira apagada fica guardada")
	result = builds.work(id, inv, out_at)
	_check(result["event"] == "faisca", "com lenha, Espaço volta a bater as pedras")


func _test_weapons() -> void:
	var state := WorldState.new(1)
	state.add_player(2, "Sol")
	var result := state.craft(2, "lanca")
	_check(not result["ok"] and result["reason"] == "faltam", "sem materiais, não faz a lança")
	var inv := state.inventory_of(2)
	inv["bambu"] = 2
	inv["silex"] = 1
	result = state.craft(2, "lanca")
	_check(result["ok"] and int(inv["lanca"]) == 1, "faz a lança")
	_check(int(inv["bambu"]) == 1 and not inv.has("silex"), "gastando 1 bambu e 1 sílex")
	_check(state.equip(2, "lanca")["ok"] and state.wielding(2) == "lanca", "a lança pode ser empunhada")
	inv["lenha_media"] = 1
	inv["pedra_media"] = 1
	_check(state.craft(2, "clava")["ok"] and int(inv["clava"]) == 1, "faz a clava")
	_check(Bag.with_article("lanca") == "a lança de bambu" and Bag.with_article("machado") == "o machado", "artigos certos na fala")


func _test_save_round_trip() -> void:
	var probe := WorldGen.new(173)
	var cell := _free_cell(probe)
	var state := _state_with_player(cell)
	var id: int = state.start_build(2, "marco", cell)["id"]
	state.inventory_of(2)["pedra_grande"] = 3
	_work(state, id)
	_work(state, id)
	var data: Dictionary = JSON.parse_string(JSON.stringify(state.to_save()))
	var loaded := WorldState.from_save(data)
	var build := loaded.builds.at(cell)
	_check(not build.is_empty() and build["kind"] == "marco", "a obra volta do mundo.json")
	_check(int(build["deposited"].get("pedra_grande", 0)) == 3 and int(build["work"]) == 1, "com o que foi depositado e trabalhado")
	_check(not loaded.world.is_passable(cell), "e continua ocupando a casa")
	var second := loaded.builds.start("fogueira", _free_cell(probe, 3))
	_check(second["ok"] and int(second["id"]) != id, "ids novos não repetem os salvos")


func _test_network_mirror() -> void:
	var probe := WorldGen.new(173)
	var cell := _free_cell(probe)
	var state := _state_with_player(cell)
	var id: int = state.start_build(2, "fogueira", cell)["id"]
	var mirror := Builds.new(WorldGen.new(173))
	mirror.apply_snapshot(state.builds.snapshot())
	_check(not mirror.at(cell).is_empty() and not mirror.world.is_passable(cell), "o cliente recebe a obra e a colisão")
	_check(mirror.spoken_name(id) == "fogueira em obra", "e sabe falar dela")
	var other := mirror.world
	mirror.apply_snapshot([])
	_check(mirror.at(cell).is_empty() and other.is_passable(cell), "um retrato vazio limpa tudo")


func _test_texts() -> void:
	_check(Crafting.materials_text({"pedra_pequena": 1, "pedra_grande": 3}) == "3 pedras grandes e 1 pedra pequena", "materiais falados em ordem")
	_check(Crafting.build_summary("marco").begins_with("3 etapas. A base, 3 pedras grandes"), "resumo do marco: " + Crafting.build_summary("marco"))


## Constrói até o fim, com a bolsa cheia do que for preciso.
func _finish(state: WorldState, id: int) -> void:
	var inv := state.inventory_of(2)
	for item: String in ["pedra_grande", "pedra_media", "pedra_pequena", "lenha_media", "lenha_pequena"]:
		inv[item] = 20
	for i in 40:
		if state.builds.get_build(id)["done"]:
			return
		_work(state, id)


## Uma casa livre na mesma região de "cell", longe o bastante para não colar.
func _free_cell_in_region(world: WorldGen, cell: Vector2i) -> Vector2i:
	for skip in range(1, 200):
		var other := _free_cell(world, skip)
		if other == WorldGen.NO_CELL:
			break
		if world.region_of(other) == world.region_of(cell) and maxi(absi(other.x - cell.x), absi(other.y - cell.y)) > 2:
			return other
	return WorldGen.NO_CELL


func _test_settlements() -> void:
	var probe := WorldGen.new(173)
	var cell := _free_cell(probe)
	var fire_cell := _free_cell_in_region(probe, cell)
	_check(fire_cell != WorldGen.NO_CELL, "há lugar para a fogueira na mesma região")
	var state := _state_with_player(cell)
	var marco: int = state.start_build(2, "marco", cell)["id"]
	_check(state.builds.get_build(marco)["name"] == "", "o marco começa sem nome")
	_check(state.builds.spoken_name(marco) == "marco em obra", "e a fala não inventa um")
	var offered := SettlementNames.options(state.world.world_seed, marco)
	var noun: int = offered["nouns"][0]
	var adjective: int = offered["adjectives"][0]
	_check(state.name_settlement(2, marco, noun, adjective)["reason"] == "em_obra", "marco em obra não recebe nome")
	_finish(state, marco)
	_check(state.builds.get_build(marco)["done"], "o marco fica pronto")
	_check(state.builds.naming_refusal(marco) == "sem_fogueira", "sem fogueira na região, não dá para nomear")
	_check(state.builds.status_text(marco).contains("fogueira"), "e a fala explica: " + state.builds.status_text(marco))
	_check(state.builds.settlements().is_empty(), "marco sem nome não é povoado")
	var fire: int = state.builds.start("fogueira", fire_cell)["id"]
	_check(not state.builds.can_name(marco), "fogueira em obra ainda não conta")
	_check(not state.builds.has_fire(state.world.region_of(cell)), "nem para a região")
	state.players[2]["pos"] = WorldGen.cell_center(fire_cell) + Vector2(0, 1.1)
	_finish(state, fire)
	_check(state.builds.can_name(marco), "marco e fogueira prontos na mesma região: dá para nomear")
	_check(state.builds.has_unnamed_marco(state.world.region_of(cell)), "a região tem um marco esperando nome")
	_check(state.builds.status_text(marco).contains("Espaço"), "a fala convida a nomear: " + state.builds.status_text(marco))
	_check(state.name_settlement(2, marco, noun, adjective)["reason"] == "longe", "de longe, não nomeia")
	state.players[2]["pos"] = WorldGen.cell_center(cell) + Vector2(0, 1.1)
	var outside := 0
	while offered["nouns"].has(outside):
		outside += 1
	_check(state.name_settlement(2, marco, outside, adjective)["reason"] == "opcao", "só vale palavra que foi oferecida")
	var named := state.name_settlement(2, marco, noun, adjective)
	_check(named["ok"] and named["name"] == SettlementNames.compose(noun, adjective), "o nome é o substantivo com o adjetivo")
	_check(state.builds.settlements().size() == 1 and state.builds.marked_regions() == [state.world.region_of(cell)], "agora é um povoado")
	_check(state.builds.title_of(marco) == "Marco " + named["name"], "o nome entra no título")
	_check(state.name_settlement(2, marco, noun, offered["adjectives"][1])["reason"] == "ja_tem_nome", "não dá para nomear de novo")
	_check(state.builds.name_taken(named["name"].to_upper()), "o nome fica ocupado")
	var mirror := Builds.new(WorldGen.new(173))
	mirror.apply_snapshot(state.builds.snapshot())
	_check(mirror.get_build(marco)["name"] == named["name"] and mirror.settlements().size() == 1, "o nome chega ao cliente")
	var loaded := WorldState.from_save(JSON.parse_string(JSON.stringify(state.to_save())))
	_check(loaded.builds.get_build(marco)["name"] == named["name"], "e fica salvo")
	# Mundo antigo: o nome vinha ao começar o marco.
	var old := Builds.new(WorldGen.new(173))
	old.load_save({"next_id": 3, "list": [
		{"id": 1, "kind": "marco", "x": cell.x, "y": cell.y, "done": false, "name": "Casa da Lua"},
		{"id": 2, "kind": "marco", "x": fire_cell.x, "y": fire_cell.y, "stage": 3, "done": true, "name": "Casa do Sol"}]})
	_check(old.get_build(1)["name"] == "" and old.get_build(2)["name"] == "Casa do Sol", "mundo antigo: marco pronto guarda o nome, em obra perde")


func _test_name_lists() -> void:
	var seen_nouns := {}
	for entry: Array in SettlementNames.NOUNS:
		_check(entry.size() == 2 and entry[1] in ["m", "f"], "substantivo com gênero: %s" % [entry])
		_check(not seen_nouns.has(entry[0]), "substantivo repetido: " + entry[0])
		seen_nouns[entry[0]] = true
	var seen_adjectives := {}
	for entry: Array in SettlementNames.ADJECTIVES:
		_check(entry.size() == 2, "adjetivo com as duas formas: %s" % [entry])
		_check(not seen_adjectives.has(entry[0]) and not seen_nouns.has(entry[0]), "adjetivo repetido: " + entry[0])
		seen_adjectives[entry[0]] = true
	var first := SettlementNames.options(42, 7)
	_check(first == SettlementNames.options(42, 7), "as opções de um marco são sempre as mesmas")
	_check(first != SettlementNames.options(42, 8), "e mudam de um marco para outro")
	for key: String in ["nouns", "adjectives"]:
		var unique := {}
		for index: int in first[key]:
			unique[index] = true
		_check(first[key].size() == SettlementNames.OPTIONS and unique.size() == SettlementNames.OPTIONS, "%d opções diferentes em %s" % [SettlementNames.OPTIONS, key])
	var clareira := 0
	var vale := 0
	for i in SettlementNames.NOUNS.size():
		if SettlementNames.NOUNS[i][0] == "Clareira":
			clareira = i
		elif SettlementNames.NOUNS[i][0] == "Vale":
			vale = i
	_check(SettlementNames.compose(clareira, 2) == "Clareira Esquecida", "o adjetivo concorda no feminino")
	_check(SettlementNames.compose(vale, 2) == "Vale Esquecido", "e no masculino")
	_check(SettlementNames.compose(-1, 2) == "" and SettlementNames.compose(vale, 999) == "", "índice que não existe não vira nome")


func _test_region_lists() -> void:
	var probe := WorldGen.new(173)
	var cell := _free_cell(probe)
	var builds := Builds.new(WorldGen.new(173))
	var here: int = builds.start("fogueira", cell)["id"]
	var far := cell + Vector2i(WorldGen.REGION_SIZE * 2, 0)
	for step in 40:
		if builds.refusal("fogueira", far).is_empty():
			break
		far += Vector2i(1, 1)
	var there: int = builds.start("fogueira", far)["id"]
	var ids := builds.in_region(probe.region_of(cell)).map(func(b): return int(b["id"]))
	_check(ids == [here], "só as construções da região: %s" % [ids])
	_check(builds.in_region(probe.region_of(far)).map(func(b): return int(b["id"])) == [there], "e a outra região tem a dela")
