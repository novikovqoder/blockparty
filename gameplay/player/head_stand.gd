# Подсадка на голову (раздел 5 SPEC): у каждого игрока есть коллайдер
# головы — плоский бокс 0.6 × 0.1 × 0.6 на макушке, на отдельном физическом
# слое LAYER_HEAD. Свой персонаж сталкивается с этим слоем, только когда
# падает (velocity.y <= 0) и его ступни выше верхней грани бокса: на голову
# можно встать сверху, но нельзя «упереться» в неё сбоку.
# Условие вынесено в чистую функцию — обязательный тест раздела 18.
class_name HeadStand
extends RefCounted

## Физический слой коллайдеров голов (маска мира — слой 1, игроки — 2).
const LAYER_HEAD: int = 3
## Группа узлов HeadTop (проверка «пол под ногами — голова» для буста прыжка).
const GROUP: StringName = &"head_top"


## Можно ли сейчас столкнуться с коллайдером головы: только при падении
## и только если ступни (feet_y) не ниже верхней грани бокса (head_top_y).
## eps — допуск на кадр контакта из balance.tres.
static func can_stand(feet_y: float, head_top_y: float, velocity_y: float, eps: float) -> bool:
	return velocity_y <= 0.0 and feet_y >= head_top_y - eps


## Уровень, которого достигают ступни при прыжке с головы другого игрока
## (рост + усиленный прыжок), м — запасной проверкой «хватает на уступ 3 блока».
static func head_jump_reach(b: Balance) -> float:
	return b.body_height + JumpMath.apex_from(JumpMath.boosted_jump_speed(b), b.gravity)
