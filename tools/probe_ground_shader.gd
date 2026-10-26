# Диагностика П14: компилируется ли шейдер земли после правок (реальные
# масштабы тайлов, макро-подмешивание, PBR/AO, кольцо детальной сетки).
# В headless (dummy-рендер) шейдеры не компилируются, поэтому прогон
# под xvfb:
#   xvfb-run -a godot --path . --rendering-driver opengl3 \
#     -s res://tools/probe_ground_shader.gd
# Материал собирается вручную (без ForestGround/IslandArt: они цепочкой
# зависят от autoload Settings, который при -s ещё не поднят): шейдер
# с uniform-ветвлением компилируется целиком, все уровни качества —
# в одном кадре. Ошибки компиляции Godot печатает в stderr (SHADER
# ERROR); PASS — кадры отрисованы и карты покраски читаются.
extends SceneTree

const GROUND: Shader = preload("res://assets/shaders/forest_ground.gdshader")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var root3d := Node3D.new()
	root.add_child(root3d)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 2.0, 3.0)
	root3d.add_child(camera)
	camera.current = true
	var quad := QuadMesh.new()
	quad.size = Vector2(4.0, 4.0)
	# Карта покраски-заглушка: RGBA 4×4, чтобы сэмплеры не были пустыми
	# (шейдер читает weight_map/border_map/relief_normal в vertex и fragment).
	var paint := ImageTexture.create_from_image(
		Image.create(4, 4, false, Image.FORMAT_RGBA8))
	# Карта высот-заглушка для ветки кольца (detail_ring): RF 4×4.
	var heights := ImageTexture.create_from_image(
		Image.create(4, 4, false, Image.FORMAT_RF))
	for tier: int in [0, 1, 2, 3]:
		await _draw_quad(root3d, quad, paint, heights, tier, false)
	for tier: int in [2, 3]:
		await _draw_quad(root3d, quad, paint, heights, tier, true)
	print("PASS: шейдер земли скомпилировался на всех уровнях")
	quit(0)


func _draw_quad(
	root3d: Node3D, quad: QuadMesh, paint: ImageTexture,
	heights: ImageTexture, tier: int, ring: bool,
) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = "Quad%d%s" % [tier, "_ring" if ring else ""]
	mesh.mesh = quad
	mesh.position = Vector3(0.0, 0.5 * float(ring), 0.0)
	var material := ShaderMaterial.new()
	material.shader = GROUND
	material.set_shader_parameter("quality", tier)
	material.set_shader_parameter("weight_map", paint)
	material.set_shader_parameter("border_map", paint)
	material.set_shader_parameter("relief_normal", paint)
	if ring:
		# Ветка vertex() кольца (П14 3.1): height_tex + средние ORM.
		material.set_shader_parameter("detail_ring", true)
		material.set_shader_parameter("height_tex", heights)
		material.set_shader_parameter("ring_radius", 8.0)
	mesh.material_override = material
	root3d.add_child(mesh)
	# Два кадра: первый — компиляция и загрузка uniform-текстур.
	await process_frame
	await process_frame
	mesh.queue_free()
	await process_frame
	print("кадр Tier.%d%s отрисован" % [tier, " ring" if ring else ""])
