class_name BuildsView3D
extends Node3D
## Etapa 4 do 3D: as construções (marco, fogueira, abrigo, oficina, armazém)
## e as outras criaturas. Só lê o espelho das obras (Builds) e a lista de
## jogadores, e não guarda nada do jogo. As obras são refeitas por inteiro
## quando algo muda (são poucas); as criaturas andam a cada quadro.

const METERS := WorldGen.METERS_PER_CELL
const SHOW_RANGE := 120.0  # metros: obras mais longe que isso nem são montadas
const FLAME_COLOR := Color("ff8a3a")
const STONE := Color("77767a")
const LOG := Color("4a3626")
const ASH := Color("2a2624")
const FLOOR := Color("8a6c52")
const POST := Color("5a4330")
const WALL := Color("7d6c4f")
const ROOF := Color("4f4031")
const FURNITURE := Color("65472e")
const NOSE := Color("e6d6b8")
const CLAY := Color("9a5a3c")
const BODY_SLOTS := 6

var _world: WorldGen
var _builds: Builds
var _players: Dictionary
var _my_id := 0
var _material: StandardMaterial3D
var _materials := {}
var _flame_material: StandardMaterial3D
var _shapes := {}
var _built_root: Node3D
var _folk := {}  # id -> Node3D
var riders := {}  # id de jogador -> true quando está montado
var _center := Vector2.ZERO
var _flickers := []  # [{ light, base, phase }] das luzes de fogueira
var _torch_lights: Array[OmniLight3D] = []
var _torch_flames: Array[MeshInstance3D] = []
var _clock := 0.0
const FIRE_ENERGY := 5.0
const FIRE_RANGE := 18.0
const TORCH_SLOTS := 4
const TORCH_ENERGY := 2.6
const TORCH_RANGE := 11.0


func setup(world: WorldGen, builds: Builds, players: Dictionary, my_id: int, shapes: Dictionary, materials: Dictionary) -> void:
	_world = world
	_builds = builds
	_players = players
	_my_id = my_id
	_shapes = shapes
	_materials = materials
	_material = materials["blob"]
	_flame_material = StandardMaterial3D.new()
	_flame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flame_material.albedo_color = FLAME_COLOR
	_flame_material.emission_enabled = true
	_flame_material.emission = FLAME_COLOR
	_flame_material.emission_energy_multiplier = 2.0
	for i in TORCH_SLOTS:
		var light := OmniLight3D.new()
		light.light_color = FLAME_COLOR
		light.light_energy = TORCH_ENERGY
		light.omni_range = TORCH_RANGE
		light.visible = false
		add_child(light)
		_torch_lights.append(light)
		var flame := MeshInstance3D.new()
		flame.mesh = _shapes["blob"]
		flame.material_override = _flame_material
		flame.scale = Vector3(0.14, 0.22, 0.14)
		flame.visible = false
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(flame)
		_torch_flames.append(flame)
	refresh()


## As tochas acesas: "mine" é a da própria criatura (só luz, na mão esquerda) e
## "others" são as posições (casas) de quem leva uma, com chama visível.
func set_torches(mine: Variant, others: Array) -> void:
	var i := 0
	if mine is Vector2:
		_place_torch(i, mine, false)
		i += 1
	for point: Vector2 in others:
		if i >= TORCH_SLOTS:
			break
		_place_torch(i, point, true)
		i += 1
	while i < TORCH_SLOTS:
		_torch_lights[i].visible = false
		_torch_flames[i].visible = false
		i += 1


func _place_torch(i: int, point: Vector2, flame_visible: bool) -> void:
	var at := Vector3(point.x * METERS, 1.0, point.y * METERS)
	_torch_lights[i].position = at
	_torch_lights[i].visible = true
	_torch_flames[i].position = at
	_torch_flames[i].visible = flame_visible


## Onde a criatura está (casas): as obras só aparecem por perto.
func follow(pos: Vector2) -> void:
	var moved := pos.distance_to(_center) * METERS > 30.0
	_center = pos
	if moved:
		refresh()


## Refaz todas as obras que estão por perto.
func refresh() -> void:
	if _builds == null:
		return
	if _built_root != null:
		remove_child(_built_root)
		_built_root.queue_free()
	_built_root = Node3D.new()
	_built_root.name = "Obras"
	add_child(_built_root)
	_flickers.clear()
	var lists := {"trunk": [], "cone": [], "blob": [], "stalk": [], "box": []}
	for build: Dictionary in _builds.all():
		var origin: Vector2 = Vector2(build["cell"])
		var size := int(build.get("size", 1))
		var middle := (origin + Vector2.ONE * size * 0.5)
		if middle.distance_to(_center) * METERS > SHOW_RANGE:
			continue
		_add_build(lists, build)
	WorldView3D.flush(lists, _shapes, _materials, _built_root)


func _cell_at(cell: Vector2i, height := 0.0) -> Vector3:
	return Vector3((cell.x + 0.5) * METERS, height, (cell.y + 0.5) * METERS)


func _add_build(lists: Dictionary, build: Dictionary) -> void:
	var kind := str(build["kind"])
	var finished := Crafting.stage_count(kind) if bool(build.get("done", false)) else int(build["stage"])
	var size := int(build.get("size", 1))
	if size <= 1:
		if kind == "forno":
			_add_oven(lists, build, finished)
		elif kind == "secador":
			_add_rack(lists, build, finished)
		elif Crafting.BUILDS[kind].get("fire", false):
			_add_fire(lists, build, finished)
		else:
			_add_marker(lists, build, finished)
	else:
		_add_house(lists, build, finished, size)


func _add_marker(lists: Dictionary, build: Dictionary, finished: int) -> void:
	var at := _cell_at(build["cell"])
	if finished >= 1:
		WorldView3D.put(lists, "blob", at, Vector3(1.5, 0.9, 1.5), 0.3, 0.4, STONE)
	if finished >= 2:
		WorldView3D.put(lists, "blob", at, Vector3(1.0, 0.9, 1.0), 1.1, 1.1, STONE * 0.9)
	if finished >= 3:
		WorldView3D.put(lists, "blob", at, Vector3(0.6, 0.6, 0.6), 2.0, 1.7, STONE * 1.1)


func _add_fire(lists: Dictionary, build: Dictionary, finished: int) -> void:
	var at := _cell_at(build["cell"])
	if finished >= 1:
		for i in 8:
			var a := TAU * i / 8.0
			WorldView3D.put(lists, "blob", at + Vector3(cos(a), 0.0, sin(a)) * 0.55, Vector3(0.32, 0.24, 0.32), a, 0.1, STONE)
	if finished >= 2:
		for i in 3:
			WorldView3D.put(lists, "box", at, Vector3(0.12, 0.12, 0.9), i * PI / 3.0, 0.14, LOG)
		if _builds.is_lit(int(build["id"])):
			var flame := MeshInstance3D.new()
			flame.mesh = _shapes["cone"]
			flame.material_override = _flame_material
			flame.position = at + Vector3.UP * 0.55
			flame.scale = Vector3(0.45, 0.9, 0.45)
			flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_built_root.add_child(flame)
			var light := OmniLight3D.new()
			light.light_color = FLAME_COLOR
			light.light_energy = FIRE_ENERGY
			light.omni_range = FIRE_RANGE
			light.position = at + Vector3.UP * 1.0
			_built_root.add_child(light)
			_flickers.append({"light": light, "base": FIRE_ENERGY, "phase": randf() * TAU})
		else:
			WorldView3D.put(lists, "blob", at, Vector3(0.7, 0.1, 0.7), 0.0, 0.05, ASH)


## Secador: dois esteios de bambu e o varal entre eles.
func _add_rack(lists: Dictionary, build: Dictionary, finished: int) -> void:
	if finished < 1:
		return
	var at := _cell_at(build["cell"])
	for side in [-0.6, 0.6]:
		WorldView3D.put(lists, "box", at + Vector3(side, 0.0, 0.0), Vector3(0.1, 1.6, 0.1), 0.0, 0.8, POST)
	WorldView3D.put(lists, "box", at, Vector3(1.3, 0.06, 0.06), 0.0, 1.5, POST)
	if not (build.get("rack", []) as Array).is_empty():
		WorldView3D.put(lists, "box", at, Vector3(1.0, 0.3, 0.08), 0.0, 1.3, CLAY)


## Forno: base de pedras, a cúpula de argila por cima e, aceso, a brasa na boca.
func _add_oven(lists: Dictionary, build: Dictionary, finished: int) -> void:
	var at := _cell_at(build["cell"])
	if finished >= 1:
		WorldView3D.put(lists, "box", at, Vector3(1.4, 0.4, 1.4), 0.0, 0.2, STONE)
	if finished >= 2:
		WorldView3D.put(lists, "blob", at, Vector3(1.2, 1.0, 1.2), 0.0, 0.85, CLAY)
	if finished >= 3 and _builds.is_lit(int(build["id"])):
		var light := OmniLight3D.new()
		light.light_color = FLAME_COLOR
		light.light_energy = FIRE_ENERGY * 0.4
		light.omni_range = FIRE_RANGE * 0.5
		light.position = at + Vector3.UP * 0.7
		_built_root.add_child(light)
		_flickers.append({"light": light, "base": FIRE_ENERGY * 0.4, "phase": randf() * TAU})


func _add_house(lists: Dictionary, build: Dictionary, finished: int, size: int) -> void:
	var origin: Vector2i = build["cell"]
	var entrance := str(build.get("entrance", ""))
	var door := Builds.door_cell(origin, size, entrance)
	var span := size * METERS
	var middle := Vector3((origin.x + size * 0.5) * METERS, 0.0, (origin.y + size * 0.5) * METERS)
	if finished >= 1:
		WorldView3D.put(lists, "box", middle, Vector3(span, 0.1, span), 0.0, 0.05, FLOOR)
	if finished >= 2:
		for cell: Vector2i in Builds.footprint_cells(origin, size):
			var inner := cell - origin
			var edge := inner.x == 0 or inner.y == 0 or inner.x == size - 1 or inner.y == size - 1
			if edge and cell != door and (inner.x + inner.y) % 2 == 0:
				WorldView3D.put(lists, "box", _cell_at(cell), Vector3(0.24, 2.6, 0.24), 0.0, 1.3, POST)
	if Builds.walls_up(build):
		for cell: Vector2i in Builds.footprint_cells(origin, size):
			var inner := cell - origin
			var horizontal := inner.y == 0 or inner.y == size - 1
			var vertical := inner.x == 0 or inner.x == size - 1
			if not (horizontal or vertical) or cell == door:
				continue
			var thick := Vector3(METERS, 2.2, 0.5) if horizontal and not vertical else Vector3(0.5, 2.2, METERS)
			if horizontal and vertical:
				thick = Vector3(0.9, 2.2, 0.9)
			WorldView3D.put(lists, "box", _cell_at(cell), thick, 0.0, 1.1, WALL)
	if finished >= 4:
		WorldView3D.put(lists, "box", middle, Vector3(span + 0.8, 0.15, span + 0.8), 0.0, 2.35, ROOF)
	if Builds.has_furniture(build):
		var cells := Builds.furniture_cells(build)
		if cells.has("bancada"):
			WorldView3D.put(lists, "box", _cell_at(cells["bancada"]), Vector3(1.2, 0.8, 0.7), 0.0, 0.4, FURNITURE)
		if cells.has("prateleiras"):
			WorldView3D.put(lists, "box", _cell_at(cells["prateleiras"]), Vector3(0.4, 1.6, 1.3), 0.0, 0.8, FURNITURE)


# --- Outras criaturas -------------------------------------------------------

func _process(delta: float) -> void:
	_clock += delta
	for entry: Dictionary in _flickers:
		var wobble := 0.85 + 0.1 * sin(_clock * 11.0 + float(entry["phase"])) + 0.05 * sin(_clock * 23.0 + float(entry["phase"]) * 2.0)
		(entry["light"] as OmniLight3D).light_energy = float(entry["base"]) * wobble
	for i in TORCH_SLOTS:
		if _torch_lights[i].visible:
			_torch_lights[i].light_energy = TORCH_ENERGY * (0.88 + 0.12 * sin(_clock * 14.0 + i * 1.7))
	if _players == null:
		return
	for id: int in _folk.keys():
		if not _players.has(id) or id == _my_id:
			_folk[id].queue_free()
			_folk.erase(id)
	for id: int in _players:
		if id == _my_id:
			continue
		var data: Dictionary = _players[id]
		var pos: Vector2 = data["pos"]
		var goal := Vector3(pos.x, 0.0, pos.y) * METERS
		var yaw := -Compass.angle(int(data.get("heading", 0)))
		if not _folk.has(id):
			var node := _make_creature(id, str(data.get("species", "")))
			node.position = goal
			node.rotation.y = yaw
			_folk[id] = node
			add_child(node)
		var node: Node3D = _folk[id]
		var before := node.position
		node.position = node.position.lerp(goal, minf(1.0, delta * 12.0))
		if node.has_node("Corpo"):
			var speed := before.distance_to(node.position) / maxf(delta, 0.001) / METERS
			SpeciesModel.animate(node, speed, _clock, id, delta, Vector2.ZERO, 0.0, 0.0, riders.has(id))
		node.rotation.y = lerp_angle(node.rotation.y, yaw, minf(1.0, delta * 10.0))


## Há uma parede de obra em "cell" (em casas) que tapa a câmera? Quem está dentro
## da obra não a vê como parede.
func wall_blocks(cell: Vector2i, from: Vector2) -> bool:
	if _builds == null:
		return false
	var build := _builds.at(cell)
	return not build.is_empty() and Crafting.is_large(build["kind"]) and Builds.walls_up(build) and not Builds.inside(build, from)


## O som do passo de outro jogador tocou: trava a perna nele.
func footfall(player_id: int) -> void:
	if _folk.has(player_id) and (_folk[player_id] as Node3D).has_node("Corpo"):
		SpeciesModel.footfall(_folk[player_id])


## Dispara uma ação (habilidade) no modelo de outro jogador.
func play_action(player_id: int, action: String) -> void:
	if _folk.has(player_id) and (_folk[player_id] as Node3D).has_node("Corpo"):
		SpeciesModel.play(_folk[player_id], action)


## Outro jogador: o modelo da sua espécie (SpeciesModel) ou, sem espécie, uma
## criatura simples: corpo, cabeça e um focinho que mostra para onde olha.
func _make_creature(id: int, species_id: String = "") -> Node3D:
	if SpeciesModel.has_model(species_id):
		var model := SpeciesModel.build(species_id, _shapes)
		model.name = "Criatura_%d" % id
		return model
	var node := Node3D.new()
	node.name = "Criatura_%d" % id
	var tint := Color.from_hsv(fmod(id * 0.137, 1.0), 0.35, 0.6)
	var parts := [
		["blob", Vector3(0.0, 0.4, 0.0), Vector3(0.6, 0.8, 0.7), tint],
		["blob", Vector3(0.0, 0.95, -0.1), Vector3(0.4, 0.4, 0.4), tint.lightened(0.15)],
		["blob", Vector3(0.0, 0.92, -0.38), Vector3(0.18, 0.16, 0.2), NOSE],
	]
	for part: Array in parts:
		var piece := MeshInstance3D.new()
		piece.mesh = _shapes[part[0]]
		var colored := _material.duplicate() as StandardMaterial3D
		colored.vertex_color_use_as_albedo = false
		colored.albedo_color = part[3]
		piece.material_override = colored
		piece.position = part[1]
		piece.scale = part[2]
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(piece)
	return node
