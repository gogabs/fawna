class_name Harvest
extends RefCounted
## Recursos coletáveis do mundo: o que cada coisa dá, quantos golpes pede e
## quanto tempo leva para voltar depois de colhida.
##
## Onde os recursos nascem vem da semente (WorldGen). O que muda com o jogo
## (golpes já dados num bambu, o que já foi colhido e quando volta) fica aqui,
## por casa. O servidor tem a cópia que vale; cada cliente guarda um espelho,
## atualizado pelo servidor, para saber o que soa, o que a fala anuncia e o que
## dá para coletar.
##
## Ciclo de cada fonte:
##   de pé -> (bambu: golpes com o machado até cair) -> pronta para recolher
##   -> recolhida (some: sem som, sem fala) -> rebrota depois de "regrow" s.

## coisa do mundo -> regras da fonte.
##   item: o que vai para a bolsa; amount: quanto dá de uma vez;
##   hits: golpes de machado até poder recolher (0: recolhe direto, com a mão);
##   extra_hits: até quantos golpes a mais uma fonte pode pedir (varia por lugar);
##   regrow: segundos até voltar depois de recolhida.
const SOURCES := {
	WorldGen.Thing.BAMBU: {"item": "bambu", "amount": 3, "hits": 3, "extra_hits": 2, "tool": "machado", "regrow": 900.0},
	WorldGen.Thing.GRAVETOS: {"item": "lenha", "amount": 2, "hits": 0, "regrow": 300.0},
	WorldGen.Thing.ARGILA: {"item": "argila", "amount": 1, "hits": 0, "regrow": 480.0},
	WorldGen.Thing.ARBUSTO_FRUTAS: {"item": "frutas", "amount": 2, "hits": 0, "regrow": 1800.0},
}

## Golpes dados num bambu que ninguém terminou de cortar se perdem depois
## deste tempo (a touceira "se recompõe").
const STRIKE_MEMORY := 180.0

var world: WorldGen
## Vector2i -> { "hits": golpes dados, "regrow_at": hora (Unix) em que volta;
## 0 enquanto não foi recolhida, "struck_at": hora do último golpe }
var _nodes := {}


func _init(new_world: WorldGen) -> void:
	world = new_world


static func is_source(thing: int) -> bool:
	return SOURCES.has(thing)


static func needs_tool(thing: int) -> bool:
	return SOURCES.has(thing) and int(SOURCES[thing]["hits"]) > 0


static func item_of(thing: int) -> String:
	return SOURCES[thing]["item"] if SOURCES.has(thing) else ""


static func now() -> float:
	return Time.get_unix_time_from_system()


## Golpes que esta fonte pede no total (o bambu de cada lugar é um pouco mais
## duro ou mais mole). 0 para o que se recolhe com a mão.
func hits_needed(cell: Vector2i) -> int:
	var source: Dictionary = SOURCES.get(world.thing_at(cell), {})
	if source.is_empty() or int(source["hits"]) <= 0:
		return 0
	var extra := int(source.get("extra_hits", 0))
	return int(source["hits"]) + mini(extra, floori(world.cell_random(cell, "dureza") * (extra + 1)))


## Golpes que ainda faltam para a fonte cair (0 se já caiu ou não precisa).
func hits_left(cell: Vector2i, at := -1.0) -> int:
	return maxi(0, hits_needed(cell) - _hits_done(cell, now() if at < 0.0 else at))


## A fonte está lá (não foi recolhida, ou já rebrotou)?
func is_available(cell: Vector2i, at := -1.0) -> bool:
	if not is_source(world.thing_at(cell)):
		return false
	var node: Dictionary = _nodes.get(cell, {})
	var regrow_at := float(node.get("regrow_at", 0.0))
	return regrow_at <= 0.0 or (now() if at < 0.0 else at) >= regrow_at


## Pronta para ir para a bolsa: está lá e não falta nenhum golpe.
func is_ready(cell: Vector2i, at := -1.0) -> bool:
	return is_available(cell, at) and hits_left(cell, at) == 0


## Um golpe de machado. Devolve { ok, reason, hits_left, felled }.
## reason: "nada" (não é algo que se corta), "colhido" (já foi recolhido),
## "caido" (já caiu, falta recolher).
func strike(cell: Vector2i, at := -1.0) -> Dictionary:
	if at < 0.0:
		at = now()
	var thing := world.thing_at(cell)
	if not needs_tool(thing):
		return {"ok": false, "reason": "nada", "hits_left": 0, "felled": false}
	if not is_available(cell, at):
		return {"ok": false, "reason": "colhido", "hits_left": 0, "felled": false}
	var left := hits_left(cell, at)
	if left == 0:
		return {"ok": false, "reason": "caido", "hits_left": 0, "felled": true}
	_nodes[cell] = {"hits": _hits_done(cell, at) + 1, "regrow_at": 0.0, "struck_at": at}
	left -= 1
	return {"ok": true, "reason": "", "hits_left": left, "felled": left == 0}


## Recolhe a fonte inteira. Devolve { ok, reason, item, amount, hits_left }.
## reason: "nada", "colhido" ou "golpear" (o bambu ainda está de pé).
func take(cell: Vector2i, at := -1.0) -> Dictionary:
	if at < 0.0:
		at = now()
	var thing := world.thing_at(cell)
	if not is_source(thing):
		return {"ok": false, "reason": "nada"}
	var source: Dictionary = SOURCES[thing]
	if not is_available(cell, at):
		return {"ok": false, "reason": "colhido", "item": source["item"]}
	var left := hits_left(cell, at)
	if left > 0:
		return {"ok": false, "reason": "golpear", "item": source["item"], "hits_left": left}
	_nodes[cell] = {"hits": 0, "regrow_at": at + float(source["regrow"]), "struck_at": 0.0}
	return {"ok": true, "reason": "", "item": source["item"], "amount": int(source["amount"])}


## Estado de uma casa para mandar pela rede: tempos relativos, porque o
## relógio de cada máquina é diferente.
func info(cell: Vector2i, at := -1.0) -> Dictionary:
	if at < 0.0:
		at = now()
	var node: Dictionary = _nodes.get(cell, {})
	return {
		"hits": _hits_done(cell, at),
		"regrow_in": maxf(0.0, float(node.get("regrow_at", 0.0)) - at) if float(node.get("regrow_at", 0.0)) > 0.0 else 0.0,
		"struck_ago": at - float(node["struck_at"]) if float(node.get("struck_at", 0.0)) > 0.0 else -1.0,
		"taken": not is_available(cell, at),
	}


## Cliente: aplica o que o servidor mandou sobre uma casa.
func apply_info(cell: Vector2i, data: Dictionary, at := -1.0) -> void:
	if at < 0.0:
		at = now()
	var node := {"hits": int(data.get("hits", 0)), "regrow_at": 0.0, "struck_at": 0.0}
	if bool(data.get("taken", false)):
		node["regrow_at"] = at + maxf(float(data.get("regrow_in", 0.0)), 0.001)
	if float(data.get("struck_ago", -1.0)) >= 0.0:
		node["struck_at"] = at - float(data["struck_ago"])
	if node["hits"] == 0 and node["regrow_at"] == 0.0:
		_nodes.erase(cell)
	else:
		_nodes[cell] = node


## Tudo o que difere do mundo intocado, para quem acabou de entrar.
func snapshot(at := -1.0) -> Dictionary:
	if at < 0.0:
		at = now()
	prune(at)
	var out := {}
	for cell in _nodes:
		out[cell] = info(cell, at)
	return out


func apply_snapshot(data: Dictionary, at := -1.0) -> void:
	_nodes.clear()
	for cell in data:
		apply_info(cell, data[cell], at)


## Esquece o que já rebrotou e os golpes velhos. Devolve as casas que voltaram
## ao normal.
func prune(at := -1.0) -> Array:
	if at < 0.0:
		at = now()
	var restored := []
	for cell in _nodes.keys():
		var node: Dictionary = _nodes[cell]
		var regrown := float(node["regrow_at"]) > 0.0 and at >= float(node["regrow_at"])
		var forgotten := float(node["regrow_at"]) <= 0.0 and _hits_done(cell, at) == 0
		if regrown or forgotten:
			_nodes.erase(cell)
			restored.append(cell)
	return restored


func to_save() -> Array:
	var out := []
	prune()
	for cell: Vector2i in _nodes:
		var node: Dictionary = _nodes[cell]
		out.append([cell.x, cell.y, node["hits"], node["regrow_at"], node["struck_at"]])
	return out


func load_save(data: Array) -> void:
	_nodes.clear()
	for entry in data:
		if typeof(entry) != TYPE_ARRAY or entry.size() < 5:
			continue
		_nodes[Vector2i(int(entry[0]), int(entry[1]))] = {
			"hits": int(entry[2]), "regrow_at": float(entry[3]), "struck_at": float(entry[4]),
		}
	prune()


func _hits_done(cell: Vector2i, at: float) -> int:
	var node: Dictionary = _nodes.get(cell, {})
	if node.is_empty() or float(node["regrow_at"]) > 0.0:
		return 0
	if at - float(node["struck_at"]) > STRIKE_MEMORY:
		return 0
	return int(node["hits"])
