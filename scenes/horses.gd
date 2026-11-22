extends Node
## Os cavalinhos-da-bruma na rede. Existe igual no servidor e nos clientes
## (/root/Game/Horses), porque é por ele que passam as chamadas de rede.
##
## No servidor, roda a simulação (Herd) e manda a cada jogador só o que
## acontece perto dele. No cliente, guarda onde cada cavalo está, toca os
## cascos enquanto ele anda (o som muda com o chão) e os bufos, relinchos e
## mastigadas no lugar certo, com HRTF quando houver. As fontes são fixas e
## reaproveitadas (o Steam Audio às vezes não pega fontes criadas na hora).

const STEP_SECONDS := 0.25
const VOICES := 16
const REACH := Herd.HEARING
const STEP_REACH := 22.0  # casas: mais longe que isso, os cascos não tocam
## Cadência dos cascos. Andando, quatro pisadas por passada, com balanço
## longo-curto (segundos entre uma e outra); galopando, uma passada inteira
## (as quatro batidas, o corpo e o fôlego já vêm no arquivo) a cada
## GALLOP_STRIDE. O andamento flutua devagar, sem passar dos limites, para não
## soar como metrônomo nem correr ou arrastar demais.
const WALK_GAPS := [0.26, 0.24, 0.26, 0.24]
const WALK_TEMPO := [0.9, 1.1]
const GALLOP_STRIDE := 0.42
const GALLOP_TEMPO := [0.93, 1.08]
## Bufadas de vez em quando enquanto andam ou galopam (segundos).
const WALK_SNORTS := [4.0, 8.0]
const GALLOP_SNORTS := [2.5, 5.0]
## Volume de cada som. Tudo bem baixinho, como o resto do mundo. Os cascos
## gravados estão 14 dB abaixo nos arquivos (para caber o pico sem distorcer).
## No jogo, o Gabs achou tudo alto, o galope principalmente: o geral desceu
## 6 dB, os cascos mais 4 e o galope mais 8.
const HORSES_DB := -16.0
const SOUND_DB := {"casco": 0.0, "galope": -4.0, "casco_gerado": -14.0, "galope_gerado": -10.0, "pasto": -18.0, "bufo": -10.0, "manso": -10.0, "relincho": -6.0, "alarme": -4.0}
const HEAD_HEIGHT := 1.3  # metros: de onde saem bufo e relincho
const HOOF_HEIGHT := 0.1

var herd: Herd  # só no servidor
var _step := 0.0

var _audio: SpatialAudio
var _world: WorldGen
var _horses := {}  # id -> { pitch, coat, from: Vector2, to: Vector2, start, duration, gait, next_step, beat, drift, next_snort, last_hoof }
var _voices := []  # [{ player, horse, height, started }]
var _clock := 0.0


func start_server(world: WorldGen) -> void:
	herd = Herd.new(world)


func start_client(audio: SpatialAudio, world: WorldGen) -> void:
	_audio = audio
	_world = world
	if not _voices.is_empty():
		return
	for i in VOICES:
		var player := audio.make_far_voice(REACH)
		if player == null:
			return
		player.name = "Cavalo_%d" % i
		_voices.append({"player": player, "horse": -1, "height": 0.0, "started": 0.0})


func forget_peer(peer: int) -> void:
	if herd != null:
		herd.forget_peer(peer)


## Barulho forte num ponto (casas): espanta as manadas por perto.
func hear_noise(point: Vector2) -> void:
	if herd != null:
		herd.hear_noise(point)


func _process(delta: float) -> void:
	_clock += delta
	if herd != null:
		_step += delta
		if _step >= STEP_SECONDS:
			_step = 0.0
			_server_step()
	_client_steps()
	_follow()


# --- Servidor ------------------------------------------------------------------

func _server_step() -> void:
	var game := get_parent()
	if game.state == null:
		return
	var positions := {}
	for id in game.state.players:
		positions[id] = game.state.players[id]["pos"]
	herd.darkness = game.daytime.darkness()
	if game.horrors.horrors != null:
		herd.hush = game.horrors.horrors.points()
	for message in herd.update(Time.get_ticks_msec(), positions):
		var peer: int = message[0]
		var args: Array = message[2]
		match message[1]:
			"appear":
				horse_appeared.rpc_id(peer, args[0], args[1], args[2], args[3], args[4], args[5], args[6], args[7], args[8])
			"gone":
				horse_gone.rpc_id(peer, args[0])
			"move":
				horse_moved.rpc_id(peer, args[0], args[1], args[2], args[3], args[4], args[5], args[6])
			"sound":
				horse_sounded.rpc_id(peer, args[0], args[1])


# --- Avisos do servidor (executados nos clientes) ------------------------------

@rpc("authority", "call_local", "reliable")
func horse_appeared(id: int, pitch: float, coat: int, from: Vector2, to: Vector2, delay: float, duration: float, elapsed: float, gait: int) -> void:
	_horses[id] = {
		"pitch": pitch, "coat": coat, "from": from, "to": to,
		"start": _clock + delay - elapsed, "duration": duration, "gait": gait,
		"next_step": _clock + randf() * 0.5, "beat": 0, "drift": 0.0,
		"next_snort": _clock + _snort_gap(gait) * 0.5, "last_hoof": null,
	}


@rpc("authority", "call_local", "reliable")
func horse_gone(id: int) -> void:
	_horses.erase(id)
	for voice in _voices:
		if voice["horse"] == id:
			voice["horse"] = -1


@rpc("authority", "call_local", "reliable")
func horse_moved(id: int, from: Vector2, to: Vector2, delay: float, duration: float, elapsed: float, gait: int) -> void:
	if not _horses.has(id):
		return
	var horse: Dictionary = _horses[id]
	horse["from"] = from
	horse["to"] = to
	horse["start"] = _clock + delay - elapsed
	horse["duration"] = duration
	horse["gait"] = gait
	horse["next_step"] = maxf(float(horse["start"]), _clock)
	horse["beat"] = 0
	horse["next_snort"] = maxf(float(horse["start"]), _clock) + _snort_gap(gait) * 0.5


@rpc("authority", "call_local", "reliable")
func horse_sounded(id: int, kind: int) -> void:
	if not _horses.has(id) or kind < 0 or kind >= Herd.SOUNDS.size():
		return
	var sound_name: String = Herd.SOUNDS[kind]
	if not Net.auto_commands.is_empty():
		print("[teste] cavalo: %s a %.0f casas" % [sound_name, horse_point(id).distance_to(get_parent()._pos)])
	_play(id, HorseSounds.voice(sound_name), SOUND_DB[sound_name], float(_horses[id]["pitch"]), HEAD_HEIGHT)


# --- Posição e som -------------------------------------------------------------

## Onde o cavalo está agora, em casas.
func horse_point(id: int) -> Vector2:
	var horse: Dictionary = _horses[id]
	var duration: float = horse["duration"]
	if duration <= 0.0:
		return horse["to"]
	var x := clampf((_clock - float(horse["start"])) / duration, 0.0, 1.0)
	return (horse["from"] as Vector2).lerp(horse["to"], x)


## O cavalo está andando (ou galopando) agora? Devolve a andadura (Herd.Gait).
func horse_gait(id: int) -> int:
	if not _horses.has(id):
		return Herd.Gait.STAND
	var horse: Dictionary = _horses[id]
	var x := (_clock - float(horse["start"])) / maxf(0.001, float(horse["duration"]))
	return int(horse["gait"]) if x > 0.0 and x < 1.0 else Herd.Gait.STAND


## Os cavalos conhecidos (id -> pelagem), para a vista 3D.
func horse_coats() -> Dictionary:
	var out := {}
	for id: int in _horses:
		out[id] = int(_horses[id]["coat"])
	return out


## Para onde o cavalo anda (casas), para virar o corpo na vista 3D.
func horse_heading(id: int) -> Vector2:
	var horse: Dictionary = _horses[id]
	return (horse["to"] as Vector2) - (horse["from"] as Vector2)


func horse_count() -> int:
	return _horses.size()


## Toca os cascos de quem está andando, no ritmo da andadura, e uma bufada
## de vez em quando.
func _client_steps() -> void:
	if _voices.is_empty():
		return
	var me: Vector2 = get_parent()._pos
	for id: int in _horses:
		var gait := horse_gait(id)
		if gait == Herd.Gait.STAND:
			continue
		var horse: Dictionary = _horses[id]
		if _clock < float(horse["next_step"]):
			continue
		var gallop := gait == Herd.Gait.GALLOP
		horse["next_step"] = _clock + _next_gap(horse, gallop)
		var point := horse_point(id)
		if point.distance_to(me) > STEP_REACH:
			continue
		var surface := _surface_at(point)
		var recorded := HorseSounds.has_hooves(surface)
		var kind := ("galope" if gallop else "casco") + ("" if recorded else "_gerado")
		var stream := HorseSounds.hoof(surface, gallop, horse["last_hoof"])
		horse["last_hoof"] = stream
		# Cascos gravados: só um tiquinho do tom do cavalo, senão muda o ritmo.
		var pitch := (1.0 + (float(horse["pitch"]) - 1.0) * 0.3) * randf_range(0.98, 1.02) if recorded else float(horse["pitch"]) * randf_range(0.95, 1.05)
		var jitter := randf_range(-1.0, 1.0) if gallop else randf_range(-3.0, 1.5)
		_play(id, stream, SOUND_DB[kind] + jitter, pitch, HOOF_HEIGHT)
		if _clock >= float(horse["next_snort"]):
			horse["next_snort"] = _clock + _snort_gap(gait)
			_play(id, HorseSounds.voice("bufo"), SOUND_DB["bufo"] + (1.0 if gallop else 0.0), float(horse["pitch"]), HEAD_HEIGHT)


## Quanto falta para a próxima pisada (andando) ou passada (galopando).
func _next_gap(horse: Dictionary, gallop: bool) -> float:
	var drift := (float(horse["drift"]) + randfn(0.0, 0.03)) * 0.9
	horse["drift"] = drift
	if gallop:
		var tempo := clampf(1.0 + drift, GALLOP_TEMPO[0], GALLOP_TEMPO[1])
		return GALLOP_STRIDE * tempo + randfn(0.0, 0.01)
	var beat: int = horse["beat"]
	horse["beat"] = beat + 1
	var walk_tempo := clampf(1.0 + drift, WALK_TEMPO[0], WALK_TEMPO[1])
	return maxf(0.08, float(WALK_GAPS[beat % WALK_GAPS.size()]) * walk_tempo + randfn(0.0, 0.03))


func _snort_gap(gait: int) -> float:
	var span: Array = GALLOP_SNORTS if gait == Herd.Gait.GALLOP else WALK_SNORTS
	return randf_range(span[0], span[1])


func _surface_at(point: Vector2) -> String:
	if _world == null:
		return "grama"
	var cell := WorldGen.cell_of(point)
	match _world.thing_at(cell):
		WorldGen.Thing.PONTE:
			return "madeira"
		WorldGen.Thing.TRILHA:
			return "terra"
		WorldGen.Thing.VAU, WorldGen.Thing.RIACHO:
			return "agua"
	if WorldGen.COLD_BIOMES.has(_world.biome_at(cell)):
		return "neve"
	return "grama"


func _play(id: int, stream: AudioStream, volume_db: float, pitch: float, height: float) -> void:
	if stream == null or _voices.is_empty():
		return
	var voice: Dictionary = _free_voice()
	var player: AudioStreamPlayer3D = voice["player"]
	voice["horse"] = id
	voice["height"] = height
	player.stop()
	player.stream = stream
	player.volume_db = volume_db + HORSES_DB + (SpatialAudio.HRTF_GAIN_DB if _audio.using_hrtf else 0.0)
	player.pitch_scale = pitch
	player.position = _to_3d(horse_point(id), height)
	player.play()
	voice["started"] = _clock


func _free_voice() -> Dictionary:
	var oldest: Dictionary = _voices[0]
	for voice in _voices:
		if not (voice["player"] as AudioStreamPlayer3D).playing:
			return voice
		if float(voice["started"]) < float(oldest["started"]):
			oldest = voice
	return oldest


func _follow() -> void:
	for voice in _voices:
		var id: int = voice["horse"]
		if id < 0 or not _horses.has(id):
			continue
		var player: AudioStreamPlayer3D = voice["player"]
		if player.playing:
			player.position = _to_3d(horse_point(id), float(voice["height"]))
		else:
			voice["horse"] = -1


static func _to_3d(point: Vector2, height: float) -> Vector3:
	return Vector3(point.x * WorldGen.METERS_PER_CELL, height, point.y * WorldGen.METERS_PER_CELL)
