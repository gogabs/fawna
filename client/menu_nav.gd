class_name MenuNav
extends RefCounted
## Navegação dos menus por setas, igual em todos (flutuante, Caminheiro,
## pilhas, principal e opções). Sempre vertical, como uma árvore de pastas:
##
##   Cima/Baixo navegam, Direita confirma (ou entra), Esquerda volta
##
## Só as setas: os menus flutuam sobre o jogo, que segue rodando, então
## nenhuma outra tecla (nem Enter) é do menu; todas ficam livres para o jogo.
## Com gamepad, cabe inteiro no direcional.
##
## Resultado: "anterior", "proximo", "confirmar" ou "voltar".

const ACTIONS := {
	"menu_cima": "cima", "menu_baixo": "baixo", "menu_esquerda": "esquerda", "menu_direita": "direita",
}


## direction: "cima", "baixo", "esquerda" ou "direita".
static func action(direction: String) -> String:
	match direction:
		"cima": return "anterior"
		"baixo": return "proximo"
		"esquerda": return "voltar"
		"direita": return "confirmar"
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
static func help() -> String:
	return "Cima e baixo escolhem, seta para a direita confirma e seta para a esquerda volta."
