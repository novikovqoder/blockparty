# Якорное позиционирование панелей HUD (vfx-fix, баг 5): окна и центральные
# элементы обязаны держаться якорями, а не абсолютными координатами под
# 1280 × 720 — при stretch keep_height логическая высота всегда 720, а ширина
# меняется с аспектом окна, и «position = (490, 240)» вместе с якорем 0.5
# уезжает в правый нижний угол (якорь умножается на размер родителя при входе
# в дерево). Все методы ставят якоря и офсеты так, что узел фиксированного
# размера остаётся на месте при любом размере окна; вызывать можно до
# add_child — офсеты не зависят от родителя.
class_name UiLayout
extends RefCounted


## Панель фиксированного размера по центру родителя.
static func center(node: Control, size: Vector2) -> void:
	center_offset(node, size, Vector2.ZERO)


## Узел фиксированного размера центром в offset от центра родителя
## (пункты колеса эмоций по окружности вокруг центра экрана).
static func center_offset(node: Control, size: Vector2, offset: Vector2) -> void:
	node.anchor_left = 0.5
	node.anchor_right = 0.5
	node.anchor_top = 0.5
	node.anchor_bottom = 0.5
	node.offset_left = offset.x - size.x * 0.5
	node.offset_right = offset.x + size.x * 0.5
	node.offset_top = offset.y - size.y * 0.5
	node.offset_bottom = offset.y + size.y * 0.5


## Узел фиксированного размера по центру нижнего края (отступ margin вверх).
static func center_bottom(node: Control, size: Vector2, margin: float) -> void:
	node.anchor_left = 0.5
	node.anchor_right = 0.5
	node.anchor_top = 1.0
	node.anchor_bottom = 1.0
	node.offset_left = -size.x * 0.5
	node.offset_right = size.x * 0.5
	node.offset_top = -margin - size.y
	node.offset_bottom = -margin


## Узел фиксированного размера по центру верхнего края (отступ margin вниз).
static func center_top(node: Control, size: Vector2, margin: float) -> void:
	node.anchor_left = 0.5
	node.anchor_right = 0.5
	node.anchor_top = 0.0
	node.anchor_bottom = 0.0
	node.offset_left = -size.x * 0.5
	node.offset_right = size.x * 0.5
	node.offset_top = margin
	node.offset_bottom = margin + size.y


## Узел фиксированного размера у правого края: отступ margin влево,
## верх узла на top от верхнего края (строки трекера заданий).
static func top_right(
	node: Control, size: Vector2, margin: float, top: float
) -> void:
	node.anchor_left = 1.0
	node.anchor_right = 1.0
	node.anchor_top = 0.0
	node.anchor_bottom = 0.0
	node.offset_left = -margin - size.x
	node.offset_right = -margin
	node.offset_top = top
	node.offset_bottom = top + size.y
