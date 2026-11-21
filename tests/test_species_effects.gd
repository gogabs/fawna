extends SceneTree
## Testes dos efeitos passivos das espécies: carga, sobrecarga, velocidade,
## tocha, acender sem faca, machado e vau.
## Rodar: godot --headless --path . --script res://tests/test_species_effects.gd

var _failures := 0


func _init() -> void:
	_test_capacity()
	_test_overload_speed()
	_test_server_pickup_limits()
	_test_torch_seconds()
	_test_fire_master_ignition()
	_test_axe_power()
	_test_speed_allowance()
	_test_ford()
	if _failures == 0:
		print("OK: todos os testes passaram")
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FALHOU: " + message)


func _test_capacity() -> void:
	_check(Bag.capacity_for("") == Bag.CAPACITY and Bag.max_load_for("") == Bag.MAX_LOAD, "sem espécie, carga padrão")
	_check(Bag.capacity_for("boi") > Bag.capacity_for("coelho"), "boi (pesado) carrega mais que coelho (leve)")
	_check(Bag.capacity_for("boi") == roundi(24 * 1.2), "pesado: +20%")
	_check(Bag.capacity_for("coelho") == roundi(24 * 0.85), "leve: -15%")
	_check(Bag.capacity_for("urso") == roundi(24 * 1.2 * 0.9), "pesado e guerreiro se multiplicam")
	_check(Bag.free_space({"pedra_grande": 5}, "", "", "boi") > Bag.free_space({"pedra_grande": 5}, "", "", "coelho"), "mais espaço para o boi")


func _test_overload_speed() -> void:
	var load_bag := {"pedra_grande": 6}  # 36
	_check(Bag.speed_factor({}, "", "", "") == 1.0, "vazio anda a toda")
	_check(is_equal_approx(Bag.speed_factor(load_bag, "", "", ""), Bag.MIN_SPEED_FACTOR), "no limite, metade da velocidade")
	var resistant := Bag.speed_factor({"pedra_grande": 7}, "", "", "boi")  # 42 de 43
	var normal := Bag.speed_factor({"pedra_grande": 7}, "", "", "cervo")
	_check(resistant > normal, "resistente perde menos velocidade na sobrecarga")
	var at_limit := Bag.speed_factor({"pedra_grande": 7, "pedra_pequena": 1}, "", "", "boi")
	_check(is_equal_approx(at_limit, 0.75), "resistente: no limite anda a 75%%, deu %f" % at_limit)
	_check(Bag.load_label({"pedra_grande": 5}, "", "", "coelho").contains("de 20"), "rótulo usa a carga da espécie")


func _test_server_pickup_limits() -> void:
	var state := WorldState.new(1)
	state.add_player(2, "Boi")
	state.add_player(3, "Coelho")
	state.choose_species(2, "boi")
	state.choose_species(3, "coelho")
	var pile := {"pedra_grande": 10}
	var for_ox := Bag.split_to_fit(state.inventory_of(2), "", pile, "", "boi")
	var for_hare := Bag.split_to_fit(state.inventory_of(3), "", pile, "", "coelho")
	_check(int(for_ox[0].get("pedra_grande", 0)) > int(for_hare[0].get("pedra_grande", 0)), "boi pega mais pedras que coelho")
	_check(state.species_of(2) == "boi", "espécie do servidor")


func _test_torch_seconds() -> void:
	var state := WorldState.new(1)
	state.add_player(2, "A")
	state.add_player(3, "B")
	state.choose_species(2, "raposa")  # mestre do fogo
	state.choose_species(3, "urso")
	_check(state.torch_seconds(2) > state.torch_seconds(3), "mestre do fogo: tocha dura mais")
	_check(state.torch_seconds(3) == WorldState.TORCH_SECONDS, "sem a tag, duração padrão")


func _test_fire_master_ignition() -> void:
	var state := WorldState.new(1)
	state.add_player(2, "Fogo")
	state.add_player(3, "Urso")
	state.choose_species(2, "raposa")
	state.choose_species(3, "urso")
	for id in [2, 3]:
		var bag := state.inventory_of(id)
		bag["pedra_pequena"] = 1
	_check(state.ignition_method(2) == "pedra", "mestre do fogo acende só com a pedra")
	_check(state.ignition_method(3) == "", "outros precisam de faca ou sílex")
	state.inventory_of(3)["faca"] = 1
	_check(state.ignition_method(3) == "faca", "faca continua valendo")
	# Batidas só com a pedra: o material não falta.
	state.offhand[state.players[2]["name"]] = "tocha"
	var started := state.light_torch(2)
	_check(started.get("started", false) and started["method"] == "pedra", "começa a riscar com pedra")
	var lit := false
	var base := Time.get_ticks_msec()
	for i in 12:
		var spark := state.strike_spark(2, base + 500 * (i + 1))
		if spark["event"] == "acendeu":
			lit = true
			break
	_check(lit, "a tocha acende sem faca nem sílex")


func _test_axe_power() -> void:
	var world := WorldGen.new(1)
	var weak := Harvest.new(world)
	var strong := Harvest.new(world)
	weak.rng.seed = 5
	strong.rng.seed = 5
	var cell := _find_needs_tool_cell(world)
	if cell == WorldGen.NO_CELL:
		_check(false, "achou algo para cortar")
		return
	var weak_blows := 0
	while weak.hits_left(cell) > 0 and weak_blows < 20:
		weak.strike(cell)
		weak_blows += 1
	var strong_blows := 0
	while strong.hits_left(cell) > 0 and strong_blows < 20:
		strong.strike(cell, -1.0, 2.0)  # sempre vale por dois quando sobra
		strong_blows += 1
	_check(strong_blows < weak_blows, "golpe mais forte derruba com menos golpes (%d contra %d)" % [strong_blows, weak_blows])


func _find_needs_tool_cell(world: WorldGen) -> Vector2i:
	for y in range(-40, 40):
		for x in range(-40, 40):
			var cell := Vector2i(x, y)
			if Harvest.needs_tool(world.thing_at(cell)):
				return cell
	return WorldGen.NO_CELL


func _test_speed_allowance() -> void:
	var state := WorldState.new(1)
	state.add_player(2, "Cervo")
	state.add_player(3, "Urso")
	state.choose_species(2, "cervo")
	state.choose_species(3, "urso")
	var from: Vector2 = state.players[2]["pos"]
	# Um segundo andando além do máximo padrão: o cervo (1,21 x) é aceito, o urso não.
	var distance := WorldState.MAX_SPEED + WorldState.MOVE_SLACK + 0.2  # acima do padrão, abaixo do cervo
	var target := from + Vector2(0, -distance)
	if not state.world.is_free(target):
		target = from + Vector2(distance, 0)
	var now := Time.get_ticks_msec()
	state._last_move[2] = now - 1000
	var deer := state.move_to(2, target, now)
	state.players[3]["pos"] = from
	state._last_move[3] = now - 1000
	var bear := state.move_to(3, target, now)
	if state.world.is_free(target):
		_check(deer["ok"], "cervo aceito a mais que o máximo padrão")
		_check(not bear["ok"], "urso recusado acima do máximo padrão")


func _test_ford() -> void:
	var world := WorldGen.new(1)
	var ford := WorldGen.NO_CELL
	for y in range(-120, 120):
		for x in range(-120, 120):
			if world.thing_at(Vector2i(x, y)) == WorldGen.Thing.VAU:
				ford = Vector2i(x, y)
				break
		if ford != WorldGen.NO_CELL:
			break
	if ford == WorldGen.NO_CELL:
		print("aviso: nenhum vau achado nesta semente, teste do vau pulado")
		return
	var pos := WorldGen.cell_center(ford)
	_check(Species.may_step("urso", world, pos), "urso atravessa o vau")
	_check(not Species.may_step("raposa", world, pos), "mestre do fogo não pisa no vau")
