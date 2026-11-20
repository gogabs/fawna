class_name DayCycle
extends RefCounted
## O ciclo de dia e noite do mundo. A hora é uma fração do dia, "t", de 0 a 1:
## 0 é a meia-noite, 0,5 é o meio-dia. O servidor guarda e conta o tempo; os
## clientes só andam junto, com ajustes de tempos em tempos.
##
## Um dia inteiro dura DEFAULT_SECONDS segundos de verdade (30 minutos): cada
## hora do jogo dura 75 s. A noite fica com quase 12 minutos, tempo de sobra
## para o Calado aparecer e para dar uma sensação de noite longa, e o dia com
## uns 14. Para mexer na duração, o servidor aceita --dia=SEGUNDOS.

const DEFAULT_SECONDS := 1800.0
## Hora em que um mundo novo começa (de manhã, sem pressa).
const START_HOUR := 8.0

## Horas do jogo em que cada período começa.
const DAWN_HOUR := 5.0  # amanhecer: 5h às 7h
const DAY_HOUR := 7.0
const DUSK_HOUR := 18.0  # entardecer: 18h às 20h
const NIGHT_HOUR := 20.0  # noite: 20h às 5h

enum Phase { NIGHT, DAWN, DAY, DUSK }


static func hour_to_t(hour: float) -> float:
	return fposmod(hour, 24.0) / 24.0


static func hour_of(t: float) -> float:
	return fposmod(t, 1.0) * 24.0


## O período do dia.
static func phase_of(t: float) -> int:
	var hour := hour_of(t)
	if hour >= NIGHT_HOUR or hour < DAWN_HOUR:
		return Phase.NIGHT
	if hour < DAY_HOUR:
		return Phase.DAWN
	if hour < DUSK_HOUR:
		return Phase.DAY
	return Phase.DUSK


## O Calado só ronda de noite (das 20h às 5h).
static func is_night(t: float) -> bool:
	return phase_of(t) == Phase.NIGHT


## Quão escuro está: 0 em pleno dia, 1 em plena noite; sobe no entardecer e
## desce no amanhecer, suavemente.
static func darkness(t: float) -> float:
	var hour := hour_of(t)
	var x := 0.0
	if hour >= NIGHT_HOUR or hour < DAWN_HOUR:
		x = 1.0
	elif hour < DAY_HOUR:
		x = 1.0 - (hour - DAWN_HOUR) / (DAY_HOUR - DAWN_HOUR)
	elif hour >= DUSK_HOUR:
		x = (hour - DUSK_HOUR) / (NIGHT_HOUR - DUSK_HOUR)
	return x * x * (3.0 - 2.0 * x)


## Quanto tempo falta (em segundos de verdade) para o período mudar.
static func seconds_to_next_phase(t: float, day_seconds: float) -> float:
	var hour := hour_of(t)
	var next := 0.0
	match phase_of(t):
		Phase.NIGHT:
			next = DAWN_HOUR if hour < DAWN_HOUR else DAWN_HOUR + 24.0
		Phase.DAWN:
			next = DAY_HOUR
		Phase.DAY:
			next = DUSK_HOUR
		Phase.DUSK:
			next = NIGHT_HOUR
	return (next - hour) / 24.0 * day_seconds


## Os períodos que o jogador ouve, só pelo nome e por um texto: [nome, hora em
## que começa, texto]. Não mexem em nada da simulação (isso é das Phase, acima),
## só dão cor ao aviso de cada virada e à resposta de "que horas são". Em ordem
## de hora, começando à meia-noite.
const PERIODS := [
	["Noite profunda", 0.0, "O silêncio pesa, e só o que não dorme se mexe."],
	["Amanhecer", 5.0, "A névoa sobe do chão, e uma luz fria toca o horizonte."],
	["Manhã", 7.0, "O ar esquenta e o mundo respira sem pressa."],
	["Meio-dia", 12.0, "O sol a pino encolhe as sombras. Tudo parece quieto demais."],
	["Tarde", 14.0, "A luz desce amarelada e o vento troca de lado."],
	["Fim de tarde", 18.0, "As sombras se alongam e a luz esfria, dourada."],
	["Anoitecer", 19.0, "O sol some no horizonte, e a escuridão toma o chão."],
	["Noite", 20.0, "O mundo fecha os olhos, e o que ronda no escuro desperta."],
]


## Índice do período em PERIODS.
static func period_of(t: float) -> int:
	var hour := hour_of(t)
	var found := 0
	for i in PERIODS.size():
		if hour >= float(PERIODS[i][1]):
			found = i
	return found


## O aviso falado quando o período muda.
static func announcement(period: int) -> String:
	return "%s. %s" % [PERIODS[period][0], PERIODS[period][2]]


## Segundos de verdade até o próximo período.
static func seconds_to_next_period(t: float, day_seconds: float) -> float:
	var hour := hour_of(t)
	var next_index := (period_of(t) + 1) % PERIODS.size()
	var next: float = PERIODS[next_index][1]
	if next <= hour:
		next += 24.0
	return (next - hour) / 24.0 * day_seconds


## A resposta de "que horas são": o período e o texto dele, sem hora numérica
## nem tempo restante.
static func describe(t: float) -> String:
	return announcement(period_of(t))


## Momentos relevantes para a depuração: [chave, rótulo, hora do jogo, chegar
## antes (true) ou exatamente nela (false)]. Os que chegam antes caem
## JUMP_LEAD segundos de verdade antes do momento, para dar para ouvir a
## virada. "grilos" é a hora em que eles passam a ser audíveis; o Calado só
## aparece de 1 a 2,5 minutos depois do começo da noite (se a criatura estiver
## exposta), então "noite" já serve para esperar por ele.
const JUMP_LEAD := 8.0
const MOMENTS := [
	["meio_dia", "Meio-dia", 12.0, false],
	["entardecer", "Entardecer (18h)", DUSK_HOUR, true],
	["grilos", "Grilos audíveis", 18.5, true],
	["noite", "Começo da noite, Calado possível", NIGHT_HOUR, true],
	["meia_noite", "Meia-noite", 0.0, false],
	["coro", "Coro do amanhecer (5h)", DAWN_HOUR, true],
	["dia", "Dia claro (7h)", DAY_HOUR, true],
]


## A hora (0 a 24) de um dos MOMENTS, ou -1 se a chave não existe.
static func moment_hour(key: String, day_seconds: float) -> float:
	for moment in MOMENTS:
		if moment[0] == key:
			var hour: float = moment[2]
			if moment[3]:
				hour -= JUMP_LEAD / day_seconds * 24.0
			return fposmod(hour, 24.0)
	return -1.0


static func moment_label(key: String) -> String:
	for moment in MOMENTS:
		if moment[0] == key:
			return moment[1]
	return ""
