extends SceneTree
## Testes das construções grandes: âncoras, preparo do terreno (limpeza e
## capina), canteiros nos cantos, secagem, salvamento e a enxada.
## Rodar: godot --headless --path . --script res://tests/test_site.gd

var _failures := 0


func _init() -> void:
	_test_planner()
	_test_refusals()
	_test_full_flow()
	_test_posts_and_drying()
	_test_persistence()
	_test_server_and_tools()
	_test_eject()
	if _failures == 0:
		print("OK: todos os testes passaram")
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FALHOU: " + message)


## Mundo com um povoado de verdade: marco com nome e uma fogueira prontos na
## região da Origem.
func _settled(state: WorldState = null) -> Dictionary:
	if state == null:
		state = WorldState.new(173)
	var builds := state.builds
	var origin_cell := WorldGen.cell_of(WorldGen.origin_point())
	var region := state.world.region_of(origin_cell)
	var spots := []
	for r in range(5, 14):
		for dx in range(-r, r + 1):
			var cell := origin_cell + Vector2i(dx, -r)
			if builds.refusal("marco", cell).is_empty() and state.world.region_of(cell) == region:
				spots.append(cell)
		if spots.size() >= 40:
			break
	var marco_cell: Vector2i = spots[0]
	var marco: int = builds.start("marco", marco_cell)["id"]
	builds.get_build(marco)["done"] = true
	builds.get_build(marco)["name"] = "Vale Calmo"
	var fire_cell := WorldGen.NO_CELL
	for cell: Vector2i in spots:
		if builds.refusal("fogueira", cell).is_empty():
			fire_cell = cell
			break
	var fire: int = builds.start("fogueira", fire_cell)["id"]
	builds.get_build(fire)["done"] = true
	return {"state": state, "region": region, "marco": marco, "fire": fire}


## A melhor âncora (a com maior quadrado livre) de qualquer quadrante.
func _best_anchor(builds: Builds, region: Vector2i) -> Dictionary:
	var best := {}
	var best_square := -1
	for quadrant: Dictionary in SitePlanner.quadrants(builds, region):
		for anchor: Dictionary in SitePlanner.quadrant_anchors(builds, region, quadrant):
			if int(anchor["square_loose"]) >= 4 and int(anchor["square"]) > best_square:
				best_square = int(anchor["square"])
				best = anchor
	return best


func _test_planner() -> void:
	var ctx := _settled()
	var builds: Builds = ctx["state"].builds
	var region: Vector2i = ctx["region"]
	var quadrants := SitePlanner.quadrants(builds, region)
	_check(quadrants.size() == 4, "a região tem 4 quadrantes")
	var names := quadrants.map(func(q): return q["id"])
	_check(names == ["nordeste", "noroeste", "sudeste", "sudoeste"], "ordem dos quadrantes")
	for quadrant: Dictionary in quadrants:
		_check(str(quadrant["text"]).begins_with(str(quadrant["name"])), "o texto do quadrante começa pelo nome")
		_check(quadrant["area_loose"].x * quadrant["area_loose"].y >= quadrant["area"].x * quadrant["area"].y,
			"com limpeza a área nunca é menor")
		if quadrant["water"].is_empty() and quadrant["clear"].is_empty():
			_check(str(quadrant["text"]).ends_with("nenhum obstáculo") or str(quadrant["text"]).ends_with("sem espaço para construir"),
				"sem obstáculos: " + quadrant["text"])
		elif not quadrant["water"].is_empty() and quadrant["clear"].is_empty():
			_check("construível" in quadrant["text"] or "sem espaço" in quadrant["text"], "com água e sem mata: construível")
		elif not quadrant["clear"].is_empty() and quadrant["fits"]:
			_check("com obstáculos a limpar" in quadrant["text"], "com mata: " + quadrant["text"])
	_check(SitePlanner.meters_text(6) == "9" and SitePlanner.meters_text(11) == "16,5", "metros: 6 casas = 9, 11 = 16,5")
	_check(SitePlanner.area_text(Vector2i(4, 3)) == "6 por 4,5 metros", "texto de área")
	var rect := SitePlanner.rect_for(Vector2i(10, 10), Vector2i(-1, 1), 4)
	_check(rect == Rect2i(7, 10, 4, 4), "o quadrado cresce na direção da âncora")
	_check(SitePlanner.rect_for(Vector2i(10, 10), Vector2i(1, -1), 4) == Rect2i(10, 7, 4, 4), "para nordeste")
	# Os quatro cantos de um quadrante ficam dentro da sua caixa.
	var box := SitePlanner.quadrant_box(region, "nordeste")
	_check(box.size == Vector2i(24, 24) and box.position.y == region.y * 48 - 24 and box.position.x == region.x * 48, "caixa do nordeste")
	var anchor := _best_anchor(builds, region)
	_check(not anchor.is_empty(), "existe ao menos uma âncora com 4x4 de espaço")
	var sizes := SitePlanner.sizes_for(anchor, Crafting.BUILDS["abrigo"]["size"])
	_check(sizes.size() >= 2 and int(sizes[0]["size"]) == 3, "tamanhos a partir de 3")
	_check(int(sizes[-1]["size"]) <= 6, "no máximo 6")
	# Âncoras ao redor de uma construção, com 2 casas para andar.
	var marco := builds.get_build(ctx["marco"])
	var around := SitePlanner.building_anchors(builds, marco)
	for entry: Dictionary in around:
		var placed := SitePlanner.rect_for(entry["corner"], entry["dir"], 3)
		var gap := maxi(maxi(marco["cell"].x - placed.end.x + 1, placed.position.x - marco["cell"].x), maxi(marco["cell"].y - placed.end.y + 1, placed.position.y - marco["cell"].y))
		_check(gap >= Builds.SPACING + 1, "ao redor do marco ficam ao menos %d casas livres" % Builds.SPACING)
		_check("do marco" in entry["text"], "o texto cita o marco: " + entry["text"])


func _test_refusals() -> void:
	var state := WorldState.new(173)
	var builds := state.builds
	var origin_cell := WorldGen.cell_of(WorldGen.origin_point())
	var region := state.world.region_of(origin_cell)
	var anchor := _best_anchor(builds, region)  # sem povoado ainda: as âncoras existem, a obra não
	var rect := SitePlanner.rect_for(anchor["corner"], anchor["dir"], 4)
	_check(builds.site_refusal("abrigo", rect.position, 4, "sul") == "sem_povoado", "sem povoado, sem obra grande")
	var ctx := _settled(state)
	anchor = _best_anchor(builds, region)
	rect = SitePlanner.rect_for(anchor["corner"], anchor["dir"], 4)
	_check(builds.site_refusal("abrigo", rect.position, 4, "sul") == "", "com povoado, o terreno escolhido serve")
	_check(builds.site_refusal("abrigo", rect.position, 2, "sul") == "tamanho", "2 é pequeno demais")
	_check(builds.site_refusal("abrigo", rect.position, 7, "sul") == "tamanho", "7 é grande demais")
	_check(builds.site_refusal("abrigo", rect.position, 4, "cima") == "entrada", "porta inválida")
	_check(builds.site_refusal("marco", rect.position, 4, "sul") == "desconhecida", "marco não é obra grande")
	var far := region + Vector2i(30, 30)
	_check(builds.site_refusal("abrigo", far * WorldGen.REGION_SIZE, 4, "sul") == "sem_povoado", "região sem povoado")
	# O marco e a fogueira não deixam construir colado.
	var marco := builds.get_build(ctx["marco"])
	_check(builds.site_refusal("abrigo", marco["cell"] + Vector2i(1, 1), 4, "sul") == "perto", "colado no marco não serve")


func _free_site(builds: Builds, region: Vector2i, size: int) -> Rect2i:
	var anchor := _best_anchor(builds, region)
	return SitePlanner.rect_for(anchor["corner"], anchor["dir"], size)


func _test_full_flow() -> void:
	var ctx := _settled()
	var state: WorldState = ctx["state"]
	var builds := state.builds
	var world := state.world
	var rect := _free_site(builds, ctx["region"], 4)
	var started := builds.start_site("abrigo", rect.position, 4, "sul")
	_check(started["ok"], "começa o abrigo 4x4")
	var id: int = started["id"]
	var build := builds.get_build(id)
	_check(build["size"] == 4 and build["entrance"] == "sul", "tamanho e porta guardados")
	_check(builds.phase_of(id) in ["limpeza", "capina"], "começa pelo preparo")
	_check(builds.spoken_name(id).begins_with("abrigo, obra em fase de "), "o nome diz a fase: " + builds.spoken_name(id))
	_check(world.is_passable(rect.position), "no preparo o terreno ainda é passável")
	# Limpeza: cada árvore, arbusto ou bambu do terreno pede golpes de machado.
	var targets: Array = (build["prep"] as Dictionary).keys() if builds.phase_of(id) == "limpeza" else []
	var wrong := builds.prep_hit(id, rect.position, "enxada") if builds.phase_of(id) == "limpeza" else {"reason": "ferramenta"}
	_check(wrong["reason"] == "ferramenta", "a enxada não limpa")
	for cell: Vector2i in targets:
		var thing := world.thing_at(cell)
		var need := int(Crafting.CLEAR_HITS[thing])
		var result := {}
		for i in need:
			result = builds.prep_hit(id, cell, "machado")
			_check(result["ok"], "golpe de limpeza")
		_check(result["event"] in ["limpo", "fase"] and result["cleared"], "a casa fica limpa depois de %d golpes" % need)
		_check(world.thing_at(cell) == WorldGen.Thing.NADA, "o que foi arrancado some do mundo")
	_check(builds.phase_of(id) == "capina", "acabou a limpeza: capina")
	_check(builds.prep_cells(id).size() == 16, "a capina cobre as 16 casas")
	var hit := builds.prep_hit(id, rect.position, "machado")
	_check(not hit["ok"] and hit["reason"] == "ferramenta" and hit["tool"] == "enxada", "na capina, só a enxada")
	var last := {}
	for cell: Vector2i in Builds.footprint_cells(rect.position, 4):
		for i in Crafting.WEED_HITS:
			last = builds.prep_hit(id, cell, "enxada")
	_check(last["event"] == "fase" and last["next"] == "obra", "a última casa capinada abre as etapas")
	_check(builds.phase_of(id) == "obra", "fase de obra")
	# Enquanto as paredes não estão de pé, a obra é só um canteiro: não bloqueia.
	var door := Builds.door_cell(rect.position, 4, "sul")
	_check(door == rect.position + Vector2i(2, 3), "porta ao sul, no meio")
	for cell: Vector2i in Builds.footprint_cells(rect.position, 4):
		_check(world.is_passable(cell), "antes das paredes, tudo passa")
	_check(builds.at(rect.position + Vector2i(1, 1))["id"] == id, "o interior pertence à obra")
	# Etapas: chão, esteios e paredes; as paredes sobem ao fim da terceira.
	var bag := {}
	for item: String in Crafting.total_materials("abrigo", 4):
		bag[item] = 999
	var now_s := 1000.0
	var raised := false
	for stage_index in 3:
		for i in 200:
			now_s += 300.0
			var r := builds.work(id, bag, now_s)
			if r.get("event", "") == "etapa":
				raised = r.get("walls", false)
				break
		if stage_index < 2:
			_check(world.is_passable(rect.position), "esteios e chão: ainda sem paredes")
	_check(raised, "o fim da etapa das paredes avisa que elas subiram")
	_check(world.is_passable(door), "a porta deixa passar")
	_check(world.is_passable(rect.position + Vector2i(1, 1)) and world.is_passable(rect.position + Vector2i(2, 2)), "dentro dá para andar")
	_check(not world.is_passable(rect.position) and not world.is_passable(rect.position + Vector2i(3, 0)), "o canto é parede")
	_check(not world.is_passable(rect.position + Vector2i(0, 2)), "a lateral é parede")
	var walls := 0
	for cell: Vector2i in Builds.footprint_cells(rect.position, 4):
		if not world.is_passable(cell):
			walls += 1
	_check(walls == 11, "4x4 tem 12 casas de borda, menos a porta: 11 (deu %d)" % walls)
	# Outra obra não cabe colada.
	_check(builds.site_refusal("abrigo", rect.position + Vector2i(5, 0), 3, "sul") == "perto", "colado no abrigo não serve")
	# Materiais e etapas escalam com o tamanho.
	var small := Crafting.stage_of("abrigo", 2, 3)
	var ref := Crafting.stage_of("abrigo", 2, 4)
	_check(int(small["materials"]["bambu"]) < int(ref["materials"]["bambu"]) and int(ref["materials"]["bambu"]) == 16, "3x3 pede menos bambu que 4x4")
	_check(int(Crafting.stage_of("abrigo", 2, 6)["materials"]["bambu"]) == 36, "6x6 pede 36 bambus")


func _ready_site(size := 4) -> Dictionary:
	var ctx := _settled()
	var builds: Builds = ctx["state"].builds
	var rect := _free_site(builds, ctx["region"], size)
	var id: int = builds.start_site("abrigo", rect.position, size, "sul")["id"]
	var build := builds.get_build(id)
	# Pula o preparo (já testado): terreno pronto.
	for cell: Vector2i in (build["prep"] as Dictionary).keys():
		while builds.phase_of(id) == "limpeza" and (build["prep"] as Dictionary).has(cell):
			builds.prep_hit(id, cell, "machado")
	for cell: Vector2i in Builds.footprint_cells(rect.position, size):
		while builds.phase_of(id) == "capina" and (build["prep"] as Dictionary).has(cell):
			builds.prep_hit(id, cell, "enxada")
	ctx["id"] = id
	ctx["rect"] = rect
	return ctx


func _test_posts_and_drying() -> void:
	var ctx := _ready_site()
	var builds: Builds = ctx["state"].builds
	var id: int = ctx["id"]
	var rect: Rect2i = ctx["rect"]
	var build := builds.get_build(id)
	_check(builds.phase_of(id) == "obra", "terreno pronto")
	var bag := {"pedra_grande": 6, "argila": 8}
	var result := builds.work(id, bag, 1000.0, Vector2(INF, INF))
	_check(result["event"] == "deposito" and builds.stage_missing(id).is_empty(), "o chão: materiais entram de uma vez")
	_check(builds.work_left(id) == 10, "o chão pede 10 batidas")
	# 10 batidas em 4 cantos: 3, 3, 2, 2.
	_check(Builds.post_share(10, 4, 0) == 3 and Builds.post_share(10, 4, 2) == 2, "divisão das batidas: 3, 3, 2, 2")
	var far := Vector2(rect.position) + Vector2(20, 20)
	result = builds.work(id, bag, 1000.0, far)
	_check(not result["ok"] and result["reason"] == "canto", "longe dos cantos, a batida não vale")
	_check((result["posts"] as Array).size() == 4, "todos os cantos têm trabalho")
	var nw := WorldGen.cell_center(Builds.post_cell(build, 0))
	var ne := WorldGen.cell_center(Builds.post_cell(build, 1))
	_check(Builds.post_cell(build, 0) == rect.position and Builds.post_cell(build, 2) == rect.position + Vector2i(3, 3), "cantos nos extremos")
	for i in 3:
		result = builds.work(id, bag, 1000.0, nw)
		_check(result["ok"] and result["post"] == 0, "canto noroeste trabalha")
	result = builds.work(id, bag, 1000.0, nw)
	_check(not result["ok"] and result["reason"] == "canto", "o canto noroeste já fez a sua parte")
	_check(builds.post_left(id, 0) == 0 and builds.post_left(id, 1) == 3, "restam 3 batidas no nordeste")
	for i in 3:
		builds.work(id, bag, 1000.0, ne)
	var se := WorldGen.cell_center(Builds.post_cell(build, 2))
	var sw := WorldGen.cell_center(Builds.post_cell(build, 3))
	for i in 2:
		builds.work(id, bag, 1000.0, se)
	for i in 1:
		result = builds.work(id, bag, 1000.0, sw)
	_check(result["event"] == "trabalho" and builds.work_left(id) == 1, "falta uma batida")
	result = builds.work(id, bag, 1000.0, sw)
	_check(result["event"] == "etapa" and result["dry"] == 240.0, "o chão termina e a argila começa a secar (240 s)")
	_check(builds.dry_left(id, 1000.0) == 240.0, "dry_left")
	_check(builds.status_text(id, 1000.0).contains("seca"), "a fala avisa que a argila seca")
	# Durante a secagem, cada batida vale metade: uma sim, outra não.
	bag = {"madeira": 6}
	builds.work(id, bag, 1001.0, nw)  # depósito
	var counted := 0
	for i in 6:
		result = builds.work(id, bag, 1002.0 + i, nw)
		if result["ok"] and result["counted"]:
			counted += 1
	_check(counted == 3, "durante a secagem só metade das batidas conta (%d de 6)" % counted)
	_check(builds.dried(1100.0).is_empty(), "ainda secando")
	_check(builds.dried(1241.0) == [id], "depois de 240 s a argila seca")
	_check(builds.dry_left(id, 1300.0) == 0.0, "seca")
	# Com fogueira acesa na região, a secagem cai pela metade.
	var ctx2 := _ready_site()
	var builds2: Builds = ctx2["state"].builds
	var fire: int = ctx2["fire"]
	builds2.get_build(fire)["burn_until"] = 5000.0
	var id2: int = ctx2["id"]
	var bag2 := {"pedra_grande": 6, "argila": 8}
	builds2.work(id2, bag2, 1000.0)
	var fin := {}
	for i in 10:
		fin = builds2.work(id2, bag2, 1000.0)
	_check(fin["event"] == "etapa" and fin["dry"] == 120.0, "fogueira acesa: secagem em 120 s")
	# Uma obra sozinha ainda termina (nada proibitivo): sem posição, qualquer canto.
	var ctx3 := _ready_site(3)
	var b3: Builds = ctx3["state"].builds
	var id3: int = ctx3["id"]
	var bag3 := {}
	for item: String in Crafting.total_materials("abrigo", 3):
		bag3[item] = 999
	var guard := 0
	var done := false
	while not done and guard < 2000:
		guard += 1
		var r := b3.work(id3, bag3, 1000.0 + float(guard) * 10.0, Vector2(INF, INF))
		done = r.get("event", "") == "pronta"
	_check(done, "dá para terminar o abrigo sozinho (%d ações)" % guard)
	_check(b3.get_build(id3)["done"], "abrigo pronto")
	_check(b3.status_text(id3).begins_with("Abrigo pronto"), "texto de pronto: " + b3.status_text(id3))
	# A porta abre e fecha com Espaço, perto dela.
	var build3 := b3.get_build(id3)
	var door3 := Builds.door_cell(build3["cell"], 3, "sul")
	var door_pos := WorldGen.cell_center(door3) + Vector2(0, 1.0)
	_check(ctx3["state"].world.is_passable(door3), "pronto: a porta começa aberta")
	var far3 := b3.work(id3, {}, 9000.0, door_pos + Vector2(30, 30))
	_check(not far3["ok"] and far3["reason"] == "porta_longe" and far3["side"] == "sul", "longe da porta, Espaço não faz nada")
	var closed := b3.work(id3, {}, 9000.0, door_pos)
	_check(closed["ok"] and closed["event"] == "porta" and not closed["open"] and closed["walls"], "Espaço perto fecha a porta")
	_check(not ctx3["state"].world.is_passable(door3), "porta fechada bloqueia")
	_check(b3.status_text(id3).contains("fechada"), "e a fala diz")
	var reopened := b3.work(id3, {}, 9000.0, door_pos)
	_check(reopened["open"] and ctx3["state"].world.is_passable(door3), "Espaço de novo abre")
	b3.work(id3, {}, 9000.0, door_pos)  # fecha de novo para o teste de salvamento
	var saved3 := JSON.parse_string(JSON.stringify(b3.to_save())) as Dictionary
	var copy3 := Builds.new(WorldGen.new(173))
	copy3.load_save(saved3)
	_check(not copy3.get_build(id3)["door_open"] and not copy3.world.is_passable(door3), "a porta fechada sobrevive ao salvamento")


func _test_persistence() -> void:
	var ctx := _ready_site()
	var builds: Builds = ctx["state"].builds
	var id: int = ctx["id"]
	var rect: Rect2i = ctx["rect"]
	var bag := {"pedra_grande": 6, "argila": 8}
	builds.work(id, bag, 1000.0)
	builds.work(id, bag, 1000.0, WorldGen.cell_center(rect.position))
	var saved := JSON.parse_string(JSON.stringify(builds.to_save())) as Dictionary
	var world := WorldGen.new(173)
	var copy := Builds.new(world)
	copy.load_save(saved)
	var a := builds.get_build(id)
	var b := copy.get_build(id)
	_check(not b.is_empty() and b["size"] == 4 and b["entrance"] == "sul" and b["phase"] == "obra", "salvar e carregar mantém tamanho, porta e fase")
	_check(b["posts"] == a["posts"], "e os canteiros")
	_check(world.removed.size() == ctx["state"].world.removed.size(), "e o que foi arrancado")
	_check(world.is_passable(rect.position), "e o canteiro ainda não bloqueia no mundo carregado")
	# Espelho da rede.
	var mirror_world := WorldGen.new(173)
	var mirror := Builds.new(mirror_world)
	mirror.apply_snapshot(builds.snapshot())
	var m := mirror.get_build(id)
	_check(m["size"] == 4 and m["posts"] == a["posts"] and m["phase"] == "obra", "o espelho do cliente recebe o estado")
	_check(mirror_world.removed.size() == ctx["state"].world.removed.size(), "o espelho também sabe o que foi arrancado")
	mirror.apply_snapshot([])
	_check(mirror_world.removed.is_empty() and mirror_world.built.is_empty(), "limpar o espelho devolve o mundo")


func _test_server_and_tools() -> void:
	var ctx := _settled()
	var state: WorldState = ctx["state"]
	var builds := state.builds
	state.add_player(2, "Lua")
	var rect := _free_site(builds, ctx["region"], 4)
	state.players[2]["pos"] = WorldGen.cell_center(rect.position + Vector2i(1, 1))
	var started := state.start_site(2, "abrigo", rect.position, 4, "oeste")
	_check(started["ok"], "o servidor começa o abrigo para quem está na região")
	var id: int = started["id"]
	state.players[2]["pos"] = Vector2(rect.position) + Vector2(2000, 2000)
	_check(state.start_site(2, "abrigo", rect.position, 4, "oeste")["reason"] == "regiao_longe", "longe da região não marca terreno")
	state.players[2]["pos"] = WorldGen.cell_center(rect.position)
	# Prep: sem machado nas mãos, recusa; com machado, golpeia.
	var cells: Array = (builds.get_build(id)["prep"] as Dictionary).keys()
	var cell: Vector2i = cells[0]
	state._last_strike.erase(2)
	state.players[2]["pos"] = WorldGen.cell_center(cell) + Vector2(0.5, 0)
	var refused := state.prep_build(2, id, cell)
	_check(not refused["ok"] and refused["reason"] == "ferramenta", "sem a ferramenta nas mãos, o servidor recusa")
	state.equip(2, "machado")
	if builds.phase_of(id) == "limpeza":
		var thing := world_thing(state, cell)
		var dropped := {}
		for i in 40:
			state._last_strike.erase(2)
			var result := state.prep_build(2, id, cell)
			if result.get("cleared", false):
				dropped = result.get("drop", {})
				break
		_check(not dropped.is_empty() or thing == WorldGen.Thing.NADA, "o que é arrancado cai no chão (%s)" % str(dropped))
		_check(state.ground.items_at(cell) == dropped, "o monte no chão tem o que caiu")
	# A colheita comum não mexe no terreno de uma obra.
	var tree_cell := WorldGen.NO_CELL
	for c: Vector2i in Builds.footprint_cells(rect.position, 4):
		if Harvest.needs_tool(state.world.thing_at(c)):
			tree_cell = c
	if tree_cell != WorldGen.NO_CELL:
		state.players[2]["pos"] = WorldGen.cell_center(tree_cell)
		state._last_strike.erase(2)
		_check(not state.strike(2, tree_cell)["ok"], "golpe comum numa árvore do terreno não vale")
	# A enxada: fabricar pede bambu, pedra média e pedra pequena.
	var inv := state.inventory_of(2)
	var missing := state.craft(2, "enxada")
	_check(not missing["ok"] and missing["reason"] == "faltam", "sem materiais não fabrica a enxada")
	inv["bambu"] = 1
	inv["pedra_media"] = 1
	inv["pedra_pequena"] = 1
	var crafted := state.craft(2, "enxada")
	_check(crafted["ok"] and int(inv.get("enxada", 0)) == 1 and not inv.has("bambu"), "fabrica a enxada")
	_check(Bag.can_wield("enxada") and state.equip(2, "enxada")["ok"] and state.wielding(2) == "enxada", "e empunha")
	_check(state.craft(2, "lanca")["reason"] == "faltam", "armas continuam como antes")
	_check(Crafting.is_tool_recipe("enxada") and not Crafting.is_tool_recipe("lanca"), "enxada é ferramenta, lança é arma")
	var steps := 0
	for step: Dictionary in Crafting.TOOLS["enxada"]["steps"]:
		steps += int(step["knocks"])
	_check(steps >= 12, "a enxada dá trabalho: %d batidas" % steps)


func _test_eject() -> void:
	var ctx := _ready_site()
	var state: WorldState = ctx["state"]
	var builds := state.builds
	var id: int = ctx["id"]
	var rect: Rect2i = ctx["rect"]
	state.add_player(2, "Lua")
	state.players[2]["pos"] = WorldGen.cell_center(rect.position)  # em cima de um canto
	_check(state.world.is_free(state.players[2]["pos"]), "antes das paredes, o canto é livre")
	var bag := {}
	for item: String in Crafting.total_materials("abrigo", 4):
		bag[item] = 999
	var now_s := 1000.0
	var raised := false
	for i in 1000:
		now_s += 300.0
		var r := builds.work(id, bag, now_s)
		if r.get("walls", false):
			raised = true
			break
	_check(raised, "as paredes sobem")
	_check(not state.world.is_free(state.players[2]["pos"]), "agora o canto bloqueia")
	var moved := state.eject_from_walls(id)
	_check(moved.size() == 1 and moved[0][0] == 2, "a criatura presa é tirada")
	_check(state.world.is_free(state.players[2]["pos"]), "e fica num ponto livre")


func world_thing(state: WorldState, cell: Vector2i) -> int:
	return state.world.thing_at(cell)
