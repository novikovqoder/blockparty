# Контакт-лист серии кадров (финал П5.8): читает сырые frame_*.rgb
# (RGBA8, размер окна Godot) из каталога и складывает выбранные кадры
# в один PNG-лист — глазами проверить, что персонаж в серии движется
# (фазы поз меняются), камера едет, фон на месте. Диагностика материалов,
# в игру не входит. Запуск:
#   godot --headless -s tools/series_sheet.gd --path . -- <каталог> <WxH> <выход.png> [сколько]
extends SceneTree

const FRAMES_DEFAULT: int = 8


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		print("использование: series_sheet.gd -- <каталог> <WxH> <выход.png> [кадров]")
		quit(1)
		return
	var dir := args[0]
	var parts := args[1].to_lower().split("x")
	var size := Vector2i(int(parts[0]), int(parts[1]))
	var count: int = FRAMES_DEFAULT if args.size() < 4 else int(args[3])

	var files: PackedStringArray = []
	for name: String in DirAccess.get_files_at(dir):
		if name.begins_with("frame_") and name.ends_with(".rgb"):
			files.append(name)
	files.sort()
	if files.is_empty():
		print("нет frame_*.rgb в " + dir)
		quit(1)
		return
	# Равномерно по серии: первый и последний кадр всегда включены.
	var picked: Array[int] = []
	for i: int in count:
		var idx := roundi(float(i) * float(files.size() - 1) / float(count - 1))
		if not picked.has(idx):
			picked.append(idx)
	var sheet := Image.create(size.x * picked.size(), size.y,
		false, Image.FORMAT_RGBA8)
	for slot: int in picked.size():
		var raw := FileAccess.get_file_as_bytes(dir.path_join(files[slot]))
		var frame := Image.create_from_data(size.x, size.y,
			false, Image.FORMAT_RGBA8, raw)
		sheet.blit_rect(frame, Rect2i(Vector2i.ZERO, size),
			Vector2i(size.x * slot, 0))
	var err := sheet.save_png(args[2])
	if err == OK:
		print("лист %s (%d кадров из %d) → %s"
			% [dir, picked.size(), files.size(), args[2]])
	else:
		push_error("не записался PNG: %s" % args[2])
	quit(0 if err == OK else 1)
