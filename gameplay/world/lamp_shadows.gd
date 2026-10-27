# П16 п. 1: тени точечных ламп («факелы» срубов) на HIGH — дёшево.
# Три механизма (SPEC):
#   1) маска кастеров Light3D.shadow_caster_mask (сверено с 4.7.2 —
#      свойство есть, дефолт 0xFFFFFFFF): тень ищется только от объектов
#      со слоем LAMP_CASTER_LAYER — построек и персонажей; трава, мелочь,
#      детальная сетка и пропсы < 0.5 м в тень ламп не попадают;
#   2) shadow_enabled только у HIGH_LAMP_SHADOW_COUNT ближайших к камере
#      ламп (update_nearest; вызывает сцена мира несколько раз в секунду);
#   3) omni_shadow_mode = SHADOW_DUAL_PARABOLOID (сверено с 4.7.2:
#      свойство omni_shadow_mode, константа SHADOW_DUAL_PARABOLOID) —
#      одна карта вместо шести граней куба.
# ULTRA не трогаем: там лампы с тенью у всех, куб, без маски и fade.
class_name LampShadows
extends RefCounted

## Группа всех ламп с тенями (добавляет CabinHouse._add_light).
const LIGHT_GROUP: StringName = &"lamp_light"
## Полная маска кастеров — дефолт движка (возвращаем уходом с HIGH).
const MASK_ALL: int = 0xFFFFFFFF


## Разрешены ли тени ближайших ламп (галочка F3 «Тени ламп» снимает —
## менеджер перестаёт включать тени, снятая срубами гасит всех).
static var enabled: bool = true


## Пометить поддерево как крупный кастер тени ламп: бит слоя 20 всем
## GeometryInstance3D (постройки — меши срубов; персонажи — визуал
## игрока/удалённых). Бит безвреден на уровнях без маски.
static func mark_caster(root: Node) -> void:
	if root is GeometryInstance3D:
		(root as GeometryInstance3D).layers |= \
			GraphicsQuality.LAMP_CASTER_MASK
	for child: Node in root.get_children():
		mark_caster(child)


## Настройка лампы под уровень (вызывает CabinHouse.set_quality):
## high — маска кастеров, dual paraboloid и distance_fade тени ~12 м;
## иначе — движковые дефолты (ULTRA/ниже: уход с HIGH не оставляет
## маску и пароболоид включёнными).
static func setup_light(light: OmniLight3D, high: bool) -> void:
	if high:
		light.shadow_caster_mask = GraphicsQuality.LAMP_CASTER_MASK
		light.omni_shadow_mode = OmniLight3D.SHADOW_DUAL_PARABOLOID
		light.distance_fade_enabled = true
		light.distance_fade_shadow = \
			GraphicsQuality.HIGH_LAMP_FADE_SHADOW
		light.distance_fade_begin = \
			GraphicsQuality.HIGH_LAMP_FADE_BEGIN
		light.distance_fade_length = \
			GraphicsQuality.HIGH_LAMP_FADE_LENGTH
	else:
		light.shadow_caster_mask = MASK_ALL
		light.omni_shadow_mode = OmniLight3D.SHADOW_CUBE
		light.distance_fade_enabled = false


## Тень только у count ближайших к камере ламп (HIGH): сортировка ламп
## группы LIGHT_GROUP по квадрату дистанции, первым count — тень на,
## остальным — прочь. Дёшево (десяток ламп), сцена мира зовёт несколько
## раз в секунду. Галочка F3 «Тени ламп» выключает тень всем лампам
## группы — включая те, что вне сруба (менеджер не выбрасывает чужие).
static func update_nearest(
	parent: Node, camera_pos: Vector3, count: int,
) -> void:
	var lights: Array[OmniLight3D] = []
	for node: Node in parent.get_tree().get_nodes_in_group(LIGHT_GROUP):
		var light := node as OmniLight3D
		if light != null and is_instance_valid(light):
			lights.append(light)
	if not enabled:
		for light: OmniLight3D in lights:
			light.shadow_enabled = false
		return
	lights.sort_custom(func(a: OmniLight3D, b: OmniLight3D) -> bool:
		return a.global_position.distance_squared_to(camera_pos) \
			< b.global_position.distance_squared_to(camera_pos))
	for i: int in lights.size():
		lights[i].shadow_enabled = i < count
