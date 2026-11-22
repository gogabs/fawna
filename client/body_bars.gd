class_name BodyBars
extends CanvasLayer
## As duas reservas do corpo na tela, no canto de baixo à esquerda: saciedade
## (o contrário da fome) e calor, cheias quando a criatura está bem. Só visual;
## quem não enxerga ouve a barra sonora (Survival: um toque no estéreo a cada
## 20 pontos).
##
## Tudo é desenhado à mão num Node2D, sem nenhum Control (ProgressBar, Label):
## os Controls aparecem para o leitor de tela, e o NVDA lia e bipava a
## porcentagem a cada mudança.

const WIDTH := 220.0
const BAR_HEIGHT := 14.0
const LABEL_WIDTH := 96.0
const ROW_GAP := 26.0
const PAD := 10.0
const MARGIN := 16.0
const FONT_SIZE := 16
const SLIDE := 2.5  # quanto da diferença a barra anda por segundo (desliza até o valor)
const FOOD_COLOR := Color("c9a227")
const WARMTH_COLOR := Color("d0603a")
const COLD_COLOR := Color("7fa7c9")  # o calor baixo esfria de cor
const BACK_COLOR := Color(0.05, 0.06, 0.07, 0.65)
const EMPTY_COLOR := Color(1, 1, 1, 0.08)
const TEXT_COLOR := Color("e8e2d0")

var _canvas: _Drawing
var _target := [Body.MAX, Body.MAX]


func _ready() -> void:
	layer = 5
	_canvas = _Drawing.new()
	_canvas.name = "Corpo"
	add_child(_canvas)


## As reservas mudaram (0 a 100). As barras deslizam até o valor novo.
func show_values(food: float, warmth: float) -> void:
	_target = [food, warmth]


func _process(delta: float) -> void:
	if _canvas == null:
		return
	var changed := false
	for i in 2:
		var now: float = _canvas.shown[i]
		var goal: float = _target[i]
		if absf(goal - now) > 0.05:
			_canvas.shown[i] = lerpf(now, goal, minf(1.0, SLIDE * delta * 4.0))
			changed = true
	if changed or _canvas.last_size != get_viewport().get_visible_rect().size:
		_canvas.queue_redraw()


class _Drawing:
	extends Node2D

	var shown := [Body.MAX, Body.MAX]
	var last_size := Vector2.ZERO

	func _draw() -> void:
		last_size = get_viewport().get_visible_rect().size
		var font := ThemeDB.fallback_font
		var box := Vector2(PAD * 2.0 + LABEL_WIDTH + WIDTH, PAD * 2.0 + ROW_GAP + BAR_HEIGHT + 4.0)
		var origin := Vector2(MARGIN, last_size.y - MARGIN - box.y)
		draw_rect(Rect2(origin, box), BACK_COLOR)
		var rows := [["Saciedade", shown[0], FOOD_COLOR],
			["Calor", shown[1], COLD_COLOR.lerp(WARMTH_COLOR, clampf(float(shown[1]) / 50.0, 0.0, 1.0))]]
		for i in rows.size():
			var top := origin.y + PAD + ROW_GAP * i
			draw_string(font, Vector2(origin.x + PAD, top + BAR_HEIGHT), str(rows[i][0]),
				HORIZONTAL_ALIGNMENT_LEFT, LABEL_WIDTH, FONT_SIZE, TEXT_COLOR)
			var bar := Rect2(origin.x + PAD + LABEL_WIDTH, top + 2.0, WIDTH, BAR_HEIGHT)
			draw_rect(bar, EMPTY_COLOR)
			var fill := bar
			fill.size.x = WIDTH * clampf(float(rows[i][1]) / Body.MAX, 0.0, 1.0)
			draw_rect(fill, rows[i][2])
