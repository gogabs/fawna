extends SceneTree
## Testes do ciclo de dia e noite: as fases e o escuro, o relógio no mundo
## salvo, o Calado só de noite e os pássaros dormindo à noite.
## Rodar: godot --headless --path . --script res://tests/test_dia_noite.gd

var _failures := 0


func _init() -> void:
	_test_phases()
	_test_describe()
	_test_ring()
	_test_seasons()
	_test_sky_text()
	_test_where()
	_test_moments()
	_test_save()
	_test_horror_only_at_night()
	_test_horror_leaves_at_dawn()
	_test_horror_ring()
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
	var names := []
	for entry in DayCycle.PERIODS:
		names.append(entry[0])
	_check(names[DayCycle.period_of(_at(14.5))] == "Tarde", "14h30 é tarde")
	_check(names[DayCycle.period_of(_at(3.0))] == "Noite profunda", "3h é noite profunda")
	_check(names[DayCycle.period_of(_at(19.5))] == "Anoitecer", "19h30 é anoitecer")
	_check(names[DayCycle.period_of(_at(23.0))] == "Noite", "23h é noite")
	_check(names[DayCycle.period_of(_at(12.0))] == "Meio-dia", "12h é meio-dia")
	_check(is_equal_approx(DayCycle.seconds_to_next_period(_at(23.0), 1800.0), 75.0), "da 23h à meia-noite é uma hora")
	var text := DayCycle.describe(_at(14.5), 36.0)
	_check(text.begins_with("Tarde, na estação do Anel Alto. ") and not text.contains("minuto"), "descreve a tarde com a estação: " + text)
	var digits := RegEx.create_from_string("[0-9]")
	for i in DayCycle.PERIODS.size():
		_check(DayCycle.period_of(_at(DayCycle.period_start(i))) == i, "o período %d começa na hora dele" % i)
		_check(digits.search(DayCycle.announcement(i)) == null and digits.search(DayCycle.announcement(i, true)) == null, "o aviso do período %d não traz hora numérica" % i)
		_check(digits.search(DayCycle.describe(_at(DayCycle.period_start(i)), 10.0)) == null, "o T não traz número")
		if i != 6:  # o anoitecer tem uma frase só, para a faixa e para fora dela
			_check(DayCycle.announcement(i) != DayCycle.announcement(i, true), "o período %d tem texto próprio dentro da faixa do anel" % i)
		for word in ["pássaro", "grilo", "coruja"]:
			_check(not DayCycle.announcement(i).to_lower().contains(word) and not DayCycle.announcement(i, true).to_lower().contains(word), "o texto não cita %s" % word)


func _test_ring() -> void:
	DayCycle.shift_hours = 0.0
	# Faixa no centro: forte; no meio entre faixas: zero. Repete a cada RING_SPACING.
	var d := 0.0
	var center := DayCycle.ring_center(d)
	_check(is_equal_approx(DayCycle.ring_strength(center, d), 1.0), "no miolo da faixa, 1")
	_check(is_equal_approx(DayCycle.ring_strength(center + DayCycle.RING_SPACING * 0.5, d), 0.0), "entre as faixas, 0")
	_check(is_equal_approx(DayCycle.ring_strength(center + DayCycle.RING_SPACING * 7.0, d), 1.0), "a faixa se repete ao longo do mundo")
	_check(is_equal_approx(DayCycle.ring_strength(center - DayCycle.RING_SPACING * 12.0, d), 1.0), "e também para o outro lado")
	_check(DayCycle.ring_strength(center + DayCycle.RING_WIDTH * 0.5 + 1.0, d) < 0.01, "passou da largura, nada")
	var edge := DayCycle.ring_strength(center + DayCycle.RING_WIDTH * 0.37, d)
	_check(edge > 0.01 and edge < 0.99, "a borda é suave")
	# O sinal: a faixa ao norte (y menor) dá deslocamento negativo.
	_check(DayCycle.ring_offset(center + 100.0, d) < 0.0, "a faixa está ao norte de quem está ao sul dela")
	_check(DayCycle.ring_offset(center - 100.0, d) > 0.0, "e ao sul de quem está ao norte")
	# O ano: vai ao extremo norte no Anel Alto, ao sul no Anel Baixo, e volta.
	_check(is_equal_approx(DayCycle.ring_center(36.0), -DayCycle.RING_TRAVEL), "no Anel Alto a faixa está no extremo norte")
	_check(is_equal_approx(DayCycle.ring_center(108.0), DayCycle.RING_TRAVEL), "no Anel Baixo, no extremo sul")
	_check(absf(DayCycle.ring_center(144.0)) < 0.001, "o ano fecha")
	# Um lugar fixo vê a sombra passar ao longo do ano; a faixa nunca cruza outra.
	var seen := 0
	for day in 144:
		if DayCycle.ring_strength(-400.0, float(day)) > 0.5:
			seen += 1
	_check(seen > 0 and seen < 144, "um lugar vê a sombra passar e sair ao longo do ano (%d dias)" % seen)
	_check(DayCycle.RING_TRAVEL * 2.0 <= DayCycle.RING_SPACING, "as faixas nunca se cruzam")


func _test_seasons() -> void:
	_check(DayCycle.season_of(36.0) == 0 and DayCycle.season_of(72.0) == 1 and DayCycle.season_of(108.0) == 2 and DayCycle.season_of(140.0) == 3, "as estações vêm na ordem")
	_check(DayCycle.season_of(0.0) == 3 and DayCycle.season_of(17.9) == 3 and DayCycle.season_of(18.0) == 0, "o ano começa na Luz Subindo e vira no dia 18")
	_check(DayCycle.season_of(36.0 + 144.0) == 0, "o ano se repete")
	_check(is_equal_approx(DayCycle.season_shift(36.0), DayCycle.SHIFT_MAX), "no Anel Alto a noite encurta")
	_check(is_equal_approx(DayCycle.season_shift(108.0), -DayCycle.SHIFT_MAX), "no Anel Baixo a noite estica")
	_check(absf(DayCycle.season_shift(72.0)) < 0.001, "entre as duas, a noite é normal")
	DayCycle.shift_hours = DayCycle.season_shift(36.0)
	_check(DayCycle.is_night(_at(4.0)) and not DayCycle.is_night(_at(4.6)) and DayCycle.is_night(_at(20.6)) and not DayCycle.is_night(_at(20.4)), "o Anel Alto tem noite de 20h30 às 4h30")
	var short_night := 24.0 - DayCycle.night_hour() + DayCycle.dawn_hour()
	DayCycle.shift_hours = DayCycle.season_shift(108.0)
	var long_night := 24.0 - DayCycle.night_hour() + DayCycle.dawn_hour()
	_check(short_night < 9.0 and long_night > 9.0, "a noite do Anel Alto é mais curta que a do Anel Baixo")
	for i in DayCycle.PERIODS.size():
		_check(DayCycle.period_of(_at(DayCycle.period_start(i))) == i, "com a noite esticada, o período %d ainda começa na hora dele" % i)
	DayCycle.shift_hours = 0.0
	_check(DayCycle.calado_rate(36.0) < 1.0 and DayCycle.calado_rate(108.0) > 1.0, "o Calado demora mais no Anel Alto e menos no Anel Baixo")
	_check(is_equal_approx(DayCycle.calado_rate(36.0), 0.8) and is_equal_approx(DayCycle.calado_rate(108.0), 1.2), "20% para cada lado")
	_check(DayCycle.darkness_with_ring(_at(12.0), 1.0) > 0.4 and DayCycle.darkness_with_ring(_at(12.0), 0.0) == 0.0, "a sombra escurece o dia")
	_check(is_equal_approx(DayCycle.darkness_with_ring(_at(2.0), 1.0), 1.0), "e não passa do escuro da noite")


func _test_sky_text() -> void:
	_check(DayCycle.sky_text(_at(15.0), 1.0, 0.0) == "É a tarde, sob a sombra do anel.", "sob a sombra")
	_check(DayCycle.sky_text(_at(23.0), 1.0, 0.0) == "É a noite, sob a luz do anel.", "sob a luz")
	_check(DayCycle.sky_text(_at(15.0), 0.0, -600.0).contains("logo ao norte"), "a faixa perto, ao norte")
	_check(DayCycle.sky_text(_at(23.0), 0.0, 600.0).contains("logo ao sul"), "a faixa perto, ao sul")
	_check(DayCycle.sky_text(_at(15.0), 0.0, 2000.0).contains("pálido"), "o anel longe, de dia")
	_check(DayCycle.sky_text(_at(23.0), 0.0, 2000.0).contains("ao longe"), "o anel longe, de noite")
	_check(DayCycle.sky_text(_at(6.0), 0.0, 2000.0).begins_with("É o amanhecer"), "o artigo certo")
	_check(DayCycle.ring_edge_text(false, true).contains("sombra") and DayCycle.ring_edge_text(true, true).contains("luz"), "avisos de entrada na faixa")


func _test_where() -> void:
	var world := WorldGen.new(42)
	var text := Narrator.stepping_on(world, Vector2(3.5, 3.5), 2)
	_check(text.ends_with("olhando para o leste.") and not text.begins_with("Você"), "o C diz o lugar e a direção: " + text)
	_check(text.substr(0, 1) == text.substr(0, 1).to_upper(), "começa com maiúscula: " + text)


func _test_moments() -> void:
	var secs := 1800.0
	var coro := DayCycle.moment_hour("coro", secs)
	_check(coro < DayCycle.dawn_hour() and DayCycle.phase_of(DayCycle.hour_to_t(coro)) == DayCycle.Phase.NIGHT, "o atalho do coro cai pouco antes do amanhecer")
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
	state.day_n = 40
	var loaded := WorldState.from_save(JSON.parse_string(JSON.stringify(state.to_save())))
	_check(is_equal_approx(loaded.day_t, state.day_t), "a hora do mundo volta do save")
	_check(loaded.day_n == 40, "os dias do mundo voltam do save")
	_check(WorldState.new(42).day_n == DayCycle.START_DAY, "mundo novo começa no dia %d" % DayCycle.START_DAY)
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


## Em quantos segundos o Calado aparece sozinho, com a luz do anel e o ritmo dados.
func _appears_in(world: WorldGen, spot: Vector2, light: float, rate: float) -> float:
	var horrors := Horrors.new(world)
	var players := {1: _player(spot)}
	var t := 0
	while t < 600000:
		horrors.update(t, players, [], true, {1: light}, rate)
		if not horrors.horrors.is_empty():
			return t / 1000.0
		t += 250
	return -1.0


func _test_horror_ring() -> void:
	var world := WorldGen.new(42)
	var spot := _forest_spot(world)
	var plain := _appears_in(world, spot, 0.0, 1.0)
	var lit := _appears_in(world, spot, 1.0, 1.0)
	_check(plain > 0.0 and lit > 0.0, "o Calado aparece com ou sem a luz do anel")
	_check(lit > plain, "na luz do anel ele demora mais (%.0f s contra %.0f s)" % [lit, plain])
	var slow := _appears_in(world, spot, 0.0, 0.8)
	var fast := _appears_in(world, spot, 0.0, 1.2)
	_check(slow > fast, "no Anel Alto ele demora mais que no Anel Baixo (%.0f s contra %.0f s)" % [slow, fast])
	# Dentro da luz ele chega mais devagar e precisa chegar mais perto.
	var pos_plain := _stalk_distance(world, spot, 0.0)
	var pos_lit := _stalk_distance(world, spot, 1.0)
	_check(pos_lit > pos_plain, "na luz ele fica mais longe depois de 10 s (%.1f contra %.1f)" % [pos_lit, pos_plain])
	_check(Horrors.CATCH_RANGE * (1.0 - Horrors.RING_CATCH_SHRINK) < Horrors.CATCH_RANGE, "alcança de mais perto na luz")


## Distância do Calado ao alvo depois de 10 s de caça, parado ele, com a luz dada.
func _stalk_distance(world: WorldGen, spot: Vector2, light: float) -> float:
	var horrors := Horrors.new(world)
	var players := {1: _player(spot)}
	horrors.summon(1, players, 20.0)
	for step in 40:
		horrors.update(step * 250, players, [], true, {1: light}, 1.0)
	var horror: Dictionary = horrors.horrors.values()[0]
	return (horror["pos"] as Vector2).distance_to(spot)


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
