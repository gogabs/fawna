class_name ResonanceSetup
extends RefCounted
## Configuração do Steam Audio (Nexus Resonance), usada pelo jogo
## (client/spatial_audio.gd) e pelo teste tools/diag_hrtf.gd. Fica separada
## para o teste rodar sem os autoloads do jogo.

const SCENE_CUSTOM_GODOT_PHYSICS := 3  # ResonanceRuntimeConfig.scene_type
const ATTENUATION_CURVE := 2  # ResonancePlayerConfig.attenuation_mode

## Queda do volume com a distância. O padrão do Steam Audio (1/d, 6 dB a menos
## a cada vez que a distância dobra) deixava sons longe parecendo perto: uma
## árvore caindo a 36 m soava só 10 dB abaixo de uma a 12 m. Agora, até
## KNEE_M cai como antes; dali em diante cai FAR_DB_PER_DOUBLING a cada dobro.
## Os sons do mundo subiram 6 dB (SpatialAudio.HRTF_GAIN_DB) para compensar:
## bem perto soam mais cheios, e a partir de uns 4 m já ficam mais baixos que
## antes. Música e interface não mudam. E no último trecho do alcance de cada
## fonte o som some aos poucos, em vez de cortar de repente.
const KNEE_M := 3.0
const NEAR_DB_PER_DOUBLING := 6.0
const FAR_DB_PER_DOUBLING := 15.0
const EDGE_FADE := 0.2  # fração final do alcance em que o som vai sumindo
const CURVE_POINTS := 48


static func configure_runtime(config: Resource, max_sources: int) -> void:
	config.set("direct_binaural", true)
	# Sem geometria, a cena padrão do Steam Audio fica com 0 triângulos, a
	# simulação nunca começa e todo ResonancePlayer sai mudo. A cena "Custom"
	# (raios da física do Godot) faz a simulação rodar mesmo sem geometria.
	config.set("scene_type", SCENE_CUSTOM_GODOT_PHYSICS)
	config.set("realtime_rays", 0)
	config.set("pathing_enabled", false)
	# Mesmo sem reflexões, o Steam Audio reserva e processa a cauda de reverb
	# de cada fonte com a duração daqui (padrão 2 s), na thread principal: com
	# umas 60 fontes, isso dava quadros de 150 ms (7 por segundo), e os passos
	# saíam lentos e aos trancos. Com 0,1 s o jogo volta a mais de 100 quadros.
	config.set("realtime_simulation_duration", 0.1)
	# O padrão do addon é 32 fontes; bússola, vozes, pássaros, ambiente e o
	# Caminheiro passam disso, e as fontes que ficam sem vaga saem mudas.
	config.set("max_simulation_sources", max_sources)


static func configure_player(config: Resource, min_distance: float, max_distance: float) -> void:
	config.set("reflections_enabled", false)
	config.set("simulation_occlusion_enabled", false)
	# Absorção do ar do Steam Audio: longe, o som perde um pouco do agudo
	# (uns 6 dB acima de 8 kHz a 36 m). O passa-baixa de distância do Godot
	# não vale nas fontes com HRTF (o addon desliga), então é esta que dá a
	# sensação de distância no timbre.
	config.set("air_absorption_enabled", true)
	# Reflexões desligadas: zera também a mistura delas, senão o addon avisa
	# a cada som que não recebeu parâmetros de reflexão.
	for prop in config.get_property_list():
		var prop_name: String = prop["name"]
		if prop_name.contains("reflection") and prop_name.contains("mix"):
			config.set(prop_name, 0.0)
	config.set("min_distance", min_distance)
	set_reach(config, max_distance)


## Alcance da fonte, em metros: além dele, silêncio. A curva é recalculada
## para a queda por metro ser a mesma em toda fonte, só o fim muda.
static func set_reach(config: Resource, max_distance: float) -> void:
	config.set("max_distance", max_distance)
	config.set("attenuation_curve", distance_curve(config.get("min_distance"), max_distance))
	config.set("attenuation_mode", ATTENUATION_CURVE)


## Volume (0 a 1) a "distance" metros, para uma fonte que alcança "reach".
static func distance_gain(distance: float, min_distance: float, reach: float) -> float:
	var d := maxf(distance, min_distance)
	var db := -NEAR_DB_PER_DOUBLING * log(minf(d, KNEE_M) / min_distance) / log(2.0)
	if d > KNEE_M:
		db -= FAR_DB_PER_DOUBLING * log(d / KNEE_M) / log(2.0)
	var gain := db_to_linear(db)
	var fade_start := reach * (1.0 - EDGE_FADE)
	if distance > fade_start:
		gain *= smoothstep(reach, fade_start, distance)
	return gain


## O addon lê a curva com X = (distância - mínima) / (alcance - mínima), de 0
## a 1, e Y = volume linear.
static func distance_curve(min_distance: float, reach: float) -> Curve:
	var curve := Curve.new()
	for i in CURVE_POINTS + 1:
		var x := float(i) / CURVE_POINTS
		# Mais pontos perto da fonte, onde a curva muda mais rápido.
		x = x * x
		var distance := min_distance + x * (reach - min_distance)
		curve.add_point(Vector2(x, distance_gain(distance, min_distance, reach)), 0.0, 0.0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	curve.bake_resolution = 256
	return curve


## Cria uma classe do Nexus Resonance pelo nome. Algumas são nativas
## (GDExtension) e outras são scripts com class_name, como as configs.
## Não usamos os nomes direto no código para o jogo funcionar sem o addon.
static func new_object(class_name_str: String) -> Object:
	if ClassDB.class_exists(class_name_str):
		return ClassDB.instantiate(class_name_str)
	for entry in ProjectSettings.get_global_class_list():
		if entry["class"] == class_name_str:
			return load(entry["path"]).new()
	return null
