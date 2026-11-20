extends SceneTree
## Testes de desmontar obras: golpes, devolução de material, estoque, recusas,
## casas limpas que continuam limpas e espelho no cliente.
## Rodar: godot --headless --path . --script res://tests/test_wreck.gd

var _failures := 0


func _init() -> void:
	_test_small()
	_test_large()
	_test_refusals()
	_test_cleared_and_mirror()
	_test_owners()
	if _failures == 0:
		print("OK: todos os testes passaram")
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FALHOU: " + message)


func _origin_cell() -> Vector2i:
	return WorldGen.cell_of(WorldGen.center_point()) + Vector2i(8, 8)


func _large(state: WorldState, kind: String, id: int, done: bool, stage := 0) -> Dictionary:
	var build := state.builds._fill(state.builds._new_build(id, kind, _origin_cell() + Vector2i(id * 12, 0), 4, "sul"), {"size": 4, "entrance": "sul"}, 0.0)
	build["done"] = done
	build["stage"] = Crafting.stage_count(kind) if done else stage
	build["phase"] = "obra"
	state.builds._add(build)
	return build


func _test_small() -> void:
	var state := WorldState.new(173)
	var builds := state.builds
	var made := builds.start("fogueira", _origin_cell())
	_check(made["ok"], "começa a fogueira")
	var id := int(made["id"])
	var build := builds.get_build(id)
	# Fogueira recém-marcada, com 2 pedras médias depositadas e nenhuma batida.
	build["deposited"] = {"pedra_media": 2}
	_check(builds.wreck_hits(id) == Builds.WRECK_MIN_HITS, "obra sem trabalho pede o mínimo de golpes")
	for i in Builds.WRECK_MIN_HITS - 1:
		var hit := builds.strike_wreck(id, 100.0 + i)
		_check(hit["ok"] and hit["event"] == "golpe", "golpe %d ainda não derruba" % i)
		_check(hit["first"] == (i == 0), "só o primeiro golpe é o primeiro")
	_check(builds.strike_wreck(id, 110.0)["event"] == "derrubada", "o último golpe derruba")
	var gone := builds.demolish(id)
	_check(gone["ok"] and gone["back"] == {"pedra_media": 2}, "sem trabalho, o depositado volta inteiro")
	_check(builds.get_build(id).is_empty(), "a obra sumiu")
	_check(gone["piles"].has(_origin_cell()), "o que volta cai na casa da obra")
	# Golpes esfriam: 3 golpes, pausa longa, recomeça.
	var again := int(builds.start("fogueira", _origin_cell())["id"])
	for i in 3:
		builds.strike_wreck(again, 0.0 + i)
	var cold := builds.strike_wreck(again, 100.0)
	_check(cold["event"] == "golpe" and cold["first"], "depois da pausa os golpes recomeçam")
	# Com trabalho feito, só metade volta.
	var worked := builds.get_build(again)
	worked["deposited"] = {"pedra_media": 4, "pedra_pequena": 4}
	worked["work"] = 1
	_check(builds.salvage(worked) == {"pedra_media": 2, "pedra_pequena": 2}, "etapa com trabalho devolve metade do depositado")


func _test_large() -> void:
	var state := WorldState.new(173)
	var builds := state.builds
	var shed := _large(state, "armazem", 1, true)
	_check(builds.wreck_hits(1) == clampi(ceili(42 * 0.6 * (16.0 / 16.0)), 4, 40) or builds.wreck_hits(1) > 4, "armazém pronto pede muitos golpes")
	_check(builds.wreck_cells(shed).size() == 12, "armazém 4x4: 12 casas de borda")
	shed["stock"] = {"bambu": 5, "pedra_grande": 3}
	var gone := builds.demolish(1)
	var back: Dictionary = gone["back"]
	# Armazém 4x4 (referência): estágios: 4 pedra_grande/6 argila; 6 madeira; 14 bambu/6 argila; 10 bambu/4 lenha.
	_check(int(back.get("pedra_grande", 0)) == 2 + 3, "metade das pedras + estoque")
	_check(int(back.get("bambu", 0)) == 7 + 5 + 5, "metade do bambu (7 + 5) + estoque (5)")
	var total := 0
	for cell: Vector2i in gone["piles"]:
		_check(cell.x > shed["cell"].x and cell.x < shed["cell"].x + 3, "cai dentro do terreno")
		for item: String in gone["piles"][cell]:
			total += int(gone["piles"][cell][item])
	var expected := 0
	for item: String in back:
		expected += int(back[item])
	_check(total == expected, "nada se perde ao espalhar (%d de %d)" % [total, expected])
	_check(state.world.built.is_empty(), "as paredes saíram do mundo")
	# Antes das paredes: só os cantos.
	var site := _large(state, "abrigo", 2, false, 0)
	_check(builds.wreck_cells(site).size() == 4, "canteiro sem paredes: 4 cantos")


func _test_refusals() -> void:
	var state := WorldState.new(173)
	var builds := state.builds
	var marco := builds.start("marco", _origin_cell())
	var fire := builds.start("fogueira", _origin_cell() + Vector2i(6, 0))
	var marco_id := int(marco["id"])
	var fire_id := int(fire["id"])
	_check(builds.demolish_refusal(marco_id) == "povoado", "marco com outra obra na região não se desmonta")
	builds.get_build(fire_id)["done"] = true
	builds.get_build(fire_id)["burn_until"] = 1e12
	_check(builds.demolish_refusal(fire_id) == "acesa", "fogueira acesa não se desmonta")
	builds.get_build(fire_id)["burn_until"] = 0.0
	_check(builds.demolish_refusal(fire_id) == "", "fogueira apagada se desmonta")
	builds.demolish(fire_id)
	_check(builds.demolish_refusal(marco_id) == "", "sozinho, o marco se desmonta")


func _test_cleared_and_mirror() -> void:
	var state := WorldState.new(173)
	var builds := state.builds
	var shed := _large(state, "armazem", 1, true)
	var cell := Vector2i(shed["cell"].x + 1, shed["cell"].y + 1)
	shed["removed"] = [cell]
	builds._add(shed)
	_check(state.world.removed.has(cell), "casa limpa pela obra")
	var mirror := WorldState.new(173)
	mirror.builds.apply_snapshot(builds.snapshot())
	builds.demolish(1)
	_check(state.world.removed.has(cell), "a casa limpa continua limpa depois de desmontar")
	var late := WorldState.new(173)
	late.builds.apply_snapshot(builds.snapshot())
	_check(late.world.removed.has(cell) and late.builds.all().is_empty(), "quem entra depois vê a casa limpa e nenhuma obra")
	mirror.builds.remove_build(1)
	_check(mirror.builds.all().is_empty() and mirror.world.removed.has(cell), "o espelho tira a obra e mantém a casa limpa")
	# Salvar e carregar.
	var loaded := WorldState.new(173)
	loaded.builds.load_save(builds.to_save())
	_check(loaded.world.removed.has(cell), "a casa limpa sobrevive ao salvar")
	# Cliente que já tinha a obra e recebe um snapshot novo (reconexão).
	mirror.builds.apply_snapshot([])
	_check(not mirror.world.removed.has(cell), "snapshot vazio zera as casas limpas")


func _test_owners() -> void:
	var state := WorldState.new(173)
	var builds := state.builds
	var home := _large(state, "abrigo", 1, true)
	_check(builds.demolish_refusal(1, -1.0, "Ana") == "", "abrigo sem dono: qualquer um derruba")
	home["owners"] = ["Ana"]
	builds.touch("Ana")
	home["lockers"] = {"Ana": {"bambu": 3}}
	_check(builds.demolish_refusal(1, -1.0, "Bia") == "nao_dono", "abrigo de Ana: Bia não derruba")
	_check(not builds.strike_wreck(1, -1.0, "Bia")["ok"], "golpe de quem não é dono é recusado")
	_check(builds.demolish_refusal(1, -1.0, "Ana") == "", "Ana derruba")
	var gone := builds.demolish(1)
	_check(int(gone["back"].get("bambu", 0)) >= 3, "o armário pessoal cai no chão")
