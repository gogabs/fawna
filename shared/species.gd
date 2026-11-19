class_name Species
extends RefCounted
## Espécies dos personagens: dão identidade a cada criatura. São híbridos de
## humano e animal (voz humana, algumas feições animais, habilidades animais),
## belos e um pouco inumanos (dark fantasy, sem fofura).
##
## Cada espécie é uma lista de tags (TAGS), e cada tag é um pequeno pacote de
## efeitos com um ganho e SEMPRE um custo: nenhuma tag só tem vantagem. O jogo
## soma as tags da espécie. Para mudar o equilíbrio, mude só TAGS e DATA.
##
## Efeitos numéricos (multiplicadores, 1.0 = igual), em "effects":
##   speed: velocidade de andar         capacity: carga plena da bolsa
##   overload: lentidão da sobrecarga   axe: força do machado
##   torch: duração da tocha            calado_hearing: alcance com que se
##   calado_noise: o Calado percebe de mais longe (ou mais perto)       ouve o Calado
##   calado_delay: tempo que o Calado leva até chegar
## Por enquanto os efeitos ainda NÃO valem no jogo (EFFECTS_ACTIVE): as tags
## aparecem no menu de personagem, e cada efeito entra em PR separado
## (velocidade e carga mexem na Bag e no servidor, o Calado em horrors, etc.).
const EFFECTS_ACTIVE := false
##
## A escolha é feita uma vez por nome de personagem e fica gravada no servidor.

const TAGS := {
	"pesado": {"name": "Pesado", "effects": {"capacity": 1.2, "speed": 0.9},
		"text": "Carga plena 20% maior, mas anda 10% mais devagar."},
	"leve": {"name": "Leve", "effects": {"speed": 1.1, "capacity": 0.85},
		"text": "Anda 10% mais rápido, mas a carga plena é 15% menor."},
	"veloz": {"name": "Veloz", "effects": {"speed": 1.1, "calado_noise": 1.25},
		"text": "Anda 10% mais rápido, mas faz barulho e o Calado o percebe de mais longe."},
	"resistente": {"name": "Resistente", "effects": {"overload": 0.5, "speed": 0.95},
		"text": "A sobrecarga custa metade da lentidão, mas anda 5% mais devagar."},
	"audicao": {"name": "Audição apurada", "effects": {"calado_hearing": 1.3},
		"text": "Ouve o Calado e os pássaros de mais longe, mas o mundo fica abafado por um instante com sons altos (golpe de machado ou enxada, uivo e qualquer outro barulho alto)."},
	"fogo": {"name": "Mestre do fogo", "effects": {"torch": 1.3},
		"text": "A tocha dura mais e acende sem sílex, mas não consegue cruzar água."},
	"guerreiro": {"name": "Guerreiro", "effects": {"axe": 1.15, "capacity": 0.9},
		"text": "Machado 15% mais forte, mas arma e armadura pesam: carga plena 10% menor."},
	"salto": {"name": "Salto", "effects": {},
		"text": "Pulo curto, com espera entre usos, e o pouso faz barulho."},
	"uivo": {"name": "Uivo", "effects": {},
		"text": "Som que os amigos ouvem de longe, com direção, e que também atrai o Calado."},
}

const ORDER: Array[String] = ["urso", "boi", "cervo", "cabra", "lebre", "lobo", "raposa", "onca", "javali"]

const DATA := {
	"urso": {"name": "Urso de musgo", "article": "um", "tags": ["pesado", "guerreiro"],
		"description": "Híbrido de humano e urso, largo, com musgo crescendo nos ombros."},
	"boi": {"name": "Boi de chifre-ferro", "article": "um", "tags": ["pesado", "resistente"],
		"description": "Híbrido de humano e boi, com chifres escuros como ferro velho."},
	"cervo": {"name": "Cervo de galhada-musgo", "article": "um", "tags": ["leve", "veloz"],
		"description": "Híbrido de humano e cervo, com uma galhada coberta de musgo."},
	"cabra": {"name": "Cabra-montesa", "article": "uma", "tags": ["leve", "resistente"],
		"description": "Híbrida de humana e cabra-montesa, de chifres curvos e pés firmes na pedra."},
	"lebre": {"name": "Lebre-de-sombra", "article": "uma", "tags": ["leve", "audicao", "salto"],
		"description": "Híbrida de humana e lebre, de orelhas longas e pelagem escura como sombra."},
	"lobo": {"name": "Lobo cinzento", "article": "um", "tags": ["guerreiro", "uivo"],
		"description": "Híbrido de humano e lobo, de pelagem cinzenta e olhar fixo."},
	"raposa": {"name": "Raposa de cinza", "article": "uma", "tags": ["leve", "fogo"],
		"description": "Híbrida de humana e raposa, de pelo cor de cinza e uma brasa viva no olhar."},
	"onca": {"name": "Onça-negra", "article": "uma", "tags": ["veloz", "salto"],
		"description": "Híbrida de humana e onça, de pelagem negra e passos que quase não pesam."},
	"javali": {"name": "Javali de carvão", "article": "um", "tags": ["guerreiro", "resistente"],
		"description": "Híbrido de humano e javali, de pele escura como carvão e presas curtas."},
}


static func is_species(id: String) -> bool:
	return DATA.has(id)


## "Urso de musgo"; vazio para uma espécie desconhecida ou ainda não escolhida.
static func display_name(id: String) -> String:
	return str(DATA[id]["name"]) if DATA.has(id) else ""


static func article(id: String) -> String:
	return str(DATA[id]["article"]) if DATA.has(id) else "um"


## "um Urso de musgo", ou "sem espécie".
static func label(id: String) -> String:
	if not DATA.has(id):
		return "sem espécie"
	return "%s %s" % [DATA[id]["article"], display_name(id)]


static func description(id: String) -> String:
	return str(DATA[id]["description"]) if DATA.has(id) else ""


static func tags_of(id: String) -> Array:
	return DATA[id]["tags"] if DATA.has(id) else []


## "Pesado, Guerreiro" (para o menu).
static func tag_names(id: String) -> String:
	var names: PackedStringArray = []
	for tag: String in tags_of(id):
		names.append(str(TAGS[tag]["name"]))
	return ", ".join(names)


## Uma tag com o que ela dá e o que custa: "Pesado: carga plena 20% maior...".
static func tag_text(tag: String) -> String:
	return "%s: %s" % [TAGS[tag]["name"], TAGS[tag]["text"]]


## Multiplicador de um efeito, somando as tags da espécie (1.0 se nenhuma mexe).
static func effect(id: String, key: String) -> float:
	var value := 1.0
	for tag: String in tags_of(id):
		value *= float(TAGS[tag]["effects"].get(key, 1.0))
	return value


## "Lia, um Urso de musgo" ou só o nome, se ainda não escolheu.
static func with_name(player_name: String, id: String) -> String:
	if not DATA.has(id):
		return player_name
	return "%s, %s" % [player_name, label(id)]
