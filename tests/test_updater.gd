extends SceneTree
## Testes do atualizador (versões, escolha do arquivo e extração do zip).
## Rodar: godot --headless --path . --script res://tests/test_updater.gd

var _failures := 0


func _init() -> void:
	_test_versions()
	_test_pick_asset()
	_test_extract_zip()
	_test_verify_download()
	if _failures == 0:
		print("OK: todos os testes passaram")
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FALHOU: " + message)


func _test_versions() -> void:
	_check(Updater.parse_version("v1.2.3") == [1, 2, 3], "parse v1.2.3")
	_check(Updater.parse_version("0.4") == [0, 4, 0], "parse 0.4")
	_check(Updater.parse_version("1.0.0-beta.2") == [1, 0, 0], "parse com sufixo")
	_check(Updater.is_newer("v0.2.0", "0.1.0"), "0.2.0 > 0.1.0")
	_check(Updater.is_newer("v0.10.0", "0.9.9"), "0.10.0 > 0.9.9 (número, não texto)")
	_check(not Updater.is_newer("v0.1.0", "0.1.0"), "mesma versão")
	_check(not Updater.is_newer("v0.1.0", "0.2.0"), "versão mais velha")
	_check(Updater.is_newer("1.0", "0.9.9"), "1.0 > 0.9.9")


func _test_pick_asset() -> void:
	var release := {"assets": [
		{"name": "fawna-0.2.0-linux.zip"},
		{"name": "fawna-0.2.0-windows.zip"},
		{"name": "notas.txt"},
	]}
	_check(Updater.pick_asset(release, "windows").name == "fawna-0.2.0-windows.zip", "escolhe windows")
	_check(Updater.pick_asset(release, "linux").name == "fawna-0.2.0-linux.zip", "escolhe linux")
	_check(Updater.pick_asset(release, "").is_empty(), "sem plataforma")
	_check(Updater.pick_asset({}, "windows").is_empty(), "release sem arquivos")


func _make_zip(path: String, files: Dictionary) -> void:
	var packer := ZIPPacker.new()
	packer.open(path)
	for name: String in files:
		packer.start_file(name)
		packer.write_file(str(files[name]).to_utf8_buffer())
		packer.close_file()
	packer.close()


func _test_extract_zip() -> void:
	var base := ProjectSettings.globalize_path("user://teste_atualizador")
	Updater._remove_recursive(base)
	DirAccess.make_dir_recursive_absolute(base)

	# Tudo dentro de uma pasta só: a pasta some do caminho.
	var zip_a := base.path_join("a.zip")
	_make_zip(zip_a, {"Fawna/Fawna.exe": "exe", "Fawna/addons/prismatoid/bin/prism.dll": "dll"})
	_check(Updater.extract_zip(zip_a, base.path_join("a")) == OK, "extrai zip com pasta raiz")
	_check(FileAccess.get_file_as_string(base.path_join("a/Fawna.exe")) == "exe", "remove pasta raiz")
	_check(FileAccess.file_exists(base.path_join("a/addons/prismatoid/bin/prism.dll")), "mantém subpastas")

	# Arquivos soltos na raiz do zip.
	var zip_b := base.path_join("b.zip")
	_make_zip(zip_b, {"Fawna.exe": "exe", "Fawna.pck": "pck"})
	_check(Updater.extract_zip(zip_b, base.path_join("b")) == OK, "extrai zip sem pasta raiz")
	_check(FileAccess.file_exists(base.path_join("b/Fawna.pck")), "arquivo solto")

	# Caminho que tenta sair da pasta é recusado.
	var zip_c := base.path_join("c.zip")
	_make_zip(zip_c, {"ok.txt": "1", "../fora.txt": "2"})
	_check(Updater.extract_zip(zip_c, base.path_join("c")) != OK, "recusa ../")
	_check(not FileAccess.file_exists(base.path_join("fora.txt")), "nada escrito fora")
	Updater._remove_recursive(base)


func _test_verify_download() -> void:
	var path := ProjectSettings.globalize_path("user://teste_download.bin")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("fawna")
	file.close()
	var sha := FileAccess.get_sha256(path)
	_check(Updater.verify_download(path, {"size": 5, "digest": "sha256:" + sha}) == "", "arquivo certo")
	_check(Updater.verify_download(path, {"size": 6}) != "", "tamanho errado")
	_check(Updater.verify_download(path, {"size": 5, "digest": "sha256:00"}) != "", "sha errado")
	DirAccess.remove_absolute(path)
