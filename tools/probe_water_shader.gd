# Диагностика П15: компилируются ли шейдеры воды после правок (волны
# sea_octave П15-ДОП, нормали во fragment, пиксельная фильтрация,
# движковое отражение, пена по SDF). В headless (dummy-рендер) шейдеры
# не компилируются, поэтому прогон под xvfb:
#   xvfb-run -a godot --path . --rendering-driver opengl3 \
#     -s res://tools/probe_water_shader.gd
# Параметры волн — реальные константы WaterArea (морская и озерная
# зоны), материалы без autoload-зависимостей. Ошибки компиляции Godot
# печатает в stderr (SHADER ERROR); PASS — кадры отрисованы.
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
	# Полный шейдер (море/озеро, октавы ULTRA/HIGH) и дешёвая версия.
	await _draw_plane(root3d, plane, WATER_BU, true, 5)
	await _draw_plane(root3d, plane, WATER_BU, true, 4)
	await _draw_plane(root3d, plane, WATER_BU, false, 4)
	await _draw_plane(root3d, plane, WATER_BU_CHEAP, true, 3)
	print("PASS: шейдеры воды скомпилировались "
		+ "(море/озеро, 5/4 октавы, дешёвый)")
	quit(0)


func _draw_plane(
	root3d: Node3D, plane: PlaneMesh, shader: Shader,
	sea: bool, iter_fragment: int,
) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = "Water%d%d" % [1 if sea else 0, iter_fragment]
	mesh.mesh = plane
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("sea_height",
		WaterArea.SEA_WAVE_HEIGHT if sea else WaterArea.LAKE_WAVE_HEIGHT)
	material.set_shader_parameter("sea_choppiness",
		WaterArea.SEA_WAVE_CHOPPY if sea else WaterArea.LAKE_WAVE_CHOPPY)
	material.set_shader_parameter("sea_speed",
		WaterArea.SEA_WAVE_SPEED if sea else WaterArea.LAKE_WAVE_SPEED)
	material.set_shader_parameter("sea_freq",
		WaterArea.SEA_WAVE_FREQ if sea else WaterArea.LAKE_WAVE_FREQ)
	material.set_shader_parameter("iter_fragment", iter_fragment)
	mesh.material_override = material
	root3d.add_child(mesh)
	# Два кадра: первый — компиляция и загрузка uniform-текстур.
	await process_frame
	await process_frame
	mesh.queue_free()
	await process_frame
	print("кадр %s (%s, %d октав) отрисован" % [
		shader.resource_path.get_file(), "море" if sea else "озеро",
		iter_fragment])
