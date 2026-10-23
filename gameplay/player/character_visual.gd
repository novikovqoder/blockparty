# Базовый класс визуала персонажа (П10): единый интерфейс, по которому игрок
# (player.gd), чужие игроки (remote_player.gd) и сцена мира обращаются к
# модели и анимациям. Реализации: CharacterModel — сборка из запечённых
# Quaternius UBC/MCO (жители, редактор внешности, --old-меню), HeroModelBU —
# рыцарь Born Unblessed (модель игрока П10). Методы базы — пустые заглушки:
# реализация обязана переопределить нужное, остальное спокойно игнорирует.
# Внешность хранится в базе: структура в сети не меняется (PROTOCOL_VERSION
# прежний), герой BU её просто не показывает.
class_name CharacterVisual
extends Node3D

## Внешность, зафиксированная в setup_appearance (у героя BU — только память).
var appearance: Appearance = null
## Номер пресета (0…2) для интерфейса setup(character) жителей.
var character: int = 0


## Построить модель пресета (жители). Герой BU пресетов не имеет.
func setup(p_character: int) -> void:
	character = p_character


## Собрать модель по внешности редактора; герой BU всегда один и тот же.
func setup_appearance(ap: Appearance) -> void:
	appearance = ap


## Цвет игрока по хэшу id (герой BU не перекрашивается).
func setup_palette(_id: int) -> void:
	pass


## Покрасить верхнюю одежду цветом (герой BU не перекрашивается).
func setup_body_color(_color: Color) -> void:
	pass


## Дистанция переключения LOD (у героя BU LOD-копий нет).
func set_lod_distance(_distance: float) -> void:
	pass


## Сетевое состояние аниматора (Protocol.AnimState) — покой/ходьба/бег/фазы
## прыжка выбираются локально по скорости и касанию земли (player.gd).
func set_state(_state: int) -> void:
	pass


## Фактическая горизонтальная скорость персонажа, м/с — темп ног.
func set_locomotion_speed(_mps: float) -> void:
	pass


## Разовая анимация (взмах, приземление): играет целиком и возвращает
## состояние. Клипа может не быть — тогда ничего не проигрывается (П10:
## эмоции героя BU показывает только пузырь).
func play_one_shot(_state: int, _duration: float) -> void:
	pass


## Удар («тычок», раздел 5): по умолчанию — тот же взмах, что и раньше;
## герой BU бьёт замахом ss_slash (комплект меча).
func play_attack(duration: float) -> void:
	play_one_shot(Protocol.AnimState.WAVE, duration)


## Покадровое продвижение анимации (съёмка серий при Engine.time_scale = 0).
func advance_preview(_delta: float) -> void:
	pass


## Точка крепления предмета (HandL/HandR/Back); у героя BU — null.
func attach_point(_point_name: String) -> Node3D:
	return null


## Макушка головы, м (с учётом масштаба модели).
func head_top_height() -> float:
	return 0.0


## Нижняя точка модели (подошвы), м.
func lowest_point() -> float:
	return 0.0


## Число мешей с LOD-близнецом (для тестов).
func lod_pairs() -> int:
	return 0


## Плеер анимаций визуала (самопроверки анимаций), может быть null.
func anim_player() -> AnimationPlayer:
	return null
