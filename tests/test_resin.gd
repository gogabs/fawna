extends SceneTree
## Testes da faca de sílex, da resina e dos recursos novos (cipó, fibra, sílex).
## Rodar: godot --headless --path . --script res://tests/test_resin.gd

var _failures := 0


func _init() -> void:
	_test_placement()
	_test_resin_cycle()
	_test_world_state()
	_test_recipes()
	_test_save()
	if _failures == 0:
		print("OK: todos os testes passaram")
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FALHOU: " + message)


func _find(world: WorldGen, thing: int, start := Vector2i.ZERO) -> Vector2i:
	for r in range(0, 400, 1):
		for dx in range(-r, r + 1):
			for dy in [-r, r]:
				for c: Vector2i in [start + Vector2i(dx, dy), start + Vector2i(dy, dx)]:
					if world.thing_at(c) == thing:
						return c
	return WorldGen.NO_CELL


func _test_placement() -> void:
	var world := WorldGen.new(42)
	var vines := 0
	var fibers := 0
	var flints := 0
	var outside := 0
	for y in range(-240, 240):
		for x in range(-240, 240):
			var cell := Vector2i(x, y)
			var thing := world.thing_at(cell)
			if thing == WorldGen.Thing.CIPO or thing == WorldGen.Thing.FIBRA:
				if thing == WorldGen.Thing.CIPO:
					vines += 1
				else:
					fibers += 1
				if world.cover_at(cell) != WorldGen.Cover.FECHADA:
					outside += 1
			elif thing == WorldGen.Thing.SILEX:
				flints += 1
	_check(vines > 0 and fibers > 0, "há cipó e fibra nas matas (cipó %d, fibra %d)" % [vines, fibers])
	_check(outside == 0, "cipó e fibra só nascem em mata fechada")
	_check(flints > 0, "há sílex no mundo (%d)" % flints)
	for thing: int in [WorldGen.Thing.CIPO, WorldGen.Thing.FIBRA, WorldGen.Thing.SILEX]:
		_check(Harvest.is_source(thing) and not Harvest.needs_tool(thing), "recurso novo se colhe com a mão")
		_check(Economy.is_item(Harvest.item_of(thing)), "item novo tem nome falado")


func _test_resin_cycle() -> void:
	var world := WorldGen.new(42)
	var tree := _find(world, WorldGen.Thing.ARVORE)
	_check(tree != WorldGen.NO_CELL, "acha uma árvore")
	var resin := Resin.new(world)
	var t := 1000.0
	_check(resin.tap(tree, t)["event"] == "corte", "golpe 1 é um corte")
	_check(resin.tap(tree, t + 1)["event"] == "corte", "golpe 2 é um corte")
	var third := resin.tap(tree, t + 2)
	_check(third["event"] == "resina" and int(third["yield"]["resina"]) == Resin.RESIN_YIELD, "golpe 3 solta a resina")
	_check(resin.tap(tree, t + 3)["event"] == "range", "golpe 4 faz o tronco ranger")
	_check(resin.tap(tree, t + 4)["event"] == "range", "golpe 5 ainda range")
	_check(resin.tap(tree, t + 5)["event"] == "secou", "golpe 6 seca a árvore")
	_check(resin.is_dead(tree), "árvore seca")
	_check(resin.tap(tree, t + 6)["event"] == "seca", "árvore seca não dá mais nada")
	# Outra árvore: cura depois de um tempo parado, e descansa depois da resina.
	var other := _find(world, WorldGen.Thing.ARVORE, tree + Vector2i(3, 0))
	_check(resin.tap(other, t)["event"] == "corte" and resin.tap(other, t + 1)["event"] == "corte", "dois cortes")
	_check(resin.cuts(other, t + 1) == 2 and resin.cuts(other, t + 1 + Resin.CUT_MEMORY + 1) == 0, "os cortes se curam com o tempo")
	_check(resin.tap(other, t + 2)["event"] == "resina", "resina na outra árvore")
	var later := t + 2 + Resin.CUT_MEMORY + 5
	_check(resin.tap(other, later)["event"] == "descanso" and resin.cuts(other, later) == 0, "primeiro golpe numa árvore que descansa só avisa, sem machucar")
	resin.tap(other, later + 1)
	resin.tap(other, later + 2)
	_check(resin.tap(other, later + 3)["event"] == "descanso", "a árvore ainda descansa: sem resina")
	var rested := t + 2 + Resin.REST_TIME + Resin.CUT_MEMORY + 10
	resin.tap(other, rested)
	resin.tap(other, rested + 1)
	_check(resin.tap(other, rested + 2)["event"] == "resina", "depois do descanso a resina volta")
	_check(resin.tap(Vector2i(1, 1), t)["event"] == "nada" or world.thing_at(Vector2i(1, 1)) == WorldGen.Thing.ARVORE, "só árvore dá resina")


func _test_world_state() -> void:
	var state := WorldState.new(42)
	var tree := _find(state.world, WorldGen.Thing.ARVORE)
	state.add_player(2, "Lua")
	state.players[2]["pos"] = WorldGen.cell_center(tree) + Vector2(0, 0.8)
	var got := 0
	for i in 3:
		state._last_strike.clear()
		var result := state.tap_tree(2, tree)
		_check(result["ok"], "golpe de faca vale perto da árvore")
		got += int(result["yield"].get("resina", 0))
	_check(got == Resin.RESIN_YIELD and int(state.inventory_of(2).get("resina", 0)) == Resin.RESIN_YIELD, "a resina vai para a bolsa")
	# Árvore derrubada não dá resina.
	var other := _find(state.world, WorldGen.Thing.ARVORE, tree + Vector2i(4, 0))
	state.players[2]["pos"] = WorldGen.cell_center(other) + Vector2(0, 0.8)
	for i in 12:
		state.harvest.strike(other)
	state._last_strike.clear()
	_check(not state.tap_tree(2, other)["ok"], "árvore caída não dá resina")
	state._last_strike.clear()
	_check(state.tap_tree(2, other + Vector2i(40, 0))["reason"] == "longe", "longe demais")


func _test_recipes() -> void:
	var state := WorldState.new(42)
	state.add_player(2, "Lua")
	var inv := state.inventory_of(2)
	_check(state.craft(2, "faca")["reason"] == "faltam", "faca sem material não sai")
	inv["silex"] = 2
	inv["lenha_pequena"] = 1
	_check(state.craft(2, "faca")["ok"] and int(inv.get("faca", 0)) == 1 and not inv.has("silex"), "faca bruta: 2 sílex e 1 lenha pequena")
	_check(Bag.can_wield("faca") and Bag.with_article("faca") == "a faca bruta de sílex", "faca se empunha e se fala")
	_check(Crafting.TOOL_ORDER.has("faca"), "faca está em Ferramentas")
	inv["lenha_media"] = 1
	inv["resina"] = 2
	inv["fibra"] = 2
	inv["cipo"] = 1
	_check(state.craft(2, "tocha")["ok"] and int(inv.get("tocha", 0)) == 1 and not inv.has("resina"), "tocha: lenha média, 2 resinas, 2 fibras, 1 cipó")
	_check(Crafting.materials_text({"resina": 2, "cipo": 1}) == "1 cipó e 2 resinas", "materiais falados: " + Crafting.materials_text({"resina": 2, "cipo": 1}))


func _test_save() -> void:
	var state := WorldState.new(42)
	var tree := _find(state.world, WorldGen.Thing.ARVORE)
	for i in 6:
		state.resin.tap(tree)
	var back := WorldState.from_save(state.to_save())
	_check(back.resin.is_dead(tree), "árvore seca sobrevive ao salvamento")


func _unused() -> void:
	pass
