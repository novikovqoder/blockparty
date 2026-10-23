extends SceneTree
## Диагностика П9-фикса: нажатие «Выход» в меню Born Unblessed.
## Запуск: godot --headless --path . -s res://tools/probe_quit_menu.gd -- [режимы]
##   (без флагов) — кит меню standalone, нажатие через btn.pressed.emit();
##   --embedded  — обвязка игры (scenes/main_menu_game.tscn);
##   --boot      — полный путь владельца: boot-экран → меню (кнопка офлайн);
##   --click     — реальный клик мышью (Input.parse_input_event) вместо emit;
##   --paused    — дерево на паузе в момент нажатия (кейс «вышел из мира»).
## Скрипт жмёт кнопку «Выход» тем же путём, что игрок, и следит: дошёл ли
## сигнал quit_requested, завершился ли процесс (quit). Если через 3 с после
## нажатия процесс жив — печать FAIL и код возврата 3.

const KIT_SCENE: String = "res://scenes/menu_bu/main_menu_bu.tscn"
const GAME_SCENE: String = "res://scenes/main_menu_game.tscn"
const BOOT_SCENE: String = "res://scenes/boot.tscn"

var _embedded: bool = false
var _boot: bool = false
var _click: bool = false
var _paused: bool = false
var _frame: int = 0
var _menu: MainMenuBU
var _pressed_at: int = -1
var _got_signal: bool = false
var _verbose_telemetry: bool = true


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		match a:
			"--embedded":
				_embedded = true
			"--boot":
				_boot = true
			"--click":
				_click = true
			"--paused":
				_paused = true
	var path: String = BOOT_SCENE if _boot else (GAME_SCENE if _embedded else KIT_SCENE)
	var packed: PackedScene = load(path) as PackedScene
	root.add_child(packed.instantiate())
	if _paused:
		# Кейс «вернулся из мира»: сессия играла, дерево могло остаться
		# на паузе. Паузу включаем перед самым нажатием — честно, без
		# process_mode=ALWAYS у корня.
		var session: Node = root.get_node_or_null("/root/Session")
		if session != null:
			session.set("played", true)


func _find_menu() -> MainMenuBU:
	# Обвязка создаёт меню в _ready (deferred-готовность) — ищем в дереве.
	return root.find_child("MainMenuBU", true, false) as MainMenuBU


func _press_boot_offline() -> bool:
	# Boot без Steam (П10 — BootScreenBU) показывает окно «Steam не запущен»:
	# жмём «Играть офлайн» — путь владельца.
	var screen: BootScreenBU = root.find_child("BootScreenBU", true, false) as BootScreenBU
	if screen == null or not screen.is_steam_missing_shown():
		return false
	var buttons: Array = screen.find_children("*", "Button", true, false)
	var btn: Button = buttons[0] as Button if buttons.size() > 0 else null
	if btn == null:
		print("PROBE FAIL: в окне «Steam не запущен» нет кнопки")
		quit(4)
		return true
	btn.pressed.emit()
	return false


func _click_at(btn: Control) -> void:
	# Реальный клик мышью: конвертируем координаты канвы в координаты окна
	# (stretch canvas_items) и пушим события в корневой viewport напрямую.
	var center: Vector2 = btn.get_global_rect().get_center()
	var win_pos: Vector2 = (root.get_final_transform() * center)
	if _verbose_telemetry:
		print("PROBE-TEL: canvas=%s window=%s root.size=%s btn=%s" % [
			str(center), str(win_pos), str(root.size), btn.get_path()])
		_verbose_telemetry = false
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = win_pos
	motion.global_position = win_pos
	root.push_input(motion)
	var ev_pos: InputEventMouseButton = InputEventMouseButton.new()
	ev_pos.button_index = MOUSE_BUTTON_LEFT
	ev_pos.pressed = true
	ev_pos.position = win_pos
	root.push_input(ev_pos)
	var ev_rel: InputEventMouseButton = InputEventMouseButton.new()
	ev_rel.button_index = MOUSE_BUTTON_LEFT
	ev_rel.pressed = false
	ev_rel.position = win_pos
	root.push_input(ev_rel)


func _process(_delta: float) -> bool:
	_frame += 1
	if _boot:
		# Boot сменяет сцену отложенно — меню появится через нескольких кадров.
		if _menu == null:
			if _frame % 15 == 0:
				_menu = _find_menu()
				if _menu == null and _frame % 60 == 0:
					if _press_boot_offline():
						return true
				if _frame > 400:
					print("PROBE FAIL: MainMenuBU не появился после boot")
					quit(4)
					return true
			return false
	elif _menu == null:
		if _frame % 15 != 0:
			return false
		_menu = _find_menu()
		if _menu == null:
			if _frame > 300:
				print("PROBE FAIL: MainMenuBU не найден в дереве")
				quit(4)
				return true
			return false
	if _frame == 90 and _menu.quit_requested.get_connections().is_empty():
		# Standalone у кита слушателей нет — пробник сам играет хозяина:
		# по сигналу завершает процесс (как это делает обвязка игры).
		_menu.quit_requested.connect(func() -> void:
			_got_signal = true
			if not _embedded and not _boot:
				create_timer(0.9, true, false, true).timeout.connect(quit))
		print("PROBE: меню готово, режимы embedded=%s boot=%s click=%s paused=%s" % [
			str(_embedded), str(_boot), str(_click), str(_paused)])
	if _pressed_at < 0:
		if _frame % 30 != 0:
			return false
		var btn: Button = _menu.find_child("Btn_exit", true, false) as Button
		if btn == null:
			return false
		# Жмём не раньше, чем intro-обзор и fade закончились (~6 с при 60 к/с).
		if _frame < 420:
			return false
		# Контроль метода: клик по «Настройки» обязан открывать раздел —
		# если нет, headless-клики до GUI не доходят и вывод про «Выход» неверен.
		if _click and _frame == 420:
			var st: Button = _menu.find_child("Btn_settings", true, false) as Button
			if st != null:
				_click_at(st)
				return false
		if _click and _frame == 450:
			print("PROBE-CONTROL: после клика по «Настройки» section=%s (ожидается SETTINGS)" % [
				MainMenuBU.Section.keys()[_menu.section]])
			if _menu.section == MainMenuBU.Section.SETTINGS:
				# Метод валиден — вернуться в главное и продолжить тест «Выхода».
				_menu._back_to_main()
			else:
				print("PROBE FAIL: headless-клик до GUI не доходит — метод невалиден")
				quit(5)
				return true
			return false
		if _click and _frame == 480 and _menu.section != MainMenuBU.Section.MAIN:
			print("PROBE FAIL: не вернулись в главное после «Настройки»")
			quit(5)
			return true
		if _click and _frame < 510:
			return false
		if _paused:
			paused = true  # SceneTree.paused — пауза всего дерева в момент клика.
		if _click:
			print("PROBE: клик мышью по Btn_exit, кадр %d, hover-фокус=%s" % [
				_frame, str(btn.has_focus())])
			_click_at(btn)
		else:
			print("PROBE: жму Btn_exit (emit pressed), кадр %d" % _frame)
			btn.pressed.emit()
		_pressed_at = _frame
		return false
	# После нажатия: ждём завершения процесса от quit-твина меню.
	if _frame - _pressed_at == 180:  # ~3 с после нажатия
		print("PROBE: сигнал quit_requested=%s, fade.a=%.2f, paused=%s" % [
			str(_got_signal), _menu._fade.color.a, str(paused)])
		print("PROBE FAIL: процесс жив, quit не произошёл")
		quit(3)
		return true
	return false
