class_name HearingMuffle
extends Node
## O custo da audição apurada (Species): quem ouve muito bem fica com o mundo
## abafado depois de um som alto. Cada som soma segundos de abafamento (ver
## Loudness) e o filtro do volume geral fecha aos poucos, abrindo de novo
## com o silêncio. Só atua para quem tem a tag.

const OPEN_HZ := 20500.0
const CLOSED_HZ := 900.0
## O máximo de abafamento acumulado, em segundos, e quanto dele é "totalmente
## abafado" (CLOSED_HZ).
const MAX_SECONDS := 4.0
const FULL_SECONDS := 2.0

var left := 0.0  # segundos de abafamento que ainda restam
var _filter: AudioEffectLowPassFilter


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_filter = AudioEffectLowPassFilter.new()
	_filter.cutoff_hz = OPEN_HZ
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Master"), _filter)


func _exit_tree() -> void:
	if _filter == null:
		return
	var master := AudioServer.get_bus_index("Master")
	for i in AudioServer.get_bus_effect_count(master):
		if AudioServer.get_bus_effect(master, i) == _filter:
			AudioServer.remove_bus_effect(master, i)
			break
	_filter = null


## Ouviu um som (nome em Loudness.SOUNDS).
func hear(sound: String) -> void:
	left = minf(MAX_SECONDS, left + Loudness.muffle_seconds(sound))


func clear() -> void:
	left = 0.0
	_apply()


func _process(delta: float) -> void:
	if left > 0.0:
		left = maxf(0.0, left - delta)
		_apply()


## 0 (nada) a 1 (totalmente abafado).
func amount() -> float:
	return clampf(left / FULL_SECONDS, 0.0, 1.0)


## A frequência de corte para uma quantidade de abafamento (cai em curva, que
## é como o ouvido sente: a primeira metade já tira o brilho).
static func cutoff_for(muffled: float) -> float:
	return OPEN_HZ * pow(CLOSED_HZ / OPEN_HZ, clampf(muffled, 0.0, 1.0))


func _apply() -> void:
	if _filter != null:
		_filter.cutoff_hz = cutoff_for(amount())
