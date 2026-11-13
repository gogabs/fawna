class_name Minigame
extends Node
## Base dos minigames de profissão.
##
## Interface pequena de propósito, para a comunidade poder criar e melhorar
## minigames sem mexer no resto do jogo:
##   start()            começa (o jogo chama depois de adicionar o nó)
##   finished(success)  sinal emitido uma vez, no fim
## Enquanto um minigame está ativo, ele recebe todas as teclas.
## Regra de ouro: tem que ser jogável só com áudio.

signal finished(success: bool)

var _player: AudioStreamPlayer
var _done := false


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.max_polyphony = 4
	add_child(_player)


func start() -> void:
	pass


## Teclas do minigame. Esc sempre cancela.
func _unhandled_input(event: InputEvent) -> void:
	if _done or not event.is_pressed() or event.is_echo():
		return
	get_viewport().set_input_as_handled()
	if event.is_action("ui_cancel"):
		Speech.say("Você saiu do minigame.")
		_finish(false)
		return
	handle_input(event)


func handle_input(_event: InputEvent) -> void:
	pass


func play(stream: AudioStream) -> void:
	_player.stream = stream
	_player.play()


func _finish(success: bool) -> void:
	if _done:
		return
	_done = true
	finished.emit(success)
	queue_free()


static func is_confirm(event: InputEvent) -> bool:
	return event.is_action("interagir")
