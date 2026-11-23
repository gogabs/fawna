class_name WildlifeView3D
extends Node3D
## Etapa 5 do 3D: os pássaros e o Calado. Só lê o que os nós Birds e Horrors
## já sabem (as posições que o servidor manda) e desenha por cima. Os pássaros
## são formas simples que batem asas quando voam; o Calado é uma nuvenzona
## cinza-escura de partículas, sem corpo nem rosto: algo que se aproxima.
## Encarar o Calado não muda nada nele. Um golpe o empurra (a posição do
## servidor já mostra o recuo, e a nuvem desliza até lá) e a agita; quando
## ele desiste ou some, a nuvem se desfaz aos poucos.

const METERS := WorldGen.METERS_PER_CELL
const CLOUD_HEIGHT := 1.3
const CLOUD_RADIUS := 2.2
const CLOUD_PARTICLES := 40
const FLAP_HZ := 14.0

## Por espécie (ordem de Aviary.Species): cor e tamanho em metros.
const LOOKS := [
	{"color": Color("6a6560"), "size": 0.28},  # sabiá-da-névoa
	{"color": Color("7a5a3c"), "size": 0.16},  # carriça-do-cardo
	{"color": Color("8a7a78"), "size": 0.24},  # rolinha-do-junco
	{"color": Color("1d1d22"), "size": 0.5},  # corvo-cinza
	{"color": Color("9a9080"), "size": 0.45},  # coruja-do-breu
	{"color": Color("5a4a3a"), "size": 0.42},  # gavião-peneira
	{"color": Color("4a7a3a"), "size": 0.26},  # periquito-do-brejo
]

var _birds_node: Node
var _horses_node: Node
var _herd := {}  # id -> Node3D (cavalinhos)
var _horrors_node: Node
var _shapes := {}
var _flock := {}  # id -> Node3D
var _clouds := {}  # id -> CPUParticles3D
var _time := 0.0
var _pulse := 0.0  # 1 logo após um golpe acertar a nuvem, volta a 0
var _cloud_mesh: SphereMesh
var _cloud_material: StandardMaterial3D


func setup(birds: Node, horrors: Node, shapes: Dictionary, horses: Node = null) -> void:
	_birds_node = birds
	_horses_node = horses
	_horrors_node = horrors
	_shapes = shapes
	_cloud_mesh = SphereMesh.new()
	_cloud_mesh.radius = 0.5
	_cloud_mesh.height = 1.0
	_cloud_mesh.radial_segments = 8
	_cloud_mesh.rings = 4
	_cloud_material = StandardMaterial3D.new()
	_cloud_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cloud_material.vertex_color_use_as_albedo = true
	_cloud_material.albedo_color = Color(0.1, 0.1, 0.12)
	_cloud_material.roughness = 1.0
	_cloud_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cloud_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cloud_mesh.material = _cloud_material


func _process(delta: float) -> void:
	_time += delta
	_sync_birds()
	_sync_horses(delta)
	_sync_horrors(delta)


func _sync_birds() -> void:
	var species: Dictionary = _birds_node.bird_species() if _birds_node != null else {}
	for id: int in _flock.keys():
		if not species.has(id):
			_flock[id].queue_free()
			_flock.erase(id)
	for id: int in species:
		if not _flock.has(id):
			var node := _make_bird(int(species[id]))
			_flock[id] = node
			add_child(node)
			node.position = _birds_node.bird_position(id)
		var node: Node3D = _flock[id]
		var goal: Vector3 = _birds_node.bird_position(id)
		var flying: bool = _birds_node.bird_flying(id)
		var heading := goal - node.position
		if flying and Vector2(heading.x, heading.z).length() > 0.01:
			node.rotation.y = lerp_angle(node.rotation.y, atan2(-heading.x, -heading.z), 0.3)
		node.position = goal
		var flap := sin(_time * TAU * FLAP_HZ) * 0.9 if flying else 0.15
		node.get_node("AsaE").rotation.z = flap
		node.get_node("AsaD").rotation.z = -flap


func _make_bird(species: int) -> Node3D:
	var look: Dictionary = LOOKS[clampi(species, 0, LOOKS.size() - 1)]
	var size: float = look["size"]
	var color: Color = look["color"]
	var node := Node3D.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	_piece(node, "blob", Vector3(0.0, 0.0, 0.0), Vector3(size * 0.9, size * 0.7, size * 1.3), material)
	_piece(node, "blob", Vector3(0.0, size * 0.25, -size * 0.65), Vector3(size * 0.55, size * 0.5, size * 0.55), material)
	_piece(node, "box", Vector3(0.0, 0.0, size * 0.75), Vector3(size * 0.25, size * 0.05, size * 0.7), material)
	for side in ["AsaE", "AsaD"]:
		var wing := Node3D.new()
		wing.name = side
		wing.position = Vector3((-1 if side == "AsaE" else 1) * size * 0.35, size * 0.15, 0.0)
		_piece(wing, "box", Vector3((-1 if side == "AsaE" else 1) * size * 0.8, 0.0, 0.0), Vector3(size * 1.6, size * 0.05, size * 0.7), material)
		node.add_child(wing)
	return node


const HORSE_TROT_HZ := 1.7


func _sync_horses(delta: float) -> void:
	var coats: Dictionary = _horses_node.horse_coats() if _horses_node != null else {}
	for id: int in _herd.keys():
		if not coats.has(id):
			_herd[id].queue_free()
			_herd.erase(id)
	for id: int in coats:
		var point: Vector2 = _horses_node.horse_point(id)
		var goal := Vector3(point.x * METERS, WorldView3D.ground_height(point.x * METERS, point.y * METERS), point.y * METERS)
		if not _herd.has(id):
			var made := _make_horse(int(coats[id]))
			_herd[id] = made
			add_child(made)
			made.position = goal
		var node: Node3D = _herd[id]
		var gait: int = _horses_node.horse_gait(id)
		var heading: Vector2 = _horses_node.horse_heading(id)
		if gait != Herd.Gait.STAND and heading.length() > 0.01:
			node.rotation.y = lerp_angle(node.rotation.y, atan2(-heading.x, -heading.y), minf(1.0, delta * 6.0))
		node.position = goal
		# O relógio do passo avança no ritmo do andar e do ânimo do cavalo.
		var hz: float = HORSE_TROT_HZ * (1.8 if gait == Herd.Gait.GALLOP else (1.4 if gait == Herd.Gait.TROT else 1.0)) * _horses_node.horse_tempo(id)
		var phase: float = float(node.get_meta("fase", 0.0)) + delta * hz
		node.set_meta("fase", fmod(phase, 1000.0))
		HorseModel.animate(node, gait, phase, _time, id, delta)


## O cavalinho em 3D (ver HorseModel).
func _make_horse(coat: int) -> Node3D:
	return HorseModel.build(coat, _shapes)


func _piece(parent: Node3D, shape: String, at: Vector3, scale_to: Vector3, material: Material) -> void:
	var piece := MeshInstance3D.new()
	piece.mesh = _shapes[shape]
	piece.material_override = material
	piece.position = at
	piece.scale = scale_to
	piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(piece)


func _sync_horrors(delta: float) -> void:
	_pulse = move_toward(_pulse, 0.0, delta * 2.5)
	var known: Dictionary = _horrors_node.shown_horrors() if _horrors_node != null else {}
	for id: int in _clouds.keys():
		if not known.has(id):
			_dissolve(_clouds[id])
			_clouds.erase(id)
	for id: int in known:
		if not _clouds.has(id):
			var cloud := _make_cloud()
			_clouds[id] = cloud
			add_child(cloud)
		var pos: Vector2 = known[id]["pos"]
		var cloud: CPUParticles3D = _clouds[id]
		cloud.position = Vector3(pos.x * METERS, CLOUD_HEIGHT, pos.y * METERS)
		# Quando ele desiste (RETREAT), para de gerar nuvem: o que já existe
		# se desfaz sozinho enquanto ele se afasta.
		if int(known[id]["mode"]) == Horrors.Mode.RETREAT:
			cloud.emitting = false
		var pulse_scale := lerpf(1.0, 1.35, _pulse)
		cloud.scale = Vector3.ONE * pulse_scale


## Um golpe acertou: a nuvem se agita por um instante.
func pulse() -> void:
	_pulse = 1.0


## Some devagar: para de gerar partículas e se solta depois de a última sumir.
func _dissolve(cloud: CPUParticles3D) -> void:
	cloud.emitting = false
	get_tree().create_timer(cloud.lifetime + 0.2).timeout.connect(cloud.queue_free)


## A nuvenzona: esferas cinza-escuras e translúcidas que se misturam.
func _make_cloud() -> CPUParticles3D:
	var cloud := CPUParticles3D.new()
	cloud.name = "Calado"
	cloud.amount = CLOUD_PARTICLES
	cloud.lifetime = 4.0
	cloud.preprocess = 4.0
	cloud.local_coords = true
	cloud.mesh = _cloud_mesh
	cloud.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	cloud.emission_sphere_radius = CLOUD_RADIUS
	cloud.direction = Vector3.UP
	cloud.spread = 180.0
	cloud.initial_velocity_min = 0.1
	cloud.initial_velocity_max = 0.5
	cloud.gravity = Vector3.ZERO
	cloud.scale_amount_min = 2.0
	cloud.scale_amount_max = 4.0
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color(0.1, 0.1, 0.12, 0.0), Color(0.1, 0.1, 0.12, 0.5), Color(0.06, 0.06, 0.08, 0.5), Color(0.1, 0.1, 0.12, 0.0)])
	ramp.offsets = PackedFloat32Array([0.0, 0.3, 0.7, 1.0])
	cloud.color_ramp = ramp
	cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return cloud
