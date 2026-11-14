class_name SpatialAudio
extends Node3D
## Áudio espacial do mundo.
##
## O mundo é 2D, mas o som é posicionado em 3D: o ponto (x, y) do mundo vira
## (x, 0, y) * METERS_PER_CELL. O ouvinte gira junto com a criatura: olhando
## para o norte, ele encara -Z; cada giro de 45° vira o ouvinte também.
##
## Com o Nexus Resonance (Steam Audio) instalado, os sons usam HRTF binaural,
## o que deixa frente e trás claros num fone de ouvido. Sem ele, cai no
## AudioStreamPlayer3D do Godot (só esquerda/direita e distância).

const METERS_PER_CELL := WorldGen.METERS_PER_CELL
const TURN_SECONDS := 0.12  # o giro do ouvinte é rápido, mas não instantâneo
const COMPASS_DISTANCE := 1.4  # casas: o clique da bússola soa a uns 2 m
const SCENE_CUSTOM_GODOT_PHYSICS := 3  # ResonanceRuntimeConfig.scene_type
## O HRTF atenua mais com a distância que o áudio 3D do Godot; compensa.
const HRTF_GAIN_DB := 6.0
const AMBIENT_RADIUS := 6  # casas
const MAX_AMBIENT_SOURCES := 8
const AMBIENT_VOLUME_DB := -12.0
const MAX_SIMULATION_SOURCES := 128  # limite do Steam Audio (o máximo do addon)

var using_hrtf := false
var village_level := 0

var _world: WorldGen
var _camera: Camera3D
var _player_config: Resource  # ResonancePlayerConfig, quando houver
var _ambient := {}  # Vector2i -> AudioStreamPlayer3D
var _listener_cell := WorldGen.NO_CELL
var _listener_pos := Vector2.ZERO
var _turn_tween: Tween
var _compass_players: Array[AudioStreamPlayer3D] = []  # um por hora do relógio
## Vozes para sons curtos (passos dos outros, esbarrões...). Ficam criadas e
## são reaproveitadas: o Steam Audio demora a registrar uma fonte nova, e um
## som curto numa fonte recém-criada acabava antes disso, saindo mudo.
var _voices: Array[AudioStreamPlayer3D] = []
var _voice_order: Array[AudioStreamPlayer3D] = []  # da que tocou há mais tempo à mais recente


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
	_setup_compass()
	_setup_voices()
	print("[audio] HRTF (Steam Audio): %s" % ("sim" if using_hrtf else "não, usando o áudio 3D do Godot"))


func setup(world: WorldGen) -> void:
	_world = world


static func point_to_3d(point: Vector2) -> Vector3:
	return Vector3(point.x, 0.0, point.y) * METERS_PER_CELL


## Centro da casa, em 3D.
static func cell_to_3d(cell: Vector2i) -> Vector3:
	return point_to_3d(WorldGen.cell_center(cell))


## Move o ouvinte e, ao trocar de casa, atualiza os sons contínuos ao redor.
func move_listener(pos: Vector2) -> void:
	if _camera == null:
		return
	_listener_pos = pos
	_camera.position = point_to_3d(pos) + Vector3.UP * 0.2
	var cell := WorldGen.cell_of(pos)
	if cell != _listener_cell and _world != null:
		_listener_cell = cell
		_refresh_ambient(cell)


## Vira o ouvinte para uma das 8 direções (0 = norte, sentido horário).
func set_heading(heading: int, smooth := true) -> void:
	if _camera == null:
		return
	var target := -Compass.angle(heading)
	var current := _camera.rotation.y
	var goal := current + wrapf(target - current, -PI, PI)
	if _turn_tween != null:
		_turn_tween.kill()
	if not smooth:
		_camera.rotation.y = goal
		return
	_turn_tween = create_tween()
	_turn_tween.tween_property(_camera, "rotation:y", goal, TURN_SECONDS)


## Bússola como um relógio em volta da cabeça: cada direção tem sua hora
## fixa (norte ao meio-dia, à frente; leste às 3, à direita; sul às 6, atrás;
## oeste às 9, à esquerda; as colaterais nas horas entre elas). As fontes
## giram junto com a cabeça, então a posição de cada som nunca muda: o que
## muda é qual delas toca. Ficam sempre criadas, para o Steam Audio já
## conhecê-las quando o clique, que é bem curto, precisar tocar.
func _setup_compass() -> void:
	for heading in Compass.STEPS:
		var player := _new_player(Sounds.compass(heading), -4.0)
		var a := Compass.angle(heading)
		player.position = Vector3(sin(a), 0.0, -cos(a)) * COMPASS_DISTANCE * METERS_PER_CELL
		player.name = "Bussola_" + Compass.name_of(heading)
		_camera.add_child(player)
		_compass_players.append(player)


func play_compass(heading: int) -> void:
	if _compass_players.is_empty():
		return
	var player := _compass_players[posmod(heading, Compass.STEPS)]
	player.stop()
	player.play()


## A vila soa diferente conforme a horta cresce.
func set_village_level(level: int) -> void:
	if level == village_level:
		return
	village_level = level
	var village := WorldGen.center()
	if _ambient.has(village):
		_ambient[village].queue_free()
		_ambient.erase(village)
	if _camera != null and _world != null and _listener_cell != WorldGen.NO_CELL:
		_refresh_ambient(_listener_cell)


## Toca um som curto numa casa do mundo (ex.: passo de outra criatura).
func play_at(cell: Vector2i, stream: AudioStream, volume_db := 0.0) -> void:
	play_at_point(WorldGen.cell_center(cell), stream, volume_db)


const VOICE_COUNT := 32


func _setup_voices() -> void:
	for i in VOICE_COUNT:
		var voice := _new_player(null, 0.0)
		voice.name = "Voz_%d" % i
		add_child(voice)
		_voices.append(voice)
		_voice_order.append(voice)


## Toca um som curto num ponto do mundo (ex.: esbarrão, passos de alguém).
## vary dá uma leve variação de altura e volume (bom para passos).
func play_at_point(point: Vector2, stream: AudioStream, volume_db := 0.0, hrtf := true, vary := false) -> void:
	if _camera == null or stream == null:
		return
	var pitch := 1.0
	if vary:
		pitch = randf_range(0.94, 1.06)
		volume_db += randf_range(-1.5, 0.0)
	if hrtf and using_hrtf and not _voices.is_empty():
		_play_on_voice(point, stream, volume_db, pitch)
		return
	var player := _new_player(stream, volume_db, hrtf)
	player.pitch_scale = pitch
	player.position = point_to_3d(point)
	player.finished.connect(player.queue_free)
	add_child(player)
	player.play()


## Usa a voz livre que está parada há mais tempo. Uma voz que ainda está
## tocando nunca é reiniciada, a não ser que as 32 estejam ocupadas; aí vai a
## que começou primeiro, que é a que está mais perto de acabar.
func _play_on_voice(point: Vector2, stream: AudioStream, volume_db: float, pitch := 1.0) -> void:
	var voice: AudioStreamPlayer3D = _voice_order[0]
	for candidate in _voice_order:
		if not candidate.playing:
			voice = candidate
			break
	_voice_order.erase(voice)
	_voice_order.append(voice)
	voice.stop()
	voice.stream = stream
	voice.pitch_scale = pitch
	voice.volume_db = volume_db + HRTF_GAIN_DB
	voice.position = point_to_3d(point)
	voice.play()


func _refresh_ambient(center: Vector2i) -> void:
	var wanted := _nearest_sounding_cells(center)
	for cell in _ambient.keys():
		if not wanted.has(cell):
			_ambient[cell].queue_free()
			_ambient.erase(cell)
	for cell: Vector2i in wanted:
		if _ambient.has(cell):
			continue
		var stream := Sounds.ambient(_world.thing_at(cell), village_level)
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
			var thing := _world.thing_at(cell)
			# A lagoa ocupa muitas casas: uma fonte a cada 3, para não abafar o resto.
			if thing == WorldGen.Thing.LAGO and (posmod(cell.x, 3) != 0 or posmod(cell.y, 3) != 0):
				continue
			if Sounds.has_ambient(thing):
				found.append(cell)
	found.sort_custom(func(a, b): return (a - center).length_squared() < (b - center).length_squared())
	return found.slice(0, MAX_AMBIENT_SOURCES)


## Uma fonte que alcança longe (até "reach" casas), para os pássaros. Fica
## criada e é reaproveitada: o Steam Audio às vezes não pega fontes criadas
## no meio do jogo. Quem chama decide o som, o volume e a posição.
func make_far_voice(reach: float) -> AudioStreamPlayer3D:
	if _camera == null:
		return null
	var player := _new_player(null, 0.0)
	if using_hrtf:
		var config: Resource = _player_config.duplicate()
		config.set("max_distance", METERS_PER_CELL * reach)
		player.set("player_config", config)
	else:
		player.max_distance = METERS_PER_CELL * reach
		player.unit_size = METERS_PER_CELL * 3.0
	add_child(player)
	return player


func _new_player(stream: AudioStream, volume_db: float, hrtf := true) -> AudioStreamPlayer3D:
	var player: AudioStreamPlayer3D
	if using_hrtf and hrtf:
		player = ClassDB.instantiate("ResonancePlayer")
		player.set("player_config", _player_config)
		volume_db += HRTF_GAIN_DB
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
	var config := _new_resonance_object("ResonanceRuntimeConfig") as Resource
	_player_config = _new_resonance_object("ResonancePlayerConfig") as Resource
	if config == null or _player_config == null:
		push_warning("Nexus Resonance incompleto; usando o áudio 3D do Godot.")
		return
	config.set("direct_binaural", true)
	# Sem geometria, a cena padrão do Steam Audio fica com 0 triângulos, a
	# simulação nunca começa e todo ResonancePlayer sai mudo. A cena "Custom"
	# (raios da física do Godot) faz a simulação rodar mesmo sem geometria.
	config.set("scene_type", SCENE_CUSTOM_GODOT_PHYSICS)
	config.set("realtime_rays", 0)
	config.set("pathing_enabled", false)
	# O padrão do addon é 32 fontes; bússola, vozes, pássaros, ambiente e o
	# Caminheiro passam disso, e as fontes que ficam sem vaga saem mudas.
	config.set("max_simulation_sources", MAX_SIMULATION_SOURCES)
	var runtime: Node = ClassDB.instantiate("ResonanceRuntime")
	runtime.name = "ResonanceRuntime"
	runtime.set("runtime", config)
	add_child(runtime)

	var listener: Node3D = ClassDB.instantiate("ResonanceListener")
	_camera.add_child(listener)

	_player_config.set("reflections_enabled", false)
	_player_config.set("simulation_occlusion_enabled", false)
	_player_config.set("air_absorption_enabled", false)
	# Reflexões desligadas: zera também a mistura delas, senão o addon avisa
	# a cada som que não recebeu parâmetros de reflexão.
	for prop in _player_config.get_property_list():
		var prop_name: String = prop["name"]
		if prop_name.contains("reflection") and prop_name.contains("mix"):
			_player_config.set(prop_name, 0.0)
	_player_config.set("min_distance", METERS_PER_CELL)
	_player_config.set("max_distance", METERS_PER_CELL * (AMBIENT_RADIUS + 2))
	using_hrtf = true
	get_tree().create_timer(2.0).timeout.connect(_log_resonance_state)


func _log_resonance_state() -> void:
	if not Engine.has_singleton("ResonanceServer"):
		return
	var server := Engine.get_singleton("ResonanceServer")
	if server.has_method("is_simulating"):
		print("[audio] Steam Audio simulando: %s" % ("sim" if server.is_simulating() else "não (os sons com HRTF vão sair mudos)"))


## Cria uma classe do Nexus Resonance pelo nome. Algumas são nativas
## (GDExtension) e outras são scripts com class_name, como as configs.
## Não usamos os nomes direto no código para o jogo funcionar sem o addon.
static func _new_resonance_object(class_name_str: String) -> Object:
	if ClassDB.class_exists(class_name_str):
		return ClassDB.instantiate(class_name_str)
	for entry in ProjectSettings.get_global_class_list():
		if entry["class"] == class_name_str:
			return load(entry["path"]).new()
	return null
