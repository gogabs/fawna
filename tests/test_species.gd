extends SceneTree
## Testes das espécies (tags, escolha, gravação no servidor).
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
	_check(Species.ORDER.size() == 10, "dez espécies")
	_check(Species.TAGS.size() == 13, "treze tags")
	for id in Species.ORDER:
		_check(Species.DATA.has(id), "dados de " + id)
		_check(not Species.description(id).is_empty(), "descrição de " + id)
		var tags := Species.tags_of(id)
		_check(tags.size() >= 2 and tags.size() <= 3, "2 a 3 tags em " + id)
		for tag: String in tags:
			_check(Species.TAGS.has(tag), "tag %s de %s existe" % [tag, id])
	for tag: String in Species.TAGS:
		var data: Dictionary = Species.TAGS[tag]
		_check(str(data["text"]).contains("mas"),
			"tag %s diz o custo" % tag)
		for key: String in data["effects"]:
			if key != "overload":  # a sobrecarga resistente é pela metade, de propósito
				_check(absf(float(data["effects"][key]) - 1.0) <= 0.31, "efeito pequeno em " + tag)
	_check(is_equal_approx(Species.effect("urso", "capacity"), 1.2 * 0.9), "efeitos se multiplicam")
	_check(Species.effect("urso", "torch") == 1.0, "efeito que ninguém mexe vale 1")
	_check(Species.effect("", "speed") == 1.0, "sem espécie vale 1")
	_check(Species.with_name("Lia", "cabra") == "Lia, uma Cabra-montesa", "nome com espécie e artigo")
	_check(Species.with_name("Lia", "") == "Lia", "nome sem espécie")
	_check(Species.tag_names("lebre") == "Leve, Audição apurada, Salto", "nomes das tags")


func _test_choose_once() -> void:
	var state := WorldState.new(1)
	state.add_player(2, "Lua")
	_check(state.species_of(2) == "", "começa sem espécie")
	_check(not state.choose_species(2, "xyz"), "espécie inválida recusada")
	_check(state.choose_species(2, "lobo"), "escolhe lobo")
	_check(state.species_of(2) == "lobo", "gravou")
	_check(not state.choose_species(2, "urso"), "não troca depois de escolher")
	_check(not state.choose_species(99, "urso"), "jogador desconhecido recusado")
	state.remove_player(2)
	state.add_player(3, "Lua")
	_check(state.species_of(3) == "lobo", "voltando com o mesmo nome, mantém a espécie")


func _test_save_round_trip() -> void:
	var state := WorldState.new(1)
	state.add_player(2, "Lua")
	state.choose_species(2, "raposa")
	var loaded := WorldState.from_save(JSON.parse_string(JSON.stringify(state.to_save())))
	loaded.add_player(5, "Lua")
	_check(loaded.species_of(5) == "raposa", "espécie sobrevive ao save")
	var data := state.to_save()
	data["species"]["Lua"] = "inexistente"
	var bad := WorldState.from_save(data)
	_check(not bad.species.has("Lua"), "espécie desconhecida no save é ignorada")


func _test_snapshot_has_species() -> void:
	var state := WorldState.new(1)
	state.add_player(2, "Lua")
	state.choose_species(2, "onca")
	_check(state.snapshot()[2]["species"] == "onca", "snapshot leva a espécie")
