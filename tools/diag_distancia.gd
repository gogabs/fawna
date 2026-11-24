extends SceneTree
## Mede quanto o volume cai com a distância numa fonte igual às do jogo.
##
## Toca um ruído à frente do ouvinte em várias distâncias, numa fonte com a
## mesma configuração das vozes do jogo (client/spatial_audio.gd), e grava o
## barramento Master. Mostra o nível em dB relativo ao primeiro ponto.
##
## Uso, na raiz do projeto:
##   godot --headless --path . --script tools/diag_distancia.gd [-- --antes]
## Com --antes, mede como era antes (1/d do Steam Audio, sem absorção do ar).

const DISTANCES_M := [1.5, 3.0, 6.0, 9.0, 12.0, 18.0, 24.0, 30.0, 36.0]
const SECONDS_EACH := 1.2
const VOICE_REACH := 28.0  # casas, igual a SpatialAudio.VOICE_REACH

var _capture: AudioEffectCapture
var _player: AudioStreamPlayer3D
var _index := -1
var _elapsed := 0.0
var _first_db := 0.0


func _initialize() -> void:
	if not ClassDB.class_exists("ResonancePlayer"):
		print("[distancia] Nexus Resonance não está instalado.")
		quit(1)
		return
	_capture = AudioEffectCapture.new()
	_capture.buffer_length = 4.0
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Master"), _capture)
	var world := Node3D.new()
	root.add_child(world)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.make_current()
	var listener := AudioListener3D.new()
	camera.add_child(listener)
	listener.make_current()
	var config: Resource = ResonanceSetup.new_object("ResonanceRuntimeConfig")
	var player_config: Resource = ResonanceSetup.new_object("ResonancePlayerConfig")
	ResonanceSetup.configure_runtime(config, 128)
	var m := WorldGen.METERS_PER_CELL
	ResonanceSetup.configure_player(player_config, m, m * 8)
	# Como as vozes do jogo (sons curtos: passos, golpes, árvore caindo).
	ResonanceSetup.set_reach(player_config, m * VOICE_REACH)
	if "--antes" in OS.get_cmdline_user_args():
		# Como era antes: 1/d do Steam Audio, sem absorção do ar.
		player_config.set("attenuation_mode", 0)
		player_config.set("air_absorption_enabled", false)
	var runtime: Node = ClassDB.instantiate("ResonanceRuntime")
	runtime.set("runtime", config)
	world.add_child(runtime)
	camera.add_child(ClassDB.instantiate("ResonanceListener"))
	_player = ClassDB.instantiate("ResonancePlayer")
	_player.set("player_config", player_config)
	_player.stream = _noise()
	_player.panning_strength = 0.0
	world.add_child(_player)
	print("[distancia] modo %s, min %.1f m, max %.1f m" % [player_config.get("attenuation_mode"), player_config.get("min_distance"), player_config.get("max_distance")])


func _noise() -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 48000
	var data := PackedByteArray()
	data.resize(48000 * 2)
	for i in 48000:
		data.encode_s16(i * 2, int(randf_range(-0.3, 0.3) * 32767))
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = 48000
	return stream


func _process(delta: float) -> bool:
	if _player == null:
		return true
	_elapsed += delta
	if _index < 0 or _elapsed >= SECONDS_EACH:
		if _index >= 0:
			_measure(DISTANCES_M[_index])
		_index += 1
		_elapsed = 0.0
		if _index >= DISTANCES_M.size():
			return true
		_player.position = Vector3(0, 0, -DISTANCES_M[_index])
		if not _player.playing:
			_player.play()
	if _elapsed < 0.5:
		_capture.clear_buffer()
	return false


func _measure(distance: float) -> void:
	var frames := _capture.get_frames_available()
	var buffer := _capture.get_buffer(frames)
	var sum := 0.0
	for v in buffer:
		sum += v.x * v.x + v.y * v.y
	var rms := sqrt(sum / maxi(frames * 2, 1))
	var db := 20.0 * log(maxf(rms, 1e-9)) / log(10.0)
	if _index == 0:
		_first_db = db
	var expected := 20.0 * log(ResonanceSetup.distance_gain(distance, WorldGen.METERS_PER_CELL, WorldGen.METERS_PER_CELL * VOICE_REACH)) / log(10.0)
	print("[distancia] %5.1f m  %6.1f dB  (%+.1f; a curva pede %+.1f)" % [distance, db, db - _first_db, expected])
