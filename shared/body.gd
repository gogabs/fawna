class_name Body
extends RefCounted
## O corpo da criatura: duas reservas, fome e calor, de 0 a 100. Fica em
## shared/ porque servidor e clientes usam as mesmas regras; quem decide é o
## servidor (WorldState.body e o nó Survival).
##
## A fome cai sempre, mais depressa no frio do ano. O calor só cai quando faz
## frio, e o frio vem da estação, da noite e do bioma. Fogueira acesa e abrigo
## pronto devolvem o calor; a tocha na mão só freia a perda. Nada disso é
## barra nem número para quem joga: a criatura ouve o próprio corpo, escuta uma
## frase quando cruza um limiar (LEVELS) e pergunta no C.
##
## Para ajustar o jogo, mude só as tabelas desta classe. Os tempos são em DIAS
## DE JOGO (um dia = 30 min reais), para que o relógio acelerado da depuração
## acelere o corpo junto.

const MAX := 100.0
## Quem chega ao mundo pela primeira vez começa cheio.
const START := 100.0
## Quem desfalece acorda com a reserva assim.
const REVIVE := 30.0

## Limiares, do mais leve ao mais grave. Abaixo de 50 começa o som do corpo;
## abaixo de 25 a criatura fica abatida; em zero, desfalece depois de
## FAINT_SECONDS. O nível 0 é "bem".
const LEVELS := [50.0, 25.0, 0.0]
const FAINT_SECONDS := 60.0
## Abatida (nível 2 ou mais em qualquer reserva): anda e trabalha mais devagar.
const WEAK_SPEED := 0.85
const WEAK_WORK := 0.75

## Barra sonora: a cada vez que uma reserva cruza um destes valores (para
## baixo ou para cima), um toque soa no estéreo, da direita (cheia) para a
## esquerda (vazia), em 6 posições: 100, 80, 60, 40, 20 e 0.
const BAR_MARKS := [80.0, 60.0, 40.0, 20.0, 0.0]

## Fome: quantos dias a reserva cheia dura, em cada estação (Coroada, Declínio,
## Longa Escuridão, Ressurgência). O frio queima mais.
const HUNGER_DAYS := [1.5, 1.4, 1.0, 1.4]
## Esforço: cada golpe, batida de obra ou passo de fabricação gasta isto a mais.
const EFFORT := 0.25

## Frio: em quantos dias o calor cheio chega a zero, longe do fogo, por
## estação: [de dia, de noite]. 0 = não esfria.
const COLD_DAYS := [
	[0.0, 0.0],  # Coroada
	[0.0, 0.5],  # Declínio
	[0.4, 0.2],  # Longa Escuridão
	[0.0, 0.5],  # Ressurgência
]
## Biomas gelados: esfria o ano todo como a noite do inverno, e no inverno
## mais ainda.
const COLD_BIOMES := [WorldGen.Biome.FLORESTA_GELADA, WorldGen.Biome.DESERTO_GELADO]
const COLD_BIOME_DAYS := 0.2
const COLD_BIOME_WINTER_DAYS := 0.133
## Molhado (cruzou um vau): o frio dobra por WET_SECONDS, se já estiver esfriando.
const WET_FACTOR := 2.0
const WET_SECONDS := 60.0
## Tocha acesa na mão: a perda cai pela metade.
const TORCH_FACTOR := 0.5
## Fogueira acesa a até FIRE_REACH casas: o calor volta de zero a cheio em
## FIRE_DAYS. Dentro de um abrigo pronto, não esfria e volta em SHELTER_DAYS.
const FIRE_REACH := 8.0
const FIRE_DAYS := 0.067
const SHELTER_DAYS := 0.25

## Comida: quanto cada item sacia (fome) e aquece (calor), em pontos da
## reserva, como se diz ao comer ("Você come uma fruta.") e em quantos dias de
## jogo estraga na bolsa ("keeps"). "raw": crua, enjoa se comer muitas seguidas.
## As espécies ("frutas_amora", "raiz_batata") valem como o grupo, a não ser
## que tenham linha própria aqui; "eat" sai do nome da espécie ("uma amora",
## "um cará cru").
const FOODS := {
	"frutas": {"food": 10.0, "warmth": 0.0, "eat": "uma fruta", "keeps": 2.0},
	"raiz": {"food": 5.0, "warmth": 0.0, "eat": "uma raiz crua", "keeps": 6.0, "raw": true},
	"raiz_assada": {"food": 20.0, "warmth": 8.0, "eat": "uma raiz assada, ainda quente", "keeps": 3.0},
	"castanha": {"food": 8.0, "warmth": 0.0, "eat": "uma castanha", "keeps": 144.0},
	# A mandioca crua estraga depressa; a cenoura se come crua, sem enjoar.
	"raiz_mandioca": {"food": 5.0, "warmth": 0.0, "keeps": 3.0, "raw": true},
	"raiz_cenoura": {"food": 6.0, "warmth": 0.0, "keeps": 6.0},
	# Cogumelos comuns: saciam pouco e estragam depressa.
	"cogumelo": {"food": 6.0, "warmth": 0.0, "keeps": 1.5},
	# Milho: cru enjoa como a raiz; assado sustenta e aquece.
	"milho": {"food": 4.0, "warmth": 0.0, "eat": "uma espiga de milho crua", "keeps": 4.0, "raw": true},
	"milho_assado": {"food": 15.0, "warmth": 6.0, "eat": "uma espiga assada, ainda quente", "keeps": 2.0},
}
## O que a comida vira quando estraga: só serve para jogar fora.
const SPOILED := "estragada"
## No frio (Longa Escuridão ou terras geladas), a comida estraga na metade da velocidade.
const COLD_SPOIL := 0.5
## Na bolsa, avisa que está passando quando falta menos que isto (dias) para estragar.
const SPOILING_SOON := 0.5
## Crua demais: cada raiz crua soma 1 a "raw", que cai RAW_DECAY por dia. Com
## RAW_LIMIT ou mais, a próxima enjoa: tira RAW_SICK de fome em vez de saciar.
const RAW_LIMIT := 3.0
const RAW_DECAY := 6.0
const RAW_SICK := 10.0
## Raízes: só saem de uma rama (Plants), com a enxada empunhada (J). Cada
## rama pede ROOT_DIG_HITS golpes e dá ROOT_AMOUNT raízes (uma só na Longa
## Escuridão); depois some e rebrota (Harvest.SOURCES).
const ROOT_DIG_HITS := 3
const ROOT_AMOUNT := 2
## Castanhas: só no Declínio, no chão embaixo de parte das árvores
## (NUT_TREES), NUT_AMOUNT por árvore, uma vez por ano.
const NUT_SEASON := 1
const NUT_TREES := 0.4
const NUT_AMOUNT := 3
## Assar: a até ROAST_REACH casas de uma fogueira acesa, a raiz crua vira assada.
const ROAST_REACH := 2.5
const ROASTS := {"raiz": "raiz_assada", "milho": "milho_assado"}  # a raiz vale para toda espécie

## Frases dos limiares, faladas só ao piorar. [fome, calor] por nível 1 a 3.
const HUNGER_LINES := [
	"A fome começa a pesar.",
	"A fome aperta. Suas pernas ficam lentas.",
	"A fome escurece a vista. Coma, ou você vai desfalecer.",
]
const COLD_LINES := [
	"O frio começa a entrar.",
	"O frio entra nos ossos. Você treme e anda devagar.",
	"Você mal sente as mãos. Procure fogo, ou vai desfalecer.",
]


## Uma reserva nova, cheia.
static func fresh() -> Dictionary:
	return {"food": START, "warmth": START}


## 0 (bem), 1 (abaixo de 50), 2 (abatido, abaixo de 25) ou 3 (vazio).
static func level_of(value: float) -> int:
	var level := 0
	for i in LEVELS.size():
		var limit: float = LEVELS[i]
		if (value <= limit) if limit <= 0.0 else (value < limit):
			level = i + 1
	return level


## Posição na barra sonora: 0 (acima de 80) a 5 (vazia). Em 80 já é a 1.
static func bar_step(value: float) -> int:
	var step := 0
	for mark: float in BAR_MARKS:
		if value <= mark:
			step += 1
	return step


## Onde o toque da barra soa no estéreo: 1 à direita (cheia), -1 à esquerda (vazia).
static func bar_pan(step: int) -> float:
	return 1.0 - 2.0 * float(clampi(step, 0, BAR_MARKS.size())) / float(BAR_MARKS.size())


## Abatido por qualquer das reservas?
static func is_weak(entry: Dictionary) -> bool:
	return level_of(float(entry.get("food", MAX))) >= 2 or level_of(float(entry.get("warmth", MAX))) >= 2


static func speed_factor(entry: Dictionary) -> float:
	return WEAK_SPEED if is_weak(entry) else 1.0


static func work_factor(entry: Dictionary) -> float:
	return WEAK_WORK if is_weak(entry) else 1.0


static func is_food(item: String) -> bool:
	return not food_info(item).is_empty()


## A linha de FOODS deste item: a dele, ou a do grupo (frutas_amora -> frutas).
static func food_info(item: String) -> Dictionary:
	return FOODS.get(item, FOODS.get(Economy.base_of(item), {}))


## No que este item vira ao assar ("" se não assa).
static func roast_of(item: String) -> String:
	return str(ROASTS.get(item, ROASTS.get(Economy.base_of(item), "")))


## Como se diz ao comer: "uma fruta", "uma amora", "um cará cru".
static func eat_text(item: String) -> String:
	var info := food_info(item)
	if Economy.base_of(item) == item and info.has("eat"):
		return str(info["eat"])
	var feminine := Economy.is_feminine(item)
	var text := ("uma " if feminine else "um ") + str(Economy.names_of(item)[0])
	if bool(info.get("raw", false)):
		text += " crua" if feminine else " cru"
	return text


## Pontos de fome perdidos por segundo de verdade.
static func hunger_rate(season: int, day_seconds: float, species := "") -> float:
	var days: float = HUNGER_DAYS[clampi(season, 0, 3)]
	return MAX / (days * day_seconds) * Species.effect(species, "hunger")


## Em quantos dias o calor cheio acaba, sem fogo nem abrigo (0 = não esfria).
static func cold_days(season: int, night: bool, biome: int) -> float:
	var days: float = COLD_DAYS[clampi(season, 0, 3)][1 if night else 0]
	if COLD_BIOMES.has(biome):
		var icy := COLD_BIOME_WINTER_DAYS if season == 2 else COLD_BIOME_DAYS
		days = icy if days <= 0.0 else minf(days, icy)
	return days


## Um passo do corpo. "ctx" diz onde a criatura está:
##   season (0-3), night (bool), biome (WorldGen.Biome), fire (fogueira perto),
##   shelter (dentro de um abrigo pronto), torch (tocha acesa), wet (molhado),
##   species, day_seconds.
## Muda "entry" no lugar e devolve os níveis {food, warmth} depois do passo.
static func step(entry: Dictionary, seconds: float, ctx: Dictionary) -> Dictionary:
	var day_seconds := float(ctx.get("day_seconds", DayCycle.DEFAULT_SECONDS))
	var season := int(ctx.get("season", 0))
	var species := str(ctx.get("species", ""))
	var food := float(entry.get("food", START))
	food -= hunger_rate(season, day_seconds, species) * seconds
	var warmth := float(entry.get("warmth", START))
	if bool(ctx.get("fire", false)):
		warmth += MAX / (FIRE_DAYS * day_seconds) * Species.effect(species, "fire_warm") * seconds
	elif bool(ctx.get("shelter", false)):
		warmth += MAX / (SHELTER_DAYS * day_seconds) * seconds
	else:
		var days := cold_days(season, bool(ctx.get("night", false)), int(ctx.get("biome", -1)))
		if days > 0.0:
			var loss := MAX / (days * day_seconds) * Species.effect(species, "cold")
			if bool(ctx.get("torch", false)):
				loss *= TORCH_FACTOR
			if bool(ctx.get("wet", false)):
				loss *= WET_FACTOR
			warmth -= loss * seconds
	entry["food"] = clampf(food, 0.0, MAX)
	entry["warmth"] = clampf(warmth, 0.0, MAX)
	return {"food": level_of(entry["food"]), "warmth": level_of(entry["warmth"])}


## Esforço (golpe, batida): um pouco mais de fome.
static func exert(entry: Dictionary, times := 1) -> void:
	entry["food"] = clampf(float(entry.get("food", START)) - EFFORT * times, 0.0, MAX)


## Come um item. Devolve "" se não for comida, "comeu" ou "enjoou" (crua
## demais: em vez de saciar, tira RAW_SICK de fome).
static func eat(entry: Dictionary, item: String) -> String:
	var food := food_info(item)
	if food.is_empty():
		return ""
	if bool(food.get("raw", false)):
		var raw := float(entry.get("raw", 0.0))
		entry["raw"] = raw + 1.0
		if raw >= RAW_LIMIT:
			entry["food"] = clampf(float(entry.get("food", START)) - RAW_SICK, 0.0, MAX)
			return "enjoou"
	entry["food"] = clampf(float(entry.get("food", START)) + float(food["food"]), 0.0, MAX)
	entry["warmth"] = clampf(float(entry.get("warmth", START)) + float(food["warmth"]), 0.0, MAX)
	return "comeu"


## O enjoo da comida crua passa com o tempo.
static func settle_raw(entry: Dictionary, days: float) -> void:
	if entry.has("raw"):
		entry["raw"] = maxf(0.0, float(entry["raw"]) - RAW_DECAY * days)
		if float(entry["raw"]) <= 0.0:
			entry.erase("raw")


# --- Estrago --------------------------------------------------------------------
# Cada comida da bolsa tem lotes, do mais velho ao mais novo: [quantidade, dias
# que ainda faltam]. A bolsa continua sendo item -> quantidade; os lotes andam
# junto (reconcile) e o que entra de novo começa fresco. Comer gasta do mais
# velho; o que sai de outro jeito (jogar, perder) sai do mais novo, para jogar e
# pegar de volta não refrescar nada.

static func keeps(item: String) -> float:
	return float(food_info(item).get("keeps", 0.0))


## Acerta os lotes com o que a bolsa tem de fato.
static func reconcile(lots: Dictionary, inv: Dictionary) -> void:
	for item: String in lots.keys():
		if int(inv.get(item, 0)) <= 0 or keeps(item) <= 0.0:
			lots.erase(item)
	for item: String in inv:
		if keeps(item) <= 0.0:
			continue
		var list: Array = lots.get(item, [])
		var have := 0
		for lot: Array in list:
			have += int(lot[0])
		var want := int(inv[item])
		if want > have:
			list.append([want - have, keeps(item)])
		while want < have and not list.is_empty():
			var last: Array = list[-1]
			var cut := mini(have - want, int(last[0]))
			last[0] = int(last[0]) - cut
			have -= cut
			if int(last[0]) <= 0:
				list.pop_back()
		lots[item] = list


## Tira "amount" do lote mais velho (ao comer).
static func take_oldest(lots: Dictionary, item: String, amount := 1) -> void:
	var list: Array = lots.get(item, [])
	while amount > 0 and not list.is_empty():
		var cut := mini(amount, int(list[0][0]))
		list[0][0] = int(list[0][0]) - cut
		amount -= cut
		if int(list[0][0]) <= 0:
			list.pop_front()


## Passa o tempo nos lotes ("days" de jogo, já com o fator do frio). O que
## estraga sai da bolsa e vira SPOILED. Devolve item -> quantidade estragada.
static func age(lots: Dictionary, inv: Dictionary, days: float) -> Dictionary:
	reconcile(lots, inv)
	var spoiled := {}
	for item: String in lots.keys():
		var list: Array = lots[item]
		for lot: Array in list:
			lot[1] = float(lot[1]) - days
		while not list.is_empty() and float(list[0][1]) <= 0.0:
			var gone := int(list[0][0])
			list.pop_front()
			spoiled[item] = int(spoiled.get(item, 0)) + gone
			inv[item] = int(inv.get(item, 0)) - gone
			if int(inv[item]) <= 0:
				inv.erase(item)
			inv[SPOILED] = int(inv.get(SPOILED, 0)) + gone
		if list.is_empty():
			lots.erase(item)
	return spoiled


## Quantas de cada comida estão para passar (item -> quantidade), para a Bolsa.
static func spoiling_soon(lots: Dictionary) -> Dictionary:
	var out := {}
	for item: String in lots:
		for lot: Array in lots[item]:
			if float(lot[1]) < SPOILING_SOON:
				out[item] = int(out.get(item, 0)) + int(lot[0])
	return out


## Fator do estrago: no frio, mais devagar.
static func spoil_factor(season: int, biome: int) -> float:
	return COLD_SPOIL if season == 2 or COLD_BIOMES.has(biome) else 1.0


## Esta árvore dá castanhas? (Parte delas, fixo pela casa.)
static func nut_tree(cell: Vector2i) -> bool:
	return float(posmod(hash(cell * 7919), 1000)) / 1000.0 < NUT_TREES


## Está cheio demais para comer isto? (Não se come de barriga cheia.)
static func is_full(entry: Dictionary, item: String) -> bool:
	return float(entry.get("food", START)) + float(food_info(item).get("food", 0.0)) * 0.5 > MAX


## A frase de quando uma reserva piora até "level" (1-3); "" no nível 0.
static func line(kind: String, level: int) -> String:
	if level <= 0:
		return ""
	var lines: Array = HUNGER_LINES if kind == "food" else COLD_LINES
	return lines[clampi(level - 1, 0, lines.size() - 1)]


## Terceiro toque do C: "Você está com fome e com frio." ou "Você está
## saciado e aquecido."
static func status_text(entry: Dictionary) -> String:
	var hunger: Array[String] = ["saciado", "com um pouco de fome", "com fome", "faminto"]
	var cold: Array[String] = ["aquecido", "com um pouco de frio", "com frio", "gelado"]
	return "Você está %s e %s." % [hunger[level_of(float(entry.get("food", MAX)))], cold[level_of(float(entry.get("warmth", MAX)))]]
