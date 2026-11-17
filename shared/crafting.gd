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
			{"name": "a lenha", "materials": {"lenha_media": 2, "lenha_pequena": 3}, "work": 2},
		],
	},
}

## Ordem em que as construções aparecem no menu.
const BUILD_ORDER := ["marco", "fogueira"]

## Fogo: batidas de pedra até acender, quanto cada lenha queima e o máximo
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
		"materials": {"bambu": 1, "pedra_pequena": 1}},
	"clava": {"name": ["clava de pedra", "clavas de pedra"], "article": "a",
		"materials": {"lenha_media": 1, "pedra_media": 1}},
}
const WEAPON_ORDER := ["lanca", "clava"]


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


static func build_name(kind: String) -> String:
	return BUILDS[kind]["name"][0] if BUILDS.has(kind) else kind


static func build_title(kind: String) -> String:
	var text := build_name(kind)
	return text.left(1).to_upper() + text.substr(1)


static func weapon_name(kind: String) -> String:
	return WEAPONS[kind]["name"][0] if WEAPONS.has(kind) else kind


static func weapon_title(kind: String) -> String:
	var text := weapon_name(kind)
	return text.left(1).to_upper() + text.substr(1)


## Tudo o que uma construção pede, somando as etapas.
static func total_materials(kind: String) -> Dictionary:
	var total := {}
	for stage: Dictionary in BUILDS[kind]["stages"]:
		for item: String in stage["materials"]:
			total[item] = int(total.get(item, 0)) + int(stage["materials"][item])
	return total


## Descrição da receita para o menu: "3 etapas: 3 pedras grandes, 2 pedras
## médias e 1 pedra pequena."
static func build_summary(kind: String) -> String:
	var stages: Array = BUILDS[kind]["stages"]
	var parts: PackedStringArray = []
	for i in stages.size():
		var stage: Dictionary = stages[i]
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
