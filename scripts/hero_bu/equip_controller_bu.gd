class_name EquipControllerBU
extends Node
## Снаряжение героя. Меч висит на левом бедре; колёсико мыши листает слоты
## (руки ↔ меч). С анимациями: при выборе меча играет «достать меч», и в момент,
## когда ладонь на рукояти, меч перецепляется с пояса в руку; при выборе рук —
## «убрать меч» и обратно на пояс. Без анимаций меч плавно переносится сам.
## Ставится дочерним узлом героя. Нужен Skeleton3D со скелетом Mixamo
## (кости «mixamorig_…» после импорта; префикс определяется сам).

signal slot_changed(slot: StringName)
## Анимация снаряжения закончилась — можно возвращать обычные анимации движения.
signal equip_finished(slot: StringName)

const SLOTS: Array[StringName] = [&"hands", &"sword"]

@export var skeleton_path: NodePath
@export var animation_player_path: NodePath
@export var sword_scene: PackedScene
@export_group("Анимации")
@export var draw_animation: StringName = &"sword/draw_sword_2"
@export var sheath_animation: StringName = &"sword/sheath_sword_1"
## Момент, когда ладонь на рукояти у пояса (секунды от начала анимации).
@export var draw_contact_time: float = 0.03
@export var sheath_contact_time: float = 1.16
@export var armed_idle_animation: StringName = &"sword/ss_idle"
## Стойка без оружия; пусто — не переключать (оставить, что играло).
@export var unarmed_idle_animation: StringName = &""
@export_group("Без анимаций")
@export var move_time: float = 0.45
@export var wheel_enabled: bool = true

var slot: StringName = &"hands"
var sword: Node3D
var busy: bool = false

var _sk: Skeleton3D
var _ap: AnimationPlayer
var _hand_att: BoneAttachment3D
var _hip_att: BoneAttachment3D
var _grip_xf: Transform3D
var _sheath_xf: Transform3D
## Переход без анимаций
var _moving: bool = false
var _t: float = 0.0
var _start: Transform3D
var _to: Node3D
var _to_local: Transform3D
## Переход с анимацией
var _anim_t: float = -1.0
var _contact: float = 0.0
var _switched: bool = false


func _ready() -> void:
	_sk = get_node(skeleton_path) as Skeleton3D
	if not animation_player_path.is_empty():
		_ap = get_node(animation_player_path) as AnimationPlayer
	_hand_att = BoneAttachment3D.new()
	_hand_att.name = "RightHandMount"
	var pre: String = WeaponMountsBU.prefix_of(_sk)
	_hand_att.bone_name = pre + "RightHand"
	_sk.add_child(_hand_att)
	_hip_att = BoneAttachment3D.new()
	_hip_att.name = "HipMount"
	_hip_att.bone_name = pre + "Hips"
	_sk.add_child(_hip_att)
	_grip_xf = WeaponMountsBU.grip_in_hand(_sk)
	if _ap and _ap.has_animation(draw_animation):
		# меч на поясе ровно там и так, как его берёт рука в начале анимации «достать меч»
		_sheath_xf = WeaponMountsBU.sheath_from_draw(_sk, _ap.get_animation(draw_animation), 0.0)
	else:
		_sheath_xf = WeaponMountsBU.sheath_on_hip(_sk)
	if sword_scene:
		sword = sword_scene.instantiate() as Node3D
		sword.name = "Sword"
		_hip_att.add_child(sword)
		sword.transform = _sheath_xf


func _unhandled_input(event: InputEvent) -> void:
	if not wheel_enabled or not event is InputEventMouseButton:
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
		cycle(1)
	elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		cycle(-1)


func cycle(dir: int) -> void:
	var i: int = SLOTS.find(slot)
	select(SLOTS[posmod(i + dir, SLOTS.size())])


func select(new_slot: StringName) -> void:
	if busy or new_slot == slot or sword == null:
		return
	slot = new_slot
	busy = true
	slot_changed.emit(slot)
	var anim_name: StringName = draw_animation if slot == &"sword" else sheath_animation
	if _ap and _ap.has_animation(anim_name):
		_ap.play(anim_name, 0.15)
		_anim_t = 0.0
		_switched = false
		_contact = draw_contact_time if slot == &"sword" else sheath_contact_time
	elif slot == &"sword":
		_begin_move(_hand_att, _grip_xf)
	else:
		_begin_move(_hip_att, _sheath_xf)


## Перецепить меч, сохранив его положение на экране, и за blend_time довести до места.
@export var blend_time: float = 0.2
var _blend_t: float = -1.0
var _blend_from: Transform3D
var _blend_to: Transform3D


func _attach_now(smooth: bool = true) -> void:
	var target_parent: Node3D = _hand_att if slot == &"sword" else _hip_att
	_blend_to = _grip_xf if slot == &"sword" else _sheath_xf
	sword.top_level = false
	sword.reparent(target_parent, true)
	if smooth and blend_time > 0.0:
		_blend_from = sword.transform
		_blend_t = 0.0
	else:
		sword.transform = _blend_to
		_blend_t = -1.0


func _begin_move(to: Node3D, to_local: Transform3D) -> void:
	_to = to
	_to_local = to_local
	_t = 0.0
	_moving = true
	_start = sword.global_transform
	sword.top_level = true
	sword.global_transform = _start


func _finish() -> void:
	busy = false
	if _ap:
		var idle: StringName = armed_idle_animation if slot == &"sword" else unarmed_idle_animation
		if _ap.has_animation(idle):
			_ap.play(idle, 0.25)
	equip_finished.emit(slot)


func _process(delta: float) -> void:
	if _blend_t >= 0.0:
		_blend_t = minf(_blend_t + delta, blend_time)
		var kb: float = smoothstep(0.0, 1.0, _blend_t / blend_time)
		var p: Vector3 = _blend_from.origin.lerp(_blend_to.origin, kb)
		var q: Quaternion = _blend_from.basis.get_rotation_quaternion().slerp(_blend_to.basis.get_rotation_quaternion(), kb)
		sword.transform = Transform3D(Basis(q), p)
		if _blend_t >= blend_time:
			_blend_t = -1.0
	if _anim_t >= 0.0:
		_anim_t += delta
		if not _switched and _anim_t >= _contact:
			_attach_now()
			_switched = true
		if not _ap.is_playing() or _anim_t >= _ap.current_animation_length:
			_anim_t = -1.0
			if not _switched:
				_attach_now()
			_finish()
	if not _moving:
		return
	_t = minf(_t + delta, move_time)
	var k: float = smoothstep(0.0, 1.0, _t / maxf(move_time, 0.001))
	var target: Transform3D = _to.global_transform * _to_local
	var pos: Vector3 = _start.origin.lerp(target.origin, k)
	var rot: Quaternion = _start.basis.get_rotation_quaternion().slerp(target.basis.get_rotation_quaternion(), k)
	sword.global_transform = Transform3D(Basis(rot), pos)
	if _t >= move_time:
		_moving = false
		_attach_now(false)
		_finish()
