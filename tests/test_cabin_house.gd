# Сруб Kless (ветка visual-overhaul, очередь владельца после доработки
# П5.13): дом жителей деревни, в который можно зайти. Проверки:
#   1) раскладка: три сруба на плоских подушках PLAZA_H у Площади,
#      вариации поворота/оттенка/террасы, двери смотрят на площадь;
#   2) «не висит» (требование распространено на дома): земля под домом
#      вровень с площадкой, видимый низ дома ниже земли (сваи в земле);
#   3) проход: бот без прыжков поднимается по лестнице террасы, входит
#      в сруб через дверной проём и выходит обратно — реальная физика;
#   4) стены и пол: постоянное давление в стену у двери и в южную стену
#      крыла не проходит сквозь, пол комнаты держит игрока;
#   5) под срубами нет твёрдых предметов наполнения;
#   6) LOD: интерьер скрыт дальше 30 м, снаружи — виден;
#   7) камера внутри прижимается (SpringArm о коллизию дома) и не
#      проходит сквозь стены/крышу;
#   8) тёплый свет внутри и у входа — ночь в доме не чёрная.
extends GutTest

const ISLAND: PackedScene = preload("res://gameplay/world/island.tscn")
const ART: IslandArt = preload("res://gameplay/world/island_art.res")
const PLAYER: PackedScene = preload("res://gameplay/player/player.tscn")

## Форсаж тика физики (как test_slope_walking): проход через дом —
## десятки секунд реального времени.
const FAST_TICKS: int = 240
var _saved_ticks: int = 60

## Прибытие к точке: XZ-дистанция и контакт с землёй.
const ARRIVE_XY: float = 1.6
## Прибытие внутри дома: радиус 1.6 срабатывает ещё на пороге (порог 0.6
## в 1.1 м от плоскости стены) — внутренние ноги требуют точности.
const ARRIVE_XY_INNER: float = 0.55
## Время одного отрезка пути, с (лестница/дверь/комната).
const LEG_TIME: float = 20.0


func before_all() -> void:
	_saved_ticks = Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = FAST_TICKS


func after_all() -> void:
	Engine.physics_ticks_per_second = _saved_ticks


func before_each() -> void:
	# Остров регистрируется в autofree и освобождается по концу каждого
	# теста — кэш _world() обязан сбрасываться, иначе следующие тесты
	# кастуют освобождённый узел («Trying to cast a freed object»).
	_island = null
	_cabins.clear()


# --- Драйвер вместо BotController: идёт к цели, НИКОГДА не прыгает ---
class Walker extends BotController:
	var target := Vector3.ZERO
	var active := false
	var _halt_left := 0.0
	var _side_left := 0.0
	var _side_sign := 1.0
	var _side_switched := 0


	func _physics_process(delta: float) -> void:
		if _player == null or not active:
			return
		var horizontal := Vector2(_player.velocity.x, _player.velocity.z).length()
		if _side_left > 0.0:
			_side_left -= delta
		elif horizontal < 0.5:
			_halt_left += delta
			if _halt_left >= 1.2:
				_halt_left = 0.0
				_side_left = 1.0
				_side_switched += 1
				if _side_switched % 2 == 0:
					_side_sign = -_side_sign
		else:
			_halt_left = 0.0


	func wish_direction() -> Vector3:
		if _player == null or not active:
			return Vector3.ZERO
		var to_target := target - _player.global_position
		to_target.y = 0.0
		if to_target.length() < 0.5:
			return Vector3.ZERO
		var dir := to_target.normalized()
		if _side_left > 0.0:
			var side := Vector3(-dir.z, 0.0, dir.x) * _side_sign
			dir = (dir + side * 1.4).normalized()
		return dir


	func consume_jump() -> bool:
		return false


	func jump_held() -> bool:
		return false


	func consume_attack() -> bool:
		return false


## Драйвер «таран»: постоянное давление в одном направлении без обходов —
## проверка, что стена держит, а пол не проваливается.
class Rammer extends BotController:
	var dir := Vector3.ZERO
	var active := false


	func wish_direction() -> Vector3:
		return dir if active else Vector3.ZERO


	func consume_jump() -> bool:
		return false


	func jump_held() -> bool:
		return false


	func consume_attack() -> bool:
		return false


var _island: Node3D
var _cabins: Array[Node] = []


func _world() -> Node3D:
	if _island == null:
		_island = ISLAND.instantiate()
		add_child_autofree(_island)
		for child in _island.get_children():
			if child.name.begins_with("Cabin"):
				_cabins.append(child)
	return _island


func test_village_layout_three_variations() -> void:
	# Три сруба, вариации поворотов/оттенков, терраса не у всех, двери
	# смотрят в сторону площади (дверное направление — на центр площади),
	# габариты домов не пересекаются (первая раскладка карманами-суммами
	# соседних выходов давала два дома в 9 м друг от друга).
	var world := _world()
	assert_eq(_cabins.size(), 3, "в деревне три сруба")
	var yaws: Array[float] = []
	var variants: Array[int] = []
	var terraces: Array[int] = []
	var boxes: Array[AABB] = []
	for cabin: Node in _cabins:
		var house := cabin as CabinHouse
		assert_ne(house, null, "узел сруба со скриптом CabinHouse")
		yaws.append(house.rotation.y)
		variants.append(house.variant)
		terraces.append(1 if house.terrace else 0)
		# Дверь (локальный −X) — на площадь: направление из двери к центру
		# площади совпадает с door_world_dir с точностью до вариации-доворота.
		var to_plaza := (Vector3(0.5, house.global_position.y, 2.5)
			- house.global_position).normalized()
		assert_gt(house.door_world_dir().dot(to_plaza), 0.9,
			"%s: вход смотрит на площадь" % house.name)
		boxes.append(_world_model_aabb(house))
	for i: int in boxes.size():
		for j: int in range(i + 1, boxes.size()):
			assert_eq(boxes[i].intersection(boxes[j]), AABB(),
				"габариты срубов %d и %d не пересекаются" % [i + 1, j + 1])
	assert_true(yaws[0] != yaws[1] or yaws[1] != yaws[2],
		"повороты срубов различаются")
	assert_true(variants.has(0) and variants.has(1) and variants.has(2),
		"три оттенка дерева")
	assert_eq(terraces.count(0), 1, "один сруб без террасы (вариация)")
	assert_eq(terraces.count(1), 2, "два сруба с террасой")


## Мировой AABB модели сруба (все видимые меши, поворот узла + позиция):
## консервативная проверка «дома не растут друг в друга».
func _world_model_aabb(house: CabinHouse) -> AABB:
	var local := AABB()
	var model := house.get_node_or_null("Cabin") as Node3D
	assert_ne(model, null, "%s: модель построена" % house.name)
	if model == null:
		return AABB()
	for child in model.get_children():
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		local = local.merge(mi.mesh.get_aabb())
	var out := AABB()
	for corner: Vector3 in [
		local.position,
		local.position + Vector3(local.size.x, 0.0, 0.0),
		local.position + Vector3(0.0, local.size.y, 0.0),
		local.position + Vector3(0.0, 0.0, local.size.z),
		local.position + Vector3(local.size.x, local.size.y, 0.0),
		local.position + Vector3(local.size.x, 0.0, local.size.z),
		local.position + Vector3(0.0, local.size.y, local.size.z),
		local.position + local.size,
	]:
		var p: Vector3 = house.global_transform * corner
		out = out.expand(p) if out != AABB() else AABB(p, Vector3.ZERO)
	return out


func test_cabins_grounded_no_gap() -> void:
	# «Не висит» для домов: подушка плоская на PLAZA_H вписана в рельеф,
	# земля под габаритом дома вровень с площадкой (зазоров нет), видимый
	# низ дома (сваи) — под землёй.
	var world := _world()
	var heights: PackedFloat32Array = ART.heights
	for cabin: Node in _cabins:
		var house := cabin as CabinHouse
		var corners: Array[Vector3] = [
			Vector3(-6.8, 0.0, -8.1), Vector3(6.8, 0.0, -8.1),
			Vector3(-6.8, 0.0, 8.1), Vector3(6.8, 0.0, 8.1),
			Vector3(0.0, 0.0, 0.0),
		]
		for corner: Vector3 in corners:
			var at: Vector3 = house.global_transform * corner
			var ground := IslandGen.ground_height(heights, at.x, at.z)
			assert_between(ground, IslandGen.PLAZA_H - 0.05, IslandGen.PLAZA_H + 0.05,
				"%s: земля под домом вровень с подушкой (%s)" % [house.name, at])
		assert_almost_eq(house.global_position.y, IslandGen.PLAZA_H, 0.01,
			"%s: сруб стоит на подушке" % house.name)


func test_no_solid_props_inside_cabins() -> void:
	# Наполнение и постройки не залезают под срубы: в габарите дома
	# (13.6 × 16.2) нет предметов вообще — ни твёрдых, ни декоративных.
	var data: Dictionary = IslandGen.generate()
	var intruders: Array[String] = []
	for plot: Dictionary in data["poi"]["village"]["plots"]:
		var base: Vector3 = plot["pos"]
		var yaw: float = plot["yaw"]
		var fwd := Vector3(cos(yaw), 0.0, -sin(yaw))
		var side := Vector3(sin(yaw), 0.0, cos(yaw))
		for prop: Dictionary in data["props"]:
			var pos: Vector3 = prop["pos"]
			var rel := pos - base
			if absf(rel.dot(fwd)) < 6.8 and absf(rel.dot(side)) < 8.1:
				intruders.append("%s: %s внутри габарита сруба" % [base, prop["type"]])
	assert_eq(intruders.size(), 0,
		"под срубами нет предметов: %s" % ", ".join(intruders))


func test_bot_enters_and_exits() -> void:
	# Главный критерий очереди владельца: в сруб можно зайти. Бот без
	# прыжков проходит вход с ЗАПАДА (замер коллизии лучами физики:
	# юг и север крыла — глухие стены): подушка под крытой террасой →
	# три ступени (x −1.2…−0.5, подъём 0.19/0.38/0.56) → крыльцо 0.62 →
	# дверной проём (западная стена крыла, z −5.55…−4.95) → комната
	# крыла с полом 0.16, и тем же путём обратно. Проём ~0.85 м при
	# капсуле Ø0.7 — путь ведём по центру проёма (z=−5.2).
	var world := _world()
	var house := _cabins[0] as CabinHouse
	var walker := Walker.new()
	add_child_autofree(walker)
	var player := PLAYER.instantiate() as Player
	world.add_child(player)
	# Старт на подушке западнее ступеней, под крышей террасы.
	var start: Vector3 = house.global_transform * Vector3(-4.5, 0.0, -5.2)
	player.global_position = start + Vector3(0.0, 0.2, 0.0)
	walker.setup(player)
	player._bot = walker
	await _settle(30)
	var legs: Array[Dictionary] = [
		{"name": "ступени крыльца", "local": Vector3(-0.85, 0.0, -5.2)},
		{"name": "крыльцо у двери", "local": Vector3(0.3, 0.0, -5.2)},
		{"name": "проём", "local": Vector3(1.1, 0.0, -5.2), "near": ARRIVE_XY_INNER},
		{"name": "комната крыла", "local": Vector3(2.7, 0.0, -5.2), "near": ARRIVE_XY_INNER},
	]
	for leg: Dictionary in legs:
		var target: Vector3 = house.global_transform * leg["local"]
		var arrived := await _walk_leg(player, walker, target, leg.get("near", ARRIVE_XY))
		assert_true(arrived, "бот дошёл: %s" % leg["name"])
	# Внутри: восточнее плоскости стены, на полу (не провалился, не застрял).
	assert_almost_eq(player.global_position.y, IslandGen.PLAZA_H + 0.16, 0.3,
		"бот стоит на полу сруба (PLAZA_H + 0.16)")
	var inside_local := house.global_transform.affine_inverse() * player.global_position
	assert_gt(inside_local.x, 1.25, "бот прошёл стену крыла и внутри (x)")
	assert_between(inside_local.z, -6.6, -3.6, "бот внутри комнаты крыла (z)")
	# Обратно: через проём на крыльцо и вниз по ступеням на подушку
	# (дверь — единственный проход).
	var reversed_legs := legs.duplicate()
	reversed_legs.reverse()
	for leg: Dictionary in reversed_legs:
		var target: Vector3 = house.global_transform * leg["local"]
		var arrived := await _walk_leg(player, walker, target, leg.get("near", ARRIVE_XY))
		assert_true(arrived, "бот вышел: %s" % leg["name"])
	var arrived_out := await _walk_leg(player, walker, start)
	assert_true(arrived_out, "бот вернулся на подушку перед ступенями")
	var out_local := house.global_transform.affine_inverse() * player.global_position
	assert_lt(out_local.x, -1.5, "бот снова снаружи (западнее ступеней)")
	walker.active = false
	walker.setup(null)
	player.queue_free()


func test_walls_and_floor_hold() -> void:
	# Стены непроходимы, пол держит: «таран» постоянным давлением —
	# сквозь западную стену крыла в 0.55 м от кромки проёма и сквозь
	# южную стену крыла игрок не проходит; на полу комнаты не проваливается
	# (вариация «без террасы» не оставляет дыр — оба типа срубов).
	var world := _world()
	for cabin: Node in _cabins:
		var house := cabin as CabinHouse
		var rammer := Rammer.new()
		add_child_autofree(rammer)
		var player := PLAYER.instantiate() as Player
		world.add_child(player)
		# Стена у двери: внутри крыла, давим на запад (локальный −X),
		# точка z=−6.2 — между проёмом (до −5.65) и южной стеной.
		player.global_position = house.global_transform * Vector3(2.7, 0.16, -6.2) \
			+ Vector3(0.0, 0.1, 0.0)
		rammer.setup(player)
		player._bot = rammer
		await _settle(10)
		rammer.dir = -(house.global_transform.basis * Vector3(1.0, 0.0, 0.0)).normalized()
		rammer.active = true
		await _settle(int(2.0 * Engine.physics_ticks_per_second))
		var local := house.global_transform.affine_inverse() * player.global_position
		assert_gt(local.x, 0.9,
			"%s: сквозь западную стену у двери таран не прошёл" % house.name)
		# Южная стена крыла: давим на юг (локальный −Z).
		player.global_position = house.global_transform * Vector3(2.7, 0.16, -6.2) \
			+ Vector3(0.0, 0.1, 0.0)
		await _settle(10)
		rammer.dir = -(house.global_transform.basis * Vector3(0.0, 0.0, 1.0)).normalized()
		await _settle(int(2.0 * Engine.physics_ticks_per_second))
		local = house.global_transform.affine_inverse() * player.global_position
		assert_gt(local.z, -6.9,
			"%s: сквозь южную стену крыла таран не прошёл" % house.name)
		assert_almost_eq(player.global_position.y, IslandGen.PLAZA_H + 0.16, 0.25,
			"%s: пол комнаты держит игрока" % house.name)
		rammer.active = false
		rammer.setup(null)
		player.queue_free()


func test_interior_lod_visibility() -> void:
	# Издалека интерьер не рисуется (visibility_range 30 м): издалека —
	# только внешний облик. Проверка на данных мешей узла.
	var world := _world()
	for cabin: Node in _cabins:
		var house := cabin as CabinHouse
		var model := house.get_node_or_null("Cabin") as Node3D
		assert_ne(model, null, "%s: модель построена" % house.name)
		if model == null:
			continue
		var interior := 0
		var exterior := 0
		for child in model.get_children():
			var mi := child as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			if mi.name.begins_with("INT_"):
				interior += 1
				assert_almost_eq(mi.visibility_range_end, 30.0, 0.01,
					"%s/%s: интерьер скрыт дальше 30 м" % [house.name, mi.name])
			elif not mi.name.begins_with("COLL"):
				exterior += 1
		assert_eq(interior, 5, "%s: пять мешей интерьера" % house.name)
		assert_eq(exterior, 10, "%s: внешний контур на месте" % house.name)


func test_camera_pulls_in_inside_cabin() -> void:
	# Очередь владельца, пункт «в»: камера от третьего лица внутри сруба
	# сама прижимается. Стены/пол/потолок ловятся физикой, но рука
	# наклонена вверх и шесть метров вылетали сквозь окна и стены —
	# внутри дома длина руки ограничена (INTERIOR_MAX), камера не покидает
	# габарит дома; на улице длина возвращается к полной.
	var world := _world()
	var house := _cabins[0] as CabinHouse
	var player := PLAYER.instantiate() as Player
	world.add_child(player)
	player.global_position = house.global_transform * Vector3(2.7, 0.5, -5.2)
	# Rig догоняет персонажа мягким lerp'ом, рука сжимается move_toward:
	# секунды хватает (остаток пути <1%, руки <0.01 м).
	await _settle(240)
	var cam: PlayerCamera = player.camera
	assert_true(
		cam.arm.spring_length <= PlayerCamera.INTERIOR_MAX + 0.05,
		"внутри сруба рука сжата до INTERIOR_MAX (факт %.2f)"
			% cam.arm.spring_length)
	var cam_local: Vector3 = house.global_transform.affine_inverse() \
		* cam.camera.global_position
	assert_between(cam_local.x, -7.2, 7.2, "камера не прошла западную/восточную стену")
	assert_between(cam_local.z, -8.6, 8.6, "камера не прошла северную/южную стену")
	assert_lt(cam_local.y, 4.6, "камера не прошла сквозь потолок")
	# Выход на подушку перед домом: рука плавно возвращается к полной.
	player.global_position = house.global_transform * Vector3(-4.5, 0.5, -5.2)
	await _settle(240)
	assert_gt(cam.arm.spring_length, 5.0,
		"снаружи рука вернулась к полной длине (факт %.2f)"
			% cam.arm.spring_length)
	player.queue_free()


func test_interior_lights_warm_and_present() -> void:
	# Пункт «в» очереди владельца: ночь внутри дома — не чёрная: тёплый
	# свет у входа и в комнате (паттерн костра) плюс лампа крыльца. Свет
	# обязателен в каждом срубе деревни — пропажа любого делает интерьер
	# неиграбельным ночью.
	var world := _world()
	for cabin: Node in _cabins:
		var house := cabin as CabinHouse
		for light_name: String in ["PorchLight", "WingLight", "HallLight"]:
			var light := house.get_node_or_null(light_name) as OmniLight3D
			assert_ne(light, null,
				"%s: источник света %s на месте" % [house.name, light_name])
			if light == null:
				continue
			assert_gt(light.light_energy, 0.0,
				"%s/%s: свет включён" % [house.name, light_name])
			# «Тёплый»: красной составляющей больше синей (паттерн костра).
			assert_gt(light.light_color.r, light.light_color.b + 0.15,
				"%s/%s: тёплый оттенок" % [house.name, light_name])


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame


func _walk_leg(player: Player, walker: Walker, target: Vector3, near: float = ARRIVE_XY) -> bool:
	walker.target = target
	walker.active = true
	var trace := ""
	for i in int(LEG_TIME * float(Engine.physics_ticks_per_second)):
		await get_tree().physics_frame
		if i % int(Engine.physics_ticks_per_second) == 0:
			trace += " %.1f;%.1f" % [player.global_position.x, player.global_position.z]
		var flat := Vector2(
			player.global_position.x - target.x,
			player.global_position.z - target.z)
		if flat.length() < near and player.is_on_floor():
			print("TRACE к (%.1f, %.1f):%s ДОВЁЛ" % [target.x, target.z, trace])
			return true
	print("TRACE к (%.1f, %.1f):%s НЕ дошёл" % [target.x, target.z, trace])
	return false
