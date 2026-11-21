extends SceneTree
## Desenha a água de uma semente num PNG: um pixel por "passo" casas.
## Rodar: godot --headless --path . --script res://tools/mapa_agua.gd -- 42 20 saida.png
## (semente, regiões para cada lado e arquivo de saída; padrão 42, 20 e agua.png).

const STEP := 2


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var world_seed := int(args[0]) if args.size() > 0 else 42
	var reach := int(args[1]) if args.size() > 1 else 20
	var path: String = args[2] if args.size() > 2 else "agua.png"
	var world := WorldGen.new(world_seed)
	var half := reach * WorldGen.REGION_SIZE
	var side := half * 2 / STEP
	var image := Image.create(side, side, false, Image.FORMAT_RGB8)
	for py in side:
		for px in side:
			var cell := Vector2i(px * STEP - half, py * STEP - half)
			var color := Color("c8d8a8")
			match world.biome_at(cell):
				WorldGen.Biome.BOSQUE: color = Color("5f8f4f")
				WorldGen.Biome.BAMBUZAL: color = Color("7fa84f")
				WorldGen.Biome.FLORESTA_GELADA: color = Color("a8c8c0")
				WorldGen.Biome.DESERTO_GELADO: color = Color("e0e8e8")
				WorldGen.Biome.BREJO: color = Color("7a8f5f")
				WorldGen.Biome.MONTANHA: color = Color("8a8078")
				WorldGen.Biome.PRADARIA: color = Color("c8d8a8")
				WorldGen.Biome.LAGOA: color = Color("c8d8a8")
				WorldGen.Biome.MAR: color = Color("a0b8e0")
			match world.thing_at(cell):
				WorldGen.Thing.MAR: color = Color("3050a0")
				WorldGen.Thing.LAGO: color = Color("1f4fd0")
				WorldGen.Thing.CHARCO: color = Color("5a8fc0")
				WorldGen.Thing.RIACHO: color = Color("0a1fff")
				WorldGen.Thing.TRILHA: color = Color("a07040")
			image.set_pixel(px, py, color)
	image.save_png(path)
	print("salvo ", path)
	quit()
