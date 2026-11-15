extends Control
## Menu principal: Conectar, Opções e Sair.
##
## Usa nós nativos do Godot, que o leitor de tela lê sozinho (Godot 4.5+).
## Sem leitor de tela, anunciamos o foco com a fala do jogo.
## O visual tem contraste alto e foco bem marcado, para quem enxerga pouco.
##
## O VSync fica desligado por padrão (project.godot, com teto de 60 quadros por
## segundo; dá para ligar em Opções):
## o Godot só entrega o foco novo ao leitor de tela quando o quadro sai, e com
## VSync isso pode levar segundos em PCs com o monitor desligado, cortina de
## tela ou driver de vídeo antigo.
##
## Para investigar atrasos no PC de alguém, cada troca de foco por seta ou Tab grava no log
## (user://logs/godot.log) quanto tempo passou entre a tecla e o quadro que
## levou o foco ao leitor de tela.

@onready var main_page: Control = %MainPage
@onready var options_page: Control = %OptionsPage
@onready var connect_button: Button = %ConnectButton
@onready var options_button: Button = %OptionsButton
@onready var quit_button: Button = %QuitButton
@onready var name_edit: LineEdit = %NameEdit
@onready var server_edit: LineEdit = %ServerEdit
@onready var vsync_check: CheckButton = %VsyncCheck
@onready var back_button: Button = %BackButton
@onready var ui_sound: AudioStreamPlayer = %UiSound

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
	name_edit.text_submitted.connect(func(_t): server_edit.grab_focus())
	server_edit.text_submitted.connect(func(_t): vsync_check.grab_focus())
	vsync_check.toggled.connect(_on_vsync_toggled)
	for control: Control in [connect_button, options_button, quit_button, name_edit, server_edit, vsync_check, back_button]:
		control.focus_entered.connect(_on_focus.bind(control))
	for button: Button in [connect_button, options_button, quit_button, back_button]:
		button.pressed.connect(_play.bind(Sounds.ui_confirm()))

	_show_main(false)
	Music.start()
	Speech.say(Updater.take_notice() + "Fawna. Menu principal. Use as setas ou Tab para escolher e Enter para confirmar.")


func _input(event: InputEvent) -> void:
	for action in ["ui_up", "ui_down", "ui_left", "ui_right", "ui_focus_next", "ui_focus_prev"]:
		if event.is_action_pressed(action, true):
			_key_usec = Time.get_ticks_usec()
			return


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and options_page.visible:
		_show_main()
		get_viewport().set_input_as_handled()


func _show_main(save := true) -> void:
	if save:
		Net.player_name = name_edit.text.strip_edges() if not name_edit.text.strip_edges().is_empty() else "Criatura"
		Net.set_server(server_edit.text)
		Net.vsync = vsync_check.button_pressed
		Net.save_settings()
	options_page.hide()
	main_page.show()
	connect_button.grab_focus.call_deferred()
	if save:
		Speech.say("Opções salvas. Menu principal.", false)


func _show_options() -> void:
	name_edit.text = Net.player_name
	server_edit.text = Net.server_text()
	vsync_check.set_pressed_no_signal(Net.vsync)
	main_page.hide()
	options_page.show()
	Speech.say("Opções.", true)
	name_edit.grab_focus.call_deferred()


## Aplica na hora, para dar para sentir a diferença antes de salvar.
func _on_vsync_toggled(on: bool) -> void:
	Net.vsync = on
	Net.apply_vsync()
	_play(Sounds.ui_confirm())
	if not Speech.screen_reader_active():
		Speech.say(_on_off(on))


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
	if control is LineEdit:
		var field := control as LineEdit
		var value := field.text if not field.text.is_empty() else "vazio"
		Speech.say("%s, campo de texto, %s" % [field.accessibility_name, value], interrupt)
	elif control == vsync_check:
		Speech.say("VSync, %s. Botão de alternar. Deixe desligado se o leitor de tela demorar." % _on_off(vsync_check.button_pressed), interrupt)
	elif control == connect_button:
		Speech.say("Conectar, como %s, em %s. Botão." % [Net.player_name, Net.server_text()], interrupt)
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
