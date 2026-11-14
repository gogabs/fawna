class_name BirdSongs
extends RefCounted
## Cantos e asas dos pássaros, gerados por código (sons do próprio projeto).
##
## A ideia é que soem selvagens e discretos, não fofos: assobios puros e
## lentos em intervalos menores, com uma segunda voz fraca, quase inumana
## (pássaros cantam com duas "gargantas" ao mesmo tempo), e um pouco de eco
## de mata. Cada som é gerado na primeira vez e guardado.
##
## Para trocar por gravações, ponha arquivos em assets/sounds/passaros/ com
## o nome <espécie>_<n>.ogg (ex.: sabia_0.ogg) ou <espécie>_asas.ogg; se
## existirem, são usados no lugar dos gerados.

const RATE := 32000
const DIR := "res://assets/sounds/passaros/"
const FILE_NAMES := {Aviary.Species.SABIA: "sabia", Aviary.Species.CARRICA: "carrica", Aviary.Species.ROLINHA: "rolinha"}

static var _cache := {}


static func clear() -> void:
	_cache.clear()


## Um dos cantos da espécie.
static func song(species: int, index: int) -> AudioStream:
	var key := "%s_%d" % [FILE_NAMES[species], index]
	if _cache.has(key):
		return _cache[key]
	var stream: AudioStream = _file(key)
	if stream == null:
		var buf := PackedFloat32Array()
		match species:
			Aviary.Species.SABIA:
				buf = _sabia(index)
			Aviary.Species.CARRICA:
				buf = _carrica(index)
			Aviary.Species.ROLINHA:
				buf = _rolinha(index)
		stream = _to_wav(_with_tail(buf, 0.55 if species == Aviary.Species.SABIA else 0.35))
	_cache[key] = stream
	return stream


## Grito curto de susto, ao fugir de alguém (só sabiá e carriça).
static func alarm(species: int) -> AudioStream:
	if species == Aviary.Species.ROLINHA:
		return null
	var key := "%s_alarme" % FILE_NAMES[species]
	if _cache.has(key):
		return _cache[key]
	var stream: AudioStream = _file(key)
	if stream == null:
		var buf := _buffer(0.5)
		if species == Aviary.Species.SABIA:
			# "Tchuk tchuk": dois estalos secos, graves para um sabiá.
			for i in 2:
				_note(buf, i * 0.16, 0.05, 1650.0, 1150.0, 0.5, {"h2": 0.35, "h3": 0.2, "breath": 0.25, "attack": 0.004})
		else:
			# Três "tchets" ásperos e rápidos.
			for i in 3:
				_note(buf, i * 0.07, 0.035, 5200.0, 3900.0, 0.35, {"h2": 0.2, "breath": 0.45, "attack": 0.002})
		stream = _to_wav(_with_tail(buf, 0.25))
	_cache[key] = stream
	return stream


## Bater de asas de um voo de "seconds" segundos: a decolagem forte, o voo
## (as carriças voam em ondas, batendo e planando; a rolinha assobia com as
## asas) e as batidas de freio ao pousar, com um farfalhar de folhas.
static func wings(species: int, seconds: float, startled := false) -> AudioStream:
	seconds = clampf(snappedf(seconds, 0.25), 0.5, 5.0)
	var key := "%s_asas_%.2f_%s" % [FILE_NAMES[species], seconds, startled]
	if _cache.has(key):
		return _cache[key]
	var file: AudioStream = _file("%s_asas" % FILE_NAMES[species])
	if file != null:
		_cache[key] = file
		return file
	var rate: float = {Aviary.Species.SABIA: 13.0, Aviary.Species.CARRICA: 21.0, Aviary.Species.ROLINHA: 9.0}[species]
	var body: float = {Aviary.Species.SABIA: 0.75, Aviary.Species.CARRICA: 0.55, Aviary.Species.ROLINHA: 0.85}[species]
	var buf := _buffer(seconds + 0.3)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var takeoff := 0.55 if startled else 0.35
	var t := 0.0
	while t < seconds:
		var level := 0.0
		if t < takeoff:
			level = 1.0 if startled else 0.8
		elif t > seconds - 0.25:
			level = 0.7  # freando para pousar
		else:
			level = 0.35
			if species == Aviary.Species.CARRICA and fmod(t - takeoff, 0.55) > 0.25:
				level = 0.0  # planando
		if level > 0.0:
			_flap(buf, t, 0.55 / rate, level * rng.randf_range(0.8, 1.0), body, rng)
			if species == Aviary.Species.ROLINHA:
				_note(buf, t, 0.5 / rate, 1250.0, 1180.0, 0.05 * level, {"attack": 0.01, "breath": 0.6})
		t += 1.0 / rate * rng.randf_range(0.93, 1.07)
	# Pouso: um farfalhar curto de folhas.
	_flap(buf, seconds, 0.18, 0.35, 0.4, rng)
	var stream := _to_wav(buf)
	_cache[key] = stream
	return stream


# --- Espécies ------------------------------------------------------------------

## Sabiá-da-névoa: uma nota longa e pura e um grupo de notas rápidas,
## etéreas, descendo em intervalos menores. Lento, com pausas longas.
static func _sabia(index: int) -> PackedFloat32Array:
	var buf := _buffer(1.6)
	var pure := {"h2": 0.12, "h3": 0.03, "breath": 0.05, "vib_rate": 5.0, "vib": 0.004, "dual": 0.12}
	var flutter := {"h2": 0.1, "breath": 0.04, "vib_rate": 32.0, "vib": 0.012, "dual": 0.1}
	match index % 4:
		0:
			_note(buf, 0.0, 0.46, 1700.0, 1760.0, 0.55, pure)
			var notes := [2350.0, 2217.0, 1976.0]
			for i in notes.size():
				_note(buf, 0.56 + i * 0.12, 0.1, notes[i], notes[i] * 0.97, 0.35, flutter)
		1:
			_note(buf, 0.0, 0.52, 1480.0, 1395.0, 0.55, pure)
			_note(buf, 0.64, 0.15, 1976.0, 1865.0, 0.4, flutter)
			_note(buf, 0.82, 0.18, 1661.0, 1600.0, 0.32, flutter)
		2:
			_note(buf, 0.0, 0.36, 2093.0, 2060.0, 0.5, pure)
			_note(buf, 0.42, 0.5, 1760.0, 1640.0, 0.45, pure.merged({"curve": 3.0}))
		3:
			_note(buf, 0.0, 0.5, 1319.0, 1568.0, 0.5, pure.merged({"curve": 0.6}))
			_note(buf, 0.68, 0.13, 2637.0, 2560.0, 0.22, flutter)
	return buf


## Carriça-do-cardo: chamados finos e curtos de um bando no mato.
static func _carrica(index: int) -> PackedFloat32Array:
	var buf := _buffer(0.4)
	var chip := {"h2": 0.08, "breath": 0.08, "attack": 0.003, "curve": 0.5}
	match index % 4:
		0:
			_note(buf, 0.0, 0.045, 7000.0, 5200.0, 0.4, chip)
		1:
			_note(buf, 0.0, 0.04, 6800.0, 5300.0, 0.4, chip)
			_note(buf, 0.1, 0.045, 6600.0, 5000.0, 0.33, chip)
		2:
			_note(buf, 0.0, 0.17, 7600.0, 7100.0, 0.22, {"breath": 0.15, "attack": 0.02, "vib_rate": 40.0, "vib": 0.01})
		3:
			for i in 5:
				_note(buf, i * 0.045, 0.025, 6100.0 - i * 90.0, 5400.0, 0.3, chip)
	return buf


## Rolinha-do-junco: arrulhos ocos e graves, de lamento, perto da água.
static func _rolinha(index: int) -> PackedFloat32Array:
	var buf := _buffer(2.4)
	var coo := {"h2": 0.22, "h3": 0.05, "breath": 0.1, "attack": 0.06, "release": 0.12, "vib_rate": 5.5, "vib": 0.006}
	match index % 3:
		0:
			_note(buf, 0.0, 0.34, 520.0, 610.0, 0.55, coo.merged({"curve": 0.5}))
			_note(buf, 0.5, 0.62, 600.0, 560.0, 0.6, coo)
			_note(buf, 1.38, 0.24, 560.0, 548.0, 0.45, coo)
			_note(buf, 1.86, 0.24, 556.0, 540.0, 0.4, coo)
		1:
			_note(buf, 0.0, 0.5, 580.0, 572.0, 0.55, coo)
			_note(buf, 0.66, 0.72, 522.0, 492.0, 0.55, coo.merged({"curve": 2.0}))
		2:
			_note(buf, 0.0, 0.85, 500.0, 468.0, 0.6, coo.merged({"tremolo": 6.0}))
	return buf


# --- Síntese -------------------------------------------------------------------

static func _buffer(seconds: float) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(int(seconds * RATE))
	return buf


## Soma uma nota ao buffer: um assobio que desliza de "f_from" a "f_to".
## Opções: curve (forma do deslize), h2/h3 (harmônicos), breath (sopro),
## vib/vib_rate (vibrato), tremolo (Hz), dual (segunda voz uma quinta
## acima), attack/release (segundos).
static func _note(buf: PackedFloat32Array, start: float, dur: float, f_from: float, f_to: float, amp: float, opts := {}) -> void:
	var curve: float = opts.get("curve", 1.0)
	var h2: float = opts.get("h2", 0.0)
	var h3: float = opts.get("h3", 0.0)
	var breath: float = opts.get("breath", 0.0)
	var vib: float = opts.get("vib", 0.0)
	var vib_rate: float = opts.get("vib_rate", 0.0)
	var tremolo: float = opts.get("tremolo", 0.0)
	var dual: float = opts.get("dual", 0.0)
	var attack: float = minf(opts.get("attack", 0.025), dur * 0.4)
	var release: float = minf(opts.get("release", 0.05), dur * 0.5)
	var first := int(start * RATE)
	var count := int(dur * RATE)
	var phase := 0.0
	var phase2 := 0.0
	var noise := 0.0
	var seed_state := int(start * 1000.0 + f_from) * 7919 + 1
	for i in count:
		var n := first + i
		if n >= buf.size():
			break
		var x := float(i) / count
		var t := float(i) / RATE
		var freq := lerpf(f_from, f_to, pow(x, curve)) * (1.0 + vib * sin(TAU * vib_rate * t))
		phase = fmod(phase + TAU * freq / RATE, TAU)
		phase2 = fmod(phase2 + TAU * freq * 1.5 / RATE, TAU)
		var env := minf(1.0, t / attack) * minf(1.0, (dur - t) / release)
		env = env * env * (3.0 - 2.0 * env)  # suaviza as pontas
		if tremolo > 0.0:
			env *= 0.7 + 0.3 * sin(TAU * tremolo * t)
		var value := sin(phase) + h2 * sin(2.0 * phase) + h3 * sin(3.0 * phase) + dual * sin(phase2)
		# Sopro: ruído suave que segue a mesma envoltória.
		seed_state = (seed_state * 1103515245 + 12345) & 0x7FFFFFFF
		noise = lerpf(float(seed_state) / 0x7FFFFFFF * 2.0 - 1.0, noise, 0.5)
		buf[n] += (value + breath * noise * 2.0) * env * amp * 0.5


## Uma batida de asa: um sopro de ar, ruído filtrado com ataque rápido.
## "body" mais alto deixa o som mais grave e cheio.
static func _flap(buf: PackedFloat32Array, start: float, dur: float, amp: float, body: float, rng: RandomNumberGenerator) -> void:
	var first := int(start * RATE)
	var count := int(dur * RATE)
	var low := 0.0
	var lower := 0.0
	for i in count:
		var n := first + i
		if n >= buf.size():
			break
		var x := float(i) / count
		var env := sin(PI * pow(x, 0.45)) * (1.0 - x * 0.3)
		low = lerpf(rng.randf_range(-1.0, 1.0), low, body)
		lower = lerpf(low, lower, 0.97)
		buf[n] += (low - lower) * env * amp * 0.9


## Eco de mata: algumas cópias atrasadas e abafadas, que dão espaço e
## distância ao canto.
static func _with_tail(buf: PackedFloat32Array, seconds: float) -> PackedFloat32Array:
	var dry := buf.size()
	var out := buf.duplicate()
	out.resize(dry + int(maxf(seconds, 0.3) * RATE))
	for tap in [[0.071, 0.22], [0.127, 0.15], [0.193, 0.1], [0.281, 0.06]]:
		var offset := int(tap[0] * RATE)
		var gain: float = tap[1]
		var smooth := 0.0
		for i in dry:
			smooth = lerpf(buf[i], smooth, 0.6)
			out[i + offset] += smooth * gain
	return out


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


static func _file(name: String) -> AudioStream:
	for ext in [".ogg", ".wav"]:
		if ResourceLoader.exists(DIR + name + ext):
			return load(DIR + name + ext) as AudioStream
	return null
