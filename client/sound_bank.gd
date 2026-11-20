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
		if WorldGen.COLD_BIOMES.has(biome):
			_cache[key] = _noise_burst(0.16, 0.6, 0.5, 1234 + biome)  # neve: mais longo, rangido
		elif biome == WorldGen.Biome.MAR:
			_cache[key] = _noise_burst(0.12, 0.2, 0.35, 1234 + biome)  # areia: chiado leve
		else:
			var smooth := 0.85 if biome == WorldGen.Biome.BOSQUE or biome == WorldGen.Biome.BAMBUZAL else 0.35
			_cache[key] = _noise_burst(0.09, smooth, 0.55, 1234 + biome)
	return _cache[key]


## Fundo (em loop) dos biomas que ainda não têm gravação: o mar e o frio.
## Nulo para os outros.
static func biome_bed(biome: WorldGen.Biome) -> AudioStreamWAV:
	var key := "fundo_%d" % biome
	if not _cache.has(key):
		match biome:
			WorldGen.Biome.MAR:
				_cache[key] = _sea_loop()
			WorldGen.Biome.FLORESTA_GELADA:
				_cache[key] = _cold_wind_loop(false)
			WorldGen.Biome.DESERTO_GELADO, WorldGen.Biome.MONTANHA:
				_cache[key] = _cold_wind_loop(true)
			_:
				return null
	return _cache[key]


const BED_SECONDS := 6

## Grilos da noite (em loop, 8 s): três grilos de alturas diferentes, cada um
## com a sua cantiga, um trinado de pulsinhos curtos que se repete. Os
## períodos cabem inteiros no loop, então ele fecha sem emenda.
static func crickets() -> AudioStreamWAV:
	if _cache.has("grilos"):
		return _cache["grilos"]
	var seconds := 8
	var count := RATE * seconds
	var samples := PackedFloat32Array()
	samples.resize(count)
	# [altura em Hz, chirps no loop, pulsos por chirp, volume, atraso em s]
	var singers := [[4300.0, 16, 4, 0.05, 0.0], [3700.0, 11, 3, 0.04, 0.21], [4900.0, 13, 5, 0.03, 0.37]]
	for singer in singers:
		var chirp_period: float = float(seconds) / int(singer[1])
		var pulses: int = singer[2]
		var pulse_period := 0.034
		var pulse_len := 0.017
		for i in count:
			var t := fposmod(float(i) / RATE - float(singer[4]), float(seconds))
			var local := fposmod(t, chirp_period)
			var n := int(local / pulse_period)
			if n >= pulses:
				continue
			var in_pulse := local - n * pulse_period
			if in_pulse >= pulse_len:
				continue
			var env := sin(PI * in_pulse / pulse_len)
			# O trinado cresce e some em arco; o grilo oscila um pouco de altura.
			var arc := sin(PI * (n + 0.5) / pulses)
			var freq: float = singer[0] * (1.0 + 0.01 * sin(TAU * t * 0.7))
			samples[i] += sin(TAU * freq * t) * env * env * arc * float(singer[3])
	var peak := 0.0
	for value in samples:
		peak = maxf(peak, absf(value))
	for i in count:
		samples[i] = samples[i] / peak * 0.5
	_cache["grilos"] = _to_wav(samples, true)
	return _cache["grilos"]


## Sapinhos da lagoa (em loop, 8 s): um coro de pios agudos e curtos que
## sobem de altura (como um sapinho-de-primavera), em duas vozes, e de vez em
## quando um coaxar grave de sapo grande, feito de pulsos rápidos. Os
## períodos cabem inteiros no loop.
static func frogs() -> AudioStreamWAV:
	if _cache.has("sapos"):
		return _cache["sapos"]
	var seconds := 8
	var count := RATE * seconds
	var samples := PackedFloat32Array()
	samples.resize(count)
	# Pios: [altura inicial em Hz, quantos no loop, atraso em s, volume]
	for peeper in [[2500.0, 14, 0.0, 0.05], [2900.0, 11, 0.31, 0.04]]:
		var period: float = float(seconds) / int(peeper[1])
		var length := 0.085
		for i in count:
			var t := fposmod(float(i) / RATE - float(peeper[2]), float(seconds))
			var local := fposmod(t, period)
			if local >= length:
				continue
			var x := local / length
			# Sobe uns 30% durante o pio.
			var phase := TAU * float(peeper[0]) * (local + 0.15 * length * x * x)
			samples[i] += sin(phase) * sin(PI * x) * float(peeper[3])
	# Coaxares: [altura em Hz, quantos no loop, atraso em s, volume]
	for croaker in [[170.0, 3, 1.1, 0.12], [210.0, 2, 4.3, 0.09]]:
		var period: float = float(seconds) / int(croaker[1])
		var length := 0.32
		for i in count:
			var t := fposmod(float(i) / RATE - float(croaker[2]), float(seconds))
			var local := fposmod(t, period)
			if local >= length:
				continue
			var x := local / length
			var pulses := 0.5 + 0.5 * sin(TAU * 38.0 * local)
			var freq: float = croaker[0] * (1.0 - 0.18 * x)
			var voice := sin(TAU * freq * local) + 0.4 * sin(TAU * freq * 2.0 * local)
			samples[i] += voice * pulses * sin(PI * x) * float(croaker[3])
	var peak := 0.0
	for value in samples:
		peak = maxf(peak, absf(value))
	for i in count:
		samples[i] = samples[i] / peak * 0.5
	_cache["sapos"] = _to_wav(samples, true)
	return _cache["sapos"]


## Mar: uma onda grave e lenta que cresce, quebra num chiado e recua. O loop
## fecha no ponto mais baixo, entre uma onda e outra.
static func _sea_loop() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var count := RATE * BED_SECONDS
	var deep := _filtered_noise(count, 0.97, 1.0, rng)
	var foam := _filtered_noise(count, 0.55, 1.0, rng)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var phase := float(i) / count
		var swell := pow(0.5 - 0.5 * cos(TAU * phase), 2.0)
		# A espuma vem um pouco depois do pico da onda e some depressa.
		var crash := pow(maxf(0.0, 0.5 - 0.5 * cos(TAU * (phase - 0.08))), 6.0)
		samples[i] = deep[i] * (0.5 + 2.2 * swell) + foam[i] * 0.1 * crash
	return _to_wav(samples, true)


## Vento frio: sopro grave com rajadas lentas. No deserto gelado ("open") ele
## é mais fino e traz um assobio distante; na floresta gelada, mais abafado.
static func _cold_wind_loop(open: bool) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 47 if open else 53
	var count := RATE * BED_SECONDS
	var low := _filtered_noise(count, 0.985 if not open else 0.96, 1.0, rng)
	var high := _filtered_noise(count, 0.8, 1.0, rng)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var whistle_phase := 0.0
	for i in count:
		var phase := float(i) / count
		# Rajadas: somas de ondas que cabem inteiras no loop.
		var gust := 0.55 + 0.3 * sin(TAU * phase - 1.0) + 0.15 * sin(TAU * 3.0 * phase + 0.7)
		var value := low[i] * (2.5 if not open else 1.2) * gust
		if open:
			value += high[i] * 0.05 * gust * gust
			whistle_phase += TAU * (840.0 + 60.0 * sin(TAU * 2.0 * phase)) / RATE
			value += sin(whistle_phase) * 0.012 * maxf(0.0, gust - 0.5) * (0.5 - 0.5 * cos(TAU * phase))
		samples[i] = value
	return _to_wav(samples, true)


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


## Limite do menu flutuante (Baixo já na raiz): notinha descendente rápida de
## interface, sem nada de colisão.
static func ui_limit() -> AudioStreamWAV:
	if not _cache.has("ui_limit"):
		# Notinha descendente de uns 70 ms: a altura cai de 330 para 150 Hz, com
		# ataque grave forte (um golpe de 90 Hz que morre em 20 ms) e cauda curta.
		var seconds := 0.07
		var count := int(seconds * RATE)
		var samples := PackedFloat32Array()
		samples.resize(count)
		var phase := 0.0
		for i in count:
			var t := float(i) / RATE
			phase += TAU * lerpf(330.0, 150.0, t / seconds) / RATE
			var body := sin(phase) * exp(-5.0 * t / seconds) * minf(t / 0.002, 1.0)
			var thump := sin(TAU * 90.0 * t) * exp(-t / 0.012)
			samples[i] = (body * 0.5 + thump * 0.45) * minf((seconds - t) / 0.01, 1.0)
		_cache["ui_limit"] = _to_wav(samples)
	return _cache["ui_limit"]


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
static func ambient(thing: WorldGen.Thing) -> AudioStreamWAV:
	var key := "amb_%d" % thing
	if not _cache.has(key):
		match thing:
			WorldGen.Thing.RIACHO, WorldGen.Thing.RIO, WorldGen.Thing.VAU, WorldGen.Thing.LAGO, WorldGen.Thing.MAR, WorldGen.Thing.CHARCO:
				_cache[key] = _water_loop()
			WorldGen.Thing.ARBUSTO, WorldGen.Thing.ARBUSTO_FRUTAS:
				_cache[key] = _bees_loop()
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


## Sininhos numa escala pentatônica, como um sino de vento: a musiquinha de
## reserva quando faltam os arquivos. Nos níveis mais altos, ganha mais notas,
## um baixo e passarinhos.
static func bells_loop(level: int) -> AudioStreamWAV:
	var key := "sinos_%d" % level
	if not _cache.has(key):
		_cache[key] = _bells_build(level)
	return _cache[key]


static func _bells_build(level: int) -> AudioStreamWAV:
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


## Machado cortando o ar: um sopro curto.
static func axe_swing() -> AudioStreamWAV:
	if not _cache.has("machado_golpe"):
		_cache["machado_golpe"] = _noise_burst(0.22, 0.75, 0.6, 4242)
	return _cache["machado_golpe"]


## Lâmina batendo em algo duro: estalo seco com um corpo grave.
static func axe_hit() -> AudioStreamWAV:
	if not _cache.has("machado_impacto"):
		var noise := _noise_burst(0.12, 0.3, 0.7, 515)
		var body := _tone([180.0], 0.12, 0.5)
		_cache["machado_impacto"] = _mix(noise, body)
	return _cache["machado_impacto"]


## A coisa cede no último golpe: um estalo longo que se arrasta.
static func axe_break() -> AudioStreamWAV:
	if not _cache.has("machado_quebra"):
		_cache["machado_quebra"] = _noise_burst(0.6, 0.55, 0.7, 616)
	return _cache["machado_quebra"]


## Pegar o machado da bolsa (couro e madeira) e guardar de volta.
static func wield() -> AudioStreamWAV:
	if not _cache.has("empunhar"):
		_cache["empunhar"] = _noise_burst(0.18, 0.5, 0.45, 717)
	return _cache["empunhar"]


static func stow() -> AudioStreamWAV:
	if not _cache.has("guardar"):
		_cache["guardar"] = _noise_burst(0.25, 0.8, 0.45, 818)
	return _cache["guardar"]


## Mudança de região: um sopro de ar grave que sobe e some, com duas notas
## ocas e distantes (uma quinta sem terça: nem alegre, nem triste).
static func region_change() -> AudioStreamWAV:
	if not _cache.has("regiao"):
		var rng := RandomNumberGenerator.new()
		rng.seed = 4801
		var seconds := 1.4
		var count := int(seconds * RATE)
		var samples := PackedFloat32Array()
		samples.resize(count)
		var air := 0.0
		var air2 := 0.0
		for i in count:
			var t := float(i) / RATE
			var swell := sin(PI * minf(t / seconds, 1.0)) ** 2.0
			air = lerpf(rng.randf_range(-1.0, 1.0), air, 0.985)
			air2 = lerpf(air, air2, 0.9)
			var first := sin(TAU * 98.0 * t) * exp(-t * 3.2) * minf(t / 0.05, 1.0)
			var later := maxf(t - 0.32, 0.0)
			var second := sin(TAU * 146.83 * later) * exp(-later * 3.6) * minf(later / 0.05, 1.0) if later > 0.0 else 0.0
			samples[i] = air2 * swell * 4.0 + first * 0.4 + second * 0.3
		_cache["regiao"] = _to_wav(samples)
	return _cache["regiao"]


## Item largado no chão: um baque surdo e curto, com um pouco de poeira.
static func drop_item() -> AudioStreamWAV:
	if not _cache.has("largar"):
		var rng := RandomNumberGenerator.new()
		rng.seed = 3303
		var count := int(0.3 * RATE)
		var samples := PackedFloat32Array()
		samples.resize(count)
		var low := 0.0
		for i in count:
			var t := float(i) / RATE
			var thud := sin(TAU * (130.0 - 50.0 * t) * t) * exp(-t * 22.0)
			low = lerpf(rng.randf_range(-1.0, 1.0), low, 0.7)
			samples[i] = (thud * 0.7 + low * exp(-t * 20.0) * 0.4) * 0.6
		_cache["largar"] = _to_wav(samples)
	return _cache["largar"]


## Monte de itens no chão: um tique macio e baixo, de tempos em tempos, para
## achá-lo de ouvido (em loop de 3 s; só se faltar o arquivo).
static func pile_loop() -> AudioStreamWAV:
	if not _cache.has("monte"):
		var count := int(3.0 * RATE)
		var samples := PackedFloat32Array()
		samples.resize(count)
		for tick in [[0.4, 520.0, 0.5], [1.3, 410.0, 0.4], [2.2, 620.0, 0.45]]:
			var start := int(float(tick[0]) * RATE)
			for i in int(0.18 * RATE):
				var t := float(i) / RATE
				samples[start + i] += sin(TAU * float(tick[1]) * t) * exp(-t * 28.0) * float(tick[2]) * 0.5
		_cache["monte"] = _to_wav(samples, true)
	return _cache["monte"]


## --- Construções e fogo ---------------------------------------------------------

## Pedra batendo em pedra: um "clac" curto e brilhante, com um corpo médio.
static func stone_knock() -> AudioStreamWAV:
	if not _cache.has("pedra_batida"):
		var rng := RandomNumberGenerator.new()
		rng.seed = 2101
		var count := int(0.22 * RATE)
		var samples := PackedFloat32Array()
		samples.resize(count)
		for i in count:
			var t := float(i) / RATE
			var ring := sin(TAU * 1850.0 * t) * 0.5 + sin(TAU * 2730.0 * t) * 0.3 + sin(TAU * 4100.0 * t) * 0.2
			var body := sin(TAU * 520.0 * t) * exp(-t * 35.0) * 0.4
			var click := rng.randf_range(-1.0, 1.0) * exp(-t * 400.0)
			samples[i] = (ring * exp(-t * 55.0) + body + click * 0.8) * 0.55
		_cache["pedra_batida"] = _to_wav(samples)
	return _cache["pedra_batida"]


## Pedra (ou material) assentada na obra: baque grave com cascalho.
static func stone_place() -> AudioStreamWAV:
	if not _cache.has("pedra_assentada"):
		var rng := RandomNumberGenerator.new()
		rng.seed = 2202
		var count := int(0.4 * RATE)
		var samples := PackedFloat32Array()
		samples.resize(count)
		var low := 0.0
		for i in count:
			var t := float(i) / RATE
			var thud := sin(TAU * (95.0 - 30.0 * t) * t) * exp(-t * 14.0)
			low = lerpf(rng.randf_range(-1.0, 1.0), low, 0.55)
			var gravel := low * exp(-t * 9.0) * (0.6 + 0.4 * sin(TAU * 31.0 * t))
			samples[i] = (thud * 0.8 + gravel * 0.45) * 0.7
		_cache["pedra_assentada"] = _to_wav(samples)
	return _cache["pedra_assentada"]


## Etapa concluída: duas pedras e um tom curto subindo.
static func build_stage() -> AudioStreamWAV:
	if not _cache.has("obra_etapa"):
		_cache["obra_etapa"] = _mix(stone_place(), _tone([392.0, 523.25], 0.4, 0.3))
	return _cache["obra_etapa"]


## Obra pronta: um acorde de três notas.
static func build_done() -> AudioStreamWAV:
	if not _cache.has("obra_pronta"):
		_cache["obra_pronta"] = _tone([392.0, 493.88, 587.33, 783.99], 0.9, 0.35)
	return _cache["obra_pronta"]


## Pedra contra pedra soltando faíscas: o clac mais um chiado agudo.
static func fire_spark() -> AudioStreamWAV:
	if not _cache.has("fogo_faisca"):
		var rng := RandomNumberGenerator.new()
		rng.seed = 2303
		var count := int(0.3 * RATE)
		var samples := PackedFloat32Array()
		samples.resize(count)
		var knock := stone_knock()
		var prev := 0.0
		for i in count:
			var t := float(i) / RATE
			var n := rng.randf_range(-1.0, 1.0)
			var hiss := (n - prev) * 0.5  # só os agudos
			prev = n
			samples[i] = hiss * exp(-t * 18.0) * 0.5
			if i * 2 < knock.data.size():
				samples[i] += knock.data.decode_s16(i * 2) / 32767.0
		_cache["fogo_faisca"] = _to_wav(samples)
	return _cache["fogo_faisca"]


## A chama pegando: um sopro que cresce e abre em estalos.
static func fire_ignite() -> AudioStreamWAV:
	if not _cache.has("fogo_acender"):
		var rng := RandomNumberGenerator.new()
		rng.seed = 2404
		var count := int(1.4 * RATE)
		var samples := PackedFloat32Array()
		samples.resize(count)
		var low := 0.0
		for i in count:
			var t := float(i) / RATE
			var swell := minf(t / 0.5, 1.0) * exp(-maxf(t - 0.5, 0.0) * 2.5)
			low = lerpf(rng.randf_range(-1.0, 1.0), low, 0.82 - 0.3 * minf(t / 0.5, 1.0))
			samples[i] = low * swell * 0.7
		_add_crackles(samples, rng, 0.4, 1.3, 14, 0.5)
		_cache["fogo_acender"] = _to_wav(samples)
	return _cache["fogo_acender"]


## Lenha entrando no fogo: madeira batendo e um chiado que sobe.
static func fire_feed() -> AudioStreamWAV:
	if not _cache.has("fogo_lenha"):
		var rng := RandomNumberGenerator.new()
		rng.seed = 2505
		var count := int(0.8 * RATE)
		var samples := PackedFloat32Array()
		samples.resize(count)
		_hollow_knock(samples, 0, 230.0, 0.6)
		_add_crackles(samples, rng, 0.15, 0.75, 8, 0.4)
		_cache["fogo_lenha"] = _to_wav(samples)
	return _cache["fogo_lenha"]


## A fogueira apagando: o crepitar morrendo num chiado.
static func fire_out() -> AudioStreamWAV:
	if not _cache.has("fogo_apagar"):
		var rng := RandomNumberGenerator.new()
		rng.seed = 2606
		var count := int(1.6 * RATE)
		var samples := PackedFloat32Array()
		samples.resize(count)
		var low := 0.0
		for i in count:
			var t := float(i) / RATE
			low = lerpf(rng.randf_range(-1.0, 1.0), low, 0.7)
			samples[i] = low * exp(-t * 2.2) * 0.35
		_add_crackles(samples, rng, 0.0, 0.8, 6, 0.3)
		_cache["fogo_apagar"] = _to_wav(samples)
	return _cache["fogo_apagar"]


## Crepitar contínuo da fogueira acesa (loop de 4 s): um rumor grave e
## estalos soltos de tamanhos variados.
static func fire_loop() -> AudioStreamWAV:
	if not _cache.has("fogo_crepitar"):
		var rng := RandomNumberGenerator.new()
		rng.seed = 2707
		var count := int(4.0 * RATE)
		var samples := _filtered_noise(count, 0.97, 0.55, rng)
		var flutter := 0.0
		for i in count:
			var t := float(i) / RATE
			flutter = lerpf(rng.randf_range(0.6, 1.0), flutter, 0.999)
			samples[i] *= flutter * (0.85 + 0.15 * sin(TAU * 0.5 * t))
		_add_crackles(samples, rng, 0.05, 3.9, 40, 0.45)
		_cache["fogo_crepitar"] = _to_wav(samples, true)
	return _cache["fogo_crepitar"]


## Estalos de fogo: rajadas curtíssimas e brilhantes entre "from" e "to"
## segundos, de intensidade sorteada.
static func _add_crackles(samples: PackedFloat32Array, rng: RandomNumberGenerator, from: float, to: float, amount: int, volume: float) -> void:
	for k in amount:
		var start := int(rng.randf_range(from, to) * RATE)
		var length := rng.randi_range(40, 260)
		var strength := rng.randf_range(0.25, 1.0) * volume
		var prev := 0.0
		for i in length:
			if start + i >= samples.size():
				break
			var n := rng.randf_range(-1.0, 1.0)
			samples[start + i] += (n - prev * 0.6) * strength * pow(1.0 - float(i) / length, 3.0)
			prev = n


## Soma dois sons gerados (mono, mesma taxa).
static func _mix(a: AudioStreamWAV, b: AudioStreamWAV) -> AudioStreamWAV:
	var count := maxi(a.data.size(), b.data.size()) / 2
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var sa := a.data.decode_s16(i * 2) / 32767.0 if i * 2 < a.data.size() else 0.0
		var sb := b.data.decode_s16(i * 2) / 32767.0 if i * 2 < b.data.size() else 0.0
		samples[i] = sa + sb
	return _to_wav(samples)


## Recolheu um recurso: cada um com seu toque (só se faltarem os arquivos).
## A argila é um "chape" úmido; o resto usa o toque genérico.
static func pickup_of(item: String) -> AudioStreamWAV:
	if item == "pedra":
		return stone_pickup()
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


## Pedras recolhidas: três toques secos de pedra contra pedra, enquanto não
## houver gravação (assets/sounds/recursos/coleta_pedra_N.ogg).
static func stone_pickup() -> AudioStreamWAV:
	if not _cache.has("coleta_pedra"):
		var rng := RandomNumberGenerator.new()
		rng.seed = 707
		var count := int(0.36 * RATE)
		var samples := PackedFloat32Array()
		samples.resize(count)
		for hit in [[0.0, 1.0, 1900.0], [0.11, 0.7, 2300.0], [0.2, 0.85, 1600.0]]:
			var start := int(float(hit[0]) * RATE)
			var low := 0.0
			for i in range(start, count):
				var t := float(i - start) / RATE
				if t > 0.08:
					break
				low = lerpf(rng.randf_range(-1.0, 1.0), low, 0.55)
				var ring := sin(TAU * float(hit[2]) * t) * exp(-t * 90.0)
				samples[i] += (low * exp(-t * 160.0) * 0.9 + ring * 0.5) * float(hit[1]) * 0.55
		_cache["coleta_pedra"] = _to_wav(samples)
	return _cache["coleta_pedra"]


## Som contínuo de cada recurso coletável, gerado por código enquanto não
## houver gravação. Todos bem esparsos e discretos.
static func resource_loop(thing: WorldGen.Thing) -> AudioStreamWAV:
	var key := "recurso_%d" % thing
	if not _cache.has(key):
		match thing:
			WorldGen.Thing.BAMBU:
				_cache[key] = _bamboo_loop()
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
			gap = maxf(gap * 0.75, 0.04)
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


## Golpe de machado no tronco: uma pancada grave e seca, de madeira maciça.
static func tree_knock() -> AudioStreamWAV:
	if not _cache.has("arvore_golpe"):
		var rng := RandomNumberGenerator.new()
		rng.seed = 1313
		var count := int(0.35 * RATE)
		var samples := PackedFloat32Array()
		samples.resize(count)
		_hollow_knock(samples, 0, 135.0, 0.8)
		_hollow_knock(samples, 0, 210.0, 0.35)
		var last := 0.0
		for i in 500:  # lascas
			last = lerpf(rng.randf_range(-1.0, 1.0), last, 0.35)
			samples[i] += last * pow(1.0 - i / 500.0, 2.0) * 0.7
		_cache["arvore_golpe"] = _to_wav(samples)
	return _cache["arvore_golpe"]


## O tronco rangendo: toca junto com os últimos golpes, avisando que a
## árvore está para cair.
static func tree_creak() -> AudioStreamWAV:
	if not _cache.has("arvore_rangido"):
		var rng := RandomNumberGenerator.new()
		rng.seed = 1414
		var count := int(0.9 * RATE)
		var samples := PackedFloat32Array()
		samples.resize(count)
		_add_creak(samples, 0, count, 70.0, 0.3)
		_add_crackles(samples, rng, 0.1, 0.7, 5, 0.25)
		_cache["arvore_rangido"] = _to_wav(samples)
	return _cache["arvore_rangido"]


## A árvore caindo: o tronco range e estala, a copa desce rasgando o ar e
## tudo bate no chão, com galhos quebrando.
static func tree_fall() -> AudioStreamWAV:
	if not _cache.has("arvore_queda"):
		var rng := RandomNumberGenerator.new()
		rng.seed = 1515
		var count := int(3.6 * RATE)
		var samples := PackedFloat32Array()
		samples.resize(count)
		_add_creak(samples, 0, int(1.3 * RATE), 60.0, 0.35)
		var at := 0.15
		var gap := 0.3
		while at < 1.3:  # estalos cada vez mais juntos
			_add_crackles(samples, rng, at, at + 0.02, 1, 0.7)
			at += gap
			gap = maxf(gap * 0.72, 0.04)  # sem piso, "at" nunca chegaria a 1,3
		var rush_start := int(1.2 * RATE)  # a copa descendo
		var rush_len := int(1.1 * RATE)
		var low := 0.0
		for i in rush_len:
			var k := float(i) / rush_len
			low = lerpf(rng.randf_range(-1.0, 1.0), low, 0.55 - 0.3 * k)
			samples[rush_start + i] += low * k * k * 0.5
		var thud_start := int(2.3 * RATE)  # o tronco no chão
		var thud_len := int(0.9 * RATE)
		for i in thud_len:
			var t := float(i) / RATE
			samples[thud_start + i] += sin(TAU * (62.0 - 20.0 * t) * t) * exp(-t * 6.0) * 0.9
			low = lerpf(rng.randf_range(-1.0, 1.0), low, 0.8)
			samples[thud_start + i] += low * exp(-t * 5.0) * 0.6
		_hollow_knock(samples, thud_start, 110.0, 0.6)
		_add_crackles(samples, rng, 2.3, 3.2, 14, 0.45)  # galhos quebrando
		_cache["arvore_queda"] = _to_wav(samples)
	return _cache["arvore_queda"]


## Rangido de madeira: um tom grave e áspero que oscila.
static func _add_creak(samples: PackedFloat32Array, start: int, length: int, base: float, volume: float) -> void:
	var phase := 0.0
	for i in length:
		if start + i >= samples.size():
			break
		var k := float(i) / length
		phase += TAU * (base + base * 0.3 * sin(TAU * 1.7 * k) + base * 0.4 * k) / RATE
		var grit := 1.0 if fmod(phase, TAU) < 0.6 else 0.0
		samples[start + i] += (grit - 0.2) * sin(PI * k) * volume


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
