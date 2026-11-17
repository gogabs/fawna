extends Node
## Teste do menu principal: nome obrigatório, páginas de jogo privado.
## Rodar: godot --headless --path . res://tests/test_menu_privado.tscn

var _failures := 0


func _ready() -> void:
	Net.mode = Net.Mode.NONE  # sem tela o Net escolhe servidor; aqui queremos o menu
	Net.player_name = ""
	var menu: Control = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(menu)
	await get_tree().process_frame
	_check(menu.connect_button.text == "Entrar no mundo", "botão sem nome")
	menu.connect_button.pressed.emit()
	_check(menu.notice_label.visible, "aviso de nome")
	_check(Net.mode == Net.Mode.NONE, "sem nome não entra")
	menu.host_button.pressed.emit()
	menu.join_button.pressed.emit()
	_check(Net.mode == Net.Mode.NONE and not menu.join_page.visible, "sem nome não hospeda nem procura")
	Net.player_name = "Ana"
	menu._show_main(false)
	_check(menu.connect_button.text == "Entrar no mundo como Ana", "botão com nome")
	menu.join_button.pressed.emit()
	_check(menu.join_page.visible and not menu.main_page.visible, "página de busca")
	await get_tree().create_timer(5.5).timeout
	_check(menu.join_status.text.begins_with("Nenhum jogo"), "nenhum jogo achado")
	menu._on_game_found("10.0.0.5", 7350, "Bia", "0.1.0")
	_check(menu.found_box.get_child_count() == 1, "jogo listado")
	_check((menu.found_box.get_child(0) as Button).text == "Jogo de Bia, em 10.0.0.5", "texto do jogo")
	menu.ip_field.nav_control().pressed.emit()
	_check(menu.ip_field.is_editing(), "campo de IP")
	print("TESTE OK" if _failures == 0 else "FALHOU: %d" % _failures)
	get_tree().quit(_failures)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		print("FALHA: " + what)
