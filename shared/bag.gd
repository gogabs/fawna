class_name Bag
extends RefCounted
## Bolsa e equipamento da criatura. Fica em shared/ porque servidor e
## clientes usam as mesmas regras.
##
## A bolsa é o mesmo dicionário de sempre (item -> quantidade), agrupado:
## "Argila, 2". O equipamento é o que a criatura tem nas mãos: um item só,
## ou "" com as mãos livres. Empunhar tira o item da bolsa e o põe nas mãos;
## guardar faz o caminho de volta.
##
## Quem decide é o servidor (WorldState): o cliente só pede para empunhar ou
## guardar e recebe a bolsa e o equipamento atualizados.

## O que toda criatura carrega desde que chega ao mundo.
const STARTER := {"machado": 1}

## Itens que podem ser empunhados (vão para o Equipamento) e a dica falada
## ao empunhar.
const WIELDABLE := {
	"machado": "J para golpear.",
	"lanca": "J para golpear.",
	"clava": "J para golpear.",
}

## Nomes dos itens da bolsa que ainda não estão em Economy.ITEM_NAMES.
const NAMES := {
	"machado": ["machado", "machados"],
	"lanca": ["lança de bambu", "lanças de bambu"],
	"clava": ["clava de pedra", "clavas de pedra"],
}


## Itens cujo nome é feminino (o resto é "o"): "a lança de bambu".
const FEMININE := ["lanca", "clava", "argila", "pedra_grande", "pedra_media", "pedra_pequena", "lenha", "lenha_grande", "lenha_media", "lenha_pequena", "frutas"]


## Nome falado com artigo: "o machado", "a lança de bambu".
static func with_article(item: String) -> String:
	return ("a " if item in FEMININE else "o ") + spoken_name(item)


## Nome do item com a primeira letra maiúscula, no singular: "Argila".
static func display_name(item: String) -> String:
	var names: Array = Economy.ITEM_NAMES.get(item, NAMES.get(item, [item]))
	var text: String = names[0]
	return text.left(1).to_upper() + text.substr(1)


## Nome falado em frases: "o machado".
static func spoken_name(item: String) -> String:
	var names: Array = Economy.ITEM_NAMES.get(item, NAMES.get(item, [item]))
	return names[0]


## Itens da bolsa com quantidade, em ordem alfabética: [[item, quantidade], ...].
static func entries(bag: Dictionary) -> Array:
	var list := []
	for item: String in bag:
		if int(bag[item]) > 0:
			list.append([item, int(bag[item])])
	list.sort_custom(func(a, b): return display_name(a[0]).naturalnocasecmp_to(display_name(b[0])) < 0)
	return list


## "Argila, 2".
static func entry_label(item: String, amount: int) -> String:
	return "%s, %d" % [display_name(item), amount]


static func can_wield(item: String) -> bool:
	return WIELDABLE.has(item)


## Dá os itens iniciais a quem ainda não os tem (nem na bolsa, nem nas mãos).
## Vale para criaturas novas e para quem já existia antes da bolsa.
static func give_starter(bag: Dictionary, wielded: String) -> void:
	for item: String in STARTER:
		if int(bag.get(item, 0)) <= 0 and wielded != item:
			bag[item] = int(STARTER[item])
