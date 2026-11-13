class_name WorldState
extends RefCounted
## Estado autoritativo do mundo compartilhado. Só existe no servidor.
## Os clientes enviam intenções (andar, coletar, contribuir) e o servidor decide.

const DIRECTIONS := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
const COLLECT_COOLDOWN_MS := 700
const MAX_STACK := 99

var world: WorldGen
## id do peer -> { "name": String, "pos": Vector2i }
var players := {}
## nome da criatura -> { item: quantidade }. Por nome, para sobreviver a reconexões.
var inventories := {}
## Horta comunitária: estágio atual, o que já foi entregue nele e quem ajudou.
var garden := {"stage": 0, "delivered": {}, "contributors": []}

var _last_collect := {}  # id -> Time.get_ticks_msec()


func _init(world_seed: int) -> void:
	world = WorldGen.new(world_seed)


func add_player(id: int, player_name: String) -> Vector2i:
	var clean_name := player_name.strip_edges().left(24)
	if clean_name.is_empty():
		clean_name = "Criatura %d" % (players.size() + 1)
	var pos := _spawn_point()
	players[id] = {"name": clean_name, "pos": pos}
	if not inventories.has(clean_name):
		inventories[clean_name] = {}
	return pos


func remove_player(id: int) -> void:
	players.erase(id)
	_last_collect.erase(id)


func inventory_of(id: int) -> Dictionary:
	if not players.has(id):
		return {}
	return inventories[players[id]["name"]]


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


## Coleta o recurso numa casa vizinha (ou na própria). Recursos não se esgotam:
## a natureza do Fawna se regenera. Devolve { ok, item, reason }.
func collect(id: int, cell: Vector2i) -> Dictionary:
	if not players.has(id):
		return {"ok": false, "reason": "desconhecido"}
	var pos: Vector2i = players[id]["pos"]
	var offset := cell - pos
	if absi(offset.x) + absi(offset.y) > 1:
		return {"ok": false, "reason": "longe"}
	var thing := world.thing_at(cell)
	if not Economy.COLLECT.has(thing):
		return {"ok": false, "reason": "nada"}
	var now := Time.get_ticks_msec()
	if now - int(_last_collect.get(id, -COLLECT_COOLDOWN_MS)) < COLLECT_COOLDOWN_MS:
		return {"ok": false, "reason": "devagar"}
	_last_collect[id] = now
	var item: String = Economy.COLLECT[thing]
	var inv := inventory_of(id)
	if int(inv.get(item, 0)) >= MAX_STACK:
		return {"ok": false, "reason": "cheio", "item": item}
	inv[item] = int(inv.get(item, 0)) + 1
	return {"ok": true, "item": item}


func can_craft(id: int, recipe_name: String) -> bool:
	if not Economy.RECIPES.has(recipe_name) or not players.has(id):
		return false
	var inv := inventory_of(id)
	var inputs: Dictionary = Economy.RECIPES[recipe_name]["inputs"]
	for item in inputs:
		if int(inv.get(item, 0)) < inputs[item]:
			return false
	return true


## Conclui uma receita. Se o minigame não deu certo, nada é gasto.
func craft(id: int, recipe_name: String, success: bool) -> Dictionary:
	if not can_craft(id, recipe_name):
		return {"ok": false, "reason": "faltam"}
	if not success:
		return {"ok": false, "reason": "tente"}
	var recipe: Dictionary = Economy.RECIPES[recipe_name]
	var inv := inventory_of(id)
	for item in recipe["inputs"]:
		inv[item] = int(inv[item]) - int(recipe["inputs"][item])
	var output: String = recipe["output"]
	inv[output] = int(inv.get(output, 0)) + 1
	return {"ok": true, "item": output}


## Entrega à horta tudo o que o estágio atual ainda precisa e o jogador tem.
## Devolve { given, completed_stage (-1 se não completou), stage }.
func contribute(id: int) -> Dictionary:
	var result := {"given": {}, "completed_stage": -1, "stage": garden["stage"]}
	if not players.has(id) or garden["stage"] >= Economy.GARDEN_STAGES.size():
		return result
	var inv := inventory_of(id)
	var missing := Economy.stage_missing(garden["stage"], garden["delivered"])
	for item in missing:
		var amount := mini(int(inv.get(item, 0)), int(missing[item]))
		if amount <= 0:
			continue
		inv[item] = int(inv[item]) - amount
		garden["delivered"][item] = int(garden["delivered"].get(item, 0)) + amount
		result["given"][item] = amount
	if result["given"].is_empty():
		return result
	var player_name: String = players[id]["name"]
	if not garden["contributors"].has(player_name):
		garden["contributors"].append(player_name)
	if Economy.stage_missing(garden["stage"], garden["delivered"]).is_empty():
		result["completed_stage"] = garden["stage"]
		garden["stage"] = int(garden["stage"]) + 1
		garden["delivered"] = {}
	result["stage"] = garden["stage"]
	return result


## Retrato dos jogadores para quem acabou de entrar.
func snapshot() -> Dictionary:
	return players.duplicate(true)


func to_save() -> Dictionary:
	return {
		"version": 1,
		"seed": world.world_seed,
		"inventories": inventories,
		"garden": garden,
	}


static func from_save(data: Dictionary) -> WorldState:
	var state := WorldState.new(int(data["seed"]))
	for player_name in data.get("inventories", {}):
		var inv := {}
		var saved: Dictionary = data["inventories"][player_name]
		for item in saved:
			inv[item] = int(saved[item])
		state.inventories[player_name] = inv
	var g: Dictionary = data.get("garden", {})
	state.garden["stage"] = int(g.get("stage", 0))
	for item in g.get("delivered", {}):
		state.garden["delivered"][item] = int(g["delivered"][item])
	for player_name in g.get("contributors", []):
		state.garden["contributors"].append(str(player_name))
	return state


func _spawn_point() -> Vector2i:
	# Ao redor da vila, que é sempre livre. Criaturas podem dividir a célula.
	var center := WorldGen.center()
	var offsets := [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]
	return center + offsets[players.size() % offsets.size()]
