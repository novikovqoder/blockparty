# Пробник born-unblessed: строит модель персонажа без GUT — найти зависание
# в character_model.tscn / setup_appearance. Запуск:
#   godot --headless -s tools/probe_char_model.gd
extends SceneTree


func _init() -> void:
	print("PROBE start")
	var packed: PackedScene = load("res://gameplay/player/character_model.tscn")
	print("PROBE loaded scene")
	for gender: int in Appearance.GENDERS:
		var model: CharacterModel = packed.instantiate() as CharacterModel
		root.add_child(model)
		print("PROBE add_child gender=", gender)
		model.setup_appearance(Appearance.default_for(gender))
		print("PROBE setup_appearance gender=", gender, " bones=",
			model.find_children("*", "Skeleton3D", true, false).size())
	print("PROBE OK")
	quit(0)
