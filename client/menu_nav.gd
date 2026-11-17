class_name MenuNav
extends RefCounted
## Navegação dos menus por setas, igual em todos (flutuante, Caminheiro,
## pilhas, principal e opções). A orientação vem de Net.vertical_nav:
##
##   Horizontal (padrão): Esquerda/Direita navegam, Cima confirma, Baixo volta
##   Vertical:            Cima/Baixo navegam, Direita confirma, Esquerda volta
##
## Resultado: "anterior", "proximo", "confirmar" ou "voltar".

const ACTIONS := {
	"menu_cima": "cima", "menu_baixo": "baixo", "menu_esquerda": "esquerda", "menu_direita": "direita",
}


## direction: "cima", "baixo", "esquerda" ou "direita".
static func action(direction: String, vertical := Net.vertical_nav) -> String:
	if vertical:
		match direction:
			"cima": return "anterior"
			"baixo": return "proximo"
			"esquerda": return "voltar"
			"direita": return "confirmar"
	else:
		match direction:
			"esquerda": return "anterior"
			"direita": return "proximo"
			"cima": return "confirmar"
			"baixo": return "voltar"
	return ""


## A ação do menu para uma tecla (só as setas); vazio para qualquer outra.
## Repetição (tecla segurada) só vale para anterior e próximo.
static func from_event(event: InputEvent) -> String:
	if not event.is_pressed():
		return ""
	for input_action: String in ACTIONS:
		if event.is_action(input_action):
			var result := action(ACTIONS[input_action])
			if event.is_echo() and result != "anterior" and result != "proximo":
				return ""
			return result
	return ""


## Como usar as setas, para falar.
static func help(vertical := Net.vertical_nav) -> String:
	if vertical:
		return "Cima e baixo escolhem, seta para a direita confirma e seta para a esquerda volta."
	return "Esquerda e direita escolhem, seta para cima confirma e seta para baixo volta."
