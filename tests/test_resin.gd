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
	_test_torch()
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
	_check(resin.status_text(tree, t).begins_with("Árvore de pé, sem cortes"), "sem cortes: " + resin.status_text(tree, t))
	_check(resin.tap(tree, t)["event"] == "corte", "golpe 1 é um corte")
	_check(resin.status_text(tree, t).begins_with("Árvore com 1 corte."), "Espaço conta os cortes: " + resin.status_text(tree, t))
	_check(resin.tap(tree, t + 1)["event"] == "corte", "golpe 2 é um corte")
	_check(resin.tap(tree, t + 2)["event"] == "escorre" and resin.has_resin(tree), "golpe 3 faz a resina escorrer")
	_check("escorre" in resin.status_text(tree, t + 10), "Espaço diz que a resina escorre: " + resin.status_text(tree, t + 10))
	_check(not resin.collect(tree, t + 10)["ok"], "ainda escorrendo, não recolhe")
	var got := resin.collect(tree, t + 2 + Resin.FLOW_TIME + 1)
	_check(got["ok"] and int(got["yield"]["resina"]) == Resin.RESIN_YIELD and not resin.has_resin(tree), "seca, recolhe 2 resinas")
	_check("descansa" in resin.status_text(tree, t + 100), "Espaço diz que a árvore descansa: " + resin.status_text(tree, t + 100))
	# Insistir mata: golpes 4 e 5 rangem, o 6 seca (com resina escorrendo, ela se perde).
	var other := _find(world, WorldGen.Thing.ARVORE, tree + Vector2i(3, 0))
	for i in 3:
		resin.tap(other, t + i)
	_check(resin.has_resin(other), "outra árvore escorrendo")
	_check(resin.tap(other, t + 3)["event"] == "range", "golpe 4 faz o tronco ranger")
	_check(resin.tap(other, t + 4)["event"] == "range", "golpe 5 ainda range")
	_check(resin.tap(other, t + 5)["event"] == "secou" and resin.is_dead(other) and not resin.has_resin(other), "golpe 6 seca a árvore e perde a resina")
	_check(resin.tap(other, t + 6)["event"] == "seca", "árvore seca não dá mais nada")
	_check(resin.status_text(other, t + 7).begins_with("Árvore seca"), "Espaço diz que está seca")
	# Cura dos cortes e descanso depois da resina.
	var third := _find(world, WorldGen.Thing.ARVORE, tree + Vector2i(8, 0))
	resin.tap(third, t)
	resin.tap(third, t + 1)
	_check(resin.cuts(third, t + 1) == 2 and resin.cuts(third, t + 1 + Resin.CUT_MEMORY + 1) == 0, "os cortes se curam com o tempo")
	resin.tap(third, t + 2)
	var collected := t + 2 + Resin.FLOW_TIME + 1
	_check(resin.collect(third, collected)["ok"], "recolhe")
	var later := collected + Resin.CUT_MEMORY + 5
	_check(resin.tap(third, later)["event"] == "descanso" and resin.cuts(third, later) == 0, "primeiro golpe numa árvore que descansa só avisa, sem machucar")
	resin.tap(third, later + 1)
	resin.tap(third, later + 2)
	_check(resin.tap(third, later + 3)["event"] == "descanso", "a árvore ainda descansa: sem resina")
	var rested := collected + Resin.REST_TIME + Resin.CUT_MEMORY + 10
	resin.tap(third, rested)
	resin.tap(third, rested + 1)
	_check(resin.tap(third, rested + 2)["event"] == "escorre", "depois do descanso a resina volta")


func _test_world_state() -> void:
	var state := WorldState.new(42)
	var tree := _find(state.world, WorldGen.Thing.ARVORE)
	state.add_player(2, "Lua")
	state.players[2]["pos"] = WorldGen.cell_center(tree) + Vector2(0, 0.8)
	for i in 3:
		state._last_strike.clear()
		_check(state.tap_tree(2, tree)["ok"], "golpe de faca vale perto da árvore")
	state._last_collect.clear()
	var early := state.collect(2, tree)
	_check(not early["ok"] and early["reason"] == "arvore" and "escorre" in str(early["item"]), "Espaço na resina ainda escorrendo só informa")
	# Passa o tempo de secagem (volta o relógio da resina).
	state.resin._trees[tree]["flow_until"] = Resin.now() - 1.0
	state._last_collect.clear()
	var result := state.collect(2, tree)
	_check(result["ok"] and result["item"] == "resina", "Espaço recolhe a resina seca")
	_check(int(state.inventory_of(2).get("resina", 0)) == Resin.RESIN_YIELD, "a resina vai para a bolsa")
	# Árvore derrubada não dá resina.
	var other := _find(state.world, WorldGen.Thing.ARVORE, tree + Vector2i(4, 0))
	state.players[2]["pos"] = WorldGen.cell_center(other) + Vector2(0, 0.8)
	for i in 12:
		state.harvest.strike(other)
	state._last_strike.clear()
	_check(not state.tap_tree(2, other)["ok"], "árvore caída não dá resina")
	state._last_strike.clear()
	_check(state.tap_tree(2, other + Vector2i(40, 0))["reason"] == "longe", "longe demais")
	state._last_collect.clear()
	var felled := state.collect(2, other)
	_check(felled["ok"] and felled["item"] == "madeira", "árvore caída dá madeira ao Espaço")


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
	# A tocha só se faz na bancada de uma oficina pronta.
	_check(state.craft(2, "tocha")["reason"] == "sem_bancada", "tocha fora da bancada não sai")
	var shop_cell := WorldGen.cell_of(WorldGen.center_point()) + Vector2i(30, 30)
	var shop := state.builds._fill(state.builds._new_build(9, "oficina", shop_cell, 5, "sul"), {"size": 5, "entrance": "sul"}, 0.0)
	shop["done"] = true
	state.builds._add(shop)
	state.players[2]["pos"] = WorldGen.cell_center(Builds.furniture_cells(shop)["bancada"]) + Vector2(0, -1.0)
	_check(state.craft(2, "tocha")["ok"] and int(inv.get("tocha", 0)) == 1 and not inv.has("resina"), "tocha: lenha média, 2 resinas, 2 fibras, 1 cipó")
	_check(Crafting.materials_text({"resina": 2, "cipo": 1}) == "1 cipó e 2 resinas", "materiais falados: " + Crafting.materials_text({"resina": 2, "cipo": 1}))


func _test_save() -> void:
	var state := WorldState.new(42)
	var tree := _find(state.world, WorldGen.Thing.ARVORE)
	for i in 6:
		state.resin.tap(tree)
	var back := WorldState.from_save(state.to_save())
	_check(back.resin.is_dead(tree), "árvore seca sobrevive ao salvamento")


func _test_torch() -> void:
	var state := WorldState.new(42)
	state.add_player(2, "Lua")
	var inv := state.inventory_of(2)
	inv["tocha"] = 2
	_check(Bag.is_offhand("tocha") and Bag.can_wield("tocha"), "tocha é equipamento de mão não dominante")
	_check(state.equip(2, "machado")["ok"] and state.wielding(2) == "machado", "machado na mão principal")
	var result := state.equip(2, "tocha")
	_check(result["ok"] and result["slot"] == "offhand" and state.offhand_of(2) == "tocha" and state.wielding(2) == "machado", "a tocha vai para a outra mão sem tirar o machado")
	_check(int(inv["tocha"]) == 1, "tira uma da bolsa")
	_check(state.light_torch(2)["reason"] == "sem_material", "sem fogueira nem faca/sílex e pedra, não acende")
	var cell := _find(state.world, WorldGen.Thing.NADA, Vector2i(30, 30))
	var fire: int = state.builds.start("fogueira", cell)["id"]
	var build: Dictionary = state.builds.get_build(fire)
	build["done"] = true
	build["burn_until"] = Builds.now() + 1000.0
	state.players[2]["pos"] = WorldGen.cell_center(cell) + Vector2(0, 1.0)
	var lit := state.light_torch(2)
	_check(lit["ok"] and state.torch_left(2) > 800.0, "perto de fogueira acesa, a tocha acende")
	_check(state.light_torch(2)["reason"] == "ja_acesa", "já acesa")
	_check(state.stow_offhand(2)["reason"] == "tocha_acesa" and state.equip(2, "tocha")["reason"] == "tocha_acesa", "tocha acesa não se guarda nem se troca")
	var torches := state.lit_torches()
	var pos: Vector2 = state.players[2]["pos"]
	_check(torches.size() == 1 and Horrors.fire_near(pos + Vector2(Horrors.TORCH_SAFE - 0.5, 0), torches), "a tocha espanta o Calado perto")
	_check(not Horrors.fire_near(pos + Vector2(Horrors.TORCH_SAFE + 1.0, 0), torches), "mas só dentro do alcance dela")
	var back := WorldState.from_save(state.to_save())
	_check(back.offhand.get("Lua", "") == "tocha" and float(back.torch_until.get("Lua", 0.0)) > 0.0, "tocha acesa sobrevive ao salvamento")
	_check(state.expire_torches(Resin.now() + 2000.0) == [2] and state.offhand_of(2) == "" and state.torch_left(2) == 0.0, "a tocha queima até o fim e some")
	_check(Bag.load_of({"machado": 1}, "machado", "tocha") == 3 + 3 + Bag.weight_of("tocha"), "a tocha pesa na carga")


func _unused() -> void:
	pass
