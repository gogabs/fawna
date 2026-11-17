extends SceneTree
## Mostra, em texto, como ficam os biomas de uma semente: um mapa de letras
## (uma por região, a Origem no meio) e a proporção de cada bioma.
## Rodar: godot --headless --path . --script res://tools/mapa_biomas.gd -- 42 20
## (semente e quantas regiões para cada lado; padrão 42 e 16).

const LETTERS := {
	WorldGen.Biome.BOSQUE: "B", WorldGen.Biome.PRADARIA: ".", WorldGen.Biome.LAGOA: "o",
	WorldGen.Biome.MAR: "~", WorldGen.Biome.FLORESTA_GELADA: "F", WorldGen.Biome.DESERTO_GELADO: "_",
	WorldGen.Biome.BAMBUZAL: "|", WorldGen.Biome.BREJO: "%",
}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var world_seed := int(args[0]) if args.size() > 0 else 42
	var reach := int(args[1]) if args.size() > 1 else 16
	var world := WorldGen.new(world_seed)
	var count := {}
	var same := 0
	var pairs := 0
	var clearings := 0
	print("Semente %d. B bosque, c clareira, | bambuzal, . pradaria, o lagoa, %% brejo, F floresta gelada, _ deserto gelado, ~ mar, @ Origem" % world_seed)
	for y in range(-reach, reach + 1):
		var row := ""
		for x in range(-reach, reach + 1):
			var region := Vector2i(x, y)
			var biome := world.region_biome(region)
			count[biome] = int(count.get(biome, 0)) + 1
			var letter: String = LETTERS[biome]
			if world.region_feature(region) == WorldGen.Feature.CLAREIRA:
				letter = "c"
				clearings += 1
			row += "@" if region == Vector2i.ZERO else letter
			for next: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
				pairs += 1
				if world.region_biome(region + next) == biome:
					same += 1
		print(row)
	var total := (reach * 2 + 1) * (reach * 2 + 1)
	for biome in count:
		print("%s: %.1f%%" % [WorldGen.BIOME_NAMES[biome], 100.0 * count[biome] / total])
	print("clareiras: %.1f%% das regiões" % (100.0 * clearings / total))
	print("vizinhas com o mesmo bioma: %.1f%%" % (100.0 * same / pairs))
	quit()
