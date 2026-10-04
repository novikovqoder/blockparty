# Вода (раздел 6 SPEC): Area3D-зона плавания + плоскость с шейдером волн.
# Персонаж в зоне плавает на поверхности со скоростью шага (само плавание —
# в Player.enter_water/exit_water); этой зоне всё равно, кто в ней плавает,
# поэтому связь — только вызовы методов тел (как PitArea в v1).
# Параметры воды — @export: сцена острова собирается оффлайн
# (tools/generate_island.gd), поверхность строится в _ready при входе в дерево,
# чтобы в сохранённой сцене не запекался headless-материал.
# Не делает: подводное плавание (вне MVP), течение и волны для лодочек.
class_name WaterArea
extends Area3D

const PAL: Palette = preload("res://assets/palette.tres")
const SHADER: Shader = preload("res://gameplay/world/water_wave.gdshader")

## Высота зоны под поверхностью воды, м.
const DEPTH: float = 1.4
## Плотность сетки плоскости, вершин на метр.
const MESH_DENSITY: float = 2.0
## Предел сегментов плоскости (море 256 × 256 м — без него 512 × 512 вершин).
const MAX_SUBDIVIDE: int = 192

## Размер плоскости воды, м (0 — зона не настроена).
@export var surface_size: Vector2 = Vector2.ZERO
## Уровень воды, абсолютный Y, м.
@export var water_level: float = 0.0
## Насколько зона заканчивается выше поверхности: 0.2 — пруды площадки,
## 0 — море и озеро острова (пляж вплотную к воде, раздел 6).
@export var surface_gap: float = 0.2

var _surface_built: bool = false


func _ready() -> void:
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 2  # слой игроков
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if surface_size != Vector2.ZERO:
		_build_surface()


## Построить зону: центр в плоскости XZ, размер, уровень воды (абсолютный Y).
## Коллизия добавляется сразу (сериализуется в сцену), плоскость — при входе
## в дерево, если нода ещё не в нём, иначе сразу (площадка П1 собирает так).
func setup(center_xz: Vector2, size: Vector2, level: float, gap: float = 0.2) -> void:
	water_level = level
	surface_size = size
	surface_gap = gap
	for child in get_children():
		if child is CollisionShape3D:
			remove_child(child)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, DEPTH + gap, size.y)
	shape.shape = box
	add_child(shape)
	position = Vector3(center_xz.x, level + (gap - DEPTH) * 0.5, center_xz.y)
	if is_inside_tree():
		_build_surface()


func level() -> float:
	return water_level


func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		(body as Player).enter_water(water_level)
		# Круги на воде при входе в неё (раздел 16).
		var pos: Vector3 = (body as Node3D).global_position
		Fx.water_ring(
			get_parent(), Vector3(pos.x, water_level + 0.02, pos.z),
			PAL.water.lightened(0.35),
		)


func _on_body_exited(body: Node3D) -> void:
	if body is Player:
		(body as Player).exit_water()


func _build_surface() -> void:
	if _surface_built:
		return
	_surface_built = true
	var surface := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = surface_size
	plane.subdivide_width = clampi(int(surface_size.x * MESH_DENSITY), 2, MAX_SUBDIVIDE)
	plane.subdivide_depth = clampi(int(surface_size.y * MESH_DENSITY), 2, MAX_SUBDIVIDE)
	surface.mesh = plane
	surface.material_override = _surface_material()
	surface.position = Vector3(0.0, water_level - position.y, 0.0)
	add_child(surface)
	surface.set_owner(null)  # не сериализовать: строится в рантайме


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
