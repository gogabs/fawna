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
