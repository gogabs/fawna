class_name Updater
extends RefCounted
## Lógica do atualizador: compara versões, escolhe o arquivo certo da release
## no GitHub, extrai o zip e troca os arquivos do jogo depois que ele fecha.
##
## O jogo não consegue sobrescrever o próprio executável enquanto roda
## (principalmente no Windows). Por isso a instalação extrai a versão nova numa
## pasta temporária e deixa um script pequeno esperando o jogo fechar; ele
## copia os arquivos por cima e abre o jogo de novo.

const REPO := "gogabs/fawna"
const LATEST_URL := "https://api.github.com/repos/%s/releases/latest" % REPO
const RELEASES_PAGE := "https://github.com/%s/releases/latest" % REPO
const WORK_DIR := "user://atualizacao"
const PENDING_FILE := "user://atualizacao/instalando.cfg"

## Aviso curto que o menu principal fala antes da apresentação dele
## (ex.: "Atualização instalada."). Lido uma vez só com take_notice().
static var notice := ""


static func take_notice() -> String:
	var text := notice
	notice = ""
	return text


static func current_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


## "v1.2.3", "1.2" ou "1.2.3-beta" viram [1, 2, 3]. Sufixos são ignorados.
static func parse_version(text: String) -> Array[int]:
	var clean := text.strip_edges().trim_prefix("v").trim_prefix("V")
	clean = clean.get_slice("-", 0).get_slice("+", 0)
	var parts: Array[int] = []
	for piece in clean.split("."):
		parts.append(int(piece) if piece.is_valid_int() else 0)
	while parts.size() < 3:
		parts.append(0)
	return parts


static func is_newer(remote: String, local: String) -> bool:
	var a := parse_version(remote)
	var b := parse_version(local)
	for i in maxi(a.size(), b.size()):
		var x := a[i] if i < a.size() else 0
		var y := b[i] if i < b.size() else 0
		if x != y:
			return x > y
	return false


## Nome da plataforma como aparece no nome do zip da release.
static func platform_tag() -> String:
	match OS.get_name():
		"Windows":
			return "windows"
		"Linux", "FreeBSD":
			return "linux"
	return ""


## Procura o zip desta plataforma (ex.: fawna-0.2.0-windows.zip).
static func pick_asset(release: Dictionary, platform := platform_tag()) -> Dictionary:
	if platform.is_empty():
		return {}
	for asset: Dictionary in release.get("assets", []):
		var file_name := str(asset.get("name", "")).to_lower()
		if file_name.ends_with(".zip") and file_name.contains(platform):
			return asset
	return {}


## Pasta onde o jogo está instalado (onde fica o executável).
static func game_dir() -> String:
	return OS.get_executable_path().get_base_dir()


## Motivo pelo qual não dá para instalar sozinho, ou "" se dá.
static func self_update_blocker() -> String:
	if OS.has_feature("editor"):
		return "o jogo está rodando pelo editor do Godot"
	if platform_tag().is_empty():
		return "a instalação automática ainda não funciona neste sistema"
	if not can_write_to(game_dir()):
		return "o jogo não tem permissão para escrever na pasta dele"
	return ""


static func can_write_to(dir: String) -> bool:
	var probe := dir.path_join(".fawna_teste_escrita")
	var file := FileAccess.open(probe, FileAccess.WRITE)
	if file == null:
		return false
	file.close()
	DirAccess.remove_absolute(probe)
	return true


## Confere o tamanho e, quando a release informa, o SHA-256 do arquivo baixado.
static func verify_download(path: String, asset: Dictionary) -> String:
	if not FileAccess.file_exists(path):
		return "o arquivo baixado sumiu"
	var expected_size := int(asset.get("size", 0))
	var file := FileAccess.open(path, FileAccess.READ)
	var actual_size := file.get_length() if file != null else 0
	if file != null:
		file.close()
	if expected_size > 0 and actual_size != expected_size:
		return "o arquivo veio incompleto"
	var digest := str(asset.get("digest", ""))
	if digest.begins_with("sha256:"):
		if FileAccess.get_sha256(path) != digest.trim_prefix("sha256:").to_lower():
			return "o arquivo veio corrompido"
	return ""


## Extrai o zip em dest. Se tudo estiver dentro de uma pasta só no zip,
## essa pasta é removida do caminho. Recusa caminhos que saem de dest.
static func extract_zip(zip_path: String, dest: String) -> Error:
	var zip := ZIPReader.new()
	var err := zip.open(zip_path)
	if err != OK:
		return err
	var files := zip.get_files()
	var prefix := _common_root(files)
	DirAccess.make_dir_recursive_absolute(dest)
	for entry in files:
		var relative := entry.trim_prefix(prefix)
		if relative.is_empty() or relative.ends_with("/"):
			continue
		if relative.begins_with("/") or relative.contains("..") or relative.contains(":"):
			zip.close()
			return ERR_FILE_CORRUPT
		var target := dest.path_join(relative)
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		var out := FileAccess.open(target, FileAccess.WRITE)
		if out == null:
			zip.close()
			return FileAccess.get_open_error()
		out.store_buffer(zip.read_file(entry))
		out.close()
	zip.close()
	return OK


static func _common_root(files: PackedStringArray) -> String:
	var root := ""
	for entry in files:
		if not entry.contains("/"):
			return ""
		var first := entry.get_slice("/", 0) + "/"
		if root.is_empty():
			root = first
		elif root != first:
			return ""
	return root


## Deixa o script de troca rodando e marca a versão que está sendo instalada.
## Quem chama precisa fechar o jogo logo em seguida.
static func launch_installer(staged_dir: String, version: String) -> Error:
	var work := ProjectSettings.globalize_path(WORK_DIR)
	var exe := OS.get_executable_path()
	var pid := str(OS.get_process_id())
	var err := OK
	var pending := ConfigFile.new()
	pending.set_value("atualizacao", "versao", version)
	pending.save(PENDING_FILE)
	if OS.get_name() == "Windows":
		var script := work.path_join("instalar.ps1")
		err = _write_text(script, WINDOWS_SCRIPT)
		if err != OK:
			return err
		var pid_started := OS.create_process("powershell.exe", [
			"-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden",
			"-File", script, "-GamePid", pid, "-Source", staged_dir,
			"-Target", game_dir(), "-Exe", exe,
		])
		return OK if pid_started > 0 else ERR_CANT_FORK
	var sh_script := work.path_join("instalar.sh")
	err = _write_text(sh_script, UNIX_SCRIPT)
	if err != OK:
		return err
	var started := OS.create_process("/bin/sh", [sh_script, pid, staged_dir, game_dir(), exe])
	return OK if started > 0 else ERR_CANT_FORK


## Chamado ao abrir o jogo: se uma instalação terminou, prepara o aviso.
static func check_finished_install() -> void:
	if not FileAccess.file_exists(PENDING_FILE):
		return
	var pending := ConfigFile.new()
	pending.load(PENDING_FILE)
	var version := str(pending.get_value("atualizacao", "versao", ""))
	DirAccess.remove_absolute(PENDING_FILE)
	if version.is_empty():
		return
	if parse_version(version) == parse_version(current_version()):
		notice = "Atualização instalada. Agora você está na versão %s. " % current_version()
	else:
		notice = "A atualização para a versão %s não foi instalada. Tente de novo mais tarde. " % version


## Apaga downloads e pastas temporárias de atualizações anteriores.
static func clean_work_dir() -> void:
	var work := ProjectSettings.globalize_path(WORK_DIR)
	if DirAccess.dir_exists_absolute(work):
		_remove_recursive(work)


static func _remove_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.include_hidden = true
	for sub in dir.get_directories():
		_remove_recursive(path.path_join(sub))
	for file_name in dir.get_files():
		dir.remove(file_name)
	DirAccess.remove_absolute(path)


static func _write_text(path: String, text: String) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.close()
	return OK


# Os scripts só usam ASCII; os caminhos (que podem ter acentos) vão como
# argumentos, que o Windows passa em Unicode.

const WINDOWS_SCRIPT := """param([int]$GamePid, [string]$Source, [string]$Target, [string]$Exe)
$log = Join-Path $env:TEMP 'fawna-atualizacao.log'
"Atualizando de $Source para $Target" | Out-File -FilePath $log -Encoding utf8
Wait-Process -Id $GamePid -Timeout 60 -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500
robocopy $Source $Target /E /R:10 /W:1 /NP /NJH /NJS | Out-File -FilePath $log -Append -Encoding utf8
if ($LASTEXITCODE -lt 8) {
	Remove-Item -LiteralPath $Source -Recurse -Force -ErrorAction SilentlyContinue
} else {
	"robocopy falhou com codigo $LASTEXITCODE" | Out-File -FilePath $log -Append -Encoding utf8
}
Start-Process -FilePath $Exe -WorkingDirectory $Target
"""

const UNIX_SCRIPT := """#!/bin/sh
pid="$1"; src="$2"; dst="$3"; exe="$4"
i=0
while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 120 ]; do sleep 0.5; i=$((i + 1)); done
if cp -Rf "$src"/. "$dst"/; then rm -rf "$src"; fi
chmod +x "$exe" 2>/dev/null
cd "$dst" && nohup "$exe" >/dev/null 2>&1 &
"""
