# Самопроверка «тело под одеждой» (П5.8, Д4): кожа персонажа (срез
# головы/шеи и открытые участки рук) не должна выходить наружу сквозь
# одежду в движении, а открытый край среза — лежать вне одежды.
# Как считается:
#  1) опорная поза — кадр 0 клипа Idle: в bind-позах тело (широкая A) и
#     одежда MCO (узкая A) не совпадают, пары можно строить только в позе,
#     где скелет реально выставлен клипом. Позиции кожи и ткани считаются
#     скиннингом Σ w·(global·bind)·v;
#  2) категории кожи по части: срез головы (head_*) и кожа рук MCO
#     (arms_*). Для среза пара «вершина → точка ткани» строится к ткани
#     всего костюма, но только вдали от канта ткани (RIM_PAIR_MIN): у
#     канта (проём ворота) кожа видна законно, и «выступ» там — артефакт
#     пары, а не дефект (замер Д4: шея у ворота давала ложные 40 мм).
#     Кожа рук спаривается только с тканью СВОЕГО узла — кисть у бедра
#     в покое случайно близка к ткани ног и при жестах «проезжает» её
#     (ложные 78 мм); со своим рукавом кожа узла делит один скин;
#  3) открытые края (рёбра одного треугольника) ищутся по ОБЪЕДИНЕНИЮ
#     поверхностей узла — стыки поверхностей glTF не края. Край среза
#     головы не должен парить в проёме одежды (OPEN_FLOAT от любой
#     ткани: у колец проймы/ворота край законно примыкает к ткани);
#     край кожи рук — шов с тканью своего пака, в позах не дальше
#     SEAM_MAX;
#  4) для набора поз всех клипов библиотеки (3 кадра на клип) позиции
#     пар пересчитываются скиннингом; кожа считается вылезшей наружу,
#     если её смещение вдоль нормали ткани перешло порог POKE_TOL
#     (в опорной позе кожа сидит внутри с отрицательным зазором).
# Используется тестом GUT (test_p58_realism) и ключом --selftest-anim.
class_name BodyFitCheck
extends RefCounted

## Порог выступания кожи наружу сквозь ткань, м (задание Д4: ~5 мм).
const POKE_TOL: float = 0.005
## Дальше этого вершина кожи не считается покрытой: подгонка топа держит
## зазор CLOTH_CLEAR 12 мм до торса, покрытие с зазором больше — фиктивное
## (случайная близость шеи к вороту, подола к бедру), в позах такие пары
## «расходятся» на сантиметры и дают ложный выступ, м.
const COVER_MAX: float = 0.0125
## Максимальная суммарная доля весов вершины кожи на цепочках конечностей
## (upperarm/thigh и потомки): срез пекаря удаляет конечностную кожу
## (LIMB_WEIGHT_MAX 0.01), но упрощение меша до HEAD_TARGET смешивает
## вершины у проймы, оставляя доли до ~0.1. Такая кожа — проймовая: она
## законно движется с рукой, а топ обязан следовать торсу — пара не
## строится (замер: дельтоид с upperarm 0.09 «выступал» на 19 мм в
## Walk_Hand, хотя ткань у проймы следовала торсу корректно).
const LIMB_SHARE_MAX: float = 0.05
## Пара не строится у канта ткани (проём ворота/рукава — там кожа видна
## законно), м: точка пары дальше от края ткани.
const RIM_PAIR_MIN: float = 0.02
## Дальше этого в позе пара «кожа→ткань» считается распавшейся (рука
## ушла от бедра при замахе и т.п.): выступ не меряется, м.
const PAIR_BREAK: float = 0.08
## Максимальное расхождение шва «кожа рук ↔ ткань своего узла» в позах
## (узел делит один скин — жёсткая связь; больше — раскол), м.
const SEAM_MAX: float = 0.015
## Открытый край среза головы парит в проёме дальше этого от любой ткани,
## м. У самых кантов (пройма топа ↔ верх рукава состыкованы кольцами,
## вырез ворота) край законно лежит у ткани; дефект Д4 был именно
## «парящий» край (плоскостной срез оставал его на 60 мм над воротом).
const OPEN_FLOAT: float = 0.02
## Кадров на клип (равномерно по длине).
const POSES_PER_CLIP: int = 3
## Шаг сетки треугольников ткани (не меньше COVER_MAX + запас), м.
const CELL: float = 0.06


## Прогнать проверку на собранной модели (внешность задаёт комбинация
## одежды/пола). Возвращает {ok, reasons, metrics}; reasons пуст — всё
## хорошо. Позы считаются вручную по рест-цепочке, без AnimationPlayer.
static func run(model: CharacterModel, verbose: bool = false) -> Dictionary:
	var reasons: PackedStringArray = []
	var metrics := {}
	var skel := model.find_children("*", "Skeleton3D", true,
		false)[0] as Skeleton3D
	if skel == null:
		return {"ok": false,
			"reasons": PackedStringArray(["нет Skeleton3D"]), "metrics": metrics}

	# Поверхности по узлам: кожа (категория cut — срез головы, seam —
	# кожа рук MCO) и ткань; только видимые, без LOD.
	var skin_flat: Array = []   # поверхности кожи {_mesh_data + cat, node}
	var cloth_flat: Array = []  # поверхности ткани {_mesh_data + node}
	var skin_of_node := {}      # узел → [индексы skin_flat]
	var cloth_of_node := {}     # узел → [индексы cloth_flat]
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if not mi.visible or String(mi.name).ends_with("_LOD") \
				or mi.skin == null or mi.mesh == null:
			continue
		for surface: int in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(surface) as Material
			if mat == null:
				continue
			var arrays := mi.mesh.surface_get_arrays(surface)
			if (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).is_empty():
				continue
			var is_skin: bool = mat.resource_name.begins_with("skin_head_") \
					or mat.resource_name.begins_with("skin_arms_")
			if not is_skin and not mat.resource_name.begins_with("cloth_"):
				continue
			var cat := ""
			if mat.resource_name.begins_with("skin_head_"):
				cat = "cut"
			elif mat.resource_name.begins_with("skin_arms_"):
				cat = "seam"
			var data := _mesh_data(arrays, mi.skin, mat.resource_name)
			data["cat"] = cat
			data["node"] = String(mi.name)
			if is_skin:
				skin_of_node.get_or_add(String(mi.name), []).append(
					skin_flat.size())
				skin_flat.append(data)
			else:
				cloth_of_node.get_or_add(String(mi.name), []).append(
					cloth_flat.size())
				cloth_flat.append(data)
	if skin_flat.is_empty() or cloth_flat.is_empty():
		return {"ok": false,
			"reasons": PackedStringArray(["нет мешей кожи или ткани"]),
			"metrics": metrics}

	# Опорная поза — кадр 0 клипа Idle.
	var lib := CharacterAnims.library()
	var idle_name := CharacterAnims.clip_for_state(Protocol.AnimState.IDLE)
	var idle := lib.get_animation(idle_name) as Animation
	if idle == null:
		return {"ok": false,
			"reasons": PackedStringArray(["нет клипа Idle"]),
			"metrics": metrics}
	var ref_pose := _clip_globals(skel, idle,
		_tracks_by_bone(idle, skel), 0.0)

	# Ткань в опорной позе: единый конкатенированный список вершин всех
	# поверхностей; поверхность → смещение её вершин, треугольник →
	# поверхность (для швов «только свой узел» — по поверхности).
	var all_vert := PackedVector3Array()
	var surf_base := PackedInt32Array()   # поверхность ткани → начало вершин
	var tri_vert := PackedInt32Array()    # треугольник → вершины (глоб.)
	var tri_surf := PackedInt32Array()    # треугольник → поверхность ткани
	surf_base.resize(cloth_flat.size() + 1)
	for cf: int in cloth_flat.size():
		surf_base[cf] = all_vert.size()
		all_vert.append_array(_posed(cloth_flat[cf], ref_pose))
		var idx := cloth_flat[cf]["index"] as PackedInt32Array
		for t: int in idx.size() / 3:
			for k: int in 3:
				tri_vert.append(surf_base[cf] + idx[t * 3 + k])
			tri_surf.append(cf)
	surf_base[cloth_flat.size()] = all_vert.size()
	var grid := _build_grid(all_vert, tri_vert)
	# Канты ткани: по узлу (стыки поверхностей узла — не кант); кант —
	# пара глобальных индексов вершин (позиции — опорная поза).
	var rim_by_surf := _rim_edges_by_surf(cloth_flat, cloth_of_node,
		surf_base, all_vert)

	# Пары «вершина кожи → точка ткани» и открытые края по узлам кожи.
	var pairs := []  # {sf, sv, cf, cv[3], bary, sign, cat}
	var covered_count := 0
	var open_total := 0
	var open_outside := 0
	var seam_pairs := 0
	var limb_bones := {}
	for bone_name: String in ["upperarm_l", "upperarm_r", "thigh_l",
			"thigh_r"]:
		var root_bone: int = skel.find_bone(bone_name)
		if root_bone >= 0:
			_subtree_bones(skel, root_bone, limb_bones)
	for node_name: String in skin_of_node.keys():
		var surf_ids: Array = skin_of_node[node_name]
		var cat: String = skin_flat[surf_ids[0]]["cat"]
		# Ткань для пар: для шва и среза — только «свой» узел. Кожа торса
		# меряется к ТОПУ: рукава и штаны весятся на конечности (upperarm,
		# thigh) и законно уезжают от торса при махе — пары торс↔рукав
		# давали ложный «выступ» до 71 мм в Sprint (кожа у проймы видна,
		# это не дефект одежды). Топ после переноса весов едет с торсом
		# одним полем.
		var only := -1
		if cat == "seam":
			var cloth_ids: Array = cloth_of_node.get(node_name, [])
			if cloth_ids.is_empty():
				reasons.append("кожа %s без ткани своего узла" % node_name)
				continue
			only = cloth_ids[0]
		elif cat == "cut":
			var found := false
			for cloth_node: String in cloth_of_node.keys():
				if cloth_node.begins_with("top_"):
					only = cloth_of_node[cloth_node][0]
					found = true
					break
			if not found:
				reasons.append("кожа %s без топа" % node_name)
				continue
		var open_verts := _open_edge_verts(skin_flat, surf_ids)
		open_total += open_verts.size()
		for sf: int in surf_ids:
			var pv := _posed(skin_flat[sf], ref_pose)
			for v: int in skin_flat[sf]["count"]:
				# Швы меряются только у открытого края кожи (кольцо у
				# кромки рукава); голое предплечье и кисть у наруча —
				# случайная близость, не шов.
				if cat == "seam" and not open_verts.has([sf, v]):
					continue
				# Праймовая кожа (доля конечности ≥ LIMB_SHARE_MAX —
				# см. комментарий к константе) едет с рукой/ногой законно.
				if cat == "cut" and _limb_share(skin_flat[sf], v,
						limb_bones) >= LIMB_SHARE_MAX:
					continue
				var hit := _nearest_tri(all_vert, tri_vert, tri_surf, grid,
					pv[v], only, cloth_flat, cat == "cut")
				if hit.is_empty() or hit["sign"] > 0.0:
					# Нет ткани рядом либо кожа снаружи её поверхности —
					# не «под одеждой»: для видимой кожи (кисти, лицо) —
					# норма. Открытый край среза головы дефектен, только
					# если парит в проёме (OPEN_FLOAT); у кантов проймы и
					# ворота край законно примыкает к ткани соседних колец.
					if open_verts.has([sf, v]):
						if cat == "cut" and _nearest_dist(all_vert, tri_vert,
								grid, pv[v]) <= OPEN_FLOAT:
							continue
						open_outside += 1
						if open_outside == 1:
							reasons.append("часть %s: открытый край "
								% node_name + "(вершина %d) вне одежды" % v)
					continue
				if cat == "cut":
					# Пара вдали от канта: у проёма ворота кожа видна законно.
					if _rim_distance(all_vert, rim_by_surf, hit) < RIM_PAIR_MIN:
						continue
				elif cat == "seam":
					# Шов — кожа примыкает к ткани, где та продолжается
					# (кольцо проймы ↔ верх рукава). Точка у самой кромки
					# ткани — голое предплечье у манжеты: при взмахе кисть
					# законно отходит от рукава на сантиметры, это не раскол.
					if _rim_distance(all_vert, rim_by_surf, hit) < RIM_PAIR_MIN:
						continue
				covered_count += 1
				pairs.append({"sf": sf, "sv": v, "cf": hit["cf"],
					"cv": [hit["v0"], hit["v1"], hit["v2"]],
					"bary": hit["bary"], "sign": hit["sign"], "cat": cat,
					"ref_s": pv[v], "ref_d": hit["d"]})
				if cat == "seam":
					seam_pairs += 1
				if open_verts.has([sf, v]):
					# Шов у канта — норма (мерится SEAM_MAX); край среза
					# у канта ткани примыкает к соседним кольцам — дефектом
					# считается только парящий (OPEN_FLOAT).
					if cat == "seam":
						continue
					if _nearest_dist(all_vert, tri_vert, grid, pv[v]) > OPEN_FLOAT:
						open_outside += 1
						if open_outside == 1:
							reasons.append("часть %s: открытый край "
								% node_name + "(вершина %d) вне одежды" % v)
	metrics["skin_covered_verts"] = covered_count
	metrics["skin_open_verts"] = open_total
	metrics["skin_open_outside"] = open_outside
	metrics["seam_pairs"] = seam_pairs
	if open_outside > 0:
		reasons.append("открытых краёв вне одежды: %d из %d"
			% [open_outside, open_total])

	# Выступ по позам всех клипов: пары кожи против ткани.
	var top: Array = []  # худшие пары для диагностики [мм, поза, кожа,
	# вершина, ткань, позиция кожи в опорной позе, зазор пары в покое]
	var top_seam: Array = []
	var res := _pose_pokes(skin_flat, cloth_flat, surf_base, pairs,
		ref_pose, "опорная поза", top, top_seam)
	var worst: float = res["poke"]
	var worst_where := "опорная поза"
	var seam_worst: float = res["seam"]
	var poses := 1
	for clip_name: StringName in lib.get_animation_list():
		var anim := lib.get_animation(clip_name) as Animation
		var tracks := _tracks_by_bone(anim, skel)
		for k: int in POSES_PER_CLIP:
			var t: float = anim.length * (float(k) + 0.5) / POSES_PER_CLIP
			var pose := _clip_globals(skel, anim, tracks, t)
			var where := "%s@%.2fs" % [clip_name, t]
			res = _pose_pokes(skin_flat, cloth_flat, surf_base, pairs, pose,
				where, top, top_seam)
			poses += 1
			if res["poke"] > worst:
				worst = res["poke"]
				worst_where = where
			seam_worst = maxf(seam_worst, res["seam"])
	metrics["poses_checked"] = poses
	metrics["poke_max_m"] = worst
	metrics["poke_worst_pose"] = worst_where
	metrics["seam_max_m"] = seam_worst
	if worst > POKE_TOL:
		reasons.append("кожа выступает сквозь ткань на %.1f мм (порог %.1f мм)"
			% [worst * 1000.0, POKE_TOL * 1000.0]
			+ ", худшая поза %s" % worst_where)
	if seam_worst > SEAM_MAX:
		reasons.append("шов кожи рук разошёлся на %.1f мм (порог %.1f мм)"
			% [seam_worst * 1000.0, SEAM_MAX * 1000.0])
	if verbose:
		for key: String in metrics:
			print("  %s = %s" % [key, metrics[key]])
		for entry: Array in top:
			print("  пара: %.1f мм %s — %s:%d против %s ref=%s d=%.1f мм"
				% [entry[0] * 1000.0, entry[1], entry[2], entry[3], entry[4],
					entry[5], entry[6] * 1000.0])
		for entry: Array in top_seam:
			print("  шов: %.1f мм %s — %s:%d ref=%s d=%.1f мм"
				% [entry[0] * 1000.0, entry[1], entry[2], entry[3],
					entry[4], entry[5] * 1000.0])
	return {"ok": reasons.is_empty(), "reasons": reasons, "metrics": metrics}


# --- Сбор данных мешей ---

## Кость и все её потомки (цепочка конечности целиком).
static func _subtree_bones(skel: Skeleton3D, bone: int, out: Dictionary) -> void:
	out[bone] = true
	for child: int in skel.get_bone_children(bone):
		_subtree_bones(skel, child, out)


## Суммарный вес вершины кожи на цепочках конечностей (LIMB_SHARE_MAX).
static func _limb_share(mesh: Dictionary, v: int, limb_bones: Dictionary) -> float:
	var vw: int = mesh["vw"]
	var bones := mesh["bones"] as PackedInt32Array
	var weights := mesh["weights"] as PackedFloat32Array
	var share := 0.0
	for k: int in vw:
		if limb_bones.has(bones[v * vw + k]):
			share += weights[v * vw + k]
	return share

## Данные поверхности: вершины, нормали, индексы, скиннинг (кости+веса
## переменной ширины) и bind-позы по кости.
static func _mesh_data(arrays: Array, skin: Skin, mat_name: String) -> Dictionary:
	var verts := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var normals := arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
	var weights := arrays[Mesh.ARRAY_WEIGHTS] as PackedFloat32Array
	var vw: int = weights.size() / maxi(verts.size(), 1)
	var bind_of := {}
	for i: int in skin.get_bind_count():
		bind_of[skin.get_bind_bone(i)] = skin.get_bind_pose(i)
	return {"name": mat_name, "vert": verts, "normal": normals,
		"index": arrays[Mesh.ARRAY_INDEX] as PackedInt32Array,
		"bones": arrays[Mesh.ARRAY_BONES] as PackedInt32Array,
		"weights": weights, "vw": vw, "bind": bind_of,
		"count": verts.size()}


## Ключ ребра по позициям концов (вершины поверхностей glTF независимы,
## общие рёбра сверяются по позиции с точностью 0.1 мм).
static func _edge_key(a: Vector3, b: Vector3) -> String:
	if _vk(a) > _vk(b):
		var t := a
		a = b
		b = t
	return "%s|%s" % [_vk(a), _vk(b)]


static func _vk(p: Vector3) -> String:
	return "%d,%d,%d" % [roundi(p.x * 10000.0), roundi(p.y * 10000.0),
		roundi(p.z * 10000.0)]


## Канты ткани: рёбра, встреченные один раз по ОБЪЕДИНЕНИЮ поверхностей
## узла (дыры ворота, манжет, подола; стыки поверхностей узла — не кант).
## Возвращает по поверхности ткани список рёбер парами глобальных
## индексов вершин (позиции — опорная поза).
static func _rim_edges_by_surf(cloth_flat: Array, cloth_of_node: Dictionary,
		surf_base: PackedInt32Array,
		all_vert: PackedVector3Array) -> Array:
	var seen := {}  # узел → ключ ребра → счётчик
	for node_name: String in cloth_of_node.keys():
		var counts := {}
		for cf: int in cloth_of_node[node_name]:
			var idx := cloth_flat[cf]["index"] as PackedInt32Array
			for t: int in idx.size() / 3:
				for e: int in 3:
					var a := all_vert[surf_base[cf] + idx[t * 3 + e]]
					var b := all_vert[surf_base[cf] + idx[t * 3 + (e + 1) % 3]]
					var key := _edge_key(a, b)
					counts[key] = int(counts.get(key, 0)) + 1
		seen[node_name] = counts
	var out := []
	out.resize(cloth_flat.size())
	for node_name: String in cloth_of_node.keys():
		var counts: Dictionary = seen[node_name]
		for cf: int in cloth_of_node[node_name]:
			var idx := cloth_flat[cf]["index"] as PackedInt32Array
			var rim := []
			for t: int in idx.size() / 3:
				for e: int in 3:
					var ia: int = surf_base[cf] + idx[t * 3 + e]
					var ib: int = surf_base[cf] + idx[t * 3 + (e + 1) % 3]
					if counts[_edge_key(all_vert[ia], all_vert[ib])] == 1:
						rim.append(PackedInt32Array([ia, ib]))
			out[cf] = rim
	return out


## Вершины открытых краёв узла кожи (срез шеи, кант вырезанного): рёбра,
## встреченные один раз по объединению поверхностей узла. Ключ —
## [поверхность, вершина].
static func _open_edge_verts(skin_flat: Array, surf_ids: Array) -> Dictionary:
	var seen := {}
	for sf: int in surf_ids:
		var idx := skin_flat[sf]["index"] as PackedInt32Array
		var verts := skin_flat[sf]["vert"] as PackedVector3Array
		for t: int in idx.size() / 3:
			for e: int in 3:
				var a := verts[idx[t * 3 + e]]
				var b := verts[idx[t * 3 + (e + 1) % 3]]
				var key := _edge_key(a, b)
				seen[key] = int(seen.get(key, 0)) + 1
	var out := {}
	for sf: int in surf_ids:
		var idx := skin_flat[sf]["index"] as PackedInt32Array
		var verts := skin_flat[sf]["vert"] as PackedVector3Array
		for t: int in idx.size() / 3:
			for e: int in 3:
				var a := verts[idx[t * 3 + e]]
				var b := verts[idx[t * 3 + (e + 1) % 3]]
				if seen[_edge_key(a, b)] == 1:
					out[[sf, idx[t * 3 + e]]] = true
					out[[sf, idx[t * 3 + (e + 1) % 3]]] = true
	return out


# --- Поиск ближайшего треугольника (сетка по AABB) ---

## Сетка CELL по AABB треугольников ткани (опорная поза): ячейка →
## candidate-треугольники. Packed-массив из словаря нельзя мутировать
## через as-каст (каст даёт копию) — только чтение/запись целиком.
static func _build_grid(all_vert: PackedVector3Array,
		tri_vert: PackedInt32Array) -> Dictionary:
	var grid := {}
	var tri_count: int = tri_vert.size() / 3
	for t: int in tri_count:
		var a := all_vert[tri_vert[t * 3]]
		var b := all_vert[tri_vert[t * 3 + 1]]
		var c := all_vert[tri_vert[t * 3 + 2]]
		var mn := Vector3(minf(a.x, minf(b.x, c.x)), minf(a.y, minf(b.y, c.y)),
			minf(a.z, minf(b.z, c.z)))
		var mx := Vector3(maxf(a.x, maxf(b.x, c.x)), maxf(a.y, maxf(b.y, c.y)),
			maxf(a.z, maxf(b.z, c.z)))
		for x: int in range(int(floor(mn.x / CELL)), int(floor(mx.x / CELL)) + 1):
			for y: int in range(int(floor(mn.y / CELL)), int(floor(mx.y / CELL)) + 1):
				for z: int in range(int(floor(mn.z / CELL)), int(floor(mx.z / CELL)) + 1):
					var key: int = (x * 4096 + y) * 4096 + z
					if not grid.has(key):
						grid[key] = PackedInt32Array()
					var cell: PackedInt32Array = grid[key]
					cell.append(t)
					grid[key] = cell
	return grid


## Ближайший к точке треугольник ткани ≤ COVER_MAX. only ≥ 0 — брать
## только треугольники поверхностей узла, которому принадлежит
## поверхность only (швы «кожа рук ↔ свой узел»). outermost — для среза
## головы: кожа видна только сквозь ВНЕШНИЙ слой, поэтому из кандидатов
## внутренней стороны (side ≤ 0, d ≤ COVER_MAX) берётся самый дальний —
## штаны под юбкой не «выдают» кожу таза, парить её должна юбка.
## Кандидаты — ячейки сферы запроса (радиус + CELL запас на размеры
## треугольников).
## Возвращает {cf, v0..2 (глобальные индексы), bary, d, sign} либо {}.
static func _nearest_tri(all_vert: PackedVector3Array,
		tri_vert: PackedInt32Array, tri_surf: PackedInt32Array,
		grid: Dictionary, p: Vector3, only: int,
		cloth_flat: Array, outermost: bool = false) -> Dictionary:
	var only_node: String = cloth_flat[only]["node"] if only >= 0 else ""
	var reach := COVER_MAX + CELL
	var best_d := COVER_MAX
	var best_t := -1
	var best_q := Vector3.ZERO
	var far_d := 0.0
	var far_t := -1
	var far_q := Vector3.ZERO
	for x: int in range(int(floor((p.x - reach) / CELL)),
			int(floor((p.x + reach) / CELL)) + 1):
		for y: int in range(int(floor((p.y - reach) / CELL)),
				int(floor((p.y + reach) / CELL)) + 1):
			for z: int in range(int(floor((p.z - reach) / CELL)),
					int(floor((p.z + reach) / CELL)) + 1):
				var key: int = (x * 4096 + y) * 4096 + z
				if not grid.has(key):
					continue
				for t: int in grid[key] as PackedInt32Array:
					if only >= 0 \
							and cloth_flat[tri_surf[t]]["node"] != only_node:
						continue
					var a := all_vert[tri_vert[t * 3]]
					var b := all_vert[tri_vert[t * 3 + 1]]
					var c := all_vert[tri_vert[t * 3 + 2]]
					var q := _closest_on_tri(p, a, b, c)
					var d := p.distance_to(q)
					if d < best_d:
						best_d = d
						best_t = t
						best_q = q
					if outermost and d <= COVER_MAX:
						var n := (b - a).cross(c - a)
						if n.length_squared() > 1e-12 \
								and (p - q).dot(n) <= 0.0 and d > far_d:
							far_d = d
							far_t = t
							far_q = q
	if far_t >= 0:
		best_t = far_t
		best_q = far_q
		best_d = far_d
	if best_t < 0:
		return {}
	var gi0: int = tri_vert[best_t * 3]
	var gi1: int = tri_vert[best_t * 3 + 1]
	var gi2: int = tri_vert[best_t * 3 + 2]
	var a := all_vert[gi0]
	var b := all_vert[gi1]
	var c := all_vert[gi2]
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return {}
	var side: float = (p - best_q).dot(n)
	# Точка на самой поверхности ткани (d≈0, шов «кожа рук ↔ рукав»
	# состыкован встык): сторона не определена, считаем внутренней —
	# пара строится, для шва важна дистанция, а не сторона.
	return {"cf": tri_surf[best_t],
		"v0": gi0, "v1": gi1, "v2": gi2,
		"bary": _barycentric(a, b, c, best_q), "d": best_d,
		"sign": 1.0 if side > 0.0 else -1.0}


## Расстояние до ближайшей ткани без порога и знака (расширяющийся
## поиск по сетке) — для «парящего» открытого края (OPEN_FLOAT).
static func _nearest_dist(all_vert: PackedVector3Array,
		tri_vert: PackedInt32Array, grid: Dictionary, p: Vector3) -> float:
	var best := 1e9
	for reach: float in [CELL * 2.0, 0.2, 0.5]:
		for x: int in range(int(floor((p.x - reach) / CELL)),
				int(floor((p.x + reach) / CELL)) + 1):
			for y: int in range(int(floor((p.y - reach) / CELL)),
					int(floor((p.y + reach) / CELL)) + 1):
				for z: int in range(int(floor((p.z - reach) / CELL)),
						int(floor((p.z + reach) / CELL)) + 1):
					var key: int = (x * 4096 + y) * 4096 + z
					if not grid.has(key):
						continue
					for t: int in grid[key] as PackedInt32Array:
						var q := _closest_on_tri(p, all_vert[tri_vert[t * 3]],
							all_vert[tri_vert[t * 3 + 1]],
							all_vert[tri_vert[t * 3 + 2]])
						best = minf(best, p.distance_to(q))
		if best < 1e9:
			return best
	return best


## Ближайшая точка треугольника (Ericson, Real-Time Collision Detection,
## разбор областей). Простой кламп барицентрических координат по отдельности
## ошибочен: сумма коэффициентов выходит за 1, точка покидает плоскость
## треугольника и расстояние занижается в разы — пары строились к далёким
## треугольникам (замер Д4: «лоб → горловина» с d=20 мм при реальных 70 мм).
static func _closest_on_tri(p: Vector3, a: Vector3, b: Vector3,
		c: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return a
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return b
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return a + ab * (d1 / (d1 - d3))
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return c
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return a + ac * (d2 / (d2 - d6))
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
	var den := 1.0 / (va + vb + vc)
	return a + ab * (vb * den) + ac * (vc * den)


## Барицентрические координаты точки p в треугольнике abc.
static func _barycentric(a: Vector3, b: Vector3, c: Vector3,
		p: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d00 := ab.dot(ab)
	var d01 := ab.dot(ac)
	var d11 := ac.dot(ac)
	var d20 := ap.dot(ab)
	var d21 := ap.dot(ac)
	var den := d00 * d11 - d01 * d01
	if absf(den) < 1e-12:
		return Vector3(1.0, 0.0, 0.0)
	var v: float = (d11 * d20 - d01 * d21) / den
	var w: float = (d00 * d21 - d01 * d20) / den
	return Vector3(1.0 - v - w, v, w)


## Расстояние от точки попадания до ближайшего канта поверхности ткани.
static func _rim_distance(all_vert: PackedVector3Array, rim_by_surf: Array,
		hit: Dictionary) -> float:
	var p := Vector3.ZERO
	for k: int in 3:
		p += all_vert[hit["v" + str(k)]] * hit["bary"][k]
	var best := 1e9
	for edge: PackedInt32Array in rim_by_surf[hit["cf"]]:
		var d: float = _point_segment(p, all_vert[edge[0]], all_vert[edge[1]])
		best = minf(best, d)
	return best


static func _point_segment(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t: float = clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-12),
		0.0, 1.0)
	return (a + ab * t).distance_to(p)


# --- Позы клипов и проверка пар ---

## Треки клипа «кость → индекс» (ротацияционные).
static func _tracks_by_bone(anim: Animation, _skel: Skeleton3D) -> Dictionary:
	var out := {}
	for i: int in anim.get_track_count():
		if anim.track_get_type(i) != Animation.TYPE_ROTATION_3D:
			continue
		var path := anim.track_get_path(i)
		out[str(path).get_slice(":", 1)] = i
	return out


## Глобальные позы всех костей в момент t (линейная интерполяция ключей,
## трансляции — рест, как в tools/probe_clip_speed.gd).
static func _clip_globals(skel: Skeleton3D, anim: Animation, tracks: Dictionary,
		t: float) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	out.resize(skel.get_bone_count())
	for i: int in skel.get_bone_count():
		var rest := skel.get_bone_rest(i)
		var q := rest.basis.get_rotation_quaternion()
		if tracks.has(skel.get_bone_name(i)):
			q = _sample_rot(anim, tracks[skel.get_bone_name(i)], t)
		var local := Transform3D(Basis(q), rest.origin)
		var parent: int = skel.get_bone_parent(i)
		out[i] = local if parent == -1 else out[parent] * local
	return out


static func _sample_rot(anim: Animation, track: int, t: float) -> Quaternion:
	var count: int = anim.track_get_key_count(track)
	if count <= 1:
		return anim.track_get_key_value(track, 0)
	for i: int in count:
		var key_t: float = anim.track_get_key_time(track, i)
		if key_t >= t:
			if i == 0:
				return anim.track_get_key_value(track, 0)
			var prev_t: float = anim.track_get_key_time(track, i - 1)
			var prev: Quaternion = anim.track_get_key_value(track, i - 1)
			var next: Quaternion = anim.track_get_key_value(track, i)
			if key_t - prev_t <= 0.0:
				return prev
			return prev.slerp(next, (t - prev_t) / (key_t - prev_t))
	return anim.track_get_key_value(track, count - 1)


## Все вершины меша в позе (формула скиннинга рендера).
static func _posed(mesh: Dictionary, pose: Array[Transform3D]) -> PackedVector3Array:
	var count: int = mesh["count"]
	var out := PackedVector3Array()
	out.resize(count)
	for v: int in count:
		out[v] = _skinned(mesh, v, pose)
	return out


## Скиннинг вершины: Σ w·(global·bind)·v (формула рендера).
static func _skinned(mesh: Dictionary, v: int, pose: Array[Transform3D]) -> Vector3:
	var out := Vector3.ZERO
	var total := 0.0
	var vw: int = mesh["vw"]
	var bones := mesh["bones"] as PackedInt32Array
	var weights := mesh["weights"] as PackedFloat32Array
	var bind := mesh["bind"] as Dictionary
	for k: int in vw:
		var w: float = weights[v * vw + k]
		if w <= 0.0:
			continue
		total += w
		var bone: int = bones[v * vw + k]
		var tr: Transform3D = pose[bone] * (bind[bone] as Transform3D)
		out += tr * (mesh["vert"] as PackedVector3Array)[v] * w
	return out / maxf(total, 1e-06)


## Пары в позе: у «cut» пар мерится выступ сквозь ткань — проекция
## смещения вдоль нормали треугольника (со стороны, где кожа сидела в
## опорной позе); у «seam» пар мерится расхождение шва — расстояние до
## точки ткани (кожа обязана оставаться у своего рукава). Распавшиеся
## пары (смещение > PAIR_BREAK) пропускаются. В top/top_seam копятся
## худшие пары для диагностики.
## Возвращает {poke: макс. выступ, seam: макс. расхождение шва}.
static func _pose_pokes(skin_flat: Array, cloth_flat: Array,
		surf_base: PackedInt32Array, pairs: Array, pose: Array[Transform3D],
		where: String, top: Array, top_seam: Array) -> Dictionary:
	var worst := 0.0
	var seam := 0.0
	for pair: Dictionary in pairs:
		var skin: Dictionary = skin_flat[pair["sf"]]
		var s := _skinned(skin, pair["sv"], pose)
		var cf: int = pair["cf"]
		var b: int = surf_base[cf]
		var cloth: Dictionary = cloth_flat[cf]
		var cv: Array = pair["cv"]
		var a := _skinned(cloth, cv[0] - b, pose)
		var b2 := _skinned(cloth, cv[1] - b, pose)
		var c := _skinned(cloth, cv[2] - b, pose)
		var bary: Vector3 = pair["bary"]
		var cp := a * bary.x + b2 * bary.y + c * bary.z
		var delta := s - cp
		if delta.length() > PAIR_BREAK:
			continue
		if pair["cat"] == "seam":
			if delta.length() > SEAM_MAX:
				top_seam.append([delta.length(), where, skin["name"],
					pair["sv"], pair["ref_s"], pair["ref_d"]])
			seam = maxf(seam, delta.length())
			continue
		var n := (b2 - a).cross(c - a)
		if n.length_squared() < 1e-12:
			continue
		n = n.normalized() * pair["sign"]
		var proj: float = delta.dot(n)
		worst = maxf(worst, proj)
		if proj > POKE_TOL:
			top.append([proj, where, skin["name"], pair["sv"], cloth["name"],
				pair["ref_s"], pair["ref_d"]])
	if not top.is_empty():
		top.sort_custom(func(x: Array, y: Array) -> bool:
			return x[0] > y[0])
		while top.size() > 8:
			top.pop_back()
	if not top_seam.is_empty():
		top_seam.sort_custom(func(x: Array, y: Array) -> bool:
			return x[0] > y[0])
		while top_seam.size() > 8:
			top_seam.pop_back()
	return {"poke": worst, "seam": seam}
