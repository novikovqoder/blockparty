# Простой бот для нагрузочных тестов (раздел 3 SPEC, --bot): бежит вправо,
# прыгает перед стеной или пропастью, выпрыгивает при застревании, бьёт моба
# впереди и сам сдаётся при «Висит». Заменяет ввод игрока, больше ничего
# не решает. Параметры — группа «Бот» в balance.tres.
class_name BotController
extends Node

const B: Balance = preload("res://gameplay/balance.tres")

var _player: Player
var _wall_cast: RayCast2D
var _gap_cast: RayCast2D
var _gap_far_cast: RayCast2D
var _plat_cast: RayCast2D
var _mob_cast: RayCast2D
var _jump_requested: bool = false
var _attack_requested: bool = false
var _jump_hold_left: float = 0.0
var _stuck_left: float = 0.0
var _hang_left: float = 0.0
var _wide_gap: bool = false
var _floor_y: float = 0.0  # уровень пола по точке спавна


func setup(player: Player) -> void:
	_player = player
	_floor_y = player.global_position.y


func _ready() -> void:
	# Лучи относительно персонажа: перед лицом и под ногами впереди.
	_wall_cast = _make_cast(Vector2(B.bot_look_ahead, 0.0), Vector2(B.bot_cast_offset_x, 0.0), 1, false)
	_wall_cast.hit_from_inside = true  # упёрся вплотную — луч уже внутри стены
	_gap_cast = _make_cast(Vector2(0.0, B.bot_gap_depth), Vector2(B.bot_cast_offset_x, 0.0), 1, false)
	_gap_far_cast = _make_cast(Vector2(0.0, B.bot_gap_depth), Vector2(B.bot_gap_far_x, 0.0), 1, false)
	# Опора впереди может быть выше ног (уступ): луч изнутри неё тоже опора.
	_gap_cast.hit_from_inside = true
	_gap_far_cast.hit_from_inside = true
	# Платформы выше центра тела — горизонтальный луч на их высоте.
	_plat_cast = _make_cast(Vector2(B.bot_look_ahead, 0.0), Vector2(B.bot_cast_offset_x, B.bot_platform_cast_y), 1, false)
	_mob_cast = _make_cast(Vector2(B.bot_attack_range, 0.0), Vector2(B.bot_cast_offset_x, 0.0), 4, true)


func _make_cast(target: Vector2, offset: Vector2, mask: int, with_areas: bool) -> RayCast2D:
	var cast := RayCast2D.new()
	cast.position = offset
	cast.target_position = target
	cast.collision_mask = mask
	cast.collide_with_areas = with_areas
	cast.collide_with_bodies = not with_areas
	# Лучи — дети персонажа: RayCast2D под обычным Node не наследует трансформ.
	_player.add_child(cast)
	return cast


func _physics_process(delta: float) -> void:
	if _player == null:
		return
	if _player.is_hanging():
		# В одиночку помощь не придёт: сдаёмся чуть раньше таймаута 8 с.
		_hang_left += delta
		if _hang_left >= B.bot_hang_give_up:
			_hang_left = 0.0
			_player.give_up_hang()
		return
	_hang_left = 0.0

	_wall_cast.force_raycast_update()
	_gap_cast.force_raycast_update()
	_gap_far_cast.force_raycast_update()
	_plat_cast.force_raycast_update()
	_mob_cast.force_raycast_update()

	if _player.is_on_floor():
		# Стоим выше уровня пола — мы на платформе (движущейся или подвешенной):
		# бежим вправо, пока впереди (дальний луч) есть опора, и спрыгиваем
		# на неё с края. На полу: пропасть шире прыжка (опоры нет и близко,
		# и далеко) — прыгать нельзя, стоим и ждём движущуюся платформу.
		var elevated: bool = _player.global_position.y < _floor_y - 30.0
		if elevated:
			_wide_gap = not _gap_far_cast.is_colliding()
			if not _wide_gap and not _gap_cast.is_colliding():
				_request_jump()  # край платформы, опора впереди — вперёд
		else:
			_wide_gap = not _gap_cast.is_colliding() and not _gap_far_cast.is_colliding()
			if _wide_gap:
				if _plat_cast.is_colliding():
					_request_jump()  # платформа у борта — запрыгиваем
			elif _wall_cast.is_colliding() or not _gap_cast.is_colliding():
				_request_jump()
		if not _wide_gap and absf(_player.velocity.x) < 30.0:
			_stuck_left += delta
			if _stuck_left >= B.bot_stuck_time:
				_stuck_left = 0.0
				_request_jump()
		else:
			_stuck_left = 0.0

	_jump_hold_left = maxf(0.0, _jump_hold_left - delta)
	if _mob_cast.is_colliding():
		_attack_requested = true


func _request_jump() -> void:
	_jump_requested = true
	_jump_hold_left = B.bot_jump_hold


## Направление бега: бот всегда вправо (раздел 3: «бежит вправо и прыгает»),
## кроме ожидания платформы у широкой пропасти — в полёте бежит всегда.
func axis() -> float:
	return 0.0 if _wide_gap and _player.is_on_floor() else 1.0


## Прыжок запрошен (одноразово, как just_pressed).
func consume_jump() -> bool:
	var value: bool = _jump_requested
	_jump_requested = false
	return value


## Держит ли бот кнопку прыжка (полная высота прыжка).
func jump_held() -> bool:
	return _jump_hold_left > 0.0


## Атака запрошена (одноразово).
func consume_attack() -> bool:
	var value: bool = _attack_requested
	_attack_requested = false
	return value
