class_name Resin
extends RefCounted
## Resina das árvores: com a faca nas mãos, alguns golpes (J) no tronco fazem
## a resina escorrer; depois de uns instantes ela seca no tronco e se recolhe
## com Espaço. Golpes demais machucam a árvore até ela secar de vez.
##
## Cada árvore guarda os golpes de faca que levou ("cuts"), que se curam sozinhos
## depois de CUT_MEMORY segundos sem golpes. No golpe número CUTS_FOR_RESIN a
## resina começa a escorrer (se a árvore já descansou da última vez) e leva
## FLOW_TIME segundos para secar; só então dá para recolher. Os golpes seguintes
## fazem o tronco ranger (a partir de WARN_AT) e o de número DEATH_AT seca a
## árvore para sempre (ela continua de pé: dá para derrubar com o machado, mas
## não dá mais resina, e a resina que escorria se perde). Depois de recolhida, a
## árvore descansa REST_TIME segundos; o primeiro golpe nesse tempo só avisa
## ("descanso"), e quem insiste em seguida a machuca.
##
## Só o servidor precisa disto: os clientes ficam sabendo pelo resultado do
## golpe e pelo que o Espaço diz sobre a árvore (status_text).

const CUTS_FOR_RESIN := 3
const WARN_AT := 4  # a partir deste golpe, o tronco range
const DEATH_AT := 6
const CUT_MEMORY := 120.0
const FLOW_TIME := 60.0
const REST_TIME := 900.0
const RESIN_YIELD := 2

var world: WorldGen
## Vector2i -> { "cuts": int, "last": hora do último golpe, "rest_until": hora
## em que volta a dar resina, "dead": bool, "pending": resina no tronco (ainda
## não recolhida), "flow_until": hora em que a resina termina de secar }
var _trees := {}


func _init(new_world: WorldGen) -> void:
	world = new_world


static func now() -> float:
	return Time.get_unix_time_from_system()


static func _fresh() -> Dictionary:
	return {"cuts": 0, "last": 0.0, "rest_until": 0.0, "dead": false, "pending": false, "flow_until": 0.0}


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


## Há resina no tronco (escorrendo ou já seca)?
func has_resin(cell: Vector2i) -> bool:
	return bool(_trees.get(cell, {}).get("pending", false))


## Um golpe de faca na árvore desta casa. Devolve { ok, event, cuts }.
## event: "corte" (um golpe comum), "escorre" (a resina começou a escorrer, ou
## já escorria), "descanso" (a árvore ainda descansa: sem resina), "range" (o
## tronco range: pare), "secou" (este golpe secou a árvore), "seca" (já estava
## seca), "nada" (não é uma árvore).
func tap(cell: Vector2i, at := -1.0) -> Dictionary:
	if at < 0.0:
		at = now()
	if world.thing_at(cell) != WorldGen.Thing.ARVORE:
		return {"ok": false, "event": "nada", "cuts": 0}
	if is_dead(cell):
		return {"ok": false, "event": "seca", "cuts": 0}
	var node: Dictionary = _trees.get(cell, _fresh())
	# Primeiro golpe numa árvore que ainda descansa: só avisa, sem machucar.
	# Quem insiste (golpes seguidos) passa a machucá-la.
	if at < float(node["rest_until"]) and cuts(cell, at) == 0 and at - float(node.get("warned", -1.0e9)) > CUT_MEMORY:
		node["warned"] = at
		_trees[cell] = node
		return {"ok": true, "event": "descanso", "cuts": 0}
	var count := cuts(cell, at) + 1
	node["cuts"] = count
	node["last"] = at
	_trees[cell] = node
	if count >= DEATH_AT:
		node["dead"] = true
		node["pending"] = false
		return {"ok": true, "event": "secou", "cuts": count}
	if count == CUTS_FOR_RESIN:
		if bool(node["pending"]):
			return {"ok": true, "event": "escorre", "cuts": count}
		if at < float(node["rest_until"]):
			return {"ok": true, "event": "descanso", "cuts": count}
		node["pending"] = true
		node["flow_until"] = at + FLOW_TIME
		return {"ok": true, "event": "escorre", "cuts": count}
	if count >= WARN_AT:
		return {"ok": true, "event": "range", "cuts": count}
	return {"ok": true, "event": "corte", "cuts": count}


## Espaço na árvore: recolhe a resina seca. Devolve { ok, yield } quando
## recolheu; senão { ok: false, text } com o que dizer sobre a árvore.
func collect(cell: Vector2i, at := -1.0) -> Dictionary:
	if at < 0.0:
		at = now()
	var node: Dictionary = _trees.get(cell, {})
	if not node.is_empty() and bool(node["pending"]) and at >= float(node["flow_until"]) and not bool(node["dead"]):
		node["pending"] = false
		node["rest_until"] = at + REST_TIME
		return {"ok": true, "yield": {"resina": RESIN_YIELD}}
	return {"ok": false, "text": status_text(cell, at)}


## Desfaz um collect (a bolsa estava cheia): a resina volta para o tronco.
func undo_collect(cell: Vector2i) -> void:
	if _trees.has(cell):
		_trees[cell]["pending"] = true
		_trees[cell]["rest_until"] = 0.0


## O que o Espaço diz de uma árvore de pé.
func status_text(cell: Vector2i, at := -1.0) -> String:
	if at < 0.0:
		at = now()
	var node: Dictionary = _trees.get(cell, {})
	if not node.is_empty() and bool(node["dead"]):
		return "Árvore seca. Não dá mais resina; ainda dá para derrubar com o machado."
	if not node.is_empty() and bool(node["pending"]):
		var left := ceili(float(node["flow_until"]) - at)
		return "A resina ainda escorre. Falta uns %d segundo%s para secar e dar para recolher." % [left, "" if left == 1 else "s"]
	var count := cuts(cell, at)
	var rest := 0.0 if node.is_empty() else float(node["rest_until"]) - at
	var parts: PackedStringArray = []
	if count > 0:
		parts.append("Árvore com %d corte%s." % [count, "" if count == 1 else "s"])
		if count >= WARN_AT - 1:
			parts.append("O tronco range: mais golpes a secam.")
		elif rest <= 0.0:
			parts.append("Faltam %d golpe%s de faca para a resina escorrer." % [CUTS_FOR_RESIN - count, "" if CUTS_FOR_RESIN - count == 1 else "s"])
	else:
		parts.append("Árvore de pé, sem cortes.")
	if rest > 0.0:
		var minutes := ceili(rest / 60.0)
		parts.append("Ela descansa da última resina: volta em uns %d minuto%s." % [minutes, "" if minutes == 1 else "s"])
	elif count == 0:
		parts.append("Com a faca, J tira resina; com o machado, derruba.")
	return " ".join(parts)


## Esquece o que já se curou (golpes velhos e descansos acabados).
func prune(at := -1.0) -> void:
	if at < 0.0:
		at = now()
	for cell in _trees.keys():
		var node: Dictionary = _trees[cell]
		if bool(node["dead"]) or bool(node["pending"]):
			continue
		if at - float(node["last"]) > CUT_MEMORY and at >= float(node["rest_until"]):
			_trees.erase(cell)


func to_save() -> Array:
	prune()
	var out := []
	for cell: Vector2i in _trees:
		var node: Dictionary = _trees[cell]
		out.append([cell.x, cell.y, node["cuts"], node["last"], node["rest_until"], node["dead"], node["pending"], node["flow_until"]])
	return out


func load_save(data: Array) -> void:
	_trees.clear()
	for entry in data:
		if typeof(entry) != TYPE_ARRAY or entry.size() < 6:
			continue
		var node := _fresh()
		node["cuts"] = int(entry[2])
		node["last"] = float(entry[3])
		node["rest_until"] = float(entry[4])
		node["dead"] = bool(entry[5])
		if entry.size() >= 8:
			node["pending"] = bool(entry[6])
			node["flow_until"] = float(entry[7])
		_trees[Vector2i(int(entry[0]), int(entry[1]))] = node
