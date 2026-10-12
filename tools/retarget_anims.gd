# Ретаргетинг анимаций Quaternius Universal Animation Library (CC0) на скелет
# MPFB персонажей (П5.7, блок 5). Исходники — glb из наборов UAL 1/2 Standard
# (лицензии — assets/third_party/LICENSES.md; архивы лежат вне git в
# .downloads/, перед запуском glb копируются в импортируемую папку):
#
#   cp ".downloads/ual/Universal Animation Library[Standard]/Unreal-Godot/UAL1_Standard.glb" builds/ual_probe/UAL1.glb
#   cp ".downloads/ual/Universal Animation Library 2[Standard]/Unreal-Godot/UAL2_Standard.glb" builds/ual_probe/UAL2.glb
#   godot --headless --path . --import
#   godot --headless --path . -s res://tools/retarget_anims.gd
#
# Результат — assets/third_party/quaternius.com/universal_animation_library/
# anims_mpfb.res (AnimationLibrary, коммитится). Треки пишутся сразу путями
# «Human_rig_export/Skeleton3D:<кость>» — дерево узлов glb всех трёх
# персонажей одинаково (риг один), поэтому одна библиотека работает на всех.
#
# Математика. Риги близки (UE-конвенция имён), но rest-позы разные: UAL —
# T-pose (руки горизонтально), MPFB — A-pose (~48° вниз, предплечья вперёд),
# поэтому простая передача локальных дельт уводит руки сквозь тело. Переносим
# «мировые» направления костей: направление кости в анимации источника
# становится направлением кости цели (тем самым разница rest-поз гасится), а
# твист источника вокруг оси кости — локальной добавкой:
#   W_rest  — накопленный rest-базис кости в пространстве скелета;
#   d       — ось Y базиса («вдоль кости» в обоих ригах);
#   W_tgt   = swing(d_rest_t → d_anim_s) ⊗ W_rest_t ⊗ Twist(φ);
#   local_t = W_tgt_parent⁻¹ ⊗ W_tgt (родители — уже ретаргеченные).
# Незакеенные в источнике кости остаются в rest-позе цели (трек не пишем).
# Позиция переносится только у pelvis, с масштабом отношения rest-высот.
#
# Клипы без аналога в Standard-наборах (взмах, «за руку», вис у кромки,
# «Помогите!» обеими руками) генерируются процедурно поверх ретаргеченных
# баз (Idle/Walk) или rest-позы — честная запись об этом в docs/STATUS.md.
extends SceneTree

## Откуда брать glb UAL (импортируемые копии; сами наборы — в .downloads/).
const UAL_GLB: PackedStringArray = [
	"res://builds/ual_probe/UAL1.glb",
	"res://builds/ual_probe/UAL2.glb",
]
## glb персонажа — источник rest-позы целевого рига (риг у троих один).
const CHARACTER_GLB: String = \
	"res://assets/third_party/makehumancommunity.org/finn/finn.glb"
## Куда писать библиотеку.
const OUT_PATH: String = "res://assets/third_party/quaternius.com/" \
	+ "universal_animation_library/anims_mpfb.res"
## Путь скелета внутри glb персонажей — треки пишутся относительно корня glb
## (AnimationPlayer в CharacterModel сидит ребёнком корня, root_node = родитель).
const SKELETON_PATH: String = "Human_rig_export/Skeleton3D"

## Переносимые клипы UAL → имена как есть в наборах.
const BAKE_CLIPS: PackedStringArray = [
	# UAL 1
	"Idle", "Walk", "Jog_Fwd", "Jump_Start", "Jump_Land", "Hit_Chest",
	"Interact", "Sitting_Idle", "Idle_Talking", "Dance",
	# UAL 2
	"NinjaJump_Idle", "ClimbUp_1m", "Idle_Rail_Call", "Idle_No",
]
## Циклические клипы (покой/перемещение/полёт/сидение/за руку).
const LOOP_CLIPS: PackedStringArray = [
	"Idle", "Walk", "Jog_Fwd", "NinjaJump_Idle", "Sitting_Idle",
	"Hang_Pose", "Walk_Hand",
]
## Частота запекания, ключей/с.
const FPS: float = 30.0
## Направление «вперёд» персонажа в пространстве скелета (носки MPFB +Z).
const FORWARD: Vector3 = Vector3(0.0, 0.0, 1.0)
## Период машущих движений в процедурных клипах, с.
const SWAY_PERIOD: float = 0.85

var _tgt_bones: PackedStringArray = []
var _tgt_parent: Array[int] = []
var _tgt_rest_world: Array[Transform3D] = []
var _tgt_rest_dir: Array[Vector3] = []
var _tgt_rest_local: Array[Quaternion] = []
var _src_bones: PackedStringArray = []
var _src_parent: Array[int] = []
var _src_rest_world: Array[Transform3D] = []
## Индексы костей: источник → цель и обратно (−1 — совпадения нет).
var _fwd_map: Array[int] = []
var _rev_map: Array[int] = []


func _init() -> void:
	print("rest персонажа…")
	_read_rest(CHARACTER_GLB, false)
	print("rest UAL…")
	_read_rest(UAL_GLB[0], true)
	_build_bone_map()

	var clips := {}
	print("загрузка клипов…")
	for path: String in UAL_GLB:
		var scene := load(path) as PackedScene
		var root := scene.instantiate()
		var player := root.find_children("*", "AnimationPlayer", true,
			false)[0] as AnimationPlayer
		var lib := player.get_animation_library("")
		for clip_name in lib.get_animation_list():
			if BAKE_CLIPS.has(String(clip_name)):
				clips[String(clip_name)] = lib.get_animation(clip_name)
		root.free()
	assert(clips.size() == BAKE_CLIPS.size(), "не все клипы найдены: %d из %d" \
		% [clips.size(), BAKE_CLIPS.size()])

	var library := AnimationLibrary.new()
	for clip_name in clips:
		print("ретаргет ", clip_name, "…")
		library.add_animation(clip_name,
			_retarget_clip(clip_name, clips[clip_name]))
	library.add_animation(&"Hang_Pose", _gen_hang_pose())
	library.add_animation(&"Walk_Hand", _gen_walk_hand(clips["Walk"]))
	library.add_animation(&"Wave_Hand", _gen_arm_wave(clips["Idle"], false))
	library.add_animation(&"Help_Call", _gen_arm_wave(clips["Idle"], true))
	for clip_name in LOOP_CLIPS:
		(library.get_animation(clip_name) as Animation).loop_mode = \
			Animation.LOOP_LINEAR

	var err := ResourceSaver.save(library, OUT_PATH)
	assert(err == OK, "ResourceSaver: %s" % err)
	print("Запечено %d клипов → %s" % [library.get_animation_list().size(),
		OUT_PATH])
	quit()


## Rest-позы скелета glb: мировые (пространство скелета) базисы и направления.
func _read_rest(path: String, source: bool) -> void:
	var scene := load(path) as PackedScene
	var root := scene.instantiate()
	var sk := root.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var names: PackedStringArray = []
	var parents: Array[int] = []
	var worlds: Array[Transform3D] = []
	var dirs: Array[Vector3] = []
	var locals: Array[Quaternion] = []
	for i in sk.get_bone_count():
		names.append(sk.get_bone_name(i))
		parents.append(sk.get_bone_parent(i))
		var w := sk.get_bone_global_rest(i)
		worlds.append(w)
		dirs.append(w.basis.y.normalized())
		locals.append(sk.get_bone_rest(i).basis.get_rotation_quaternion())
	root.free()
	if source:
		_src_bones = names
		_src_parent = parents
		_src_rest_world = worlds
	else:
		_tgt_bones = names
		_tgt_parent = parents
		_tgt_rest_world = worlds
		_tgt_rest_dir = dirs
		_tgt_rest_local = locals


## Совпадение имён с точностью до регистра (root/Root, Head/head); leaf-кости
## UAL (index_04_leaf_l, ball_leaf_l) на MPFB отсутствуют — пропускаются.
func _build_bone_map() -> void:
	var lower := {}
	for i in _tgt_bones.size():
		lower[_tgt_bones[i].to_lower()] = i
	_fwd_map.resize(_src_bones.size())
	_rev_map.resize(_tgt_bones.size())
	_rev_map.fill(-1)
	for i in _src_bones.size():
		var tgt: int = lower.get(_src_bones[i].to_lower(), -1)
		_fwd_map[i] = tgt
		if tgt >= 0:
			_rev_map[tgt] = i
	var mapped := 0
	for i in _fwd_map:
		if i >= 0:
			mapped += 1
	print("Кости: источник %d, цель %d, совпало %d" % [_src_bones.size(),
		_tgt_bones.size(), mapped])


func _nearest_key(anim: Animation, track: int, t: float) -> int:
	# Ключи клипов на сетке FPS — берём ближайший к моменту t.
	var best := 0
	var best_dt := INF
	for k in anim.track_get_key_count(track):
		var dt: float = absf(anim.track_get_key_time(track, k) - t)
		if dt < best_dt:
			best_dt = dt
			best = k
	return best


## Ретаргет одного клипа: возвращает Animation с треками под риг MPFB.
func _retarget_clip(clip_name: String, anim: Animation) -> Animation:
	# Треки источника по индексу кости (повороты и позиция).
	var rot_tracks := {}
	var pos_track := -1
	var pos_tgt := -1
	for i in anim.get_track_count():
		var bone_name := _bone_of_track(anim.track_get_path(i))
		var src_idx := _src_bones.find(bone_name)
		if src_idx < 0:
			continue
		match anim.track_get_type(i):
			Animation.TYPE_ROTATION_3D:
				rot_tracks[src_idx] = i
			Animation.TYPE_POSITION_3D:
				if bone_name == &"pelvis":
					pos_track = i
					pos_tgt = _fwd_map[src_idx]
	# Отношение rest-высот таза — масштаб переноса позиции.
	var height_ratio := 1.0
	if pos_track >= 0 and pos_tgt >= 0:
		height_ratio = _tgt_rest_world[pos_tgt].origin.y \
			/ _src_rest_world[_rev_map[pos_tgt]].origin.y

	var times := _sample_times(anim)
	# Ретаргеченные локальные повороты цели по кадрам.
	var keyed_src := {}
	for src_idx in rot_tracks:
		keyed_src[src_idx] = true
	var keyed_tgt: Array[int] = []
	for i in _tgt_bones.size():
		if keyed_src.has(_rev_map[i]):
			keyed_tgt.append(i)
	var frames: Array[Array] = []
	for t in times:
		frames.append(_retarget_pose(anim, rot_tracks, t, keyed_src))

	var out := Animation.new()
	out.resource_name = clip_name
	out.length = anim.length
	if pos_track >= 0 and pos_tgt >= 0:
		var ti := _add_track(out, Animation.TYPE_POSITION_3D, pos_tgt)
		for k in times.size():
			out.position_track_insert_key(ti, times[k],
				anim.track_get_key_value(pos_track,
					_nearest_key(anim, pos_track, times[k])) * height_ratio)
	var track_of := {}
	for tgt in keyed_tgt:
		track_of[tgt] = _add_track(out, Animation.TYPE_ROTATION_3D, tgt)
		for k in times.size():
			out.rotation_track_insert_key(track_of[tgt], times[k],
				frames[k][tgt])
	return out


## Один кадр: мировые повороты источника → мировые цели → локальные цели.
func _retarget_pose(anim: Animation, rot_tracks: Dictionary, t: float,
		keyed_src: Dictionary) -> Array[Quaternion]:
	# 1. Локальные и мировые повороты источника в момент t.
	var src_locals: Array[Quaternion] = []
	src_locals.resize(_src_bones.size())
	for i in _src_bones.size():
		var track: int = rot_tracks.get(i, -1)
		if track >= 0:
			src_locals[i] = anim.track_get_key_value(track,
				_nearest_key(anim, track, t))
		else:
			src_locals[i] = _src_rest_world[i].basis.get_rotation_quaternion()
	var src_world: Array[Quaternion] = []
	src_world.resize(_src_bones.size())
	for i in _src_bones.size():
		var parent_q := src_world[_src_parent[i]] \
			if _src_parent[i] >= 0 else Quaternion.IDENTITY
		src_world[i] = parent_q * src_locals[i]
	# 2. Мировые повороты цели: закеенная кость — свинг по направлению
	# источника + его твист; незакеенная — rest под (уже анимированным)
	# родителем, как это прочтёт рантайм.
	var tgt_world: Array[Quaternion] = []
	tgt_world.resize(_tgt_bones.size())
	var tgt_locals: Array[Quaternion] = []
	tgt_locals.resize(_tgt_bones.size())
	for i in _tgt_bones.size():
		var parent_q := tgt_world[_tgt_parent[i]] \
			if _tgt_parent[i] >= 0 else Quaternion.IDENTITY
		var src_idx := _rev_map[i]
		if keyed_src.has(src_idx):
			tgt_locals[i] = _retarget_bone(src_idx, i, src_locals[src_idx],
				src_world[src_idx], parent_q)
		else:
			tgt_locals[i] = _tgt_rest_local[i]
		tgt_world[i] = parent_q * tgt_locals[i]
	return tgt_locals


## Свинг-твист перенос одной кости: направление анимации источника становится
## направлением цели, твист источника вокруг оси кости сохраняется.
func _retarget_bone(src_idx: int, tgt_idx: int, src_local: Quaternion,
		src_world_anim: Quaternion, tgt_parent_world: Quaternion) -> Quaternion:
	var rest_src_q := _src_rest_world[src_idx].basis.get_rotation_quaternion()
	var d_anim := (src_world_anim * Vector3.UP).normalized()
	var world := _swing(_tgt_rest_dir[tgt_idx], d_anim) \
		* _tgt_rest_world[tgt_idx].basis.get_rotation_quaternion()
	# Твист источника: проекция локальной дельты на его ось Y.
	var delta := rest_src_q.inverse() * src_local
	var twist := 2.0 * atan2(delta.y, delta.w)
	world = world * Quaternion(Vector3.UP, twist)
	return tgt_parent_world.inverse() * world


## Минимальный поворот, приводящий from к to (без поворота вокруг to).
func _swing(from: Vector3, to: Vector3) -> Quaternion:
	var cross := from.cross(to)
	if cross.length_squared() < 1e-12:
		return Quaternion.IDENTITY
	return Quaternion(cross.normalized(),
		acos(clampf(from.dot(to), -1.0, 1.0))).normalized()


func _sample_times(anim: Animation) -> Array[float]:
	var times: Array[float] = []
	var n := int(ceilf(anim.length * FPS)) + 1
	for k in n:
		times.push_back(minf(k / FPS, anim.length))
	if times.size() > 1 and is_equal_approx(times[times.size() - 1],
			times[times.size() - 2]):
		times.pop_back()
	return times


func _bone_of_track(path: NodePath) -> StringName:
	return path.get_subname(path.get_subname_count() - 1)


## Трек под кость цели (по индексу), возвращает индекс трека.
func _add_track(anim: Animation, type: int, tgt_idx: int) -> int:
	var ti := anim.add_track(type)
	anim.track_set_path(ti, NodePath("%s:%s" % [SKELETON_PATH,
		_tgt_bones[tgt_idx]]))
	anim.track_set_interpolation_type(ti, Animation.INTERPOLATION_LINEAR)
	return ti


# --- Процедурные клипы (нет аналогов в UAL Standard) ---
# Направление кости задаётся словарём {"base": Vector3, "sway": Vector3}:
# итог = normal(base + sway·sin(2πt/SWAY_PERIOD)), качание гасит статичность.


func _sway_dir(base: Vector3, sway: Vector3, t: float) -> Vector3:
	return (base + sway * sin(TAU * t / SWAY_PERIOD)).normalized()


func _static_(dir: Vector3) -> Dictionary:
	return {"base": dir, "sway": Vector3.ZERO}


## Вис у кромки расщелины: руки подняты через стороны над головой (плечи
## наклонены наружу, предплечья почти вертикальны — кисти на ширине плеч,
## не над лицом), ноги слегка поджаты. Тело прямое — остальное в rest.
func _gen_hang_pose() -> Animation:
	var anim := Animation.new()
	anim.resource_name = "Hang_Pose"
	anim.length = 1.5
	var times: Array[float] = []
	for k in int(anim.length * FPS) + 1:
		times.push_back(minf(k / FPS, anim.length))
	var overrides := {
		"upperarm_l": _static_(Vector3(-0.36, 0.91, 0.02)),
		"lowerarm_l": _static_(Vector3(-0.24, 0.96, 0.02)),
		"hand_l": _static_(Vector3(-0.14, 0.99, 0.05)),
		"upperarm_r": _static_(Vector3(0.36, 0.91, 0.02)),
		"lowerarm_r": _static_(Vector3(0.24, 0.96, 0.02)),
		"hand_r": _static_(Vector3(0.14, 0.99, 0.05)),
		"thigh_l": _static_(Vector3(0.0, -0.85, 0.52)),
		"calf_l": _static_(Vector3(0.0, -0.95, -0.3)),
		"foot_l": _static_(Vector3(0.0, -0.35, 0.94)),
		"thigh_r": _static_(Vector3(0.0, -0.85, 0.52)),
		"calf_r": _static_(Vector3(0.0, -0.95, -0.3)),
		"foot_r": _static_(Vector3(0.0, -0.35, 0.94)),
	}
	# База — пустая анимация (все кости в rest), треки только на override-кости.
	var scratch := Animation.new()
	scratch.length = anim.length
	var bones: Array[int] = []
	for bone in overrides:
		var idx := _tgt_bones.find(String(bone))
		assert(idx >= 0, "нет кости %s" % bone)
		bones.append(idx)
	_fill_overrides(anim, times, scratch, bones, overrides)
	return anim


## «За руку»: ходьба с вытянутой к ведущему рукой — вперёд и вбок, на уровне
## груди (база — ретаргеченная ходьба, правая рука каждый кадр в направлении).
func _gen_walk_hand(walk_src: Animation) -> Animation:
	var dir := (FORWARD * 0.88 + Vector3(0.40, -0.14, 0.0)).normalized()
	var base := _retarget_clip("Walk_Hand", walk_src)
	return _with_overrides(base, {
		"upperarm_r": _static_(dir),
		"lowerarm_r": _static_(dir),
		"hand_r": _static_(dir),
	})


## Взмах одной рукой («Привет!»), both — «Помогите!» обеими руками: рука(и)
## подняты через сторону вверх, предплечья машут туда-сюда; у Help_Call плечи
## разведены шире (кисти на ширине плеч, не над лицом). База — ретаргеченный
## Idle.
func _gen_arm_wave(idle_src: Animation, both: bool) -> Animation:
	var clip_name := "Help_Call" if both else "Wave_Hand"
	var base := _retarget_clip(clip_name, idle_src)
	var side := 0.38 if both else 0.42
	var forearm := 0.50 if both else 0.52
	var overrides := {
		"upperarm_r": {"base": Vector3(side, 0.91, 0.05),
			"sway": Vector3(0.06, 0.0, 0.0)},
		"lowerarm_r": {"base": Vector3(forearm, 0.84, 0.05),
			"sway": Vector3(0.28, 0.0, 0.0)},
		"hand_r": {"base": Vector3(forearm, 0.84, 0.05),
			"sway": Vector3(0.22, 0.0, 0.0)},
	}
	if both:
		overrides["upperarm_l"] = {"base": Vector3(-side, 0.91, 0.05),
			"sway": Vector3(-0.06, 0.0, 0.0)}
		overrides["lowerarm_l"] = {"base": Vector3(-forearm, 0.84, 0.05),
			"sway": Vector3(-0.28, 0.0, 0.0)}
		overrides["hand_l"] = {"base": Vector3(-forearm, 0.84, 0.05),
			"sway": Vector3(-0.22, 0.0, 0.0)}
	return _with_overrides(base, overrides)


## Перезапись костей поверх готовой печки: локали читаются из треков base,
## override-кости пересчитываются свингом (родители — из того же клипа),
## результат собирается в новую Animation. Позиционные треки копируются.
func _with_overrides(base: Animation, overrides: Dictionary) -> Animation:
	var times := _sample_times(base)
	var out := Animation.new()
	out.resource_name = base.resource_name
	out.length = base.length
	var bones: Array[int] = []
	for i in base.get_track_count():
		var bone_name := _bone_of_track(base.track_get_path(i))
		var tgt_idx := _tgt_bones.find(String(bone_name))
		if tgt_idx < 0:
			continue
		if base.track_get_type(i) == Animation.TYPE_POSITION_3D:
			var pt := _add_track(out, Animation.TYPE_POSITION_3D, tgt_idx)
			for k in times.size():
				out.position_track_insert_key(pt, times[k],
					base.track_get_key_value(i,
						_nearest_key(base, i, times[k])))
		else:
			bones.append(tgt_idx)
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
			base_track_of[_bone_of_track(base.track_get_path(i))] = i
	var track_of := {}
	for tgt in bones:
		track_of[tgt] = _add_track(out, Animation.TYPE_ROTATION_3D, tgt)
	for k in times.size():
		var t := times[k]
		var locals: Array[Quaternion] = []
		locals.resize(_tgt_bones.size())
		for i in _tgt_bones.size():
			var ti: int = base_track_of.get(_tgt_bones[i], -1)
			if ti >= 0:
				locals[i] = base.track_get_key_value(ti,
					_nearest_key(base, ti, t))
			else:
				locals[i] = _tgt_rest_local[i]
		var worlds: Array[Quaternion] = []
		worlds.resize(_tgt_bones.size())
		for i in _tgt_bones.size():
			var parent_q := worlds[_tgt_parent[i]] \
				if _tgt_parent[i] >= 0 else Quaternion.IDENTITY
			if overrides.has(_tgt_bones[i]):
				var spec: Dictionary = overrides[_tgt_bones[i]]
				locals[i] = parent_q.inverse() * (_swing(_tgt_rest_dir[i],
					_sway_dir(spec["base"], spec["sway"], t))
					* _tgt_rest_world[i].basis.get_rotation_quaternion())
			worlds[i] = parent_q * locals[i]
		for tgt in bones:
			out.rotation_track_insert_key(track_of[tgt], t, locals[tgt])
