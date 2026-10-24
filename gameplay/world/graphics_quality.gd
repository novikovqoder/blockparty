# Уровни качества картинки (шаг 4 П4.5; раздел 15 «Простая графика»,
# раздел 16 «Свет и атмосфера»): применяются к Environment и солнцу
# сцены мира. SIMPLE — слабые GPU: без теней и пост-эффектов; NORMAL —
# базовая картинка: мягкие тени и дымка по высоте; HIGH — то же плюс
# постобработка (блок е vfx-fix: аккуратный glow огня и светлячков, SSAO,
# виньетка) и объёмный туман с локальными сгустками в Лесу и у Озера
# (тяжёлые эффекты — только по явному выбору игрока).
# ULTRA (П11, каркас «меню → мир»): пункт меню выбирается и доезжает до
# мира, но пока применяется как HIGH — полный набор «Ультра»-эффектов
# (SDFGI, SSIL, SSR, тени 8192, SMAA) — отдельный этап ветки bu-gfx.
# Compatibility-рендерер (скриншоты на сервере) SSAO и объёмный туман не
# поддерживает: свойства выставляются, движок молча пропускает их.
class_name GraphicsQuality
extends RefCounted

const VIGNETTE_SHADER: Shader = preload("res://assets/shaders/vignette.gdshader")

enum Tier { SIMPLE, NORMAL, HIGH, ULTRA }

## Меню Born Unblessed хранит настройки в своём cfg (MenuSettingsBU);
## «Качество графики» — int: 0 Низкое, 1 Среднее, 2 Высокое, 3 Ультра
## (DEFAULTS меню — 2, «Высокое»).
const MENU_SAVE_PATH: String = "user://settings_bu.cfg"
const MENU_SECTION: String = "settings"
const MENU_KEY_QUALITY: String = "quality"

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
## всё, кроме огня и светлячков; сила небольшая — «аккуратно».
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


## Активный уровень из настроек (П11): dev-флаги (Settings через Dev —
## --simple-graphics, --high-quality, --ultra-quality) имеют приоритет над
## меню; иначе — пункт «Качество графики» из user://settings_bu.cfg.
## Вызывается редко (вход в мир, повторное применение), поэтому cfg читается
## без кэша — каждое применение видит свежее значение меню.
static func tier_from_settings() -> int:
	if Settings.ultra_quality:
		return Tier.ULTRA
	if Settings.high_quality:
		return Tier.HIGH
	if Settings.simple_graphics:
		return Tier.SIMPLE
	return menu_tier()


## Уровень из пункта меню «Качество графики» (П11, раздел 1.1): Низкое →
## SIMPLE, Среднее → NORMAL, Высокое → HIGH, Ультра → ULTRA. Старый cfg без
## ключа quality — «Высокое», как в DEFAULTS меню; некорректное значение
## (не int или вне 0–3) — тоже «Высокое».
static func menu_tier() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(MENU_SAVE_PATH) != OK:
		return Tier.HIGH
	if not cfg.has_section_key(MENU_SECTION, MENU_KEY_QUALITY):
		return Tier.HIGH
	var value: Variant = cfg.get_value(MENU_SECTION, MENU_KEY_QUALITY)
	if typeof(value) != TYPE_INT:
		return Tier.HIGH
	match value:
		Tier.SIMPLE:
			return Tier.SIMPLE
		Tier.NORMAL:
			return Tier.NORMAL
		Tier.HIGH:
			return Tier.HIGH
		Tier.ULTRA:
			return Tier.ULTRA
	return Tier.HIGH


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
	# ULTRA (П11, каркас) применяется как HIGH: набор «Ультра»-эффектов
	# (SDFGI, SSIL, SSR, тени 8192, SMAA) появляется отдельным этапом.
	var high := tier >= Tier.HIGH
	if viewport != null:
		viewport.texture_mipmap_bias = SIMPLE_MIPMAP_BIAS if tier == Tier.SIMPLE else 0.0
		viewport.msaa_3d = AA_MSAA_HIGH if high else Viewport.MSAA_DISABLED
		viewport.screen_space_aa = (
			Viewport.SCREEN_SPACE_AA_FXAA if high
			else Viewport.SCREEN_SPACE_AA_DISABLED)
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
