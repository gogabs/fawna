class_name WorldState
extends RefCounted
## Estado autoritativo do mundo compartilhado. Só existe no servidor.
## Os clientes enviam intenções (andar, interagir) e o servidor decide.

const DIRECTIONS := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

var world: WorldGen
## id do peer -> { "name": String, "pos": Vector2i }
var players := {}


func _init(world_seed: int) -> void:
	world = WorldGen.new(world_seed)


func add_player(id: int, player_name: String) -> Vector2i:
	var clean_name := player_name.strip_edges().left(24)
	if clean_name.is_empty():
		clean_name = "Criatura %d" % (players.size() + 1)
	var pos := _spawn_point()
	players[id] = {"name": clean_name, "pos": pos}
	return pos


func remove_player(id: int) -> void:
	players.erase(id)


## Tenta mover um jogador um passo. Devolve { ok, pos, thing }.
## "thing" é o que bloqueou (se não andou) ou o que há na nova célula.
func try_move(id: int, dir: Vector2i) -> Dictionary:
	if not players.has(id) or not DIRECTIONS.has(dir):
		return {"ok": false, "pos": Vector2i.ZERO, "thing": WorldGen.Thing.NADA}
	var from: Vector2i = players[id]["pos"]
	var to := from + dir
	if not world.is_passable(to):
		return {"ok": false, "pos": from, "thing": world.thing_at(to)}
	players[id]["pos"] = to
	return {"ok": true, "pos": to, "thing": world.thing_at(to)}


## Retrato dos jogadores para quem acabou de entrar.
func snapshot() -> Dictionary:
	return players.duplicate(true)


func _spawn_point() -> Vector2i:
	# Ao redor da vila, que é sempre livre. Criaturas podem dividir a célula.
	var center := WorldGen.center()
	var offsets := [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]
	return center + offsets[players.size() % offsets.size()]
