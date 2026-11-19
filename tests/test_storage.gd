extends SceneTree
## Testes do armazenamento: categorias, capacidade, armazém e abrigo.
## Rodar: godot --headless --path . --script res://tests/test_storage.gd

var _failures := 0


func _init() -> void:
	_test_categories()
	_test_store_and_fetch()
	_test_persistence()
	if _failures == 0:
		print("OK: todos os testes passaram")
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FALHOU: " + message)


func _ready_build(state: WorldState, kind: String) -> int:
	var cell := WorldGen.cell_of(WorldGen.origin_point()) + Vector2i(8, 8)
	var made := {}
	var id := -1
	if made.get("ok", false):
		id = int(made["id"])
	else:
		# Fora de um povoado a obra grande é recusada: monta a construção à mão.
		id = 1
		state.builds._add(state.builds._fill(state.builds._new_build(id, kind, cell, 4, "sul"), {"size": 4, "entrance": "sul"}, 0.0))
	var build := state.builds.get_build(id)
	build["done"] = true
	build["stage"] = Crafting.stage_count(kind)
	return id


func _ready_build_at(state: WorldState, kind: String, id: int) -> void:
	var cell := WorldGen.cell_of(WorldGen.origin_point()) + Vector2i(20, 20)
	var build := state.builds._fill(state.builds._new_build(id, kind, cell, 4, "sul"), {"size": 4, "entrance": "sul"}, 0.0)
	build["done"] = true
	state.builds._add(build)


func _test_categories() -> void:
	_check(Bag.category_of("pedra_grande") == "material", "pedra é material")
	_check(Bag.category_of("bambu") == "material", "bambu é material")
	_check(Bag.category_of("machado") == "ferramenta", "machado é ferramenta")
	_check(Bag.category_of("frutas") == "comida", "frutas são comida")
	_check(Crafting.BUILDS.has("armazem") and Crafting.is_large("armazem"), "o armazém é uma construção grande")
	_check("armazem" in Crafting.BUILD_ORDER, "o armazém aparece no menu")


func _test_store_and_fetch() -> void:
	var state := WorldState.new(173)
	var id := _ready_build(state, "armazem")
	var builds := state.builds
	var build := builds.get_build(id)
	_check(Builds.capacity(build) == 128, "armazém 4x4 guarda 128")
	var bag := {"pedra_grande": 3, "bambu": 5, "frutas": 4, "machado": 1}
	var result := builds.store(id, bag, "pedra_grande", 2)
	_check(result["ok"] and result["amount"] == 2 and bag["pedra_grande"] == 1, "guarda 2 pedras grandes")
	_check(int(build["stock"]["pedra_grande"]) == 2 and Builds.stock_load(build) == 12, "o estoque pesa 12")
	_check(builds.store(id, bag, "frutas", 1)["reason"] == "nao_aceita", "armazém não guarda comida")
	_check(builds.store(id, bag, "machado", 1)["reason"] == "nao_aceita", "armazém não guarda ferramenta")
	_check(builds.store(id, bag, "argila", 1)["reason"] == "nao_tem", "não guarda o que não tem")
	# Pede mais do que tem: guarda só o que há.
	result = builds.store(id, bag, "bambu", 99)
	_check(result["amount"] == 5 and not bag.has("bambu"), "guarda só o que há na bolsa")
	# Capacidade: enche com pedras grandes (6 cada).
	var big := {"pedra_grande": 100}
	result = builds.store(id, big, "pedra_grande", 100)
	_check(Builds.stock_load(build) <= Builds.capacity(build), "não passa da capacidade")
	_check(builds.store(id, big, "pedra_grande", 1)["reason"] == "cheio", "cheio recusa")
	# Pegar: respeita a carga.
	var empty := {}
	result = builds.fetch(id, empty, "", "pedra_grande", 100)
	_check(result["ok"] and result["amount"] == Bag.MAX_LOAD / Bag.weight_of("pedra_grande"), "pega só o que a carga aguenta")
	var full := {"pedra_grande": Bag.MAX_LOAD / 6}
	_check(builds.fetch(id, full, "", "pedra_grande", 1)["reason"] == "carga", "carga cheia recusa")
	_check(builds.fetch(id, {}, "", "argila", 1)["reason"] == "nao_tem", "pegar o que não há")
	# O abrigo só guarda roupas (ainda não existem).
	_ready_build_at(state, "abrigo", 2)
	var other := state.builds.all().filter(func(b): return b["kind"] == "abrigo")
	if not other.is_empty():
		_check(builds.store(int(other[0]["id"]), {"bambu": 1}, "bambu", 1)["reason"] == "nao_aceita", "abrigo não guarda material")
		_check(Builds.capacity(other[0]) == 64, "abrigo 4x4 guarda 64")
	# Obra em andamento não guarda.
	var cell := WorldGen.cell_of(WorldGen.origin_point()) + Vector2i(30, 30)
	var site := builds._new_build(77, "armazem", cell, 4, "sul")
	builds._add(builds._fill(site, {"size": 4, "entrance": "sul"}, 0.0))
	_check(builds.store(77, {"bambu": 1}, "bambu", 1)["reason"] == "nao_guarda", "obra não pronta não guarda")


func _test_persistence() -> void:
	var state := WorldState.new(173)
	var id := _ready_build(state, "armazem")
	var bag := {"bambu": 4, "argila": 2}
	state.builds.store(id, bag, "bambu", 3)
	state.builds.store(id, bag, "argila", 2)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(state.builds.to_save()))
	var copy := WorldState.new(173)
	copy.builds.load_save(saved)
	var build := copy.builds.get_build(id)
	_check(int(build["stock"].get("bambu", 0)) == 3 and int(build["stock"].get("argila", 0)) == 2, "o estoque volta do arquivo")
	var net := WorldState.new(173)
	net.builds.apply_info(state.builds.info(id))
	_check(int(net.builds.get_build(id)["stock"].get("bambu", 0)) == 3, "o estoque vai pela rede")
