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
	_check(state.builds.marked_regions() == [state.world.region_of(cell)], "a região do marco vira um local")
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
	for i in Crafting.SPARKS_TO_LIGHT - 1:
		result = builds.work(id, inv, t)
		_check(result["event"] == "faisca", "batidas de pedra soltam faíscas")
	result = builds.work(id, inv, t)
	_check(result["event"] == "acesa" and builds.is_lit(id, t), "acende na quarta batida")
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
	inv["pedra_pequena"] = 1
	result = state.craft(2, "lanca")
	_check(result["ok"] and int(inv["lanca"]) == 1, "faz a lança")
	_check(int(inv["bambu"]) == 1 and not inv.has("pedra_pequena"), "gastando 1 bambu e 1 pedra pequena")
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
