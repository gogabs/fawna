extends SceneTree
## Testes rápidos da geração do mundo e das frases do narrador.
## Rodar: godot --headless --path . --script res://tests/test_world.gd

var _failures := 0


func _init() -> void:
	_test_same_seed_same_world()
	_test_village_is_free()
	_test_has_both_biomes()
	_test_narrator_direction()
	_test_world_state_moves()
	if _failures == 0:
		print("OK: todos os testes passaram")
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FALHOU: " + message)


func _test_same_seed_same_world() -> void:
	var a := WorldGen.new(42)
	var b := WorldGen.new(42)
	var c := WorldGen.new(43)
	var differs := false
	for y in WorldGen.SIZE:
		for x in WorldGen.SIZE:
			var cell := Vector2i(x, y)
			_check(a.thing_at(cell) == b.thing_at(cell), "mesma semente deveria gerar a mesma coisa em %s" % cell)
			_check(a.biome_at(cell) == b.biome_at(cell), "mesma semente deveria gerar o mesmo bioma em %s" % cell)
			if a.thing_at(cell) != c.thing_at(cell):
				differs = true
	_check(differs, "sementes diferentes deveriam gerar mundos diferentes")


func _test_village_is_free() -> void:
	for world_seed in range(20):
		var world := WorldGen.new(world_seed)
		var center := WorldGen.center()
		_check(world.thing_at(center) == WorldGen.Thing.VILA, "a vila deveria estar no centro")
		for offset in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			_check(world.is_passable(center + offset), "o entorno da vila deveria ser livre (semente %d)" % world_seed)


func _test_has_both_biomes() -> void:
	var seen := {}
	var world := WorldGen.new(7)
	for y in WorldGen.SIZE:
		for x in WorldGen.SIZE:
			seen[world.biome_at(Vector2i(x, y))] = true
	_check(seen.size() == 2, "o mapa deveria ter os dois biomas")


func _test_narrator_direction() -> void:
	_check(Narrator.direction(Vector2i(1, -2)) == "2 ao norte e 1 a leste", "direção norte/leste")
	_check(Narrator.direction(Vector2i(-3, 0)) == "3 a oeste", "direção oeste")
	_check(Narrator.direction(Vector2i.ZERO) == "aqui", "direção zero")


func _test_world_state_moves() -> void:
	var state := WorldState.new(42)
	var pos := state.add_player(10, "Lua")
	_check(state.world.is_passable(pos), "o ponto de entrada deveria ser livre")
	var result := state.try_move(10, Vector2i(5, 5))
	_check(not result["ok"], "movimento que não é de um passo deveria ser recusado")
	result = state.try_move(99, Vector2i.UP)
	_check(not result["ok"], "jogador desconhecido não deveria andar")
	result = state.try_move(10, Vector2i.UP)
	_check(result["ok"], "andar em direção à vila deveria funcionar")
