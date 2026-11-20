class_name MenuTextField
extends HBoxContainer
## Campo de texto de menu. Na navegação aparece só "Nome: valor", como um
## botão; ao confirmar, vira um campo para digitar (Enter aceita, Esc
## cancela). Usar este padrão em todos os campos de texto dos menus.
##
## Quem navega usa nav_control() (o botão, que recebe o foco) e is_editing()
## (enquanto edita, as setas movem o cursor, não o menu).

signal submitted(text: String)
signal cancelled

var label := ""
var value := "":
	set(v):
		value = v
		_refresh()
var empty_text := "vazio"
var max_length := 0
var placeholder := ""
## Campo de senha: não mostra o que foi digitado, nem na tela nem na fala.
var secret := false

var _button: Button
var _edit: LineEdit


func _init(field_label := "", initial := "") -> void:
	label = field_label
	value = initial
	_button = Button.new()
	_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_button.pressed.connect(begin_edit)
	_edit = LineEdit.new()
	_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit.visible = false
	_edit.text_submitted.connect(_on_submitted)
	_edit.gui_input.connect(_on_edit_input)
	add_child(_button)
	add_child(_edit)
	_refresh()


func nav_control() -> Control:
	return _button


func is_editing() -> bool:
	return _edit.visible


## O que o leitor de tela e a fala dizem na navegação.
func spoken() -> String:
	if secret:
		return "%s: %s" % [label, "definida" if not value.is_empty() else empty_text]
	return "%s: %s" % [label, value if not value.is_empty() else empty_text]


func begin_edit() -> void:
	_edit.max_length = max_length
	_edit.placeholder_text = placeholder
	_edit.accessibility_name = label
	_edit.secret = secret
	_edit.text = value
	_button.hide()
	_edit.show()
	_edit.grab_focus()
	_edit.select_all()
	_edit.caret_column = _edit.text.length()


func end_edit() -> void:
	_edit.hide()
	_button.show()
	_button.grab_focus()


func _on_submitted(text: String) -> void:
	value = text.strip_edges()
	end_edit()
	submitted.emit(value)


func _on_edit_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_edit.accept_event()
		end_edit()
		cancelled.emit()


func _refresh() -> void:
	if _button == null:
		return
	_button.text = spoken()
	_button.accessibility_name = spoken()
