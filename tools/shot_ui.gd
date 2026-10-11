# Одноразовая проверка центрирования UI-окон (vfx-fix, баг 5): снимает
# меню Esc, диалог заданий, карту острова и колесо эмоций поверх тёмного
# фона — панель обязана быть в центре кадра на любом разрешении.
# UI-скрипты используют автолоады, поэтому запуск сценой, а не -s:
#   xvfb-run -a godot --path . --resolution 1280x720 \
#     --rendering-driver opengl3 res://tools/shot_ui.tscn -- --tag=720
#   xvfb-run -a godot --path . --resolution 1920x1080 \
#     --rendering-driver opengl3 res://tools/shot_ui.tscn -- --tag=1080
extends Node

const TAG_PREFIX: String = "--tag="


func _ready() -> void:
	# Root ещё настраивает детей этой сцены — один кадр, и add_child пройдёт.
	await get_tree().process_frame
	var tag := "720"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(TAG_PREFIX):
			tag = arg.substr(TAG_PREFIX.length())
	var out_dir := "builds/screenshots"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.12, 0.10)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	get_tree().root.add_child(bg)

	# Меню Esc: _ready строит панель скрытой, toggle() показывает.
	var menu := EscMenu.new()
	get_tree().root.add_child(menu)
	menu.toggle()
	await _snap(out_dir.path_join("ui_esc_%s.png" % tag), menu)
	menu.queue_free()

	# Диалог заданий: панель строится в _ready, показываем корень.
	var dialog := QuestDialog.new()
	get_tree().root.add_child(dialog)
	await get_tree().create_timer(0.2).timeout
	dialog._root.visible = true
	await _snap(out_dir.path_join("ui_quest_%s.png" % tag), dialog)
	dialog.queue_free()

	# Карта острова: показывается действием map в _process, включаем напрямую.
	var map := IslandMap.new()
	get_tree().root.add_child(map)
	map._shown = true
	map._frame.visible = true
	await _snap(out_dir.path_join("ui_map_%s.png" % tag), map)
	map.queue_free()

	# Колесо эмоций: метки по окружности вокруг центра.
	var wheel := EmoteWheel.new()
	get_tree().root.add_child(wheel)
	await get_tree().create_timer(0.2).timeout
	wheel._show(true)
	await _snap(out_dir.path_join("ui_wheel_%s.png" % tag), wheel)
	wheel.queue_free()
	get_tree().quit()


func _snap(path: String, layer: CanvasLayer) -> void:
	await get_tree().create_timer(0.3).timeout
	get_viewport().get_texture().get_image().save_png(path)
	print("стенд UI: ", path, " (", layer.name, ")")
