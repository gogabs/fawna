class_name DebugTools
extends RefCounted
## Ferramentas de depuração, para testar sem sofrer (menu "Depuração", no menu
## das setas): dar recursos, esvaziar a bolsa, subir o limite de carga,
## teleportar e controlar o Calado.
##
## Só existem em testes. Quem decide é o servidor (ver allowed): o jogo normal
## não mostra o menu nem aceita os pedidos.
##   - servidor dedicado: só com --debug na linha de comando (qualquer jogador
##     que entrar nele usa; é para um servidor de testes, em outra porta);
##   - jogo hospedado pelo menu (Hospedar jogo privado) ou --host: só quem
##     hospeda usa, mesmo com convidados no mundo.

## Carga com o limite alto: cabe praticamente tudo.
const HIGH_CAPACITY := 1000

## Pacotes de recursos, na ordem do menu: chave -> [rótulo, itens].
const KIT_ORDER := ["materiais", "raros", "comida", "ferramentas", "tudo"]
const KITS := {
	"materiais": ["Materiais de obra", {
		"madeira_grande": 10, "madeira_media": 10, "madeira_pequena": 10,
		"pedra_grande": 6, "pedra_media": 6, "pedra_pequena": 6,
		"bambu": 10, "argila": 10,
	}],
	"raros": ["Raros: sílex, cipó, fibra e resina", {"silex": 10, "cipo": 10, "fibra": 10, "resina": 10}],
	"comida": ["Frutas e raízes", {"frutas_amora": 10, "frutas_pitanga": 10, "raiz_batata": 5, "raiz_mandioca": 5, "raiz_cara": 5, "raiz_cenoura": 5, "cogumelo_pardo": 5, "milho": 5}],
	"ferramentas": ["Ferramentas e armas", {"faca": 1, "enxada": 1, "lanca": 1, "clava": 1, "tocha": 1, "pote": 1, "pote_selado": 1, "manto": 1}],
}

## Distância dos saltos para os pontos cardeais, em casas.
const JUMP := 40.0


## Pode este jogador usar a depuração? "available": o servidor liga a
## depuração (--debug ou jogo hospedado); "hosting": é um jogo hospedado, onde
## só o anfitrião (peer 1) usa.
static func allowed(available: bool, hosting: bool, id: int) -> bool:
	return available and (not hosting or id == 1)


## Os itens de um pacote ("tudo" soma todos).
static func kit_items(kit: String) -> Dictionary:
	if kit == "tudo":
		var all := {}
		for key: String in KIT_ORDER:
			if key != "tudo":
				add_items(all, kit_items(key))
		return all
	if not KITS.has(kit):
		return {}
	return (KITS[kit][1] as Dictionary).duplicate()


static func kit_label(kit: String) -> String:
	return "Tudo, de todos os pacotes" if kit == "tudo" else str(KITS[kit][0])


static func add_items(bag: Dictionary, items: Dictionary) -> void:
	for item: String in items:
		bag[item] = int(bag.get(item, 0)) + int(items[item])


## Põe os itens na bolsa sem olhar a carga (o limite alto é uma opção à parte).
static func give(bag: Dictionary, kit: String) -> Dictionary:
	var items := kit_items(kit)
	add_items(bag, items)
	return items


## Esvazia a bolsa, deixando só o que toda criatura leva (o machado, se não
## está nas mãos).
static func empty_bag(bag: Dictionary, wielded: String) -> void:
	bag.clear()
	Bag.give_starter(bag, wielded)


## "x,y" (em casas) -> Vector2, ou null se não for um ponto válido. Aceita
## ";" no lugar da vírgula (os comandos --auto dos testes já usam vírgula).
static func parse_point(text: String) -> Variant:
	var parts := text.replace(";", ",").split(",")
	if parts.size() != 2 or not parts[0].strip_edges().is_valid_float() or not parts[1].strip_edges().is_valid_float():
		return null
	var point := Vector2(float(parts[0]), float(parts[1]))
	return point if point.is_finite() and absf(point.x) < 1.0e6 and absf(point.y) < 1.0e6 else null


## Um ponto livre perto de "point", mesmo que o ponto caia num lago, no mar ou
## dentro de uma construção. Procura em anéis cada vez mais largos; sem achar,
## a Origem.
static func free_spot(world: WorldGen, point: Vector2, blocked: Array = []) -> Vector2:
	for radius in range(0, 31, 3):
		for i in (1 if radius == 0 else 8):
			var try: Vector2 = point + Vector2.from_angle(TAU * i / 8.0) * radius
			var spot := world.nearest_free(try)
			if world.is_free(spot) and not blocked.has(WorldGen.cell_of(spot)):
				return spot
	return WorldGen.center_point()
