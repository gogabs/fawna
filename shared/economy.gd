class_name Economy
extends RefCounted
## Recursos coletáveis e seus nomes falados.
## Fica em shared/ porque servidor e clientes precisam das mesmas regras.

## Nome falado de cada item: [singular, plural].
const ITEM_NAMES := {
	"madeira": ["madeira", "madeiras"],
	"sementes": ["semente", "sementes"],
	"agua": ["balde de água", "baldes de água"],
}

## O que cada coisa do mundo dá ao ser coletada.
const COLLECT := {
	WorldGen.Thing.ARVORE: "madeira",
	WorldGen.Thing.ARBUSTO: "sementes",
	WorldGen.Thing.RIACHO: "agua",
	WorldGen.Thing.LAGO: "agua",
}

static func item_text(item: String, amount: int) -> String:
	var names: Array = ITEM_NAMES.get(item, [item, item])
	return "%d %s" % [amount, names[0] if amount == 1 else names[1]]


## Ex.: {"madeira": 2, "sementes": 1} -> "2 madeiras e 1 semente"
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

