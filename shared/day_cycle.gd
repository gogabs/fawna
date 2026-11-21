class_name DayCycle
extends RefCounted
## O ciclo de dia e noite do mundo, as estações e o anel. A hora é uma fração
## do dia, "t", de 0 a 1: 0 é a meia-noite, 0,5 é o meio-dia. Os dias inteiros
## são contados à parte ("days"), e juntos formam o "dia do mundo" d = days + t,
## de onde saem as estações e a posição do anel. O servidor guarda e conta o
## tempo; os clientes só andam junto, com ajustes de tempos em tempos.
##
## Um dia inteiro dura DEFAULT_SECONDS segundos de verdade (30 minutos): cada
## hora do jogo dura 75 s. Para mexer na duração, o servidor aceita --dia=SEGUNDOS.
##
## O anel: um anel no céu que desenha faixas (listras de leste a oeste) de
## sombra de dia e de luz refletida de noite. É só uma função do lugar
## (a coordenada norte-sul) e do dia do mundo, sem nada guardado no mapa, então
## vale num mundo infinito: as faixas se repetem a cada RING_SPACING metros e
## todas vão e vêm juntas, norte e sul, ao longo do ano (YEAR_DAYS dias do
## jogo, ou 3 dias reais). O ano tem quatro estações; a noite fica mais curta
## na Coroada e mais longa na Longa Escuridão.

const DEFAULT_SECONDS := 1800.0
## Hora em que um mundo novo começa (de manhã, sem pressa), e o dia do mundo
## (já com a faixa do anel longe de onde se nasce).
const START_HOUR := 8.0
const START_DAY := 6

## Quanto o ano e a faixa do anel valem, em dias do jogo e em metros.
const YEAR_DAYS := 144.0
const SEASON_DAYS := 36.0
const RING_SPACING := 2880.0  # de uma faixa à seguinte
const RING_TRAVEL := 1440.0  # o quanto cada faixa anda para cada lado
const RING_WIDTH := 500.0  # largura da parte clara ou sombria
## A noite encolhe ou estica até essa metade de hora de cada lado, com a estação.
const SHIFT_MAX := 0.5
## O Calado leva até 20% mais ou menos tempo para aparecer, com a estação.
const CALADO_SEASON_SWING := 0.2
## Quanto o anel escurece o dia sob a sombra dele (0 a 1).
const SHADOW_DARKNESS := 0.45

enum Phase { NIGHT, DAWN, DAY, DUSK }

## Quanto a estação alonga (+) ou encolhe (-) a noite, em horas. Quem anda com o
## relógio (o nó Daytime) atualiza a cada quadro; os testes deixam em 0.
static var shift_hours := 0.0


## Horas do jogo em que cada período começa: o amanhecer, o dia, o entardecer
## e a noite. Com shift_hours em 0: 5h, 7h, 18h e 20h.
static func dawn_hour() -> float:
	return 5.0 - shift_hours


static func day_hour() -> float:
	return 7.0 - shift_hours


static func dusk_hour() -> float:
	return 18.0 + shift_hours


static func night_hour() -> float:
	return 20.0 + shift_hours


static func hour_to_t(hour: float) -> float:
	return fposmod(hour, 24.0) / 24.0


static func hour_of(t: float) -> float:
	return fposmod(t, 1.0) * 24.0


## O período do dia.
static func phase_of(t: float) -> int:
	var hour := hour_of(t)
	if hour >= night_hour() or hour < dawn_hour():
		return Phase.NIGHT
	if hour < day_hour():
		return Phase.DAWN
	if hour < dusk_hour():
		return Phase.DAY
	return Phase.DUSK


## O Calado só ronda de noite (das 20h às 5h, mais ou menos, com a estação).
static func is_night(t: float) -> bool:
	return phase_of(t) == Phase.NIGHT


## Quão escuro está: 0 em pleno dia, 1 em plena noite; sobe no entardecer e
## desce no amanhecer, suavemente.
static func darkness(t: float) -> float:
	var hour := hour_of(t)
	var x := 0.0
	if hour >= night_hour() or hour < dawn_hour():
		x = 1.0
	elif hour < day_hour():
		x = 1.0 - (hour - dawn_hour()) / (day_hour() - dawn_hour())
	elif hour >= dusk_hour():
		x = (hour - dusk_hour()) / (night_hour() - dusk_hour())
	return x * x * (3.0 - 2.0 * x)


## O escuro onde a criatura está: sob a sombra do anel (strength de 0 a 1),
## o dia escurece um pouco, sem passar do escuro da noite.
static func darkness_with_ring(t: float, ring: float) -> float:
	var base := darkness(t)
	return maxf(base, SHADOW_DARKNESS * ring * (1.0 - base))


## Quanto tempo falta (em segundos de verdade) para o período mudar.
static func seconds_to_next_phase(t: float, day_seconds: float) -> float:
	var hour := hour_of(t)
	var next := 0.0
	match phase_of(t):
		Phase.NIGHT:
			next = dawn_hour() if hour < dawn_hour() else dawn_hour() + 24.0
		Phase.DAWN:
			next = day_hour()
		Phase.DAY:
			next = dusk_hour()
		Phase.DUSK:
			next = night_hour()
	return (next - hour) / 24.0 * day_seconds


# --- O anel e as estações --------------------------------------------------------

## O dia do mundo: dias inteiros mais a fração do dia.
static func world_day(days: int, t: float) -> float:
	return float(days) + fposmod(t, 1.0)


## Onde está o centro de uma faixa, em metros ao longo do eixo norte-sul (o norte é
## o y negativo). No começo do ano o centro está em 0, sobe até o extremo norte,
## volta, desce até o extremo sul e volta, como o sol entre os solstícios.
static func ring_center(d: float) -> float:
	return -RING_TRAVEL * sin(TAU * d / YEAR_DAYS)


## De "y" (metros) até o centro da faixa mais próxima, com sinal: negativo quer
## dizer que ela está ao norte.
static func ring_offset(y: float, d: float) -> float:
	var rel := y - ring_center(d)
	return -(fposmod(rel + RING_SPACING * 0.5, RING_SPACING) - RING_SPACING * 0.5)


## Quanto a faixa do anel pega este y: 1 no miolo, 0 fora, suave nas bordas.
static func ring_strength(y: float, d: float) -> float:
	var half := RING_WIDTH * 0.5
	var x := clampf((absf(ring_offset(y, d)) - half * 0.5) / (half * 0.5), 0.0, 1.0)
	return 1.0 - x * x * (3.0 - 2.0 * x)


## Estações: [nome, o que vem depois de "Estação " no C e na depuração, frase do aviso].
## 0 Coroada (faixa no extremo norte, noites curtas), 1 Declínio (desce para o sul),
## 2 Longa Escuridão (extremo sul, noites longas), 3 Ressurgência (volta ao norte).
## Cada uma centrada no seu ponto do ano.
const SEASONS := [
	["Coroada", "Coroada", "O anel alcança seu ápice, e as noites se encurtam."],
	["Declínio", "do Declínio", "O anel declina para o sul, e luz e sombra mudam de lugar."],
	["Longa Escuridão", "da Longa Escuridão", "As noites se alongam e o frio dói nos ossos."],
	["Ressurgência", "da Ressurgência", "O anel retorna ao norte, trazendo com ele a vitalidade do mundo."],
]


## O aviso falado na virada da estação: "Estação do Declínio. O anel declina...".
static func season_announcement(season: int) -> String:
	return "Estação %s. %s" % [SEASONS[season][1], SEASONS[season][2]]


static func season_of(d: float) -> int:
	return int(floor(fposmod(d - SEASON_DAYS * 0.5, YEAR_DAYS) / SEASON_DAYS)) % 4


## Quanto a noite encolhe (+, Coroada) ou estica (-, Longa Escuridão): muda aos
## poucos, sem saltos.
static func season_shift(d: float) -> float:
	return SHIFT_MAX * cos(TAU * (d - SEASON_DAYS) / YEAR_DAYS)


## O ritmo com que o Calado se aproxima de aparecer: 0,8 no Coroada (noite
## curta, ele demora mais), 1,2 no Longa Escuridão.
static func calado_rate(d: float) -> float:
	return 1.0 + CALADO_SEASON_SWING * cos(TAU * (d - 3.0 * SEASON_DAYS) / YEAR_DAYS)


# --- Períodos e textos -------------------------------------------------------------

## Os períodos que o jogador ouve: [nome, "é ..." (o que o C diz), texto normal,
## texto dentro da faixa do anel (igual ao normal onde só há uma frase)]. Os de 1 a 6 são de dia (a faixa é de sombra);
## o 0 e o 7, de noite (a faixa é de luz). Não mexem na simulação, só dão cor ao
## aviso de cada virada e ao T.
const PERIODS := [
	["Noite profunda", "a noite profunda", "O silêncio pesa, e só o que não dorme se mexe.", "A luz do anel banha quem vagueia pela noite profunda."],
	["Amanhecer", "o amanhecer", "A névoa sobe do chão, e uma luz fria toca o horizonte, sob o arco pálido do anel.", "A luz tênue brilha no orvalho sob a sombra do anel."],
	["Manhã", "a manhã", "A manhã esquenta devagar, e o mundo respira sem pressa.", "A manhã nasce fria sob a sombra do anel."],
	["Meio-dia", "o meio-dia", "O sol a pino encolhe as sombras, e tudo parece quieto demais.", "A calmaria se instala no meio-dia crepuscular."],
	["Tarde", "a tarde", "A tarde desce amarelada, e o vento troca de lado.", "Um vento cortante varre a terra na penumbra."],
	["Fim de tarde", "o fim de tarde", "As sombras se alongam enquanto a tarde se vai sob a coroa dourada no céu.", "O fim de tarde chega antes da hora, e a sombra lentamente devora o que resta de luz."],
	["Anoitecer", "o anoitecer", "O sol some no horizonte, e a escuridão toma o chão.", "O sol some no horizonte, e a escuridão toma o chão."],
	["Noite", "a noite", "A noite fecha os olhos do mundo, e a escuridão parece respirar.", "A noite chega, e o anel derrama no chão uma luz fria que não conforta."],
]


## Hora do jogo em que o período começa (acompanha a estação).
static func period_start(period: int) -> float:
	match period:
		0:
			return 0.0
		1:
			return dawn_hour()
		2:
			return day_hour()
		3:
			return 12.0
		4:
			return 14.0
		5:
			return dusk_hour()
		6:
			return dusk_hour() + 1.0
	return night_hour()


## Índice do período em PERIODS.
static func period_of(t: float) -> int:
	var hour := hour_of(t)
	var found := 0
	for i in PERIODS.size():
		if hour >= period_start(i):
			found = i
	return found


## O período é de noite (a faixa do anel é de luz)?
static func is_night_period(period: int) -> bool:
	return period == 0 or period == 7


## O aviso falado quando o período muda; "in_ring" quando se está na faixa.
static func announcement(period: int, in_ring := false) -> String:
	return "%s. %s" % [PERIODS[period][0], PERIODS[period][3] if in_ring else PERIODS[period][2]]


## Segundos de verdade até o próximo período.
static func seconds_to_next_period(t: float, day_seconds: float) -> float:
	var hour := hour_of(t)
	var next_index := (period_of(t) + 1) % PERIODS.size()
	var next := period_start(next_index)
	if next <= hour:
		next += 24.0
	return (next - hour) / 24.0 * day_seconds


## A segunda fala do C: o momento do dia, o anel onde se está e a estação.
## "strength" é ring_strength e "offset" é ring_offset, no y da criatura.
static func sky_text(t: float, strength: float, offset: float, season: int) -> String:
	var period := period_of(t)
	var night := is_night_period(period)
	var text := "É %s" % PERIODS[period][1]
	if strength >= 0.5:
		text += ", sob a luz do anel." if night else ", sob a sombra do anel."
	elif absf(offset) <= RING_WIDTH * 1.5:
		var side := "ao norte" if offset < 0.0 else "ao sul"
		text += (", e a luz do anel passa logo %s." if night else ", e a sombra do anel passa logo %s.") % side
	else:
		text += ", e o anel brilha, frio, ao longe." if night else ", e o anel corta o céu, pálido."
	return "%s Estação %s." % [text, SEASONS[season][1]]


## O aviso de entrar ou sair da faixa do anel.
static func ring_edge_text(night: bool, entering: bool) -> String:
	if night:
		return "A luz do anel alcança você." if entering else "A luz do anel fica para trás."
	return "Uma sombra fria do anel cai sobre você." if entering else "Você sai da sombra do anel."


# --- Momentos para a depuração -----------------------------------------------------

## Momentos relevantes: [chave, rótulo, chegar antes (true) ou exatamente nele (false)].
## Os que chegam antes caem JUMP_LEAD segundos de verdade antes do momento, para
## dar para ouvir a virada. "grilos" é a hora em que eles passam a ser audíveis; o
## Calado só aparece de 1 a 2,5 minutos depois do começo da noite (se a criatura
## estiver exposta), então "noite" já serve para esperar por ele.
const JUMP_LEAD := 8.0
const MOMENTS := [
	["meio_dia", "Meio-dia", false],
	["entardecer", "Começo do fim de tarde", true],
	["grilos", "Grilos audíveis", true],
	["noite", "Começo da noite, Calado possível", true],
	["meia_noite", "Meia-noite", false],
	["coro", "Coro do amanhecer", true],
	["dia", "Dia claro", true],
]


static func _moment_base(key: String) -> float:
	match key:
		"meio_dia":
			return 12.0
		"entardecer":
			return dusk_hour()
		"grilos":
			return dusk_hour() + 0.5
		"noite":
			return night_hour()
		"meia_noite":
			return 0.0
		"coro":
			return dawn_hour()
		"dia":
			return day_hour()
	return -1.0


## A hora (0 a 24) de um dos MOMENTS, ou -1 se a chave não existe.
static func moment_hour(key: String, day_seconds: float) -> float:
	for moment in MOMENTS:
		if moment[0] == key:
			var hour := _moment_base(key)
			if moment[2]:
				hour -= JUMP_LEAD / day_seconds * 24.0
			return fposmod(hour, 24.0)
	return -1.0


static func moment_label(key: String) -> String:
	for moment in MOMENTS:
		if moment[0] == key:
			return moment[1]
	return ""


## O dia do mundo em que a estação "season" (0 a 3) começa, no primeiro ano.
static func season_start_day(season: int) -> float:
	return SEASON_DAYS * (season + 0.5)
