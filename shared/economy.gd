class_name Economy
extends RefCounted
## Recursos coletáveis e seus nomes falados.
## Fica em shared/ porque servidor e clientes precisam das mesmas regras.
##
## Alguns recursos têm tamanhos (subtipos): cada tamanho é um item separado
## na bolsa, com a chave "<recurso>_<tamanho>" (ex.: "pedra_grande",
## "lenha_pequena"). As receitas gastam essas chaves. Na fala e no menu da
## Bolsa eles aparecem agrupados: "Pedra, 3 grandes, 1 pequena".

## Nome falado de cada item: [singular, plural]. O que cada coisa do mundo
## dá ao ser coletada fica em Harvest.SOURCES.
const ITEM_NAMES := {
	"bambu": ["bambu", "bambus"],
	"lenha": ["lenha", "lenhas"],
	"madeira": ["madeira", "madeiras"],
	"argila": ["argila", "argilas"],
	"frutas": ["fruta", "frutas"],
	"pedra": ["pedra", "pedras"],
	"machado": ["machado", "machados"],
	"silex": ["sílex", "sílex"],
	"cipo": ["cipó", "cipós"],
	"fibra": ["fibra vegetal", "fibras vegetais"],
	"resina": ["resina", "resinas"],
}

## Tamanhos, do maior para o menor, com o nome falado [singular, plural]
## (todos os recursos com tamanho são femininos: lenha, pedra).
const SIZE_ORDER := ["grande", "media", "pequena"]
const SIZE_NAMES := {
	"grande": ["grande", "grandes"],
	"media": ["média", "médias"],
	"pequena": ["pequena", "pequenas"],
}

## Que tamanhos cada recurso pode ter. Lenha grande só vem das árvores; os
## arbustos dão lenha média e pequena.
const SIZES := {
	"lenha": ["grande", "media", "pequena"],
	"pedra": ["grande", "media", "pequena"],
}


## "pedra_grande" -> "pedra". Itens sem tamanho voltam como estão.
static func base_of(item: String) -> String:
	var cut := item.rfind("_")
	if cut > 0 and SIZES.has(item.left(cut)) and SIZE_NAMES.has(item.substr(cut + 1)):
		return item.left(cut)
	return item


## "pedra_grande" -> "grande"; "" se o item não tem tamanho.
static func size_of(item: String) -> String:
	var base := base_of(item)
	return "" if base == item else item.substr(base.length() + 1)


## ("pedra", "grande") -> "pedra_grande".
static func sized(base: String, size: String) -> String:
	return "%s_%s" % [base, size]


static func has_sizes(base: String) -> bool:
	return SIZES.has(base)


## O item existe no jogo (com ou sem tamanho)?
static func is_item(item: String) -> bool:
	return ITEM_NAMES.has(base_of(item))


## [singular, plural] de qualquer item: "pedra_grande" -> ["pedra grande", "pedras grandes"].
static func names_of(item: String) -> Array:
	var base := base_of(item)
	var names: Array = ITEM_NAMES.get(base, [base, base])
	var size := size_of(item)
	if size.is_empty():
		return names
	return ["%s %s" % [names[0], SIZE_NAMES[size][0]], "%s %s" % [names[1], SIZE_NAMES[size][1]]]


static func item_text(item: String, amount: int) -> String:
	var names := names_of(item)
	return "%d %s" % [amount, names[0] if amount == 1 else names[1]]


## Quantidades por tamanho, só as que existem, do maior para o menor:
## {"pedra_grande": 3, "pedra_pequena": 1} -> "3 grandes, 1 pequena".
static func sizes_text(base: String, items: Dictionary, joiner := ", ") -> String:
	var parts: PackedStringArray = []
	for size: String in SIZE_ORDER:
		var amount := int(items.get(sized(base, size), 0))
		if amount > 0:
			parts.append("%d %s" % [amount, SIZE_NAMES[size][0] if amount == 1 else SIZE_NAMES[size][1]])
	return joiner.join(parts)


## O que se acabou de coletar: "3 pedras: 1 grande e 2 pequenas", "2 lenhas
## médias", "1 argila".
static func collected_text(base: String, amount: int, parts: Dictionary) -> String:
	var sizes := 0
	var only := ""
	for item: String in parts:
		if int(parts[item]) > 0:
			sizes += 1
			only = item
	if sizes == 0:
		return item_text(base, amount)
	if sizes == 1:
		return item_text(only, int(parts[only]))
	var detail := sizes_text(base, parts)
	var cut := detail.rfind(", ")
	detail = detail.left(cut) + " e " + detail.substr(cut + 2)
	return "%s: %s" % [item_text(base, amount), detail]


## Tudo o que uma coleta rendeu: o item principal (com seus tamanhos) e os
## extras: "2 madeiras e 2 lenhas grandes".
static func haul_text(base: String, amount: int, parts: Dictionary, extras: Dictionary) -> String:
	var main := collected_text(base, amount, parts)
	if extras.is_empty():
		return main
	return "%s e %s" % [main, items_text(extras)]


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
