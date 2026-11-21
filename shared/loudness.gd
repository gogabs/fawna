class_name Loudness
extends RefCounted
## Quão alto é cada som, para o abafamento gradual de quem tem audição
## apurada (Species): todo som abafa um pouco o mundo, e o quanto depende do
## volume. NONE não abafa nada (passos, pássaros). Ainda só dados: ligar ao
## jogo e ao áudio fica para outro PR. Um som novo entra aqui com o seu nível.

const NONE := 0
const LOW := 1
const MEDIUM := 2
const HIGH := 3

const SOUNDS := {
	"passos": NONE,
	"passaros": NONE,
	"obra": LOW,
	"coleta": LOW,
	"machadada": MEDIUM,
	"enxada": MEDIUM,
	"uivo": HIGH,
	"arvore_caindo": HIGH,
}

## Quanto o mundo abafa, em segundos, para cada nível (valores provisórios).
const MUFFLE_SECONDS := [0.0, 0.4, 1.0, 2.0]


static func level_of(sound: String) -> int:
	return int(SOUNDS.get(sound, NONE))


## Segundos de abafamento que o som causa em quem tem audição apurada.
static func muffle_seconds(sound: String) -> float:
	return MUFFLE_SECONDS[level_of(sound)]
