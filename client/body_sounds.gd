class_name BodySounds
extends RefCounted
## Sons do próprio corpo (fome e frio), gerados por código como provisórios.
## Curtos e baixos: a barriga que ronca, os dentes que batem e a respiração
## trêmula, o suspiro ao chegar perto do fogo, o mastigar e o apagar.
## Cada um tem algumas variações, sorteadas a cada vez.

const RATE := SoundBank.RATE
const VARIANTS := 3

static var _cache := {}
static var _rng := RandomNumberGenerator.new()


static func clear() -> void:
	_cache.clear()


static func _pick(key: String, maker: Callable) -> AudioStreamWAV:
	if not _cache.has(key):
		var list := []
		for i in VARIANTS:
			list.append(maker.call(i))
		_cache[key] = list
	var list: Array = _cache[key]
	return list[_rng.randi() % list.size()]


## Barra sonora: um toque curto, colocado no estéreo pela posição na barra
## (Body.bar_pan). A fome é um toque grave e amadeirado; o calor, um toque
## agudo de vidro, para não se confundirem.
static func ping(kind: String, step: int) -> AudioStreamWAV:
	var key := "ping_%s_%d" % [kind, step]
	if not _cache.has(key):
		_cache[key] = [_make_ping(kind, Body.bar_pan(step))]
	return _cache[key][0]


static func _make_ping(kind: String, pan: float) -> AudioStreamWAV:
	var food := kind == "food"
	var seconds := 0.35 if food else 0.45
	var base := 392.0 if food else 1046.5
	var count := int(seconds * RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var t := float(i) / RATE
		var attack := minf(t / 0.004, 1.0)
		var tone: float
		if food:
			# Madeira: fundamental e um parcial inarmônico que some depressa.
			tone = sin(TAU * base * t) * exp(-t * 14.0) + 0.4 * sin(TAU * base * 2.76 * t) * exp(-t * 30.0)
		else:
			# Vidro: parciais altos, cauda mais longa.
			tone = sin(TAU * base * t) * exp(-t * 7.0) + 0.3 * sin(TAU * base * 2.4 * t) * exp(-t * 11.0)
		samples[i] = tone * attack * 0.45
	return _to_stereo(samples, pan)


## Mono para estéreo com pan de potência constante (-1 esquerda, 1 direita).
static func _to_stereo(samples: PackedFloat32Array, pan: float) -> AudioStreamWAV:
	var angle := (clampf(pan, -1.0, 1.0) + 1.0) * PI * 0.25
	var left := cos(angle)
	var right := sin(angle)
	var data := PackedByteArray()
	data.resize(samples.size() * 4)
	for i in samples.size():
		data.encode_s16(i * 4, int(clampf(samples[i] * left, -1.0, 1.0) * 32767.0))
		data.encode_s16(i * 4 + 2, int(clampf(samples[i] * right, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = true
	wav.data = data
	return wav


## Barriga roncando: um gorgolejo grave que sobe e desce, com bolhas.
static func growl() -> AudioStreamWAV:
	return _pick("growl", _make_growl)


static func _make_growl(variant: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9100 + variant
	var seconds := 1.1 + 0.3 * variant
	var count := int(seconds * RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var phase := 0.0
	var noise := 0.0
	var base := 70.0 + 12.0 * variant
	for i in count:
		var t := float(i) / RATE
		var x := t / seconds
		var env := sin(PI * x) * (0.6 + 0.4 * sin(TAU * 3.1 * t + variant))
		var freq := base * (1.0 + 0.5 * sin(TAU * (1.3 + 0.4 * variant) * t)) + 25.0 * sin(TAU * 7.0 * t)
		phase += TAU * freq / RATE
		noise = lerpf(noise, rng.randf_range(-1.0, 1.0), 0.05)
		var tone := sin(phase) + 0.35 * sin(phase * 2.0) + 0.15 * sin(phase * 3.0)
		samples[i] = (tone * 0.55 + noise * 0.8) * env * 0.45
	# Bolhas: estalinhos graves espalhados.
	for b in 4 + variant * 2:
		var at := int(rng.randf_range(0.15, 0.85) * count)
		var length := int(0.04 * RATE)
		var f := rng.randf_range(160.0, 260.0)
		for j in length:
			if at + j < count:
				var e := exp(-6.0 * float(j) / length)
				samples[at + j] += sin(TAU * f * j / RATE * (1.0 + 0.6 * j / length)) * e * 0.25
	return SoundBank._to_wav(samples)


## Frio: dentes batendo depressa e uma respiração trêmula por baixo.
static func shiver() -> AudioStreamWAV:
	return _pick("shiver", _make_shiver)


static func _make_shiver(variant: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9200 + variant
	var seconds := 1.3 + 0.2 * variant
	var count := int(seconds * RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var noise := 0.0
	for i in count:
		var t := float(i) / RATE
		var x := t / seconds
		# Respiração: ar soprado, que treme a uns 7 Hz.
		noise = lerpf(noise, rng.randf_range(-1.0, 1.0), 0.25)
		var breath := sin(PI * x) * (0.55 + 0.45 * sin(TAU * 7.0 * t))
		samples[i] = noise * breath * 0.12
	# Dentes: cliques secos a uns 14 por segundo, irregulares.
	var at := 0.05
	while at < seconds - 0.1:
		var start := int(at * RATE)
		var length := int(0.012 * RATE)
		var f := rng.randf_range(2200.0, 3200.0)
		var loud := rng.randf_range(0.18, 0.32) * sin(PI * at / seconds)
		for j in length:
			if start + j < count:
				var e := exp(-9.0 * float(j) / length)
				samples[start + j] += (sin(TAU * f * j / RATE) + rng.randf_range(-0.5, 0.5)) * e * loud
		at += rng.randf_range(0.055, 0.09)
	return SoundBank._to_wav(samples)


## O suspiro de quem chega com frio perto do fogo.
static func warm_sigh() -> AudioStreamWAV:
	return _pick("sigh", _make_sigh)


static func _make_sigh(variant: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9300 + variant
	var seconds := 1.4
	var count := int(seconds * RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var noise := 0.0
	var smooth := 0.18
	for i in count:
		var x := float(i) / count
		noise = lerpf(noise, rng.randf_range(-1.0, 1.0), smooth)
		smooth = lerpf(0.18, 0.06, x)  # o sopro escurece no fim
		var env := pow(sin(PI * minf(x * 1.6, 1.0) * 0.5), 2.0) * (1.0 - x)
		samples[i] = noise * env * 0.35
	return SoundBank._to_wav(samples)


## Mastigar: três ou quatro mordidas abafadas.
static func eat() -> AudioStreamWAV:
	return _pick("eat", _make_eat)


static func _make_eat(variant: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9400 + variant
	var seconds := 1.2
	var count := int(seconds * RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for bite in 3 + variant % 2:
		var start := int((0.08 + bite * 0.28) * RATE)
		var length := int(0.16 * RATE)
		var noise := 0.0
		for j in length:
			if start + j < count:
				noise = lerpf(noise, rng.randf_range(-1.0, 1.0), 0.3)
				var e := sin(PI * float(j) / length) * exp(-3.0 * float(j) / length)
				samples[start + j] += noise * e * 0.4
	return SoundBank._to_wav(samples)


## Desfalecer: um zumbido grave que se fecha e um baque surdo.
static func faint() -> AudioStreamWAV:
	return _pick("faint", _make_faint)


static func _make_faint(variant: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9500 + variant
	var seconds := 2.2
	var count := int(seconds * RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var phase := 0.0
	var noise := 0.0
	for i in count:
		var x := float(i) / count
		var freq := lerpf(180.0, 55.0, x)
		phase += TAU * freq / RATE
		noise = lerpf(noise, rng.randf_range(-1.0, 1.0), lerpf(0.2, 0.02, x))
		var env := minf(x * 4.0, 1.0) * (1.0 - x)
		samples[i] = (sin(phase) * 0.3 + noise * 0.4) * env * 0.4
	# O baque, no fim.
	var at := int(0.78 * count)
	for j in int(0.25 * RATE):
		if at + j < count:
			var e := exp(-12.0 * float(j) / RATE * 4.0)
			samples[at + j] += sin(TAU * 48.0 * j / RATE) * e * 0.5
	return SoundBank._to_wav(samples)
