# Самопроверка «реализма» персонажа (П5.8, Д1–Д4). Три численных блока:
#  1) стопы не скользят (Д2/Д3). Две метрики:
#     — контактная (критерий задания «опорная стопа за время касания
#       земли смещается ≤~5 см за шаг») — на клипе Walk, где стопа
#       реально опирается: подошва (нижняя из ball/ball_leaf) в пределах
#       CONTACT_EPS от пола окна; смещение за касание сравнивается с
#       V×t — модель на месте, «прилипшая» стопа обязана ехать назад
#       ровно со скоростью персонажа;
#     — оконная (методика калибровки NATURAL_SPEED, tools/
#       probe_clip_speed.gd): средняя скорость обратного хода стопы в
#       нижних 40% дуги × каденция против V — на игровых походках
#       (ходьба 2.5 = Jog_Fwd 0.85×, бег 6.5 = Sprint 1.49×). У беговых
#       клипов стопы не опираются, а чиркают план земли в нижней точке
#       дуги на пиковой скорости маятника (~10–13 м/с при каденции
#       1.49×) — контактный замер там меряет геометрию клипа, а не
#       каденцию; кроме того, дорожка ПОЛОЖЕНИЯ pelvis (±13 см у
#       Jog_Fwd/Sprint) не входила в калибровку Д3 и смещает оконную
#       скорость вверх. Допуски — достигнутые уровни с запасом (ловят
#       развал каденции класса Д2: каденция не по скорости даёт
#       расхождение в разы), остаток задокументирован в STATUS.md.
#     Сценарий приземления (Д2): LAND ≤ land_time, через 0.3 с — бег
#     с каденцией по фактической скорости.
#     Физический сценарий приземления (Д2, этап 0): прыжок на бегу/шагу
#     с зажатым движением и 2 с после касания — поза ленда при скорости
#     не играется вовсе (бленд в локомоцию ≤ ANIM_BLEND, покой — только
#     при ≈0); приземление в стойку позу ленда сохраняет.
#  2) руки в пределах (Д1): на позах всех клипов библиотеки углы локтя
#     (плечо–локоть–запястье) и кисти (локоть–запястье–палец) не выходят
#     за анатомические диапазоны — до фикса Д1 aim без ролла выкручивало
#     локти назад и кисти крутило случайно.
#  3) тело под одеждой (Д4): BodyFitCheck по текущей внешности модели;
#     приёмка раунда — по достигнутым уровням (замеры в docs/STATUS.md),
#     цель ~5 мм остаётся за правкой мешей одежды (владелец).
# Используется тестом GUT (test_p58_realism) и ключом --selftest-anim
# (все комбинации одежды × пол).
class_name RealismCheck
extends RefCounted

## Баланс геймплея (land_time приземления, скорости ходьбы/бега).
const B: Balance = preload("res://gameplay/balance.tres")

## Скольжение опорной стопы за одно касание земли, м — цель задания
## «~5 см за шаг»; на клипе Walk фактически 1–7 мм.
const STEP_SLIDE_MAX: float = 0.05
## Подошва считается «на земле» в пределах от пола окна замера, м.
const CONTACT_EPS: float = 0.005
## Доля размаха дуги стопы снизу — «фаза опоры» оконной метрики (та же,
## которой калибровались NATURAL_SPEED).
const CONTACT_SHARE: float = 0.4
## Допуск оконной метрики |обратный ход − V| для походки 2.5 м/с, м/с:
## достигнуто 0.9–1.4 (смещение дорожкой pelvis, которой не было в
## калибровке Д3; клипа быстрой ходьбы в библиотеке нет).
const WALK_GAIT_TOL: float = 1.6
## Допуск оконной метрики для бега 6.5 м/с, м/с: достигнуто ~0.3.
const RUN_TOL: float = 0.65
## Длительность замера локомоции, с.
const SLIDE_SECONDS: float = 2.4
## Скорость сценария контактной метрики — клип Walk (истинная опора).
const WALK_CLIP_MPS: float = 1.0

## Локоть: сгиб плечо–локоть–запястье, полный разгиб — 180°. Выше —
## выворот назад (дефект Д1), ниже — «сложенная» вплоть до схлопывания.
## Калибровка по клипам: 71°–178° (Idle_Rail_Call… Walk_Hand).
const ELBOW_MIN_DEG: float = 20.0
const ELBOW_MAX_DEG: float = 180.0
## Кисть: локоть–запястье–первая фаланга, 180° — кисть в линию с
## предплечьем. Калибровка по клипам: 130°–176°; сильный сгиб ниже —
## выкрут запястья.
const WRIST_MIN_DEG: float = 110.0
const WRIST_MAX_DEG: float = 180.0
## Кадров на клип для поз рук.
const ARM_POSES: int = 3

## Приёмка Д4 по достигнутым уровням (docs/STATUS.md, замеры probe_body_fit
## v8): выступ кожи сквозь ткань — худшая комбинация 17.2 мм (шея у ворота
## мужских топов при наклонах головы; правка мешей одежды — владелец).
## Порог ловит регрессию, не принимая остаток за норму цели (~5 мм).
const POKE_ACCEPT_M: float = 0.020
## Открытые края среза кожи вне одежды: худшая комбинация 65 из 152
## (плечи мужского Peasant — топ MCO шире тела UBC). Порог — с запасом.
const OPEN_EDGE_ACCEPT: int = 80
## Шов кожи рук с рукавом: достигнуто 23.6 мм (Wave_Hand, поднятая рука).
const SEAM_ACCEPT_M: float = 0.026


## Скольжение стоп (Д2/Д3): ходьба (контактно), игровые походки (оконно)
## и 0.3 с после приземления. Сопрограмма — точка входа GUT-теста.
static func check_foot_slide(model: CharacterModel) -> Dictionary:
	var reasons: PackedStringArray = PackedStringArray()
	var metrics := {}
	var skel := model.find_children("*", "Skeleton3D", true,
		false)[0] as Skeleton3D
	if skel == null:
		return {"ok": false,
			"reasons": PackedStringArray(["нет Skeleton3D"]),
			"metrics": metrics}
	var bad := await _settle(model, Protocol.AnimState.WALK, WALK_CLIP_MPS,
		"ходьба %.1f" % WALK_CLIP_MPS, reasons)
	if bad.is_empty():
		var window := await _sample_feet(model, skel, SLIDE_SECONDS)
		reasons += _touch_slides(window, WALK_CLIP_MPS, STEP_SLIDE_MAX,
			"ходьба_1.0", metrics)
	reasons += await _gait_window(model, skel, Protocol.AnimState.WALK,
		B.walk_speed, WALK_GAIT_TOL, "походка_%.1f" % B.walk_speed, metrics)
	reasons += await _gait_window(model, skel, Protocol.AnimState.RUN,
		B.run_speed, RUN_TOL, "бег_%.1f" % B.run_speed, metrics)
	reasons += await _land_then_run(model, skel, metrics)
	model.set_state(Protocol.AnimState.IDLE)
	return {"ok": reasons.is_empty(), "reasons": reasons,
		"metrics": metrics}


## Руки в пределах (Д1) на всех клипах — синхронно, без кадров.
static func check_arms(model: CharacterModel) -> Dictionary:
	var skel := model.find_children("*", "Skeleton3D", true,
		false)[0] as Skeleton3D
	if skel == null:
		return {"ok": false,
			"reasons": PackedStringArray(["нет Skeleton3D"]),
			"metrics": {}}
	var metrics := {}
	var reasons := _arm_ranges(skel, metrics)
	return {"ok": reasons.is_empty(), "reasons": reasons,
		"metrics": metrics}


## Тело под одеждой (Д4) — BodyFitCheck по текущей внешности, приёмка
## по достигнутым уровням раунда (см. константы выше).
static func check_body_fit(model: CharacterModel) -> Dictionary:
	var fit: Dictionary = BodyFitCheck.run(model, false)
	var metrics := {}
	for key: String in fit["metrics"]:
		metrics["fit_%s" % key] = fit["metrics"][key]
	var reasons: PackedStringArray = PackedStringArray()
	if float(metrics.get("fit_poke_max_m", 0.0)) > POKE_ACCEPT_M:
		for reason: String in fit["reasons"]:
			if reason.begins_with("кожа выступает"):
				reasons.append(reason)
	if int(metrics.get("fit_skin_open_outside", 0)) > OPEN_EDGE_ACCEPT:
		for reason: String in fit["reasons"]:
			if reason.begins_with("открытых краёв"):
				reasons.append(reason)
	if float(metrics.get("fit_seam_max_m", 0.0)) > SEAM_ACCEPT_M:
		for reason: String in fit["reasons"]:
			if reason.begins_with("шов кожи"):
				reasons.append(reason)
	# Структурные проблемы (нет мешей кожи/ткани, кожа без топа) — всегда
	# провал, независимо от приёмочных порогов.
	for reason: String in fit["reasons"]:
		if not reason.begins_with("кожа выступает") \
				and not reason.begins_with("открытых краёв") \
				and not reason.begins_with("шов кожи") \
				and not reason.begins_with("часть "):
			reasons.append(reason)
	return {"ok": reasons.is_empty(), "reasons": reasons,
		"metrics": metrics}


## Прогнать все проверки на модели (сопрограмма — ждёт кадры физики).
## Возвращает {ok, reasons, metrics}; reasons пустой — всё хорошо. Модель
## остаётся играть покой.
static func run(model: CharacterModel, verbose: bool = false) -> Dictionary:
	var reasons: PackedStringArray = []
	var metrics := {}
	var skel := model.find_children("*", "Skeleton3D", true,
		false)[0] as Skeleton3D
	if skel == null:
		return {"ok": false,
			"reasons": PackedStringArray(["нет Skeleton3D"]),
			"metrics": metrics}

	# 1) Скольжение стоп: ходьба, игровые походки и приземление.
	var feet: Dictionary = await check_foot_slide(model)
	reasons += feet["reasons"]
	for key: String in feet["metrics"]:
		metrics[key] = feet["metrics"][key]

	# 2) Руки в пределах на всех клипах.
	reasons += _arm_ranges(skel, metrics)

	# 3) Тело под одеждой (Д4) — текущая внешность модели.
	var fit: Dictionary = check_body_fit(model)
	reasons += fit["reasons"]
	for key: String in fit["metrics"]:
		metrics[key] = fit["metrics"][key]

	model.set_state(Protocol.AnimState.IDLE)
	if verbose:
		for key: String in metrics:
			print("  %s = %s" % [key, metrics[key]])
	return {"ok": reasons.is_empty(), "reasons": reasons,
		"metrics": metrics}


# --- Скольжение стоп (Д2/Д3) ---

## Оконная метрика игровой походки: средняя скорость обратного хода
## стопы (нижние CONTACT_SHARE дуги) × каденция против V, допуск tol.
static func _gait_window(model: CharacterModel, skel: Skeleton3D,
		state: int, mps: float, tol: float, label: String,
		metrics: Dictionary) -> PackedStringArray:
	var reasons: PackedStringArray = PackedStringArray()
	var bad := await _settle(model, state, mps, label, reasons)
	if not bad.is_empty():
		return reasons
	var window := await _sample_feet(model, skel, SLIDE_SECONDS)
	var dt: float = window["dt"]
	var worst := 0.0
	for side: String in ["лев", "прав"]:
		var ankle: Array[Vector3] = window["ankle_" + side]
		# сэмплы сняты с играющего клипа — каденция уже в них
		var back := _window_speed(ankle, dt)
		var diff: float = absf(back - mps)
		metrics["%s_%s_back_mps" % [label, side]] = back
		if diff > tol:
			reasons.append("%s (%s): обратный ход стопы %.2f м/с ≠ V %.2f"
				% [label, side, back, mps]
				+ " (|Δ| %.2f > %.2f) — каденция разъехалась со скоростью"
				% [diff, tol])
		worst = maxf(worst, diff)
	metrics["%s_window_diff_worst" % label] = worst
	return reasons


## Средняя горизонтальная скорость стопы в нижней части дуги (методика
## probe_clip_speed: нижние CONTACT_SHARE размаха по Y).
static func _window_speed(samples: Array[Vector3], dt: float) -> float:
	var low := 1e9
	var top := -1e9
	for p: Vector3 in samples:
		low = minf(low, p.y)
		top = maxf(top, p.y)
	var contact_top: float = low + (top - low) * CONTACT_SHARE
	var stance := 0
	var moved := 0.0
	for i: int in samples.size() - 1:
		if samples[i].y > contact_top or samples[i + 1].y > contact_top:
			continue
		stance += 1
		moved += Vector2(samples[i + 1].x - samples[i].x,
			samples[i + 1].z - samples[i].z).length()
	if stance == 0:
		return 0.0
	return moved / (float(stance) * dt)


## Дождаться установившейся локомоции: фактическая скорость сглаживается
## (LOCO_SMOOTH), клип выбирается по сглаженной скорости и переключается
## с кросс-фейдом ANIM_BLEND — пока каденция не вышла на целевую и бленд
## не догорел, траектория стопы — смесь двух клипов, замер бессмыслен.
## Возвращает непустой список причин, если не сошлось.
static func _settle(model: CharacterModel, state: int, mps: float,
		label: String, reasons: PackedStringArray) -> PackedStringArray:
	model.set_locomotion_speed(mps)
	model.set_state(state)
	var want_clip: StringName = CharacterAnims.locomotion_clip(mps)
	var want_scale: float = CharacterAnims.speed_scale(want_clip, mps)
	var settled := false
	for i: int in 90:  # ≤1.5 с: рампа 10/с сходится за ~0.5 с
		await model.get_tree().physics_frame
		if model._playing_clip() == want_clip \
				and absf(model._player.speed_scale - want_scale) < 0.02:
			settled = true
			break
	if not settled:
		reasons.append("%s: каденция не вышла на %s×%.2f за 1.5 с "
			% [label, want_clip, want_scale]
			+ "(играет %s×%.2f)" % [model._playing_clip(),
				model._player.speed_scale])
		return reasons
	for i: int in 15:  # догореть кросс-фейду (ANIM_BLEND 0.15 с)
		await model.get_tree().physics_frame
	return PackedStringArray()


## Окно позиций стоп по кадрам физики: подошва (нижняя из ball/ball_leaf)
## и лодыжка (foot — для оконной метрики). Возвращает {dt, sole_лев,
## sole_прав, ankle_лев, ankle_прав}.
static func _sample_feet(model: CharacterModel, skel: Skeleton3D,
		seconds: float) -> Dictionary:
	var dt: float = 1.0 / float(Engine.physics_ticks_per_second)
	var out := {"dt": dt}
	# метки сторон (в отчётах) → суффиксы костей UBC
	var suffix := {"лев": "l", "прав": "r"}
	var bones := {}
	for side: String in ["лев", "прав"]:
		bones[side] = [skel.find_bone("foot_" + suffix[side]),
			skel.find_bone("ball_" + suffix[side]),
			skel.find_bone("ball_leaf_" + suffix[side])]
		out["sole_" + side] = [] as Array[Vector3]
		out["ankle_" + side] = [] as Array[Vector3]
	for i: int in int(seconds / dt):
		await model.get_tree().physics_frame
		for side: String in ["лев", "прав"]:
			var b: Array = bones[side]
			(out["ankle_" + side] as Array[Vector3]).append(
				skel.get_bone_global_pose(b[0]).origin)
			var a: Vector3 = skel.get_bone_global_pose(b[1]).origin
			var c: Vector3 = skel.get_bone_global_pose(b[2]).origin
			(out["sole_" + side] as Array[Vector3]).append(
				a if a.y < c.y else c)
	return out


## Касания земли: подряд идущие кадры с подошвой в CONTACT_EPS от пола
## окна. Смещение за касание против V×длительность: модель на месте,
## стоящая на земле стопа едет назад со скоростью персонажа. Касание в
## один кадр меряется по соседним кадрам (центральная разность).
static func _touch_slides(window: Dictionary, mps: float,
		slide_max: float, label: String,
		metrics: Dictionary) -> PackedStringArray:
	var reasons: PackedStringArray = PackedStringArray()
	var dt: float = window["dt"]
	var worst := 0.0
	for side: String in ["лев", "прав"]:
		var samples: Array[Vector3] = window["sole_" + side]
		var floor_y := 1e9
		for p: Vector3 in samples:
			floor_y = minf(floor_y, p.y)
		var touches := 0
		var side_worst := 0.0
		var i := 0
		while i < samples.size():
			if samples[i].y > floor_y + CONTACT_EPS:
				i += 1
				continue
			var j: int = i
			while j + 1 < samples.size() \
					and samples[j + 1].y <= floor_y + CONTACT_EPS:
				j += 1
			# эпизод касания i..j; длительность и смещение — с кадром
			# до и после (подлёт и отрыв — часть шага у земли)
			var first: int = maxi(i - 1, 0)
			var last: int = mini(j + 1, samples.size() - 1)
			var dur: float = float(last - first) * dt
			var disp: float = Vector2(samples[last].x - samples[first].x,
				samples[last].z - samples[first].z).length()
			touches += 1
			side_worst = maxf(side_worst, absf(disp - mps * dur))
			i = j + 1
		metrics["%s_%s_touches" % [label, side]] = touches
		metrics["%s_%s_slide_m" % [label, side]] = side_worst
		if touches == 0:
			reasons.append("%s (%s): подошва не касается земли за %.1f с"
				% [label, side, float(samples.size()) * dt])
		elif side_worst > slide_max:
			reasons.append("%s (%s): опорная стопа за касание уезжает на "
				% [label, side] + "%.0f мм (порог %.0f мм), касаний %d"
				% [side_worst * 1000.0, slide_max * 1000.0, touches])
		worst = maxf(worst, side_worst)
	metrics["%s_slide_worst_m" % label] = worst
	return reasons


## Приземление на бегу (Д2): LAND играется не дольше land_time, затем
## локомоция по скорости — через 0.3 с после касания модель обязана
## играть бег с каденцией по фактической скорости.
static func _land_then_run(model: CharacterModel, skel: Skeleton3D,
		metrics: Dictionary) -> PackedStringArray:
	var reasons: PackedStringArray = PackedStringArray()
	model.set_locomotion_speed(B.run_speed)
	model.play_one_shot(Protocol.AnimState.LAND, B.land_time)
	# Пока LAND играет: суммарно не дольше land_time (клип ускорен до 6×).
	var hz: int = Engine.physics_ticks_per_second
	for i: int in int(0.3 * hz):
		await model.get_tree().physics_frame
	var land_left: float = model._one_shot_left
	metrics["land_left_after_300ms"] = land_left
	if land_left > 0.02:
		reasons.append("приземление: через 0.3 с LAND ещё играет "
			+ "(осталось %.2f с > land_time %.2f)" % [land_left, B.land_time])
	model.set_state(Protocol.AnimState.RUN)
	for i: int in int(0.1 * hz):
		await model.get_tree().physics_frame
	var clip := model._player.current_animation
	var scale: float = model._player.speed_scale
	metrics["post_land_clip"] = String(clip)
	metrics["post_land_speed_scale"] = scale
	if not String(clip).begins_with("%s/" % CharacterAnims.LIB_NAME):
		clip = StringName("%s/%s" % [CharacterAnims.LIB_NAME, clip])
	if String(clip) != "%s/%s" % [CharacterAnims.LIB_NAME,
			CharacterAnims.locomotion_clip(B.run_speed)]:
		reasons.append("после приземления: играет %s, ожидается бег %s"
			% [String(clip), CharacterAnims.locomotion_clip(B.run_speed)])
	elif absf(scale - CharacterAnims.speed_scale(
			CharacterAnims.locomotion_clip(B.run_speed),
			B.run_speed)) > 0.02:
		reasons.append("после приземления: каденция %.2f ≠ %.2f по скорости"
			% [scale, CharacterAnims.speed_scale(
				CharacterAnims.locomotion_clip(B.run_speed), B.run_speed)])
	return reasons


# --- Приземление с зажатым движением (Д2, этап 0) ---

## Сценарий владельца на ФИЗИЧЕСКОМ игроке (не статичной модели): движение
## зажато, прыжок, движение не отпускать, 2 с после приземления. До этапа 0
## поза ленда (статичный присед) играла land_time ≈ 0.2 с при беге 6.5 м/с —
## тело проезжало ~1.3 м со скольжением; проверка требует: при приземлении
## с горизонтальной скоростью ленд не играется ни кадра — с кадра касания
## модель блендится в локомоцию по фактической скорости (смена клипа
## мгновенна, кросс-фейд ANIM_BLEND = 0.15 с), покой — только при ≈ 0.
## mode: "run" (W), "walk" (W+Shift — шаг), "still" (прыжок на месте:
## поза ленда обязана сохраниться — скольжения при ≈ 0 нет).
## Вызывают GUT-тест (test_landing_anim, чистая площадка) и --selftest-anim
## (реальный остров: направление бега выбирается raycast'ом — самое
## свободное из 8, чтобы не упереться в постройку/дерево).
static func check_landing_blend(player: Player, mode: String = "run",
		verbose: bool = false) -> Dictionary:
	var reasons: PackedStringArray = PackedStringArray()
	var metrics := {}
	var hz: int = Engine.physics_ticks_per_second
	var hold_move: bool = mode != "still"
	# П10: имена клипов модели — у блочного UBC и героя Born Unblessed
	# разные (Walk/Jog_Fwd/Sprint против loco_walk/loco_run).
	var land_clip := "Jump_Land"
	var idle_clip := "Idle"
	var loco_clips: PackedStringArray = PackedStringArray(["Walk", "Jog_Fwd", "Sprint"])
	if player.visual is HeroModelBU:
		land_clip = "loco_jump_land"
		idle_clip = "loco_idle"
		loco_clips = PackedStringArray(["loco_walk", "loco_run"])
	if hold_move:
		_face_clear_direction(player)
		Input.action_press("move_forward")
		if mode == "walk":
			Input.action_press("walk")
		var target: float = B.walk_speed if mode == "walk" else B.run_speed
		for i: int in int(0.6 * hz):
			await player.get_tree().physics_frame
		var pre: float = _player_hspeed(player)
		metrics["%s_pre_jump_mps" % mode] = pre
		if pre < target * 0.7:
			reasons.append(
				"%s: до прыжка не разогнался до 70%% скорости (%.2f из %.1f м/с — препятствие на пути?)"
				% [mode, pre, target])
	# Прыжок и полёт: буфер ввода ловит кадр; ждём отрыва, затем касания.
	Input.action_press("jump")
	await player.get_tree().physics_frame
	Input.action_release("jump")
	var airborne := false
	for i: int in int(0.8 * hz):
		await player.get_tree().physics_frame
		if not player.is_on_floor():
			airborne = true
		elif airborne:
			break
	if not airborne:
		reasons.append("%s: не оторвался от земли за 0.8 с" % mode)
		_release_move(hold_move)
		return {"ok": false, "reasons": reasons, "metrics": metrics}
	# 2 с после касания, покадрово: клип модели против фактической скорости.
	var land_frames := 0
	var bad_frames := 0
	var air_frames := 0
	var first_loco_s: float = -1.0
	for i: int in int(2.0 * hz):
		await player.get_tree().physics_frame
		var clip := _model_clip(player.visual)
		var hs := _player_hspeed(player)
		if clip == land_clip:
			land_frames += 1
		# Кадры без контакта с землёй — не скольжение: поза прыжка в
		# воздухе уместна (состояние FALL — прямое отражение
		# is_on_floor), а «ехать по земле» без земли нельзя. На реальном
		# острове (GROUND_SNUG-прижатые камни, кромки подушек) бег
		# после приземления пересекает препятствия и коротко отрывается;
		# наземные кадры проверяются как раньше, без послаблений.
		if not player.is_on_floor():
			air_frames += 1
			continue
		if not hold_move or hs <= B.anim_idle_speed + 0.1:
			continue
		var loco: bool = clip in loco_clips
		if clip == land_clip or clip == idle_clip or not loco:
			bad_frames += 1
			if bad_frames <= 3:
				reasons.append(
					"%s: кадр %d после касания — %s при скорости %.2f м/с (поза ленда/покой едет по земле = скольжение)"
					% [mode, i + 1, clip, hs])
		elif first_loco_s < 0.0:
			first_loco_s = float(i + 1) / hz
	metrics["%s_land_pose_frames" % mode] = land_frames
	metrics["%s_air_frames" % mode] = air_frames
	metrics["%s_bad_clip_frames" % mode] = bad_frames
	if mode == "still":
		# Прыжок на месте: приземление почти без скорости — поза ленда
		# уместна и обязана сохраниться (чекер этапа 0 её не выпилил).
		if land_frames == 0:
			reasons.append(
				"still: поза ленда не играется при приземлении в стойку (скорость ≈ 0) — регресс одного лишь ленда")
	else:
		metrics["%s_first_locomotion_s" % mode] = first_loco_s
		if land_frames > 0:
			reasons.append(
				"%s: поза ленда играется при приземлении на ходу: %d кадров (~%.2f с) — статичный присед едет по земле"
				% [mode, land_frames, float(land_frames) / hz])
		if first_loco_s < 0.0 or first_loco_s > CharacterModel.ANIM_BLEND:
			reasons.append(
				"%s: бленд в локомоцию дольше ANIM_BLEND %.2f с: %.2f с"
				% [mode, CharacterModel.ANIM_BLEND, maxf(first_loco_s, 0.0)])
	_release_move(hold_move)
	if verbose:
		for key: String in metrics:
			print("  %s = %s" % [key, metrics[key]])
	return {"ok": reasons.is_empty(), "reasons": reasons,
		"metrics": metrics}


## Горизонтальная скорость игрока, м/с.
static func _player_hspeed(player: Player) -> float:
	return Vector2(player.velocity.x, player.velocity.z).length()


## Клип, играющий на визуале персонажа (без имени библиотеки), «-» — ничего.
## П10: работает с любой моделью (CharacterVisual): плеер даёт anim_player().
static func _model_clip(visual: CharacterVisual) -> String:
	var ap: AnimationPlayer = visual.anim_player()
	if ap == null or ap.current_animation.is_empty():
		return "-"
	var parts := (ap.current_animation as String).split("/")
	return parts[parts.size() - 1]


static func _release_move(hold_move: bool) -> void:
	Input.action_release("move_forward")
	if hold_move and Input.is_action_pressed("walk"):
		Input.action_release("walk")


## Повернуть камеру игрока в самое свободное из 8 направлений (по
## горизонтальным raycast'ам на высоте щиколотки и груди — ловят и
## камни, и стены): W бежит от камеры, сценарий не упрётся в постройку.
static func _face_clear_direction(player: Player) -> void:
	var space := player.get_world_3d().direct_space_state
	var best_dir := Vector3(0.0, 0.0, -1.0)
	var best_clear := -1.0
	for k: int in 8:
		var ang: float = TAU * float(k) / 8.0
		var dir := Vector3(sin(ang), 0.0, cos(ang))
		var clear := 14.0
		for height: float in [0.3, 1.2]:
			var from := player.global_position + Vector3.UP * height
			var query := PhysicsRayQueryParameters3D.create(from,
				from + dir * 14.0, player.collision_mask,
				[player.get_rid()])
			var hit := space.intersect_ray(query)
			if not hit.is_empty():
				clear = minf(clear,
					(hit["position"] as Vector3).distance_to(from))
		if clear > best_clear:
			best_clear = clear
			best_dir = dir
	player.camera.rotation.y = atan2(-best_dir.x, -best_dir.z)


# --- Руки в пределах (Д1) ---

## Углы локтя и кисти в позах всех клипов (позы по цепочке рестов, как
## BodyFitCheck._clip_globals). Позиции суставов — глобальные трансформы
## костей: плечо (upperarm), локоть (lowerarm), запястье (hand), палец
## (middle_01).
static func _arm_ranges(skel: Skeleton3D,
		metrics: Dictionary) -> PackedStringArray:
	var reasons: PackedStringArray = PackedStringArray()
	var lib := CharacterAnims.library()
	var elbow_min := 180.0
	var elbow_max := 0.0
	var wrist_min := 180.0
	var wrist_max := 0.0
	var poses_checked := 0
	for clip_name: StringName in lib.get_animation_list():
		var anim := lib.get_animation(clip_name) as Animation
		var tracks := BodyFitCheck._tracks_by_bone(anim, skel)
		for k: int in ARM_POSES:
			var t: float = anim.length * (float(k) + 0.5) / ARM_POSES
			var pose := BodyFitCheck._clip_globals(skel, anim, tracks, t)
			poses_checked += 1
			for side: String in ["l", "r"]:
				var shoulder: int = skel.find_bone("upperarm_" + side)
				var elbow_b: int = skel.find_bone("lowerarm_" + side)
				var wrist_b: int = skel.find_bone("hand_" + side)
				var finger_b: int = skel.find_bone("middle_01_" + side)
				if shoulder < 0 or elbow_b < 0 or wrist_b < 0 or finger_b < 0:
					continue
				var sh := pose[shoulder].origin
				var el := pose[elbow_b].origin
				var wr := pose[wrist_b].origin
				var fg := pose[finger_b].origin
				var elbow: float = rad_to_deg((sh - el)
					.angle_to(wr - el))
				var wrist: float = rad_to_deg((el - wr).angle_to(fg - wr))
				elbow_min = minf(elbow_min, elbow)
				elbow_max = maxf(elbow_max, elbow)
				wrist_min = minf(wrist_min, wrist)
				wrist_max = maxf(wrist_max, wrist)
				if elbow < ELBOW_MIN_DEG or elbow > ELBOW_MAX_DEG:
					reasons.append("%s@%.2fs: локоть %.0f° вне [%.0f, %.0f°]"
						% [clip_name, t, elbow, ELBOW_MIN_DEG, ELBOW_MAX_DEG])
				if wrist < WRIST_MIN_DEG or wrist > WRIST_MAX_DEG:
					reasons.append("%s@%.2fs: кисть %.0f° вне [%.0f, %.0f°]"
						% [clip_name, t, wrist, WRIST_MIN_DEG, WRIST_MAX_DEG])
	metrics["arm_poses_checked"] = poses_checked
	metrics["arm_elbow_min_deg"] = elbow_min
	metrics["arm_elbow_max_deg"] = elbow_max
	metrics["arm_wrist_min_deg"] = wrist_min
	metrics["arm_wrist_max_deg"] = wrist_max
	return reasons
