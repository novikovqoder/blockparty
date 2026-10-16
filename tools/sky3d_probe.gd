# Проба совместимости Sky3D с Godot 4.7.2 (П5.9 блок 6): создаёт Sky3D,
# гоняет несколько кадров и снимает скриншоты полдня/заката/ночи. Запуск:
#   xvfb-run -a godot --path . --rendering-driver opengl3 \
#     -s tools/sky3d_probe.gd
# PASS — структура нод на месте, шейдер скомпилировался, кадры не пустые.
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var root3d := Node3D.new()
	root.add_child(root3d)
	var sky: WorldEnvironment = load(
		"res://addons/sky_3d/src/Sky3D.gd").new() as WorldEnvironment
	root3d.add_child(sky)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 2.0, 0.0)
	root3d.add_child(camera)
	camera.current = true
	var checks: PackedStringArray = PackedStringArray()
	for child: String in ["SunLight", "MoonLight", "SkyDome", "TimeOfDay"]:
		if sky.get_node_or_null(child) == null:
			checks.append("нет %s" % child)
	var dome: Node = sky.get_node("SkyDome")
	var material: ShaderMaterial = sky.environment.sky.sky_material
	if material == null or material.shader == null:
		checks.append("материал неба не собрался")
	if not checks.is_empty():
		for line: String in checks:
			push_error("SKY3D-PROBE: FAIL — " + line)
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute("res://builds/screenshots")
	# Полдень → закат → ночь: sun_altitude здесь — полярный угол от зенита
	# (0 — в зените, ~90° — горизонт, >90° — под горизонтом).
	dome.set("sun_altitude", deg_to_rad(-62.0))
	await _snap("noon")
	dome.set("sun_altitude", deg_to_rad(-6.0))
	await _snap("dusk")
	dome.set("sun_altitude", deg_to_rad(120.0))
	dome.set("moon_altitude", deg_to_rad(-30.0))
	await _snap("night")
	print("SKY3D-PROBE: PASS — структура и шейдер в порядке")
	quit(0)


func _snap(tag: String) -> void:
	for i: int in 4:
		await process_frame
	var image := root.get_viewport().get_texture().get_image()
	image.save_png("res://builds/screenshots/sky3d_probe_%s.png" % tag)
	print("SKY3D-PROBE: кадр %s сохранён" % tag)
