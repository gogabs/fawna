extends Node
## Os pássaros na rede. Este nó existe igual no servidor e nos clientes
## (/root/Game/Birds), porque é por ele que passam as chamadas de rede.
##
## No servidor, roda a simulação (Aviary) e manda a cada jogador só o que
## acontece perto dele. No cliente, guarda onde cada pássaro está e toca os
## cantos e as asas no lugar certo, com HRTF quando houver.

const STEP_SECONDS := 0.25  # passo da simulação no servidor
const VOICES := 14  # fontes de som reaproveitadas para todos os pássaros
const REACH := Aviary.HEARING  # casas: até onde um pássaro é ouvido
const ARC_HEIGHT := 1.6  # metros: o voo sobe um pouco no meio do caminho
## Volumes de origem. Os pássaros ficam longe, então a distância já os deixa
## bem baixinhos; cantos discretos, abaixo da fala.
const SONG_DB := {Aviary.Species.SABIA: -9.0, Aviary.Species.CARRICA: -17.0, Aviary.Species.ROLINHA: -11.0}
const WINGS_DB := -15.0
## Asas gravadas: mais agudas no passarinho, mais graves na rolinha.
const WINGS_PITCH := {Aviary.Species.SABIA: 1.0, Aviary.Species.CARRICA: 1.3, Aviary.Species.ROLINHA: 0.85}
const ALARM_DB := -12.0

var aviary: Aviary  # só no servidor
var _step := 0.0

# Lado do cliente
var _audio: SpatialAudio
var _birds := {}  # id -> { species, pitch, from: Vector3, to: Vector3, start, duration }
var _voices := []  # [{ player, bird }]
var _clock := 0.0  # segundos desde que o cliente começou


func start_server(world: WorldGen) -> void:
	aviary = Aviary.new(world)


func start_client(audio: SpatialAudio) -> void:
	_audio = audio
	if not _voices.is_empty():
		return
	for i in VOICES:
		var player := audio.make_far_voice(REACH)
		if player == null:
			return  # sem som (servidor dedicado ou teste sem tela)
		player.name = "Passaro_%d" % i
		_voices.append({"player": player, "bird": -1})


func forget_peer(peer: int) -> void:
	if aviary != null:
		aviary.forget_peer(peer)


func _process(delta: float) -> void:
	_clock += delta
	if aviary != null:
		_step += delta
		if _step >= STEP_SECONDS:
			_step = 0.0
			_server_step()
	_follow_birds()


# --- Servidor ------------------------------------------------------------------

func _server_step() -> void:
	var game := get_parent()
	if game.state == null:
		return
	var positions := {}
	for id in game.state.players:
		positions[id] = game.state.players[id]["pos"]
	for message in aviary.update(Time.get_ticks_msec(), positions):
		var peer: int = message[0]
		var args: Array = message[2]
		match message[1]:
			"appear":
				bird_appeared.rpc_id(peer, args[0], args[1], args[2], args[3], args[4], args[5], args[6], args[7])
			"gone":
				bird_gone.rpc_id(peer, args[0])
			"sing":
				bird_sang.rpc_id(peer, args[0], args[1])
			"fly":
				bird_flew.rpc_id(peer, args[0], args[1], args[2], args[3], args[4], args[5], args[6])


# --- Avisos do servidor (executados nos clientes) ------------------------------

@rpc("authority", "call_local", "reliable")
func bird_appeared(id: int, species: int, pitch: float, from: Vector3, to: Vector3, delay: float, duration: float, elapsed: float) -> void:
	_birds[id] = {
		"species": species, "pitch": pitch, "from": from, "to": to,
		"start": _clock + delay - elapsed, "duration": duration,
	}


@rpc("authority", "call_local", "reliable")
func bird_gone(id: int) -> void:
	_birds.erase(id)
	for voice in _voices:
		if voice["bird"] == id:
			voice["bird"] = -1  # o som que estiver tocando termina parado


@rpc("authority", "call_local", "reliable")
func bird_sang(id: int, song: int) -> void:
	if not _birds.has(id):
		return
	var bird: Dictionary = _birds[id]
	if not Net.auto_commands.is_empty():
		print("[teste] %s cantou a %.0f m" % [Aviary.species_name(bird["species"]), bird_position(id).distance_to(Aviary.to_3d(get_parent()._pos, 0.0))])
	_play(id, BirdSongs.song(bird["species"], song), SONG_DB[bird["species"]], bird["pitch"])


@rpc("authority", "call_local", "reliable")
func bird_flew(id: int, from: Vector3, to: Vector3, delay: float, duration: float, elapsed: float, startled: bool) -> void:
	if not _birds.has(id):
		return
	var bird: Dictionary = _birds[id]
	bird["from"] = from
	bird["to"] = to
	bird["start"] = _clock + delay - elapsed
	bird["duration"] = duration
	if _voices.is_empty():
		return
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
		if not _birds.has(id):
			return
	_play(id, BirdSongs.wings(bird["species"], duration, startled), WINGS_DB, WINGS_PITCH[bird["species"]] * randf_range(0.95, 1.05))
	# Quem sai na frente do bando dá o grito de susto.
	if startled and delay <= 0.0:
		var alarm := BirdSongs.alarm(bird["species"])
		if alarm != null:
			_play(id, alarm, ALARM_DB, bird["pitch"])


# --- Som -----------------------------------------------------------------------

## Onde o pássaro está agora, em 3D (metros).
func bird_position(id: int) -> Vector3:
	var bird: Dictionary = _birds[id]
	var duration: float = bird["duration"]
	if duration <= 0.0:
		return bird["to"]
	var x := clampf((_clock - float(bird["start"])) / duration, 0.0, 1.0)
	var smooth := x * x * (3.0 - 2.0 * x)  # sai e chega devagar
	var pos: Vector3 = (bird["from"] as Vector3).lerp(bird["to"], smooth)
	pos.y += sin(PI * x) * ARC_HEIGHT
	return pos


func bird_count() -> int:
	return _birds.size()


## Toca um som do pássaro numa fonte livre (ou na mais antiga, se todas
## estiverem ocupadas), que passa a acompanhar o pássaro enquanto toca.
func _play(id: int, stream: AudioStream, volume_db: float, pitch: float) -> void:
	if stream == null or _voices.is_empty():
		return
	var voice: Dictionary = _free_voice()
	var player: AudioStreamPlayer3D = voice["player"]
	voice["bird"] = id
	player.stop()
	player.stream = stream
	player.volume_db = volume_db + (SpatialAudio.HRTF_GAIN_DB if _audio.using_hrtf else 0.0)
	player.pitch_scale = pitch
	player.position = bird_position(id)
	player.play()
	voice["started"] = _clock


func _free_voice() -> Dictionary:
	var oldest: Dictionary = _voices[0]
	for voice in _voices:
		if not (voice["player"] as AudioStreamPlayer3D).playing:
			return voice
		if float(voice.get("started", 0.0)) < float(oldest.get("started", 0.0)):
			oldest = voice
	return oldest


func _follow_birds() -> void:
	for voice in _voices:
		var id: int = voice["bird"]
		if id < 0 or not _birds.has(id):
			continue
		var player: AudioStreamPlayer3D = voice["player"]
		if player.playing:
			player.position = bird_position(id)
		else:
			voice["bird"] = -1
