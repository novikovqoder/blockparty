# Базовый моб (раздел 6 SPEC): общие для всех мобов — уникальный spawn_id,
# жизнь, позиция как чистая функция run_time (детерминизм от seed) и смерть
# по подтверждению «хоста». Мобы не наносят урон, только отталкивают.
# Не делает: золотую цель (этап 3), сетевое подтверждение (этап 2).
class_name Mob
extends Area2D

const B: Balance = preload("res://gameplay/balance.tres")

## id спавна из LevelPlan, одинаковый у всех участников забега.
var spawn_id: int = -1
## Жив ли моб (решает «хост», раздел 6).
var alive: bool = true
## Параметры траектории из ChunkDef секции; интерпретирует подкласс.
var params: Dictionary = {}

var _origin: Vector2 = Vector2.ZERO
var _box: Vector2 = Vector2(24, 20)
var _fx: ColorRect


func _init(box: Vector2 = Vector2(24, 20)) -> void:
	_box = box
	collision_layer = 4
	collision_mask = 2
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = box
	shape.shape = rect
	add_child(shape)


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	EventBus.mob_killed.connect(_on_mob_killed)
	_origin = global_position
	_build_visual()
	_fx = Prim.rect(_box * 1.15, Color(1, 1, 1, 0))
	add_child(_fx)
	_update_position(Session.run_time)


func _physics_process(_delta: float) -> void:
	if alive:
		_update_position(Session.run_time)


## Привязать данные спавна из плана уровня.
func setup(p_spawn_id: int, p_params: Dictionary) -> void:
	spawn_id = p_spawn_id
	params = p_params


## Смещение от точки спавна в момент t. Инстанс-метод полиморфен; подклассы
## делегируют своей статической trajectory — её же проверяют тесты GUT.
func compute_offset(t: float) -> Vector2:
	return Vector2.ZERO


## Смещение как чистая функция параметров спавна и времени (для тестов).
static func trajectory(_params: Dictionary, _t: float) -> Vector2:
	return Vector2.ZERO


## Эффект удара: играется локально сразу, до подтверждения «хостом».
func play_hit_fx() -> void:
	if _fx == null:
		return
	_fx.color = Color(1, 1, 1, 0.9)
	var t := create_tween()
	t.tween_property(_fx, "color:a", 0.0, 0.2)


func _build_visual() -> void:
	pass  # визуал определяет подкласс


func _update_position(t: float) -> void:
	position = _origin + compute_offset(t)


## Треугольная волна −1..1, phase — доля периода 0..2.
static func triangle_wave(phase: float) -> float:
	var p := fmod(phase, 2.0)
	if p < 0.0:
		p += 2.0
	return -1.0 + 2.0 * p if p < 1.0 else 3.0 - 2.0 * p


func _on_body_entered(body: Node2D) -> void:
	var player := body as Player
	if player != null and alive:
		player.push_from(global_position)


func _on_mob_killed(killed_id: int, _killer_id: int) -> void:
	if killed_id != spawn_id:
		return
	alive = false
	_death_fx()
	await create_tween().tween_property(self, "modulate:a", 0.0, 0.25).finished
	queue_free()


func _death_fx() -> void:
	scale = Vector2(1.4, 0.6)
