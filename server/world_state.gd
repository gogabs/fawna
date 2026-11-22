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
const MAX_STACK := 99  # só para armas fabricadas; a bolsa se limita pela carga (Bag.CAPACITY)
const DROP_COOLDOWN_MS := 250  # largar e pegar do chão mais rápido que isso não conta
const BUILD_COOLDOWN_MS := 300  # batidas numa obra mais rápidas que isso não contam
const TORCH_SECONDS := 900.0  # quanto uma tocha acesa queima
const STRIKE_MIN := 5  # batidas para acender sem fogueira: de 5 a 9, sorteado
const STRIKE_MAX := 9
const STRIKE_GAP := 1.0  # um segundo sem riscar cancela
const STRIKE_FIRST_GRACE := 3.0  # tempo para a primeira batida (dá para ouvir a fala)
const STRIKE_MIN_INTERVAL := 0.12  # batidas coladas demais não contam
const BUILD_REACH := 1.9  # a obra ocupa a casa toda: dá para trabalhar de um pouco mais longe

var world: WorldGen
## Recursos coletáveis: golpes dados, o que foi colhido e quando volta.
var harvest: Harvest
## Resina das árvores: golpes de faca e árvores secas. Ver Resin.
var resin: Resin
## Construções (marcos, fogueiras). Ver Builds e Crafting.
var builds: Builds
## Itens soltos no chão. Ver Ground.
var ground: Ground
## id do peer -> { "name": String, "pos": Vector2, "heading": int }
var players := {}
## nome da criatura -> última posição (Vector2) em que esteve; é onde ela nasce ao voltar.
var last_pos := {}
## nome da criatura -> { item: quantidade }. Por nome, para sobreviver a reconexões.
var inventories := {}
## nome da criatura -> item empunhado ("" = mãos livres). Ver Bag.
var equipment := {}
## nome do personagem -> id da espécie (ver Species); vazio até escolher.
var species := {}
## nome da criatura -> { "food", "warmth" }: fome e calor, de 0 a 100 (ver Body).
var body := {}
## nome da criatura -> { comida: [[quantidade, dias que faltam], ...] }: os
## lotes de cada comida na bolsa, para o estrago (ver Body.reconcile).
var lots := {}
## casa da árvore -> ano (DayCycle) em que as castanhas dela foram catadas.
var nuts := {}
## Cavalos domesticados (Herd.tame_to_save): quem os simula é o nó Horses; o
## jogo copia para cá antes de salvar.
var tame_horses := []
## casa -> ms da última raiz cavada ali com a enxada.
var _rooted := {}  # casa da rama -> golpes de enxada já dados nela
var _food_rng := RandomNumberGenerator.new()
## id -> segundos seguidos com alguma reserva em zero (para desfalecer; não se salva).
var faint_clock := {}
## id -> segundos que ainda faltam para secar depois de cruzar um vau.
var wet_left := {}
## nome da criatura -> item na mão não dominante ("" = livre). Ver Bag.OFFHAND.
var offhand := {}
## nome da criatura -> hora (Unix) em que a tocha acesa na mão se apaga (0 = apagada).
var torch_until := {}
## id -> { method, needed, count, last_ms, first }: quem está riscando a tocha.
var striking := {}
## A hora do mundo (fração do dia, 0 = meia-noite; ver DayCycle). Quem anda com o
## relógio é o nó Daytime, no servidor; aqui ela só fica guardada e salva.
var day_t := DayCycle.hour_to_t(DayCycle.START_HOUR)
## Quantos dias inteiros já passaram (conta as estações e a posição do anel).
var day_n := DayCycle.START_DAY
var _strike_rng := RandomNumberGenerator.new()

var _last_collect := {}  # id -> Time.get_ticks_msec()
var _last_move := {}  # id -> Time.get_ticks_msec()
## Quem está montado (id -> true), mantido pelo nó dos cavalos.
var riding := {}
const RIDE_MAX_SPEED := 4.4  # casas por segundo: o galope montado (game.gd RIDE_GALLOP)
## Habilidades ativas (tecla H; ver Abilities).
var _ability_ready := {}  # id -> ms em que dá para usar de novo
var dashing := {}  # id -> { "until": ms, "tired_until": ms } (disparada)
var channels := {}  # id -> { "tag", "until": ms, "pos": Vector2, "cell": Vector2i, "build": int }
var _dug := {}  # casa -> ms do último fuçar (não rende de novo logo)
var _ability_rng := RandomNumberGenerator.new()
var _last_strike := {}  # id -> Time.get_ticks_msec()
var _last_build := {}  # id -> Time.get_ticks_msec()
var _last_drop := {}  # id -> Time.get_ticks_msec()


func _init(world_seed: int) -> void:
	world = WorldGen.new(world_seed)
	_ability_rng.seed = world_seed + 7211
	harvest = Harvest.new(world)
	resin = Resin.new(world)
	builds = Builds.new(world)
	ground = Ground.new()


## Senhas dos personagens (ver Credentials).
var credentials := Credentials.new()


## Confere a senha de quem quer entrar. "" = pode entrar; senão o motivo:
## "curta", "errada", "devagar" (ver Credentials.check) ou "ja_conectado"
## (o personagem já está no mundo). Na primeira vez de um nome, a senha fica
## registrada; "criada" também deixa entrar (vem em created).
func login(player_name: String, password: String) -> Dictionary:
	var clean_name := player_name.strip_edges().left(24)
	if clean_name.is_empty():
		return {"ok": false, "reason": "sem_nome"}
	for id in players:
		if players[id]["name"] == clean_name:
			return {"ok": false, "reason": "ja_conectado"}
	var result := credentials.check(clean_name, password)
	if result == "ok" or result == "criada":
		return {"ok": true, "created": result == "criada"}
	return {"ok": false, "reason": result}


func add_player(id: int, player_name: String) -> Vector2:
	var clean_name := player_name.strip_edges().left(24)
	if clean_name.is_empty():
		clean_name = "Criatura %d" % (players.size() + 1)
	var pos := _spawn_point()
	if last_pos.has(clean_name):
		# Volta para onde saiu; se o lugar não for mais livre, o ponto livre mais perto.
		var saved: Vector2 = last_pos[clean_name]
		pos = saved if world.is_free(saved) else world.nearest_free(saved)
	players[id] = {"name": clean_name, "pos": pos, "heading": 0, "species": species.get(clean_name, "")}
	if not inventories.has(clean_name):
		inventories[clean_name] = {}
	if not equipment.has(clean_name):
		equipment[clean_name] = ""
	Bag.give_starter(inventories[clean_name], equipment[clean_name])
	if not body.has(clean_name):
		body[clean_name] = Body.fresh()
	builds.touch(owner_key_of_name(clean_name))
	return pos


## Usa a habilidade ativa da espécie (tecla H). Devolve { ok, reason } nas
## recusas: "desconhecido", "sem_habilidade", "ocupado" (já está fazendo algo
## parado), "espera" ("seconds"), "sem_espaco" (salto), "sem_terreno" (arar),
## "sem_pesca". No sucesso: { ok, tag, event, ... } com "noise" (segundos
## de exposição ao Calado) e o que cada habilidade traz:
##   salto: from, to; disparada: seconds, tired, boost; uivo: pos, radius;
##   fucar e arar: seconds (a criatura fica parada até update_channels).
func use_ability(id: int, now_ms := -1) -> Dictionary:
	if not players.has(id):
		return {"ok": false, "reason": "desconhecido"}
	var species_id := species_of(id)
	var tag := Species.active_of(species_id)
	if tag.is_empty():
		return {"ok": false, "reason": "sem_habilidade"}
	if now_ms < 0:
		now_ms = Time.get_ticks_msec()
	if channels.has(id):
		return {"ok": false, "reason": "ocupado", "tag": tag}
	var left := (int(_ability_ready.get(id, 0)) - now_ms) / 1000.0
	if left > 0.0:
		return {"ok": false, "reason": "espera", "seconds": ceili(left), "tag": tag}
	var info := Abilities.data(tag)
	var pos: Vector2 = players[id]["pos"]
	var heading := int(players[id].get("heading", 0))
	var forward := Compass.forward(heading)
	var noise := float(info.get("noise", 0.0)) * Species.effect(species_id, "noise")
	var result := {"ok": true, "tag": tag, "event": tag, "noise": noise}
	match tag:
		"salto":
			var land := pos
			var reach := float(info["distance"]) * Species.effect(species_id, "jump")
			var travelled := 0.25
			while travelled <= reach + 0.001:
				var point := pos + forward * travelled
				if not world.is_free(point) or not Species.may_step(species_id, world, point) or _occupied(id, point):
					break
				land = point
				travelled += 0.25
			if land.distance_to(pos) < 0.5:
				return {"ok": false, "reason": "sem_espaco", "tag": tag}
			players[id]["pos"] = land
			_last_move[id] = now_ms
			result["from"] = pos
			result["to"] = land
		"disparada":
			var seconds := float(info["duration"])
			dashing[id] = {"until": now_ms + int(seconds * 1000.0), "tired_until": now_ms + int((seconds + float(info["tired"])) * 1000.0)}
			result["seconds"] = seconds
			result["tired"] = float(info["tired"])
			result["boost"] = float(info["boost"])
		"uivo":
			result["pos"] = pos
			result["radius"] = float(info["repel"])
		"fucar":
			channels[id] = {"tag": tag, "until": now_ms + int(float(info["channel"]) * 1000.0), "pos": pos,
				"cell": WorldGen.cell_of(pos + forward * 1.0), "build": -1}
			result["seconds"] = float(info["channel"])
		"arar":
			var target := builds.prep_target(pos, forward, REACH, "", true)
			if target.is_empty():
				return {"ok": false, "reason": "sem_terreno", "tag": tag}
			channels[id] = {"tag": tag, "until": now_ms + int(float(info["channel"]) * 1000.0), "pos": pos,
				"cell": target["cell"], "build": int(target["id"])}
			result["seconds"] = float(info["channel"])
		_:
			return {"ok": false, "reason": "sem_pesca" if tag == "pesca" else "sem_habilidade", "tag": tag}
	_ability_ready[id] = now_ms + int(float(info.get("cooldown", 0.0)) * 1000.0)
	return result


## Tem outra criatura em cima deste ponto?
func _occupied(id: int, point: Vector2) -> bool:
	for other_id in players:
		if other_id != id and (players[other_id]["pos"] as Vector2).distance_to(point) < 2.0 * WorldGen.PLAYER_RADIUS:
			return true
	return false


## Termina (ou cancela) o que as criaturas fazem paradas: fuçar e arar.
## Devolve eventos { id, event, tag, ... }: "cancelada", "achou" (item,
## amount, cell, pile), "nada" (fuçar sem achado), "arou" (build, cell,
## result de prep_build, com "drop"/"pile" se algo caiu).
func update_channels(now_ms := -1) -> Array:
	var out := []
	if channels.is_empty():
		return out
	if now_ms < 0:
		now_ms = Time.get_ticks_msec()
	for id: int in channels.keys():
		var work: Dictionary = channels[id]
		if not players.has(id) or (players[id]["pos"] as Vector2).distance_to(work["pos"]) > Abilities.CHANNEL_MOVE_LIMIT:
			channels.erase(id)
			if players.has(id):
				_ability_ready[id] = now_ms
				out.append({"id": id, "event": "cancelada", "tag": work["tag"]})
			continue
		if now_ms < int(work["until"]):
			continue
		channels.erase(id)
		if work["tag"] == "fucar":
			out.append(_finish_dig(id, work, now_ms))
		else:
			out.append(_finish_plow(id, work))
	return out


func _finish_dig(id: int, work: Dictionary, now_ms: int) -> Dictionary:
	var cell: Vector2i = work["cell"]
	var info := Abilities.data("fucar")
	var last := int(_dug.get(cell, -1000000000))
	var diggable := world.is_free(WorldGen.cell_center(cell)) and builds.at(cell).is_empty()
	if not diggable or now_ms - last < int(float(info["retry"]) * 1000.0) or _ability_rng.randf() >= float(info["find_chance"]):
		_dug[cell] = now_ms
		return {"id": id, "event": "nada", "tag": "fucar", "cell": cell}
	_dug[cell] = now_ms
	var roll := _ability_rng.randf()
	var pick: Array = Abilities.DIG_FINDS[-1]
	for find: Array in Abilities.DIG_FINDS:
		roll -= float(find[3])
		if roll < 0.0:
			pick = find
			break
	var amount := _ability_rng.randi_range(int(pick[1]), int(pick[2]))
	var item := str(pick[0])
	var key := item
	if item == "raiz":
		key = Plants.root_item(Plants.root_species(world.biome_at(cell)))
	elif Economy.has_sizes(item):
		key = Economy.sized(item, "media")
	ground.add_items(cell, {key: amount})
	return {"id": id, "event": "achou", "tag": "fucar", "cell": cell, "item": item, "amount": amount, "pile": ground.items_at(cell)}


func _finish_plow(id: int, work: Dictionary) -> Dictionary:
	var build_id := int(work["build"])
	var cell: Vector2i = work["cell"]
	var result := {}
	for i in 12:
		var phase := str(builds.get_build(build_id).get("phase", ""))
		if not Crafting.PREP_TOOLS.has(phase):
			break
		_last_strike.erase(id)
		result = prep_build(id, build_id, cell, Crafting.PREP_TOOLS[phase])
		if not result["ok"] or result["event"] in ["limpo", "capinado", "fase"]:
			break
	if result.is_empty() or not result["ok"]:
		return {"id": id, "event": "nada", "tag": "arar", "cell": cell}
	return {"id": id, "event": "arou", "tag": "arar", "cell": cell, "build": build_id, "result": result}


## Quanto a disparada multiplica a velocidade permitida agora (1.0 sem ela).
func dash_boost(id: int, now_ms := -1) -> float:
	if not dashing.has(id):
		return 1.0
	if now_ms < 0:
		now_ms = Time.get_ticks_msec()
	if now_ms >= int(dashing[id]["tired_until"]):
		dashing.erase(id)
		return 1.0
	return float(Abilities.DATA["disparada"]["boost"]) if now_ms < int(dashing[id]["until"]) else 1.0


## Escolhe a espécie do personagem. Só vale uma vez por nome: depois de
## escolhida, não muda. Devolve true se gravou.
func choose_species(id: int, species_id: String) -> bool:
	if not players.has(id) or not Species.is_species(species_id):
		return false
	var player_name: String = players[id]["name"]
	if species.has(player_name):
		return false
	species[player_name] = species_id
	players[id]["species"] = species_id
	return true


## Depuração: troca a espécie do jogador, mesmo já escolhida.
func debug_set_species(id: int, species_id: String) -> bool:
	if not players.has(id) or not Species.is_species(species_id):
		return false
	species[players[id]["name"]] = species_id
	players[id]["species"] = species_id
	_ability_ready.erase(id)
	return true


func species_of(id: int) -> String:
	return str(players[id].get("species", "")) if players.has(id) else ""


func remove_player(id: int) -> void:
	if players.has(id):
		last_pos[players[id]["name"]] = players[id]["pos"]
	builds.touch(owner_key(id))
	players.erase(id)
	_ability_ready.erase(id)
	dashing.erase(id)
	channels.erase(id)
	_last_collect.erase(id)
	_last_move.erase(id)
	_last_strike.erase(id)
	_last_build.erase(id)
	_last_drop.erase(id)
	faint_clock.erase(id)
	wet_left.erase(id)


## Fome e calor da criatura ({} se ela não está no mundo). É o mesmo
## dicionário guardado: mudá-lo muda o corpo dela.
func body_of(id: int) -> Dictionary:
	if not players.has(id):
		return {}
	var player_name: String = players[id]["name"]
	if not body.has(player_name):
		body[player_name] = Body.fresh()
	return body[player_name]


## A estação de agora (0 Coroada, 1 Declínio, 2 Longa Escuridão, 3 Ressurgência).
func season() -> int:
	return DayCycle.season_of(DayCycle.world_day(day_n, day_t))


## O ano do mundo (conta as castanhas: uma vez por ano em cada árvore).
func year() -> int:
	return int(DayCycle.world_day(day_n, day_t) / DayCycle.YEAR_DAYS)


## Os lotes de comida da criatura (o mesmo dicionário guardado).
func lots_of(id: int) -> Dictionary:
	if not players.has(id):
		return {}
	var player_name: String = players[id]["name"]
	if not lots.has(player_name):
		lots[player_name] = {}
	return lots[player_name]


## Passa o tempo na comida da bolsa de quem está no mundo ("days" de jogo, já
## com o frio). Devolve id -> { item: quantidade estragada } de quem perdeu algo.
func age_food(id: int, days: float) -> Dictionary:
	var entry := body_of(id)
	Body.settle_raw(entry, days)
	return Body.age(lots_of(id), inventory_of(id), days)


## Come 1 item de comida da bolsa (do lote mais velho). Devolve { ok, reason,
## item, event } com reason "desconhecido", "nao_e_comida", "sem_item" ou
## "cheio" (barriga cheia); event "comeu" ou "enjoou" (raiz crua demais).
func eat(id: int, item: String) -> Dictionary:
	if not players.has(id):
		return {"ok": false, "reason": "desconhecido"}
	if not Body.is_food(item):
		return {"ok": false, "reason": "nao_e_comida", "item": item}
	var inv := inventory_of(id)
	if int(inv.get(item, 0)) <= 0:
		return {"ok": false, "reason": "sem_item", "item": item}
	var entry := body_of(id)
	if Body.is_full(entry, item):
		return {"ok": false, "reason": "cheio", "item": item}
	var food_lots := lots_of(id)
	Body.reconcile(food_lots, inv)
	Body.take_oldest(food_lots, item)
	inv[item] = int(inv[item]) - 1
	if int(inv[item]) <= 0:
		inv.erase(item)
	return {"ok": true, "item": item, "event": Body.eat(entry, item)}


## Tira 1 "item" da bolsa sem comer (ex.: fruta dada a um cavalo). Comida sai
## do lote mais velho. Devolve false se não tinha.
func give_away(id: int, item: String) -> bool:
	if not players.has(id):
		return false
	var inv := inventory_of(id)
	if int(inv.get(item, 0)) <= 0:
		return false
	if Body.is_food(item):
		var food_lots := lots_of(id)
		Body.reconcile(food_lots, inv)
		Body.take_oldest(food_lots, item)
	inv[item] = int(inv[item]) - 1
	if int(inv[item]) <= 0:
		inv.erase(item)
	return true


## Assa na fogueira acesa ao alcance (Body.ROASTS) até "amount" itens crus.
## "fires": posições das fogueiras acesas. Devolve { ok, reason, item, into,
## amount } com reason "desconhecido", "nao_assa", "sem_item" ou "sem_fogo".
func roast(id: int, item: String, amount: int, fires: Array) -> Dictionary:
	if not players.has(id):
		return {"ok": false, "reason": "desconhecido"}
	if Body.roast_of(item).is_empty():
		return {"ok": false, "reason": "nao_assa", "item": item}
	var inv := inventory_of(id)
	var have := int(inv.get(item, 0))
	if have <= 0:
		return {"ok": false, "reason": "sem_item", "item": item}
	var pos: Vector2 = players[id]["pos"]
	var near := false
	for fire: Vector2 in fires:
		if fire.distance_to(pos) <= Body.ROAST_REACH:
			near = true
			break
	if not near:
		return {"ok": false, "reason": "sem_fogo", "item": item}
	var count := clampi(amount, 1, have)
	var into := Body.roast_of(item)
	inv[item] = have - count
	if int(inv[item]) <= 0:
		inv.erase(item)
	inv[into] = int(inv.get(into, 0)) + count
	Body.reconcile(lots_of(id), inv)
	return {"ok": true, "item": item, "into": into, "amount": count}


## J com a enxada perto de uma rama (Plants): cava a raiz. Cada rama pede
## Body.ROOT_DIG_HITS golpes; no último, a raiz sai (Body.ROOT_AMOUNT, um só
## na Longa Escuridão) e a rama some até rebrotar (Harvest). "cell" é a casa
## à frente; se não for uma rama, vale a rama mais perto ao alcance.
## Devolve { ok, reason, amount, item, kept, left_over, pile_cell } com reason
## "desconhecido", "sem_enxada", "terreno" (nenhuma rama ao alcance) ou
## "cavando" (golpe dado, a raiz ainda não saiu).
func dig_roots(id: int, cell: Vector2i, _now_ms := -1) -> Dictionary:
	if not players.has(id):
		return {"ok": false, "reason": "desconhecido"}
	if wielding(id) != "enxada":
		return {"ok": false, "reason": "sem_enxada"}
	var pos: Vector2 = players[id]["pos"]
	var target := _rama_near(pos, cell)
	if target == WorldGen.NO_CELL:
		return {"ok": false, "reason": "terreno"}
	Body.exert(body_of(id))
	var hits := int(_rooted.get(target, 0)) + 1
	if hits < Body.ROOT_DIG_HITS:
		_rooted[target] = hits
		return {"ok": false, "reason": "cavando", "cell": target}
	_rooted.erase(target)
	var taken := harvest.take(target)
	if not taken["ok"]:
		return {"ok": false, "reason": "terreno"}
	var amount := 1 if season() == 2 else Body.ROOT_AMOUNT
	var item := Plants.root_item(Plants.species_at(world, target))
	var result := _give(id, {item: amount})
	result["item"] = item
	result["cell"] = target
	return result


## A rama de pé mais perto ao alcance ("ahead" primeiro). NO_CELL se não há.
func _rama_near(pos: Vector2, ahead: Vector2i) -> Vector2i:
	var reach := REACH + 0.6
	var best := WorldGen.NO_CELL
	var best_distance := INF
	var here := WorldGen.cell_of(pos)
	for cell: Vector2i in [ahead] + _around(here, 2):
		if world.thing_at(cell) != WorldGen.Thing.RAMA or not harvest.is_available(cell):
			continue
		var distance := pos.distance_to(WorldGen.cell_center(cell))
		if distance > reach:
			continue
		if cell == ahead:
			return cell
		if distance < best_distance:
			best_distance = distance
			best = cell
	return best


static func _around(center: Vector2i, radius: int) -> Array:
	var cells := []
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			cells.append(center + Vector2i(dx, dy))
	return cells


## Põe itens na bolsa; o que não couber fica no chão, onde a criatura está.
func _give(id: int, got: Dictionary) -> Dictionary:
	var inv := inventory_of(id)
	var pos: Vector2 = players[id]["pos"]
	var split := Bag.split_to_fit(inv, wielding(id), got, offhand_of(id), species_of(id))
	for key: String in split[0]:
		inv[key] = int(inv.get(key, 0)) + int(split[0][key])
	if not split[1].is_empty():
		ground.add_items(WorldGen.cell_of(pos), split[1])
	var amount := 0
	for key: String in got:
		amount += int(got[key])
	return {"ok": true, "amount": amount, "kept": split[0], "left_over": split[1], "pile_cell": WorldGen.cell_of(pos)}


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


## O que a criatura tem na mão não dominante ("" = livre).
func offhand_of(id: int) -> String:
	if not players.has(id):
		return ""
	return offhand.get(players[id]["name"], "")


## Quanto a tocha desta criatura queima (o mestre do fogo, mais).
func torch_seconds(id: int) -> float:
	return TORCH_SECONDS * Species.effect(species_of(id), "torch")


## Segundos que a tocha acesa na mão ainda queima (0 = apagada ou sem tocha).
func torch_left(id: int, at := -1.0) -> float:
	if not players.has(id):
		return 0.0
	return maxf(0.0, float(torch_until.get(players[id]["name"], 0.0)) - (Time.get_unix_time_from_system() if at < 0.0 else at))


## Ids de quem leva uma tocha acesa.
func lit_torch_ids() -> Array:
	var out := []
	for id in players:
		if torch_left(id) > 0.0:
			out.append(id)
	return out


## Posições (Vector3: x, y, raio) de quem leva uma tocha acesa: o Calado respeita.
func lit_torches() -> Array:
	var out := []
	for id in players:
		if torch_left(id) > 0.0:
			var pos: Vector2 = players[id]["pos"]
			out.append(Vector3(pos.x, pos.y, Horrors.TORCH_SAFE))
	return out


## Acender a tocha. Perto de uma fogueira acesa ela acende na hora; senão,
## com uma pedra pequena e uma faca (de graça) ou um sílex (que se gasta), o
## jogador risca faíscas com Espaço (request_spark): de 5 a 9 batidas, uma a
## cada STRIKE_GAP segundos no máximo.
## Devolve { ok, reason, seconds } (acendeu), { ok, started, method, needed }
## (começou a riscar) ou a recusa: "sem_tocha", "ja_acesa", "sem_material".
func light_torch(id: int) -> Dictionary:
	if not players.has(id):
		return {"ok": false, "reason": "desconhecido"}
	if offhand_of(id) != "tocha":
		return {"ok": false, "reason": "sem_tocha"}
	if torch_left(id) > 0.0:
		return {"ok": false, "reason": "ja_acesa"}
	var pos: Vector2 = players[id]["pos"]
	for build: Dictionary in builds.all():
		if build["kind"] == "fogueira" and builds.is_lit(int(build["id"])) and Builds.reach_distance(build, pos) <= BUILD_REACH:
			torch_until[players[id]["name"]] = Time.get_unix_time_from_system() + torch_seconds(id)
			return {"ok": true, "seconds": torch_seconds(id)}
	var method := ignition_method(id)
	if method.is_empty():
		return {"ok": false, "reason": "sem_material"}
	var needed := _strike_rng.randi_range(STRIKE_MIN, STRIKE_MAX)
	striking[id] = {"method": method, "needed": needed, "count": 0, "last_ms": Time.get_ticks_msec(), "first": true}
	return {"ok": true, "started": true, "method": method, "needed": needed}


## Como esta criatura acenderia a tocha sem fogueira: "faca" (faca + pedra
## pequena, não gasta nada), "silex" (sílex + pedra pequena, gasta o sílex), "pedra" (só a pedra pequena,
## para o mestre do fogo) ou "".
func ignition_method(id: int) -> String:
	var bag := inventory_of(id)
	if int(bag.get("pedra_pequena", 0)) <= 0:
		return ""
	if int(bag.get("faca", 0)) > 0:
		return "faca"
	# O mestre do fogo acende só com a pedra, sem faca nem sílex.
	if Species.TAGS.has("fogo") and Species.tags_of(species_of(id)).has("fogo"):
		return "pedra"
	if int(bag.get("silex", 0)) > 0:
		return "silex"
	return ""


## Quem está riscando a tocha (para o servidor saber se cancela).
func is_striking(id: int) -> bool:
	return striking.has(id)


## Uma batida (Espaço) de quem está riscando a tocha. Devolve { event } com
## "nada" (não estava riscando ou foi cedo demais), "faisca", "acendeu"
## (com "seconds") ou "cancelada" (com "why": "demora" ou "sem_material").
func strike_spark(id: int, at_ms := -1) -> Dictionary:
	if not striking.has(id) or not players.has(id):
		return {"event": "nada"}
	var now := Time.get_ticks_msec() if at_ms < 0 else at_ms
	var entry: Dictionary = striking[id]
	var waited := (now - int(entry["last_ms"])) / 1000.0
	if waited > (STRIKE_FIRST_GRACE if bool(entry["first"]) else STRIKE_GAP):
		striking.erase(id)
		return {"event": "cancelada", "why": "demora"}
	if not bool(entry["first"]) and waited < STRIKE_MIN_INTERVAL:
		return {"event": "nada"}
	var bag := inventory_of(id)
	var tool_item: String = {"faca": "faca", "silex": "silex"}.get(str(entry["method"]), "")
	if int(bag.get("pedra_pequena", 0)) <= 0 or (not tool_item.is_empty() and int(bag.get(tool_item, 0)) <= 0):
		striking.erase(id)
		return {"event": "cancelada", "why": "sem_material"}
	entry["last_ms"] = now
	entry["first"] = false
	entry["count"] = int(entry["count"]) + 1
	if int(entry["count"]) < int(entry["needed"]):
		return {"event": "faisca"}
	striking.erase(id)
	if str(entry["method"]) == "silex":
		bag["silex"] = int(bag.get("silex", 0)) - 1
		if int(bag["silex"]) <= 0:
			bag.erase("silex")
	torch_until[players[id]["name"]] = Time.get_unix_time_from_system() + torch_seconds(id)
	return {"event": "acendeu", "seconds": torch_seconds(id)}


## Cancela quem parou de riscar por tempo demais. Devolve os ids cancelados.
func expire_strikes(at_ms := -1) -> Array:
	var now := Time.get_ticks_msec() if at_ms < 0 else at_ms
	var out := []
	for id: int in striking.keys():
		var entry: Dictionary = striking[id]
		var limit := STRIKE_FIRST_GRACE if bool(entry["first"]) else STRIKE_GAP
		if not players.has(id) or (now - int(entry["last_ms"])) / 1000.0 > limit:
			striking.erase(id)
			out.append(id)
	return out


## Tochas que queimaram até o fim: somem da mão. Devolve os ids de quem estava
## no mundo.
func expire_torches(at := -1.0) -> Array:
	if at < 0.0:
		at = Time.get_unix_time_from_system()
	var out := []
	for player_name: String in torch_until.keys():
		if float(torch_until[player_name]) > at:
			continue
		torch_until.erase(player_name)
		offhand[player_name] = ""
		for id in players:
			if players[id]["name"] == player_name:
				out.append(id)
	return out


## Guarda na bolsa o que estiver na mão não dominante. Devolve { ok, reason, item }.
## Tocha acesa não se guarda: queima até o fim.
func stow_offhand(id: int) -> Dictionary:
	var item := offhand_of(id)
	if item.is_empty():
		return {"ok": false, "reason": "maos_livres"}
	if torch_left(id) > 0.0:
		return {"ok": false, "reason": "tocha_acesa", "item": item}
	var inv := inventory_of(id)
	inv[item] = int(inv.get(item, 0)) + 1
	offhand[players[id]["name"]] = ""
	return {"ok": true, "item": item}


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
	if Bag.is_offhand(item):
		# Segunda peça de equipamento: a mão principal não muda.
		if torch_left(id) > 0.0:
			return {"ok": false, "reason": "tocha_acesa", "item": item}
		var old: String = offhand.get(player_name, "")
		if not old.is_empty():
			inv[old] = int(inv.get(old, 0)) + 1
		inv[item] = int(inv[item]) - 1
		if int(inv[item]) <= 0:
			inv.erase(item)
		offhand[player_name] = item
		return {"ok": true, "item": item, "stowed": old, "slot": "offhand"}
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


## O que o Calado faz com quem alcança: a bolsa perde todos os recursos
## (Economy.is_item, menos o que se empunha, como o machado); armas e o que
## está nas mãos ficam.
## Devolve o que foi perdido (item -> quantidade).
func strip_resources(id: int) -> Dictionary:
	var lost := {}
	var inv := inventory_of(id)
	for item: String in inv.keys():
		if Economy.is_item(item) and not Bag.WIELDABLE.has(item):
			lost[item] = inv[item]
			inv.erase(item)
	return lost


## Quem desfalece de fome ou de frio perde metade de cada recurso da bolsa
## (arredondado para baixo: quem tem 1 fica com ele); armas, ferramentas e o
## que está nas mãos ficam. Devolve o que foi perdido (item -> quantidade).
func strip_half_resources(id: int) -> Dictionary:
	var lost := {}
	var inv := inventory_of(id)
	for item: String in inv.keys():
		if Economy.is_item(item) and not Bag.WIELDABLE.has(item):
			var half := int(inv[item]) / 2
			if half > 0:
				lost[item] = half
				inv[item] = int(inv[item]) - half
	return lost


## Leva o jogador a outro ponto sem a conferência de velocidade (ex.: o
## Calado o alcançou).
func teleport(id: int, pos: Vector2) -> void:
	if players.has(id):
		players[id]["pos"] = pos
		_last_move[id] = Time.get_ticks_msec()


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
	# Espécies mais rápidas (cervo: leve e veloz) andam mais longe por segundo.
	var allowed := MAX_SPEED * maxf(1.0, Species.effect(species_of(id), "speed")) * dash_boost(id, now_ms) * seconds + MOVE_SLACK
	if riding.has(id):
		allowed = RIDE_MAX_SPEED * seconds + MOVE_SLACK
	if not pos.is_finite() or from.distance_to(pos) > allowed or not world.is_free(pos) \
			or not Species.may_step(species_of(id), world, pos):
		return {"ok": false, "pos": from}
	_last_move[id] = now_ms
	players[id]["pos"] = pos
	return {"ok": true, "pos": pos}


## Recolhe o recurso de uma casa ao alcance (fibra ou frutas de um arbusto,
## galhos, argila, pedras, ou um bambu já derrubado). Madeira e pedra entram na bolsa
## por tamanho (Harvest.take devolve "parts"). A fonte se esgota e rebrota com o tempo
## (Harvest).
## O que não cabe na carga (Bag.CAPACITY) fica no chão, na casa da criatura.
## Devolve { ok, item, amount, reason, hits_left, kept, left_over }. reason: "longe", "nada",
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
	# A rama não se arranca com a mão: a raiz sai com a enxada.
	if thing == WorldGen.Thing.RAMA:
		return {"ok": false, "reason": "cavar"}
	# Na Longa Escuridão as plantas de fruta não dão nada.
	if season() == 2 and harvest.is_available(cell) and Plants.is_fruit(Plants.species_at(world, cell)):
		return {"ok": false, "reason": "sem_frutas"}
	var now := Time.get_ticks_msec()
	if now - int(_last_collect.get(id, -COLLECT_COOLDOWN_MS)) < COLLECT_COOLDOWN_MS:
		return {"ok": false, "reason": "devagar"}
	_last_collect[id] = now
	var item := Harvest.item_of(thing)
	var inv := inventory_of(id)
	var carrying := wielding(id)
	# Árvore de pé: o Espaço recolhe a resina seca ou diz como ela está.
	var resin_haul := {}
	# Árvore de pé no Declínio: primeiro as castanhas do chão, uma vez por ano.
	var standing_tree := thing == WorldGen.Thing.ARVORE and builds.at(cell).is_empty() and harvest.is_available(cell) and harvest.hits_left(cell) > 0
	if standing_tree and season() == Body.NUT_SEASON and Body.nut_tree(cell) and int(nuts.get(cell, -1)) != year():
		if Bag.free_space(inv, carrying, offhand_of(id), species_of(id)) <= 0:
			return {"ok": false, "reason": "cheio", "item": "castanha"}
		nuts[cell] = year()
		var nut_result := _give(id, {"castanha": Body.NUT_AMOUNT})
		nut_result.merge({"reason": "", "item": "castanha", "parts": {}, "extras": {}})
		return nut_result
	if standing_tree:
		var tapped := resin.collect(cell)
		if not tapped["ok"]:
			return {"ok": false, "reason": "arvore", "item": tapped["text"]}
		resin_haul = tapped["yield"]
		item = "resina"
	if Bag.free_space(inv, carrying, offhand_of(id), species_of(id)) <= 0:
		if not resin_haul.is_empty():
			resin.undo_collect(cell)
		return {"ok": false, "reason": "cheio", "item": item}
	var result := {"ok": true, "reason": "", "item": item, "amount": int(resin_haul["resina"]), "parts": {}, "extras": {}} if not resin_haul.is_empty() else harvest.take(cell)
	if not result["ok"]:
		return result
	item = str(result["item"])
	var parts: Dictionary = result.get("parts", {})
	var got: Dictionary = (parts if not parts.is_empty() else {item: int(result["amount"])}).duplicate()
	var extras: Dictionary = result.get("extras", {})
	for extra: String in extras:
		got[extra] = int(got.get(extra, 0)) + int(extras[extra])
	# O que não cabe na carga fica no chão, onde a criatura está.
	var split := Bag.split_to_fit(inv, carrying, got, offhand_of(id), species_of(id))
	for key: String in split[0]:
		inv[key] = int(inv.get(key, 0)) + int(split[0][key])
	if not split[1].is_empty():
		ground.add_items(WorldGen.cell_of(pos), split[1])
	result["kept"] = split[0]
	result["left_over"] = split[1]
	result["pile_cell"] = WorldGen.cell_of(pos)
	return result


## Larga itens da bolsa no chão, na casa da criatura. Devolve { ok, reason,
## cell, item, amount }. reason: "nao_tem" (não há isso na bolsa), "devagar".
func drop(id: int, item: String, amount: int) -> Dictionary:
	if not players.has(id):
		return {"ok": false, "reason": "desconhecido"}
	var inv := inventory_of(id)
	var have := int(inv.get(item, 0))
	if have <= 0 or amount <= 0:
		return {"ok": false, "reason": "nao_tem", "item": item}
	var now := Time.get_ticks_msec()
	if now - int(_last_drop.get(id, -DROP_COOLDOWN_MS)) < DROP_COOLDOWN_MS:
		return {"ok": false, "reason": "devagar"}
	_last_drop[id] = now
	var moved := mini(amount, have)
	inv[item] = have - moved
	if int(inv[item]) <= 0:
		inv.erase(item)
	var cell := WorldGen.cell_of(players[id]["pos"])
	ground.add(cell, item, moved)
	return {"ok": true, "cell": cell, "item": item, "amount": moved}


## Pega do chão o que couber na carga, do mais pesado ao mais leve. Devolve
## { ok, reason, cell, taken, left }. reason: "longe", "nada", "cheio", "devagar".
func pick_up(id: int, cell: Vector2i, only := "") -> Dictionary:
	if not players.has(id):
		return {"ok": false, "reason": "desconhecido"}
	if players[id]["pos"].distance_to(WorldGen.cell_center(cell)) > REACH:
		return {"ok": false, "reason": "longe"}
	var pile := ground.items_at(cell)
	# "only": o jogador escolheu um item do monte (a chave exata, ex. "pedra_grande").
	if not only.is_empty():
		pile = {only: pile[only]} if pile.has(only) else {}
	if pile.is_empty():
		return {"ok": false, "reason": "nada"}
	var inv := inventory_of(id)
	var split := Bag.split_to_fit(inv, wielding(id), pile, offhand_of(id), species_of(id))
	if split[0].is_empty():
		return {"ok": false, "reason": "cheio"}
	var now := Time.get_ticks_msec()
	if now - int(_last_drop.get(id, -DROP_COOLDOWN_MS)) < DROP_COOLDOWN_MS:
		return {"ok": false, "reason": "devagar"}
	_last_drop[id] = now
	for key: String in split[0]:
		inv[key] = int(inv.get(key, 0)) + ground.remove(cell, key, int(split[0][key]))
	return {"ok": true, "cell": cell, "taken": split[0], "left": split[1]}


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
	Body.exert(body_of(id))
	# O terreno de uma obra tem as suas próprias fases (preparo).
	if not builds.at(cell).is_empty():
		return {"ok": false, "reason": "nada", "hits_left": 0, "felled": false}
	return harvest.strike(cell, -1.0, Species.effect(species_of(id), "axe"))


## Um golpe de faca no tronco de uma árvore ao alcance, para tirar resina.
## Quem chama confere se a faca está empunhada. A resina vai para a bolsa; o
## que não couber fica no chão, onde a criatura está. Devolve { ok, reason,
## event, cuts, yield, kept, left_over, pile_cell } (event: ver Resin.tap).
func tap_tree(id: int, cell: Vector2i) -> Dictionary:
	if not players.has(id):
		return {"ok": false, "reason": "desconhecido"}
	var pos: Vector2 = players[id]["pos"]
	if pos.distance_to(WorldGen.cell_center(cell)) > REACH:
		return {"ok": false, "reason": "longe"}
	var now := Time.get_ticks_msec()
	if now - int(_last_strike.get(id, -STRIKE_COOLDOWN_MS)) < STRIKE_COOLDOWN_MS:
		return {"ok": false, "reason": "devagar"}
	_last_strike[id] = now
	# Árvore já derrubada (ou obra no lugar): não há tronco para sangrar.
	if not builds.at(cell).is_empty() or not harvest.is_available(cell) or harvest.hits_left(cell) == 0:
		return {"ok": false, "reason": "nada"}
	var result := resin.tap(cell)
	if not result["ok"]:
		result["reason"] = result["event"]
	return result


## Um golpe de preparo no terreno de uma obra grande: machado (limpar) ou
## enxada (capinar), na casa "cell", ao alcance. Quem chama confere o que está
## empunhado. O que for arrancado cai no chão da casa, como se tivesse sido
## colhido ("drop"). Devolve o resultado de Builds.prep_hit, com "drop" e
## "pile" quando algo caiu.
func prep_build(id: int, build_id: int, cell: Vector2i, force_tool := "") -> Dictionary:
	if not players.has(id):
		return {"ok": false, "reason": "desconhecido"}
	var pos: Vector2 = players[id]["pos"]
	if pos.distance_to(WorldGen.cell_center(cell)) > REACH:
		return {"ok": false, "reason": "longe"}
	var now := Time.get_ticks_msec()
	if now - int(_last_strike.get(id, -STRIKE_COOLDOWN_MS)) < STRIKE_COOLDOWN_MS:
		return {"ok": false, "reason": "devagar"}
	_last_strike[id] = now
	var thing := world.thing_at(cell)
	var drop := _clear_yield(cell) if Crafting.CLEAR_HITS.has(thing) else {}
	var result := builds.prep_hit(build_id, cell, force_tool if not force_tool.is_empty() else wielding(id))
	if result["ok"] and result.get("cleared", false) and not drop.is_empty():
		ground.add_items(cell, drop)
		result["drop"] = drop
		result["pile"] = ground.items_at(cell)
	return result


## Um golpe de machado numa obra ao alcance, para desmontá-la (Builds.strike_wreck).
## Quem chama é o J com o machado; aqui se confere o machado nas mãos, a casa
## (Builds.wreck_cells) e o alcance. Quando o golpe completa a conta, a obra
## some: o material que volta e o estoque caem no chão, dentro do terreno.
## Devolve { ok, reason } nas recusas ("ferramenta", "longe", "devagar", "casa",
## "povoado", "acesa", "nao_dono") ou { ok, event, hits_left, total, first, cell } e, se
## foi a última, também { kind, title, piles, back }.
func wreck_build(id: int, build_id: int, cell: Vector2i) -> Dictionary:
	if not players.has(id):
		return {"ok": false, "reason": "desconhecido"}
	var build := builds.get_build(build_id)
	if build.is_empty():
		return {"ok": false, "reason": "desconhecida"}
	if wielding(id) != "machado":
		return {"ok": false, "reason": "ferramenta"}
	if not Builds.wreck_cells(build).has(cell):
		return {"ok": false, "reason": "casa"}
	if players[id]["pos"].distance_to(WorldGen.cell_center(cell)) > REACH:
		return {"ok": false, "reason": "longe"}
	var now := Time.get_ticks_msec()
	if now - int(_last_strike.get(id, -STRIKE_COOLDOWN_MS)) < STRIKE_COOLDOWN_MS:
		return {"ok": false, "reason": "devagar"}
	_last_strike[id] = now
	var result := builds.strike_wreck(build_id, -1.0, owner_key(id))
	if not result["ok"]:
		return result
	result["cell"] = cell
	if result["event"] == "derrubada":
		var gone := builds.demolish(build_id)
		var piles := {}
		for pile_cell: Vector2i in gone["piles"]:
			ground.add_items(pile_cell, gone["piles"][pile_cell])
			piles[pile_cell] = ground.items_at(pile_cell)
		result["kind"] = gone["kind"]
		result["title"] = gone["title"]
		result["back"] = gone["back"]
		result["piles"] = piles
	return result


## O que uma árvore, bambu ou arbusto arrancado deixa no chão: o mesmo que
## daria ao ser colhido (Harvest.SOURCES), já com os tamanhos sorteados.
## Precisa ser chamado antes de a casa ser limpa.
func _clear_yield(cell: Vector2i) -> Dictionary:
	var source: Dictionary = Harvest.SOURCES.get(world.thing_at(cell), {})
	if source.is_empty():
		return {}
	var items := {}
	var parts := harvest._roll_parts(cell, source["item"], int(source["amount"]))
	if parts.is_empty():
		items[source["item"]] = int(source["amount"])
	else:
		items = parts
	for extra: String in source.get("extras", {}):
		items[extra] = int(items.get(extra, 0)) + int(source["extras"][extra])
	return items


## Começa uma construção na casa "cell" (a que está à frente da criatura,
## escolhida pelo cliente; o servidor confere se está ao alcance, livre e
## sem ninguém em cima). Devolve { ok, reason, id }.
func start_build(id: int, kind: String, cell: Vector2i) -> Dictionary:
	if not players.has(id):
		return {"ok": false, "reason": "desconhecido"}
	var pos: Vector2 = players[id]["pos"]
	if pos.distance_to(WorldGen.cell_center(cell)) > BUILD_REACH:
		return {"ok": false, "reason": "longe"}
	for other_id in players:
		var other: Vector2 = players[other_id]["pos"]
		if WorldGen.cell_of(other) == cell or other.distance_to(WorldGen.cell_center(cell)) < 0.5 + WorldGen.PLAYER_RADIUS:
			return {"ok": false, "reason": "ocupado"}
	return builds.start(kind, cell)


## Começa uma construção grande no terreno com o canto noroeste em "origin" e
## lado "size", com a porta para o lado "entrance". A criatura precisa estar na
## mesma região do terreno. Devolve { ok, reason, id }.
func start_site(id: int, kind: String, origin: Vector2i, size: int, entrance: String) -> Dictionary:
	if not players.has(id):
		return {"ok": false, "reason": "desconhecido"}
	var pos: Vector2 = players[id]["pos"]
	if world.region_of(WorldGen.cell_of(pos)) != world.region_of(origin):
		return {"ok": false, "reason": "regiao_longe"}
	return builds.start_site(kind, origin, size, entrance)


## Tira do caminho quem estava dentro de uma parede que acabou de subir: cada
## criatura vai para o ponto livre mais perto. Devolve [[id, posição nova], ...].
func eject_from_walls(build_id: int) -> Array:
	var build := builds.get_build(build_id)
	var moved := []
	for id in players:
		var pos: Vector2 = players[id]["pos"]
		if world.is_free(pos):
			continue
		var best := world.nearest_free(pos)
		if best != pos:
			players[id]["pos"] = best
			moved.append([id, best])
	return moved


## Dá nome ao povoado de um marco ao alcance (Builds.name_settlement).
func name_settlement(id: int, build_id: int, noun_index: int, adjective_index: int) -> Dictionary:
	if not players.has(id):
		return {"ok": false, "reason": "desconhecido"}
	var build := builds.get_build(build_id)
	if build.is_empty():
		return {"ok": false, "reason": "nao_marco"}
	var pos: Vector2 = players[id]["pos"]
	if Builds.reach_distance(build, pos) > BUILD_REACH:
		return {"ok": false, "reason": "longe"}
	return builds.name_settlement(build_id, noun_index, adjective_index)


## Um Espaço numa construção ao alcance: deposita materiais, bate, acende
## ou alimenta o fogo (Builds.work). Devolve o resultado de Builds.work.
func work_build(id: int, build_id: int) -> Dictionary:
	if not players.has(id):
		return {"ok": false, "reason": "desconhecido"}
	var build := builds.get_build(build_id)
	if build.is_empty():
		return {"ok": false, "reason": "desconhecida"}
	var pos: Vector2 = players[id]["pos"]
	if Builds.reach_distance(build, pos) > BUILD_REACH:
		return {"ok": false, "reason": "longe"}
	var now := Time.get_ticks_msec()
	if float(now - int(_last_build.get(id, -BUILD_COOLDOWN_MS))) < build_cooldown_ms(id):
		return {"ok": false, "reason": "devagar"}
	_last_build[id] = now
	Body.exert(body_of(id))
	return builds.work(build_id, inventory_of(id), -1.0, pos)


## Intervalo mínimo entre batidas numa obra: quem trabalha mais devagar
## (efeito "work" da espécie) leva mais tempo por batida.
func build_cooldown_ms(id: int) -> float:
	var body_factor := Body.work_factor(body_of(id)) if players.has(id) else 1.0
	return BUILD_COOLDOWN_MS / maxf(0.1, Species.effect(species_of(id), "work") * body_factor)


## A chave de dono de uma criatura (Builds.claim). Hoje é o nome; quando houver
## login, é aqui que passa a ser o id da conta.
static func owner_key_of_name(player_name: String) -> String:
	return player_name.strip_edges().left(24)


func owner_key(id: int) -> String:
	return owner_key_of_name(players[id]["name"]) if players.has(id) else ""


## Vazio se a criatura pode mexer nos donos agora; senão, a recusa.
func _owner_check(id: int, build_id: int) -> Dictionary:
	if not players.has(id):
		return {"ok": false, "reason": "desconhecido"}
	var build := builds.get_build(build_id)
	if build.is_empty():
		return {"ok": false, "reason": "desconhecida"}
	if Builds.has_owners(build) and not Builds.inside(build, players[id]["pos"]):
		return {"ok": false, "reason": "fora"}
	return {}


## Propor derrubar uma construção, no marco do povoado (Builds.propose_wreck).
## Devolve o resultado dele, ou { ok: false, reason: "longe" | "desconhecido" }.
func propose_wreck(id: int, marco_id: int, target_id: int) -> Dictionary:
	var check := _marco_check(id, marco_id)
	if not check.is_empty():
		return check
	return builds.propose_wreck(marco_id, owner_key(id), target_id)


## Votar numa proposta, no marco (Builds.vote_wreck).
func vote_wreck(id: int, marco_id: int, target_id: int, yes: bool) -> Dictionary:
	var check := _marco_check(id, marco_id)
	if not check.is_empty():
		return check
	return builds.vote_wreck(marco_id, owner_key(id), target_id, yes)


## Vazio se a criatura está ao alcance do marco; senão, a recusa.
func _marco_check(id: int, marco_id: int) -> Dictionary:
	if not players.has(id):
		return {"ok": false, "reason": "desconhecido"}
	var marco := builds.get_build(marco_id)
	if marco.is_empty():
		return {"ok": false, "reason": "desconhecida"}
	if Builds.reach_distance(marco, players[id]["pos"]) > BUILD_REACH:
		return {"ok": false, "reason": "longe"}
	return {}


## Ser dono do abrigo onde se está. Devolve o resultado de Builds.claim, ou
## { ok: false, reason: "fora" } se a criatura não está lá dentro.
func claim_build(id: int, build_id: int) -> Dictionary:
	var check := _owner_check(id, build_id)
	if not check.is_empty():
		return check
	return builds.claim(build_id, owner_key(id))


func release_build(id: int, build_id: int) -> Dictionary:
	var check := _owner_check(id, build_id)
	if not check.is_empty():
		return check
	return builds.release(build_id, owner_key(id))


## Guarda itens da bolsa numa construção que armazena (armazém, abrigo).
## Devolve o resultado de Builds.store, ou { ok: false, reason: "longe" | "devagar" }.
func store_in_build(id: int, build_id: int, item: String, amount: int) -> Dictionary:
	var check := _storage_check(id, build_id)
	if not check.is_empty():
		return check
	return builds.store(build_id, inventory_of(id), item, amount, owner_key(id))


## Pega itens do estoque de uma construção para a bolsa, até onde cabe na carga.
func fetch_from_build(id: int, build_id: int, item: String, amount: int) -> Dictionary:
	var check := _storage_check(id, build_id)
	if not check.is_empty():
		return check
	return builds.fetch(build_id, inventory_of(id), wielding(id), item, amount, owner_key(id), species_of(id))


## Vazio se a criatura pode mexer no estoque agora; senão, a recusa.
func _storage_check(id: int, build_id: int) -> Dictionary:
	if not players.has(id):
		return {"ok": false, "reason": "desconhecido"}
	var build := builds.get_build(build_id)
	if build.is_empty():
		return {"ok": false, "reason": "desconhecida"}
	if Builds.reach_distance(build, players[id]["pos"]) > BUILD_REACH:
		return {"ok": false, "reason": "longe"}
	if Builds.has_furniture(build) and Builds.furniture_near(build, players[id]["pos"]) != "prateleiras":
		return {"ok": false, "reason": "longe"}
	# Armazém e abrigo: só se mexe no estoque lá dentro.
	if not Builds.has_furniture(build) and not Builds.inside(build, players[id]["pos"]):
		return {"ok": false, "reason": "longe"}
	var now := Time.get_ticks_msec()
	if now - int(_last_drop.get(id, -DROP_COOLDOWN_MS)) < DROP_COOLDOWN_MS:
		return {"ok": false, "reason": "devagar"}
	_last_drop[id] = now
	return {}


## Fabrica uma arma com o que está na bolsa. Devolve { ok, reason, item,
## missing }.
func craft(id: int, weapon: String) -> Dictionary:
	if not players.has(id):
		return {"ok": false, "reason": "desconhecido"}
	if Crafting.recipe(weapon).is_empty():
		return {"ok": false, "reason": "desconhecida"}
	if Crafting.needs_bench(weapon) and not builds.bench_near(players[id]["pos"]):
		return {"ok": false, "reason": "sem_bancada", "item": weapon}
	var inv := inventory_of(id)
	var materials: Dictionary = Crafting.recipe(weapon)["materials"]
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
	# Quem está online conta com a posição de agora (o servidor pode cair sem ninguém sair).
	var positions := {}
	for player_name: String in last_pos:
		positions[player_name] = [last_pos[player_name].x, last_pos[player_name].y]
	for id in players:
		var pos: Vector2 = players[id]["pos"]
		positions[players[id]["name"]] = [pos.x, pos.y]
	return {
		"version": 1,
		"seed": world.world_seed,
		"inventories": inventories,
		"equipment": equipment,
		"offhand": offhand,
		"species": species,
		"torch_until": torch_until,
		"body": body,
		"lots": lots,
		"nuts": _cells_to_save(nuts),
		"day_t": day_t,
		"day_n": day_n,
		"last_pos": positions,
		"credentials": credentials.to_save(),
		"harvest": harvest.to_save(),
		"resin": resin.to_save(),
		"builds": builds.to_save(),
		"ground": ground.to_save(),
		"horses": tame_horses,
	}


static func from_save(data: Dictionary) -> WorldState:
	var state := WorldState.new(int(data["seed"]))
	for player_name in data.get("inventories", {}):
		var inv := {}
		var saved: Dictionary = data["inventories"][player_name]
		for item: String in saved:
			# Lenha e madeira de saves antigos viram madeira com tamanho.
			var key := Economy.migrate(item)
			# Itens que não existem mais no jogo ficam para trás.
			if Economy.is_item(key) or Bag.NAMES.has(key):
				inv[key] = int(inv.get(key, 0)) + int(saved[item])
		state.inventories[player_name] = inv
	for player_name in data.get("equipment", {}):
		state.equipment[player_name] = str(data["equipment"][player_name])
	for player_name in data.get("species", {}):
		if Species.is_species(str(data["species"][player_name])):
			state.species[player_name] = str(data["species"][player_name])
	for player_name in data.get("offhand", {}):
		state.offhand[player_name] = str(data["offhand"][player_name])
	for player_name in data.get("torch_until", {}):
		state.torch_until[player_name] = float(data["torch_until"][player_name])
	var saved_body = data.get("body", {})
	if typeof(saved_body) == TYPE_DICTIONARY:
		for player_name in saved_body:
			var entry = saved_body[player_name]
			if typeof(entry) == TYPE_DICTIONARY:
				state.body[player_name] = {
					"food": clampf(float(entry.get("food", Body.START)), 0.0, Body.MAX),
					"warmth": clampf(float(entry.get("warmth", Body.START)), 0.0, Body.MAX),
				}
	var saved_lots = data.get("lots", {})
	if typeof(saved_lots) == TYPE_DICTIONARY:
		for player_name in saved_lots:
			var per_item = saved_lots[player_name]
			if typeof(per_item) != TYPE_DICTIONARY:
				continue
			var clean := {}
			for item in per_item:
				var list := []
				if typeof(per_item[item]) == TYPE_ARRAY:
					for lot in per_item[item]:
						if typeof(lot) == TYPE_ARRAY and lot.size() == 2:
							list.append([int(lot[0]), float(lot[1])])
				clean[str(item)] = list
			state.lots[player_name] = clean
	var saved_nuts = data.get("nuts", [])
	if typeof(saved_nuts) == TYPE_ARRAY:
		for row in saved_nuts:
			if typeof(row) == TYPE_ARRAY and row.size() == 3:
				state.nuts[Vector2i(int(row[0]), int(row[1]))] = int(row[2])
	state.day_t = fposmod(float(data.get("day_t", state.day_t)), 1.0)
	state.day_n = maxi(int(data.get("day_n", state.day_n)), 0)
	var positions = data.get("last_pos", {})
	if typeof(positions) == TYPE_DICTIONARY:
		for player_name in positions:
			var xy = positions[player_name]
			if typeof(xy) == TYPE_ARRAY and xy.size() == 2:
				var pos := Vector2(float(xy[0]), float(xy[1]))
				if pos.is_finite():
					state.last_pos[player_name] = pos
	var saved_credentials = data.get("credentials", {})
	if typeof(saved_credentials) == TYPE_DICTIONARY:
		state.credentials.load_save(saved_credentials)
	var harvested = data.get("harvest", [])
	if typeof(harvested) == TYPE_ARRAY:
		state.harvest.load_save(harvested)
	var tapped = data.get("resin", [])
	if typeof(tapped) == TYPE_ARRAY:
		state.resin.load_save(tapped)
	var dropped = data.get("ground", [])
	if typeof(dropped) == TYPE_ARRAY:
		state.ground.load_save(dropped)
	var tamed = data.get("horses", [])
	if typeof(tamed) == TYPE_ARRAY:
		state.tame_horses = tamed
	var built = data.get("builds", {})
	if typeof(built) == TYPE_DICTIONARY:
		state.builds.load_save(built)
	return state


static func _cells_to_save(cells: Dictionary) -> Array:
	var out := []
	for cell: Vector2i in cells:
		out.append([cell.x, cell.y, cells[cell]])
	return out


func _spawn_point() -> Vector2:
	# Quem entra pela primeira vez nasce no cruzamento de trilhas da região
	# (0, 0), o ponto de encontro do mundo: o chão livre mais próximo, saindo
	# do centro em voltas, e cada jogador na sua vez de lugar.
	var skip := players.size()
	var centre := WorldGen.center_point()
	for radius in range(0, 12):
		for i in maxi(1, radius * 4):
			var spot := centre + Vector2.from_angle(PI * 0.5 + TAU * i / float(maxi(1, radius * 4))) * float(radius) * 1.5
			if world.is_free(spot):
				if skip == 0:
					return spot
				skip -= 1
	return centre
