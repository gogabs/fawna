class_name GameView
extends Node2D
## Visual provisório, só para quem enxerga acompanhar e depurar.
## O jogo precisa ser totalmente jogável sem esta tela.

const TILE := 20

const VIEW_CELLS := Vector2i(48, 32)  # quantas casas cabem na tela, em volta da criatura

const BIOME_COLORS := {
	WorldGen.Biome.BOSQUE: Color("2f4a3a"),
	WorldGen.Biome.PRADARIA: Color("8a9a3c"),
	WorldGen.Biome.LAGOA: Color("4f7f6a"),
}
const THING_COLORS := {
	WorldGen.Thing.ARVORE: Color("1d2e1f"),
	WorldGen.Thing.RIACHO: Color("3a7bd5"),
	WorldGen.Thing.LAGO: Color("2f65b5"),
	WorldGen.Thing.TRILHA: Color("a07a4f"),
	WorldGen.Thing.PONTE: Color("7a5230"),
	WorldGen.Thing.ARBUSTO: Color("d98ad9"),
	WorldGen.Thing.VILA: Color("f6c453"),
}

var _world: WorldGen
var _players := {}
var _my_id := 0
var heading := 0  # para onde a criatura local olha
var caminheiro: Caminheiro  # a rota acesa aparece em azul


func setup(world: WorldGen, players: Dictionary, my_id: int) -> void:
	_world = world
	_players = players
	_my_id = my_id
	queue_redraw()


## O mundo não tem bordas: a tela mostra só o entorno da criatura local.
func _origin() -> Vector2:
	var me: Vector2 = _players[_my_id]["pos"] if _players.has(_my_id) else WorldGen.village_point()
	return me - Vector2(VIEW_CELLS) * 0.5


func point_to_pixel(point: Vector2) -> Vector2:
	return (point - _origin()) * TILE


func _draw() -> void:
	if _world == null:
		return
	var first := WorldGen.cell_of(_origin())
	for y in range(first.y, first.y + VIEW_CELLS.y + 2):
		for x in range(first.x, first.x + VIEW_CELLS.x + 2):
			var cell := Vector2i(x, y)
			var rect := Rect2(point_to_pixel(Vector2(cell)), Vector2.ONE * TILE)
			draw_rect(rect, BIOME_COLORS[_world.biome_at(cell)])
			var thing := _world.thing_at(cell)
			if THING_COLORS.has(thing):
				draw_rect(rect.grow(-4), THING_COLORS[thing])
	if caminheiro != null and caminheiro.active and _players.has(_my_id):
		var previous: Vector2 = _players[_my_id]["pos"]
		for point in caminheiro.route():
			draw_line(point_to_pixel(previous), point_to_pixel(point), Color(0.35, 0.65, 1.0, 0.7), 2.0)
			draw_circle(point_to_pixel(point), 3.0, Color("6fb3ff"))
			previous = point
	for id in _players:
		var color := Color.WHITE if id == _my_id else Color("ffb38a")
		var center := point_to_pixel(_players[id]["pos"])
		draw_circle(center, TILE * WorldGen.PLAYER_RADIUS, color)
		if id == _my_id:
			draw_line(center, center + Compass.forward(heading) * TILE * 0.7, Color("e8792b"), 3.0)
