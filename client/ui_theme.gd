class_name UiTheme
extends RefCounted
## Tema visual dos menus: contraste alto e foco laranja bem marcado,
## para quem enxerga pouco. Usado pelo menu principal e pelo atualizador.

const COLOR_BG_TOP := Color("1d3b2a")
const COLOR_BG_BOTTOM := Color("0f2018")
const COLOR_PANEL := Color("f4ecd8")
const COLOR_TEXT := Color("1f2a24")
const COLOR_ACCENT := Color("f6c453")
const COLOR_BUTTON := Color("3f7d4e")
const COLOR_BUTTON_HOVER := Color("4f9a60")
const COLOR_FOCUS := Color("e8792b")


static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = 22

	var normal := _box(COLOR_BUTTON, 14)
	var hover := _box(COLOR_BUTTON_HOVER, 14)
	var focus := _box(Color(0, 0, 0, 0), 14)
	focus.draw_center = false
	focus.border_color = COLOR_FOCUS
	focus.set_border_width_all(4)
	focus.expand_margin_left = 4
	focus.expand_margin_right = 4
	focus.expand_margin_top = 4
	focus.expand_margin_bottom = 4
	for state in ["normal", "disabled"]:
		t.set_stylebox(state, "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", _box(COLOR_TEXT, 14))
	t.set_stylebox("focus", "Button", focus)
	t.set_color("font_color", "Button", Color.WHITE)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", COLOR_ACCENT)
	t.set_font_size("font_size", "Button", 26)

	var field := _box(Color.WHITE, 10)
	field.border_color = COLOR_BUTTON
	field.set_border_width_all(2)
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", focus)
	t.set_color("font_color", "LineEdit", COLOR_TEXT)
	t.set_color("caret_color", "LineEdit", COLOR_TEXT)
	t.set_color("font_placeholder_color", "LineEdit", Color(COLOR_TEXT, 0.5))

	t.set_stylebox("focus", "RichTextLabel", focus)
	t.set_color("default_color", "RichTextLabel", COLOR_TEXT)
	var bar_bg := _box(Color.WHITE, 10, 0)
	bar_bg.border_color = COLOR_BUTTON
	bar_bg.set_border_width_all(2)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", _box(COLOR_BUTTON, 10, 0))
	t.set_color("font_color", "ProgressBar", COLOR_TEXT)
	t.set_color("font_color", "Label", COLOR_TEXT)
	t.set_stylebox("panel", "PanelContainer", _box(COLOR_PANEL, 24, 36))
	return t


static func _box(color: Color, radius: int, padding := 12) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.content_margin_left = padding + 8
	box.content_margin_right = padding + 8
	box.content_margin_top = padding
	box.content_margin_bottom = padding
	return box
