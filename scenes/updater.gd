extends Control
## Primeira tela do jogo: procura uma versão nova nas releases do GitHub.
##
## Sem novidade (ou sem internet), segue direto para o menu principal.
## Com novidade, oferece "Baixar e instalar", "Ouvir novidades" e "Pular".
## Tudo é anunciado pela fala do jogo e funciona só com o teclado.
##
## Linha de comando:
##   --sem-atualizar           pula a verificação
##   --testar-atualizador      verifica mesmo rodando pelo editor
##   --atualizacao-url=URL     usa outro endereço no lugar da API do GitHub (testes)

enum State { CHECKING, AVAILABLE, DOWNLOADING, INSTALLING, FAILED }

const MAIN_SCENE := "res://scenes/main.tscn"
const CHECK_TIMEOUT := 8.0
const BYTES_PER_MB := 1048576.0

@onready var title_label: Label = %Title
@onready var status_label: Label = %Status
@onready var notes_text: RichTextLabel = %Notes
@onready var progress_bar: ProgressBar = %Progress
@onready var primary_button: Button = %PrimaryButton
@onready var notes_button: Button = %NotesButton
@onready var skip_button: Button = %SkipButton
@onready var ui_sound: AudioStreamPlayer = %UiSound
@onready var http: HTTPRequest = %Http

var state := State.CHECKING
var release: Dictionary = {}
var asset: Dictionary = {}
var blocker := ""
var _latest_url := Updater.LATEST_URL
var _download_path := ""
var _last_spoken_quarter := 0
var _leaving := false


func _ready() -> void:
	Updater.check_finished_install()
	Updater.clean_work_dir()

	var args := OS.get_cmdline_user_args()
	var forced := "--testar-atualizador" in args
	for arg in args:
		if arg.begins_with("--atualizacao-url="):
			_latest_url = arg.trim_prefix("--atualizacao-url=")
			forced = true
	# Servidor dedicado, testes automáticos e o editor não precisam da tela.
	var skip := Net.mode != Net.Mode.NONE or "--sem-atualizar" in args
	if not forced and (skip or OS.has_feature("editor") or DisplayServer.get_name() == "headless"):
		_go_to_menu.call_deferred()
		return

	theme = UiTheme.build()
	primary_button.pressed.connect(_on_primary)
	notes_button.pressed.connect(_speak_notes)
	skip_button.pressed.connect(_on_skip)
	for button: Button in [primary_button, notes_button, skip_button]:
		button.focus_entered.connect(_on_focus.bind(button))
		button.pressed.connect(_play.bind(Sounds.ui_confirm()))
	notes_text.focus_entered.connect(_on_notes_focus)
	http.request_completed.connect(_on_request_completed)
	_check()


func _process(_delta: float) -> void:
	if state == State.DOWNLOADING:
		_update_progress()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("repetir_fala"):
		Speech.say(_status_sentence())
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and state != State.INSTALLING:
		get_viewport().set_input_as_handled()
		_on_skip()


# --- Verificação --------------------------------------------------------------

func _check() -> void:
	state = State.CHECKING
	title_label.text = "Fawna"
	status_label.text = "Procurando atualizações..."
	notes_text.hide()
	progress_bar.hide()
	_show_buttons([])
	Speech.say("Fawna, versão %s. Procurando atualizações." % Updater.current_version())
	http.timeout = CHECK_TIMEOUT
	http.download_file = ""
	var headers := ["Accept: application/vnd.github+json", "User-Agent: Fawna-Atualizador"]
	if http.request(_latest_url, headers) != OK:
		_no_update("não deu para procurar atualizações")


func _on_request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if state == State.CHECKING:
		_on_check_done(result, code, body)
	elif state == State.DOWNLOADING:
		_on_download_done(result, code)


func _on_check_done(result: int, code: int, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		_no_update("sem conexão para procurar atualizações")
		return
	if code == 404:
		_no_update("")  # o repositório ainda não tem nenhuma release
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if code != 200 or not data is Dictionary:
		_no_update("não deu para procurar atualizações")
		return
	release = data
	var remote := str(release.get("tag_name", ""))
	if not Updater.is_newer(remote, Updater.current_version()):
		_no_update("")
		return
	asset = Updater.pick_asset(release)
	blocker = Updater.self_update_blocker()
	if asset.is_empty() and blocker.is_empty():
		blocker = "esta versão não tem um arquivo para o seu sistema"
	_show_available()


## Segue para o menu. Problemas na verificação viram um aviso curto lá.
func _no_update(problem: String) -> void:
	if not problem.is_empty():
		print("[atualizador] %s" % problem)
		Updater.notice += "Não deu para procurar atualizações. "
	_go_to_menu()


# --- Atualização disponível ---------------------------------------------------

func _remote_version() -> String:
	return str(release.get("tag_name", "")).trim_prefix("v")


func _show_available() -> void:
	state = State.AVAILABLE
	title_label.text = "Atualização disponível"
	var size_mb := int(asset.get("size", 0)) / BYTES_PER_MB
	var details := "Versão %s. Você tem a versão %s." % [_remote_version(), Updater.current_version()]
	if size_mb > 0.0:
		details += " Tamanho: %.0f MB." % maxf(size_mb, 1.0)
	if not blocker.is_empty():
		details += "\nNão dá para instalar sozinho porque %s. Baixe pela página da versão." % blocker
	status_label.text = details
	var notes := _notes()
	notes_text.text = _notes_bbcode(notes) if not notes.is_empty() else "Esta versão não tem notas."
	notes_text.show()
	progress_bar.hide()
	primary_button.text = "Baixar e instalar" if blocker.is_empty() else "Abrir página de download"
	notes_button.text = "Ouvir novidades"
	skip_button.text = "Pular"
	_show_buttons([primary_button, notes_button, skip_button])
	_play(Sounds.chime())
	Speech.say("Atualização disponível. %s Escolha %s, Ouvir novidades ou Pular." % [
		details.replace("\n", " "), primary_button.text])
	_focus(primary_button)


func _notes() -> String:
	return str(release.get("body", "")).strip_edges()


## Markdown simples (títulos, listas e negrito) para o texto da tela.
func _notes_bbcode(notes: String) -> String:
	var lines: PackedStringArray = []
	for line in notes.replace("\r", "").split("\n"):
		var clean := line.replace("[", "[lb]").replace("**", "")
		if clean.begins_with("#"):
			clean = "[b]%s[/b]" % clean.lstrip("# ")
		elif clean.begins_with("- ") or clean.begins_with("* "):
			clean = "• " + clean.substr(2)
		lines.append(clean)
	return "\n".join(lines)


func _speak_notes() -> void:
	var notes := _notes()
	if notes.is_empty():
		Speech.say("Esta versão não tem notas.")
		return
	# Tira a marcação mais comum do Markdown para a fala ficar limpa.
	var spoken := notes
	for mark in ["### ", "## ", "# ", "**", "__", "`"]:
		spoken = spoken.replace(mark, "")
	spoken = spoken.replace("\r", "").replace("\n- ", "\n").replace("\n* ", "\n")
	if spoken.begins_with("- ") or spoken.begins_with("* "):
		spoken = spoken.substr(2)
	Speech.say("Novidades da versão %s. %s" % [_remote_version(), spoken.replace("\n", ". ")])


func _on_primary() -> void:
	match state:
		State.AVAILABLE:
			if blocker.is_empty():
				_start_download()
			else:
				OS.shell_open(str(release.get("html_url", Updater.RELEASES_PAGE)))
				Speech.say("Página aberta no navegador. Depois de instalar, abra o jogo de novo.")
		State.FAILED:
			_start_download()


func _on_skip() -> void:
	if state == State.DOWNLOADING:
		http.cancel_request()
		DirAccess.remove_absolute(_download_path)
		Speech.say("Download cancelado.")
		_show_available()
		return
	_go_to_menu()


# --- Download -----------------------------------------------------------------

func _start_download() -> void:
	state = State.DOWNLOADING
	title_label.text = "Baixando a versão %s" % _remote_version()
	status_label.text = "Baixando... 0%"
	notes_text.hide()
	progress_bar.value = 0
	progress_bar.show()
	skip_button.text = "Cancelar"
	_show_buttons([skip_button])
	_focus(skip_button)
	_last_spoken_quarter = 0
	DirAccess.make_dir_recursive_absolute(Updater.WORK_DIR)
	_download_path = ProjectSettings.globalize_path(Updater.WORK_DIR.path_join(str(asset.get("name", "fawna.zip"))))
	http.timeout = 0.0
	http.download_file = _download_path
	var headers := ["Accept: application/octet-stream", "User-Agent: Fawna-Atualizador"]
	Speech.say("Baixando. Aperte Esc para cancelar ou R para ouvir o progresso.")
	if http.request(str(asset.get("browser_download_url", "")), headers) != OK:
		_fail("não deu para começar o download")


func _percent() -> int:
	var total := http.get_body_size()
	if total <= 0:
		total = int(asset.get("size", 0))
	if total <= 0:
		return 0
	return clampi(int(100.0 * http.get_downloaded_bytes() / total), 0, 100)


func _update_progress() -> void:
	var percent := _percent()
	progress_bar.value = percent
	status_label.text = "Baixando... %d%%" % percent
	var quarter := percent / 25
	if quarter > _last_spoken_quarter and quarter < 4:
		_last_spoken_quarter = quarter
		Speech.say("%d por cento." % (quarter * 25), false)


func _on_download_done(result: int, code: int) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail("o download não terminou")
		return
	progress_bar.value = 100
	var problem := Updater.verify_download(_download_path, asset)
	if not problem.is_empty():
		_fail(problem)
		return
	_install()


# --- Instalação ---------------------------------------------------------------

func _install() -> void:
	state = State.INSTALLING
	title_label.text = "Instalando"
	status_label.text = "O jogo vai fechar e abrir de novo sozinho, já na versão %s." % _remote_version()
	progress_bar.hide()
	_show_buttons([])
	Speech.say("Download completo. Instalando. %s" % status_label.text)
	var staged := ProjectSettings.globalize_path(Updater.WORK_DIR.path_join("nova_versao"))
	var err := Updater.extract_zip(_download_path, staged)
	DirAccess.remove_absolute(_download_path)
	if err != OK:
		_fail("não deu para abrir o arquivo baixado")
		return
	err = Updater.launch_installer(staged, _remote_version())
	if err != OK:
		_fail("não deu para começar a instalação")
		return
	# Tempo para a fala terminar antes de fechar.
	await get_tree().create_timer(4.0).timeout
	get_tree().quit()


func _fail(reason: String) -> void:
	state = State.FAILED
	print("[atualizador] falhou: %s" % reason)
	title_label.text = "Não deu para atualizar"
	status_label.text = "Motivo: %s." % reason
	progress_bar.hide()
	notes_text.hide()
	primary_button.text = "Tentar de novo"
	skip_button.text = "Continuar sem atualizar"
	_show_buttons([primary_button, skip_button])
	Speech.say("Não deu para atualizar: %s. Tentar de novo, ou continuar sem atualizar." % reason)
	_focus(primary_button)


# --- Utilidades ---------------------------------------------------------------

func _status_sentence() -> String:
	match state:
		State.DOWNLOADING:
			return "Baixando, %d por cento." % _percent()
		State.CHECKING:
			return "Procurando atualizações."
	return "%s. %s" % [title_label.text, status_label.text.replace("\n", " ")]


func _show_buttons(visible_buttons: Array) -> void:
	for button: Button in [primary_button, notes_button, skip_button]:
		button.visible = button in visible_buttons


func _focus(button: Button) -> void:
	# A fala do estado novo já cita o botão; evita repetir o nome dele.
	if not button.has_focus():
		button.set_meta("silent_focus", true)
	button.grab_focus.call_deferred()


func _on_focus(button: Button) -> void:
	_play(Sounds.ui_move())
	if button.get_meta("silent_focus", false):
		button.set_meta("silent_focus", false)
		return
	if not Speech.screen_reader_active():
		Speech.say("%s, botão" % button.text, false)


func _on_notes_focus() -> void:
	_play(Sounds.ui_move())
	if not Speech.screen_reader_active():
		_speak_notes()


func _play(stream: AudioStream) -> void:
	if stream == null or not ui_sound.is_inside_tree():
		return
	ui_sound.stream = stream
	ui_sound.play()


func _go_to_menu() -> void:
	if _leaving:
		return
	_leaving = true
	get_tree().change_scene_to_file(MAIN_SCENE)
