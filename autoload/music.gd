extends Node
## Música de fundo do jogo: a musiquinha de ocarina (tools/musica_vila.py).
##
## Toca bem baixinho, sem posição no espaço, do menu até o mundo. Fica mais
## cheia conforme a horta comunitária cresce (níveis 0 a 3), trocando de
## versão no fim do loop para a melodia não ser cortada no meio.

const VOLUME_DB := -24.0

var level := 0

var _player: AudioStreamPlayer
var _pending_level := -1


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return  # servidor dedicado e testes não tocam música
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
	var stream := Sounds.music(lvl)
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = false
	return stream
