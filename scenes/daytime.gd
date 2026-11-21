extends Node
## O dia e a noite na rede. Este nó existe igual no servidor e nos clientes
## (/root/Game/Daytime), porque é por ele que passam as chamadas de rede.
##
## O servidor é quem manda na hora: conta o tempo, guarda no mundo salvo e
## avisa os clientes ao entrarem e de tempos em tempos. Cada cliente anda
## sozinho com o relógio entre um aviso e outro. Como o jogo é todo de som,
## a hora se percebe assim:
##   - pássaros do dia dormem à noite e a coruja assume; ao amanhecer, o coro;
##   - grilos ao fundo, cada vez mais, do entardecer até a noite plena
##     (menos no mar e no frio), e sapinhos na lagoa e no brejo;
##   - um aviso falado a cada mudança de período (ver DayCycle.PERIODS);
##   - o segundo toque do C (circular) diz o momento do dia, onde se está em
##     relação ao anel e a estação;
##   - o anel: faixa de sombra de dia e de luz de noite que anda norte e sul
##     com as estações, avisada ao entrar e ao sair dela;
##   - estações (36 dias do jogo cada): a noite encolhe na Coroada e estica
##     na Longa Escuridão, e o Calado demora mais ou menos para aparecer.
## E o Calado só ronda de noite (ver Horrors), e tem mais dificuldade na luz
## do anel.

const SYNC_SECONDS := 15.0  # o servidor reafirma a hora a cada tanto
const CRICKETS_DB := -24.0  # grilos na noite plena
const CRICKETS_FADE := 12.0  # dB por segundo, para subir e descer sem susto
const FROGS_DB := -22.0  # sapinhos na noite plena, na beira da água
const SILENT_DB := -70.0
const WATER_BIOMES := [WorldGen.Biome.LAGOA, WorldGen.Biome.BREJO]
const MUTE_BIOMES := [WorldGen.Biome.MAR, WorldGen.Biome.FLORESTA_GELADA, WorldGen.Biome.DESERTO_GELADO]

## A hora do mundo (fração do dia), os dias inteiros que já passaram e quanto
## dura um dia, em segundos de verdade.
var t := DayCycle.hour_to_t(DayCycle.START_HOUR)
var days := DayCycle.START_DAY
var day_seconds := DayCycle.DEFAULT_SECONDS

var _state: WorldState  # só no servidor
var _since_sync := 0.0
var _phase := -1
var _season := -1
var _crickets: AudioStreamPlayer
var _frogs: AudioStreamPlayer
var _frogs_on := false
var _biome_check := 0.0
var _crickets_on := true
var _playing := false  # este nó é de quem joga (não de um servidor dedicado)
var _ring_check := 0.0
var _ring_known := false
var _ring_in := false
var _ring_night := false
var _ring_strength := 0.0  # onde a criatura está, atualizado a cada 0,5 s


## O servidor assume o relógio do mundo carregado (ou o que veio de --hora e --dia).
func start_server(state: WorldState) -> void:
	_state = state
	t = state.day_t
	days = state.day_n
	if Net.day_hour >= 0.0:
		t = DayCycle.hour_to_t(Net.day_hour)
	if Net.day_start >= 0:
		days = Net.day_start
	if Net.day_seconds > 0.0:
		day_seconds = Net.day_seconds
	_apply_shift()
	_phase = DayCycle.period_of(t)
	_season = DayCycle.season_of(world_day())


func start_client() -> void:
	_playing = true
	_apply_shift()
	_phase = DayCycle.period_of(t)
	_season = DayCycle.season_of(world_day())
	if _crickets == null and DisplayServer.get_name() != "headless":
		_crickets = _make_player("Grilos", SoundBank.crickets())
		_frogs = _make_player("Sapinhos", SoundBank.frogs())


func _make_player(player_name: String, stream: AudioStream) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.stream = stream
	player.volume_db = SILENT_DB
	add_child(player)
	return player


func world_day() -> float:
	return DayCycle.world_day(days, t)


func _apply_shift() -> void:
	DayCycle.shift_hours = DayCycle.season_shift(world_day())


func is_night() -> bool:
	return DayCycle.is_night(t)


## A faixa do anel neste lugar (em casas): 0 fora, 1 no miolo.
func ring_strength_at(pos: Vector2) -> float:
	return DayCycle.ring_strength(pos.y * WorldGen.METERS_PER_CELL, world_day())


## Só no servidor: a faixa em cada jogador, para o Calado (peer -> 0 a 1).
func ring_lights(players: Dictionary) -> Dictionary:
	var lights := {}
	for peer in players:
		lights[peer] = ring_strength_at(players[peer]["pos"])
	return lights


## O ritmo do Calado nesta estação (ver DayCycle.calado_rate).
func calado_rate() -> float:
	return DayCycle.calado_rate(world_day())


## O escuro no lugar da criatura (conta a sombra do anel).
func darkness_here() -> float:
	return DayCycle.darkness_with_ring(t, _ring_strength)


## O escuro do mundo todo, sem a sombra do anel (os pássaros dormem por ele).
func darkness() -> float:
	return DayCycle.darkness(t)


## Segundo toque do C: o momento do dia, o anel onde a criatura está e a estação.
func sky_text() -> String:
	var y: float = _my_y()
	var d := world_day()
	return DayCycle.sky_text(t, DayCycle.ring_strength(y, d), DayCycle.ring_offset(y, d), d)


func _my_y() -> float:
	return get_parent().my_position().y * WorldGen.METERS_PER_CELL


## Só no servidor: vai para a hora (0 a 24), sempre para frente no tempo (se ela
## já passou hoje, é a de amanhã), para testes e depuração, e avisa todo mundo.
func set_hour(hour: float) -> void:
	var new_t := DayCycle.hour_to_t(hour)
	if new_t < t:
		days += 1
	t = new_t
	_after_jump()


## Só no servidor: vai para o início de uma estação (0 a 3), no próximo
## ano ou neste, o que vier primeiro à frente. Mantém a hora.
func set_season(season: int) -> void:
	var base := DayCycle.season_start_day(clampi(season, 0, 3))
	var target := base
	while target < world_day():
		target += DayCycle.YEAR_DAYS
	days = int(ceil(target))
	_after_jump()


func _after_jump() -> void:
	_apply_shift()
	if _state != null:
		_state.day_t = t
		_state.day_n = days
		_sync_all()


## Só no servidor: vai para um momento relevante (DayCycle.MOMENTS), poucos
## segundos antes dele. Devolve o texto do que fez, ou "" se a chave não existe.
## É o que o menu de depuração chama.
func jump_to(key: String) -> String:
	var hour := DayCycle.moment_hour(key, day_seconds)
	if hour < 0.0:
		return ""
	set_hour(hour)
	return "%s: %s." % [DayCycle.moment_label(key), DayCycle.PERIODS[DayCycle.period_of(t)][0]]


## Só no servidor: vai para o início de uma estação; devolve o texto do que fez.
func jump_to_season(season: int) -> String:
	if season < 0 or season > 3:
		return ""
	set_season(season)
	return "Início: %s." % DayCycle.SEASONS[season][0]


## Só no servidor: manda a hora para quem acabou de entrar.
func sync_to(peer: int) -> void:
	if _state != null:
		time_sync.rpc_id(peer, t, day_seconds, days)


func _sync_all() -> void:
	_since_sync = 0.0
	time_sync.rpc(t, day_seconds, days)


@rpc("authority", "call_local", "reliable")
func time_sync(new_t: float, new_day_seconds: float, new_days: int) -> void:
	t = fposmod(new_t, 1.0)
	days = maxi(new_days, 0)
	day_seconds = maxf(new_day_seconds, 1.0)
	_apply_shift()


func _process(delta: float) -> void:
	var next := t + delta / day_seconds
	if next >= 1.0:
		days += 1
	t = fposmod(next, 1.0)
	_apply_shift()
	if _state != null:
		_state.day_t = t
		_state.day_n = days
		_since_sync += delta
		if _since_sync >= SYNC_SECONDS and multiplayer.has_multiplayer_peer():
			_sync_all()
	if _playing:
		_track_ring(delta)
	_track_season()
	_track_phase()
	if _crickets != null:
		_update_night_sounds(delta)


## Avisa quando a estação muda. Na entrada, não diz nada.
func _track_season() -> void:
	var season := DayCycle.season_of(world_day())
	if season == _season:
		return
	_season = season
	if _playing:
		Speech.say(DayCycle.season_announcement(season), false)


## Avisa quando o período muda. Na entrada, não diz nada: o C responde.
func _track_phase() -> void:
	var period := DayCycle.period_of(t)
	if period == _phase:
		return
	_phase = period
	if _playing:  # só quem joga ouve o aviso
		Speech.say(DayCycle.announcement(period, _ring_in), false)


## A faixa do anel onde a criatura está; avisa ao entrar e ao sair dela (e nada
## quando só o dia vira noite ou a noite vira dia estando dentro).
func _track_ring(delta: float) -> void:
	_ring_check -= delta
	if _ring_check > 0.0:
		return
	_ring_check = 0.5
	var game := get_parent()
	if game.world == null:
		return
	_ring_strength = DayCycle.ring_strength(_my_y(), world_day())
	var night := DayCycle.is_night_period(DayCycle.period_of(t))
	var inside := _ring_in
	if _ring_strength >= 0.6:
		inside = true
	elif _ring_strength < 0.4:
		inside = false
	if _ring_known and inside != _ring_in and night == _ring_night:
		Speech.say(DayCycle.ring_edge_text(night, inside), false)
	_ring_known = true
	_ring_in = inside
	_ring_night = night


## Sons da noite que dependem do bioma: grilos em terra, sapinhos na água.
func _update_night_sounds(delta: float) -> void:
	_biome_check -= delta
	if _biome_check <= 0.0:
		_biome_check = 1.0
		var game := get_parent()
		var biome := -1
		if game.world != null:
			biome = game.world.biome_at(WorldGen.cell_of(game.my_position()))
		_crickets_on = not MUTE_BIOMES.has(biome)
		_frogs_on = WATER_BIOMES.has(biome)
	var dark := darkness_here()
	_fade(_crickets, CRICKETS_DB, _crickets_on, dark, delta)
	_fade(_frogs, FROGS_DB, _frogs_on, dark, delta)


func _fade(player: AudioStreamPlayer, full_db: float, on: bool, dark: float, delta: float) -> void:
	var target := SILENT_DB
	if on and dark > 0.02:
		target = lerpf(SILENT_DB, full_db, sqrt(dark))
	if target <= SILENT_DB + 0.5 and player.volume_db <= SILENT_DB + 0.5:
		if player.playing:
			player.stop()
		return
	if not player.playing:
		player.play(randf() * player.stream.get_length())
	player.volume_db = move_toward(player.volume_db, target, CRICKETS_FADE * delta)
