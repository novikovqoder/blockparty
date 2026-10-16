# Тесты «реализма» П5.8 (Д1–Д4), численно с порогами:
#  Д2/Д3 — стопы не скользят: клипы на месте, каденция по фактической
#    скорости (set_locomotion_speed); опорная стопа обязана стоять
#    (~5 см за шаг → средняя скорость в опоре ≤0.15 м/с). Сценарии:
#    ходьба 2.0 м/с, бег 6.5 м/с, 0.3 с после приземления на бегу
#    (Jump_Land ≤ land_time и возврат в бег с каденцией по скорости).
#  Д1 — руки в пределах: углы локтя и кисти в позах всех клипов
#    библиотеки не выходят за анатомические диапазоны (до фикса
#    aim-ретаргет без ролла выкручивал локти/кисти).
#  Д4 — тело под одеждой: BodyFitCheck по всем комбинациям внешности
#    (пол × наряд): кожа не выступает сквозь ткань (~5 мм + запас),
#    открытые края кожи не висят вне одежды, швы кожи рук с тканью
#    в пределах.
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
	for gender: int in Appearance.GENDERS:
		for outfit: int in Appearance.OUTFITS.size():
			var model := _make(gender, outfit)
			var res: Dictionary = RealismCheck.check_body_fit(model)
			var reasons: PackedStringArray = res["reasons"]
			assert_true(res["ok"], "пол %d наряд %d: %s" % [gender, outfit,
				"; ".join(PackedStringArray(reasons))])
