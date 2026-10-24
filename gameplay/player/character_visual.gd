# Базовый класс визуала персонажа: единый интерфейс, по которому игрок
# (player.gd), чужие игроки (remote_player.gd) и сцена мира обращаются к
# модели и анимациям. Реализация — HeroModelBU, рыцарь Born Unblessed
# (модель игрока). Методы базы — пустые заглушки: реализация обязана
# переопределить нужное, остальное спокойно игнорирует.
# Прежняя вторая реализация — блочная CharacterModel из запечённых
# Quaternius UBC/MCO — вычищена вместе с редактором внешности и жителями
# (born-unblessed); внешность в сети и настройки цвета больше не ходят.
class_name CharacterVisual
extends Node3D


## Сетевое состояние аниматора (Protocol.AnimState) — покой/ходьба/бег/фазы
## прыжка выбираются локально по скорости и касанию земли (player.gd).
func set_state(_state: int) -> void:
	pass


## Фактическая горизонтальная скорость персонажа, м/с — темп ног.
func set_locomotion_speed(_mps: float) -> void:
	pass


## Разовая анимация (взмах, приземление): играет целиком и возвращает
## состояние. Клипа может не быть — тогда ничего не проигрывается
## (эмоции героя BU показывает только пузырь).
func play_one_shot(_state: int, _duration: float) -> void:
	pass


## Удар («тычок», раздел 5): по умолчанию — тот же взмах, что и раньше;
## герой BU бьёт замахом ss_slash (комплект меча).
func play_attack(duration: float) -> void:
	play_one_shot(Protocol.AnimState.WAVE, duration)


## Покадровое продвижение анимации (съёмка серий при Engine.time_scale = 0).
func advance_preview(_delta: float) -> void:
	pass


## Макушка головы, м (с учётом масштаба модели).
func head_top_height() -> float:
	return 0.0


## Нижняя точка модели (подошвы), м.
func lowest_point() -> float:
	return 0.0


## Плеер анимаций визуала (самопроверки анимаций), может быть null.
func anim_player() -> AnimationPlayer:
	return null
