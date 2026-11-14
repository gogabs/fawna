class_name SoundBank
extends RefCounted
## Sons provisórios gerados por código, para o protótipo não depender de
## arquivos de áudio. Serão trocados por sons gravados (ex.: freesound.org, CC0).

const RATE := 22050

static var _cache := {}


## Libera os sons gerados (chamado ao sair da cena do jogo).
static func clear() -> void:
	_cache.clear()


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


## Metrônomo da contagem.
static func tick() -> AudioStreamWAV:
	if not _cache.has("tick"):
		_cache["tick"] = _tone([1320.0], 0.05, 0.4)
	return _cache["tick"]


## Batida do serrote.
static func saw() -> AudioStreamWAV:
	if not _cache.has("saw"):
		_cache["saw"] = _noise_burst(0.16, 0.2, 0.5, 77)
	return _cache["saw"]


## Clique da bússola (só se faltarem os arquivos de assets/sounds/bussola).
static func compass(kind: String) -> AudioStreamWAV:
	var key := "bussola_" + kind
	if not _cache.has(key):
		var freq: float = {"norte": 2200.0, "sul": 520.0}.get(kind, 1100.0)
		_cache[key] = _tone([freq], 0.06, 0.3 if kind == "colateral" else 0.5)
	return _cache[key]


## Acerto no ritmo.
static func tok() -> AudioStreamWAV:
	if not _cache.has("tok"):
		_cache["tok"] = _tone([440.0], 0.08, 0.5)
	return _cache["tok"]


## Pegou um recurso.
static func pickup() -> AudioStreamWAV:
	if not _cache.has("pickup"):
		_cache["pickup"] = _tone([523.25, 783.99], 0.18, 0.35)
	return _cache["pickup"]


## Água caindo na muda.
static func water_splash() -> AudioStreamWAV:
	if not _cache.has("splash"):
		_cache["splash"] = _noise_burst(0.35, 0.5, 0.45, 99)
	return _cache["splash"]


## Uma obra coletiva cresceu.
static func fanfare() -> AudioStreamWAV:
	if not _cache.has("fanfare"):
		_cache["fanfare"] = _tone([523.25, 659.25, 783.99, 1046.5], 1.0, 0.35)
	return _cache["fanfare"]


## Muda do minigame de jardinagem: saudável soa clara; com sede, murcha e
## descendo de tom. "pan" vai de -1 (esquerda) a 1 (direita).
static func seedling(pan: float, thirsty: bool) -> AudioStreamWAV:
	var key := "muda_%.2f_%s" % [pan, thirsty]
	if _cache.has(key):
		return _cache[key]
	var count := int(0.45 * RATE)
	var left := PackedFloat32Array()
	var right := PackedFloat32Array()
	left.resize(count)
	right.resize(count)
	var gain_l := sqrt((1.0 - pan) * 0.5)
	var gain_r := sqrt((1.0 + pan) * 0.5)
	for i in count:
		var t := float(i) / RATE
		var env := exp(-4.0 * t)
		var value: float
		if thirsty:
			var freq := 392.0 * (1.0 - 0.35 * t / 0.45)
			value = sin(TAU * freq * t + 0.8 * sin(TAU * 7.0 * t)) * env * 0.4
		else:
			value = (sin(TAU * 659.25 * t) + 0.3 * sin(TAU * 1318.5 * t)) * env * 0.35
		left[i] = value * gain_l
		right[i] = value * gain_r
	_cache[key] = _to_wav_stereo(left, right)
	return _cache[key]


static func _to_wav_stereo(left: PackedFloat32Array, right: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(left.size() * 4)
	for i in left.size():
		data.encode_s16(i * 4, int(clampf(left[i], -1.0, 1.0) * 32767.0))
		data.encode_s16(i * 4 + 2, int(clampf(right[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = true
	wav.data = data
	return wav


## Som contínuo (em loop) de cada coisa do mundo, para o áudio espacial.
## "level" é o quanto a vila já cresceu (estágios concluídos da horta):
## a vila soa mais cheia e viva a cada obra concluída.
static func ambient(thing: WorldGen.Thing, level := 0) -> AudioStreamWAV:
	var key := "amb_%d_%d" % [thing, level if thing == WorldGen.Thing.VILA else 0]
	if not _cache.has(key):
		match thing:
			WorldGen.Thing.RIACHO, WorldGen.Thing.LAGO:
				_cache[key] = _water_loop()
			WorldGen.Thing.ARVORE:
				_cache[key] = _tree_loop()
			WorldGen.Thing.ARBUSTO:
				_cache[key] = _bees_loop()
			WorldGen.Thing.VILA:
				_cache[key] = _village_loop(level)
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


## Vila: sininhos numa escala pentatônica, como um sino de vento. A cada
## estágio da horta concluído, ganha mais notas, um baixo e passarinhos.
static func _village_loop(level: int) -> AudioStreamWAV:
	var notes := [523.25, 659.25, 783.99, 659.25] if level == 0 else \
		[523.25, 587.33, 659.25, 783.99, 880.0, 783.99, 659.25, 587.33]
	var count := RATE * 4
	var samples := PackedFloat32Array()
	samples.resize(count)
	var step := count / notes.size()
	for n in notes.size():
		for i in step:
			var t := float(i) / RATE
			samples[n * step + i] += sin(TAU * notes[n] * t) * exp(-3.0 * t) * 0.22
	if level >= 2:
		for i in count:
			var t := float(i) / RATE
			samples[i] += sin(TAU * 130.81 * t) * 0.06 * (0.5 + 0.5 * sin(TAU * t / 4.0))
	if level >= 3:
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		for b in 6:
			var start := rng.randi_range(0, count - 3000)
			for i in 2600:
				var t := float(i) / RATE
				var freq := 2600.0 + 900.0 * sin(TAU * 18.0 * t)
				samples[start + i] += sin(TAU * freq * t) * sin(PI * i / 2600.0) * 0.07
	return _to_wav(samples, true)


## Batida do Caminheiro: tambor bem abafado, em duas pancadas, como um
## coração ("tum-tum"). Tem um grave que cai de tom e um pouco de pele
## abafada (médios), sem o que o HRTF não consegue dizer de onde vem.
static func heartbeat() -> AudioStreamWAV:
	if not _cache.has("coracao"):
		var count := int(0.62 * RATE)
		var samples := PackedFloat32Array()
		samples.resize(count)
		var rng := RandomNumberGenerator.new()
		rng.seed = 2718
		for hit in [[0.0, 1.0], [0.24, 0.72]]:
			var start := int(hit[0] * RATE)
			var phase := 0.0
			var skin := 0.0
			for i in range(start, count):
				var t := float(i - start) / RATE
				var freq := 58.0 + 70.0 * exp(-t * 28.0)
				phase += TAU * freq / RATE
				skin = lerpf(rng.randf_range(-1.0, 1.0), skin, 0.82)
				var body := sin(phase) * exp(-t * 16.0)
				var thump := skin * exp(-t * 55.0) * 0.9
				samples[i] += (body + thump) * hit[1] * 0.55
		_cache["coracao"] = _to_wav(samples)
	return _cache["coracao"]


## Woosh do Caminheiro: um sopro que cresce e some, abrindo e fechando o
## brilho no meio. Quem toca move a fonte rumo ao próximo beacon.
static func woosh() -> AudioStreamWAV:
	if not _cache.has("woosh"):
		var count := int(0.75 * RATE)
		var samples := PackedFloat32Array()
		samples.resize(count)
		var rng := RandomNumberGenerator.new()
		rng.seed = 31415
		var low := 0.0
		var band := 0.0
		for i in count:
			var k := float(i) / count
			var envelope := pow(sin(PI * pow(k, 0.7)), 2.0)
			# Mais aberto (menos suavizado) no meio do sopro.
			var smooth := lerpf(0.97, 0.8, envelope)
			low = lerpf(rng.randf_range(-1.0, 1.0), low, smooth)
			band = lerpf(low, band, 0.6)
			samples[i] = (low - band * 0.5) * envelope * 1.4
		_cache["woosh"] = _to_wav(samples)
	return _cache["woosh"]


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
