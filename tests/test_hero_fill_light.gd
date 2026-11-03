extends GutTest
## П17 п.11: заполняющий «свет персонажа» — герой читается в тени. Свет
## касается ТОЛЬКО слоя персонажей (light_cull_mask), теней не отбрасывает,
## ночью слабее; модель героя и меш меча помечаются слоем автоматически.

const B: Balance = preload("res://gameplay/balance.tres")


func test_light_touches_only_hero_layer() -> void:
	# Маска света — единственный бит слоя персонажей; тени выключены.
	# Мир слоя не имеет (дефолт GeometryInstance3D.layers = 1), значит свет
	# физически не может коснуться рельефа и построек.
	var light := HeroFillLight.new()
	add_child_autofree(light)
	assert_eq(light.light_cull_mask, HeroFillLight.LAYER_MASK,
		"маска света — только слой персонажей")
	assert_false(light.shadow_enabled, "fill-свет без теней")
	assert_eq(HeroFillLight.LAYER_MASK & 1, 0,
		"маска не задевает дефолтный слой 1 мира")
	assert_eq(HeroFillLight.LAYER_MASK & GraphicsQuality.LAMP_CASTER_MASK, 0,
		"слой персонажей ≠ слой кастеров ламп (число слоя уникально)")
	var plain := MeshInstance3D.new()
	add_child_autofree(plain)
	assert_eq(plain.layers & HeroFillLight.LAYER_MASK, 0,
		"обычный меш мира слой персонажей не имеет")


func test_energy_night_below_day() -> void:
	# Сила ведётся временем суток: ночью заметно слабее (ночь тёмная),
	# полдень — базовая константа.
	var light := HeroFillLight.new()
	add_child_autofree(light)
	var saved := Session.world_time
	Session.world_time = 0.8 * B.day_cycle_sec  # ночь
	light.update(Vector3(5.0, 3.0, 5.0), Vector3.ZERO)
	var night: float = light.light_energy
	Session.world_time = 0.3 * B.day_cycle_sec  # полдень
	light.update(Vector3(5.0, 3.0, 5.0), Vector3.ZERO)
	var day: float = light.light_energy
	Session.world_time = saved
	assert_almost_eq(day, HeroFillLight.HERO_FILL_ENERGY, 0.001,
		"днём — базовая сила")
	assert_lt(night, day * 0.75, "ночью fill-свет заметно слабее")


func test_update_faces_target_from_camera_side() -> void:
	# Направление со стороны камеры: свет смотрит от камеры на героя —
	# видимые камерой стороны освещены (герой «чёрный спиной к солнцу»
	# читается).
	var light := HeroFillLight.new()
	add_child_autofree(light)
	light.update(Vector3(0.0, 2.0, 10.0), Vector3.ZERO)
	var forward := -light.global_transform.basis.z
	var to_hero := (Vector3.ZERO + Vector3.UP * 1.2 - light.global_position).normalized()
	assert_gt(forward.dot(to_hero), 0.95,
		"свет направлен от камеры к герою")


func test_hero_model_marked_with_layer() -> void:
	# Модель героя помечает себя слоем в _ready: все меши визуала имеют бит.
	var model := HeroModelBU.new()
	add_child_autofree(model)
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	assert_gt(meshes.size(), 0, "модель героя собрана")
	for node: Node in meshes:
		assert_gt(
			(node as MeshInstance3D).layers & HeroFillLight.LAYER_MASK, 0,
			"меш %s — на слое персонажей" % node.name,
		)


func test_sword_marked_when_equipped() -> void:
	# Меч появляется в рантайме позже разметки героя — EquipControllerBU
	# помечает его сам; выхвачен или на поясе, он на слое персонажей.
	var model := HeroModelBU.new()
	add_child_autofree(model)
	var equip := model.get_node("EquipBU") as EquipControllerBU
	assert_not_null(equip.sword, "меч создан при старте (на поясе)")
	var meshes: Array[Node] = equip.sword.find_children(
		"*", "MeshInstance3D", true, false)
	assert_gt(meshes.size(), 0, "меши меча найдены")
	for node: Node in meshes:
		assert_gt(
			(node as MeshInstance3D).layers & HeroFillLight.LAYER_MASK, 0,
			"меш меча %s — на слое персонажей" % node.name,
		)
