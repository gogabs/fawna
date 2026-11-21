class_name BodyBars
extends CanvasLayer
## As duas reservas do corpo na tela, no canto de baixo à esquerda: saciedade
## (o contrário da fome) e calor, cheias quando a criatura está bem. Só visual;
## quem não enxerga ouve a barra sonora (Survival: um toque no estéreo a cada
## 20 pontos).

const WIDTH := 220.0
const FOOD_COLOR := Color("c9a227")
const WARMTH_COLOR := Color("d0603a")
const COLD_COLOR := Color("7fa7c9")  # o calor baixo esfria de cor
const BACK_COLOR := Color(0.05, 0.06, 0.07, 0.65)

var _food: ProgressBar
var _warmth: ProgressBar
var _warmth_fill: StyleBoxFlat


func _ready() -> void:
	layer = 5
	var panel := PanelContainer.new()
	panel.name = "Corpo"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 16.0
	panel.offset_top = -92.0
	panel.offset_bottom = -16.0
	var back := StyleBoxFlat.new()
	back.bg_color = BACK_COLOR
	back.set_corner_radius_all(8)
	back.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", back)
	add_child(panel)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	panel.add_child(rows)
	_food = _row(rows, "Saciedade", FOOD_COLOR)
	_warmth = _row(rows, "Calor", WARMTH_COLOR)
	_warmth_fill = _warmth.get_theme_stylebox("fill") as StyleBoxFlat


func _row(parent: Control, text: String, color: Color) -> ProgressBar:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(96, 0)
	label.add_theme_color_override("font_color", Color("e8e2d0"))
	label.add_theme_font_size_override("font_size", 16)
	row.add_child(label)
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = Body.MAX
	bar.value = Body.MAX
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(WIDTH, 14)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(4)
	var empty := StyleBoxFlat.new()
	empty.bg_color = Color(1, 1, 1, 0.08)
	empty.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", empty)
	row.add_child(bar)
	return bar


## As reservas mudaram (0 a 100). As barras deslizam até o valor novo.
func show_values(food: float, warmth: float) -> void:
	if _food == null:
		return
	for pair: Array in [[_food, food], [_warmth, warmth]]:
		var bar: ProgressBar = pair[0]
		create_tween().tween_property(bar, "value", float(pair[1]), 0.4)
	if _warmth_fill != null:
		_warmth_fill.bg_color = COLD_COLOR.lerp(WARMTH_COLOR, clampf(warmth / 50.0, 0.0, 1.0))
