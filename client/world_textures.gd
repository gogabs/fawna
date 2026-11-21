class_name WorldTextures
extends RefCounted
## Texturas do mundo em 3D, geradas por código (ruído que se repete sem emenda),
## em tons de cinza: elas só dão relevo e a cor continua vindo do bioma, das
## cores nos vértices e de cada peça. Pequenas (SIZE pixels de lado, com
## mipmaps), então quase não pesam na memória nem no download.

const SIZE := 128

## Quanto cada textura escurece no máximo (1 = nada): o relevo aparece sem
## apagar a cor do bioma.
const GROUND_FLOOR := 0.62
const BARK_FLOOR := 0.35
const LEAF_FLOOR := 0.55
const STONE_FLOOR := 0.5


static func make_all() -> Dictionary:
	return {
		"ground": ground(),
		"bark": bark(),
		"leaf": leaf(),
		"stone": stone(),
	}


## Terra e grama: manchas largas com um pontilhado fino por cima.
static func ground() -> ImageTexture:
	var coarse := _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.035, 3, 11).get_seamless_image(SIZE, SIZE)
	var fine := _noise(FastNoiseLite.TYPE_PERLIN, 0.35, 2, 12).get_seamless_image(SIZE, SIZE)
	return _combine(coarse, fine, 0.7, GROUND_FLOOR)


## Casca: veios que correm no sentido do comprimento (o V da malha).
static func bark() -> ImageTexture:
	var strip := _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.12, 3, 21).get_seamless_image(SIZE, 6)
	strip.resize(SIZE, SIZE, Image.INTERPOLATE_BILINEAR)
	var grain := _noise(FastNoiseLite.TYPE_PERLIN, 0.4, 1, 22).get_seamless_image(SIZE, SIZE)
	return _combine(strip, grain, 0.75, BARK_FLOOR)


## Folhagem: tufos arredondados, de células.
static func leaf() -> ImageTexture:
	var cells := _noise(FastNoiseLite.TYPE_CELLULAR, 0.06, 1, 31)
	cells.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	var blobs := cells.get_seamless_image(SIZE, SIZE)
	var fine := _noise(FastNoiseLite.TYPE_PERLIN, 0.3, 2, 32).get_seamless_image(SIZE, SIZE)
	return _combine(blobs, fine, 0.7, LEAF_FLOOR)


## Pedra: manchas com rachaduras finas.
static func stone() -> ImageTexture:
	var blotch := _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.05, 4, 41).get_seamless_image(SIZE, SIZE)
	var cracks_noise := _noise(FastNoiseLite.TYPE_CELLULAR, 0.07, 1, 42)
	cracks_noise.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	var cracks := cracks_noise.get_seamless_image(SIZE, SIZE)
	return _combine(blotch, cracks, 0.65, STONE_FLOOR)


static func _noise(kind: int, frequency: float, octaves: int, noise_seed: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.noise_type = kind
	noise.frequency = frequency
	noise.seed = noise_seed
	if octaves > 1:
		noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		noise.fractal_octaves = octaves
	else:
		noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	return noise


## Mistura duas imagens de ruído (peso "weight" na primeira) e põe o resultado
## entre "floor_value" e 1, como textura em tons de cinza com mipmaps.
static func _combine(a: Image, b: Image, weight: float, floor_value: float) -> ImageTexture:
	a.convert(Image.FORMAT_L8)
	b.convert(Image.FORMAT_L8)
	var out := Image.create(SIZE, SIZE, true, Image.FORMAT_L8)
	for y in SIZE:
		for x in SIZE:
			var v := a.get_pixel(x, y).r * weight + b.get_pixel(x, y).r * (1.0 - weight)
			var g := lerpf(floor_value, 1.0, clampf(v, 0.0, 1.0))
			out.set_pixel(x, y, Color(g, g, g))
	out.generate_mipmaps()
	return ImageTexture.create_from_image(out)
