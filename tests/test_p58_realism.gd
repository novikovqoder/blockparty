# Тесты «реализма» П5.8 (Д1–Д4) проверяли блочную UBC-модель
# (CharacterModel, пол × наряд, клипы Quaternius UAL): вычищены вместе
# с ней и редактором внешности (born-unblessed). Анимации героя
# Born Unblessed проверяют test_landing_anim.gd (лендинг-сценарий Д2
# на физическом игроке) и AnimSelfCheckBU в --selftest-anim.
extends GutTest


func test_p58_realism_retired_with_ubc_model() -> void:
	pending("П5.8 ушёл вместе с UBC/MCO-моделью и редактором внешности "
		+ "(born-unblessed); героя BU проверяют test_landing_anim.gd "
		+ "и --selftest-anim")
