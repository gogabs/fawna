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
	# Mapeamento puro: sempre vertical.
	_check(MenuNav.action("cima") == "anterior", "cima anterior")
	_check(MenuNav.action("baixo") == "proximo", "baixo proximo")
	_check(MenuNav.action("direita") == "confirmar", "direita confirma")
	_check(MenuNav.action("esquerda") == "voltar", "esquerda volta")

	# Menu principal: navegação só por setas, sem perder o foco.
	var main: Control = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var vp := get_viewport()
	_check(vp.gui_get_focus_owner() == main.connect_button, "foco inicial no primeiro botão")
	await _key(KEY_UP)
	_check(vp.gui_get_focus_owner() == main.quit_button, "cima na primeira opção vai para a última")
	await _key(KEY_DOWN)
	_check(vp.gui_get_focus_owner() == main.connect_button, "baixo volta à primeira")
	await _key(KEY_TAB)
	_check(vp.gui_get_focus_owner() == main.connect_button, "Tab não move o foco")
	# Entrar, Hospedar, Entrar em jogo privado, Opções, Sair.
	await _key(KEY_DOWN)
	_check(vp.gui_get_focus_owner() == main.host_button, "baixo vai para Hospedar")
	await _key(KEY_DOWN)
	_check(vp.gui_get_focus_owner() == main.join_button, "baixo vai para Entrar em jogo privado")
	await _key(KEY_DOWN)
	_check(vp.gui_get_focus_owner() == main.options_button, "baixo vai para Configurações")
	await _key(KEY_LEFT)  # voltar na página principal: nada acontece
	_check(vp.gui_get_focus_owner() == main.options_button and main.main_page.visible, "esquerda no principal não faz nada")
	await _key(KEY_RIGHT)  # confirmar
	_check(main.options_page.visible, "direita abre as Configurações")
	_check(vp.gui_get_focus_owner() == main.name_field.nav_control(), "foco no campo Nome")
	_check(main.name_field.spoken() == "Nome: " + Net.player_name or Net.player_name.is_empty(), "navegação mostra Nome: valor")
	await _key(KEY_RIGHT)
	_check(main.name_field.is_editing(), "confirmar abre o campo de digitar")
	await _key(KEY_UP)  # no campo, as setas não navegam o menu
	_check(main.name_field.is_editing(), "seta no campo não sai da edição")
	await _key(KEY_ESCAPE)
	_check(not main.name_field.is_editing() and vp.gui_get_focus_owner() == main.name_field.nav_control(), "Esc cancela e devolve o foco")
	await _key(KEY_DOWN)
	_check(vp.gui_get_focus_owner() == main.password_field.nav_control(), "baixo: Senha")
	_check(not main.password_field.spoken().contains(Net.password) or Net.password.is_empty(), "a senha não aparece na fala")
	await _key(KEY_DOWN)
	_check(vp.gui_get_focus_owner() == main.graphics_button, "baixo: categoria Gráficos")
	await _key(KEY_RIGHT)
	_check(main.graphics_page.visible and vp.gui_get_focus_owner() == main.preset_button, "direita abre Gráficos no preset")
	await _key(KEY_RIGHT)
	_check(Net.graphics_preset() == 2 and Net.shadows, "direita muda para Melhores gráficos")
	await _key(KEY_RIGHT)
	_check(Net.graphics_off, "direita de novo: Desativados")
	await _key(KEY_RIGHT)
	_check(Net.graphics_preset() == 1 and not Net.shadows, "e de novo: Mais desempenho")
	await _key(KEY_DOWN)
	_check(vp.gui_get_focus_owner() == main.vsync_check, "baixo: VSync")
	await _key(KEY_DOWN)
	_check(vp.gui_get_focus_owner() == main.shadows_check, "baixo: sombras")
	await _key(KEY_DOWN)
	_check(vp.gui_get_focus_owner() == main.msaa_button, "baixo: antisserrilhamento")
	await _key(KEY_RIGHT)
	_check(Net.msaa == 2 and Net.graphics_preset() == -1, "direita liga o antisserrilhamento e vira Personalizado")
	await _key(KEY_RIGHT)
	await _key(KEY_RIGHT)
	_check(Net.msaa == 0, "2x, 4x e volta a desligado")
	await _key(KEY_DOWN)
	_check(vp.gui_get_focus_owner() == main.glow_check, "baixo: brilho")
	await _key(KEY_DOWN)
	_check(vp.gui_get_focus_owner() == main.graphics_back_button, "baixo: voltar de Gráficos")
	await _key(KEY_RIGHT)
	_check(main.options_page.visible and vp.gui_get_focus_owner() == main.graphics_button, "voltar de Gráficos devolve ao botão Gráficos")
	await _key(KEY_DOWN)
	_check(vp.gui_get_focus_owner() == main.back_button, "baixo: voltar (sem opção de orientação)")
	await _key(KEY_DOWN)
	_check(vp.gui_get_focus_owner() == main.name_field.nav_control(), "baixo no último dá a volta")
	await _key(KEY_UP)
	_check(vp.gui_get_focus_owner() == main.back_button, "cima no primeiro dá a volta")
	await _key(KEY_LEFT)
	_check(main.main_page.visible, "esquerda volta ao principal")
	Net.set_graphics_preset(1)
	Net.save_settings()  # o teste salvou as Opções; desfaz
	if _failures == 0:
		print("OK: todos os testes passaram")
	get_tree().quit(1 if _failures > 0 else 0)
