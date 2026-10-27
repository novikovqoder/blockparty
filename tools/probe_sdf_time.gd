# Пробник времени печати SDF-карты берега (П15 блок 3): godot --headless
# -s tools/probe_sdf_time.gd — печатает секунды и знак в паре точек.
extends SceneTree


func _init() -> void:
	print("probe: loading art")
	var art: IslandArt = load("res://gameplay/world/island_art.res")
	print("probe: art loaded, baking sdf")
	var t0: int = Time.get_ticks_msec()
	var image := ShoreBand.sdf_image(art, IslandGen.SEA_LEVEL)
	print("sdf bake ms=%d" % (Time.get_ticks_msec() - t0))
	print("size=%d fmt=%d" % [image.get_width(), image.get_format()])
	print("center=%.2f lake=%.2f" % [
		ShoreBand.sdf_at(image, 0.0, 0.0),
		ShoreBand.sdf_at(image, IslandGen.LAKE_CENTER.x,
			IslandGen.LAKE_CENTER.y)])
	var heights: PackedFloat32Array = art.heights
	var t1: int = Time.get_ticks_msec()
	var contour := ShoreBand.contour_points(heights, IslandGen.SEA_LEVEL)
	print("contour=%d pts ms=%d" % [
		contour.size(), Time.get_ticks_msec() - t1])
	var worst: float = 0.0
	for i: int in 30:
		var point: Vector2 = contour[(i * 37) % contour.size()]
		var got: float = ShoreBand.sdf_at(image, point.x, point.y)
		var truth: float = ShoreBand.true_distance(
			heights, IslandGen.SEA_LEVEL, contour, point.x, point.y)
		worst = maxf(worst, absf(got - truth))
	print("worst at contour=%.3f" % worst)
	quit(0)
