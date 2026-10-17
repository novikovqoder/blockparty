# Уровни качества картинки (шаг 4 П4.5; раздел 15 «Простая графика»,
# раздел 16 «Свет и атмосфера»): применяются к Environment и солнцу
# сцены мира. SIMPLE — слабые GPU: без теней и пост-эффектов; NORMAL —
# базовая картинка: мягкие тени и дымка по высоте; HIGH — то же плюс
# постобработка (блок е vfx-fix: аккуратный glow огня и маяков, SSAO,
# виньетка) и объёмный туман с локальными сгустками в Лесу и у Озера
# (тяжёлые эффекты — только по явному выбору игрока).
# Compatibility-рендерер (скриншоты на сервере) SSAO и объёмный туман не
# поддерживает: свойства выставляются, движок молча пропускает их.
class_name GraphicsQuality
extends RefCounted

const VIGNETTE_SHADER: Shader = preload("res://assets/shaders/vignette.gdshader")

enum Tier { SIMPLE, NORMAL, HIGH }

## Радиус зоны локального тумана (Лес, Озеро), м.
const ZONE_FOG_RADIUS: float = 26.0
## Высота локального тумана, м.
const ZONE_FOG_HEIGHT: float = 7.0
## Плотность локального тумана зоны (FogVolume). Доработка под эталон
## («туман небольшой, всё читается»): 0.035 при 30 м пути сквозь сгусток
## давало ~65% тумана — кроны в глубине тонули; 0.02 — та же стелющаяся
## дымка при читаемых дальних деревьях.
const ZONE_FOG_DENSITY: float = 0.02
## Плотность глобального объёмного тумана (HIGH): воздух с лёгкой дымкой.
const VOLUMETRIC_DENSITY: float = 0.005
## Glow (блок е): SOFTLIGHT не выбеливает картинку, порог bloom отсекает
## всё, кроме огня, лампы маяка и светлячков; сила небольшая — «аккуратно».
const GLOW_INTENSITY: float = 0.6
const GLOW_STRENGTH: float = 1.05
const GLOW_BLOOM: float = 0.55
## SSAO (блок е): мягкие контактные тени у камней и под деревьями.
const SSAO_INTENSITY: float = 1.6
const SSAO_RADIUS: float = 1.5
## Вклад солнца в объёмный туман (П5.7 блок 3): заметнее лучи сквозь кроны
## и длинные световые столбы на закате (по умолчанию у света — 1.0).
const SUN_FOG_ENERGY: float = 1.4
## Смещение мипов текстур в «Простой графике» (П5.7 блок 7): +1 сэмплит
## текстуры 2K из мипа 1K — дешевле выборки при том же виде (SPEC п. 7:
## «текстуры 1K»).
const SIMPLE_MIPMAP_BIAS: float = 1.0
## Доля обычной дистанции LOD персонажей в «Простой графике» (П5.7 блок 7):
## облегчённые копии включаются заметно ближе (18 м → ~8 м).
const CHARACTER_LOD_FACTOR: float = 0.45
## Сглаживание «Высокого качества» (планка качества П5.9): MSAA 4x плюс
## FXAA — края без «лесенок» (TAA недоступен в Compatibility-рендерере,
## на котором снимаются серверные скриншоты). Обычный и простой уровни —
## без AA: планка требует сглаживания именно в «Высоком качестве».
const AA_MSAA_HIGH: int = Viewport.MSAA_4X


## Активный уровень из настроек (экран настроек — П8; dev-флаги — Dev).
static func tier_from_settings() -> int:
	if Settings.high_quality:
		return Tier.HIGH
	if Settings.simple_graphics:
		return Tier.SIMPLE
	return Tier.NORMAL


## Тени и пост-эффекты по уровню (блок е: постобработка — только HIGH).
## Цвет тумана и неба ведёт DayCycle. Viewport (опционально) получает
## смещение мипов текстур: SIMPLE сэмплит из мипа 1K (П5.7 блок 7).
## Луна (опционально, П5.9 блок 6: Sky3D) — те же правила теней, что у
## солнца: «Простая графика» без теней вовсе.
static func apply(
	env: Environment, sun: DirectionalLight3D, tier: int,
	viewport: Viewport = null, moon: DirectionalLight3D = null
) -> void:
	sun.shadow_enabled = tier != Tier.SIMPLE
	if moon != null:
		moon.shadow_enabled = tier != Tier.SIMPLE
	if viewport != null:
		viewport.texture_mipmap_bias = SIMPLE_MIPMAP_BIAS if tier == Tier.SIMPLE else 0.0
		viewport.msaa_3d = AA_MSAA_HIGH if tier == Tier.HIGH \
			else Viewport.MSAA_DISABLED
		viewport.screen_space_aa = (
			Viewport.SCREEN_SPACE_AA_FXAA if tier == Tier.HIGH
			else Viewport.SCREEN_SPACE_AA_DISABLED)
	var high := tier == Tier.HIGH
	env.ssao_enabled = high
	if high:
		env.ssao_intensity = SSAO_INTENSITY
		env.ssao_radius = SSAO_RADIUS
	env.glow_enabled = high
	if high:
		env.glow_intensity = GLOW_INTENSITY
		env.glow_strength = GLOW_STRENGTH
		env.glow_bloom = GLOW_BLOOM
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.volumetric_fog_enabled = high
	if high:
		env.volumetric_fog_density = VOLUMETRIC_DENSITY
	# Лучи сквозь кроны (П5.7 блок 3): вклад солнца в объёмный туман
	# заметнее дефолтного — световые столбы между деревьями.
	sun.light_volumetric_fog_energy = SUN_FOG_ENERGY if high else 1.0


## Дистанция переключения LOD персонажей по уровню (П5.7 блок 7): «Простая
## графика» приближает облегчённые копии (SPEC п. 7), остальные уровни
## оставляют базовую дистанцию модели.
static func character_lod_distance(base: float) -> float:
	return base * CHARACTER_LOD_FACTOR if tier_from_settings() == Tier.SIMPLE else base


## Локальный сгусток тумана зоны (шаг 4: «лёгкий объёмный туман в Лесу
## и у Озера»; П5.7 блок 3: у Леса радиус больше — зона широкая). Работает
## только при volumetric_fog_enabled (HIGH).
static func make_zone_fog(
	center: Vector3, color: Color, radius: float = ZONE_FOG_RADIUS
) -> FogVolume:
	var volume := FogVolume.new()
	var material := FogMaterial.new()
	material.density = ZONE_FOG_DENSITY
	material.albedo = color
	volume.material = material
	volume.size = Vector3(radius * 2.0, ZONE_FOG_HEIGHT, radius * 2.0)
	# Центр бокса — над землёй зоны, чуть утоплен, чтобы дымка «стелилась».
	volume.position = center + Vector3.UP * (ZONE_FOG_HEIGHT * 0.5 - 1.0)
	return volume


## Полноэкранный слой виньетки (блок е): шейдер затемняет углы, мышиные
## события проходят насквозь. Добавлять до HUD — интерфейс поверх.
static func make_vignette() -> ColorRect:
	var rect := ColorRect.new()
	rect.name = "Vignette"
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = VIGNETTE_SHADER
	rect.material = material
	return rect
