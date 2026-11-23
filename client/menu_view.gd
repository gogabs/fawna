class_name MenuView
extends CanvasLayer
## O menu das setas na tela: o caminho em que você está (Bolsa, Caminheiro...)
## e as opções do nível atual, com a que está em foco destacada. Aparece quando
## o menu é mexido e some sozinho depois de uns segundos. Só visual: o menu em
## si e a fala continuam sendo o FloatingMenu.
##
## Desenhado à mão num Node2D, sem Controls (ver BodyBars): os Controls
## aparecem para o leitor de tela.

const SHOW_SECONDS := 6.0
const FADE_SECONDS := 1.0
const ROWS := 9  # opções visíveis de uma vez (a lista rola junto com o foco)
const ROW_HEIGHT := 28.0
const WIDTH := 380.0
const PAD := 12.0
const MARGIN_X := 16.0
const TOP := 70.0
const FONT_SIZE := 18
const TITLE_SIZE := 20
const BACK_COLOR := Color(0.05, 0.06, 0.07, 0.78)
const FOCUS_COLOR := Color(0.78, 0.65, 0.2, 0.28)
const ACCENT_COLOR := Color("c9a227")
const TEXT_COLOR := Color("e8e2d0")
const DIM_COLOR := Color(0.91, 0.89, 0.82, 0.6)

var _canvas: _Drawing
var _menu: FloatingMenu
var _seen := -1
var _left := 0.0


func setup(menu: FloatingMenu) -> void:
	_menu = menu
	layer = 6
	_canvas = _Drawing.new()
	_canvas.name = "Menu"
	add_child(_canvas)


func _process(delta: float) -> void:
	if _menu == null or _canvas == null:
		return
	if _menu.revision != _seen:
		_seen = _menu.revision
		_left = SHOW_SECONDS
		_canvas.snapshot = _menu.snapshot()
		_canvas.vertical = Net.vertical_nav
	elif _left <= 0.0:
		return
	_left = maxf(_left - delta, 0.0)
	_canvas.alpha = clampf(_left / FADE_SECONDS, 0.0, 1.0)
	_canvas.queue_redraw()


class _Drawing:
	extends Node2D

	var snapshot := {}
	var alpha := 0.0
	var vertical := false

	func _draw() -> void:
		if alpha <= 0.0 or snapshot.is_empty():
			return
		var font := ThemeDB.fallback_font
		var path: Array = snapshot["path"]
		var items: Array = snapshot["items"]
		var index: int = snapshot["index"]
		var title := "Menu" if path.is_empty() else " › ".join(PackedStringArray(path))
		var shown := mini(ROWS, items.size())
		var first := clampi(index - ROWS / 2, 0, maxi(items.size() - ROWS, 0))
		var height := PAD * 2.0 + 34.0 + maxf(shown, 1) * ROW_HEIGHT + 24.0
		var origin := Vector2(MARGIN_X, TOP)
		draw_rect(Rect2(origin, Vector2(WIDTH, height)), _faded(BACK_COLOR))
		draw_rect(Rect2(origin, Vector2(3.0, height)), _faded(ACCENT_COLOR))
		draw_string(font, origin + Vector2(PAD + 4.0, PAD + 20.0), _fit(font, title, TITLE_SIZE), HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_SIZE, _faded(ACCENT_COLOR))
		if items.is_empty():
			draw_string(font, origin + Vector2(PAD + 4.0, PAD + 34.0 + ROW_HEIGHT * 0.7), "nada aqui por enquanto", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, _faded(DIM_COLOR))
		for row in shown:
			var at := first + row
			var top := origin.y + PAD + 34.0 + row * ROW_HEIGHT
			var focused := at == index
			if focused:
				draw_rect(Rect2(origin.x + 6.0, top, WIDTH - 12.0, ROW_HEIGHT - 2.0), _faded(FOCUS_COLOR))
				draw_rect(Rect2(origin.x + 6.0, top, 3.0, ROW_HEIGHT - 2.0), _faded(ACCENT_COLOR))
			draw_string(font, Vector2(origin.x + PAD + 6.0, top + ROW_HEIGHT * 0.7), _fit(font, str(items[at]), FONT_SIZE), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, _faded(TEXT_COLOR if focused else DIM_COLOR))
		if items.size() > ROWS:
			var more := "%d de %d" % [index + 1, items.size()]
			draw_string(font, Vector2(origin.x + WIDTH - PAD - 70.0, origin.y + PAD + 20.0), more, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, _faded(DIM_COLOR))
		var hint := "↑ ↓ escolher   → confirmar   ← voltar" if vertical else "← → escolher   ↑ confirmar   ↓ voltar"
		draw_string(font, Vector2(origin.x + PAD + 4.0, origin.y + height - 10.0), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, _faded(DIM_COLOR))

	func _faded(color: Color) -> Color:
		return Color(color.r, color.g, color.b, color.a * alpha)

	## Corta o texto com "…" se passar da largura do painel.
	func _fit(font: Font, text: String, size: int) -> String:
		var room := WIDTH - PAD * 2.0 - 12.0
		if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= room:
			return text
		while text.length() > 1 and font.get_string_size(text + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > room:
			text = text.left(text.length() - 1)
		return text + "…"
