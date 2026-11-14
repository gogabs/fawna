class_name Sounds
extends RefCounted
## Todos os sons do jogo passam por aqui.
##
## Cada som tem um nome lógico ("passo_bosque", "colisao"...) e uma lista de
## arquivos em assets/sounds/. Quando há mais de um arquivo, um é sorteado a
## cada vez, para o som não ficar repetitivo. Se o arquivo não existir, usa o
## som gerado por código do SoundBank, então o jogo nunca fica mudo.

const DIR := "res://assets/sounds/"

## nome lógico -> arquivos (relativos a DIR). Os da pasta world/ vêm do
## "World Sounds Audio Pack" (CC0); para adicionar mais, inclua aqui e rode
## tools/copiar_sons.ps1.
const MANIFEST := {
	"passo_pradaria": ["world/grassstep1.ogg", "world/grassstep2.ogg", "world/grassstep3.ogg", "world/grassstep4.ogg", "world/grassstep5.ogg"],
	"passo_bosque": ["world/leavesstep1.ogg", "world/leavesstep2.ogg", "world/leavesstep3.ogg", "world/leavesstep4.ogg", "world/leavesstep5.ogg"],
	"colisao": ["world/wallbrush.ogg", "world/wallbrush2.ogg"],
	"colisao_arvore": ["world/walltree.ogg"],
	"colisao_agua": ["world/wallwater.ogg"],
	"coleta_madeira": ["world/wallwood.ogg", "world/wallwood2.ogg", "world/wallwood3.ogg"],
	"coleta_sementes": ["world/wallfoliage.ogg", "world/wallfoliage2.ogg", "world/wallfoliage3.ogg"],
	"coleta_agua": ["world/water1.ogg", "world/water2.ogg", "world/water3.ogg"],
	"chegada": ["world/notify.ogg"],
	"obra_concluida": ["world/achievement.ogg", "world/achievement2.ogg"],
	"metronomo": ["world/uiblip1.ogg"],
	"serrote": ["cc0/serrote.ogg"],
	"serrote_alt": ["world/wallwood4.ogg", "world/wallwood5.ogg", "world/wallwood6.ogg"],
	"acerto": ["world/uiclick1.ogg"],
	"regar": ["world/waterjet.ogg", "world/waterjet2.ogg"],
	"ui_mover": ["world/menuclick.ogg"],
	"ui_confirmar": ["world/menuenter.ogg"],
	"ui_abrir": ["world/menuopen.ogg"],
	"ui_fechar": ["world/menuclose.ogg"],
	"amb_agua": ["world/loop_brook.ogg"],
	"amb_arvore": ["world/loop_windintrees.ogg"],
	"amb_arbusto": ["world/loop_windinbushes.ogg"],
	"amb_vila_0": ["world/loop_windchimes1.ogg"],
	"amb_vila_1": ["world/loop_windchimes2.ogg"],
	"amb_vila_2": ["world/loop_windchimes3.ogg"],
	"amb_vila_3": ["world/loop_SpringBirds.ogg"],
	"bussola_norte": ["bussola/norte.ogg"],
	"bussola_sul": ["bussola/sul.ogg"],
	"bussola_lateral": ["bussola/lateral.ogg"],
	"bussola_colateral": ["bussola/colateral.ogg"],
	"musica_sombria": ["musica/sombria.ogg"],
	"musica_vila_0": ["musica/vila_0.ogg"],
	"musica_vila_1": ["musica/vila_1.ogg"],
	"musica_vila_2": ["musica/vila_2.ogg"],
	"musica_vila_3": ["musica/vila_3.ogg"],
	"passo_trilha": ["world/dirtstep1.ogg", "world/dirtstep2.ogg", "world/dirtstep3.ogg", "world/dirtstep4.ogg", "world/dirtstep5.ogg"],
	"passo_ponte": ["world/bridgestep1.ogg", "world/bridgestep2.ogg", "world/bridgestep3.ogg", "world/bridgestep4.ogg", "world/bridgestep5.ogg"],
	"amb_lago": ["world/loop_wind_water.ogg"],
	"fundo_lagoa": ["world/loop_lapping_waves.ogg"],
	"fundo_bosque": ["world/loop_forest_windy.ogg"],
	"fundo_pradaria": ["world/loop_windy_afternoon.ogg"],
	"vento_aberto": ["world/loop_wind.ogg"],
}

static var _loaded := {}  # caminho -> AudioStream


## Passo: o chão da trilha e da ponte soa diferente do mato de cada bioma.
static func footstep(biome: WorldGen.Biome, ground := WorldGen.Thing.NADA) -> AudioStream:
	var key := "passo_bosque" if biome == WorldGen.Biome.BOSQUE else "passo_pradaria"
	if ground == WorldGen.Thing.TRILHA and _has_file("passo_trilha"):
		key = "passo_trilha"
	elif ground == WorldGen.Thing.PONTE and _has_file("passo_ponte"):
		key = "passo_ponte"
	return _pick(key, func(): return SoundBank.footstep(biome))


## Esbarrão, com o som do material quando houver (árvore, água...).
static func bump(thing := WorldGen.Thing.NADA) -> AudioStream:
	var key := "colisao"
	if thing == WorldGen.Thing.ARVORE:
		key = "colisao_arvore"
	elif thing == WorldGen.Thing.RIACHO or thing == WorldGen.Thing.LAGO:
		key = "colisao_agua"
	if not _has_file(key):
		key = "colisao"
	return _pick(key, SoundBank.bump)


static func chime() -> AudioStream:
	return _pick("chegada", SoundBank.chime)


static func pickup(item := "") -> AudioStream:
	var key := "coleta_" + item
	return _pick(key if _has_file(key) else "coleta", SoundBank.pickup)


static func fanfare() -> AudioStream:
	return _pick("obra_concluida", SoundBank.fanfare)


static func tick() -> AudioStream:
	return _pick("metronomo", SoundBank.tick)


## Batida do serrote. Sem o arquivo CC0, usa batidas de madeira do pacote.
static func saw() -> AudioStream:
	return _pick("serrote" if _has_file("serrote") else "serrote_alt", SoundBank.saw)


static func tok() -> AudioStream:
	return _pick("acerto", SoundBank.tok)


static func water_splash() -> AudioStream:
	return _pick("regar", SoundBank.water_splash)


## Clique da bússola ao girar (tools/sons_bussola.py): agudo no norte, grave
## no sul, igual para leste e oeste e abafado nos pontos colaterais.
static func compass(heading: int) -> AudioStream:
	var kind := compass_kind(heading)
	return _pick("bussola_" + kind, func(): return SoundBank.compass(kind))


static func compass_kind(heading: int) -> String:
	match posmod(heading, Compass.STEPS):
		0:
			return "norte"
		4:
			return "sul"
		2, 6:
			return "lateral"
	return "colateral"


static func ui_move() -> AudioStream:
	return _pick("ui_mover", func(): return null)


static func ui_confirm() -> AudioStream:
	return _pick("ui_confirmar", func(): return null)


static func ui_open() -> AudioStream:
	return _pick("ui_abrir", func(): return null)


static func ui_close() -> AudioStream:
	return _pick("ui_fechar", func(): return null)


## Vento de lugar aberto (trilhas e beira da lagoa), em loop, não posicional.
static func open_wind() -> AudioStream:
	var stream := _pick("vento_aberto", func(): return null, false)
	if stream != null:
		_make_loop(stream)
	return stream


## Ambiente de fundo do bioma (não posicional), em loop.
static func biome_bed(biome: WorldGen.Biome) -> AudioStream:
	var key := "fundo_bosque" if biome == WorldGen.Biome.BOSQUE else "fundo_pradaria"
	if biome == WorldGen.Biome.LAGOA and _has_file("fundo_lagoa"):
		key = "fundo_lagoa"
	var stream := _pick(key, func(): return null, false)
	if stream != null:
		_make_loop(stream)
	return stream


## Som contínuo de cada coisa do mundo. A vila muda com o nível da horta.
static func ambient(thing: WorldGen.Thing, level := 0) -> AudioStream:
	var key := ""
	match thing:
		WorldGen.Thing.RIACHO:
			key = "amb_agua"
		WorldGen.Thing.LAGO:
			key = "amb_lago" if _has_file("amb_lago") else "amb_agua"
		WorldGen.Thing.ARVORE:
			key = "amb_arvore"
		WorldGen.Thing.ARBUSTO:
			key = "amb_arbusto"
		WorldGen.Thing.VILA:
			key = "amb_vila_%d" % level
	if key.is_empty():
		return null
	var stream := _pick(key, func(): return null, false)
	if stream == null:
		return SoundBank.ambient(thing, level)
	_make_loop(stream)
	return stream


## Música dark fantasy de fundo (tools/musica_sombria.py).
static func dark_music() -> AudioStream:
	return _pick("musica_sombria", func(): return null, false)


## Musiquinha de ocarina (tools/musica_vila.py), guardada: uma versão por
## nível da horta. Sem os arquivos, usa os sininhos gerados por código.
static func music(level: int) -> AudioStream:
	var stream := _pick("musica_vila_%d" % clampi(level, 0, 3), func(): return null, false)
	if stream == null:
		stream = SoundBank.ambient(WorldGen.Thing.VILA, level)
	return stream


static func has_ambient(thing: WorldGen.Thing) -> bool:
	return thing in [WorldGen.Thing.RIACHO, WorldGen.Thing.LAGO, WorldGen.Thing.ARVORE, WorldGen.Thing.ARBUSTO, WorldGen.Thing.VILA]


static func _has_file(key: String) -> bool:
	for file in MANIFEST.get(key, []):
		if ResourceLoader.exists(DIR + file):
			return true
	return false


static func _pick(key: String, fallback: Callable, random := true) -> AudioStream:
	var files: Array = MANIFEST.get(key, [])
	if not files.is_empty():
		var file: String = files[randi() % files.size()] if random else files[0]
		var stream := _load(DIR + file)
		if stream != null:
			return stream
	return fallback.call()


static func _load(path: String) -> AudioStream:
	if _loaded.has(path):
		return _loaded[path]
	var stream: AudioStream = null
	if ResourceLoader.exists(path):
		stream = load(path) as AudioStream
	_loaded[path] = stream
	return stream


static func _make_loop(stream: AudioStream) -> void:
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		if wav.loop_mode == AudioStreamWAV.LOOP_DISABLED:
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			wav.loop_end = int(wav.get_length() * wav.mix_rate)


static func clear() -> void:
	_loaded.clear()
	SoundBank.clear()
