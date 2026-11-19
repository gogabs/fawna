class_name Species
extends RefCounted
## Espécies dos personagens: dão identidade a cada criatura. Todas são híbridas,
## belas e um pouco inumanas (dark fantasy, sem fofura). Cada uma tem um traço
## pequeno, de uns 10 a 15%, para ninguém ficar muito à frente.
##
## Por enquanto só a identidade vale (escolha, gravação, menu de personagem,
## avisos). Os traços (campo "traits") ficam como dados, para ligar depois à
## velocidade, à carga, à tocha e ao Calado, e os sons de passos e voz por
## espécie também ficam para depois.
##
## A escolha é feita uma vez por nome de personagem e fica gravada no servidor.

const ORDER: Array[String] = ["ramado", "brasido", "enraizado", "noturno"]

## "traits": multiplicadores/bônus em relação ao padrão (1.0 = igual).
##   speed: velocidade de andar; capacity: carga da bolsa; torch: duração da
##   tocha; axe: eficiência do machado; calado_hearing: alcance com que se
##   percebe o Calado.
const DATA := {
	"ramado": {
		"name": "Ramado", "article": "um",
		"short": "cervo e árvore",
		"description": "Híbrido de cervo e árvore, com uma galhada coberta de musgo. Os passos são macios, quase não se ouvem.",
		"trait_text": "Anda um pouco mais rápido e carrega um pouco menos.",
		"traits": {"speed": 1.10, "capacity": 0.90},
	},
	"brasido": {
		"name": "Brasido", "article": "um",
		"short": "lobo de brasa",
		"description": "Lobo de pelagem que guarda calor e olhos de brasa. Pisa com pata pesada e tem voz de uivo baixo.",
		"trait_text": "A tocha dura mais e a fogueira acende com menos esforço.",
		"traits": {"torch": 1.25},
	},
	"enraizado": {
		"name": "Enraizado", "article": "um",
		"short": "urso de musgo e pedra",
		"description": "Urso lento e largo, com cascas de pedra e raiz nas costas. Os passos são fundos.",
		"trait_text": "Carrega mais e golpeia melhor com o machado, mas anda mais devagar.",
		"traits": {"speed": 0.90, "capacity": 1.15, "axe": 1.15},
	},
	"noturno": {
		"name": "Noturno", "article": "um",
		"short": "coruja e morcego",
		"description": "Híbrido de coruja e morcego, com as asas dobradas como uma capa. Os passos são de garra seca e a voz é um pio fino.",
		"trait_text": "Percebe o Calado de mais longe, mas carrega um pouco menos.",
		"traits": {"calado_hearing": 1.3, "capacity": 0.90},
	},
}


static func is_species(id: String) -> bool:
	return DATA.has(id)


## "Ramado"; vazio para uma espécie desconhecida ou ainda não escolhida.
static func display_name(id: String) -> String:
	return str(DATA[id]["name"]) if DATA.has(id) else ""


## "um Ramado, cervo e árvore" (para a escolha) ou "sem espécie".
static func label(id: String) -> String:
	if not DATA.has(id):
		return "sem espécie"
	return "%s, %s" % [display_name(id), DATA[id]["short"]]


static func description(id: String) -> String:
	return str(DATA[id]["description"]) if DATA.has(id) else ""


static func trait_text(id: String) -> String:
	return str(DATA[id]["trait_text"]) if DATA.has(id) else ""


## Multiplicador de um traço (1.0 se a espécie não mexe nele).
static func trait_value(id: String, key: String) -> float:
	if not DATA.has(id):
		return 1.0
	return float(DATA[id]["traits"].get(key, 1.0))


## "Lia, um Ramado" ou só o nome, se ainda não escolheu.
static func with_name(player_name: String, id: String) -> String:
	if not DATA.has(id):
		return player_name
	return "%s, %s %s" % [player_name, DATA[id]["article"], display_name(id)]
