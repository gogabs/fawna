extends Node
## Testa os minigames simulando as teclas no tempo certo.
## Rodar (precisa ser uma cena, para os autoloads existirem):
##   godot --headless --path . res://tests/test_minigames.tscn

var _results := {}


func _ready() -> void:
	await _test_carpentry(7, true)
	await _test_carpentry(3, false)
	await _test_gardening(true)
	await _test_gardening(false)
	var failures := 0
	for name in _results:
		if not _results[name]:
			failures += 1
			printerr("FALHOU: " + name)
	if failures == 0:
		print("OK: minigames passaram")
	get_tree().quit(1 if failures > 0 else 0)


func _act(node: Minigame, action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	node.handle_input(event)


func _test_carpentry(hits: int, expect_success: bool) -> void:
	var game := CarpentryMinigame.new()
	add_child(game)
	var outcome := []
	game.finished.connect(func(ok): outcome.append(ok))
	game.start()
	_act(game, "interagir")
	var first_beat := Time.get_ticks_msec() + 500 + CarpentryMinigame.COUNT_IN * CarpentryMinigame.BEAT_MS
	for beat in CarpentryMinigame.BEATS:
		var target := first_beat + beat * CarpentryMinigame.BEAT_MS + 30
		while Time.get_ticks_msec() < target:
			await get_tree().process_frame
		if beat < hits:
			_act(game, "interagir")
	while outcome.is_empty():
		await get_tree().process_frame
	_results["carpintaria com %d acertos" % hits] = outcome[0] == expect_success


func _test_gardening(choose_right: bool) -> void:
	var game := GardeningMinigame.new()
	add_child(game)
	var outcome := []
	game.finished.connect(func(ok): outcome.append(ok))
	game.start()
	for round_index in GardeningMinigame.ROUNDS:
		await get_tree().create_timer(0.1).timeout
		var target := game._thirsty if choose_right else (game._thirsty + 1) % GardeningMinigame.SEEDLINGS
		for i in target:
			_act(game, "mover_leste")
		_act(game, "interagir")
		await get_tree().create_timer(1.7).timeout
	while outcome.is_empty():
		await get_tree().process_frame
	_results["jardinagem acertando=%s" % choose_right] = outcome[0] == choose_right
