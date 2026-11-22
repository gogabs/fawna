class_name Plants
extends RefCounted
## Plantas por categoria: arbustos, raízes, trepadeiras e árvores de fruto.
##
## Quem anda pelo mundo vê a categoria ("arbusto", "rama", "trepadeira",
## "árvore"); a espécie só se sabe com a coisa na mão, ao colher ("Você
## coletou 2 amoras"). Quem tem a tag Forrageador reconhece a espécie de longe:
## a fala, o Tab e o Caminheiro dizem "pé de amora" (Harvest.knows_plants).
##
## A espécie de cada planta é fixa pela casa e pela semente (cell_random), e
## depende do bioma. A coisa do mundo (WorldGen.Thing) diz a categoria; aqui
## fica qual espécie é e o que ela dá.

## Espécies: nome falado [singular, plural] para o Forrageador, categoria e o
## que dá. "fruit": espécie da fruta (Economy.KINDS["frutas"]); "root": da
## raiz; "item": outro item (fibra, cipó).
const SPECIES := {
	# Arbustos de fruta: no campo aberto, do lado de fora da orla da mata.
	"amora": {"name": ["pé de amora", "pés de amora"], "category": "arbusto", "fruit": "amora"},
	"pitanga": {"name": ["pitangueira", "pitangueiras"], "category": "arbusto", "fruit": "pitanga"},
	"baga": {"name": ["pé de baga-de-cinza", "pés de baga-de-cinza"], "category": "arbusto", "fruit": "baga"},
	# Arbustos de fibra: dentro da mata e na beira da água.
	"embira": {"name": ["embira", "embiras"], "category": "arbusto", "item": "fibra"},
	"sisal": {"name": ["sisal-do-brejo", "sisais-do-brejo"], "category": "arbusto", "item": "fibra"},
	# Raízes: a rama fica à vista; a raiz, embaixo, sai com a enxada.
	"batata": {"name": ["pé de batata", "pés de batata"], "category": "raiz", "root": "batata"},
	"mandioca": {"name": ["pé de mandioca", "pés de mandioca"], "category": "raiz", "root": "mandioca"},
	"cara": {"name": ["pé de cará", "pés de cará"], "category": "raiz", "root": "cara"},
	# Trepadeiras: nas matas fechadas.
	"cipo": {"name": ["cipó-de-amarra", "cipós-de-amarra"], "category": "trepadeira", "item": "cipo"},
	"maracuja": {"name": ["maracujá-do-mato", "maracujás-do-mato"], "category": "trepadeira", "fruit": "maracuja"},
	# Árvores de fruto.
	"castanheira": {"name": ["castanheira", "castanheiras"], "category": "arvore"},
	# Capim: por enquanto só o de fibra, na mata fechada e na beira da água.
	"capim": {"name": ["capim-de-fibra", "capins-de-fibra"], "category": "capim", "item": "fibra"},
}

## Nome falado de cada categoria, como todos a veem (o mesmo de
## WorldGen.THING_NAMES), para "Pé de batata (rama)".
const CATEGORY_NAMES := {"arbusto": "arbusto", "raiz": "rama", "trepadeira": "trepadeira", "arvore": "árvore", "capim": "capim"}
## Espécies de nome masculino ("o pé de amora"); o resto é feminino.
const MASCULINE := ["amora", "baga", "batata", "mandioca", "cara", "cipo", "maracuja", "sisal", "capim"]

## Ordem em que as espécies aparecem no Caminheiro do Forrageador.
const ORDER := ["amora", "pitanga", "baga", "maracuja", "embira", "sisal", "capim", "batata", "mandioca", "cara", "cipo", "castanheira"]

## Fração das trepadeiras que são de maracujá (o resto é cipó). Nas terras
## geladas não há maracujá.
const PASSION_SHARE := 0.3
## Fração dos pés de fruta que são pitangueiras (o resto, amora). Nas terras
## geladas, só baga-de-cinza.
const PITANGA_SHARE := 0.45


## A espécie da planta desta casa ("" se não é planta, ou é uma árvore comum).
static func species_at(world: WorldGen, cell: Vector2i) -> String:
	var biome := world.biome_at(cell)
	var cold := WorldGen.COLD_BIOMES.has(biome)
	match world.thing_at(cell):
		WorldGen.Thing.ARBUSTO_FRUTAS:
			if cold:
				return "baga"
			return "pitanga" if world.cell_random(cell, "especie") < PITANGA_SHARE else "amora"
		WorldGen.Thing.ARBUSTO:
			return "sisal" if biome == WorldGen.Biome.BREJO or world.is_waterside(cell) else "embira"
		WorldGen.Thing.RAMA:
			return root_species(biome)
		WorldGen.Thing.CIPO:
			return "maracuja" if not cold and world.cell_random(cell, "especie") < PASSION_SHARE else "cipo"
		WorldGen.Thing.ARVORE:
			return "castanheira" if Body.nut_tree(cell) else ""
		WorldGen.Thing.FIBRA:
			return "capim"
	return ""


## Que raiz nasce em cada bioma: batata no campo, cará no brejo, mandioca no
## bosque (e nos outros).
static func root_species(biome: int) -> String:
	match biome:
		WorldGen.Biome.PRADARIA:
			return "batata"
		WorldGen.Biome.BREJO:
			return "cara"
	return "mandioca"


## O item da bolsa da raiz desta espécie de planta: "raiz_batata".
static func root_item(species: String) -> String:
	return Economy.sized("raiz", str(SPECIES[species].get("root", "batata")))


## A espécie dá fruta?
static func is_fruit(species: String) -> bool:
	return SPECIES.get(species, {}).has("fruit")


## O que a planta desta casa dá ao ser colhida, no formato de Harvest.take:
## {item, parts}. Vazio se a espécie não muda nada do que Harvest.SOURCES diz.
static func yield_at(world: WorldGen, cell: Vector2i, amount: int) -> Dictionary:
	var species := species_at(world, cell)
	if species.is_empty() or species == "castanheira":
		return {}
	var info: Dictionary = SPECIES[species]
	if info.has("fruit"):
		return {"item": "frutas", "parts": {Economy.sized("frutas", str(info["fruit"])): amount}}
	if info.has("root"):
		return {"item": "raiz", "parts": {root_item(species): amount}}
	return {"item": str(info["item"]), "parts": {}}


## Nome falado da espécie: "pé de amora".
static func name_of(species: String, plural := false) -> String:
	return str(SPECIES[species]["name"][1 if plural else 0])


## Com artigo, para "rumo ao pé de amora": "o pé de amora", "a embira".
static func with_article(species: String) -> String:
	return ("o " if MASCULINE.has(species) else "a ") + name_of(species)


## Categoria falada: "rama", "arbusto".
static func category_name(species: String) -> String:
	return str(CATEGORY_NAMES[SPECIES[species]["category"]])
