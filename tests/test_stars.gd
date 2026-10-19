# Доработка-2 П5.13, П9 — звёзды частью неба. Источник текстур — ночное
# HDRI Poly Haven dikhololo_night (CC0): звёзды перерисованы чёткими
# точками (ядро 1–2 px, без гауссовых ореолов и «размытых пятен»), полоса
# Млечного Пути — настоящий фон снимка после вычитания засветки горизонта
# (без растянутого fbm — «чёрточек» прежней процедурной версии). Купол
# вращает звёзды с часами мира, мерцание — лёгкое. Частиц «Звездопада» в
# мире нет (удалены переделкой П5.9 П4), регресс запрещает их возврат.
# Текстуры статичны — планка проверяется по пикселям, без скриншотов.
extends GutTest

const B: Balance = preload("res://gameplay/balance.tres")
const WORLD: PackedScene = preload("res://scenes/world_scene.tscn")

## Порог «точки» в текстуре (8-бит): ниже — фон между звёздами.
const POINT_LUM: float = 0.15
## Ядро яркой звезды: пик компонента, по которому меряется размер и цвет.
const CORE_LUM: float = 0.45


func _texture(path: String) -> Texture2D:
	return load(path) as Texture2D


func _luminance(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


## Компоненты связности ярче POINT_LUM: {bbox, peak, peak_color} — по ним
## меряются чёткость (размер), количество и оттенки звёзд.
func _point_components(image: Image) -> Array[Dictionary]:
	var w := image.get_width()
	var h := image.get_height()
	var visited := PackedByteArray()
	visited.resize(w * h)
	var out: Array[Dictionary] = []
	var queue := PackedInt32Array()
	for p: int in w * h:
		if visited[p] == 1:
			continue
		var x := p % w
		var y := p / w
		if _luminance(image.get_pixel(x, y)) <= POINT_LUM:
			visited[p] = 1
			continue
		queue.clear()
		queue.append(p)
		visited[p] = 1
		var min_x := x
		var max_x := x
		var min_y := y
		var max_y := y
		var peak := 0.0
		var peak_col := Color.BLACK
		var at := 0
		while at < queue.size():
			var q := queue[at]
			at += 1
			var qx := q % w
			var qy := q / w
			var col := image.get_pixel(qx, qy)
			var lum := _luminance(col)
			if lum > peak:
				peak = lum
				peak_col = col
			min_x = mini(min_x, qx)
			max_x = maxi(max_x, qx)
			min_y = mini(min_y, qy)
			max_y = maxi(max_y, qy)
			for d: int in 4:
				var nx := qx + (1 if d == 0 else -1 if d == 1 else 0)
				var ny := qy + (0 if d < 2 else 1 if d == 2 else -1)
				if nx < 0 or nx >= w or ny < 0 or ny >= h:
					continue
				var np := ny * w + nx
				if visited[np] == 0 \
						and _luminance(image.get_pixel(nx, ny)) > POINT_LUM:
					visited[np] = 1
					queue.append(np)
		out.append({
			"size": Vector2i(max_x - min_x + 1, max_y - min_y + 1),
			"peak": peak,
			"color": peak_col,
		})
	return out


func test_starfield_sharp_points() -> void:
	# Россыпь звёзд: чёткие точки разного размера и яркости, тёплые и
	# холодные оттенки, фон между звёздами тёмный. Никаких размытых
	# пятен: даже самые яркие звёзды — пара пикселей, не гауссов blob.
	var texture := _texture("res://assets/visual/sky_starfield.png")
	assert_not_null(texture, "текстура звёзд на месте")
	if texture == null:
		return
	var image := texture.get_image()
	assert_eq(Vector2i(image.get_width(), image.get_height()), Vector2i(4096, 2048),
		"звёздное небо — высокое разрешение 4K")
	# Фон: медианный пиксель — чёрный (половина неба пустая).
	var lums := PackedFloat32Array()
	lums.resize(image.get_width() * image.get_height())
	for p: int in lums.size():
		lums[p] = _luminance(image.get_pixel(p % image.get_width(), p / image.get_width()))
	lums.sort()
	assert_lte(lums[lums.size() / 2], 1.0 / 255.0,
		"медиана неба — чёрный фон (звёзды редки)")
	# Точки: тысячи, без гигантских скоплений-пятен.
	var points := _point_components(image)
	assert_between(points.size(), 3000, 16000,
		"звёзды: россыпь тысяч точек (найдено %d)" % points.size())
	var biggest := Vector2i.ZERO
	var brightest := 0.0
	for point: Dictionary in points:
		var size: Vector2i = point["size"]
		if size.x * size.y > biggest.x * biggest.y:
			biggest = size
		if point["peak"] > brightest and point["peak"] < 0.999:
			brightest = point["peak"]
	assert_lte(maxi(biggest.x, biggest.y), 6,
		"самая крупная звезда ≤6 px без ореолов (%dx%d)" % [biggest.x, biggest.y])
	# Оттенки: тёплые и холодные звёзды обеих групп заметны.
	var warm := 0
	var cold := 0
	for point: Dictionary in points:
		if point["peak"] < CORE_LUM:
			continue
		var c: Color = point["color"]
		if c.r > c.b * 1.12:
			warm += 1
		elif c.b > c.r * 1.12:
			cold += 1
	assert_gte(warm, 30, "тёплых звёзд ≥30 (найдено %d)" % warm)
	assert_gte(cold, 30, "холодных звёзд ≥30 (найдено %d)" % cold)


func test_starmap_weak_smooth_band() -> void:
	# Слабый Млечный Путь: полоса есть, но тёмное небо доминирует; фон
	# гладкий (растянут из блочной карты) — без мелкой фактуры и полос.
	var texture := _texture("res://assets/visual/sky_starmap.png")
	assert_not_null(texture, "текстура млечного пути на месте")
	if texture == null:
		return
	var map := texture.get_image()
	assert_eq(Vector2i(map.get_width(), map.get_height()), Vector2i(4096, 2048),
		"стармап — 4K")
	var w := map.get_width()
	var h := map.get_height()
	var peak := 0.0
	var median_in: Array[float] = []
	var max_step := 0.0
	for y: int in h:
		for x: int in w:
			var lum := _luminance(map.get_pixel(x, y))
			peak = maxf(peak, lum)
			if (x + y) % 97 == 0:
				median_in.append(lum)
			if x + 1 < w:
				var right := _luminance(map.get_pixel(x + 1, y))
				max_step = maxf(max_step, absf(lum - right))
	median_in.sort()
	assert_between(peak, 0.30, 0.80,
		"полоса млечного пути слабая, но видна (пик %.2f)" % peak)
	assert_lte(median_in[median_in.size() / 2], 0.04,
		"медиана стармапа тёмная — небо не залито свечением")
	assert_lte(max_step, 0.16,
		"соседние пиксели близки: без мелкой фактуры (шаг %.3f)" % max_step)


func test_stars_rotate_with_night_twinkle_gently() -> void:
	# Звёзды — часть неба: небо с часами мира поворачивается (звёзды
	# неподвижны относительно неба, ходят вместе), мерцание лёгкое —
	# звезда не гаснет почти в ноль шумом сцинтилляции.
	var sky := Sky3D.new()
	add_child_autofree(sky)
	var cycle := DayCycle.new()
	cycle.setup(sky.sun, sky)
	var saved := Session.world_time
	Session.world_time = 0.75 * B.day_cycle_sec
	cycle._process(0.0)
	var rot_a: float = sky.sky_material.get_shader_parameter("star_rotation")
	Session.world_time = 0.85 * B.day_cycle_sec
	cycle._process(0.0)
	var rot_b: float = sky.sky_material.get_shader_parameter("star_rotation")
	Session.world_time = saved
	assert_gt(rot_a, 0.0, "звёздное небо повёрнуто по часам")
	assert_ne(rot_a, rot_b, "звёзды медленно ходят с ночью")
	var scint: float = sky.sky_material.get_shader_parameter("star_scintillation")
	assert_between(scint, 0.2, 0.5,
		"мерцание лёгкое: минимум звезды ~0.66 яркости (%.2f)" % scint)
	cycle.free()


func test_sky_stays_sharp() -> void:
	# Небо и звёзды должны быть резкими: TAA выключен (сглаживание —
	# MSAA на рёбрах + FXAA), DOF в проекте нет, порог bloom выше
	# яркости звёзд (текстура ≤1.0 — glow их не размывает в пятна).
	assert_false(ProjectSettings.get_setting_with_override(
			"rendering/anti_aliasing/quality/use_taa"), "TAA выключен")
	var world := WORLD.instantiate()
	add_child_autofree(world)
	var camera := _find_camera(world)
	assert_not_null(camera, "камера мира найдена")
	if camera != null:
		var attributes := camera.attributes
		assert_true(
			attributes == null or not (attributes as CameraAttributesPractical).dof_blur_far_enabled,
			"DOF на камере мира выключен")
	var env: Environment = world.get_node("WorldEnvironment").environment
	assert_gte(env.glow_hdr_threshold, 1.0,
		"порог bloom не ниже 1.0 — звёзды (≤1.0) не светятся пятнами")


func _find_camera(node: Node) -> Camera3D:
	if node is Camera3D:
		return node as Camera3D
	for child: Node in node.get_children():
		var found := _find_camera(child)
		if found != null:
			return found
	return null


func test_no_starfall_particles_left() -> void:
	# Остатков «Звездопада» (размытые пятна и чёрточки частиц) в мире
	# нет: частицы мира — светлячки/пыльца/листья Леса и искры с дымом
	# костра (П5.9, приняты); имена звёздно-метеорных систем запрещены.
	var world := WORLD.instantiate()
	add_child_autofree(world)
	var particles: Array[String] = []
	_collect_particles(world, particles)
	assert_gt(particles.size(), 0, "в мире есть частицы (костёр, светлячки)")
	for name: String in particles:
		var low := name.to_lower()
		assert_false(
			low.contains("star") or low.contains("meteor") or low.contains("звез"),
			"звёздных частиц нет, найдено: %s" % name)


func _collect_particles(node: Node, out: Array[String]) -> void:
	if node is GPUParticles3D or node is CPUParticles3D:
		out.append(String(node.name))
	for child: Node in node.get_children():
		_collect_particles(child, out)
