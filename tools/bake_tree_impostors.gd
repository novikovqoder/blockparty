# Запекание импосторов дальних деревьев (П17 п.3): для каждой базы GLB
# из EzTreeMeshes.ASSETS рендерит LOD0 (k = 1, без масштаба варианта) в
# SubViewport с 16 ракурсов — 8 азимутов × 2 подъёма — и собирает два
# атласа 1024×1024 (кадр 256 px — нижняя граница плана «256–512 px на
# кадр» и порог аудита текстур assets/visual ≥1024):
#   assets/visual/trees/impostors/<base>_impostor.png        — albedo+альфа
#   assets/visual/trees/impostors/<base>_impostor_normal.png — нормали
#     в базисе кадра (right, up, к камере): RGB = (n·basis) * 0.5 + 0.5
#   assets/visual/trees/impostors/manifest.json              — раскладка
# Запуск на сервере (обкатанная схема tools/fog_lab.gd):
#   xvfb-run -a godot --path . --rendering-driver opengl3 \
#     --script tools/bake_tree_impostors.gd   (GL; --headless не годится).
# Рендер при ЖИВОЙ петле: UPDATE_ALWAYS + два process_frame и пауза на
# каждый кадр — под llvmpipe синхронный force_draw отдаёт ещё не
# отрисованный кадр (первые кадры атласов выходили пустыми).
# Пропорции дерева в кадре — от AABB базы: варианты видов отличаются
# только масштабом, атлас базу один на все варианты (quad масштабируется).
extends SceneTree

const OUT_DIR: String = "res://assets/visual/trees/impostors/"
## Кадры: 8 азимутов (шаг 45°) × 2 подъёма камеры; атлас 4×4 кадра 256 px.
const AZIMUTH_STEPS: int = 8
const ELEVATIONS: Array[float] = [8.0, 26.0]
const FRAME_PX: int = 256
const COLS: int = 4
const ROWS: int = 4

## Шейдеры запекания (живут только здесь, в ассеты не идут): albedo —
## текстура поверхности × тон пресета × вершинный AO (COLOR, П17 п.2),
## вырезка альфы порогом вида; без света и без ветра (TIME у реального
# canopy-шейдера менял бы кадры от ракурса к ракурсу). Нормали — нормаль
# геометрии в базисе ракурса (right/up/к камере), альфа той же вырезкой.
const ALBEDO_SHADER_CODE: String = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
uniform sampler2D face_tex : source_color, filter_linear_mipmap;
uniform vec3 face_tint : source_color = vec3(1.0);
uniform float alpha_cut = 0.5;
void fragment() {
	vec4 face = texture(face_tex, UV);
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ALPHA = face.a;
	ALBEDO = face.rgb * face_tint * COLOR.rgb;
}
"""
const NORMAL_SHADER_CODE: String = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
uniform sampler2D face_tex : source_color, filter_linear_mipmap;
uniform float alpha_cut = 0.5;
uniform vec3 basis_right = vec3(1.0, 0.0, 0.0);
uniform vec3 basis_up = vec3(0.0, 1.0, 0.0);
uniform vec3 basis_view = vec3(0.0, 0.0, 1.0);
void fragment() {
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ALPHA = texture(face_tex, UV).a;
	vec3 world_normal = normalize(
		(MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	ALBEDO = vec3(
		dot(world_normal, basis_right),
		dot(world_normal, basis_up),
		dot(world_normal, basis_view)) * 0.5 + 0.5;
}
"""

var _albedo_shader: Shader
var _normal_shader: Shader


func _initialize() -> void:
	# Живая петля (fog_lab.gd): под llvmpipe синхронный force_draw отдаёт
	# не отрисованный кадр, UPDATE_ALWAYS + пауза надёжнее.
	await _bake_all()
	quit()


func _bake_all() -> void:
	_albedo_shader = Shader.new()
	_albedo_shader.code = ALBEDO_SHADER_CODE
	_normal_shader = Shader.new()
	_normal_shader.code = NORMAL_SHADER_CODE

	var bases := _unique_bases()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for base: String in bases:
		var started := Time.get_ticks_msec()
		var ok := await _bake_base(base)
		print("%s: %s (%.1f с)" % [
			base, "готово" if ok else "ОШИБКА",
			(Time.get_ticks_msec() - started) / 1000.0])
	var manifest: Dictionary = {
		"frame_px": FRAME_PX,
		"cols": COLS,
		"rows": ROWS,
		"azimuth_steps": AZIMUTH_STEPS,
		"elevations": ELEVATIONS,
	}
	var file := FileAccess.open(OUT_DIR + "manifest.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	print("Готово: %d баз, атласы в %s" % [bases.size(), OUT_DIR])


## Все базы видов:вариантов (уникальные GLB, без повторов масштаба).
func _unique_bases() -> Array[String]:
	var bases: Array[String] = []
	for type: StringName in EzTreeMeshes.ASSETS:
		for entry: Array in EzTreeMeshes.ASSETS[type]:
			if not bases.has(String(entry[0])):
				bases.append(String(entry[0]))
	bases.sort()
	return bases


## Одна база: 16 кадров в два атласа. Меш — _lod_mesh с k = 1 (масштаб
## варианта не влияет на пропорции кадра), материалы заменены на шейдеры
## запекания с параметрами реальных поверхностей.
func _bake_base(base: String) -> bool:
	var info := EzTreeMeshes.entry(base)
	if info.is_empty():
		return false
	var source: ArrayMesh = EzTreeMeshes._lod_mesh(base, 0, 1.0, info)
	if source.get_surface_count() == 0:
		push_error("%s: пустой меш LOD0" % base)
		return false
	var aabb := source.get_aabb()
	var center := aabb.get_center()

	var viewport := SubViewport.new()
	viewport.size = Vector2i(FRAME_PX, FRAME_PX)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var holder := Node3D.new()
	viewport.add_child(holder)
	var root := Node3D.new()
	root.add_child(viewport)
	get_root().add_child(root)

	var albedo := Image.create(COLS * FRAME_PX, ROWS * FRAME_PX,
		false, Image.FORMAT_RGBA8)
	var normals := Image.create(COLS * FRAME_PX, ROWS * FRAME_PX,
		false, Image.FORMAT_RGB8)

	var frame := 0
	var empty_frames := 0
	for elevation: float in ELEVATIONS:
		for step: int in AZIMUTH_STEPS:
			var azimuth: float = TAU * float(step) / float(AZIMUTH_STEPS)
			var cell := Vector2i(frame % COLS, frame / COLS)
			frame += 1
			# Два прохода кадра: albedo и нормали.
			for normal_pass: bool in [false, true]:
				_setup_frame(holder, source, center, aabb,
					azimuth, elevation, normal_pass)
				await process_frame
				await process_frame
				await create_timer(0.25).timeout
				var shot := viewport.get_texture().get_image()
				# Контроль живого силуэта (каждый 4-й пиксель): пустой кадр —
				# признак мёртвой камеры/материала, атлас с ним бракуем.
				if not normal_pass and _solid_share(shot) < 0.005:
					empty_frames += 1
				_blit(shot, normals if normal_pass else albedo, cell)
	root.free()
	if empty_frames > 0:
		push_error("%s: %d пустых кадров — атлас не записан" % [
			base, empty_frames])
		return false
	albedo.save_png(OUT_DIR + "%s_impostor.png" % base)
	normals.save_png(OUT_DIR + "%s_impostor_normal.png" % base)
	return true


## Кадр: дерево с материалом прохода, ортокамера на ракурсе. Камера и меш
## пересоздаются на каждый кадр — атласу нужны 16 независимых ракурсов.
func _setup_frame(holder: Node3D, source: ArrayMesh,
		center: Vector3, aabb: AABB, azimuth: float, elevation: float,
		normal_pass: bool
) -> void:
	for child: Node in holder.get_children():
		holder.remove_child(child)
		child.queue_free()
	var mesh := MeshInstance3D.new()
	mesh.mesh = _bake_mesh(source, normal_pass, azimuth, elevation)
	holder.add_child(mesh)

	# Направление «дерево → камера» (к зрителю) задаёт и базис нормалей.
	var direction := Vector3(
		cos(deg_to_rad(elevation)) * sin(azimuth),
		sin(deg_to_rad(elevation)),
		cos(deg_to_rad(elevation)) * cos(azimuth))
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	# Кадр покрывает всё дерево с запасом 8 % по вертикали и ширине.
	var spread: float = maxf(aabb.size.y, maxf(aabb.size.x, aabb.size.z))
	camera.size = spread * 1.08
	camera.near = 0.1
	camera.far = aabb.size.length() * 4.0
	camera.position = center + direction * aabb.size.length() * 1.5
	# Ориентация без look_at (узел ещё не в дереве): -Z камеры — на центр.
	# make_current — строго ПОСЛЕ add_child: у камеры, созданной кодом,
	# current=false, без этого SubViewport без активной камеры и рисует
	# пустой прозрачный кадр (кадры атласов выходили нулями).
	camera.basis = Basis.looking_at(-direction, Vector3.UP)
	holder.add_child(camera)
	camera.make_current()


## Копия меша с материалами запекания: параметры поверхностей (текстуры,
## тон, порог вырезки) — из реальных материалов LOD0; кору красит нечем —
# тон белый, порог нейтральный (альфа карты коры непрозрачная).
func _bake_mesh(source: ArrayMesh, normal_pass: bool,
		azimuth: float, elevation: float
) -> ArrayMesh:
	var direction := Vector3(
		cos(deg_to_rad(elevation)) * sin(azimuth),
		sin(deg_to_rad(elevation)),
		cos(deg_to_rad(elevation)) * cos(azimuth))
	var right := Vector3.UP.cross(direction).normalized()
	var up := direction.cross(right).normalized()

	var mesh := ArrayMesh.new()
	for surface: int in source.get_surface_count():
		var material := source.surface_get_material(surface) as ShaderMaterial
		var is_canopy: bool = material != null \
			and material.shader == EzTreeMeshes.CANOPY_SHADER
		var bake := ShaderMaterial.new()
		bake.shader = _normal_shader if normal_pass else _albedo_shader
		bake.set_shader_parameter("face_tex", material.get_shader_parameter(
			"leaf_tex" if is_canopy else "bark_tex"))
		if is_canopy:
			bake.set_shader_parameter(
				"face_tint", material.get_shader_parameter("leaf_tint"))
			bake.set_shader_parameter(
				"alpha_cut", material.get_shader_parameter("alpha_cut"))
		else:
			bake.set_shader_parameter("face_tint", Color.WHITE)
			bake.set_shader_parameter("alpha_cut", 0.5)
		if normal_pass:
			bake.set_shader_parameter("basis_right", right)
			bake.set_shader_parameter("basis_up", up)
			bake.set_shader_parameter("basis_view", direction)
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,
			source.surface_get_arrays(surface))
		mesh.surface_set_material(mesh.get_surface_count() - 1, bake)
	return mesh


## Пиксели кадра → ячейка атласа (кадр SubViewport RGBA8, атлас нормалей
## RGB8 — конверсия формата перед blit).
func _blit(shot: Image, atlas: Image, cell: Vector2i) -> void:
	if shot.get_format() != atlas.get_format():
		shot.convert(atlas.get_format())
	atlas.blit_rect(shot, Rect2i(0, 0, FRAME_PX, FRAME_PX),
		cell * FRAME_PX)


## Доля непрозрачных пикселей кадра (каждый 4-й пиксель, alpha ≥ 0.3):
## живой силуэт дерева занимает и не 0 % (пустой кадр), и не ~100 %
## (сплошной прямоугольник — вырезка альфы не сработала).
func _solid_share(image: Image) -> float:
	var data := image.get_data()
	var solid := 0
	var total := 0
	for i: int in range(3, data.size(), 16):
		total += 1
		if data[i] >= 77:
			solid += 1
	return float(solid) / float(maxi(total, 1))
