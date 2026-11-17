class_name WorldState
extends RefCounted
## Estado autoritativo do mundo compartilhado. Só existe no servidor.
## Os clientes enviam intenções (andar, coletar) e o servidor decide.

const COLLECT_COOLDOWN_MS := 700
const STRIKE_COOLDOWN_MS := 350  # golpes de machado mais rápidos que isso não contam
## Movimento contínuo: o cliente anda sozinho e manda a posição; o servidor
## confere a velocidade e as colisões. Valores em casas.
const MAX_SPEED := 2.2  # casas por segundo (a criatura anda a 1,5)
const MOVE_SLACK := 0.4  # folga para atrasos da rede
const REACH := 1.6  # até onde dá para coletar ou golpear (do centro da criatura ao centro da casa)
const ORIGIN_REACH := 1.2
const MAX_STACK := 99
const BUILD_COOLDOWN_MS := 300  # batidas numa obra mais rápidas que isso não contam
const BUILD_REACH := 1.9  # a obra ocupa a casa toda: dá para trabalhar de um pouco mais longe

var world: WorldGen
## Recursos coletáveis: golpes dados, o que foi colhido e quando volta.
var harvest: Harvest
## Construções (marcos, fogueiras). Ver Builds e Crafting.
var builds: Builds
## id do peer -> { "name": String, "pos": Vector2, "heading": int }
var players := {}
## nome da criatura -> { item: quantidade }. Por nome, para sobreviver a reconexões.
var inventories := {}
## nome da criatura -> item empunhado ("" = mãos livres). Ver Bag.
var equipment := {}

var _last_collect := {}  # id -> Time.get_ticks_msec()
var _last_move := {}  # id -> Time.get_ticks_msec()
var _last_strike := {}  # id -> Time.get_ticks_msec()
var _last_build := {}  # id -> Time.get_ticks_msec()


func _init(world_seed: int) -> void:
	world = WorldGen.new(world_seed)
	harvest = Harvest.new(world)
	builds = Builds.new(world)


func add_player(id: int, player_name: String) -> Vector2:
	var clean_name := player_name.strip_edges().left(24)
	if clean_name.is_empty():
		clean_name = "Criatura %d" % (players.size() + 1)
	var pos := _spawn_point()
	players[id] = {"name": clean_name, "pos": pos, "heading": 0}
	if not inventories.has(clean_name):
		inventories[clean_name] = {}
	if not equipment.has(clean_name):
		equipment[clean_name] = ""
	Bag.give_starter(inventories[clean_name], equipment[clean_name])
	return pos


func remove_player(id: int) -> void:
	players.erase(id)
	_last_collect.erase(id)
	_last_move.erase(id)
	_last_strike.erase(id)
	_last_build.erase(id)


## Para onde o jogador olha (0 norte, 1 nordeste...; ver Compass).
func set_heading(id: int, heading: int) -> void:
	if players.has(id):
		players[id]["heading"] = posmod(heading, Compass.STEPS)


func inventory_of(id: int) -> Dictionary:
	if not players.has(id):
		return {}
	return inventories[players[id]["name"]]


## O que o jogador tem nas mãos ("" = mãos livres).
func wielding(id: int) -> String:
	if not players.has(id):
		return ""
	return equipment.get(players[id]["name"], "")


## Tira um item da bolsa e o põe nas mãos. Se já havia outro nas mãos, ele
## volta para a bolsa. Devolve { ok, reason, item, stowed }.
func equip(id: int, item: String) -> Dictionary:
	if not players.has(id):
		return {"ok": false, "reason": "desconhecido"}
	if not Bag.can_wield(item):
		return {"ok": false, "reason": "nao_empunha", "item": item}
	var player_name: String = players[id]["name"]
	var inv := inventory_of(id)
	if int(inv.get(item, 0)) <= 0:
		return {"ok": false, "reason": "nao_tem", "item": item}
	var stowed: String = equipment.get(player_name, "")
	if not stowed.is_empty():
		inv[stowed] = int(inv.get(stowed, 0)) + 1
	inv[item] = int(inv[item]) - 1
	if int(inv[item]) <= 0:
		inv.erase(item)
	equipment[player_name] = item
	return {"ok": true, "item": item, "stowed": stowed}


## Guarda na bolsa o que estiver nas mãos. Devolve { ok, reason, item }.
func stow(id: int) -> Dictionary:
	var item := wielding(id)
	if item.is_empty():
		return {"ok": false, "reason": "maos_livres"}
	var inv := inventory_of(id)
	inv[item] = int(inv.get(item, 0)) + 1
	equipment[players[id]["name"]] = ""
	return {"ok": true, "item": item}


## Aceita a nova posição de um jogador se ela é possível: perto o bastante
## da anterior (pela velocidade máxima) e sem atravessar nada. Devolve
## { ok, pos }; se recusar, "pos" é onde o servidor acha que ele está.
func move_to(id: int, pos: Vector2, now_ms := -1) -> Dictionary:
	if not players.has(id):
		return {"ok": false, "pos": Vector2.ZERO}
	var from: Vector2 = players[id]["pos"]
	if now_ms < 0:
		now_ms = Time.get_ticks_msec()
	var seconds := clampf((now_ms - int(_last_move.get(id, now_ms - 1000))) / 1000.0, 0.0, 1.0)
	var allowed := MAX_SPEED * seconds + MOVE_SLACK
	if not pos.is_finite() or from.distance_to(pos) > allowed or not world.is_free(pos):
		return {"ok": false, "pos": from}
	_last_move[id] = now_ms
	players[id]["pos"] = pos
	return {"ok": true, "pos": pos}


## Recolhe o recurso de uma casa ao alcance (gravetos ou frutas de um arbusto,
## argila, pedras, ou um bambu já derrubado). Lenha e pedra entram na bolsa
## por tamanho (Harvest.take devolve "parts"). A fonte se esgota e rebrota com o tempo
## (Harvest).
## Devolve { ok, item, amount, reason, hits_left }. reason: "longe", "nada",
## "devagar", "colhido" (já recolhido, ainda não voltou), "golpear" (bambu de
## pé: falta cortar com o machado) ou "cheio".
func collect(id: int, cell: Vector2i) -> Dictionary:
	if not players.has(id):
		return {"ok": false, "reason": "desconhecido"}
	var pos: Vector2 = players[id]["pos"]
	if pos.distance_to(WorldGen.cell_center(cell)) > REACH:
		return {"ok": false, "reason": "longe"}
	var thing := world.thing_at(cell)
	if not Harvest.is_source(thing):
		return {"ok": false, "reason": "nada"}
	var now := Time.get_ticks_msec()
	if now - int(_last_collect.get(id, -COLLECT_COOLDOWN_MS)) < COLLECT_COOLDOWN_MS:
		return {"ok": false, "reason": "devagar"}
	_last_collect[id] = now
	var item := Harvest.item_of(thing)
	var inv := inventory_of(id)
	if Bag.count(inv, item) >= MAX_STACK:
		return {"ok": false, "reason": "cheio", "item": item}
	var result := harvest.take(cell)
	if not result["ok"]:
		return result
	var parts: Dictionary = result.get("parts", {})
	if parts.is_empty():
		inv[item] = mini(MAX_STACK, int(inv.get(item, 0)) + int(result["amount"]))
	else:
		for part: String in parts:
			inv[part] = mini(MAX_STACK, int(inv.get(part, 0)) + int(parts[part]))
	return result


## Um golpe de machado numa touceira de bambu ao alcance. Não confere a
## ferramenta: quem chama (request_strike) confere se o machado está
## empunhado. Devolve { ok, reason, hits_left, felled }; felled diz que este
## golpe derrubou o bambu, que agora pode ser recolhido.
func strike(id: int, cell: Vector2i) -> Dictionary:
	if not players.has(id):
		return {"ok": false, "reason": "desconhecido"}
	var pos: Vector2 = players[id]["pos"]
	if pos.distance_to(WorldGen.cell_center(cell)) > REACH:
		return {"ok": false, "reason": "longe"}
	var now := Time.get_ticks_msec()
	if now - int(_last_strike.get(id, -STRIKE_COOLDOWN_MS)) < STRIKE_COOLDOWN_MS:
		return {"ok": false, "reason": "devagar"}
	_last_strike[id] = now
	return harvest.strike(cell)


## Começa uma construção na casa "cell" (a que está à frente da criatura,
## escolhida pelo cliente; o servidor confere se está ao alcance, livre e
## sem ninguém em cima). Devolve { ok, reason, id }.
func start_build(id: int, kind: String, cell: Vector2i, build_name := "") -> Dictionary:
	if not players.has(id):
		return {"ok": false, "reason": "desconhecido"}
	var pos: Vector2 = players[id]["pos"]
	if pos.distance_to(WorldGen.cell_center(cell)) > BUILD_REACH:
		return {"ok": false, "reason": "longe"}
	for other_id in players:
		var other: Vector2 = players[other_id]["pos"]
		if WorldGen.cell_of(other) == cell or other.distance_to(WorldGen.cell_center(cell)) < 0.5 + WorldGen.PLAYER_RADIUS:
			return {"ok": false, "reason": "ocupado"}
	return builds.start(kind, cell, build_name)


## Um Espaço numa construção ao alcance: deposita materiais, bate, acende
## ou alimenta o fogo (Builds.work). Devolve o resultado de Builds.work.
func work_build(id: int, build_id: int) -> Dictionary:
	if not players.has(id):
		return {"ok": false, "reason": "desconhecido"}
	var build := builds.get_build(build_id)
	if build.is_empty():
		return {"ok": false, "reason": "desconhecida"}
	var pos: Vector2 = players[id]["pos"]
	if pos.distance_to(WorldGen.cell_center(build["cell"])) > BUILD_REACH:
		return {"ok": false, "reason": "longe"}
	var now := Time.get_ticks_msec()
	if now - int(_last_build.get(id, -BUILD_COOLDOWN_MS)) < BUILD_COOLDOWN_MS:
		return {"ok": false, "reason": "devagar"}
	_last_build[id] = now
	return builds.work(build_id, inventory_of(id))


## Fabrica uma arma com o que está na bolsa. Devolve { ok, reason, item,
## missing }.
func craft(id: int, weapon: String) -> Dictionary:
	if not players.has(id):
		return {"ok": false, "reason": "desconhecido"}
	if not Crafting.WEAPONS.has(weapon):
		return {"ok": false, "reason": "desconhecida"}
	var inv := inventory_of(id)
	var materials: Dictionary = Crafting.WEAPONS[weapon]["materials"]
	var missing := Crafting.missing(inv, materials)
	if not missing.is_empty():
		return {"ok": false, "reason": "faltam", "item": weapon, "missing": missing}
	if int(inv.get(weapon, 0)) >= MAX_STACK:
		return {"ok": false, "reason": "cheio", "item": weapon}
	for item: String in materials:
		inv[item] = int(inv[item]) - int(materials[item])
		if int(inv[item]) <= 0:
			inv.erase(item)
	inv[weapon] = int(inv.get(weapon, 0)) + 1
	return {"ok": true, "item": weapon}


## Retrato dos jogadores para quem acabou de entrar.
func snapshot() -> Dictionary:
	return players.duplicate(true)


func to_save() -> Dictionary:
	return {
		"version": 1,
		"seed": world.world_seed,
		"inventories": inventories,
		"equipment": equipment,
		"harvest": harvest.to_save(),
		"builds": builds.to_save(),
	}


static func from_save(data: Dictionary) -> WorldState:
	var state := WorldState.new(int(data["seed"]))
	for player_name in data.get("inventories", {}):
		var inv := {}
		var saved: Dictionary = data["inventories"][player_name]
		for item: String in saved:
			var key := item
			# Lenha de antes dos tamanhos vira lenha média.
			if Economy.has_sizes(item):
				key = Economy.sized(item, "media")
			# Itens que não existem mais no jogo ficam para trás.
			if Economy.is_item(key) or Bag.NAMES.has(key):
				inv[key] = int(inv.get(key, 0)) + int(saved[item])
		state.inventories[player_name] = inv
	for player_name in data.get("equipment", {}):
		state.equipment[player_name] = str(data["equipment"][player_name])
	var harvested = data.get("harvest", [])
	if typeof(harvested) == TYPE_ARRAY:
		state.harvest.load_save(harvested)
	var built = data.get("builds", {})
	if typeof(built) == TYPE_DICTIONARY:
		state.builds.load_save(built)
	return state


func _spawn_point() -> Vector2:
	# Ao redor da Origem, que é sempre livre, começando ao sul dela: quem entra
	# olhando para o norte já tem a Origem à frente.
	var offsets := [Vector2(0, 1.5), Vector2(1.5, 0), Vector2(-1.5, 0), Vector2(0, -1.5)]
	return WorldGen.origin_point() + offsets[players.size() % offsets.size()]
