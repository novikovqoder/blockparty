# Главное меню (раздел 13 SPEC): «Играть» ведёт в одиночный забег этапа 1;
# быстрый подбор и лобби появятся на этапах 4. Остальные кнопки — заглушки.
extends Control

const RUN_SCENE: String = "res://scenes/run.tscn"


func _ready() -> void:
	LocLabels.apply(self)


func _on_play_pressed() -> void:
	Log.info("MainMenu: «Играть» — одиночный забег (этап 1)")
	get_tree().change_scene_to_file(RUN_SCENE)


func _on_quit_pressed() -> void:
	get_tree().quit()
