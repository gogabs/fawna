extends SceneTree
## Conta quantos recursos cabem num raio (casas) ao redor de pontos de cada bioma.
##   godot --headless --path . --script res://tools/contar_recursos.gd -- 24

const NAMES := {
	WorldGen.Thing.BAMBU: "Bambu", WorldGen.Thing.ARBUSTO: "Lenha(arbusto)", WorldGen.Thing.ARVORE: "Madeira(árvore)",
	WorldGen.Thing.PEDRAS: "Pedras", WorldGen.Thing.ARGILA: "Argila", WorldGen.Thing.ARBUSTO_FRUTAS: "Frutas",
	WorldGen.Thing.CIPO: "Cipó", WorldGen.Thing.FIBRA: "Fibra", WorldGen.Thing.SILEX: "Sílex", WorldGen.Thing.GALHOS: "Galhos",
}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var radius := int(args[0]) if args.size() > 0 else 24
	var samples := {}  # bioma -> lista de {thing: count}
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for seed_value in [42, 173, 9001]:
		var world := WorldGen.new(seed_value)
		var tries := 0
		var per_biome := {}
		while tries < 4000:
			tries += 1
			var cell := Vector2i(rng.randi_range(-400, 400), rng.randi_range(-400, 400))
			var biome := world.biome_at(cell)
			if biome == WorldGen.Biome.MAR or per_biome.get(biome, 0) >= 25:
				continue
			if not world.is_free(WorldGen.cell_center(cell)):
				continue
			per_biome[biome] = per_biome.get(biome, 0) + 1
			var counts := {}
			for dy in range(-radius, radius + 1):
				for dx in range(-radius, radius + 1):
					if dx * dx + dy * dy > radius * radius:
						continue
					var t := world.thing_at(cell + Vector2i(dx, dy))
					if NAMES.has(t):
						counts[t] = counts.get(t, 0) + 1
			if not samples.has(biome):
				samples[biome] = []
			samples[biome].append(counts)
	print("raio = %d casas (%.0f m)" % [radius, radius * 1.5])
	for biome in samples:
		var list: Array = samples[biome]
		var line := "%s (%d pontos):" % [WorldGen.Biome.keys()[biome], list.size()]
		var total_types := 0.0
		var total_all := 0.0
		for thing in NAMES:
			var values := []
			for c in list:
				values.append(c.get(thing, 0))
			values.sort()
			var mean := 0.0
			for v in values:
				mean += v
			mean /= values.size()
			total_all += mean
			var present := 0
			for v in values:
				if v > 0:
					present += 1
			total_types += float(present) / values.size()
			if mean > 0:
				line += "\n   %-16s média %6.1f  mediana %4d  máx %4d  presente em %3d%%" % [NAMES[thing], mean, values[values.size() / 2], values[-1], 100 * present / values.size()]
		line += "\n   -> tipos presentes em média: %.1f de 9; total de coletáveis: %.0f" % [total_types, total_all]
		print(line)
	quit()
