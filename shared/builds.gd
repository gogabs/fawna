class_name Builds
extends RefCounted
## Construções no mundo (marcos, fogueiras): onde estão, em que etapa, o que
## já foi depositado e, nas fogueiras, se estão acesas e quanta lenha têm.
## As receitas ficam em Crafting.
##
## Povoado: um marco e uma fogueira prontos na mesma região. Só então o marco
## pode receber um nome (um substantivo e um adjetivo, ver SettlementNames),
## e é com o nome que o povoado aparece em Locais, no Caminheiro.
##
## O servidor tem a cópia que vale (dentro do WorldState, salva em
## mundo.json como "builds"); cada cliente guarda um espelho, atualizado pelo
## servidor, para saber o que soa, o que a fala diz e para onde o Caminheiro
## leva. Marcos e fogueiras ocupam uma casa e não deixam passar
## (WorldGen.built). As construções grandes (Crafting, com "size") ocupam um
## quadrado: a parede bloqueia, menos a porta, e dentro dele dá para andar.
##
## Ciclo de uma construção:
##   iniciada -> (só as grandes: limpeza, com o machado, e capina, com a
##   enxada, J nas casas do terreno) -> em cada etapa: materiais (Espaço
##   deposita) -> trabalho (Espaço bate) -> próxima etapa ... -> pronta.
## Nas grandes, o trabalho de cada etapa se divide em 4 canteiros, um em cada
## canto: cada canto só aceita a sua parte, então sozinho a criatura dá a volta
## pelos cantos e em grupo cada uma fica no seu. A etapa do chão pede tempo
## para a argila secar (Crafting, "dry"): dá para trabalhar antes, mas cada
## batida vale metade; uma fogueira acesa na região seca em metade do tempo.
## Fogueira pronta:
##   apagada com lenha -> batidas de pedra (faíscas; reacender pede lenha e 1 sílex dentro da fogueira) -> acesa -> queima a
##   lenha com o tempo -> apagada. Espaço com ela acesa (ou sem lenha) põe
##   mais uma lenha.

## Quantas casas livres ficam entre uma construção e outra (2 casas, 3 m).
const SPACING := 2
## Distância mínima do ponto de chegada da Origem, para não fechar a entrada.
const ORIGIN_CLEARANCE := 2.5
var world: WorldGen
## id -> { "id", "kind", "cell": Vector2i, "region": Vector2i, "stage": int,
## "deposited": {item: qtd}, "work": int, "done": bool, "fuel": s guardados
## (apagada), "burn_until": hora Unix em que apaga (0 = apagada), "sparks": int,
## "name": nome do povoado (marcos; vazio até alguém nomear) }
var _builds := {}
var _by_cell := {}  # Vector2i -> id
var _next_id := 1

## O que uma casa é para quem quer construir nela (cell_status).
const FREE := 0  # chão livre
const CLEARABLE := 1  # árvore, arbusto ou bambu: dá para arrancar
const WATER := 2  # lago, riacho, mar ou charco: não dá
const TAKEN := 3  # trilha, recurso, Origem, outra obra ou fora da região
## Canteiros de uma construção grande: um em cada canto (NO, NE, SE, SO).
const POSTS := 4
## As 9 partes de uma obra grande, de noroeste a sudeste (ver sector_name).
const SECTORS := ["noroeste", "norte", "nordeste", "oeste", "centro", "leste", "sudoeste", "sul", "sudeste"]
## Até onde (em casas) do canto a batida conta para aquele canteiro.
const POST_REACH := 2.2
## Até onde (em casas) de um móvel da oficina o Espaço ainda o alcança.
const FURNITURE_REACH := 1.6
## Até onde (em casas) da porta Espaço ainda a abre ou fecha.
const DOOR_REACH := 1.6  # só na frente da porta, dentro ou fora


func _init(new_world: WorldGen) -> void:
	world = new_world


static func now() -> float:
	return Time.get_unix_time_from_system()


func all() -> Array:
	return _builds.values()


func get_build(id: int) -> Dictionary:
	return _builds.get(id, {})


## A construção que ocupa a casa, ou {}.
func at(cell: Vector2i) -> Dictionary:
	return _builds.get(_by_cell.get(cell, -1), {})


## Casas do terreno de uma construção (origem = canto noroeste).
static func footprint_cells(origin: Vector2i, size: int) -> Array:
	var cells := []
	for dy in size:
		for dx in size:
			cells.append(origin + Vector2i(dx, dy))
	return cells


## A casa da porta: no meio do lado escolhido ("norte", "sul", "leste", "oeste").
static func door_cell(origin: Vector2i, size: int, entrance: String) -> Vector2i:
	var mid := size / 2
	match entrance:
		"norte":
			return origin + Vector2i(mid, 0)
		"leste":
			return origin + Vector2i(size - 1, mid)
		"oeste":
			return origin + Vector2i(0, mid)
		_:
			return origin + Vector2i(mid, size - 1)


## Casas que bloqueiam a passagem: a casa única das pequenas; nas grandes,
## a parede (borda do quadrado menos a porta), só depois de limpo e capinado.
static func wall_cells(build: Dictionary) -> Array:
	var size := int(build.get("size", 1))
	if size <= 1:
		return [build["cell"]]
	if not walls_up(build):
		return []
	var door := door_cell(build["cell"], size, str(build.get("entrance", "")))
	var door_closed := not bool(build.get("door_open", true))
	var cells := []
	for cell: Vector2i in footprint_cells(build["cell"], size):
		var inner: Vector2i = cell - build["cell"]
		if (inner.x == 0 or inner.y == 0 or inner.x == size - 1 or inner.y == size - 1) and (cell != door or door_closed):
			cells.append(cell)
	if bool(build.get("done", false)):
		for cell: Vector2i in furniture_cells(build).values():
			cells.append(cell)
	return cells


## Para onde olha quem entra pela porta (sentido do lado da porta para dentro).
static func inward(entrance: String) -> Vector2i:
	match entrance:
		"norte":
			return Vector2i(0, 1)
		"leste":
			return Vector2i(-1, 0)
		"oeste":
			return Vector2i(1, 0)
		_:
			return Vector2i(0, -1)


## Os móveis de uma construção com "furniture" (a oficina): nome -> casa. Ficam
## dentro, na fileira junto da porta: a bancada à esquerda de quem entra e as
## prateleiras à direita. Vazio nas outras construções.
static func furniture_cells(build: Dictionary) -> Dictionary:
	var kind := str(build.get("kind", ""))
	var size := int(build.get("size", 1))
	if not Crafting.has_furniture(kind) or size < 5:
		return {}
	var entrance := str(build.get("entrance", ""))
	var facing := inward(entrance)
	var left := Vector2i(facing.y, -facing.x)
	var base := door_cell(build["cell"], size, entrance) + facing
	return {"bancada": base + left, "prateleiras": base - left}


static func has_furniture(build: Dictionary) -> bool:
	return bool(build.get("done", false)) and not furniture_cells(build).is_empty()


## O móvel ao alcance de quem está em "pos" e mais perto dele que a porta
## ("" se nenhum): "bancada" ou "prateleiras".
static func furniture_near(build: Dictionary, pos: Vector2) -> String:
	if not has_furniture(build):
		return ""
	var door := WorldGen.cell_center(door_cell(build["cell"], int(build["size"]), str(build["entrance"])))
	var best := ""
	var best_distance := minf(FURNITURE_REACH, pos.distance_to(door) - 0.001)
	var cells := furniture_cells(build)
	for name: String in cells:
		var distance := pos.distance_to(WorldGen.cell_center(cells[name]))
		if distance <= best_distance:
			best_distance = distance
			best = name
	return best


## Há uma oficina pronta com a bancada ao alcance de "pos"?
func bench_near(pos: Vector2) -> bool:
	for build: Dictionary in _builds.values():
		if furniture_near(build, pos) == "bancada":
			return true
	return false


## "A bancada fica à sua esquerda ao entrar e as prateleiras à direita."
static func furniture_hint(build: Dictionary) -> String:
	return "A bancada fica à sua esquerda ao entrar, e as prateleiras à direita."


## As paredes já estão de pé? Só depois da etapa das paredes (ou da obra pronta);
## antes, a obra é um canteiro por onde se anda e não bloqueia nada.
static func walls_up(build: Dictionary) -> bool:
	if bool(build.get("done", false)):
		return true
	if str(build.get("phase", "obra")) != "obra":
		return false
	var index := Crafting.walls_stage(str(build["kind"]))
	return index >= 0 and int(build["stage"]) > index


static func post_count(build: Dictionary) -> int:
	return 1 if int(build.get("size", 1)) <= 1 else POSTS


## A casa do canteiro "i" (0 noroeste, 1 nordeste, 2 sudeste, 3 sudoeste).
static func post_cell(build: Dictionary, i: int) -> Vector2i:
	var size := int(build.get("size", 1))
	if size <= 1:
		return build["cell"]
	var far := size - 1
	var offsets := [Vector2i(0, 0), Vector2i(far, 0), Vector2i(far, far), Vector2i(0, far)]
	return build["cell"] + offsets[i % POSTS]


## A parte da obra em que uma casa fica, dividindo o quadrado em 3 por 3:
## "noroeste", "norte", ..., "centro". "cell" é uma casa do mundo.
static func sector_name(build: Dictionary, cell: Vector2i) -> String:
	var size := maxi(1, int(build.get("size", 1)))
	var local: Vector2i = cell - (build["cell"] as Vector2i)
	var col := clampi(local.x * 3 / size, 0, 2)
	var row := clampi(local.y * 3 / size, 0, 2)
	return [["noroeste", "norte", "nordeste"], ["oeste", "centro", "leste"], ["sudoeste", "sul", "sudeste"]][row][col]


static func post_name(i: int) -> String:
	return ["noroeste", "nordeste", "sudeste", "sudoeste"][i % POSTS]


## Quantas batidas cabem ao canteiro "i" numa etapa de "work" batidas.
static func post_share(work: int, count: int, i: int) -> int:
	return work / count + (1 if i < work % count else 0)


## Distância de um ponto até a construção: ao centro da casa nas pequenas, à
## borda do quadrado nas grandes.
static func reach_distance(build: Dictionary, pos: Vector2) -> float:
	var size := int(build.get("size", 1))
	if size <= 1:
		return pos.distance_to(WorldGen.cell_center(build["cell"]))
	var low := Vector2(build["cell"])
	var closest := Vector2(clampf(pos.x, low.x, low.x + size), clampf(pos.y, low.y, low.y + size))
	return pos.distance_to(closest)


## O ponto da construção mais perto de "pos" (centro de uma casa do terreno).
static func nearest_point(build: Dictionary, pos: Vector2) -> Vector2:
	var best := WorldGen.cell_center(build["cell"])
	var best_distance := INF
	for cell: Vector2i in footprint_cells(build["cell"], int(build.get("size", 1))):
		var distance := WorldGen.cell_center(cell).distance_to(pos)
		if distance < best_distance:
			best_distance = distance
			best = WorldGen.cell_center(cell)
	return best


## As construções de uma região.
func in_region(region: Vector2i) -> Array:
	return _builds.values().filter(func(build: Dictionary): return build["region"] == region)


## Os povoados: marcos prontos que já receberam nome. São os "locais" do
## Caminheiro.
func settlements() -> Array:
	return _builds.values().filter(func(build: Dictionary):
		return build["kind"] == "marco" and build["done"] and not str(build["name"]).is_empty())


## Regiões que são povoados.
func marked_regions() -> Array:
	return settlements().map(func(build: Dictionary): return build["region"])


## A região tem uma fogueira pronta (acesa ou não)?
func has_fire(region: Vector2i) -> bool:
	for build: Dictionary in _builds.values():
		if build["region"] == region and build["done"] and Crafting.BUILDS[build["kind"]].get("fire", false):
			return true
	return false


## A região tem um marco pronto que ainda não recebeu nome?
func has_unnamed_marco(region: Vector2i) -> bool:
	for build: Dictionary in _builds.values():
		if build["region"] == region and build["kind"] == "marco" and build["done"] and str(build["name"]).is_empty():
			return true
	return false


## Por que este marco não pode receber um nome agora ("" = pode).
## "nao_marco", "em_obra", "ja_tem_nome", "sem_fogueira" (falta uma fogueira
## pronta na mesma região).
func naming_refusal(id: int) -> String:
	var build := get_build(id)
	if build.is_empty() or build["kind"] != "marco":
		return "nao_marco"
	if not build["done"]:
		return "em_obra"
	if not str(build["name"]).is_empty():
		return "ja_tem_nome"
	if not has_fire(build["region"]):
		return "sem_fogueira"
	return ""


func can_name(id: int) -> bool:
	return naming_refusal(id).is_empty()


## Já existe um povoado com este nome?
func name_taken(settlement_name: String) -> bool:
	for build: Dictionary in _builds.values():
		if str(build["name"]).to_lower() == settlement_name.to_lower():
			return true
	return false


## Dá nome ao povoado deste marco: um substantivo e um adjetivo, pelos
## índices, que precisam estar entre as opções sorteadas para ele
## (SettlementNames.options). Devolve { ok, reason, name }. Recusas: as de
## naming_refusal, "opcao" (fora das opções) e "repetido" (já há um povoado
## com esse nome; vem com "name").
func name_settlement(id: int, noun_index: int, adjective_index: int) -> Dictionary:
	var reason := naming_refusal(id)
	if not reason.is_empty():
		return {"ok": false, "reason": reason}
	var offered := SettlementNames.options(world.world_seed, id)
	if not offered["nouns"].has(noun_index) or not offered["adjectives"].has(adjective_index):
		return {"ok": false, "reason": "opcao"}
	var settlement_name := SettlementNames.compose(noun_index, adjective_index)
	if name_taken(settlement_name):
		return {"ok": false, "reason": "repetido", "name": settlement_name}
	_builds[id]["name"] = settlement_name
	return {"ok": true, "reason": "", "name": settlement_name}


func is_lit(id: int, at_time := -1.0) -> bool:
	var build := get_build(id)
	if build.is_empty():
		return false
	if at_time < 0.0:
		at_time = now()
	return float(build["burn_until"]) > at_time


## Segundos de lenha que a fogueira ainda tem (queimando ou guardada).
func fuel_left(id: int, at_time := -1.0) -> float:
	var build := get_build(id)
	if build.is_empty():
		return 0.0
	if at_time < 0.0:
		at_time = now()
	if is_lit(id, at_time):
		return float(build["burn_until"]) - at_time
	return float(build["fuel"])


## A etapa "index" desta construção, já no tamanho dela.
func stage_def(build: Dictionary, index := -1) -> Dictionary:
	return Crafting.stage_of(build["kind"], int(build["stage"]) if index < 0 else index, int(build.get("size", 1)))


## Os materiais que ainda faltam na etapa atual (item -> quantidade).
func stage_missing(id: int) -> Dictionary:
	var build := get_build(id)
	if build.is_empty() or build["done"] or str(build.get("phase", "obra")) != "obra":
		return {}
	var stage := stage_def(build)
	var out := {}
	for item: String in stage["materials"]:
		var left := int(stage["materials"][item]) - int(build["deposited"].get(item, 0))
		if left > 0:
			out[item] = left
	return out


func work_left(id: int) -> int:
	var build := get_build(id)
	if build.is_empty() or build["done"] or str(build.get("phase", "obra")) != "obra":
		return 0
	return int(stage_def(build)["work"]) - int(build["work"])


## Batidas que ainda faltam ao canteiro "post" na etapa atual.
func post_left(id: int, post: int) -> int:
	var build := get_build(id)
	if build.is_empty() or build["done"]:
		return 0
	var count := post_count(build)
	var share := post_share(int(stage_def(build)["work"]), count, post)
	return maxi(0, share - int((build["posts"] as Array)[post]))


## Segundos que a argila ainda tem para secar (0 = seca).
func dry_left(id: int, at_time := -1.0) -> float:
	var build := get_build(id)
	if build.is_empty():
		return 0.0
	if at_time < 0.0:
		at_time = now()
	return maxf(0.0, float(build.get("dry_until", 0.0)) - at_time)


## Fase da construção: "limpeza", "capina" ou "obra" (etapas; também depois de pronta).
func phase_of(id: int) -> String:
	return str(get_build(id).get("phase", "obra"))


## Alguma fogueira acesa na região (seca a argila na metade do tempo)?
func has_lit_fire(region: Vector2i, at_time := -1.0) -> bool:
	for build: Dictionary in _builds.values():
		if build["region"] == region and build["done"] and Crafting.BUILDS[build["kind"]].get("fire", false) \
				and is_lit(int(build["id"]), at_time):
			return true
	return false


## Há um povoado (marco com nome) nesta região?
func has_settlement(region: Vector2i) -> bool:
	for build: Dictionary in settlements():
		if build["region"] == region:
			return true
	return false


## O que a casa é para quem quer construir: FREE, CLEARABLE, WATER ou TAKEN.
## "region": só vale a casa que pertence a esta região. "ignore": id de uma
## obra cujo terreno não conta (ela mesma).
func cell_status(cell: Vector2i, region: Vector2i, ignore := -1) -> int:
	if not world.in_bounds(cell) or world.region_of(cell) != region:
		return TAKEN
	for dy in range(-SPACING, SPACING + 1):
		for dx in range(-SPACING, SPACING + 1):
			var other: int = _by_cell.get(cell + Vector2i(dx, dy), -1)
			if other != -1 and other != ignore:
				return TAKEN
	var thing := world.thing_at(cell)
	if WorldGen.WATER.has(thing):
		return WATER
	if Crafting.CLEAR_HITS.has(thing):
		return CLEARABLE
	if thing != WorldGen.Thing.NADA or not world.is_passable(cell):
		return TAKEN
	if WorldGen.cell_center(cell).distance_to(WorldGen.origin_point()) < ORIGIN_CLEARANCE:
		return TAKEN
	return FREE


## Por que não dá para começar uma construção pequena nesta casa ("" = dá).
## "lugar": a casa não está livre (água, trilha, recurso, Origem...);
## "perto": outra construção colada; "regiao": já há um marco nesta região.
func refusal(kind: String, cell: Vector2i) -> String:
	if not Crafting.BUILDS.has(kind) or Crafting.is_large(kind):
		return "desconhecida"
	if world.thing_at(cell) != WorldGen.Thing.NADA or not world.is_passable(cell):
		return "lugar"
	if WorldGen.cell_center(cell).distance_to(WorldGen.origin_point()) < ORIGIN_CLEARANCE:
		return "lugar"
	for dy in range(-SPACING, SPACING + 1):
		for dx in range(-SPACING, SPACING + 1):
			if _by_cell.has(cell + Vector2i(dx, dy)):
				return "perto"
	if Crafting.BUILDS[kind].get("one_per_region", false):
		var region := world.region_of(cell)
		for build: Dictionary in _builds.values():
			if build["kind"] == kind and build["region"] == region:
				return "regiao"
	return ""


## Começa uma construção pequena (vazia, na primeira etapa). Devolve { ok, reason, id }.
func start(kind: String, cell: Vector2i) -> Dictionary:
	var reason := refusal(kind, cell)
	if not reason.is_empty():
		return {"ok": false, "reason": reason}
	var id := _next_id
	_next_id += 1
	_add(_new_build(id, kind, cell, 1, ""))
	return {"ok": true, "reason": "", "id": id}


func _new_build(id: int, kind: String, cell: Vector2i, size: int, entrance: String) -> Dictionary:
	return {"id": id, "kind": kind, "cell": cell, "region": world.region_of(cell), "stage": 0,
		"deposited": {}, "work": 0, "done": false, "fuel": 0.0, "burn_until": 0.0, "sparks": 0, "ignited": false, "flint": 0,
		"name": "", "size": size, "entrance": entrance, "phase": "obra", "prep": {}, "removed": [],
		"posts": _zero_posts(size), "dry_until": 0.0, "slack": false, "door_open": true, "stock": {}}


static func _zero_posts(size: int) -> Array:
	var posts := []
	posts.resize(1 if size <= 1 else POSTS)
	posts.fill(0)
	return posts


## Por que não dá para começar uma construção grande com o canto noroeste em
## "origin" e lado "size" ("" = dá): "desconhecida", "tamanho", "regiao" (o
## terreno atravessa a divisa), "sem_povoado" (falta um marco com nome na
## região), "agua", "perto" (outra obra a menos de SPACING casas, trilha,
## recurso ou Origem no terreno), "entrada" (lado inválido).
func site_refusal(kind: String, origin: Vector2i, size: int, entrance: String) -> String:
	if not Crafting.is_large(kind):
		return "desconhecida"
	var limits: Dictionary = Crafting.BUILDS[kind]["size"]
	if size < int(limits["min"]) or size > int(limits["max"]):
		return "tamanho"
	if not ["norte", "sul", "leste", "oeste"].has(entrance):
		return "entrada"
	var region := world.region_of(origin)
	if Crafting.BUILDS[kind].get("settlement", false) and not has_settlement(region):
		return "sem_povoado"
	var water := false
	for cell: Vector2i in footprint_cells(origin, size):
		if world.region_of(cell) != region:
			return "regiao"
		match cell_status(cell, region):
			WATER:
				water = true
			TAKEN:
				return "perto"
	return "agua" if water else ""


## Começa uma construção grande. O terreno nasce na fase de limpeza (ou, se
## não há nada a arrancar, na de capina). Devolve { ok, reason, id }.
func start_site(kind: String, origin: Vector2i, size: int, entrance: String) -> Dictionary:
	var reason := site_refusal(kind, origin, size, entrance)
	if not reason.is_empty():
		return {"ok": false, "reason": reason}
	var id := _next_id
	_next_id += 1
	var build := _new_build(id, kind, origin, size, entrance)
	var prep := {}
	for cell: Vector2i in footprint_cells(origin, size):
		var thing := world.thing_at(cell)
		if Crafting.CLEAR_HITS.has(thing):
			prep[cell] = int(Crafting.CLEAR_HITS[thing])
	build["phase"] = "limpeza"
	build["prep"] = prep
	if prep.is_empty():
		_begin_weeding(build)
	_add(build)
	return {"ok": true, "reason": "", "id": id}


func _begin_weeding(build: Dictionary) -> void:
	var prep := {}
	for cell: Vector2i in footprint_cells(build["cell"], int(build["size"])):
		prep[cell] = Crafting.WEED_HITS
	build["phase"] = "capina"
	build["prep"] = prep


## Casas que ainda faltam na fase de preparo (casa -> golpes que faltam).
func prep_cells(id: int) -> Dictionary:
	var build := get_build(id)
	if build.is_empty():
		return {}
	return build["prep"]


## A casa de preparo mais perto de "pos" (de preferência à frente), até "reach"
## casas. Devolve { id, cell } ou {} se não há. "tool" é o que está nas mãos.
func prep_target(pos: Vector2, ahead: Vector2, reach: float, tool: String) -> Dictionary:
	var best := {}
	var best_score := INF
	for build: Dictionary in _builds.values():
		if build["done"] or str(build["phase"]) == "obra" or Crafting.PREP_TOOLS[build["phase"]] != tool:
			continue
		for cell: Vector2i in build["prep"]:
			var offset := WorldGen.cell_center(cell) - pos
			var distance := offset.length()
			if distance > reach:
				continue
			var score := distance - (0.6 if distance > 0.01 and ahead.dot(offset / distance) > 0.5 else 0.0)
			if score < best_score:
				best_score = score
				best = {"id": build["id"], "cell": cell}
	return best


## Um golpe de preparo na casa "cell" da obra "id", com a ferramenta "tool".
## Devolve { ok, reason, event, ... }:
##   "limpando" / "capinando": golpe dado ("left": golpes que faltam na casa);
##   "limpo" / "capinado": a casa ficou pronta ("thing": o que foi arrancado,
##   "cells_left": casas que faltam na fase);
##   "fase": acabou a fase ("next": "capina" ou "obra").
## Recusas: "desconhecida", "fase" (a obra não está em preparo), "ferramenta",
## "casa" (a casa não precisa de preparo).
func prep_hit(id: int, cell: Vector2i, tool: String) -> Dictionary:
	var build := get_build(id)
	if build.is_empty():
		return {"ok": false, "reason": "desconhecida"}
	var phase := str(build["phase"])
	if build["done"] or phase == "obra":
		return {"ok": false, "reason": "fase"}
	if Crafting.PREP_TOOLS[phase] != tool:
		return {"ok": false, "reason": "ferramenta", "tool": Crafting.PREP_TOOLS[phase]}
	var prep: Dictionary = build["prep"]
	if not prep.has(cell):
		return {"ok": false, "reason": "casa"}
	var thing := world.thing_at(cell)
	prep[cell] = int(prep[cell]) - 1
	if int(prep[cell]) > 0:
		return {"ok": true, "event": "limpando" if phase == "limpeza" else "capinando", "left": int(prep[cell]), "cell": cell}
	prep.erase(cell)
	if phase == "limpeza":
		build["removed"].append(cell)
		world.removed[cell] = true
	var result := {"ok": true, "event": "limpo" if phase == "limpeza" else "capinado", "thing": thing,
		"cell": cell, "cells_left": prep.size(), "cleared": phase == "limpeza"}
	if prep.is_empty():
		if phase == "limpeza":
			_begin_weeding(build)
			result["next"] = "capina"
		else:
			build["phase"] = "obra"
			build["prep"] = {}
			result["next"] = "obra"
		result["event"] = "fase"
	return result


## Um Espaço numa construção, com a bolsa de quem trabalha (que perde o que
## for depositado) e a posição dela (nas grandes, é o canteiro mais perto que
## recebe a batida). Devolve { ok, reason, event, ... }:
##   "deposito": entraram materiais ("deposited"), ainda podem faltar ("missing");
##   "trabalho": uma batida ("work_left" na etapa; nas grandes também "post",
##   o canteiro, e "post_left", o que falta a ele; "slow" se a argila ainda seca e a batida valeu menos);
##   "etapa": a etapa terminou ("next": nome da próxima; "dry": segundos de secagem, se houver);
##   "pronta": a construção terminou;
##   "abasteceu" / "alimentou": lenha na fogueira apagada / acesa ("item");
##   "faisca": uma batida de pedra ("sparks_left"); "acesa": pegou fogo.
## Recusas (ok = false): "faltam" (a bolsa não tem nada do que falta;
## "missing"), "pronta" (nada mais a fazer), "sem_lenha" (fogueira sem lenha
## e bolsa sem lenha), "cheia" (fogueira com lenha no máximo), "preparo" (a
## obra grande ainda está na limpeza ou na capina), "canto" (nenhum canteiro
## com trabalho a fazer ao alcance; "posts": os cantos que ainda têm).
func work(id: int, bag: Dictionary, at_time := -1.0, pos := Vector2(INF, INF)) -> Dictionary:
	var build := get_build(id)
	if build.is_empty():
		return {"ok": false, "reason": "desconhecida"}
	if at_time < 0.0:
		at_time = now()
	if build["done"]:
		if Crafting.BUILDS[build["kind"]].get("fire", false):
			return _tend_fire(build, bag, at_time)
		if int(build["size"]) > 1:
			var piece := furniture_near(build, pos) if pos.x != INF else ""
			if not piece.is_empty():
				return {"ok": false, "reason": "movel", "furniture": piece}
			return _use_door(build, pos)
		return {"ok": false, "reason": "pronta"}
	if str(build["phase"]) != "obra":
		return {"ok": false, "reason": "preparo", "phase": build["phase"]}
	var missing := stage_missing(id)
	if not missing.is_empty():
		var given := {}
		for item: String in missing:
			var amount := mini(int(missing[item]), int(bag.get(item, 0)))
			if amount <= 0:
				continue
			given[item] = amount
			build["deposited"][item] = int(build["deposited"].get(item, 0)) + amount
			bag[item] = int(bag[item]) - amount
			if int(bag[item]) <= 0:
				bag.erase(item)
		if given.is_empty():
			return {"ok": false, "reason": "faltam", "missing": missing}
		return {"ok": true, "event": "deposito", "deposited": given, "missing": stage_missing(id)}
	var post := _pick_post(build, id, pos)
	if post < 0:
		var open_posts := []
		for i in post_count(build):
			if post_left(id, i) > 0:
				open_posts.append(i)
		return {"ok": false, "reason": "canto", "posts": open_posts}
	var slow := false
	if float(build["dry_until"]) > at_time:
		# A argila ainda seca: uma batida sim, outra não.
		build["slack"] = not bool(build["slack"])
		if bool(build["slack"]):
			return {"ok": true, "event": "trabalho", "slow": true, "post": post, "post_left": post_left(id, post),
				"work_left": work_left(id), "counted": false}
		slow = true
	build["posts"][post] = int(build["posts"][post]) + 1
	build["work"] = int(build["work"]) + 1
	if work_left(id) > 0:
		return {"ok": true, "event": "trabalho", "slow": slow, "post": post, "post_left": post_left(id, post),
			"work_left": work_left(id), "counted": true}
	var finished := stage_def(build)
	build["stage"] = int(build["stage"]) + 1
	build["work"] = 0
	build["deposited"] = {}
	build["posts"] = _zero_posts(int(build["size"]))
	if build["stage"] < Crafting.stage_count(build["kind"]):
		var result := {"ok": true, "event": "etapa", "next": stage_def(build)["name"]}
		if int(build["size"]) > 1 and Crafting.walls_stage(build["kind"]) == int(build["stage"]) - 1:
			_register_walls(build)
			result["walls"] = true
		var dry := float(Crafting.BUILDS[build["kind"]]["stages"][int(build["stage"]) - 1].get("dry", 0.0))
		if dry > 0.0:
			if has_lit_fire(build["region"], at_time):
				dry *= 0.5
			build["dry_until"] = at_time + dry
			result["dry"] = dry
		return result
	build["done"] = true
	_register_walls(build)
	var done_result := {"ok": true, "event": "pronta"}
	if Crafting.has_furniture(build["kind"]):
		done_result["walls"] = true  # os móveis ocupam casas: quem estava nelas é levado para o lado
	if Crafting.BUILDS[build["kind"]].get("fire", false):
		# A lenha da última etapa fica como o primeiro combustível.
		var fuel := 0.0
		for item: String in finished["materials"]:
			fuel += float(Crafting.FUEL_SECONDS.get(item, 0.0)) * int(finished["materials"][item])
		build["fuel"] = minf(fuel, Crafting.MAX_FUEL)
	return done_result


## O canteiro que recebe a batida de quem está em "pos": o mais perto que
## ainda tem trabalho, dentro de POST_REACH. Nas pequenas, o único. -1 se nenhum.
## Sem posição (testes), o primeiro com trabalho.
func _pick_post(build: Dictionary, id: int, pos: Vector2) -> int:
	var best := -1
	var best_distance := INF
	for i in post_count(build):
		if post_left(id, i) <= 0:
			continue
		if post_count(build) == 1 or pos.x == INF:
			return i
		var distance := pos.distance_to(WorldGen.cell_center(post_cell(build, i)))
		if distance <= POST_REACH and distance < best_distance:
			best_distance = distance
			best = i
	return best


# --- Armazenamento ------------------------------------------------------------------

## Esta construção guarda itens?
static func stores(build: Dictionary) -> bool:
	return bool(build.get("done", false)) and Crafting.STORAGE.has(str(build.get("kind", "")))


## Quanto peso a construção guarda no total.
static func capacity(build: Dictionary) -> int:
	var size := int(build.get("size", 1))
	return int(Crafting.STORAGE.get(str(build["kind"]), {}).get("per_cell", 0)) * size * size


## Peso guardado agora.
static func stock_load(build: Dictionary) -> int:
	return Bag.weight_of_items(build.get("stock", {}))


## Esta construção aceita o item (pela categoria)?
static func accepts(build: Dictionary, item: String) -> bool:
	return Crafting.STORAGE.get(str(build["kind"]), {}).get("accepts", []).has(Bag.category_of(item))


## "Armazém, 12 de 128" (peso guardado e capacidade).
static func stock_label(build: Dictionary) -> String:
	return "%s, %d de %d" % [Crafting.build_title(build["kind"]), stock_load(build), capacity(build)]


## Guarda itens da bolsa "bag" (muda a bolsa). Devolve { ok, reason, item,
## amount }. reason: "desconhecida", "nao_guarda" (a construção não guarda
## nada), "nao_aceita" (categoria errada), "nao_tem", "cheio".
func store(id: int, bag: Dictionary, item: String, amount: int) -> Dictionary:
	var build := get_build(id)
	if build.is_empty():
		return {"ok": false, "reason": "desconhecida"}
	if not stores(build):
		return {"ok": false, "reason": "nao_guarda"}
	if not accepts(build, item):
		return {"ok": false, "reason": "nao_aceita", "item": item}
	var have := int(bag.get(item, 0))
	if have <= 0 or amount <= 0:
		return {"ok": false, "reason": "nao_tem", "item": item}
	var room := (capacity(build) - stock_load(build)) / maxi(1, Bag.weight_of(item))
	var moved := mini(mini(amount, have), room)
	if moved <= 0:
		return {"ok": false, "reason": "cheio", "item": item}
	bag[item] = have - moved
	if int(bag[item]) <= 0:
		bag.erase(item)
	build["stock"][item] = int(build["stock"].get(item, 0)) + moved
	return {"ok": true, "item": item, "amount": moved}


## Tira itens do estoque para a bolsa "bag", até onde cabe na carga. Devolve
## { ok, reason, item, amount }. reason: "desconhecida", "nao_guarda",
## "nao_tem" (não há isso lá), "carga" (a criatura não aguenta mais peso).
func fetch(id: int, bag: Dictionary, wielded: String, item: String, amount: int) -> Dictionary:
	var build := get_build(id)
	if build.is_empty():
		return {"ok": false, "reason": "desconhecida"}
	if not stores(build):
		return {"ok": false, "reason": "nao_guarda"}
	var have := int(build["stock"].get(item, 0))
	if have <= 0 or amount <= 0:
		return {"ok": false, "reason": "nao_tem", "item": item}
	var moved := mini(mini(amount, have), Bag.room_for(bag, wielded, item))
	if moved <= 0:
		return {"ok": false, "reason": "carga", "item": item}
	build["stock"][item] = have - moved
	if int(build["stock"][item]) <= 0:
		build["stock"].erase(item)
	bag[item] = int(bag.get(item, 0)) + moved
	return {"ok": true, "item": item, "amount": moved}


## Espaço perto da porta de uma construção grande pronta: abre ou fecha.
## Recusa "porta_longe" (com "side": o lado da porta) se está longe dela.
func _use_door(build: Dictionary, pos: Vector2) -> Dictionary:
	var door := WorldGen.cell_center(door_cell(build["cell"], int(build["size"]), str(build["entrance"])))
	if pos.x != INF and pos.distance_to(door) > DOOR_REACH:
		return {"ok": false, "reason": "porta_longe", "side": build["entrance"]}
	_unregister_walls(build)
	build["door_open"] = not bool(build["door_open"])
	_register_walls(build)
	return {"ok": true, "event": "porta", "open": build["door_open"], "walls": not build["door_open"]}


func _tend_fire(build: Dictionary, bag: Dictionary, at_time: float) -> Dictionary:
	var id: int = build["id"]
	var lit := is_lit(id, at_time)
	if lit or float(build["fuel"]) <= 0.0:
		var wood := ""
		for item: String in Crafting.FUEL_ORDER:
			if int(bag.get(item, 0)) > 0:
				wood = item
				break
		if wood.is_empty():
			return {"ok": false, "reason": "sem_lenha" if not lit else "sem_lenha_bolsa"}
		# Não aceita lenha que ia sobrar (mais da metade passando do máximo).
		if fuel_left(id, at_time) + float(Crafting.FUEL_SECONDS[wood]) * 0.5 > Crafting.MAX_FUEL:
			return {"ok": false, "reason": "cheia"}
		bag[wood] = int(bag[wood]) - 1
		if int(bag[wood]) <= 0:
			bag.erase(wood)
		var seconds: float = Crafting.FUEL_SECONDS[wood]
		if lit:
			build["burn_until"] = minf(float(build["burn_until"]) + seconds, at_time + Crafting.MAX_FUEL)
			return {"ok": true, "event": "alimentou", "item": wood}
		build["fuel"] = minf(float(build["fuel"]) + seconds, Crafting.MAX_FUEL)
		return {"ok": true, "event": "abasteceu", "item": wood}
	# A primeira vez usa o sílex que entrou na obra. Reacender (depois que o fogo
	# já pegou uma vez) pede lenha e um sílex dentro da fogueira: Espaço põe a
	# lenha, depois o sílex (que passa a fazer parte dela) e só então acende,
	# gastando esse sílex.
	var relight := bool(build.get("ignited", false))
	if relight and int(build.get("flint", 0)) <= 0:
		if int(bag.get("silex", 0)) <= 0:
			return {"ok": false, "reason": "sem_silex"}
		bag["silex"] = int(bag["silex"]) - 1
		if int(bag["silex"]) <= 0:
			bag.erase("silex")
		build["flint"] = 1
		return {"ok": true, "event": "silex"}
	build["sparks"] = int(build["sparks"]) + 1
	if int(build["sparks"]) < Crafting.SPARKS_TO_LIGHT:
		return {"ok": true, "event": "faisca", "sparks_left": Crafting.SPARKS_TO_LIGHT - int(build["sparks"])}
	build["sparks"] = 0
	build["flint"] = 0
	build["ignited"] = true
	build["burn_until"] = at_time + float(build["fuel"])
	build["fuel"] = 0.0
	return {"ok": true, "event": "acesa"}


## Fogueiras que apagaram desde a última vez (a lenha acabou). Devolve os ids.
func burn_out(at_time := -1.0) -> Array:
	if at_time < 0.0:
		at_time = now()
	var out := []
	for build: Dictionary in _builds.values():
		if float(build["burn_until"]) > 0.0 and float(build["burn_until"]) <= at_time:
			build["burn_until"] = 0.0
			build["sparks"] = 0
			out.append(build["id"])
	return out


## Obras cuja argila acabou de secar desde a última vez. Devolve os ids.
func dried(at_time := -1.0) -> Array:
	if at_time < 0.0:
		at_time = now()
	var out := []
	for build: Dictionary in _builds.values():
		var until := float(build.get("dry_until", 0.0))
		if until > 0.0 and until <= at_time:
			build["dry_until"] = 0.0
			build["slack"] = false
			out.append(build["id"])
	return out


# --- Rede e salvamento -----------------------------------------------------------

## Estado de uma construção para mandar pela rede: o tempo de fogo vai
## relativo, porque o relógio de cada máquina é diferente.
func info(id: int, at_time := -1.0) -> Dictionary:
	var build := get_build(id)
	if build.is_empty():
		return {}
	if at_time < 0.0:
		at_time = now()
	return {
		"id": id, "kind": build["kind"], "x": build["cell"].x, "y": build["cell"].y,
		"stage": build["stage"], "deposited": build["deposited"].duplicate(), "work": build["work"],
		"done": build["done"], "fuel": build["fuel"], "sparks": build["sparks"], "name": build["name"],
		"ignited": build["ignited"], "flint": build["flint"],
		"burn_left": maxf(0.0, float(build["burn_until"]) - at_time) if float(build["burn_until"]) > 0.0 else 0.0,
		"size": build["size"], "entrance": build["entrance"], "phase": build["phase"],
		"prep": _cells_to_list(build["prep"]), "removed": _cells_to_list(build["removed"]),
		"posts": build["posts"].duplicate(), "door_open": build["door_open"],
		"dry_left": maxf(0.0, float(build["dry_until"]) - at_time) if float(build["dry_until"]) > 0.0 else 0.0,
		"stock": build["stock"].duplicate(),
	}


## Cliente: aplica o que o servidor mandou sobre uma construção.
func apply_info(data: Dictionary, at_time := -1.0) -> void:
	if at_time < 0.0:
		at_time = now()
	var cell := Vector2i(int(data["x"]), int(data["y"]))
	var deposited := {}
	for item in data.get("deposited", {}):
		deposited[str(item)] = int(data["deposited"][item])
	var burn_left := float(data.get("burn_left", 0.0))
	var dry_left := float(data.get("dry_left", 0.0))
	_add(_fill({"id": int(data["id"]), "kind": str(data["kind"]), "cell": cell, "region": world.region_of(cell),
		"stage": int(data.get("stage", 0)), "deposited": deposited, "work": int(data.get("work", 0)),
		"done": bool(data.get("done", false)), "fuel": float(data.get("fuel", 0.0)),
		"burn_until": at_time + burn_left if burn_left > 0.0 else 0.0, "sparks": int(data.get("sparks", 0)),
		"ignited": bool(data.get("ignited", false)), "flint": int(data.get("flint", 0)),
		"name": str(data.get("name", ""))}, data, at_time + dry_left if dry_left > 0.0 else 0.0))


func snapshot(at_time := -1.0) -> Array:
	var out := []
	for id: int in _builds:
		out.append(info(id, at_time))
	return out


func apply_snapshot(data: Array, at_time := -1.0) -> void:
	for build: Dictionary in _builds.values():
		_unregister(build)
	_builds.clear()
	_by_cell.clear()
	for entry in data:
		if typeof(entry) == TYPE_DICTIONARY:
			apply_info(entry, at_time)


## Para o mundo.json: a hora em que a fogueira apaga vai absoluta, então o
## fogo continua queimando (e apaga) com o servidor desligado.
func to_save() -> Dictionary:
	var list := []
	for build: Dictionary in _builds.values():
		list.append({
			"id": build["id"], "kind": build["kind"], "x": build["cell"].x, "y": build["cell"].y,
			"stage": build["stage"], "deposited": build["deposited"], "work": build["work"],
			"done": build["done"], "fuel": build["fuel"], "burn_until": build["burn_until"],
			"sparks": build["sparks"], "name": build["name"], "ignited": build["ignited"], "flint": build["flint"],
			"size": build["size"], "entrance": build["entrance"], "phase": build["phase"],
			"prep": _cells_to_list(build["prep"]), "removed": _cells_to_list(build["removed"]),
			"posts": build["posts"], "dry_until": build["dry_until"], "door_open": build["door_open"],
			"stock": build["stock"],
		})
	return {"next_id": _next_id, "list": list}


func load_save(data: Dictionary) -> void:
	_next_id = maxi(1, int(data.get("next_id", 1)))
	for entry in data.get("list", []):
		if typeof(entry) != TYPE_DICTIONARY or not Crafting.BUILDS.has(str(entry.get("kind", ""))):
			continue
		var cell := Vector2i(int(entry["x"]), int(entry["y"]))
		var deposited := {}
		for item in entry.get("deposited", {}):
			deposited[str(item)] = int(entry["deposited"][item])
		_add(_fill({"id": int(entry["id"]), "kind": str(entry["kind"]), "cell": cell, "region": world.region_of(cell),
			"stage": int(entry.get("stage", 0)), "deposited": deposited, "work": int(entry.get("work", 0)),
			"done": bool(entry.get("done", false)), "fuel": float(entry.get("fuel", 0.0)),
			"burn_until": float(entry.get("burn_until", 0.0)), "sparks": int(entry.get("sparks", 0)),
			"ignited": bool(entry.get("ignited", false)), "flint": int(entry.get("flint", 0)),
			# Mundos antigos davam o nome ao começar o marco: em obra, ele some.
			"name": str(entry.get("name", "")) if bool(entry.get("done", false)) and str(entry["kind"]) == "marco" else ""},
			entry, float(entry.get("dry_until", 0.0))))
		_next_id = maxi(_next_id, int(entry["id"]) + 1)
	burn_out()


## Completa uma construção com os campos das grandes (tamanho, preparo,
## canteiros, secagem), vindos da rede ou do arquivo. Construções antigas, sem
## esses campos, são pequenas e já em obra.
func _fill(build: Dictionary, data: Dictionary, dry_until: float) -> Dictionary:
	var size := maxi(1, int(data.get("size", 1)))
	build["size"] = size
	build["entrance"] = str(data.get("entrance", ""))
	build["phase"] = str(data.get("phase", "obra"))
	var prep := {}
	for entry in data.get("prep", []):
		prep[Vector2i(int(entry[0]), int(entry[1]))] = int(entry[2])
	build["prep"] = prep
	var removed := []
	for entry in data.get("removed", []):
		removed.append(Vector2i(int(entry[0]), int(entry[1])))
	build["removed"] = removed
	var posts := _zero_posts(size)
	var given: Array = data.get("posts", [])
	for i in mini(posts.size(), given.size()):
		posts[i] = int(given[i])
	build["posts"] = posts
	build["dry_until"] = dry_until
	build["slack"] = false
	build["door_open"] = bool(data.get("door_open", true))
	var stock := {}
	for item in data.get("stock", {}):
		if int(data["stock"][item]) > 0:
			stock[str(item)] = int(data["stock"][item])
	build["stock"] = stock
	return build


## {Vector2i: n} ou [Vector2i] -> [[x, y, n]] / [[x, y]], para a rede e o arquivo.
static func _cells_to_list(cells) -> Array:
	var out := []
	if typeof(cells) == TYPE_DICTIONARY:
		for cell: Vector2i in cells:
			out.append([cell.x, cell.y, int(cells[cell])])
	else:
		for cell: Vector2i in cells:
			out.append([cell.x, cell.y])
	return out


func _add(build: Dictionary) -> void:
	var old: Dictionary = _builds.get(build["id"], {})
	if not old.is_empty():
		_unregister(old)
	_builds[build["id"]] = build
	for cell: Vector2i in footprint_cells(build["cell"], int(build["size"])):
		_by_cell[cell] = build["id"]
	for cell: Vector2i in build["removed"]:
		world.removed[cell] = true
	_register_walls(build)


func _register_walls(build: Dictionary) -> void:
	for cell: Vector2i in wall_cells(build):
		world.built[cell] = build["id"]


func _unregister_walls(build: Dictionary) -> void:
	for cell: Vector2i in footprint_cells(build["cell"], int(build["size"])):
		world.built.erase(cell)


func _unregister(build: Dictionary) -> void:
	for cell: Vector2i in footprint_cells(build["cell"], int(build["size"])):
		_by_cell.erase(cell)
		world.built.erase(cell)
	for cell: Vector2i in build["removed"]:
		world.removed.erase(cell)


# --- Fala -------------------------------------------------------------------------

## Nome para a fala e para o Caminheiro: "fogueira acesa", "marco em obra".
func spoken_name(id: int, at_time := -1.0) -> String:
	var build := get_build(id)
	if build.is_empty():
		return ""
	var text := Crafting.build_name(build["kind"])
	if not str(build.get("name", "")).is_empty():
		text += " " + build["name"]
	if not build["done"]:
		match str(build["phase"]):
			"limpeza":
				return text + ", obra em fase de limpeza"
			"capina":
				return text + ", obra em fase de capina"
		return text + " em obra"
	if Crafting.BUILDS[build["kind"]].get("fire", false):
		return text + (" acesa" if is_lit(id, at_time) else " apagada")
	return text


## "Marco Casa da Lua", "Fogueira": o tipo com maiúscula e o nome, se houver.
func title_of(id: int) -> String:
	var build := get_build(id)
	if build.is_empty():
		return ""
	var title := Crafting.build_title(build["kind"])
	if not str(build.get("name", "")).is_empty():
		title += " " + build["name"]
	return title


## O que dizer ao chegar perto ou ao perguntar: a etapa e o que falta.
func status_text(id: int, at_time := -1.0) -> String:
	var build := get_build(id)
	if build.is_empty():
		return ""
	var title := title_of(id)
	if not build["done"]:
		if str(build["phase"]) == "limpeza":
			return "%s em obra, fase de limpeza: %s. Empunhe o machado e golpeie com J." % [title, _prep_text(build)]
		if str(build["phase"]) == "capina":
			return "%s em obra, fase de capina: %s. Empunhe a enxada e golpeie com J." % [title, _prep_text(build)]
		var stage := stage_def(build)
		var missing := stage_missing(id)
		var step := "Etapa %d de %d, %s" % [int(build["stage"]) + 1, Crafting.stage_count(build["kind"]), stage["name"]]
		var drying := dry_left(id, at_time)
		var dry_note := " A argila ainda seca, faltam uns %s; trabalhar agora rende metade." % _minutes_text(drying) if drying > 0.0 else ""
		if not missing.is_empty():
			return "%s em obra. %s: %s.%s" % [title, step, Crafting.missing_text(missing), dry_note]
		var left := work_left(id)
		var text := "%s em obra. %s: falta%s %d batida%s." % [title, step, "" if left == 1 else "m", left, "" if left == 1 else "s"]
		if post_count(build) > 1:
			text += " Cada canto cuida da sua parte: " + _posts_text(id) + "."
		return text + dry_note
	if Crafting.BUILDS[build["kind"]].get("fire", false):
		var minutes := ceili(fuel_left(id, at_time) / 60.0)
		if is_lit(id, at_time):
			return "%s acesa, com lenha para uns %d minuto%s." % [title, minutes, "" if minutes == 1 else "s"]
		var needs_flint: bool = bool(build.get("ignited", false)) and int(build.get("flint", 0)) <= 0
		if float(build["fuel"]) > 0.0:
			if needs_flint:
				return "%s apagada, com lenha para uns %d minuto%s, mas sem sílex. Espaço põe um sílex da bolsa; depois bate as pedras para acender." % [title, minutes, "" if minutes == 1 else "s"]
			return "%s apagada, com lenha para uns %d minuto%s. Espaço bate as pedras para acender." % [title, minutes, "" if minutes == 1 else "s"]
		return "%s apagada e sem lenha%s. Espaço põe uma lenha." % [title, ", e vai precisar de um sílex" if needs_flint else ""]
	if int(build["size"]) > 1:
		var text := "%s pronto, %d por %d casas, com a porta ao %s, %s. Espaço perto da porta abre ou fecha." % [
			title, int(build["size"]), int(build["size"]), build["entrance"], "aberta" if build["door_open"] else "fechada"]
		if has_furniture(build):
			text += " %s Espaço junto da bancada abre as receitas; junto das prateleiras, o armazenamento: guardam %s, %s." % [
				furniture_hint(build), Crafting.STORAGE[build["kind"]]["label"], stock_label(build).trim_prefix(title + ", ")]
		elif stores(build):
			text += " Guarda %s: %s. Espaço longe da porta abre o armazenamento." % [
				Crafting.STORAGE[build["kind"]]["label"], stock_label(build).trim_prefix(title + ", ")]
		return text
	if build["kind"] == "marco":
		if not str(build["name"]).is_empty():
			return "Marco do povoado %s." % build["name"]
		if has_fire(build["region"]):
			return "Marco pronto. Espaço para dar nome ao povoado."
		return "Marco pronto. Com uma fogueira nesta região, o lugar vira um povoado."
	return "%s pronto." % title if Crafting.BUILDS[build["kind"]]["article"] == "o" else "%s pronta." % title


## "faltam 3 coisas a arrancar: 2 arbustos e 1 árvore" / "faltam 9 casas de grama".
func _prep_text(build: Dictionary) -> String:
	var prep: Dictionary = build["prep"]
	var by_sector := {}
	for cell: Vector2i in prep:
		var sector := sector_name(build, cell)
		if not by_sector.has(sector):
			by_sector[sector] = []
		by_sector[sector].append(cell)
	var sectors: Array = by_sector.keys()
	sectors.sort_custom(func(a: String, b: String) -> bool: return SECTORS.find(a) < SECTORS.find(b))
	var plural := "" if prep.size() == 1 else "s"
	if str(build["phase"]) == "capina":
		var parts: PackedStringArray = []
		for sector: String in sectors:
			parts.append("%d %s" % [by_sector[sector].size(), _sector_place(sector)])
		return "falta%s %d casa%s de grama: %s" % ["" if prep.size() == 1 else "m", prep.size(), plural, ", ".join(parts)]
	var names := {
		WorldGen.Thing.ARVORE: ["árvore", "árvores"], WorldGen.Thing.BAMBU: ["touceira de bambu", "touceiras de bambu"],
		WorldGen.Thing.ARBUSTO: ["arbusto", "arbustos"], WorldGen.Thing.ARBUSTO_FRUTAS: ["arbusto com frutas", "arbustos com frutas"],
	}
	var parts: PackedStringArray = []
	for sector: String in sectors:
		var counts := {}
		for cell: Vector2i in by_sector[sector]:
			var thing := world.thing_at(cell)
			counts[thing] = int(counts.get(thing, 0)) + 1
		var things: PackedStringArray = []
		for thing in counts:
			var pair: Array = names.get(thing, ["coisa", "coisas"])
			things.append("%d %s" % [counts[thing], pair[0] if counts[thing] == 1 else pair[1]])
		parts.append("%s: %s" % [sector, ", ".join(things)])
	return "falta%s %d coisa%s a arrancar. %s" % ["" if prep.size() == 1 else "m", prep.size(), plural, "; ".join(parts)]


## "no sudeste", "no centro" (a parte da obra, dita em lugar).
static func _sector_place(sector: String) -> String:
	return "no centro" if sector == "centro" else "no " + sector


## "noroeste 3, nordeste 0, sudeste 3, sudoeste 2": quantas batidas faltam em cada canto.
func _posts_text(id: int) -> String:
	var parts: PackedStringArray = []
	for i in post_count(get_build(id)):
		parts.append("%s %d" % [post_name(i), post_left(id, i)])
	return ", ".join(parts)


static func _minutes_text(seconds: float) -> String:
	if seconds < 90.0:
		return "%d segundos" % maxi(1, roundi(seconds / 5.0) * 5)
	var minutes := ceili(seconds / 60.0)
	return "%d minutos" % minutes
