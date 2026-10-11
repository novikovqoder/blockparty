# Проверка постобработки (vfx-fix, визуальный блок е): виньетка поверх
# яркого ровного поля — затемнение углов видно без острова и быстро.
# Glow и SSAO в Compatibility-рендерере недоступны (проверяет владелец
# в Forward+); виньетка — canvas_item шейдер, работает и здесь.
# Запуск (сервер без экрана):
#   xvfb-run -a godot --path . --resolution 1280x720 \
#     --rendering-driver opengl3 res://tools/shot_post.tscn -- <dir>
extends Node


func _ready() -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "builds/screenshots"

	# Ровное светлое поле — контраст углов после наложения читается сразу.
	var field := ColorRect.new()
	field.color = Color(0.75, 0.8, 0.72)
	field.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(field)

	add_child(GraphicsQuality.make_vignette())

	await get_tree().create_timer(0.5).timeout
	get_viewport().get_texture().get_image().save_png(
		out_dir.path_join("post_vignette.png"))
	print("виньетка снята")
	get_tree().quit()
