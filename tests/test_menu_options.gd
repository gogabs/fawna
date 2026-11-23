extends Node
## Testes da navegação dos menus (MenuNav) e das Opções.
## Rodar (precisa de tela; use xvfb-run no Linux, e Net.mode não pode ser
## SERVER, então nada de --headless):
##   godot --path . res://tests/test_menu_options.tscn

var _failures := 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		print("FALHOU: ", what)


func _key(keycode: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = keycode
		e.physical_keycode = keycode
		e.pressed = pressed
		Input.parse_input_event(e)
	await get_tree().process_frame
	await get_tree().process_frame


func _ready() -> void:
	# Mapeamento puro.
	_check(MenuNav.action("esquerda", false) == "anterior", "horizontal: esquerda anterior")
	_check(MenuNav.action("direita", false) == "proximo", "horizontal: direita proximo")
	_check(MenuNav.action("cima", false) == "confirmar", "horizontal: cima confirma")
	_check(MenuNav.action("baixo", false) == "voltar", "horizontal: baixo volta")
	_check(MenuNav.action("cima", true) == "anterior", "vertical: cima anterior")
	_check(MenuNav.action("baixo", true) == "proximo", "vertical: baixo proximo")
	_check(MenuNav.action("direita", true) == "confirmar", "vertical: direita confirma")
	_check(MenuNav.action("esquerda", true) == "voltar", "vertical: esquerda volta")

	# Menu principal: navegação só por setas, sem perder o foco.
	var main: Control = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var vp := get_viewport()
	_check(vp.gui_get_focus_owner() == main.connect_button, "foco inicial no primeiro botão")
	await _key(KEY_LEFT)
	_check(vp.gui_get_focus_owner() == main.quit_button, "esquerda na primeira opção vai para a última")
	await _key(KEY_RIGHT)
	_check(vp.gui_get_focus_owner() == main.connect_button, "direita volta à primeira")
	await _key(KEY_TAB)
	_check(vp.gui_get_focus_owner() == main.connect_button, "Tab não move o foco")
	# Entrar, Hospedar, Entrar em jogo privado, Opções, Sair.
	await _key(KEY_RIGHT)
	_check(vp.gui_get_focus_owner() == main.host_button, "direita vai para Hospedar")
	await _key(KEY_RIGHT)
	_check(vp.gui_get_focus_owner() == main.join_button, "direita vai para Entrar em jogo privado")
	await _key(KEY_RIGHT)
	_check(vp.gui_get_focus_owner() == main.options_button, "direita vai para Configurações")
	await _key(KEY_DOWN)  # voltar na página principal: nada acontece
	_check(vp.gui_get_focus_owner() == main.options_button and main.main_page.visible, "baixo no principal não faz nada")
	await _key(KEY_UP)  # confirmar
	_check(main.options_page.visible, "cima abre as Configurações")
	_check(vp.gui_get_focus_owner() == main.name_field.nav_control(), "foco no campo Nome")
	_check(main.name_field.spoken() == "Nome: " + Net.player_name or Net.player_name.is_empty(), "navegação mostra Nome: valor")
	await _key(KEY_UP)
	_check(main.name_field.is_editing(), "confirmar abre o campo de digitar")
	await _key(KEY_LEFT)  # no campo, as setas não navegam o menu
	_check(main.name_field.is_editing(), "seta no campo não sai da edição")
	await _key(KEY_ESCAPE)
	_check(not main.name_field.is_editing() and vp.gui_get_focus_owner() == main.name_field.nav_control(), "Esc cancela e devolve o foco")
	await _key(KEY_RIGHT)
	_check(vp.gui_get_focus_owner() == main.password_field.nav_control(), "direita: Senha")
	_check(not main.password_field.spoken().contains(Net.password) or Net.password.is_empty(), "a senha não aparece na fala")
	await _key(KEY_RIGHT)
	_check(vp.gui_get_focus_owner() == main.graphics_button, "direita: categoria Gráficos")
	await _key(KEY_UP)
	_check(main.graphics_page.visible and vp.gui_get_focus_owner() == main.preset_button, "cima abre Gráficos no preset")
	await _key(KEY_UP)
	_check(Net.graphics_preset() == 2 and Net.shadows, "cima muda para Melhores gráficos")
	await _key(KEY_UP)
	_check(Net.graphics_off, "cima de novo: Desativados")
	await _key(KEY_UP)
	_check(Net.graphics_preset() == 1 and not Net.shadows, "e de novo: Mais desempenho")
	await _key(KEY_RIGHT)
	_check(vp.gui_get_focus_owner() == main.vsync_check, "direita: VSync")
	await _key(KEY_RIGHT)
	_check(vp.gui_get_focus_owner() == main.shadows_check, "direita: sombras")
	await _key(KEY_RIGHT)
	_check(vp.gui_get_focus_owner() == main.msaa_button, "direita: antisserrilhamento")
	await _key(KEY_UP)
	_check(Net.msaa == 2 and Net.graphics_preset() == -1, "cima liga o antisserrilhamento e vira Personalizado")
	await _key(KEY_UP)
	await _key(KEY_UP)
	_check(Net.msaa == 0, "2x, 4x e volta a desligado")
	await _key(KEY_RIGHT)
	_check(vp.gui_get_focus_owner() == main.glow_check, "direita: brilho")
	await _key(KEY_RIGHT)
	_check(vp.gui_get_focus_owner() == main.minimap_check, "direita: minimapa")
	await _key(KEY_RIGHT)
	_check(vp.gui_get_focus_owner() == main.menu_view_check, "direita: menus na tela")
	await _key(KEY_RIGHT)
	_check(vp.gui_get_focus_owner() == main.graphics_back_button, "direita: voltar de Gráficos")
	await _key(KEY_UP)
	_check(main.options_page.visible and vp.gui_get_focus_owner() == main.graphics_button, "voltar de Gráficos devolve ao botão Gráficos")
	await _key(KEY_RIGHT)
	_check(vp.gui_get_focus_owner() == main.nav_button, "direita: navegação")
	await _key(KEY_UP)
	_check(Net.vertical_nav, "cima alterna para vertical")
	await _key(KEY_DOWN)
	_check(vp.gui_get_focus_owner() == main.back_button, "vertical: baixo é próximo")
	await _key(KEY_DOWN)
	_check(vp.gui_get_focus_owner() == main.name_field.nav_control(), "vertical: baixo no último dá a volta")
	await _key(KEY_UP)  # anterior (vertical)
	_check(vp.gui_get_focus_owner() == main.back_button, "vertical: cima é anterior")
	await _key(KEY_LEFT)
	_check(main.main_page.visible, "vertical: esquerda volta ao principal")
	Net.vertical_nav = false
	Net.set_graphics_preset(1)
	Net.save_settings()  # o teste salvou as Opções; desfaz
	if _failures == 0:
		print("OK: todos os testes passaram")
	get_tree().quit(1 if _failures > 0 else 0)
