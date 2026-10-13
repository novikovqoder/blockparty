# Самопроверка скелетных анимаций персонажа (возврат П5.8): до фикса
# кости анимировались, а меши рендерились байнд-позой (T-pose) — у
# запечённых мешей был пустой skeleton-путь. Проверка ловит именно класс
# «анимация не доходит до меша», а не только конкретный баг:
#  1) у каждого меша со скином skeleton-путь резолвится в Skeleton3D сцены;
#  2) позы ключевых костей (бедро/колено/плечо) в ходьбе численно отличаются
#     от покоя больше порога (владелец: «поза ходьбы ≠ T-поза»);
#  3) вершины меша ног реально едут за костями: ручной расчёт скиннинга
#     Σ w·(global_pose·bind)·v для покоя и ходьбы — максимальный сдвиг
#     больше порога. Это та же математика, что у рендера: сломается
#     привязка — проверка увидит T-pose меша при живом скелете.
# Используется тестом GUT (test_ubc_anims) и ключом --selftest-anim
# в запущенной игре (включая экспортированную сборку).
class_name AnimSelfCheck
extends RefCounted

## Кости ходьбы: локальная поза кости в Walk против Idle, порог в градусах.
## Пороги ~⅓ измеренных значений (Walk 0.5 с против Idle 0.5 с): бедро ~28°,
## колено ~30°, плечо ~17° — запас на вариации клипа и фазы.
const POSE_BONES: Dictionary = {
	"thigh_l": 10.0,
	"calf_l": 10.0,
	"upperarm_l": 6.0,
}
## Минимальный сдвиг вершин меша ног в ходьбе, м (нога размахивается
## на ~0.3 м; 0.03 — запас в 10 раз).
const MESH_MIN_SHIFT: float = 0.03
## Прокрутка клипа перед снимком поз, с: бленд (0.15 с) закончился,
## Walk — середина шага.
const ADVANCE: float = 0.5
## Предел ожидания кадров физики (headless гоняет idle-кадры медленнее
## физики — запас на любую частоту).
const MAX_FRAMES: int = 600


## Прогнать проверку на модели (сопрограмма — ждёт кадры физики; звать
## через await). Возвращает {ok, reasons, metrics}; reasons пустой — всё
## хорошо. Модель остаётся играть покой.
static func run(model: CharacterModel, verbose: bool = false) -> Dictionary:
	var reasons: PackedStringArray = []
	var metrics := {}
	var skel := model.find_children("*", "Skeleton3D", true,
		false)[0] as Skeleton3D
	if skel == null:
		return {"ok": false,
			"reasons": PackedStringArray(["нет Skeleton3D"]),
			"metrics": metrics}

	# 1) Скин-привязка: меш со скином обязан ссылаться на скелет сцены.
	var unbound := 0
	var meshes := 0
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.skin == null:
			continue
		meshes += 1
		if not (mi.get_node_or_null(mi.skeleton) is Skeleton3D):
			unbound += 1
			if unbound == 1:
				reasons.append("меш %s: skeleton-путь «%s» не ведёт к Skeleton3D"
					% [mi.name, String(mi.skeleton)])
	if unbound > 0:
		reasons.append("без скелета %d мешей из %d" % [unbound, meshes])

	# Снимки покоя и ходьбы: локальные позы ключевых костей + глобальные
	# позы всех костей (для скиннинга меша).
	var idle: Dictionary = await _snapshot(model, skel,
		Protocol.AnimState.IDLE)
	var walk: Dictionary = await _snapshot(model, skel,
		Protocol.AnimState.WALK)
	if not idle["reached"] or not walk["reached"]:
		reasons.append("клип не докрутился до %.1f с за %d кадров физики"
			% [ADVANCE, MAX_FRAMES])

	# 2) Позы костей: покой против ходьбы.
	for bone: String in POSE_BONES:
		var angle: float = rad_to_deg(
			(idle["local"][bone] as Quaternion).angle_to(
				walk["local"][bone] as Quaternion))
		metrics["pose_deg_%s" % bone] = angle
		if angle < POSE_BONES[bone]:
			reasons.append("кость %s: ходьба против покоя %.1f° < %.1f°"
				% [bone, angle, POSE_BONES[bone]])

	# 3) Деформация меша ног: вершины едут за костями.
	var shift := _leg_mesh_shift(skel, idle["global"], walk["global"])
	metrics["leg_mesh_max_shift_m"] = shift["max"]
	metrics["leg_mesh_vertices"] = shift["count"]
	if shift["count"] <= 0:
		reasons.append("меш ног: не найдено вершин на костях ног")
	elif shift["max"] < MESH_MIN_SHIFT:
		reasons.append("меш ног: сдвиг вершин %.3f м < %.3f м — меши стоят "
			+ "в байнд-позе при живом скелете" % [shift["max"],
			MESH_MIN_SHIFT])

	# Вернуть модели покой (снимки сняты, клип Walk не должен остаться).
	model.set_state(Protocol.AnimState.IDLE)
	metrics["meshes_with_skin"] = meshes
	metrics["meshes_unbound"] = unbound
	if verbose:
		for key: String in metrics:
			print("  %s = %s" % [key, metrics[key]])
	return {"ok": reasons.is_empty(), "reasons": reasons,
		"metrics": metrics}


## Снимок состояния: включить клип состояния и ждать КАДРОВ ФИЗИКИ, пока
## позиция клипа не дойдёт до ADVANCE (advance() двигает позицию, но не
## применяет бленд к скелету — проверено на 4.7.2), затем снять локальные
## позы ключевых костей и глобальные позы всех костей.
static func _snapshot(model: CharacterModel, skel: Skeleton3D,
		state: int) -> Dictionary:
	model.set_state(state)
	var reached: bool = await _reach_position(model, ADVANCE)
	var local := {}
	for bone: String in POSE_BONES:
		local[bone] = skel.get_bone_pose_rotation(skel.find_bone(bone))
	var global_poses: Array[Transform3D] = []
	global_poses.resize(skel.get_bone_count())
	for i: int in skel.get_bone_count():
		global_poses[i] = skel.get_bone_global_pose(i)
	return {"local": local, "global": global_poses, "reached": reached}


## Ждать кадры физики, пока позиция текущего клипа не станет ≥ target
## (не дольше MAX_FRAMES — защита от зависания, headless-прогон быстрый).
static func _reach_position(model: CharacterModel, target: float) -> bool:
	for i: int in MAX_FRAMES:
		if model._player.get_current_animation_position() >= target:
			return true
		await model.get_tree().physics_frame
	return model._player.get_current_animation_position() >= target


## Сдвиг вершин меша ног между двумя снимками: для каждой вершины с весом
## на костях ног позиция считается скиннингом (global_pose·bind)·v в обоих
## состояниях, берётся максимум длины разности.
static func _leg_mesh_shift(skel: Skeleton3D, pose_idle: Array[Transform3D],
		pose_walk: Array[Transform3D]) -> Dictionary:
	var max_shift := 0.0
	var count := 0
	var legs := _visible_legs(skel)
	if legs == null or legs.skin == null:
		return {"max": max_shift, "count": count}
	var arrays := (legs.mesh as ArrayMesh).surface_get_arrays(0)
	var verts := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var bones := arrays[Mesh.ARRAY_BONES] as PackedInt32Array
	var weights := arrays[Mesh.ARRAY_WEIGHTS] as PackedFloat32Array
	var leg_bones := {}
	for bone: String in ["thigh_l", "calf_l", "thigh_r", "calf_r"]:
		leg_bones[skel.find_bone(bone)] = true
	# bind-позы по индексу кости (бинды индексные, без имён).
	var bind_of := {}
	for i: int in legs.skin.get_bind_count():
		bind_of[legs.skin.get_bind_bone(i)] = legs.skin.get_bind_pose(i)
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


## Позиция вершины по формуле скиннинга: Σ wᵢ·(global_poseᵢ·bindᵢ)·v.
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
		var t: Transform3D = poses[bone] * (bind_of[bone] as Transform3D)
		out += t * v * w
	return out / maxf(total, 1e-06)


## Видимый (не LOD) меш ног: ищется под скелетом, чтобы не тащить модель.
static func _visible_legs(skel: Skeleton3D) -> MeshInstance3D:
	for node in skel.find_children("legs_*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.visible and not String(mi.name).ends_with("_LOD"):
			return mi
	return null
