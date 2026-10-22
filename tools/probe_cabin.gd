# Одноразовая диагностика сруба Kless (visual-overhaul, сруб): структура
# импортированной сцены GLB, треугольники по мешам, габариты外壳 EXT_*,
# дословная проверка дверного проёма рейкастами по COLL-мешу (луч сквозь
# стену на высоте 1 м в центре двери должен проходить насквозь, лучи
# в стороне от двери — упираться в стену). Запуск:
#   godot --headless -s tools/probe_cabin.gd
extends SceneTree

const GLB := "res://assets/visual/cabin/log_cabin.glb"
const DOOR := Vector3(0.105, 0.0, -5.11)


func _initialize() -> void:
	var scene: PackedScene = load(GLB)
	if scene == null:
		print("FAIL: сцена не грузится")
		quit(1)
		return
	var root := scene.instantiate()
	var ok := true
	var total := 0
	var total_ext := 0
	var aabb := AABB()
	var coll_faces: Array[Vector3] = []
	print("== дети корня ==")
	for child in root.get_children():
		var mi := child as MeshInstance3D
		if mi == null:
			print("%s: НЕ MeshInstance3D (%s) — обход в cabin_house.gd его не увидит" %
				[mi.name if mi != null else "?", child.get_class()])
			ok = false
			continue
		var tris := 0
		for surface in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(surface)
			var idx := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
			tris += idx.size() / 3
		total += tris
		if mi.name.begins_with("EXT_") or mi.name == "TERRACE_deck":
			total_ext += tris
			aabb = aabb.merge(mi.mesh.get_aabb())
		if mi.name == "COLL":
			for surface in mi.mesh.get_surface_count():
				var arrays := mi.mesh.surface_get_arrays(surface)
				var verts := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
				var idx := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
				for i in range(0, idx.size(), 3):
					coll_faces.append(verts[idx[i]])
					coll_faces.append(verts[idx[i + 1]])
					coll_faces.append(verts[idx[i + 2]])
		var mat_name := ""
		if mi.mesh.get_surface_count() > 0:
			var mat := mi.mesh.surface_get_material(0)
			mat_name = "" if mat == null else mat.resource_name
		print("%-14s %7d tris  mat=%s" % [mi.name, tris, mat_name])
	print("TOTAL=%d  EXT+terrace=%d" % [total, total_ext])
	print("AABB EXT: pos=%s size=%s" % [aabb.position, aabb.size])
	if total > 100_000:
		print("FAIL: весь дом %d > 100k" % total)
		ok = false
	if total_ext > 50_000:
		print("FAIL: снаружи %d > 50k" % total_ext)
		ok = false
	# Пол под дверью должен быть на ~0 (проход вровень с землёй).
	print("== проём ==")
	var floor_hit := _ray(coll_faces, DOOR + Vector3(0, 3, 0), Vector3(0, -1, 0))
	print("пол под дверью: y=%.3f" % floor_hit)
	# Луч сквозь стену по ходу входа (−Z) на высоте 1.0 м: в центре двери —
	# насквозь (нет пересечений до 6 м), в 1.2 м сбоку — стена.
	var through_door := _ray(coll_faces, DOOR + Vector3(0, 1.0, 0), Vector3(0, 0, -1))
	var side := _ray(coll_faces, DOOR + Vector3(1.2, 1.0, 0), Vector3(0, 0, -1))
	var side2 := _ray(coll_faces, DOOR + Vector3(-1.2, 1.0, 0), Vector3(0, 0, -1))
	print("сквозь дверь (−Z): %.3f  сбоку +1.2: %.3f  сбоку −1.2: %.3f" %
		[through_door, side, side2])
	if through_door > 0.0 and through_door < 6.0:
		print("FAIL: в центре двери на высоте 1 м препятствие")
		ok = false
	var wall_checks := [side, side2]
	for h in [0.4, 1.9]:
		var hit := _ray(coll_faces, DOOR + Vector3(0, h, 0), Vector3(0, 0, -1))
		print("над/под дверью (y=%.1f): %.3f" % [h, hit])
		wall_checks.append(hit)
	for d in wall_checks:
		if d <= 0.0 or d > 6.0:
			print("FAIL: рядом с проёмом нет стены (луч прошёл насквозь)")
			ok = false
	root.free()
	print("PROBE OK" if ok else "PROBE FAIL")
	quit(0 if ok else 1)


## Дистанция до ближайшего пересечения луча с треугольниками COLL
## (Мёллер–Трумбор), −1 — нет пересечений.
func _ray(faces: Array[Vector3], from: Vector3, dir: Vector3) -> float:
	var best := -1.0
	for i in range(0, faces.size(), 3):
		var t := _tri(from, dir, faces[i], faces[i + 1], faces[i + 2])
		if t > 0.0 and (best < 0.0 or t < best):
			best = t
	return best


func _tri(from: Vector3, dir: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	var e1 := b - a
	var e2 := c - a
	var p := dir.cross(e2)
	var det := e1.dot(p)
	if absf(det) < 1e-9:
		return -1.0
	var inv := 1.0 / det
	var s := from - a
	var u := inv * s.dot(p)
	if u < 0.0 or u > 1.0:
		return -1.0
	var q := s.cross(e1)
	var v := inv * dir.dot(q)
	if v < 0.0 or u + v > 1.0:
		return -1.0
	var t := inv * e2.dot(q)
	return t if t > 1e-4 else -1.0
