class_name Economy
extends RefCounted
## Recursos, receitas das profissões e obras coletivas.
## Fica em shared/ porque servidor e clientes precisam das mesmas regras.

## Nome falado de cada item: [singular, plural].
const ITEM_NAMES := {
	"madeira": ["madeira", "madeiras"],
	"sementes": ["semente", "sementes"],
	"agua": ["balde de água", "baldes de água"],
	"tabuas": ["tábua", "tábuas"],
	"mudas": ["muda", "mudas"],
}

## O que cada coisa do mundo dá ao ser coletada.
const COLLECT := {
	WorldGen.Thing.ARVORE: "madeira",
	WorldGen.Thing.ARBUSTO: "sementes",
	WorldGen.Thing.RIACHO: "agua",
	WorldGen.Thing.LAGO: "agua",
}

## Profissões: o minigame transforma recursos brutos em peças.
const RECIPES := {
	"carpintaria": {"inputs": {"madeira": 2}, "output": "tabuas"},
	"jardinagem": {"inputs": {"sementes": 1, "agua": 1}, "output": "mudas"},
}

## A horta comunitária cresce em estágios; cada um se apoia no anterior.
const GARDEN_NAME := "horta comunitária"
const GARDEN_STAGES := [
	{"name": "canteiro", "needs": {"tabuas": 4}},
	{"name": "horta", "needs": {"mudas": 4}},
	{"name": "horta com irrigação solar", "needs": {"tabuas": 3, "mudas": 3}},
]


static func item_text(item: String, amount: int) -> String:
	var names: Array = ITEM_NAMES.get(item, [item, item])
	return "%d %s" % [amount, names[0] if amount == 1 else names[1]]


## Ex.: {"tabuas": 2, "mudas": 1} -> "2 tábuas e 1 muda"
static func items_text(items: Dictionary) -> String:
	var parts: PackedStringArray = []
	for item in items:
		if items[item] > 0:
			parts.append(item_text(item, items[item]))
	if parts.is_empty():
		return "nada"
	if parts.size() == 1:
		return parts[0]
	return ", ".join(parts.slice(0, -1)) + " e " + parts[-1]


static func stage_missing(stage_index: int, delivered: Dictionary) -> Dictionary:
	var missing := {}
	if stage_index >= GARDEN_STAGES.size():
		return missing
	var needs: Dictionary = GARDEN_STAGES[stage_index]["needs"]
	for item in needs:
		var left: int = needs[item] - int(delivered.get(item, 0))
		if left > 0:
			missing[item] = left
	return missing
