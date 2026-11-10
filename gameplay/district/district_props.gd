# Малые постройки и предметы района (постапокалипсис), собранные кодом:
# гаражи, магазин, будки, заборы, блоки завалов. Каждая функция возвращает
# Node3D «ногами» в начале координат, с мешем и коллизией-коробкой.
# Локальные оси: ширина по X, глубина по Z, «лицо» (ворота, дверь) — в +Z.
class_name DistrictProps
extends RefCounted


static func _finish(
	root: Node3D, kit: MeshKit, materials: Dictionary, size: Vector3
) -> Node3D:
	var instance := MeshInstance3D.new()
	instance.name = "Mesh"
	instance.mesh = kit.commit(materials)
	root.add_child(instance)
	var shape := BoxShape3D.new()
	shape.size = size
	SolidBody.add(root, shape, Vector3(0.0, size.y * 0.5, 0.0))
	return root


## Простая коробка из одного материала (блок, контейнер, настил).
static func block(
	block_name: String, size: Vector3, material: Material,
	tone: Color = Color.WHITE
) -> Node3D:
	var root := Node3D.new()
	root.name = block_name
	var kit := MeshKit.new()
	kit.add_box(&"m", Vector3(0.0, size.y * 0.5, 0.0), size, tone, Basis.IDENTITY, true)
	return _finish(root, kit, {&"m": material}, size)


## Постройка-коробка: стены, плита крыши со свесом, дверь или ворота
## на лицевой стороне (door.x — ширина, door.y — высота; 0 — без двери),
## заколоченные витрины (windows — число проёмов на лице).
static func building(
	building_name: String, size: Vector3, wall: Material, roof: Material,
	door: Vector2, door_material: Material, windows: int, seed_value: int
) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var root := Node3D.new()
	root.name = building_name
	var kit := MeshKit.new()
	var tone := Color.WHITE * rng.randf_range(0.85, 1.0)
	kit.add_box(&"wall", Vector3(0.0, size.y * 0.5, 0.0), size, tone, Basis.IDENTITY, true)
	kit.add_box(
		&"roof", Vector3(0.0, size.y + 0.07, 0.0),
		Vector3(size.x + 0.3, 0.14, size.z + 0.3), Color.WHITE * rng.randf_range(0.8, 1.0))
	var front: float = size.z * 0.5
	if door.x > 0.0:
		var dx: float = 0.0 if windows == 0 else -size.x * 0.5 + door.x * 0.5 + 0.6
		kit.add_box(
			&"door", Vector3(dx, door.y * 0.5 + 0.03, front + 0.02),
			Vector3(door.x, door.y, 0.06), Color.WHITE * rng.randf_range(0.7, 1.0))
	if windows > 0:
		var span: float = size.x - door.x - 1.6
		var ww: float = span / float(windows) - 0.4
		for i: int in windows:
			var wx: float = -size.x * 0.5 + door.x + 1.2 + (float(i) + 0.5) * span / float(windows)
			kit.add_box(
				&"void", Vector3(wx, size.y * 0.55, front + 0.005),
				Vector3(ww, size.y * 0.5, 0.02))
			for k: int in 3:
				var tilt := Basis(Vector3.BACK, rng.randf_range(-0.08, 0.08))
				kit.add_box(
					&"boards",
					Vector3(wx, size.y * (0.38 + 0.17 * float(k)), front + 0.04),
					Vector3(ww + 0.3, size.y * 0.12, 0.03),
					Color.WHITE * rng.randf_range(0.7, 1.0), tilt)
	var materials: Dictionary = DistrictMaterials.house_set()
	materials[&"wall"] = wall
	materials[&"roof"] = roof
	materials[&"door"] = door_material
	return _finish(root, kit, materials, size)
