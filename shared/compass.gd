class_name Compass
extends RefCounted
## Direções da criatura em primeira pessoa.
##
## A criatura olha para uma de 8 direções (giros de 45°): 0 é norte, e os
## números crescem no sentido horário (1 nordeste, 2 leste...). Norte é y
## negativo no mundo.

const STEPS := 8

const NAMES := ["norte", "nordeste", "leste", "sudeste", "sul", "sudoeste", "oeste", "noroeste"]

## Onde algo está em relação a quem olha, em 8 setores.
const RELATIVE := [
	"à frente", "à frente e à direita", "à direita", "atrás e à direita",
	"atrás", "atrás e à esquerda", "à esquerda", "à frente e à esquerda",
]


static func angle(heading: int) -> float:
	return posmod(heading, STEPS) * TAU / STEPS


static func forward(heading: int) -> Vector2:
	var a := angle(heading)
	return Vector2(sin(a), -cos(a))


static func right(heading: int) -> Vector2:
	return forward(heading + 2)


static func name_of(heading: int) -> String:
	return NAMES[posmod(heading, STEPS)]


## Direção de bússola (0 norte, horário) mais próxima de um deslocamento.
static func bearing(offset: Vector2) -> float:
	return atan2(offset.x, -offset.y)


## Ex.: algo 2 casas à frente e 2 à direita de quem olha para o norte ->
## "à frente e à direita".
static func relative(offset: Vector2, heading: int) -> String:
	var rel := wrapf(bearing(offset) - angle(heading), 0.0, TAU)
	return RELATIVE[posmod(roundi(rel / (TAU / STEPS)), STEPS)]


## Distância em casas -> "3 metros".
static func meters(distance_cells: float) -> String:
	var m := roundi(distance_cells * WorldGen.METERS_PER_CELL)
	if m <= 0:
		return "bem pertinho"
	return "1 metro" if m == 1 else "%d metros" % m


## "à frente e à direita, 3 metros"
static func describe(offset: Vector2, heading: int) -> String:
	if offset.length() < 0.35:
		return "bem aqui"
	return "%s, %s" % [relative(offset, heading), meters(offset.length())]
