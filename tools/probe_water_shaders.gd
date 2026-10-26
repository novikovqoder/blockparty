# Диагностика П14 4: компилируются ли шейдеры воды water_bu (полная
# версия с экранной текстурой и глубиной) и water_bu_cheap. В headless
# (dummy-рендер) шейдеры не компилируются, поэтому прогон под xvfb:
#   xvfb-run -a godot --path . --rendering-driver opengl3 \
#     -s res://tools/probe_water_shaders.gd
# PASS — оба материала пережили по кадру рендера (у полной версии —
# со спектром волн и всеми уровнями ряби); ошибки компиляции Godot сам
# печатает в stderr (SHADER ERROR). Сцену проекта не грузит (boot-ловушка
# не при чём: boot не добавляется).
extends SceneTree

const WATER_BU: Shader = preload("res://assets/shaders/water_bu.gdshader")
const WATER_CHEAP: Shader = preload(
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
	# Полная версия: море и озеро, рябь 0/2/3 слоя (ветки fragment).
	for calm: bool in [true, false]:
		for ripple: int in [0, 2, 3]:
			await _draw_water(root3d, WATER_BU, calm, ripple)
	# Дешёвая: одна ветка (волн 8, рябь 1 — константы материала).
	await _draw_water(root3d, WATER_CHEAP, true, 1)
	print("PASS: шейдеры воды water_bu скомпилировались")
	quit(0)


func _draw_water(
	root3d: Node3D, shader: Shader, calm: bool, ripple: int,
) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = "Water%s%d" % ["Lake" if calm else "Sea", ripple]
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	mesh.mesh = quad
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("color_deep",
		WaterArea.LAKE_DEEP if calm else WaterArea.SEA_DEEP)
	material.set_shader_parameter("color_shallow",
		WaterArea.LAKE_SHALLOW if calm else WaterArea.SEA_SHALLOW)
	material.set_shader_parameter("absorption",
		WaterArea.LAKE_ABSORPTION if calm else WaterArea.SEA_ABSORPTION)
	var spectrum: Array = WaterArea.wave_spectrum(not calm)
	material.set_shader_parameter("waves_a", spectrum[0])
	material.set_shader_parameter("waves_b", spectrum[1])
	material.set_shader_parameter("wave_count", spectrum[0].size())
	material.set_shader_parameter("ripple_layers", float(ripple))
	mesh.material_override = material
	root3d.add_child(mesh)
	await process_frame
	await process_frame
	print("кадр %s (рябь %d) отрисован" % [mesh.name, ripple])
	mesh.queue_free()
	await process_frame
