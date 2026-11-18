extends Node
## Música de fundo do jogo (tools/musica_sombria.py): lenta, grave e esparsa,
## no clima dark fantasy. Toca bem baixinho, sem posição no espaço, do menu
## até o mundo.
##
## A musiquinha de ocarina (tools/musica_vila.py) continua guardada: com
## USE_OCARINA, ela volta a tocar; set_level escolhe uma das versões (níveis 0
## a 3), trocando no fim do loop.

const VOLUME_DB := -20.0
## Todos os sons do jogo passam pelo barramento Master, que fica bem mais
## baixo; a fala (Prism ou a voz do sistema) não passa por ele e continua
## clara por cima.
const MASTER_DB := -10.0
const USE_OCARINA := false

var level := 0

var _player: AudioStreamPlayer
var _pending_level := -1


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return  # servidor dedicado e testes não tocam música
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), MASTER_DB)
	_player = AudioStreamPlayer.new()
	_player.volume_db = VOLUME_DB
	add_child(_player)
	_player.finished.connect(_on_loop_end)


func start() -> void:
	if _player == null or _player.playing:
		return
	_player.stream = _stream(level)
	_player.play()


func stop() -> void:
	if _player != null:
		_player.stop()


## Muda a versão da música. Se já estiver tocando, troca no fim do loop.
func set_level(new_level: int) -> void:
	new_level = clampi(new_level, 0, 3)
	if new_level == level and _pending_level < 0:
		return
	if _player == null or not _player.playing:
		level = new_level
		return
	_pending_level = new_level


func _on_loop_end() -> void:
	if _pending_level >= 0:
		level = _pending_level
		_pending_level = -1
	_player.stream = _stream(level)
	_player.play()


## Sem loop no arquivo: o fim de cada volta é o ponto de troca de nível.
func _stream(lvl: int) -> AudioStream:
	var stream := Sounds.music(lvl) if USE_OCARINA else Sounds.dark_music()
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = false
	return stream
