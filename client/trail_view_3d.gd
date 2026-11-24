class_name TrailView3D
extends Node3D
## O rastro do Caminheiro: uma névoa azulada que flutua baixa sobre o chão e
## traça a rota até o destino, a partir de onde a criatura está (como o feitiço
## de clarividência do Skyrim). Só visual: a rota vem do Caminheiro. Enquanto o
## cristal está apagado, não há nada.
##
## São poucas bolhas achatadas (um MultiMesh) que balançam devagar e somem na
## ponta de perto e na de longe. A névoa começa colada na criatura.
##
## Cada bolha tem um lugar fixo na rota (contado em metros a partir de onde a
## rota começou), então andar não arrasta as bolhas: as de perto somem quando a
## criatura passa por elas e novas aparecem lá na frente. Quando a rota é
## recalculada, as bolhas deslizam até o lugar novo; as que teriam de pular
## longe somem onde estão e reaparecem no lugar novo, sem trancos.

const METERS := WorldGen.METERS_PER_CELL
const PUFFS := 64
const SPACING := 1.0  # metros entre bolhas
const REACH := PUFFS * SPACING  # até onde o rastro vai à frente
const HEIGHT := 0.4
const REFRESH := 0.2  # segundos entre os recálculos
const NEAR_START := 0.4  # metros: perto disso a bolha some (dentro da criatura)
const NEAR_FULL := 1.4  # metros: daqui em diante a bolha aparece inteira
const GLIDE := 5.0  # quão depressa a bolha desliza até o lugar novo (por segundo)
const FADE_RATE := 2.5  # opacidade por segundo ao aparecer e sumir
const JUMP := 2.5  # metros: mais longe que isso, a bolha some e reaparece
const NONE := -1000000000  # vaga sem bolha (ids podem ser negativos: antes do primeiro beacon)
const SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, skip_vertex_transform;
uniform vec4 tint : source_color = vec4(0.62, 0.8, 0.98, 0.8);
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
varying float seed;
void vertex() {
	seed = float(INSTANCE_ID);
	// Cada bolha é um quadrado que sempre olha para a câmera.
	float t = TIME * 0.5 + float(INSTANCE_ID) * 1.7;
	vec3 center = MODEL_MATRIX[3].xyz + vec3(sin(t * 0.7) * 0.25, sin(t) * 0.12, cos(t * 0.5) * 0.25);
	vec2 scale = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz));
	mat4 billboard = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], vec4(center, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * billboard;
	VERTEX = (MODELVIEW_MATRIX * vec4(VERTEX.xy * scale, 0.0, 1.0)).xyz;
}
void fragment() {
	// Mancha macia: forte no meio, some na borda, com um leve repuxo.
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	float soft = pow(clamp(1.0 - d, 0.0, 1.0), 1.2);
	float swirl = 0.75 + 0.25 * sin(atan(p.y, p.x) * 3.0 + TIME * 0.4 + seed);
	// Some aos poucos onde encosta no chão, sem linha dura.
	float scene = texture(depth_tex, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec4 behind = INV_PROJECTION_MATRIX * vec4(vec3(SCREEN_UV, scene) * 2.0 - 1.0, 1.0);
#else
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, scene, 1.0);
#endif
	float gap = VERTEX.z - behind.z / behind.w;
	float touch = clamp(gap / 0.35, 0.0, 1.0);
	ALBEDO = tint.rgb;
	ALPHA = tint.a * soft * swirl * COLOR.a * touch;
}
"""

var _caminheiro: Caminheiro
var _multi: MultiMesh
var _clock := 0.0
var _route: Array[Vector2] = []  # beacons da última leitura, em metros
var _base := 0.0  # metros da rota já percorridos até o primeiro beacon de _route
# Estado de cada vaga do MultiMesh: qual bolha (id) ocupa, onde está, para onde
# vai, o tamanho e a opacidade.
var _ids := PackedInt32Array()
var _pos := PackedVector3Array()
var _goal := PackedVector3Array()
var _size := PackedFloat32Array()
var _alpha := PackedFloat32Array()
var _far := PackedFloat32Array()  # opacidade desejada pela ponta de longe
var _wanted := PackedInt32Array()  # id que deveria ocupar a vaga (NONE: nenhum)


func setup(caminheiro: Caminheiro) -> void:
	_caminheiro = caminheiro
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	var material := ShaderMaterial.new()
	material.shader = Shader.new()
	material.shader.code = SHADER
	mesh.material = material
	_multi = MultiMesh.new()
	_multi.transform_format = MultiMesh.TRANSFORM_3D
	_multi.use_colors = true
	_multi.mesh = mesh
	_multi.instance_count = PUFFS
	var holder := MultiMeshInstance3D.new()
	holder.multimesh = _multi
	holder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(holder)
	_ids.resize(PUFFS)
	_pos.resize(PUFFS)
	_goal.resize(PUFFS)
	_size.resize(PUFFS)
	_alpha.resize(PUFFS)
	_far.resize(PUFFS)
	_wanted.resize(PUFFS)
	_ids.fill(NONE)
	_wanted.fill(NONE)
	_alpha.fill(0.0)
	for i in PUFFS:
		_hide(i)


## Chamado a cada quadro com a posição da criatura (em casas).
func follow(pos: Vector2, delta: float) -> void:
	_clock -= delta
	if _clock <= 0.0:
		_clock = REFRESH
		_retarget(pos * METERS)
	_animate(pos * METERS, delta)


## Relê a rota e decide onde cada bolha deveria estar.
func _retarget(here: Vector2) -> void:
	_wanted.fill(NONE)
	if _caminheiro == null or not _caminheiro.active:
		_route.clear()
		return
	var route: Array[Vector2] = []
	for beacon: Vector2 in _caminheiro.route():
		route.append(beacon * METERS)
	if route.is_empty():
		_route.clear()
		return
	_base = advance_base(_route, route, _base)
	_route = route
	var spots := puff_spots(here, route, _base)
	var start := _base - here.distance_to(route[0])
	for id: int in spots:
		var slot := posmod(id, PUFFS)
		var spot: Vector2 = spots[id]
		_wanted[slot] = id
		var side := sin(id * 1.3) * 0.25
		var y := WorldView3D.ground_height(spot.x, spot.y) + HEIGHT + 0.12 * sin(id * 0.9)
		_goal[slot] = Vector3(spot.x + side, y, spot.y - side)
		_size[slot] = 1.5 + 0.5 * sin(id * 2.1)
		# A ponta de longe some aos poucos (nos últimos 10 m do alcance).
		_far[slot] = clampf((REACH - (id * SPACING - start)) / 10.0, 0.0, 1.0)


## Desliza, faz aparecer e sumir cada bolha um pouquinho por quadro.
func _animate(here: Vector2, delta: float) -> void:
	var glide := 1.0 - exp(-GLIDE * delta)
	var step := FADE_RATE * delta
	for i in PUFFS:
		var want := _wanted[i]
		if want == NONE and _ids[i] == NONE:
			continue
		if want != _ids[i] or (want != NONE and _alpha[i] > 0.0 and _pos[i].distance_to(_goal[i]) > JUMP):
			# Outra bolha (ou nenhuma) deve ocupar a vaga, ou o salto é grande:
			# some onde está e, apagada, muda de lugar.
			_alpha[i] = move_toward(_alpha[i], 0.0, step)
			if _alpha[i] <= 0.0:
				_ids[i] = want
				if want != NONE:
					_pos[i] = _goal[i]
				else:
					_hide(i)
					continue
		else:
			_pos[i] = _pos[i].lerp(_goal[i], glide)
			_alpha[i] = move_toward(_alpha[i], 1.0, step)
		var flat := Vector2(_pos[i].x, _pos[i].z).distance_to(here)
		var near := clampf((flat - NEAR_START) / (NEAR_FULL - NEAR_START), 0.0, 1.0)
		# Perto da criatura as bolhas encolhem, para não tapar a vista.
		# Perto, o quadrado vira para a câmera inclinado e entraria no chão:
		# sobe um pouco e fica mais achatado.
		var close := 1.0 - clampf(flat / 3.0, 0.0, 1.0)
		var size := _size[i] * lerpf(1.0, 0.6, close)
		var basis := Basis.IDENTITY.scaled(Vector3(size, size * lerpf(0.4, 0.3, close), 1.0))
		_multi.set_instance_transform(i, Transform3D(basis, _pos[i] + Vector3.UP * 0.15 * close))
		_multi.set_instance_color(i, Color(1, 1, 1, _alpha[i] * near * _far[i]))


## Quantos metros da rota ficaram para trás entre duas leituras: se o primeiro
## beacon novo é um dos antigos, soma os trechos passados; se a rota mudou
## (recalculada), recomeça do zero.
static func advance_base(old: Array[Vector2], new: Array[Vector2], base: float) -> float:
	if old.is_empty() or new.is_empty():
		return 0.0
	for j in old.size():
		if old[j].distance_to(new[0]) < 0.01:
			var passed := 0.0
			for k in j:
				passed += old[k].distance_to(old[k + 1])
			return base + passed
	return 0.0


## Onde ficam as bolhas: id -> ponto (metros). A bolha de id n fica a
## n * SPACING metros do começo da rota (que está `base` metros antes do
## primeiro beacon). Vão desde a criatura até REACH metros adiante.
static func puff_spots(here: Vector2, route: Array[Vector2], base: float) -> Dictionary:
	var spots := {}
	if route.is_empty():
		return spots
	var points: Array[Vector2] = [here]
	points.append_array(route)
	# Comprimento da rota no começo de cada trecho; o primeiro trecho (da
	# criatura ao beacon) termina em `base`.
	var at := base - here.distance_to(route[0])
	var start := at
	var first := ceili(start / SPACING - 0.001)
	var id := first
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		var length := a.distance_to(b)
		while length >= 0.01 and id * SPACING <= at + length and id * SPACING - start <= REACH and spots.size() < PUFFS:
			spots[id] = a.lerp(b, (id * SPACING - at) / length)
			id += 1
		at += length
		if spots.size() >= PUFFS or id * SPACING - start > REACH:
			break
	return spots


func _hide(index: int) -> void:
	_multi.set_instance_transform(index, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3(0, -100, 0)))
	_multi.set_instance_color(index, Color(1, 1, 1, 0))
