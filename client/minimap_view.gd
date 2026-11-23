class_name MinimapView
extends CanvasLayer
## Minimapa redondo no canto de cima à direita, com a bússola em volta: o mapa
## gira para a frente da criatura ficar sempre para cima, e as letras N, L, S e
## O dão a volta no anel, sempre onde cada direção está. Só visual (quem não
## enxerga ouve a bússola de cliques).
##
## Tudo é desenhado à mão num Node2D, sem nenhum Control: os Controls aparecem
## para o leitor de tela (ver BodyBars).

const RADIUS_CELLS := 24  # casas do centro até a borda do mapa
const SIZE := 170.0  # diâmetro do mapa na tela
const MARGIN := 16.0
const RING_COLOR := Color(0.85, 0.82, 0.72, 0.8)
const BACK_COLOR := Color(0.05, 0.06, 0.07, 0.65)
const NORTH_COLOR := Color("d0603a")
const LETTER_COLOR := Color("e8e2d0")
const LETTERS := ["N", "L", "S", "O"]  # norte, leste, sul, oeste
const SHADER := """
shader_type canvas_item;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float d = distance(UV, vec2(0.5));
	COLOR = vec4(pow(c.rgb, vec3(0.6)), c.a * step(d, 0.5));
}
"""

var _canvas: _Drawing
var _map_node: _MapNode
var _image: Image
var _texture: ImageTexture
var _colors := {}  # casa -> cor no mapa
var _color_of: Callable  # (casa) -> Color
var _cell := Vector2i(1 << 30, 1 << 30)


func setup(color_of: Callable) -> void:
	_color_of = color_of
	layer = 5
	var side := RADIUS_CELLS * 2 + 1
	_image = Image.create(side, side, false, Image.FORMAT_RGBA8)
	_texture = ImageTexture.create_from_image(_image)
	_canvas = _Drawing.new()
	_canvas.name = "Minimapa"
	var material := ShaderMaterial.new()
	material.shader = Shader.new()
	material.shader.code = SHADER
	_map_node = _MapNode.new()
	_map_node.name = "Mapa"
	_map_node.material = material
	_map_node.texture = _texture
	_map_node.owner_view = _canvas
	add_child(_map_node)
	add_child(_canvas)


## Chamado a cada quadro: onde a criatura está (em casas) e para onde olha
## (o giro da câmera, em radianos).
func update(pos: Vector2, yaw: float) -> void:
	if _canvas == null:
		return
	var cell := WorldGen.cell_of(pos)
	if cell != _cell:
		_cell = cell
		_rebuild()
	var size := get_viewport().get_visible_rect().size
	if not is_equal_approx(_canvas.yaw, yaw) or _canvas.last_size != size or _canvas.dirty:
		_canvas.yaw = yaw
		_canvas.dirty = false
		_canvas.queue_redraw()
		_map_node.queue_redraw()


func _rebuild() -> void:
	if _colors.size() > 8000:
		_colors.clear()
	var side := RADIUS_CELLS * 2 + 1
	for y in side:
		for x in side:
			var c := _cell + Vector2i(x - RADIUS_CELLS, y - RADIUS_CELLS)
			if not _colors.has(c):
				_colors[c] = _color_of.call(c)
			_image.set_pixel(x, y, _colors[c])
	_texture.update(_image)
	_canvas.dirty = true
	_map_node.queue_redraw()


class _Drawing:
	extends Node2D

	var yaw := 0.0
	var dirty := true
	var last_size := Vector2.ZERO

	func _draw() -> void:
		last_size = get_viewport().get_visible_rect().size
		var radius := SIZE * 0.5
		var center := Vector2(last_size.x - MARGIN - radius - 14.0, MARGIN + radius + 14.0)
		draw_circle(center, radius + 3.0, BACK_COLOR)
		draw_arc(center, radius + 1.0, 0.0, TAU, 64, RING_COLOR, 2.0, true)
		# As quatro direções dão a volta no anel.
		var font := ThemeDB.fallback_font
		for i in 4:
			var angle := i * PI * 0.5 + yaw  # sentido horário a partir de cima
			var at := center + Vector2(sin(angle), -cos(angle)) * (radius + 14.0)
			var color := NORTH_COLOR if i == 0 else LETTER_COLOR
			var extent := font.get_string_size(LETTERS[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
			draw_string(font, at + Vector2(-extent.x * 0.5, 7.0), LETTERS[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, color)
		# A criatura, sempre apontando para cima.
		draw_colored_polygon(PackedVector2Array([center + Vector2(0, -8), center + Vector2(6, 7), center + Vector2(0, 3), center + Vector2(-6, 7)]), Color("f2efe4"))


## O mapa em si, num nó com o material que o recorta em círculo (o material vale
## para o nó todo, por isso fica separado do anel e das letras).
class _MapNode:
	extends Node2D

	var texture: Texture2D
	var owner_view: _Drawing

	func _draw() -> void:
		var size := get_viewport().get_visible_rect().size
		var radius := SIZE * 0.5
		var center := Vector2(size.x - MARGIN - radius - 14.0, MARGIN + radius + 14.0)
		# O mapa, com o norte em cima, gira para a frente da criatura ficar para cima.
		draw_set_transform(center, owner_view.yaw, Vector2.ONE)
		draw_texture_rect(texture, Rect2(Vector2(-radius, -radius), Vector2(SIZE, SIZE)), false)
