# Фирменные головные уборы трёх персонажей (раздел 16 SPEC): процедурные
# low-poly меши, которые CharacterModel крепит к кости head поверх родной
# головы/шлема/шляпы. Убор одинаков у всех игроков одного персонажа —
# игроков различает цвет тела (шаг 3), а персонажей — силуэт и убор.
# Размеры — в локальных координатах модели KayKit (рост ~2.3, ширина
# головы ~1.1): контейнер лежит внутри масштабируемого glb-инстанса,
# при масштабе ~0.72 убор уменьшится вместе с моделью.
class_name CharacterHat
extends RefCounted

## Виды уборов: индексы фиксированы — на них ссылается CharacterModel.HATS.
enum Kind { SPROUT, SHELL, EARS }

const SPROUT_STEM := Color(0.32, 0.58, 0.26)
const SPROUT_LEAF_A := Color(0.45, 0.78, 0.32)
const SPROUT_LEAF_B := Color(0.55, 0.85, 0.38)
const SHELL_BASE := Color(0.96, 0.82, 0.74)
const SHELL_EDGE := Color(0.88, 0.52, 0.55)
const EARS_FUR := Color(0.93, 0.82, 0.62)
const EARS_INNER := Color(0.98, 0.90, 0.78)


## Собрать убор: Node3D с именами частей (осмотр и тесты), origin — у кости
## head персонажа, ось Y — вверх вдоль шеи.
static func build(kind: int) -> Node3D:
	var hat := Node3D.new()
	hat.name = "Hat"
	hat.set_meta("kind", kind)
	match kind:
		Kind.SPROUT:
			_sprout(hat)
		Kind.SHELL:
			_shell(hat)
		Kind.EARS:
			_ears(hat)
	return hat


static func _part(parent: Node3D, part_name: String, mesh: Mesh, color: Color,
		pos: Vector3, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = part_name
	part.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.65
	part.material_override = material
	# Метка «часть убора»: цвет игрока (CharacterModel.setup_palette) убор
	# не тонирует — убор отличает персонажа, цвет — игрока.
	part.set_meta("hat_part", true)
	part.position = pos
	part.rotation_degrees = rot_deg
	parent.add_child(part)
	return part


## Росток с двумя листиками (Ranger): стебель из макушки, листики врозь.
## Макушка волос ~1.03 от кости head: стебель уходит низом в причёску,
## а верх с листиками — заметно над головой (по выговору осмотра первый
## вариант «утоп в волосах»).
static func _sprout(hat: Node3D) -> void:
	var stem := CylinderMesh.new()
	stem.top_radius = 0.026
	stem.bottom_radius = 0.045
	stem.height = 0.52
	stem.radial_segments = 6
	_part(hat, "SproutStem", stem, SPROUT_STEM, Vector3(0.0, 1.06, 0.0))
	var leaf := SphereMesh.new()
	leaf.radius = 0.115
	leaf.height = 0.23
	leaf.radial_segments = 5
	leaf.rings = 2
	# Наклон врозь и вперёд-назад: в профиль листики не сливаются.
	var leaf_l := _part(
		hat, "SproutLeafL", leaf, SPROUT_LEAF_A,
		Vector3(0.15, 1.30, 0.04), Vector3(22.0, 25.0, -55.0),
	)
	leaf_l.scale = Vector3(1.0, 0.5, 0.35)
	var leaf_r := _part(
		hat, "SproutLeafR", leaf, SPROUT_LEAF_B,
		Vector3(-0.15, 1.30, -0.04), Vector3(-22.0, -25.0, 55.0),
	)
	leaf_r.scale = Vector3(1.0, 0.5, 0.35)


## Ракушка-веер (Mage): пять лопастей, расходящихся от шарнира на тулье
## веером ±60° с шагом 30°, к краю короче и розовее — гребень-брошка.
## По осмотру рендера лопасти разведены по дуге и укрупнены: подряд стоящие
## слипались в один силуэт за счёт чёрного контура.
static func _shell(hat: Node3D) -> void:
	var hub := SphereMesh.new()
	hub.radius = 0.08
	hub.height = 0.16
	hub.radial_segments = 6
	hub.rings = 3
	var hub_pos := Vector3(0.0, 1.04, -0.12)
	_part(hat, "ShellHub", hub, SHELL_BASE, hub_pos)
	var blade := BoxMesh.new()
	for i: int in 5:
		var angle_deg: float = (i - 2) * 30.0  # −60 … 60, шаг 30°
		var frac: float = absf(angle_deg) / 60.0  # 0 в центре … 1 по краям
		var height: float = 0.55 - frac * 0.14
		var lobe := blade.duplicate() as BoxMesh
		lobe.size = Vector3(0.05, height, 0.12)
		# Лопасть растёт из шарнира: центр на полвысоты вдоль своей оси.
		var dir := Vector3(sin(deg_to_rad(angle_deg)), cos(deg_to_rad(angle_deg)), 0.0)
		var color := SHELL_BASE.lerp(SHELL_EDGE, frac)
		_part(
			hat, "ShellBlade%d" % i, lobe, color,
			hub_pos + dir * (height * 0.5 + 0.02),
			Vector3(0.0, 0.0, -angle_deg),
		)


## Круглые ушки (Knight): два меховых диска по бокам шлема, слегка врозь —
#  суровый шлем и тёплая милота в одном силуэте. Диски достаточно объёмные
#  по глубине, чтобы с бокового ракурса читаться как ушки, а не наклейки.
static func _ears(hat: Node3D) -> void:
	var ear := SphereMesh.new()
	ear.radius = 0.17
	ear.height = 0.34
	ear.radial_segments = 7
	ear.rings = 4
	for side: float in [-1.0, 1.0]:
		var tag := "L" if side < 0.0 else "R"
		var outer := _part(
			hat, "Ear%sOuter" % tag, ear, EARS_FUR,
			Vector3(side * 0.53, 0.86, 0.0), Vector3(0.0, 0.0, side * 18.0),
		)
		outer.scale = Vector3(0.75, 1.0, 0.85)
		var inner := _part(
			hat, "Ear%sInner" % tag, ear, EARS_INNER,
			Vector3(side * 0.575, 0.86, 0.0), Vector3(0.0, 0.0, side * 18.0),
		)
		inner.scale = Vector3(0.5, 0.72, 0.65)
