# Сборщик мешей района: копит четырёхугольники и коробки по ключам
# материалов и выдаёт один ArrayMesh (поверхность на материал).
# UV — метры по плоскости грани (для стен V идёт вниз по высоте),
# нормали плоские, касательные считает SurfaceTool.
# Порядок вершин add_quad: против часовой стрелки, если смотреть снаружи.
class_name MeshKit
extends RefCounted

var _tools: Dictionary = {}  # ключ материала -> SurfaceTool
var _counts: Dictionary = {}


func _tool(key: StringName) -> SurfaceTool:
	if not _tools.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_tools[key] = st
		_counts[key] = 0
	return _tools[key]


static func _uv(p: Vector3, n: Vector3) -> Vector2:
	if absf(n.y) > 0.7:
		return Vector2(p.x, p.z)
	var h: Vector3 = n.cross(Vector3.UP).normalized()
	return Vector2(p.dot(h), -p.y)


func add_quad(
	key: StringName, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
	color: Color = Color.WHITE
) -> void:
	var n: Vector3 = (b - a).cross(d - a).normalized()
	var st: SurfaceTool = _tool(key)
	# Лицевая сторона Godot — по часовой стрелке.
	for p: Vector3 in [a, c, b, a, d, c]:
		st.set_normal(n)
		st.set_color(color)
		st.set_uv(_uv(p, n))
		st.add_vertex(p)
	_counts[key] = int(_counts[key]) + 2


## Коробка: центр, размер, базис (оси коробки). Без нижней грани, если
## skip_bottom (стоит на земле).
func add_box(
	key: StringName, center: Vector3, size: Vector3,
	color: Color = Color.WHITE, basis: Basis = Basis.IDENTITY,
	skip_bottom: bool = false
) -> void:
	var x: Vector3 = basis.x * size.x * 0.5
	var y: Vector3 = basis.y * size.y * 0.5
	var z: Vector3 = basis.z * size.z * 0.5
	# Грань: нормаль n и оси u, v с u × v = n.
	var faces: Array = [
		[x, y, z], [-x, z, y], [y, z, x], [-y, x, z], [z, x, y], [-z, y, x],
	]
	for i: int in faces.size():
		if skip_bottom and i == 3:
			continue
		var n: Vector3 = faces[i][0]
		var u: Vector3 = faces[i][1]
		var v: Vector3 = faces[i][2]
		var o: Vector3 = center + n
		add_quad(key, o - u - v, o + u - v, o + u + v, o - u + v, color)


func triangle_count() -> int:
	var total: int = 0
	for key: StringName in _counts:
		total += int(_counts[key])
	return total


## Собрать меш: materials — ключ -> Material (ключ без записи остаётся
## без материала).
func commit(materials: Dictionary) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var keys: Array = _tools.keys()
	keys.sort()
	for key: StringName in keys:
		var st: SurfaceTool = _tools[key]
		st.generate_tangents()
		st.commit(mesh)
		var index: int = mesh.get_surface_count() - 1
		mesh.surface_set_name(index, String(key))
		if materials.has(key):
			mesh.surface_set_material(index, materials[key])
	return mesh
