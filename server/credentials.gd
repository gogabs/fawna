class_name Credentials
extends RefCounted
## Senhas dos personagens, guardadas só no servidor (no save do mundo).
##
## Cada nome tem uma senha. O primeiro a entrar com um nome (inclusive os
## personagens que já existiam antes do login) define a senha; depois, só
## entra quem souber. O save guarda só um hash com sal, nunca a senha.

const MIN_LENGTH := 4
const MAX_LENGTH := 64
const ROUNDS := 2000
## Intervalo mínimo entre duas tentativas erradas no mesmo nome (segundos).
const RETRY_DELAY := 3.0

## nome -> { "salt": String, "hash": String }
var entries := {}
var _last_failure := {}


static func hash_of(salt: String, password: String) -> String:
	var digest := salt + password
	for i in ROUNDS:
		digest = (salt + digest).sha256_text()
	return digest


## "ok" (senha certa), "criada" (primeira vez: a senha ficou registrada),
## "errada", "curta" ou "devagar" (muitas tentativas erradas seguidas).
func check(player_name: String, password: String, now := -1.0) -> String:
	if now < 0.0:
		now = Time.get_ticks_msec() / 1000.0
	if password.length() < MIN_LENGTH:
		return "curta"
	if not entries.has(player_name):
		var salt := Crypto.new().generate_random_bytes(16).hex_encode()
		entries[player_name] = {"salt": salt, "hash": hash_of(salt, password)}
		return "criada"
	if now - float(_last_failure.get(player_name, -1000.0)) < RETRY_DELAY:
		return "devagar"
	var entry: Dictionary = entries[player_name]
	if hash_of(entry["salt"], password) == entry["hash"]:
		_last_failure.erase(player_name)
		return "ok"
	_last_failure[player_name] = now
	return "errada"


func to_save() -> Dictionary:
	return entries.duplicate(true)


func load_save(data: Dictionary) -> void:
	for player_name: String in data:
		var entry = data[player_name]
		if typeof(entry) == TYPE_DICTIONARY and entry.has("salt") and entry.has("hash"):
			entries[player_name] = {"salt": str(entry["salt"]), "hash": str(entry["hash"])}
