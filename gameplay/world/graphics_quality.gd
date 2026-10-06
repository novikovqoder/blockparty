# Уровни качества картинки (шаг 4 П4.5; раздел 15 «Простая графика»,
# раздел 16 «Свет и атмосфера»): применяются к Environment и солнцу
# сцены мира. SIMPLE — слабые GPU: без теней и пост-эффектов; NORMAL —
# базовая картинка: мягкие тени, glow огня и маяков, SSAO, дымка по
# высоте; HIGH — то же плюс объёмный туман с локальными сгустками в Лесу
# и у Озера (тяжёлый эффект — только по явному выбору игрока).
# Compatibility-рендерер (скриншоты на сервере) SSAO и объёмный туман не
# поддерживает: свойства выставляются, движок молча пропускает их.
class_name GraphicsQuality
extends RefCounted

enum Tier { SIMPLE, NORMAL, HIGH }

## Радиус зоны локального тумана (Лес, Озеро), м.
const ZONE_FOG_RADIUS: float = 26.0
## Высота локального тумана, м.
const ZONE_FOG_HEIGHT: float = 7.0
## Плотность локального тумана зоны (FogVolume).
const ZONE_FOG_DENSITY: float = 0.035
## Плотность глобального объёмного тумана (HIGH): воздух с лёгкой дымкой.
const VOLUMETRIC_DENSITY: float = 0.005


## Активный уровень из настроек (экран настроек — П8; dev-флаги — Dev).
static func tier_from_settings() -> int:
	if Settings.high_quality:
		return Tier.HIGH
	if Settings.simple_graphics:
		return Tier.SIMPLE
	return Tier.NORMAL


## Тени и пост-эффекты по уровню. Цвет тумана и неба ведёт DayCycle.
static func apply(env: Environment, sun: DirectionalLight3D, tier: int) -> void:
	var full := tier != Tier.SIMPLE
	sun.shadow_enabled = full
	env.ssao_enabled = full
	env.glow_enabled = full
	env.volumetric_fog_enabled = tier == Tier.HIGH
	if env.volumetric_fog_enabled:
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
