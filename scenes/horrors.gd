extends Node
## Os horrores na rede. Este nó existe igual no servidor e nos clientes
## (/root/Game/Horrors), porque é por ele que passam as chamadas de rede.
##
## No servidor, roda a simulação (Horrors) e manda a cada jogador onde estão
## os horrores perto dele. No cliente, cuida do som: quanto mais perto o
## Calado, mais o mundo inteiro fica abafado e baixo; a respiração dele
## soa no lugar onde ele está, e ela se cala
## quando a criatura vira de frente para ele.

const STEP_SECONDS := 0.25  # passo da simulação no servidor
const STALE_SECONDS := 2.0  # sem notícias por esse tempo, o cliente o esquece
const OPEN_HZ := 20000.0
const HUSHED_HZ := 900.0  # passa-baixa do mundo com ele ao lado
const HUSHED_DB := -6.0  # e o volume geral cai junto
const INDOOR_HUSH := 0.6  # dentro do abrigo: abafado, mas menos que o horror
const PRESENCE_RISE := 0.5  # por segundo: o abafamento chega devagar
const PRESENCE_FALL := 0.35
const BREATH_DB := -8.0
const BREATH_FADE := 40.0  # dB por segundo
const BREATH_CUT := 240.0  # encarado, ele prende a respiração de uma vez
const BREATH_HEIGHT := 1.7  # metros
const SILENT_DB := -80.0

var horrors: Horrors  # só no servidor
var _step := 0.0

# Lado do cliente
var _audio: SpatialAudio
var _known := {}  # id -> { pos: Vector2, shown: Vector2, mode, seen: s }
var _clock := 0.0
var _caught := false
var _presence := 0.0  # 0 (longe) a 1 (ao lado)
var _breath: AudioStreamPlayer3D
var _filter: AudioEffectLowPassFilter
var _touched_master := false
var _indoors := 0.0  # 0 fora, 1 dentro de paredes fechadas


func start_server(world: WorldGen) -> void:
	horrors = Horrors.new(world)


func start_client(audio: SpatialAudio) -> void:
	_audio = audio
	if _breath == null:
		_breath = audio.make_far_voice(Horrors.HEARING)
		if _breath != null:
			_breath.name = "Calado"
			_breath.stream = HorrorSounds.calado_breath()
			_breath.volume_db = SILENT_DB
	if _filter == null and DisplayServer.get_name() != "headless":
		_filter = AudioEffectLowPassFilter.new()
		_filter.cutoff_hz = OPEN_HZ
		AudioServer.add_bus_effect(_master(), _filter)


func _exit_tree() -> void:
	if _filter != null:
		var master := _master()
		for i in AudioServer.get_bus_effect_count(master):
			if AudioServer.get_bus_effect(master, i) == _filter:
				AudioServer.remove_bus_effect(master, i)
				break
		_filter = null
	if _touched_master:
		AudioServer.set_bus_volume_db(_master(), Music.MASTER_DB)
	HorrorSounds.clear()


func forget_peer(peer: int) -> void:
	if horrors != null:
		horrors.forget_peer(peer)


func _process(delta: float) -> void:
	_clock += delta
	if horrors != null:
		_step += delta
		if _step >= STEP_SECONDS:
			_step = 0.0
			_server_step()
	if _audio != null:
		_client_step(delta)


# --- Servidor ------------------------------------------------------------------

func _server_step() -> void:
	var game := get_parent()
	if game.state == null:
		return
	for message in horrors.update(Time.get_ticks_msec(), game.state.players, _lit_fires(game.state.builds) + game.state.lit_torches(), game.daytime.is_night(), game.daytime.ring_lights(game.state.players), game.daytime.calado_rate()):
		var peer: int = message[0]
		var args: Array = message[2]
		match message[1]:
			"at":
				horror_at.rpc_id(peer, args[0], args[1], args[2])
			"gone":
				horror_gone.rpc_id(peer, args[0])
			"caught":
				_catch(peer)
	if game.birds.aviary != null:
		game.birds.aviary.hush = horrors.points()


## O Calado alcançou o jogador: ele perde os recursos e reaparece no ponto
## seguro mais próximo (fogueira acesa, povoado ou cruzamento de trilhas).
func _catch(peer: int) -> void:
	var game := get_parent()
	var state: WorldState = game.state
	if not state.players.has(peer):
		return
	var shelters := _lit_fires(state.builds)
	for settlement: Dictionary in state.builds.settlements():
		shelters.append(WorldGen.cell_center(settlement["cell"]))
	var blocked := state.builds.all().map(func(build: Dictionary): return build["cell"])
	var from: Vector2 = state.players[peer]["pos"]
	var spot := Horrors.landing_spot(state.world, Horrors.nearest_shelter(state.world, from, shelters), blocked)
	var lost := state.strip_resources(peer)
	state.teleport(peer, spot)
	game.inventory_changed.rpc_id(peer, state.inventory_of(peer), "", "")
	game.player_moved.rpc(peer, spot)
	horror_caught.rpc_id(peer, spot, not lost.is_empty())
	print("[servidor] Calado alcançou %s: levado a %s, perdeu %s" % [state.players[peer]["name"], spot, lost])


func _lit_fires(builds: Builds) -> Array:
	var fires := []
	for build: Dictionary in builds.all():
		if build["kind"] == "fogueira" and builds.is_lit(int(build["id"])):
			fires.append(WorldGen.cell_center(build["cell"]))
	return fires


## Um barulho de quem está aí (as batidas ao acender a tocha): conta como
## "seconds" de tempo exposto a mais, e o Calado pode aparecer mais cedo.
func hear_noise(peer: int, seconds: float) -> void:
	if horrors != null:
		horrors.hear_noise(peer, seconds)


## O uivo afasta o Calado a até "radius" casas de "pos".
func repel(pos: Vector2, radius: float) -> int:
	if horrors == null:
		return 0
	return horrors.repel(pos, radius, get_parent().state.players)


## Testes: faz o Calado aparecer atrás de um jogador, a "distance" casas.
func summon(peer: int, distance := Horrors.SPAWN_DISTANCE) -> int:
	if horrors == null:
		return -1
	return horrors.summon(peer, get_parent().state.players, distance)


## Depuração: manda os Calados embora (e avisa quem os ouvia).
func debug_dismiss() -> int:
	if horrors == null:
		return 0
	var count := horrors.horrors.size()
	for message in horrors.dismiss_all(Time.get_ticks_msec()):
		if message[1] == "gone":
			horror_gone.rpc_id(message[0], message[2][0])
	return count


## Depuração: liga ou desliga as aparições sozinhas do Calado.
func debug_set_spawning(on: bool) -> void:
	if horrors != null:
		horrors.spawning = on


# --- Avisos do servidor (executados nos clientes) ------------------------------

@rpc("authority", "call_local", "unreliable_ordered")
func horror_at(id: int, pos: Vector2, mode: int) -> void:
	if _known.has(id):
		_known[id]["pos"] = pos
		_known[id]["mode"] = mode
		_known[id]["seen"] = _clock
	else:
		_known[id] = {"pos": pos, "shown": pos, "mode": mode, "seen": _clock}


@rpc("authority", "call_local", "reliable")
func horror_gone(id: int) -> void:
	_known.erase(id)


## O Calado alcançou esta criatura: o som se fecha, ela é levada e reaparece
## no ponto seguro. Ao voltar a si, uma fala curta.
@rpc("authority", "call_local", "reliable")
func horror_caught(spot: Vector2, _lost_something: bool) -> void:
	var game := get_parent()
	if game.world == null or _caught:
		return
	_caught = true
	_known.clear()
	game._play(HorrorSounds.caught())
	await get_tree().create_timer(HorrorSounds.CAUGHT_SECONDS).timeout
	game._set_pos(spot)
	game._last_sent = spot
	game._play(HorrorSounds.relief())
	await get_tree().create_timer(HorrorSounds.RELIEF_SECONDS).timeout
	_caught = false
	Speech.say("Você acorda em outro lugar, sem lembrança do que aconteceu.")


## Os horrores conhecidos agora (id -> { pos casas, mode }), para a vista 3D.
func shown_horrors() -> Dictionary:
	var out := {}
	for id: int in _known:
		out[id] = {"pos": _known[id]["shown"], "mode": int(_known[id]["mode"])}
	return out


## Levada pelo Calado: a criatura não anda até reaparecer.
func is_caught() -> bool:
	return _caught


# --- Som -----------------------------------------------------------------------

## Quanto o Calado pesa agora sobre o som: 0 (longe) a 1 (ao lado).
func presence() -> float:
	return _presence


## Distância, em casas, até o horror mais próximo (INF se não há nenhum).
func nearest_distance() -> float:
	var nearest := _nearest()
	if nearest.is_empty():
		return INF
	return (nearest["shown"] as Vector2).distance_to(get_parent()._pos)


func _client_step(delta: float) -> void:
	var game := get_parent()
	if game.world == null:
		return
	for id in _known.keys():
		var horror: Dictionary = _known[id]
		if _clock - float(horror["seen"]) > STALE_SECONDS:
			_known.erase(id)
			continue
		# As posições chegam 4 vezes por segundo: desliza até a mais nova.
		horror["shown"] = (horror["shown"] as Vector2).lerp(horror["pos"], minf(1.0, delta * 6.0))
	var nearest := _nearest()
	var wanted := 0.0 if nearest.is_empty() else Horrors.presence_at(nearest_distance())
	var rate := PRESENCE_RISE if wanted > _presence else PRESENCE_FALL
	_presence = move_toward(_presence, wanted, rate * delta)
	_indoors = move_toward(_indoors, _indoor_target(game), delta / 0.6)
	_apply_hush()
	_update_breath(nearest, delta)


func _nearest() -> Dictionary:
	var me: Vector2 = get_parent()._pos
	var best := {}
	for horror: Dictionary in _known.values():
		if best.is_empty() or (horror["shown"] as Vector2).distance_to(me) < (best["shown"] as Vector2).distance_to(me):
			best = horror
	return best


## Abafa e abaixa o mundo inteiro (a fala não passa pelo Master e continua
## clara).
func _apply_hush() -> void:
	if _filter == null:
		return
	# Na escala das oitavas, para o ouvido sentir o filtro fechar por igual.
	var hush := maxf(_presence, _indoors * INDOOR_HUSH)
	_filter.cutoff_hz = OPEN_HZ * pow(HUSHED_HZ / OPEN_HZ, hush)
	if hush > 0.0 or _touched_master:
		_touched_master = hush > 0.0
		AudioServer.set_bus_volume_db(_master(), Music.MASTER_DB + HUSHED_DB * hush)


## 1 dentro de uma construção grande de paredes de pé (porta fechada), metade
## com a porta aberta, 0 fora dela.
func _indoor_target(game: Node) -> float:
	var cell := WorldGen.cell_of(game._pos)
	var build: Dictionary = game.builds.at(cell)
	if build.is_empty() or not Crafting.is_large(build["kind"]) or not Builds.walls_up(build):
		return 0.0
	if cell == Builds.door_cell(build["cell"], int(build["size"]), str(build["entrance"])):
		return 0.5
	return 0.5 if bool(build.get("door_open", false)) else 1.0


## A respiração soa no silêncio que o próprio Calado causa, e some
## quando a criatura o encara: é assim que se descobre onde ele está.
func _update_breath(nearest: Dictionary, delta: float) -> void:
	if _breath == null:
		return
	var game := get_parent()
	var target := SILENT_DB
	var rate := BREATH_FADE
	if not nearest.is_empty():
		var pos: Vector2 = nearest["shown"]
		_breath.position = Aviary.to_3d(pos, BREATH_HEIGHT)
		if Horrors.is_facing(game._pos, game._heading, pos):
			rate = BREATH_CUT
		else:
			# Compensa o que o próprio abafamento tira dela.
			target = BREATH_DB - HUSHED_DB * _presence + (SpatialAudio.HRTF_GAIN_DB if _audio.using_hrtf else 0.0)
	_breath.volume_db = move_toward(_breath.volume_db, target, rate * delta)
	if _breath.volume_db > SILENT_DB + 1.0:
		if not _breath.playing:
			_breath.play()
	elif _breath.playing:
		_breath.stop()


func _master() -> int:
	return AudioServer.get_bus_index("Master")
