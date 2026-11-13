class_name CarpentryMinigame
extends Minigame
## Carpintaria: serrar no ritmo.
## Quatro batidas de contagem, depois oito batidas do serrote. A pessoa aperta
## Espaço junto com cada batida. Acertou 5 de 8: sai uma tábua.

const BEAT_MS := 650
const COUNT_IN := 4
const BEATS := 8
const WINDOW_MS := 200
const HITS_NEEDED := 5

var _started := false
var _start_ms := 0
var _next_beat := 0
var _hits := {}  # índice da batida -> true


func start() -> void:
	Speech.say("Carpintaria. Aperte Espaço junto com cada batida do serrote. Primeiro vêm 4 batidas de contagem. Aperte Espaço para começar.")


func handle_input(event: InputEvent) -> void:
	if not Minigame.is_confirm(event):
		return
	if not _started:
		_started = true
		Speech.stop()
		_start_ms = Time.get_ticks_msec() + 500
		return
	var elapsed := Time.get_ticks_msec() - _start_ms - COUNT_IN * BEAT_MS
	var beat := roundi(float(elapsed) / BEAT_MS)
	if beat < 0 or beat >= BEATS or _hits.has(beat):
		return
	if absi(elapsed - beat * BEAT_MS) <= WINDOW_MS:
		_hits[beat] = true
		play(Sounds.tok())


func _process(_delta: float) -> void:
	if not _started or _done:
		return
	var elapsed := Time.get_ticks_msec() - _start_ms
	if elapsed < 0:
		return
	var beat_now := elapsed / BEAT_MS
	if beat_now >= _next_beat and _next_beat < COUNT_IN + BEATS:
		play(Sounds.tick() if _next_beat < COUNT_IN else Sounds.saw())
		_next_beat += 1
	if elapsed > (COUNT_IN + BEATS) * BEAT_MS + WINDOW_MS + 300:
		var hits := _hits.size()
		if hits >= HITS_NEEDED:
			Speech.say("Acertou %d de %d. Você fez uma tábua!" % [hits, BEATS])
			_finish(true)
		else:
			Speech.say("Acertou %d de %d. Quase! Precisa de %d. A madeira continua com você, tente de novo." % [hits, BEATS, HITS_NEEDED])
			_finish(false)
