extends Node
## Testes do rastro de névoa do Caminheiro (TrailView3D): começa colado na
## criatura e as bolhas ficam paradas no mundo enquanto ela anda.
## Rodar: godot --headless --path . res://tests/test_rastro.tscn

var _failures := 0


func _ready() -> void:
	_test_starts_close()
	_test_puffs_stay_put_while_walking()
	_test_base_after_beacon()
	_test_base_resets_on_replan()
	if _failures == 0:
		print("OK: todos os testes passaram")
	get_tree().quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FALHOU: ", message)


func _test_starts_close() -> void:
	var route: Array[Vector2] = [Vector2(20, 0), Vector2(20, 80)]
	var spots := TrailView3D.puff_spots(Vector2.ZERO, route, 20.0)
	var nearest := INF
	for id: int in spots:
		nearest = minf(nearest, (spots[id] as Vector2).length())
	_check(nearest <= TrailView3D.SPACING, "a primeira bolha deveria estar colada (%.2f m)" % nearest)
	_check(TrailView3D.NEAR_FULL <= 1.5, "a névoa deveria aparecer inteira a 1,5 m")
	_check(spots.size() == TrailView3D.PUFFS, "deveria usar todas as bolhas numa rota longa (%d)" % spots.size())


func _test_puffs_stay_put_while_walking() -> void:
	var route: Array[Vector2] = [Vector2(30, 0), Vector2(30, 60)]
	var before := TrailView3D.puff_spots(Vector2.ZERO, route, 30.0)
	var after := TrailView3D.puff_spots(Vector2(2.3, 0), route, 30.0)
	var shared := 0
	for id: int in after:
		if before.has(id):
			shared += 1
			_check((before[id] as Vector2).distance_to(after[id]) < 0.01, "a bolha %d deveria ficar parada ao andar" % id)
	_check(shared > 50, "quase todas as bolhas deveriam continuar (%d)" % shared)


func _test_base_after_beacon() -> void:
	var old: Array[Vector2] = [Vector2(10, 0), Vector2(10, 7), Vector2(20, 7)]
	var new: Array[Vector2] = [Vector2(20, 7)]
	_check(is_equal_approx(TrailView3D.advance_base(old, new, 10.0), 27.0), "deveria somar os trechos passados")
	var grown: Array[Vector2] = [Vector2(10, 0), Vector2(10, 7), Vector2(20, 7), Vector2(20, 30)]
	_check(is_equal_approx(TrailView3D.advance_base(old, grown, 10.0), 10.0), "rota estendida não muda a base")
	# Passar pelo beacon não deve mexer nas bolhas adiante dele.
	var a := TrailView3D.puff_spots(Vector2(10, 6.5), old.slice(1), 17.0)
	var b := TrailView3D.puff_spots(Vector2(10, 7.2), old.slice(2), 27.0)
	for id: int in b:
		if a.has(id) and id * TrailView3D.SPACING > 18.0:
			_check((a[id] as Vector2).distance_to(b[id]) < 0.3, "a bolha %d não deveria pular ao passar do beacon" % id)


func _test_base_resets_on_replan() -> void:
	var old: Array[Vector2] = [Vector2(10, 0), Vector2(10, 7)]
	var new: Array[Vector2] = [Vector2(-5, 3), Vector2(-5, 9)]
	_check(TrailView3D.advance_base(old, new, 40.0) == 0.0, "rota nova recomeça do zero")
