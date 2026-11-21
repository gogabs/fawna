class_name WorldView3D
extends Node3D
## O mundo em 3D, em primeira pessoa. É só uma tradução do que o WorldGen já
## informa (bioma e coisa de cada casa): não guarda nada do jogo, não mexe no
## servidor e não toca em som. O jogo continua inteiro jogável sem esta tela.
##
## Etapa 1: chão colorido por bioma, trilhas, pontes e água, com neblina.
## Etapa 2: árvores, arbustos, bambu, pedras e recursos pequenos, feitos de
## primitivas (cilindros, cones, esferas) em MultiMesh, um por forma e pedaço.
## O chão é montado em pedaços do tamanho dos pedaços do mundo (CHUNK casas),
## com cores nos vértices, uma malha por pedaço e um só material. Só os
## pedaços perto da criatura existem, e no máximo MAX_BUILDS_PER_FRAME nascem
## por quadro, para andar não gerar engasgo.

const CHUNK := WorldGen.CHUNK
const TEXTURE_METERS := 3.0  # tamanho de um ladrilho da textura do chão
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
	WorldGen.Thing.RIO: Color("21405a"),
	WorldGen.Thing.VAU: Color("2c4d63"),  # vau: água rasa, mais clara
}
const WATER_DRIFT := Vector2(0.018, 0.011)  # deslocamento das ondas por segundo (ladrilhos)
const WATER_LEVEL := -0.18  # a água fica abaixo do chão
const BANK_COLOR := Color("1c2a26")
const FALLBACK_COLOR := Color("3a3a3a")  # bioma novo ainda sem cor
const TRAIL_COLOR := Color("6a5640")
const BRIDGE_COLOR := Color("503a24")

var _world: WorldGen
var _audio: SpatialAudio
var _harvest: Harvest
var _daytime: Node  # o relógio do mundo (Daytime); nulo = sempre noite
var _env: Environment
var _sun: DirectionalLight3D
var _ring_glow := 0.0
var _ring_check := 0.0
var _obras: BuildsView3D
var _wildlife: WildlifeView3D
var _flash_rect: ColorRect
var _held_torch: Node3D
var _held_flame: MeshInstance3D
var _bridges := {}  # pedaço -> casas de ponte (para refazer as coisas)
var _sources := {}  # pedaço -> [[casa, visível]] das fontes de recurso, para notar mudanças
var _camera: Camera3D
var _chunks := {}  # Vector2i (pedaço) -> MeshInstance3D
var _material: StandardMaterial3D
var _water_time := 0.0
var _materials := {}  # forma -> material com a textura dela
var _water_material: StandardMaterial3D
var _noise := FastNoiseLite.new()
var _shapes := {}  # forma (String) -> Mesh, criadas uma vez e repartidas entre os pedaços
var _center_chunk := Vector2i(1 << 30, 1 << 30)
var _wanted: Array[Vector2i] = []  # pedaços a montar, do mais perto ao mais longe
var _pos := Vector2.ZERO


func setup(world: WorldGen, audio: SpatialAudio, harvest: Harvest = null, builds: Builds = null, players: Dictionary = {}, my_id := 0, birds: Node = null, horrors: Node = null, daytime: Node = null) -> void:
	_world = world
	_daytime = daytime
	_audio = audio
	_harvest = harvest
	_noise.seed = 1234
	_noise.frequency = 0.9
	var textures := WorldTextures.make_all()
	_material = _textured(textures["ground"])
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var bark := _textured(textures["bark"])
	var leaf := _textured(textures["leaf"])
	var stone := _textured(textures["stone"])
	# Cada forma ganha a textura que combina: casca nos troncos, hastes e peças
	# retas, folhagem nas copas, pedra nas pedras e arbustos.
	_materials = {"trunk": bark, "stalk": bark, "box": bark, "cone": leaf, "blob": stone}
	_water_material = StandardMaterial3D.new()
	_water_material.vertex_color_use_as_albedo = true
	_water_material.roughness = 0.12
	_water_material.normal_enabled = true
	_water_material.normal_texture = WorldTextures.water_normal()
	_water_material.normal_scale = 0.8
	_water_material.texture_repeat = true
	_water_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_water_material.metallic_specular = 0.9
	_water_material.emission_enabled = true
	_water_material.emission = Color("0d2233")
	_water_material.emission_energy_multiplier = 0.6
	_make_shapes()
	_camera = Camera3D.new()
	_camera.name = "Olhos"
	_camera.fov = FOV
	_camera.far = FOG_END * 1.5
	_camera.near = 0.05
	add_child(_camera)
	_camera.make_current()
	_setup_environment()
	if builds != null:
		_obras = BuildsView3D.new()
		_obras.name = "Obras3D"
		add_child(_obras)
		_obras.setup(world, builds, players, my_id, _shapes, _materials)
	if birds != null or horrors != null:
		var wildlife := WildlifeView3D.new()
		wildlife.name = "Bichos3D"
		add_child(wildlife)
		wildlife.setup(birds, horrors, _shapes)
		_wildlife = wildlife


## Chamado a cada movimento: onde a criatura está. O giro vem do ouvinte,
## que já gira suave de uma direção à outra.
func follow(pos: Vector2) -> void:
	_pos = pos
	if _camera == null:
		return
	_camera.position = Vector3(pos.x, 0.0, pos.y) * METERS + Vector3.UP * EYE_HEIGHT
	if _obras != null:
		_obras.follow(pos)
	var chunk := _chunk_of(WorldGen.cell_of(pos))
	if chunk != _center_chunk:
		_center_chunk = chunk
		_plan(chunk)


## As construções mudaram (nova, em andamento, acesa ou apagada).
func refresh_builds() -> void:
	if _obras != null:
		_obras.refresh()


## Um clarão suave que se desfaz em "seconds" (sinal visual, sem texto); o
## 2D de depuração tem o seu, mas fica escondido quando o 3D está ligado.
func flash(seconds: float) -> void:
	if _flash_rect == null:
		var layer := CanvasLayer.new()
		layer.layer = 10
		add_child(layer)
		_flash_rect = ColorRect.new()
		_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(_flash_rect)
	_flash_rect.color = Color(0.85, 0.93, 1.0, 0.35)
	var tween := create_tween()
	tween.tween_property(_flash_rect, "color:a", 0.0, maxf(seconds, 0.1))


## A tocha na mão esquerda, no canto da tela: "held" se há uma tocha na mão,
## "lit" se está acesa (apagada, só o cabo).
func set_held_torch(held: bool, lit: bool) -> void:
	if _camera == null:
		return
	if _held_torch == null:
		_make_held_torch()
	_held_torch.visible = held
	_held_flame.visible = held and lit


func _make_held_torch() -> void:
	_held_torch = Node3D.new()
	_held_torch.name = "TochaNaMao"
	_held_torch.position = Vector3(-0.34, -0.42, -0.75)
	_held_torch.rotation_degrees = Vector3(18.0, 0.0, -10.0)
	_camera.add_child(_held_torch)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("4a3626")
	wood.roughness = 1.0
	var stick := MeshInstance3D.new()
	stick.mesh = _shapes["trunk"]
	stick.material_override = wood
	stick.scale = Vector3(0.14, 0.55, 0.14)
	stick.position = Vector3(0.0, 0.0, 0.0)
	stick.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_held_torch.add_child(stick)
	var wrap := MeshInstance3D.new()  # o pano embebido em resina na ponta
	wrap.mesh = _shapes["blob"]
	wrap.material_override = wood
	wrap.scale = Vector3(0.06, 0.09, 0.06)
	wrap.position = Vector3(0.0, 0.28, 0.0)
	wrap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_held_torch.add_child(wrap)
	_held_flame = MeshInstance3D.new()
	_held_flame.mesh = _shapes["cone"]
	var fire := StandardMaterial3D.new()
	fire.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fire.albedo_color = Color("ff8a3a")
	_held_flame.material_override = fire
	_held_flame.scale = Vector3(0.07, 0.17, 0.07)
	_held_flame.position = Vector3(0.0, 0.38, 0.0)
	_held_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_held_torch.add_child(_held_flame)


## As tochas acesas (a sua, se estiver acesa, e as dos outros).
func set_torches(mine: Variant, others: Array) -> void:
	if _obras != null:
		_obras.set_torches(mine, others)


## Um golpe acertou o Calado.
func pulse_horror() -> void:
	if _wildlife != null:
		_wildlife.pulse()


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
	_env = env
	var holder := WorldEnvironment.new()
	holder.environment = env
	add_child(holder)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, 30.0, 0.0)
	light.light_color = Color("a9b6cf")
	light.light_energy = 0.55
	light.shadow_enabled = false
	add_child(light)
	_sun = light
	_update_sky(0.0)


static func _chunk_of(cell: Vector2i) -> Vector2i:
	return Vector2i(floori(float(cell.x) / CHUNK), floori(float(cell.y) / CHUNK))


## Decide quais pedaços devem existir: apaga os que ficaram longe e põe numa
## fila, do mais perto ao mais longe, os que faltam.
func _plan(center: Vector2i) -> void:
	for key: Vector2i in _chunks.keys():
		if maxi(absi(key.x - center.x), absi(key.y - center.y)) > RADIUS_CHUNKS + 1:
			_chunks[key].queue_free()
			_chunks.erase(key)
			_sources.erase(key)
			_bridges.erase(key)
	_wanted.clear()
	for dy in range(-RADIUS_CHUNKS, RADIUS_CHUNKS + 1):
		for dx in range(-RADIUS_CHUNKS, RADIUS_CHUNKS + 1):
			var key := center + Vector2i(dx, dy)
			if not _chunks.has(key):
				_wanted.append(key)
	_wanted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - center).length_squared() > (b - center).length_squared())  # o mais perto no fim, para pop_back


func _process(delta: float) -> void:
	_update_sky(delta)
	_animate_water(delta)
	if _held_flame != null and _held_flame.visible:
		var flicker := 1.0 + 0.12 * sin(Time.get_ticks_msec() * 0.021) + 0.06 * sin(Time.get_ticks_msec() * 0.047)
		_held_flame.scale = Vector3(0.07, 0.17 * flicker, 0.07)
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
	var ground := _Surface.new()
	var water := _Surface.new()
	var bridges := []  # casas de ponte, para a peça em 3D
	for y in CHUNK:
		for x in CHUNK:
			var cell := first + Vector2i(x, y)
			var thing := _world.thing_at(cell)
			var x0 := cell.x * METERS
			var x1 := x0 + METERS
			var z0 := cell.y * METERS
			var z1 := z0 + METERS
			if _is_water(thing):
				# Água: um plano mais baixo e, onde o vizinho é terra, uma
				# parede de margem do chão até a água.
				water.quad(Vector3(x0, WATER_LEVEL, z0), Vector3(x1, WATER_LEVEL, z0), Vector3(x1, WATER_LEVEL, z1), Vector3(x0, WATER_LEVEL, z1), _cell_color(cell), Vector3.UP)
				for dir: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if _is_water(_world.thing_at(cell + dir)):
						continue
					var a: Vector3
					var b: Vector3
					if dir.x == 1:
						a = Vector3(x1, 0.0, z1)
						b = Vector3(x1, 0.0, z0)
					elif dir.x == -1:
						a = Vector3(x0, 0.0, z0)
						b = Vector3(x0, 0.0, z1)
					elif dir.y == 1:
						a = Vector3(x0, 0.0, z1)
						b = Vector3(x1, 0.0, z1)
					else:
						a = Vector3(x1, 0.0, z0)
						b = Vector3(x0, 0.0, z0)
					var down := Vector3(0.0, WATER_LEVEL, 0.0)
					ground.quad(a, b, b + down, a + down, BANK_COLOR, Vector3(dir.x, 0.0, dir.y))
				continue
			if thing == WorldGen.Thing.PONTE:
				bridges.append(cell)
			ground.quad(Vector3(x0, 0.0, z0), Vector3(x1, 0.0, z0), Vector3(x1, 0.0, z1), Vector3(x0, 0.0, z1), _cell_color(cell), Vector3.UP)
	var mesh := ArrayMesh.new()
	ground.add_to(mesh, _material)
	water.add_to(mesh, _water_material)
	var instance := MeshInstance3D.new()
	instance.name = "Chao_%d_%d" % [key.x, key.y]
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	_chunks[key] = instance
	_bridges[key] = bridges
	_add_things(instance, first, bridges)


static func _is_water(thing: int) -> bool:
	return WATER_COLORS.has(thing)


## Uma malha que se monta quadrado a quadrado (cores nos vértices).
class _Surface:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color, normal: Vector3) -> void:
		var v := vertices.size()
		vertices.append_array(PackedVector3Array([a, b, c, d]))
		for point: Vector3 in [a, b, c, d]:
			colors.append(color)
			normals.append(normal)
			# Textura em coordenadas do mundo (um ladrilho a cada TEXTURE_METERS), para
			# não haver emenda entre casas nem entre pedaços.
			uvs.append(Vector2(point.x, point.z) / TEXTURE_METERS if normal.y > 0.5 else Vector2(point.x + point.z, point.y) / TEXTURE_METERS)
		# O mesmo giro serve para chão (cima) e margens: a luz de duas faces
		# não importa, o material não tem culling.
		indices.append_array(PackedInt32Array([v, v + 1, v + 2, v, v + 2, v + 3]))

	func add_to(mesh: ArrayMesh, material: Material) -> void:
		if vertices.is_empty():
			return
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)


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


# --- Etapa 2: coisas em cima do chão -------------------------------------

const TREE_CROWN := {
	WorldGen.Biome.FLORESTA_GELADA: Color("5a737d"),
	WorldGen.Biome.BREJO: Color("3b4a2e"),
	WorldGen.Biome.BAMBUZAL: Color("2c4a28"),
}
const TREE_CROWN_DEFAULT := Color("1f3324")
const TRUNK_COLOR := Color("3a2c22")
const SHRUB_COLOR := Color("2f4a2c")
const BAMBOO_COLOR := Color("5f7d3c")
const STONE_COLOR := Color("69686a")
const CLAY_COLOR := Color("8f5844")
const FLINT_COLOR := Color("2a3036")
const FIBER_COLOR := Color("b3a468")
const VINE_COLOR := Color("2d5430")


func _make_shapes() -> void:
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.12
	trunk.bottom_radius = 0.2
	trunk.height = 1.0
	trunk.radial_segments = 6
	trunk.rings = 1
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 1.0
	cone.height = 1.0
	cone.radial_segments = 7
	cone.rings = 1
	var blob := SphereMesh.new()
	blob.radius = 0.5
	blob.height = 1.0
	blob.radial_segments = 8
	blob.rings = 4
	var stalk := CylinderMesh.new()
	stalk.top_radius = 0.05
	stalk.bottom_radius = 0.08
	stalk.height = 1.0
	stalk.radial_segments = 5
	stalk.rings = 1
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	_shapes = {"trunk": trunk, "cone": cone, "blob": blob, "stalk": stalk, "box": box}


## Número estável de 0 a 1 por casa e "sal": a mesma casa sempre sai igual.
static func _rand(cell: Vector2i, salt: int) -> float:
	var h := (cell.x * 73856093) ^ (cell.y * 19349663) ^ (salt * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	return float((h ^ (h >> 16)) & 0xFFFF) / 65535.0


## A fonte desta casa está de pé (não foi derrubada nem recolhida)?
func _standing(cell: Vector2i, thing: int) -> bool:
	if _harvest == null or not Harvest.is_source(thing):
		return true
	return _harvest.is_available(cell) and not _world.cleared.has(cell)


## Chamado quando algo foi colhido, derrubado ou rebrotou: refaz só os
## pedaços onde alguma fonte mudou de estado.
func refresh_state() -> void:
	for key: Vector2i in _chunks:
		for entry: Array in _sources.get(key, []):
			if _standing(entry[0], _world.thing_at(entry[0])) != entry[1]:
				var old: Node = _chunks[key].get_node_or_null("Coisas")
				if old != null:
					_chunks[key].remove_child(old)
					old.queue_free()
				_add_things(_chunks[key], key * CHUNK, _bridges.get(key, []))
				break


func _add_things(parent: Node3D, first: Vector2i, bridges: Array = []) -> void:
	var lists := {"trunk": [], "cone": [], "blob": [], "stalk": [], "box": []}
	var sources := []
	for bridge: Vector2i in bridges:
		_add_bridge(lists, bridge)
	for y in CHUNK:
		for x in CHUNK:
			var cell := first + Vector2i(x, y)
			var thing := _world.thing_at(cell)
			if thing == WorldGen.Thing.NADA:
				continue
			if Harvest.is_source(thing):
				var standing := _standing(cell, thing)
				sources.append([cell, standing])
				if not standing:
					continue
			var base := Vector3((cell.x + 0.5) * METERS, 0.0, (cell.y + 0.5) * METERS)
			var r1 := _rand(cell, 1)
			var r2 := _rand(cell, 2)
			var r3 := _rand(cell, 3)
			var turn := r1 * TAU
			var shade := 0.85 + 0.3 * r2
			match thing:
				WorldGen.Thing.ARVORE:
					var s := 0.8 + 0.5 * r1
					put(lists, "trunk", base, Vector3(s, 2.2 * s, s), turn, 1.1 * s, TRUNK_COLOR * shade)
					var crown: Color = TREE_CROWN.get(_world.biome_at(cell), TREE_CROWN_DEFAULT)
					put(lists, "cone", base, Vector3(1.3 * s, 3.4 * s, 1.3 * s), turn, 3.3 * s, crown * shade)
				WorldGen.Thing.ARBUSTO, WorldGen.Thing.ARBUSTO_FRUTAS:
					var s := 0.8 + 0.5 * r1
					# Arbusto é arbusto: o de frutas não pode se distinguir (decisão do Gabs).
					put(lists, "blob", base, Vector3(1.0 * s, 0.7 * s, 1.0 * s), turn, 0.3 * s, SHRUB_COLOR * shade)
				WorldGen.Thing.BAMBU:
					for k in 3:
						var offset := Vector3((_rand(cell, 10 + k) - 0.5) * 1.0, 0.0, (_rand(cell, 20 + k) - 0.5) * 1.0)
						var h := 3.5 + 2.0 * _rand(cell, 30 + k)
						put(lists, "stalk", base + offset, Vector3(1.0, h, 1.0), 0.0, h * 0.5, BAMBOO_COLOR * shade)
				WorldGen.Thing.PEDRAS:
					var s := 0.6 + 0.6 * r1
					put(lists, "blob", base, Vector3(s, 0.6 * s * (0.7 + r3), s * (0.8 + 0.4 * r2)), turn, 0.15 * s, STONE_COLOR * shade)
				WorldGen.Thing.ARGILA:
					put(lists, "blob", base, Vector3(0.9, 0.25, 0.9), turn, 0.05, CLAY_COLOR * shade)
				WorldGen.Thing.SILEX:
					put(lists, "blob", base, Vector3(0.3, 0.22, 0.25), turn, 0.07, FLINT_COLOR * shade)
				WorldGen.Thing.FIBRA:
					put(lists, "stalk", base, Vector3(2.0, 0.6, 2.0), turn, 0.3, FIBER_COLOR * shade)
				WorldGen.Thing.CIPO:
					put(lists, "blob", base, Vector3(0.6, 0.3, 0.6), turn, 0.1, VINE_COLOR * shade)
	_sources[first / CHUNK] = sources
	var holder_parent := Node3D.new()
	holder_parent.name = "Coisas"
	parent.add_child(holder_parent)
	flush(lists, _shapes, _materials, holder_parent)


## Cria um MultiMesh por forma com as peças guardadas e os põe em "parent".
## "materials": um material por forma (Dictionary) ou um só para todas.
static func flush(lists: Dictionary, shapes: Dictionary, materials: Variant, parent: Node3D) -> void:
	for shape: String in lists:
		var items: Array = lists[shape]
		if items.is_empty():
			continue
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_colors = true
		multi.mesh = shapes[shape]
		multi.instance_count = items.size()
		for i in items.size():
			multi.set_instance_transform(i, items[i][0])
			multi.set_instance_color(i, items[i][1])
		var holder := MultiMeshInstance3D.new()
		holder.multimesh = multi
		holder.material_override = materials[shape] if materials is Dictionary else materials
		holder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(holder)


## Material de cores nos vértices com uma textura em tons de cinza por baixo.
static func _textured(texture: Texture2D) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.texture_repeat = true
	material.roughness = 1.0
	return material


## Guarda uma peça: escala, giro, altura do centro e cor.
static func put(lists: Dictionary, shape: String, at: Vector3, scale: Vector3, turn: float, height: float, color: Color) -> void:
	var basis := Basis(Vector3.UP, turn).scaled(scale)
	color.a = 1.0
	lists[shape].append([Transform3D(basis, at + Vector3.UP * height), color])


## Ponte: um tablado um pouco acima do chão e, onde a água encosta, um
## guarda-corpo baixo.
func _add_bridge(lists: Dictionary, cell: Vector2i) -> void:
	var center := Vector3((cell.x + 0.5) * METERS, 0.0, (cell.y + 0.5) * METERS)
	var shade := 0.9 + 0.2 * _rand(cell, 4)
	put(lists, "box", center, Vector3(METERS, 0.14, METERS), 0.0, 0.07, BRIDGE_COLOR * shade)
	var half := METERS * 0.5 - 0.06
	for dir: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if not _is_water(_world.thing_at(cell + dir)):
			continue
		var side := Vector3(dir.x, 0.0, dir.y) * half
		var size := Vector3(0.1, 0.6, METERS) if dir.x != 0 else Vector3(METERS, 0.6, 0.1)
		put(lists, "box", center + side, size, 0.0, 0.14 + 0.3, BRIDGE_COLOR * 0.75)


# --- Dia e noite --------------------------------------------------------------

const DAY_SKY := Color("56666b")  # céu encoberto, verde-acinzentado
const NIGHT_SKY := Color("0d1217")
const DAY_FOG := Color("5c6b70")
const NIGHT_FOG := Color("141b20")
const DUSK_TINT := Color("a2603c")  # o céu esquenta um pouco entre o dia e a noite
const DAY_AMBIENT := Color("8d9a9e")
const NIGHT_AMBIENT := Color("56627a")
const SUN_COLOR := Color("d6cfbd")
const MOON_COLOR := Color("a9b6cf")
const RING_GLOW := Color("9fb4d6")  # a luz refletida do anel, de noite


## A água se mexe: o relevo das ondas desliza devagar em duas direções ao
## mesmo tempo (só mexe no deslocamento do material, sem custo de malha).
func _animate_water(delta: float) -> void:
	_water_time += delta
	_water_material.uv1_offset = Vector3(_water_time * WATER_DRIFT.x, _water_time * WATER_DRIFT.y, 0.0)
	_water_material.uv1_scale = Vector3.ONE * (0.9 + 0.1 * sin(_water_time * 0.3))


## Liga céu, neblina e luz ao relógio do jogo: dark fantasy, então o dia é
## encoberto e pálido, nunca ensolarado; o anel clareia a noite e escurece o dia.
func _update_sky(delta: float) -> void:
	if _env == null:
		return
	var dark := 1.0  # 0 dia, 1 noite
	var hour := 0.0
	if _daytime != null:
		dark = _daytime.darkness_here()
		hour = DayCycle.hour_of(_daytime.t)
		_ring_check -= delta
		if _ring_check <= 0.0:
			_ring_check = 0.5
			_ring_glow = _daytime.ring_strength_at(_pos)
	var warm := sin(PI * clampf(dark, 0.0, 1.0)) * 0.35  # só entre o dia e a noite
	var sky := DAY_SKY.lerp(NIGHT_SKY, dark).lerp(DUSK_TINT, warm * 0.5)
	var fog := DAY_FOG.lerp(NIGHT_FOG, dark).lerp(DUSK_TINT, warm * 0.4)
	# De noite, a faixa do anel reflete luz: o céu e o chão clareiam.
	var glow := _ring_glow * dark
	sky = sky.lerp(RING_GLOW * 0.35, glow * 0.5)
	fog = fog.lerp(RING_GLOW * 0.3, glow * 0.5)
	_env.background_color = sky
	_env.fog_light_color = fog
	_env.ambient_light_color = DAY_AMBIENT.lerp(NIGHT_AMBIENT, dark).lerp(RING_GLOW, glow * 0.5)
	_env.ambient_light_energy = lerpf(1.3, 0.8, dark) + 0.5 * glow
	# O sol cruza o céu de leste a oeste das 6h às 18h; de noite, uma lua fixa.
	var progress := clampf((hour - 6.0) / 12.0, 0.0, 1.0)
	var sun_pitch := -(12.0 + 55.0 * sin(PI * progress))
	var sun_yaw := lerpf(90.0, 270.0, progress)
	_sun.rotation_degrees = Vector3(lerpf(sun_pitch, -40.0, dark), lerpf(sun_yaw, 30.0, dark), 0.0)
	_sun.light_color = SUN_COLOR.lerp(MOON_COLOR, dark).lerp(RING_GLOW, glow * 0.4)
	_sun.light_energy = lerpf(0.9, 0.3, dark) + 0.4 * glow
