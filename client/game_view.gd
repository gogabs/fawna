class_name GameView
extends Node2D
## Visual provisório, só para quem enxerga acompanhar e depurar.
## O jogo precisa ser totalmente jogável sem esta tela.

const TILE := 20

const BIOME_COLORS := {
	WorldGen.Biome.BOSQUE: Color("2f4a3a"),
	WorldGen.Biome.PRADARIA: Color("8a9a3c"),
}
const THING_COLORS := {
	WorldGen.Thing.ARVORE: Color("1d2e1f"),
	WorldGen.Thing.RIACHO: Color("3a7bd5"),
	WorldGen.Thing.ARBUSTO: Color("d98ad9"),
	WorldGen.Thing.VILA: Color("f6c453"),
}

var _world: WorldGen
var _players := {}
var _my_id := 0


func setup(world: WorldGen, players: Dictionary, my_id: int) -> void:
	_world = world
	_players = players
	_my_id = my_id
	queue_redraw()


func cell_to_pixel(cell: Vector2i) -> Vector2:
	return Vector2(cell) * TILE + Vector2.ONE * TILE * 0.5


func _draw() -> void:
	if _world == null:
		return
	for y in WorldGen.SIZE:
		for x in WorldGen.SIZE:
			var cell := Vector2i(x, y)
			var rect := Rect2(Vector2(cell) * TILE, Vector2.ONE * TILE)
			draw_rect(rect, BIOME_COLORS[_world.biome_at(cell)])
			var thing := _world.thing_at(cell)
			if THING_COLORS.has(thing):
				draw_rect(rect.grow(-4), THING_COLORS[thing])
	for id in _players:
		var color := Color.WHITE if id == _my_id else Color("ffb38a")
		draw_circle(cell_to_pixel(_players[id]["pos"]), TILE * 0.35, color)
