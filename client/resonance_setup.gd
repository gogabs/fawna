class_name ResonanceSetup
extends RefCounted
## Configuração do Steam Audio (Nexus Resonance), usada pelo jogo
## (client/spatial_audio.gd) e pelo teste tools/diag_hrtf.gd. Fica separada
## para o teste rodar sem os autoloads do jogo.

const SCENE_CUSTOM_GODOT_PHYSICS := 3  # ResonanceRuntimeConfig.scene_type


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
	config.set("air_absorption_enabled", false)
	# Reflexões desligadas: zera também a mistura delas, senão o addon avisa
	# a cada som que não recebeu parâmetros de reflexão.
	for prop in config.get_property_list():
		var prop_name: String = prop["name"]
		if prop_name.contains("reflection") and prop_name.contains("mix"):
			config.set(prop_name, 0.0)
	config.set("min_distance", min_distance)
	config.set("max_distance", max_distance)


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
