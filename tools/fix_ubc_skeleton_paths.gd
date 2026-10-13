# Одноразовый фикс запечённых сцен UBC (возврат П5.8): сцены собраны
# make_ubc_characters/make_hats ДО исправления — у мешей пустой skeleton-
# путь, скиннинг не включается, персонажи в T-pose при живом скелете.
# Скрипт загружает ubc_male.res/ubc_female.res, ставит всем MeshInstance3D
# со скином путь «..» (меш — ребёнок Skeleton3D) и пересохраняет сцены.
# Запекатели уже исправлены — при следующей перезапечке путь ставится сам,
# этот скрипт нужен только для уже запечённых файлов.
#   godot --headless --path . -s res://tools/fix_ubc_skeleton_paths.gd
extends SceneTree

const BAKED: String = "res://assets/third_party/quaternius.com/" \
	+ "universal_base_characters/baked"
const SCENES: PackedStringArray = ["ubc_male.res", "ubc_female.res"]


func _init() -> void:
	await create_timer(0.01).timeout
	for file: String in SCENES:
		var path := "%s/%s" % [BAKED, file]
		var scene := load(path) as PackedScene
		assert(scene != null, "нет сцены %s" % path)
		var root := scene.instantiate()
		var skeleton := root.find_children("*", "Skeleton3D", true,
			false)[0] as Skeleton3D
		assert(skeleton != null, "%s: нет скелета" % file)
		var fixed := 0
		for node in skeleton.find_children("*", "MeshInstance3D", true,
				false):
			var mi := node as MeshInstance3D
			if mi.skin == null:
				continue
			mi.skeleton = ^".."
			fixed += 1
		var packed := PackedScene.new()
		assert(packed.pack(root) == OK, "не запаковалась %s" % path)
		root.free()
		assert(ResourceSaver.save(packed, path) == OK,
			"не сохранилась %s" % path)
		print("%s: skeleton-путь «..» выставлен %d мешам" % [file, fixed])
	quit(0)
