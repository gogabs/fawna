extends Control
## Menu principal: Conectar, Opções e Sair.
##
## Usa nós nativos do Godot, que o leitor de tela lê sozinho (Godot 4.5+).
## Sem leitor de tela, anunciamos o foco com a fala do jogo.
## O visual tem contraste alto e foco bem marcado, para quem enxerga pouco.

@onready var main_page: Control = %MainPage
@onready var options_page: Control = %OptionsPage
@onready var connect_button: Button = %ConnectButton
@onready var options_button: Button = %OptionsButton
@onready var quit_button: Button = %QuitButton
@onready var name_edit: LineEdit = %NameEdit
@onready var server_edit: LineEdit = %ServerEdit
@onready var back_button: Button = %BackButton
@onready var ui_sound: AudioStreamPlayer = %UiSound


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
	server_edit.text_submitted.connect(func(_t): _show_main())
	for control: Control in [connect_button, options_button, quit_button, name_edit, server_edit, back_button]:
		control.focus_entered.connect(_on_focus.bind(control))
	for button: Button in [connect_button, options_button, quit_button, back_button]:
		button.pressed.connect(_play.bind(Sounds.ui_confirm()))

	_show_main(false)
	Music.start()
	Speech.say(Updater.take_notice() + "Fawna. Menu principal. Use as setas ou Tab para escolher e Enter para confirmar.")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and options_page.visible:
		_show_main()
		get_viewport().set_input_as_handled()


func _show_main(save := true) -> void:
	if save:
		Net.player_name = name_edit.text.strip_edges() if not name_edit.text.strip_edges().is_empty() else "Criatura"
		Net.set_server(server_edit.text)
		Net.save_settings()
	options_page.hide()
	main_page.show()
	connect_button.grab_focus.call_deferred()
	if save:
		Speech.say("Opções salvas. Menu principal.", false)


func _show_options() -> void:
	name_edit.text = Net.player_name
	server_edit.text = Net.server_text()
	main_page.hide()
	options_page.show()
	Speech.say("Opções.", true)
	name_edit.grab_focus.call_deferred()


func _on_connect() -> void:
	Net.mode = Net.Mode.CLIENT
	_start_game()


func _on_focus(control: Control) -> void:
	_play(Sounds.ui_move())
	if Speech.screen_reader_active():
		return
	if control is LineEdit:
		var field := control as LineEdit
		var value := field.text if not field.text.is_empty() else "vazio"
		Speech.say("%s, campo de texto, %s" % [field.accessibility_name, value], false)
	elif control == connect_button:
		Speech.say("Conectar, como %s, em %s. Botão." % [Net.player_name, Net.server_text()], false)
	elif control is Button:
		Speech.say("%s, botão" % (control as Button).text, false)


func _play(stream: AudioStream) -> void:
	if stream == null or not ui_sound.is_inside_tree():
		return  # ex.: Conectar já trocou de cena
	ui_sound.stream = stream
	ui_sound.play()


func _start_game() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")
