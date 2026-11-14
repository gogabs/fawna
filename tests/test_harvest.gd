extends SceneTree
## Testes dos recursos coletáveis: onde nascem, golpes no bambu, coleta,
## rebrota, rede (info) e salvamento.
## Rodar: godot --headless --path . --script res://tests/test_harvest.gd

const SEARCH := 160  # casas em volta da Origem

var _failures := 0


func _init() -> void:
	_test_placement()
	_test_bamboo_needs_strikes()
	_test_direct_collect_and_regrow()
	_test_strike_memory()
	_test_network_info()
	_test_save()
	_test_world_state()
	_test_narrator()
	if _failures == 0:
		print("OK: todos os testes passaram")
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FALHOU: " + message)


## Conta cada recurso numa área grande e confere onde eles estão.
func _census(world: WorldGen) -> Dictionary:
	var count := {}
	var near_water := 0
	for y in range(-SEARCH, SEARCH):
		for x in range(-SEARCH, SEARCH):
			var cell := Vector2i(x, y)
			var thing := world.thing_at(cell)
			if not Harvest.is_source(thing):
				continue
			count[thing] = int(count.get(thing, 0)) + 1
			if thing == WorldGen.Thing.ARGILA and _water_within(world, cell, 4):
				near_water += 1
	count["argila_perto_da_agua"] = near_water
	return count


func _water_within(world: WorldGen, cell: Vector2i, r: int) -> bool:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var t := world.thing_at(cell + Vector2i(dx, dy))
			if t == WorldGen.Thing.LAGO or t == WorldGen.Thing.RIACHO or t == WorldGen.Thing.PONTE:
				return true
	return false


func _find(world: WorldGen, thing: WorldGen.Thing) -> Array:
	# [casa livre ao lado, casa do recurso]
	for r in range(1, SEARCH):
		for y in range(-r, r + 1):
			for x in [-r, r]:
				for cell in [Vector2i(x, y), Vector2i(y, x)]:
					if world.thing_at(cell) != thing:
						continue
					for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
						if world.is_passable(cell + d) and world.is_free(WorldGen.cell_center(cell + d)):
							return [cell + d, cell]
	return []


func _test_placement() -> void:
	for world_seed in [1, 42]:
		var world := WorldGen.new(world_seed)
		var count := _census(world)
		print("[recursos] semente %d: %s" % [world_seed, count])
		for thing in Harvest.SOURCES:
			_check(int(count.get(thing, 0)) > 0, "deveria haver %s (semente %d)" % [WorldGen.THING_NAMES[thing], world_seed])
		var fruits := int(count.get(WorldGen.Thing.ARBUSTO_FRUTAS, 0))
		_check(fruits < int(count.get(WorldGen.Thing.GRAVETOS, 0)) / 3, "frutas deveriam ser raras")
		var clay := int(count.get(WorldGen.Thing.ARGILA, 0))
		_check(count["argila_perto_da_agua"] == clay, "toda argila deveria estar perto da água (%d de %d)" % [count["argila_perto_da_agua"], clay])
		_check(not world.is_passable(_find(world, WorldGen.Thing.BAMBU)[1]), "bambu deveria bloquear a passagem")
		_check(world.is_passable(_find(world, WorldGen.Thing.GRAVETOS)[1]), "dá para pisar nos gravetos")
	# Mesma semente, mesmos recursos.
	var a := WorldGen.new(7)
	var b := WorldGen.new(7)
	for y in range(-60, 60):
		for x in range(-60, 60):
			_check(a.thing_at(Vector2i(x, y)) == b.thing_at(Vector2i(x, y)), "mesma semente, mesmos recursos")


func _test_bamboo_needs_strikes() -> void:
	var world := WorldGen.new(42)
	var harvest := Harvest.new(world)
	var cell: Vector2i = _find(world, WorldGen.Thing.BAMBU)[1]
	var needed := harvest.hits_needed(cell)
	_check(needed >= 3 and needed <= 5, "bambu pede de 3 a 5 golpes (pediu %d)" % needed)
	var t := 1000.0
	var first := harvest.take(cell, t)
	_check(not first["ok"] and first["reason"] == "golpear" and first["hits_left"] == needed, "bambu de pé não se recolhe")
	for i in needed:
		var hit := harvest.strike(cell, t + i)
		_check(hit["ok"] and hit["hits_left"] == needed - i - 1, "golpe %d conta" % (i + 1))
		_check(hit["felled"] == (i == needed - 1), "só o último golpe derruba")
	_check(harvest.strike(cell, t + 10)["reason"] == "caido", "bambu caído não leva mais golpe")
	var got := harvest.take(cell, t + 11)
	_check(got["ok"] and got["item"] == "bambu" and got["amount"] == 3, "bambu derrubado vai para a bolsa")
	_check(harvest.strike(cell, t + 12)["reason"] == "colhido", "toco não leva golpe")
	_check(harvest.is_available(cell, t + 11 + 900.0), "bambu rebrota")
	_check(harvest.hits_left(cell, t + 11 + 900.0) == needed, "bambu rebrotado pede todos os golpes de novo")
	var gravetos: Vector2i = _find(world, WorldGen.Thing.GRAVETOS)[1]
	_check(harvest.strike(gravetos, t)["reason"] == "nada", "gravetos não se golpeiam")


func _test_direct_collect_and_regrow() -> void:
	var world := WorldGen.new(42)
	var harvest := Harvest.new(world)
	var expected := {WorldGen.Thing.GRAVETOS: "lenha", WorldGen.Thing.ARGILA: "argila", WorldGen.Thing.ARBUSTO_FRUTAS: "frutas"}
	for thing in expected:
		var cell: Vector2i = _find(world, thing)[1]
		var got := harvest.take(cell, 5000.0)
		_check(got["ok"] and got["item"] == expected[thing], "%s se recolhe com a mão" % WorldGen.THING_NAMES[thing])
		var again := harvest.take(cell, 5001.0)
		_check(not again["ok"] and again["reason"] == "colhido", "%s colhido some" % WorldGen.THING_NAMES[thing])
		var regrow: float = Harvest.SOURCES[thing]["regrow"]
		_check(not harvest.is_available(cell, 5000.0 + regrow - 1.0), "ainda não rebrotou")
		_check(harvest.is_available(cell, 5000.0 + regrow), "rebrota depois de %d s" % regrow)
		_check(harvest.prune(5000.0 + regrow).has(cell), "prune devolve o que rebrotou")


func _test_strike_memory() -> void:
	var world := WorldGen.new(42)
	var harvest := Harvest.new(world)
	var cell: Vector2i = _find(world, WorldGen.Thing.BAMBU)[1]
	var needed := harvest.hits_needed(cell)
	harvest.strike(cell, 100.0)
	_check(harvest.hits_left(cell, 101.0) == needed - 1, "golpe guardado")
	_check(harvest.hits_left(cell, 100.0 + Harvest.STRIKE_MEMORY + 1.0) == needed, "golpes velhos se perdem")


func _test_network_info() -> void:
	var world := WorldGen.new(42)
	var server := Harvest.new(world)
	var client := Harvest.new(world)
	var bamboo: Vector2i = _find(world, WorldGen.Thing.BAMBU)[1]
	var clay: Vector2i = _find(world, WorldGen.Thing.ARGILA)[1]
	server.strike(bamboo, 1000.0)
	server.take(clay, 1000.0)
	# O cliente tem o relógio adiantado: o que vale são os tempos relativos.
	client.apply_snapshot(server.snapshot(1010.0), 50000.0)
	_check(client.hits_left(bamboo, 50000.0) == server.hits_left(bamboo, 1010.0), "golpes chegam ao cliente")
	_check(not client.is_available(clay, 50000.0), "argila colhida some no cliente")
	var regrow: float = Harvest.SOURCES[WorldGen.Thing.ARGILA]["regrow"]
	_check(client.is_available(clay, 50000.0 + regrow - 10.0 + 0.5), "e volta no cliente na mesma hora")
	# Info pela rede de uma casa intocada deixa o espelho limpo.
	client.apply_info(bamboo, Harvest.new(world).info(bamboo, 0.0), 50001.0)
	_check(client.hits_left(bamboo, 50001.0) == client.hits_needed(bamboo), "rebrota limpa os golpes")


func _test_save() -> void:
	var state := WorldState.new(42)
	var clay: Vector2i = _find(state.world, WorldGen.Thing.ARGILA)[1]
	var bamboo: Vector2i = _find(state.world, WorldGen.Thing.BAMBU)[1]
	state.harvest.take(clay)
	state.harvest.strike(bamboo)
	var path := "user://teste_recursos.json"
	_check(WorldSave.save_state(state, path), "deveria salvar")
	var loaded := WorldSave.load_state(path)
	_check(not loaded.harvest.is_available(clay), "argila colhida continua colhida depois de carregar")
	_check(loaded.harvest.hits_left(bamboo) == loaded.harvest.hits_needed(bamboo) - 1, "golpes salvos")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_world_state() -> void:
	var state := WorldState.new(42)
	state.add_player(1, "Lua")
	var spot := _find(state.world, WorldGen.Thing.BAMBU)
	state.players[1]["pos"] = WorldGen.cell_center(spot[0])
	var refused := state.collect(1, spot[1])
	_check(refused["reason"] == "golpear", "Espaço no bambu de pé pede o machado")
	var needed := state.harvest.hits_needed(spot[1])
	for i in needed:
		state._last_strike[1] = -100000
		state.strike(1, spot[1])
	_check(state.strike(1, spot[1])["reason"] in ["devagar", "caido"], "bambu já caiu")
	state._last_collect[1] = -100000
	var got := state.collect(1, spot[1])
	_check(got["ok"] and state.inventories["Lua"]["bambu"] == 3, "3 bambus na bolsa (%s)" % got)
	state._last_strike[1] = -100000
	_check(state.strike(1, spot[1] + Vector2i(6, 6))["reason"] == "longe", "golpe tem alcance")


func _test_narrator() -> void:
	var world := WorldGen.new(42)
	var harvest := Harvest.new(world)
	var spot := _find(world, WorldGen.Thing.ARBUSTO_FRUTAS)
	var pos := WorldGen.cell_center(spot[0])
	var before := Narrator.surroundings(world, pos, 0, [], harvest)
	_check(before.contains("arbusto com frutas"), "Tab fala do arbusto com frutas: " + before)
	harvest.take(spot[1])
	var after := Narrator.surroundings(world, pos, 0, [], harvest)
	_check(not after.contains("arbusto com frutas"), "Tab não fala das frutas colhidas: " + after)
