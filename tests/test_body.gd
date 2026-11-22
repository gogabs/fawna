extends SceneTree
## Testes de fome e frio (Body e WorldState.body).
## Rodar: godot --headless --path . --script res://tests/test_body.gd

var _failures := 0


func _init() -> void:
	_test_levels()
	_test_hunger()
	_test_cold()
	_test_warming()
	_test_eat()
	_test_save_round_trip()
	_test_species()
	_test_faint_loss()
	_test_bar()
	_test_spoil()
	_test_raw_and_roast()
	_test_seasonal_food()
	if _failures == 0:
		print("OK: todos os testes passaram")
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FALHOU: " + message)


const DAY := 1800.0


func _ctx(extra := {}) -> Dictionary:
	var ctx := {"season": 0, "night": false, "biome": WorldGen.Biome.BOSQUE, "fire": false,
		"shelter": false, "torch": false, "wet": false, "species": "", "day_seconds": DAY}
	ctx.merge(extra, true)
	return ctx


func _test_levels() -> void:
	_check(Body.level_of(100.0) == 0, "cheio é nível 0")
	_check(Body.level_of(50.0) == 0, "50 ainda é nível 0")
	_check(Body.level_of(49.0) == 1, "abaixo de 50 é nível 1")
	_check(Body.level_of(24.0) == 2, "abaixo de 25 é abatido")
	_check(Body.level_of(0.0) == 3, "zero é nível 3")
	_check(Body.speed_factor({"food": 20.0, "warmth": 100.0}) == Body.WEAK_SPEED, "abatido de fome anda devagar")
	_check(Body.speed_factor({"food": 60.0, "warmth": 60.0}) == 1.0, "bem anda normal")


func _test_hunger() -> void:
	var entry := Body.fresh()
	Body.step(entry, DAY * 0.75, _ctx())
	_check(absf(entry["food"] - 50.0) < 0.5, "na Coroada, meio dia e meio gasta metade em 0,75 dia: %f" % entry["food"])
	var winter := Body.fresh()
	Body.step(winter, DAY * 0.5, _ctx({"season": 2}))
	_check(absf(winter["food"] - 50.0) < 0.5, "na Longa Escuridão, meio dia gasta metade: %f" % winter["food"])


func _test_cold() -> void:
	var summer := Body.fresh()
	Body.step(summer, DAY, _ctx({"night": true}))
	_check(summer["warmth"] == Body.MAX, "a Coroada não esfria, nem de noite")
	var night := Body.fresh()
	Body.step(night, DAY * 0.1, _ctx({"season": 2, "night": true}))
	_check(absf(night["warmth"] - 50.0) < 0.5, "noite do inverno: metade em 0,1 dia (3 min): %f" % night["warmth"])
	var torch := Body.fresh()
	Body.step(torch, DAY * 0.1, _ctx({"season": 2, "night": true, "torch": true}))
	_check(absf(torch["warmth"] - 75.0) < 0.5, "a tocha freia o frio pela metade: %f" % torch["warmth"])
	var wet := Body.fresh()
	Body.step(wet, DAY * 0.05, _ctx({"season": 2, "night": true, "wet": true}))
	_check(absf(wet["warmth"] - 50.0) < 0.5, "molhado esfria em dobro: %f" % wet["warmth"])
	var icy := Body.fresh()
	Body.step(icy, DAY * 0.1, _ctx({"biome": WorldGen.Biome.FLORESTA_GELADA}))
	_check(icy["warmth"] < 60.0, "floresta gelada esfria mesmo na Coroada de dia")
	_check(Body.cold_days(1, false, WorldGen.Biome.BOSQUE) == 0.0, "dia do Declínio não esfria")


func _test_warming() -> void:
	var entry := {"food": 100.0, "warmth": 10.0}
	Body.step(entry, DAY * 0.067, _ctx({"season": 2, "night": true, "fire": true}))
	_check(entry["warmth"] >= 99.0, "a fogueira devolve o calor em uns 2 min: %f" % entry["warmth"])
	var shelter := {"food": 100.0, "warmth": 10.0}
	Body.step(shelter, DAY * 0.05, _ctx({"season": 2, "night": true, "shelter": true}))
	_check(shelter["warmth"] > 10.0 and shelter["warmth"] < 40.0, "o abrigo aquece devagar: %f" % shelter["warmth"])


func _test_eat() -> void:
	var state := WorldState.new(42)
	var id := 7
	state.add_player(id, "Ana")
	var entry := state.body_of(id)
	_check(entry["food"] == Body.START, "quem chega começa cheio")
	_check(state.eat(id, "frutas")["reason"] == "sem_item", "sem fruta não come")
	state.inventory_of(id)["frutas"] = 2
	_check(state.eat(id, "frutas")["reason"] == "cheio", "de barriga cheia não come")
	entry["food"] = 40.0
	_check(state.eat(id, "frutas")["ok"], "come uma fruta")
	_check(entry["food"] == 50.0, "a fruta sacia 10")
	_check(int(state.inventory_of(id)["frutas"]) == 1, "a fruta sai da bolsa")
	_check(state.eat(id, "pedra_grande")["reason"] == "nao_e_comida", "pedra não se come")
	_check(Body.status_text({"food": 40.0, "warmth": 10.0}) == "Você está com um pouco de fome e com frio.", "fala do C: " + Body.status_text({"food": 40.0, "warmth": 10.0}))


func _test_save_round_trip() -> void:
	var state := WorldState.new(42)
	state.add_player(3, "Bia")
	state.body_of(3)["food"] = 33.0
	state.body_of(3)["warmth"] = 12.0
	var loaded := WorldState.from_save(state.to_save())
	_check(loaded.body.has("Bia"), "o corpo sobrevive ao salvar")
	_check(loaded.body["Bia"]["food"] == 33.0 and loaded.body["Bia"]["warmth"] == 12.0, "fome e calor salvos")
	loaded.add_player(4, "Bia")
	_check(loaded.body_of(4)["food"] == 33.0, "quem volta continua com a fome de antes")


func _test_species() -> void:
	var bear := Body.fresh()
	var hare := Body.fresh()
	Body.step(bear, DAY * 0.5, _ctx({"species": "urso"}))
	Body.step(hare, DAY * 0.5, _ctx({"species": "coelho"}))
	_check(bear["food"] < hare["food"], "o Troncudo (pesado) sente fome antes do Lunar (leve)")
	var fox := {"food": 100.0, "warmth": 10.0}
	var wolf := {"food": 100.0, "warmth": 10.0}
	Body.step(fox, DAY * 0.02, _ctx({"fire": true, "species": "raposa"}))
	Body.step(wolf, DAY * 0.02, _ctx({"fire": true, "species": "lobo"}))
	_check(fox["warmth"] > wolf["warmth"], "o mestre do fogo se aquece mais depressa")


func _test_faint_loss() -> void:
	var state := WorldState.new(42)
	state.add_player(5, "Caio")
	var inv := state.inventory_of(5)
	inv["pedra_grande"] = 5
	inv["frutas"] = 1
	var lost := state.strip_half_resources(5)
	_check(int(inv["pedra_grande"]) == 3 and int(lost["pedra_grande"]) == 2, "perde metade das pedras (para baixo)")
	_check(int(inv["frutas"]) == 1 and not lost.has("frutas"), "quem tem 1 fica com ele")
	_check(int(inv.get("machado", 0)) == 1, "o machado fica")
	var wolf_cold := Body.fresh()
	var deer_cold := Body.fresh()
	Body.step(wolf_cold, DAY * 0.1, _ctx({"season": 2, "night": true, "species": "lobo"}))
	Body.step(deer_cold, DAY * 0.1, _ctx({"season": 2, "night": true, "species": "cervo"}))
	_check(wolf_cold["warmth"] > deer_cold["warmth"], "o Geado (pelagem) aguenta mais o frio que o Ramado (leve)")


func _test_bar() -> void:
	_check(Body.bar_step(100.0) == 0 and Body.bar_step(81.0) == 0, "acima de 80, posição 0")
	_check(Body.bar_step(80.0) == 1, "em 80 já é a posição 1")
	_check(Body.bar_step(20.0) == 4 and Body.bar_step(0.0) == 5, "20 é a 4, vazio a 5")
	_check(Body.bar_pan(0) == 1.0 and Body.bar_pan(5) == -1.0, "cheia à direita, vazia à esquerda")
	_check(absf(Body.bar_pan(1) - 0.6) < 0.001, "80 soa perto da direita")


func _test_spoil() -> void:
	var lots := {}
	var inv := {"frutas": 3, "pedra_grande": 1}
	Body.reconcile(lots, inv)
	_check(lots["frutas"] == [[3, 2.0]], "frutas novas ganham um lote fresco: %s" % str(lots))
	_check(not lots.has("pedra_grande"), "pedra não estraga")
	Body.age(lots, inv, 1.0)
	inv["frutas"] = 5
	Body.reconcile(lots, inv)
	_check(lots["frutas"].size() == 2 and lots["frutas"][1] == [2, 2.0], "as que chegam depois são outro lote")
	inv["frutas"] = 4
	Body.reconcile(lots, inv)
	_check(int(lots["frutas"][1][0]) == 1, "jogar fora tira do lote mais novo")
	Body.take_oldest(lots, "frutas")
	_check(int(lots["frutas"][0][0]) == 2, "comer tira do mais velho")
	inv["frutas"] = 3
	var spoiled := Body.age(lots, inv, 1.2)
	_check(int(spoiled.get("frutas", 0)) == 2, "o lote velho estraga: %s" % str(spoiled))
	_check(int(inv["frutas"]) == 1 and int(inv[Body.SPOILED]) == 2, "vira comida estragada na bolsa: %s" % str(inv))
	_check(Body.spoiling_soon(lots).is_empty(), "o que sobrou ainda está fresco")
	Body.age(lots, inv, 0.6)
	_check(int(Body.spoiling_soon(lots).get("frutas", 0)) == 1, "perto do fim, está passando")
	_check(Body.spoil_factor(2, WorldGen.Biome.BOSQUE) == 0.5 and Body.spoil_factor(0, WorldGen.Biome.BOSQUE) == 1.0, "no inverno estraga mais devagar")


func _test_raw_and_roast() -> void:
	var entry := {"food": 50.0, "warmth": 50.0}
	for i in 3:
		_check(Body.eat(entry, "raiz") == "comeu", "raiz crua %d sacia" % (i + 1))
	_check(Body.eat(entry, "raiz") == "enjoou", "a quarta raiz crua seguida enjoa")
	_check(entry["food"] == 55.0, "enjoo tira fome: %f" % entry["food"])
	Body.settle_raw(entry, 1.0)
	_check(not entry.has("raw"), "o enjoo passa com o tempo")
	var state := WorldState.new(42)
	state.add_player(9, "Lia")
	var inv := state.inventory_of(9)
	inv["raiz"] = 3
	_check(state.roast(9, "raiz", 3, [])["reason"] == "sem_fogo", "sem fogueira não assa")
	var near: Vector2 = state.players[9]["pos"] + Vector2(1, 0)
	var result := state.roast(9, "raiz", 2, [near])
	_check(result["ok"] and int(inv["raiz"]) == 1 and int(inv["raiz_assada"]) == 2, "assa 2 raízes: %s" % str(inv))
	_check(state.roast(9, "frutas", 1, [near])["reason"] == "nao_assa", "fruta não se assa")


func _test_seasonal_food() -> void:
	var state := WorldState.new(42)
	state.add_player(2, "Rui")
	state.day_n = int(DayCycle.season_start_day(1))
	_check(state.season() == 1, "dia do Declínio")
	var tree := WorldGen.NO_CELL
	var origin := WorldGen.cell_of(state.players[2]["pos"])
	for r in range(1, 200):
		for dx in range(-r, r + 1):
			for dy in [-r, r]:
				var c := origin + Vector2i(dx, dy)
				if tree == WorldGen.NO_CELL and state.world.thing_at(c) == WorldGen.Thing.ARVORE and Body.nut_tree(c):
					tree = c
		if tree != WorldGen.NO_CELL:
			break
	_check(tree != WorldGen.NO_CELL, "acha uma árvore de castanhas")
	state.teleport(2, WorldGen.cell_center(tree) + Vector2(1.2, 0))
	var nut := state.collect(2, tree)
	_check(nut["ok"] and nut["item"] == "castanha" and int(state.inventory_of(2).get("castanha", 0)) == Body.NUT_AMOUNT, "Espaço na árvore no Declínio dá castanhas: %s" % str(nut))
	state._last_collect.clear()
	_check(state.collect(2, tree).get("item", "") != "castanha", "a mesma árvore só dá castanhas uma vez por ano")
