class_name AbilitySounds
extends RefCounted
## Sons das habilidades ativas das espécies (tecla H), gerados por código: o
## jogo nunca fica mudo por falta de arquivo. São curtos e sem efeitos em
## tempo real (o que se ouve já está pronto no sample).

const RATE := 44100

static var _cache := {}


## Salto: o sopro do impulso e, no fim, o baque do pouso.
static func jump() -> AudioStreamWAV:
	if not _cache.has("salto"):
		var rng := RandomNumberGenerator.new()
		rng.seed = 6101
		var seconds := 0.75
		var samples := _blank(seconds)
		var low := 0.0
		for i in samples.size():
			var t := float(i) / RATE
			var whoosh := 0.0
			if t < 0.4:
				var edge := sin(PI * t / 0.4)
				low = lerpf(low, rng.randf_range(-1.0, 1.0), 0.18 + 0.4 * t)
				whoosh = low * edge * 0.55
			var thud := 0.0
			if t >= 0.42:
				var u := t - 0.42
				thud = sin(TAU * (95.0 - 40.0 * u) * u) * exp(-u * 16.0) * 0.8 + rng.randf_range(-1.0, 1.0) * exp(-u * 70.0) * 0.4
			samples[i] = (whoosh + thud) * 0.8
		_cache["salto"] = _to_wav(samples)
	return _cache["salto"]


## Disparada: o arranque, uma rajada que cresce e some.
static func dash() -> AudioStreamWAV:
	if not _cache.has("disparada"):
		var rng := RandomNumberGenerator.new()
		rng.seed = 6102
		var seconds := 0.9
		var samples := _blank(seconds)
		var low := 0.0
		for i in samples.size():
			var t := float(i) / RATE
			var env := minf(t / 0.12, 1.0) * exp(-maxf(t - 0.12, 0.0) * 3.2)
			low = lerpf(low, rng.randf_range(-1.0, 1.0), 0.25)
			var stomp := sin(TAU * 70.0 * t) * exp(-t * 14.0) * 0.6
			samples[i] = (low * env * 0.6 + stomp) * 0.85
		_cache["disparada"] = _to_wav(samples)
	return _cache["disparada"]


## Uivo: um canto longo que sobe, segura com vibrato e desce.
static func howl() -> AudioStreamWAV:
	if not _cache.has("uivo"):
		var rng := RandomNumberGenerator.new()
		rng.seed = 6103
		var seconds := 2.6
		var samples := _blank(seconds)
		var phase := 0.0
		var breath := 0.0
		for i in samples.size():
			var t := float(i) / RATE
			var pitch := 260.0
			if t < 0.7:
				pitch = lerpf(260.0, 520.0, smoothstep(0.0, 0.7, t))
			elif t < 1.7:
				pitch = 520.0 + 12.0 * sin(TAU * 5.2 * t)
			else:
				pitch = lerpf(520.0, 300.0, smoothstep(1.7, 2.6, t))
			phase += TAU * pitch / RATE
			var voice := sin(phase) + 0.45 * sin(2.0 * phase) + 0.2 * sin(3.0 * phase)
			breath = lerpf(breath, rng.randf_range(-1.0, 1.0), 0.3)
			var env := smoothstep(0.0, 0.25, t) * (1.0 - smoothstep(2.0, 2.6, t))
			samples[i] = (voice * 0.42 + breath * 0.1) * env
		_cache["uivo"] = _to_wav(samples)
	return _cache["uivo"]


## Fuçar: o focinho remexendo a terra, arranhões curtos.
static func dig() -> AudioStreamWAV:
	if not _cache.has("fucar"):
		var rng := RandomNumberGenerator.new()
		rng.seed = 6104
		var samples := _blank(0.7)
		var low := 0.0
		for i in samples.size():
			var t := float(i) / RATE
			var pulse := 0.0
			for start in [0.0, 0.22, 0.45]:
				if t >= start:
					pulse = maxf(pulse, exp(-(t - start) * 18.0))
			low = lerpf(low, rng.randf_range(-1.0, 1.0), 0.32)
			samples[i] = low * pulse * 0.7
		_cache["fucar"] = _to_wav(samples)
	return _cache["fucar"]


## Arar: o chifre arrastando o chão, grave e pesado.
static func plow() -> AudioStreamWAV:
	if not _cache.has("arar"):
		var rng := RandomNumberGenerator.new()
		rng.seed = 6105
		var samples := _blank(0.9)
		var low := 0.0
		for i in samples.size():
			var t := float(i) / RATE
			var env := smoothstep(0.0, 0.1, t) * (1.0 - smoothstep(0.55, 0.9, t))
			low = lerpf(low, rng.randf_range(-1.0, 1.0), 0.12)
			var thump := sin(TAU * 60.0 * t) * exp(-t * 9.0) * 0.7
			samples[i] = (low * env * 0.9 + thump) * 0.8
		_cache["arar"] = _to_wav(samples)
	return _cache["arar"]


## Achou algo ao fuçar: dois pontinhos que sobem.
static func found() -> AudioStreamWAV:
	if not _cache.has("achou"):
		var samples := _blank(0.5)
		for i in samples.size():
			var t := float(i) / RATE
			var a := sin(TAU * 660.0 * t) * exp(-t * 9.0)
			var u := maxf(t - 0.12, 0.0)
			var b := sin(TAU * 990.0 * u) * exp(-u * 9.0) if t >= 0.12 else 0.0
			samples[i] = (a + b) * 0.35
		_cache["achou"] = _to_wav(samples)
	return _cache["achou"]


static func _blank(seconds: float) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	samples.resize(int(seconds * RATE))
	return samples


static func _to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav
