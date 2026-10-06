# Тесты сторонних CC0-ресурсов (шаг 3 П4.5, правила — CLAUDE.md):
# каждый файл assets/third_party упомянут в LICENSES.md (и наоборот — записи
# указывают на существующие файлы), форматы допустимые, общий размер в лимите,
# и все модели Cc0Meshes реально лежат на диске (набор не «переезда» без
# правки кода). Ресурсы с неизвестной лицензией в проект не попадают.
extends GutTest

const ROOT: String = "res://assets/third_party"
const LICENSES: String = "res://assets/third_party/LICENSES.md"
## Префиксы каталогов наборов в колонке «Файлы» LICENSES.md.
const VENDOR_PREFIXES: PackedStringArray = ["kenney.nl/", "kaykit/"]
## Допустимые форматы (CLAUDE.md, «Скачивание ресурсов»).
const FORMATS: PackedStringArray = [
	".glb", ".gltf", ".obj", ".png", ".jpg", ".webp", ".hdr", ".exr",
	".ogg", ".wav", ".ttf", ".otf",
]
## Лимит общего размера ресурсов (CLAUDE.md).
const SIZE_LIMIT_MB: float = 300.0


func _files_under(path: String) -> PackedStringArray:
	var found := PackedStringArray()
	for file: String in DirAccess.get_files_at(path):
		if file == ".gdignore" or file == "LICENSES.md":
			continue
		# .import/.uid — служебные файлы Godot рядом с ресурсом (наборы
		# KayKit импортируются движком, в отличие от закрытых .gdignore
		# наборов Kenney): генерируются автоматически, не скачиваются.
		if file.ends_with(".import") or file.ends_with(".uid"):
			continue
		found.append(path.path_join(file))
	for dir: String in DirAccess.get_directories_at(path):
		found.append_array(_files_under(path.path_join(dir)))
	return found


func test_every_third_party_file_is_licensed() -> void:
	var text: String = FileAccess.get_file_as_string(LICENSES)
	assert_false(text.is_empty(), "LICENSES.md существует и не пуст")
	for path: String in _files_under(ROOT):
		assert_true(
			text.contains(path.get_file()),
			"%s упомянут в LICENSES.md" % path.get_file(),
		)


func test_licenses_have_no_stale_entries() -> void:
	# Обратная проверка: точные файлы из записей существуют, а маски
	# (например `kenney.nl/nature-kit/*.glb`) указывают на непустой каталог.
	var text: String = FileAccess.get_file_as_string(LICENSES)
	for line: String in text.split("\n"):
		if not line.begins_with("|") or "CC0" not in line:
			continue
		for token: String in line.split("`"):
			var from_set := false
			for prefix: String in VENDOR_PREFIXES:
				if token.begins_with(prefix):
					from_set = true
			if not from_set:
				continue
			var looks_like_file := false
			for ext: String in FORMATS:
				if token.ends_with(ext):
					looks_like_file = true
			if looks_like_file:
				assert_true(
					FileAccess.file_exists(ROOT.path_join(token)),
					"файл из LICENSES.md существует: %s" % token,
				)
			else:
				# Маска или каталог: должен существовать и не быть пустым.
				var dir: String = token.get_base_dir().split(":")[0].strip_edges()
				assert_true(
					not _files_under(ROOT.path_join(dir)).is_empty(),
					"каталог из LICENSES.md не пуст: %s" % token,
				)


func test_formats_and_size_limit() -> void:
	var total := 0.0
	for path: String in _files_under(ROOT):
		var format_ok := false
		for ext: String in FORMATS:
			if path.get_extension() == ext.substr(1):
				format_ok = true
		assert_true(format_ok, "%s: допустимый формат" % path)
		var file := FileAccess.open(path, FileAccess.READ)
		assert_not_null(file, "%s открывается" % path)
		if file != null:
			total += file.get_length()
	assert_lt(
		total / (1024.0 * 1024.0), SIZE_LIMIT_MB,
		"общий размер third_party < %.0f МБ (факт %.1f МБ)"
		% [SIZE_LIMIT_MB, total / (1024.0 * 1024.0)],
	)


func test_cc0_models_exist_on_disk() -> void:
	# Каждая модель из таблицы Cc0Meshes лежит в assets/third_party —
	# запекание острова не зависит от файлов, которых нет в репозитории.
	for type: StringName in Cc0Meshes.MODELS:
		var cfg: Array = Cc0Meshes.MODELS[type]
		for file: String in cfg[1]:
			var path: String = "%s/%s/%s/%s.glb" % [
				ROOT, "kenney.nl", cfg[0], file,
			]
			assert_true(
				FileAccess.file_exists(path),
				"модель %s (%s) существует" % [file, type],
			)


func test_cc0_meshes_have_colors_and_stand_on_ground() -> void:
	# CC0-модель после конвертации — тот же контракт, что у процедурных
	# мешей: цвет каждой вершине, грани есть, «ноги» в origin, размер
	# в окрестности эталона из таблицы (±40 % — варианты бывают короче).
	for type: StringName in Cc0Meshes.MODELS:
		var cfg: Array = Cc0Meshes.MODELS[type]
		for variant: int in (cfg[1] as PackedStringArray).size():
			var mesh: ArrayMesh = Cc0Meshes.mesh(type, variant)
			assert_gt(mesh.get_surface_count(), 0, "%s: меш собран" % type)
			var arrays: Array = mesh.surface_get_arrays(0)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			assert_eq(colors.size(), verts.size(), "%s: цвет каждой вершине" % type)
			assert_between(
				mesh.get_aabb().position.y, -0.05, 0.05,
				"%s: origin у земли" % type,
			)
			var size: Vector3 = mesh.get_aabb().size
			# Высота может быть заметно ниже эталона: нормировка берёт меньший
			# из коэффициентов (высота/ширина), а kenney-камни и трава — плоские.
			assert_between(
				size.y, float(cfg[2]) * 0.3, float(cfg[2]) * 1.05,
				"%s: высота около эталона %.2f (факт %.2f)"
				% [type, float(cfg[2]), size.y],
			)
			assert_between(
				maxf(size.x, size.z), float(cfg[3]) * 0.5, float(cfg[3]) * 1.05,
				"%s: ширина около эталона %.2f (факт %.2f)"
				% [type, float(cfg[3]), maxf(size.x, size.z)],
			)
