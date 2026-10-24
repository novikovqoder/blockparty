# Доработка-2 П5.13, П2 — ходьба по склонам: числовые и физические тесты.
# Требования владельца:
#   - максимальный угол ходьбы ~50°: синтетические рампы 50° проходимы,
#     62° — стена (кромки/стенки/скалы острова круче пола — не проходимы);
#   - постоянная скорость на склоне: бег в гору не медленнее 0.75× бега
#     по ровному (без компенсации скольжение по плоскости склона резало
#     горизонтальный ход примерно до cos²θ);
#   - привязка к поверхности: через гребень и под уклон персонаж идёт
#     без отрыва от земли (не подпрыгивает на рёбрах);
#   - авто-шаг ~0.3 м: ступень 0.3 м проходится шагом, 0.5 м — нет;
#   - холмы: бот БЕЗ прыжков поднимается на вершину каждого холма зоны
#     «Холмы» и спускается обратно;
#   - смотровые уступы и стенки расщелины пешеходом НЕ проходимы (только
#     механики: лестница после подсадки; в расщелину — упасть и повиснуть).
extends GutTest

const ART: IslandArt = preload("res://gameplay/world/island_art.res")
const ISLAND: PackedScene = preload("res://gameplay/world/island.tscn")
const PLAYER: PackedScene = preload("res://gameplay/player/player.tscn")
const B: Balance = preload("res://gameplay/balance.tres")

## Проходная рампа (пол) и стена: граничные углы ходьбы.
const RAMP_WALK_DEG: float = 50.0
const RAMP_WALL_DEG: float = 62.0
## Доля полных 6.5 м/с, ниже которой подъём считается замедленным.
const UPHILL_SPEED_MIN_SHARE: float = 0.75
## Доля кадров с контактом с землёй на гребне/склонах; для острова — доля
## «чистого» контакта, остальное обязано быть честными падениями с кромок
## (см. _walk_leg: bounce_share < 1 − FLOOR_CONTACT_MIN_SHARE).
const FLOOR_CONTACT_MIN_SHARE: float = 0.85
## Предел вертикальной скорости «без прыжка», м/с: тяга в гору capped
## slope_climb_vy_max (5.0), прыжок — 7.5; порог между ними.
const NO_JUMP_VY: float = 6.0
## Время одного отрезка симуляции (подъём/спуск/подход), с.
const LEG_TIME: float = 30.0

## Форсаж тика физики: тесты — десятки реальных секунд симуляции; 240
## тиков/с вместо 60 прогоняют их вчетверо быстрее. Вся физика игрока —
## по delta, поведение от частоты тиков не зависит.
const FAST_TICKS: int = 240
var _saved_ticks: int = 60


func before_all() -> void:
	_saved_ticks = Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = FAST_TICKS


func after_all() -> void:
	Engine.physics_ticks_per_second = _saved_ticks


# --- Драйвер вместо BotController: идёт к цели, НИКОГДА не прыгает ---

## Подкласс BotController (Player._bot типизирован именно так; ввод
## персонажа читает wish_direction/consume_jump/jump_held/consume_attack):
## свой цикл вместо бродячего — одна цель, прыжков нет, застрявшее у
## препятствия направление сносит вбок, чтобы дерево или валун на пути
## не завешивали тест.
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
			# Снос перпендикулярно курсу — обойти препятствие.
			var side := Vector3(-dir.z, 0.0, dir.x) * _side_sign
			dir = (dir + side * 1.4).normalized()
		return dir


	func consume_jump() -> bool:
		return false


	func jump_held() -> bool:
		return false


	func consume_attack() -> bool:
		return false


func _walker() -> Walker:
	var walker := Walker.new()
	add_child_autofree(walker)
	return walker


# --- Синтетические склоны (наклонные боксы над плоским полом) ---

func _floor_box(parent: Node3D, size: float) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size, 1.0, size)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(0.0, -0.5, 0.0)
	parent.add_child(body)


## Рампа-бокс: верхняя кромка поверхности — в точке top, склон длиной
## length м уходит вниз в направлении descent_deg (угол от +X: 0 —
## восток, 180 — запад; направление вниз по склону). Возвращает нижнюю
## кромку поверхности (для спавна и замеров). Нормаль принудительно
## смотрит вверх — бокс всегда ПОД склоном.
func _ramp_from_top(
	parent: Node3D, top: Vector2, descent_deg: float, length: float = 26.0,
) -> Vector2:
	var phi := deg_to_rad(descent_deg)
	var descend := Vector2(cos(phi), sin(phi))
	var normal := Vector2(-descend.y, descend.x)
	if normal.y < 0.0:
		normal = -normal
	var face_center := top + descend * (length * 0.5)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(length, 1.0, 4.0)
	shape.shape = box
	body.add_child(shape)
	body.rotation.z = phi
	body.position = Vector3(face_center.x - normal.x * 0.5, face_center.y - normal.y * 0.5, 0.0)
	parent.add_child(body)
	return top + descend * length


func _spawn(parent: Node3D, position: Vector3) -> Player:
	var player := PLAYER.instantiate() as Player
	parent.add_child(player)
	player.global_position = position
	return player


func _settle(frames: int) -> void:
	for i: int in frames:
		await get_tree().physics_frame


func _frames(seconds: float) -> int:
	return int(seconds * float(Engine.physics_ticks_per_second))


func _release(player: Player, walker: Walker) -> void:
	walker.active = false
	walker.setup(null)
	player.queue_free()


func test_walk_max_slope_and_wall() -> void:
	# 50° — ещё пол (подъём на верхнюю кромку без прыжка), 62° — стена
	# (максимальный угол ходьбы ~50°; круче — только механики).
	for deg: float in [RAMP_WALK_DEG, RAMP_WALL_DEG]:
		var world := Node3D.new()
		add_child_autofree(world)
		_floor_box(world, 44.0)
		var theta := deg_to_rad(deg)
		var ramp_top := Vector2(13.0 * cos(theta), 26.0 * sin(theta))
		var bottom: Vector2 = _ramp_from_top(world, ramp_top, 180.0 + deg)
		var player := _spawn(world, Vector3(bottom.x - 2.0, 0.1, 0.0))
		await _settle(20)
		var walker := _walker()
		walker.setup(player)
		player._bot = walker
		walker.target = Vector3(ramp_top.x + 3.0, ramp_top.y, 0.0)
		walker.active = true
		var reached := false
		for i: int in _frames(12.0):
			await get_tree().physics_frame
			# Вершина рампы, не «за рампой»: боковой обход тонкой рампы
			# по плоскому полу тоже даёт нужный X — проверяем и высоту.
			if player.global_position.x > ramp_top.x - 0.4 \
					and player.global_position.y > ramp_top.y - 0.6 \
					and player.is_on_floor():
				reached = true
				break
		if deg == RAMP_WALK_DEG:
			assert_true(reached, "рампа 50° проходится шагом, без прыжка")
		else:
			assert_false(reached,
				"рампа 62° — стена: пешеходом не пройти (угол хода ~50°)")
		_release(player, walker)


func test_constant_speed_uphill() -> void:
	# Бег в гору 40°: горизонтальная скорость на рампе — не ниже доли
	# UPHILL_SPEED_MIN_SHARE от беговой (до доработки — cos²θ ≈ 0.58).
	var world := Node3D.new()
	add_child_autofree(world)
	_floor_box(world, 44.0)
	var deg: float = 40.0
	var theta := deg_to_rad(deg)
	_ramp_from_top(world, Vector2(13.0 * cos(theta), 26.0 * sin(theta)), 180.0 + deg)
	var player := _spawn(world, Vector3(-14.0, 0.1, 0.0))
	await _settle(20)
	var walker := _walker()
	walker.setup(player)
	player._bot = walker
	walker.target = Vector3(16.0, 0.0, 0.0)
	walker.active = true
	var start_x := -8.0
	var end_x := 8.0
	var started := false
	var frames := 0
	for i: int in _frames(15.0):
		await get_tree().physics_frame
		var x: float = player.global_position.x
		if not started and x >= start_x:
			started = true
			frames = 0
		if started:
			frames += 1
			if x >= end_x:
				break
	assert_true(started, "дошли до начала замера")
	var seconds: float = float(frames) / float(Engine.physics_ticks_per_second)
	var speed: float = (end_x - start_x) / seconds
	assert_gt(speed, B.run_speed * UPHILL_SPEED_MIN_SHARE,
		"подъём 40°: горизонтальная скорость %.1f м/с ≥ %.1f (бег без замедления)"
		% [speed, B.run_speed * UPHILL_SPEED_MIN_SHARE])
	assert_lt(speed, B.run_speed * 1.6,
		"подъём не быстрее разумного предела (%.1f м/с)" % speed)
	_release(player, walker)


func test_no_bounce_at_crest() -> void:
	# Гребень: подъём 35° сразу в спуск 35°. Перешагивание гребня —
	# без отрыва от земли: персонаж «прилипает», не подпрыгивает на рёбрах.
	var world := Node3D.new()
	add_child_autofree(world)
	_floor_box(world, 44.0)
	var deg: float = 35.0
	var theta := deg_to_rad(deg)
	var crest_y: float = 13.0 * sin(theta)
	# Западный склон (подъём в +X к гребню) и восточный (спуск в +X):
	# у обоих верхняя кромка — гребень (0, 13·sin).
	_ramp_from_top(world, Vector2(0.0, crest_y), 180.0 + deg)
	_ramp_from_top(world, Vector2(0.0, crest_y), -deg)
	var player := _spawn(world, Vector3(-14.0, 0.1, 0.0))
	await _settle(20)
	var walker := _walker()
	walker.setup(player)
	player._bot = walker
	walker.target = Vector3(14.0, 0.0, 0.0)
	walker.active = true
	var floor_frames := 0
	var total := 0
	var max_height := 0.0
	var crossed := false
	for i: int in _frames(15.0):
		await get_tree().physics_frame
		var x: float = player.global_position.x
		if x > -9.0 and x < 9.0:
			total += 1
			if player.is_on_floor():
				floor_frames += 1
			max_height = maxf(max_height, player.global_position.y)
			if x > 8.5:
				crossed = true
				break
	assert_true(crossed, "гребень пройден")
	var share: float = float(floor_frames) / float(maxi(total, 1))
	assert_gt(share, FLOOR_CONTACT_MIN_SHARE,
		"контакт с землёй ≥ %.0f%% кадров (факт %.0f%%)" % [
			FLOOR_CONTACT_MIN_SHARE * 100.0, 100.0 * share])
	assert_lt(max_height, crest_y + 0.35,
		"над гребнем не подскакивает (%.2f м против %.2f)" % [max_height, crest_y])
	_release(player, walker)


func test_auto_step_is_small_steps_only() -> void:
	# Авто-шаг ~0.3 м: ступень 0.3 м проходится шагом, 0.5 м — нет.
	for height: float in [0.3, 0.5]:
		var world := Node3D.new()
		add_child_autofree(world)
		_floor_box(world, 44.0)
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(6.0, height, 4.0)
		shape.shape = box
		body.add_child(shape)
		body.position = Vector3(0.0, height * 0.5, 0.0)
		world.add_child(body)
		var player := _spawn(world, Vector3(-4.0, 0.1, 0.0))
		await _settle(20)
		var walker := _walker()
		walker.setup(player)
		player._bot = walker
		walker.target = Vector3(2.0, 0.0, 0.0)
		walker.active = true
		var stepped := false
		for i: int in _frames(6.0):
			await get_tree().physics_frame
			if player.global_position.y > height - 0.05 \
					and player.global_position.x > -0.8:
				stepped = true
				break
		if height <= 0.31:
			assert_true(stepped, "ступень 0.3 м — заход шагом (авто-шаг)")
		else:
			assert_false(stepped, "ступень 0.5 м шагом не берётся")
		_release(player, walker)


# --- Остров: вершины холмов, смотровые, расщелина ---

## Вершины зоны «Холмы»: локальные максимумы карты высот (окно ±5 м,
## высота ≥ 6 м, внутри круга зоны, не на смотровых) с разводкой не ближе
## 14 м; плюс кольца-основания четырёх смотровых — холмы, на которых
## стоят смотровые, тоже обязаны быть проходимы пешком.
func _hill_targets() -> Array[Vector3]:
	var heights: PackedFloat32Array = ART.heights
	var found: Array[Vector3] = []
	for z: int in range(-100, 101):
		for x: int in range(-100, 101):
			if Vector2(float(x) + 58.0, float(z) - 42.0).length() > 42.0:
				continue
			var here: float = heights[(z + IslandGen.HALF) * IslandGen.POINTS + x + IslandGen.HALF]
			if here < 6.0:
				continue
			var near_lookout := false
			for center: Vector2i in IslandGen.LOOKOUTS:
				if Vector2(float(center.x) - float(x), float(center.y) - float(z)).length() < 5.0:
					near_lookout = true
					break
			if near_lookout:
				continue
			var is_max := true
			for dz: int in range(-5, 6):
				for dx: int in range(-5, 6):
					if heights[(z + dz + IslandGen.HALF) * IslandGen.POINTS + x + dx + IslandGen.HALF] > here:
						is_max = false
						break
				if not is_max:
					break
			if not is_max:
				continue
			var separated := true
			for peak: Vector3 in found:
				if Vector2(peak.x - float(x), peak.z - float(z)).length() < 14.0:
					separated = false
					break
			if separated:
				found.append(Vector3(float(x), here, float(z)))
	for center: Vector2i in IslandGen.LOOKOUTS:
		found.append(Vector3(float(center.x), 0.0, float(center.y) + 4.5))
	return found


## Прогон одного отрезка пути: идёт к цели, возвращает {reached, bounce_share,
## max_vy, max_height}. Останавливается по прибытии (1.6 м и на земле).
## bounce_share — доля кадров ПОДСКОКОВ: потерь контакта с землёй, в которых
## персонаж поднимался выше точки отрыва (> 0.15 м). Честные падения с
## кромок рельефа (y только убывает) и однотиковые швы треугольников —
## нормальная физика, привязка к поверхности их не должна убирать.
func _walk_leg(player: Player, walker: Walker, target: Vector3, seconds: float) -> Dictionary:
	walker.target = target
	walker.active = true
	var frames_on_floor: Array[bool] = []
	var heights: Array[float] = []
	var max_vy := -100.0
	var max_height := -100.0
	for i: int in _frames(seconds):
		await get_tree().physics_frame
		frames_on_floor.append(player.is_on_floor())
		heights.append(player.global_position.y)
		max_vy = maxf(max_vy, player.velocity.y)
		max_height = maxf(max_height, player.global_position.y)
		var flat := Vector2(
			player.global_position.x - target.x,
			player.global_position.z - target.z)
		if flat.length() < 1.6 and player.is_on_floor():
			break
	# Разметка бурстов потери контакта: кадр «плохой», если в его бурсте
	# высота поднималась выше точки отрыва.
	var bad: PackedInt32Array = []
	var i := 0
	while i < frames_on_floor.size():
		if frames_on_floor[i]:
			i += 1
			continue
		var j := i
		var top := heights[i]
		while j < frames_on_floor.size() and not frames_on_floor[j]:
			top = maxf(top, heights[j])
			j += 1
		if top - heights[i] > 0.15:
			for k: int in range(i, j):
				bad.append(k)
		i = j
	var total: int = frames_on_floor.size()
	return {
		"reached": Vector2(
			player.global_position.x - target.x,
			player.global_position.z - target.z).length() < 1.6,
		"bounce_share": float(bad.size()) / float(maxi(total, 1)),
		"max_vy": max_vy,
		"max_height": max_height,
	}


func test_bot_climbs_every_hill_and_descends() -> void:
	# Бот без прыжков: на вершину КАЖДОГО холма зоны «Холмы» и обратно;
	# по пути — контакт с землёй (привязка к поверхности) и вертикальная
	# скорость в гравитационных пределах (прыжков нет).
	var island := ISLAND.instantiate() as Island
	add_child_autofree(island)
	var walker := _walker()
	var targets: Array[Vector3] = _hill_targets()
	assert_gt(targets.size(), 4,
		"вершин и смотровых колец для проверки достаточно (%d)" % targets.size())
	for target: Vector3 in targets:
		var to_plaza := (Vector2(0.0, 4.0)
			- Vector2(target.x, target.z)).normalized()
		var base_xz: Vector2 = Vector2(target.x, target.z) + to_plaza * 16.0
		var base := Vector3(
			base_xz.x,
			TerrainBuilder.height_at(ART.heights, base_xz.x, base_xz.y) + 0.4,
			base_xz.y)
		var player := _spawn(island, base)
		await _settle(30)
		walker.setup(player)
		player._bot = walker
		var up: Dictionary = await _walk_leg(player, walker, target, LEG_TIME)
		assert_true(bool(up["reached"]),
			"вершина %s достигнута пешком (без прыжков)" % target)
		assert_lt(float(up["max_vy"]), NO_JUMP_VY,
			"подъём к %s без прыжка (макс vy %.1f)" % [target, float(up["max_vy"])])
		assert_lt(float(up["bounce_share"]), 1.0 - FLOOR_CONTACT_MIN_SHARE,
			"подъём к %s: без подскоков над рельефом (факт %.0f%%)" % [
				target, 100.0 * float(up["bounce_share"])])
		var down: Dictionary = await _walk_leg(player, walker, base, LEG_TIME)
		assert_true(bool(down["reached"]), "спуск с %s к подошве прошёл пешком" % target)
		assert_lt(float(down["bounce_share"]), 1.0 - FLOOR_CONTACT_MIN_SHARE,
			"спуск с %s: прилипание к поверхности, без подскоков (факт %.0f%%)" % [
				target, 100.0 * float(down["bounce_share"])])
		_release(player, walker)


func test_lookout_ledges_not_climbable_on_foot() -> void:
	# Смотровые уступы (+3 м): с кольца-основания бот идёт к центру
	# площадки — и не попадает на неё без подсадки (стены кольца и уступ).
	var island := ISLAND.instantiate() as Island
	add_child_autofree(island)
	var walker := _walker()
	for center: Vector2i in IslandGen.LOOKOUTS:
		var start := Vector3(
			float(center.x), IslandGen.LOOKOUT_BASE_H + 0.4, float(center.y) + 5.5)
		var player := _spawn(island, start)
		await _settle(30)
		walker.setup(player)
		player._bot = walker
		var leg: Dictionary = await _walk_leg(player, walker,
			Vector3(float(center.x), IslandGen.LOOKOUT_TOP_H, float(center.y)), 10.0)
		assert_false(bool(leg["reached"]),
			"смотровая %s: на площадку без подсадки не попасть" % center)
		assert_lt(float(leg["max_height"]), IslandGen.LOOKOUT_TOP_H - 0.6,
			"смотровая %s: максимальная высота %.2f (площадка %.1f недостижима)"
			% [center, float(leg["max_height"]), IslandGen.LOOKOUT_TOP_H])
		_release(player, walker)


func test_crevasse_walls_not_walkable() -> void:
	# Стенки расщелины: бот идёт через каньон вне мостков — на ту сторону
	# пешеходом не попасть: падает внутрь и зависает на HangPoint (механика),
	# но не переходит каньон по стенке.
	var island := ISLAND.instantiate() as Island
	add_child_autofree(island)
	# X = 70 — вне мостков (BRIDGE_X = 33, 52).
	var start := Vector3(
		70.0, IslandGen.CREVASSE_RIM_H + 1.0, float(IslandGen.CREVASSE_Z1 + 6))
	var player := _spawn(island, start)
	await _settle(30)
	var walker := _walker()
	walker.setup(player)
	player._bot = walker
	walker.target = Vector3(
		70.0, IslandGen.CREVASSE_RIM_H, float(IslandGen.CREVASSE_Z0 - 6))
	walker.active = true
	for i: int in _frames(9.0):
		await get_tree().physics_frame
		if player.is_hanging():
			pass_test("расщелина: упал и повис на HangPoint — пешеходом не пройти")
			_release(player, walker)
			return
		if player.global_position.z < float(IslandGen.CREVASSE_Z0 - 1.0):
			fail_test("перешёл расщелину пешком по стенке")
			_release(player, walker)
			return
	assert_gt(player.global_position.z, float(IslandGen.CREVASSE_Z0 - 1.0),
		"на северную сторону пешеходом не перейти")
	_release(player, walker)
