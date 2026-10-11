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
## Плотность локального тумана зоны (FogVolume).
const ZONE_FOG_DENSITY: float = 0.035
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


## Активный уровень из настроек (экран настроек — П8; dev-флаги — Dev).
static func tier_from_settings() -> int:
	if Settings.high_quality:
		return Tier.HIGH
	if Settings.simple_graphics:
		return Tier.SIMPLE
	return Tier.NORMAL


## Тени и пост-эффекты по уровню (блок е: постобработка — только HIGH).
## Цвет тумана и неба ведёт DayCycle.
static func apply(env: Environment, sun: DirectionalLight3D, tier: int) -> void:
	sun.shadow_enabled = tier != Tier.SIMPLE
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


## Локальный сгусток тумана зоны (шаг 4: «лёгкий объёмный туман в Лесу
## и у Озера»). Работает только при volumetric_fog_enabled (HIGH).
static func make_zone_fog(center: Vector3, color: Color) -> FogVolume:
	var volume := FogVolume.new()
	var material := FogMaterial.new()
	material.density = ZONE_FOG_DENSITY
	material.albedo = color
	volume.material = material
	volume.size = Vector3(
		ZONE_FOG_RADIUS * 2.0, ZONE_FOG_HEIGHT, ZONE_FOG_RADIUS * 2.0
	)
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
