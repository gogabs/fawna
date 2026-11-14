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


## Clique da bússola (só se faltarem os arquivos de assets/sounds/bussola).
static func compass(kind: String) -> AudioStreamWAV:
	var key := "bussola_" + kind
	if not _cache.has(key):
		var freq: float = {"norte": 2200.0, "sul": 520.0}.get(kind, 1100.0)
		_cache[key] = _tone([freq], 0.06, 0.3 if kind == "colateral" else 0.5)
	return _cache[key]


## Pegou um recurso.
static func pickup() -> AudioStreamWAV:
	if not _cache.has("pickup"):
		_cache["pickup"] = _tone([523.25, 783.99], 0.18, 0.35)
	return _cache["pickup"]


## Som contínuo (em loop) de cada coisa do mundo, para o áudio espacial.
## "level" escolhe uma versão mais cheia da Origem (usada só pela ocarina
## guardada, como reserva).
static func ambient(thing: WorldGen.Thing, level := 0) -> AudioStreamWAV:
	var key := "amb_%d_%d" % [thing, level if thing == WorldGen.Thing.ORIGEM else 0]
	if not _cache.has(key):
		match thing:
			WorldGen.Thing.RIACHO, WorldGen.Thing.LAGO:
				_cache[key] = _water_loop()
			WorldGen.Thing.ARVORE:
				_cache[key] = _tree_loop()
			WorldGen.Thing.ARBUSTO:
				_cache[key] = _bees_loop()
			WorldGen.Thing.ORIGEM:
				_cache[key] = _origin_loop(level)
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


## Origem: sininhos numa escala pentatônica, como um sino de vento. Nos
## níveis mais altos, ganha mais notas, um baixo e passarinhos.
static func _origin_loop(level: int) -> AudioStreamWAV:
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
		# Normaliza: o pico vai a quase o máximo, o volume fica no jogo.
		var peak := 0.0
		for v in samples:
			peak = maxf(peak, absf(v))
		if peak > 0.0:
			for i in count:
				samples[i] *= 0.95 / peak
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


## Recolheu um recurso: cada um com seu toque (só se faltarem os arquivos).
## A argila é um "chape" úmido; o resto usa o toque genérico.
static func pickup_of(item: String) -> AudioStreamWAV:
	if item != "argila":
		return pickup()
	if not _cache.has("coleta_argila"):
		var rng := RandomNumberGenerator.new()
		rng.seed = 404
		var count := int(0.28 * RATE)
		var samples := _filtered_noise(count, 0.92, 0.0, rng)
		var low := 0.0
		for i in count:
			var t := float(i) / RATE
			low = lerpf(rng.randf_range(-1.0, 1.0), low, 0.9)
			var squelch := sin(TAU * (140.0 + 260.0 * t) * t) * exp(-t * 14.0)
			samples[i] = (low * 1.6 * exp(-t * 18.0) + squelch * 0.5) * 0.6
		_cache["coleta_argila"] = _to_wav(samples)
	return _cache["coleta_argila"]


## Som contínuo de cada recurso coletável, gerado por código enquanto não
## houver gravação. Todos bem esparsos e discretos.
static func resource_loop(thing: WorldGen.Thing) -> AudioStreamWAV:
	var key := "recurso_%d" % thing
	if not _cache.has(key):
		match thing:
			WorldGen.Thing.BAMBU:
				_cache[key] = _bamboo_loop()
			WorldGen.Thing.GRAVETOS:
				_cache[key] = _twigs_loop()
			WorldGen.Thing.ARGILA:
				_cache[key] = _clay_loop()
			WorldGen.Thing.ARBUSTO_FRUTAS:
				_cache[key] = _flies_loop()
			_:
				return null
	return _cache[key]


## Colmo oco batendo: dois ou três modos ressonantes que somem rápido.
static func _hollow_knock(samples: PackedFloat32Array, start: int, base: float, volume: float) -> void:
	var modes := [[1.0, 1.0, 38.0], [2.76, 0.45, 60.0], [5.4, 0.2, 90.0]]
	var count := mini(int(0.25 * RATE), samples.size() - start)
	for i in count:
		var t := float(i) / RATE
		var v := 0.0
		for m in modes:
			v += sin(TAU * base * m[0] * t) * m[1] * exp(-t * m[2])
		samples[start + i] += v * volume


## Bambu: colmos batendo uns nos outros ao vento, um rangido grave e longo e
## um fundo de folhas finas.
static func _bamboo_loop() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 808
	var count := RATE * 6
	var samples := _filtered_noise(count, 0.97, 0.05, rng)
	for k in 5:
		var start := rng.randi_range(0, count - RATE / 2)
		var base := rng.randf_range(330.0, 620.0)
		_hollow_knock(samples, start, base, 0.22)
		if rng.randf() < 0.5:  # às vezes um segundo colmo responde logo depois
			_hollow_knock(samples, start + rng.randi_range(1500, 3500), base * rng.randf_range(0.8, 1.25), 0.14)
	# Rangido: um tom grave que oscila, com aspereza.
	var creak_start := rng.randi_range(RATE, count - RATE * 2)
	var creak_len := int(1.1 * RATE)
	var phase := 0.0
	for i in creak_len:
		var k := float(i) / creak_len
		phase += TAU * (95.0 + 25.0 * sin(TAU * 1.3 * k)) / RATE
		var grit := 1.0 if fmod(phase, TAU) < 0.6 else 0.0
		samples[creak_start + i] += (grit - 0.2) * sin(PI * k) * 0.05
	return _to_wav(samples, true)


## Gravetos: estalidos secos, raros, às vezes em pares.
static func _twigs_loop() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 909
	var count := RATE * 5
	var samples := PackedFloat32Array()
	samples.resize(count)
	for k in 7:
		var start := rng.randi_range(0, count - 2000)
		for crack in rng.randi_range(1, 3):
			var at := start + crack * rng.randi_range(400, 1400)
			var length := rng.randi_range(120, 380)
			var last := 0.0
			for i in mini(length, count - at):
				last = lerpf(rng.randf_range(-1.0, 1.0), last, 0.15)
				samples[at + i] += last * pow(1.0 - float(i) / length, 3.0) * 0.35
	return _to_wav(samples, true)


## Argila: barro molhado, com bolhas lentas e gotas que caem no raso.
static func _clay_loop() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1010
	var count := RATE * 5
	var samples := _filtered_noise(count, 0.985, 0.04, rng)
	for k in 4:  # bolhas que estouram: um "blop" que sobe de tom
		var start := rng.randi_range(0, count - 4000)
		var freq := rng.randf_range(110.0, 190.0)
		for i in 3600:
			var t := float(i) / RATE
			samples[start + i] += sin(TAU * freq * (1.0 + t * 9.0) * t) * exp(-t * 22.0) * 0.3
	for k in 5:  # gotas
		var start := rng.randi_range(0, count - 2000)
		var freq := rng.randf_range(900.0, 1500.0)
		for i in 1600:
			var t := float(i) / RATE
			samples[start + i] += sin(TAU * freq * (1.0 + t * 5.0) * t) * exp(-t * 60.0) * 0.12
	return _to_wav(samples, true)


## Frutas: moscas rondando o arbusto, num zumbido baixo que vai e volta.
static func _flies_loop() -> AudioStreamWAV:
	var count := RATE * 4
	var samples := PackedFloat32Array()
	samples.resize(count)
	for fly in [[180.0, 0.7, 0.0], [232.0, 1.1, 1.7], [205.0, 0.45, 3.1]]:
		var phase := 0.0
		for i in count:
			var t := float(i) / RATE
			var freq: float = fly[0] * (1.0 + 0.06 * sin(TAU * 5.0 * t + fly[2]))
			phase += TAU * freq / RATE
			# Cada mosca chega e se afasta, num ciclo que fecha o loop.
			var near := pow(0.5 + 0.5 * sin(TAU * t / 4.0 * (1.0 if fly[1] > 0.6 else 2.0) + fly[2]), 2.0)
			var buzz := sin(phase) + 0.6 * sin(phase * 2.0) + 0.3 * sin(phase * 3.0)
			samples[i] += buzz * near * 0.035
	return _to_wav(samples, true)


## Golpe de machado no bambu: um "toc" oco, com o estalo da lâmina.
static func bamboo_knock() -> AudioStreamWAV:
	if not _cache.has("bambu_golpe"):
		var rng := RandomNumberGenerator.new()
		rng.seed = 1111
		var count := int(0.3 * RATE)
		var samples := PackedFloat32Array()
		samples.resize(count)
		_hollow_knock(samples, 0, 420.0, 0.7)
		var last := 0.0
		for i in 300:
			last = lerpf(rng.randf_range(-1.0, 1.0), last, 0.1)
			samples[i] += last * (1.0 - i / 300.0) * 0.6
		_cache["bambu_golpe"] = _to_wav(samples)
	return _cache["bambu_golpe"]


## A touceira caindo: estalos que se aceleram, um rasgo e os colmos batendo
## no chão.
static func bamboo_fall() -> AudioStreamWAV:
	if not _cache.has("bambu_queda"):
		var rng := RandomNumberGenerator.new()
		rng.seed = 1212
		var count := int(1.8 * RATE)
		var samples := PackedFloat32Array()
		samples.resize(count)
		var at := 0.0
		var gap := 0.18
		while at < 0.7:  # estalos cada vez mais juntos
			var start := int(at * RATE)
			var last := 0.0
			for i in 260:
				last = lerpf(rng.randf_range(-1.0, 1.0), last, 0.2)
				samples[start + i] += last * pow(1.0 - i / 260.0, 2.0) * 0.5
			at += gap
			gap *= 0.75
		var rip_start := int(0.7 * RATE)  # rasgo das fibras e folhas
		var rip_len := int(0.5 * RATE)
		var low := 0.0
		for i in rip_len:
			var k := float(i) / rip_len
			low = lerpf(rng.randf_range(-1.0, 1.0), low, 0.6)
			samples[rip_start + i] += low * sin(PI * k) * 0.45
		for k in 4:  # colmos no chão
			var start := int((1.15 + k * 0.09 + rng.randf_range(0.0, 0.05)) * RATE)
			_hollow_knock(samples, start, rng.randf_range(260.0, 480.0), 0.5 - k * 0.08)
		_cache["bambu_queda"] = _to_wav(samples)
	return _cache["bambu_queda"]


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
