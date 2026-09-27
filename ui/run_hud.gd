# HUD забега (раздел 13 SPEC): монеты за забег, номер секции «X / N»,
# таймер до конца (виден последние 2 минуты), отсчёт старта, панель «Висит»
# с кнопкой «Сдаться» и оверлей финиша (в сети — «ждём остальных» и
# «хост покинул игру»). Строится кодом из примитивов; общая тема — этап 7.
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
var _end_title: Label
var _end_coins: Label
var _end_again: Button
var _end_menu: Button
var _play_again_allowed: bool = true


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


## Сетевой старт: ждём, пока хост соберёт готовность и назначит GO.
func show_countdown_waiting() -> void:
	_countdown_label.text = tr("RUN_WAITING")


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
	_end_title.text = tr("RUN_FINISHED") if finished else tr("RUN_TIMEOUT")
	_end_coins.text = tr("RUN_RESULT_COINS") % coins
	_end_again.visible = _play_again_allowed
	_end_menu.visible = true
	_end_overlay.visible = true


## Сетевой забег: свой финиш есть, забег ещё идёт — ждём остальных (раздел 7.6).
func show_wait_finish(coins: int) -> void:
	_hang_panel.visible = false
	_end_title.text = tr("RUN_FINISHED_EARLY")
	_end_coins.text = tr("RUN_RESULT_COINS") % coins
	_end_again.visible = false
	_end_menu.visible = false
	_end_overlay.visible = true


## Раздел 8: хост отключился — только выход в меню.
func show_host_lost() -> void:
	_hang_panel.visible = false
	_end_title.text = tr("RUN_HOST_LEFT")
	_end_coins.text = ""
	_end_again.visible = false
	_end_menu.visible = true
	_end_overlay.visible = true


## «Ещё раз» доступен только хосту и в одиночной игре (раздел 9 — этап 6).
func set_play_again_allowed(allowed: bool) -> void:
	_play_again_allowed = allowed


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
	_end_title = Label.new()
	_end_title.position = Vector2(0, 220)
	_end_title.size = Vector2(1280, 70)
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_title.add_theme_font_size_override("font_size", 56)
	overlay.add_child(_end_title)
	_end_coins = Label.new()
	_end_coins.position = Vector2(0, 300)
	_end_coins.size = Vector2(1280, 40)
	_end_coins.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_coins.add_theme_font_size_override("font_size", 30)
	overlay.add_child(_end_coins)
	_end_again = Button.new()
	_end_again.text = tr("RUN_AGAIN")
	_end_again.position = Vector2(640 - 230, 380)
	_end_again.custom_minimum_size = Vector2(220, 48)
	_end_again.pressed.connect(func() -> void: play_again_pressed.emit())
	overlay.add_child(_end_again)
	_end_menu = Button.new()
	_end_menu.text = tr("RUN_TO_MENU")
	_end_menu.position = Vector2(640 + 10, 380)
	_end_menu.custom_minimum_size = Vector2(220, 48)
	_end_menu.pressed.connect(func() -> void: to_menu_pressed.emit())
	overlay.add_child(_end_menu)
	return overlay
