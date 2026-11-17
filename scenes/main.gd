extends Control
## Menu principal e Opções.
##
## Usa nós nativos do Godot, que o leitor de tela lê sozinho (Godot 4.5+).
## Sem leitor de tela, anunciamos o foco com a fala do jogo.
##
## A navegação é só por setas (sem Tab), na orientação escolhida em Opções
## (ver MenuNav): escolher, confirmar e voltar. As setas são tratadas aqui, não
## pela navegação de foco do Godot, que perdia o foco na primeira opção.
## Campos de texto são MenuTextField: na navegação mostram "Nome: valor" e
## só abrem o campo de digitar ao confirmar.
## O visual tem contraste alto e foco bem marcado, para quem enxerga pouco.
##
## O VSync fica desligado por padrão (project.godot, com teto de 60 quadros por
## segundo; dá para ligar em Opções):
## o Godot só entrega o foco novo ao leitor de tela quando o quadro sai, e com
## VSync isso pode levar segundos em PCs com o monitor desligado, cortina de
## tela ou driver de vídeo antigo.
##
## Para investigar atrasos no PC de alguém, cada troca de foco por seta grava no log
## (user://logs/godot.log) quanto tempo passou entre a tecla e o quadro que
## levou o foco ao leitor de tela.

@onready var main_page: Control = %MainPage
@onready var options_page: Control = %OptionsPage
@onready var connect_button: Button = %ConnectButton
@onready var options_button: Button = %OptionsButton
@onready var quit_button: Button = %QuitButton
@onready var vsync_check: CheckButton = %VsyncCheck
@onready var graphics_check: CheckButton = %GraphicsCheck
@onready var nav_button: Button = %NavButton
@onready var back_button: Button = %BackButton
@onready var ui_sound: AudioStreamPlayer = %UiSound

var name_field: MenuTextField
var _key_usec := -1


func _ready() -> void:
	# Modos vindos da linha de comando pulam o menu.
	if Net.mode != Net.Mode.NONE:
		_start_game.call_deferred()
		return

	theme = UiTheme.build()
	connect_button.pressed.connect(_on_connect)
	options_button.pressed.connect(_show_options)
	quit_button.pressed.connect(func(): get_tree().quit())
	back_button.pressed.connect(_show_main)
	name_field = MenuTextField.new("Nome")
	name_field.max_length = 24
	name_field.placeholder = "Como sua criatura se chama?"
	options_page.add_child(name_field)
	options_page.move_child(name_field, 1)  # logo depois do título
	name_field.nav_control().pressed.connect(_say_editing)
	name_field.submitted.connect(func(_t): _say_field_done("Nome"))
	vsync_check.toggled.connect(_on_vsync_toggled)
	graphics_check.toggled.connect(_on_graphics_toggled)
	nav_button.pressed.connect(_on_nav_pressed)
	for control: Control in [connect_button, options_button, quit_button, name_field.nav_control(), vsync_check, graphics_check, nav_button, back_button]:
		control.focus_entered.connect(_on_focus.bind(control))
	for button: Button in [connect_button, options_button, quit_button, back_button, nav_button]:
		button.pressed.connect(_play.bind(Sounds.ui_confirm()))

	_show_main(false)
	Music.start()
	Speech.say(Updater.take_notice() + "Fawna. Menu principal. " + MenuNav.help())


func _input(event: InputEvent) -> void:
	# Sem Tab nos menus: a navegação é só pelas setas.
	if event.is_action("ui_focus_next") or event.is_action("ui_focus_prev"):
		get_viewport().set_input_as_handled()
		return
	for input_action: String in MenuNav.ACTIONS:
		if not event.is_action(input_action):
			continue
		if _editing():  # as setas movem o cursor do campo
			return
		get_viewport().set_input_as_handled()
		if event.is_pressed():
			_key_usec = Time.get_ticks_usec()
			_navigate(MenuNav.from_event(event))
		return


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _editing():
		get_viewport().set_input_as_handled()
		_navigate("voltar")


func _editing() -> bool:
	return name_field != null and name_field.is_editing()


## Itens navegáveis da página aberta, na ordem de cima para baixo. Campos de
## texto entram pelo botão (nav_control).
func _page_items() -> Array[Control]:
	var page: Control = options_page if options_page.visible else main_page
	var items: Array[Control] = []
	for child in page.get_children():
		if not child.visible:
			continue
		if child is MenuTextField:
			items.append((child as MenuTextField).nav_control())
		elif child is BaseButton:
			items.append(child)
	return items


func _navigate(action: String) -> void:
	match action:
		"anterior", "proximo":
			var items := _page_items()
			if items.is_empty():
				return
			var at := items.find(get_viewport().gui_get_focus_owner())
			var next := 0 if at < 0 else posmod(at + (-1 if action == "anterior" else 1), items.size())
			items[next].grab_focus()
		"confirmar":
			var focused := get_viewport().gui_get_focus_owner()
			if focused is BaseButton:
				var button := focused as BaseButton
				if button.toggle_mode:
					button.button_pressed = not button.button_pressed
				else:
					button.pressed.emit()
		"voltar":
			if options_page.visible:
				_show_main()
			else:
				_play(Sounds.ui_limit())


func _show_main(save := true) -> void:
	if save:
		Net.player_name = name_field.value
		Net.save_settings()
	options_page.hide()
	main_page.show()
	connect_button.grab_focus.call_deferred()
	if save:
		Speech.say("Opções salvas. Menu principal.", false)


func _show_options() -> void:
	name_field.value = Net.player_name
	vsync_check.set_pressed_no_signal(Net.vsync)
	graphics_check.set_pressed_no_signal(Net.graphics_off)
	_refresh_nav_button()
	main_page.hide()
	options_page.show()
	Speech.say("Opções.", true)
	name_field.nav_control().grab_focus.call_deferred()


## Aplica na hora, para dar para sentir a diferença antes de salvar.
func _on_vsync_toggled(on: bool) -> void:
	Net.vsync = on
	Net.apply_vsync()
	_play(Sounds.ui_confirm())
	if not Speech.screen_reader_active():
		Speech.say(_on_off(on))


## Gráficos desligados: vale ao entrar no jogo, para os menus continuarem
## visíveis (e o leitor de tela recebendo o foco).
func _on_graphics_toggled(on: bool) -> void:
	Net.graphics_off = on
	_play(Sounds.ui_confirm())
	if not Speech.screen_reader_active():
		Speech.say(_on_off(on))


func _on_nav_pressed() -> void:
	Net.vertical_nav = not Net.vertical_nav
	_refresh_nav_button()
	# Aplica na hora, no menu e no jogo; salva ao sair de Opções.
	Speech.say("Navegação %s. %s" % [_nav_name(), MenuNav.help()])


func _nav_name() -> String:
	return "vertical" if Net.vertical_nav else "horizontal"


func _refresh_nav_button() -> void:
	nav_button.text = "Navegação dos menus: %s" % _nav_name().capitalize()


func _say_editing() -> void:
	if not Speech.screen_reader_active():
		Speech.say("Digite o nome. Enter confirma e Esc cancela.")


func _say_field_done(field: String) -> void:
	_play(Sounds.ui_confirm())
	if not Speech.screen_reader_active():
		Speech.say("%s: %s" % [field, name_field.value if not name_field.value.is_empty() else "vazio"])


func _on_off(on: bool) -> String:
	return "ligado" if on else "desligado"


func _on_connect() -> void:
	Net.mode = Net.Mode.CLIENT
	_start_game()


func _on_focus(control: Control) -> void:
	_play(Sounds.ui_move())
	# Foco vindo de tecla corta o anúncio anterior: com fila, setas rápidas
	# acumulavam falas e a voz ficava para trás. Foco automático (ao abrir
	# uma página) espera o anúncio da página terminar.
	var interrupt := _key_usec >= 0
	_log_focus_delay(control)
	if Speech.screen_reader_active():
		return
	if control == name_field.nav_control():
		Speech.say(name_field.spoken(), interrupt)
	elif control == vsync_check:
		Speech.say("VSync, %s. Botão de alternar. Deixe desligado se o leitor de tela demorar." % _on_off(vsync_check.button_pressed), interrupt)
	elif control == graphics_check:
		Speech.say("Desligar os gráficos, %s. Botão de alternar. Gasta bem menos processador no jogo; a janela fica parada." % _on_off(graphics_check.button_pressed), interrupt)
	elif control == connect_button:
		Speech.say("Conectar, como %s. Botão." % Net.player_name, interrupt)
	elif control is Button:
		Speech.say("%s, botão" % (control as Button).text, interrupt)


## Grava no log o tempo entre a tecla e o começo do segundo quadro depois do
## foco: nesse ponto o quadro do foco já foi desenhado e apresentado (é aí
## que o VSync segura), e o leitor de tela já recebeu o foco novo.
func _log_focus_delay(control: Control) -> void:
	var key_usec := _key_usec
	_key_usec = -1
	var name_text := String(control.name)
	await get_tree().process_frame
	await get_tree().process_frame
	if key_usec < 0:
		print("[menu] foco em %s (sem tecla)" % name_text)
		return
	print("[menu] foco em %s: %d ms depois da tecla | %d qps | leitor de tela: %d | fala: %s" % [
		name_text, (Time.get_ticks_usec() - key_usec) / 1000, Engine.get_frames_per_second(),
		DisplayServer.accessibility_screen_reader_active(), Speech.backend_name])


func _play(stream: AudioStream) -> void:
	if stream == null or not ui_sound.is_inside_tree():
		return  # ex.: Conectar já trocou de cena
	ui_sound.stream = stream
	ui_sound.play()


func _start_game() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")
