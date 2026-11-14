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
	_test_collision()
	_test_compass()
	_test_regions_and_trails()
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
	for y in range(-40, 40):
		for x in range(-40, 40):
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
	for y in range(-40, 40):
		for x in range(-40, 40):
			seen[world.biome_at(Vector2i(x, y))] = true
	_check(seen.size() >= 2, "o mapa deveria ter mais de um bioma")


func _test_narrator_direction() -> void:
	_check(Narrator.direction(Vector2i(1, -2)) == "2 ao norte e 1 a leste", "direção norte/leste")
	_check(Narrator.direction(Vector2i(-3, 0)) == "3 a oeste", "direção oeste")
	_check(Narrator.direction(Vector2i.ZERO) == "aqui", "direção zero")


func _test_world_state_moves() -> void:
	var state := WorldState.new(42)
	var pos := state.add_player(10, "Lua")
	_check(state.world.is_free(pos), "o ponto de entrada deveria ser livre")
	_check(pos.distance_to(WorldGen.village_point()) < 2.0, "entra perto da vila")
	var t := 100000
	var result := state.move_to(10, pos + Vector2(6, 0), t)
	_check(not result["ok"] and result["pos"] == pos, "teletransporte deveria ser recusado")
	result = state.move_to(99, pos, t)
	_check(not result["ok"], "jogador desconhecido não deveria andar")
	result = state.move_to(10, pos + Vector2(0, -0.15), t + 100)
	_check(result["ok"], "andar um pouquinho em direção à vila deveria funcionar")
	_check(state.near_village(10) == (state.players[10]["pos"].distance_to(WorldGen.village_point()) <= WorldState.VILLAGE_REACH), "perto da vila")
	state.players[10]["pos"] = WorldGen.village_point()
	_check(state.near_village(10), "no centro da vila")


func _test_collision() -> void:
	var world := WorldGen.new(42)
	var tree := WorldGen.NO_CELL
	for y in range(-40, 40):
		for x in range(-40, 40):
			if tree == WorldGen.NO_CELL and world.thing_at(Vector2i(x, y)) == WorldGen.Thing.ARVORE:
				tree = Vector2i(x, y)
	_check(tree != WorldGen.NO_CELL, "deveria haver uma árvore")
	_check(not world.is_free(WorldGen.cell_center(tree)), "não dá para ficar dentro da árvore")
	_check(world.blocker_at(WorldGen.cell_center(tree)) == tree, "o obstáculo é a árvore")
	_check(not world.is_free(Vector2(WorldGen.WORLD_LIMIT + 1.1, 5.5)), "o limite do mundo bloqueia")
	_check(world.is_free(WorldGen.village_point()), "a vila é livre")
	_check(WorldGen.cell_of(Vector2(3.99, 4.0)) == Vector2i(3, 4), "casa de um ponto")


func _test_compass() -> void:
	_check(Compass.forward(0).is_equal_approx(Vector2(0, -1)), "norte é y negativo")
	_check(Compass.forward(2).is_equal_approx(Vector2(1, 0)), "leste é x positivo")
	_check(Compass.right(0).is_equal_approx(Vector2(1, 0)), "olhando para o norte, a direita é leste")
	_check(Compass.name_of(-1) == "noroeste", "girar à esquerda do norte dá noroeste")
	_check(Compass.relative(Vector2(0, -3), 0) == "à frente", "à frente")
	_check(Compass.relative(Vector2(0, -3), 2) == "à esquerda", "olhando para leste, o norte fica à esquerda")
	_check(Compass.relative(Vector2(2, 2), 0) == "atrás e à direita", "sudeste olhando para o norte")
	_check(Compass.relative(Vector2(-1, 0), 4) == "à direita", "olhando para o sul, o oeste fica à direita")
	_check(Compass.describe(Vector2(0, -2), 0) == "à frente, 3 metros", "descreve em metros")
	_check(Sounds.compass_kind(0) == "norte" and Sounds.compass_kind(4) == "sul", "cliques de norte e sul")
	_check(Sounds.compass_kind(2) == Sounds.compass_kind(6), "leste e oeste soam igual")
	_check(Sounds.compass_kind(1) == "colateral" and Sounds.compass_kind(7) == "colateral", "colaterais abafados")


func _test_regions_and_trails() -> void:
	var world := WorldGen.new(42)
	_check(world.region_biome(Vector2i.ZERO) == WorldGen.Biome.PRADARIA, "a vila fica numa pradaria")
	# Regiões são grandes: casas vizinhas quase sempre têm o mesmo bioma.
	var same := 0
	var total := 0
	for y in range(-60, 60, 3):
		for x in range(-60, 60, 3):
			total += 1
			if world.biome_at(Vector2i(x, y)) == world.biome_at(Vector2i(x + 1, y)):
				same += 1
	_check(same > total * 0.9, "biomas deveriam vir em regiões grandes")
	# Longe da vila também existe mundo (sem bordas), e é sempre o mesmo.
	var far := Vector2i(1500, -2200)
	_check(world.thing_at(far) == WorldGen.new(42).thing_at(far), "mundo distante também é fixo pela semente")
	# A vila é ponto de encontro de trilhas: deve haver trilha logo ao lado.
	var near_village := world.nearest_trail(WorldGen.village_point(), 6)
	_check(near_village != WorldGen.NO_CELL, "deveria sair uma trilha da vila")
	# Seguindo a reta até o ponto de encontro vizinho, quase tudo é trilha
	# (ela serpenteia um pouco em volta da reta).
	var a := world.region_landmark(Vector2i.ZERO)
	var b := world.region_landmark(Vector2i.RIGHT)
	var on_trail := 0
	var samples := 40
	for i in samples:
		var p := a.lerp(b, (i + 0.5) / samples)
		if world.nearest_trail(p, 3) != WorldGen.NO_CELL:
			on_trail += 1
	_check(on_trail >= samples * 0.9, "deveria haver trilha ligando a vila à região vizinha (%d/%d)" % [on_trail, samples])
	# Ponte em vez de água no meio da trilha: trilhas nunca bloqueiam.
	for y in range(-80, 80):
		for x in range(-80, 80):
			var cell := Vector2i(x, y)
			if world.thing_at(cell) == WorldGen.Thing.PONTE or world.thing_at(cell) == WorldGen.Thing.TRILHA:
				_check(world.is_passable(cell), "trilha e ponte são passáveis")
				return


func _find_next_to(state: WorldState, thing: WorldGen.Thing) -> Array:
	# Acha uma casa livre ao lado de "thing"; devolve [livre, coisa].
	for y in range(-40, 40):
		for x in range(-40, 40):
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
	state.players[1]["pos"] = WorldGen.cell_center(spot[0])
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
