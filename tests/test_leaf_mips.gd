# Тесты П17 п.1 «Листва без таяния»: текстуры листвы — запечённые
# ImageTexture с мипами, сохраняющими плотность выреза (tools/make_leaf_mips.gd):
# условная плотность (доля пикселей с альфой ≥ порога среди «активных» —
# footprint’ов карточек листвы, где у уровня 0 есть альфа) на мипах
# не проваливается ниже 0.85 × уровня 0; ресурс подключён в EzTreeMeshes;
# alpha-to-coverage включается только на ULTRA (MSAA), на HIGH — 0.
extends GutTest

## Вид листвы → пороги вырезки alphaTest пресетов ez-tree (manifest.json).
const CUTS: Dictionary = {
	"pine": [0.3, 0.5],
	"oak": [0.5],
	"aspen": [0.5],
	"ash": [0.5],
}
## Мип, на котором план требует сохранить плотность (128 × 128 от 1024):
## деревья переключаются на импосторы за ~90 м — глубже мипы не сэмплятся.
const CHECK_MIP: int = 3
const KEEP: float = 0.85


func _tex(kind: String) -> ImageTexture:
	return load("res://assets/visual/trees/leaves/%s_mips.res" % kind) \
		as ImageTexture


## Выборка отдельного мипа из изображения (RGBA8 без паддинга строк).
func _mip_bytes(image: Image, mip: int) -> PackedByteArray:
	var width := image.get_width() >> mip
	var height := image.get_height() >> mip
	return image.get_data().slice(
		image.get_mipmap_offset(mip),
		image.get_mipmap_offset(mip) + width * height * 4)


func _mip_size(image: Image, mip: int) -> int:
	return (image.get_width() >> mip) * (image.get_height() >> mip)


## Условная плотность мипа: доля активных пикселей с альфой ≥ порога.
## Активная область каждого мипа — footprint уровня 0 с альфой (OR 2×2
## при спуске на уровень, как в тулe).
func _density(
	image: Image, mip: int, cut: float, mask: PackedByteArray
) -> float:
	var data := _mip_bytes(image, mip)
	var count := 0
	var active := 0
	for px: int in data.size() / 4:
		if mask[px] > 0:
			active += 1
			if data[px * 4 + 3] / 255.0 >= cut:
				count += 1
	if active == 0:
		return 0.0
	return float(count) / float(active)


## Активная маска мипа: спуск маски уровня 0 (альфа > 0) OR-ом 2×2.
## База — байты только уровня 0: get_data() у изображения с мипами
## возвращает всю цепочку, и маска выходила за границы.
func _mask_at(image: Image, mip: int) -> PackedByteArray:
	var width := image.get_width()
	var height := image.get_height()
	var data := _mip_bytes(image, 0)
	var mask := PackedByteArray()
	mask.resize(width * height)
	var px := 0
	var i := 3
	while i < data.size():
		mask[px] = 1 if data[i] > 0 else 0
		i += 4
		px += 1
	for _level: int in mip:
		var next := PackedByteArray()
		next.resize(maxi(1, (width >> 1) * (height >> 1)))
		if (width >> 1) * (height >> 1) != width * height / 4:
			push_error("тест поддерживает квадратные степени двойки")
			return next
		var src := 0
		var dst := 0
		for _y: int in height >> 1:
			for _x: int in width >> 1:
				var or_sum: int = mask[src] + mask[src + 1] \
					+ mask[src + width] + mask[src + width + 1]
				# Тернарник обязан быть одной строкой: разрыв условия
				# переносом ломает парсер, и тест молча выпадал из GUT.
				next[dst] = 1 if or_sum > 0 else 0
				src += 2
				dst += 1
			src += width
		mask = next
		width >>= 1
		height >>= 1
	return mask


func test_mips_preserve_cut_density() -> void:
	# Т1 плана: плотность выреза на мипе 3 ≥ 0.85 × уровня 0 по каждому
	# порогу вида — крона вдали той же густоты, «таяния» нет.
	for kind: String in CUTS:
		var texture := _tex(kind)
		assert_not_null(texture, "%s: ресурс с мипами запечён" % kind)
		var image := texture.get_image()
		assert_gt(
			image.get_mipmap_count(), CHECK_MIP,
			"%s: мипов больше %d" % [kind, CHECK_MIP])
		for cut: float in CUTS[kind]:
			var base := _density(image, 0, cut, _mask_at(image, 0))
			assert_gt(
				base, 0.1, "%s: плотность карточек уровня 0 не пустая" % kind)
			var far := _density(
				image, CHECK_MIP, cut, _mask_at(image, CHECK_MIP))
			assert_gte(
				far, KEEP * base,
				"%s (порог %.1f): плотность мипа %d %.3f ≥ %.2f×%.3f" % [
					kind, cut, CHECK_MIP, far, KEEP, base])


func test_canopy_material_uses_baked_mips() -> void:
	# Материал листвы берёт текстуру из .res (мипы с сохранением плотности
	# внутри ресурса), а не импорт движка над исходным PNG.
	for type: String in ["etree_pine", "etree_oak", "etree_aspen"]:
		var set: Dictionary = EzTreeMeshes.build_set(StringName(type), 0)
		var mesh: ArrayMesh = set["mesh"]
		var material := mesh.surface_get_material(
			mesh.get_surface_count() - 1) as ShaderMaterial
		var texture: Texture2D = material.get_shader_parameter("leaf_tex")
		assert_not_null(texture, "%s: у материала есть текстура листвы" % type)
		var image := (texture as ImageTexture).get_image()
		assert_gt(
			image.get_mipmap_count(), 1,
			"%s: текстура листвы с мипами (запечённый .res)" % type)


func test_a2c_edge_only_on_ultra() -> void:
	# Решение владельца: alpha-to-coverage листвы — только на ULTRA
	# (MSAA 4x), на HIGH (SMAA без MSAA) — 0, остаётся scissor + мипы.
	assert_almost_eq(
		GraphicsQuality.canopy_a2c_edge(GraphicsQuality.Tier.ULTRA),
		GraphicsQuality.CANOPY_A2C_EDGE, 0.001,
		"ULTRA: край A2C включён")
	for tier: int in [
		GraphicsQuality.Tier.SIMPLE,
		GraphicsQuality.Tier.NORMAL,
		GraphicsQuality.Tier.HIGH,
	]:
		assert_almost_eq(
			GraphicsQuality.canopy_a2c_edge(tier), 0.0, 0.001,
			"уровень %d без MSAA: A2C выключен" % tier)
	# Шейдер выводит край в ALPHA_ANTIALIASING_EDGE из uniform a2c_edge.
	assert_true(
		EzTreeMeshes.CANOPY_SHADER.code.contains("ALPHA_ANTIALIASING_EDGE"),
		"canopy.gdshader пишет ALPHA_ANTIALIASING_EDGE")
	assert_true(
		EzTreeMeshes.CANOPY_SHADER.code.contains("a2c_edge"),
		"canopy.gdshader принимает uniform a2c_edge")


func test_island_view_applies_a2c_to_canopy_materials() -> void:
	# IslandView собирает материалы листвы из мешей дерева (включая LOD)
	# и применяет край по уровню: ULTRA — CANOPY_A2C_EDGE, HIGH — 0.
	var view := IslandView.new()
	var art := IslandArt.new()
	var set: Dictionary = EzTreeMeshes.build_set(&"etree_oak", 0)
	var group := PropGroup.new()
	group.mesh = set["mesh"]
	group.lods = set["lods"]
	group.transforms = [Transform3D(Basis(), Vector3(3.0, 0.0, 3.0))]
	group.colors = [Color.WHITE]
	art.prop_groups = {"etree_oak:0": group}
	view.art = art
	view._build_tree_lods("etree_oak:0", "etree_oak", group)
	assert_eq(
		view._canopy_materials.size(), 2,
		"материалы листвы собраны с двух уровней (по одному — кора "
		+ "отфильтрована; LOD2 заменён импостором — свой шейдер, П17 п.3)")
	view.set_quality(GraphicsQuality.Tier.ULTRA)
	for material: ShaderMaterial in view._canopy_materials:
		assert_almost_eq(
			float(material.get_shader_parameter("a2c_edge")),
			GraphicsQuality.CANOPY_A2C_EDGE, 0.001,
			"ULTRA: A2C применён к материалу листвы")
	view.set_quality(GraphicsQuality.Tier.HIGH)
	for material: ShaderMaterial in view._canopy_materials:
		assert_almost_eq(
			float(material.get_shader_parameter("a2c_edge")), 0.0, 0.001,
			"HIGH: A2C снят")
	view.free()
