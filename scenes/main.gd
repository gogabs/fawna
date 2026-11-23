extends Control
## Menu principal e Opções.
##
## Usa nós nativos do Godot, que o leitor de tela lê sozinho (Godot 4.5+).
## Sem leitor de tela, anunciamos o foco com a fala do jogo.
##
## A navegação é só por setas (sem Tab nem Enter), sempre vertical (ver
## MenuNav): cima e baixo escolhem, direita confirma e esquerda volta. As setas são tratadas aqui, não
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
@onready var host_button: Button = %HostButton
@onready var join_button: Button = %JoinButton
@onready var notice_label: Label = %NoticeLabel
@onready var join_page: Control = %JoinPage
@onready var join_status: Label = %JoinStatus
@onready var found_box: VBoxContainer = %FoundBox
@onready var rescan_button: Button = %RescanButton
@onready var join_back_button: Button = %JoinBackButton
@onready var options_button: Button = %OptionsButton
@onready var quit_button: Button = %QuitButton
@onready var vsync_check: CheckButton = %VsyncCheck
@onready var graphics_page: Control = %GraphicsPage
@onready var graphics_button: Button = %GraphicsButton
@onready var graphics_back_button: Button = %GraphicsBackButton
@onready var preset_button: Button = %PresetButton
@onready var shadows_check: CheckButton = %ShadowsCheck
@onready var msaa_button: Button = %MsaaButton
@onready var glow_check: CheckButton = %GlowCheck
@onready var back_button: Button = %BackButton
@onready var ui_sound: AudioStreamPlayer = %UiSound

var name_field: MenuTextField
var password_field: MenuTextField
var _notice_dialog: AcceptDialog
var ip_field: MenuTextField
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
	rescan_button.pressed.connect(_start_scan)
	join_back_button.pressed.connect(_show_main.bind(false))
	ip_field = MenuTextField.new("IP")
	ip_field.placeholder = "ip ou ip:porta"
	ip_field.empty_text = "digitar"
	join_page.add_child(ip_field)
	join_page.move_child(ip_field, found_box.get_index() + 1)
	ip_field.nav_control().pressed.connect(_say_editing_ip)
	ip_field.submitted.connect(_on_ip_submitted)
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
	password_field = MenuTextField.new("Senha")
	password_field.secret = true
	password_field.max_length = Credentials.MAX_LENGTH
	password_field.placeholder = "Protege sua criatura. Mínimo %d caracteres." % Credentials.MIN_LENGTH
	password_field.empty_text = "definir"
	options_page.add_child(password_field)
	options_page.move_child(password_field, name_field.get_index() + 1)
	password_field.nav_control().pressed.connect(_say_editing_password)
	password_field.submitted.connect(func(_t): _say_field_done("Senha"))
	vsync_check.toggled.connect(_on_vsync_toggled)
	graphics_button.pressed.connect(_show_graphics)
	graphics_back_button.pressed.connect(_back_to_options)
	preset_button.pressed.connect(_on_preset_pressed)
	shadows_check.toggled.connect(_on_shadows_toggled)
	msaa_button.pressed.connect(_on_msaa_pressed)
	glow_check.toggled.connect(_on_glow_toggled)
	for control: Control in [connect_button, host_button, join_button, options_button, quit_button, name_field.nav_control(), password_field.nav_control(), ip_field.nav_control(), graphics_button, graphics_back_button, preset_button, vsync_check, shadows_check, msaa_button, glow_check, back_button, rescan_button, join_back_button]:
		control.focus_entered.connect(_on_focus.bind(control))
	for button: Button in [connect_button, host_button, join_button, options_button, quit_button, back_button, rescan_button, join_back_button, preset_button, msaa_button, graphics_button, graphics_back_button]:
		button.pressed.connect(_play.bind(Sounds.ui_confirm()))

	_show_main(false)
	Music.start()
	if Net.menu_notice.is_empty():
		Speech.say(Updater.take_notice() + "Fawna. Menu principal. " + MenuNav.help())
	else:
		_show_notice_box(Net.menu_notice)
		Net.menu_notice = ""


## Caixa de aviso (senha errada, servidor fora do ar...): confirmar ou voltar
## fecha e devolve o foco ao menu principal.
func _show_notice_box(text: String) -> void:
	_notice_dialog = AcceptDialog.new()
	_notice_dialog.title = "Aviso"
	_notice_dialog.dialog_text = text
	_notice_dialog.dialog_autowrap = true
	_notice_dialog.ok_button_text = "OK"
	_notice_dialog.exclusive = true
	_notice_dialog.canceled.connect(_close_notice_box)
	_notice_dialog.confirmed.connect(_close_notice_box)
	add_child(_notice_dialog)
	_notice_dialog.popup_centered(Vector2i(560, 0))
	_notice_dialog.get_ok_button().grab_focus.call_deferred()
	Speech.say("Aviso. %s Aperte Enter ou a seta de confirmar para fechar." % text, true)


func _close_notice_box() -> void:
	if _notice_dialog == null:
		return
	_notice_dialog.queue_free()
	_notice_dialog = null
	connect_button.grab_focus.call_deferred()
	Speech.say("Menu principal.", false)


func _input(event: InputEvent) -> void:
	if _notice_dialog != null:
		for nav_action: String in MenuNav.ACTIONS:
			if event.is_action(nav_action):
				get_viewport().set_input_as_handled()
				if event.is_pressed() and MenuNav.from_event(event) in ["confirmar", "voltar"]:
					_close_notice_box()
				return
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
	if event.is_action_pressed("ui_cancel") and not _editing() and _notice_dialog == null:
		get_viewport().set_input_as_handled()
		_navigate("voltar")


func _editing() -> bool:
	return (name_field != null and name_field.is_editing()) or (password_field != null and password_field.is_editing()) or (ip_field != null and ip_field.is_editing())


func _process(delta: float) -> void:
	if _scan_left <= 0.0:
		return
	_scan_left -= delta
	if _scan_left <= 0.0:
		_stop_scan()
		if found_box.get_child_count() == 0:
			join_status.text = "Nenhum jogo privado encontrado na rede."
			Speech.say(join_status.text, false)


## Itens navegáveis da página aberta, na ordem de cima para baixo. Campos de
## texto entram pelo botão (nav_control).
func _page_items() -> Array[Control]:
	var page: Control = main_page
	if graphics_page.visible:
		page = graphics_page
	elif options_page.visible:
		page = options_page
	elif join_page.visible:
		page = join_page
	var items: Array[Control] = []
	for child in page.get_children():
		if not child.visible:
			continue
		if child is MenuTextField:
			items.append((child as MenuTextField).nav_control())
		elif child == found_box:  # jogos encontrados, um botão cada
			for found in found_box.get_children():
				items.append(found)
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
			if graphics_page.visible:
				_back_to_options()
			elif options_page.visible:
				_show_main()
			elif join_page.visible:
				_show_main(false)
			else:
				_play(Sounds.ui_limit())


func _show_main(save := true) -> void:
	if save:
		Net.player_name = name_field.value
		Net.password = password_field.value
		Net.save_settings()
	_stop_scan()
	options_page.hide()
	graphics_page.hide()
	join_page.hide()
	main_page.show()
	connect_button.text = ("Entrar no mundo como %s" % Net.player_name) if _has_name() else "Entrar no mundo"
	notice_label.hide()
	connect_button.grab_focus.call_deferred()
	if save:
		Speech.say("Configurações salvas. Menu principal.", false)


func _show_options() -> void:
	name_field.value = Net.player_name
	password_field.value = Net.password
	vsync_check.set_pressed_no_signal(Net.vsync)
	_refresh_graphics()
	main_page.hide()
	options_page.show()
	Speech.say("Configurações.", true)
	name_field.nav_control().grab_focus.call_deferred()


func _show_graphics() -> void:
	_refresh_graphics()
	options_page.hide()
	graphics_page.show()
	Speech.say("Gráficos.", true)
	preset_button.grab_focus.call_deferred()


## Volta da categoria Gráficos sem refazer os campos de nome e senha.
func _back_to_options() -> void:
	graphics_page.hide()
	options_page.show()
	Speech.say("Configurações.", true)
	graphics_button.grab_focus.call_deferred()


## Aplica na hora, para dar para sentir a diferença antes de salvar.
func _on_vsync_toggled(on: bool) -> void:
	Net.vsync = on
	Net.apply_vsync()
	_play(Sounds.ui_confirm())
	if not Speech.screen_reader_active():
		Speech.say(_on_off(on))


## Os gráficos valem ao entrar no jogo, para os menus continuarem visíveis
## (e o leitor de tela recebendo o foco). "Desativados" para de desenhar.
func _on_preset_pressed() -> void:
	var preset := Net.graphics_preset()
	Net.set_graphics_preset((preset + 1) % Net.PRESET_NAMES.size() if preset >= 0 else 1)
	_refresh_graphics()
	_say_choice(preset_button.text)


func _on_shadows_toggled(on: bool) -> void:
	Net.shadows = on
	_refresh_graphics()
	_play(Sounds.ui_confirm())
	if not Speech.screen_reader_active():
		Speech.say("%s. %s" % [_on_off(on), preset_button.text])


func _on_msaa_pressed() -> void:
	Net.msaa = {0: 2, 2: 4, 4: 0}.get(Net.msaa, 0)
	_refresh_graphics()
	_say_choice(msaa_button.text)


func _on_glow_toggled(on: bool) -> void:
	Net.glow = on
	_refresh_graphics()
	_play(Sounds.ui_confirm())
	if not Speech.screen_reader_active():
		Speech.say("%s. %s" % [_on_off(on), preset_button.text])


func _say_choice(text: String) -> void:
	if not Speech.screen_reader_active():
		Speech.say(text)


func _refresh_graphics() -> void:
	preset_button.text = "Preset de gráficos: %s" % Net.graphics_preset_name()
	msaa_button.text = "Antisserrilhamento: %s" % ("Desligado" if Net.msaa == 0 else "%dx" % Net.msaa)
	shadows_check.set_pressed_no_signal(Net.shadows)
	glow_check.set_pressed_no_signal(Net.glow)


func _say_editing() -> void:
	if not Speech.screen_reader_active():
		Speech.say("Digite o nome. Enter confirma e Esc cancela.")


func _say_editing_password() -> void:
	if not Speech.screen_reader_active():
		Speech.say("Digite a senha. Enter confirma e Esc cancela.")


func _say_field_done(field: String) -> void:
	_play(Sounds.ui_confirm())
	if not Speech.screen_reader_active():
		var field_value := password_field.spoken().get_slice(": ", 1) if field == "Senha" else name_field.value
		Speech.say("%s: %s" % [field, field_value if not field_value.is_empty() else "vazio"])


func _on_off(on: bool) -> String:
	return "ligado" if on else "desligado"


func _has_name() -> bool:
	return not Net.player_name.strip_edges().is_empty()


## Sem nome e senha não se entra em lugar nenhum: ambos vêm de Opções.
func _require_name() -> bool:
	if _has_name() and Net.password.length() >= Credentials.MIN_LENGTH:
		return true
	if _has_name():
		notice_label.text = "Defina uma senha de pelo menos %d caracteres nas Configurações antes de entrar." % Credentials.MIN_LENGTH
	else:
		notice_label.text = "Defina seu nome e uma senha nas Configurações antes de entrar."
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


func _say_editing_ip() -> void:
	if not Speech.screen_reader_active():
		Speech.say("Digite o IP. Enter confirma e Esc cancela.")


func _on_ip_submitted(text: String) -> void:
	_play(Sounds.ui_confirm())
	if not text.is_empty():
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
	if control == name_field.nav_control():
		Speech.say(name_field.spoken(), interrupt)
	elif control == password_field.nav_control():
		Speech.say(password_field.spoken(), interrupt)
	elif control == vsync_check:
		Speech.say("VSync, %s. Botão de alternar. Deixe desligado se o leitor de tela demorar." % _on_off(vsync_check.button_pressed), interrupt)
	elif control == graphics_button:
		Speech.say("Gráficos, botão. Preset, VSync, sombras e mais.", interrupt)
	elif control == preset_button:
		Speech.say("%s. Botão. Desativados para de desenhar no jogo e gasta bem menos processador. Mais desempenho desliga sombras e brilho. Melhores gráficos liga tudo." % preset_button.text, interrupt)
	elif control == shadows_check:
		Speech.say("Sombras, %s. Botão de alternar. Pesa na placa de vídeo." % _on_off(shadows_check.button_pressed), interrupt)
	elif control == glow_check:
		Speech.say("Brilho nas luzes, %s. Botão de alternar." % _on_off(glow_check.button_pressed), interrupt)
	elif control == ip_field.nav_control():
		Speech.say(ip_field.spoken(), interrupt)
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
