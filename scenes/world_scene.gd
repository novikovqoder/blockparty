# Сцена мира (раздел 6 SPEC): остров (генерация — этап П2), игроки, мобы и UI.
# Этап П0 — базовая тестовая площадка 64 × 64 м из примитивов: пол, блоки,
# ступени, солнце с тенями, процедурное небо и туман. Персонаж, камера игрока
# и полная площадка раздела 6 (уступ, яма, плита, вода) — этап П1; снапшоты
# и вход в идущий мир по сети — этап П3.
extends Node3D

const MENU_SCENE: String = "res://scenes/main_menu.tscn"

var _debug: DebugPanel
var _leaving: bool = false


func _ready() -> void:
	$Sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	$Camera3D.look_at(Vector3(0.0, 1.0, 0.0))
	_debug = DebugPanel.new()
	add_child(_debug)
	Session.enter_world()
	EventBus.host_lost.connect(_on_host_lost)


func _unhandled_input(event: InputEvent) -> void:
	# Esc — выход из мира; полное меню паузы (раздел 15) — этап П8.
	if event.is_action_pressed("pause"):
		_exit_to_menu()


func _exit_to_menu() -> void:
	if _leaving:
		return
	_leaving = true
	Session.leave_world()
	get_tree().call_deferred("change_scene_to_file", MENU_SCENE)


func _on_host_lost(_reason: String) -> void:
	# Хост вышел: мир закрылся у всех; экран «Встречи» на его месте — П7.
	_exit_to_menu()
