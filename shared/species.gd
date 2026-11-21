class_name Species
extends RefCounted
## Espécies dos personagens: dão identidade a cada criatura. São híbridos de
## humano e animal (voz humana, algumas feições animais, habilidades animais),
## belos e um pouco inumanos (dark fantasy, sem fofura).
##
## Cada espécie é uma lista de tags (TAGS), e cada tag é um pequeno pacote de
## efeitos com um ganho e um custo: nenhuma tag só tem vantagem. Exceções, por
## decisão do Gabs (2026-11-20): uivo, garras e forrageador não têm custo,
## porque quem as tem compensa com poucas tags.
## Toda espécie tem exatamente UMA tag ativa (habilidade usada numa tecla, com
## espera entre usos, "active": true; pode repetir em outras espécies) e uma
## tag ÚNICA, que só ela tem (a ativa pode ser a própria única). O jogo
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
	"audicao": {"name": "Audição apurada", "effects": {"calado_hearing": 1.3, "caminheiro_regions": 1},
		"text": "Ouve o Calado e os pássaros de mais longe, e o Caminheiro alcança também as 8 regiões ao redor, mas todo som alto abafa o mundo por um instante, mais quanto mais alto: uma árvore caindo abafa muito, uma machadada médio, os ruídos de obra pouco, e passos e pássaros não abafam nada (ver Loudness)."},
	"fogo": {"name": "Mestre do fogo", "effects": {"torch": 1.3},
		"text": "A tocha dura mais e acende sem sílex, mas não consegue cruzar água."},
	"guerreiro": {"name": "Guerreiro", "effects": {"axe": 1.15, "capacity": 0.9},
		"text": "Machado 15% mais forte, mas arma e armadura pesam: carga plena 10% menor."},
	"furtividade": {"name": "Furtividade", "effects": {"noise": 0.5, "speed": 0.9, "jump": 0.8},
		"text": "Faz menos barulho ao andar e ao saltar, mas anda mais devagar e salta mais curto."},
	"garras": {"name": "Garras", "effects": {},
		"text": "Ataca sem precisar de arma, com as garras."},
	"forrageador": {"name": "Forrageador", "effects": {},
		"text": "Distingue as plantas pelo faro: frutos, leguminosas, raízes e outras. Por enquanto não há plantas que façam sentido."},
	# Ativas (ainda sem lógica no jogo; cada uma entra em PR próprio).
	"salto": {"name": "Salto", "active": true, "effects": {},
		"text": "Pulo curto, com espera entre usos, e o pouso faz barulho."},
	"uivo": {"name": "Uivo", "active": true, "effects": {},
		"text": "Som que os amigos ouvem de longe, com direção, e que afasta o Calado."},
	"disparada": {"name": "Disparada", "active": true, "effects": {},
		"text": "Corre o dobro por uns 3 s, mas faz muito barulho e fica cansado depois."},
	"fucar": {"name": "Fuçar", "active": true, "effects": {},
		"text": "Escava a terra à frente e acha argila ou sílex escondidos por perto (e raízes e sementes, quando existirem), mas demora uns 5 s parado e faz barulho."},
	"pesca": {"name": "Pesca com as patas", "active": true, "effects": {},
		"text": "Pesca sem precisar de ferramenta, só com as patas, mas demora e faz barulho na água. Vale quando houver pesca no jogo."},
	"arar": {"name": "Arar", "active": true, "effects": {},
		"text": "Limpa a grama, os arbustos e os bambus da casa à frente sem enxada nem machado, e depois o preparo de terra agrícola, mas demora uns 5 s por casa e faz barulho."},
}

const ORDER: Array[String] = ["urso", "boi", "cervo", "coelho", "lobo", "raposa", "onca", "javali"]

const DATA := {
	"urso": {"name": "Troncudo", "animal": "urso", "article": "um", "tags": ["pesado", "guerreiro", "pesca"],
		"description": "Largo e lento, com os ombros cobertos por uma casca grossa de tronco, rugosa como carvalho velho. Anda com o peso de quem não tem pressa, e o cheiro de madeira e terra molhada vai atrás dele."},
	"boi": {"name": "Ferrenho", "animal": "boi", "article": "um", "tags": ["pesado", "resistente", "arar"],
		"description": "Pescoço grosso, chifres escuros como ferro velho e um olhar paciente que quase não pisca. Quando pega peso, leva até o fim, sem reclamar e sem pressa."},
	"cervo": {"name": "Ramado", "animal": "cervo", "article": "um", "tags": ["leve", "veloz", "disparada"],
		"description": "Esguio e alto, com uma galhada coberta de musgo que parece mais velha do que ele. Os passos mal tocam o chão, e ele corre como quem foge de algo que só ele ouve."},
	"coelho": {"name": "Lunar", "animal": "coelho", "article": "um", "tags": ["leve", "audicao", "salto"],
		"description": "Pequeno e atento, de orelhas longas e pelagem branca salpicada de manchas castanhas, como a lua com as suas crateras. Conhece cada toca do caminho, escuta o chão antes de ouvir o ar, e já sumiu quando alguém percebe que ele estava ali."},
	"lobo": {"name": "Geado", "animal": "lobo", "article": "um", "tags": ["guerreiro", "uivo"],
		"description": "Pelagem cinzenta com as pontas brancas, como neve suja de cinza, e um olhar fixo de quem já esperou muito por pouco. Quando uiva, a floresta inteira ouve."},
	"raposa": {"name": "Brasido", "animal": "raposa", "article": "um", "tags": ["furtividade", "fogo", "salto"],
		"description": "Pelo cor de cinza e, por baixo dele, uma brasa que nunca apaga por inteiro, viva nos olhos. Gosta do que queima e do que se esconde, e deixa um cheiro leve de fumaça por onde passa."},
	"onca": {"name": "Retinto", "animal": "onça", "article": "um", "tags": ["garras", "guerreiro", "salto"],
		"description": "Pelagem negra como breu, onde só se vê o brilho dos olhos e das garras. Anda sem peso, ataca sem aviso e raramente precisa de mais do que tem nas próprias mãos."},
	"javali": {"name": "Raizeiro", "animal": "javali", "article": "um", "tags": ["guerreiro", "forrageador", "fucar"],
		"description": "Pele escura como carvão e presas curtas, sujas de terra. Fuça o chão como quem sabe que a terra guarda coisas, e reconhece pelo cheiro o que serve de comida e o que não serve."},
}


static func is_species(id: String) -> bool:
	return DATA.has(id)


## "Troncudo"; vazio para uma espécie desconhecida ou ainda não escolhida.
static func display_name(id: String) -> String:
	return str(DATA[id]["name"]) if DATA.has(id) else ""


## O animal da espécie ("urso", "coelho"...); vazio se desconhecida.
static func animal(id: String) -> String:
	return str(DATA[id]["animal"]) if DATA.has(id) else ""


## "Troncudo, urso" (nome e animal, para as listas).
static func name_and_animal(id: String) -> String:
	return "%s, %s" % [display_name(id), animal(id)] if DATA.has(id) else ""


static func article(id: String) -> String:
	return str(DATA[id]["article"]) if DATA.has(id) else "um"


## "um Troncudo", ou "sem espécie".
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
		names.append(tag_label(tag))
	return ", ".join(names)


## "Salto (ativa)" para as ativas; o nome puro para as outras.
static func tag_label(tag: String) -> String:
	return "%s (ativa)" % TAGS[tag]["name"] if is_active(tag) else str(TAGS[tag]["name"])


static func is_active(tag: String) -> bool:
	return bool(TAGS[tag].get("active", false))


## A tag ativa da espécie ("" se não houver).
static func active_of(id: String) -> String:
	for tag: String in tags_of(id):
		if is_active(tag):
			return tag
	return ""


## As tags que só esta espécie tem.
static func unique_tags(id: String) -> Array:
	var result := []
	for tag: String in tags_of(id):
		var others := 0
		for other: String in ORDER:
			if other != id and tags_of(other).has(tag):
				others += 1
		if others == 0:
			result.append(tag)
	return result



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
