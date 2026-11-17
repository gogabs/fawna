class_name Ground
extends RefCounted
## Itens soltos no chão: o que as criaturas largam da bolsa, ou o que não
## coube nela na hora de coletar.
##
## Cada casa do mundo guarda um monte (item -> quantidade). Um monte não
## bloqueia a passagem, não some com o tempo e pode ser recolhido por
## qualquer criatura. O servidor tem a cópia que vale e a salva no mundo.json
## ("ground"); cada cliente guarda um espelho, atualizado pelo servidor, para
## saber o que soa, o que a fala anuncia e o que dá para recolher.

## Vector2i -> { item: quantidade }
var _piles := {}


func add(cell: Vector2i, item: String, amount: int) -> void:
	if amount <= 0:
		return
	var pile: Dictionary = _piles.get(cell, {})
	pile[item] = int(pile.get(item, 0)) + amount
	_piles[cell] = pile


func add_items(cell: Vector2i, items: Dictionary) -> void:
	for item: String in items:
		add(cell, item, int(items[item]))


## Tira até "amount" de um item do monte. Devolve quanto saiu.
func remove(cell: Vector2i, item: String, amount: int) -> int:
	var pile: Dictionary = _piles.get(cell, {})
	var taken := clampi(amount, 0, int(pile.get(item, 0)))
	if taken <= 0:
		return 0
	pile[item] = int(pile[item]) - taken
	if int(pile[item]) <= 0:
		pile.erase(item)
	if pile.is_empty():
		_piles.erase(cell)
	return taken


## O monte de uma casa (cópia; vazio se não há nada).
func items_at(cell: Vector2i) -> Dictionary:
	return _piles.get(cell, {}).duplicate()


func has_pile(cell: Vector2i) -> bool:
	return _piles.has(cell)


## As casas que têm algum monte.
func cells() -> Array:
	return _piles.keys()


## A casa do monte mais próximo de "pos" (em linha reta), até "radius" casas.
## NO_CELL se não houver.
func nearest(pos: Vector2, radius: float) -> Vector2i:
	var best := WorldGen.NO_CELL
	var best_distance := radius * radius
	for cell: Vector2i in _piles:
		var distance := WorldGen.cell_center(cell).distance_squared_to(pos)
		if distance <= best_distance:
			best_distance = distance
			best = cell
	return best


## "2 pedras grandes e 1 bambu".
static func pile_text(items: Dictionary) -> String:
	return Crafting.materials_text(items)


# --- Rede e salvamento -----------------------------------------------------------

## Todos os montes, para quem acabou de entrar.
func snapshot() -> Dictionary:
	return _piles.duplicate(true)


func apply_snapshot(data: Dictionary) -> void:
	_piles.clear()
	for cell in data:
		if cell is Vector2i and typeof(data[cell]) == TYPE_DICTIONARY:
			apply_pile(cell, data[cell])


## Cliente: o servidor mandou como ficou o monte de uma casa (vazio: sumiu).
func apply_pile(cell: Vector2i, items: Dictionary) -> void:
	var pile := {}
	for item in items:
		if int(items[item]) > 0:
			pile[str(item)] = int(items[item])
	if pile.is_empty():
		_piles.erase(cell)
	else:
		_piles[cell] = pile


func to_save() -> Array:
	var out := []
	for cell: Vector2i in _piles:
		out.append([cell.x, cell.y, _piles[cell]])
	return out


func load_save(data: Array) -> void:
	_piles.clear()
	for entry in data:
		if typeof(entry) != TYPE_ARRAY or entry.size() < 3 or typeof(entry[2]) != TYPE_DICTIONARY:
			continue
		var cell := Vector2i(int(entry[0]), int(entry[1]))
		for item in entry[2]:
			# Itens que não existem mais no jogo ficam para trás.
			if Economy.is_item(str(item)) or Bag.NAMES.has(str(item)):
				add(cell, str(item), int(entry[2][item]))
