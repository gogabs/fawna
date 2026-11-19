extends SceneTree
## Testes da oficina: móveis ao lado da porta, bancada e prateleiras.
## Rodar: godot --headless --path . --script res://tests/test_workshop.gd

var _failures := 0


func _init() -> void:
	_test_recipe()
	_test_furniture_sides()
	_test_interaction()
	_test_bench_and_shelves()
	if _failures == 0:
		print("OK: todos os testes passaram")
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FALHOU: " + message)


func _workshop(state: WorldState, entrance: String, size := 5, done := true) -> Dictionary:
	var cell := WorldGen.cell_of(WorldGen.origin_point()) + Vector2i(30, 30)
	var build := state.builds._fill(state.builds._new_build(1, "oficina", cell, size, entrance), {"size": size, "entrance": entrance}, 0.0)
	build["done"] = done
	state.builds._add(build)
	return build


func _test_recipe() -> void:
	_check(Crafting.BUILDS.has("oficina") and Crafting.is_large("oficina"), "a oficina é construção grande")
	_check("oficina" in Crafting.BUILD_ORDER, "a oficina aparece no menu")
	_check(int(Crafting.BUILDS["oficina"]["size"]["min"]) >= 5, "a oficina tem pelo menos 5 casas de lado")
	_check(Crafting.walls_stage("oficina") >= 0, "a oficina tem paredes (e porta)")
	_check(Crafting.STORAGE.has("oficina") and Crafting.STORAGE["oficina"]["accepts"].has("ferramenta"), "as prateleiras guardam ferramentas")


func _test_furniture_sides() -> void:
	# Quem entra pela porta vê a bancada à esquerda e as prateleiras à direita.
	var expected := {
		"sul": [Vector2i(-1, 0), Vector2i(1, 0)],
		"norte": [Vector2i(1, 0), Vector2i(-1, 0)],
		"leste": [Vector2i(0, 1), Vector2i(0, -1)],
		"oeste": [Vector2i(0, -1), Vector2i(0, 1)],
	}
	for entrance: String in expected:
		for size in [5, 6, 7]:
			var state := WorldState.new(173)
			var build := _workshop(state, entrance, size)
			var door := Builds.door_cell(build["cell"], size, entrance)
			var cells := Builds.furniture_cells(build)
			var facing := Builds.inward(entrance)
			_check(cells["bancada"] == door + facing + expected[entrance][0], "bancada à esquerda, porta %s, %d" % [entrance, size])
			_check(cells["prateleiras"] == door + facing + expected[entrance][1], "prateleiras à direita, porta %s, %d" % [entrance, size])
			for name: String in cells:
				var inner: Vector2i = cells[name] - build["cell"]
				_check(inner.x > 0 and inner.y > 0 and inner.x < size - 1 and inner.y < size - 1, "%s dentro da oficina (%s, %d)" % [name, entrance, size])
				_check(state.world.built.has(cells[name]), "%s bloqueia a passagem (%s, %d)" % [name, entrance, size])
			_check(state.world.is_free(WorldGen.cell_center(door + facing)), "o caminho junto da porta fica livre (%s, %d)" % [entrance, size])
	var open_state := WorldState.new(173)
	var unfinished := _workshop(open_state, "sul", 5, false)
	_check(Builds.furniture_cells(unfinished).size() == 2 and not Builds.has_furniture(unfinished), "sem estar pronta, não há móveis")


func _test_interaction() -> void:
	var state := WorldState.new(173)
	var build := _workshop(state, "sul")
	var cells := Builds.furniture_cells(build)
	var door := WorldGen.cell_center(Builds.door_cell(build["cell"], 5, "sul"))
	_check(Builds.furniture_near(build, door + Vector2(0, 1.5)).is_empty(), "fora, longe dos móveis, nada")
	_check(Builds.furniture_near(build, door).is_empty(), "na porta, a porta vence")
	var beside_bench := WorldGen.cell_center(cells["bancada"]) + Vector2(0, -1.0)
	_check(Builds.furniture_near(build, beside_bench) == "bancada", "junto da bancada")
	var beside_shelves := WorldGen.cell_center(cells["prateleiras"]) + Vector2(0, -1.0)
	_check(Builds.furniture_near(build, beside_shelves) == "prateleiras", "junto das prateleiras")
	var r: Dictionary = state.builds.work(1, {}, -1.0, beside_bench)
	_check(not r["ok"] and r["reason"] == "movel" and r["furniture"] == "bancada", "Espaço junto da bancada não mexe na porta")
	var open_before := bool(build["door_open"])
	r = state.builds.work(1, {}, -1.0, door)
	_check(r["ok"] and r["event"] == "porta" and bool(build["door_open"]) != open_before, "Espaço na porta abre e fecha")


func _test_bench_and_shelves() -> void:
	var state := WorldState.new(173)
	var build := _workshop(state, "sul")
	var cells := Builds.furniture_cells(build)
	state.add_player(1, "ana")
	var bench_pos := WorldGen.cell_center(cells["bancada"]) + Vector2(0, -1.0)
	var shelf_pos := WorldGen.cell_center(cells["prateleiras"]) + Vector2(0, -1.0)
	var inv := state.inventory_of(1)
	for item: String in Crafting.WORKSHOP["tocha"]["materials"]:
		inv[item] = 5
	state.players[1]["pos"] = bench_pos + Vector2(0, -5)
	var r := state.craft(1, "tocha")
	_check(not r["ok"] and r["reason"] == "sem_bancada", "longe da bancada não se faz a tocha")
	state.players[1]["pos"] = bench_pos
	r = state.craft(1, "tocha")
	_check(r["ok"], "na bancada faz a tocha")
	# Prateleiras: só ferramentas e armas, e só junto delas.
	inv["machado"] = 1
	inv["bambu"] = 4
	state._last_drop.clear()
	state.players[1]["pos"] = bench_pos
	r = state.store_in_build(1, 1, "machado", 1)
	_check(not r["ok"], "longe das prateleiras não guarda")
	state._last_drop.clear()
	state.players[1]["pos"] = shelf_pos
	r = state.store_in_build(1, 1, "machado", 1)
	_check(r["ok"], "guarda ferramenta nas prateleiras")
	state._last_drop.clear()
	r = state.store_in_build(1, 1, "bambu", 1)
	_check(not r["ok"] and r["reason"] == "nao_aceita", "prateleira não aceita material")
