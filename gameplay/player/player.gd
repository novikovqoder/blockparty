# Персонаж игрока (раздел 5 SPEC): CharacterBody3D (капсула 0.35 × 1.6 м),
# движение относительно камеры (бег/шаг, ускорение/торможение, 60% в воздухе),
# прыжок с coyote time, буфером и переменной высотой, автоподъём на полублоки,
# плавание на поверхности, состояние «Висит» с переносом к Камню духа, удар
# («тычок» по игрокам, мобы — один удар, раздел 8).
# Игроки проходят друг сквозь друга: маска не содержит слой игроков.
# Кооп-механики Blockparty (подсадка на голову, вытягивание, «за руку»)
# удалены с наследием (born-unblessed).
class_name Player
extends CharacterBody3D

const B: Balance = preload("res://gameplay/balance.tres")

## Группа узлов персонажей (для площадок, удара и будущих снапшотов).
const GROUP: StringName = &"player"
## Насколько ниже точки HangPoint висит центр тела, м.
const HANG_BODY_DROP: float = 0.2
## Глубина проверки автоподъёма вперёд, м.
const STEP_PROBE: float = 0.35
## Кулдаун после отклонённого авто-шага, с (сруб Kless): повтор «вверх-
## вперёд-вниз» у высокой стены каждый тик вжимал персонажа в стену.
const STEP_FAIL_COOLDOWN: float = 0.25

@onready var model: Node3D = $Model
@onready var visual: CharacterVisual = $Model/Visual
@onready var camera: PlayerCamera = $CameraRig
@onready var attack_area: Area3D = $AttackArea

## Публичное состояние для снапшотов П3.
var _anim: int = Protocol.AnimState.IDLE

## Бот --bot заменяет ввод (раздел 18: бродит между POI, прыгает, бьёт мобов).
var _bot: BotController = null

var _coyote: float = 0.0
var _jump_buffer: float = 0.0
var _step_fail_left: float = 0.0
var _jump_cut_done: bool = false
## Прыжок выполнен в текущем кадре (анти-подскок на гребнях его не гасит).
var _jumped: bool = false
var _was_on_floor: bool = true
var _attack_cooldown: float = 0.0
var _attack_active: float = 0.0
var _hanging: bool = false
var _hang_left: float = 0.0
var _in_water: bool = false
var _water_level: float = 0.0
## Ближайший интерактивный объект (подсказка HUD, удержание E; П5).
var _interactable: Interactable = null
## Накопленное удержание E у объекта с hold_time > 0, с.
var _hold_accum: float = 0.0
## Характеристики (Сила/Скорость/Прыжок) убраны — П5.8, часть D: все
## игроки равны, множителей бега/прыжка/кооп-действий нет.
## Точка, за которую висим (куда поднимет вытягивание; раздел 9.1).
var _hang_point: Vector3 = Vector3.ZERO
## Частицы из-под ног (переделка П9): порция в момент шага по покрытию.
var _foot_fx: FootFx = null


func _ready() -> void:
	add_to_group(GROUP)
	# Слой 2 — игроки (для Area3D: удар), маска — только мир: игроки
	# проходят друг сквозь друга (раздел 5).
	collision_layer = 2
	collision_mask = 1
	# Ходьба по склонам (доработка-2 П5.13, П2): пологие склоны холмов
	# (включая крутые диагонали ~52°) — пол, отвесные кромки и скалы — стена.
	floor_max_angle = deg_to_rad(B.walk_max_slope_deg)
	floor_snap_length = B.floor_snap_length
	# Player — всегда локальный игрок (RemotePlayer отдельно): с него Net
	# берёт снапшоты и позицию для проверок хоста (раздел 10).
	Net.register_local_player(self)
	if Session.bot:
		_bot = BotController.new()
		_bot.setup(self)
		add_child(_bot)
	# Частицы из-под ног (переделка П9): ребёнок самого игрока (origin
	# в ногах — землю под стопой берём из позиции владельца); порции по
	# шагам включит setup_foot_fx (сцена мира передаст арт острова).
	_foot_fx = FootFx.new()
	_foot_fx.name = "FootFx"
	add_child(_foot_fx)


func _physics_process(delta: float) -> void:
	_jumped = false
	if _hanging:
		_process_hang(delta)
		_update_interaction(delta)
		return
	_attack_cooldown = maxf(_attack_cooldown - delta, 0.0)
	_step_fail_left = maxf(_step_fail_left - delta, 0.0)
	if _attack_active > 0.0:
		_attack_active -= delta
		if _attack_active <= 0.0:
			_end_attack()

	var wish := _wish_direction()
	_move_horizontally(wish, delta)
	_apply_gravity_or_buoyancy(delta)
	_update_jump(delta)
	_limit_slope_climb()
	var was_floor := is_on_floor()
	move_and_slide()
	# Анти-подскок на гребнях (доработка-2 П5.13, П2): срыв с пола без
	# прыжка не должен подбрасывать — восходящая скорость гасится, и
	# floor_snap возвращает на поверхность (бег через гребень без
	# подпрыгивания на рёбрах).
	if was_floor and not is_on_floor() and velocity.y > 0.0 and not _jumped:
		velocity.y = 0.0
	# Авто-шаг — и на ходу, и из неподвижного упора в ступень: скорость
	# у стены гасится проекцией на направление вдоль стены, и у порога
	# сруба (лесенка 0.16→0.64) персонаж с прижатой скоростью <1 м/с
	# не мог взять ступень 0.18 м никогда (сруб Kless). Дребезг у высоких
	# стен гасит не порог скорости, а кулдаун отклонённого шага в
	# _try_step_up (поднялся — принят, нет — откат и пауза).
	if was_floor and is_on_floor() and is_on_wall():
		_try_step_up(wish)
	_update_animation()
	_turn_model(wish, delta)
	if _attack_pressed():
		_try_attack()
	_update_interaction(delta)


# --- Взаимодействие E (раздел 9, П5) ---

## Подсказка «E — …» и удержание: ищем ближайший доступный объект группы
## Interactable.GROUP; короткое нажатие E или полное удержание вызывает use().
func _update_interaction(delta: float) -> void:
	var nearest: Interactable = null
	if not _hanging:
		nearest = _nearest_interactable()
	if nearest != _interactable:
		_interactable = nearest
		_hold_accum = 0.0
	if _interactable == null:
		EventBus.interaction_hint.emit("")
		EventBus.interaction_progress.emit(-1.0)
		return
	EventBus.interaction_hint.emit(_interactable.hint_key())
	var hold: float = _interactable.hold_time(self)
	var human: bool = _bot == null
	if hold <= 0.0:
		EventBus.interaction_progress.emit(-1.0)
		if human and Input.is_action_just_pressed("interact"):
			_interactable.use(self)
		return
	# Удержание: копим, пока E зажат; отпускание сбрасывает прогресс.
	if human and Input.is_action_pressed("interact"):
		_hold_accum += delta
		EventBus.interaction_progress.emit(clampf(_hold_accum / hold, 0.0, 1.0))
		if _hold_accum >= hold:
			_hold_accum = 0.0
			EventBus.interaction_progress.emit(-1.0)
			_interactable.use(self)
	else:
		_hold_accum = 0.0
		EventBus.interaction_progress.emit(-1.0)


## Ближайший доступный объект в радиусе use_radius (от груди персонажа).
func _nearest_interactable() -> Interactable:
	var best: Interactable = null
	var best_distance: float = 1e9
	var chest := global_position + Vector3.UP * 0.8
	for node in get_tree().get_nodes_in_group(Interactable.GROUP):
		var interactable := node as Interactable
		if interactable == null or not is_instance_valid(interactable):
			continue
		if interactable.hint_key().is_empty():
			continue
		var distance: float = interactable.global_position.distance_to(chest)
		if distance > interactable.use_radius:
			continue
		if distance < best_distance:
			best_distance = distance
			best = interactable
	return best


# --- Движение ---

## Направление ввода в мире: относительно камеры, в плоскости земли.
## Бот (--bot) задаёт направление сам — куда идти.
func _wish_direction() -> Vector3:
	if _bot != null:
		return _bot.wish_direction()
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var forward := camera.forward_flat()
	var right := Vector3(-forward.z, 0.0, forward.x)
	return (forward * -input.y + right * input.x)


## Однократный ввод прыжка/удара: клавиатура или бот.
func _jump_pressed() -> bool:
	if _bot != null:
		return _bot.consume_jump()
	return Input.is_action_just_pressed("jump")


func _jump_held() -> bool:
	if _bot != null:
		return _bot.jump_held()
	return Input.is_action_pressed("jump")


func _attack_pressed() -> bool:
	if _bot != null:
		return _bot.consume_attack()
	return Input.is_action_just_pressed("attack")


func _move_horizontally(wish: Vector3, delta: float) -> void:
	var walking: bool = Input.is_action_pressed("walk") if _bot == null else false
	var speed: float = B.walk_speed if walking else B.run_speed
	if _in_water:
		# Плавание медленнее бега (раздел 6): одна скорость для всех.
		speed = minf(speed, B.swim_speed)
	var target := wish.limit_length(1.0) * speed
	# Ходьба по склонам (доработка-2 П5.13, П2) — два эффекта физики:
	# 1) горизонтальная скорость, направленная «в» склон, скользит по
	#    плоскости пола и теряет горизонтальный ход до v·cos²θ — бег в гору
	#    замедлялся почти вдвое. Цель проецируется на плоскость пола и
	#    масштабируется до полной горизонтальной скорости (предел
	#    slope_speed_comp_max), включая вертикальную тягу вдоль склона;
	#    тяга — только в подъём, у гребней и на спуске ведёт гравитация.
	# 2) наклонная СТЕНА (круче walk_max_slope_deg) — «эскалатор»: давление
	#    в неё move_and_slide переизлучает вверх по касательной, персонаж
	#    вылезал по отвесным кромкам пешеходом. Составляющая давления в
	#    стену гасится — остаётся скольжение вдоль стены по горизонтали.
	var uphill := false
	if not _in_water:
		if is_on_floor():
			var normal := get_floor_normal()
			var into: float = target.dot(normal)
			if into < -0.01:
				var along: Vector3 = target - normal * into
				var horiz: float = Vector2(along.x, along.z).length()
				var wanted: float = Vector2(target.x, target.z).length()
				if horiz > 0.01 and wanted > 0.01:
					target = along * minf(wanted / horiz, B.slope_speed_comp_max)
					# Крутые склоны: вертикальная часть тяги не прыжковая
					# (v·tanθ у 54° догоняет прыжок — срезаем до предела,
					# подъём становится чуть медленнее полной скорости).
					if target.y > B.slope_climb_vy_max:
						target *= B.slope_climb_vy_max / target.y
					uphill = true
		if is_on_wall():
			var wall_normal := get_wall_normal()
			if target.dot(wall_normal) < -0.001:
				var along_wall := Vector3(
					-wall_normal.z, 0.0, wall_normal.x).normalized()
				target = along_wall * maxf(target.dot(along_wall), 0.0)
	var accel: float = B.deceleration if target == Vector3.ZERO else B.acceleration
	if not is_on_floor() and not _in_water:
		accel *= B.air_control
	velocity.x = move_toward(velocity.x, target.x, accel * delta)
	velocity.z = move_toward(velocity.z, target.z, accel * delta)
	if uphill:
		velocity.y = move_toward(velocity.y, target.y, accel * delta)


## Излишек вертикальной тяги срезается по ТЕКУЩЕМУ наклону пола
## (доработка-2 П5.13, П2). Тяга в гору нужна ровно в размере
## «горизонтальный ход × тангенс уклона» — на выполаживании у гребня
## прежние 5 м/с держались по инерции и подбрасывали персонажа над
## землёй на четверть секунды. Мгновенная срезка держит его на склоне.
func _limit_slope_climb() -> void:
	if _jumped or _in_water or not is_on_floor() or velocity.y <= 0.0:
		return
	var normal := get_floor_normal()
	var tan_a: float = sqrt(maxf(1.0 - normal.y * normal.y, 0.0)) \
		/ maxf(normal.y, 0.05)
	var cap: float = minf(
		Vector2(velocity.x, velocity.z).length() * tan_a,
		B.slope_climb_vy_max)
	if velocity.y > cap:
		velocity.y = cap


func _apply_gravity_or_buoyancy(delta: float) -> void:
	if _in_water and velocity.y <= 0.5:
		# Плавание на поверхности (раздел 6): тело держится погружённым
		# на swim_submerge (origin — в ногах, коллайдер поднят внутри
		# сцены), вертикальная скорость ограничена.
		var target_y: float = _water_level - B.swim_submerge
		velocity.y = clampf(
			(target_y - global_position.y) * B.swim_buoyancy,
			-B.swim_vertical_speed, B.swim_vertical_speed,
		)
	else:
		velocity.y = JumpMath.step_vertical(velocity.y, delta, B)


func _update_jump(delta: float) -> void:
	if is_on_floor():
		_coyote = B.coyote_time
	else:
		_coyote = maxf(_coyote - delta, 0.0)
	if _jump_pressed():
		_jump_buffer = B.jump_buffer_time
	else:
		_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	if _jump_buffer > 0.0 and (_coyote > 0.0 or _in_water):
		velocity.y = B.jump_speed
		_jump_buffer = 0.0
		_jumped = true
		_coyote = 0.0
		_jump_cut_done = false
		# Порция в толчке прыжка (переделка П9): по покрытию под ногами,
		# чуть больше обычного шага.
		_foot_fx.jump(Vector2(velocity.x, velocity.z).length())
	# Переменная высота: отпускание режет вертикальную скорость (один раз).
	if not _jump_held() and not _jump_cut_done:
		velocity.y = JumpMath.jump_cut(velocity.y, B)
		_jump_cut_done = true


## Автоподъём на ступеньку до step_up_height: вверх, вперёд, вниз. Встать
## выше старта получилось — шаг принят; впереди стена выше ступени —
## позиция откатывается к исходной, персонаж остаётся у стены без
## подскоков (доработка-2 П5.13, П2). Отклонённый шаг — кулдаун
## STEP_FAIL_COOLDOWN (сруб Kless): у высокой стены цикл «поднялся-упал»
## из каждого тика вжимал персонажа в стену, теперь повторы редкие.
## Вызов — и из неподвижного упора: прежний порог скорости 1.0 м/с
## замыкал у ступеней (скорость у стены гасится проекцией вдоль стены —
## лесенка порога сруба 0.18 м не бралась никогда).
func _try_step_up(wish: Vector3) -> void:
	if wish.length() < 0.1:
		return
	if _step_fail_left > 0.0:
		return
	var before := global_position
	var dir := wish.normalized()
	var up := move_and_collide(Vector3.UP * B.step_up_height)
	var lifted: float = B.step_up_height if up == null \
		else B.step_up_height - up.get_remainder().length()
	move_and_collide(dir * STEP_PROBE)
	move_and_collide(Vector3.DOWN * (lifted + 0.01))
	if global_position.y < before.y + 0.05:
		global_position = before
		velocity.y = 0.0
		_step_fail_left = STEP_FAIL_COOLDOWN


# --- Удар (раздел 5) ---

func _try_attack() -> void:
	if _attack_cooldown > 0.0:
		return
	_attack_cooldown = B.attack_cooldown
	_attack_active = B.attack_active_time
	attack_area.monitoring = true
	# Взмах при ударе: UBC — та же анимация «Привет!» (мах рукой, раздел 5),
	# герой BU — замах мечом ss_slash (П10).
	visual.play_attack(0.25)


func _end_attack() -> void:
	# Пересечения читаем, пока monitoring включён: после выключения
	# get_overlapping_* пуст (и ругается в консоль движка).
	var bodies := attack_area.get_overlapping_bodies()
	attack_area.monitoring = false
	# По игрокам — только визуальный «тычок» (раздел 5). Мобы (раздел 8)
	# удалены в доработке П5.13 — удар больше никого не убивает.
	for body in bodies:
		if body is Player and body != self:
			(body as Player).receive_bonk()


func receive_bonk() -> void:
	visual.play_one_shot(Protocol.AnimState.BONK, B.bonk_time)


# --- Состояние «Висит» (раздел 9.1; вытягивание другим игроком — П5) ---

## Зацепиться за точку HangPoint (вызывает HangArea при падении в расщелину).
func start_hang(point: Vector3) -> void:
	if _hanging:
		return
	_hanging = true
	_hang_left = B.hang_time
	_hang_point = point
	velocity = Vector3.ZERO
	global_position = point + Vector3(0.0, -HANG_BODY_DROP, 0.0)
	_set_anim(Protocol.AnimState.HANG)
	EventBus.player_hang_started.emit(B.hang_time)
	Log.info("Висит у края (%.1f с)" % B.hang_time, "Player")


## Висит ли у края расщелины (флаг снапшота, раздел 10).
func is_hanging() -> bool:
	return _hanging


func _process_hang(delta: float) -> void:
	_hang_left -= delta
	EventBus.player_hang_updated.emit(maxf(_hang_left, 0.0))
	if _hang_left <= 0.0:
		_respawn()


## Перенос к ближайшему Камню духа без штрафа (раздел 9.1; камней на острове
## несколько — по одному на зону).
func _respawn() -> void:
	_hanging = false
	velocity = Vector3.ZERO
	var stone := _nearest_stone()
	if stone != null:
		global_position = stone.global_position + Vector3(0.0, 1.0, 0.0)
	_set_anim(Protocol.AnimState.IDLE)
	EventBus.player_hang_ended.emit()
	EventBus.player_respawned.emit()
	Log.info("Перенос к Камню духа", "Player")


func _nearest_stone() -> Node3D:
	var best: Node3D = null
	var best_distance: float = 1e9
	for node in get_tree().get_nodes_in_group(RespawnStone.GROUP):
		if node is Node3D:
			var distance: float = (node as Node3D).global_position.distance_squared_to(global_position)
			if distance < best_distance:
				best_distance = distance
				best = node
	return best


# --- Вода (раздел 6) ---

func enter_water(level: float) -> void:
	_in_water = true
	_water_level = level


func exit_water() -> void:
	_in_water = false


func in_water() -> bool:
	return _in_water


# --- Модель и анимации ---

## Подключить частицы шагов к острову: сцена мира передаёт запечённый
## арт — по нему FootFx берёт покрытие и цвет поверхности под стопой.
func setup_foot_fx(art: IslandArt) -> void:
	_foot_fx.setup(art)


func _update_animation() -> void:
	var hspeed := Vector2(velocity.x, velocity.z).length()
	if not _was_on_floor and is_on_floor():
		# Приземление (Д2, этап 0): поза ленда — статичный присед, при
		# скорости она едет по земле = то самое скольжение после прыжка.
		# На ходу/бегу ленд не играем вовсе — сразу локомоция по фактической
		# скорости кросс-фейдом ANIM_BLEND (0.15 с); Jump_Land остаётся
		# приземлению почти в стойку (скорость ≈ anim_idle_speed).
		if hspeed <= B.anim_idle_speed:
			visual.play_one_shot(Protocol.AnimState.LAND, B.land_time)
		# Порция при приземлении (переделка П9): той же системой шагов,
		# по покрытию и чуть больше обычной (было — Fx.puff).
		_foot_fx.land(hspeed)
	var moving := hspeed > B.anim_idle_speed
	if _in_water:
		_set_anim(Protocol.AnimState.WALK if moving else Protocol.AnimState.IDLE)
	elif not is_on_floor():
		_set_anim(Protocol.AnimState.JUMP if velocity.y > 0.0 else Protocol.AnimState.FALL)
	elif moving:
		# Ходьба/бег — по фактической скорости (Д2/Д3), не по вводу:
		# сам клип (Walk/Jog/Sprint) и каденцию модель выбирает по скорости.
		_set_anim(Protocol.AnimState.WALK if hspeed < B.anim_walk_run_speed
			else Protocol.AnimState.RUN)
	else:
		_set_anim(Protocol.AnimState.IDLE)
	# Темп ног (Д3): фактическая скорость.
	visual.set_locomotion_speed(hspeed)
	# Частицы из-под ног (переделка П9): детект шагов по костям стоп;
	# в воде их нет (там круги Fx.water_ring), в воздухе — тоже.
	_foot_fx.update(hspeed, is_on_floor() and not _in_water, global_position)
	_was_on_floor = is_on_floor()


func _set_anim(state: int) -> void:
	if state == _anim:
		return
	_anim = state
	visual.set_state(state)


## Плавный поворот модели к направлению движения (раздел 5), лицом в +Z.
func _turn_model(wish: Vector3, delta: float) -> void:
	var direction := wish if wish.length() > 0.1 else Vector3(velocity.x, 0.0, velocity.z)
	if direction.length() < 0.1:
		return
	var target_yaw := atan2(direction.x, direction.z)
	model.rotation.y = lerp_angle(model.rotation.y, target_yaw, B.model_turn_speed * delta)


# --- Экспорт состояния для снапшотов (П3) ---

func anim_state() -> int:
	return _anim


func model_yaw() -> float:
	return model.rotation.y


func snapshot_flags() -> int:
	var flags := 0
	if is_on_floor():
		flags |= Protocol.FLAG_ON_FLOOR
	if _hanging:
		flags |= Protocol.FLAG_HANGING
	return flags


## Точки интереса для бота (задаёт сцена мира: зоны, камни духа).
func set_bot_targets(points: Array) -> void:
	if _bot != null:
		_bot.set_targets(points)
