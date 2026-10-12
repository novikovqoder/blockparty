# Одноразовая диагностика (П5.8): имена клипов UAL1/UAL2 и формат путей
# треков — для прямой (без ретаргетинга) запечки на риг UBC.
# Запуск: godot --headless -s tools/probe_ual_names.gd -- <файл.glb>
extends SceneTree


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("нет файлов")
		quit(1)
		return
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(args[0], state) != OK:
		print("не читается")
		quit(1)
		return
	var names: PackedStringArray = []
	for anim in state.get_animations():
		names.append(String(anim.resource_name))
	names.sort()
	print("клипов: %d" % names.size())
	print("\n".join(names))
	var root := doc.generate_scene(state)
	for node in root.get_children():
		print("узел корня: %s (%s)" % [node.name, node.get_class()])
	var player := root.find_children("*", "AnimationPlayer", true, false)
	if not player.is_empty():
		var ap := player[0] as AnimationPlayer
		var lib_list := ap.get_animation_library_list()
		for lib_name in lib_list:
			var lib := ap.get_animation_library(StringName(lib_name))
			for clip_name in lib.get_animation_list():
				var anim := lib.get_animation(StringName(clip_name))
				for ti in mini(3, anim.get_track_count()):
					print("трек %s: %s" % [clip_name, anim.track_get_path(ti)])
				break
			break
	root.free()
	quit(0)
