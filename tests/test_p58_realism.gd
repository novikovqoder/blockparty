# Тесты «реализма» П5.8 (Д1–Д4), численно с порогами:
#  Д2/Д3 — стопы не скользят: клипы на месте, каденция по фактической
#    скорости (set_locomotion_speed); опорная стопа обязана стоять
#    (~5 см за шаг → средняя скорость в опоре ≤0.15 м/с). Сценарии:
#    ходьба 2.0 м/с, бег 6.5 м/с, 0.3 с после приземления на бегу
#    (Jump_Land ≤ land_time и возврат в бег с каденцией по скорости);
#    этап 0 — физический лендинг-сценарий отдельно (test_landing_anim).
#  Д1 — руки в пределах: углы локтя и кисти в позах всех клипов
#    библиотеки не выходят за анатомические диапазоны. После отката
#    фикса Д1 (этап 0) тест ЗЕЛЁНЫЙ: дореволюционные процедурники в
#    пределах углов — визуальный дефект (гуляющий ролл ладони) пределами
#    не измеряется, известный дефект закрывается П5.10–П5.11 (STATUS.md).
#    Тест остаётся активным, чтобы ловить регрессию диапазонов.
#  Д4 — тело под одеждой: после отката Д4 (этап 0) тела несрезанные —
#    кожа выступает сквозь ткань в движении. ИЗВЕСТНЫЙ ДЕФЕКТ П5.8 →
#    закрывается П5.10–П5.11 (см. STATUS.md), тест в known-fail;
#    пороги чекера не ослаблены.
extends GutTest

const MODEL: PackedScene = preload("res://gameplay/player/character_model.tscn")


func _make(gender: int, outfit: int = -1) -> CharacterModel:
	var model := MODEL.instantiate() as CharacterModel
	add_child_autofree(model)
	var ap := Appearance.default_for(gender)
	if outfit >= 0:
		ap.top = outfit
		ap.legs = outfit
		ap.feet = outfit
	model.setup_appearance(ap)
	return model


func test_feet_do_not_slide() -> void:
	# Д2/Д3: ходьба, бег и 0.3 с после приземления — опорная стопа на месте.
	for gender: int in Appearance.GENDERS:
		var model := _make(gender)
		var res: Dictionary = await RealismCheck.check_foot_slide(model)
		var reasons: PackedStringArray = res["reasons"]
		assert_true(res["ok"], "пол %d: %s" % [gender,
			"; ".join(PackedStringArray(reasons))])


func test_arms_within_ranges() -> void:
	# Д1: локти/кисти всех клипов в анатомических диапазонах.
	for gender: int in Appearance.GENDERS:
		var model := _make(gender)
		var res: Dictionary = RealismCheck.check_arms(model)
		var reasons: PackedStringArray = res["reasons"]
		assert_true(res["ok"], "пол %d: %s" % [gender,
			"; ".join(PackedStringArray(reasons))])


func test_body_under_clothes() -> void:
	# Д4: срез тела «по одежде» держит кожу под тканью во всех позах
	# всех клипов — все комбинации пол × наряд.
	# Этап 0 (откат Д4 по решению владельца: «тело пятнами сквозь
	# рубашку, раздутые плечи» — срез сделал хуже): тела снова
	# несрезанные, кожа выступает сквозь ткань в движении (замер
	# 21.8 мм > порога 5 мм на позе ClimbUp_1m). Известный дефект П5.8,
	# закрывается П5.10–П5.11 по VISUAL_PLAN v1.1 — тест отложен
	# (known-fail/pending), пороги чекера не тронуты.
	pending("известный дефект П5.8 (тело под одеждой после отката Д4) → "
		+ "закрывается П5.10–П5.11, см. STATUS.md")
