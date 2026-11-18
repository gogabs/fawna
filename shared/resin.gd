class_name Resin
extends RefCounted
## Resina das árvores: com a faca nas mãos, alguns golpes (J) no tronco fazem
## a resina escorrer. Golpes demais machucam a árvore até ela secar de vez.
##
## Cada árvore guarda os golpes de faca que levou ("cuts"), que se curam sozinhos
## depois de CUT_MEMORY segundos sem golpes. No golpe número CUTS_FOR_RESIN a
## resina escorre (se a árvore já descansou da última vez); os golpes seguintes
## fazem o tronco ranger (a partir de WARN_AT) e o de número DEATH_AT seca a
## árvore para sempre (ela continua de pé: dá para derrubar com o machado, mas
## não dá mais resina). Depois de dar resina, a árvore descansa REST_TIME
## segundos; o primeiro golpe nesse tempo só avisa ("descanso"), e quem insiste
## em seguida a machuca.
##
## Só o servidor precisa disto: os clientes ficam sabendo pelo resultado do
## golpe, mandado a quem golpeou e, como som, a quem está por perto.

const CUTS_FOR_RESIN := 3
const WARN_AT := 4  # a partir deste golpe, o tronco range
const DEATH_AT := 6
const CUT_MEMORY := 120.0
const REST_TIME := 900.0
const RESIN_YIELD := 2


var world: WorldGen
## Vector2i -> { "cuts": int, "last": hora do último golpe, "rest_until": hora
## em que volta a dar resina, "dead": bool }
var _trees := {}


func _init(new_world: WorldGen) -> void:
	world = new_world


static func now() -> float:
	return Time.get_unix_time_from_system()


func is_dead(cell: Vector2i) -> bool:
	return bool(_trees.get(cell, {}).get("dead", false))


## Golpes que a árvore ainda lembra (0 se já se curou).
func cuts(cell: Vector2i, at := -1.0) -> int:
	var node: Dictionary = _trees.get(cell, {})
	if node.is_empty() or bool(node["dead"]):
		return 0
	if (now() if at < 0.0 else at) - float(node["last"]) > CUT_MEMORY:
		return 0
	return int(node["cuts"])


## Um golpe de faca na árvore desta casa. Devolve { ok, event, cuts, yield }.
## event: "corte" (um golpe comum), "resina" (escorreu: "yield" diz quanto),
## "descanso" (era para escorrer, mas a árvore ainda descansa), "range" (o tronco
## range: pare), "secou" (este golpe secou a árvore), "seca" (já estava seca),
## "nada" (não é uma árvore).
func tap(cell: Vector2i, at := -1.0) -> Dictionary:
	if at < 0.0:
		at = now()
	if world.thing_at(cell) != WorldGen.Thing.ARVORE:
		return {"ok": false, "event": "nada", "cuts": 0, "yield": {}}
	if is_dead(cell):
		return {"ok": false, "event": "seca", "cuts": 0, "yield": {}}
	var node: Dictionary = _trees.get(cell, {"cuts": 0, "last": 0.0, "rest_until": 0.0, "dead": false})
	# Primeiro golpe numa árvore que ainda descansa: só avisa, sem machucar.
	# Quem insiste (golpes seguidos) passa a machucá-la.
	if at < float(node["rest_until"]) and cuts(cell, at) == 0 and at - float(node.get("warned", -1.0e9)) > CUT_MEMORY:
		node["warned"] = at
		_trees[cell] = node
		return {"ok": true, "event": "descanso", "cuts": 0, "yield": {}}
	var count := cuts(cell, at) + 1
	node["cuts"] = count
	node["last"] = at
	_trees[cell] = node
	if count >= DEATH_AT:
		node["dead"] = true
		return {"ok": true, "event": "secou", "cuts": count, "yield": {}}
	if count == CUTS_FOR_RESIN:
		if at < float(node["rest_until"]):
			return {"ok": true, "event": "descanso", "cuts": count, "yield": {}}
		node["rest_until"] = at + REST_TIME
		return {"ok": true, "event": "resina", "cuts": count, "yield": {"resina": RESIN_YIELD}}
	if count >= WARN_AT:
		return {"ok": true, "event": "range", "cuts": count, "yield": {}}
	return {"ok": true, "event": "corte", "cuts": count, "yield": {}}


## Esquece o que já se curou (golpes velhos e descansos acabados).
func prune(at := -1.0) -> void:
	if at < 0.0:
		at = now()
	for cell in _trees.keys():
		var node: Dictionary = _trees[cell]
		if bool(node["dead"]):
			continue
		if at - float(node["last"]) > CUT_MEMORY and at >= float(node["rest_until"]):
			_trees.erase(cell)


func to_save() -> Array:
	prune()
	var out := []
	for cell: Vector2i in _trees:
		var node: Dictionary = _trees[cell]
		out.append([cell.x, cell.y, node["cuts"], node["last"], node["rest_until"], node["dead"]])
	return out


func load_save(data: Array) -> void:
	_trees.clear()
	for entry in data:
		if typeof(entry) != TYPE_ARRAY or entry.size() < 6:
			continue
		_trees[Vector2i(int(entry[0]), int(entry[1]))] = {
			"cuts": int(entry[2]), "last": float(entry[3]),
			"rest_until": float(entry[4]), "dead": bool(entry[5]),
		}
