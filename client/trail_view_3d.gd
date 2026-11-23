class_name TrailView3D
extends Node3D
## O rastro do Caminheiro: uma névoa azulada que flutua baixa sobre o chão e
## traça a rota até o destino, a partir de onde a criatura está (como o feitiço
## de clarividência do Skyrim). Só visual: a rota vem do Caminheiro. Enquanto o
## cristal está apagado, não há nada.
##
## São poucas bolhas achatadas (um MultiMesh) que balançam devagar e somem na
## ponta de perto e na de longe.

const METERS := WorldGen.METERS_PER_CELL
const PUFFS := 64
const SPACING := 1.0  # metros entre bolhas
const REACH := PUFFS * SPACING  # até onde o rastro vai à frente
const HEIGHT := 0.4
const REFRESH := 0.2  # segundos entre os recálculos
const SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, skip_vertex_transform;
uniform vec4 tint : source_color = vec4(0.62, 0.8, 0.98, 0.8);
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
	ALBEDO = tint.rgb;
	ALPHA = tint.a * soft * swirl * COLOR.a;
}
"""

var _caminheiro: Caminheiro
var _multi: MultiMesh
var _clock := 0.0
var _last_pos := Vector2(1e9, 1e9)


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
	_hide_all()


## Chamado a cada quadro com a posição da criatura (em casas).
func follow(pos: Vector2, delta: float) -> void:
	_clock -= delta
	if _clock > 0.0:
		return
	_clock = REFRESH
	if _caminheiro == null or not _caminheiro.active:
		if _last_pos.x < 1e8:
			_hide_all()
			_last_pos = Vector2(1e9, 1e9)
		return
	_last_pos = pos
	var points: Array[Vector2] = [pos * METERS]
	for beacon: Vector2 in _caminheiro.route():
		points.append(beacon * METERS)
	_place(points)


## Bolhas de SPACING em SPACING metros ao longo da linha quebrada.
func _place(points: Array[Vector2]) -> void:
	var placed := 0
	var carry := SPACING * 0.5
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		var length := a.distance_to(b)
		if length < 0.01:
			continue
		var dir := (b - a) / length
		var at := carry
		while at < length and placed < PUFFS:
			var p := a + dir * at
			var travelled := placed * SPACING
			var fade := clampf((travelled - 1.5) / 3.0, 0.0, 1.0) * clampf((REACH - travelled) / 10.0, 0.0, 1.0)
			var side := Vector2(-dir.y, dir.x) * sin(placed * 1.3) * 0.25
			var y := WorldView3D.ground_height(p.x, p.y) + HEIGHT + 0.12 * sin(placed * 0.9)
			var size := 1.5 + 0.5 * sin(placed * 2.1)
			var basis := Basis.IDENTITY.scaled(Vector3(size, size * 0.4, 1.0))
			_multi.set_instance_transform(placed, Transform3D(basis, Vector3(p.x + side.x, y, p.y + side.y)))
			_multi.set_instance_color(placed, Color(1, 1, 1, fade))
			placed += 1
			at += SPACING
		carry = at - length
		if placed >= PUFFS:
			break
	for k in range(placed, PUFFS):
		_hide(k)


func _hide(index: int) -> void:
	_multi.set_instance_transform(index, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3(0, -100, 0)))
	_multi.set_instance_color(index, Color(1, 1, 1, 0))


func _hide_all() -> void:
	for i in PUFFS:
		_hide(i)
