# Тесты якорного позиционирования UI (vfx-fix, баг 5): окна и центральные
# элементы HUD обязаны держаться якорями — при stretch keep_height логическая
# ширина меняется с аспектом окна, и позиции, захардкоженные под 1280 × 720
# (тем более вместе с якорем 0.5), уводят панель в угол. Проверяем чистый
# расчёт на родителе-контейнере разных размеров (1280×720, 1920×1080,
# 1600×900, 1280×1024) и факт «панель в центре вьюпорта» у реальных окон
# (EscMenu, QuestDialog) и правый край трекера.
extends GutTest


## Панель 300 × 220 в контейнере: центр совпадает с центром контейнера
## при любом его размере.
func test_center_panel_follows_parent_size() -> void:
	var parent := Control.new()
	parent.size = Vector2(1280, 720)
	add_child_autofree(parent)
	var panel := PanelContainer.new()
	UiLayout.center(panel, Vector2(300, 220))
	parent.add_child(panel)
	assert_eq(panel.size, Vector2(300, 220), "размер панели задан")
	assert_almost_eq(
		panel.position.x + panel.size.x * 0.5, 640.0, 0.01, "центр по x (1280)")
	assert_almost_eq(
		panel.position.y + panel.size.y * 0.5, 360.0, 0.01, "центр по y (720)")
	for parent_size: Vector2 in [Vector2(1920, 1080), Vector2(1600, 900), Vector2(1280, 1024)]:
		parent.size = parent_size
		await get_tree().process_frame
		assert_almost_eq(
			panel.position.x + panel.size.x * 0.5, parent_size.x * 0.5, 0.01,
			"центр по x (%d)" % int(parent_size.x))
		assert_almost_eq(
			panel.position.y + panel.size.y * 0.5, parent_size.y * 0.5, 0.01,
			"центр по y (%d)" % int(parent_size.y))


## Приблизительно центральный нижний/верхний/правый края считаются
## от фактического размера родителя, а не от 1280 × 720.
func test_edge_layouts_follow_parent_size() -> void:
	var parent := Control.new()
	parent.size = Vector2(1280, 720)
	add_child_autofree(parent)
	var bottom := Label.new()
	UiLayout.center_bottom(bottom, Vector2(400, 60), 100.0)
	parent.add_child(bottom)
	var top := Label.new()
	UiLayout.center_top(top, Vector2(200, 30), 12.0)
	parent.add_child(top)
	var right := Label.new()
	UiLayout.top_right(right, Vector2(230, 26), 16.0, 16.0)
	parent.add_child(right)
	var offset := Label.new()
	UiLayout.center_offset(offset, Vector2(120, 48), Vector2(0.0, -170.0))
	parent.add_child(offset)
	for parent_size: Vector2 in [Vector2(1280, 720), Vector2(1600, 900)]:
		parent.size = parent_size
		await get_tree().process_frame
		assert_almost_eq(
			bottom.position.y + bottom.size.y + 100.0, parent_size.y, 0.01,
			"низ панели у нижнего края (высота %d)" % int(parent_size.y))
		assert_almost_eq(
			bottom.position.x + bottom.size.x * 0.5, parent_size.x * 0.5, 0.01,
			"панель по центру (ширина %d)" % int(parent_size.x))
		assert_almost_eq(top.position.y, 12.0, 0.01, "верхняя метка у верхнего края")
		assert_almost_eq(
			top.position.x + top.size.x * 0.5, parent_size.x * 0.5, 0.01,
			"верхняя метка по центру")
		assert_almost_eq(
			right.position.x + right.size.x + 16.0, parent_size.x, 0.01,
			"правая метка у правого края (ширина %d)" % int(parent_size.x))
		assert_almost_eq(
			offset.position.y + offset.size.y * 0.5, parent_size.y * 0.5 - 170.0,
			0.01, "метка со смещением от центра")


## Реальные окна: панель меню Esc и панель диалога заданий — в центре
## видимой области (раньше якорь 0.5 плюс абсолютные офсеты уводили панель
## в правый нижний угол).
func test_esc_menu_and_quest_dialog_panels_centered() -> void:
	var viewport_center := get_viewport().get_visible_rect().size * 0.5
	var menu := EscMenu.new()
	add_child_autofree(menu)
	var menu_panel := _first_panel(menu)
	assert_not_null(menu_panel, "панель меню построена")
	assert_almost_eq(
		menu_panel.global_position.x + menu_panel.size.x * 0.5,
		viewport_center.x, 0.5, "меню Esc в центре по x")
	assert_almost_eq(
		menu_panel.global_position.y + menu_panel.size.y * 0.5,
		viewport_center.y, 0.5, "меню Esc в центре по y")

	var dialog := QuestDialog.new()
	add_child_autofree(dialog)
	var dialog_panel := _first_panel(dialog)
	assert_not_null(dialog_panel, "панель диалога построена")
	assert_almost_eq(
		dialog_panel.global_position.x + dialog_panel.size.x * 0.5,
		viewport_center.x, 0.5, "диалог заданий в центре по x")
	assert_almost_eq(
		dialog_panel.global_position.y + dialog_panel.size.y * 0.5,
		viewport_center.y, 0.5, "диалог заданий в центре по y")


## Строки трекера заданий прижаты к правому краю видимой области.
func test_quest_tracker_lines_at_right_edge() -> void:
	var width := get_viewport().get_visible_rect().size.x
	var tracker := QuestTracker.new()
	add_child_autofree(tracker)
	EventBus.quest_state.emit({
		Protocol.QUEST_THYME: {
			"stage": QuestAuthority.ACTIVE, "steps": [1, 0, 0, 0, 0],
		},
	})
	var labels: Array = tracker.find_children("*", "Label", true, false)
	assert_gt(labels.size(), 0, "строки трекера построены")
	for label: Label in labels:
		if not label.visible:
			continue
		assert_almost_eq(
			label.global_position.x + label.size.x + QuestTracker.MARGIN,
			width, 0.5, "строка у правого края")


func _first_panel(layer: CanvasLayer) -> PanelContainer:
	var panels: Array = layer.find_children("*", "PanelContainer", true, false)
	return panels[0] as PanelContainer if not panels.is_empty() else null
