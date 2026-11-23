class_name HorseModel
extends RefCounted
## O cavalinho-da-bruma em 3D: baixo, atarracado, de pelo grosso e crina
## desgrenhada. Montado com formas simples geradas por código (as "shapes" do
## WorldView3D), sem arquivos de modelo. O corpo todo é feito de peças em
## nós, e o movimento é só girar esses nós (barato para o FPS):
## pernas em duas juntas (coxa e canela, com casco), pescoço e cabeça que
## abaixam para pastar, orelhas, crina e cauda que balançam.
##
## O cavalo olha para -Z, como as outras criaturas do 3D.

const COAT_COLORS := [Color("7a4528"), Color("4a3a2c"), Color("1f1e22"), Color("a39a8c")]
const MANE_COLOR := Color("141316")
const HOOF_COLOR := Color("1b1a1c")
const MUZZLE_DARKEN := 0.55
const LEG_DARKEN := 0.7  # as canelas são mais escuras que o corpo
## Fase de cada perna (0 e 1 na frente, esquerda e direita; 2 e 3 atrás) em
## cada andar: no trote, as pernas em diagonal andam juntas; no galope, os
## pares da frente e de trás.
const PHASES_WALK := [0.0, PI, PI * 0.5, PI * 1.5]
const PHASES_TROT := [0.0, PI, PI, 0.0]
const PHASES_GALLOP := [0.0, 0.35, 2.6, 2.95]


## Monta o cavalo de uma pelagem (índice de Herd.COATS) com as formas dadas.
static func build(coat: int, shapes: Dictionary) -> Node3D:
	var base: Color = COAT_COLORS[clampi(coat, 0, COAT_COLORS.size() - 1)]
	var fur := _material(base)
	var dark := _material(base.darkened(MUZZLE_DARKEN))
	var legs := _material(base.darkened(1.0 - LEG_DARKEN))
	var mane := _material(MANE_COLOR)
	var hoof := _material(HOOF_COLOR)
	var root := Node3D.new()
	var trunk := Node3D.new()
	trunk.name = "Tronco"
	root.add_child(trunk)
	# Tronco: peito, barriga e garupa se juntam num barril.
	_piece(trunk, shapes["blob"], Vector3(0.0, 0.86, 0.0), Vector3(0.56, 0.54, 1.1), fur)
	_piece(trunk, shapes["blob"], Vector3(0.0, 0.88, -0.36), Vector3(0.62, 0.7, 0.56), fur)  # peito mais cheio
	_piece(trunk, shapes["blob"], Vector3(0.0, 0.9, 0.4), Vector3(0.52, 0.56, 0.5), fur)
	# Pescoço, com a crina em tufos, e a cabeça, que pivota no alto dele.
	var neck := Node3D.new()
	neck.name = "Pescoco"
	neck.position = Vector3(0.0, 1.05, -0.5)
	trunk.add_child(neck)
	# O pescoço afunila: grosso na base, fino perto da cabeça.
	var neck_base := _piece(neck, shapes["blob"], Vector3(0.0, 0.1, -0.04), Vector3(0.36, 0.42, 0.4), fur)
	neck_base.rotation.x = -0.35
	var neck_piece := _piece(neck, shapes["blob"], Vector3(0.0, 0.34, -0.15), Vector3(0.24, 0.42, 0.27), fur)
	neck_piece.rotation.x = -0.35
	for k in 6:
		var tuft := _piece(neck, shapes["box"], Vector3(0.0, 0.04 + 0.085 * k, 0.04 - 0.04 * k), Vector3(0.09, 0.18, 0.12), mane)
		tuft.rotation.x = -0.35
		tuft.rotation.z = 0.15 * sin(k * 2.3)
	var head := Node3D.new()
	head.name = "Cabeca"
	head.position = Vector3(0.0, 0.46, -0.3)
	neck.add_child(head)
	_piece(head, shapes["blob"], Vector3(0.0, 0.0, -0.18), Vector3(0.22, 0.24, 0.46), fur)
	_piece(head, shapes["blob"], Vector3(0.0, -0.07, -0.44), Vector3(0.16, 0.16, 0.2), dark)  # focinho
	_piece(head, shapes["box"], Vector3(0.0, 0.1, -0.08), Vector3(0.09, 0.07, 0.16), mane)  # topete
	for side in [-1, 1]:
		var ear := _piece(head, shapes["cone"], Vector3(side * 0.08, 0.17, -0.02), Vector3(0.09, 0.2, 0.09), fur)
		ear.name = "Orelha%d" % (0 if side < 0 else 1)
		ear.rotation.z = -side * 0.2
		_piece(head, shapes["blob"], Vector3(side * 0.115, 0.03, -0.2), Vector3(0.04, 0.04, 0.04), hoof)  # olho
	# Cauda: um tufo que pende da garupa.
	var tail := Node3D.new()
	tail.name = "Cauda"
	tail.position = Vector3(0.0, 1.05, 0.62)
	trunk.add_child(tail)
	var tail_piece := _piece(tail, shapes["cone"], Vector3(0.0, -0.3, 0.09), Vector3(0.15, 0.6, 0.15), mane)
	tail_piece.rotation.x = PI + 0.15  # o cone é largo embaixo: vira para ficar largo no alto e afinar para baixo
	var tail_tuft := _piece(tail, shapes["blob"], Vector3(0.0, -0.58, 0.13), Vector3(0.12, 0.22, 0.12), mane)
	tail_tuft.rotation.x = 0.15
	# Pernas: coxa (que pivota no quadril) e canela (que pivota no joelho), com casco.
	for i in 4:
		var hip := Node3D.new()
		hip.name = "Perna%d" % i
		hip.position = Vector3(0.18 * (-1 if i % 2 == 0 else 1), 0.7, -0.4 if i < 2 else 0.4)
		root.add_child(hip)
		_piece(hip, shapes["trunk"], Vector3(0.0, -0.17, 0.0), Vector3(0.7, 0.36, 0.7), fur)
		var knee := Node3D.new()
		knee.name = "Joelho%d" % i
		knee.position = Vector3(0.0, -0.34, 0.0)
		hip.add_child(knee)
		# Joelho (na frente) ou jarrete (atrás, com ponta para trás) marcado.
		var joint := _piece(knee, shapes["blob"], Vector3(0.0, 0.0, 0.03 if i >= 2 else -0.01), Vector3(0.13, 0.13, 0.15), fur)
		if i >= 2:
			joint.scale = Vector3(0.12, 0.17, 0.17)
		_piece(knee, shapes["box"], Vector3(0.0, -0.11, 0.0), Vector3(0.075, 0.2, 0.075), legs)
		_piece(knee, shapes["blob"], Vector3(0.0, -0.24, 0.015), Vector3(0.09, 0.09, 0.1), legs)  # boleto
		_piece(knee, shapes["box"], Vector3(0.0, -0.3, 0.0), Vector3(0.12, 0.07, 0.13), hoof)
	return root


## Um casco tocou: puxa a fase para o ponto em que uma perna encosta no chão
## (no passo, a cada quarto de ciclo; no trote, a cada meio; no galope, uma
## vez por passada), suavemente.
static func footfall(root: Node3D, gait: int) -> void:
	if not root.has_meta("fase"):
		return
	var phase: float = root.get_meta("fase")
	var grid := 0.25
	var offset := 0.0
	if gait == Herd.Gait.TROT:
		grid = 0.5
		offset = 0.25
	elif gait == Herd.Gait.GALLOP:
		grid = 1.0
		offset = 0.22
	var target := roundf((phase - offset) / grid) * grid + offset
	root.set_meta("fase", phase + (target - phase) * 0.5)


## Move as peças de um cavalo montado por build(). "phase" é o relógio do passo
## (em ciclos), "gait" é Herd.Gait, "amount" a energia do movimento (0 parado).
## "turn_hint" (-1 a 1) é o giro que o cavaleiro pediu: o pescoço e o corpo entortam para o lado.
static func animate(root: Node3D, gait: int, phase: float, time: float, id: int, delta: float, turn_hint := 0.0, chilled := false, skid := 0.0) -> void:
	var moving := gait != Herd.Gait.STAND
	var phases: Array = PHASES_GALLOP if gait == Herd.Gait.GALLOP else (PHASES_TROT if gait == Herd.Gait.TROT else PHASES_WALK)
	var swing := 0.62 if gait == Herd.Gait.GALLOP else (0.45 if gait == Herd.Gait.TROT else 0.32)
	for i in 4:
		var hip: Node3D = root.get_node("Perna%d" % i)
		var knee: Node3D = hip.get_node("Joelho%d" % i)
		var angle: float = phase * TAU + phases[i]
		var forward := sin(angle) * swing if moving else 0.0
		hip.rotation.x = lerpf(hip.rotation.x, forward, minf(1.0, delta * 25.0))
		# O joelho dobra para trás quando a perna sobe, e fica reto no apoio.
		var bend := -maxf(0.0, sin(angle + 1.2)) * swing * 1.4 if moving else 0.0
		knee.rotation.x = lerpf(knee.rotation.x, bend, minf(1.0, delta * 25.0))
	var trunk: Node3D = root.get_node("Tronco")
	# Respira parado; no passo, o tronco sobe e desce duas vezes por ciclo.
	var bounce := (0.035 if gait == Herd.Gait.GALLOP else 0.02) * sin(phase * TAU * 2.0) if moving else 0.012 * sin(time * 1.7 + id)
	trunk.position.y = lerpf(trunk.position.y, bounce, minf(1.0, delta * 20.0))
	var neck: Node3D = trunk.get_node("Pescoco")
	var head: Node3D = neck.get_node("Cabeca")
	# De cabeça baixa pastando, quando parado; erguida e balançando ao andar.
	var neck_goal := -0.95 if not moving else (0.05 + 0.05 * sin(phase * TAU * 2.0))
	neck.rotation.x = lerpf(neck.rotation.x, neck_goal, minf(1.0, delta * 2.5))
	# Derrapando: cabeça erguida, corpo jogado para trás. Com frio: treme e abaixa a cabeça.
	if skid > 0.0:
		neck.rotation.x = lerpf(neck.rotation.x, -0.35 * skid, minf(1.0, delta * 12.0))
		trunk.rotation.x = lerpf(trunk.rotation.x, 0.2 * skid, minf(1.0, delta * 10.0))
	else:
		trunk.rotation.x = lerpf(trunk.rotation.x, 0.0, minf(1.0, delta * 6.0))
	if chilled and gait == Herd.Gait.STAND:
		neck.rotation.x = lerpf(neck.rotation.x, -0.5, minf(1.0, delta * 3.0))
	var shiver := 0.025 if chilled else 0.0
	trunk.rotation.z += sin(time * 38.0 + id) * shiver
	# Pedido de giro: o pescoço e a cabeça apontam para o lado e o corpo se inclina.
	neck.rotation.y = lerpf(neck.rotation.y, -turn_hint * 0.55, minf(1.0, delta * 10.0))
	trunk.rotation.z = lerpf(trunk.rotation.z, -turn_hint * 0.08, minf(1.0, delta * 8.0))
	head.rotation.x = lerpf(head.rotation.x, 0.0 if moving else 0.4 + 0.05 * sin(time * 0.9 + id), minf(1.0, delta * 2.5))
	var tail: Node3D = trunk.get_node("Cauda")
	tail.rotation.z = sin(time * (3.0 if moving else 1.2) + id) * (0.25 if moving else 0.12)
	tail.rotation.x = -0.3 if gait == Herd.Gait.GALLOP else 0.0
	# As orelhas dão uma mexida de vez em quando.
	var twitch := maxf(0.0, sin(time * 0.7 + id * 3.1) - 0.85) * 4.0
	for e in 2:
		var ear: Node3D = head.get_node("Orelha%d" % e)
		ear.rotation.y = (e * 2 - 1) * twitch * 0.5


static func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	return material


static func _piece(parent: Node3D, mesh: Mesh, at: Vector3, scale_to: Vector3, material: Material) -> MeshInstance3D:
	var piece := MeshInstance3D.new()
	piece.mesh = mesh
	piece.material_override = material
	piece.position = at
	piece.scale = scale_to
	piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(piece)
	return piece
