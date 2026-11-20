extends SceneTree
## Testes do ciclo de dia e noite: as fases e o escuro, o relógio no mundo
## salvo, o Calado só de noite e os pássaros dormindo à noite.
## Rodar: godot --headless --path . --script res://tests/test_dia_noite.gd

var _failures := 0


func _init() -> void:
	_test_phases()
	_test_describe()
	_test_moments()
	_test_save()
	_test_horror_only_at_night()
	_test_horror_leaves_at_dawn()
	_test_birds_sleep()
	if _failures == 0:
		print("OK: dia e noite passaram")
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FALHOU: " + message)


func _at(hour: float) -> float:
	return DayCycle.hour_to_t(hour)


func _test_phases() -> void:
	_check(DayCycle.phase_of(_at(0.0)) == DayCycle.Phase.NIGHT, "meia-noite é noite")
	_check(DayCycle.phase_of(_at(4.9)) == DayCycle.Phase.NIGHT, "4h54 ainda é noite")
	_check(DayCycle.phase_of(_at(5.0)) == DayCycle.Phase.DAWN, "5h amanhece")
	_check(DayCycle.phase_of(_at(7.0)) == DayCycle.Phase.DAY, "7h é dia")
	_check(DayCycle.phase_of(_at(17.9)) == DayCycle.Phase.DAY, "17h54 ainda é dia")
	_check(DayCycle.phase_of(_at(18.0)) == DayCycle.Phase.DUSK, "18h entardece")
	_check(DayCycle.phase_of(_at(20.0)) == DayCycle.Phase.NIGHT, "20h anoitece")
	_check(DayCycle.phase_of(_at(23.9)) == DayCycle.Phase.NIGHT, "23h54 é noite")
	_check(DayCycle.is_night(_at(22.0)) and not DayCycle.is_night(_at(12.0)), "só a noite é noite")
	_check(is_equal_approx(DayCycle.darkness(_at(12.0)), 0.0), "meio-dia sem escuro")
	_check(is_equal_approx(DayCycle.darkness(_at(2.0)), 1.0), "madrugada escura")
	var dusk := DayCycle.darkness(_at(19.0))
	_check(dusk > 0.3 and dusk < 0.7, "no meio do entardecer, meio escuro")
	_check(DayCycle.darkness(_at(6.0)) > DayCycle.darkness(_at(6.5)), "o escuro diminui ao amanhecer")
	_check(is_equal_approx(DayCycle.hour_of(DayCycle.hour_to_t(30.0)), 6.0), "horas dão a volta")
	_check(is_equal_approx(DayCycle.seconds_to_next_phase(_at(17.0), 1800.0), 75.0), "uma hora do jogo são 75 s num dia de 30 min")
	_check(is_equal_approx(DayCycle.seconds_to_next_phase(_at(22.0), 1800.0), 7.0 * 75.0), "da 22h às 5h são 7 horas")


func _test_describe() -> void:
	_check(DayCycle.PERIODS[DayCycle.period_of(_at(14.5))][0] == "Tarde", "14h30 é tarde")
	_check(DayCycle.PERIODS[DayCycle.period_of(_at(3.0))][0] == "Noite profunda", "3h é noite profunda")
	_check(DayCycle.PERIODS[DayCycle.period_of(_at(19.5))][0] == "Anoitecer", "19h30 é anoitecer")
	_check(DayCycle.PERIODS[DayCycle.period_of(_at(23.0))][0] == "Noite", "23h é noite")
	_check(DayCycle.PERIODS[DayCycle.period_of(_at(12.0))][0] == "Meio-dia", "12h é meio-dia")
	_check(is_equal_approx(DayCycle.seconds_to_next_period(_at(23.0), 1800.0), 75.0), "da 23h à meia-noite é uma hora")
	var text := DayCycle.describe(_at(14.5), 1800.0)
	_check(text.begins_with("Tarde. ") and text.contains("minuto"), "descreve a tarde: " + text)
	var digits := RegEx.create_from_string("[0-9]")
	for i in DayCycle.PERIODS.size():
		var hour: float = DayCycle.PERIODS[i][1]
		_check(DayCycle.period_of(_at(hour)) == i, "o período %d começa na hora dele" % i)
		_check(digits.search(DayCycle.announcement(i)) == null, "o aviso do período %d não traz hora numérica" % i)
		_check(digits.search(DayCycle.describe(_at(hour), 1800.0).split(";")[0].split(". ")[0]) == null, "a resposta não começa com hora numérica")


func _test_moments() -> void:
	var secs := 1800.0
	var coro := DayCycle.moment_hour("coro", secs)
	_check(coro < DayCycle.DAWN_HOUR and DayCycle.phase_of(DayCycle.hour_to_t(coro)) == DayCycle.Phase.NIGHT, "o atalho do coro cai pouco antes do amanhecer")
	_check(is_equal_approx(DayCycle.seconds_to_next_phase(DayCycle.hour_to_t(coro), secs), DayCycle.JUMP_LEAD), "a virada vem em JUMP_LEAD segundos")
	var noite := DayCycle.moment_hour("noite", secs)
	_check(DayCycle.phase_of(DayCycle.hour_to_t(noite)) == DayCycle.Phase.DUSK, "o atalho da noite cai pouco antes de anoitecer")
	_check(is_equal_approx(DayCycle.moment_hour("meio_dia", secs), 12.0), "meio-dia exato")
	var grilos := DayCycle.moment_hour("grilos", secs)
	_check(DayCycle.darkness(DayCycle.hour_to_t(grilos)) < 0.2 and DayCycle.darkness(DayCycle.hour_to_t(grilos)) > 0.05, "os grilos começam a se ouvir")
	_check(DayCycle.moment_hour("nada", secs) < 0.0, "momento desconhecido")
	for moment in DayCycle.MOMENTS:
		_check(DayCycle.moment_hour(moment[0], secs) >= 0.0, "momento %s existe" % moment[0])
	_check(SoundBank.frogs().data.size() > 0 and SoundBank.crickets().data.size() > 0, "sons da noite gerados")


func _test_save() -> void:
	var state := WorldState.new(42)
	_check(is_equal_approx(DayCycle.hour_of(state.day_t), DayCycle.START_HOUR), "mundo novo começa de manhã")
	state.day_t = _at(21.0)
	var loaded := WorldState.from_save(JSON.parse_string(JSON.stringify(state.to_save())))
	_check(is_equal_approx(loaded.day_t, state.day_t), "a hora do mundo volta do save")
	var old := state.to_save()
	old.erase("day_t")
	var legacy := WorldState.from_save(JSON.parse_string(JSON.stringify(old)))
	_check(is_equal_approx(DayCycle.hour_of(legacy.day_t), DayCycle.START_HOUR), "save antigo, sem hora, começa de manhã")


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
					if world.biome_at(cell) == WorldGen.Biome.BOSQUE and not world.is_trail(cell):
						return point
	return Vector2.ZERO


func _player(pos: Vector2) -> Dictionary:
	return {"name": "Teste", "pos": pos, "heading": 0}


## Anda a simulação até o Calado aparecer; devolve quantos segundos levou (-1: não veio).
func _until_appears(horrors: Horrors, players: Dictionary, night: bool, seconds: float) -> float:
	var t := 0
	while t < int(seconds * 1000.0):
		horrors.update(t, players, [], night)
		if not horrors.horrors.is_empty():
			return t / 1000.0
		t += 250
	return -1.0


func _test_horror_only_at_night() -> void:
	var world := WorldGen.new(42)
	var spot := _forest_spot(world)
	var long := Horrors.EXPOSURE[1] + 30.0
	var day := Horrors.new(world)
	_check(_until_appears(day, {1: _player(spot)}, false, long * 3.0) < 0.0, "de dia o Calado não aparece, por mais que se fique exposto")
	var night := Horrors.new(world)
	_check(_until_appears(night, {1: _player(spot)}, true, long) >= 0.0, "de noite o Calado aparece")
	# Batidas de pedra de dia não o atraem.
	var quiet := Horrors.new(world)
	quiet.update(0, {1: _player(spot)}, [], false)
	quiet.hear_noise(1, 500.0)
	quiet.update(250, {1: _player(spot)}, [], false)
	_check(quiet.horrors.is_empty(), "o barulho de dia não chama o Calado")


func _test_horror_leaves_at_dawn() -> void:
	var world := WorldGen.new(42)
	var spot := _forest_spot(world)
	var horrors := Horrors.new(world)
	var players := {1: _player(spot)}
	horrors.summon(1, players, 25.0)
	horrors.update(0, players, [], true)
	_check(not horrors.horrors.is_empty(), "o Calado caça de noite")
	# Amanheceu: ele recua e some, sem alcançar ninguém.
	var caught := false
	var t := 250
	while t < 60000 and not horrors.horrors.is_empty():
		for message in horrors.update(t, players, [], false):
			if message[1] == "caught":
				caught = true
		t += 250
	_check(horrors.horrors.is_empty(), "ao amanhecer o Calado some")
	_check(not caught, "ao amanhecer ele não alcança ninguém")


## Um ponto de bosque com poleiros por perto: o meio de um pedaço da orla do
## bosque, onde ficam os arbustos (o miolo do bosque quase não tem poleiros).
func _forest_point(world: WorldGen) -> Vector2:
	var chunks := WorldGen.REGION_SIZE / WorldGen.CHUNK
	for r in range(1, 40):
		for region in [Vector2i(r, 0), Vector2i(-r, 0), Vector2i(0, r), Vector2i(0, -r)]:
			if world.region_biome(region) != WorldGen.Biome.BOSQUE:
				continue
			var first: Vector2i = region * WorldGen.REGION_SIZE - Vector2i.ONE * (WorldGen.REGION_SIZE / 2)
			for cy in chunks:
				for cx in chunks:
					var origin := first + Vector2i(cx, cy) * WorldGen.CHUNK
					var middle := origin + Vector2i.ONE * (WorldGen.CHUNK / 2)
					if world.biome_at(middle) != WorldGen.Biome.BOSQUE:
						continue
					var bushes := 0
					for y in WorldGen.CHUNK:
						for x in WorldGen.CHUNK:
							if world.thing_at(origin + Vector2i(x, y)) == WorldGen.Thing.ARBUSTO:
								bushes += 1
					if bushes >= 8:
						return WorldGen.cell_center(middle)
	return Vector2.ZERO


func _songs(world: WorldGen, spot: Vector2, darkness: float, dawn := false) -> Dictionary:
	var aviary := Aviary.new(world)
	aviary.darkness = darkness
	aviary.dawn = dawn
	var players := {1: spot}
	var songs := {"dia": 0, "coruja": 0, "voos_dia": 0}
	var t := 0
	while t < 600000:
		for message in aviary.update(t, players):
			var species := -1
			if aviary.birds.has(message[2][0]):
				species = int(aviary.birds[message[2][0]]["species"])
			if message[1] == "sing":
				songs["coruja" if species == Aviary.Species.CORUJA else "dia"] += 1
			elif message[1] == "fly" and species != Aviary.Species.CORUJA and not bool(message[2][6]):
				songs["voos_dia"] += 1
		t += 250
	return songs


func _test_birds_sleep() -> void:
	var world := WorldGen.new(42)
	var spot := _forest_point(world)
	_check(spot != Vector2.ZERO, "deveria haver um bosque com poleiros")
	var day := _songs(world, spot, 0.0)
	_check(int(day["dia"]) > 0, "de dia os pássaros cantam")
	_check(int(day["coruja"]) == 0, "de dia a coruja dorme")
	var night := _songs(world, spot, 1.0)
	_check(int(night["dia"]) == 0, "de noite os pássaros do dia não cantam")
	_check(int(night["voos_dia"]) == 0, "de noite os pássaros do dia não trocam de poleiro")
	var chorus := _songs(world, spot, 0.3, true)
	_check(int(chorus["dia"]) > int(day["dia"]), "ao amanhecer, o coro canta mais que de dia")
