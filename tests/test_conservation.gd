extends SceneTree
## Testes da conservação: manto de fibra (calor), pote selado (comida que não
## estraga) e secador (fruta e cogumelo secos).
## Rodar: godot --headless --path . --script res://tests/test_conservation.gd

var _failures := 0


func _init() -> void:
	_test_cloak()
	_test_wear()
	_test_jar()
	_test_rack()
	if _failures == 0:
		print("OK: todos os testes passaram")
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FALHOU: " + message)


func _cold(extra := {}) -> Dictionary:
	var ctx := {"season": 2, "night": true, "biome": WorldGen.Biome.BOSQUE, "day_seconds": 1800.0}
	ctx.merge(extra, true)
	return ctx


func _test_cloak() -> void:
	# Sozinho, no frio, o manto segura o calor no teto dele.
	var bare := {"food": 100.0, "warmth": 100.0}
	var cloaked := {"food": 100.0, "warmth": 100.0}
	Body.step(bare, 1800.0 * 2.0, _cold())
	Body.step(cloaked, 1800.0 * 2.0, _cold({"cloak": true}))
	_check(bare["warmth"] == 0.0, "sem nada, o frio leva tudo")
	_check(absf(cloaked["warmth"] - Body.CLOAK_BONUS) < 0.5, "com o manto, para em %d: %f" % [Body.CLOAK_BONUS, cloaked["warmth"]])
	# Perde mais devagar.
	var a := {"food": 100.0, "warmth": 100.0}
	var b := {"food": 100.0, "warmth": 100.0}
	Body.step(a, 60.0, _cold())
	Body.step(b, 60.0, _cold({"cloak": true}))
	_check(b["warmth"] > a["warmth"], "o manto freia a perda")
	# Soma ao teto do abrigo.
	var shelter := {"food": 100.0, "warmth": 10.0}
	Body.step(shelter, 1800.0 * 3.0, _cold({"shelter": true, "cloak": true}))
	_check(absf(shelter["warmth"] - (Body.SHELTER_CAP + Body.CLOAK_BONUS)) < 0.5, "abrigo com manto: %f" % shelter["warmth"])
	var oven := {"food": 100.0, "warmth": 10.0}
	Body.step(oven, 1800.0 * 3.0, _cold({"shelter": true, "oven": true, "cloak": true}))
	_check(oven["warmth"] == Body.MAX, "forno e manto chegam a cheio: %f" % oven["warmth"])


func _test_wear() -> void:
	var state := WorldState.new(173)
	state.add_player(2, "Lua")
	var inv := state.inventory_of(2)
	_check(state.wear(2, "manto")["reason"] == "nao_tem", "sem manto na bolsa")
	inv["manto"] = 1
	_check(state.wear(2, "manto")["ok"], "veste")
	_check(state.worn_of(2) == "manto" and not inv.has("manto"), "o manto sai da bolsa")
	inv["manto"] = 1
	_check(state.wear(2, "manto")["reason"] == "ja_veste", "um manto de cada vez")
	_check(state.take_off(2)["ok"] and int(inv["manto"]) == 2, "tira e volta para a bolsa")
	state.wear(2, "manto")
	var loaded := WorldState.from_save(state.to_save())
	_check(str(loaded.worn.get("Lua", "")) == "manto", "o manto vestido é salvo")
	_check(Crafting.recipe("manto")["materials"].has("fibra") and not Crafting.recipe("manto")["materials"].has("pele"), "manto de fibra, sem pele")
	_check(Crafting.needs_bench("manto"), "o manto se faz na bancada da oficina")


func _test_jar() -> void:
	var state := WorldState.new(173)
	state.add_player(2, "Lua")
	var inv := state.inventory_of(2)
	inv["frutas_amora"] = 5
	_check(state.jar_store(2, "frutas_amora", 2)["reason"] == "sem_pote", "sem pote selado não guarda")
	inv["pote_selado"] = 1
	var lots := state.lots_of(2)
	Body.reconcile(lots, inv)
	# Envelhece as amoras um pouco antes de guardar.
	Body.age(lots, inv, 1.0)
	var stored := state.jar_store(2, "frutas_amora", 3)
	_check(stored["ok"] and int(stored["amount"]) == 3, "guarda 3 amoras")
	_check(int(inv["frutas_amora"]) == 2, "ficam 2 na bolsa")
	_check(int(state.jar_of(2).get("frutas_amora", 0)) == 3, "3 no pote")
	_check(state.jar_store(2, "pote_selado", 1)["reason"] == "nao_e_comida", "só comida")
	# Na bolsa, o tempo passa e as amoras estragam; no pote, não.
	Body.age(lots, inv, 5.0)
	_check(not inv.has("frutas_amora"), "as da bolsa estragaram")
	_check(int(state.jar_of(2).get("frutas_amora", 0)) == 3, "as do pote seguem lá")
	# Ao tirar, voltam com a idade que tinham (1 dia passado de 2).
	_check(state.jar_take(2, "frutas_amora", 3)["ok"], "tira as 3")
	var lot: Array = lots["frutas_amora"][0]
	_check(absf(float(lot[1]) - 1.0) < 0.01, "voltam com 1 dia de vida: %s" % [lot])
	Body.age(lots, inv, 1.5)
	_check(not inv.has("frutas_amora"), "e estragam no tempo que faltava")
	# Capacidade e largar o pote cheio.
	inv["broa"] = 20
	_check(int(state.jar_store(2, "broa", 20)["amount"]) == WorldState.JAR_CAPACITY, "cabem %d por pote" % WorldState.JAR_CAPACITY)
	_check(state.drop(2, "pote_selado", 1)["reason"] == "pote_cheio", "pote com comida não se larga")
	var loaded := WorldState.from_save(state.to_save())
	loaded.add_player(3, "Lua")
	_check(int(loaded.jar_of(3).get("broa", 0)) == WorldState.JAR_CAPACITY, "o pote é salvo")


func _test_rack() -> void:
	var state := WorldState.new(173)
	var builds := state.builds
	var cell := WorldGen.NO_CELL
	var origin := WorldGen.cell_of(WorldGen.center_point())
	for r in range(3, 60):
		for dx in range(-r, r + 1):
			var c := origin + Vector2i(dx, r)
			if cell == WorldGen.NO_CELL and builds.refusal("secador", c).is_empty() and builds.refusal("fogueira", c + Vector2i(3, 0)).is_empty():
				cell = c
		if cell != WorldGen.NO_CELL:
			break
	var id := int(builds.start("secador", cell)["id"])
	var bag := {"bambu": 4, "cipo": 2}
	var t := 1000.0
	for i in 10:
		builds.work(id, bag, t)
	_check(builds.get_build(id)["done"], "o secador fica pronto")
	bag = {"frutas_amora": 10, "cogumelo_pardo": 5, "raiz_batata": 2}
	_check(builds.hang(id, bag, "raiz_batata", 2, t)["reason"] == "nao_seca", "raiz não vai no varal")
	var hung := builds.hang(id, bag, "frutas_amora", 10, t)
	_check(hung["ok"] and float(hung["seconds"]) == Builds.DRY_SECONDS, "pendura 10 amoras, secam no tempo inteiro")
	_check(int(builds.hang(id, bag, "cogumelo_pardo", 5, t)["amount"]) == Builds.RACK_CAPACITY - 10, "o varal enche")
	_check(builds.gather_rack(id, bag, t + 10.0)["reason"] == "secando", "ainda secando")
	var got := builds.gather_rack(id, bag, t + Builds.DRY_SECONDS + 1.0)
	_check(got["ok"] and int(bag.get("fruta_seca", 0)) == 10 and int(bag.get("cogumelo_seco", 0)) == 2, "recolhe 10 frutas secas e 2 cogumelos secos: %s" % [bag])
	_check(Body.keeps("fruta_seca") > Body.keeps("frutas_amora") * 5.0, "a fruta seca dura muito mais")
	# Com fogueira acesa ao lado, metade do tempo.
	var fire := int(builds.start("fogueira", cell + Vector2i(3, 0))["id"])
	builds.get_build(fire)["done"] = true
	builds.get_build(fire)["burn_until"] = t + 5000.0
	var quick := builds.hang(id, bag, "cogumelo_pardo", 1, t)
	_check(float(quick["seconds"]) == Builds.DRY_SECONDS * 0.5, "perto do fogo seca na metade do tempo")
	# Salva e carrega com o que está pendurado.
	var copy := Builds.new(state.world)
	copy.load_save(builds.to_save())
	_check(Builds.rack_count(copy.get_build(id)) == 1, "o varal é salvo")
	var mirror := Builds.new(state.world)
	mirror.apply_info(builds.info(id, t), t)
	_check(Builds.rack_count(mirror.get_build(id)) == 1, "o varal vai pela rede")
	_check(builds.status_text(id, t).begins_with("Secador pronto"), "texto: " + builds.status_text(id, t))
