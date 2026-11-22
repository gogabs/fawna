extends SceneTree
## Testes dos cavalinhos-da-bruma: manadas aparecem perto de quem chega na
## pradaria, bufam quando alguém chega, fogem de quem vem direto, toleram
## quem espera parado, fogem de barulho forte e somem quando todos saem.
## Rodar: godot --headless --path . --script res://tests/test_horses.gd
## Com "-- --exportar=PASTA", também salva os sons gerados em .wav.

var _failures := 0


func _init() -> void:
	var world := WorldGen.new(42)
	var spot := _herd_point(world)
	_check(spot != Vector2.INF, "acha uma manada na pradaria ou no deserto gelado")
	if spot != Vector2.INF:
		_test_same_seed(world, spot)
		_test_alert_and_flee(world, spot)
		_test_patience(world, spot)
		_test_noise(world, spot)
		_test_walks_on_ground(world, spot)
		_test_despawn(world, spot)
		_test_summon(world, spot)
		_test_taming(world, spot)
		_test_tame_save(world, spot)
		_test_follow_and_ride(world, spot)
	_test_sounds()
	_test_recorded()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--exportar="):
			_export(arg.get_slice("=", 1))
	if _failures == 0:
		print("OK: cavalos passaram")
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FALHOU: " + message)


## Um ponto com manada: procura pedaços da pradaria até um ter cavalos.
func _herd_point(world: WorldGen) -> Vector2:
	for r in range(0, 60):
		for region in [Vector2i(r, 0), Vector2i(-r, 0), Vector2i(0, r), Vector2i(0, -r), Vector2i(r, r), Vector2i(-r, -r)]:
			var center := WorldGen.cell_center(region * WorldGen.REGION_SIZE)
			if not Herd.SPAWNS.has(world.biome_at(WorldGen.cell_of(center))):
				continue
			var herd := Herd.new(world)
			herd.update(0, {1: center})
			if herd.horse_count() > 0:
				return herd.nearest(center, 0)["to"]
	return Vector2.INF


## Fica a "far" casas da manada, do lado de fora, em chão livre.
func _approach_from(herd: Herd, spot: Vector2, far: float) -> Vector2:
	for angle in 16:
		var point := spot + Vector2.from_angle(angle * TAU / 16.0) * far
		if WorldGen.GROUND.has(herd.world.thing_at(WorldGen.cell_of(point))):
			return point
	return spot + Vector2(far, 0)


func _run(herd: Herd, players: Dictionary, from_ms: int, seconds: float) -> Array:
	var all := []
	var t := from_ms
	while t < from_ms + int(seconds * 1000.0):
		all.append_array(herd.update(t, players))
		t += 250
	return all


func _count(messages: Array, kind: String, sound := "") -> int:
	var n := 0
	for m in messages:
		if m[1] != kind:
			continue
		if sound != "" and Herd.SOUNDS[int(m[2][1])] != sound:
			continue
		n += 1
	return n


func _gallops(messages: Array) -> int:
	var n := 0
	for m in messages:
		if m[1] == "move" and int(m[2][6]) == Herd.Gait.GALLOP:
			n += 1
	return n


func _test_same_seed(world: WorldGen, spot: Vector2) -> void:
	var a := Herd.new(world)
	var b := Herd.new(world)
	a.update(0, {1: spot + Vector2(25, 0)})
	b.update(0, {1: spot + Vector2(25, 0)})
	_check(a.horse_count() == b.horse_count() and a.horse_count() >= Herd.GROUP[0], "mesma semente, mesmas manadas (%d e %d)" % [a.horse_count(), b.horse_count()])


func _test_alert_and_flee(world: WorldGen, spot: Vector2) -> void:
	var herd := Herd.new(world)
	var start := _approach_from(herd, spot, 25.0)
	var out := _run(herd, {1: start}, 0, 2.0)
	_check(_count(out, "appear") >= Herd.GROUP[0], "quem chega fica sabendo dos cavalos")
	# Vem andando direto na manada, sem parar.
	var t := 2000
	var pos := start
	var flee := 0
	var snorts := 0
	while t < 40000 and flee == 0:
		var center := herd.nearest(pos, t)
		pos = pos.move_toward(herd.position_of(center, t), 1.8 * 0.25)
		var msgs := herd.update(t, {1: pos})
		snorts += _count(msgs, "sound", "bufo")
		flee += _gallops(msgs)
		t += 250
	_check(snorts >= 1, "a manada bufa de alerta quando alguém chega")
	_check(flee >= Herd.GROUP[0], "quem vem direto faz a manada fugir a galope (%d)" % flee)


func _test_patience(world: WorldGen, spot: Vector2) -> void:
	var herd := Herd.new(world)
	herd.update(0, {1: spot + Vector2(40, 40)})
	# Para a manada não sair andando sozinha durante o teste.
	for h in herd.herds.values():
		h["leave_ms"] = 999999999
	var target := herd.nearest(spot, 0)
	# Só a manada do teste (outra no caminho fugiria, com razão).
	for id in herd.herds.keys():
		if id != target["herd"]:
			herd.herds.erase(id)
	var center := herd._herd_center(herd.herds[target["herd"]], 0)
	var pos := _approach_from(herd, center, 6.0)
	var t := 250
	var flee := 0
	# Espera parado dentro do alcance de alerta.
	for i in int(Herd.SETTLE / 0.25) + 4:
		flee += _gallops(herd.update(t, {1: pos}))
		t += 250
	# Agora chega bem perto, devagar.
	var herd_of_target: Dictionary = herd.herds[target["herd"]]
	while herd._nearest_member(herd_of_target, pos, t) > 1.0 and t < 60000:
		pos = pos.move_toward(herd.position_of(target, t), 1.8 * 0.25)
		flee += _gallops(herd.update(t, {1: pos}))
		t += 250
	_check(flee == 0, "quem espera parado chega perto sem espantar (fugas: %d)" % flee)


func _test_noise(world: WorldGen, spot: Vector2) -> void:
	var herd := Herd.new(world)
	var far := spot + Vector2(20, 0)
	herd.update(0, {1: far})
	herd.hear_noise(spot + Vector2(3, 0))
	herd.update(250, {1: far})
	_run(herd, {1: far}, 500, 1.0)
	# Sem ninguém assistindo de perto, as mensagens podem não sair; olha o estado.
	var galloping := 0
	for horse in herd.horses.values():
		if int(horse["gait"]) == Herd.Gait.GALLOP:
			galloping += 1
	_check(galloping >= Herd.GROUP[0], "barulho forte por perto espanta a manada (%d)" % galloping)


func _test_walks_on_ground(world: WorldGen, spot: Vector2) -> void:
	var herd := Herd.new(world)
	var watcher := spot + Vector2(28, 0)
	var out := _run(herd, {1: watcher}, 0, 240.0)
	var walks := 0
	var bad := 0
	for m in out:
		if m[1] != "move":
			continue
		walks += 1
		var to: Vector2 = m[2][2]
		if WorldGen.BLOCKING.has(world.thing_at(WorldGen.cell_of(to))):
			bad += 1
	_check(walks > 0, "a manada anda sozinha de vez em quando")
	_check(bad == 0, "cavalos só param em chão livre (%d fora)" % bad)
	_check(_count(out, "sound", "pasto") > 0, "cavalos parados mastigam capim")


func _test_despawn(world: WorldGen, spot: Vector2) -> void:
	var herd := Herd.new(world)
	herd.update(0, {1: spot})
	_check(herd.horse_count() > 0, "manada existe com alguém perto")
	herd.update(250, {1: spot + Vector2(400, 400)})
	_check(herd.nearest(spot, 250).is_empty() or herd.position_of(herd.nearest(spot, 250), 250).distance_to(spot) > 60.0, "manada some quando todos vão embora")


func _test_summon(world: WorldGen, spot: Vector2) -> void:
	var herd := Herd.new(world)
	var me := _approach_from(herd, spot, 30.0)
	herd.update(0, {1: me})
	var came := herd.summon(me, 250)
	_check(came >= Herd.GROUP[0], "a depuração chama uma manada (%d)" % came)
	var out := _run(herd, {1: me}, 500, 20.0)
	var center := herd.nearest(me, 20500)
	_check(not center.is_empty() and herd.position_of(center, 20500).distance_to(me) < Herd.SUMMON_TO + 1.0, "a manada chamada para perto de quem chamou")
	_check(_gallops(out) == 0, "chegar chamada não espanta a manada")
	# Longe de qualquer pradaria também funciona (cria uma manada ali).
	var other := Herd.new(world)
	_check(other.summon(Vector2(0.5, 0.5) + Vector2(3000, -3000), 0) >= 0, "chamar em qualquer lugar não quebra")


## Uma manada só, quieta, com alguém já aceito ao lado de um cavalo.
func _calm_herd(world: WorldGen, spot: Vector2) -> Array:
	var herd := Herd.new(world)
	herd.update(0, {1: spot + Vector2(40, 40)})
	for h in herd.herds.values():
		h["leave_ms"] = 999999999
	var target := herd.nearest(spot, 0)
	for id in herd.herds.keys():
		if id != target["herd"]:
			herd.herds.erase(id)
	herd.peer_keys[1] = "Lua"
	var center := herd._herd_center(herd.herds[target["herd"]], 0)
	var pos := _approach_from(herd, center, 8.5)
	herd._last_players = {1: pos}  # já chega parado ali
	var t := 250
	for i in int(Herd.SETTLE / 0.25) + 4:
		herd.update(t, {1: pos})
		t += 250
	# Chega devagar até ficar a 1 casa do cavalo mais perto (sem atravessar a
	# manada, onde esbarraria nos outros).
	var best := INF
	for horse_id in herd.herds[target["herd"]]["members"]:
		var d := herd.position_of(herd.horses[horse_id], t).distance_to(pos)
		if d < best:
			best = d
			target = herd.horses[horse_id]
	while pos.distance_to(herd.position_of(target, t)) > 1.0 and t < 60000:
		pos = pos.move_toward(herd.position_of(target, t), 0.4)
		herd.update(t, {1: pos})
		t += 250
	herd.update(t, {1: pos})
	t += 250
	return [herd, target, pos, t]


func _test_taming(world: WorldGen, spot: Vector2) -> void:
	var stranger := Herd.new(world)
	stranger.update(0, {1: spot})
	var any := stranger.nearest(spot, 0)
	_check(stranger.offer(1, int(any["id"]), 0, stranger.position_of(any, 0))["reason"] == "desconfia", "manada que não aceitou a pessoa não come da mão")
	var setup := _calm_herd(world, spot)
	var herd: Herd = setup[0]
	var horse: Dictionary = setup[1]
	var pos: Vector2 = setup[2]
	var t: int = setup[3]
	var id := int(horse["id"])
	_check(herd.offer(1, id, t, pos + Vector2(5, 0))["reason"] == "longe", "de longe não dá fruta")
	var first := herd.offer(1, id, t, pos)
	_check(first["ok"] and first["reason"] == "comeu", "cavalo come a fruta da mão (%s)" % first["reason"])
	_check(herd.offer(1, id, t + 500, pos)["reason"] == "mastigando", "não aceita outra enquanto mastiga")
	var last := ""
	var fed := 1
	while fed < int(horse["need"]):
		t += int(Herd.CHEW * 1000.0) + 250
		herd.update(t, {1: pos})
		last = herd.offer(1, id, t, pos)["reason"]
		fed += 1
	_check(last == "pronto", "depois de %d frutas fica junto (%s)" % [fed, last])
	var tamed := 0
	for i in int(Herd.QUIET_TO_TAME / 0.25) + 4:
		t += 250
		for m in herd.update(t, {1: pos}):
			if m[1] == "tamed" and int(m[2][0]) == id:
				tamed += 1
	_check(tamed == 1, "quieto ao lado, o cavalo vira seu")
	_check(int(horse["herd"]) < 0 and horse["owner"] == "Lua", "domesticado tem dono e sai da manada")
	_check(herd.rename(1, id, "Bramion") and horse["name"] == "Bramion", "o dono dá nome")
	_check(not herd.rename(1, id, "Fulano"), "nome fora das listas é recusado")
	herd.peer_keys[2] = "Sol"
	_check(not herd.rename(2, id, "Cinza"), "só o dono dá nome")
	# Todo mundo vai embora: o domesticado fica.
	herd.update(t + 250, {1: spot + Vector2(500, 500)})
	_check(herd.horses.has(id), "domesticado não some quando todos vão embora")
	# Um susto zera a confiança dos outros.
	var setup2 := _calm_herd(world, spot)
	var herd2: Herd = setup2[0]
	var other: Dictionary = setup2[1]
	herd2.offer(1, int(other["id"]), int(setup2[3]), setup2[2])
	herd2.hear_noise(setup2[2])
	herd2.update(int(setup2[3]) + 250, {1: setup2[2]})
	_check(int(other["trust"]) == 0, "susto que espanta a manada perde a confiança")
	_check(Herd.name_prefixes(7, 0) != Herd.name_prefixes(7, 1) and Herd.name_prefixes(7, 0).size() == Herd.NAME_CHOICES, "outros prefixos na página seguinte")
	var p0: int = Herd.name_prefixes(7, 0)[0]
	var s0: int = Herd.name_suffixes(7, p0, 0)[0]
	_check(Herd.is_name(Herd.compose_name(p0, s0)), "prefixo e sufixo formam um nome válido")


func _test_tame_save(world: WorldGen, spot: Vector2) -> void:
	var herd := Herd.new(world)
	herd.update(0, {1: spot})
	herd.peer_keys[1] = "Lua"
	var id := herd.debug_tame(1, spot, 0)
	_check(id >= 0, "depuração domestica o cavalo mais perto")
	herd.rename(1, id, "Velura")
	var saved := herd.tame_to_save()
	_check(saved.size() == 1 and saved[0]["name"] == "Velura" and saved[0]["owner"] == "Lua", "domesticado vai para o save")
	var back := Herd.new(world)
	back.load_tame(JSON.parse_string(JSON.stringify(saved)))
	var found := back.nearest(Vector2(saved[0]["x"], saved[0]["y"]), 0)
	_check(not found.is_empty() and found["name"] == "Velura" and found["owner"] == "Lua" and int(found["herd"]) < 0, "domesticado volta do save com nome e dono")


## O domesticado segue o dono (menos comendo), monta e desmonta.
func _test_follow_and_ride(world: WorldGen, spot: Vector2) -> void:
	var herd := Herd.new(world)
	herd.update(0, {1: spot})
	herd.peer_keys[1] = "Lua"
	herd.peer_keys[2] = "Sol"
	var id := herd.debug_tame(1, spot, 0)
	var horse: Dictionary = herd.horses[id]
	var at: Vector2 = horse["to"]
	_run(herd, {1: at}, 250, 2.0)
	# O dono anda para longe; o cavalo vem (pode parar para comer antes).
	var away := _approach_from(herd, at, 8.0)
	_run(herd, {1: away}, 2500, 20.0)
	var near := herd.position_of(horse, 22500).distance_to(away)
	_check(near <= Herd.FOLLOW_FAR, "domesticado segue o dono (ficou a %.1f casas)" % near)
	# Comendo, não segue.
	horse["eat_until_ms"] = 40000
	var later := _approach_from(herd, away, 6.0)
	_run(herd, {1: later}, 22750, 3.0)
	var here := herd.position_of(horse, 25750)
	_check(here.distance_to(later) > Herd.FOLLOW_FAR, "comendo, não segue")
	# Longe demais: surge ao lado.
	horse["eat_until_ms"] = 0
	var gone := later + Vector2(60, 0)
	_run(herd, {1: gone}, 26000, 1.0)
	_check(herd.position_of(horse, 27000).distance_to(gone) <= Herd.FOLLOW_NEAR + 0.5, "muito longe, surge ao lado do dono")
	# Montar: longe recusa, de outro recusa, perto monta.
	var pos := herd.position_of(horse, 27000)
	_check(herd.mount(1, id, pos + Vector2(5, 0), 27000) == "longe", "montar de longe recusa")
	_check(herd.mount(2, id, pos, 27000) == "nao_e_seu", "montar no cavalo de outro recusa")
	_check(herd.mount(1, id, pos, 27000) == "montou", "monta no próprio cavalo")
	_check(herd.riding_of(1) == id, "sabe quem está montado")
	_check(herd.mount(1, id, pos, 27000) == "montado", "não monta duas vezes")
	# Montado, vai junto: a galope se rápido, a passo se devagar.
	var messages := []
	var t := 27250
	var rider := pos
	for i in 8:
		rider += Vector2(1.0, 0)  # 4 casas/s
		messages.append_array(herd.update(t, {1: rider}))
		t += 250
	_check(_gallops(messages) >= 6, "montado e rápido, galopa")
	_check(herd.position_of(horse, t).distance_to(rider) < 1.2, "montado, vai junto de quem monta")
	var walks := 0
	for i in 8:
		rider += Vector2(0.5, 0)  # 2 casas/s
		for m in herd.update(t, {1: rider}):
			if m[1] == "move" and int(m[2][6]) == Herd.Gait.WALK:
				walks += 1
		t += 250
	_check(walks >= 6, "montado e devagar, anda a passo")
	_check(herd.dismount(1, t) == id and herd.riding_of(1) == -1, "desmonta")
	herd.mount(1, id, herd.position_of(horse, t), t)
	herd.forget_peer(1)
	_check(int(horse["rider"]) == -1, "quem sai do mundo desmonta")


func _test_recorded() -> void:
	for surface in ["grama", "terra", "neve", "madeira"]:
		_check(HorseSounds.has_hooves(surface), "cascos gravados: %s" % surface)
		_check(not HorseSounds._recorded("galope_" + surface).is_empty(), "galope gravado: %s" % surface)
	for kind in ["relincho", "bufo", "manso", "pasto", "alarme"]:
		_check(HorseSounds.voice(kind) != null, "voz: %s" % kind)


func _test_sounds() -> void:
	for kind in ["relincho", "alarme", "bufo", "pasto", "manso"]:
		for v in HorseSounds.VARIANTS:
			var s := HorseSounds.generated(kind, v) as AudioStreamWAV
			_check(s != null and s.data.size() > 2000, "som gerado: %s %d" % [kind, v])
	for surface in HorseSounds.SURFACES:
		for gallop in [false, true]:
			var s := HorseSounds.generated(("galope_" if gallop else "casco_") + surface, 0) as AudioStreamWAV
			_check(s != null and s.data.size() > 2000, "cascos gerados: %s" % surface)


func _export(folder: String) -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	for kind in ["relincho", "alarme", "bufo", "pasto", "manso"]:
		for v in HorseSounds.VARIANTS:
			(HorseSounds.generated(kind, v) as AudioStreamWAV).save_to_wav("%s/%s_%d.wav" % [folder, kind, v])
	for surface in HorseSounds.SURFACES:
		(HorseSounds.generated("casco_" + surface, 0) as AudioStreamWAV).save_to_wav("%s/casco_%s.wav" % [folder, surface])
		(HorseSounds.generated("galope_" + surface, 0) as AudioStreamWAV).save_to_wav("%s/galope_%s.wav" % [folder, surface])
	print("sons salvos em ", folder)
