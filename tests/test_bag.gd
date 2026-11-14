extends SceneTree
## Testes da bolsa e do equipamento (servidor) e do menu das setas.
## Rodar: godot --headless --path . --script res://tests/test_bag.gd

var _failures := 0


func _init() -> void:
	_test_starter_axe()
	_test_equip_and_stow()
	_test_equip_refusals()
	_test_save_round_trip()
	_test_grouped_labels()
	_test_menu_info_and_empty()
	if _failures == 0:
		print("OK: todos os testes passaram")
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FALHOU: " + message)


func _test_starter_axe() -> void:
	var state := WorldState.new(1)
	state.add_player(2, "Lua")
	_check(int(state.inventory_of(2).get("machado", 0)) == 1, "toda criatura chega com um machado na bolsa")
	_check(state.wielding(2) == "", "e de mãos livres")
	# Reconectar não dá um segundo machado, nem com ele nas mãos.
	state.equip(2, "machado")
	state.remove_player(2)
	state.add_player(3, "Lua")
	_check(int(state.inventory_of(3).get("machado", 0)) == 0 and state.wielding(3) == "machado", "reconectar mantém o machado nas mãos, sem duplicar")


func _test_equip_and_stow() -> void:
	var state := WorldState.new(1)
	state.add_player(2, "Sol")
	var result := state.equip(2, "machado")
	_check(result["ok"] and state.wielding(2) == "machado", "empunhar põe o machado nas mãos")
	_check(not state.inventory_of(2).has("machado"), "e tira da bolsa")
	result = state.stow(2)
	_check(result["ok"] and result["item"] == "machado" and state.wielding(2) == "", "guardar libera as mãos")
	_check(int(state.inventory_of(2).get("machado", 0)) == 1, "e o machado volta para a bolsa")


func _test_equip_refusals() -> void:
	var state := WorldState.new(1)
	state.add_player(2, "Rio")
	state.inventory_of(2)["argila"] = 2
	_check(state.equip(2, "argila")["reason"] == "nao_empunha", "argila não se empunha")
	_check(state.stow(2)["reason"] == "maos_livres", "guardar de mãos livres é recusado")
	state.equip(2, "machado")
	_check(state.equip(2, "machado")["reason"] == "nao_tem", "não dá para empunhar um machado que já está nas mãos")
	_check(state.equip(99, "machado")["ok"] == false, "jogador desconhecido é recusado")


func _test_save_round_trip() -> void:
	var state := WorldState.new(7)
	state.add_player(2, "Mel")
	state.equip(2, "machado")
	var loaded := WorldState.from_save(JSON.parse_string(JSON.stringify(state.to_save())))
	_check(loaded.equipment.get("Mel", "") == "machado", "o que está nas mãos é salvo com o mundo")
	loaded.add_player(5, "Mel")
	_check(loaded.wielding(5) == "machado" and not loaded.inventory_of(5).has("machado"), "e volta igual ao recarregar")
	# Machado guardado também sobrevive ao save (não é descartado como item velho).
	state.stow(2)
	loaded = WorldState.from_save(JSON.parse_string(JSON.stringify(state.to_save())))
	_check(int(loaded.inventories["Mel"].get("machado", 0)) == 1, "machado na bolsa sobrevive ao save")


func _test_grouped_labels() -> void:
	_check(Bag.entry_label("machado", 1) == "Machado, 1", "rótulo agrupado: Machado, 1")
	var entries := Bag.entries({"machado": 1, "zzz": 0, "abacate": 3})
	_check(entries.size() == 2 and entries[0][0] == "abacate", "itens com zero somem e a ordem é alfabética")


func _test_menu_info_and_empty() -> void:
	var root := func(): return [
		{"label": "Bolsa", "open": func(): return [{"label": "Argila, 2", "info": "Argila, 2"}], "empty": "vazia"},
		{"label": "Equipamento", "open": func(): return [], "empty": "mãos livres"},
	]
	var menu := FloatingMenu.new(root)
	_check(menu.press("cima") == "Bolsa. Argila, 2", "cima entra na bolsa")
	_check(menu.press("cima") == "Argila, 2" and menu.depth() == 2, "item sem ação repete o nome e fica na bolsa")
	menu.press("baixo")
	menu.press("direita")
	_check(menu.press("cima") == "Equipamento: mãos livres.", "equipamento vazio diz mãos livres")
