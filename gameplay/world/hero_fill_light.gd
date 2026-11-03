# П17 п.11: заполняющий «свет персонажа» — герой читается в тени (одежда
# Born Unblessed темная: люминанс альбедо плаща/капюшона ~0.04, аудит
# tools/dump_hero_materials.gd). Мягкий DirectionalLight3D со стороны
# камеры, БЕЗ теней, светит ТОЛЬКО слой персонажей (light_cull_mask):
# мир на этот слой не назначается — свет не касается рельефа и построек.
# Ночью слабее (ведётся dayness, как ambient). Свет дешёвый — на всех
# уровнях качества; базу силы подбирает владелец константой ниже.
class_name HeroFillLight
extends DirectionalLight3D

## Слой визуала персонажей (бит 10): единственный в маске света. Помечается
## героям (HeroModelBU._ready), чужим игрокам и мешу меча при появлении.
const LAYER_MASK: int = 1 << 9

## Базовая сила днём (≈0.5 полуденного солнца из Balance; подбор — владелец).
const HERO_FILL_ENERGY: float = 0.15
## Доля силы глубокой ночью: герой читается и в темноте, но ночь остаётся
## тёмной.
const NIGHT_FACTOR: float = 0.35
## Слегка тёплый нейтральный тон — без подсинивания теней персонажа.
const FILL_COLOR: Color = Color(1.0, 0.97, 0.93)


func _init() -> void:
	shadow_enabled = false
	light_cull_mask = LAYER_MASK
	light_color = FILL_COLOR
	light_energy = HERO_FILL_ENERGY


## Пометить поддерево как получатель fill-света (герой, чужой игрок, меч):
## бит слоя всем GeometryInstance3D. Бит безвреден там, где света нет
## (по образцу LampShadows.mark_caster).
static func mark_visual(root: Node) -> void:
	if root is GeometryInstance3D:
		(root as GeometryInstance3D).layers |= LAYER_MASK
	for child: Node in root.get_children():
		mark_visual(child)


## Направление со стороны камеры (чуть сверху — заполняющий, не контровой)
## и сила по времени суток. Вызывает сцена мира каждый кадр; для
## DirectionalLight3D важен только поворот, позиция условная.
func update(cam_pos: Vector3, target: Vector3) -> void:
	global_position = cam_pos + Vector3.UP * 4.0
	if global_position.distance_squared_to(target) > 1.0:
		look_at(target + Vector3.UP * 1.2, Vector3.UP)
	light_energy = HERO_FILL_ENERGY * lerpf(
		NIGHT_FACTOR, 1.0, DayMath.dayness(Session.world_time))
