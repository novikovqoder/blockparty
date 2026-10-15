# Запечка клипов Quaternius Universal Animation Library 1/2 (CC0 —
# assets/third_party/LICENSES.md) на риг Universal Base Characters
# (П5.8, часть C) — БЕЗ ретаргетинга: линейки Quaternius Universal shares
# один риг, обе rest-позы T-pose, кости совпадают с точностью до регистра
# (Head/head, Root/root). Что делает скрипт:
# - перекладывает треки выбранного клипа как есть: путь «Armature/-
#   Skeleton3D:кость» совпадает с иерархией запечённых сцен UBC
#   (UbcRoot/Armature/Skeleton3D), имя кости поднимается регистронезависимой
#   картой на риг UBC; лист-кости и неизвестные кости отбрасываются;
# - позиция pelvis масштабируется отношением rest-высот таза UBC/UAL
#   (0.949/0.917 ≈ 1.035) — ступни остаются на земле, не проваливаются;
# - клипы без аналога в UAL Standard (взмах, «Помогите!», вис у кромки,
#   «за руку») генерируются процедурно свингом поверх rest/ретаргеченной
#   базы — честная запись в docs/STATUS.md (раздел 16);
# - loop-режимы выставляются по LOOP_CLIPS (в .res, рантайм не настраивает).
#
# Исходники — glb из наборов UAL 1/2 Standard (архивы вне git в .downloads/,
# перед запуском glb копируются в импортируемую папку):
#
#   mkdir -p builds/ual_probe
#   cp ".downloads/ual/Universal Animation Library[Standard]/Unreal-Godot/UAL1_Standard.glb" builds/ual_probe/UAL1.glb
#   cp ".downloads/ual/Universal Animation Library 2[Standard]/Unreal-Godot/UAL2_Standard.glb" builds/ual_probe/UAL2.glb
#   godot --headless --path . --import
#   godot --headless --path . -s res://tools/make_ubc_anims.gd
#
# Результат — assets/third_party/quaternius.com/universal_animation_library/
# anims_ubc.res (AnimationLibrary, коммитится). Риг у полов общий (UBC),
# одна библиотека работает на ubc_male и ubc_female.
extends SceneTree

## Откуда брать glb UAL (импортируемые копии; наборы — в .downloads/).
const UAL_GLB: PackedStringArray = [
	"res://builds/ual_probe/UAL1.glb",
	"res://builds/ual_probe/UAL2.glb",
]
## Запечённая сцена UBC — rest-поза целевого рига (риг у полов общий).
const UBC_SCENE: String = "res://assets/third_party/quaternius.com/" \
	+ "universal_base_characters/baked/ubc_male.res"
## Куда писать библиотеку.
const OUT_PATH: String = "res://assets/third_party/quaternius.com/" \
	+ "universal_animation_library/anims_ubc.res"
## Путь скелета в сценах UAL и UBC — треки пишутся от родителя плеера
## (AnimationPlayer — ребёнок UbcRoot, root_node «..»).
const SKELETON_PATH: String = "Armature/Skeleton3D"

## Клипы UAL → имена в библиотеке (как в CharacterAnims.STATE_CLIPS).
## Имена — как в импортированном glb: Godot срезает суффикс «_Loop»
## (он превращается в loop_mode клипа), т.е. «Idle_Loop» в наборе = «Idle».
const BAKE_CLIPS: Dictionary = {
	# UAL 1
	"Idle": "Idle",
	"Walk": "Walk",
	"Jog_Fwd": "Jog_Fwd",
	"Sprint": "Sprint",
	"Jump_Start": "Jump_Start",
	"Jump": "Jump_Loop",
	"Jump_Land": "Jump_Land",
	"Hit_Chest": "Hit_Chest",
	"Interact": "Interact",
	"Sitting_Idle": "Sitting_Idle",
	"Idle_Talking": "Idle_Talking",
	"Dance": "Dance",
	# UAL 2
	"NinjaJump_Idle": "NinjaJump_Idle",
	"ClimbUp_1m": "ClimbUp_1m",
	"Idle_Rail_Call": "Idle_Rail_Call",
	"Idle_No": "Idle_No",
}
## Циклические клипы (покой/перемещение/полёт/вис/сидение/за руку).
const LOOP_CLIPS: PackedStringArray = [
	"Idle", "Walk", "Jog_Fwd", "Sprint", "Jump_Loop", "Sitting_Idle",
	"Hang_Pose", "Walk_Hand",
]
## Период машущих движений в процедурных клипах, с.
const SWAY_PERIOD: float = 0.85

var _bones: PackedStringArray = []
var _parent: Array[int] = []
var _rest_world: Array[Transform3D] = []
var _rest_dir: Array[Vector3] = []
var _rest_local: Array[Quaternion] = []
var _lower_to_bone: Dictionary = {}


func _init() -> void:
	print("rest UBC…")
	_read_rest()
	var clips := {}
	print("загрузка клипов…")
	for path: String in UAL_GLB:
		var scene := load(path) as PackedScene
		var root := scene.instantiate()
		var player := root.find_children("*", "AnimationPlayer", true,
			false)[0] as AnimationPlayer
		var lib := player.get_animation_library("")
		for src_name in lib.get_animation_list():
			if BAKE_CLIPS.has(String(src_name)):
				clips[String(src_name)] = lib.get_animation(src_name)
		root.free()
	assert(clips.size() == BAKE_CLIPS.size(),
		"не все клипы найдены: %d из %d" % [clips.size(), BAKE_CLIPS.size()])

	var library := AnimationLibrary.new()
	for src_name in clips:
		var out_name: String = BAKE_CLIPS[src_name]
		print("клип ", src_name, " → ", out_name)
		library.add_animation(out_name,
			_remapped(out_name, clips[src_name]))
	library.add_animation(&"Hang_Pose", _gen_hang_pose())
	library.add_animation(&"Walk_Hand", _gen_walk_hand(library.get_animation(&"Walk")))
	library.add_animation(&"Wave_Hand", _gen_arm_wave(library.get_animation(&"Idle"), false))
	library.add_animation(&"Help_Call", _gen_arm_wave(library.get_animation(&"Idle"), true))
	for clip_name in LOOP_CLIPS:
		(library.get_animation(clip_name) as Animation).loop_mode = \
			Animation.LOOP_LINEAR

	var err := ResourceSaver.save(library, OUT_PATH)
	assert(err == OK, "ResourceSaver: %s" % err)
	print("Запечено %d клипов → %s" % [library.get_animation_list().size(),
		OUT_PATH])
	quit()


## Rest-поза рига UBC: мировые (в пространстве скелета) базисы и направления.
func _read_rest() -> void:
	var scene := load(UBC_SCENE) as PackedScene
	var root := scene.instantiate()
	var sk := root.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	for i in sk.get_bone_count():
		_bones.append(sk.get_bone_name(i))
		_parent.append(sk.get_bone_parent(i))
		var w := sk.get_bone_global_rest(i)
		_rest_world.append(w)
		_rest_dir.append(w.basis.y.normalized())
		_rest_local.append(sk.get_bone_rest(i).basis.get_rotation_quaternion())
		_lower_to_bone[sk.get_bone_name(i).to_lower()] = i
	root.free()


## Переложить клип UAL на риг UBC: имена костей — регистронезависимо, путь
## скелета тот же; позиция pelvis — умножением на отношение rest-высот таза.
func _remapped(out_name: String, anim: Animation) -> Animation:
	var out := Animation.new()
	out.resource_name = out_name
	out.length = anim.length
	out.loop_mode = anim.loop_mode  # импортёр уже распознал суффикс «_Loop»
	# Отношение rest-высот таза UBC/UAL: позиция анимации переносится с масштабом.
	var pelvis_ratio := 0.949 / 0.917
	for i in anim.get_track_count():
		var path := anim.track_get_path(i)
		var bone_idx: int = _lower_to_bone.get(
			String(path.get_subname(path.get_subname_count() - 1)).to_lower(), -1)
		if bone_idx < 0:
			continue  # лист-кости UAL и нериговые треки на UBC нет кого везти
		match anim.track_get_type(i):
			Animation.TYPE_ROTATION_3D, Animation.TYPE_POSITION_3D:
				var ti := out.add_track(anim.track_get_type(i))
				out.track_set_path(ti, NodePath("%s:%s"
					% [SKELETON_PATH, _bones[bone_idx]]))
				out.track_set_interpolation_type(ti,
					anim.track_get_interpolation_type(i))
				for k in anim.track_get_key_count(i):
					var value: Variant = anim.track_get_key_value(i, k)
					if anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
						value = (value as Vector3) * pelvis_ratio
					out.track_insert_key(ti, anim.track_get_key_time(i, k), value)
			_:
				pass  # масштаб и прочие типы треков UAL не несёт
	return out


# --- Процедурные клипы (нет аналогов в UAL Standard) ---
# Фикс Д1 (руки выкручивало): старый генератор наводил только направление
# оси кости минимальным свингом — ролл вокруг оси кости не контролировался
# и при качании «гулял» по кадрам (закрученные кисть/локоть). Теперь
# ориентация кости задаётся в мире ДВУМЯ наведениями + шарниром:
#   dir     — куда смотрит ось кости (basis.y, от родительского сустава);
#   aim_dir — куда смотреть вторичной осью aim_axis (rest-базис кости,
#             по умолчанию basis.z): ролл вокруг dir подбирается так, чтобы
#             проекция aim-оси на плоскость ⊥ dir смотрела на aim_dir —
#             ладонь/локоть контролируются явно и стабильно по кадрам;
#   sway_axis/sway_angle/sway_phase — качание вокруг ФИКСИРОВАННОЙ мировой
#             оси (шарнир): ролл стабилен по построению, ладонь не выкручивает.
# В rest у костей рук UBC: basis.y — вдоль руки, basis.x — вверх, basis.z —
# вперёд (T-pose). Нормаль ладони кисти — −basis.x (ладони вниз в T-pose),
# поэтому ладонь к зрителю держим наведением оси (−1,0,0) в (0,0,1).


## Спека ориентации одной кости (все поля, кроме dir, опциональны).
func _pose(dir: Vector3, aim_dir: Vector3 = Vector3.ZERO,
		aim_axis: Vector3 = Vector3(0.0, 0.0, 1.0),
		sway_axis: Vector3 = Vector3.ZERO, sway_angle: float = 0.0,
		sway_phase: float = 0.0) -> Dictionary:
	var spec := {"dir": dir.normalized()}
	if aim_dir != Vector3.ZERO:
		spec["aim_dir"] = aim_dir.normalized()
		spec["aim_axis"] = aim_axis.normalized()
	if sway_axis != Vector3.ZERO:
		spec["sway_axis"] = sway_axis.normalized()
		spec["sway_angle"] = sway_angle
		spec["sway_phase"] = sway_phase
	return spec


## Мировая ориентация кости i по спеке в момент t.
func _aimed_world(i: int, spec: Dictionary, t: float) -> Quaternion:
	var dir: Vector3 = (spec["dir"] as Vector3).normalized()
	var q := _swing(_rest_dir[i], dir) \
		* _rest_world[i].basis.get_rotation_quaternion()
	if spec.has("aim_dir"):
		q = _roll_to_aim(q, dir, spec["aim_axis"], spec["aim_dir"])
	if spec.has("sway_axis"):
		var ang: float = spec["sway_angle"] \
			* sin(TAU * t / SWAY_PERIOD + spec["sway_phase"])
		q = Quaternion(spec["sway_axis"] as Vector3, ang) * q
	return q


## Докрутка вокруг оси кости dir: проекция aim-оси на плоскость ⊥ dir
## поворачивается на aim_dir. Держит ролл заданным, не минимальным.
func _roll_to_aim(q1: Quaternion, dir: Vector3, aim_axis: Vector3,
		aim_dir: Vector3) -> Quaternion:
	var cur := (q1 * aim_axis).normalized()
	var cur_p := cur - dir * cur.dot(dir)
	var tgt_p := aim_dir - dir * aim_dir.dot(dir)
	if cur_p.length_squared() < 1e-9 or tgt_p.length_squared() < 1e-9:
		return q1  # aim-ось вдоль кости — ролль не определить, оставляем свинг
	cur_p = cur_p.normalized()
	tgt_p = tgt_p.normalized()
	var ang := atan2(cur_p.cross(tgt_p).dot(dir), cur_p.dot(tgt_p))
	return Quaternion(dir, ang) * q1


## Вис у кромки расщелины: руки над головой почти прямые (вис на выпрямленных
## руках — локоть ~157°), кисти на ширине плеч, ладони вперёд (обхват кромки);
## ноги слегка поджаты. Тело прямое — остальное в rest.
func _gen_hang_pose() -> Animation:
	var anim := Animation.new()
	anim.resource_name = "Hang_Pose"
	anim.length = 1.5
	var times: Array[float] = []
	for k in int(anim.length * 30.0) + 1:
		times.push_back(minf(k / 30.0, anim.length))
	var overrides := {
		"upperarm_l": _pose(Vector3(-0.26, 0.96, 0.02)),
		"lowerarm_l": _pose(Vector3(-0.10, 0.99, 0.02)),
		"hand_l": _pose(Vector3(-0.06, 0.998, 0.02), Vector3(0.0, 0.0, 1.0),
			Vector3(-1.0, 0.0, 0.0)),
		"upperarm_r": _pose(Vector3(0.26, 0.96, 0.02)),
		"lowerarm_r": _pose(Vector3(0.10, 0.99, 0.02)),
		"hand_r": _pose(Vector3(0.06, 0.998, 0.02), Vector3(0.0, 0.0, 1.0),
			Vector3(-1.0, 0.0, 0.0)),
		"thigh_l": _pose(Vector3(0.0, -0.87, 0.49)),
		"calf_l": _pose(Vector3(0.0, -0.90, -0.43)),
		"foot_l": _pose(Vector3(0.0, -0.40, 0.92)),
		"thigh_r": _pose(Vector3(0.0, -0.87, 0.49)),
		"calf_r": _pose(Vector3(0.0, -0.90, -0.43)),
		"foot_r": _pose(Vector3(0.0, -0.40, 0.92)),
	}
	# База — пустая анимация (все кости в rest), треки только на override-кости.
	var scratch := Animation.new()
	scratch.length = anim.length
	var bones: Array[int] = []
	for bone in overrides:
		var idx: int = _lower_to_bone.get(String(bone), -1)
		assert(idx >= 0, "нет кости %s" % bone)
		bones.append(idx)
	_fill_overrides(anim, times, scratch, bones, overrides)
	return anim


## «За руку»: ходьба с вытянутой к ведущему рукой — вперёд и вбок, чуть ниже
## плеча, ладонь вперёд (база — запечённая ходьба UAL, правая рука каждый
## кадр наведена на ведущего).
func _gen_walk_hand(walk_src: Animation) -> Animation:
	return _with_overrides(walk_src, "Walk_Hand", {
		"upperarm_r": _pose(Vector3(0.30, -0.18, 0.93)),
		"lowerarm_r": _pose(Vector3(0.28, -0.16, 0.94)),
		"hand_r": _pose(Vector3(0.27, -0.15, 0.95), Vector3(0.0, 0.0, 1.0),
			Vector3(-1.0, 0.0, 0.0)),
	})


## Взмах одной рукой («Привет!»), both — «Помогите!» обеими руками.
## Геометрия человеческого взмаха: плечо почти горизонтально (подъём ~103°
## от «вниз»), предплечье вверх от локтя (сгиб локтя ~110°), ладонь вперёд.
## Качание — шарнир вокруг мировой оси Z (вперёд): предплечье ходит
## в боковой плоскости, ладонь к зрителю всю дорогу, ролл стабилен.
## У Help_Call руки выше (V над головой, качание симметричное наружу).
func _gen_arm_wave(idle_src: Animation, both: bool) -> Animation:
	var clip_name := "Help_Call" if both else "Wave_Hand"
	var overrides := {}
	if both:
		overrides = {
			"upperarm_r": _pose(Vector3(0.72, 0.68, 0.06),
				Vector3.ZERO, Vector3(0.0, 0.0, 1.0), Vector3(0.0, 0.0, 1.0), 0.08),
			"lowerarm_r": _pose(Vector3(0.30, 0.95, 0.06),
				Vector3.ZERO, Vector3(0.0, 0.0, 1.0), Vector3(0.0, 0.0, 1.0), 0.40),
			"hand_r": _pose(Vector3(0.32, 0.94, 0.10),
				Vector3(0.0, 0.0, 1.0), Vector3(-1.0, 0.0, 0.0),
				Vector3(0.0, 0.0, 1.0), 0.26),
			"upperarm_l": _pose(Vector3(-0.72, 0.68, 0.06),
				Vector3.ZERO, Vector3(0.0, 0.0, 1.0), Vector3(0.0, 0.0, 1.0), -0.08),
			"lowerarm_l": _pose(Vector3(-0.30, 0.95, 0.06),
				Vector3.ZERO, Vector3(0.0, 0.0, 1.0), Vector3(0.0, 0.0, 1.0), -0.40),
			"hand_l": _pose(Vector3(-0.32, 0.94, 0.10),
				Vector3(0.0, 0.0, 1.0), Vector3(-1.0, 0.0, 0.0),
				Vector3(0.0, 0.0, 1.0), -0.26),
		}
	else:
		overrides = {
			"upperarm_r": _pose(Vector3(0.95, 0.22, 0.05),
				Vector3.ZERO, Vector3(0.0, 0.0, 1.0), Vector3(0.0, 0.0, 1.0), 0.10),
			"lowerarm_r": _pose(Vector3(0.10, 0.99, 0.05),
				Vector3.ZERO, Vector3(0.0, 0.0, 1.0), Vector3(0.0, 0.0, 1.0), 0.45),
			"hand_r": _pose(Vector3(0.14, 0.98, 0.10),
				Vector3(0.0, 0.0, 1.0), Vector3(-1.0, 0.0, 0.0),
				Vector3(0.0, 0.0, 1.0), 0.30),
		}
	return _with_overrides(idle_src, clip_name, overrides)


## Перезапись костей поверх готового клипа: локали читаются из треков base,
## override-кости пересчитываются свингом (родители — из того же клипа),
## результат собирается в новую Animation. Позиционные треки копируются.
func _with_overrides(base: Animation, clip_name: String,
		overrides: Dictionary) -> Animation:
	var times := _sample_times(base)
	var out := Animation.new()
	out.resource_name = clip_name
	out.length = base.length
	var bones: Array[int] = []
	for i in base.get_track_count():
		var bone_name := _bone_of_track(base.track_get_path(i))
		var bone_idx: int = _lower_to_bone.get(bone_name.to_lower(), -1)
		if bone_idx < 0:
			continue
		if base.track_get_type(i) == Animation.TYPE_POSITION_3D:
			var pt := _add_track(out, Animation.TYPE_POSITION_3D, bone_idx)
			for k in times.size():
				out.position_track_insert_key(pt, times[k],
					base.track_get_key_value(i, _nearest_key(base, i, times[k])))
		else:
			bones.append(bone_idx)
	_fill_overrides(out, times, base, bones, overrides)
	return out


## Общий проход: по кадрам собирает локали из base (нет трека — rest),
## поднимает до мировых, для override-костей считает свинг в заданное
## направление и пишет поворотные треки перечисленных костей.
func _fill_overrides(out: Animation, times: Array[float], base: Animation,
		bones: Array[int], overrides: Dictionary) -> void:
	var base_track_of := {}
	for i in base.get_track_count():
		if base.track_get_type(i) == Animation.TYPE_ROTATION_3D:
			base_track_of[_bone_of_track(base.track_get_path(i)).to_lower()] = i
	var track_of := {}
	for tgt in bones:
		track_of[tgt] = _add_track(out, Animation.TYPE_ROTATION_3D, tgt)
	for k in times.size():
		var t := times[k]
		var locals: Array[Quaternion] = []
		locals.resize(_bones.size())
		for i in _bones.size():
			var ti: int = base_track_of.get(_bones[i].to_lower(), -1)
			if ti >= 0:
				locals[i] = base.track_get_key_value(ti,
					_nearest_key(base, ti, t))
			else:
				locals[i] = _rest_local[i]
		var worlds: Array[Quaternion] = []
		worlds.resize(_bones.size())
		for i in _bones.size():
			var parent_q := worlds[_parent[i]] \
				if _parent[i] >= 0 else Quaternion.IDENTITY
			if overrides.has(_bones[i].to_lower()):
				var spec: Dictionary = overrides[_bones[i].to_lower()]
				locals[i] = parent_q.inverse() * _aimed_world(i, spec, t)
			worlds[i] = parent_q * locals[i]
		for tgt in bones:
			out.rotation_track_insert_key(track_of[tgt], t, locals[tgt])


## Минимальный поворот, приводящий from к to (без поворота вокруг to).
func _swing(from: Vector3, to: Vector3) -> Quaternion:
	var cross := from.cross(to)
	if cross.length_squared() < 1e-12:
		return Quaternion.IDENTITY
	return Quaternion(cross.normalized(),
		acos(clampf(from.dot(to), -1.0, 1.0))).normalized()


func _sample_times(anim: Animation) -> Array[float]:
	var times: Array[float] = []
	var n := int(ceilf(anim.length * 30.0)) + 1
	for k in n:
		times.push_back(minf(k / 30.0, anim.length))
	if times.size() > 1 and is_equal_approx(times[times.size() - 1],
			times[times.size() - 2]):
		times.pop_back()
	return times


func _nearest_key(anim: Animation, track: int, t: float) -> int:
	var best := 0
	var best_dt := INF
	for k in anim.track_get_key_count(track):
		var dt: float = absf(anim.track_get_key_time(track, k) - t)
		if dt < best_dt:
			best_dt = dt
			best = k
	return best


func _bone_of_track(path: NodePath) -> String:
	return String(path.get_subname(path.get_subname_count() - 1))


## Трек под кость цели (по индексу), возвращает индекс трека.
func _add_track(anim: Animation, type: int, bone_idx: int) -> int:
	var ti := anim.add_track(type)
	anim.track_set_path(ti, NodePath("%s:%s" % [SKELETON_PATH,
		_bones[bone_idx]]))
	anim.track_set_interpolation_type(ti, Animation.INTERPOLATION_LINEAR)
	return ti
