extends Node
## Anúncios de fala do jogo.
##
## Usa o Prism (prismatoid-gdextension) quando ele está instalado: o Prism fala
## pelo leitor de tela da pessoa (NVDA, JAWS, VoiceOver, Orca...) ou, se não
## houver um, por um motor de voz do sistema. Sem o Prism, usa a voz embutida
## do Godot (DisplayServer.tts_speak). Toda fala também vai para o console,
## o que ajuda quem desenvolve e os testes automáticos.

signal spoke(text: String)

var backend_name := "nenhum"
var last_text := ""

var _prism_backend: Object = null
var _tts_voice := ""


func _ready() -> void:
	_setup_prism()
	if _prism_backend == null:
		_setup_godot_tts()
	print("[fala] backend: %s" % backend_name)


## Fala um texto. Com interrupt = true, corta a fala anterior.
func say(text: String, interrupt := true) -> void:
	if text.is_empty():
		return
	last_text = text
	print("[fala] %s" % text)
	spoke.emit(text)
	if _prism_backend != null:
		_prism_backend.call("speak", text, interrupt)
	elif not _tts_voice.is_empty():
		DisplayServer.tts_speak(text, _tts_voice, 100, 1.0, 1.0, 0, interrupt)


## Repete a última fala (útil quando a pessoa não entendeu).
func repeat_last() -> void:
	if not last_text.is_empty():
		say(last_text)


func stop() -> void:
	if _prism_backend != null and _prism_backend.has_method("stop"):
		_prism_backend.call("stop")
	elif not _tts_voice.is_empty():
		DisplayServer.tts_stop()


## true quando um leitor de tela está ativo. Nesse caso os menus nativos do
## Godot já são lidos por ele e não precisamos anunciar o foco.
func screen_reader_active() -> bool:
	return DisplayServer.accessibility_screen_reader_active() == 1


func _setup_prism() -> void:
	if not Engine.has_singleton("Prism"):
		return
	var prism := Engine.get_singleton("Prism")
	var backend: Object = prism.call("create_best")
	if backend == null or not backend.call("is_valid"):
		push_warning("Prism instalado, mas nenhum backend de fala disponível.")
		return
	_prism_backend = backend
	backend_name = "Prism"


func _setup_godot_tts() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var pt_voices := DisplayServer.tts_get_voices_for_language("pt")
	if not pt_voices.is_empty():
		_tts_voice = pt_voices[0]
	else:
		var all_voices := DisplayServer.tts_get_voices()
		if all_voices.is_empty():
			return
		_tts_voice = all_voices[0]["id"]
	backend_name = "voz do Godot"
