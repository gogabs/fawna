extends SceneTree
## Testes de acender a tocha sem fogueira (faca ou sílex + pedra, batidas com
## Espaço) e do armazenamento só por dentro.
## Rodar: godot --headless --path . --script res://tests/test_ignicao.gd

var _failures := 0


func _init() -> void:
	_test_methods()
	_test_strikes()
	_test_cancel()
	_test_flint_cost()
	_test_noise()
	_test_inside()
	if _failures == 0:
		print("OK: todos os testes passaram")
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FALHOU: " + message)


func _player(items: Dictionary) -> WorldState:
	var state := WorldState.new(42)
	state.add_player(2, "Lua")
	var inv := state.inventory_of(2)
	inv.clear()
	inv["tocha"] = 1
	for item: String in items:
		inv[item] = items[item]
	state.equip(2, "tocha")
	return state


func _test_methods() -> void:
	var state := _player({})
	_check(state.light_torch(2)["reason"] == "sem_material", "sem nada, falta material")
	state.inventory_of(2)["pedra_pequena"] = 1
	_check(state.light_torch(2)["reason"] == "sem_material", "só a pedra não basta")
	state.inventory_of(2)["silex"] = 1
	_check(state.ignition_method(2) == "silex", "sílex + pedra")
	state.inventory_of(2)["faca"] = 1
	_check(state.ignition_method(2) == "faca", "com faca e sílex, a faca tem prioridade")
	state.inventory_of(2).erase("pedra_pequena")
	_check(state.ignition_method(2) == "", "sem pedra pequena, nada")


func _test_strikes() -> void:
	var state := _player({"pedra_pequena": 1, "faca": 1})
	var start := state.light_torch(2)
	_check(start["ok"] and start.get("started", false) and start["method"] == "faca", "começa a riscar com a faca")
	_check(int(start["needed"]) >= WorldState.STRIKE_MIN and int(start["needed"]) <= WorldState.STRIKE_MAX, "de 5 a 9 batidas")
	var now := Time.get_ticks_msec()
	var sparks := 0
	var result := {}
	for i in 20:
		now += 500
		result = state.strike_spark(2, now)
		if result["event"] == "acendeu":
			break
		_check(result["event"] == "faisca", "batida %d é só uma faísca" % (i + 1))
		sparks += 1
	_check(result["event"] == "acendeu" and sparks == int(start["needed"]) - 1, "acende na última batida (%d faíscas)" % sparks)
	_check(state.torch_left(2) > 800.0, "a tocha ficou acesa")
	_check(int(state.inventory_of(2).get("faca", 0)) == 1 and int(state.inventory_of(2).get("pedra_pequena", 0)) == 1, "faca e pedra não se gastam")
	_check(not state.is_striking(2), "terminou de riscar")


func _test_cancel() -> void:
	var state := _player({"pedra_pequena": 1, "silex": 1})
	state.light_torch(2)
	var now := Time.get_ticks_msec()
	_check(state.strike_spark(2, now + 1000)["event"] == "faisca", "primeira batida dentro da tolerância")
	_check(state.strike_spark(2, now + 1050)["event"] == "nada", "batida colada demais não conta")
	_check(state.strike_spark(2, now + 1950)["event"] == "faisca", "quase um segundo depois ainda vale")
	_check(state.strike_spark(2, now + 3500)["event"] == "cancelada", "mais de um segundo sem riscar cancela")
	_check(not state.is_striking(2) and state.torch_left(2) == 0.0, "cancelado, a tocha segue apagada")
	state.light_torch(2)
	var late := Time.get_ticks_msec() + 5000
	_check(state.expire_strikes(late) == [2], "sem bater nada, o tempo cancela")
	# Perder o material no meio do caminho cancela.
	state.light_torch(2)
	state.inventory_of(2).erase("pedra_pequena")
	_check(state.strike_spark(2, Time.get_ticks_msec() + 500)["why"] == "sem_material", "sem a pedra, cancela por falta de material")


func _test_flint_cost() -> void:
	var state := _player({"pedra_pequena": 1, "silex": 2})
	var needed := int(state.light_torch(2)["needed"])
	var now := Time.get_ticks_msec()
	var result := {}
	for i in needed:
		now += 500
		result = state.strike_spark(2, now)
	_check(result["event"] == "acendeu", "acendeu com sílex")
	_check(int(state.inventory_of(2).get("silex", 0)) == 1, "o sílex gasta um")
	_check(int(state.inventory_of(2).get("pedra_pequena", 0)) == 1, "a pedra fica")


func _test_noise() -> void:
	var world := WorldGen.new(42)
	var horrors := Horrors.new(world)
	var players := {1: {"name": "A", "pos": WorldGen.center_point() + Vector2(60, 60), "heading": 0}}
	horrors.update(0, players, [])
	for i in 40:
		horrors.hear_noise(1, 8.0)
	horrors.update(1000, players, [])
	_check(not horrors.hunting(1).is_empty(), "muito barulho traz o Calado")


func _test_inside() -> void:
	var build := {"cell": Vector2i(10, 10), "size": 4, "kind": "armazem", "entrance": "sul"}
	_check(Builds.inside(build, WorldGen.cell_center(Vector2i(11, 11))), "miolo é dentro")
	_check(Builds.inside(build, WorldGen.cell_center(Vector2i(12, 12))), "o outro miolo também")
	_check(not Builds.inside(build, WorldGen.cell_center(Vector2i(10, 11))), "parede não é dentro")
	_check(not Builds.inside(build, WorldGen.cell_center(Vector2i(12, 13))), "a porta não é dentro")
	_check(not Builds.inside(build, WorldGen.cell_center(Vector2i(8, 8))), "fora não é dentro")
	var state := WorldState.new(173)
	state.add_player(2, "Lua")
	var cell := WorldGen.cell_of(WorldGen.center_point()) + Vector2i(20, 20)
	var made: Dictionary = state.builds._fill(state.builds._new_build(5, "armazem", cell, 4, "sul"), {"size": 4, "entrance": "sul"}, 0.0)
	made["done"] = true
	state.builds._add(made)
	state.inventory_of(2)["bambu"] = 3
	state.players[2]["pos"] = WorldGen.cell_center(cell + Vector2i(2, 4))  # fora, ao lado da porta
	_check(state.store_in_build(2, 5, "bambu", 1)["reason"] == "longe", "por fora não se guarda")
	state.players[2]["pos"] = WorldGen.cell_center(cell + Vector2i(1, 1))
	state._last_drop.clear()
	_check(state.store_in_build(2, 5, "bambu", 1)["ok"], "por dentro se guarda")
