class_name NamePrompt
extends CanvasLayer
## Caixinha de edição para dar um nome (por enquanto, aos marcos). Abre por
## cima do jogo, com o foco no campo: Enter confirma, Esc cancela. Enquanto
## está aberta, o jogo não anda nem usa as teclas (game.gd confere is_open()).
## O texto falado vai pela Speech; com leitor de tela, o campo também tem
## accessibility_name.

signal submitted(text: String)
signal cancelled

var _panel: PanelContainer
var _edit: LineEdit
var _title: Label
var _open := false


func _ready() -> void:
	layer = 10
	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(420, 0)
	var box := VBoxContainer.new()
	_panel.add_child(box)
	_title = Label.new()
	box.add_child(_title)
	_edit = LineEdit.new()
	_edit.max_length = Builds.MAX_NAME
	_edit.text_submitted.connect(_on_submitted)
	box.add_child(_edit)
	add_child(_panel)
	_panel.hide()


func is_open() -> bool:
	return _open


## Abre a caixinha com um título ("Nome do marco") e o texto inicial.
func ask(title: String, initial := "") -> void:
	_title.text = title
	_edit.accessibility_name = title
	_edit.text = initial
	_open = true
	_panel.show()
	_edit.grab_focus()
	_edit.select_all()
	if not Speech.screen_reader_active():
		Speech.say("%s, campo de texto. Digite e aperte Enter; Esc cancela." % title)


func _input(event: InputEvent) -> void:
	if _open and event is InputEventKey and event.is_pressed() and (event as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_close()
		cancelled.emit()


## Fecha sem avisar ninguém (testes automáticos).
func cancel_silently() -> void:
	if _open:
		_close()


func _on_submitted(text: String) -> void:
	if not _open:
		return
	_close()
	submitted.emit(text)


func _close() -> void:
	_open = false
	_edit.release_focus()
	_panel.hide()
