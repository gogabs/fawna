class_name Crafting
extends RefCounted
## Receitas de fabricação: construções (feitas no mundo, em etapas) e armas
## (feitas na hora, a partir da bolsa). Fica em shared/ porque servidor e
## clientes usam as mesmas regras; quem decide é o servidor (WorldState).
##
## Construção: começa vazia num lugar à frente da criatura e passa por
## etapas. Em cada etapa, primeiro entram os materiais (Espaço perto da obra
## deposita o que a bolsa tiver do que falta) e depois o trabalho (cada
## Espaço é uma batida, até completar a etapa). Qualquer criatura pode
## ajudar em qualquer obra.
##
## Os materiais usam os subtipos da bolsa: pedra_grande, pedra_media,
## pedra_pequena, lenha_media, lenha_pequena (lenha_grande só vem das
## árvores, junto com a madeira).

## Nome falado de cada material: [singular, plural].
const MATERIAL_NAMES := {
	"pedra_grande": ["pedra grande", "pedras grandes"],
	"pedra_media": ["pedra média", "pedras médias"],
	"pedra_pequena": ["pedra pequena", "pedras pequenas"],
	"lenha_grande": ["lenha grande", "lenhas grandes"],
	"lenha_media": ["lenha média", "lenhas médias"],
	"lenha_pequena": ["lenha pequena", "lenhas pequenas"],
	"bambu": ["bambu", "bambus"],
	"madeira": ["madeira", "madeiras"],
	"argila": ["argila", "argilas"],
	"frutas": ["fruta", "frutas"],
	"silex": ["sílex", "sílex"],
	"cipo": ["cipó", "cipós"],
	"fibra": ["fibra vegetal", "fibras vegetais"],
	"resina": ["resina", "resinas"],
}

## Construções. Cada etapa: "name" (falado), "materials" (item -> quantidade)
## e "work" (batidas depois que os materiais entram).
##   name: [singular, plural]; article: "o"/"a" (para "o marco", "a fogueira");
##   one_per_region: só uma por região (o marco marca a região como um local);
##   fire: pode ser acesa depois de pronta.
const BUILDS := {
	"marco": {
		"name": ["marco", "marcos"],
		"article": "o",
		"one_per_region": true,
		"stages": [
			{"name": "a base", "materials": {"pedra_grande": 3}, "work": 3},
			{"name": "o corpo", "materials": {"pedra_media": 2}, "work": 2},
			{"name": "o topo", "materials": {"pedra_pequena": 1}, "work": 1},
		],
	},
	"fogueira": {
		"name": ["fogueira", "fogueiras"],
		"article": "a",
		"fire": true,
		"stages": [
			{"name": "o anel de pedras", "materials": {"pedra_media": 4, "pedra_pequena": 4}, "work": 3},
			{"name": "a lenha", "materials": {"lenha_media": 2, "lenha_pequena": 3, "silex": 1}, "work": 2},
		],
	},
	"abrigo": {
		"name": ["abrigo", "abrigos"],
		"article": "o",
		"settlement": true,
		"size": {"min": 3, "max": 6, "default": 4, "reference": 4},
		"stages": [
			{"name": "o chão", "materials": {"pedra_grande": 6, "argila": 8}, "work": 10, "dry": 240.0},
			{"name": "os esteios", "materials": {"madeira": 6}, "work": 12},
			{"name": "as paredes", "materials": {"bambu": 16, "argila": 8}, "work": 16, "walls": true},
			{"name": "o telhado", "materials": {"bambu": 12, "lenha_media": 6}, "work": 12},
		],
	},
	# Barracão com porta e dois móveis dentro (Builds.furniture_cells): a bancada,
	# à esquerda de quem entra, onde se fazem as receitas de WORKSHOP; e as
	# prateleiras, à direita, onde se guardam ferramentas e armas. Os móveis pedem
	# um lado de pelo menos 5 casas, para caberem os dois ao lado da porta.
	"oficina": {
		"name": ["oficina", "oficinas"],
		"article": "a",
		"settlement": true,
		"furniture": true,
		"size": {"min": 5, "max": 8, "default": 5, "reference": 5},
		"stages": [
			{"name": "o chão", "materials": {"pedra_grande": 6, "argila": 8}, "work": 10, "dry": 240.0},
			{"name": "os esteios", "materials": {"madeira": 6}, "work": 12},
			{"name": "as paredes", "materials": {"bambu": 16, "argila": 8}, "work": 16, "walls": true},
			{"name": "o telhado", "materials": {"bambu": 12, "lenha_media": 6}, "work": 12},
			{"name": "a bancada e as prateleiras", "materials": {"madeira": 4, "bambu": 6, "pedra_media": 2}, "work": 8},
		],
	},
	"armazem": {
		"name": ["armazém", "armazéns"],
		"article": "o",
		"settlement": true,
		"size": {"min": 3, "max": 6, "default": 4, "reference": 4},
		"stages": [
			{"name": "o chão", "materials": {"pedra_grande": 4, "argila": 6}, "work": 8, "dry": 240.0},
			{"name": "os esteios", "materials": {"madeira": 6}, "work": 10},
			{"name": "as paredes", "materials": {"bambu": 14, "argila": 6}, "work": 14, "walls": true},
			{"name": "o telhado", "materials": {"bambu": 10, "lenha_media": 4}, "work": 10},
		],
	},
}

## Ordem em que as construções aparecem no menu.
const BUILD_ORDER := ["marco", "fogueira", "abrigo", "armazem", "oficina"]

## Armazenamento: construções grandes prontas guardam itens, cada uma só de
## certas categorias (Bag.CATEGORIES). "per_cell" é o peso que cabe por casa do
## terreno (um 4 por 4 com 8 guarda 128, o tamanho 6 por 6 guarda 288). Para
## uma oficina guardar ferramentas, basta acrescentá-la aqui.
const STORAGE := {
	"armazem": {"accepts": ["material"], "per_cell": 8, "label": "materiais"},
	"abrigo": {"accepts": ["roupa"], "per_cell": 4, "label": "roupas"},
	"oficina": {"accepts": ["ferramenta", "arma"], "per_cell": 2, "label": "ferramentas e armas"},
}

## Construções grandes (as de BUILDS com "size"): ocupam um quadrado de lados
## "size" (em casas) em vez de uma casa só. O lugar é escolhido por âncoras
## (SitePlanner), só dentro de um povoado (um marco com nome na região), e a
## obra começa por duas fases de preparo antes das etapas: limpar (arrancar
## árvores, bambus e arbustos do terreno, com o machado) e capinar (arrancar a
## grama de cada casa, com a enxada). As etapas e o trabalho valem para o
## tamanho de referência ("reference"); em outros tamanhos, materiais e batidas
## crescem ou diminuem com a área (stage_of).
##
## Golpes de machado (limpar) para arrancar o que está no terreno de uma obra
## grande, e de enxada (capinar) para a grama de cada casa. A árvore pede bem
## mais que numa queda comum.
const CLEAR_HITS := {
	WorldGen.Thing.ARVORE: 10,
	WorldGen.Thing.BAMBU: 4,
	WorldGen.Thing.ARBUSTO: 3,
	WorldGen.Thing.ARBUSTO_FRUTAS: 3,
}
const WEED_HITS := 2
## Ferramenta de cada fase de preparo.
const PREP_TOOLS := {"limpeza": "machado", "capina": "enxada"}

## Fogo: batidas até acender (a primeira vez usa o sílex da obra; reacender gasta 1 sílex da bolsa), quanto cada lenha queima e o máximo
## que a fogueira guarda. A lenha da última etapa da fogueira já é o
## primeiro combustível.
const SPARKS_TO_LIGHT := 4
const FUEL_SECONDS := {"lenha_pequena": 180.0, "lenha_media": 420.0, "lenha_grande": 900.0}
const MAX_FUEL := 3600.0
## Ao alimentar, gasta primeiro a lenha que queima mais.
const FUEL_ORDER := ["lenha_grande", "lenha_media", "lenha_pequena"]

## Armas: feitas na hora com o que está na bolsa. Vão para a bolsa e podem
## ser empunhadas (Bag.WIELDABLE).
const WEAPONS := {
	"lanca": {"name": ["lança de bambu", "lanças de bambu"], "article": "a",
		"materials": {"bambu": 1, "silex": 1}},
	"clava": {"name": ["clava de pedra", "clavas de pedra"], "article": "a",
		"materials": {"lenha_media": 1, "pedra_media": 1}},
}
const WEAPON_ORDER := ["lanca", "clava"]

## Ferramentas: também fabricadas da bolsa, mas dão trabalho: "steps" são os
## passos que a criatura vê e ouve ao fabricar (cada um com suas batidas).
const TOOLS := {
	"enxada": {"name": ["enxada", "enxadas"], "article": "a",
		"materials": {"bambu": 1, "pedra_media": 1, "pedra_pequena": 1},
		"steps": [
			{"say": "Você fura a pedra com a pedra pequena.", "knocks": 7, "sound": "pedra"},
			{"say": "Você afeiçoa o cabo de bambu.", "knocks": 5, "sound": "madeira"},
			{"say": "Você encaixa o cabo na pedra furada.", "knocks": 3, "sound": "encaixe"},
		]},
	# Dois sílex: um vira a lâmina, o outro se perde nas lascas.
	"faca": {"name": ["faca bruta de sílex", "facas brutas de sílex"], "article": "a",
		"materials": {"silex": 2, "lenha_pequena": 1},
		"steps": [
			{"say": "Você lasca o sílex contra a pedra, até sair um fio.", "knocks": 6, "sound": "pedra"},
			{"say": "Você afeiçoa o cabo de lenha.", "knocks": 3, "sound": "madeira"},
			{"say": "Você prende a lâmina no cabo.", "knocks": 2, "sound": "encaixe"},
		]},
}
const TOOL_ORDER := ["enxada", "faca"]

## Receitas da bancada da oficina (ainda sem o menu da bancada: quem faz a
## oficina liga aqui). Mesmo formato das ferramentas; Crafting.recipe as acha.
const WORKSHOP := {
	"tocha": {"name": ["tocha", "tochas"], "article": "a",
		"materials": {"lenha_media": 1, "resina": 2, "fibra": 2, "cipo": 1},
		"steps": [
			{"say": "Você enrola a fibra na ponta da lenha.", "knocks": 4, "sound": "madeira"},
			{"say": "Você amarra tudo com o cipó.", "knocks": 2, "sound": "encaixe"},
			{"say": "Você embebe a ponta na resina.", "knocks": 3, "sound": "encaixe"},
		]},
}
const WORKSHOP_ORDER := ["tocha"]


static func material_text(item: String, amount: int) -> String:
	var names: Array = MATERIAL_NAMES.get(item, Bag.NAMES.get(item, [item, item]))
	return "%d %s" % [amount, names[0] if amount == 1 else names[1]]


## {"pedra_grande": 3, "pedra_media": 1} -> "3 pedras grandes e 1 pedra média".
## Segue a ordem de MATERIAL_NAMES, para soar sempre igual.
static func materials_text(materials: Dictionary) -> String:
	var parts: PackedStringArray = []
	for item: String in MATERIAL_NAMES:
		if int(materials.get(item, 0)) > 0:
			parts.append(material_text(item, int(materials[item])))
	for item: String in materials:
		if not MATERIAL_NAMES.has(item) and int(materials[item]) > 0:
			parts.append(material_text(item, int(materials[item])))
	if parts.is_empty():
		return "nada"
	if parts.size() == 1:
		return parts[0]
	return ", ".join(parts.slice(0, -1)) + " e " + parts[-1]


## "falta 1 pedra pequena" ou "faltam 3 pedras grandes e 1 pedra média".
static func missing_text(missing: Dictionary) -> String:
	var single := missing.size() == 1 and int(missing.values()[0]) == 1
	return ("falta " if single else "faltam ") + materials_text(missing)


static func is_large(kind: String) -> bool:
	return BUILDS.has(kind) and BUILDS[kind].has("size")


## A etapa "index" de uma construção para o tamanho "size" (1 nas pequenas).
## Nas grandes, materiais e batidas acompanham a área em relação ao tamanho de
## referência.
static func stage_of(kind: String, index: int, size := 1) -> Dictionary:
	var stage: Dictionary = BUILDS[kind]["stages"][index]
	if not is_large(kind):
		return stage
	var factor := float(size * size) / float(int(BUILDS[kind]["size"]["reference"]) ** 2)
	var materials := {}
	for item: String in stage["materials"]:
		materials[item] = maxi(1, ceili(float(stage["materials"][item]) * factor - 0.001))
	return {"name": stage["name"], "materials": materials, "work": maxi(1, roundi(float(stage["work"]) * factor))}


## As paredes de uma construção grande ficam de pé quando termina a etapa
## marcada com "walls" (ou quando a obra termina); antes disso o terreno é
## só um canteiro por onde se anda. Sem etapa marcada, nunca bloqueiam.
static func walls_stage(kind: String) -> int:
	var stages: Array = BUILDS[kind]["stages"]
	for i in stages.size():
		if stages[i].get("walls", false):
			return i
	return -1


static func stage_count(kind: String) -> int:
	return BUILDS[kind]["stages"].size()


static func build_name(kind: String) -> String:
	return BUILDS[kind]["name"][0] if BUILDS.has(kind) else kind


static func build_title(kind: String) -> String:
	var text := build_name(kind)
	return text.left(1).to_upper() + text.substr(1)


static func weapon_name(kind: String) -> String:
	if TOOLS.has(kind):
		return TOOLS[kind]["name"][0]
	if WORKSHOP.has(kind):
		return WORKSHOP[kind]["name"][0]
	return WEAPONS[kind]["name"][0] if WEAPONS.has(kind) else kind


## Receita de uma arma ou ferramenta ({} se não existe).
static func recipe(kind: String) -> Dictionary:
	if WEAPONS.has(kind):
		return WEAPONS[kind]
	if WORKSHOP.has(kind):
		return WORKSHOP[kind]
	return TOOLS.get(kind, {})


## A receita só se faz na bancada de uma oficina?
static func needs_bench(kind: String) -> bool:
	return WORKSHOP.has(kind)


static func has_furniture(kind: String) -> bool:
	return BUILDS.has(kind) and BUILDS[kind].get("furniture", false)


static func is_tool_recipe(kind: String) -> bool:
	return TOOLS.has(kind) or WORKSHOP.has(kind)


static func weapon_title(kind: String) -> String:
	var text := weapon_name(kind)
	return text.left(1).to_upper() + text.substr(1)


## Tudo o que uma construção pede, somando as etapas.
static func total_materials(kind: String, size := 1) -> Dictionary:
	var total := {}
	for i in stage_count(kind):
		var stage := stage_of(kind, i, size)
		for item: String in stage["materials"]:
			total[item] = int(total.get(item, 0)) + int(stage["materials"][item])
	return total


## Descrição da receita para o menu: "3 etapas: 3 pedras grandes, 2 pedras
## médias e 1 pedra pequena."
static func build_summary(kind: String, size := 0) -> String:
	if size <= 0 and is_large(kind):
		size = int(BUILDS[kind]["size"]["default"])
	var stages: Array = BUILDS[kind]["stages"]
	var parts: PackedStringArray = []
	for i in stages.size():
		var stage: Dictionary = stage_of(kind, i, maxi(size, 1))
		parts.append("%s, %s" % [stage["name"], materials_text(stage["materials"])])
	return "%d etapas. %s." % [stages.size(), "; ".join(parts).left(1).to_upper() + "; ".join(parts).substr(1)]


## O que falta na bolsa para uma receita (item -> quantidade que falta).
static func missing(bag: Dictionary, materials: Dictionary) -> Dictionary:
	var out := {}
	for item: String in materials:
		var lacking := int(materials[item]) - int(bag.get(item, 0))
		if lacking > 0:
			out[item] = lacking
	return out
