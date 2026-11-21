class_name HorseSounds
extends RefCounted
## Sons dos cavalinhos-da-bruma, gerados por código enquanto não há gravações.
##
## A ideia é soarem selvagens e um pouco inumanos, não de fazenda: relincho
## grave e rouco, com uma segunda voz fraca num intervalo estranho; bufo de
## ar pelas narinas com os lábios tremendo; cascos abafados que mudam com o
## chão; mastigar de capim. Cada som é gerado na primeira vez e guardado.
##
## Gravações em assets/sounds/cavalos/ entram no lugar dos sons gerados,
## sorteadas a cada vez entre as que existirem:
##   casco_<chão>_<n>   (chão: grama, terra, neve, madeira, agua)
##   galope_<chão>_<n>  (sem elas, o galope usa os cascos, mais fortes)
##   pasto_<n>, bufo_<n>, relincho_<n>, alarme_<n>

const RATE := 32000
const DIR := "res://assets/sounds/cavalos/"
const VARIANTS := 4  # variações geradas de cada som
const SURFACES := ["grama", "terra", "neve", "madeira", "agua"]

static var _cache := {}
static var _files := {}


static func clear() -> void:
	_cache.clear()
	_files.clear()


## Bufo, relincho, alarme ou pasto: uma das variações, sorteada.
static func voice(kind: String) -> AudioStream:
	var recorded := _recorded(kind)
	if not recorded.is_empty():
		return recorded[randi() % recorded.size()]
	return generated(kind, randi() % VARIANTS)


## Uma batida de casco (andando, um par de batidas; galopando, três).
static func hoof(surface: String, gallop: bool) -> AudioStream:
	var recorded := _recorded(("galope_" if gallop else "casco_") + surface)
	if recorded.is_empty() and gallop:
		recorded = _recorded("casco_" + surface)
	if not recorded.is_empty():
		return recorded[randi() % recorded.size()]
	return generated(("galope_" if gallop else "casco_") + surface, randi() % VARIANTS)


## O som gerado (sem olhar gravações). Usado também pelos testes.
static func generated(kind: String, variant: int) -> AudioStream:
	var key := "%s_%d" % [kind, variant]
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var buf: PackedFloat32Array
	if kind.begins_with("casco_") or kind.begins_with("galope_"):
		var gallop := kind.begins_with("galope_")
		buf = _hooves(kind.get_slice("_", 1), gallop, rng)
	else:
		match kind:
			"relincho":
				buf = _with_tail(_neigh(rng, false), 0.6)
			"alarme":
				buf = _with_tail(_neigh(rng, true), 0.6)
			"bufo":
				buf = _with_tail(_snort(rng), 0.3)
			"pasto":
				buf = _graze(rng)
			_:
				buf = _buffer(0.1)
	var stream := _to_wav(buf)
	_cache[key] = stream
	return stream


# --- Síntese -------------------------------------------------------------------

## Cascos: cada batida é um baque grave (o peso) mais um estalo filtrado (o
## casco no chão). O chão muda o estalo: grama abafa, terra é seca, neve
## range, madeira ressoa oca, água espirra.
static func _hooves(surface: String, gallop: bool, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var hits := [0.0, 0.11] if not gallop else [0.0, 0.07, 0.15]
	var buf := _buffer(0.45 if not gallop else 0.5)
	for i in hits.size():
		var at: float = hits[i] + rng.randf_range(-0.01, 0.01)
		var amp := rng.randf_range(0.7, 1.0) * (1.25 if gallop else 1.0) * (1.0 if i == 0 else 0.8)
		_thump(buf, at, 0.09, rng.randf_range(70.0, 105.0), amp * 0.55)
		match surface:
			"grama":
				_noise_burst(buf, at, 0.07, 0.08, 0.35, amp * 0.4, rng)
				_noise_burst(buf, at + 0.01, 0.12, 0.5, 0.0, amp * 0.12, rng)  # capim roçando
			"terra":
				_noise_burst(buf, at, 0.05, 0.25, 0.25, amp * 0.6, rng)
			"neve":
				for g in 6:
					_noise_burst(buf, at + g * 0.012 + rng.randf() * 0.006, 0.014, 0.55, 0.0, amp * rng.randf_range(0.15, 0.35), rng)
			"madeira":
				_noise_burst(buf, at, 0.02, 0.4, 0.0, amp * 0.5, rng)
				_ring(buf, at, 0.14, rng.randf_range(240.0, 300.0), amp * 0.35)
				_ring(buf, at, 0.09, rng.randf_range(610.0, 700.0), amp * 0.12)
			"agua":
				_noise_burst(buf, at, 0.18, 0.6, 0.0, amp * 0.35, rng)
				_noise_burst(buf, at + 0.03, 0.12, 0.12, 0.3, amp * 0.25, rng)
			_:
				_noise_burst(buf, at, 0.05, 0.2, 0.3, amp * 0.5, rng)
	return buf


## Relincho: vários pulsos que descem, voz rouca (dente de serra com
## ruído), tremor rápido e uma segunda voz fraca a 1,41 (trítono). O alarme
## é mais curto, mais alto e mais áspero.
static func _neigh(rng: RandomNumberGenerator, alarm: bool) -> PackedFloat32Array:
	var dur := rng.randf_range(0.9, 1.3) if alarm else rng.randf_range(1.3, 1.8)
	var buf := _buffer(dur + 0.1)
	var top := rng.randf_range(560.0, 640.0) if alarm else rng.randf_range(430.0, 520.0)
	var bottom := top * (0.45 if alarm else 0.5)
	var phase := 0.0
	var phase2 := 0.0
	var noise := 0.0
	var low := 0.0
	var count := int(dur * RATE)
	var trill := rng.randf_range(9.0, 12.0)
	for i in count:
		var x := float(i) / count
		var t := float(i) / RATE
		# Sobe rápido no começo e desce aos trancos até o fim.
		var contour := minf(1.0, x / 0.08)
		var freq := lerpf(bottom * 0.8, top, contour) * lerpf(1.0, bottom / top, pow(x, 0.8))
		freq *= 1.0 + 0.05 * sin(TAU * trill * t) * x
		phase = fmod(phase + freq / RATE, 1.0)
		phase2 = fmod(phase2 + freq * 1.41 / RATE, 1.0)
		var saw := 2.0 * phase - 1.0
		var saw2 := 2.0 * phase2 - 1.0
		# Pulsos: o relincho "gagueja" em trancos que vão ficando mais lentos.
		var pulses := 0.6 + 0.4 * absf(sin(PI * (trill * 0.5) * t * (1.0 - 0.4 * x)))
		var env := minf(1.0, t / 0.04) * pow(1.0 - x, 0.6) * pulses
		noise = lerpf(rng.randf_range(-1.0, 1.0), noise, 0.4)
		var raw := saw * 0.5 + saw2 * (0.12 if alarm else 0.08) + noise * (0.5 if alarm else 0.35)
		low = lerpf(raw, low, 0.55)  # tira o brilho de serra
		buf[i] += low * env * 0.55
	return buf


## Bufo: ar pelas narinas (ruído) com os lábios tremendo (modulação de
## uns 25 Hz) e uma ressonância grave de focinho.
static func _snort(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := rng.randf_range(0.45, 0.8)
	var buf := _buffer(dur + 0.05)
	var count := int(dur * RATE)
	var flutter := rng.randf_range(22.0, 30.0)
	var center := rng.randf_range(500.0, 800.0)
	var b0 := 0.0
	var b1 := 0.0
	var r := 0.97
	for i in count:
		var x := float(i) / count
		var t := float(i) / RATE
		var env := minf(1.0, t / 0.015) * pow(1.0 - x, 1.5)
		var lips := 0.45 + 0.55 * absf(sin(PI * flutter * t))
		var input := rng.randf_range(-1.0, 1.0)
		# Ressonador de dois polos (passa-faixa simples) que desce um pouco.
		var w := TAU * center * (1.0 - 0.3 * x) / RATE
		var y := input * (1.0 - r) + 2.0 * r * cos(w) * b0 - r * r * b1
		b1 = b0
		b0 = y
		buf[i] += (y * 6.0 + input * 0.08) * env * lips * 0.7
	return buf


## Pasto: arranca o capim (um rasgo de ruído) e mastiga (trituradas graves).
static func _graze(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var chews := rng.randi_range(3, 5)
	var buf := _buffer(0.35 + chews * 0.3 + 0.2)
	_noise_burst(buf, 0.0, 0.22, 0.45, 0.0, 0.35, rng)  # rasgo
	for c in chews:
		var at := 0.3 + c * rng.randf_range(0.26, 0.34)
		for g in 5:
			_noise_burst(buf, at + g * 0.018, 0.02, 0.3, 0.2, rng.randf_range(0.15, 0.3), rng)
		_thump(buf, at, 0.06, rng.randf_range(110.0, 140.0), 0.12)
	return buf


# --- Ajudantes de síntese ------------------------------------------------------

static func _buffer(seconds: float) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(int(seconds * RATE))
	return buf


## Baque grave: seno que cai de tom e some rápido.
static func _thump(buf: PackedFloat32Array, start: float, dur: float, freq: float, amp: float) -> void:
	var first := int(start * RATE)
	var count := int(dur * RATE)
	var phase := 0.0
	for i in count:
		var n := first + i
		if n < 0 or n >= buf.size():
			continue
		var x := float(i) / count
		phase += TAU * freq * (1.0 - 0.4 * x) / RATE
		buf[n] += sin(phase) * pow(1.0 - x, 3.0) * minf(1.0, i / 40.0) * amp


## Ressonância que soa e some (madeira oca).
static func _ring(buf: PackedFloat32Array, start: float, dur: float, freq: float, amp: float) -> void:
	var first := int(start * RATE)
	var count := int(dur * RATE)
	for i in count:
		var n := first + i
		if n < 0 or n >= buf.size():
			continue
		var x := float(i) / count
		buf[n] += sin(TAU * freq * i / RATE) * exp(-6.0 * x) * amp


## Rajada de ruído. "bright" (0 a 1) quanto de agudo passa; "body" (0 a 1)
## quanto de grave sobra. Envoltória de ataque rápido e queda.
static func _noise_burst(buf: PackedFloat32Array, start: float, dur: float, bright: float, body: float, amp: float, rng: RandomNumberGenerator) -> void:
	var first := int(start * RATE)
	var count := maxi(1, int(dur * RATE))
	var low := 0.0
	var lower := 0.0
	var smooth := lerpf(0.92, 0.2, clampf(bright, 0.0, 1.0))
	for i in count:
		var n := first + i
		if n < 0 or n >= buf.size():
			continue
		var x := float(i) / count
		var env := minf(1.0, i / 30.0) * pow(1.0 - x, 2.0)
		low = lerpf(rng.randf_range(-1.0, 1.0), low, smooth)
		lower = lerpf(low, lower, 0.98)
		buf[n] += ((low - lower) + lower * body * 4.0) * env * amp


## Eco de campo aberto: poucas cópias atrasadas e abafadas.
static func _with_tail(buf: PackedFloat32Array, seconds: float) -> PackedFloat32Array:
	var dry := buf.size()
	var out := buf.duplicate()
	out.resize(dry + int(seconds * RATE))
	for tap in [[0.09, 0.18], [0.17, 0.1], [0.29, 0.05]]:
		var offset := int(tap[0] * RATE)
		var gain: float = tap[1]
		var smooth := 0.0
		for i in dry:
			smooth = lerpf(buf[i], smooth, 0.7)
			out[i + offset] += smooth * gain
	return out


static func _to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	# Normaliza para um pico de 0,8: cada síntese tem o seu nível.
	var peak := 0.0001
	for s in samples:
		peak = maxf(peak, absf(s))
	var gain := 0.8 / peak
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i] * gain, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav


## As gravações de um som (ex.: "bufo" acha bufo_0, bufo_1...).
static func _recorded(prefix: String) -> Array:
	if _files.has(prefix):
		return _files[prefix]
	var found := []
	for i in 16:
		for ext in [".ogg", ".wav"]:
			var path := "%s%s_%d%s" % [DIR, prefix, i, ext]
			if ResourceLoader.exists(path):
				found.append(load(path))
				break
	_files[prefix] = found
	return found
