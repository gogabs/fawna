class_name SettlementNames
extends RefCounted
## Nomes de povoado: um substantivo e um adjetivo escolhidos em duas listas
## curtas, sorteadas de listas maiores ("Clareira" + "Esquecida").
##
## O sorteio depende só da semente do mundo e do marco, então o servidor e
## todos os clientes veem as mesmas opções para o mesmo marco, e o servidor
## confere a escolha sem precisar guardar nada.

## Quantas opções de cada lista aparecem para um marco.
const OPTIONS := 6

## Substantivos: [palavra, gênero ("m" ou "f")].
const NOUNS := [
	["Vale", "m"], ["Refúgio", "m"], ["Abrigo", "m"], ["Recanto", "m"], ["Pouso", "m"], ["Limiar", "m"],
	["Ermo", "m"], ["Outeiro", "m"], ["Remanso", "m"], ["Ninho", "m"], ["Covil", "m"], ["Umbral", "m"],
	["Farol", "m"], ["Jardim", "m"], ["Berço", "m"], ["Porto", "m"], ["Braseiro", "m"], ["Lume", "m"],
	["Sussurro", "m"], ["Silêncio", "m"], ["Caminho", "m"], ["Regato", "m"], ["Espinheiro", "m"], ["Bosque", "m"],
	["Clareira", "f"], ["Toca", "f"], ["Lareira", "f"], ["Morada", "f"], ["Brasa", "f"], ["Raiz", "f"],
	["Fonte", "f"], ["Colina", "f"], ["Penumbra", "f"], ["Vigília", "f"], ["Margem", "f"], ["Pedra", "f"],
	["Bruma", "f"], ["Travessia", "f"], ["Guarida", "f"], ["Cinza", "f"], ["Aurora", "f"], ["Enseada", "f"],
	["Trégua", "f"], ["Vereda", "f"], ["Gruta", "f"], ["Fresta", "f"], ["Chama", "f"], ["Passagem", "f"],
]

## Adjetivos: [masculino, feminino].
const ADJECTIVES := [
	["Sombrio", "Sombria"], ["Antigo", "Antiga"], ["Esquecido", "Esquecida"], ["Quieto", "Quieta"],
	["Profundo", "Profunda"], ["Velado", "Velada"], ["Selvagem", "Selvagem"], ["Errante", "Errante"],
	["Sereno", "Serena"], ["Frio", "Fria"], ["Pálido", "Pálida"], ["Oculto", "Oculta"],
	["Derradeiro", "Derradeira"], ["Dourado", "Dourada"], ["Rubro", "Rubra"], ["Cinzento", "Cinzenta"],
	["Úmido", "Úmida"], ["Torto", "Torta"], ["Manso", "Mansa"], ["Bravio", "Bravia"],
	["Calado", "Calada"], ["Perdido", "Perdida"], ["Vigilante", "Vigilante"], ["Tardio", "Tardia"],
	["Lento", "Lenta"], ["Áspero", "Áspera"], ["Brando", "Branda"], ["Distante", "Distante"],
	["Eterno", "Eterna"], ["Humilde", "Humilde"], ["Teimoso", "Teimosa"], ["Musgoso", "Musgosa"],
	["Enluarado", "Enluarada"], ["Orvalhado", "Orvalhada"], ["Ferido", "Ferida"], ["Faminto", "Faminta"],
	["Insone", "Insone"], ["Paciente", "Paciente"], ["Primeiro", "Primeira"], ["Último", "Última"],
	["Secreto", "Secreta"], ["Silvestre", "Silvestre"], ["Nebuloso", "Nebulosa"], ["Desperto", "Desperta"],
	["Remoto", "Remota"], ["Solene", "Solene"], ["Agreste", "Agreste"], ["Inquieto", "Inquieta"],
]


## As opções de um marco: { "nouns": [índices em NOUNS], "adjectives":
## [índices em ADJECTIVES] }, OPTIONS de cada, sempre as mesmas para o mesmo
## mundo e o mesmo marco.
static func options(world_seed: int, build_id: int) -> Dictionary:
	return {
		"nouns": _draw(NOUNS.size(), hash([world_seed, build_id, "substantivos"])),
		"adjectives": _draw(ADJECTIVES.size(), hash([world_seed, build_id, "adjetivos"])),
	}


static func noun(index: int) -> String:
	return NOUNS[index][0] if index >= 0 and index < NOUNS.size() else ""


## O adjetivo já concordando com o substantivo ("Clareira" pede "Esquecida").
static func adjective(noun_index: int, adjective_index: int) -> String:
	if noun_index < 0 or noun_index >= NOUNS.size() or adjective_index < 0 or adjective_index >= ADJECTIVES.size():
		return ""
	return ADJECTIVES[adjective_index][1 if NOUNS[noun_index][1] == "f" else 0]


## "Clareira Esquecida". Vazio se algum índice não existe.
static func compose(noun_index: int, adjective_index: int) -> String:
	var second := adjective(noun_index, adjective_index)
	return "" if second.is_empty() else "%s %s" % [noun(noun_index), second]


## OPTIONS índices diferentes entre 0 e size - 1 (embaralha e pega os
## primeiros).
static func _draw(size: int, draw_seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = draw_seed
	var indices := range(size)
	for i in mini(OPTIONS, size):
		var j := rng.randi_range(i, size - 1)
		var kept: int = indices[i]
		indices[i] = indices[j]
		indices[j] = kept
	return indices.slice(0, mini(OPTIONS, size))
