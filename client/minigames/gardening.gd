class_name GardeningMinigame
extends Minigame
## Jardinagem: achar a muda com sede.
## Quatro mudas, da esquerda para a direita. Uma soa murcha. Setas para ouvir
## cada uma, Espaço para regar. Três rodadas; acertou 2: sai uma muda.

const SEEDLINGS := 4
const ROUNDS := 3
const CORRECT_NEEDED := 2

var _round := 0
var _correct := 0
var _thirsty := 0
var _selected := 0
var _rng := RandomNumberGenerator.new()


func start() -> void:
	_rng.randomize()
	Speech.say("Jardinagem. São 4 mudas, da esquerda para a direita. Uma está com sede e soa murcha. Use as setas para ouvir cada muda e Espaço para regar.")
	_new_round()


func handle_input(event: InputEvent) -> void:
	if event.is_action("mover_oeste"):
		_select(_selected - 1)
	elif event.is_action("mover_leste"):
		_select(_selected + 1)
	elif Minigame.is_confirm(event):
		_water()


func _new_round() -> void:
	_thirsty = _rng.randi_range(0, SEEDLINGS - 1)
	_selected = 0
	_select(0)


func _select(index: int) -> void:
	_selected = clampi(index, 0, SEEDLINGS - 1)
	play(SoundBank.seedling(_pan(_selected), _selected == _thirsty))


func _water() -> void:
	_round += 1
	if _selected == _thirsty:
		_correct += 1
		play(SoundBank.water_splash())
		Speech.say("Isso! A muda %d estava com sede." % (_selected + 1))
	else:
		Speech.say("Essa estava bem. A com sede era a %d." % (_thirsty + 1))
	if _round >= ROUNDS:
		await get_tree().create_timer(1.2).timeout
		if _correct >= CORRECT_NEEDED:
			Speech.say("Você acertou %d de %d e cuidou de uma muda nova!" % [_correct, ROUNDS])
			_finish(true)
		else:
			Speech.say("Acertou %d de %d. A semente e a água continuam com você, tente de novo." % [_correct, ROUNDS])
			_finish(false)
		return
	await get_tree().create_timer(1.5).timeout
	if not _done:
		_new_round()


static func _pan(index: int) -> float:
	return lerpf(-0.9, 0.9, float(index) / (SEEDLINGS - 1))
