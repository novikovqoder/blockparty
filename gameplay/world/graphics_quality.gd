# Уровни качества картинки (шаг 4 П4.5; раздел 15 «Простая графика»,
# раздел 16 «Свет и атмосфера»): применяются к Environment и солнцу
# сцены мира. SIMPLE — слабые GPU: без теней и пост-эффектов; NORMAL —
# базовая картинка: мягкие тени и дымка по высоте; HIGH — то же плюс
# постобработка (блок е vfx-fix: аккуратный glow огня и светлячков, SSAO,
# виньетка) и объёмный туман с локальными сгустками в Лесу и у Озера
# (тяжёлые эффекты — только по явному выбору игрока).
# ULTRA (П11, раздел 2 SPEC): всё из HIGH плюс SDFGI, SSIL, SSR, мягкие
# тени высокого разрешения, объёмный туман высокого качества и SMAA.
# П13: HIGH — «почти как Ультра, но дешевле» — лёгкий SDFGI и SSIL/SSR
# в половинном разрешении, SMAA без MSAA, атласы 4096, туман 128×64.
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
## Сглаживание «Ультра» (П11 2.7): MSAA 4x плюс SMAA — края без
## «лесенок». П13 1.5: «Высокое» перешло на SMAA без MSAA (MSAA 4x
## упирается в пропускную способность общей памяти встроенной графики);
## обычный и простой уровни — без AA. TAA не включается нигде
## (утверждённые резкие звёзды).
const AA_MSAA_ULTRA: int = Viewport.MSAA_4X

# --- ULTRA (П11, раздел 2 SPEC): числа стартовые, подбирает владелец ---

## SDFGI (2.1): глобальное освещение. Каскадов 4–6 — берём середину;
## окклюзия убирает засветку сквозь стены, небо читается в лепестках
## (read_sky_light), отскок ≈ 0.5 — дважды отражённый свет еле заметен.
const ULTRA_SDFGI_CASCADES: int = 5
const ULTRA_SDFGI_BOUNCE_FEEDBACK: float = 0.5
const ULTRA_SDFGI_ENERGY: float = 1.0
## Ночь остаётся тёмной (2.1): SDFGI светит и под тёмным небом (отскоки
## и накопленный свет), поэтому ночью энергия приглушается — лерп по
## dayness ведёт DayCycle, как у экспозиции. Подбирает владелец.
const ULTRA_SDFGI_NIGHT_ENERGY: float = 0.3
## SSIL (2.2): отражённый свет ближних поверхностей, умеренно.
const ULTRA_SSIL_INTENSITY: float = 1.0
const ULTRA_SSIL_RADIUS: float = 5.0
## SSR (2.3): отражения на гладких поверхностях. Вода Boujie рисует свои
## отражения шейдером (ветка bu-ground-water) — риск двойного отражения
## описан в STATUS.md, саму воду П11 не трогает.
const ULTRA_SSR_MAX_STEPS: int = 64
const ULTRA_SSR_FADE_IN: float = 0.15
const ULTRA_SSR_FADE_OUT: float = 2.0
## Тени (2.5): атлас направленных теней и атлас точечных источников
## (viewport) — по 8192; мягкий фильтр Ultra (полутон у края, а не резкая
## лесенка); у солнца и луны 4 сплита PSSM (дефолт движка, фиксируем),
## угловое расхождение 0.5° — полутень как у реального светила, дальность
## теней 200 м (обычная — 100 м).
const ULTRA_SHADOW_ATLAS_SIZE: int = 8192
const ULTRA_POSITIONAL_ATLAS_SIZE: int = 8192
const ULTRA_SOFT_SHADOW_QUALITY: int = RenderingServer.SHADOW_QUALITY_SOFT_ULTRA
const ULTRA_LIGHT_ANGULAR_DISTANCE: float = 0.5
const ULTRA_SHADOW_MAX_DISTANCE: float = 200.0
## Объёмный туман (2.6): только качество сэмплирования — плотности
## утверждены (VOLUMETRIC_DENSITY, ZONE_FOG_DENSITY), вид не меняется.
const ULTRA_VF_WIDTH: int = 256
const ULTRA_VF_DEPTH: int = 128

# --- HIGH (П13 «Оптимизированное Высокое», Radeon 780M): визуально близко
# --- к ULTRA, но дешевле — числа стартовые, подбирает владелец ---

## Лёгкий SDFGI (П13 1.1): каскадов 3–4 (берём 4), без окклюзии (самый
## дорогой SDFGI-проход), GI в половинном разрешении, лучей меньше
## (8 вместо движковых 16), схождение медленнее (30 кадров вместо 10) и
## реже обновляется свет (16 кадров вместо 2) — шум сходится дольше,
## но каждый кадр дешевле. Ночь ведёт DayCycle той же логикой, что на
## ULTRA (sdfgi_energy по dayness).
const HIGH_SDFGI_CASCADES: int = 4
const HIGH_SDFGI_BOUNCE_FEEDBACK: float = 0.5
const HIGH_SDFGI_RAY_COUNT: int = RenderingServer.ENV_SDFGI_RAY_COUNT_8
const HIGH_SDFGI_FRAMES_TO_CONVERGE: int = \
	RenderingServer.ENV_SDFGI_CONVERGE_IN_30_FRAMES
const HIGH_SDFGI_FRAMES_TO_UPDATE_LIGHT: int = \
	RenderingServer.ENV_SDFGI_UPDATE_LIGHT_IN_16_FRAMES
## Движковые дефолты SDFGI (ProjectSettings 4.7 их не переопределяет):
## в них уход с HIGH возвращает лучи/кадры, ULTRA живёт на них же.
const SDFGI_RAY_COUNT_BASE: int = RenderingServer.ENV_SDFGI_RAY_COUNT_16
const SDFGI_FRAMES_TO_CONVERGE_BASE: int = \
	RenderingServer.ENV_SDFGI_CONVERGE_IN_10_FRAMES
const SDFGI_FRAMES_TO_UPDATE_LIGHT_BASE: int = \
	RenderingServer.ENV_SDFGI_UPDATE_LIGHT_IN_2_FRAMES
## SSIL (П13 1.2): отражённый свет ближних поверхностей, качество Low
## и половинное разрешение (half_size у environment_set_ssil_quality),
## радиус меньше ULTRA.
const HIGH_SSIL_INTENSITY: float = 1.0
const HIGH_SSIL_RADIUS: float = 3.0
const HIGH_SSIL_QUALITY: int = RenderingServer.ENV_SSIL_QUALITY_LOW
## SSR (П13 1.3): шагов 24–32 (берём 32) — лужи и вода не теряют
## отражения; шероховатые отражения — минимальное качество (LOW — он же
## движковый дефолт, хвоста при уходе нет). SSR всегда считается
## в половинном разрешении экрана — отдельного API в 4.7.2 нет.
const HIGH_SSR_MAX_STEPS: int = 32
const HIGH_SSR_FADE_IN: float = 0.15
const HIGH_SSR_FADE_OUT: float = 2.0
## Тени (П13 1.6; П16 п. 2): атласы 4096, фильтр Soft Medium (дешевле
## Ultra), полутень чуть уже ULTRA, дальность 70 м (П16: было 120 — на
## встроенной графике карты сплитов дороже самой геометрии), сплиты с
## плавным растворением (fade_start + blend) — без резкой границы.
## Сплитов 4: трёх в 4.7.2 нет (SHADOW_ORTHOGONAL/2/4 — сверено).
const HIGH_SHADOW_ATLAS_SIZE: int = 4096
## П16 п. 1: атлас точечных теней на HIGH 2048 (тень у 1-2 ближайших
## ламп, dual paraboloid — карты хватает).
const HIGH_POSITIONAL_ATLAS_SIZE: int = 2048
const HIGH_SOFT_SHADOW_QUALITY: int = RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM
const HIGH_LIGHT_ANGULAR_DISTANCE: float = 0.4
const HIGH_SHADOW_MAX_DISTANCE: float = 70.0
const HIGH_SHADOW_FADE_START: float = 0.85
## Объёмный туман (П13 1.7): сетка 128×64 между базой и ULTRA, фильтр
## включён (ставится ниже для всех уровней); плотности не меняются.
const HIGH_VF_WIDTH: int = 128
const HIGH_VF_DEPTH: int = 64
## Трава-буст (П13 1.9): спад густоты травы начинается ближе, чем на
## ULTRA (×1.5) — множитель к базовым fade_start/fade_end шейдера травы.
const HIGH_GRASS_FADE_MULT: float = 0.85
## Параллакс земли (П13 1.9): до ~15 м (на ULTRA — 25, как было);
## дальше параллакс почти не виден, а выборка ORM стоит.
const HIGH_PARALLAX_NEAR: float = 10.0
const HIGH_PARALLAX_FAR: float = 15.0
## База шейдера (движковые значения uniform параллакса, ULTRA).
const PARALLAX_NEAR_BASE: float = 15.0
const PARALLAX_FAR_BASE: float = 25.0
## Тени ламп срубов (П13 1.6; П16 п. 1): на HIGH включены (решает
## LampShadows.update_nearest — максимум HIGH_LAMP_SHADOW_COUNT ближайших
## к камере ламп), гаснут дальше ~12 м (distance_fade тени), сам свет
## живёт до HIGH_LAMP_FADE_BEGIN.
const HIGH_LAMP_FADE_SHADOW: float = 12.0
const HIGH_LAMP_FADE_BEGIN: float = 45.0
const HIGH_LAMP_FADE_LENGTH: float = 15.0
## П16 п. 1: сколько ближайших к камере ламп отбрасывают тень на HIGH
## (SPEC: 1-2, берём 2). ULTRA не трогаем — там тени у всех ламп.
const HIGH_LAMP_SHADOW_COUNT: int = 2
## П16 п. 1: визуальный слой, помечающий «крупных» кастеров тени ламп —
## постройки и персонажей (Light3D.shadow_caster_mask в 4.7.2). Слой 20
## свободен: физические слои проекта — только 1 (мир) и 2 (игроки),
## визуальные слои никем больше не заняты. Трава, мелочь, детальная
## сетка и пропсы < 0.5 м слоя не имеют — тень лампы от них не ищется.
const LAMP_CASTER_LAYER: int = 20
const LAMP_CASTER_MASK: int = 1 << (LAMP_CASTER_LAYER - 1)
## Движковые базы для возврата с HIGH (fade сплитов и смешение).
const SHADOW_FADE_START_BASE: float = 0.1
const BLEND_SPLITS_BASE: bool = false

## База не-«Ультра» (2.10): значения движка 4.7 по умолчанию (проект
## рендер-настройок не перекрывает) — в них возвращает картинку уход
## с ULTRA на HIGH/NORMAL/SIMPLE, чтобы атлас 8192 и Ultra-фильтры
## не оставались включёнными.
const SDFGI_ENERGY_BASE: float = 1.0
const SOFT_SHADOW_QUALITY_BASE: int = RenderingServer.SHADOW_QUALITY_SOFT_LOW
const SHADOW_ATLAS_SIZE_BASE: int = 4096
const POSITIONAL_ATLAS_SIZE_BASE: int = 2048
const PSSM_SPLITS_BASE: int = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
const LIGHT_ANGULAR_DISTANCE_BASE: float = 0.0
const SHADOW_MAX_DISTANCE_BASE: float = 100.0
const SSAO_QUALITY_BASE: int = RenderingServer.ENV_SSAO_QUALITY_MEDIUM
const SSIL_QUALITY_BASE: int = RenderingServer.ENV_SSIL_QUALITY_MEDIUM
const VF_WIDTH_BASE: int = 64
const VF_DEPTH_BASE: int = 64
const MESH_LOD_THRESHOLD_BASE: float = 1.0


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


## Тени и пост-эффекты по уровню (блок е: постобработка — только HIGH;
## П11 раздел 2 — ULTRA добавляет GI, отражения и качество тумана/теней).
## Цвет тумана и неба ведёт DayCycle (ULTRA — ещё и sdfgi_energy по времени
## суток). Viewport (опционально) получает смещение мипов текстур: SIMPLE
## сэмплит из мипа 1K (П5.7 блок 7). Луна (опционально, П5.9 блок 6:
## Sky3D) — те же правила теней, что у солнца: «Простая графика» без
## теней вовсе. RenderingServer-настройки глобальные (атласы, фильтры,
## качество SSAO/SSIL, объём тумана) — ставятся при каждом вызове, поэтому
## уход с ULTRA возвращает их к базе (2.10: «не остаются»).
static func apply(
	env: Environment, sun: DirectionalLight3D, tier: int,
	viewport: Viewport = null, moon: DirectionalLight3D = null
) -> void:
	var ultra := tier == Tier.ULTRA
	# П13-рецепт HIGH: уровень ровно HIGH (постобработка ниже — для HIGH+).
	var hi := tier == Tier.HIGH
	var high := tier >= Tier.HIGH
	# Тени (2.5; П13 1.6): атлас направленных теней, мягкость фильтра,
	# полутень, дальность и плавное растворение сплитов — глобально;
	# у солнца и луны одинаково. База — дефолты движка (PSSM_SPLITS_BASE —
	# как раз 4 сплита; fade_start 0.1, blend выключен).
	RenderingServer.directional_shadow_atlas_set_size(
		ULTRA_SHADOW_ATLAS_SIZE if ultra
		else HIGH_SHADOW_ATLAS_SIZE if hi
		else SHADOW_ATLAS_SIZE_BASE, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(
		ULTRA_SOFT_SHADOW_QUALITY if ultra
		else HIGH_SOFT_SHADOW_QUALITY if hi
		else SOFT_SHADOW_QUALITY_BASE)
	RenderingServer.positional_soft_shadow_filter_set_quality(
		ULTRA_SOFT_SHADOW_QUALITY if ultra
		else HIGH_SOFT_SHADOW_QUALITY if hi
		else SOFT_SHADOW_QUALITY_BASE)
	sun.shadow_enabled = tier != Tier.SIMPLE
	sun.directional_shadow_mode = (
		DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if ultra else PSSM_SPLITS_BASE)
	sun.light_angular_distance = (
		ULTRA_LIGHT_ANGULAR_DISTANCE if ultra
		else HIGH_LIGHT_ANGULAR_DISTANCE if hi
		else LIGHT_ANGULAR_DISTANCE_BASE)
	sun.directional_shadow_max_distance = (
		ULTRA_SHADOW_MAX_DISTANCE if ultra
		else HIGH_SHADOW_MAX_DISTANCE if hi
		else SHADOW_MAX_DISTANCE_BASE)
	# П13 1.6: на HIGH сплиты растворяются плавно (fade_start + blend),
	# без резкой границы на дальности теней.
	sun.directional_shadow_fade_start = (
		HIGH_SHADOW_FADE_START if hi else SHADOW_FADE_START_BASE)
	sun.directional_shadow_blend_splits = (
		true if hi else BLEND_SPLITS_BASE)
	if moon != null:
		moon.shadow_enabled = tier != Tier.SIMPLE
		moon.directional_shadow_mode = sun.directional_shadow_mode
		moon.light_angular_distance = sun.light_angular_distance
		moon.directional_shadow_max_distance = sun.directional_shadow_max_distance
		moon.directional_shadow_fade_start = sun.directional_shadow_fade_start
		moon.directional_shadow_blend_splits = sun.directional_shadow_blend_splits
	if viewport != null:
		viewport.texture_mipmap_bias = SIMPLE_MIPMAP_BIAS if tier == Tier.SIMPLE else 0.0
		# Сглаживание (П13 1.5): ULTRA — MSAA 4x + SMAA; HIGH — только SMAA
		# (MSAA 4x на общей памяти встроенной графики — главный тормоз);
		# NORMAL/SIMPLE — без AA. TAA не включаем ни на одном уровне
		# (владелец утвердил резкое небо и звёзды).
		viewport.msaa_3d = AA_MSAA_ULTRA if ultra else Viewport.MSAA_DISABLED
		viewport.screen_space_aa = (
			Viewport.SCREEN_SPACE_AA_SMAA if high
			else Viewport.SCREEN_SPACE_AA_DISABLED)
		viewport.use_taa = false
		# Детализация (2.8): модели всегда полной детализации (порог
		# переключения LOD — 0 пикселей); атлас теней ламп (2.5, П13 1.6).
		viewport.mesh_lod_threshold = 0.0 if ultra else MESH_LOD_THRESHOLD_BASE
		viewport.positional_shadow_atlas_size = (
			ULTRA_POSITIONAL_ATLAS_SIZE if ultra
			else HIGH_POSITIONAL_ATLAS_SIZE if hi
			else POSITIONAL_ATLAS_SIZE_BASE)
	# Глобальное освещение SDFGI (2.1; П13 1.1 — лёгкий SDFGI на HIGH).
	# Ночью энергию ведёт DayCycle (lerp по dayness), здесь — дневное.
	env.sdfgi_enabled = high
	if ultra:
		env.sdfgi_cascades = ULTRA_SDFGI_CASCADES
		env.sdfgi_use_occlusion = true
		env.sdfgi_read_sky_light = true
		env.sdfgi_bounce_feedback = ULTRA_SDFGI_BOUNCE_FEEDBACK
		env.sdfgi_energy = ULTRA_SDFGI_ENERGY
	elif hi:
		env.sdfgi_cascades = HIGH_SDFGI_CASCADES
		env.sdfgi_use_occlusion = false
		env.sdfgi_read_sky_light = true
		env.sdfgi_bounce_feedback = HIGH_SDFGI_BOUNCE_FEEDBACK
		env.sdfgi_energy = ULTRA_SDFGI_ENERGY
	else:
		env.sdfgi_energy = SDFGI_ENERGY_BASE
	# П13 1.1: GI в половинном разрешении — только на HIGH; ULTRA и база —
	# полное (глобальный флаг, ставится при каждом вызове — без хвостов).
	RenderingServer.gi_set_use_half_resolution(hi)
	# Лучи и кадры SDFGI (П13 1.1): на HIGH дешевле и медленнее, на остальных —
	# движковые дефолты (глобальные, уход с HIGH возвращает их).
	RenderingServer.environment_set_sdfgi_ray_count(
		HIGH_SDFGI_RAY_COUNT if hi else SDFGI_RAY_COUNT_BASE)
	RenderingServer.environment_set_sdfgi_frames_to_converge(
		HIGH_SDFGI_FRAMES_TO_CONVERGE if hi
		else SDFGI_FRAMES_TO_CONVERGE_BASE)
	RenderingServer.environment_set_sdfgi_frames_to_update_light(
		HIGH_SDFGI_FRAMES_TO_UPDATE_LIGHT if hi
		else SDFGI_FRAMES_TO_UPDATE_LIGHT_BASE)
	# SSIL (2.2; П13 1.2) и SSR (2.3; П13 1.3): на ULTRA полноценно,
	# на HIGH — дешевле, ниже HIGH выключены.
	env.ssil_enabled = high
	if ultra:
		env.ssil_intensity = ULTRA_SSIL_INTENSITY
		env.ssil_radius = ULTRA_SSIL_RADIUS
	elif hi:
		env.ssil_intensity = HIGH_SSIL_INTENSITY
		env.ssil_radius = HIGH_SSIL_RADIUS
	env.ssr_enabled = high
	if ultra:
		env.ssr_max_steps = ULTRA_SSR_MAX_STEPS
		env.ssr_fade_in = ULTRA_SSR_FADE_IN
		env.ssr_fade_out = ULTRA_SSR_FADE_OUT
	elif hi:
		env.ssr_max_steps = HIGH_SSR_MAX_STEPS
		env.ssr_fade_in = HIGH_SSR_FADE_IN
		env.ssr_fade_out = HIGH_SSR_FADE_OUT
		# Минимальное качество шероховатых SSR (LOW — движковый дефолт,
		# поэтому на остальных уровнях явно возвращать не нужно).
		RenderingServer.environment_set_ssr_roughness_quality(
			RenderingServer.ENV_SSR_ROUGHNESS_QUALITY_LOW)
	# Качество SSAO/SSIL (2.4; П13 1.2/1.4): Ultra и без полуразрешения
	# на ULTRA; на HIGH SSIL Low и полуразрешение, SSAO — база (Medium,
	# полуразрешение, как было). Остальные аргументы — дефолты движка.
	RenderingServer.environment_set_ssao_quality(
		RenderingServer.ENV_SSAO_QUALITY_ULTRA if ultra else SSAO_QUALITY_BASE,
		not ultra, 0.5, 2, 50.0, 300.0)
	RenderingServer.environment_set_ssil_quality(
		RenderingServer.ENV_SSIL_QUALITY_ULTRA if ultra
		else HIGH_SSIL_QUALITY if hi
		else SSIL_QUALITY_BASE,
		not ultra, 0.5, 2, 50.0, 300.0)
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
	# Качество объёмного тумана (2.6; П13 1.7): сетка плотнее (свет
	# в сгустках зон считается точнее) и фильтр активен; плотности
	# не меняются. HIGH — 128×64, между базой и ULTRA.
	RenderingServer.environment_set_volumetric_fog_volume_size(
		ULTRA_VF_WIDTH if ultra
		else HIGH_VF_WIDTH if hi
		else VF_WIDTH_BASE,
		ULTRA_VF_DEPTH if ultra
		else HIGH_VF_DEPTH if hi
		else VF_DEPTH_BASE)
	RenderingServer.environment_set_volumetric_fog_filter_active(true)
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
