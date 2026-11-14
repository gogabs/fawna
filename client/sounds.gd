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
	# Recursos coletáveis. Os de recursos/ são os escolhidos para cada um;
	# enquanto não existirem, valem os do pacote world/ ou os gerados por
	# código (SoundBank), na ordem em que aparecem em cada função.
	"rec_coleta_bambu": ["recursos/coleta_bambu_1.ogg", "recursos/coleta_bambu_2.ogg", "recursos/coleta_bambu_3.ogg", "recursos/coleta_bambu_4.ogg"],
	"rec_coleta_lenha": ["recursos/coleta_lenha_1.ogg", "recursos/coleta_lenha_2.ogg", "recursos/coleta_lenha_3.ogg", "recursos/coleta_lenha_4.ogg"],
	"rec_coleta_argila": ["recursos/coleta_argila_1.ogg", "recursos/coleta_argila_2.ogg", "recursos/coleta_argila_3.ogg", "recursos/coleta_argila_4.ogg"],
	"rec_coleta_frutas": ["recursos/coleta_frutas_1.ogg", "recursos/coleta_frutas_2.ogg", "recursos/coleta_frutas_3.ogg", "recursos/coleta_frutas_4.ogg"],
	"coleta_bambu": ["world/wallwood.ogg", "world/wallwood2.ogg", "world/wallwood3.ogg"],
	"coleta_lenha": ["world/wallwood4.ogg", "world/wallwood5.ogg", "world/wallwood6.ogg"],
	"coleta_frutas": ["world/wallfoliage.ogg", "world/wallfoliage2.ogg", "world/wallfoliage3.ogg"],
	"amb_bambu": ["recursos/amb_bambu.ogg"],
	"amb_gravetos": ["recursos/amb_gravetos.ogg"],
	"amb_frutas": ["recursos/amb_frutas.ogg"],
	"bambu_golpe": ["recursos/bambu_golpe_1.ogg", "recursos/bambu_golpe_2.ogg", "recursos/bambu_golpe_3.ogg", "recursos/bambu_golpe_4.ogg"],
	"bambu_queda": ["recursos/bambu_queda_1.ogg", "recursos/bambu_queda_2.ogg", "recursos/bambu_queda_3.ogg"],
	"chegada": ["world/notify.ogg"],
	"ui_mover": ["menu/menu_navegar.ogg", "world/menuclick.ogg"],
	"ui_confirmar": ["world/menuenter.ogg"],
	"ui_abrir": ["menu/menu_abrir.ogg", "world/menuopen.ogg"],
	"ui_fechar": ["menu/menu_fechar.ogg", "world/menuclose.ogg"],
	"amb_agua": ["world/loop_brook.ogg"],
	"amb_arvore": ["world/loop_windintrees.ogg"],
	"amb_arbusto": ["world/loop_windinbushes.ogg"],
	"amb_origem": ["world/loop_windchimes1.ogg"],
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
	# Foley de movimento da criatura (roupa de algodão e tornozeleira de
	# conchas). Ficam em foley/, fora do repositório até a licença ser
	# confirmada; sem eles o jogo segue sem esses sons.
	"mov_giro": ["foley/giro_1.ogg", "foley/giro_2.ogg", "foley/giro_3.ogg"],
	"mov_inicio": ["foley/inicio_sintetico.ogg"],
	"mov_parada": ["foley/parada_sintetica.ogg"],
	"mov_inicio_amigo": ["foley/inicio_amigo.ogg"],
	"mov_parada_amigo": ["foley/parada_amigo.ogg"],
	"mov_farfalhar": ["foley/farfalhar_1.ogg", "foley/farfalhar_2.ogg", "foley/farfalhar_3.ogg", "foley/farfalhar_4.ogg", "foley/farfalhar_5.ogg", "foley/farfalhar_6.ogg", "foley/farfalhar_7.ogg"],
	"mov_tornozeleira": ["foley/tornozeleira_concha.ogg", "foley/tornozeleira_1.ogg", "foley/tornozeleira_2.ogg", "foley/tornozeleira_3.ogg", "foley/tornozeleira_4.ogg", "foley/tornozeleira_5.ogg", "foley/tornozeleira_6.ogg", "foley/tornozeleira_7.ogg", "foley/tornozeleira_8.ogg", "foley/tornozeleira_9.ogg", "foley/tornozeleira_10.ogg"],
	"caminheiro_batida": ["caminheiro/batida.ogg"],
	# Bolsa, equipamento e machado: um arquivo só ou variações _1 a _4 (sorteadas
	# sem repetir a última). Sem os arquivos, sons gerados por código.
	"machado_golpe": ["ferramentas/machado_golpe.ogg", "ferramentas/machado_golpe_1.ogg", "ferramentas/machado_golpe_2.ogg", "ferramentas/machado_golpe_3.ogg", "ferramentas/machado_golpe_4.ogg"],
	"machado_impacto": ["ferramentas/machado_impacto.ogg", "ferramentas/machado_impacto_1.ogg", "ferramentas/machado_impacto_2.ogg", "ferramentas/machado_impacto_3.ogg", "ferramentas/machado_impacto_4.ogg"],
	"machado_quebra": ["ferramentas/machado_quebra.ogg", "ferramentas/machado_quebra_1.ogg", "ferramentas/machado_quebra_2.ogg", "ferramentas/machado_quebra_3.ogg", "ferramentas/machado_quebra_4.ogg"],
	"empunhar": ["ferramentas/empunhar.ogg", "ferramentas/empunhar_1.ogg", "ferramentas/empunhar_2.ogg", "ferramentas/empunhar_3.ogg", "ferramentas/empunhar_4.ogg"],
	"guardar": ["ferramentas/guardar.ogg", "ferramentas/guardar_1.ogg", "ferramentas/guardar_2.ogg", "ferramentas/guardar_3.ogg", "ferramentas/guardar_4.ogg"],
	"bolsa_abrir": ["ferramentas/bolsa_abrir.ogg", "ferramentas/bolsa_abrir_1.ogg", "ferramentas/bolsa_abrir_2.ogg", "ferramentas/bolsa_abrir_3.ogg", "ferramentas/bolsa_abrir_4.ogg"],
	"bolsa_mexer": ["ferramentas/bolsa_mexer.ogg", "ferramentas/bolsa_mexer_1.ogg", "ferramentas/bolsa_mexer_2.ogg", "ferramentas/bolsa_mexer_3.ogg", "ferramentas/bolsa_mexer_4.ogg"],
	"bolsa_fechar": ["ferramentas/bolsa_fechar.ogg", "ferramentas/bolsa_fechar_1.ogg", "ferramentas/bolsa_fechar_2.ogg", "ferramentas/bolsa_fechar_3.ogg", "ferramentas/bolsa_fechar_4.ogg"],
}

## Início e parada do movimento: true troca os sintéticos pelos farfalhares
## gravados (as alternativas da seleção).
const FRIEND_START_STOP := false

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
	return _pick_existing(["rec_coleta_" + item, "coleta_" + item], func(): return SoundBank.pickup_of(item))


## Som baixinho e contínuo de cada recurso coletável, para achá-lo de ouvido:
## o bambu range e bate os colmos, os gravetos estalam secos e as frutas
## (raras) têm moscas rondando. A argila não tem som próprio (escolha do
## Gabs): fica sempre na beira da água, que já soa.
static func resource_loop(thing: WorldGen.Thing) -> AudioStream:
	var key: String = {
		WorldGen.Thing.BAMBU: "amb_bambu",
		WorldGen.Thing.GRAVETOS: "amb_gravetos",
		WorldGen.Thing.ARBUSTO_FRUTAS: "amb_frutas",
	}.get(thing, "")
	if key.is_empty():
		return null
	var stream := _pick_existing([key], func(): return SoundBank.resource_loop(thing))
	if stream != null:
		_make_loop(stream)
	return stream


static func has_resource_loop(thing: WorldGen.Thing) -> bool:
	return thing in [WorldGen.Thing.BAMBU, WorldGen.Thing.GRAVETOS, WorldGen.Thing.ARBUSTO_FRUTAS]


## O colmo oco do bambu levando um golpe de machado (o som do machado
## cortando o ar fica com quem empunha).
static func bamboo_knock() -> AudioStream:
	return _pick_existing(["bambu_golpe"], SoundBank.bamboo_knock)


## A touceira estalando e caindo, no último golpe.
static func bamboo_fall() -> AudioStream:
	return _pick_existing(["bambu_queda"], SoundBank.bamboo_fall)


## Sorteia um arquivo existente da primeira chave que tiver algum, sem repetir
## o último; sem nenhum, usa o fallback.
static func _pick_existing(keys: Array, fallback: Callable) -> AudioStream:
	for key: String in keys:
		var files := []
		for file in MANIFEST.get(key, []):
			if ResourceLoader.exists(DIR + file):
				files.append(file)
		if files.is_empty():
			continue
		if files.size() > 1:
			files.erase(_last_pick.get(key, ""))
		var file: String = files[randi() % files.size()]
		_last_pick[key] = file
		var stream := _load(DIR + file)
		if stream != null:
			return stream
	return fallback.call()


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


## Foley de movimento: o pano da roupa ao girar, ao começar e ao parar de
## andar, o farfalhar contínuo enquanto anda e as conchas da tornozeleira.
static func turn_rustle() -> AudioStream:
	return _pick("mov_giro", func(): return null)


static func move_start() -> AudioStream:
	var key := "mov_inicio_amigo" if FRIEND_START_STOP and _has_file("mov_inicio_amigo") else "mov_inicio"
	return _pick(key, func(): return null)


static func move_stop() -> AudioStream:
	var key := "mov_parada_amigo" if FRIEND_START_STOP and _has_file("mov_parada_amigo") else "mov_parada"
	return _pick(key, func(): return null)


static func cloth_rustle() -> AudioStream:
	return _pick_fresh("mov_farfalhar")


static func anklet() -> AudioStream:
	return _pick_fresh("mov_tornozeleira")


static var _last_pick := {}  # nome lógico -> último arquivo sorteado


## Sorteia sem repetir o último arquivo, e só entre os que existem.
static func _pick_fresh(key: String) -> AudioStream:
	var files := []
	for file in MANIFEST.get(key, []):
		if ResourceLoader.exists(DIR + file) and (file != _last_pick.get(key, "")):
			files.append(file)
	if files.is_empty():
		return _pick(key, func(): return null)
	var file: String = files[randi() % files.size()]
	_last_pick[key] = file
	return _load(DIR + file)


## Batida do Caminheiro (tambor abafado, como um coração, com passa-baixa e
## reverb já no arquivo: tools/som_caminheiro.py) e o woosh de chegada a um
## beacon. Sem os arquivos, sons gerados por código.
static func heartbeat() -> AudioStream:
	return _pick("caminheiro_batida", SoundBank.heartbeat)


static func woosh() -> AudioStream:
	return _pick("caminheiro_woosh", SoundBank.woosh)


## Machado: o golpe no ar, a lâmina batendo (no bambu, por exemplo) e o
## último golpe, quando a coisa cede.
static func axe_swing() -> AudioStream:
	return _pick_variant("machado_golpe", SoundBank.axe_swing)


static func axe_hit() -> AudioStream:
	return _pick_variant("machado_impacto", SoundBank.axe_hit)


static func axe_break() -> AudioStream:
	return _pick_variant("machado_quebra", SoundBank.axe_break)


## Tirar um item da bolsa para as mãos, e guardar de volta.
static func wield() -> AudioStream:
	return _pick_variant("empunhar", SoundBank.wield)


static func stow() -> AudioStream:
	return _pick_variant("guardar", SoundBank.stow)


static func bag_open() -> AudioStream:
	return _pick_variant("bolsa_abrir", func(): return _pick_first("ui_abrir", SoundBank.stow))


static func bag_close() -> AudioStream:
	return _pick_variant("bolsa_fechar", func(): return _pick_first("ui_fechar"))


## Mexer nos itens da bolsa (passar de um para outro).
static func bag_rummage() -> AudioStream:
	return _pick_variant("bolsa_mexer", ui_move)


## O primeiro arquivo da lista que existir (os sons escolhidos vêm antes dos
## do pacote world, que ficam de reserva).
static func _pick_first(key: String, fallback := Callable()) -> AudioStream:
	for file in MANIFEST.get(key, []):
		var stream := _load(DIR + file)
		if stream != null:
			return stream
	return fallback.call() if fallback.is_valid() else null


## Sorteia entre os arquivos que existem, sem repetir o último; sem nenhum,
## usa o fallback.
static func _pick_variant(key: String, fallback: Callable) -> AudioStream:
	var files := []
	for file in MANIFEST.get(key, []):
		if ResourceLoader.exists(DIR + file):
			files.append(file)
	if files.size() > 1:
		files.erase(_last_pick.get(key, ""))
	if files.is_empty():
		return fallback.call()
	var file: String = files[randi() % files.size()]
	_last_pick[key] = file
	var stream := _load(DIR + file)
	return stream if stream != null else fallback.call()


static func ui_move() -> AudioStream:
	return _pick_first("ui_mover")


static func ui_confirm() -> AudioStream:
	return _pick("ui_confirmar", func(): return null)


static func ui_open() -> AudioStream:
	return _pick_first("ui_abrir")


static func ui_close() -> AudioStream:
	return _pick_first("ui_fechar")


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


## Som contínuo de cada coisa do mundo.
static func ambient(thing: WorldGen.Thing) -> AudioStream:
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
		WorldGen.Thing.ORIGEM:
			key = "amb_origem"
	if key.is_empty():
		return null
	var stream := _pick(key, func(): return null, false)
	if stream == null:
		return SoundBank.ambient(thing)
	_make_loop(stream)
	return stream


## Música dark fantasy de fundo (tools/musica_sombria.py).
static func dark_music() -> AudioStream:
	return _pick("musica_sombria", func(): return null, false)


## Musiquinha de ocarina (tools/musica_vila.py), guardada: uma versão por
## nível. Sem os arquivos, usa os sininhos gerados por código.
static func music(level: int) -> AudioStream:
	var stream := _pick("musica_vila_%d" % clampi(level, 0, 3), func(): return null, false)
	if stream == null:
		stream = SoundBank.ambient(WorldGen.Thing.ORIGEM, level)
	return stream


static func has_ambient(thing: WorldGen.Thing) -> bool:
	return thing in [WorldGen.Thing.RIACHO, WorldGen.Thing.LAGO, WorldGen.Thing.ARVORE, WorldGen.Thing.ARBUSTO, WorldGen.Thing.ORIGEM]


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
