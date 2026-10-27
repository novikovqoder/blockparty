# Диагностика П15: компилируются ли шейдеры воды после правок (нормали
# во fragment, пиксельная фильтрация, движковое отражение, пена по SDF).
# В headless (dummy-рендер) шейдеры не компилируются, поэтому прогон
# под xvfb:
#   xvfb-run -a godot --path . --rendering-driver opengl3 \
#     -s res://tools/probe_water_shader.gd
# Спектр волн — реальный (WaterArea.wave_spectrum, статические данные),
# материалы без autoload-зависимостей. Ошибки компиляции Godot печатает
# в stderr (SHADER ERROR); PASS — кадры отрисованы.
extends SceneTree

const WATER_BU: Shader = preload("res://assets/shaders/water_bu.gdshader")
const WATER_BU_CHEAP: Shader = preload(
	"res://assets/shaders/water_bu_cheap.gdshader")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var root3d := Node3D.new()
	root.add_child(root3d)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 2.0, 3.0)
	root3d.add_child(camera)
	camera.current = true
	var plane := PlaneMesh.new()
	plane.size = Vector2(8.0, 8.0)
	plane.subdivide_width = 4
	plane.subdivide_depth = 4
	# Полный шейдер (морской спектр) и дешёвая версия.
	await _draw_plane(root3d, plane, WATER_BU, 32, true)
	await _draw_plane(root3d, plane, WATER_BU, 16, true)
	await _draw_plane(root3d, plane, WATER_BU_CHEAP, 8, false)
	print("PASS: шейдеры воды скомпилировались (32/16 волн, дешёвый)")
	quit(0)


func _draw_plane(
	root3d: Node3D, plane: PlaneMesh, shader: Shader,
	wave_count: int, sea: bool,
) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = "Water%d" % wave_count
	mesh.mesh = plane
	var material := ShaderMaterial.new()
	material.shader = shader
	var spectrum: Array = WaterArea.wave_spectrum(sea)
	material.set_shader_parameter("waves_a", spectrum[0])
	material.set_shader_parameter("waves_b", spectrum[1])
	material.set_shader_parameter("wave_count", wave_count)
	mesh.material_override = material
	root3d.add_child(mesh)
	# Два кадра: первый — компиляция и загрузка uniform-текстур.
	await process_frame
	await process_frame
	mesh.queue_free()
	await process_frame
	print("кадр %s (%d волн) отрисован" % [
		shader.resource_path.get_file(), wave_count])
