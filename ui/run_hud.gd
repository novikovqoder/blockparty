# HUD забега (раздел 13 SPEC): монеты за забег, номер секции «X / N»,
# таймер до конца (виден последние 2 минуты), отсчёт старта, панель «Висит»
# с кнопкой «Сдаться» и оверлей финиша. Строится кодом из примитивов;
# общая тема ui/theme.tres — позже (этап 7).
# Не делает: иконку микрофона и подсказки у объектов (этапы 5–7).
class_name RunHud
extends CanvasLayer

const PAL: Palette = preload("res://assets/palette.tres")

## Панель «Висит» просит сдаться — сцену забега соединяет с player.give_up_hang().
signal give_up_pressed
signal play_again_pressed
signal to_menu_pressed

var _coins_label: Label
var _section_label: Label
var _timer_label: Label
var _countdown_label: Label
var _hang_panel: Control
var _hang_time_label: Label
var _end_overlay: Control


func _ready() -> void:
	layer = 10
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_coins_label = _label(root, Vector2(16, 12), 28)
	_section_label = _label(root, Vector2(16, 44), 20)
	_timer_label = _label(root, Vector2(1120, 12), 28)
	_timer_label.visible = false
	_countdown_label = _label(root, Vector2(0, 260), 96)
	_countdown_label.size = Vector2(1280, 110)
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.visible = false
	_hang_panel = _build_hang_panel(root)
	_end_overlay = _build_end_overlay(root)

	EventBus.run_coins_changed.connect(func(total: int) -> void: _coins_label.text = "%s: %d" % [tr("HUD_COINS"), total])
	EventBus.hang_started.connect(_on_hang_started)
	EventBus.hang_ended.connect(func() -> void: _hang_panel.visible = false)
	EventBus.run_countdown_started.connect(func() -> void: _countdown_label.visible = true)
	EventBus.run_go.connect(_on_run_go)
	_coins_label.text = "%s: 0" % tr("HUD_COINS")
	_section_label.text = ""


## Общее число секций для показа «X / N».
func setup(total_sections: int) -> void:
	_section_label.text = "1 / %d" % total_sections


func set_section(current: int, total: int) -> void:
	_section_label.text = "%d / %d" % [current, total]


func show_countdown(seconds_left: float) -> void:
	if seconds_left > 0.5:
		_countdown_label.text = str(int(ceil(seconds_left - 0.5)))
	else:
		_countdown_label.text = tr("RUN_GO")


## Таймер виден только за последние timer_visible_last секунд (раздел 13).
func set_time_left(seconds_left: float, visible_after: float) -> void:
	var show: bool = seconds_left <= visible_after
	_timer_label.visible = show
	if show:
		var s := int(ceil(seconds_left))
		_timer_label.text = "%d:%02d" % [int(s) / 60, s % 60]
		_timer_label.add_theme_color_override("font_color", Color.RED if s <= 30 else Color.WHITE)


## Оставшееся время висения для панели.
func set_hang_time(seconds_left: float) -> void:
	_hang_time_label.text = "%.1f" % maxf(0.0, seconds_left)


## Оверлей конца забега: дошёл (finished) или время вышло.
func show_end(finished: bool, coins: int) -> void:
	_hang_panel.visible = false
	_end_overlay.get_node("Title").text = tr("RUN_FINISHED") if finished else tr("RUN_TIMEOUT")
	(_end_overlay.get_node("Coins") as Label).text = tr("RUN_RESULT_COINS") % coins
	_end_overlay.visible = true


func _on_hang_started() -> void:
	_hang_panel.visible = true


func _on_run_go() -> void:
	_countdown_label.text = tr("RUN_GO")
	var tween := create_tween()
	tween.tween_interval(0.6)
	tween.tween_callback(func() -> void: _countdown_label.visible = false)


func _label(parent: Control, pos: Vector2, size: int) -> Label:
	var label := Label.new()
	label.position = pos
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", PAL.hud_text)
	label.add_theme_color_override("font_outline_color", Color.WHITE)
	label.add_theme_constant_override("outline_size", 4)
	parent.add_child(label)
	return label


func _build_hang_panel(root: Control) -> Control:
	var panel := PanelContainer.new()
	panel.position = Vector2(640 - 180, 720 - 130)
	panel.custom_minimum_size = Vector2(360, 96)
	panel.visible = false
	root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var title := Label.new()
	title.text = tr("RUN_HANGING")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	box.add_child(title)
	_hang_time_label = Label.new()
	_hang_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hang_time_label.add_theme_font_size_override("font_size", 26)
	box.add_child(_hang_time_label)
	var button := Button.new()
	button.text = tr("RUN_GIVE_UP")
	button.pressed.connect(func() -> void: give_up_pressed.emit())
	box.add_child(button)
	return panel


func _build_end_overlay(root: Control) -> Control:
	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.visible = false
	root.add_child(overlay)
	var title := Label.new()
	title.name = "Title"
	title.position = Vector2(0, 220)
	title.size = Vector2(1280, 70)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	overlay.add_child(title)
	var coins := Label.new()
	coins.name = "Coins"
	coins.position = Vector2(0, 300)
	coins.size = Vector2(1280, 40)
	coins.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coins.add_theme_font_size_override("font_size", 30)
	overlay.add_child(coins)
	var again := Button.new()
	again.text = tr("RUN_AGAIN")
	again.position = Vector2(640 - 230, 380)
	again.custom_minimum_size = Vector2(220, 48)
	again.pressed.connect(func() -> void: play_again_pressed.emit())
	overlay.add_child(again)
	var menu := Button.new()
	menu.text = tr("RUN_TO_MENU")
	menu.position = Vector2(640 + 10, 380)
	menu.custom_minimum_size = Vector2(220, 48)
	menu.pressed.connect(func() -> void: to_menu_pressed.emit())
	overlay.add_child(menu)
	return overlay
