extends SceneTree
## Testes das espécies (escolha, gravação no servidor, menu).
## Rodar: godot --headless --path . --script res://tests/test_species.gd

var _failures := 0


func _init() -> void:
	_test_data()
	_test_choose_once()
	_test_save_round_trip()
	_test_snapshot_has_species()
	if _failures == 0:
		print("OK: todos os testes passaram")
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FALHOU: " + message)


func _test_data() -> void:
	_check(Species.ORDER.size() == 4, "quatro espécies")
	for id in Species.ORDER:
		_check(Species.DATA.has(id), "dados de " + id)
		_check(not Species.description(id).is_empty() and not Species.trait_text(id).is_empty(), "textos de " + id)
		for value in Species.DATA[id]["traits"].values():
			_check(absf(float(value) - 1.0) <= 0.31, "traço pequeno em " + id)
	_check(Species.trait_value("enraizado", "capacity") > 1.0, "enraizado carrega mais")
	_check(Species.trait_value("ramado", "torch") == 1.0, "traço que não existe vale 1")
	_check(Species.trait_value("", "speed") == 1.0, "sem espécie vale 1")
	_check(Species.with_name("Lia", "ramado") == "Lia, um Ramado", "nome com espécie")
	_check(Species.with_name("Lia", "") == "Lia", "nome sem espécie")


func _test_choose_once() -> void:
	var state := WorldState.new(1)
	state.add_player(2, "Lua")
	_check(state.species_of(2) == "", "começa sem espécie")
	_check(not state.choose_species(2, "xyz"), "espécie inválida recusada")
	_check(state.choose_species(2, "noturno"), "escolhe noturno")
	_check(state.species_of(2) == "noturno", "gravou")
	_check(not state.choose_species(2, "ramado"), "não troca depois de escolher")
	_check(not state.choose_species(99, "ramado"), "jogador desconhecido recusado")
	state.remove_player(2)
	state.add_player(3, "Lua")
	_check(state.species_of(3) == "noturno", "voltando com o mesmo nome, mantém a espécie")


func _test_save_round_trip() -> void:
	var state := WorldState.new(1)
	state.add_player(2, "Lua")
	state.choose_species(2, "brasido")
	var loaded := WorldState.from_save(JSON.parse_string(JSON.stringify(state.to_save())))
	loaded.add_player(5, "Lua")
	_check(loaded.species_of(5) == "brasido", "espécie sobrevive ao save")
	var data := state.to_save()
	data["species"]["Lua"] = "inexistente"
	var bad := WorldState.from_save(data)
	_check(not bad.species.has("Lua"), "espécie desconhecida no save é ignorada")


func _test_snapshot_has_species() -> void:
	var state := WorldState.new(1)
	state.add_player(2, "Lua")
	state.choose_species(2, "ramado")
	_check(state.snapshot()[2]["species"] == "ramado", "snapshot leva a espécie")
