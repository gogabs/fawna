class_name WorldView3D
extends Node3D
## O mundo em 3D, em primeira pessoa. É só uma tradução do que o WorldGen já
## informa (bioma e coisa de cada casa): não guarda nada do jogo, não mexe no
## servidor e não toca em som. O jogo continua inteiro jogável sem esta tela.
##
## Etapa 1: chão colorido por bioma, trilhas, pontes e água, com neblina.
## O chão é montado em pedaços do tamanho dos pedaços do mundo (CHUNK casas),
## com cores nos vértices, uma malha por pedaço e um só material. Só os
## pedaços perto da criatura existem, e no máximo MAX_BUILDS_PER_FRAME nascem
## por quadro, para andar não gerar engasgo.

const CHUNK := WorldGen.CHUNK
const METERS := WorldGen.METERS_PER_CELL
## Quantos pedaços em volta (além do da criatura) ficam montados. O alcance
## visível é um pouco menor que isso, e a neblina esconde a borda.
const RADIUS_CHUNKS := 3
const MAX_BUILDS_PER_FRAME := 1
const EYE_HEIGHT := 1.2  # metros: uma criatura baixinha
const FOV := 80.0
const FOG_END := RADIUS_CHUNKS * CHUNK * METERS * 0.85

const SKY_COLOR := Color("0d1217")
const FOG_COLOR := Color("141b20")

const BIOME_COLORS := {
	WorldGen.Biome.BOSQUE: Color("26362a"),
	WorldGen.Biome.PRADARIA: Color("55633a"),
	WorldGen.Biome.LAGOA: Color("33514a"),
	WorldGen.Biome.MAR: Color("8a8065"),  # a areia da praia
	WorldGen.Biome.FLORESTA_GELADA: Color("4d666f"),
	WorldGen.Biome.DESERTO_GELADO: Color("a9b4b9"),
	WorldGen.Biome.BAMBUZAL: Color("33502a"),
	WorldGen.Biome.BREJO: Color("464c36"),
	WorldGen.Biome.MONTANHA: Color("62594f"),
}
const WATER_COLORS := {
	WorldGen.Thing.RIACHO: Color("24415a"),
	WorldGen.Thing.LAGO: Color("1d364d"),
	WorldGen.Thing.MAR: Color("14263d"),
	WorldGen.Thing.CHARCO: Color("2a4540"),
}
const FALLBACK_COLOR := Color("3a3a3a")  # bioma novo ainda sem cor
const TRAIL_COLOR := Color("6a5640")
const BRIDGE_COLOR := Color("503a24")

var _world: WorldGen
var _audio: SpatialAudio
var _camera: Camera3D
var _chunks := {}  # Vector2i (pedaço) -> MeshInstance3D
var _material: StandardMaterial3D
var _noise := FastNoiseLite.new()
var _center_chunk := Vector2i(1 << 30, 1 << 30)
var _wanted: Array[Vector2i] = []  # pedaços a montar, do mais perto ao mais longe
var _pos := Vector2.ZERO


func setup(world: WorldGen, audio: SpatialAudio) -> void:
	_world = world
	_audio = audio
	_noise.seed = 1234
	_noise.frequency = 0.9
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 1.0
	_camera = Camera3D.new()
	_camera.name = "Olhos"
	_camera.fov = FOV
	_camera.far = FOG_END * 1.5
	_camera.near = 0.05
	add_child(_camera)
	_camera.make_current()
	_setup_environment()


## Chamado a cada movimento: onde a criatura está. O giro vem do ouvinte,
## que já gira suave de uma direção à outra.
func follow(pos: Vector2) -> void:
	_pos = pos
	if _camera == null:
		return
	_camera.position = Vector3(pos.x, 0.0, pos.y) * METERS + Vector3.UP * EYE_HEIGHT
	var chunk := _chunk_of(WorldGen.cell_of(pos))
	if chunk != _center_chunk:
		_center_chunk = chunk
		_plan(chunk)


func chunk_count() -> int:
	return _chunks.size()


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = SKY_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("56627a")
	env.ambient_light_energy = 1.0
	env.fog_enabled = true
	env.fog_light_color = FOG_COLOR
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = FOG_END * 0.2
	env.fog_depth_end = FOG_END
	env.fog_depth_curve = 1.4
	var holder := WorldEnvironment.new()
	holder.environment = env
	add_child(holder)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, 30.0, 0.0)
	light.light_color = Color("a9b6cf")
	light.light_energy = 0.55
	light.shadow_enabled = false
	add_child(light)


static func _chunk_of(cell: Vector2i) -> Vector2i:
	return Vector2i(floori(float(cell.x) / CHUNK), floori(float(cell.y) / CHUNK))


## Decide quais pedaços devem existir: apaga os que ficaram longe e põe numa
## fila, do mais perto ao mais longe, os que faltam.
func _plan(center: Vector2i) -> void:
	for key: Vector2i in _chunks.keys():
		if maxi(absi(key.x - center.x), absi(key.y - center.y)) > RADIUS_CHUNKS + 1:
			_chunks[key].queue_free()
			_chunks.erase(key)
	_wanted.clear()
	for dy in range(-RADIUS_CHUNKS, RADIUS_CHUNKS + 1):
		for dx in range(-RADIUS_CHUNKS, RADIUS_CHUNKS + 1):
			var key := center + Vector2i(dx, dy)
			if not _chunks.has(key):
				_wanted.append(key)
	_wanted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - center).length_squared() > (b - center).length_squared())  # o mais perto no fim, para pop_back


func _process(_delta: float) -> void:
	if _camera != null and _audio != null:
		_camera.rotation.y = _audio.facing_yaw()
	for i in MAX_BUILDS_PER_FRAME:
		if _wanted.is_empty():
			return
		var key: Vector2i = _wanted.pop_back()
		if not _chunks.has(key):
			_build(key)


## Monta já todos os pedaços da fila (para a captura de tela e os testes).
func build_all() -> void:
	while not _wanted.is_empty():
		var key: Vector2i = _wanted.pop_back()
		if not _chunks.has(key):
			_build(key)


func _build(key: Vector2i) -> void:
	var first := key * CHUNK
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	vertices.resize(CHUNK * CHUNK * 4)
	colors.resize(CHUNK * CHUNK * 4)
	normals.resize(CHUNK * CHUNK * 4)
	indices.resize(CHUNK * CHUNK * 6)
	var n := 0
	for y in CHUNK:
		for x in CHUNK:
			var cell := first + Vector2i(x, y)
			var drop := 0.0  # etapa 1: tudo plano (o nível da água vem depois)
			var color := _cell_color(cell)
			var x0 := cell.x * METERS
			var x1 := x0 + METERS
			var z0 := cell.y * METERS
			var z1 := z0 + METERS
			var v := n * 4
			vertices[v] = Vector3(x0, drop, z0)
			vertices[v + 1] = Vector3(x1, drop, z0)
			vertices[v + 2] = Vector3(x1, drop, z1)
			vertices[v + 3] = Vector3(x0, drop, z1)
			for k in 4:
				colors[v + k] = color
				normals[v + k] = Vector3.UP
			var i := n * 6
			indices[i] = v
			indices[i + 1] = v + 1
			indices[i + 2] = v + 2
			indices[i + 3] = v
			indices[i + 4] = v + 2
			indices[i + 5] = v + 3
			n += 1
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _material)
	var instance := MeshInstance3D.new()
	instance.name = "Chao_%d_%d" % [key.x, key.y]
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	_chunks[key] = instance


func _cell_color(cell: Vector2i) -> Color:
	var thing := _world.thing_at(cell)
	var jitter := 1.0 + 0.10 * _noise.get_noise_2d(cell.x, cell.y)
	if WATER_COLORS.has(thing):
		return WATER_COLORS[thing] * jitter
	if thing == WorldGen.Thing.TRILHA:
		return TRAIL_COLOR * jitter
	if thing == WorldGen.Thing.PONTE:
		return BRIDGE_COLOR * jitter
	var ground: Color = BIOME_COLORS.get(_world.biome_at(cell), FALLBACK_COLOR)
	if _world.feature_at(cell) == WorldGen.Feature.CLAREIRA:
		ground = ground.lightened(0.15)
	var out := ground * jitter
	out.a = 1.0
	return out
