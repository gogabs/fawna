class_name RideSteer
extends RefCounted
## Rédea sozinha do cavalo montado (ver game.gd, _steer): quanto caminho livre
## há numa direção e para onde segue uma trilha cercada de mata, bambuzal ou
## água. Só geometria, para dar para testar sem a cena.

const STEP := PI / 18.0  # 10°
const TRAIL_AHEAD := [1.2, 3.0]  # casas: os dois pontos que têm de cair na trilha
const TRAIL_TRIES := 7  # até 70° para cada lado
const TRAIL_GAP := PI / 6.0  # a trilha tem de seguir a até 30° da frente: virou para sair dela, a rédea solta
const TRAIL_WATER := [WorldGen.Thing.LAGO, WorldGen.Thing.RIO, WorldGen.Thing.MAR, WorldGen.Thing.CHARCO, WorldGen.Thing.RIACHO, WorldGen.Thing.VAU]


## Quanto dá para andar de "pos" em linha reta na direção "dir", até "look"
## casas, conferindo a cada quarto de casa com "can_stand" (Vector2 -> bool).
static func clearance(pos: Vector2, dir: Vector2, look: float, can_stand: Callable) -> float:
	var d := 0.25
	while d <= look:
		if not can_stand.call(pos + dir * d):
			return d - 0.25
		d += 0.25
	return look


## Numa trilha cercada: para onde ela segue a partir de "pos", em relação ao
## ângulo "base" (rad, horário a partir do norte), ou NAN.
static func trail_offset(world: WorldGen, pos: Vector2, base: float) -> float:
	var cell := WorldGen.cell_of(pos)
	if not world.is_trail(cell) or not enclosed(world, cell):
		return NAN
	var run := []
	var runs := []
	for k in range(-TRAIL_TRIES, TRAIL_TRIES + 1):
		var off := STEP * k
		var dir := Vector2(sin(base + off), -cos(base + off))
		var on := true
		for d: float in TRAIL_AHEAD:
			if not world.is_trail(WorldGen.cell_of(pos + dir * d)):
				on = false
				break
		if on:
			run.append(off)
		elif not run.is_empty():
			runs.append(run)
			run = []
	if not run.is_empty():
		runs.append(run)
	# O trecho de direções na trilha mais perto da frente; segue pelo meio dele.
	var best := NAN
	var best_gap := INF
	for r: Array in runs:
		var gap := 0.0 if float(r[0]) <= 0.0 and float(r[-1]) >= 0.0 else minf(absf(r[0]), absf(r[-1]))
		if gap < best_gap:
			best_gap = gap
			best = (float(r[0]) + float(r[-1])) * 0.5
	return best if best_gap <= TRAIL_GAP else NAN


## Trilha cercada: na mata, no bambuzal ou com água a até 3 casas.
static func enclosed(world: WorldGen, cell: Vector2i) -> bool:
	if world.is_forest(cell) or world.biome_at(cell) == WorldGen.Biome.BAMBUZAL:
		return true
	for y in range(-3, 4):
		for x in range(-3, 4):
			if world.thing_at(cell + Vector2i(x, y)) in TRAIL_WATER:
				return true
	return false
