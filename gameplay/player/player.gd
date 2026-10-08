# Персонаж игрока (раздел 5 SPEC): CharacterBody3D (капсула 0.35 × 1.6 м),
# движение относительно камеры (бег/шаг, ускорение/торможение, 60% в воздухе),
# прыжок с coyote time, буфером и переменной высотой, автоподъём на полублоки,
# плавание на поверхности, состояние «Висит» с переносом к Камню духа, удар
# («тычок» по игрокам, мобы — один удар, раздел 8), коллайдер головы для
# подсадки (отдельный слой, столкновение только при падении сверху — HeadStand).
# Игроки проходят друг сквозь друга: маска не содержит слой игроков.
# Не делает: снапшоты в сеть (П3 подключит anim_state()/snapshot_flags()),
# вытягивание другим игроком и эмоции (П5), светлячка на двоих (П5).
class_name Player
extends CharacterBody3D

const B: Balance = preload("res://gameplay/balance.tres")

## Группа узлов персонажей (для площадок, удара и будущих снапшотов).
const GROUP: StringName = &"player"
## Насколько ниже точки HangPoint висит центр тела, м.
const HANG_BODY_DROP: float = 0.2
## Голова «под ногами», если её верхняя грань ближе этого, м.
const HEAD_BELOW_EPS: float = 0.15
## Глубина проверки автоподъёма вперёд, м.
const STEP_PROBE: float = 0.35

@onready var model: Node3D = $Model
@onready var visual: CharacterModel = $Model/CharacterModel
@onready var camera: PlayerCamera = $CameraRig
@onready var attack_area: Area3D = $AttackArea

## Публичное состояние для снапшотов П3.
var _anim: int = Protocol.AnimState.IDLE

## Бот --bot заменяет ввод (раздел 18: бродит между POI, прыгает, бьёт мобов).
var _bot: BotController = null

var _coyote: float = 0.0
var _jump_buffer: float = 0.0
var _jump_cut_done: bool = false
var _was_on_floor: bool = true
var _attack_cooldown: float = 0.0
var _attack_active: float = 0.0
var _hanging: bool = false
var _hang_left: float = 0.0
var _in_water: bool = false
var _water_level: float = 0.0
var _head_below: bool = false
## Чью голову нашли под ногами (meta узла HeadTop; 0 — своя/чужая без meta).
var _head_peer: int = 0
## Ближайший интерактивный объект (подсказка HUD, удержание E; П5).
var _interactable: Interactable = null
## Накопленное удержание E у объекта с hold_time > 0, с.
var _hold_accum: float = 0.0
## «За руку» (раздел 9.5): peer ведущего, чьим ведомым я являюсь (0 — никого).
var _hand_leader_peer: int = 0
## «За руку»: peer моего ведомого (0 — никого; веду не больше одного).
var _hand_follower_peer: int = 0
## Приглашение «за руку»: от кого и сколько секунд осталось принимать, с.
var _invite_peer: int = 0
var _invite_left: float = 0.0
## Прыгал ли ведущий в прошлом кадре (повтор прыжков, раздел 9.5).
var _leader_was_jumping: bool = false
## Сидение у костра (раздел 9.6): индекс места и ожидание подтверждения
## вставания (движение уже послано хосту, новое событие ещё не пришло).
var _sitting: bool = false
var _seat_index: int = -1
var _stand_sent: bool = false
## Множители выбранного персонажа (раздел 16, «Характеристики»): бег и высота
## прыжка. Скорость прыжка умножается на корень высотного множителя.
var _run_multiplier: float = 1.0
var _jump_height_multiplier: float = 1.0
## Сила 1–5 (раздел 17): ускоряет вытягивание и даёт чуть больше высоты
## прыжка с головы; хранится индексом массива множителей в balance.
var _strength: int = 3
## Точка, за которую висим (куда поднимет вытягивание; раздел 9.1).
var _hang_point: Vector3 = Vector3.ZERO


func _ready() -> void:
	add_to_group(GROUP)
	# Слой 2 — игроки (для Area3D: удар, плита), маска — только мир: игроки
	# проходят друг сквозь друга (раздел 5), слой голов включается на лету.
	collision_layer = 2
	collision_mask = 1
	# Собственная голова не должна ловить собственную капсулу.
	$HeadTop.add_collision_exception_with(self)
	floor_snap_length = 0.2
	# Player — всегда локальный игрок (RemotePlayer отдельно): с него Net
	# берёт снапшоты и позицию для проверок хоста (раздел 10).
	Net.register_local_player(self)
	EventBus.hand_link.connect(_on_hand_link)
	EventBus.hand_invite.connect(_on_hand_invite)
	EventBus.campfire_seats.connect(_on_campfire_seats)
	if Session.bot:
		_bot = BotController.new()
		_bot.setup(self)
		add_child(_bot)


func _physics_process(delta: float) -> void:
	_update_invite_timer(delta)
	if _sitting:
		if _stand_input():
			stand_up_from_seat()
		return
	if _hanging:
		_process_hang(delta)
		_update_interaction(delta)
		return
	_attack_cooldown = maxf(_attack_cooldown - delta, 0.0)
	if _attack_active > 0.0:
		_attack_active -= delta
		if _attack_active <= 0.0:
			_end_attack()

	var wish := _wish_direction()
	if _hand_leader_peer != 0:
		# Ведомый игнорирует свой ввод и идёт за ведущим (раздел 9.5).
		wish = _follow_leader()
	else:
		_move_horizontally(wish, delta)
	_apply_gravity_or_buoyancy(delta)
	if _hand_leader_peer == 0:
		_update_jump(delta)
	_update_head_collision()
	var was_floor := is_on_floor()
	move_and_slide()
	if was_floor and is_on_floor() and is_on_wall():
		_try_step_up(wish)
	_update_animation(wish)
	_turn_model(wish, delta)
	if _wave_pressed():
		visual.play_one_shot(Protocol.AnimState.WAVE, B.wave_time)
	if _attack_pressed():
		_try_attack()
	if _hand_pressed():
		_handle_hand_key()
	_update_interaction(delta)


# --- «За руку» (раздел 9.5) ---

## Хост подтвердил связь (rpc_hand_link): запоминаем роль. Ведущий сбавляет
## бег до более медленного из цепочки (раздел 17), ведомый начинает следование.
func _on_hand_link(leader_peer: int, follower_peer: int, on: bool) -> void:
	if leader_peer == Net.local_peer_id:
		_hand_follower_peer = follower_peer if on else 0
	if follower_peer == Net.local_peer_id:
		_hand_leader_peer = leader_peer if on else 0
		_leader_was_jumping = false
	# Любое событие с нами гасит подсказку-приглашение (приняли или разорвали).
	if leader_peer == Net.local_peer_id or follower_peer == Net.local_peer_id:
		_invite_peer = 0


## Приглашение взять за руку (раздел 9.5): живёт hand_invite_time, ответ — F.
func _on_hand_invite(by_peer: int, _by_name: String) -> void:
	if _hand_leader_peer != 0 or _hand_follower_peer != 0:
		return
	_invite_peer = by_peer
	_invite_left = B.hand_invite_time


func _update_invite_timer(delta: float) -> void:
	if _invite_peer != 0:
		_invite_left -= delta
		if _invite_left <= 0.0:
			_invite_peer = 0


## F — «взять за руку / отпустить» (разделы 5, 9.5): связан — отпустить,
## есть приглашение — принять, рядом игрок — позвать.
func _handle_hand_key() -> void:
	if _hand_leader_peer != 0 or _hand_follower_peer != 0:
		Net.request_hand_release()
		return
	if _invite_peer != 0:
		var from_peer := _invite_peer
		_invite_peer = 0
		Net.accept_hand_invite(from_peer)
		return
	var target := _nearest_remote_for_hand()
	if target != 0:
		Net.request_hand_link(target)


## Ближайший чужой игрок в радиусе hand_link_radius (0 — никого рядом).
func _nearest_remote_for_hand() -> int:
	var best := 0
	var best_distance := B.hand_link_radius
	for node in get_tree().get_nodes_in_group(RemotePlayer.GROUP):
		var remote := node as RemotePlayer
		if remote == null:
			continue
		var distance: float = remote.last_position().distance_to(global_position)
		if distance <= best_distance:
			best_distance = distance
			best = remote.peer_id
	return best


## Узел ведущего на сцене (null — уже исчез: хост разорвёт связь, стоим).
func _leader_remote() -> RemotePlayer:
	if _hand_leader_peer == 0:
		return null
	for node in get_tree().get_nodes_in_group(RemotePlayer.GROUP):
		var remote := node as RemotePlayer
		if remote != null and remote.peer_id == _hand_leader_peer:
			return remote
	return null


## Шаг ведомого (раздел 9.5): персонаж стремится к точке в
## hand_follow_distance позади-сбоку интерполированной позиции ведущего
## (скорость ограничена, коллизии работают через move_and_slide), прыжки
## ведущего повторяются. Возвращает направление движения (поворот модели
## и автоподъём) или ноль — стоять.
func _follow_leader() -> Vector3:
	var leader := _leader_remote()
	if leader == null:
		return Vector3.ZERO
	var forward := Vector3(sin(leader.model_yaw()), 0.0, cos(leader.model_yaw()))
	var right := Vector3(forward.z, 0.0, -forward.x)
	var target: Vector3 = leader.last_position() \
		- forward * B.hand_follow_distance * 0.8 + right * B.hand_follow_distance * 0.6
	var to_target := target - global_position
	to_target.y = 0.0
	var distance := to_target.length()
	if distance > B.hand_break_distance + B.mob_hit_slack:
		# Дальше разрыва: хост вот-вот оборвёт связь — стоим без рывка.
		velocity.x = 0.0
		velocity.z = 0.0
		_leader_was_jumping = leader.is_jumping()
		return Vector3.ZERO
	if distance > 0.15:
		var speed := minf(distance * B.hand_follow_gain, B.hand_follow_speed)
		velocity.x = to_target.x / distance * speed
		velocity.z = to_target.z / distance * speed
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	# Прыжки ведущего повторяются (раздел 9.5): на отрыве и с земли.
	var leader_jumping := leader.is_jumping()
	if leader_jumping and not _leader_was_jumping and is_on_floor():
		velocity.y = B.jump_speed * sqrt(_jump_height_multiplier)
		_jump_cut_done = true
	_leader_was_jumping = leader_jumping
	return to_target / distance if distance > 0.15 else Vector3.ZERO


## Пока веду за руку (цепочка до 4), бег — со скоростью более медленного
## из цепочки (раздел 17): характеристики каждый клиент берёт из своего
## файла данных по номеру персонажа из ростера (раздел 16), по сети числа
## не ходят.
func _link_speed_multiplier() -> float:
	var multiplier := _run_multiplier
	for peer_id: int in Net.hand_chain_below(Net.local_peer_id):
		if peer_id == Net.local_peer_id:
			continue
		var stats := CharacterData.stats(Net.peer_character(peer_id))
		multiplier = minf(multiplier, B.stat_multipliers[(stats["speed"] as int) - 1])
	return multiplier


# --- Сидение у костра (раздел 9.6) ---

## Занятость мест от хоста (раздел 9.6): моё имя появилось в массиве —
## сажусь, пропало — встаю (шевельнулись сами или хост освободил место).
func _on_campfire_seats(seats: Array) -> void:
	var mine := -1
	for i: int in seats.size():
		if int(seats[i]) == Net.local_peer_id:
			mine = i
			break
	if mine >= 0 and not _sitting and not _stand_sent:
		_sit_at(mine)
	elif mine < 0 and _sitting:
		_leave_seat()


## Поза KayKit «Sit_Chair_Idle» считается от пола: origin опускаем на землю
## перед лавкой (вне её коллайдера), модель — лицом к костру. Физика сидя
## заморожена (ранний выход в _physics_process), снапшоты идут как обычно.
func _sit_at(seat_index: int) -> void:
	var seat := _seat_node(seat_index)
	if seat == null:
		return
	_sitting = true
	_stand_sent = false
	_seat_index = seat_index
	velocity = Vector3.ZERO
	var to_fire := seat.face_target - seat.global_position
	to_fire.y = 0.0
	var dir := to_fire.normalized()
	global_position = seat.global_position + dir * 0.75 - Vector3(0.0, B.campfire_seat_floor, 0.0)
	model.rotation.y = atan2(dir.x, dir.z)
	_set_anim(Protocol.AnimState.SIT)
	# Подсказку «E — сесть» гасим сами: _update_interaction сидя не работает.
	EventBus.interaction_hint.emit("")
	EventBus.interaction_progress.emit(-1.0)
	Log.info("Сел у костра (место %d)" % (seat_index + 1), "Player")


## Встать (раздел 9.6: любое движение). Локально — сразу, хост снимет
## занятость подтверждением; пока его событие не пришло, не садимся снова.
func stand_up_from_seat() -> void:
	if not _sitting:
		return
	_stand_sent = true
	_leave_seat()
	Net.request_stand_up()


func _leave_seat() -> void:
	_sitting = false
	_stand_sent = false
	_seat_index = -1
	_set_anim(Protocol.AnimState.IDLE)


## Сидит ли у костра (флаг снапшота, раздел 10).
func is_sitting() -> bool:
	return _sitting


## Любое движение, прыжок или удар — сигнал встать (раздел 9.6).
func _stand_input() -> bool:
	return _wish_direction().length() > 0.1 or _jump_pressed() or _attack_pressed()


## Узел места по индексу (порядок имён Seat1..Seat8 — как benches IslandGen).
func _seat_node(seat_index: int) -> CampfireSeat:
	for node in get_tree().get_nodes_in_group(CampfireSeat.SEAT_GROUP):
		var seat := node as CampfireSeat
		if seat != null and seat.seat_index == seat_index:
			return seat
	return null


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

## Характеристики выбранного персонажа (раздел 16): множители бега и высоты
## прыжка из characters.json по номеру модели; Сила с П5 ускоряет
## вытягивание и прибавляет высоту прыжка с головы (раздел 17).
## По сети числа не ходят: каждый клиент берёт их из своего файла данных.
func apply_stats(character: int) -> void:
	var stats := CharacterData.stats(character)
	_run_multiplier = B.stat_multipliers[stats["speed"] as int - 1]
	_jump_height_multiplier = B.stat_multipliers[stats["jump"] as int - 1]
	_strength = stats["strength"] as int


func run_multiplier() -> float:
	return _run_multiplier


func jump_height_multiplier() -> float:
	return _jump_height_multiplier


## Сила персонажа 1–5 (кооп-действия П5; множители — в balance).
func strength() -> int:
	return _strength


## Множитель усиления прыжка с головы от Силы прыгуна (раздел 17: «чуть
## больше высоты подсадки» у сильных) — вызывается при прыжке с головы.
func strength_head_boost() -> float:
	return B.strength_head_boost[clampi(_strength, 1, 5) - 1]


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


## «Помахать» (клавиша 1, действие emote_1): временная проверка эмоций
## до П5 (раздел 16); бот не машет.
func _wave_pressed() -> bool:
	return _bot == null and Input.is_action_just_pressed("emote_1")


## F — «взять за руку / отпустить» (раздел 9.5); бот за руку не берётся.
func _hand_pressed() -> bool:
	return _bot == null and Input.is_action_just_pressed("hand_hold")


func _move_horizontally(wish: Vector3, delta: float) -> void:
	var walking: bool = Input.is_action_pressed("walk") if _bot == null else false
	var speed: float = B.walk_speed if walking else B.run_speed
	if _in_water:
		# Множитель персонажа — про бег по земле (раздел 16), плавание не трогаем.
		speed = minf(speed, B.swim_speed)
	else:
		speed *= _link_speed_multiplier()
	var target := wish.limit_length(1.0) * speed
	var accel: float = B.deceleration if target == Vector3.ZERO else B.acceleration
	if not is_on_floor() and not _in_water:
		accel *= B.air_control
	velocity.x = move_toward(velocity.x, target.x, accel * delta)
	velocity.z = move_toward(velocity.z, target.z, accel * delta)


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
		var speed := B.jump_speed
		if is_on_floor() and _head_below:
			# Прыжок с головы другого игрока усилен (раздел 5); Сила прыгуна
			# добавляет чуть больше высоты (раздел 17, П5). Факт подсадки —
			# хост рассылает всем для очков «Встреч» (раздел 13).
			speed = JumpMath.boosted_jump_speed(B) * strength_head_boost()
			if _head_peer != 0:
				Net.request_boost(_head_peer)
		# Множитель высоты прыжка персонажа: v = √(2·g·h) — скорость из корня.
		velocity.y = speed * sqrt(_jump_height_multiplier)
		_jump_buffer = 0.0
		_coyote = 0.0
		_jump_cut_done = false
	# Переменная высота: отпускание режет вертикальную скорость (один раз).
	if not _jump_held() and not _jump_cut_done:
		velocity.y = JumpMath.jump_cut(velocity.y, B)
		_jump_cut_done = true


## Автоподъём на ступеньку до step_up_height (полублоки): вверх, вперёд, вниз.
## Если впереди стена выше ступени, подъёма не выходит — игрок остаётся у стены.
func _try_step_up(wish: Vector3) -> void:
	if wish.length() < 0.1:
		return
	var dir := wish.normalized()
	var up := move_and_collide(Vector3.UP * B.step_up_height)
	var lifted: float = B.step_up_height if up == null \
		else B.step_up_height - up.get_remainder().length()
	move_and_collide(dir * STEP_PROBE)
	move_and_collide(Vector3.DOWN * (lifted + 0.01))


# --- Голова другого игрока (подсадка) ---

## Включить столкновение со слоем голов, только если падаем и ступни выше
## верхней грани бокса (условие HeadStand.can_stand); заодно запоминаем,
## стоим ли прямо на голове (буст прыжка). Origin персонажа — в ногах,
## поэтому ступни — это global_position.y, а луч ищет голову в полуметре
## под ногами (чуть больше шага кадра при максимальной скорости падения).
func _update_head_collision() -> void:
	_head_below = false
	_head_peer = 0
	var allow := false
	if velocity.y <= 0.0:
		var from := global_position + Vector3.UP * 0.6
		var to := from + Vector3.DOWN * (0.6 + 0.5)
		var query := PhysicsRayQueryParameters3D.create(from, to, 1 << (HeadStand.LAYER_HEAD - 1), [get_rid()])
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit:
			var head_top_y: float = (hit["position"] as Vector3).y
			var feet_y: float = global_position.y
			allow = HeadStand.can_stand(feet_y, head_top_y, velocity.y, B.head_stand_epsilon)
			_head_below = allow and feet_y - head_top_y < HEAD_BELOW_EPS
			if _head_below:
				# Чья это голова (RemotePlayer пишет peer_id в meta) — событие
				# подсадки для «Встреч» (раздел 13).
				_head_peer = int((hit["collider"] as Node).get_meta("peer_id", 0))
	set_collision_mask_value(HeadStand.LAYER_HEAD, allow)


# --- Удар (раздел 5) ---

func _try_attack() -> void:
	if _attack_cooldown > 0.0:
		return
	_attack_cooldown = B.attack_cooldown
	_attack_active = B.attack_active_time
	attack_area.monitoring = true
	# Взмах при ударе — та же анимация «Привет!» (мах рукой, раздел 5).
	visual.play_one_shot(Protocol.AnimState.WAVE, 0.25)


func _end_attack() -> void:
	# Пересечения читаем, пока monitoring включён: после выключения
	# get_overlapping_* пуст (и ругается в консоль движка).
	var bodies := attack_area.get_overlapping_bodies()
	var areas := attack_area.get_overlapping_areas()
	attack_area.monitoring = false
	# По игрокам — только визуальный «тычок» (раздел 5).
	for body in bodies:
		if body is Player and body != self:
			(body as Player).receive_bonk()
	# Мобы (раздел 8): птица и зверёк — один удар; светлячок на двоих — П5.
	for area in areas:
		if area is Mob:
			(area as Mob).take_hit()


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


## Помощник тянет: хост подтвердил rpc_pulled (раздел 9.1). Игрок
## поднимается на кромку в точку цепляния — без штрафа и Камня духа.
func pulled_up() -> void:
	if not _hanging:
		return
	_hanging = false
	velocity = Vector3.ZERO
	global_position = _hang_point + Vector3(0.0, 0.05, 0.0)
	_set_anim(Protocol.AnimState.IDLE)
	visual.play_one_shot(Protocol.AnimState.PULLED_UP, 0.5)
	EventBus.player_hang_ended.emit()
	Log.info("Вытянут из расщелины", "Player")


## Помощник начал тянуть: короткая анимация «помогает» (раздел 5).
func helper_pull() -> void:
	visual.play_one_shot(Protocol.AnimState.HELP_PULL, 0.6)


## Висит ли у края расщелины (проверка хоста для вытягивания, раздел 9.1).
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

func _update_animation(wish: Vector3) -> void:
	if not _was_on_floor and is_on_floor():
		visual.play_one_shot(Protocol.AnimState.LAND, 0.25)
		# Облачко пыли при приземлении (раздел 16); частицы в мировых
		# координатах — эмиттер едет вместе с игроком, пыль остаётся на месте.
		Fx.puff(self, Vector3(0.0, 0.06, 0.0), Color(0.86, 0.8, 0.7), 10, 0.12, 1.1)
	var moving := Vector2(velocity.x, velocity.z).length() > 0.3
	var linked := _hand_leader_peer != 0 or _hand_follower_peer != 0
	if _in_water:
		_set_anim(Protocol.AnimState.WALK if moving else Protocol.AnimState.IDLE)
	elif not is_on_floor():
		_set_anim(Protocol.AnimState.JUMP if velocity.y > 0.0 else Protocol.AnimState.FALL)
	elif moving and linked:
		# Пара на ходу — рука вытянута к партнёру (клип KayKit Walking_B).
		_set_anim(Protocol.AnimState.HOLD_HAND)
	elif moving:
		var walking: bool = Input.is_action_pressed("walk") or wish.length() <= 0.1
		_set_anim(Protocol.AnimState.WALK if walking else Protocol.AnimState.RUN)
	else:
		_set_anim(Protocol.AnimState.IDLE)
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
	if _sitting:
		flags |= Protocol.FLAG_SITTING
	if _hand_follower_peer != 0:
		flags |= Protocol.FLAG_HAND_HELD
	if _hand_leader_peer != 0:
		flags |= Protocol.FLAG_LED_BY_HAND
	return flags


## Точки интереса для бота (задаёт сцена мира: зоны, камни духа).
func set_bot_targets(points: Array) -> void:
	if _bot != null:
		_bot.set_targets(points)
