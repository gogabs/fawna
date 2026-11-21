extends Node
## Teste do cÃ©u 3D: de dia claro, de noite escuro, laranja no entardecer,
## e o cÃ©u acompanha o relÃ³gio aos poucos.
## Rodar: godot --headless --path . res://tests/test_ceu_3d.tscn (precisa dos autoloads, por isso é cena)

var _failures := 0
var _dark := 1.0


func _ready() -> void:
	var view := WorldView3D.new()
	add_child(view)
	view.setup(WorldGen.new(42), null)
	_check(is_equal_approx(view.sky_darkness(), 1.0), "comeÃ§a de noite")
	var night_color: Color = view._env.background_color
	view.darkness_source = func() -> float: return _dark
	_dark = 0.0
	view._process(0.1)
	_check(view.sky_darkness() < 1.0 and view.sky_darkness() > 0.0, "acompanha aos poucos, sem salto")
	view._process(10.0)
	_check(is_equal_approx(view.sky_darkness(), 0.0), "chega ao dia")
	var day_color: Color = view._env.background_color
	_check(day_color.get_luminance() > night_color.get_luminance() * 4.0, "o cÃ©u de dia Ã© bem mais claro")
	_check(view._sun.light_energy > 0.9, "sol forte de dia")
	_check(view._sun.rotation_degrees.x < -55.0, "sol alto de dia")
	_dark = 0.5
	view._process(10.0)
	_check(view._sun.light_color.r > view._sun.light_color.b, "luz alaranjada no meio do caminho")
	_dark = 1.0
	view._process(10.0)
	_check(view._env.background_color.is_equal_approx(night_color), "volta ao cÃ©u da noite")
	if _failures == 0:
		print("OK: cÃ©u 3D passou")
	get_tree().quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		printerr("FALHOU: ", what)