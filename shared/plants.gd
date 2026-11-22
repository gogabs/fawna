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
	"cenoura": {"name": ["pé de cenoura", "pés de cenoura"], "category": "raiz", "root": "cenoura"},
	# Trepadeiras: nas matas fechadas.
	"cipo": {"name": ["cipó-de-amarra", "cipós-de-amarra"], "category": "trepadeira", "item": "cipo"},
	"maracuja": {"name": ["maracujá-do-mato", "maracujás-do-mato"], "category": "trepadeira", "fruit": "maracuja"},
	# Árvores de fruto.
	"castanheira": {"name": ["castanheira", "castanheiras"], "category": "arvore"},
	# Capim: por enquanto só o de fibra, na mata fechada e na beira da água.
	"capim": {"name": ["capim-de-fibra", "capins-de-fibra"], "category": "capim", "item": "fibra"},
	# Capim de milho: no campo, longe da água; volta devagar.
	"milho": {"name": ["pé de milho", "pés de milho"], "category": "capim", "item": "milho", "regrow": 1800.0, "seasonal": true},
	# Cogumelos comuns, todos de comer (os sósias venenosos virão depois).
	"pardo": {"name": ["chapéu-pardo", "chapéus-pardos"], "category": "cogumelo", "mushroom": "pardo"},
	"orelha": {"name": ["orelha-de-pau", "orelhas-de-pau"], "category": "cogumelo", "mushroom": "orelha"},
	"neve": {"name": ["cogumelo-da-neve", "cogumelos-da-neve"], "category": "cogumelo", "mushroom": "neve"},
}

## Nome falado de cada categoria, como todos a veem (o mesmo de
## WorldGen.THING_NAMES), para "Pé de batata (rama)".
const CATEGORY_NAMES := {"arbusto": "arbusto", "raiz": "rama", "trepadeira": "trepadeira", "arvore": "árvore", "capim": "capim", "cogumelo": "cogumelo"}
## Espécies de nome masculino ("o pé de amora"); o resto é feminino.
const MASCULINE := ["amora", "baga", "batata", "mandioca", "cara", "cenoura", "cipo", "maracuja", "sisal", "capim", "milho", "pardo", "neve"]

## Ordem em que as espécies aparecem no Caminheiro do Forrageador.
const ORDER := ["amora", "pitanga", "baga", "maracuja", "embira", "sisal", "capim", "milho", "batata", "cenoura", "mandioca", "cara", "pardo", "orelha", "neve", "cipo", "castanheira"]

## Fração das trepadeiras que são de maracujá (o resto é cipó). Nas terras
## geladas não há maracujá.
const PASSION_SHARE := 0.3
## Fração dos pés de fruta que são pitangueiras (o resto, amora). Nas terras
## geladas, só baga-de-cinza.
const PITANGA_SHARE := 0.45
## Fração das ramas do campo que são de cenoura (o resto, batata).
const CARROT_SHARE := 0.4
## Fração dos cogumelos do bosque que são orelha-de-pau (o resto, chapéu-pardo).
## Na floresta gelada, cogumelo-da-neve; no brejo, orelha-de-pau.
const EAR_SHARE := 0.4


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
			if biome == WorldGen.Biome.PRADARIA and world.cell_random(cell, "especie") < CARROT_SHARE:
				return "cenoura"
			return root_species(biome)
		WorldGen.Thing.COGUMELO:
			if biome == WorldGen.Biome.FLORESTA_GELADA:
				return "neve"
			if biome == WorldGen.Biome.BREJO or world.cell_random(cell, "especie") < EAR_SHARE:
				return "orelha"
			return "pardo"
		WorldGen.Thing.CIPO:
			return "maracuja" if not cold and world.cell_random(cell, "especie") < PASSION_SHARE else "cipo"
		WorldGen.Thing.ARVORE:
			return "castanheira" if Body.nut_tree(cell) else ""
		WorldGen.Thing.FIBRA:
			return "milho" if biome == WorldGen.Biome.PRADARIA and not world.is_waterside(cell) else "capim"
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


## Some na Longa Escuridão (frutas, milho e cogumelos não dão nada)?
static func is_seasonal(species: String) -> bool:
	var info: Dictionary = SPECIES.get(species, {})
	return info.has("fruit") or info.has("mushroom") or bool(info.get("seasonal", false))


## Segundos até voltar depois de colhida, se a espécie tem tempo próprio (0: o
## de Harvest.SOURCES).
static func regrow_of(species: String) -> float:
	return float(SPECIES.get(species, {}).get("regrow", 0.0))


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
	if info.has("mushroom"):
		return {"item": "cogumelo", "parts": {Economy.sized("cogumelo", str(info["mushroom"])): amount}}
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
