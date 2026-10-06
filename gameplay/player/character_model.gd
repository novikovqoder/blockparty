# Модель персонажа игрока (раздел 16 SPEC, v2.3): одна из трёх моделей
# CC0-набора KayKit Adventurers (автор Kay Lousberg, лицензия CC0 —
# assets/third_party/LICENSES.md) на общем риге Rig_Medium.
# Что делает setup(character):
# - инстансит glb (точка опоры glb уже у ступней) и масштабирует так, чтобы
#   макушка головы встала на HEAD_TOP_Y — рост подогнан под коллизию игрока
#   (капсула из раздела 5), управление и физика не меняются;
# - вокруг каждого меша строит мультяшный чёрный контур (обратная оболочка:
#   близнец-меш расширяется вдоль нормалей и рисуется задними гранями,
#   без прозрачности — assets/shaders/outline.gdshader);
# - к кости head крепит фирменный процедурный головной убор (CharacterHat).
# Цвет тела по хэшу id (шаг 3) и скелетные анимации KayKit (шаг 4) —
# следующие шаги; интерфейс setup_palette/set_state/play_one_shot уже здесь,
# чтобы player.gd и remote_player.gd не переключали класс второй раз.
class_name CharacterModel
extends Node3D

## glb-модели персонажей (0 — Knight, 1 — Mage, 2 — Ranger).
const GLBS: PackedStringArray = [
	"res://assets/third_party/kaykit/adventurers/Knight.glb",
	"res://assets/third_party/kaykit/adventurers/Mage.glb",
	"res://assets/third_party/kaykit/adventurers/Ranger.glb",
]
## Фирменный убор по персонажу (раздел 16: круглые ушки, ракушка-веер,
## росток с двумя листиками).
const HATS: Array[int] = [
	CharacterHat.Kind.EARS,
	CharacterHat.Kind.SHELL,
	CharacterHat.Kind.SPROUT,
]
## Целевая высота макушки головы, м — как HeadTop в player.tscn
## и remote_player.gd (коллизия капсулы игрока до 1.6 м).
const HEAD_TOP_Y: float = 1.65
## Толщина чёрного контура в метрах (после масштаба модели).
const OUTLINE_WIDTH: float = 0.022
## Кость крепления убора (риг KayKit Rig_Medium, имена в нижнем регистре).
const HEAD_BONE: String = "head"
## Число цветовых вариантов тела (шаг 3: выдаётся по хэшу id).
const PALETTES: int = 6

const OUTLINE_SHADER: Shader = preload("res://assets/shaders/outline.gdshader")

## Номер персонажа (0…GLBS.size()−1), фиксируется в setup.
var character: int = 0

var _glb_root: Node3D = null
var _skeleton: Skeleton3D = null
var _scale: float = 1.0
var _outline: ShaderMaterial = null


## Номер персонажа по хэшу id: один id — всегда один цвет и один ремоут-вариант.
## absi — id бывает отрицательным (peer id ENet); по сети ничего не передаётся.
static func palette_index(id: int) -> int:
	return absi(id) % PALETTES


static func count() -> int:
	return GLBS.size()


## Номер персонажа вне диапазона → 0 (то же правило применяет хост к номеру
## из сети, раздел 10 SPEC).
static func valid_index(p_character: int) -> int:
	return p_character if p_character >= 0 and p_character < GLBS.size() else 0


## Построить модель персонажа; вне диапазона — первый.
func setup(p_character: int) -> void:
	character = valid_index(p_character)
	if _glb_root != null:
		_glb_root.queue_free()
	var scene := load(GLBS[character]) as PackedScene
	_glb_root = scene.instantiate() as Node3D
	add_child(_glb_root)
	_skeleton = _find_skeleton(_glb_root)
	# Контур зависит от масштаба модели — материал свой у каждого экземпляра.
	_outline = ShaderMaterial.new()
	_outline.shader = OUTLINE_SHADER
	_apply_fit_scale()
	_outline_pass(_glb_root)
	_attach_hat()


## Цвет тела по хэшу id (шаг 3: перекраска текстуры/материалов). До шага 3
## модель носит родные цвета KayKit.
func setup_palette(_id: int) -> void:
	pass


## Сетевое состояние анимации (Protocol.AnimState) — скелетные клипы KayKit
## подключаются шагом 4; до него модель в позе glb.
func set_state(_state: int) -> void:
	pass


## Разовая анимация (взмах и т.п.) — шаг 4.
func play_one_shot(_state: int, _duration: float) -> void:
	pass


## Макушка головы с учётом масштаба, м (только исходные меши, без контура).
func head_top_height() -> float:
	var top := 0.0
	for node in _glb_root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if _is_outline(mi) or not (mi.name as String).ends_with("_Head"):
			continue
		top = maxf(top, _mesh_box(mi).end.y)
	return top


## Нижняя точка модели (ступни), м — только исходные меши.
func lowest_point() -> float:
	var bottom := 0.0
	for node in _glb_root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if _is_outline(mi):
			continue
		bottom = minf(bottom, _mesh_box(mi).position.y)
	return bottom


## AABB меша в координатах модели: glb-меши стоят в origin скелета, а части
## убора — центрированные примитивы в собственных position/scale узла.
func _mesh_box(mi: MeshInstance3D) -> AABB:
	var to_model := global_transform.affine_inverse()
	return to_model * (mi.global_transform * mi.mesh.get_aabb())


## Число контурных близнецов (по одному на меш).
func outline_count() -> int:
	var found := 0
	for node in _glb_root.find_children("*", "MeshInstance3D", true, false):
		if (node as MeshInstance3D).name.ends_with("Outline"):
			found += 1
	return found


## Узор убора (для тестов): узел Hat с мета kind, или null.
func hat() -> Node3D:
	if _skeleton == null:
		return null
	return _skeleton.get_node_or_null("HatAnchor/Hat")


func _apply_fit_scale() -> void:
	# Масштаб по верху меша *_Head: у KayKit верх головы 2.16–2.28 при
	# ногах на y=0; шляпы выше — декор поверх HEAD_TOP_Y. Так головы всех
	# персонажей на одной высоте (ник, коллайдер головы) при разных шляпах.
	# glb-меши в origin скелета — aabb.end.y без трансформа узла.
	var top := 0.0
	for node in _glb_root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if not _is_outline(mi) and (mi.name as String).ends_with("_Head"):
			top = maxf(top, mi.mesh.get_aabb().end.y)
	assert(top > 1.0, "меш головы не найден: некуда подгонять рост")
	_scale = HEAD_TOP_Y / top
	_glb_root.scale = Vector3.ONE * _scale
	# Толщина контура задана в метрах готовой модели — в локали меша она
	# больше во столько же, во сколько модель уменьшена.
	_outline.set_shader_parameter("thickness", OUTLINE_WIDTH / _scale)


func _outline_pass(root: Node) -> void:
	# Близнец кладётся тому же родителю: относительный skeleton NodePath
	# («..») остаётся валидным, скиннинг работает, трансформ копируется.
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if _is_outline(mi) or mi.has_meta("outlined"):
			continue
		mi.set_meta("outlined", true)
		var twin := MeshInstance3D.new()
		twin.name = String(mi.name) + "Outline"
		twin.mesh = mi.mesh
		twin.skeleton = mi.skeleton
		twin.material_override = _outline
		twin.transform = mi.transform
		twin.set_meta("outlined", true)
		mi.get_parent().add_child(twin)


func _attach_hat() -> void:
	if _skeleton == null or _skeleton.find_bone(HEAD_BONE) < 0:
		push_warning("CharacterModel: кость %s не найдена — убор не закреплён" % HEAD_BONE)
		return
	var anchor := BoneAttachment3D.new()
	anchor.name = "HatAnchor"
	anchor.bone_name = HEAD_BONE
	_skeleton.add_child(anchor)
	var hat := CharacterHat.build(HATS[character])
	anchor.add_child(hat)
	_outline_pass(hat)


func _find_skeleton(root: Node) -> Skeleton3D:
	for node in root.find_children("*", "Skeleton3D", true, false):
		return node as Skeleton3D
	return null


static func _is_outline(mi: MeshInstance3D) -> bool:
	return (mi.name as String).ends_with("Outline")
