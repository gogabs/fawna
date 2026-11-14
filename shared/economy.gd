class_name Economy
extends RefCounted
## Recursos coletáveis e seus nomes falados.
## Fica em shared/ porque servidor e clientes precisam das mesmas regras.

## Nome falado de cada item: [singular, plural]. O que cada coisa do mundo
## dá ao ser coletada fica em Harvest.SOURCES.
const ITEM_NAMES := {
	"bambu": ["bambu", "bambus"],
	"lenha": ["lenha", "lenhas"],
	"argila": ["argila", "argilas"],
	"frutas": ["fruta", "frutas"],
	"machado": ["machado", "machados"],
}


static func item_text(item: String, amount: int) -> String:
	var names: Array = ITEM_NAMES.get(item, [item, item])
	return "%d %s" % [amount, names[0] if amount == 1 else names[1]]


## Ex.: {"bambu": 3, "argila": 1} -> "3 bambus e 1 argila"
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

