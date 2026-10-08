# Верёвочная лестница смотровой площадки (раздел 9.3 SPEC): поднявшийся
# подсадкой жмёт E у края — лестница падает вдоль южной грани скалы и 60 с
# висит, чтобы поднялись остальные. Сброс подтверждает хост (ActivityAuthority:
# просящий должен стоять на площадке), узел только шлёт запрос и рисует.
# Лестница — наклонная стремянка из досек на двух тросах: перепад ступени
# меньше автоподъёма игрока, подниматься можно шагом (как тропа из plank_deck).
# До сброса не видна и без коллизий. Дети island.tscn; порядок имён
# LookoutLadder1..4 — как LOOKOUTS у IslandGen.
class_name LookoutLadder
extends Interactable

const B: Balance = preload("res://gameplay/balance.tres")
const PAL: Palette = preload("res://assets/palette.tres")

## Группа узлов лестниц (хост находит вершины смотровых; GROUP занято
## базовым Interactable.GROUP для подсказки E).
const LADDER_GROUP: StringName = &"lookout_ladder"

## Подъём лестницы: уступ смотровой, м.
const LADDER_DROP: float = 3.0
## Ступень: высота и вынос, м (перепад меньше автоподъёма игрока 0.55).
const STEP_RISE: float = 0.3
const STEP_RUN: float = 0.42
## Глубина доски-ступени вдоль хода, м.
const STEP_DEPTH: float = 0.7
## Толщина доски, м.
const STEP_THICK: float = 0.12
## Ширина лестницы, м.
const LADDER_WIDTH: float = 1.0
## Центр верхней ступени: вплотную к наружной грани стены кольца (1.95 м).
const TOP_STEP_Z: float = 2.3

var _active: bool = false
var _visual: Node3D
var _collisions: Array[CollisionShape3D] = []

## Индекс в порядке имени узла — как сортирует хост.
var _index: int = 0


func _ready() -> void:
	super()
	add_to_group(LADDER_GROUP)
	_index = _compute_index()
	use_radius = 2.6
	EventBus.ladder_state.connect(_on_ladder_state)
	_build_ladder()
	set_active(false)


func _on_ladder_state(index: int, active: bool, _expires_at: float) -> void:
	if index == _index:
		set_active(active)


## «E — сбросить лестницу»: только стоя на площадке и пока лестница
## не висит (повторный сброс до истечения 60 с невозможен).
func hint_key() -> String:
	return "" if _active or not _player_on_top() else "HINT_LADDER"


func use(_player: Node3D) -> void:
	Net.request_drop_ladder(_index)


## Локальный игрок на площадке: в радиусе ladder_top_radius от вершины
## и в окне высоты (проверку повторит хост по своей позиции игрока).
func _player_on_top() -> bool:
	var player := get_tree().get_first_node_in_group(Player.GROUP) as Player
	if player == null:
		return false
	var flat := player.global_position - global_position
	flat.y = 0.0
	return flat.length() <= B.ladder_top_radius \
		and absf(player.global_position.y - global_position.y) <= B.ladder_top_window


## Позиция среди лестниц группы в порядке имени (тот же порядок у хоста).
func _compute_index() -> int:
	var siblings: Array = []
	for node in get_tree().get_nodes_in_group(LADDER_GROUP):
		if node is LookoutLadder:
			siblings.append(node)
	siblings.sort_custom(
		func(a: LookoutLadder, b: LookoutLadder) -> bool:
			return (a as Node).name.naturalcasecmp_to((b as Node).name) < 0
	)
	return siblings.find(self)


## Применить состояние от хоста (rpc_ladder / world_state): лестница
## появляется со ступенями-коллайдерами или убирается. Повторный вызов
## с тем же состоянием — холостой.
func set_active(active: bool) -> void:
	if active == _active:
		return
	_active = active
	_visual.visible = active
	for collision: CollisionShape3D in _collisions:
		collision.disabled = not active


## Стремянка по южной грани: ступени поднимаются к площадке с юга, верхняя
## — у стены кольца (через её верх, слегка выше площадки, игрок заходит
## на площадку). Origin узла — центр площадки (LOOKOUT_TOP_H).
func _build_ladder() -> void:
	_visual = Node3D.new()
	_visual.name = "Ladder"
	add_child(_visual)

	var steps: int = int(round(LADDER_DROP / STEP_RISE))
	var body := StaticBody3D.new()
	body.name = "Steps"
	_visual.add_child(body)
	var material := StandardMaterial3D.new()
	material.albedo_color = PAL.planks
	for i: int in steps:
		# i = 0 — нижняя ступень у земли (юг), steps-1 — верхняя у стены.
		var top: float = -LADDER_DROP + float(i + 1) * STEP_RISE
		var z: float = TOP_STEP_Z + float(steps - 1 - i) * STEP_RUN
		var collision := CollisionShape3D.new()
		collision.name = "Step%d" % i
		var shape := BoxShape3D.new()
		shape.size = Vector3(LADDER_WIDTH, STEP_THICK, STEP_DEPTH)
		collision.shape = shape
		collision.position = Vector3(0.0, top - STEP_THICK * 0.5, z)
		body.add_child(collision)
		_collisions.append(collision)

		var rung := MeshInstance3D.new()
		rung.name = "Rung%d" % i
		var mesh := BoxMesh.new()
		mesh.size = Vector3(LADDER_WIDTH, STEP_THICK, STEP_DEPTH)
		rung.mesh = mesh
		rung.material_override = material
		rung.position = collision.position
		_visual.add_child(rung)

	# Тросы по краям лестницы — от нижней ступени до площадки.
	var dz: float = float(steps - 1) * STEP_RUN
	var length: float = Vector2(dz, LADDER_DROP).length()
	for side: float in [-1.0, 1.0]:
		var rope := MeshInstance3D.new()
		rope.name = "Rope%d" % int(side + 1.0)
		var rope_mesh := BoxMesh.new()
		rope_mesh.size = Vector3(0.06, length, 0.06)
		rope.mesh = rope_mesh
		var rope_material := StandardMaterial3D.new()
		rope_material.albedo_color = PAL.trunk
		rope.material_override = rope_material
		rope.position = Vector3(
			side * LADDER_WIDTH * 0.5, -LADDER_DROP * 0.5, TOP_STEP_Z + dz * 0.5
		)
		rope.rotation.x = atan2(-dz, LADDER_DROP)
		_visual.add_child(rope)
