# Boot-экран: ждёт результата инициализации Steam и решает, куда идти —
# в главное меню или в окно офлайн-режима (раздел 13 SPEC, экран Boot).
extends Control

const MAIN_MENU_SCENE: String = "res://scenes/main_menu.tscn"


func _ready() -> void:
	LocLabels.apply(self)
	Log.info("Boot: экран загрузки")
	if SteamService.available:
		_go_to_menu()
	else:
		# SteamService уже выяснил причину и залогировал её.
		%OfflineBox.show()


func _go_to_menu() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _on_play_offline_pressed() -> void:
	Log.info("Boot: выбран офлайн-режим (разработка, ENet)")
	_go_to_menu()


func _on_quit_pressed() -> void:
	get_tree().quit()
