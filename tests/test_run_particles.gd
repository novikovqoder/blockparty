# Тесты частиц бега (доработка П9, правка 5 по замечанию владельца о
# «квадратиках»): интенсивность растёт со скоростью (шаг почти без пыли,
# бег — полная эмиссия), покрытие под ногами согласовано с весами окраски
# земли (ForestGround: камень склонов, тропа/гравий/низины, мох), спрайты
# пассов текстурированы по покрытию (ни одна частица — не белый квадрат),
# и эмиссия включается только на земле.
extends GutTest

const ART: IslandArt = preload("res://gameplay/world/island_art.res")
const B: Balance = preload("res://gameplay/balance.tres")
const DIRT_TEX: Texture2D = preload("res://assets/vfx/particles/dirt.png")
const GRASS_TEX: Texture2D = preload("res://assets/vfx/particles/grass.png")
const STONE_TEX: Texture2D = preload("res://assets/vfx/particles/stone.png")
const LEAF_TEX: Texture2D = preload("res://assets/vfx/particles/leaf.png")
const SOFT_TEX: Texture2D = preload("res://assets/vfx/particles/soft.png")


func test_intensity_grows_with_speed() -> void:
	# Покой и порог анимаций — ноль; бег (B.run_speed) — единица; шаг —
	# заметно меньше половины; между шагом и бегом монотонный рост.
	assert_eq(RunParticles.intensity(0.0, B), 0.0, "покой — без пыли")
	assert_eq(RunParticles.intensity(B.anim_idle_speed, B), 0.0,
		"на пороге анимаций пыли ещё нет")
	var walk := RunParticles.intensity(B.walk_speed, B)
	assert_between(walk, 0.01, 0.35, "шаг — почти нет: %f" % walk)
	assert_eq(RunParticles.intensity(B.run_speed, B), 1.0, "бег — полная эмиссия")
	assert_eq(RunParticles.intensity(99.0, B), 1.0, "выше бега не усиливается")
	var prev := 0.0
	var v := B.anim_idle_speed
	while v <= B.run_speed + 0.001:
		var now := RunParticles.intensity(v, B)
		assert_true(now >= prev - 1e-6,
			"интенсивность не убывает (v=%f: %f < %f)" % [v, now, prev])
		prev = now
		v += 0.25


func test_surface_kind_matches_ground_weights() -> void:
	# Покрытие под ногами — те же веса, что красят землю (_weights_image):
	# камень на крутых склонах, тропа/Площадь и влажные низины — земля,
	# мох — трава. Точки ищем по формулам весов, сверяем surface_kind.
	var noise := FastNoiseLite.new()
	noise.seed = ForestGround.MOSS_SEED
	noise.frequency = ForestGround.MOSS_FREQUENCY
	var found := {"stone": Vector3(), "grass": Vector3(), "wet": Vector3()}
	var have := {"stone": false, "grass": false, "wet": false}
	for z: int in range(0, ForestGround.MAP_M, 3):
		for x: int in range(0, ForestGround.MAP_M, 3):
			var wx := float(x) - 128.0
			var wz := float(z) - 128.0
			var w_rock: float = smoothstep(
				ForestGround.ROCK_SLOPE_SOFT, ForestGround.ROCK_SLOPE_FULL,
				ForestGround._slope(ART, x, z))
			var h: float = ART.heights[z * IslandGen.POINTS + x]
			var w_wet: float = 1.0 - smoothstep(
				ForestGround.WET_H_FULL, ForestGround.WET_H_SOFT, h)
			var w_path: float = maxf(
				ForestGround._path_weight(wx, wz),
				ForestGround._plaza_weight(wx, wz))
			var pos := Vector3(wx, 0.0, wz)
			if w_rock >= 0.5:
				assert_eq(ForestGround.surface_kind(ART, pos),
					ForestGround.Surface.STONE,
					"крутой склон (%d, %d) — камень" % [x, z])
				if not have["stone"]:
					have["stone"] = true
					found["stone"] = pos
			elif w_path < 0.5 and w_wet < 0.6:
				var w_moss: float = ForestGround._moss_weight(
					noise, x, z, 0.0, w_wet)
				if w_moss >= 0.35:
					assert_eq(ForestGround.surface_kind(ART, pos),
						ForestGround.Surface.GRASS,
						"мох (%d, %d) — трава" % [x, z])
					if not have["grass"]:
						have["grass"] = true
						found["grass"] = pos
			elif w_path >= 0.5 or w_wet >= 0.6:
				assert_eq(ForestGround.surface_kind(ART, pos),
					ForestGround.Surface.DIRT,
					"тропа/низина (%d, %d) — земля" % [x, z])
				if w_wet >= 0.6 and not have["wet"]:
					have["wet"] = true
					found["wet"] = pos
	assert_true(have["stone"], "на острове есть каменные склоны")
	assert_true(have["grass"], "на острове есть трава")
	# Жёсткие точки: вершина полилинии тропы и центр гравийной Площади —
	# утоптанная земля.
	assert_eq(ForestGround.surface_kind(
			ART, Vector3(ForestGround.PATH_POINTS[1].x, 0.0,
				ForestGround.PATH_POINTS[1].y)),
		ForestGround.Surface.DIRT, "тропа — земля")
	assert_eq(ForestGround.surface_kind(
			ART, Vector3(ForestGround.PLAZA_CENTER.x, 0.0,
				ForestGround.PLAZA_CENTER.y)),
		ForestGround.Surface.DIRT, "гравий Площади — земля")
	# За пределами карты — кламп, не падение.
	assert_true(ForestGround.surface_kind(
			ART, Vector3(999.0, 0.0, 999.0)) in [
			ForestGround.Surface.DIRT, ForestGround.Surface.GRASS,
			ForestGround.Surface.STONE],
		"вне карты покрытие определено")


func test_passes_textured_by_surface() -> void:
	# Спрайты пассов — по покрытию: камень — крошка, трава — комья +
	# травинки, земля — комья; у каждого материала есть текстура
	# (нетекстурный квад = белый квадрат = FAIL). Таймер перекладки в
	# игре — раз в 0.25 с, здесь перекладываем напрямую.
	var dust := RunParticles.new()
	add_child_autofree(dust)
	dust.setup(ART)
	var fx := dust.get_node("RunDust") as GPUParticles3D
	var cases := [
		{"pos": _find_surface(ForestGround.Surface.STONE),
			"kind": ForestGround.Surface.STONE, "passes": 1},
		{"pos": _find_surface(ForestGround.Surface.GRASS),
			"kind": ForestGround.Surface.GRASS, "passes": 2},
		{"pos": Vector3(ForestGround.PLAZA_CENTER.x, 0.0,
				ForestGround.PLAZA_CENTER.y),
			"kind": ForestGround.Surface.DIRT, "passes": 1},
	]
	for entry: Dictionary in cases:
		dust.global_position = entry["pos"]
		dust._refresh_surface()
		assert_eq(dust.surface(), entry["kind"], "покрытие определилось")
		assert_eq(fx.draw_passes, entry["passes"],
			"покрытие %d — пассов %d" % [entry["kind"], entry["passes"]])
		for i: int in fx.draw_passes:
			var mesh: QuadMesh = fx.get("draw_pass_%d" % (i + 1)) as QuadMesh
			var mat := mesh.material as StandardMaterial3D
			assert_not_null(mat.albedo_texture,
				"пасс %d покрытия %d: спрайт есть" % [i + 1, entry["kind"]])
	dust.global_position = _find_surface(ForestGround.Surface.GRASS)
	dust._refresh_surface()
	assert_eq((fx.draw_pass_1.material as StandardMaterial3D).albedo_texture,
		DIRT_TEX, "на траве первый пасс — комья земли")
	assert_eq((fx.draw_pass_2.material as StandardMaterial3D).albedo_texture,
		GRASS_TEX, "на траве второй пасс — травинки")
	dust.global_position = _find_surface(ForestGround.Surface.STONE)
	dust._refresh_surface()
	assert_eq((fx.draw_pass_1.material as StandardMaterial3D).albedo_texture,
		STONE_TEX, "камень — спрайт крошки")


func test_emission_follows_speed_and_floor() -> void:
	# Эмиттер включается только на земле и выше порога анимаций; доля
	# эмиссии — кривая интенсивности.
	var dust := RunParticles.new()
	add_child_autofree(dust)
	dust.setup(ART)
	dust.global_position = Vector3(ForestGround.PLAZA_CENTER.x, 0.0,
		ForestGround.PLAZA_CENTER.y)
	dust.update(0.0, true)
	assert_false(dust.is_emitting(), "стоя — пыли нет")
	dust.update(B.run_speed, false)
	assert_false(dust.is_emitting(), "в воздухе пыли нет")
	dust.update(B.walk_speed, true)
	assert_true(dust.is_emitting(), "на шаге по земле — чуть-чуть")
	assert_between(dust.ratio(), 0.01, 0.35, "шаг — малая доля эмиссии")
	dust.update(B.run_speed, true)
	assert_true(dust.is_emitting(), "на бегу по земле — пыль")
	assert_almost_eq(dust.ratio(), 1.0, 1e-6, "бег — полная эмиссия")


func test_fx_and_ambient_textured() -> void:
	# Однократные эффекты и атмосфера несут спрайты: пыль приземления —
	# комья земли, искры костра — мягкое пятно, светлячки/пыльца — мягкое
	# пятно, листья — лист.
	var holder := Node3D.new()
	add_child_autofree(holder)
	Fx.puff(holder, Vector3.ZERO, Color(0.86, 0.8, 0.7), 10, 0.12, 1.1)
	var puff_fx := holder.get_node("Fx") as GPUParticles3D
	assert_eq((puff_fx.draw_pass_1.material as StandardMaterial3D).albedo_texture,
		DIRT_TEX, "пыль приземления — спрайт земли")
	var sparks := Fx.fire_sparks(holder, Vector3.ONE, Color(1.0, 0.6, 0.2))
	assert_eq((sparks.draw_pass_1.material as StandardMaterial3D).albedo_texture,
		SOFT_TEX, "искры — мягкое пятно")
	var ambient := AmbientParticles.new()
	add_child_autofree(ambient)
	ambient.setup(GraphicsQuality.Tier.HIGH)
	for fx_name: String in ["Fireflies", "Pollen", "Leaves"]:
		var fx := ambient.get_node(fx_name) as GPUParticles3D
		var mat := fx.draw_pass_1.material as StandardMaterial3D
		assert_not_null(mat.albedo_texture, "%s — спрайт есть" % fx_name)
	assert_eq(
		(ambient.get_node("Leaves").draw_pass_1.material as StandardMaterial3D).albedo_texture,
		LEAF_TEX, "листья — спрайт листа")


## Точка первого встреченного покрытия (камень/трава) или центр Площади
## (земля) — для раскладки пассов в тесте.
func _find_surface(kind: int) -> Vector3:
	if kind == ForestGround.Surface.DIRT:
		return Vector3(ForestGround.PLAZA_CENTER.x, 0.0,
			ForestGround.PLAZA_CENTER.y)
	for z: int in range(0, ForestGround.MAP_M, 3):
		for x: int in range(0, ForestGround.MAP_M, 3):
			var pos := Vector3(float(x) - 128.0, 0.0, float(z) - 128.0)
			if ForestGround.surface_kind(ART, pos) == kind:
				return pos
	fail_test("покрытие %d не найдено на острове" % kind)
	return Vector3.ZERO
