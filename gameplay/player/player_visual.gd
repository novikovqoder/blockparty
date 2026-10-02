# Кубическая модель персонажа (разделы 5, 16 SPEC): голова 0.5 м, тело, руки
# и ноги — отдельные BoxMesh, глаза — два тёмных кубика. Все анимации — твины
# поворотов конечностей: idle, walk, run, jump, fall, land, bonk, hang,
# pulled_up, help_pull, sit, hold_hand, emote ×6, wave.
# Визуал отделён от логики (правило проекта): player.gd только вызывает
# set_state()/play_one_shot() с кодом Protocol.AnimState, сам ничего не знает
# о мешах. Материалы берутся из assets/palette.tres в _ready.
# Не делает: косметику (цвета, шляпы, плащ — П8), подписи над головой (П3).
class_name PlayerVisual
extends Node3D

const PAL: Palette = preload("res://assets/palette.tres")

## Длительность перехода в позу, с.
const POSE_TIME: float = 0.1
## Нейтральная высота бёдер, м (низ ног на нуле модели).
const HIPS_Y: float = 0.55
## Приседание при приземлении, м.
const LAND_DIP: float = 0.1
## Подъём корпуса при вытягивании, м.
const PULL_LIFT: float = 0.3

@onready var hips: Node3D = $Hips
@onready var head: Node3D = $Hips/Head
@onready var arm_l: Node3D = $Hips/ArmL
@onready var arm_r: Node3D = $Hips/ArmR
@onready var leg_l: Node3D = $LegL
@onready var leg_r: Node3D = $LegR

## Базовое состояние (устойчивое: idle, walk, run, jump, fall, hang, sit…).
var _base_state: int = Protocol.AnimState.IDLE
## Осталось секунд у разовой анимации (land, bonk, wave, emote…); 0 — нет.
var _one_shot_left: float = 0.0

var _tweens: Array[Tween] = []


func _ready() -> void:
	_paint_meshes()


func _process(delta: float) -> void:
	if _one_shot_left > 0.0:
		_one_shot_left -= delta
		if _one_shot_left <= 0.0:
			_apply(_base_state)


## Установить устойчивое состояние (движение, висит, сидит, за руку).
func set_state(state: int) -> void:
	_base_state = state
	_one_shot_left = 0.0
	_apply(state)


## Разовая анимация поверх базовой (приземление, тычок, эмоция); после
## duration секунд возвращается базовое состояние.
func play_one_shot(state: int, duration: float) -> void:
	_apply(state)
	_one_shot_left = duration


func _apply(state: int) -> void:
	_stop_tweens()
	match state:
		Protocol.AnimState.IDLE:
			_pose({})
			_swing(hips, "position:y", HIPS_Y, 0.012, 2.0)
		Protocol.AnimState.WALK:
			_pose({})
			_gait(0.55, 0.7, 0.4)
		Protocol.AnimState.RUN:
			_pose({"hips": Vector3(-0.12, 0.0, 0.0)})
			_gait(0.9, 0.45, 0.65)
		Protocol.AnimState.JUMP:
			_pose({
				"arm_l": Vector3(-0.8, 0.0, 0.0),
				"arm_r": Vector3(-0.65, 0.0, 0.0),
				"leg_l": Vector3(-0.5, 0.0, 0.0),
				"leg_r": Vector3(-0.3, 0.0, 0.0),
			})
		Protocol.AnimState.FALL:
			_pose({
				"arm_l": Vector3(2.7, 0.0, 0.0),
				"arm_r": Vector3(2.7, 0.0, 0.0),
				"leg_l": Vector3(-0.3, 0.0, 0.0),
				"leg_r": Vector3(-0.15, 0.0, 0.0),
			})
		Protocol.AnimState.LAND:
			_pose({})
			_dip(-LAND_DIP, POSE_TIME)
		Protocol.AnimState.BONK:
			_pose({})
			_bonk()
		Protocol.AnimState.HANG:
			_pose({
				"arm_l": Vector3(3.0, 0.0, 0.0),
				"arm_r": Vector3(3.0, 0.0, 0.0),
				"leg_l": Vector3(-0.4, 0.0, 0.0),
				"leg_r": Vector3(-0.25, 0.0, 0.0),
			})
			_swing(hips, "rotation:z", 0.0, 0.06, 2.0)
		Protocol.AnimState.PULLED_UP:
			_pose({
				"arm_l": Vector3(3.0, 0.0, 0.0),
				"arm_r": Vector3(3.0, 0.0, 0.0),
			})
			_dip(PULL_LIFT, 0.3)
		Protocol.AnimState.HELP_PULL:
			_pose({
				"arm_r": Vector3(-1.35, 0.0, 0.0),
				"hips": Vector3(-0.15, 0.0, 0.0),
			})
		Protocol.AnimState.SIT:
			_pose({
				"leg_l": Vector3(-1.35, 0.0, 0.0),
				"leg_r": Vector3(-1.35, 0.0, 0.0),
				"arm_l": Vector3(-0.5, 0.0, 0.0),
				"arm_r": Vector3(-0.5, 0.0, 0.0),
			}, HIPS_Y - 0.35)
		Protocol.AnimState.HOLD_HAND:
			_pose({
				"arm_r": Vector3(0.0, 0.0, 0.7),
			})
		Protocol.AnimState.WAVE, Protocol.AnimState.EMOTE_1:
			# «Привет!» — правая рука над головой, машет.
			_pose({"arm_r": Vector3(0.0, 0.0, 2.7)})
			_swing(arm_r, "rotation:z", 2.7, 0.35, 0.55)
		Protocol.AnimState.EMOTE_2:
			# «Спасибо!» — поклон.
			_pose({})
			_bow()
		Protocol.AnimState.EMOTE_3:
			# «Сюда!» — рука вперёд, манит.
			_pose({"arm_r": Vector3(-1.2, 0.0, 0.0)})
			_swing(arm_r, "rotation:z", 0.0, 0.3, 0.5)
		Protocol.AnimState.EMOTE_4:
			# «Подожди!» — руки в стороны, лёгкое покачивание.
			_pose({
				"arm_l": Vector3(0.0, 0.0, -1.3),
				"arm_r": Vector3(0.0, 0.0, 1.3),
			})
			_swing(arm_l, "rotation:z", -1.3, 0.12, 1.2)
			_swing(arm_r, "rotation:z", 1.3, 0.12, 1.2)
		Protocol.AnimState.EMOTE_5:
			# «Ха-ха» — подпрыгивает, голова запрокинута.
			_pose({"head": Vector3(-0.3, 0.0, 0.0)})
			_swing(hips, "position:y", HIPS_Y, 0.06, 0.5)
		Protocol.AnimState.EMOTE_6:
			# «Помогите!» — обе руки вверх, машет.
			_pose({
				"arm_l": Vector3(0.0, 0.0, -2.8),
				"arm_r": Vector3(0.0, 0.0, 2.8),
			})
			_swing(arm_l, "rotation:z", -2.8, 0.3, 0.6)
			_swing(arm_r, "rotation:z", 2.8, 0.3, 0.6)
		_:
			_pose({})


# --- Инструменты аниматора ---

func _stop_tweens() -> void:
	for tween: Tween in _tweens:
		tween.kill()
	_tweens.clear()


func _node_for(key: String) -> Node3D:
	match key:
		"hips": return hips
		"head": return head
		"arm_l": return arm_l
		"arm_r": return arm_r
		"leg_l": return leg_l
		"leg_r": return leg_r
	return hips


## Применить позу: плавные твины поворотов всех частей к целевым углам
## (не названные в pose части — к нейтрали). hips_y задаёт высоту бёдер
## (SIT); по умолчанию положение не трогается, чтобы не мешать качанию.
func _pose(pose: Dictionary, hips_y: float = -1.0) -> void:
	var parts: Array[String] = ["hips", "head", "arm_l", "arm_r", "leg_l", "leg_r"]
	var tween := create_tween()
	tween.set_parallel(true)
	for part: String in parts:
		tween.tween_property(_node_for(part), "rotation", pose.get(part, Vector3.ZERO), POSE_TIME)
	if hips_y >= 0.0:
		tween.tween_property(hips, "position:y", hips_y, POSE_TIME)
	_tweens.append(tween)


## Цикл качания вокруг базового значения base: base → base±amp → base,
## период period с. Плавно стартует из текущего значения.
func _swing(node: Node3D, property: String, base: float, amp: float, period: float) -> void:
	var tween := create_tween().set_loops(-1)
	tween.tween_property(node, property, base + amp, period * 0.25)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(node, property, base - amp, period * 0.5)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(node, property, base, period * 0.25)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tweens.append(tween)


## Походка: ноги и руки в противофазе (раздел 16 — твины поворотов конечностей).
func _gait(leg_amp: float, period: float, arm_amp: float) -> void:
	_swing(leg_l, "rotation:x", 0.0, leg_amp, period)
	_swing(leg_r, "rotation:x", 0.0, -leg_amp, period)
	_swing(arm_l, "rotation:x", 0.0, -arm_amp, period)
	_swing(arm_r, "rotation:x", 0.0, arm_amp, period)


## Присед/подъём корпуса с возвратом (приземление, вытягивание).
func _dip(dip: float, hold: float) -> void:
	var tween := create_tween()
	tween.tween_property(hips, "position:y", HIPS_Y + dip, POSE_TIME)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_interval(hold)
	tween.tween_property(hips, "position:y", HIPS_Y, 2.0 * POSE_TIME)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tweens.append(tween)


## «Тычок»: голова мотнулась вперёд-назад.
func _bonk() -> void:
	var tween := create_tween()
	tween.tween_property(head, "rotation:x", 0.5, 0.07)
	tween.tween_property(head, "rotation:x", -0.3, 0.1)
	tween.tween_property(head, "rotation:x", 0.0, 0.15)
	_tweens.append(tween)


## Поклон («Спасибо!»).
func _bow() -> void:
	var tween := create_tween()
	tween.tween_property(hips, "rotation:x", -0.5, 0.25)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.35)
	tween.tween_property(hips, "rotation:x", 0.0, 0.3)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tweens.append(tween)


# --- Материалы из палитры ---

func _paint_meshes() -> void:
	_paint($Hips/Torso, PAL.player_body)
	_paint($Hips/Head/HeadMesh, PAL.player_body)
	_paint($Hips/ArmL/ArmMesh, PAL.player_accent)
	_paint($Hips/ArmR/ArmMesh, PAL.player_accent)
	_paint($LegL/LegMesh, PAL.player_accent)
	_paint($LegR/LegMesh, PAL.player_accent)
	_paint($Hips/Head/EyeL, PAL.hud_text)
	_paint($Hips/Head/EyeR, PAL.hud_text)


func _paint(mesh: MeshInstance3D, color: Color) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	mesh.material_override = material
