# Самопроверка анимаций героя Born Unblessed — бывший аналог AnimSelfCheck
# (чекер блочной UBC-модели, вычищен с наследием Blockparty, born-unblessed)
# (возврат П5.8) для рига Mixamo (mixamorig_*) и библиотеки sword
# (Pro Sword and Shield). Правила CLAUDE.md «этапы с персонажами»:
#  1) позы ключевых костей (бедро, колено, плечо) в ходьбе отличаются от
#     покоя больше порога, в числах;
#  2) каждая дорожка каждого используемого клипа находит свою кость на риге;
#  3) вершины меша ног едут за костями (ручной скиннинг).
# Используется тестом GUT (test_hero_bu) и ключом --selftest-anim в игре.
class_name AnimSelfCheckBU
extends RefCounted

## Кости ходьбы против покоя (локальная поза, порог в градусах): срезы
## шага замерены на loco_walk — бедро ~28°, колено ~25°, плечо ~12°.
const POSE_BONES: Dictionary = {
	"mixamorig_LeftUpLeg": 10.0,
	"mixamorig_LeftLeg": 10.0,
	"mixamorig_LeftArm": 6.0,
}
## Минимальный сдвиг вершин меша ног в ходьбе, м (нога размахивается
## на ~0,3 м; 0,03 — запас в 10 раз).
const MESH_MIN_SHIFT: float = 0.03
## Прокрутка клипа перед снимком поз, с: бленд (0,15 с) закончился,
## ходьба — середина шага.
const ADVANCE: float = 0.5
const MAX_FRAMES: int = 600
## Кости ног для проверки скиннинга.
const LEG_BONES: Array[String] = [
	"mixamorig_LeftUpLeg", "mixamorig_LeftLeg",
	"mixamorig_RightUpLeg", "mixamorig_RightLeg",
]


## Прогнать проверку на герое (сопрограмма — ждёт кадры физики; звать
## через await). Возвращает {ok, reasons, metrics}; герой остаётся в покое.
static func run(model: HeroModelBU, verbose: bool = false) -> Dictionary:
	var reasons: PackedStringArray = []
	var metrics := {}
	var skel := model.skeleton()
	var ap := model.anim_player()
	if skel == null or ap == null:
		return {"ok": false, "reasons": PackedStringArray(
			["герой без скелета или плеера"]), "metrics": metrics}

	# 1) Резолв: каждая дорожка каждого клипа библиотеки находит кость/узел.
	# Дорожки записаны от root_node плеера в виде «<узел>:<кость>».
	var unresolved := 0
	var tracks := 0
	var root := ap.get_node(ap.root_node)
	for clip_name: StringName in ap.get_animation_library_list():
		var lib: AnimationLibrary = ap.get_animation_library(clip_name)
		for anim_name: StringName in lib.get_animation_list():
			var anim: Animation = lib.get_animation(anim_name)
			for tr: int in anim.get_track_count():
				var path := String(anim.track_get_path(tr))
				var node := root.get_node_or_null(NodePath(path.get_slice(":", 0)))
				if node == null:
					unresolved += 1
					if unresolved <= 1:
						reasons.append("клип %s/%s: дорожка «%s» — узла нет"
							% [clip_name, anim_name, path])
				elif node is Skeleton3D:
					var bone := path.get_slice(":", 1)
					if (node as Skeleton3D).find_bone(bone) < 0:
						unresolved += 1
						if unresolved <= 1:
							reasons.append("клип %s/%s: дорожка «%s» — кости нет на риге"
								% [clip_name, anim_name, path])
				tracks += 1
	metrics["tracks"] = tracks
	metrics["tracks_unresolved"] = unresolved
	if unresolved > 0:
		reasons.append("не резолвятся %d дорожек из %d" % [unresolved, tracks])

	# 2) Позы костей: покой против ходьбы (кадры физики,
	# advance() двигает позицию, но применяет бленд только игровой цикл).
	var idle := await _snapshot(model, skel, Protocol.AnimState.IDLE)
	var walk := await _snapshot(model, skel, Protocol.AnimState.WALK)
	if not idle["reached"] or not walk["reached"]:
		reasons.append("клип не докрутился до %.1f с за %d кадров физики"
			% [ADVANCE, MAX_FRAMES])
	for bone: String in POSE_BONES:
		var angle: float = rad_to_deg(
			(idle["local"][bone] as Quaternion).angle_to(
				walk["local"][bone] as Quaternion))
		metrics["pose_deg_%s" % bone] = angle
		if angle < POSE_BONES[bone]:
			reasons.append("кость %s: ходьба против покоя %.1f° < %.1f°"
				% [bone, angle, POSE_BONES[bone]])

	# 3) Деформация меша ног (скиннинг): вершины едут за костями.
	var shift := _leg_mesh_shift(skel, idle["global"], walk["global"])
	metrics["leg_mesh_max_shift_m"] = shift["max"]
	metrics["leg_mesh_vertices"] = shift["count"]
	if shift["count"] <= 0:
		reasons.append("меш ног: не найдено вершин на костях ног")
	elif shift["max"] < MESH_MIN_SHIFT:
		reasons.append("меш ног: сдвиг вершин %.3f м < %.3f м — меш стоит в "
			+ "байнд-позе при живом скелете" % [shift["max"], MESH_MIN_SHIFT])

	model.set_state(Protocol.AnimState.IDLE)
	if verbose:
		for key: String in metrics:
			print("  %s = %s" % [key, metrics[key]])
	return {"ok": reasons.is_empty(), "reasons": reasons, "metrics": metrics}


## Снимок состояния: включить клип состояния и ждать кадров физики, пока
## позиция клипа не дойдёт до ADVANCE (поза применена к скелету).
static func _snapshot(model: HeroModelBU, skel: Skeleton3D, state: int) -> Dictionary:
	model.set_state(state)
	var reached := await _reach_position(model, ADVANCE)
	var local := {}
	for bone: String in POSE_BONES:
		local[bone] = skel.get_bone_pose_rotation(skel.find_bone(bone))
	var global_poses: Array[Transform3D] = []
	global_poses.resize(skel.get_bone_count())
	for i: int in skel.get_bone_count():
		global_poses[i] = skel.get_bone_global_pose(i)
	return {"local": local, "global": global_poses, "reached": reached}


static func _reach_position(model: HeroModelBU, target: float) -> bool:
	var ap := model.anim_player()
	for i: int in MAX_FRAMES:
		if ap.get_current_animation_position() >= target:
			return true
		await model.get_tree().physics_frame
	return ap.get_current_animation_position() >= target


## Сдвиг вершин меша ног между снимками (формула рендера Σ w·(pose·bind)·v,
## ручной скиннинг): у героя BU ноги — меш Pants (штаны) или Boots.
static func _leg_mesh_shift(skel: Skeleton3D, pose_idle: Array[Transform3D],
		pose_walk: Array[Transform3D]) -> Dictionary:
	var max_shift := 0.0
	var count := 0
	var legs := _legs_mesh(skel)
	if legs == null or legs.skin == null:
		return {"max": max_shift, "count": count}
	var arrays := (legs.mesh as ArrayMesh).surface_get_arrays(0)
	var verts := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var bones := arrays[Mesh.ARRAY_BONES] as PackedInt32Array
	var weights := arrays[Mesh.ARRAY_WEIGHTS] as PackedFloat32Array
	var leg_bones := {}
	for bone: String in LEG_BONES:
		leg_bones[skel.find_bone(bone)] = true
	var bind_of := {}
	for i: int in legs.skin.get_bind_count():
		bind_of[legs.skin.get_bind_bone(i)] = legs.skin.get_bind_pose(i)
	# Godot рендерит кость без бинда с identity-позой — так же считаем
	# (у мешей MakeHuman бинды не на каждую кость скелета).
	for v: int in verts.size():
		var on_leg := false
		for j: int in 4:
			if leg_bones.has(bones[v * 4 + j]) and weights[v * 4 + j] > 0.05:
				on_leg = true
				break
		if not on_leg:
			continue
		count += 1
		var pw := _skinned(verts[v], bones, weights, v, pose_walk, bind_of)
		var pi := _skinned(verts[v], bones, weights, v, pose_idle, bind_of)
		max_shift = maxf(max_shift, (pw - pi).length())
	return {"max": max_shift, "count": count}


static func _skinned(v: Vector3, bones: PackedInt32Array,
		weights: PackedFloat32Array, index: int,
		poses: Array[Transform3D], bind_of: Dictionary) -> Vector3:
	var out := Vector3.ZERO
	var total := 0.0
	for j: int in 4:
		var w: float = weights[index * 4 + j]
		if w <= 0.0:
			continue
		total += w
		var bone: int = bones[index * 4 + j]
		var t: Transform3D = poses[bone] * (
			bind_of.get(bone, Transform3D.IDENTITY) as Transform3D)
		out += t * v * w
	return out / maxf(total, 1e-06)


## Меш ног героя: штаны (Pants) под скелетом, запасной — обувь (Boots).
static func _legs_mesh(skel: Skeleton3D) -> MeshInstance3D:
	for name: String in ["Pants", "Boots"]:
		for node: Node in skel.find_children(name, "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			if mi.visible and mi.mesh is ArrayMesh:
				return mi
	return null
