# Твёрдое тело узла мира (vfx-fix, баг 2): единая фабрика StaticBody3D
# на слое 1 — его чувствует маска игрока (collision_mask = 1). Форма —
# по габариту видимой модели, «ногами» в origin узла: как у предметов
# раскладки (IslandArt.colliders) и персонажей. Пользуются узлы, которые
# не проходят через IslandGen: костёр, мята, вехи, квестовые маяки,
# сундук, камни духа, жители.
class_name SolidBody
extends RefCounted


## Присоединить к узлу StaticBody3D с одной формой; position — центр формы
## в локальных координатах узла. Возвращает тело (выключение — set_enabled).
static func add(
	parent: Node3D, shape: Shape3D, position: Vector3 = Vector3.ZERO
) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Solid"
	body.collision_layer = 1  # слой мира: блокирует игрока
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = position
	body.add_child(collision)
	parent.add_child(body)
	return body


## Включить/выключить коллизию (set_deferred — вызов может попасть
## в физический шаг). Выключенное тело не блокирует, оставаясь в дереве.
static func set_enabled(body: StaticBody3D, enabled: bool) -> void:
	for child: Node in body.get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).set_deferred("disabled", not enabled)
