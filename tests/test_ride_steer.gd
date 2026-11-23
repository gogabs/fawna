extends SceneTree
## Testes da rédea sozinha do cavalo montado (RideSteer): caminho livre numa
## direção e seguir sozinho uma trilha cercada de mata, bambuzal ou água.
## Rodar: godot --headless --path . --script res://tests/test_ride_steer.gd

var _failures := 0


func _init() -> void:
	_test_clearance()
	_test_follow_trail(WorldGen.new(42))
	if _failures == 0:
		print("OK: rédea sozinha passou")
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FALHOU: " + message)


func _test_clearance() -> void:
	var wall := func(p: Vector2) -> bool: return p.x < 2.0
	_check(is_equal_approx(RideSteer.clearance(Vector2.ZERO, Vector2.RIGHT, 3.0, wall), 1.75), "para antes da parede")
	_check(is_equal_approx(RideSteer.clearance(Vector2.ZERO, Vector2.UP, 3.0, wall), 3.0), "livre até onde olha")


## Acha trechos de trilha cercada e anda por eles só seguindo trail_offset:
## o cavalo não sai da trilha.
func _test_follow_trail(world: WorldGen) -> void:
	var center := WorldGen.center()
	var starts := []
	for r in range(0, 400, 3):
		for k in 24:
			var cell := center + Vector2i(roundi(cos(k * TAU / 24.0) * r), roundi(sin(k * TAU / 24.0) * r))
			if world.is_trail(cell) and world.thing_at(cell) == WorldGen.Thing.TRILHA and RideSteer.enclosed(world, cell):
				starts.append(cell)
		if starts.size() >= 12:
			break
	_check(starts.size() >= 4, "acha trilhas cercadas para testar (%d)" % starts.size())
	var rides := 0
	var kept := 0
	var steps := 0
	for cell: Vector2i in starts:
		var pos := WorldGen.cell_center(cell)
		for heading in Compass.STEPS:
			var base := Compass.angle(heading)
			if is_nan(RideSteer.trail_offset(world, pos, base)):
				continue
			rides += 1
			var at := pos
			var angle := base
			for i in 60:
				var off := RideSteer.trail_offset(world, at, angle)
				if is_nan(off):
					break  # a trilha acabou ou saiu da mata: a rédea solta
				angle += off
				at += Vector2(sin(angle), -cos(angle)) * 0.25
				steps += 1
				if world.is_trail(WorldGen.cell_of(at)):
					kept += 1
			break
	print("trilhas: %d inícios, %d passeios, %d de %d passos na trilha" % [starts.size(), rides, kept, steps])
	_check(rides >= 4, "trilha com direção para seguir (%d)" % rides)
	_check(steps > 0 and float(kept) / steps >= 0.97, "seguindo a trilha, fica nela (%d de %d passos)" % [kept, steps])
