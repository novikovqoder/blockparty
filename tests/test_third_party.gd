# Тесты сторонних CC0-ресурсов (шаг 3 П4.5, правила — CLAUDE.md):
# каждый файл assets/third_party упомянут в LICENSES.md (и наоборот — записи
# указывают на существующие файлы), форматы допустимые, общий размер в лимите.
# Ресурсы с неизвестной лицензией в проект не попадают. П5.13, блок 1:
# таблицы CC0-моделей окружения больше нет (Cc0Meshes удалён — всё
# процедурное, из kenney осталось только бревно валежника, его читает
# PropMeshes._dead_log напрямую).
extends GutTest

const ROOT: String = "res://assets/third_party"
const LICENSES: String = "res://assets/third_party/LICENSES.md"
## Префиксы каталогов наборов в колонке «Файлы» LICENSES.md (наборы
## kenney и Quaternius-персонажи вычищены с наследием Blockparty,
## born-unblessed; остались ambientcg и polyhaven).
const VENDOR_PREFIXES: PackedStringArray = ["ambientcg.com/", "polyhaven.com/"]
## Допустимые форматы (CLAUDE.md, «Скачивание ресурсов»); .res и .bin —
## производные: .res — децимированные Godot-ArrayMesh со сканами Poly Haven
## (tools/decimate_polyhaven.gd, исходники glb в проекте не хранятся),
## .bin — буфер геометрии glTF-модели fern_02.
const FORMATS: PackedStringArray = [
	".glb", ".gltf", ".obj", ".png", ".jpg", ".webp", ".hdr", ".exr",
	".ogg", ".wav", ".ttf", ".otf", ".res", ".bin",
]
## Лимит общего размера ресурсов (CLAUDE.md).
const SIZE_LIMIT_MB: float = 300.0


func _files_under(path: String) -> PackedStringArray:
	var found := PackedStringArray()
	for file: String in DirAccess.get_files_at(path):
		if file == ".gdignore" or file == "LICENSES.md":
			continue
		# .import/.uid — служебные файлы Godot рядом с ресурсом (импортируемые
		# движком наборы, в отличие от закрытых .gdignore наборов Kenney):
		# генерируются автоматически, не скачиваются.
		if file.ends_with(".import") or file.ends_with(".uid"):
			continue
		found.append(path.path_join(file))
	for dir: String in DirAccess.get_directories_at(path):
		found.append_array(_files_under(path.path_join(dir)))
	return found


func test_every_third_party_file_is_licensed() -> void:
	var text: String = FileAccess.get_file_as_string(LICENSES)
	assert_false(text.is_empty(), "LICENSES.md существует и не пуст")
	# Маска каталога (токен в бэктиках с косой чертой на конце) покрывает
	# всё его содержимое: запечённые наборы вроде UBC дают сотню
	# производных .res-файлов, перечислять их поэлементно бессмысленно;
	# сама маска проверяется на непустоту тестом stale-entries ниже.
	var masks := _dir_masks(text)
	for path: String in _files_under(ROOT):
		var rel := path.trim_prefix(ROOT + "/")
		var covered := text.contains(path.get_file())
		for mask: String in masks:
			if rel.begins_with(mask):
				covered = true
		assert_true(
			covered,
			"%s упомянут в LICENSES.md" % path.get_file(),
		)


## Токены-маски каталогов из колонки «Файлы» (токен заканчивается «/»).
func _dir_masks(text: String) -> PackedStringArray:
	var masks := PackedStringArray()
	for line: String in text.split("\n"):
		if not line.begins_with("|") or "CC0" not in line:
			continue
		for token: String in line.split("`"):
			if token.ends_with("/"):
				masks.append(token)
	return masks


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


## Эталон дословной атрибуции сруба Kless (CC-BY 4.0): лицензия требует
## воспроизводить строку неизменной. Сверяем константу титров и запись
## LICENSES.md — правка «по смыслу» ломает соответствие лицензии.
const KLESS_ATTRIBUTION_EXACT: String = "\"Log Cabin (Free Download)\" " \
	+ "(https://skfb.ly/6ZQuZ) by Kless is licensed under " \
	+ "Creative Commons Attribution " \
	+ "(http://creativecommons.org/licenses/by/4.0/)."


func test_kless_attribution_verbatim() -> void:
	assert_eq(CabinCredits.KLESS_ATTRIBUTION, KLESS_ATTRIBUTION_EXACT,
		"титры: атрибуция Kless дословная")
	var text: String = FileAccess.get_file_as_string(LICENSES)
	assert_true(text.contains(KLESS_ATTRIBUTION_EXACT),
		"LICENSES.md: та же дословная строка атрибуции")


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
