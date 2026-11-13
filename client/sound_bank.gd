class_name SoundBank
extends RefCounted
## Sons provisórios gerados por código, para o protótipo não depender de
## arquivos de áudio. Serão trocados por sons gravados (ex.: freesound.org, CC0).

const RATE := 22050

static var _cache := {}


## Passo: ruído curto. No bosque é abafado e grave; na pradaria, mais aberto.
static func footstep(biome: WorldGen.Biome) -> AudioStreamWAV:
	var key := "passo_%d" % biome
	if not _cache.has(key):
		var smooth := 0.85 if biome == WorldGen.Biome.BOSQUE else 0.35
		_cache[key] = _noise_burst(0.09, smooth, 0.55, 1234 + biome)
	return _cache[key]


## Esbarrão: tom grave e curto.
static func bump() -> AudioStreamWAV:
	if not _cache.has("bump"):
		_cache["bump"] = _tone([110.0], 0.14, 0.7)
	return _cache["bump"]


## Sininho de chegada de alguém.
static func chime() -> AudioStreamWAV:
	if not _cache.has("chime"):
		_cache["chime"] = _tone([660.0, 880.0], 0.35, 0.35)
	return _cache["chime"]


## Som contínuo (em loop) de cada coisa do mundo, para o áudio espacial.
static func ambient(thing: WorldGen.Thing) -> AudioStreamWAV:
	var key := "amb_%d" % thing
	if not _cache.has(key):
		match thing:
			WorldGen.Thing.RIACHO:
				_cache[key] = _water_loop()
			WorldGen.Thing.ARVORE:
				_cache[key] = _tree_loop()
			WorldGen.Thing.ARBUSTO:
				_cache[key] = _bees_loop()
			WorldGen.Thing.VILA:
				_cache[key] = _village_loop()
			_:
				return null
	return _cache[key]


## Água: chiado suave com bolhas que sobem de tom.
static func _water_loop() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var count := RATE * 2
	var samples := _filtered_noise(count, 0.6, 0.08, rng)
	for b in 9:
		var start := rng.randi_range(0, count - 2000)
		var freq := rng.randf_range(500.0, 900.0)
		for i in 1800:
			var t := float(i) / RATE
			var env := sin(PI * i / 1800.0)
			samples[start + i] += sin(TAU * freq * (1.0 + t * 6.0) * t) * env * 0.18
	return _to_wav(samples, true)


## Árvore: folhas farfalhando, com ondas lentas de vento.
static func _tree_loop() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 22
	var count := RATE * 3
	var samples := _filtered_noise(count, 0.93, 0.5, rng)
	for i in count:
		samples[i] *= 0.55 + 0.45 * sin(TAU * float(i) / count)
	return _to_wav(samples, true)


## Arbusto de sementes: zumbido de abelhas.
static func _bees_loop() -> AudioStreamWAV:
	var count := RATE * 2
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var t := float(i) / RATE
		var freq := 210.0 + 12.0 * sin(TAU * 3.0 * t)
		var buzz := sin(TAU * freq * t) + 0.5 * sin(TAU * freq * 2.0 * t)
		samples[i] = buzz * (0.6 + 0.4 * sin(TAU * t)) * 0.08
	return _to_wav(samples, true)


## Vila: sininhos numa escala pentatônica, como um sino de vento.
static func _village_loop() -> AudioStreamWAV:
	var notes := [523.25, 587.33, 659.25, 783.99, 880.0, 783.99, 659.25, 587.33]
	var count := RATE * 4
	var samples := PackedFloat32Array()
	samples.resize(count)
	var step := count / notes.size()
	for n in notes.size():
		for i in step:
			var t := float(i) / RATE
			samples[n * step + i] += sin(TAU * notes[n] * t) * exp(-3.0 * t) * 0.22
	return _to_wav(samples, true)


static func _filtered_noise(count: int, smooth: float, volume: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	samples.resize(count)
	var last := 0.0
	for i in count:
		last = lerpf(rng.randf_range(-1.0, 1.0), last, smooth)
		samples[i] = last * volume
	# Suaviza as pontas para o loop não estalar.
	var fade := mini(800, count / 4)
	for i in fade:
		var k := float(i) / fade
		samples[i] *= k
		samples[count - 1 - i] *= k
	return samples


static func _noise_burst(seconds: float, smooth: float, volume: float, noise_seed: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = noise_seed
	var count := int(seconds * RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var last := 0.0
	for i in count:
		var envelope := pow(1.0 - float(i) / count, 2.0)
		last = lerpf(rng.randf_range(-1.0, 1.0), last, smooth)
		samples[i] = last * envelope * volume
	return _to_wav(samples)


static func _tone(freqs: Array, seconds: float, volume: float) -> AudioStreamWAV:
	var count := int(seconds * RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var t := float(i) / RATE
		var envelope := exp(-6.0 * t / seconds)
		var part := mini(int(float(i) / count * freqs.size()), freqs.size() - 1)
		samples[i] = sin(TAU * freqs[part] * t) * envelope * volume
	return _to_wav(samples)


static func _to_wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav
