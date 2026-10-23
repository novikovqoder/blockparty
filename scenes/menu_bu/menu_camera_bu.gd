class_name MenuCameraBU
extends Camera2D
## Камера меню: плавные переходы между «кадрами» разделов, лёгкое дыхание,
## микродрожь, следование за мышью и толчки (гром). Координаты кадров —
## в пикселях мира, где высота сцены = WORLD_HEIGHT.

const WORLD_HEIGHT: float = 1080.0
## Запас по краям под дрожь и мышь, в пикселях экрана.
const EDGE_MARGIN: float = 44.0

## Ширина мира (ширина фоновой панорамы после масштабирования). Задаётся сценой.
var world_width: float = 1920.0
## 0..1 — сила всех покачиваний (из настройки «Дрожь камеры»).
var shake_factor: float = 0.7
var mouse_follow_px: float = 16.0
var drift_px: float = 9.0
var tremor_px: float = 0.8

var _shot_zoom: float = 1.0
var _tween: Tween
var _noise: FastNoiseLite = FastNoiseLite.new()
var _t: float = 0.0
var _impulse: float = 0.0
var _mouse: Vector2 = Vector2.ZERO
var _mouse_smooth: Vector2 = Vector2.ZERO


func _ready() -> void:
	_noise.seed = 7
	_noise.frequency = 0.9
	ignore_rotation = true
	get_viewport().size_changed.connect(_reapply_zoom)


## Множитель, при котором высота мира ровно заполняет экран.
func fit_zoom() -> float:
	var vp: Vector2 = get_viewport_rect().size
	return maxf(vp.y / WORLD_HEIGHT, vp.x / maxf(world_width, 1.0))


func _reapply_zoom() -> void:
	zoom = Vector2.ONE * _shot_zoom * fit_zoom()
	position = _clamped(position, _shot_zoom)


func _clamped(center: Vector2, shot_zoom: float) -> Vector2:
	var vp: Vector2 = get_viewport_rect().size
	var z: float = shot_zoom * fit_zoom()
	var half: Vector2 = vp / z * 0.5
	var m: float = EDGE_MARGIN / z
	var min_x: float = half.x + m
	var max_x: float = world_width - half.x - m
	var min_y: float = half.y + m
	var max_y: float = WORLD_HEIGHT - half.y - m
	var cx: float = world_width * 0.5 if min_x > max_x else clampf(center.x, min_x, max_x)
	var cy: float = WORLD_HEIGHT * 0.5 if min_y > max_y else clampf(center.y, min_y, max_y)
	return Vector2(cx, cy)


## Мгновенно встать в кадр. shot = (x, y, zoom).
func snap_to(shot: Vector3) -> void:
	if _tween:
		_tween.kill()
	_shot_zoom = shot.z
	zoom = Vector2.ONE * shot.z * fit_zoom()
	position = _clamped(Vector2(shot.x, shot.y), shot.z)


## Плавно перейти в кадр. Возвращает Tween, чтобы можно было дождаться конца.
func go_to(shot: Vector3, duration: float = 1.6, trans: Tween.TransitionType = Tween.TRANS_SINE, ease_type: Tween.EaseType = Tween.EASE_IN_OUT) -> Tween:
	if _tween:
		_tween.kill()
	var target_pos: Vector2 = _clamped(Vector2(shot.x, shot.y), shot.z)
	_tween = create_tween().set_parallel(true).set_trans(trans).set_ease(ease_type)
	_tween.tween_property(self, "position", target_pos, duration)
	_tween.tween_property(self, "zoom", Vector2.ONE * shot.z * fit_zoom(), duration)
	_tween.tween_property(self, "_shot_zoom", shot.z, duration)
	return _tween


## Толчок камеры (гром, удар). strength — пиксели экрана.
func add_impulse(strength: float) -> void:
	_impulse = maxf(_impulse, strength)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var vp: Vector2 = get_viewport_rect().size
		var p: Vector2 = (event as InputEventMouseMotion).position
		_mouse = Vector2(p.x / vp.x * 2.0 - 1.0, p.y / vp.y * 2.0 - 1.0).clampf(-1.0, 1.0)


func _process(delta: float) -> void:
	_t += delta
	_mouse_smooth = _mouse_smooth.lerp(_mouse, 1.0 - exp(-delta * 2.5))
	var k: float = shake_factor
	var off: Vector2 = Vector2.ZERO
	off += Vector2(sin(_t * TAU / 34.0), sin(_t * TAU / 47.0 + 1.3)) * drift_px * k
	off += Vector2(_noise.get_noise_2d(_t * 6.0, 0.0), _noise.get_noise_2d(0.0, _t * 6.0)) * tremor_px * k * 2.0
	off += _mouse_smooth * mouse_follow_px
	if _impulse > 0.01:
		off += Vector2(_noise.get_noise_2d(_t * 40.0, 50.0), _noise.get_noise_2d(50.0, _t * 40.0)) * _impulse * k * 2.0
		_impulse = move_toward(_impulse, 0.0, delta * _impulse * 2.2 + delta)
	offset = off / maxf(zoom.x, 0.001)
