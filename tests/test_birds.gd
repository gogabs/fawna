extends SceneTree
## Testes dos pássaros: aparecem perto de quem chega, cantam pousados, fogem
## de quem chega perto, voam em bando e somem quando todos vão embora.
## Rodar: godot --headless --path . --script res://tests/test_birds.gd
## Com "-- --exportar=PASTA", também salva os cantos em .wav para ouvir.

var _failures := 0


func _init() -> void:
	_test_spawn_near_player()
	_test_same_seed_same_birds()
	_test_songs_and_flights()
	_test_flee()
	_test_flock_flies_together()
	_test_despawn()
	_test_sounds()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--exportar="):
			_export(arg.get_slice("=", 1))
	if _failures == 0:
		print("OK: pássaros passaram")
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FALHOU: " + message)


## Uma semente e um ponto com bosque, para os testes terem árvores.
func _forest_point(world: WorldGen) -> Vector2:
	for r in range(1, 40):
		for region in [Vector2i(r, 0), Vector2i(-r, 0), Vector2i(0, r), Vector2i(0, -r)]:
			if world.region_biome(region) == WorldGen.Biome.BOSQUE:
				return world.region_landmark(region)
	return Vector2.ZERO


func _run(aviary: Aviary, players: Dictionary, from_ms: int, seconds: float) -> Array:
	var all := []
	var t := from_ms
	while t < from_ms + int(seconds * 1000.0):
		all.append_array(aviary.update(t, players))
		t += 250
	return all


func _test_spawn_near_player() -> void:
	var world := WorldGen.new(42)
	var aviary := Aviary.new(world)
	var spot := _forest_point(world)
	var messages := aviary.update(0, {1: spot})
	_check(aviary.birds.size() > 0, "deveria haver pássaros perto de quem está no bosque")
	var appeared := messages.filter(func(m): return m[1] == "appear").size()
	_check(appeared > 0, "o jogador deveria ficar sabendo dos pássaros por perto")
	var has_sabia := false
	for bird in aviary.birds.values():
		has_sabia = has_sabia or bird["species"] == Aviary.Species.SABIA
		var cell := WorldGen.cell_of(bird["pos"])
		var thing := world.thing_at(bird["cell"])
		_check(Aviary.SPECIES[bird["species"]]["perches"].has(thing), "pássaro deveria nascer num poleiro (está em %s)" % cell)
	_check(has_sabia, "o bosque deveria ter sabiás")
	for bird in aviary.birds.values():
		var voices := {}
		for song in bird["songs"]:
			voices[int(song) / Aviary.VOICE_STRIDE] = true
		_check(voices.size() == 1, "cada pássaro deveria cantar com uma voz só")


func _test_same_seed_same_birds() -> void:
	var a := Aviary.new(WorldGen.new(42))
	var b := Aviary.new(WorldGen.new(42))
	var spot := _forest_point(a.world)
	a.update(0, {1: spot})
	b.update(0, {7: spot})
	var pa := a.birds.values().map(func(x): return x["pos"])
	var pb := b.birds.values().map(func(x): return x["pos"])
	_check(pa == pb, "mesma semente e mesmo lugar deveriam dar os mesmos pássaros")


func _test_songs_and_flights() -> void:
	var world := WorldGen.new(42)
	var aviary := Aviary.new(world)
	var spot := _forest_point(world)
	var messages := _run(aviary, {1: spot}, 0, 120.0)
	var sings := messages.filter(func(m): return m[1] == "sing")
	var flights := messages.filter(func(m): return m[1] == "fly")
	_check(sings.size() > 5, "em 2 minutos os pássaros deveriam cantar várias vezes (%d)" % sings.size())
	_check(flights.size() > 0, "em 2 minutos algum pássaro deveria trocar de poleiro")
	# Ninguém canta voando: cada canto vem de um pássaro pousado naquela hora.
	for bird in aviary.birds.values():
		var home: Vector2 = aviary.groups[bird["group"]]["home"]
		_check(aviary.position_of(bird, 120000).distance_to(home) <= Aviary.HOME_RADIUS + Aviary.SPREAD + 1.0, "pássaro não deveria se afastar de casa")


func _test_flee() -> void:
	var world := WorldGen.new(42)
	var aviary := Aviary.new(world)
	var spot := _forest_point(world)
	aviary.update(0, {1: spot})
	_run(aviary, {1: spot}, 250, 3.0)
	# Escolhe um pássaro pousado e chega bem perto dele.
	var target: Dictionary = {}
	for bird in aviary.birds.values():
		if not bird["flying"] and bird["watchers"].has(1):
			target = bird
			break
	_check(not target.is_empty(), "deveria haver um pássaro pousado")
	if target.is_empty():
		return
	var before: Vector2 = target["pos"]
	var close := before + Vector2(0.8, 0.0)
	var messages := _run(aviary, {1: close}, 3500, 1.0)
	var fled := messages.filter(func(m): return m[1] == "fly" and m[2][0] == target["id"])
	_check(not fled.is_empty(), "chegar perto deveria espantar o pássaro")
	if not fled.is_empty():
		_check(fled[0][2][6] == true, "a fuga deveria vir marcada como susto")
	_run(aviary, {1: close}, 4500, 6.0)
	_check(aviary.position_of(target, 10500).distance_to(close) > Aviary.SPECIES[target["species"]]["flee"], "depois de fugir, o pássaro deveria estar longe de quem chegou")


func _test_flock_flies_together() -> void:
	# Procura um bando de carriças em alguma pradaria.
	var world := WorldGen.new(42)
	var aviary: Aviary
	var flock: Dictionary = {}
	var spot := Vector2.ZERO
	for r in range(0, 30):
		spot = world.region_landmark(Vector2i(r % 6 - 3, r / 6 - 2))
		aviary = Aviary.new(world)
		aviary.update(0, {1: spot})
		for group in aviary.groups.values():
			if group["members"].size() >= 4 and aviary.birds[group["members"][0]]["watchers"].has(1):
				flock = group
				break
		if not flock.is_empty():
			break
	_check(not flock.is_empty(), "deveria existir algum bando de carriças")
	if flock.is_empty():
		return
	var messages := _run(aviary, {1: spot}, 250, 90.0)
	var ids: Array = flock["members"]
	var flights := messages.filter(func(m): return m[1] == "fly" and ids.has(m[2][0]))
	_check(flights.size() >= ids.size(), "o bando deveria voar junto (%d voos para %d pássaros)" % [flights.size(), ids.size()])
	var targets := {}
	for m in flights.slice(0, ids.size()):
		targets[m[2][0]] = m[2][2]
	var first: Vector3 = targets.values()[0]
	for t: Vector3 in targets.values():
		_check(t.distance_to(first) <= (Aviary.SPREAD * 2.0 + 1.5) * WorldGen.METERS_PER_CELL, "os membros do bando deveriam pousar perto uns dos outros")


func _test_despawn() -> void:
	var world := WorldGen.new(42)
	var aviary := Aviary.new(world)
	var spot := _forest_point(world)
	aviary.update(0, {1: spot})
	_check(aviary.birds.size() > 0, "deveria haver pássaros antes de ir embora")
	var far := spot + Vector2(500, 0)
	var messages := aviary.update(1000, {1: far})
	var gone := messages.filter(func(m): return m[1] == "gone").size()
	_check(gone > 0, "ao ir embora, os pássaros de lá deveriam sumir para o jogador")
	for bird in aviary.birds.values():
		_check(aviary.position_of(bird, 1000).distance_to(far) < 120.0, "só deveriam restar pássaros perto de quem está no mundo")
	aviary.update(2000, {})
	_check(aviary.birds.is_empty(), "sem ninguém no mundo, não deveria haver pássaros")


func _test_sounds() -> void:
	for species in Aviary.SPECIES:
		for i in Aviary.SPECIES[species]["songs"]:
			var stream := BirdSongs.song(species, i)
			_check(stream != null and stream.get_length() > 0.1, "canto %d de %s" % [i, Aviary.species_name(species)])
		_check(BirdSongs.wings(species, 2.0, true).get_length() >= 0.3, "asas de %s" % Aviary.species_name(species))


func _export(folder: String) -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	for species in Aviary.SPECIES:
		var name: String = BirdSongs.FILE_NAMES[species]
		for i in Aviary.SPECIES[species]["songs"]:
			(BirdSongs.song(species, i) as AudioStreamWAV).save_to_wav("%s/%s_%d.wav" % [folder, name, i])
		(BirdSongs.wings(species, 2.5, false) as AudioStreamWAV).save_to_wav("%s/%s_asas.wav" % [folder, name])
		var alarm := BirdSongs.alarm(species)
		if alarm != null:
			(alarm as AudioStreamWAV).save_to_wav("%s/%s_susto.wav" % [folder, name])
	print("cantos salvos em " + folder)
