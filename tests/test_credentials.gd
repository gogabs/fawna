extends SceneTree
## Testes do login dos personagens (Credentials e WorldState.login).
## Rodar: godot --headless --path . --script res://tests/test_credentials.gd

var _failures := 0


func _init() -> void:
	var state := WorldState.new(7)
	# Personagem antigo, de antes do login: tem bolsa, mas não tem senha.
	state.inventories["Lua"] = {"bambu": 3}

	var first := state.login("Lua", "abcd")
	_check(first["ok"] and first["created"], "primeiro a entrar num nome define a senha")
	state.add_player(1, "Lua")
	_check(state.login("Lua", "abcd")["reason"] == "ja_conectado", "mesmo personagem não entra duas vezes")
	state.remove_player(1)
	_check(state.inventories["Lua"]["bambu"] == 3, "o inventário antigo continua do personagem")

	_check(state.login("Lua", "abcd")["ok"], "senha certa entra")
	_check(not state.login("Lua", "abcd")["created"], "senha certa não registra de novo")
	_check(state.login("Lua", "outra")["reason"] == "errada", "senha errada é recusada")
	_check(state.login("Lua", "outra")["reason"] == "devagar", "tentativas seguidas esperam")
	_check(state.login("Lua", "abc")["reason"] == "curta", "senha curta é recusada")
	_check(state.login("", "abcd")["reason"] == "sem_nome", "sem nome é recusado")

	# Passado o intervalo, a senha certa volta a valer.
	_check(state.credentials.check("Lua", "abcd", Time.get_ticks_msec() / 1000.0 + 10.0) == "ok", "depois da espera a senha certa entra")

	# Maiúsculas importam na senha.
	_check(state.credentials.check("Lua", "ABCD", Time.get_ticks_msec() / 1000.0 + 20.0) == "errada", "senha diferencia maiúsculas")

	# Persistência: o save guarda hash, nunca a senha.
	var saved := JSON.stringify(state.to_save())
	_check(not saved.contains("abcd"), "o save não guarda a senha")
	var loaded := WorldState.from_save(JSON.parse_string(saved))
	_check(loaded.login("Lua", "abcd")["ok"], "senha vale depois de recarregar o save")
	var wrong := loaded.login("Lua", "xxxx")
	_check(wrong["reason"] == "errada", "senha errada recusada depois de recarregar")
	_check(loaded.login("Sol", "xxxx")["created"], "outro nome registra a própria senha")

	# Save sem credenciais (mundo anterior ao login) carrega e deixa os nomes livres.
	var old := WorldState.from_save({"seed": 7, "inventories": {"Vento": {"bambu": 1}}})
	_check(old.login("Vento", "qualquer")["created"], "personagem antigo é reclamado por quem entra primeiro")

	if _failures == 0:
		print("OK: todos os testes passaram")
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FALHOU: " + message)
