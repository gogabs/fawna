extends Node
## Teste da descoberta de jogos na rede local: um anunciante e um buscador no
## mesmo computador. Rodar (precisa ser uma cena, para os autoloads existirem):
##   godot --headless --path . res://tests/test_lan.tscn

var _found := false


func _ready() -> void:
	var targets := LanDiscovery.broadcast_targets()
	_check(targets.has("255.255.255.255"), "difusão geral entre os destinos")
	for target in targets:
		_check(target.ends_with(".255"), "destino de difusão: " + target)

	var host := LanDiscovery.new()
	add_child(host)
	_check(host.start_announcing(), "anunciante abre a porta")
	var seeker := LanDiscovery.new()
	add_child(seeker)
	seeker.found.connect(func(address: String, port: int, who: String, version: String) -> void:
		print("achou %s:%d de %s, versão %s" % [address, port, who, version])
		_found = true)
	seeker.start_searching()
	for i in 40:
		await get_tree().create_timer(0.1).timeout
		if _found:
			break
	_check(_found, "buscador acha o anunciante")
	print("TESTE OK" if _failures == 0 else "FALHOU: %d" % _failures)
	get_tree().quit(_failures)


var _failures := 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		print("FALHA: " + what)
