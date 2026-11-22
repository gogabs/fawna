class_name Abilities
extends RefCounted
## As habilidades ativas das espécies (tecla H). Cada espécie tem uma só, a
## tag marcada como "active" em Species. Quem decide é o servidor (WorldState).
##
## "cooldown": espera, em segundos, entre usos; "channel": quanto a criatura
## fica parada executando; "noise": segundos de exposição que o barulho soma
## para o Calado (Horrors.hear_noise). Os valores são palpites para testar.

const DATA := {
	"salto": {"cooldown": 2.5, "distance": 3.0, "noise": 6.0},
	"uivo": {"cooldown": 60.0, "repel": 14.0},
	"disparada": {"cooldown": 40.0, "duration": 3.0, "boost": 2.0, "tired": 4.0, "tired_factor": 0.7, "noise": 10.0},
	"fucar": {"cooldown": 180.0, "channel": 5.0, "noise": 8.0, "find_chance": 0.75, "retry": 600.0},
	"arar": {"cooldown": 0.0, "channel": 5.0, "noise": 8.0},
	"pesca": {"cooldown": 0.0},
	# Garras (J de mãos livres): sem espera de habilidade, só o ritmo de um
	# golpe de machado (Game.SWING_COOLDOWN).
	"garras": {"cooldown": 0.0, "swing": 0.45},
}

## Ao fuçar: o que se acha e as quantidades.
const DIG_FINDS := [["argila", 1, 2, 0.45], ["silex", 1, 1, 0.3], ["raiz", 1, 3, 0.25]]
const CHANNEL_MOVE_LIMIT := 0.6  # andar mais que isso cancela o que se faz parado


static func data(tag: String) -> Dictionary:
	return DATA.get(tag, {})


## "3 min de espera", "5 s parado", etc., para o menu de personagem.
static func summary(tag: String) -> String:
	var info := data(tag)
	var parts := PackedStringArray()
	if float(info.get("channel", 0.0)) > 0.0:
		parts.append("fica %d s parado" % roundi(float(info["channel"])))
	if float(info.get("cooldown", 0.0)) > 0.0:
		var wait := float(info["cooldown"])
		parts.append("espera de %s entre usos" % ("%d min" % roundi(wait / 60.0) if wait >= 60.0 else ("%s s" % str(snappedf(wait, 0.5)).trim_suffix(".0").replace(".", ","))))
	return ", ".join(parts)
