# Тесты персонажа «Фонарщика» (шаг 5 П4.5, раздел 16): палитра по хэшу id
# (одинаковый id — один набор, все шесть достижимы и точно из ТЗ),
# set_glow_level клампится в 0..1, материал тела — «леденец» без
# прозрачности, у фонарика есть маленький источник света из balance.
extends GutTest

const PAL: Palette = preload("res://assets/palette.tres")
const B: Balance = preload("res://gameplay/balance.tres")

## Шесть палитр из ТЗ раздела 16: тело / капюшон-накидка / фонарик.
const SPEC_BODY: PackedStringArray = [
	"f4a987", "8fd6c0", "b48acf", "f3dc6b", "7fa8e8", "d9a066",
]
const SPEC_HOOD: PackedStringArray = [
	"6b4e9b", "2f5d73", "f2c14e", "3f7f5a", "e86f6f", "2e3a59",
]
const SPEC_LIGHT: PackedStringArray = [
	"ffd27a", "ffe9a8", "fff1c2", "ffb86b", "ffe3a3", "ffd9a0",
]


func _make_visual() -> PlayerVisual:
	var visual := PlayerVisual.new()
	add_child_autofree(visual)
	return visual


func test_same_id_gets_same_palette() -> void:
	# Хэш id: одинаковый id — одинаковый набор цветов у всех участников
	# (без передачи по сети), в том числе у двух разных экземпляров модели.
	var first := _make_visual()
	var second := _make_visual()
	var id := 1234567
	first.setup_palette(id)
	second.setup_palette(id)
	var index: int = PlayerVisual.palette_index(id)
	var material_a: StandardMaterial3D = first.body_material()
	var material_b: StandardMaterial3D = second.body_material()
	assert_eq(material_a.albedo_color, PAL.lantern_body[index], "тело — цвет палитры")
	assert_eq(
		material_a.albedo_color, material_b.albedo_color,
		"два экземпляра: цвет тела одинаков",
	)
	var light_a: OmniLight3D = first.find_children("*", "OmniLight3D", true, false)[0]
	var light_b: OmniLight3D = second.find_children("*", "OmniLight3D", true, false)[0]
	assert_eq(light_a.light_color, light_b.light_color, "цвет фонарика одинаков")
	assert_eq(
		light_a.light_color, PAL.lantern_light[index],
		"фонарик — цвет палитры",
	)


func test_all_six_palettes_reachable() -> void:
	# Палитр шесть, и каждая достижима: соседние id дают разные наборы,
	# а полный обход покрывает все шесть (в т.ч. отрицательный id — abs).
	var seen: Array[Color] = []
	for id: int in 6:
		var index: int = PlayerVisual.palette_index(id)
		assert_between(index, 0, 5, "индекс палитры в диапазоне")
		var visual := _make_visual()
		visual.setup_palette(id)
		var color: Color = visual.body_material().albedo_color
		assert_false(
			color in seen, "палитра %d раньше не встречалась" % id,
		)
		seen.append(color)
	assert_eq(seen.size(), 6, "шесть разных наборов")
	assert_eq(
		PlayerVisual.palette_index(-7),
		PlayerVisual.palette_index(7),
		"отрицательный id — та же палитра (abs)",
	)


func test_palette_colors_match_spec() -> void:
	# Точные цвета ТЗ (раздел 16): Персик, Мята, Слива, Лимон, Голубика,
	# Карамель — регресс на случайную правку палитр.
	assert_eq(PAL.lantern_body.size(), 6, "шесть цветов тела")
	assert_eq(PAL.lantern_hood.size(), 6, "шесть цветов капюшона/накидки")
	assert_eq(PAL.lantern_light.size(), 6, "шесть цветов фонарика")
	for i: int in 6:
		assert_eq(
			PAL.lantern_body[i], Color(SPEC_BODY[i]),
			"тело %d = #%s" % [i, SPEC_BODY[i]],
		)
		assert_eq(
			PAL.lantern_hood[i], Color(SPEC_HOOD[i]),
			"капюшон %d = #%s" % [i, SPEC_HOOD[i]],
		)
		assert_eq(
			PAL.lantern_light[i], Color(SPEC_LIGHT[i]),
			"фонарик %d = #%s" % [i, SPEC_LIGHT[i]],
		)


func test_glow_level_is_clamped() -> void:
	# set_glow_level — публичная точка для П5 («взяться за руки», костёр):
	# значения клампятся в 0..1, дробные внутри диапазона — как есть.
	var visual := _make_visual()
	visual.set_glow_level(-3.0)
	assert_almost_eq(visual.glow_level(), 0.0, 0.0001, "ниже нуля → 0")
	visual.set_glow_level(2.5)
	assert_almost_eq(visual.glow_level(), 1.0, 0.0001, "выше единицы → 1")
	visual.set_glow_level(0.4)
	assert_almost_eq(visual.glow_level(), 0.4, 0.0001, "внутри диапазона — как есть")


func test_body_material_is_opaque_candy() -> void:
	# «Леденец»: непрозрачный (без альфы — тело «сочное», не желейное),
	# с subsurface scattering, глянец около 0.45. Rim не используется:
	# compatibility-рендерер заливает им материал белым (шаг 5 П4.5).
	var material: StandardMaterial3D = _make_visual().body_material()
	assert_not_null(material, "материал тела есть")
	assert_eq(
		material.transparency, BaseMaterial3D.TRANSPARENCY_DISABLED,
		"материал тела непрозрачен",
	)
	assert_almost_eq(material.albedo_color.a, 1.0, 0.001, "альфа = 1")
	assert_false(material.rim_enabled, "rim выключен (белит на compat)")
	assert_true(
		material.subsurf_scatter_enabled,
		"subsurface scattering включён",
	)
	assert_between(material.roughness, 0.35, 0.55, "глянец около 0.45")


func test_lantern_has_small_light() -> void:
	# Фонарик-сердечко — маленький источник света радиусом из balance
	# (раздел 16: ~3 м), тёплого цвета палитры, без теней (перф).
	var visual := _make_visual()
	visual.setup_palette(2)
	var lights: Array = visual.find_children("*", "OmniLight3D", true, false)
	assert_eq(lights.size(), 1, "у фонарика ровно один источник света")
	var light: OmniLight3D = lights[0]
	assert_almost_eq(
		light.omni_range, B.lantern_light_radius, 0.001,
		"радиус света из balance",
	)
	assert_eq(light.light_color, PAL.lantern_light[2], "цвет — палитра фонарика")
	assert_false(light.shadow_enabled, "без теней")
