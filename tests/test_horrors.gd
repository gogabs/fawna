extends SceneTree
## Testes do Calado: aparece atrás de quem fica exposto, em trilha ou não,, chega
## devagar pelas costas, para quando é encarado e recua do olhar e do fogo; e os pássaros se calam e fogem perto dele.
## Rodar: godot --headless --path . --script res://tests/test_horrors.gd
## Com "-- --exportar=PASTA", também salva a respiração em .wav para ouvir.

var _failures := 0


func _init() -> void:
	_test_appears_when_exposed()
	_test_safe_places()
	_test_stalks_from_behind()
	_test_caught_consequences()
	_test_stare_holds_and_repels()
	_test_fire_repels()
	_test_trail_and_company_do_not_protect()
	_test_gives_up_and_rests()
	_test_watchers()
	_test_birds_hush()
	_test_sound()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--exportar="):
			_export(arg.get_slice("=", 1))
	if _failures == 0:
		print("OK: horrores passaram")
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FALHOU: " + message)


## Um ponto de bosque fora da trilha, longe da Origem, com bosque em volta
## (para o Calado ter por onde vir sem o alvo estar numa trilha).
func _forest_spot(world: WorldGen) -> Vector2:
	for r in range(1, 40):
		for region in [Vector2i(r, 0), Vector2i(-r, 0), Vector2i(0, r), Vector2i(0, -r)]:
			if world.region_biome(region) != WorldGen.Biome.BOSQUE:
				continue
			var middle := WorldGen.cell_of(world.region_landmark(region))
			for dy in range(-12, 13):
				for dx in range(-12, 13):
					var cell := middle + Vector2i(dx, dy)
					var point := WorldGen.cell_center(cell)
					if world.biome_at(cell) == WorldGen.Biome.BOSQUE and not _trail_within(world, cell, 3) \
							and point.distance_to(WorldGen.origin_point()) > Horrors.ORIGIN_SAFE + 10.0:
						return point
	return Vector2.ZERO


func _trail_within(world: WorldGen, cell: Vector2i, r: int) -> bool:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if world.is_trail(cell + Vector2i(dx, dy)):
				return true
	return false


func _player(pos: Vector2, heading := 0) -> Dictionary:
	return {"name": "Teste", "pos": pos, "heading": heading}


func _run(horrors: Horrors, players: Dictionary, fires: Array, from_ms: int, seconds: float) -> Array:
	var all := []
	var t := from_ms
	while t < from_ms + int(seconds * 1000.0):
		all.append_array(horrors.update(t, players, fires))
		t += 250
	return all


## Anda a simulação até o Calado aparecer (ele alcança depressa quem não se mexe).
func _run_until_appears(horrors: Horrors, players: Dictionary, from_ms: int, seconds: float) -> void:
	var t := from_ms
	while t < from_ms + int(seconds * 1000.0) and horrors.horrors.is_empty():
		horrors.update(t, players, [])
		t += 250


func _test_appears_when_exposed() -> void:
	var world := WorldGen.new(42)
	var horrors := Horrors.new(world)
	var spot := _forest_spot(world)
	_check(spot != Vector2.ZERO, "deveria haver um bosque fora da trilha para os testes")
	var players := {1: _player(spot)}
	_run(horrors, players, [], 0, Horrors.EXPOSURE[0] - 5.0)
	_check(horrors.horrors.is_empty(), "o Calado não deveria aparecer antes do tempo mínimo de exposição")
	_run_until_appears(horrors, players, int((Horrors.EXPOSURE[0] - 5.0) * 1000.0), Horrors.EXPOSURE[1] - Horrors.EXPOSURE[0] + 10.0)
	_check(horrors.horrors.size() == 1, "sozinho no bosque por tempo bastante, o Calado deveria aparecer")
	if horrors.horrors.is_empty():
		return
	var horror: Dictionary = horrors.horrors.values()[0]
	_check(horror["target"] == 1, "o Calado deveria perseguir quem ficou exposto")
	# Olhando para o norte, "atrás" é o sul (y maior).
	_check((horror["pos"] as Vector2).y > spot.y, "o Calado deveria nascer às costas do alvo")


func _test_safe_places() -> void:
	var world := WorldGen.new(42)
	var spot := _forest_spot(world)
	var long := Horrors.EXPOSURE[1] + 20.0
	# Perto de uma fogueira acesa.
	var by_fire := Horrors.new(world)
	_run(by_fire, {1: _player(spot)}, [spot + Vector2(3, 0)], 0, long)
	_check(by_fire.horrors.is_empty(), "perto de uma fogueira acesa o Calado não deveria aparecer")
	# Na Origem.
	var home := Horrors.new(world)
	_run(home, {1: _player(WorldGen.origin_point() + Vector2(0, 1.5))}, [], 0, long)
	_check(home.horrors.is_empty(), "na Origem o Calado não deveria aparecer")
	# Em qualquer bioma, menos no mar: na pradaria ele aparece.
	for r in range(1, 40):
		var region := Vector2i(r, 0)
		if world.region_biome(region) == WorldGen.Biome.PRADARIA:
			var meadow := world.region_landmark(region) + Vector2(6.5, 6.5)
			if world.biome_at(WorldGen.cell_of(meadow)) != WorldGen.Biome.PRADARIA \
					or world.is_trail(WorldGen.cell_of(meadow)):
				continue
			var open := Horrors.new(world)
			_run_until_appears(open, {1: _player(meadow)}, 0, long)
			_check(not open.horrors.is_empty(), "na pradaria o Calado também deveria aparecer")
			break
	# No mar não.
	for r in range(1, 40):
		var sea := Vector2i(0, r)
		if world.region_biome(sea) == WorldGen.Biome.MAR:
			var swim := Horrors.new(world)
			_run(swim, {1: _player(world.region_landmark(sea))}, [], 0, long)
			_check(swim.horrors.is_empty(), "no mar o Calado não deveria aparecer")
			break


func _test_stalks_from_behind() -> void:
	var world := WorldGen.new(42)
	var horrors := Horrors.new(world)
	var spot := _forest_spot(world)
	var players := {1: _player(spot)}
	var id := horrors.summon(1, players)
	_check(id > 0, "summon deveria criar o Calado")
	_check(horrors.summon(1, players) == -1, "não deveria haver dois Calados atrás da mesma criatura")
	var horror: Dictionary = horrors.horrors[id]
	var start: float = (horror["pos"] as Vector2).distance_to(spot)
	_check(is_equal_approx(start, Horrors.SPAWN_DISTANCE), "o Calado deveria nascer a %.0f casas" % Horrors.SPAWN_DISTANCE)
	_run(horrors, players, [], 0, 5.0)
	var after: float = (horror["pos"] as Vector2).distance_to(spot)
	_check(after < start - 3.0, "o Calado deveria se aproximar de quem não olha para ele (%.1f -> %.1f)" % [start, after])
	_check(start - after <= Horrors.STALK_SPEED * 5.0 + 0.1, "o Calado não deveria andar mais rápido que a velocidade dele")
	_check(Horrors.STALK_SPEED < 1.8, "o Calado deveria ser mais lento que a criatura andando")
	var messages := _run(horrors, players, [], 5000, 60.0)
	var caught := messages.filter(func(m): return m[1] == "caught")
	_check(caught.size() == 1 and caught[0][0] == 1, "sem ser encarado, o Calado deveria alcançar o alvo (uma vez só)")
	_check(not horrors.horrors.has(id), "depois de alcançar, o Calado deveria sumir")
	_check(messages.any(func(m): return m[1] == "gone" and m[0] == 1), "quem o ouvia deveria ser avisado de que ele sumiu")
	_check(horrors.summon(1, players) > 0, "ele pode voltar a ser chamado (o sossego só vale para o sorteio)")
	# Sossego depois de alcançar: não reaparece logo sozinho.
	var calm := Horrors.new(world)
	var calm_players := {1: _player(spot)}
	calm.summon(1, calm_players)
	_run(calm, calm_players, [], 0, 60.0)
	_run(calm, calm_players, [], 60000, Horrors.COOLDOWN[0] - 70.0)
	_check(calm.horrors.is_empty(), "depois de alcançar, o Calado deveria deixar a criatura em paz por um tempo")


func _test_caught_consequences() -> void:
	var world := WorldGen.new(42)
	var origin := WorldGen.origin_point()
	_check(Horrors.nearest_shelter(Vector2(500, 500), []) == origin, "sem abrigo nenhum, o ponto seguro é a Origem")
	var fire := Vector2(520.5, 505.5)
	_check(Horrors.nearest_shelter(Vector2(500, 500), [fire]) == fire, "uma fogueira mais perto que a Origem deveria ser o ponto seguro")
	_check(Horrors.nearest_shelter(origin + Vector2(3, 3), [fire]) == origin, "a Origem mais perto deveria vencer")
	var landed := Horrors.landing_spot(world, origin, [])
	_check(world.is_free(landed) and landed.distance_to(origin) < 4.0, "deveria reaparecer num ponto livre ao lado do abrigo")
	var blocked := Horrors.landing_spot(world, origin, [WorldGen.cell_of(origin + Vector2(0, 1.6))])
	_check(WorldGen.cell_of(blocked) != WorldGen.cell_of(origin + Vector2(0, 1.6)), "não deveria reaparecer em cima de uma construção")
	# A bolsa: recursos somem; machado (nas mãos ou guardado) e armas ficam.
	var state := WorldState.new(42)
	state.add_player(1, "Teste")
	var inv := state.inventory_of(1)
	inv["bambu"] = 3
	inv["pedra_grande"] = 2
	inv["frutas"] = 4
	inv["lanca"] = 1
	var lost := state.strip_resources(1)
	_check(lost == {"bambu": 3, "pedra_grande": 2, "frutas": 4}, "deveria perder todos os recursos (%s)" % str(lost))
	_check(inv == {"machado": 1, "lanca": 1}, "o machado e as armas deveriam ficar (%s)" % str(inv))
	state.equip(1, "machado")
	state.inventory_of(1)["argila"] = 2
	state.strip_resources(1)
	_check(state.wielding(1) == "machado" and state.inventory_of(1).get("argila", 0) == 0, "o que está nas mãos fica, a argila vai")
	state.teleport(1, origin + Vector2(0, 3))
	_check(state.players[1]["pos"] == origin + Vector2(0, 3), "teleport deveria mudar a posição")
	_check(state.move_to(1, origin + Vector2(0, 3.3))["ok"], "depois de levado, andar a partir dali deveria valer")


func _test_stare_holds_and_repels() -> void:
	var world := WorldGen.new(42)
	var horrors := Horrors.new(world)
	var spot := _forest_spot(world)
	var players := {1: _player(spot)}
	var id := horrors.summon(1, players)
	var horror: Dictionary = horrors.horrors[id]
	_run(horrors, players, [], 0, 2.0)
	# Vira para o sul: de frente para ele.
	players[1]["heading"] = 4
	_check(Horrors.is_facing(spot, 4, horror["pos"]), "virado para o sul, o alvo deveria estar encarando o Calado")
	_check(not Horrors.is_facing(spot, 0, horror["pos"]), "virado para o norte, não")
	var before: Vector2 = horror["pos"]
	_run(horrors, players, [], 2000, 2.0)
	_check(horror["mode"] == Horrors.Mode.HELD, "encarado, o Calado deveria parar")
	_check((horror["pos"] as Vector2).is_equal_approx(before), "encarado, o Calado não deveria sair do lugar")
	# Desvia o olhar: ele volta a andar, e o tempo encarado não se perde.
	players[1]["heading"] = 0
	_run(horrors, players, [], 4000, 1.0)
	_check(horror["mode"] == Horrors.Mode.STALK, "sem o olhar, o Calado deveria voltar a se aproximar")
	players[1]["heading"] = 4
	_run(horrors, players, [], 5000, Horrors.STARE_SECONDS - 2.0 + 0.5)
	_check(horror["mode"] == Horrors.Mode.RETREAT, "encarado por tempo bastante, o Calado deveria recuar")
	var far: float = (horror["pos"] as Vector2).distance_to(spot)
	var messages := _run(horrors, players, [], 12000, Horrors.RETREAT_MAX + 1.0)
	_check(not horrors.horrors.has(id), "depois de recuar, o Calado deveria sumir")
	_check(messages.any(func(m): return m[1] == "gone" and m[0] == 1), "quem o ouvia deveria ser avisado de que ele sumiu")
	_check(far < Horrors.GONE_DISTANCE, "o recuo deveria começar de perto")
	# Todos os giros de 45° têm de servir para encarar algo em qualquer direção.
	for degrees in range(0, 360, 5):
		var point := Vector2.from_angle(deg_to_rad(degrees)) * 10.0
		var seen := false
		for heading in Compass.STEPS:
			seen = seen or Horrors.is_facing(Vector2.ZERO, heading, point)
		_check(seen, "alguma das 8 direções deveria encarar um ponto a %d graus" % degrees)


func _test_fire_repels() -> void:
	var world := WorldGen.new(42)
	var spot := _forest_spot(world)
	var by_fire := Horrors.new(world)
	var players := {1: _player(spot)}
	var id := by_fire.summon(1, players)
	_run(by_fire, players, [], 0, 3.0)
	var before: float = (by_fire.horrors[id]["pos"] as Vector2).distance_to(spot)
	# Acende uma fogueira ao lado do alvo.
	_run(by_fire, players, [spot + Vector2(2, 0)], 3000, 3.0)
	_check(by_fire.horrors[id]["mode"] == Horrors.Mode.RETREAT, "fogueira acesa perto do alvo deveria fazer o Calado recuar")
	_check((by_fire.horrors[id]["pos"] as Vector2).distance_to(spot) > before, "recuando, o Calado deveria se afastar")
	_check(not Horrors.fire_near(spot, [spot + Vector2(Horrors.FIRE_SAFE + 1.0, 0)]), "fogueira longe demais não protege")


func _test_trail_and_company_do_not_protect() -> void:
	var world := WorldGen.new(42)
	var spot := _forest_spot(world)
	var trail := Vector2.INF
	var here := WorldGen.cell_of(spot)
	for r in range(1, 60):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if trail == Vector2.INF and world.is_trail(here + Vector2i(dx, dy)):
					trail = WorldGen.cell_center(here + Vector2i(dx, dy))
		if trail != Vector2.INF:
			break
	_check(trail != Vector2.INF, "deveria haver uma trilha perto do bosque")
	var horrors := Horrors.new(world)
	_run_until_appears(horrors, {1: _player(trail)}, 0, Horrors.EXPOSURE[1] + 10.0)
	_check(not horrors.horrors.is_empty(), "parado na trilha, o Calado deveria aparecer do mesmo jeito")
	var id: int = horrors.horrors.keys()[0] if not horrors.horrors.is_empty() else -1
	var players := {1: _player(trail), 2: _player(trail + Vector2(2, 0))}
	var messages := _run(horrors, players, [], 0, 60.0)
	_check(messages.any(func(m): return m[1] == "caught"), "na trilha e com companhia, o Calado ainda deveria alcançar o alvo")
	_check(id > 0, "o Calado deveria existir")


func _test_gives_up_and_rests() -> void:
	var world := WorldGen.new(42)
	var horrors := Horrors.new(world)
	var spot := _forest_spot(world)
	var players := {1: _player(spot)}
	var id := horrors.summon(1, players)
	horrors.update(0, players, [])
	# O alvo vai parar muito longe de uma vez.
	players[1]["pos"] = spot + Vector2(0, -(Horrors.GIVE_UP_DISTANCE + 30.0))
	horrors.update(250, players, [])
	_check(not horrors.horrors.has(id), "com o alvo longe demais, o Calado deveria desistir")
	# Quem só se afasta andando (um pouco além de GIVE_UP_DISTANCE) não o perde: ele ressurge atrás.
	var chased := Horrors.new(world)
	var walker := {1: _player(spot)}
	var chased_id := chased.summon(1, walker)
	chased.update(0, walker, [])
	walker[1]["pos"] = spot + Vector2(0, -(Horrors.GIVE_UP_DISTANCE + 5.0))
	chased.update(250, walker, [])
	_check(chased.horrors.has(chased_id) and (chased.horrors[chased_id]["pos"] as Vector2).distance_to(walker[1]["pos"]) <= Horrors.SPAWN_DISTANCE + 0.1,
		"quem se afasta andando deveria ter o Calado ressurgindo atrás")
	# Depois de uma visita, sossego: ele não volta antes do descanso mínimo.
	players[1]["pos"] = spot
	_run(horrors, players, [], 500, Horrors.COOLDOWN[0] - 5.0)
	_check(horrors.horrors.is_empty(), "o Calado não deveria voltar antes do descanso")
	# Quem sai do jogo leva o seu Calado embora.
	var other := Horrors.new(world)
	players = {1: _player(spot)}
	other.summon(1, players)
	other.update(0, players, [])
	other.update(250, {}, [])
	_check(other.horrors.is_empty(), "sem o alvo no jogo, o Calado deveria sumir")


func _test_watchers() -> void:
	var world := WorldGen.new(42)
	var horrors := Horrors.new(world)
	var spot := _forest_spot(world)
	var players := {1: _player(spot), 2: _player(spot + Vector2(0, -(Horrors.HEARING + 30.0)))}
	var id := horrors.summon(1, players)
	var messages := horrors.update(0, players, [])
	_check(messages.any(func(m): return m[0] == 1 and m[1] == "at" and m[2][0] == id), "o alvo deveria saber onde o Calado está")
	_check(not messages.any(func(m): return m[0] == 2), "quem está longe não deveria saber do Calado")
	_check(horrors.points().size() == 1, "points deveria listar o Calado para os pássaros")


func _test_birds_hush() -> void:
	var world := WorldGen.new(42)
	var aviary := Aviary.new(world)
	var spot := _forest_spot(world)
	var players := {1: spot}
	# Sem horror: os pássaros cantam.
	var t := 0
	var sings := 0
	while t < 120000:
		sings += aviary.update(t, players).filter(func(m): return m[1] == "sing").size()
		t += 250
	_check(sings > 3, "sem o Calado, os pássaros deveriam cantar (%d)" % sings)
	# Com um horror no meio deles: fogem assustados e ninguém canta.
	var landed := aviary.birds.values().filter(func(b): return not b["flying"])
	_check(not landed.is_empty(), "deveria haver pássaros pousados")
	if landed.is_empty():
		return
	# O horror fica em cima do líder de um bando que tenha para onde fugir (um
	# bando sem outro poleiro por perto não tem o que fazer a não ser ficar).
	var dread := Vector2.INF
	for group: Dictionary in aviary.groups.values():
		var leader: Dictionary = aviary.birds[group["members"][0]]
		if not leader["flying"] and aviary._pick_target(group, leader["pos"], leader["pos"] + Vector2(1, 0)) != WorldGen.NO_CELL:
			dread = leader["pos"]
			break
	_check(dread != Vector2.INF, "deveria haver um bando com outro poleiro por perto")
	if dread == Vector2.INF:
		return
	# Quem ouve as mensagens tem de estar perto dos pássaros.
	players[1] = dread + Vector2(4, 0)
	aviary.hush = [dread]
	var hushed_sings := 0
	var scared := 0
	while t < 240000:
		for message in aviary.update(t, players):
			var bird: Dictionary = aviary.birds.get(message[2][0], {})
			if bird.is_empty():
				continue
			var near := aviary.position_of(bird, t).distance_to(dread) <= Horrors.HUSH_RADIUS - 1.0
			if message[1] == "sing" and near:
				hushed_sings += 1
			if message[1] == "fly" and message[2][6] == true:
				scared += 1
		t += 250
	_check(hushed_sings == 0, "perto do Calado nenhum pássaro deveria cantar (%d)" % hushed_sings)
	_check(scared > 0, "o Calado deveria espantar os pássaros por perto")
	# O susto não se repete sem parar: no máximo um por grupo a cada HUSH_FLEE_EVERY.
	var most := aviary.birds.size() * int(120.0 / Aviary.HUSH_FLEE_EVERY + 1.0)
	_check(scared <= most, "os pássaros não deveriam fugir sem parar (%d sustos)" % scared)


func _test_sound() -> void:
	var samples := HorrorSounds.calado_breath_samples()
	_check(samples.size() == int(HorrorSounds.BREATH_SECONDS * HorrorSounds.RATE), "a respiração deveria ter o tamanho do ciclo")
	var peak := 0.0
	for value in samples:
		peak = maxf(peak, absf(value))
	_check(peak > 0.2 and peak <= 1.0, "a respiração deveria soar sem estourar (pico %.2f)" % peak)
	_check(absf(samples[0]) < 0.02 and absf(samples[samples.size() - 1]) < 0.02, "o loop deveria fechar em silêncio, sem estalo")
	var stream := HorrorSounds.calado_breath()
	_check(stream is AudioStreamWAV and (stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD, "a respiração gerada deveria tocar em loop")
	var caught := HorrorSounds.caught_samples()
	var relief := HorrorSounds.relief_samples()
	_check(absf(caught[caught.size() - 1]) < 0.01 and absf(relief[relief.size() - 1]) < 0.01, "os sons de ser alcançado e de reaparecer deveriam fechar em silêncio")
	for pair in [caught, relief]:
		var top := 0.0
		for value in pair:
			top = maxf(top, absf(value))
		_check(top > 0.2 and top <= 1.0, "os sons de ser alcançado e de reaparecer deveriam soar sem estourar (%.2f)" % top)
	# Abafamento: nada de longe, tudo de perto, crescendo no caminho.
	_check(Horrors.presence_at(30.0) == 0.0, "longe, o Calado não deveria abafar nada")
	_check(Horrors.presence_at(2.0) == 1.0, "ao lado, o abafamento deveria ser total")
	_check(Horrors.presence_at(8.0) > Horrors.presence_at(14.0), "o abafamento deveria crescer conforme ele chega")


func _export(folder: String) -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	var one := HorrorSounds.calado_breath_samples()
	var three := PackedFloat32Array()
	for i in 3:
		three.append_array(one)
	var data := PackedByteArray()
	data.resize(three.size() * 2)
	for i in three.size():
		data.encode_s16(i * 2, int(clampf(three[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = HorrorSounds.RATE
	wav.data = data
	wav.save_to_wav(folder.path_join("calado_respiracao.wav"))
	print("respiração salva em %s" % folder)
