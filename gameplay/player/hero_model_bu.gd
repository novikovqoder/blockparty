# Герой Born Unblessed: рыцарь в багровом капюшоне (MakeHuman, CC0 —
# assets/hero_bu/LICENSES_hero_bu.md) — модель игрока и чужих игроков.
# Модель одна на всех (редактора внешности больше нет — born-unblessed).
# Анимации — пак Mixamo
# «Pro Sword and Shield», перенесённый tools/retarget_mixamo_bu.gd в
# assets/hero/hero_sword_anims.res и нарезанный tools/slice_locomotion_bu.gd
# (клипы loco_*: у корня вычищен вшитый «пробег», прыжок разрезан на фазы).
# Локомоция: покой/шаг/бег — loco_*, прыжок — loco_jump_up/fly/land,
# поворот на месте — loco_turn (разовый, при быстром повороте модели в покое).
# Клипов «сесть», «помахать», жестов эмоций, вытягивания и «за руку» в паке
# нет — временно не играются (механики работают, эмоции показывает пузырь).
# Меч — EquipControllerBU (комплект меча): на поясе, колёсико «руки ↔ меч»,
# выхватывание/убирание; на время смены (busy) клипы состояния не перебивают
# анимацию снаряжения. Моргание — BlinkLidsBU внутри hero_bu.tscn, поверх
# любой анимации, у каждого игрока локально.
class_name HeroModelBU
extends CharacterVisual

const HERO_SCENE: PackedScene = preload("res://assets/hero_bu/hero_bu.tscn")
const ANIMS: AnimationLibrary = preload("res://assets/hero/hero_sword_anims.res")
const SWORD_SCENE: PackedScene = preload("res://assets/sword_bu/sword_bu.glb")
## Имя библиотеки внутри AnimationPlayer (клипы «sword/…», как у комплекта меча).
const LIB_NAME: StringName = &"sword"

## Состояние (Protocol.AnimState) → клип; чего в паке нет — не играется
## (set_state ставит loco_idle, разовые просто пропускаются).
const STATE_CLIPS: Dictionary = {
	Protocol.AnimState.IDLE: &"loco_idle",
	Protocol.AnimState.WALK: &"loco_walk",
	Protocol.AnimState.RUN: &"loco_run",
	Protocol.AnimState.JUMP: &"loco_jump_up",
	Protocol.AnimState.FALL: &"loco_jump_fly",
	Protocol.AnimState.LAND: &"loco_jump_land",
}
## Разовые клипы (play_one_shot) — только удар с мечом: ss_slash.
const ATTACK_CLIP: StringName = &"ss_slash"

## Естественная скорость локомоционных клипов, м/с (замер по треку Hips пака:
## loco_walk 1,5 м за 1,1 с, loco_run 2,69 м за 0,7 с) — темп speed_scale =
## скорость/natural, стопы не скользят.
const NATURAL_SPEED: Dictionary = {
	&"loco_walk": 1.36,
	&"loco_run": 3.84,
}
## Пределы темпа: ниже — шаг замирает, выше — мельтешение (у BU шире UBC:
## скорость игры 2,5 м/с против natural шага 1,36).
const SPEED_SCALE_MIN: float = 0.55
const SPEED_SCALE_MAX: float = 2.0
## Плавный переход между клипами и сглаживание темпа ног.
const ANIM_BLEND: float = 0.15
const LOCO_SMOOTH: float = 10.0

## Поворот на месте: за это окно |поворота модели| больше порога — сыграть
## loco_turn; окно/порог подобраны по model_turn_speed 12 (рад/с).
const TURN_WINDOW: float = 0.35
const TURN_TRIGGER: float = 0.55
## После разового клипа поворота — пауза, с (иначе переигрывается каждое окно).
const TURN_COOLDOWN: float = 0.4

## Колёсико мыши листает слоты «руки ↔ меч» (включает локальный игрок;
## у чужих стоит false, чтобы чужие модели не реагировали на моё колёсико).
@export var sword_wheel: bool = false

var _hero: Node3D = null
var _player: AnimationPlayer = null
var _skeleton: Skeleton3D = null
var equip: EquipControllerBU = null
var _state: int = Protocol.AnimState.IDLE
## Сколько ещё играть разовый клип, с; < 0 — не играет.
var _one_shot_left: float = -1.0
var _loco_target: float = 0.0
var _loco_display: float = 0.0
## Поворот на месте: накопленный |Δyaw| за окно и время с последнего клипа.
var _turn_accum: float = 0.0
var _turn_last_yaw: float = 0.0
var _turn_lock: float = 0.0


func _ready() -> void:
	_hero = HERO_SCENE.instantiate() as Node3D
	add_child(_hero)
	_skeleton = _hero.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	# Плеер — ребёнок корня героя: треки библиотеки записаны путями
	# «Armature/Skeleton3D:<кость>» от него (root_node по умолчанию «..»).
	_player = AnimationPlayer.new()
	_player.name = "HeroAnims"
	_hero.add_child(_player)
	_player.add_animation_library(LIB_NAME, ANIMS)
	# Меч (комплект меча П10): на поясе, выхватывание/убирание по анимациям.
	# Пути задаются до add_child — EquipControllerBU резолвит их в своём _ready.
	# Узел меча — ребёнок HeroModelBU, поэтому «..» к корню и дальше внутрь героя.
	equip = EquipControllerBU.new()
	equip.name = "EquipBU"
	equip.wheel_enabled = sword_wheel
	equip.skeleton_path = NodePath("../%s/%s" % [_hero.name, _hero.get_path_to(_skeleton)])
	equip.animation_player_path = NodePath("../%s/%s" % [_hero.name, _hero.get_path_to(_player)])
	equip.sword_scene = SWORD_SCENE
	add_child(equip)
	# Пока идёт выхватывание/убирание, клипы состояния меч не перебивают;
	# по окончании возвращаем состояние сами.
	equip.equip_finished.connect(_on_equip_finished)
	_quality_materials()
	set_state(_state)


func set_state(state: int) -> void:
	_state = state
	if _defer_by_one_shot() or _defer_by_equip():
		return
	var clip: StringName = STATE_CLIPS.get(state, &"")
	if clip == &"":
		# Клипа нет (сесть, вис, жесты…): нейтральный покой, если сейчас
		# играет локомоция — стоять в позе покоя лучше, чем идти на месте.
		clip = &"loco_idle"
	if _is_locomotion(state):
		_apply_locomotion()
		return
	if _playing_clip() != clip:
		_play_clip(clip, 1.0)


func set_locomotion_speed(mps: float) -> void:
	_loco_target = maxf(mps, 0.0)


## Разовый клип: у героя BU это удар (ss_slash). Прочие разовые (взмах,
## «тычок», приземление, эмоции) клипов пака не имеют — пропускаются.
func play_one_shot(state: int, duration: float) -> void:
	if _player == null or _defer_by_equip():
		return
	if state == Protocol.AnimState.LAND:
		_play_fitted(&"loco_jump_land", duration, 0.55, 3.0)
	# Остальные разовые состояния клипов не имеют (STATUS, П10).


## Удар (раздел 5): со мечом и без — замах ss_slash, темп подогнан под окно
## удара, но не быстрее 0,9× (иначе движение не читается).
func play_attack(duration: float) -> void:
	if _player == null or _defer_by_equip():
		return
	_play_fitted(ATTACK_CLIP, duration, 0.9, 2.2)


## Покадровое продвижение (съёмка серий при Engine.time_scale = 0).
func advance_preview(delta: float) -> void:
	if _one_shot_left > 0.0:
		_one_shot_left -= delta
		if _one_shot_left <= 0.0:
			set_state(_state)
	if _player != null:
		_player.advance(delta)


func anim_player() -> AnimationPlayer:
	return _player


func skeleton() -> Skeleton3D:
	return _skeleton


## Планка качества текстур (П5.9, тест аудита): материалы героя и меча
## приходят из GLB с линейным фильтром (3) — переводим в анизотропный
## (мип-мапы + 16x). Ресурсы сцен общие для всех копий героя — значение
## идемпотентно.
func _quality_materials() -> void:
	for node: Node in find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for i: int in mi.get_surface_override_material_count():
			var mat: Material = mi.get_active_material(i)
			if mat is BaseMaterial3D:
				(mat as BaseMaterial3D).texture_filter = \
					BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC


## Меч ли сейчас в руке (для тестов и будущих состояний с оружием).
func is_sword_drawn() -> bool:
	return equip != null and equip.slot == &"sword"


func head_top_height() -> float:
	return _mesh_bounds().end.y


func lowest_point() -> float:
	return _mesh_bounds().position.y


func _process(delta: float) -> void:
	if _player == null:
		return
	if _one_shot_left > 0.0:
		_one_shot_left -= delta
		if _one_shot_left <= 0.0:
			set_state(_state)
		return
	_track_turn_in_place(delta)
	if _is_locomotion(_state) and not _defer_by_equip():
		_loco_display = lerpf(_loco_display, _loco_target,
			minf(delta * LOCO_SMOOTH, 1.0))
		_apply_locomotion()


# --- Внутреннее ---

## Разовый клип доигрывает и сам вернёт состояние.
func _defer_by_one_shot() -> bool:
	return _one_shot_left > 0.0


## Идёт выхватывание/убирание меча — анимацию снаряжения не перебиваем
## (комплект меча: busy == true до equip_finished).
func _defer_by_equip() -> bool:
	return equip != null and equip.busy


func _on_equip_finished(_slot: StringName) -> void:
	_one_shot_left = -1.0
	set_state(_state)


func _is_locomotion(state: int) -> bool:
	return state == Protocol.AnimState.WALK or state == Protocol.AnimState.RUN


func _apply_locomotion() -> void:
	var clip := STATE_CLIPS.get(_state, &"loco_idle") as StringName
	if _playing_clip() != clip:
		_play_clip(clip, _speed_scale(clip))
	else:
		_player.speed_scale = _speed_scale(clip)


func _speed_scale(clip: StringName) -> float:
	var natural: float = float(NATURAL_SPEED.get(clip, 1.0))
	return clampf(_loco_display / natural, SPEED_SCALE_MIN, SPEED_SCALE_MAX)


func _playing_clip() -> StringName:
	if _player == null or _player.current_animation.is_empty():
		return &""
	var full: PackedStringArray = _player.current_animation.split("/")
	return StringName(full[full.size() - 1])


func _play_clip(clip: StringName, speed: float) -> void:
	_player.speed_scale = speed
	_player.play("%s/%s" % [LIB_NAME, clip], ANIM_BLEND)


## Разовый клип с темпом length/duration в пределах [min_s, max_s].
func _play_fitted(clip: StringName, duration: float, min_s: float, max_s: float) -> void:
	var length: float = (_player.get_animation("%s/%s" % [LIB_NAME, clip]) as Animation).length
	var speed: float = clampf(length / maxf(duration, 0.05), min_s, max_s)
	_one_shot_left = length / speed
	_play_clip(clip, speed)


## Поворот на месте (SPEC П10: «поворот» из клипов пака): в покое модель
## игрока разворачивается камерой/движением — накопили быстрый поворот,
## сыграли loco_turn (шаговый разворот без вшитого смещения — корень чищен).
func _track_turn_in_place(delta: float) -> void:
	_turn_lock = maxf(_turn_lock - delta, 0.0)
	var parent: Node3D = get_parent() as Node3D
	if parent == null:
		return
	var yaw: float = parent.rotation.y
	if _state == Protocol.AnimState.IDLE and _one_shot_left <= 0.0:
		_turn_accum += absf(angle_difference(yaw, _turn_last_yaw))
		if _turn_accum > TURN_TRIGGER and _turn_lock <= 0.0:
			_play_fitted(&"loco_turn", 0.6, 0.8, 1.4)
			_turn_accum = 0.0
			_turn_lock = TURN_COOLDOWN + 0.5
	else:
		_turn_accum = 0.0
	_turn_last_yaw = yaw


func _mesh_bounds() -> AABB:
	var box := AABB()
	var first := true
	for node: Node in _hero.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if not mi.visible or mi.mesh == null:
			continue
		var b: AABB = mi.transform * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box if not first else AABB(Vector3.ZERO, Vector3.ONE)
