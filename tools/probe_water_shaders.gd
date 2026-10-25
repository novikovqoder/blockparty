# Диагностика П12 F: компилируются ли копии шейдера воды. В headless
# (dummy-рендер) шейдеры не компилируются, поэтому прогон под xvfb:
#   xvfb-run -a godot --path . --rendering-driver opengl3 \
#     -s res://tools/probe_water_shaders.gd
# PASS — оба материала пережили по кадру рендера; ошибки компиляции
# Godot сам печатает в stderr (SHADER ERROR). Сцену проекта не грузит
# (boot-ловушка не при чём: boot не добавляется).
extends SceneTree

const PLAIN: Shader = preload("res://assets/shaders/water_plain.gdshader")
const REFRACTION: Shader = preload(
	"res://assets/shaders/water_refraction.gdshader")
const FOAM_TEX: Texture2D = preload(
	"res://addons/boujie_water_shader/shader/foam_1.png")
const REFRACTION_TEX: Texture2D = preload(
	"res://addons/boujie_water_shader/shader/refraction.png")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var root3d := Node3D.new()
	root.add_child(root3d)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 0.0, 3.0)
	root3d.add_child(camera)
	camera.current = true
	var checks: PackedStringArray = PackedStringArray()
	for shader: Shader in [PLAIN, REFRACTION]:
		var mesh := MeshInstance3D.new()
		mesh.name = "Quad"
		var quad := QuadMesh.new()
		quad.size = Vector2(2.0, 2.0)
		mesh.mesh = quad
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("albedo", Color(0.05, 0.08, 0.07, 0.72))
		material.set_shader_parameter("texture_foam", FOAM_TEX)
		material.set_shader_parameter("texture_refraction", REFRACTION_TEX)
		mesh.material_override = material
		root3d.add_child(mesh)
		await process_frame
		await process_frame
		if material.get_shader_parameter("albedo") == null:
			checks.append("%s: параметр albedo не читается" % shader.resource_path)
		print("кадр с %s отрисован" % shader.resource_path.get_file())
		mesh.queue_free()
		await process_frame
	if checks.is_empty():
		print("PASS: оба шейдера воды скомпилировались")
		quit(0)
	else:
		for line: String in checks:
			printerr("FAIL: %s" % line)
		quit(1)
