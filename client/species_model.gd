class_name SpeciesModel
extends RefCounted
## Os oito híbridos jogáveis em 3D: corpo em pé, de gente, com cabeça e traços
## de bicho (orelhas, focinho, galhada, chifres, presas, cauda). Montados com as
## formas simples do WorldView3D, sem arquivos de modelo. O movimento é só girar
## nós (pernas, braços, cabeça, cauda), barato para o FPS.
##
## Cada espécie é uma receita em SPECS: cor do pelo, medidas do corpo e quais
## traços ela leva. O modelo olha para -Z, como as outras criaturas do 3D.

const SKIN := Color("b99a7c")
const DARK := Color("1d1b1c")
const BONE := Color("d8cdb4")

## fur: pelo; belly: cor do peito/focinho; w: largura do corpo; h: altura total
## (m); head: tamanho da cabeça; snout: comprimento do focinho; ears: "none",
## "short", "long", "tall"; extras: lista de traços.
const SPECS := {
	"urso": {"shoulder": 1.55, "waist": 1.5, "legs": 1.45, "arms": 1.25, "feet_w": 1.5, "trap": true, "fur": Color("4a3b2f"), "belly": Color("3a2e25"), "w": 1.3, "h": 1.62, "head": 0.9, "snout": 0.9, "ears": "round",
		"extras": ["casca", "cauda_curta"]},
	"boi": {"shoulder": 1.1, "waist": 1.15, "legs": 1.15, "arms": 1.15, "fur": Color("3b3532"), "belly": Color("2a2625"), "w": 1.25, "h": 1.8, "head": 1.0, "snout": 1.1, "ears": "side",
		"extras": ["chifres", "cauda_longa", "argola"]},
	"cervo": {"shoulder": 0.7, "waist": 0.7, "legs": 0.65, "arms": 0.65, "neck": 0.3, "neck_w": 0.6, "fur": Color("8a6a46"), "belly": Color("c9b48f"), "w": 0.8, "h": 1.95, "head": 0.8, "snout": 1.1, "ears": "side",
		"extras": ["galhada", "cauda_curta"]},
	"coelho": {"shoulder": 0.85, "waist": 0.95, "legs": 1.2, "arms": 0.75, "hips": 1.35, "feet_w": 1.3, "feet_l": 1.45, "round_feet": true, "neck_w": 0.7, "fur": Color("d6d0c4"), "belly": Color("efe9dc"), "w": 0.8, "h": 1.4, "head": 0.9, "snout": 0.6, "eye_patch": true, "ears": "tall",
		"extras": ["manchas", "cauda_pompom"]},
	"lobo": {"shoulder": 1.3, "waist": 0.7, "legs": 0.85, "arms": 1.0, "feet_l": 1.45, "trap": true, "fur": Color("767a80"), "belly": Color("c7c9cc"), "w": 1.0, "h": 1.88, "head": 0.9, "snout": 1.3, "ears": "tall_short",
		"extras": ["cauda_longa", "pontas"]},
	"raposa": {"meias": true, "shoulder": 0.95, "waist": 0.8, "legs": 0.8, "arms": 0.85, "fur": Color("9a4426"), "belly": Color("e6d3b5"), "w": 0.85, "h": 1.6, "head": 0.85, "snout": 1.3, "ears": "tall",
		"extras": ["cauda_cheia", "manchas"]},
	"onca": {"meias": true, "shoulder": 1.15, "waist": 0.8, "legs": 1.0, "arms": 1.05, "fur": Color("17161a"), "belly": Color("232126"), "w": 0.95, "h": 1.75, "head": 0.85, "snout": 0.8, "ears": "round",
		"extras": ["cauda_longa", "garras"]},
	"javali": {"shoulder": 1.1, "waist": 1.3, "legs": 1.15, "arms": 1.1, "fur": Color("2b2724"), "belly": Color("1f1c1b"), "w": 1.15, "h": 1.65, "head": 0.95, "snout": 1.2, "ears": "short",
		"extras": ["presas", "cauda_curta", "crina"]},
}


static func has_model(species_id: String) -> bool:
	return SPECS.has(species_id)


## Monta o modelo de uma espécie. Sem espécie conhecida, devolve o modelo do
## lobo (ninguém fica invisível).
static func build(species_id: String, shapes: Dictionary) -> Node3D:
	var spec: Dictionary = SPECS.get(species_id, SPECS["lobo"])
	var extras: Array = spec["extras"]
	var fur := _material(spec["fur"])
	var belly := _material(spec["belly"])
	var skin := _material(SKIN)
	var dark := _material(DARK)
	var bone := _material(BONE)
	var w: float = spec["w"]
	var scale_h: float = float(spec["h"]) / 1.75
	var shoulder: float = spec.get("shoulder", 1.0)
	var waist: float = spec.get("waist", 1.0)
	var leg_t: float = spec.get("legs", 1.0)
	var arm_t: float = spec.get("arms", 1.0)
	var neck_up: float = spec.get("neck", 0.0)
	var feet_w: float = spec.get("feet_w", 1.0)
	var feet_l: float = spec.get("feet_l", 1.0)
	var hips: float = spec.get("hips", 1.0)
	var neck_w: float = spec.get("neck_w", 1.0)
	var root := Node3D.new()
	var body := Node3D.new()  # tudo que balança junto: sobe e desce ao andar
	body.name = "Corpo"
	body.scale = Vector3(1.0, scale_h, 1.0)
	root.add_child(body)
	# Tronco: peito, barriga mais clara e quadris.
	# Peito e ombros (largos nos fortes, estreitos nos esguios), cintura e quadris.
	_piece(body, shapes["blob"], Vector3(0.0, 1.2, 0.0), Vector3(0.62 * w * shoulder, 0.48, 0.42 * w), fur)
	_piece(body, shapes["blob"], Vector3(0.0, 1.17, -0.1 * w), Vector3(0.44 * w * shoulder, 0.4, 0.22 * w), belly)
	_piece(body, shapes["blob"], Vector3(0.0, 0.97, 0.0), Vector3(0.42 * w * waist, 0.3, 0.34 * w * waist), fur)
	_piece(body, shapes["blob"], Vector3(0.0, 0.8, 0.02), Vector3(0.5 * w * (1.0 + (waist - 1.0) * 0.5) * hips, 0.3, 0.36 * w * hips), fur)
	_piece(body, shapes["blob"], Vector3(0.0, 1.44 + neck_up * 0.5, 0.0), Vector3(0.2 * neck_w, 0.2 + neck_up, 0.2 * neck_w), fur)  # pescoço
	if "casca" in extras:  # ombros de tronco do Troncudo
		for side in [-1, 1]:
			_piece(body, shapes["blob"], Vector3(side * 0.3 * w * shoulder, 1.34, 0.0), Vector3(0.26, 0.2, 0.3), _material(Color("5a4a39")))
	if "crina" in extras:  # cerdas ao longo das costas do Raizeiro
		for k in 4:
			var bristle := _piece(body, shapes["cone"], Vector3(0.0, 1.38 - 0.14 * k, 0.17 * w + 0.01 * k), Vector3(0.07, 0.14, 0.07), dark)
			bristle.rotation.x = 0.5
	if spec.get("trap", false):  # trapézio: liga a cabeça aos ombros
		_piece(body, shapes["blob"], Vector3(0.0, 1.42, 0.07), Vector3(0.5 * w * shoulder, 0.22, 0.34), fur)
	# Cabeça: pivota na base do pescoço.
	var head := Node3D.new()
	head.name = "Cabeca"
	head.position = Vector3(0.0, 1.46 + neck_up, -0.02)
	head.scale = Vector3.ONE * 1.4
	body.add_child(head)
	var hs: float = spec["head"]
	_piece(head, shapes["blob"], Vector3(0.0, 0.14, 0.0), Vector3(0.3, 0.3, 0.3) * hs, fur)
	var snout_len: float = 0.16 * float(spec["snout"])
	var snout := _piece(head, shapes["blob"], Vector3(0.0, 0.08, -0.14 - snout_len * 0.5) * 1.0, Vector3(0.16, 0.14, snout_len + 0.1) * hs, belly)
	snout.position *= hs
	var nose := _piece(head, shapes["blob"], Vector3(0.0, 0.1, (-0.19 - snout_len) * hs), Vector3(0.07, 0.06, 0.06), dark)
	nose.name = "Nariz"
	if spec.get("eye_patch", false):
		for side in [-1, 1]:
			_piece(head, shapes["blob"], Vector3(side * 0.1 * hs, 0.2, -0.1 * hs), Vector3(0.12, 0.1, 0.07), _material(Color("8a6a4a")))
	for side in [-1, 1]:  # olhos: um contorno claro e a íris, que na raposa brilha
		_piece(head, shapes["blob"], Vector3(side * 0.1 * hs, 0.2, -0.11 * hs), Vector3(0.075, 0.065, 0.06), bone)
		_piece(head, shapes["blob"], Vector3(side * 0.105 * hs, 0.2, -0.135 * hs), Vector3(0.045, 0.05, 0.03), _material(Color("e8b24a")) if "cauda_cheia" in extras else dark)
	_add_ears(head, shapes, spec["ears"], fur, belly, hs)
	if "chifres" in extras:
		for side in [-1, 1]:
			var horn := _piece(head, shapes["cone"], Vector3(side * 0.2 * hs, 0.3, -0.02), Vector3(0.08, 0.26, 0.08), _material(Color("2d2a2b")))
			horn.rotation.z = -side * 0.75
	if "argola" in extras:
		_piece(head, shapes["blob"], Vector3(0.0, 0.04, (-0.2 - snout_len) * hs), Vector3(0.09, 0.03, 0.09), bone)
	if "galhada" in extras:
		var moss := _material(Color("55603a"))
		var antler := _material(Color("4b3b2c"))
		for side in [-1, 1]:
			var beam := _piece(head, shapes["cone"], Vector3(side * 0.12, 0.4, 0.0), Vector3(0.05, 0.5, 0.05), antler)
			beam.rotation.z = -side * 0.35
			for k in 2:
				var tine := _piece(head, shapes["cone"], Vector3(side * (0.2 + 0.07 * k), 0.46 + 0.14 * k, -0.03), Vector3(0.04, 0.24, 0.04), antler)
				tine.rotation.z = -side * (0.7 + 0.2 * k)
			_piece(head, shapes["blob"], Vector3(side * 0.16, 0.5, 0.0), Vector3(0.12, 0.06, 0.1), moss)  # musgo
	if "presas" in extras:
		for side in [-1, 1]:
			var tusk := _piece(head, shapes["cone"], Vector3(side * 0.07, 0.06, (-0.3 - snout_len) * hs), Vector3(0.04, 0.14, 0.04), bone)
			tusk.rotation.z = side * 0.3
			tusk.rotation.x = -0.5
	if "manchas" in extras:
		var spot := _material(Color("8a6a4a") if "cauda_pompom" in extras else Color("5a5a5c"))
		_piece(head, shapes["blob"], Vector3(0.1 * hs, 0.26, 0.04), Vector3(0.1, 0.08, 0.1), spot)
	if "pontas" in extras:  # pontas brancas, como neve: ao redor do pescoço
		_piece(body, shapes["blob"], Vector3(0.0, 1.4, 0.0), Vector3(0.44 * w, 0.14, 0.34 * w), _material(Color("e6e8ea")))
	# Braços: pendem dos ombros, um pouco mais longos que os de gente, com
	# ombro e cotovelo marcados e mãos grandes. O ombro nasce na borda do peito
	# (meio enterrado nele, para não sobrar fresta), e o braço abre um pouco
	# para fora até a mão passar ao lado dos quadris sem atravessá-los.
	var chest_half := 0.31 * w * shoulder  # meia largura do peito (elipsoide)
	var arm_y := 1.32
	var chest_at_arm := chest_half * sqrt(1.0 - pow((arm_y - 1.2) / 0.24, 2.0))
	var arm_x := chest_at_arm + 0.02
	var waist_half := 0.21 * w * waist
	var hip_half := 0.25 * w * (1.0 + (waist - 1.0) * 0.5) * hips
	var spread := 0.06
	# Cotovelo (~0,38 m abaixo do ombro) passa a cintura; antebraço (~0,6 m) passa os quadris.
	spread = maxf(spread, asin(clampf((waist_half + 0.08 * arm_t - arm_x) / 0.38, -1.0, 1.0)))
	spread = maxf(spread, asin(clampf((hip_half + 0.07 * arm_t - arm_x) / 0.6, -1.0, 1.0)))
	for side in [-1, 1]:
		var arm := Node3D.new()
		arm.name = "Braco%d" % (0 if side < 0 else 1)
		arm.position = Vector3(side * arm_x, arm_y, 0.0)
		arm.rotation.z = side * spread
		body.add_child(arm)
		_piece(arm, shapes["blob"], Vector3(0.0, -0.01, 0.0), Vector3(0.26, 0.26, 0.24) * arm_t, fur)  # ombro
		var upper := _piece(arm, shapes["trunk"], Vector3(0.0, -0.2, 0.0), Vector3(0.62 * arm_t, 0.38, 0.62 * arm_t), fur)
		upper.rotation.x = PI  # grosso no ombro, afina até o cotovelo
		_piece(arm, shapes["blob"], Vector3(0.0, -0.38, -0.01), Vector3(0.17, 0.17, 0.17) * arm_t, fur)  # cotovelo
		var forearm := _piece(arm, shapes["trunk"], Vector3(0.0, -0.55, -0.05), Vector3(0.5 * arm_t, 0.38, 0.5 * arm_t), fur)
		forearm.rotation.x = PI + 0.28  # grosso no cotovelo, dobra um pouco para a frente
		_piece(arm, shapes["blob"], Vector3(0.0, -0.75, -0.1), Vector3(0.2, 0.2, 0.2), skin)  # palma
		_piece(arm, shapes["box"], Vector3(0.0, -0.84, -0.12), Vector3(0.2, 0.1, 0.14), dark)  # bloco dos dedos (ponta escura)
		if side == 0:  # tocha na mão esquerda (escondida até haver uma)
			var torch := Node3D.new()
			torch.name = "Tocha"
			torch.position = Vector3(0.0, -0.8, -0.12)
			torch.rotation.x = -0.5
			torch.visible = false
			arm.add_child(torch)
			_piece(torch, shapes["trunk"], Vector3(0.0, 0.0, 0.0), Vector3(0.09, 0.5, 0.09), _material(Color("5a4630")))
			var flame_material := StandardMaterial3D.new()
			flame_material.albedo_color = Color("ff9a2e")
			flame_material.emission_enabled = true
			flame_material.emission = Color("ff7a1a")
			flame_material.emission_energy_multiplier = 2.0
			var flame := _piece(torch, shapes["cone"], Vector3(0.0, 0.34, 0.0), Vector3(0.12, 0.26, 0.12), flame_material)
			flame.name = "Chama"
		if side == 1:  # ferramenta na mão direita (escondida até empunhar algo)
			var held := Node3D.new()
			held.name = "Ferramenta"
			held.position = Vector3(0.0, -0.8, -0.12)
			held.rotation.x = -0.4
			held.visible = false
			arm.add_child(held)
			var handle := _piece(held, shapes["trunk"], Vector3(0.0, -0.05, 0.0), Vector3(0.1, 0.55, 0.1), _material(Color("5a4630")))
			handle.name = "Cabo"
			var blade := _piece(held, shapes["box"], Vector3(0.0, -0.28, -0.08), Vector3(0.05, 0.16, 0.22), _material(Color("7b7f84")))
			blade.name = "Cabeca"
		if "garras" in extras:
			for k in 3:
				var claw := _piece(arm, shapes["cone"], Vector3((k - 1) * 0.045, -0.93, -0.13), Vector3(0.03, 0.12, 0.03), bone)
				claw.rotation.x = PI - 0.3
	# Pernas: coxa grossa, joelho marcado, panturrilha mais fina e pé grande.
	for side in [-1, 1]:
		var leg := Node3D.new()
		leg.name = "Perna%d" % (0 if side < 0 else 1)
		leg.position = Vector3(side * 0.17 * w, 0.76, 0.0)
		body.add_child(leg)
		_piece(leg, shapes["trunk"], Vector3(0.0, -0.17, 0.0), Vector3(0.95 * leg_t, 0.38, 0.95 * leg_t), fur)
		_piece(leg, shapes["blob"], Vector3(0.0, -0.36, -0.02), Vector3(0.24, 0.22, 0.26) * leg_t, fur)  # joelho
		_piece(leg, shapes["blob"], Vector3(0.0, -0.36, -0.02), Vector3(0.34, 0.07, 0.36) * leg_t, belly)  # anel do joelho
		var calf := _piece(leg, shapes["trunk"], Vector3(0.0, -0.52, 0.02), Vector3(0.75 * leg_t, 0.36, 0.75 * leg_t), dark if spec.get("meias", false) else fur)
		calf.rotation.x = 0.22  # quebra de ângulo no joelho
		if spec.get("round_feet", false):
			_piece(leg, shapes["blob"], Vector3(0.0, -0.66, -0.1), Vector3(0.22 * feet_w, 0.12, 0.4 * feet_l), dark)  # pata arredondada
		else:
			_piece(leg, shapes["box"], Vector3(0.0, -0.66, -0.07 - 0.03 * (feet_l - 1.0)), Vector3(0.2 * feet_w, 0.07, 0.36 * feet_l), fur)  # peito do pé
			_piece(leg, shapes["box"], Vector3(0.0, -0.705, -0.07 - 0.03 * (feet_l - 1.0)), Vector3(0.21 * feet_w, 0.04, 0.37 * feet_l), dark)  # sola escura
	# Cauda.
	var tail := Node3D.new()
	tail.name = "Cauda"
	tail.position = Vector3(0.0, 0.82, 0.16 * w)
	body.add_child(tail)
	var tail_color: Color = Color("efe9dc") if "cauda_pompom" in extras else spec["fur"]
	var tail_shape := "cone"
	var tail_scale := Vector3(0.1, 0.3, 0.1)
	if "cauda_longa" in extras:
		tail_scale = Vector3(0.09, 0.62, 0.09)
	elif "cauda_cheia" in extras:
		tail_scale = Vector3(0.24, 0.56, 0.24)
	elif "cauda_pompom" in extras:
		tail_shape = "blob"
		tail_scale = Vector3(0.14, 0.14, 0.14)
	var tail_piece := _piece(tail, shapes[tail_shape], Vector3(0.0, -0.1, 0.08), tail_scale, _material(tail_color))
	tail_piece.rotation.x = PI * 0.5 + 0.4 if tail_shape == "cone" else 0.0
	if "cauda_cheia" in extras:  # ponta branca da raposa
		_piece(tail, shapes["blob"], Vector3(0.0, -0.18, 0.42), Vector3(0.14, 0.14, 0.14), _material(Color("efe6d4")))
	return root


static func _add_ears(head: Node3D, shapes: Dictionary, kind: String, fur: Material, inner: Material, hs: float) -> void:
	for side in [-1, 1]:
		var ear: MeshInstance3D
		match kind:
			"tall":
				ear = _piece(head, shapes["cone"], Vector3(side * 0.1 * hs, 0.42, 0.04), Vector3(0.09, 0.42, 0.07), fur)
				ear.rotation.z = -side * 0.12
			"tall_short":
				ear = _piece(head, shapes["cone"], Vector3(side * 0.1 * hs, 0.34, 0.04), Vector3(0.1, 0.22, 0.07), fur)
			"short":
				ear = _piece(head, shapes["cone"], Vector3(side * 0.14 * hs, 0.28, 0.06), Vector3(0.08, 0.14, 0.06), fur)
				ear.rotation.z = -side * 0.5
			"side":
				ear = _piece(head, shapes["blob"], Vector3(side * 0.2 * hs, 0.2, 0.06), Vector3(0.18, 0.07, 0.1), fur)
				ear.rotation.z = -side * 0.35
			_:  # redondas
				ear = _piece(head, shapes["blob"], Vector3(side * 0.12 * hs, 0.3, 0.02), Vector3(0.1, 0.1, 0.06), fur)
		ear.name = "Orelha%d" % (0 if side < 0 else 1)
		if kind in ["tall", "tall_short", "side"]:  # interior mais claro
			var inner_piece := MeshInstance3D.new()
			inner_piece.mesh = ear.mesh
			inner_piece.material_override = inner
			inner_piece.position = Vector3(0.0, -0.02, -0.4 if kind != "side" else -0.5)
			inner_piece.scale = Vector3(0.6, 0.85, 0.5)
			inner_piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ear.add_child(inner_piece)


## Quanto o corpo sobe ao montar: os quadris (a ~1,14 m com a subida antiga
## de 0,34 m) vão até o lombo do cavalo.
static func mount_lift() -> float:
	return 0.34 + HorseModel.BACK_HEIGHT - 1.13


## Duração de cada ação pontual (segundos). Cada evento (um golpe, um trabalho na obra) toca uma vez.
const ACTIONS := {
	"golpe": 0.45, "comer": 1.3, "coleta": 0.9, "obra": 1.2, "salto": 0.6, "uivo": 1.8,
	"disparada": 3.0, "fucar": 2.0, "arar": 2.0, "pesca": 2.0,
}


## Dispara uma ação pontual (golpe, coleta, habilidade...). Ver ACTIONS.
static func play(root: Node3D, action: String) -> void:
	if ACTIONS.has(action):
		root.set_meta("acao", action)
		root.set_meta("acao_t", 0.0)


## O som de um passo tocou: puxa a fase da perna para o ponto em que o pé
## encosta no chão (perna toda para a frente ou toda para trás, a cada meio
## ciclo), suavemente, para o pé e o som caírem juntos.
static func footfall(root: Node3D) -> void:
	if not root.has_meta("fase"):
		return
	var phase: float = root.get_meta("fase")
	var target := roundf((phase - 0.25) * 2.0) / 2.0 + 0.25
	root.set_meta("fase", phase + (target - phase) * 0.6)


## A tocha na mão esquerda: "held" se há uma, "lit" se está acesa (apagada, só o cabo).
static func set_torch(root: Node3D, held: bool, lit: bool) -> void:
	var torch := root.get_node_or_null("Corpo/Braco0/Tocha")
	if torch == null:
		return
	torch.visible = held
	torch.get_node("Chama").visible = lit


## O que está na mão direita: "machado", "enxada", "faca", ou "" (nada).
static func set_wield(root: Node3D, item: String) -> void:
	var tool_node := root.get_node_or_null("Corpo/Braco1/Ferramenta")
	if tool_node == null:
		return
	tool_node.visible = item in ["machado", "enxada", "faca"]
	if not tool_node.visible:
		return
	var long_handle := item != "faca"
	tool_node.get_node("Cabo").scale = Vector3(0.1, 0.55 if long_handle else 0.25, 0.1)
	tool_node.get_node("Cabo").position = Vector3(0.0, -0.05, 0.0)
	var head: Node3D = tool_node.get_node("Cabeca")
	head.position = Vector3(0.0, -0.28 if long_handle else -0.12, -0.08 if item == "machado" else 0.0)
	head.scale = {"machado": Vector3(0.05, 0.16, 0.22), "enxada": Vector3(0.05, 0.1, 0.22), "faca": Vector3(0.03, 0.14, 0.05)}[item]


## Anima o modelo. "speed" é a velocidade em casas por segundo (0 parado);
## "motion" (x lado, y frente, com sinal) dá a direção do passo: de costas as
## pernas invertem, de lado elas abrem e fecham; "turn" (rad/s) faz o corpo
## arrastar os pés ao girar parado; "load" é a carga (0 a 1,5 da carga plena,
## curva o corpo); "mounted" senta o personagem. Mantém o relógio de passo e
## o da ação no próprio nó.
static func animate(root: Node3D, speed: float, time: float, id: int, delta: float,
		motion := Vector2.ZERO, turn := 0.0, load := 0.0, mounted := false) -> void:
	var step_speed := speed
	var shuffle := false
	if speed <= 0.15 and absf(turn) > 0.5 and not mounted:
		step_speed = 0.9
		shuffle = true
	var moving := step_speed > 0.15 and not mounted
	var backwards := motion.y < -absf(motion.x) * 0.8 and motion != Vector2.ZERO
	var sideways := absf(motion.x) > absf(motion.y) * 0.8 and motion != Vector2.ZERO
	var phase: float = root.get_meta("fase", float(id) * 0.37)
	if moving:
		# Mesma cadência do som dos passos (game.gd: 3,3 passos por segundo a 1,8
		# casas por segundo, de 0,3x a 2x): dois passos por ciclo de perna.
		phase += delta * 1.65 * clampf(step_speed / 1.8, 0.3, 2.0) * (-1.0 if backwards else 1.0)
		root.set_meta("fase", phase)
	var body: Node3D = root.get_node("Corpo")
	var head: Node3D = body.get_node("Cabeca")
	var swing := clampf(step_speed * 0.28, 0.0, 0.7) if moving else 0.0
	if shuffle:
		swing = 0.18
	var k := minf(1.0, delta * 14.0)
	var arms: Array[Node3D] = []
	var legs: Array[Node3D] = []
	for side in 2:
		var sign_ := 1.0 if side == 0 else -1.0
		var leg: Node3D = body.get_node("Perna%d" % side)
		var arm: Node3D = body.get_node("Braco%d" % side)
		legs.append(leg)
		arms.append(arm)
		var leg_x := sin(phase * TAU) * swing * sign_
		var leg_z := 0.0
		var arm_x := -sin(phase * TAU) * swing * 0.8 * sign_
		if sideways and moving:  # passo de lado: as pernas abrem e fecham
			leg_z = absf(sin(phase * TAU + (0.0 if side == 0 else PI * 0.5))) * 0.35 * (1.0 if side == 0 else -1.0) * signf(motion.x) * -1.0
			leg_x *= 0.3
			arm_x *= 0.3
		if mounted:  # sentado: coxas para a frente, abertas em volta do lombo, mãos na rédea
			leg_x = 0.75
			leg_z = -0.55 * sign_
			arm_x = 0.75
		leg.rotation.x = lerpf(leg.rotation.x, leg_x, k)
		leg.rotation.z = lerpf(leg.rotation.z, leg_z, k)
		arm.rotation.x = lerpf(arm.rotation.x, arm_x, k)
	var bob := absf(sin(phase * TAU)) * 0.05 * (swing / 0.3) if moving else 0.012 * sin(time * 1.6 + id)
	var lift := mount_lift() if mounted else 0.0
	# O corpo guarda o seu valor-base (sem a ação por cima), para a ação não se acumular.
	var base_y := lerpf(float(root.get_meta("base_y", 0.0)), bob + lift, minf(1.0, delta * 12.0))
	root.set_meta("base_y", base_y)
	body.position.y = base_y
	# Curva-se sob a carga (até um pouco além da carga plena).
	var lean := -clampf(load, 0.0, 1.5) * 0.14
	if moving and absf(motion.y) > 0.0 and not backwards:
		lean -= clampf(step_speed * 0.02, 0.0, 0.08)
	var base_x := lerpf(float(root.get_meta("base_x", 0.0)), lean, minf(1.0, delta * 6.0))
	root.set_meta("base_x", base_x)
	body.rotation.x = base_x
	# Montado, o cavaleiro se inclina para o lado do giro.
	var lean_z := clampf(-turn * 0.12, -0.25, 0.25) if mounted else 0.0
	body.rotation.z = lerpf(body.rotation.z, lean_z, minf(1.0, delta * 8.0))
	head.rotation.y = sin(time * 0.5 + id) * 0.25 if not moving else 0.0
	head.rotation.x = 0.0 if moving else 0.06 * sin(time * 0.9 + id)
	var tail: Node3D = body.get_node("Cauda")
	tail.rotation.z = sin(time * (4.0 if moving else 1.3) + id) * (0.35 if moving else 0.15)
	var twitch := maxf(0.0, sin(time * 0.7 + id * 3.1) - 0.88) * 4.0
	for e in 2:
		var ear: Node3D = head.get_node("Orelha%d" % e)
		ear.rotation.y = (e * 2 - 1) * twitch * 0.4
	var flame := body.get_node_or_null("Braco0/Tocha/Chama")
	if flame != null and flame.visible:  # a chama tremula
		flame.scale = Vector3(0.12, 0.26 * (1.0 + 0.15 * sin(time * 17.0 + id) + 0.08 * sin(time * 31.0)), 0.12)
	_apply_action(root, body, head, arms, legs, delta)


## A ação pontual por cima do andar: braços, agachar, salto, uivo.
static func _apply_action(root: Node3D, body: Node3D, head: Node3D, arms: Array[Node3D], legs: Array[Node3D], delta: float) -> void:
	var action: String = root.get_meta("acao", "")
	if action.is_empty():
		return
	var t: float = float(root.get_meta("acao_t", 0.0)) + delta
	var duration: float = ACTIONS[action]
	if t >= duration:
		root.set_meta("acao", "")
		return
	root.set_meta("acao_t", t)
	var u := t / duration
	var w := sin(clampf(u, 0.0, 1.0) * PI)  # entra e sai suave
	match action:
		"golpe":  # braço direito sobe e desce, com um passo de tronco
			var raise := smoothstep(0.0, 0.3, u)
			var drop := smoothstep(0.3, 0.65, u)
			arms[1].rotation.x = -2.3 * raise + 2.7 * drop
			body.rotation.x += -0.2 * w
		"comer":  # leva a mão à boca duas vezes, mastigando
			arms[1].rotation.x = (-2.0 + 0.25 * sin(t * 14.0)) * w
			head.rotation.x = (0.15 + 0.1 * sin(t * 14.0)) * w
		"coleta":  # agacha e estica as mãos
			body.position.y -= 0.32 * w
			for arm in arms:
				arm.rotation.x = -0.9 * w
			head.rotation.x = 0.35 * w
			for leg in legs:
				leg.rotation.x = -0.7 * w
		"pesca":
			body.position.y -= 0.3 * w
			arms[0].rotation.x = -0.8 * w + sin(t * 9.0) * 0.25 * w
			arms[1].rotation.x = -0.8 * w - sin(t * 9.0) * 0.25 * w
			head.rotation.x = 0.4 * w
			for leg in legs:
				leg.rotation.x = -0.6 * w
		"fucar", "arar":  # agachado, braços cavando
			body.position.y -= 0.3 * w
			body.rotation.x -= 0.25 * w
			arms[0].rotation.x = -0.9 * w + sin(t * 14.0) * 0.5 * w
			arms[1].rotation.x = -0.9 * w - sin(t * 14.0) * 0.5 * w
			head.rotation.x = 0.3 * w
			for leg in legs:
				leg.rotation.x = -0.7 * w
		"obra":  # martelando, os braços alternam
			body.rotation.x -= 0.1
			arms[0].rotation.x = -1.2 + sin(u * TAU * 2.0) * 0.7
			arms[1].rotation.x = -1.2 - sin(u * TAU * 2.0) * 0.7
		"salto":
			body.position.y += 0.55 * sin(clampf(u, 0.0, 1.0) * PI)
			for leg in legs:
				leg.rotation.x = -0.6 * w
			for arm in arms:
				arm.rotation.x = -0.9 * w
		"uivo":  # cabeça para trás, peito aberto
			head.rotation.x = -0.9 * w
			body.rotation.x += 0.12 * w
			for arm in arms:
				arm.rotation.x = 0.35 * w
		"disparada":  # corpo inclinado para a frente
			body.rotation.x -= 0.3 * w
			for arm in arms:
				arm.rotation.x -= 0.4 * w


static func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	return material


static func _piece(parent: Node3D, mesh: Mesh, at: Vector3, scale_to: Vector3, material: Material) -> MeshInstance3D:
	return HorseModel._piece(parent, mesh, at, scale_to, material)
