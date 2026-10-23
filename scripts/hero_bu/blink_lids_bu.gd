class_name BlinkLidsBU
extends SkeletonModifier3D
## Моргание настоящими веками: поворачивает кости верхних век (LeftEyelidUpper /
## RightEyelidUpper, скелет героя MakeHuman с именами Mixamo) поверх анимации.
## Ставится дочерним узлом Skeleton3D. Ресницы привязаны к векам и двигаются вместе с ними.

## Угол закрытия века, градусы (вокруг локальной оси X кости).
@export var close_angle: float = 35.0
## Пауза между морганиями, секунды (случайно в этих пределах).
@export var interval_min: float = 2.5
@export var interval_max: float = 6.0
## Длительность моргания целиком (закрыть + открыть), секунды.
@export var blink_time: float = 0.16
## Вероятность двойного моргания.
@export_range(0.0, 1.0) var double_chance: float = 0.2
## Постоянный прищур 0..1 (0 — глаза открыты, 1 — закрыты).
@export_range(0.0, 1.0) var squint: float = 0.12
@export var auto_blink: bool = true

var _lids: Array[int] = []
var _wait: float = 3.0
var _t: float = -1.0
var _second: bool = false


func _ready() -> void:
	_wait = randf_range(interval_min, interval_max)


func _find_lids() -> void:
	var sk: Skeleton3D = get_skeleton()
	if sk == null:
		return
	for i: int in sk.get_bone_count():
		var n: String = sk.get_bone_name(i)
		if n.ends_with("EyelidUpper"):
			_lids.append(i)


## Моргнуть сейчас (twice — двойное).
func blink(twice: bool = false) -> void:
	_t = 0.0
	_second = twice


func is_closed() -> bool:
	return _t >= 0.0 and _t < blink_time * 0.6


func _process_modification_with_delta(delta: float) -> void:
	var sk: Skeleton3D = get_skeleton()
	if sk == null:
		return
	if _lids.is_empty():
		_find_lids()
	var amount: float = squint
	if _t >= 0.0:
		_t += delta
		var k: float = _t / blink_time
		amount = maxf(amount, sin(clampf(k, 0.0, 1.0) * PI))
		if k >= 1.0:
			_t = -1.0
			if _second:
				_second = false
				_wait = 0.08
			else:
				_wait = randf_range(interval_min, interval_max)
	elif auto_blink:
		_wait -= delta
		if _wait <= 0.0:
			blink(randf() < double_chance)
	for b: int in _lids:
		var rest: Quaternion = sk.get_bone_rest(b).basis.get_rotation_quaternion()
		sk.set_bone_pose_rotation(b, rest * Quaternion(Vector3.RIGHT, deg_to_rad(close_angle * amount)))
