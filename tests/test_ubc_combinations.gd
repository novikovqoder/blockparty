# Тест всех комбинаций одежды (П5.8, часть B, «Персонаж всегда одет»):
# перебирает пол × верх × низ × обувь × убор × причёска (все разумные
# комбинации индексов редактора) и проверяет:
# - обязательные части видимы и не пусты, лишние скрыты (тела под одеждой
#   в сцене нет — срез головы, глаза, брови, причёска + одежда);
# - бюджет ~13–20 тыс. треугольников ближнего варианта (SPEC);
# - горизонтальные лучи на высотах щиколотки/голени/бедра/пояса/груди/шеи
#   со всех сторон во что-то попадают — сквозных дыр силуэта нет
#   (персонаж всегда одет, тело вырезано; луч мимо геометрии = просвет).
extends GutTest

const MODEL: PackedScene = preload("res://gameplay/player/character_model.tscn")
## Верх бюджета треугольников ближнего варианта (раздел «Этап П5.8»).
const TRI_BUDGET: int = 20000
## Высоты срезов силуэта, м (после подгонки роста): щиколотка, голень,
## бедро, пояс, грудь, шея.
const RAY_HEIGHTS: PackedFloat32Array = [0.05, 0.4, 0.85, 1.05, 1.35, 1.5]
## Число направлений лучей вокруг оси персонажа.
const RAY_DIRECTIONS: int = 12
## Лучи пускаются тройками со сдвигом поперёк: между ног у оси пусто
## по построению, одежда проверяется любым из трёх.
const RAY_OFFSET: float = 0.07


func test_all_clothing_combinations_cover_body() -> void:
	var combos := 0
	for gender: int in Appearance.GENDERS:
		for top: int in Appearance.OUTFITS.size():
			for legs: int in Appearance.OUTFITS.size():
				for feet: int in Appearance.OUTFITS.size():
					for hat: int in Appearance.HATS:
						for hair: int in Appearance.hair_variants(gender):
							var ap := Appearance.default_for(gender)
							ap.top = top
							ap.legs = legs
							ap.feet = feet
							ap.hat = hat
							ap.hair = hair
							ap.hair_color = hair % Appearance.HAIR_COLORS.size()
							ap.skin = (top + legs + feet) % Appearance.SKIN_COLORS.size()
							ap.eye_color = hat % Appearance.EYE_COLORS.size()
							var model := MODEL.instantiate() as CharacterModel
							add_child(model)
							model.setup_appearance(ap)
							_check_structure(model, ap)
							_check_budget(model)
							await _check_no_see_through(model,
								"пол %d верх %d низ %d обувь %d убор %d волосы %d"
								% [gender, top, legs, feet, hat, hair])
							model.queue_free()
							combos += 1
	assert_gt(combos, 100, "перебраны все разумные комбинации (факт %d)" % combos)


## Структура: ровно выбранные части видимы, меши не пусты.
func _check_structure(model: CharacterModel, ap: Appearance) -> void:
	var g := "mf"[ap.gender]
	var expected: PackedStringArray = [
		"head_%s" % g, "eyes_%s" % g, "brows_%s" % g,
		"hair_%s" % Appearance.HAIRS[ap.hair],
		"top_%s_%s" % [Appearance.OUTFITS[ap.top], g],
		"arms_%s_%s" % [Appearance.OUTFITS[ap.top], g],
		"legs_%s_%s" % [Appearance.OUTFITS[ap.legs], g],
		"feet_%s_%s" % [Appearance.OUTFITS[ap.feet], g],
	]
	if ap.hat == Appearance.HAT_HOOD:
		expected.append("hood_ranger_%s" % g)
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var name := String(mi.name)
		var part := name.substr(0, name.length() - 4) \
			if name.ends_with("_LOD") else name
		if not expected.has(part):
			assert_false(mi.visible, "%s скрыта в этой комбинации" % name)
			continue
		assert_true(mi.visible, "%s видна" % name)
		assert_not_null(mi.mesh, "%s: меш есть" % name)
		assert_gt(mi.mesh.get_surface_count(), 0, "%s: поверхности есть" % name)
		var tris := 0
		for surface: int in mi.mesh.get_surface_count():
			tris += (mi.mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX]
				as PackedInt32Array).size() / 3
		assert_gt(tris, 0, "%s: треугольники есть" % name)


## Бюджет: ближний вариант целиком не выше TRI_BUDGET, LOD ниже ближнего.
func _check_budget(model: CharacterModel) -> void:
	var near := 0
	var lod := 0
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if not mi.visible or mi.mesh == null:
			continue
		var tris := 0
		for surface: int in mi.mesh.get_surface_count():
			tris += (mi.mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX]
				as PackedInt32Array).size() / 3
		if (mi.name as String).ends_with("_LOD"):
			lod += tris
		else:
			near += tris
	assert_between(near, 12000, TRI_BUDGET,
		"бюджет ближнего варианта (факт %d)" % near)
	assert_lt(lod, near, "LOD легче ближнего варианта")


## Просветы: физический силуэт из видимых мешей, горизонтальные лучи
## тройками со всех направлений на высотах срезов. Луч мимо всей
## геометрии — дыра (одежда не прикрывает / часть не собралась).
func _check_no_see_through(model: CharacterModel, label: String) -> void:
	var root := model.find_child("UbcRoot", true, false) as Node3D
	assert_not_null(root, "%s: корень сцены найден" % label)
	var body := StaticBody3D.new()
	root.add_child(body)
	var shapes := 0
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if not mi.visible or (mi.name as String).ends_with("_LOD"):
			continue
		var shape := mi.mesh.create_trimesh_shape()
		if shape == null:
			continue
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		shapes += 1
	assert_gt(shapes, 5, "%s: силуэт собран из мешей" % label)
	await get_tree().physics_frame
	var space := model.get_world_3d().direct_space_state
	for height: int in RAY_HEIGHTS.size():
		var y: float = RAY_HEIGHTS[height]
		for dir_index: int in RAY_DIRECTIONS:
			var angle := TAU * float(dir_index) / float(RAY_DIRECTIONS)
			var dir := Vector3(cos(angle), 0.0, sin(angle))
			var side := Vector3(-dir.z, 0.0, dir.x)
			var hit := false
			for offset: int in [-1, 0, 1]:
				var from := dir * 2.5 + side * (RAY_OFFSET * float(offset)) \
					+ Vector3(0.0, y, 0.0)
				var query := PhysicsRayQueryParameters3D.create(
					from, from - dir * 5.0)
				if space.intersect_ray(query).size() > 0:
					hit = true
					break
			assert_true(hit, "%s: высота %.2f, направление %d закрыт" % [
				label, y, dir_index])
	body.queue_free()
