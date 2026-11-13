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
	_test_collect_craft_contribute()
	_test_save_roundtrip()
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


func _find_next_to(state: WorldState, thing: WorldGen.Thing) -> Array:
	# Acha uma casa livre ao lado de "thing"; devolve [livre, coisa].
	for y in range(1, WorldGen.SIZE - 1):
		for x in range(1, WorldGen.SIZE - 1):
			var cell := Vector2i(x, y)
			if state.world.thing_at(cell) != thing:
				continue
			for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
				if state.world.is_passable(cell + d):
					return [cell + d, cell]
	return []


func _test_collect_craft_contribute() -> void:
	var state := WorldState.new(42)
	state.add_player(1, "Lua")
	var spot := _find_next_to(state, WorldGen.Thing.ARVORE)
	_check(not spot.is_empty(), "deveria haver uma árvore acessível")
	state.players[1]["pos"] = spot[0]
	var far: Vector2i = spot[1] + Vector2i(5, 5)
	_check(not state.collect(1, far)["ok"], "não deveria coletar longe")
	_check(state.collect(1, spot[1])["ok"], "deveria coletar madeira ao lado da árvore")
	_check(not state.collect(1, spot[1])["ok"], "deveria haver uma pausa entre coletas")
	state.inventories["Lua"]["madeira"] = 10
	_check(not state.craft(1, "carpintaria", false)["ok"], "minigame perdido não deveria gastar recursos")
	_check(state.inventories["Lua"]["madeira"] == 10, "madeira não deveria ser gasta ao perder")
	for i in 4:
		_check(state.craft(1, "carpintaria", true)["ok"], "carpintaria deveria funcionar")
	_check(state.inventories["Lua"]["tabuas"] == 4 and state.inventories["Lua"]["madeira"] == 2, "4 tábuas, 2 madeiras")
	state.add_player(2, "Tico")
	state.inventories["Lua"]["tabuas"] = 3
	var r := state.contribute(1)
	_check(r["given"].get("tabuas", 0) == 3 and r["completed_stage"] == -1, "entrega parcial")
	state.inventories["Tico"]["tabuas"] = 5
	r = state.contribute(2)
	_check(r["given"].get("tabuas", 0) == 1, "só entrega o que falta")
	_check(r["completed_stage"] == 0 and state.garden["stage"] == 1, "canteiro concluído com a ajuda dos dois")
	_check(state.garden["contributors"] == ["Lua", "Tico"], "créditos para os dois")
	_check(state.inventories["Tico"]["tabuas"] == 4, "Tico fica com o que sobrou")


func _test_save_roundtrip() -> void:
	var state := WorldState.new(99)
	state.add_player(1, "Lua")
	state.inventories["Lua"] = {"madeira": 3}
	state.garden = {"stage": 1, "delivered": {"mudas": 2}, "contributors": ["Lua"]}
	var path := "user://teste_mundo.json"
	_check(WorldSave.save_state(state, path), "deveria salvar")
	var loaded := WorldSave.load_state(path)
	_check(loaded != null and loaded.world.world_seed == 99, "semente salva")
	_check(loaded.inventories["Lua"]["madeira"] == 3, "inventário salvo")
	_check(loaded.garden["stage"] == 1 and loaded.garden["delivered"]["mudas"] == 2, "horta salva")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
