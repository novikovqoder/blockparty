# Управление и камера (born-unblessed, вычистка наследия Blockparty):
# зум камеры — только клавишами «+»/«−» (основной ряд и нумпад), удержание
# двигает руку плавно, пределы прежние — balance 3–10 м; колесо мыши камеру
# НЕ двигает (оно листает слоты снаряжения героя — EquipControllerBU).
# Мёртвые действия Input Map (push_to_talk, player_list) удалены, а клавиши
# 1–6, Q, F, M не привязаны ни к одному действию: строки будущего боя в
# настройках BU — механик за ними пока нет, нажатия не должны ничего звать.
extends GutTest

const B: Balance = preload("res://gameplay/balance.tres")

## Коды клавиш (Key): «=»/«+» и «−» основного ряда, нумпад, мёртвые буквы.
const KEY_EQUAL: int = 61
const KEY_MINUS: int = 45
const KEY_KP_ADD: int = 4194437
const KEY_KP_SUBTRACT: int = 4194435
const KEY_PLUS: int = 43
const DEAD_KEYS: PackedInt32Array = [
	49, 50, 51, 52, 53, 54,  # 1–6
	81,  # Q — «блок» из настроек BU
	70,  # F — «добивание»
	77,  # M — карта удалена с наследием (0ce7860)
]


## Риг камеры без сцены игрока: иерархия по путям player_camera.gd
## (Pivot → SpringArm → Camera3D), родитель — Node3D для следования.
func _make_camera() -> PlayerCamera:
	var root := Node3D.new()
	add_child_autofree(root)
	var rig := PlayerCamera.new()
	rig.name = "CameraRig"
	var pivot := Node3D.new()
	pivot.name = "Pivot"
	rig.add_child(pivot)
	var arm := SpringArm3D.new()
	arm.name = "SpringArm"
	pivot.add_child(arm)
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	arm.add_child(camera)
	root.add_child(rig)
	return rig


func test_zoom_in_out_keys_move_camera_smoothly() -> void:
	var rig := _make_camera()
	await get_tree().physics_frame
	assert_almost_eq(rig.arm.spring_length, B.camera_length, 0.01,
		"старт руки — camera_length из баланса")
	# «+» (удержание) — приблизить: 0,5 с при ZOOM_SPEED 4 м/с ≈ −2 м,
	# рука сглаживается move_toward и успевает догнать цель.
	Input.action_press("camera_zoom_in")
	for i: int in 30:
		await get_tree().physics_frame
	Input.action_release("camera_zoom_in")
	assert_between(rig.arm.spring_length, B.camera_length_min,
		B.camera_length - 1.0,
		"«+» приблизил камеру (факт %.2f м)" % rig.arm.spring_length)
	# «−» (удержание) — дальше предела не уехать: предел balance.
	Input.action_press("camera_zoom_out")
	for i: int in 240:
		await get_tree().physics_frame
	Input.action_release("camera_zoom_out")
	assert_almost_eq(rig.arm.spring_length, B.camera_length_max, 0.05,
		"«−» увёл камеру до предела и остановился (факт %.2f м)"
			% rig.arm.spring_length)


func test_numpad_plus_minus_bound() -> void:
	# Основной ряд и нумпад — оба «+» и оба «−» обязаны быть в Input Map
	# (задание born-unblessed): физические коды клавиш в событиях действий.
	var zoom_in_keys: PackedInt32Array = PackedInt32Array()
	for event: InputEvent in InputMap.action_get_events("camera_zoom_in"):
		if event is InputEventKey:
			zoom_in_keys.append((event as InputEventKey).physical_keycode)
	var zoom_out_keys: PackedInt32Array = PackedInt32Array()
	for event: InputEvent in InputMap.action_get_events("camera_zoom_out"):
		if event is InputEventKey:
			zoom_out_keys.append((event as InputEventKey).physical_keycode)
	assert_has(zoom_in_keys, KEY_EQUAL, "«+» основного ряда привязан")
	assert_has(zoom_in_keys, KEY_KP_ADD, "«+» нумпада привязан")
	assert_has(zoom_out_keys, KEY_MINUS, "«−» основного ряда привязан")
	assert_has(zoom_out_keys, KEY_KP_SUBTRACT, "«−» нумпада привязан")


func test_mouse_wheel_does_not_move_camera() -> void:
	var rig := _make_camera()
	await get_tree().physics_frame
	var before: float = rig.arm.spring_length
	# Колесо в _unhandled_input камеры не обрабатывается вовсе: курсор
	# захватываем, событие прокрутки отдаём камере напрямую — рука не двинется.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	for button: int in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var event := InputEventMouseButton.new()
		event.button_index = button as MouseButton
		event.pressed = true
		rig._unhandled_input(event)
		for i: int in 12:
			await get_tree().physics_frame
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	assert_almost_eq(rig.arm.spring_length, before, 0.001,
		"колесо мыши дистанцию камеры не меняет (факт %.3f)"
			% rig.arm.spring_length)


func test_dead_keys_bound_to_nothing() -> void:
	# 1–6, Q, F, M не привязаны ни к одному действию Input Map (механик за
	# ними нет — нажатия не должны вызывать ничего), мёртвые действия
	# push_to_talk/player_list удалены вместе с наследием Blockparty.
	assert_false(InputMap.has_action("push_to_talk"),
		"push_to_talk удалён из Input Map")
	assert_false(InputMap.has_action("player_list"),
		"player_list удалён из Input Map")
	var offenders: PackedStringArray = PackedStringArray()
	for action: StringName in InputMap.get_actions():
		if String(action).begins_with("ui_"):
			continue  # встроенные действия Godot не трогаем
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventKey:
				var key: int = (event as InputEventKey).physical_keycode
				if key in DEAD_KEYS:
					offenders.append("%s→%d" % [action, key])
	assert_eq(offenders.size(), 0,
		"клавиши 1–6/Q/F/M не привязаны к действиям: %s"
			% ", ".join(offenders))
