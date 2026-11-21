extends SceneTree
## Testes rápidos da geração do mundo e das frases do narrador.
## Rodar: godot --headless --path . --script res://tests/test_world.gd

var _failures := 0


func _init() -> void:
	_test_same_seed_same_world()
	_test_spawn_is_free()
	_test_has_both_biomes()
	_test_narrator_direction()
	_test_world_state_moves()
	_test_collision()
	_test_compass()
	_test_regions_and_trails()
	_test_straight_bridges()
	_test_clear_wide_trails()
	_test_biomes_and_borders()
	_test_route_around_sea()
	_test_collect()
	_test_save_roundtrip()
	if _failures == 0:
		print("OK: todos os testes passaram")
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FALHOU: " + message)


func _test_same_seed_same_world() -> void:
	var a := WorldGen.new(42)
	var b := WorldGen.new(42)
	var c := WorldGen.new(43)
	var differs := false
	for y in range(-40, 40):
		for x in range(-40, 40):
			var cell := Vector2i(x, y)
			_check(a.thing_at(cell) == b.thing_at(cell), "mesma semente deveria gerar a mesma coisa em %s" % cell)
			_check(a.biome_at(cell) == b.biome_at(cell), "mesma semente deveria gerar o mesmo bioma em %s" % cell)
			if a.thing_at(cell) != c.thing_at(cell):
				differs = true
	_check(differs, "sementes diferentes deveriam gerar mundos diferentes")


func _test_spawn_is_free() -> void:
	for world_seed in range(20):
		var state := WorldState.new(world_seed)
		var seen := {}
		for id in range(1, 6):
			var pos := state.add_player(id, "J%d" % id)
			_check(state.world.is_free(pos), "o ponto de entrada deveria ser livre (semente %d)" % world_seed)
			_check(not seen.has(pos), "cada jogador deveria nascer num lugar diferente (semente %d)" % world_seed)
			seen[pos] = true


func _test_has_both_biomes() -> void:
	var seen := {}
	var world := WorldGen.new(7)
	for y in range(-40, 40):
		for x in range(-40, 40):
			seen[world.biome_at(Vector2i(x, y))] = true
	_check(seen.size() >= 2, "o mapa deveria ter mais de um bioma")


func _test_narrator_direction() -> void:
	_check(Narrator.direction(Vector2i(1, -2)) == "2 ao norte e 1 a leste", "direção norte/leste")
	_check(Narrator.direction(Vector2i(-3, 0)) == "3 a oeste", "direção oeste")
	_check(Narrator.direction(Vector2i.ZERO) == "aqui", "direção zero")


func _test_world_state_moves() -> void:
	var state := WorldState.new(42)
	var pos := state.add_player(10, "Lua")
	_check(state.world.is_free(pos), "o ponto de entrada deveria ser livre")
	_check(pos.distance_to(WorldGen.center_point()) < 2.0, "entra perto do centro do mundo")
	var t := 100000
	var result := state.move_to(10, pos + Vector2(6, 0), t)
	_check(not result["ok"] and result["pos"] == pos, "teletransporte deveria ser recusado")
	result = state.move_to(99, pos, t)
	_check(not result["ok"], "jogador desconhecido não deveria andar")
	result = state.move_to(10, pos + Vector2(0, -0.15), t + 100)
	_check(result["ok"], "andar um pouquinho deveria funcionar")


func _test_collision() -> void:
	var world := WorldGen.new(42)
	var bamboo := WorldGen.NO_CELL
	for y in range(-80, 80):
		for x in range(-80, 80):
			if bamboo == WorldGen.NO_CELL and world.thing_at(Vector2i(x, y)) == WorldGen.Thing.BAMBU:
				bamboo = Vector2i(x, y)
	_check(bamboo != WorldGen.NO_CELL, "deveria haver uma touceira de bambu")
	_check(not world.is_free(WorldGen.cell_center(bamboo)), "não dá para ficar dentro do bambu")
	_check(world.blocker_at(WorldGen.cell_center(bamboo)) == bamboo, "o obstáculo é o bambu")
	_check(not world.is_free(Vector2(WorldGen.WORLD_LIMIT + 1.1, 5.5)), "o limite do mundo bloqueia")
	_check(world.is_free(WorldGen.center_point()), "o centro do mundo é livre")
	_check(WorldGen.cell_of(Vector2(3.99, 4.0)) == Vector2i(3, 4), "casa de um ponto")


func _test_compass() -> void:
	_check(Compass.forward(0).is_equal_approx(Vector2(0, -1)), "norte é y negativo")
	_check(Compass.forward(2).is_equal_approx(Vector2(1, 0)), "leste é x positivo")
	_check(Compass.right(0).is_equal_approx(Vector2(1, 0)), "olhando para o norte, a direita é leste")
	_check(Compass.name_of(-1) == "noroeste", "girar à esquerda do norte dá noroeste")
	_check(Compass.relative(Vector2(0, -3), 0) == "à frente", "à frente")
	_check(Compass.relative(Vector2(0, -3), 2) == "à esquerda", "olhando para leste, o norte fica à esquerda")
	_check(Compass.relative(Vector2(2, 2), 0) == "atrás e à direita", "sudeste olhando para o norte")
	_check(Compass.relative(Vector2(-1, 0), 4) == "à direita", "olhando para o sul, o oeste fica à direita")
	_check(Compass.describe(Vector2(0, -2), 0) == "à frente, 3 metros", "descreve em metros")
	_check(Sounds.compass_kind(0) == "norte" and Sounds.compass_kind(4) == "sul", "cliques de norte e sul")
	_check(Sounds.compass_kind(2) == Sounds.compass_kind(6), "leste e oeste soam igual")
	_check(Sounds.compass_kind(1) == "colateral" and Sounds.compass_kind(7) == "colateral", "colaterais abafados")


func _test_regions_and_trails() -> void:
	var world := WorldGen.new(42)
	_check(world.region_biome(Vector2i.ZERO) == WorldGen.Biome.PRADARIA, "o centro do mundo fica numa pradaria")
	# Regiões são grandes: casas vizinhas quase sempre têm o mesmo bioma.
	var same := 0
	var total := 0
	for y in range(-60, 60, 3):
		for x in range(-60, 60, 3):
			total += 1
			if world.biome_at(Vector2i(x, y)) == world.biome_at(Vector2i(x + 1, y)):
				same += 1
	_check(same > total * 0.9, "biomas deveriam vir em regiões grandes")
	# Longe do centro também existe mundo (sem bordas), e é sempre o mesmo.
	var far := Vector2i(1500, -2200)
	_check(world.thing_at(far) == WorldGen.new(42).thing_at(far), "mundo distante também é fixo pela semente")
	# O centro do mundo é ponto de encontro de trilhas: deve haver trilha logo ao lado.
	var near_origin := world.nearest_trail(WorldGen.center_point(), 6)
	_check(near_origin != WorldGen.NO_CELL, "deveria sair uma trilha do centro")
	# Seguindo a reta até o ponto de encontro vizinho, quase tudo é trilha
	# (ela serpenteia um pouco em volta da reta).
	var a := world.region_landmark(Vector2i.ZERO)
	var b := world.region_landmark(Vector2i.RIGHT)
	var on_trail := 0
	var samples := 40
	for i in samples:
		var p := a.lerp(b, (i + 0.5) / samples)
		if world.nearest_trail(p, 3) != WorldGen.NO_CELL:
			on_trail += 1
	_check(on_trail >= samples * 0.9, "deveria haver trilha ligando o centro à região vizinha (%d/%d)" % [on_trail, samples])
	# Ponte em vez de água no meio da trilha: trilhas nunca bloqueiam.
	for y in range(-80, 80):
		for x in range(-80, 80):
			var cell := Vector2i(x, y)
			if world.thing_at(cell) == WorldGen.Thing.PONTE or world.thing_at(cell) == WorldGen.Thing.TRILHA:
				_check(world.is_passable(cell), "trilha e ponte são passáveis")
				return


func _test_straight_bridges() -> void:
	var world := WorldGen.new(7)
	var bridges := 0
	var orthogonal := 0
	for ry in range(-3, 3):
		for rx in range(-3, 3):
			for d: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
				if not world.has_trail(Vector2i(rx, ry), Vector2i(rx, ry) + d):
					continue  # o mar não tem trilhas
				var line := world.trail_line(Vector2i(rx, ry), Vector2i(rx, ry) + d)
				for i in line.size() - 1:
					var a: Vector2 = line[i]
					var b: Vector2 = line[i + 1]
					# Sobre a água a ponte é um trecho reto e ortogonal
					# (norte-sul ou leste-oeste), nunca na diagonal.
					if a.distance_to(b) > WorldGen.TRAIL_STEP * 1.5 and (world._is_water_at(WorldGen.cell_of(a)) or world._is_water_at(WorldGen.cell_of(b)) or world._is_water_at(WorldGen.cell_of(a.lerp(b, 0.5)))):
						_check(is_equal_approx(a.x, b.x) or is_equal_approx(a.y, b.y), "ponte na diagonal de %s a %s" % [a, b])
						orthogonal += 1
					if a.distance_to(b) > WorldGen.TRAIL_STEP * 1.5:
						bridges += 1
					# Seguir a linha da trilha nunca esbarra em nada.
					var steps := maxi(1, ceili(a.distance_to(b) / 0.25))
					for k in steps:
						var p := a.lerp(b, float(k) / steps)
						if not world.is_free(p):
							_check(false, "a linha da trilha esbarra em algo em %s" % p)
							return
	_check(bridges > 0, "deveria haver alguma ponte perto do centro")
	_check(orthogonal > 0, "deveria haver alguma ponte ortogonal")
	# A linha é a mesma nos dois sentidos.
	var there := world.trail_line(Vector2i.ZERO, Vector2i.RIGHT)
	var back := world.trail_line(Vector2i.RIGHT, Vector2i.ZERO)
	_check(there[0] == back[back.size() - 1] and back[0] == there[there.size() - 1], "trilha igual nos dois sentidos")


## Trilhas largas e limpas: a até 0,8 casa da linha, para os dois lados, é
## sempre trilha, e nada (bambu, arbusto, argila) nasce em cima nem na
## beira. E elas curvam pouco: a linha nunca vira de repente.
func _test_clear_wide_trails() -> void:
	for world_seed in [7, 42]:
		var world := WorldGen.new(world_seed)
		var resources := [WorldGen.Thing.BAMBU, WorldGen.Thing.ARBUSTO, WorldGen.Thing.ARBUSTO_FRUTAS, WorldGen.Thing.ARGILA]
		var checked := 0
		for ry in range(-2, 2):
			for rx in range(-2, 2):
				for d: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
					if not world.has_trail(Vector2i(rx, ry), Vector2i(rx, ry) + d):
						continue
					var line := world.trail_line(Vector2i(rx, ry), Vector2i(rx, ry) + d)
					for i in range(1, line.size() - 1):
						var p: Vector2 = line[i]
						var dir: Vector2 = (line[i + 1] - line[i - 1]).normalized()
						# Curva suave: entre pontos vizinhos, a direção muda pouco.
						# (As quinas das pontes ortogonais ficam de fora.)
						var bridge_corner: bool = is_equal_approx(line[i].x, line[i - 1].x) or is_equal_approx(line[i].y, line[i - 1].y) or is_equal_approx(line[i].x, line[i + 1].x) or is_equal_approx(line[i].y, line[i + 1].y)
						if not bridge_corner and line[i].distance_to(line[i - 1]) < WorldGen.TRAIL_STEP * 1.5 and line[i + 1].distance_to(line[i]) < WorldGen.TRAIL_STEP * 1.5:
							var turn := absf((line[i] - line[i - 1]).angle_to(line[i + 1] - line[i]))
							_check(turn < deg_to_rad(12.0), "trilha vira de repente em %s (semente %d)" % [p, world_seed])
						var side := dir.orthogonal()
						for offset in [-0.8, 0.8]:
							var cell := WorldGen.cell_of(p + side * offset)
							var thing := world.thing_at(cell)
							checked += 1
							_check(thing == WorldGen.Thing.TRILHA or thing == WorldGen.Thing.PONTE, "a 0,8 casa da linha deveria ser trilha em %s, é %s (semente %d)" % [cell, thing, world_seed])
						for offset in [-2.0, -1.0, 0.0, 1.0, 2.0]:
							var thing := world.thing_at(WorldGen.cell_of(p + side * offset))
							_check(not resources.has(thing), "recurso (%s) em cima ou na beira da trilha em %s (semente %d)" % [thing, p + side * offset, world_seed])
		_check(checked > 1000, "deveria ter conferido bastante trilha (%d)" % checked)


func _find_next_to(state: WorldState, thing: WorldGen.Thing) -> Array:
	# Acha uma casa livre ao lado de "thing"; devolve [livre, coisa].
	for y in range(-40, 40):
		for x in range(-40, 40):
			var cell := Vector2i(x, y)
			if state.world.thing_at(cell) != thing:
				continue
			for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
				if state.world.is_passable(cell + d):
					return [cell + d, cell]
	return []


func _test_collect() -> void:
	var state := WorldState.new(42)
	state.add_player(1, "Lua")
	var spot := _find_next_to(state, WorldGen.Thing.ARBUSTO)
	_check(not spot.is_empty(), "deveria haver arbusto com gravetos acessível")
	state.players[1]["pos"] = WorldGen.cell_center(spot[0])
	var far: Vector2i = spot[1] + Vector2i(5, 5)
	_check(not state.collect(1, far)["ok"], "não deveria coletar longe")
	_check(state.collect(1, spot[1])["ok"], "deveria coletar os gravetos ao lado")
	_check(not state.collect(1, spot[1])["ok"], "deveria haver uma pausa entre coletas")
	_check(Bag.count(state.inventories["Lua"], "lenha") == 2, "2 lenhas na bolsa")
	_check(int(state.inventories["Lua"].get("lenha_grande", 0)) == 0, "arbusto não dá lenha grande")

func _test_save_roundtrip() -> void:
	var state := WorldState.new(99)
	state.add_player(1, "Lua")
	state.inventories["Lua"] = {"bambu": 3}
	state.inventories["Tico"] = {"sementes": 2, "argila": 1}
	var path := "user://teste_mundo.json"
	_check(WorldSave.save_state(state, path), "deveria salvar")
	var loaded := WorldSave.load_state(path)
	_check(loaded != null and loaded.world.world_seed == 99, "semente salva")
	_check(loaded.inventories["Lua"]["bambu"] == 3, "inventário salvo")
	_check(loaded.inventories["Tico"] == {"argila": 1}, "itens que não existem mais (sementes) ficam para trás")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Biomas vizinhos parecidos, clareiras no meio da mata, mar sem trilhas e
## com praia, e as consultas de cobertura e de borda.
func _test_biomes_and_borders() -> void:
	for world_seed in [7, 42, 173]:
		var world := WorldGen.new(world_seed)
		var seen := {}
		var same := 0
		var pairs := 0
		var clearings := 0
		var reach := 24
		for ry in range(-reach, reach):
			for rx in range(-reach, reach):
				var region := Vector2i(rx, ry)
				var biome := world.region_biome(region)
				seen[biome] = true
				for next: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
					pairs += 1
					if world.region_biome(region + next) == biome:
						same += 1
				if world.region_feature(region) == WorldGen.Feature.CLAREIRA:
					clearings += 1
					_check(biome == WorldGen.Biome.BOSQUE or biome == WorldGen.Biome.FLORESTA_GELADA, "clareira só em floresta (semente %d)" % world_seed)
					_check(world.cover_of(region) == WorldGen.Cover.ABERTA, "clareira é aberta")
					var forest := 0
					for next: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
						if WorldGen.FOREST_BIOMES.has(world.region_biome(region + next)):
							forest += 1
					_check(forest >= WorldGen.CLEARING_FOREST_AROUND, "clareira fica no meio da mata (semente %d, %s)" % [world_seed, region])
				if biome == WorldGen.Biome.MAR:
					_check(world.trail_neighbors(region).is_empty(), "o mar não tem trilhas")
					_check(world.cover_of(region) == WorldGen.Cover.AGUA, "o mar é água")
				else:
					for next in world.trail_neighbors(region):
						_check(world.region_biome(next) != WorldGen.Biome.MAR, "trilha não entra no mar")
		_check(seen.size() == WorldGen.Biome.size(), "todos os biomas aparecem (semente %d: %d)" % [world_seed, seen.size()])
		_check(clearings > 0, "deveria haver clareiras (semente %d)" % world_seed)
		# Sorteando ao acaso, uns 20% das vizinhas teriam o mesmo bioma.
		_check(same > pairs * 0.45, "regiões vizinhas deveriam ser parecidas (semente %d: %d de %d)" % [world_seed, same, pairs])
		# Perto do centro não há mar nem frio.
		for ry in range(-1, 2):
			for rx in range(-1, 2):
				var near := world.region_biome(Vector2i(rx, ry))
				_check(near != WorldGen.Biome.MAR and not WorldGen.COLD_BIOMES.has(near), "em volta do centro o clima é ameno (semente %d)" % world_seed)
	# Mar: água que bloqueia, com uma praia andável encostada na terra.
	var world := WorldGen.new(42)
	var sea := WorldGen.NO_CELL
	for ry in range(-12, 12):
		for rx in range(-12, 12):
			if sea == WorldGen.NO_CELL and world.region_biome(Vector2i(rx, ry)) == WorldGen.Biome.MAR and world.region_biome(Vector2i(rx + 1, ry)) != WorldGen.Biome.MAR:
				sea = Vector2i(rx, ry) * WorldGen.REGION_SIZE
	_check(sea != WorldGen.NO_CELL, "deveria haver um mar com terra a leste")
	_check(world.thing_at(sea) == WorldGen.Thing.MAR and not world.is_passable(sea), "o meio do mar é água e bloqueia")
	# Andando do mar para a terra a leste: água, depois praia, depois terra.
	var stage := 0
	var beach := 0
	for dx in range(0, WorldGen.REGION_SIZE):
		var cell := sea + Vector2i(dx, 0)
		if world.region_biome(world.region_of(cell)) != WorldGen.Biome.MAR:
			break
		if world.is_beach(cell):
			stage = 1
			beach += 1
			_check(world.is_passable(cell) or world.thing_at(cell) != WorldGen.Thing.MAR, "a praia não é água")
			_check(world.border_distance(cell, [WorldGen.Cover.ABERTA, WorldGen.Cover.FECHADA]) < WorldGen.BEACH_WIDTH * 1.6, "a praia fica colada na terra")
		else:
			_check(stage == 0, "depois da praia não volta a ser mar em %s" % cell)
			_check(world.thing_at(cell) == WorldGen.Thing.MAR, "fora da praia, o mar é água")
	_check(beach >= 2, "deveria haver uma faixa de praia (%d casas)" % beach)
	# Borda: a distância cai até zero ao chegar na região vizinha.
	var a := Vector2i(0, 0)
	var east_cover := world.cover_of(Vector2i.RIGHT)
	var d0 := world.border_distance(a, [east_cover])
	var d1 := world.border_distance(Vector2i(20, 0), [east_cover])
	_check(d1 < d0 and d1 < 8.0, "a borda leste fica mais perto andando para leste (%.1f, %.1f)" % [d0, d1])
	# Nomes de lugar.
	_check(world.place_in(Vector2i.ZERO) == "na pradaria de girassóis", "o centro fica na pradaria")


## O Caminheiro dá a volta no mar, e sabe sair da praia e chegar nela.
func _test_route_around_sea() -> void:
	var world := WorldGen.new(42)
	var found := false
	for ry in range(-10, 10):
		for rx in range(-10, 10):
			var west := Vector2i(rx, ry)
			var east := Vector2i(rx + 2, ry)
			if found or world.region_biome(west + Vector2i.RIGHT) != WorldGen.Biome.MAR:
				continue
			if world.region_biome(west) == WorldGen.Biome.MAR or world.region_biome(east) == WorldGen.Biome.MAR:
				continue
			var finder := Wayfinder.new(world)
			var regions := finder.region_route(west, east)
			if regions.size() < 2:
				continue  # ilha: não há volta por terra
			found = true
			for region in regions:
				_check(world.region_biome(region) != WorldGen.Biome.MAR, "a rota entre regiões não passa pelo mar")
			_check(regions.size() > 3, "contornar o mar dá uma volta (%d regiões)" % regions.size())
			# Da praia até o ponto de encontro do outro lado.
			var beach := WorldGen.NO_CELL
			var sea_origin := (west + Vector2i.RIGHT) * WorldGen.REGION_SIZE
			for dy in range(-20, 20):
				for dx in range(-24, 24):
					var cell := sea_origin + Vector2i(dx, dy)
					if beach == WorldGen.NO_CELL and world.is_beach(cell) and world.is_passable(cell):
						beach = cell
			_check(beach != WorldGen.NO_CELL, "deveria haver praia nesse mar")
			if beach != WorldGen.NO_CELL:
				_check(finder.plan(WorldGen.cell_center(beach), world.region_landmark(east)), "rota saindo da praia")
				var route := finder.full_route()
				_check(not route.is_empty() and route[route.size() - 1].distance_to(world.region_landmark(east)) < 6.0, "a rota da praia chega ao destino")
				for point in route:
					_check(world.thing_at(WorldGen.cell_of(point)) != WorldGen.Thing.MAR, "beacon dentro do mar em %s" % point)
				var back := Wayfinder.new(world)
				_check(back.plan(world.region_landmark(west), WorldGen.cell_center(beach)), "rota chegando na praia")
				_check(not back.full_route().is_empty(), "a rota até a praia tem beacons")
	_check(found, "deveria haver um mar entre duas regiões de terra, com volta por terra")
