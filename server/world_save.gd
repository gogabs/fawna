class_name WorldSave
extends RefCounted
## Salva e carrega o mundo do servidor num arquivo JSON.
## Só guarda o que os jogadores mudaram; o terreno vem da semente.

const DEFAULT_PATH := "user://mundo.json"


static func load_state(path: String) -> WorldState:
	if not FileAccess.file_exists(path):
		return null
	var text := FileAccess.get_file_as_string(path)
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY or not data.has("seed"):
		push_warning("Arquivo do mundo inválido em %s; começando um mundo novo." % path)
		return null
	return WorldState.from_save(data)


static func save_state(state: WorldState, path: String) -> bool:
	var tmp_path := path + ".tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_error("Não foi possível salvar o mundo em %s" % path)
		return false
	file.store_string(JSON.stringify(state.to_save(), "\t"))
	file.close()
	# Troca o arquivo de uma vez, para uma queda no meio não corromper o save.
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp_path), ProjectSettings.globalize_path(path))
	return err == OK
