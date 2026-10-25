# Диагностика земли Площади (фикс-задача П12): что реально в картах покраски
# в точках Площади/тропы и в ORM-каналах высот слоёв. Печатает веса
# (r камень, g влага, b мох, a тропа/гравий), вес тона border.a (1 = текстура
# земли полностью заменена плоским цветом) и статистику канала B (Height)
# ORM-карт, плюс вклад слоёв в softmax шейдера в пробных точках.
# Запуск: godot --headless --path . -s tools/diag_plaza_ground.gd
extends SceneTree

const HEIGHT_TEX := 0.35  # forest_ground.gdshader HEIGHT_TEX
const BLEND_SHARP := 6.0  # forest_ground.gdshader BLEND_SHARP


func _initialize() -> void:
	var art: IslandArt = load("res://gameplay/world/island_art.res") as IslandArt
	var weights := ForestGround._weights_image(art)
	var border := ForestGround._border_image(art)
	var tint: Dictionary = IslandGen.tint_hints()

	print("=== Точки Площади/тропы: вес тона a (1 = плоский цвет) и веса слоёв ===")
	print("точка        h     тон_a  r_кам  g_влага b_мох  a_гравий  hint")
	for p: Vector2 in [
		Vector2(0, 4), Vector2(8, 4), Vector2(-8, 4), Vector2(0, 14),
		Vector2(0, -8), Vector2(-8, -8), Vector2(17, 4), Vector2(19, 4),
		Vector2(21, 4), Vector2(23, 4), Vector2(0, 26),
		Vector2(-16, -10), Vector2(-34, -26), Vector2(-50, -48),
		Vector2(58, -48),
	]:
		var px := int(p.x) + 128
		var pz := int(p.y) + 128
		var h: float = art.heights[pz * IslandGen.POINTS + px]
		var w: Color = weights.get_pixel(px, pz)
		var b: Color = border.get_pixel(px, pz)
		var zone: String = "-"
		var hint: Dictionary = tint.get(Vector2i(int(p.x), int(p.y)), {})
		if not hint.is_empty():
			zone = str(hint["zone"])
		print("(%4d,%4d) %6.2f  %.3f  %.3f  %.3f  %.3f  %.3f    zone=%s"
			% [p.x, p.y, h, b.a, w.r, w.g, w.b, w.a, zone])

	print("")
	print("=== ORM-каналы слоёв: средний B (Height), разброс ===")
	var orm_b := {}
	for key: String in ["gravel", "mud", "moss", "litter"]:
		var tex: Texture2D = {
			"gravel": ForestGround.GRAVEL_ORM,
			"mud": ForestGround.MUD_ORM,
			"moss": ForestGround.MOSS_ORM,
			"litter": ForestGround.LITTER_ORM,
		}[key]
		var img := tex.get_image()
		img.decompress()
		var sum := 0.0
		var mn := 1.0
		var mx := 0.0
		var n := 0
		for y: int in range(0, img.get_height(), 37):
			for x: int in range(0, img.get_width(), 37):
				var v: float = img.get_pixel(x, y).b
				sum += v
				mn = minf(mn, v)
				mx = maxf(mx, v)
				n += 1
		orm_b[key] = sum / n
		print("%s: B ср=%.3f мин=%.3f макс=%.3f (сэмплов %d)"
			% [key, sum / n, mn, mx, n])

	print("")
	print("=== Softmax шейдера в пробных точках (по средним B карт) ===")
	for p: Vector2 in [Vector2(0, 4), Vector2(8, 4), Vector2(21, 4)]:
		var px := int(p.x) + 128
		var pz := int(p.y) + 128
		var w: Color = weights.get_pixel(px, pz)
		var total: float = clampf(w.r + w.g + w.b + w.a, 0.0, 1.0)
		var w_base: float = 1.0 - total
		var e := func(weight: float, h_map: float) -> float:
			return weight * exp((weight + h_map * HEIGHT_TEX) * BLEND_SHARP)
		var e_base: float = e.call(w_base, 0.5)
		var e_rock: float = e.call(w.r, 0.5)
		var e_mud: float = e.call(w.g, orm_b["mud"])
		var e_moss: float = e.call(w.b, orm_b["moss"])
		var e_gravel: float = e.call(w.a, orm_b["gravel"])
		var s: float = e_base + e_rock + e_mud + e_moss + e_gravel
		print("(%4d,%4d): base=%.2f камень=%.2f грязь=%.2f мох=%.2f ГРАВИЙ=%.2f"
			% [p.x, p.y, e_base / s, e_rock / s, e_mud / s, e_moss / s, e_gravel / s])
	quit(0)
