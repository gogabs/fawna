extends Control
## Menu inicial: nome, endereço, hospedar ou entrar.
##
## Usa nós nativos do Godot, que o leitor de tela lê sozinho (Godot 4.5+).
## Sem leitor de tela, anunciamos o foco com a fala do jogo.

@onready var name_edit: LineEdit = %NameEdit
@onready var address_edit: LineEdit = %AddressEdit
@onready var host_button: Button = %HostButton
@onready var join_button: Button = %JoinButton


func _ready() -> void:
	# Modos vindos da linha de comando pulam o menu.
	if Net.mode != Net.Mode.NONE:
		_start_game.call_deferred()
		return

	name_edit.text = Net.player_name
	address_edit.text = Net.address
	host_button.pressed.connect(_on_host)
	join_button.pressed.connect(_on_join)
	name_edit.text_submitted.connect(func(_t): address_edit.grab_focus())
	address_edit.text_submitted.connect(func(_t): _on_join())
	for control: Control in [name_edit, address_edit, host_button, join_button]:
		control.focus_entered.connect(_announce_focus.bind(control))

	Speech.say("Fawna. Menu inicial. Use Tab para navegar entre os campos e botões.")
	name_edit.grab_focus.call_deferred()


func _announce_focus(control: Control) -> void:
	if Speech.screen_reader_active():
		return
	if control is LineEdit:
		var field := control as LineEdit
		var value := field.text if not field.text.is_empty() else "vazio"
		Speech.say("%s, campo de texto, %s" % [field.accessibility_name, value], false)
	elif control is Button:
		Speech.say("%s, botão" % (control as Button).text, false)


func _on_host() -> void:
	_read_fields()
	Net.mode = Net.Mode.HOST
	_start_game()


func _on_join() -> void:
	_read_fields()
	Net.mode = Net.Mode.CLIENT
	_start_game()


func _read_fields() -> void:
	Net.player_name = name_edit.text.strip_edges()
	var address := address_edit.text.strip_edges()
	if address.contains(":"):
		Net.port = int(address.get_slice(":", 1))
		address = address.get_slice(":", 0)
	Net.address = address if not address.is_empty() else "127.0.0.1"


func _start_game() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")
