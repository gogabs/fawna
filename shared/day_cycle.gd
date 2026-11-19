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


static func phase_name(phase: int) -> String:
	match phase:
		Phase.NIGHT:
			return "noite"
		Phase.DAWN:
			return "amanhecer"
		Phase.DAY:
			return "dia"
		_:
			return "entardecer"


## O aviso falado quando o período muda.
static func announcement(phase: int) -> String:
	match phase:
		Phase.NIGHT:
			return "Anoiteceu."
		Phase.DAWN:
			return "Amanhece."
		Phase.DAY:
			return "O dia clareou."
		_:
			return "Entardece."


## A resposta de "que horas são": a hora do jogo e o período, com o tempo que
## falta para ele mudar.
static func describe(t: float, day_seconds: float) -> String:
	var hour := int(floor(hour_of(t)))
	var minutes := int(floor((hour_of(t) - hour) * 60.0))
	var part := ""
	match phase_of(t):
		Phase.NIGHT:
			part = "Madrugada" if hour < DAWN_HOUR else "Noite"
		Phase.DAWN:
			part = "Amanhecendo"
		Phase.DAY:
			part = "Manhã" if hour < 12 else "Tarde"
		Phase.DUSK:
			part = "Entardecendo"
	var left := int(round(seconds_to_next_phase(t, day_seconds) / 60.0))
	var until := "falta menos de um minuto para mudar"
	if left == 1:
		until = "falta cerca de um minuto para mudar"
	elif left > 1:
		until = "faltam uns %d minutos para mudar" % left
	return "%s, %s e %02d minutos; %s." % [part, "1 hora" if hour == 1 else "%d horas" % hour, minutes, until]


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
