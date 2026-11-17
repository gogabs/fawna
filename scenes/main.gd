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
## Para investigar atrasos no PC de alguém, cada troca de foco por seta grava no log
## (user://logs/godot.log) quanto tempo passou entre a tecla e o quadro que
## levou o foco ao leitor de tela.

@onready var main_page: Control = %MainPage
@onready var options_page: Control = %OptionsPage
@onready var connect_button: Button = %ConnectButton
@onready var host_button: Button = %HostButton
@onready var join_button: Button = %JoinButton
@onready var notice_label: Label = %NoticeLabel
@onready var join_page: Control = %JoinPage
@onready var join_status: Label = %JoinStatus
@onready var found_box: VBoxContainer = %FoundBox
@onready var ip_button: Button = %IpButton
@onready var ip_edit: LineEdit = %IpEdit
@onready var rescan_button: Button = %RescanButton
@onready var join_back_button: Button = %JoinBackButton
@onready var options_button: Button = %OptionsButton
@onready var quit_button: Button = %QuitButton
@onready var name_edit: LineEdit = %NameEdit
@onready var server_edit: LineEdit = %ServerEdit
@onready var vsync_check: CheckButton = %VsyncCheck
@onready var back_button: Button = %BackButton
@onready var ui_sound: AudioStreamPlayer = %UiSound

var _key_usec := -1
var _scanner: LanDiscovery
var _scan_left := 0.0


func _ready() -> void:
	# Modos vindos da linha de comando pulam o menu.
	if Net.mode != Net.Mode.NONE:
		_start_game.call_deferred()
		return

	theme = UiTheme.build()
	connect_button.pressed.connect(_on_connect)
	host_button.pressed.connect(_on_host)
	join_button.pressed.connect(_show_join)
	ip_button.pressed.connect(_on_ip_button)
	ip_edit.text_submitted.connect(_on_ip_submitted)
	rescan_button.pressed.connect(_start_scan)
	join_back_button.pressed.connect(_show_main.bind(false))
	options_button.pressed.connect(_show_options)
	quit_button.pressed.connect(func(): get_tree().quit())
	back_button.pressed.connect(_show_main)
	name_edit.text_submitted.connect(func(_t): server_edit.grab_focus())
	server_edit.text_submitted.connect(func(_t): vsync_check.grab_focus())
	vsync_check.toggled.connect(_on_vsync_toggled)
	for control: Control in [connect_button, host_button, join_button, options_button, quit_button, name_edit, server_edit, vsync_check, back_button, ip_button, ip_edit, rescan_button, join_back_button]:
		control.focus_entered.connect(_on_focus.bind(control))
	for button: Button in [connect_button, host_button, join_button, options_button, quit_button, back_button, ip_button, rescan_button, join_back_button]:
		button.pressed.connect(_play.bind(Sounds.ui_confirm()))

	_show_main(false)
	Music.start()
	Speech.say(Updater.take_notice() + "Fawna. Menu principal. Use as setas para escolher e Enter para confirmar.")


func _input(event: InputEvent) -> void:
	# O Tab não navega mais pelo menu: só as setas.
	if event.is_action_pressed("ui_focus_next", true) or event.is_action_pressed("ui_focus_prev", true):
		get_viewport().set_input_as_handled()
		return
	for action in ["ui_up", "ui_down", "ui_left", "ui_right"]:
		if event.is_action_pressed(action, true):
			_key_usec = Time.get_ticks_usec()
			return


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if options_page.visible:
			_show_main()
			get_viewport().set_input_as_handled()
		elif join_page.visible:
			_show_main(false)
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _scan_left <= 0.0:
		return
	_scan_left -= delta
	if _scan_left <= 0.0:
		_stop_scan()
		if found_box.get_child_count() == 0:
			join_status.text = "Nenhum jogo privado encontrado na rede."
			Speech.say(join_status.text, false)


func _show_main(save := true) -> void:
	if save:
		Net.player_name = name_edit.text.strip_edges()
		Net.set_server(server_edit.text)
		Net.vsync = vsync_check.button_pressed
		Net.save_settings()
	_stop_scan()
	options_page.hide()
	join_page.hide()
	main_page.show()
	connect_button.text = ("Entrar no mundo como %s" % Net.player_name) if _has_name() else "Entrar no mundo"
	notice_label.hide()
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


func _has_name() -> bool:
	return not Net.player_name.strip_edges().is_empty()


## Sem nome não se entra em lugar nenhum: o nome vem de Opções.
func _require_name() -> bool:
	if _has_name():
		return true
	notice_label.text = "Defina seu nome nas Opções antes de entrar."
	notice_label.show()
	Speech.say(notice_label.text)
	return false


## O mundo principal sempre usa o servidor padrão.
func _on_connect() -> void:
	if not _require_name():
		return
	Net.set_server("")
	Net.mode = Net.Mode.CLIENT
	_start_game()


## Sobe o servidor aqui, ouvindo em qualquer endereço na porta padrão.
func _on_host() -> void:
	if not _require_name():
		return
	Net.port = Net.DEFAULT_PORT
	Net.mode = Net.Mode.HOST
	_start_game()


func _show_join() -> void:
	if not _require_name():
		return
	main_page.hide()
	options_page.hide()
	join_page.show()
	ip_edit.hide()
	ip_button.show()
	Speech.say("Entrar em um jogo privado.", true)
	_start_scan()
	rescan_button.grab_focus.call_deferred()


func _start_scan() -> void:
	_stop_scan()
	for child in found_box.get_children():
		found_box.remove_child(child)
		child.queue_free()
	join_status.text = "Procurando jogos na rede local..."
	Speech.say(join_status.text, false)
	_scanner = LanDiscovery.new()
	add_child(_scanner)
	_scanner.found.connect(_on_game_found)
	_scanner.start_searching()
	_scan_left = 5.0


func _stop_scan() -> void:
	_scan_left = 0.0
	if _scanner != null:
		_scanner.queue_free()
		_scanner = null


func _on_game_found(address: String, port: int, host_name: String, version: String) -> void:
	var button := Button.new()
	button.text = "Jogo de %s, em %s" % [host_name, address]
	if port != Net.DEFAULT_PORT:
		button.text += ":%d" % port
	if version != Updater.current_version():
		button.text += " (versão %s, diferente da sua)" % version
	button.focus_entered.connect(_on_focus.bind(button))
	button.pressed.connect(_play.bind(Sounds.ui_confirm()))
	button.pressed.connect(_join_address.bind(address if port == Net.DEFAULT_PORT else "%s:%d" % [address, port]))
	found_box.add_child(button)
	join_status.text = "Jogos encontrados na rede local:"
	Speech.say("Encontrado: " + button.text, false)


func _on_ip_button() -> void:
	ip_button.hide()
	ip_edit.show()
	ip_edit.grab_focus.call_deferred()


func _on_ip_submitted(text: String) -> void:
	if text.strip_edges().is_empty():
		ip_edit.hide()
		ip_button.show()
		ip_button.grab_focus.call_deferred()
		return
	_join_address(text)


func _join_address(text: String) -> void:
	_stop_scan()
	Net.set_server(text)
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
