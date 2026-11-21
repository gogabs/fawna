extends SceneTree
## Testes das ferramentas de depuração: quem pode usar, pacotes de recursos,
## limite de carga, teleporte para um ponto livre e controle do Calado.
## Rodar: godot --headless --path . --script res://tests/test_debug.gd

var _failures := 0


func _init() -> void:
	_test_allowed()
	_test_kits()
	_test_capacity()
	_test_point_and_spot()
	_test_horror_controls()
	if _failures == 0:
		print("OK: depuração passou")
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FALHOU: " + message)


func _test_allowed() -> void:
	_check(not DebugTools.allowed(false, false, 5), "servidor sem --debug não deveria aceitar")
	_check(not DebugTools.allowed(false, true, 1), "jogo hospedado sem depuração ligada não deveria aceitar")
	_check(DebugTools.allowed(true, false, 5), "servidor de testes aceita qualquer jogador")
	_check(DebugTools.allowed(true, true, 1), "o anfitrião usa a depuração")
	_check(not DebugTools.allowed(true, true, 7), "convidado de jogo hospedado não usa a depuração")


func _test_kits() -> void:
	for kit: String in DebugTools.KIT_ORDER:
		_check(not DebugTools.kit_items(kit).is_empty(), "pacote %s não deveria ser vazio" % kit)
		_check(not DebugTools.kit_label(kit).is_empty(), "pacote %s sem rótulo" % kit)
		for item: String in DebugTools.kit_items(kit):
			_check(Economy.is_item(item) or Bag.WEIGHTS.has(item), "item desconhecido no pacote %s: %s" % [kit, item])
	_check(DebugTools.kit_items("nada").is_empty(), "pacote desconhecido deveria vir vazio")
	var all := DebugTools.kit_items("tudo")
	_check(all.has("pedra_grande") and all.has("silex") and all.has("frutas") and all.has("tocha"), "\"tudo\" deveria somar os pacotes")
	var bag := {"bambu": 2}
	DebugTools.give(bag, "materiais")
	_check(int(bag["bambu"]) == 12, "dar recursos soma ao que já tem (%s)" % str(bag))
	DebugTools.empty_bag(bag, "")
	_check(bag == {"machado": 1}, "esvaziar deixa só o machado (%s)" % str(bag))
	DebugTools.empty_bag(bag, "machado")
	_check(bag.is_empty(), "com o machado nas mãos, a bolsa fica vazia (%s)" % str(bag))


func _test_capacity() -> void:
	var bag := {}
	DebugTools.give(bag, "tudo")
	_check(Bag.load_of(bag) > Bag.CAPACITY, "o pacote tudo passa do limite normal")
	_check(Bag.free_space(bag) == 0, "no limite normal, não cabe mais nada")
	Bag.apply_limit(DebugTools.HIGH_CAPACITY)
	_check(Bag.free_space(bag) > 0, "com o limite alto, ainda cabe")
	_check(Bag.load_label(bag).ends_with("de %d" % DebugTools.HIGH_CAPACITY), "o rótulo mostra o limite novo")
	var split := Bag.split_to_fit({}, "", {"pedra_grande": 50}, "")
	_check(split[1].is_empty(), "com o limite alto, 50 pedras grandes cabem")
	_check(Bag.speed_factor(bag) == 1.0, "com o limite alto, não anda mais devagar")
	Bag.apply_limit(Bag.CAPACITY)
	_check(Bag.free_space({}) == Bag.MAX_LOAD and Bag.capacity == Bag.CAPACITY, "voltar ao normal")


func _test_point_and_spot() -> void:
	_check(DebugTools.parse_point("12.5,-3") == Vector2(12.5, -3), "ponto válido")
	_check(DebugTools.parse_point("abc") == null and DebugTools.parse_point("1,2,3") == null, "ponto inválido")
	_check(DebugTools.parse_point("nan,1") == null and DebugTools.parse_point("1e30,1") == null, "ponto absurdo")
	var world := WorldGen.new(42)
	for point: Vector2 in [Vector2(40, 40), Vector2(-300, 200), Vector2(1000, -1000), WorldGen.center_point()]:
		var spot := DebugTools.free_spot(world, point)
		_check(world.is_free(spot), "o teleporte deveria cair num ponto livre perto de %s (caiu em %s)" % [point, spot])


func _test_horror_controls() -> void:
	var world := WorldGen.new(42)
	var horrors := Horrors.new(world)
	var players := {1: {"pos": WorldGen.center_point() + Vector2(60, 60), "heading": 0}}
	_check(horrors.summon(1, players, 12.0) >= 0, "chamar o Calado")
	_check(horrors.summon(1, players, 12.0) < 0, "já há um atrás dele")
	var out := horrors.dismiss_all(1000)
	_check(horrors.horrors.is_empty(), "dispensar todos")
	_check(horrors.summon(1, players, 12.0) >= 0, "depois de dispensar, dá para chamar de novo na hora (sem sossego)")
	horrors.dismiss_all(2000)
	horrors.spawning = false
	var now := 0
	for i in 4000:
		now += 250
		horrors.hear_noise(1, 5.0)
		horrors.update(now, players, [])
	_check(horrors.horrors.is_empty(), "com as aparições desligadas, ele não vem sozinho")
	_check(out is Array, "dismiss_all devolve mensagens")
