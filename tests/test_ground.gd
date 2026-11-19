extends SceneTree
## Testes da carga da bolsa e dos itens no chão (servidor).
## Rodar: godot --headless --path . --script res://tests/test_ground.gd

var _failures := 0


func _init() -> void:
	_test_weights()
	_test_split_to_fit()
	_test_drop_and_pick_up()
	_test_collect_overflow()
	_test_full_refuses()
	_test_save_round_trip()
	_test_network_mirror()
	if _failures == 0:
		print("OK: todos os testes passaram")
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FALHOU: " + message)


func _state_with_player() -> WorldState:
	var state := WorldState.new(5)
	state.add_player(2, "Lua")
	return state


func _test_weights() -> void:
	_check(Bag.load_of({"pedra_grande": 2, "frutas": 3}) == 15, "carga soma pesos (2 pedras grandes + 3 frutas = 15)")
	_check(Bag.load_of({"frutas": 1}, "machado") == 4, "o que está nas mãos conta na carga")
	_check(Bag.free_space({"pedra_grande": 5}) == Bag.CAPACITY - 30 or Bag.free_space({"pedra_grande": 5}) == 0, "espaço nunca é negativo")
	_check(Bag.free_space({"pedra_grande": 99}) == 0, "acima do limite não sobra espaço")
	_check(Bag.room_for({}, "", "pedra_grande") == Bag.CAPACITY / Bag.weight_of("pedra_grande"), "quantas pedras grandes cabem numa bolsa vazia")
	var marco := Crafting.total_materials("marco")
	_check(Bag.weight_of_items(marco) > Bag.CAPACITY, "um marco inteiro não cabe numa viagem só")
	_check(Bag.weight_of_items(Crafting.total_materials("fogueira")) <= Bag.CAPACITY, "mas uma fogueira cabe na bolsa")
	_check(Bag.load_label({"frutas": 2}) == "Carga, 2 de %d" % Bag.CAPACITY, "rótulo da carga")


func _test_split_to_fit() -> void:
	var split := Bag.split_to_fit({}, "", {"pedra_grande": 10})
	var fit: int = int(split[0].get("pedra_grande", 0))
	_check(fit == Bag.CAPACITY / Bag.weight_of("pedra_grande") and int(split[1]["pedra_grande"]) == 10 - fit, "split separa o que cabe do que sobra")
	split = Bag.split_to_fit({"pedra_grande": 2}, "", {"pedra_grande": 1, "frutas": 4})
	_check(split[0].get("pedra_grande", 0) == 1 and split[0].get("frutas", 0) == 4 and split[1].is_empty(), "cabe tudo quando há espaço")
	split = Bag.split_to_fit({"pedra_grande": 3}, "", {"pedra_grande": 5, "frutas": 6})
	_check(int(split[0].get("pedra_grande", 0)) == 1 and Bag.load_of(split[0]) + 18 <= Bag.CAPACITY, "põe primeiro o mais pesado e nunca passa do limite")


func _test_drop_and_pick_up() -> void:
	var state := _state_with_player()
	var inv := state.inventory_of(2)
	inv["pedra_grande"] = 3
	inv["frutas"] = 2
	var cell: Vector2i = WorldGen.cell_of(state.players[2]["pos"])
	var result := state.drop(2, "pedra_grande", 2)
	_check(result["ok"] and result["cell"] == cell and int(inv["pedra_grande"]) == 1, "jogar tira da bolsa")
	_check(int(state.ground.items_at(cell).get("pedra_grande", 0)) == 2, "e põe no chão, na casa da criatura")
	_check(not state.drop(2, "argila", 1)["ok"], "não dá para jogar o que não se tem")
	_check(state.drop(2, "frutas", 1)["reason"] == "devagar", "jogar em sequência rápida demais espera")
	await_cooldown(state, 2)
	result = state.drop(2, "pedra_grande", 99)
	_check(result["ok"] and result["amount"] == 1 and not inv.has("pedra_grande"), "jogar mais do que tem joga só o que tem")
	await_cooldown(state, 2)
	result = state.pick_up(2, cell)
	_check(result["ok"] and int(inv.get("pedra_grande", 0)) == 3 and not state.ground.has_pile(cell), "pegar do chão devolve tudo se couber")
	# Outra criatura longe não alcança.
	state.add_player(3, "Sol")
	state.players[3]["pos"] = WorldGen.cell_center(cell + Vector2i(10, 0))
	state.ground.add(cell, "frutas", 1)
	_check(state.pick_up(3, cell)["reason"] == "longe", "pegar de longe é recusado")
	await_cooldown(state, 2)
	_check(state.pick_up(2, cell)["ok"], "quem está perto pega")
	await_cooldown(state, 2)
	_check(state.pick_up(2, cell)["reason"] == "nada", "monte vazio não tem o que pegar")


func await_cooldown(state: WorldState, id: int) -> void:
	state._last_drop[id] = -WorldState.DROP_COOLDOWN_MS * 2
	state._last_collect[id] = -WorldState.COLLECT_COOLDOWN_MS * 2


func _first_cell_of(state: WorldState, thing: int) -> Vector2i:
	for r in range(1, 60):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var cell := WorldGen.cell_of(WorldGen.center_point()) + Vector2i(dx, dy)
				if state.world.thing_at(cell) == thing:
					return cell
	return WorldGen.NO_CELL


func _test_collect_overflow() -> void:
	var state := _state_with_player()
	var cell := _first_cell_of(state, WorldGen.Thing.PEDRAS)
	_check(cell != WorldGen.NO_CELL, "o teste acha pedras perto do centro")
	var inv := state.inventory_of(2)
	inv["pedra_grande"] = 2  # peso 12 de 24, com o machado (3) = 15
	state.players[2]["pos"] = WorldGen.cell_center(cell) + Vector2(0.0, 1.0)
	state.harvest.rng.seed = 11
	var before := Bag.load_of(inv, state.wielding(2))
	var result := state.collect(2, cell)
	_check(result["ok"], "coleta aceita com espaço")
	var after := Bag.load_of(inv, state.wielding(2))
	_check(after <= Bag.CAPACITY, "a carga nunca passa do limite (%d)" % after)
	var kept_weight := Bag.weight_of_items(result["kept"])
	var over_weight := Bag.weight_of_items(result["left_over"])
	_check(after - before == kept_weight, "só o que coube entra na bolsa")
	_check(over_weight == Bag.weight_of_items(state.ground.items_at(WorldGen.cell_of(state.players[2]["pos"]))), "o que não coube fica no chão onde a criatura está")


func _test_full_refuses() -> void:
	var state := _state_with_player()
	var cell := _first_cell_of(state, WorldGen.Thing.PEDRAS)
	var inv := state.inventory_of(2)
	inv["pedra_grande"] = 4  # 24: lotado, e ainda o machado
	state.players[2]["pos"] = WorldGen.cell_center(cell) + Vector2(0.0, 1.0)
	var result := state.collect(2, cell)
	_check(not result["ok"] and result["reason"] == "cheio", "lotado, coletar é recusado")
	_check(state.harvest.is_available(cell), "e o recurso não é gasto")
	_check(not state.pick_up(2, WorldGen.cell_of(state.players[2]["pos"]))["ok"], "pegar do chão sem espaço é recusado")


func _test_save_round_trip() -> void:
	var state := _state_with_player()
	state.ground.add(Vector2i(3, 4), "pedra_media", 2)
	state.ground.add(Vector2i(3, 4), "bambu", 1)
	state.ground.add(Vector2i(-5, 9), "frutas", 4)
	var loaded := WorldState.from_save(JSON.parse_string(JSON.stringify(state.to_save())))
	_check(loaded.ground.items_at(Vector2i(3, 4)) == {"pedra_media": 2, "bambu": 1}, "o chão é salvo com o mundo")
	_check(int(loaded.ground.items_at(Vector2i(-5, 9)).get("frutas", 0)) == 4, "inclusive em coordenadas negativas")
	# Mundo salvo antes dos itens no chão carrega sem erro.
	var old := state.to_save()
	old.erase("ground")
	_check(WorldState.from_save(JSON.parse_string(JSON.stringify(old))).ground.cells().is_empty(), "save antigo, sem chão, carrega vazio")


func _test_network_mirror() -> void:
	var state := _state_with_player()
	state.ground.add(Vector2i(1, 1), "argila", 2)
	var mirror := Ground.new()
	mirror.apply_snapshot(state.ground.snapshot())
	_check(mirror.items_at(Vector2i(1, 1)) == {"argila": 2}, "o espelho do cliente recebe o retrato")
	mirror.apply_pile(Vector2i(1, 1), {})
	_check(not mirror.has_pile(Vector2i(1, 1)), "monte vazio some do espelho")
	state.ground.add(Vector2i(8, 8), "bambu", 1)
	_check(state.ground.nearest(WorldGen.cell_center(Vector2i(7, 8)), 3.0) == Vector2i(8, 8), "o monte mais próximo é achado")
	_check(Ground.pile_text({"pedra_grande": 2, "bambu": 1}) != "nada", "texto do monte")
