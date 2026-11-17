class_name FloatingMenu
extends RefCounted
## Menu flutuante das setas, sempre ativo durante o jogo (as setas não
## movem a criatura; quem anda é W/A/S/D e quem gira é Q/E).
##
## A orientação das setas é a das opções (Net.vertical_nav, ver MenuNav):
##   Horizontal (padrão): Esquerda/Direita passam pelas opções do nível
##     atual, Cima confirma (entra na opção ou executa), Baixo volta um nível
##   Vertical: Cima/Baixo passam pelas opções, Direita confirma, Esquerda volta
##
## Cada opção é um dicionário com "label" e uma destas chaves:
##   "open": Callable que devolve as opções do submenu (Array de opções)
##   "run":  Callable executado ao confirmar; o menu não fecha: o foco fica
##           onde está e as opções são atualizadas
##   "info": texto falado ao confirmar, sem sair do lugar (itens sem ação)
## Opcionais: "close" (com "run": fecha o menu depois, para o fim de um fluxo), "empty" (o que dizer se o submenu vier vazio) e os sons do
## submenu, no lugar dos genéricos: "open_sound" (ao entrar, em vez de
## "abrir"), "move_sound" (ao passar pelas opções, em vez de "mover") e
## "close_sound" (ao sair com Baixo, em vez de "fechar").
## press() devolve o texto a falar; quem usa o menu (o jogo) fala e toca os
## sons de interface.

signal sound(kind: String)  # "mover", "abrir", "confirmar", "fechar", "limite" ou um "open_sound"

var _root: Callable  # devolve as opções do primeiro nível
var _levels: Array = []  # [{ "title", "items", "index" }], o último é o atual


func _init(root: Callable) -> void:
	_root = root
	reset()


func reset() -> void:
	_levels = [{"title": "", "items": _root.call(), "index": 0}]


## Abre o menu direto num submenu, a partir do começo (ex.: o Espaço num
## marco abre a escolha do nome). source devolve as opções. Devolve o texto
## a falar.
func open_at(title: String, source: Callable) -> String:
	reset()
	_levels.append({"title": title, "items": source.call(), "index": 0, "source": source,
		"move_sound": "mover", "close_sound": "fechar"})
	sound.emit("abrir")
	return "%s. %s" % [title, _describe(_levels[-1])]


func depth() -> int:
	return _levels.size()


func current_label() -> String:
	var level: Dictionary = _levels[-1]
	if level["items"].is_empty():
		return ""
	return level["items"][level["index"]]["label"]


## "esquerda", "direita", "cima" ou "baixo". Devolve o texto a falar.
func press(direction: String) -> String:
	var text := ""
	match MenuNav.action(direction):
		"anterior":
			text = _move(-1)
		"proximo":
			text = _move(1)
		"confirmar":
			text = _confirm()
		"voltar":
			text = _back()
	return text


func _move(step: int) -> String:
	var level: Dictionary = _levels[-1]
	var items: Array = level["items"]
	if items.is_empty():
		return ""
	level["index"] = posmod(level["index"] + step, items.size())
	sound.emit(level.get("move_sound", "mover"))
	return _describe(level)


func _confirm() -> String:
	var level: Dictionary = _levels[-1]
	if level["items"].is_empty():
		return ""
	var item: Dictionary = level["items"][level["index"]]
	if item.has("info"):
		return item["info"]
	if item.has("open"):
		var items: Array = item["open"].call()
		_levels.append({"title": item["label"], "items": items, "index": 0, "source": item["open"],
			"move_sound": item.get("move_sound", "mover"), "close_sound": item.get("close_sound", "fechar")})
		sound.emit(item.get("open_sound", "abrir"))
		if items.is_empty():
			return "%s: %s." % [item["label"], item.get("empty", "nada aqui por enquanto")]
		return "%s. %s" % [item["label"], _describe(_levels[-1])]
	sound.emit("confirmar")
	# O menu nunca fecha ao executar: o foco fica onde está e só as opções são
	# atualizadas (a bolsa mudou, o cristal acendeu, o monte esvaziou...). Se a
	# ação abriu outro menu (open_at), esse é que vale.
	var depth_before := _levels.size()
	var said: Variant = item["run"].call() if item.has("run") else ""
	if item.get("close", false):  # só para o fim de um fluxo (ex.: escolher o nome)
		reset()
	elif _levels.size() == depth_before and is_same(_levels[-1], level):
		_refresh(level)
	return said if said is String else ""


## O mundo mudou por fora do menu (a bolsa, as mãos, o chão): atualiza as
## opções de todos os níveis. Um nível que tinha opções e ficou vazio (o item
## acabou) é fechado junto com os de dentro dele, e o foco volta ao menu pai
## mais próximo que ainda existe. Devolve o texto a falar quando o foco subiu;
## vazio se nada se moveu.
func sync() -> String:
	var kept := 1
	_levels[0]["items"] = _root.call()
	_levels[0]["index"] = clampi(_levels[0]["index"], 0, maxi(_levels[0]["items"].size() - 1, 0))
	for i in range(1, _levels.size()):
		var level: Dictionary = _levels[i]
		if not level.has("source"):
			break
		var had_items: bool = not level["items"].is_empty()
		var items: Array = level["source"].call()
		if had_items and items.is_empty():
			break
		level["items"] = items
		level["index"] = clampi(level["index"], 0, maxi(items.size() - 1, 0))
		kept = i + 1
	if kept == _levels.size():
		return ""
	_levels.resize(kept)
	return _describe(_levels[-1])


## Voltar sobe um nível; no primeiro, só toca o som de limite.
func _back() -> String:
	if _levels.size() <= 1:
		sound.emit("limite")
		return ""
	var closed: Dictionary = _levels.pop_back()
	_refresh(_levels[-1])
	sound.emit(closed.get("close_sound", "fechar"))
	return _describe(_levels[-1])


## As opções do nível podem ter mudado: pergunta de novo à fonte dele.
func _refresh(level: Dictionary) -> void:
	var source: Callable = level.get("source", _root) if _levels.size() > 1 else _root
	var index: int = level["index"]
	level["items"] = source.call()
	level["index"] = clampi(index, 0, maxi(level["items"].size() - 1, 0))


## "Origem", ou "Origem, 1 de 2" quando há mais de uma opção.
static func _describe(level: Dictionary) -> String:
	var items: Array = level["items"]
	if items.is_empty():
		return "nada aqui por enquanto"
	var label: String = items[level["index"]]["label"]
	if items.size() == 1:
		return label
	return "%s, %d de %d" % [label, level["index"] + 1, items.size()]
