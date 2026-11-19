extends SceneTree
## Testes do armazenamento: categorias, capacidade, armazém e abrigo.
## Rodar: godot --headless --path . --script res://tests/test_storage.gd

var _failures := 0


func _init() -> void:
	_test_categories()
	_test_store_and_fetch()
	_test_persistence()
	_test_owners()
	_test_shelter_sizes()
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
		builds.claim(int(other[0]["id"]), "Ana")
		_check(builds.store(int(other[0]["id"]), {"bambu": 1}, "bambu", 1, "Ana")["reason"] == "nao_aceita", "abrigo não guarda material")
		_check(Builds.capacity(other[0]) == 64, "armário do abrigo guarda 64")
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


func _test_owners() -> void:
	var state := WorldState.new(173)
	var builds := state.builds
	var small := _ready_build(state, "abrigo")  # 4x4: um dono
	_ready_build_at(state, "abrigo", 2)  # 4x4 em outro lugar
	var big_cell := WorldGen.cell_of(WorldGen.origin_point()) + Vector2i(30, 30)
	var big_build := builds._fill(builds._new_build(3, "abrigo", big_cell, 6, "sul"), {"size": 6, "entrance": "sul"}, 0.0)
	big_build["done"] = true
	builds._add(big_build)
	_check(Builds.owner_slots(builds.get_build(small)) == 1, "abrigo 4x4 tem um dono")
	_check(Builds.owner_slots(big_build) == 2, "abrigo grande tem dois donos")
	_check(builds.claim(small, "Ana")["ok"], "Ana vira dona")
	_check(builds.claim(small, "Ana")["reason"] == "ja_dono", "Ana não vira dona duas vezes")
	_check(builds.claim(small, "Bia")["reason"] == "lotada", "abrigo pequeno lotado")
	_check(builds.claim(2, "Ana")["reason"] == "ja_tem_outro", "uma criatura, um abrigo")
	_check(builds.claim(3, "Bia")["ok"] and builds.claim(3, "Caio")["ok"], "abrigo grande aceita dois")
	_check(builds.claim(3, "Dani")["reason"] == "lotada", "abrigo grande lota no terceiro")
	_check(builds.release(small, "Bia")["reason"] == "nao_dono", "quem não é dono não larga")
	_check(builds.release(small, "Ana")["ok"] and builds.claim(small, "Fred")["ok"], "vaga liberada vai a outro")
	_check(builds.claim(99, "X")["reason"] == "desconhecida", "abrigo inexistente")
	var fire := builds._fill(builds._new_build(4, "fogueira", big_cell + Vector2i(10, 0), 1, ""), {}, 0.0)
	fire["done"] = true
	builds._add(fire)
	_check(builds.claim(4, "Ana")["reason"] == "sem_dono", "fogueira não tem dono")
	# Persistência e rede
	var copy := Builds.new(state.world)
	copy.load_save(builds.to_save())
	_check(copy.get_build(3)["owners"] == ["Bia", "Caio"], "donos sobrevivem ao arquivo")
	var client := Builds.new(state.world)
	client.apply_info(builds.info(3))
	_check(Builds.is_owner(client.get_build(3), "Caio"), "donos chegam ao cliente")
	# Pelo estado: só lá dentro
	var id := 7
	state.add_player(id, "Eva")
	var inside_cell := Vector2i(big_cell) + Vector2i(2, 2)
	state.players[id]["pos"] = WorldGen.cell_center(Vector2i(big_cell) + Vector2i(-5, -5))
	_check(state.claim_build(id, 3)["reason"] == "fora", "não vira dono de fora")
	builds.release(3, "Bia")
	state.players[id]["pos"] = WorldGen.cell_center(inside_cell)
	_check(state.claim_build(id, 3)["ok"], "vira dono lá dentro")
	_check(Builds.is_owner(builds.get_build(3), "Eva"), "dono é a chave do nome")
	_check(state.release_build(id, 3)["ok"], "deixa de ser dono lá dentro")


func _shelter(state: WorldState, id: int, size: int) -> Dictionary:
	var cell := WorldGen.cell_of(WorldGen.origin_point()) + Vector2i(40 + id * 10, 40)
	var build := state.builds._fill(state.builds._new_build(id, "abrigo", cell, size, "sul"), {"size": size, "entrance": "sul"}, 0.0)
	build["done"] = true
	state.builds._add(build)
	return build


func _test_shelter_sizes() -> void:
	var state := WorldState.new(173)
	var builds := state.builds
	var expected := {3: [1, false], 4: [1, true], 5: [2, false], 6: [2, true]}
	for size: int in expected:
		var build := _shelter(state, size, size)
		_check(Builds.owner_slots(build) == expected[size][0], "abrigo %d: donos" % size)
		_check(Builds.can_store(build) == expected[size][1], "abrigo %d: armário" % size)
		builds.claim(size, "Ana%d" % size)
	_check(builds.store(3, {"bambu": 1}, "bambu", 1, "Ana3")["reason"] == "nao_guarda", "abrigo 3 não guarda")
	_check(builds.store(5, {"bambu": 1}, "bambu", 1, "Ana5")["reason"] == "nao_guarda", "abrigo 5 não guarda")
	_check(builds.store(4, {"bambu": 1}, "bambu", 1, "Intruso")["reason"] == "nao_dono", "só dono guarda")
	_check(builds.fetch(4, {}, "", "bambu", 1, "Intruso")["reason"] == "nao_dono", "só dono pega")
	# Armário pessoal: cada dono do abrigo 6 tem o seu, com a capacidade inteira.
	builds.claim(6, "Bia")
	var six := builds.get_build(6)
	six["lockers"]["Ana6"] = {"bambu": 3}
	_check(Builds.stock_load(six, "Ana6") == 3 * Bag.weight_of("bambu") and Builds.stock_load(six, "Bia") == 0, "armários separados")
	_check(Builds.capacity(six) == 64, "cada dono do 6 tem 64")
	var bag := {}
	_check(builds.fetch(6, bag, "", "bambu", 2, "Ana6")["ok"] and int(bag["bambu"]) == 2, "dono pega do armário")
	_check(builds.fetch(6, {}, "", "bambu", 1, "Bia")["reason"] == "nao_tem", "o armário de Bia está vazio")
	# Abrigo de 5 com sobra de antes: o dono ainda pega.
	var five := builds.get_build(5)
	five["lockers"]["Ana5"] = {"bambu": 1}
	_check(builds.fetch(5, {}, "", "bambu", 1, "Ana5")["ok"], "sobra do abrigo 5 pode ser pega")
	# Estoque comum antigo vai para o primeiro dono.
	var old := _shelter(state, 8, 4)
	old["stock"] = {"bambu": 2}
	builds.claim(8, "Caio")
	_check(Builds.stock_of(old, "Caio").get("bambu", 0) == 2 and old["stock"].is_empty(), "estoque antigo vira armário do dono")
	_check(builds.spoken_name(5) == "abrigo sem dono" or builds.spoken_name(5) == "abrigo de Ana5", "nome falado do abrigo de 5")
	_check(builds.spoken_name(6) == "abrigo de Ana6 e Bia", "abrigo de dois donos")
	builds.release(6, "Ana6")
	builds.release(6, "Bia")
	_check(builds.spoken_name(6) == "abrigo sem dono", "abrigo sem dono")
	builds.claim(6, "Bia")
	_check(builds.spoken_name(6) == "abrigo de Bia", "abrigo de um dono só")
	builds.claim(6, "Ana6")
	# Persistência
	var copy := Builds.new(state.world)
	copy.load_save(builds.to_save())
	_check(copy.get_build(6)["lockers"]["Ana6"]["bambu"] == 1, "armários sobrevivem ao arquivo")

