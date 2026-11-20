extends SceneTree
## Testes da votação no marco para derrubar construções comuns, dos membros e
## da inatividade. Rodar: godot --headless --path . --script res://tests/test_vote.gd

var _failures := 0
const D := Builds.DAY
const T0 := 1000000.0


func _init() -> void:
	_test_membership()
	_test_vote_flow()
	_test_limits()
	_test_expiry_and_inactivity()
	_test_persistence()
	if _failures == 0:
		print("OK: todos os testes passaram")
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FALHOU: " + message)


func _cell(dx: int, dy := 0) -> Vector2i:
	return WorldGen.cell_of(WorldGen.center_point()) + Vector2i(-20 + dx, -20 + dy)


## Povoado de teste: marco com nome, um armazém, uma fogueira e abrigos de
## Ana, Bia e Caco (donos há 8 dias, ativos), mais Duda (dona há 1 dia).
func _town() -> Builds:
	var state := WorldState.new(173)
	var builds := state.builds
	var marco := builds._new_build(1, "marco", _cell(0), 1, "")
	marco["done"] = true
	marco["stage"] = 3
	marco["name"] = "Clareira Esquecida"
	builds._add(marco)
	var shed := builds._fill(builds._new_build(2, "armazem", _cell(10), 4, "sul"), {"size": 4, "entrance": "sul"}, 0.0)
	shed["done"] = true
	shed["stage"] = 4
	builds._add(shed)
	var owners := ["Ana", "Bia", "Caco", "Duda"]
	for i in owners.size():
		var home := builds._fill(builds._new_build(3 + i, "abrigo", _cell(10 + i * 8, 10), 4, "sul"), {"size": 4, "entrance": "sul"}, 0.0)
		home["done"] = true
		home["stage"] = 4
		home["owners"] = [owners[i]]
		home["since"] = {owners[i]: T0 - (1.0 if i == 3 else 8.0) * D}
		builds._add(home)
		builds.touch(owners[i], T0)
	return builds


func _test_membership() -> void:
	var builds := _town()
	var region: Vector2i = builds.get_build(1)["region"]
	var members := builds.members(region, T0)
	_check(members.size() == 3 and not members.has("Duda"), "membros: 3 donos há 7+ dias, sem a recém-chegada")
	_check(not builds.members(region, T0 + 5.0 * D).has("Duda"), "Duda ainda não é membro aos 6 dias")
	_check(builds.members(region, T0 + 6.0 * D).has("Duda"), "Duda vira membro ao completar 7 dias de posse")


func _test_vote_flow() -> void:
	var builds := _town()
	_check(builds.demolish_refusal(2, T0, "Zé") == "votacao", "armazém do povoado: sem votação, ninguém derruba")
	_check(builds.propose_wreck(1, "Zé", 2, T0)["reason"] == "nao_membro", "não membro não propõe")
	_check(builds.propose_wreck(1, "Duda", 2, T0)["reason"] == "nao_membro", "membro há menos de 7 dias não propõe")
	var made := builds.propose_wreck(1, "Ana", 2, T0)
	_check(made["ok"] and made["event"] == "votacao_aberta", "Ana propõe")
	_check(builds.propose_wreck(1, "Bia", 2, T0)["reason"] == "ja_votando", "duas propostas sobre a mesma obra: não")
	_check(builds.propose_wreck(1, "Ana", 1, T0)["reason"] == "alvo", "o marco não vai a votação")
	_check(builds.vote_wreck(1, "Zé", 2, true, T0)["reason"] == "nao_membro", "não membro não vota")
	_check(builds.vote_wreck(1, "Ana", 2, true, T0)["reason"] == "ja_votou", "quem propôs já votou a favor")
	_check(builds.demolish_refusal(2, T0, "Ana") == "votacao", "ainda em votação")
	var vote := builds.vote_wreck(1, "Bia", 2, true, T0 + 100.0)
	_check(vote["ok"] and vote["event"] == "votacao_aprovada", "2 de 3 é maioria: aprovada")
	_check(builds.demolish_refusal(2, T0 + 100.0, "Zé") == "", "aprovada, qualquer um com o machado derruba")
	_check(builds.get_build(1)["votes"].is_empty(), "a votação saiu da lista")
	# Ana tem de esperar 1 dia para propor de novo.
	var again := builds.propose_wreck(1, "Ana", 2, T0 + 200.0)
	_check(again["reason"] == "ja_aprovada", "obra aprovada não vai a nova votação")
	builds.get_build(2)["approved"] = false
	var wait := builds.propose_wreck(1, "Ana", 2, T0 + 200.0)
	_check(wait["reason"] == "espera", "Ana espera 1 dia depois da proposta")
	_check(builds.propose_wreck(1, "Ana", 2, T0 + 100.0 + D + 1.0)["ok"], "passado o dia, propõe outra")


func _test_limits() -> void:
	var builds := _town()
	# Fogueira também vai a votação; uma proposta por membro por vez.
	var fire := builds._new_build(9, "fogueira", _cell(4), 1, "")
	fire["done"] = true
	fire["stage"] = 2
	builds._add(fire)
	_check(builds.propose_wreck(1, "Ana", 2, T0)["ok"], "Ana propõe o armazém")
	_check(builds.propose_wreck(1, "Ana", 9, T0)["reason"] == "ja_propos", "Ana não abre duas ao mesmo tempo")
	_check(builds.propose_wreck(1, "Bia", 9, T0)["ok"], "Bia abre outra, sobre outra obra")
	# Maioria impossível: 2 contra de 3 membros rejeitam.
	var no1 := builds.vote_wreck(1, "Caco", 9, false, T0)
	_check(no1["ok"] and no1["event"] == "voto", "um contra ainda não decide")
	var no2 := builds.vote_wreck(1, "Ana", 9, false, T0)
	_check(no2["event"] == "votacao_rejeitada", "2 contra de 3 rejeitam")
	_check(builds.demolish_refusal(9, T0, "Zé") == "votacao", "rejeitada, a obra segue protegida")
	# Abrigo com dono não vai a votação.
	_check(builds.propose_wreck(1, "Ana", 3, T0)["reason"] == "alvo", "abrigo com dono não vai a votação")
	_check(builds.demolish_refusal(4, T0, "Ana") == "nao_dono", "abrigo de Bia: Ana não derruba")
	_check(builds.demolish_refusal(4, T0, "Bia") == "", "dono derruba o seu abrigo")


func _test_expiry_and_inactivity() -> void:
	var builds := _town()
	builds.propose_wreck(1, "Ana", 2, T0)
	_check(builds.close_votes(T0 + 2.0 * D).is_empty(), "em 2 dias ainda aberta")
	for key in ["Ana", "Bia", "Caco"]:
		builds.touch(key, T0 + 3.0 * D)
	var closed := builds.close_votes(T0 + 3.0 * D + 1.0)
	_check(closed.size() == 1 and closed[0]["event"] == "votacao_rejeitada", "passados 3 dias sem maioria, rejeita")
	# Quem sumiu por 30 dias sai da conta; sem membros ativos, o povoado é livre.
	var later := T0 + 40.0 * D
	_check(builds.members(builds.get_build(1)["region"], later).is_empty(), "todos inativos: sem membros")
	_check(builds.demolish_refusal(2, later, "Zé") == "", "povoado abandonado: qualquer um derruba")
	_check(builds.demolish_refusal(4, later, "Zé") == "", "abrigo de dono inativo: qualquer um derruba")
	# Sem povoado (marco sem nome), nada é protegido por votação.
	var lone := WorldState.new(173)
	var fire := lone.builds._new_build(1, "fogueira", _cell(0), 1, "")
	fire["done"] = true
	lone.builds._add(fire)
	_check(lone.builds.demolish_refusal(1, T0, "Zé") == "", "fora de povoado, qualquer um derruba")
	# Derrubar a obra cancela a votação sobre ela.
	var town := _town()
	town.propose_wreck(1, "Ana", 2, T0)
	town.demolish(2)
	_check(town.get_build(1)["votes"].is_empty(), "votação de obra derrubada some")


func _test_persistence() -> void:
	var builds := _town()
	builds.propose_wreck(1, "Ana", 2, T0)
	var saved := builds.to_save()
	var loaded := WorldState.new(173)
	loaded.builds.load_save(JSON.parse_string(JSON.stringify(saved)))
	var marco: Dictionary = loaded.builds.get_build(1)
	_check(marco["votes"].size() == 1 and marco["votes"][0]["by"] == "Ana", "a votação sobrevive ao salvar")
	_check(loaded.builds.seen.has("Ana"), "a atividade sobrevive ao salvar")
	_check(float(loaded.builds.get_build(3)["since"]["Ana"]) == T0 - 8.0 * D, "a data de posse sobrevive ao salvar")
	var mirror := WorldState.new(173)
	mirror.builds.apply_snapshot(builds.snapshot(T0))
	var copy: Dictionary = mirror.builds.get_build(1)
	_check(copy["votes"].size() == 1 and copy["voters"].size() == 3, "o espelho vê a votação e os membros")
	_check(mirror.builds.vote_text(1, 2, T0).contains("1 a favor"), "texto da votação")
