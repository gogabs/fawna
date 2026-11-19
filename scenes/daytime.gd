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
##     (menos no mar e no frio);
##   - um aviso falado quando entardece, anoitece e amanhece;
##   - a tecla T diz que horas são.
## E o Calado só ronda de noite (ver Horrors).

const SYNC_SECONDS := 15.0  # o servidor reafirma a hora a cada tanto
const CRICKETS_DB := -24.0  # grilos na noite plena
const CRICKETS_FADE := 12.0  # dB por segundo, para subir e descer sem susto
const SILENT_DB := -70.0
const MUTE_BIOMES := [WorldGen.Biome.MAR, WorldGen.Biome.FLORESTA_GELADA, WorldGen.Biome.DESERTO_GELADO]

## A hora do mundo (fração do dia) e quanto dura um dia, em segundos de verdade.
var t := DayCycle.hour_to_t(DayCycle.START_HOUR)
var day_seconds := DayCycle.DEFAULT_SECONDS

var _state: WorldState  # só no servidor
var _since_sync := 0.0
var _phase := -1
var _crickets: AudioStreamPlayer
var _biome_check := 0.0
var _crickets_on := true
var _playing := false  # este nó é de quem joga (não de um servidor dedicado)


## O servidor assume o relógio do mundo carregado (ou o que veio de --hora e --dia).
func start_server(state: WorldState) -> void:
	_state = state
	t = state.day_t
	if Net.day_hour >= 0.0:
		t = DayCycle.hour_to_t(Net.day_hour)
	if Net.day_seconds > 0.0:
		day_seconds = Net.day_seconds
	_phase = DayCycle.phase_of(t)


func start_client() -> void:
	_playing = true
	_phase = DayCycle.phase_of(t)
	if _crickets == null and DisplayServer.get_name() != "headless":
		var stream := SoundBank.crickets()
		_crickets = AudioStreamPlayer.new()
		_crickets.name = "Grilos"
		_crickets.stream = stream
		_crickets.volume_db = SILENT_DB
		add_child(_crickets)


func is_night() -> bool:
	return DayCycle.is_night(t)


func darkness() -> float:
	return DayCycle.darkness(t)


func describe() -> String:
	return DayCycle.describe(t, day_seconds)


## Só no servidor: muda a hora (0 a 24) na hora, para testes e depuração, e
## avisa todo mundo.
func set_hour(hour: float) -> void:
	t = DayCycle.hour_to_t(hour)
	if _state != null:
		_state.day_t = t
		_sync_all()


## Só no servidor: manda a hora para quem acabou de entrar.
func sync_to(peer: int) -> void:
	if _state != null:
		time_sync.rpc_id(peer, t, day_seconds)


func _sync_all() -> void:
	_since_sync = 0.0
	time_sync.rpc(t, day_seconds)


@rpc("authority", "call_local", "reliable")
func time_sync(new_t: float, new_day_seconds: float) -> void:
	t = fposmod(new_t, 1.0)
	day_seconds = maxf(new_day_seconds, 1.0)


func _process(delta: float) -> void:
	t = fposmod(t + delta / day_seconds, 1.0)
	if _state != null:
		_state.day_t = t
		_since_sync += delta
		if _since_sync >= SYNC_SECONDS and multiplayer.has_multiplayer_peer():
			_sync_all()
	_track_phase()
	if _crickets != null:
		_update_crickets(delta)


## Avisa quando o período muda. Na entrada, não diz nada: a tecla T responde.
func _track_phase() -> void:
	var phase := DayCycle.phase_of(t)
	if phase == _phase:
		return
	_phase = phase
	if _playing:  # só quem joga ouve o aviso
		Speech.say(DayCycle.announcement(phase), false)


func _update_crickets(delta: float) -> void:
	_biome_check -= delta
	if _biome_check <= 0.0:
		_biome_check = 1.0
		var game := get_parent()
		_crickets_on = game.world == null or not MUTE_BIOMES.has(game.world.biome_at(WorldGen.cell_of(game.my_position())))
	var target := SILENT_DB
	var dark := darkness()
	if _crickets_on and dark > 0.02:
		target = lerpf(SILENT_DB, CRICKETS_DB, sqrt(dark))
	if target <= SILENT_DB + 0.5 and _crickets.volume_db <= SILENT_DB + 0.5:
		if _crickets.playing:
			_crickets.stop()
		return
	if not _crickets.playing:
		_crickets.play(randf() * _crickets.stream.get_length())
	_crickets.volume_db = move_toward(_crickets.volume_db, target, CRICKETS_FADE * delta)
