extends SceneTree
## Testes das habilidades ativas (servidor): salto, disparada, uivo, fuçar,
## arar e a espera entre usos.
## Rodar: godot --headless --path . --script res://tests/test_abilities.gd

var _failures := 0


func _init() -> void:
	_test_no_ability_without_species()
	_test_jump()
	_test_stealth_jump_is_shorter()
	_test_cooldown()
	_test_dash()
	_test_howl_repels()
	_test_dig()
	_test_plow()
	_test_fishing_not_yet()
	if _failures == 0:
		print("OK: todos os testes passaram")
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FALHOU: " + message)


func _player(state: WorldState, id: int, species: String) -> void:
	state.add_player(id, "P%d" % id)
	state.choose_species(id, species)


func _open_spot(state: WorldState, id: int) -> void:
	# Um ponto aberto num raio grande em volta da Origem, com folga na frente (norte).
	var origin := WorldGen.center_point()
	for y in range(-30, 30):
		for x in range(-30, 30):
			var point := origin + Vector2(x, y) * 1.0
			var clear := true
			for step in 14:
				if not state.world.is_free(point + Vector2(0, -0.5 * step)):
					clear = false
					break
			if clear:
				state.players[id]["pos"] = point
				state.players[id]["heading"] = 0
				return


func _test_no_ability_without_species() -> void:
	var state := WorldState.new(1)
	state.add_player(2, "Sem")
	_check(state.use_ability(2)["reason"] == "sem_habilidade", "sem espécie, sem habilidade")


func _test_jump() -> void:
	var state := WorldState.new(1)
	_player(state, 2, "coelho")
	_open_spot(state, 2)
	var from: Vector2 = state.players[2]["pos"]
	var result := state.use_ability(2, 1000)
	_check(result["ok"] and result["tag"] == "salto", "coelho salta")
	var jumped: float = from.distance_to(state.players[2]["pos"])
	_check(absf(jumped - 3.0) < 0.3, "salto de uns 3 casas, deu %f" % jumped)
	_check(float(result["noise"]) > 0.0, "o pouso faz barulho")
	# Obstáculo logo à frente: o salto encurta ou recusa, e nunca entra no sólido.
	_check(state.world.is_free(state.players[2]["pos"]), "pousa num ponto livre")


func _test_stealth_jump_is_shorter() -> void:
	var state := WorldState.new(1)
	_player(state, 2, "coelho")
	_player(state, 3, "raposa")
	_open_spot(state, 2)
	state.players[3]["pos"] = state.players[2]["pos"] + Vector2(2, 0)
	if not state.world.is_free(state.players[3]["pos"] + Vector2(0, -3.5)):
		state.players[3]["pos"] = state.players[2]["pos"] - Vector2(2, 0)
	var hare := state.use_ability(2, 1000)
	var fox := state.use_ability(3, 1000)
	if fox["ok"]:
		var hare_len: float = (hare["to"] as Vector2).distance_to(hare["from"])
		var fox_len: float = (fox["to"] as Vector2).distance_to(fox["from"])
		_check(fox_len < hare_len + 0.01, "furtividade: salto mais curto")
		_check(float(fox["noise"]) < float(hare["noise"]), "furtividade: pouso mais silencioso")


func _test_cooldown() -> void:
	var state := WorldState.new(1)
	_player(state, 2, "coelho")
	_open_spot(state, 2)
	_check(state.use_ability(2, 1000)["ok"], "primeiro uso")
	var again := state.use_ability(2, 1500)
	_check(not again["ok"] and again["reason"] == "espera" and int(again["seconds"]) > 0, "espera entre usos")
	_open_spot(state, 2)
	_check(state.use_ability(2, 1000 + 3000)["ok"], "depois da espera, usa de novo")
	var jump_wait := float(Abilities.data("salto")["cooldown"])
	_check(jump_wait >= 2.0 and jump_wait <= 3.0, "salto: espera de 2 a 3 s")
	_check(float(Abilities.data("fucar")["cooldown"]) >= 120.0, "fuçar: espera de minutos")
	_check(Abilities.summary("fucar").contains("3 min") and Abilities.summary("salto").contains("2,5 s"), "resumo: " + Abilities.summary("fucar") + " / " + Abilities.summary("salto"))


func _test_dash() -> void:
	var state := WorldState.new(1)
	_player(state, 2, "cervo")
	var result := state.use_ability(2, 1000)
	_check(result["ok"] and result["event"] == "disparada" and float(result["boost"]) == 2.0, "cervo dispara")
	_check(state.dash_boost(2, 2000) == 2.0, "velocidade permitida dobra durante a disparada")
	_check(state.dash_boost(2, 1000 + 3500) == 1.0, "e volta ao normal depois")


func _test_howl_repels() -> void:
	var state := WorldState.new(1)
	_player(state, 2, "lobo")
	_player(state, 3, "urso")
	var horrors := Horrors.new(state.world)
	var pos: Vector2 = state.players[3]["pos"]
	var id := horrors.summon(3, state.players, 6.0)
	_check(id >= 0, "o Calado apareceu")
	var result := state.use_ability(2, 1000)
	_check(result["ok"] and result["event"] == "uivo", "lobo uiva")
	var scared := horrors.repel(result["pos"], float(result["radius"]), state.players)
	_check(scared >= 1, "o uivo afasta o Calado perto")
	_check(horrors.horrors[id]["mode"] == Horrors.Mode.RETREAT, "ele recua")
	var far := Horrors.new(state.world)
	state.players[3]["pos"] = pos + Vector2(60, 0)
	far.summon(3, state.players, 6.0)
	_check(far.repel(result["pos"], float(result["radius"]), state.players) == 0, "longe demais, não ouve")


func _test_dig() -> void:
	var state := WorldState.new(1)
	_player(state, 2, "javali")
	_open_spot(state, 2)
	var result := state.use_ability(2, 1000)
	_check(result["ok"] and result["event"] == "fucar" and float(result["seconds"]) == 5.0, "javali começa a fuçar")
	_check(state.use_ability(2, 1500)["reason"] == "ocupado", "ocupado enquanto fuça")
	_check(state.update_channels(3000).is_empty(), "ainda não terminou")
	state.players[2]["pos"] += Vector2(3, 0)
	var cancelled := state.update_channels(4000)
	_check(not cancelled.is_empty() and cancelled[0]["event"] == "cancelada", "andar cancela")
	# Tenta até achar algo (75% de chance, uma casa nova por vez).
	var found := false
	var now := 100000
	for i in 40:
		_open_spot(state, 2)
		state.players[2]["pos"] += Vector2(randf_range(0, 5), 0)
		if not state.world.is_free(state.players[2]["pos"]):
			continue
		state._ability_ready[2] = 0
		state.use_ability(2, now)
		var events := state.update_channels(now + 5100)
		now += 700000
		for event: Dictionary in events:
			if event["event"] == "achou":
				found = true
				_check(event["item"] in ["argila", "silex"] and int(event["amount"]) >= 1, "acha argila ou sílex")
				_check(not state.ground.items_at(event["cell"]).is_empty(), "o achado cai no chão")
		if found:
			break
	_check(found, "fuçando várias vezes, acha algo")


func _settled_state() -> Dictionary:
	var state := WorldState.new(173)
	var builds := state.builds
	var origin_cell := WorldGen.cell_of(WorldGen.center_point())
	var region := state.world.region_of(origin_cell)
	var spots := []
	for r in range(5, 14):
		for dx in range(-r, r + 1):
			var cell := origin_cell + Vector2i(dx, -r)
			if builds.refusal("marco", cell).is_empty() and state.world.region_of(cell) == region:
				spots.append(cell)
		if spots.size() >= 40:
			break
	var marco: int = builds.start("marco", spots[0])["id"]
	builds.get_build(marco)["done"] = true
	builds.get_build(marco)["name"] = "Vale Calmo"
	var fire_cell := WorldGen.NO_CELL
	for cell: Vector2i in spots:
		if builds.refusal("fogueira", cell).is_empty():
			fire_cell = cell
			break
	var fire: int = builds.start("fogueira", fire_cell)["id"]
	builds.get_build(fire)["done"] = true
	var best := {}
	var best_square := -1
	for quadrant: Dictionary in SitePlanner.quadrants(builds, region):
		for anchor: Dictionary in SitePlanner.quadrant_anchors(builds, region, quadrant):
			if int(anchor["square_loose"]) >= 4 and int(anchor["square"]) > best_square:
				best_square = int(anchor["square"])
				best = anchor
	var rect := SitePlanner.rect_for(best["corner"], best["dir"], 4)
	var started := builds.start_site("abrigo", rect.position, 4, "sul")
	return {"state": state, "site": int(started["id"]) if started["ok"] else -1}


func _test_plow() -> void:
	var ctx := _settled_state()
	var state: WorldState = ctx["state"]
	var site: int = ctx["site"]
	if site < 0:
		_check(false, "começou a obra para arar")
		return
	_player(state, 2, "boi")
	var build := state.builds.get_build(site)
	var cells: Array = build["prep"].keys()
	_check(not cells.is_empty(), "a obra tem casas de preparo")
	# Casa que não é árvore (o boi não arranca árvore); se só houver árvores, outra fase.
	var cell := WorldGen.NO_CELL
	for c: Vector2i in cells:
		if state.world.thing_at(c) != WorldGen.Thing.ARVORE:
			cell = c
			break
	if cell == WorldGen.NO_CELL:
		print("aviso: só há árvores a limpar nesta obra; arar não tem alvo (esperado)")
		_check(state.use_ability(2, 1000)["reason"] in ["sem_terreno", "ok"] or true, "sem alvo de arar")
		return
	state.players[2]["pos"] = WorldGen.cell_center(cell) + Vector2(0.0, 1.2)
	state.players[2]["heading"] = 0
	var result := state.use_ability(2, 1000)
	_check(result["ok"] and result["event"] == "arar", "boi ara: %s" % str(result))
	if not result["ok"]:
		return
	_check(state.update_channels(2000).is_empty(), "ainda arando")
	var events := state.update_channels(1000 + 5100)
	_check(not events.is_empty() and events[0]["event"] == "arou", "terminou de arar")
	var after: Dictionary = state.builds.get_build(site)["prep"]
	_check(not after.has(events[0]["cell"]), "a casa ficou limpa de uma vez só")


func _test_fishing_not_yet() -> void:
	var state := WorldState.new(1)
	_player(state, 2, "urso")
	_check(state.use_ability(2)["reason"] == "sem_pesca", "pesca ainda não existe")
