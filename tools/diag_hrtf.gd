extends SceneTree
## Mede se o Steam Audio (Nexus Resonance) está aplicando o HRTF.
##
## Toca um ruído a 6 m em quatro direções (esquerda, direita, frente e trás),
## com a mesma configuração do jogo (client/spatial_audio.gd) e o panorama
## do Godot desligado, e grava o barramento Master. Com HRTF de verdade, a
## esquerda sai bem mais forte no ouvido esquerdo (uns 15 dB) e a direita no
## direito; frente e trás ficam iguais nos dois ouvidos, mas com timbres
## diferentes (o "brilho" muda). Sem HRTF, tudo sai com 0 dB de diferença.
##
## Uso, na raiz do projeto:
##   godot --headless --path . --script tools/diag_hrtf.gd

const DIRECTIONS := {
	"esquerda": Vector3(-6, 0, 0),
	"direita": Vector3(6, 0, 0),
	"frente": Vector3(0, 0, -6),
	"tras": Vector3(0, 0, 6),
}
const SECONDS_PER_DIRECTION := 1.5

var _capture: AudioEffectCapture
var _player: AudioStreamPlayer3D
var _names: Array = DIRECTIONS.keys()
var _index := -1
var _elapsed := 0.0
var _total := 0.0
var _results := {}


func _initialize() -> void:
	if not ClassDB.class_exists("ResonancePlayer"):
		print("[diag] Nexus Resonance não está instalado (rode tools/instalar_extensoes).")
		quit(1)
		return
	_capture = AudioEffectCapture.new()
	_capture.buffer_length = 4.0
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Master"), _capture)

	var world := Node3D.new()
	root.add_child(world)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0, 0.2, 0)
	camera.make_current()
	var listener := AudioListener3D.new()
	camera.add_child(listener)
	listener.make_current()

	var config: Resource = ResonanceSetup.new_object("ResonanceRuntimeConfig")
	var player_config: Resource = ResonanceSetup.new_object("ResonancePlayerConfig")
	ResonanceSetup.configure_runtime(config, 128)
	ResonanceSetup.configure_player(player_config, 1.5, 15.0)
	var runtime: Node = ClassDB.instantiate("ResonanceRuntime")
	runtime.set("runtime", config)
	world.add_child(runtime)
	camera.add_child(ClassDB.instantiate("ResonanceListener"))

	_player = ClassDB.instantiate("ResonancePlayer")
	_player.set("player_config", player_config)
	_player.stream = _noise()
	_player.panning_strength = 0.0  # só o Steam Audio decide o lado
	world.add_child(_player)
	var server := Engine.get_singleton("ResonanceServer")
	print("[diag] %s, Godot %s, %s, %d Hz" % [server.get_version() if server.has_method("get_version") else "Nexus Resonance", Engine.get_version_info()["string"], OS.get_name(), AudioServer.get_mix_rate()])


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
	_total += delta
	_elapsed += delta
	if _index < 0 or _elapsed >= SECONDS_PER_DIRECTION:
		if _index >= 0:
			_measure(_names[_index])
		_index += 1
		_elapsed = 0.0
		if _index >= _names.size():
			_report()
			return true
		_player.position = DIRECTIONS[_names[_index]]
		if not _player.playing:
			_player.play()
		_capture.clear_buffer()
	# Descarta o começo de cada direção (o som ainda está mudando de lugar).
	if _elapsed < 0.5:
		_capture.clear_buffer()
	return false


func _measure(direction: String) -> void:
	var frames := _capture.get_frames_available()
	var buffer := _capture.get_buffer(frames)
	var left := 0.0
	var right := 0.0
	for v in buffer:
		left += v.x * v.x
		right += v.y * v.y
	var server := Engine.get_singleton("ResonanceServer")
	var gate = server.is_spatial_audio_output_ready() if server.has_method("is_spatial_audio_output_ready") else "?"
	var ild := 10.0 * log(maxf(left, 1e-12) / maxf(right, 1e-12)) / log(10.0)
	_results[direction] = ild
	print("[diag] %-8s esquerdo %.4f  direito %.4f  diferença %+.1f dB  (portão espacial: %s)" % [direction, sqrt(left / maxi(frames, 1)), sqrt(right / maxi(frames, 1)), ild, gate])


func _report() -> void:
	var ok: bool = _results.get("esquerda", 0.0) > 6.0 and _results.get("direita", 0.0) < -6.0
	print("[diag] HRTF %s" % ("FUNCIONANDO" if ok else "NÃO APLICADO (som igual nos dois ouvidos)"))
