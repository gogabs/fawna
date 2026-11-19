class_name Bag
extends RefCounted
## Bolsa e equipamento da criatura. Fica em shared/ porque servidor e
## clientes usam as mesmas regras.
##
## A bolsa é o mesmo dicionário de sempre (item -> quantidade), agrupado:
## "Argila, 2". Recursos com tamanho (Economy.SIZES) ficam um item por tamanho
## ("pedra_grande", "pedra_pequena") e aparecem juntos: "Pedra, 3 grandes,
## 1 pequena", só com os tamanhos que a criatura tem. O equipamento é o que a criatura tem nas mãos: um item só,
## ou "" com as mãos livres. Empunhar tira o item da bolsa e o põe nas mãos;
## guardar faz o caminho de volta.
##
## Quem decide é o servidor (WorldState): o cliente só pede para empunhar ou
## guardar e recebe a bolsa e o equipamento atualizados.

## O que toda criatura carrega desde que chega ao mundo.
const STARTER := {"machado": 1}

## Carga: quanto peso a criatura aguenta levar, somando a bolsa e o que está
## nas mãos (empunhar e guardar não mudam a carga). Para deixar o jogo mais
## fácil ou mais difícil, mude só CAPACITY e WEIGHTS.
##
## A medida é o peso de uma fruta (1). Com 24, um marco inteiro (3 pedras
## grandes, 2 médias e 1 pequena = 25) não cabe numa viagem só, e uma
## fogueira (23) só cabe se o machado (3) ficar no chão.
const CAPACITY := 24
## Peso de cada item. O que não estiver aqui pesa DEFAULT_WEIGHT.
const WEIGHTS := {
	"frutas": 1,
	"lenha_pequena": 1,
	"lenha_media": 2,
	"lenha_grande": 4,
	"pedra_pequena": 1,
	"pedra_media": 3,
	"pedra_grande": 6,
	"bambu": 2,
	"argila": 2,
	"machado": 3,
	"lanca": 2,
	"clava": 4,
	"enxada": 3,
	"silex": 1,
	"cipo": 1,
	"fibra": 1,
	"resina": 1,
	"faca": 2,
	"tocha": 2,
}
const DEFAULT_WEIGHT := 1

## Categoria de cada recurso ou item (pela chave sem tamanho: "pedra_grande"
## vale como "pedra"). Decide onde cada coisa pode ser guardada (Crafting.STORAGE).
## O que não estiver aqui é "material".
const CATEGORIES := {
	"machado": "ferramenta",
	"enxada": "ferramenta",
	"lanca": "arma",
	"clava": "arma",
	"frutas": "comida",
}
const DEFAULT_CATEGORY := "material"


static func category_of(item: String) -> String:
	return str(CATEGORIES.get(Economy.base_of(item), DEFAULT_CATEGORY))

## Itens que podem ser empunhados (vão para o Equipamento) e a dica falada
## ao empunhar.
const WIELDABLE := {
	"machado": "J para golpear.",
	"lanca": "J para golpear.",
	"clava": "J para golpear.",
	"enxada": "J para capinar a grama de uma obra.",
	"faca": "J no tronco de uma árvore, poucas vezes, para tirar resina.",
	"tocha": "Vai na mão não dominante. Para acendê-la, use Equipamento perto de uma fogueira acesa; longe de uma, risque faca ou sílex numa pedra pequena com Espaço.",
}

## Itens que vão na mão não dominante, a segunda peça de equipamento: não
## tiram o que está na mão principal.
const OFFHAND := ["tocha"]

## Nomes dos itens da bolsa que ainda não estão em Economy.ITEM_NAMES.
const NAMES := {
	"machado": ["machado", "machados"],
	"lanca": ["lança de bambu", "lanças de bambu"],
	"clava": ["clava de pedra", "clavas de pedra"],
	"enxada": ["enxada", "enxadas"],
	"faca": ["faca bruta de sílex", "facas brutas de sílex"],
	"tocha": ["tocha", "tochas"],
}


## Itens cujo nome é feminino (o resto é "o"): "a lança de bambu".
const FEMININE := ["lanca", "clava", "enxada", "argila", "pedra_grande", "pedra_media", "pedra_pequena", "lenha", "lenha_grande", "lenha_media", "lenha_pequena", "frutas", "madeira", "faca", "tocha", "fibra", "resina"]


## Nome falado com artigo: "o machado", "a lança de bambu".
static func with_article(item: String) -> String:
	return ("a " if item in FEMININE else "o ") + spoken_name(item)


## Nome do item com a primeira letra maiúscula, no singular: "Argila".
static func display_name(item: String) -> String:
	var names: Array = Economy.names_of(item) if Economy.is_item(item) else NAMES.get(item, [item])
	var text: String = names[0]
	return text.left(1).to_upper() + text.substr(1)


## Nome falado em frases: "o machado".
static func spoken_name(item: String) -> String:
	var names: Array = Economy.names_of(item) if Economy.is_item(item) else NAMES.get(item, [item])
	return names[0]


## Itens da bolsa agrupados, em ordem alfabética: [[item, quantidade], ...].
## Os tamanhos de um recurso viram uma entrada só, com o nome do recurso e a
## soma ("pedra", 4).
static func entries(bag: Dictionary) -> Array:
	var totals := {}
	for item: String in bag:
		if int(bag[item]) > 0:
			var base := Economy.base_of(item)
			totals[base] = int(totals.get(base, 0)) + int(bag[item])
	var list := []
	for item: String in totals:
		list.append([item, totals[item]])
	list.sort_custom(func(a, b): return display_name(a[0]).naturalnocasecmp_to(display_name(b[0])) < 0)
	return list


## Quanto há de um recurso, somando os tamanhos: count(bag, "pedra").
## Com a chave de um tamanho ("pedra_grande"), só aquele tamanho.
static func count(bag: Dictionary, item: String) -> int:
	if Economy.base_of(item) != item:
		return int(bag.get(item, 0))
	var total := int(bag.get(item, 0))
	if Economy.has_sizes(item):
		for size: String in Economy.SIZE_ORDER:
			total += int(bag.get(Economy.sized(item, size), 0))
	return total


## "Argila, 2"; com tamanhos, "Pedra, 3 grandes, 1 pequena".
static func entry_label(item: String, amount: int, bag := {}) -> String:
	if Economy.has_sizes(item):
		var sizes := Economy.sizes_text(item, bag)
		if not sizes.is_empty():
			return "%s, %s" % [display_name(item), sizes]
	return "%s, %d" % [display_name(item), amount]


static func can_wield(item: String) -> bool:
	return WIELDABLE.has(item)


static func is_offhand(item: String) -> bool:
	return OFFHAND.has(item)


## Dá os itens iniciais a quem ainda não os tem (nem na bolsa, nem nas mãos).
## Vale para criaturas novas e para quem já existia antes da bolsa.
static func give_starter(bag: Dictionary, wielded: String) -> void:
	for item: String in STARTER:
		if int(bag.get(item, 0)) <= 0 and wielded != item:
			bag[item] = int(STARTER[item])


static func weight_of(item: String) -> int:
	return int(WEIGHTS.get(item, DEFAULT_WEIGHT))


## Peso de um punhado de itens (item -> quantidade).
static func weight_of_items(items: Dictionary) -> int:
	var total := 0
	for item: String in items:
		total += weight_of(item) * maxi(0, int(items[item]))
	return total


## Carga atual: a bolsa mais o que está nas mãos.
static func load_of(bag: Dictionary, wielded := "", offhand := "") -> int:
	return weight_of_items(bag) + (0 if wielded.is_empty() else weight_of(wielded)) \
			+ (0 if offhand.is_empty() else weight_of(offhand))


## Quanto peso ainda cabe (0 se a criatura já está no limite ou acima dele,
## como quem vem de um mundo salvo antes do limite existir).
static func free_space(bag: Dictionary, wielded := "", offhand := "") -> int:
	return maxi(0, CAPACITY - load_of(bag, wielded, offhand))


## Quantas unidades de "item" ainda cabem.
static func room_for(bag: Dictionary, wielded: String, item: String, offhand := "") -> int:
	return free_space(bag, wielded, offhand) / maxi(1, weight_of(item))


## Separa o que cabe do que não cabe, pondo primeiro o mais pesado (o que
## sobra de fora é o miúdo). Devolve [cabe, não cabe], cada um item -> quantidade.
static func split_to_fit(bag: Dictionary, wielded: String, items: Dictionary, offhand := "") -> Array:
	var free := free_space(bag, wielded, offhand)
	var keys := items.keys()
	keys.sort_custom(func(a, b):
		return weight_of(a) > weight_of(b) if weight_of(a) != weight_of(b) else str(a) < str(b))
	var fit := {}
	var rest := {}
	for item: String in keys:
		var amount := maxi(0, int(items[item]))
		var take := mini(amount, free / maxi(1, weight_of(item)))
		free -= take * weight_of(item)
		if take > 0:
			fit[item] = take
		if amount - take > 0:
			rest[item] = amount - take
	return [fit, rest]


## As chaves da bolsa que formam um item agrupado, do maior tamanho ao menor:
## "pedra" -> ["pedra_grande", "pedra_pequena"] (só as que a criatura tem).
static func keys_of(bag: Dictionary, base: String) -> Array:
	var keys := []
	if int(bag.get(base, 0)) > 0:
		keys.append(base)
	if Economy.has_sizes(base):
		for size: String in Economy.SIZE_ORDER:
			if int(bag.get(Economy.sized(base, size), 0)) > 0:
				keys.append(Economy.sized(base, size))
	return keys


## "Carga, 18 de 24".
static func load_label(bag: Dictionary, wielded := "", offhand := "") -> String:
	return "Carga, %d de %d" % [load_of(bag, wielded, offhand), CAPACITY]
