# Контроллер локального игрока: движение и физика из раздела 4 SPEC,
# атака, неуязвимость после шипов, состояние «Висит» (раздел 7.1).
# Владелец персонажа авторитетен над его движением; подтверждения событий
# (мобы, монеты) уходят через EventBus — в сетевом режиме их решает хост.
# Ввод приходит с клавиатуры/геймпада или от бота (--bot, BotController);
# состояние для снапшота 20 Гц отдаёт get_anim_state()/get_flags().
# Не делает: эмоции (этап 3).
class_name Player
extends CharacterBody2D

const B: Balance = preload("res://gameplay/balance.tres")

enum State { NORMAL, HANGING }

@onready var visual: Node2D = $Visual
@onready var attack_area: Area2D = $AttackArea
@onready var camera: Camera2D = $Camera

## Управление разрешено после стартового отсчёта (EventBus.run_go).
var control_enabled: bool = false

var _state: State = State.NORMAL
var _facing: int = 1
var _coyote_left: float = 0.0
var _jump_buffer_left: float = 0.0
var _attack_cooldown_left: float = 0.0
var _attack_active_left: float = 0.0
var _invuln_left: float = 0.0
var _hang_left: float = 0.0
var _was_on_floor: bool = true
var _prev_jump_held: bool = false
var _hit_targets: Array[int] = []  # spawn_id мобов, задетых текущим ударом
var _bot: BotController = null


func _ready() -> void:
	attack_area.area_entered.connect(_on_attack_area_entered)
	attack_area.monitoring = false
	EventBus.hang_started.connect(_on_hang_started)
	EventBus.hang_ended.connect(_on_hang_ended)
	EventBus.run_go.connect(_on_run_go)
	EventBus.run_finished.connect(_on_run_finished)
	if Session.bot:
		_bot = BotController.new()
		_bot.setup(self)
		add_child(_bot)


func _physics_process(delta: float) -> void:
	match _state:
		State.HANGING:
			_process_hanging(delta)
		State.NORMAL:
			_process_normal(delta)


func _process_normal(delta: float) -> void:
	_tick_timers(delta)
	_apply_horizontal(delta)
	_apply_gravity(delta)
	_update_coyote(delta)
	_update_jump_buffer(delta)
	_try_jump()
	_try_attack()
	move_and_slide()
	_after_move()


func _process_hanging(delta: float) -> void:
	# Игрок неподвижно висит у края; по таймауту — возврат на чекпоинт.
	velocity = Vector2.ZERO
	_hang_left -= delta
	if _hang_left <= 0.0:
		give_up_hang()


## Разрешить/запретить ввод (отсчёт, конец забега).
func set_control(enabled: bool) -> void:
	control_enabled = enabled


## Ограничить камеру границами собранного уровня (вызывает сцена забега).
func set_camera_limits(right: int) -> void:
	camera.limit_right = right


## Телепорт на чекпоинт (после «Висит»); даём короткую неуязвимость.
func respawn_at(point: Vector2) -> void:
	global_position = point
	velocity = Vector2.ZERO
	_invuln_left = B.hit_invuln_time
	visual.play_idle()


## Прыжок с чужой головы: усиление скорости (механика «ступенька», раздел 4).
func apply_head_jump_bonus() -> void:
	velocity.y = -B.jump_speed * B.head_jump_bonus
	_coyote_left = 0.0
	_jump_buffer_left = 0.0
	visual.play_jump()


## Отталкивание от моба при касании (урона нет, раздел 6).
func push_from(source: Vector2) -> void:
	if _state != State.NORMAL or _invuln_left > 0.0:
		return
	var dir := 1 if global_position.x >= source.x else -1
	velocity.x = dir * B.mob_push_speed
	velocity.y = -B.mob_push_speed * 0.5


## Удар шипов/кактуса: отбрасывание, мигание, неуязвимость (раздел 4).
func apply_hit(source: Vector2) -> void:
	if _state != State.NORMAL or _invuln_left > 0.0:
		return
	_invuln_left = B.hit_invuln_time
	var dir := 1 if global_position.x >= source.x else -1
	velocity = Vector2(dir * B.hazard_knockback_x, -B.hazard_knockback_y)
	visual.play_hit(B.hit_blink_time)
	visual.play_blink(B.hit_blink_time)


## Встать в состояние «Висит» у точки HangPoint (вызывает PitArea).
func enter_hang(point: Vector2) -> void:
	if _state != State.NORMAL:
		return
	_state = State.HANGING
	_hang_left = B.hang_time
	velocity = Vector2.ZERO
	# Держится руками за левый край пропасти: тело в яме, голова над краем.
	global_position = Vector2(
		point.x + B.hitbox_width * 0.25,
		point.y + B.hang_offset_y
	)
	visual.play_hang()
	EventBus.hang_started.emit()


## Досрочный выход из «Висит» (кнопка «Сдаться» или таймаут 8 с).
func give_up_hang() -> void:
	if _state != State.HANGING:
		return
	_state = State.NORMAL
	_invuln_left = B.hit_invuln_time
	visual.play_idle()
	EventBus.hang_ended.emit()  # сцена забега переносит на чекпоинт


func is_hanging() -> bool:
	return _state == State.HANGING


func hang_time_left() -> float:
	return _hang_left


func _on_hang_started() -> void:
	set_control(false)


func _on_hang_ended() -> void:
	if not Session.run_active:
		return
	set_control(true)


func _on_run_go() -> void:
	_state = State.NORMAL
	set_control(true)


func _on_run_finished(_finished: bool, _time: float) -> void:
	# После финиша бегать по площадке можно, счёт уже не идёт.
	set_control(true)


func _tick_timers(delta: float) -> void:
	_attack_cooldown_left = maxf(0.0, _attack_cooldown_left - delta)
	if _attack_active_left > 0.0:
		_attack_active_left -= delta
		if _attack_active_left <= 0.0:
			attack_area.monitoring = false
			_hit_targets.clear()
	_invuln_left = maxf(0.0, _invuln_left - delta)
	if _invuln_left <= 0.0:
		visual.stop_blink()


## Состояние аниматора для снапшота (Protocol.AnimState).
func get_anim_state() -> int:
	if _state == State.HANGING:
		return Protocol.AnimState.HANG
	if _attack_active_left > 0.0:
		return Protocol.AnimState.ATTACK
	if not is_on_floor():
		return Protocol.AnimState.JUMP if velocity.y < 0.0 else Protocol.AnimState.FALL
	if absf(velocity.x) > 20.0:
		return Protocol.AnimState.RUN
	return Protocol.AnimState.IDLE


## Флаги снапшота (раздел 8: направление, на земле, висит, говорит).
func get_flags() -> int:
	var flags: int = 0
	if _facing > 0:
		flags |= Protocol.FLAG_FACING_RIGHT
	if is_on_floor():
		flags |= Protocol.FLAG_ON_FLOOR
	if _state == State.HANGING:
		flags |= Protocol.FLAG_HANGING
	# FLAG_TALKING появится вместе с голосом (этап 5).
	return flags


func _input_axis() -> float:
	if not control_enabled:
		return 0.0
	if _bot != null:
		return _bot.axis()
	return Input.get_axis("move_left", "move_right")


func _jump_just_pressed() -> bool:
	if not control_enabled:
		return false
	if _bot != null:
		return _bot.consume_jump()
	return Input.is_action_just_pressed("jump")


func _jump_held() -> bool:
	if _bot != null:
		return _bot.jump_held()
	return Input.is_action_pressed("jump")


func _attack_pressed() -> bool:
	if not control_enabled:
		return false
	if _bot != null:
		return _bot.consume_attack()
	return Input.is_action_pressed("attack")


func _apply_horizontal(delta: float) -> void:
	var dir := _input_axis()
	var target := dir * B.run_speed
	var accel := B.accel_ground
	if not is_on_floor():
		accel *= B.air_control
	velocity.x = move_toward(velocity.x, target, accel * delta)
	if absf(velocity.x) > 1.0:
		_facing = 1 if velocity.x > 0.0 else -1


func _apply_gravity(delta: float) -> void:
	var g := B.gravity
	if velocity.y > 0.0:
		g *= B.gravity_fall_multiplier
	velocity.y = minf(velocity.y + g * delta, B.max_fall_speed)


func _update_coyote(delta: float) -> void:
	if is_on_floor():
		_coyote_left = B.coyote_time
	else:
		_coyote_left = maxf(0.0, _coyote_left - delta)


func _update_jump_buffer(delta: float) -> void:
	if _jump_just_pressed():
		_jump_buffer_left = B.jump_buffer_time
	else:
		_jump_buffer_left = maxf(0.0, _jump_buffer_left - delta)


func _try_jump() -> void:
	# Переменная высота: отпускание кнопки режет скорость подъёма.
	var held := control_enabled and _jump_held()
	if _prev_jump_held and not held and velocity.y < 0.0:
		velocity.y *= B.jump_cut_factor
	_prev_jump_held = held
	if _jump_buffer_left > 0.0 and _coyote_left > 0.0:
		velocity.y = -B.jump_speed
		_jump_buffer_left = 0.0
		_coyote_left = 0.0
		visual.play_jump()


func _try_attack() -> void:
	if not _attack_pressed():
		return
	if _attack_active_left > 0.0 or _attack_cooldown_left > 0.0:
		return
	_attack_active_left = B.attack_active_time
	_attack_cooldown_left = B.attack_cooldown
	_hit_targets.clear()
	attack_area.monitoring = true
	visual.play_attack()


func _after_move() -> void:
	if is_on_floor() and not _was_on_floor:
		visual.play_land()
	_was_on_floor = is_on_floor()
	visual.set_run_blend(velocity.x / B.run_speed)
	visual.set_facing(_facing)
	# Хитбокс удара всегда перед лицом.
	attack_area.position = Vector2(_facing * (B.hitbox_width * 0.5 + 8.0), 0.0)
	visual.set_attack_side(_facing)
	# Опережение камеры по направлению бега (раздел 4).
	var target_x := _facing * B.camera_lead
	camera.offset.x = lerpf(camera.offset.x, target_x, B.camera_smoothing * get_physics_process_delta_time())


## Один удар не бьёт одного и того же моба дважды.
func _on_attack_area_entered(area: Area2D) -> void:
	var mob := area as Mob
	if mob == null or not mob.alive:
		return
	if mob.spawn_id in _hit_targets:
		return
	_hit_targets.append(mob.spawn_id)
	# Раздел 6: попадание видно локально сразу, подтверждение даёт «хост».
	mob.play_hit_fx()
	EventBus.mob_hit_requested.emit(mob.spawn_id, Session.run_time, global_position)
