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
