# Процедурные камни Леса (П5.9, блоки 3 и 5): глыба — сфера с редкими
# кольцами, искажённая шумом FastNoiseLite (фиксированный seed от
# (seed, вариант): детерминизм), приплюснутая и утопленная низом в землю
# («врастает», SPEC 16 — бесшовность). Нормали сглаженные: полуреализм,
# мягкий объём; мох по верхним граням красит шейдер rock_moss.gdshader.
# Цвет в вершинах — белый тон (±яркость от rng, верх чуть светлее низа):
# палитра камешка — в uniform шейдера, вершинный и instance-тон умножаются
# на неё (как у прочих предметов).
class_name RockGen
extends RefCounted


## Глыба радиусом radius (м): flatten — приплюснутость по Y, seed —
## вариация формы. Низ чуть ниже origin — камень врос в землю.
static func boulder(variant: int, radius: float, flatten: float = 0.7) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(["rock", variant, radius])
	var noise := FastNoiseLite.new()
	noise.seed = hash(["rock_noise", variant, radius])
	noise.frequency = 1.7 / maxf(radius, 0.05)
	noise.fractal_octaves = 3

	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 9
	sphere.rings = 5
	var arrays: Array = sphere.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]

	# Искажение: смещение вдоль нормали (у сферы — вдоль радиуса) шумом,
	# плюс общая асимметрия (одна на всю глыбу) от rng — не «шарик».
	var stretch := Vector3(
		1.0 + rng.randf_range(-0.12, 0.28), 1.0, 1.0 + rng.randf_range(-0.12, 0.28))
	var warp := PackedVector3Array()
	warp.resize(verts.size())
	for i: int in verts.size():
		var direction := verts[i].normalized()
		var offset: float = noise.get_noise_3d(
			verts[i].x * 3.0 + 17.0, verts[i].y * 3.0, verts[i].z * 3.0)
		warp[i] = direction * offset * radius * 0.35 + \
			(direction * stretch - direction) * radius

	# Сглаженные нормали усреднением по граням.
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.ZERO)
	for t: int in indices.size() / 3:
		var a: int = indices[t * 3]
		var b: int = indices[t * 3 + 1]
		var c: int = indices[t * 3 + 2]
		var face := (verts[b] - verts[a]).cross(verts[c] - verts[a])
		normals[a] += face
		normals[b] += face
		normals[c] += face

	var min_y := 1e9
	for i: int in verts.size():
		verts[i] = Vector3(verts[i].x + warp[i].x,
			(verts[i].y + warp[i].y) * flatten, verts[i].z + warp[i].z)
		min_y = minf(min_y, verts[i].y)
	var colors := PackedColorArray()
	colors.resize(verts.size())
	for i: int in verts.size():
		# Низ утоплен в землю, камень «врос».
		verts[i].y -= min_y + radius * 0.25
		normals[i] = normals[i].normalized()
		# Тон: ±10 % яркости и лёгкий подъём к вершине — глыба читается
		# объёмом даже до мха.
		var tone: float = rng.randf_range(0.9, 1.1) \
			+ 0.08 * clampf(verts[i].y / (radius * 1.3), 0.0, 1.0)
		colors[i] = Color(tone, tone, tone)

	var out: Array = []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = normals
	out[Mesh.ARRAY_COLOR] = colors
	out[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return mesh
