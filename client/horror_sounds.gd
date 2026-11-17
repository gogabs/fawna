class_name HorrorSounds
extends RefCounted
## Sons dos horrores, gerados por código (sons do próprio projeto).
##
## O Calado não faz som nenhum; só quem escuta com atenção (segurando o Tab)
## ouve a respiração dele: lenta, grave e longa demais para ser de gente.
## Uma gravação em assets/sounds/horrores/calado_respiracao.ogg|wav entra no
## lugar do som gerado.

const RATE := 32000
const DIR := "res://assets/sounds/horrores/"
const BREATH_SECONDS := 5.2
const CAUGHT_SECONDS := 2.2  # o som de ser alcançado, até o corte
const RELIEF_SECONDS := 1.8  # o som de reaparecer, até a criatura poder andar

static var _cache := {}


static func clear() -> void:
	_cache.clear()


## A respiração do Calado, em loop.
static func calado_breath() -> AudioStream:
	if _cache.has("respiracao"):
		return _cache["respiracao"]
	var stream: AudioStream = null
	for ext in [".ogg", ".wav"]:
		if ResourceLoader.exists(DIR + "calado_respiracao" + ext):
			stream = load(DIR + "calado_respiracao" + ext) as AudioStream
			break
	if stream == null:
		stream = _to_loop(calado_breath_samples())
	_cache["respiracao"] = stream
	return stream


## Um ciclo: puxa o ar devagar, segura, solta mais longo e mais grave, com
## um ronco fundo por baixo, e um silêncio antes de recomeçar.
static func calado_breath_samples() -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(int(BREATH_SECONDS * RATE))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7741
	_breath(buf, 0.0, 1.7, 420.0, 760.0, 0.55, rng)
	_breath(buf, 2.1, 2.5, 680.0, 300.0, 0.9, rng)
	_growl(buf, 2.2, 2.3, 62.0, 0.28)
	return buf


## Sopro: ruído passado por um filtro passa-faixa cujo centro desliza de
## "f_from" a "f_to". Fica entre 300 e 800 Hz, para atravessar o abafamento
## que o próprio Calado põe no mundo.
static func _breath(buf: PackedFloat32Array, start: float, dur: float, f_from: float, f_to: float, amp: float, rng: RandomNumberGenerator) -> void:
	var first := int(start * RATE)
	var count := int(dur * RATE)
	var low := 0.0
	var band := 0.0
	var q := 0.35  # amortecimento: menor, mais "assobiado"
	for i in count:
		var n := first + i
		if n >= buf.size():
			break
		var x := float(i) / count
		var freq := lerpf(f_from, f_to, x)
		var f := 2.0 * sin(PI * freq / RATE)
		var high := rng.randf_range(-1.0, 1.0) - low - q * band
		band += f * high
		low += f * band
		# Sobe devagar, desce mais devagar ainda, com um tremor leve.
		var env := pow(sin(PI * pow(x, 0.7)), 1.5) * (0.85 + 0.15 * sin(TAU * 9.0 * x * dur))
		buf[n] += band * env * amp * 0.5


## Ronco: um grave que treme, quase só sentido.
static func _growl(buf: PackedFloat32Array, start: float, dur: float, freq: float, amp: float) -> void:
	var first := int(start * RATE)
	var count := int(dur * RATE)
	for i in count:
		var n := first + i
		if n >= buf.size():
			break
		var x := float(i) / count
		var t := float(i) / RATE
		var env := pow(sin(PI * x), 2.0) * (0.6 + 0.4 * sin(TAU * 21.0 * t))
		buf[n] += (sin(TAU * freq * t) + 0.5 * sin(TAU * freq * 2.01 * t) + 0.25 * sin(TAU * freq * 3.02 * t)) * env * amp


static func _to_loop(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = samples.size()
	return wav


## Ser alcançado: um baque grave no peito, o mundo sugado para dentro (ar que
## cai de tom e some) e um silêncio total no fim.
static func caught() -> AudioStream:
	if not _cache.has("alcancado"):
		_cache["alcancado"] = _to_one_shot(caught_samples())
	return _cache["alcancado"]


static func caught_samples() -> PackedFloat32Array:
	var count := int(CAUGHT_SECONDS * RATE)
	var buf := PackedFloat32Array()
	buf.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3313
	var low := 0.0
	var band := 0.0
	var phase := 0.0
	for i in count:
		var t := float(i) / RATE
		var x := t / CAUGHT_SECONDS
		# Baque: seno grave que cai.
		var thump := sin(TAU * (70.0 - 30.0 * minf(t * 3.0, 1.0)) * t) * exp(-t * 9.0) * 0.8
		# Sucção: ruído filtrado cujo centro cai e cuja força some.
		var freq := lerpf(900.0, 120.0, x)
		var f := 2.0 * sin(PI * freq / RATE)
		var high := rng.randf_range(-1.0, 1.0) - low - 0.3 * band
		band += f * high
		low += f * band
		var env := pow(sin(PI * minf(maxf((x - 0.04) / 0.96, 0.0), 1.0)), 0.8) * (1.0 - x)
		# Um zumbido grave que também cai, para dar peso.
		phase += TAU * lerpf(55.0, 30.0, x) / RATE
		var hum := sin(phase) * env * 0.3
		var fade := minf((1.0 - x) / 0.08, 1.0)  # fecha em silêncio
		buf[i] = (thump + band * env * 0.35 + hum) * fade
	return buf


## Reaparecer em lugar seguro: um sopro quente que sobe e uma nota baixa e
## macia, como o ar voltando.
static func relief() -> AudioStream:
	if not _cache.has("alivio"):
		_cache["alivio"] = _to_one_shot(relief_samples())
	return _cache["alivio"]


static func relief_samples() -> PackedFloat32Array:
	var count := int(RELIEF_SECONDS * RATE)
	var buf := PackedFloat32Array()
	buf.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3314
	var air := 0.0
	for i in count:
		var t := float(i) / RATE
		var x := t / RELIEF_SECONDS
		air = lerpf(rng.randf_range(-1.0, 1.0), air, 0.97)
		var swell := pow(sin(PI * x), 2.0)
		var note := sin(TAU * 196.0 * t) + 0.4 * sin(TAU * 392.0 * t)
		var enter := minf(t / 0.12, 1.0)
		buf[i] = (air * 0.5 * swell + note * 0.22 * exp(-t * 1.6)) * enter * minf((1.0 - x) / 0.1, 1.0)
	return buf


static func _to_one_shot(samples: PackedFloat32Array) -> AudioStreamWAV:
	var wav := _to_loop(samples)
	wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return wav
