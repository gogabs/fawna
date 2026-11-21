extends SceneTree
## Testes de onde o jogador nasce (servidor): no último local em que esteve.
## Rodar: godot --headless --path . --script res://tests/test_spawn.gd

var _failures := 0


func _init() -> void:
	_test_returns_to_last_spot()
	_test_save_round_trip()
	_test_new_player_uses_default_spawn()
	if _failures == 0:
		print("OK: todos os testes passaram")
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FALHOU: " + message)


func _free_spot(state: WorldState) -> Vector2:
	return state.world.nearest_free(Vector2(40, 25))


func _test_returns_to_last_spot() -> void:
	var state := WorldState.new(7)
	var far := _free_spot(state)
	state.add_player(2, "Lua")
	state.teleport(2, far)
	state.remove_player(2)
	var back := state.add_player(3, "Lua")
	_check(back.distance_to(far) < 0.01, "quem volta nasce onde saiu")


func _test_save_round_trip() -> void:
	var state := WorldState.new(7)
	var far := _free_spot(state)
	state.add_player(2, "Sol")
	state.teleport(2, far)
	# Salva com o jogador ainda online (queda do servidor): vale a posição de agora.
	var loaded := WorldState.from_save(JSON.parse_string(JSON.stringify(state.to_save())))
	var back := loaded.add_player(5, "Sol")
	_check(back.distance_to(far) < 0.01, "a última posição sobrevive ao save")


func _test_new_player_uses_default_spawn() -> void:
	var state := WorldState.new(7)
	state.add_player(2, "Rio")
	state.teleport(2, _free_spot(state))
	state.remove_player(2)
	var fresh := state.add_player(3, "Mel")
	_check(state.world.is_free(fresh), "quem nunca entrou nasce num ponto livre")
