extends SceneTree
## O foco do menu volta ao pai quando a ação esvazia o nível na hora (quem
## hospeda recebe a resposta do servidor dentro da própria ação).
## Rodar: godot --headless --path . --script res://tests/test_menu_focus.gd

var _failures := 0
var bag := {"amora": 1, "pedra": 2}


func _init() -> void:
	var menu := FloatingMenu.new(_root)
	menu._confirm()  # entra na Bolsa
	menu._confirm()  # entra na amora
	_check(menu.depth() == 3, "abriu as ações da amora")
	menu._confirm()  # Comer: tira a amora na hora
	var said := menu.sync()
	_check(menu.depth() == 2, "o foco voltou à Bolsa (profundidade %d)" % menu.depth())
	_check(not said.is_empty(), "fala a nova posição: " + said)
	if _failures == 0:
		print("OK: todos os testes passaram")
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FALHOU: " + message)


func _root() -> Array:
	return [{"label": "Bolsa", "open": _items}]


func _items() -> Array:
	var out := []
	for item: String in bag:
		out.append({"label": item, "open": _actions.bind(item)})
	return out


func _actions(item: String) -> Array:
	if int(bag.get(item, 0)) <= 0:
		return []
	return [{"label": "Comer", "run": _eat.bind(item)}]


func _eat(item: String) -> String:
	bag[item] = int(bag[item]) - 1
	if bag[item] <= 0:
		bag.erase(item)
	return ""
