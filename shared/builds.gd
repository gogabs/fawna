class_name Builds
extends RefCounted
## Construções no mundo (marcos, fogueiras): onde estão, em que etapa, o que
## já foi depositado e, nas fogueiras, se estão acesas e quanta lenha têm.
## As receitas ficam em Crafting.
##
## O servidor tem a cópia que vale (dentro do WorldState, salva em
## mundo.json como "builds"); cada cliente guarda um espelho, atualizado pelo
## servidor, para saber o que soa, o que a fala diz e para onde o Caminheiro
## leva. Toda construção ocupa uma casa e não deixa passar (WorldGen.built).
##
## Ciclo de uma construção:
##   iniciada -> em cada etapa: materiais (Espaço deposita) -> trabalho
##   (Espaço bate) -> próxima etapa ... -> pronta.
## Fogueira pronta:
##   apagada com lenha -> batidas de pedra (faíscas) -> acesa -> queima a
##   lenha com o tempo -> apagada. Espaço com ela acesa (ou sem lenha) põe
##   mais uma lenha.

## Até onde (em casas, Chebyshev) não dá para começar outra construção.
const SPACING := 1
## Distância mínima do ponto de chegada da Origem, para não fechar a entrada.
const ORIGIN_CLEARANCE := 2.5

var world: WorldGen
## id -> { "id", "kind", "cell": Vector2i, "region": Vector2i, "stage": int,
## "deposited": {item: qtd}, "work": int, "done": bool, "fuel": s guardados
## (apagada), "burn_until": hora Unix em que apaga (0 = apagada), "sparks": int }
var _builds := {}
var _by_cell := {}  # Vector2i -> id
var _next_id := 1


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


## Regiões que têm um marco pronto: são os "locais" do Caminheiro.
func marked_regions() -> Array:
	var regions := []
	for build: Dictionary in _builds.values():
		if build["kind"] == "marco" and build["done"]:
			regions.append(build["region"])
	return regions


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


## Os materiais que ainda faltam na etapa atual (item -> quantidade).
func stage_missing(id: int) -> Dictionary:
	var build := get_build(id)
	if build.is_empty() or build["done"]:
		return {}
	var stage: Dictionary = Crafting.BUILDS[build["kind"]]["stages"][build["stage"]]
	var out := {}
	for item: String in stage["materials"]:
		var left := int(stage["materials"][item]) - int(build["deposited"].get(item, 0))
		if left > 0:
			out[item] = left
	return out


func work_left(id: int) -> int:
	var build := get_build(id)
	if build.is_empty() or build["done"]:
		return 0
	var stage: Dictionary = Crafting.BUILDS[build["kind"]]["stages"][build["stage"]]
	return int(stage["work"]) - int(build["work"])


## Por que não dá para começar uma construção nesta casa ("" = dá).
## "lugar": a casa não está livre (água, trilha, recurso, Origem...);
## "perto": outra construção colada; "regiao": já há um marco nesta região.
func refusal(kind: String, cell: Vector2i) -> String:
	if not Crafting.BUILDS.has(kind):
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


## Começa uma construção (vazia, na primeira etapa). Devolve { ok, reason, id }.
func start(kind: String, cell: Vector2i) -> Dictionary:
	var reason := refusal(kind, cell)
	if not reason.is_empty():
		return {"ok": false, "reason": reason}
	var id := _next_id
	_next_id += 1
	_add({"id": id, "kind": kind, "cell": cell, "region": world.region_of(cell), "stage": 0,
		"deposited": {}, "work": 0, "done": false, "fuel": 0.0, "burn_until": 0.0, "sparks": 0})
	return {"ok": true, "reason": "", "id": id}


## Um Espaço numa construção, com a bolsa de quem trabalha (que perde o que
## for depositado). Devolve { ok, reason, event, ... }:
##   "deposito": entraram materiais ("deposited"), ainda podem faltar ("missing");
##   "trabalho": uma batida ("work_left" na etapa);
##   "etapa": a etapa terminou ("next": nome da próxima);
##   "pronta": a construção terminou;
##   "abasteceu" / "alimentou": lenha na fogueira apagada / acesa ("item");
##   "faisca": uma batida de pedra ("sparks_left"); "acesa": pegou fogo.
## Recusas (ok = false): "faltam" (a bolsa não tem nada do que falta;
## "missing"), "pronta" (nada mais a fazer), "sem_lenha" (fogueira sem lenha
## e bolsa sem lenha), "cheia" (fogueira com lenha no máximo).
func work(id: int, bag: Dictionary, at_time := -1.0) -> Dictionary:
	var build := get_build(id)
	if build.is_empty():
		return {"ok": false, "reason": "desconhecida"}
	if at_time < 0.0:
		at_time = now()
	if build["done"]:
		if Crafting.BUILDS[build["kind"]].get("fire", false):
			return _tend_fire(build, bag, at_time)
		return {"ok": false, "reason": "pronta"}
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
	build["work"] = int(build["work"]) + 1
	if work_left(id) > 0:
		return {"ok": true, "event": "trabalho", "work_left": work_left(id)}
	var stages: Array = Crafting.BUILDS[build["kind"]]["stages"]
	var finished: Dictionary = stages[build["stage"]]
	build["stage"] = int(build["stage"]) + 1
	build["work"] = 0
	build["deposited"] = {}
	if build["stage"] < stages.size():
		return {"ok": true, "event": "etapa", "next": stages[build["stage"]]["name"]}
	build["done"] = true
	if Crafting.BUILDS[build["kind"]].get("fire", false):
		# A lenha da última etapa fica como o primeiro combustível.
		var fuel := 0.0
		for item: String in finished["materials"]:
			fuel += float(Crafting.FUEL_SECONDS.get(item, 0.0)) * int(finished["materials"][item])
		build["fuel"] = minf(fuel, Crafting.MAX_FUEL)
	return {"ok": true, "event": "pronta"}


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
	build["sparks"] = int(build["sparks"]) + 1
	if int(build["sparks"]) < Crafting.SPARKS_TO_LIGHT:
		return {"ok": true, "event": "faisca", "sparks_left": Crafting.SPARKS_TO_LIGHT - int(build["sparks"])}
	build["sparks"] = 0
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
		"done": build["done"], "fuel": build["fuel"], "sparks": build["sparks"],
		"burn_left": maxf(0.0, float(build["burn_until"]) - at_time) if float(build["burn_until"]) > 0.0 else 0.0,
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
	_add({"id": int(data["id"]), "kind": str(data["kind"]), "cell": cell, "region": world.region_of(cell),
		"stage": int(data.get("stage", 0)), "deposited": deposited, "work": int(data.get("work", 0)),
		"done": bool(data.get("done", false)), "fuel": float(data.get("fuel", 0.0)),
		"burn_until": at_time + burn_left if burn_left > 0.0 else 0.0, "sparks": int(data.get("sparks", 0))})


func snapshot(at_time := -1.0) -> Array:
	var out := []
	for id: int in _builds:
		out.append(info(id, at_time))
	return out


func apply_snapshot(data: Array, at_time := -1.0) -> void:
	for cell in _by_cell:
		world.built.erase(cell)
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
			"sparks": build["sparks"],
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
		_add({"id": int(entry["id"]), "kind": str(entry["kind"]), "cell": cell, "region": world.region_of(cell),
			"stage": int(entry.get("stage", 0)), "deposited": deposited, "work": int(entry.get("work", 0)),
			"done": bool(entry.get("done", false)), "fuel": float(entry.get("fuel", 0.0)),
			"burn_until": float(entry.get("burn_until", 0.0)), "sparks": int(entry.get("sparks", 0))})
		_next_id = maxi(_next_id, int(entry["id"]) + 1)
	burn_out()


func _add(build: Dictionary) -> void:
	var old: Dictionary = _builds.get(build["id"], {})
	if not old.is_empty():
		_by_cell.erase(old["cell"])
		world.built.erase(old["cell"])
	_builds[build["id"]] = build
	_by_cell[build["cell"]] = build["id"]
	world.built[build["cell"]] = build["id"]


# --- Fala -------------------------------------------------------------------------

## Nome para a fala e para o Caminheiro: "fogueira acesa", "marco em obra".
func spoken_name(id: int, at_time := -1.0) -> String:
	var build := get_build(id)
	if build.is_empty():
		return ""
	var text := Crafting.build_name(build["kind"])
	if not build["done"]:
		return text + " em obra"
	if Crafting.BUILDS[build["kind"]].get("fire", false):
		return text + (" acesa" if is_lit(id, at_time) else " apagada")
	return text


## O que dizer ao chegar perto ou ao perguntar: a etapa e o que falta.
func status_text(id: int, at_time := -1.0) -> String:
	var build := get_build(id)
	if build.is_empty():
		return ""
	var title := Crafting.build_title(build["kind"])
	if not build["done"]:
		var stages: Array = Crafting.BUILDS[build["kind"]]["stages"]
		var stage: Dictionary = stages[build["stage"]]
		var missing := stage_missing(id)
		var step := "Etapa %d de %d, %s" % [int(build["stage"]) + 1, stages.size(), stage["name"]]
		if not missing.is_empty():
			return "%s em obra. %s: %s." % [title, step, Crafting.missing_text(missing)]
		var left := work_left(id)
		return "%s em obra. %s: falta%s %d batida%s." % [title, step, "" if left == 1 else "m", left, "" if left == 1 else "s"]
	if Crafting.BUILDS[build["kind"]].get("fire", false):
		var minutes := ceili(fuel_left(id, at_time) / 60.0)
		if is_lit(id, at_time):
			return "%s acesa, com lenha para uns %d minuto%s." % [title, minutes, "" if minutes == 1 else "s"]
		if float(build["fuel"]) > 0.0:
			return "%s apagada, com lenha para uns %d minuto%s. Espaço bate as pedras para acender." % [title, minutes, "" if minutes == 1 else "s"]
		return "%s apagada e sem lenha. Espaço põe uma lenha." % title
	return "%s pronto." % title if Crafting.BUILDS[build["kind"]]["article"] == "o" else "%s pronta." % title
