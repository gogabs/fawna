class_name FloatingMenu
extends RefCounted
## Menu flutuante das setas, sempre ativo durante o jogo (as setas não
## movem a criatura; quem anda é W/A/S/D e quem gira é Q/E).
##
##   Esquerda e Direita: passam pelas opções do nível atual
##   Cima: confirma (entra na opção ou executa)
##   Baixo: volta um nível
##
## Cada opção é um dicionário com "label" e uma destas chaves:
##   "open": Callable que devolve as opções do submenu (Array de opções)
##   "run":  Callable executado ao confirmar; depois o menu volta ao começo
## press() devolve o texto a falar; quem usa o menu (o jogo) fala e toca os
## sons de interface.

signal sound(kind: String)  # "mover", "abrir", "confirmar", "fechar"

var _root: Callable  # devolve as opções do primeiro nível
var _levels: Array = []  # [{ "title", "items", "index" }], o último é o atual


func _init(root: Callable) -> void:
	_root = root
	reset()


func reset() -> void:
	_levels = [{"title": "", "items": _root.call(), "index": 0}]


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
	match direction:
		"esquerda", "direita":
			text = _move(-1 if direction == "esquerda" else 1)
		"cima":
			text = _confirm()
		"baixo":
			text = _back()
	return text


func _move(step: int) -> String:
	var level: Dictionary = _levels[-1]
	var items: Array = level["items"]
	if items.is_empty():
		return ""
	level["index"] = posmod(level["index"] + step, items.size())
	sound.emit("mover")
	return _describe(level)


func _confirm() -> String:
	var level: Dictionary = _levels[-1]
	if level["items"].is_empty():
		return ""
	var item: Dictionary = level["items"][level["index"]]
	if item.has("open"):
		var items: Array = item["open"].call()
		_levels.append({"title": item["label"], "items": items, "index": 0})
		sound.emit("abrir")
		if items.is_empty():
			return "%s: nada aqui por enquanto." % item["label"]
		return "%s. %s" % [item["label"], _describe(_levels[-1])]
	sound.emit("confirmar")
	reset()
	if item.has("run"):
		var said: Variant = item["run"].call()
		return said if said is String else ""
	return ""


func _back() -> String:
	if _levels.size() <= 1:
		# No primeiro nível, Baixo só lembra onde se está.
		return "Menu das setas: %s." % _describe(_levels[-1])
	_levels.pop_back()
	# As opções podem ter mudado (ex.: o cristal acendeu).
	var level: Dictionary = _levels[-1]
	if _levels.size() == 1:
		var index: int = level["index"]
		level["items"] = _root.call()
		level["index"] = clampi(index, 0, maxi(level["items"].size() - 1, 0))
	sound.emit("fechar")
	return _describe(level)


## "Origem", ou "Origem, 1 de 2" quando há mais de uma opção.
static func _describe(level: Dictionary) -> String:
	var items: Array = level["items"]
	if items.is_empty():
		return "nada aqui por enquanto"
	var label: String = items[level["index"]]["label"]
	if items.size() == 1:
		return label
	return "%s, %d de %d" % [label, level["index"] + 1, items.size()]
