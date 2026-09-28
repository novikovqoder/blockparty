# Визуал игрока-«кубика» из примитивов (раздел 14 SPEC): голова и тело — блоки,
# тёмный контур, анимации твинами (покадровая анимация — после MVP).
# Логика игрока знает только методы этого скрипта, спрайты заменяются без неё.
# Не делает: косметику и наряды (этап 7).
class_name PlayerVisual
extends Node2D

const PAL: Palette = preload("res://assets/palette.tres")

var _outline: ColorRect
var _head: ColorRect
var _body: ColorRect
var _eye: ColorRect
var _arm: ColorRect
var _blink_left: float = 0.0
var _facing: int = 1
var _tween: Tween


func _ready() -> void:
	# Контур чуть больше блоков — «толстый тёмный контур» стиля MVP.
	_outline = _rect(Vector2(32, 48), PAL.outline)
	_body = _rect(Vector2(28, 30), PAL.player_body, Vector2(0, 7))
	_head = _rect(Vector2(28, 14), PAL.player_body, Vector2(0, -15))
	_head.color = _head.color.lerp(PAL.player_accent, 0.35)
	_eye = _rect(Vector2(6, 8), PAL.outline)
	# Рука-блок: видна только при ударе.
	_arm = _rect(Vector2(16, 8), PAL.player_accent)
	_arm.visible = false
	add_child(_outline)
	add_child(_body)
	add_child(_head)
	add_child(_eye)
	add_child(_arm)
	set_facing(1)


func _process(delta: float) -> void:
	# Мигание после урона: наремя неуязвимости видимость мерцает.
	if _blink_left > 0.0:
		_blink_left -= delta
		var on: bool = fmod(_blink_left, 0.16) < 0.08
		_outline.visible = on
		_body.visible = on
		_head.visible = on
		if _blink_left <= 0.0:
			_outline.visible = true
			_body.visible = true
			_head.visible = true


## Направление взгляда: глаз и рука переходят на сторону бега.
func set_facing(dir: int) -> void:
	_facing = dir
	_eye.position = Vector2(dir * 6.0 - _eye.size.x * 0.5, -17.0)


## Оттенок тела: различать удалённых игроков (плейсхолдер до косметики этапа 7).
## Вызывать после добавления в дерево (блоки строятся в _ready).
func tint(color: Color) -> void:
	if _body == null:
		return
	_body.color = color
	_head.color = color.lerp(PAL.player_accent, 0.35)


## Сила бега 0..1 — лёгкий наклон вперёд.
func set_run_blend(blend: float) -> void:
	rotation = clampf(blend, -1.0, 1.0) * 0.08


## Сторона удара для руки; не мешает идущей анимации (атака/висит).
func set_attack_side(dir: int) -> void:
	_arm.scale.x = dir
	if not _arm.visible:
		_arm.position = Vector2(dir * 22.0, 4.0)


func play_idle() -> void:
	_kill_tween()
	_arm.visible = false
	_arm.position.y = 4.0
	_animate_scale(Vector2.ONE)


func play_jump() -> void:
	_kill_tween()
	_animate_scale(Vector2(0.8, 1.2))


func play_land() -> void:
	_kill_tween()
	_animate_scale(Vector2(1.25, 0.75))


func play_hit(duration: float) -> void:
	_kill_tween()
	modulate = Color(1.0, 0.55, 0.55)
	var t := create_tween()
	t.tween_interval(duration * 0.5)
	t.tween_property(self, "modulate", Color.WHITE, duration * 0.5)


func play_blink(duration: float) -> void:
	_blink_left = duration


func stop_blink() -> void:
	_blink_left = 0.0
	if _outline != null:
		_outline.visible = true
		_body.visible = true
		_head.visible = true


func play_attack() -> void:
	_arm.visible = true
	_arm.position.y = 4.0
	var t := create_tween()
	t.tween_property(_arm, "position:x", _facing * 32.0, 0.06)
	t.tween_property(_arm, "position:x", _facing * 22.0, 0.08)
	t.tween_callback(func() -> void: _arm.visible = false)


func play_hang() -> void:
	# Руки подняты над краем.
	_arm.visible = true
	_arm.position = Vector2(6.0, -20.0)
	_arm.scale.x = 1.0
	set_run_blend(0.0)


## Вытягивание висящего (раздел 7.1): рука тянется к нему и возвращается.
func play_pull() -> void:
	_arm.visible = true
	_arm.position.y = 4.0
	var t := create_tween()
	t.tween_property(_arm, "position:x", _facing * 34.0, 0.12)
	t.tween_property(_arm, "position:x", _facing * 22.0, 0.2)
	t.tween_callback(func() -> void: _arm.visible = false)


func _rect(size: Vector2, color: Color, center: Vector2 = Vector2.ZERO) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.size = size
	rect.pivot_offset = size * 0.5  # вращение/масштаб вокруг центра блока
	rect.position = center - size * 0.5
	return rect


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if _arm != null and _arm.visible and _arm.position.y < 0.0:
		_arm.visible = false  # рука «висит» больше не нужна


func _animate_scale(target: Vector2) -> void:
	_tween = create_tween()
	_tween.tween_property(self, "scale", target, 0.06)
	_tween.tween_property(self, "scale", Vector2.ONE, 0.12)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
