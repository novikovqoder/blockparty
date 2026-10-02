# Вода (раздел 6 SPEC): Area3D-зона плавания + плоскость с шейдером волн.
# Персонаж в зоне плавает на поверхности со скоростью шага (само плавание —
# в Player.enter_water/exit_water); этой зоне всё равно, кто в ней плавает,
# поэтому связь — только вызовы методов тел (как PitArea в v1).
# Не делает: подводное плавание (вне MVP), течение и волны для лодочек (П2).
class_name WaterArea
extends Area3D

const PAL: Palette = preload("res://assets/palette.tres")
const SHADER: Shader = preload("res://gameplay/world/water_wave.gdshader")

## Высота зоны под поверхностью воды, м.
const DEPTH: float = 1.4
## Зона заканчивается чуть выше поверхности, м.
const SURFACE_GAP: float = 0.2
## Плотность сетки плоскости, вершин на метр.
const MESH_DENSITY: float = 2.0

var _level: float = 0.0


func _ready() -> void:
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 2  # слой игроков
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


## Построить зону: центр в плоскости XZ, размер, уровень воды (абсолютный Y).
func setup(center_xz: Vector2, size: Vector2, level: float) -> void:
	_level = level
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, DEPTH + SURFACE_GAP, size.y)
	shape.shape = box
	add_child(shape)
	position = Vector3(center_xz.x, level + (SURFACE_GAP - DEPTH) * 0.5, center_xz.y)
	_build_surface(size)


func water_level() -> float:
	return _level


func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		(body as Player).enter_water(_level)


func _on_body_exited(body: Node3D) -> void:
	if body is Player:
		(body as Player).exit_water()


func _build_surface(size: Vector2) -> void:
	var surface := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = size
	plane.subdivide_width = maxi(2, int(size.x * MESH_DENSITY))
	plane.subdivide_depth = maxi(2, int(size.y * MESH_DENSITY))
	surface.mesh = plane
	surface.material_override = _surface_material()
	surface.position = Vector3(0.0, _level - position.y, 0.0)
	add_child(surface)


## В нормальном рендере — шейдер волн; в headless (dummy-рендер без шейдеров,
## серверные прогоны) — полупрозрачный стандартный материал без волн.
func _surface_material() -> Material:
	if DisplayServer.get_name() == "headless":
		var flat := StandardMaterial3D.new()
		flat.albedo_color = PAL.water
		flat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		flat.albedo_color.a = 0.55
		return flat
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("water_color", Color(PAL.water, 0.55))
	return material
