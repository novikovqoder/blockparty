# Самопроверка приземления (Д2, этап 0 закрытия П5.8): сценарий владельца
# на физическом игроке — бег (W зажата), прыжок, W НЕ отпускать, 2 с после
# приземления; то же с шагом (W+Shift); и приземление в стойку (поза ленда
# там уместна и должна сохраниться). При приземлении с горизонтальной
# скоростью поза ленда (статичный присед) не играется ни кадра — с кадра
# касания модель блендится в локомоцию (кросс-фейд ANIM_BLEND героя BU),
# покой — только при скорости ≈ 0. Клипы героя Born Unblessed: loco_*.
# Вызывают GUT-тест (test_landing_anim, чистая площадка) и --selftest-anim
# (реальный остров: направление бега выбирается raycast'ом — самое
# свободное из 8, чтобы не упереться в постройку/дерево).
# Прежние блоки реалистичности блочной UBC-модели (скольжение стоп на
# клипах, диапазоны рук, посадка MCO-одежды) вычищены вместе с ней
# (born-unblessed); статические позы героя BU проверяет AnimSelfCheckBU.
class_name RealismCheck
extends RefCounted

const B: Balance = preload("res://gameplay/balance.tres")


## Сценарий приземления (mode: "run" — W, "walk" — W+Shift, "still" —
## прыжок на месте). Возвращает {ok, reasons, metrics}.
static func check_landing_blend(player: Player, mode: String = "run",
		verbose: bool = false) -> Dictionary:
	var reasons: PackedStringArray = PackedStringArray()
	var metrics := {}
	var hz: int = Engine.physics_ticks_per_second
	var hold_move: bool = mode != "still"
	# Клипы героя Born Unblessed (П10): loco_jump_land / loco_idle /
	# loco_walk / loco_run.
	var land_clip := "loco_jump_land"
	var idle_clip := "loco_idle"
	var loco_clips: PackedStringArray = PackedStringArray(["loco_walk", "loco_run"])
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
		if first_loco_s < 0.0 or first_loco_s > HeroModelBU.ANIM_BLEND:
			reasons.append(
				"%s: бленд в локомоцию дольше ANIM_BLEND %.2f с: %.2f с"
				% [mode, HeroModelBU.ANIM_BLEND, maxf(first_loco_s, 0.0)])
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
## Работает с любой моделью (CharacterVisual): плеер даёт anim_player().
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
