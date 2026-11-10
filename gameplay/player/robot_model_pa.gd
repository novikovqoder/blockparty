# Герой района-постапокалипсиса: человекоподобный робот «Ivory Sentinel»
# (assets/robot_pa: заготовка Meshy, доработка Claude — жёсткий таз, ноги
# на шаровых шарнирах, текстура по листу персонажа с износом).
# Та же логика, что у рыцаря Born Unblessed (HeroModelBU): локомоция,
# прыжок, поворот на месте, самопроверка анимаций. Отличия: своя модель
# и своя библиотека локомоции (Mixamo «Male Locomotion», перенесена
# tools/retarget_mixamo_bu.gd + tools/build_base_anims_bu.gd на скелет
# робота); меча нет — снаряжения и удара мечом нет.
# Ставит его в игрока сцена района (DistrictLab) — Born Unblessed не меняется.
class_name RobotModelPA
extends HeroModelBU

const ROBOT_SCENE: PackedScene = preload("res://assets/robot_pa/robot_pa.glb")
const ROBOT_ANIMS_PATH: String = "res://assets/robot_pa/robot_base_anims.res"


func _hero_scene() -> PackedScene:
	return ROBOT_SCENE


func _sword_library() -> AnimationLibrary:
	return null


func _base_library_path() -> String:
	return ROBOT_ANIMS_PATH
