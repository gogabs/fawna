class_name SpatialAudio
extends Node3D
## Áudio espacial do mundo.
##
## O mundo é uma grade 2D, mas o som é posicionado em 3D: a casa (x, y) vira o
## ponto (x, 0, y) * METERS_PER_CELL. A pessoa ouve sempre virada para o norte
## (-Z), então "à esquerda" é oeste e "atrás" é sul.
##
## Com o Nexus Resonance (Steam Audio) instalado, os sons usam HRTF binaural,
## o que deixa frente e trás claros num fone de ouvido. Sem ele, cai no
## AudioStreamPlayer3D do Godot (só esquerda/direita e distância).

const METERS_PER_CELL := 1.5
const AMBIENT_RADIUS := 6  # casas
const MAX_AMBIENT_SOURCES := 8
const AMBIENT_VOLUME_DB := -8.0

var using_hrtf := false

var _world: WorldGen
var _camera: Camera3D
var _player_config: Resource  # ResonancePlayerConfig, quando houver
var _ambient := {}  # Vector2i -> AudioStreamPlayer3D


func _ready() -> void:
	if not Net.has_local_player():
		return  # servidor dedicado não toca som
	_camera = Camera3D.new()
	_camera.name = "Ouvinte"
	add_child(_camera)
	_camera.make_current()
	var listener := AudioListener3D.new()
	_camera.add_child(listener)
	listener.make_current()
	_setup_resonance()
	print("[audio] HRTF (Steam Audio): %s" % ("sim" if using_hrtf else "não, usando o áudio 3D do Godot"))


func setup(world: WorldGen) -> void:
	_world = world


static func cell_to_3d(cell: Vector2i) -> Vector3:
	return Vector3(cell.x, 0.0, cell.y) * METERS_PER_CELL


## Move o ouvinte e atualiza os sons contínuos ao redor.
func move_listener(cell: Vector2i) -> void:
	if _camera == null:
		return
	_camera.position = cell_to_3d(cell) + Vector3.UP * 0.2
	if _world != null:
		_refresh_ambient(cell)


## Toca um som curto numa casa do mundo (ex.: passo de outra criatura).
func play_at(cell: Vector2i, stream: AudioStream, volume_db := 0.0) -> void:
	var player := _new_player(stream, volume_db)
	player.position = cell_to_3d(cell)
	player.finished.connect(player.queue_free)
	add_child(player)
	player.play()


func _refresh_ambient(center: Vector2i) -> void:
	var wanted := _nearest_sounding_cells(center)
	for cell in _ambient.keys():
		if not wanted.has(cell):
			_ambient[cell].queue_free()
			_ambient.erase(cell)
	for cell: Vector2i in wanted:
		if _ambient.has(cell):
			continue
		var stream := SoundBank.ambient(_world.thing_at(cell))
		if stream == null:
			continue
		var player := _new_player(stream, AMBIENT_VOLUME_DB)
		player.position = cell_to_3d(cell)
		add_child(player)
		# Começa em pontos diferentes do loop para dois sons iguais não soarem em uníssono.
		player.play(randf() * stream.get_length())
		_ambient[cell] = player


func _nearest_sounding_cells(center: Vector2i) -> Array:
	var found := []
	var r := AMBIENT_RADIUS
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var cell := center + Vector2i(dx, dy)
			if SoundBank.ambient(_world.thing_at(cell)) != null:
				found.append(cell)
	found.sort_custom(func(a, b): return (a - center).length_squared() < (b - center).length_squared())
	return found.slice(0, MAX_AMBIENT_SOURCES)


func _new_player(stream: AudioStream, volume_db: float) -> AudioStreamPlayer3D:
	var player: AudioStreamPlayer3D
	if using_hrtf:
		player = ClassDB.instantiate("ResonancePlayer")
		player.set("player_config", _player_config)
	else:
		player = AudioStreamPlayer3D.new()
		player.unit_size = METERS_PER_CELL * 2.0
		player.max_distance = METERS_PER_CELL * (AMBIENT_RADIUS + 2)
		player.panning_strength = 1.5
	player.stream = stream
	player.volume_db = volume_db
	return player


## Liga o Steam Audio só para o som direto com HRTF. Sem reflexões, oclusão
## ou pathing por enquanto: o mundo ainda não tem geometria 3D.
func _setup_resonance() -> void:
	if not ClassDB.class_exists("ResonanceRuntime") or not ClassDB.class_exists("ResonancePlayer"):
		return
	var config: Resource = ClassDB.instantiate("ResonanceRuntimeConfig")
	config.set("direct_binaural", true)
	config.set("realtime_rays", 0)
	config.set("pathing_enabled", false)
	var runtime: Node = ClassDB.instantiate("ResonanceRuntime")
	runtime.name = "ResonanceRuntime"
	runtime.set("runtime", config)
	add_child(runtime)

	var listener: Node3D = ClassDB.instantiate("ResonanceListener")
	_camera.add_child(listener)

	_player_config = ClassDB.instantiate("ResonancePlayerConfig")
	_player_config.set("reflections_enabled", false)
	_player_config.set("simulation_occlusion_enabled", false)
	_player_config.set("air_absorption_enabled", false)
	_player_config.set("min_distance", METERS_PER_CELL)
	_player_config.set("max_distance", METERS_PER_CELL * (AMBIENT_RADIUS + 2))
	using_hrtf = true
