# П16. План «Оптимизированное Высокое» под Radeon 780M

Ветка `born-unblessed` от `7a3cde5`. Цель: 16.9 FPS (GPU 54.9 мс, владелец,
Площадь, 2560×1600, «Высокое», 67 % FSR) → ≥40 FPS (GPU ≤25 мс) при почти
той же картинке. «Ультра» не трогаем (кроме ничего). После каждого блока —
коммит и push.

Сверка API с движком 4.7.2 (headless-пробой ClassDB, уже сделан):

- `Light3D.shadow_caster_mask` — **есть** (дефолт `0xFFFFFFFF`), как и
  `distance_fade_*`, `GeometryInstance3D.gi_mode`,
  `visibility_range_fade_mode`.
- `DirectionalLight3D`: сплиты только `SHADOW_ORTHOGONAL` /
  `SHADOW_PARALLEL_2_SPLITS` / `SHADOW_PARALLEL_4_SPLITS`. **Трёх сплитов
  в 4.7.2 нет** — остаёмся на 4 сплитах с дальностью 70 м и плавным
  растворением (fade_start 0.85 + blend уже включены с П13); в STATUS.
- Окклюдеры: классы `BoxOccluder3D` / `QuadOccluder3D` / `PolygonOccluder3D`
  / `ArrayOccluder3D` (базовый `Occluder3D`), у `OccluderInstance3D` нет
  bake-методов в рантайме — окклюдеры строим программно как ресурсы
  `BoxOccluder3D(size)`; настройка проекта
  `rendering/occlusion_culling/use_occlusion_culling` существует.
- SDFGI: `frames_to_update_light` максимум `...IN_16_FRAMES` — на HIGH
  уже 16 (П13), «реже» некуда; в STATUS.

## Блок 1 (п. 1). Тени ламп — маска кастеров, 2 ближайшие лампы, атлас 2048

- `gameplay/world/graphics_quality.gd`:
  - `HIGH_POSITIONAL_ATLAS_SIZE` 4096 → **2048**;
  - `HIGH_LAMP_FADE_SHADOW` 20 → **12** (тень гаснет дальше ~12 м,
    свет живёт до `HIGH_LAMP_FADE_BEGIN` 45 м как раньше);
  - новые константы: `HIGH_LAMP_SHADOW_COUNT = 2` (тень максимум у двух
    ближайших к камере ламп), `LAMP_CASTER_LAYER = 20`,
    `LAMP_CASTER_MASK = 1 << 19` (слой 20 свободен: физические слои —
    только 1 и 2; визуальные слои ни кем больше не заняты).
- Новый `gameplay/world/lamp_shadows.gd` (RefCounted, static):
  - `mark_caster(root: Node)` — рекурсивно `layers |= LAMP_CASTER_MASK`
    всем `GeometryInstance3D` (постройки, персонажи);
  - `LIGHT_GROUP = &"lamp_light"`; `update_nearest(camera_pos, count)` —
    по группе ламп включает `shadow_enabled` только `count` ближайшим
    (в мировых координатах), остальным выключает; возвращает ничего;
  - `set_light_caster_mask(light, on)` — `shadow_caster_mask` =
    `LAMP_CASTER_MASK` или дефолт (уход с HIGH возвращает всё).
- `gameplay/world/props/cabin_house.gd`:
  - `_add_light` добавляет лампу в группу `lamp_light`;
  - `set_quality(HIGH)`: маска кастеров, `distance_fade_shadow = 12`,
    `shadow_mode = OmniLight3D.SHADOW_MODE_DUAL_PARABOLOID` (1 карта
    вместо 6 куба; ULTRA — как было, CUBE), `shadow_enabled = false` —
    включит менеджер ближайших (по умолчанию тени на HIGH включены —
    после первого апдейта у 2 ближайших ламп);
  - ULTRA/ниже: как сейчас (без маски, без dual paraboloid, уход с HIGH
    возвращает дефолт маски и режима);
  - меши дома (EXT_/TERRACE) помечаются `LampShadows.mark_caster`.
- `scenes/world_scene.gd`: в `_process` раз в 0.25 с на HIGH —
  `LampShadows.update_nearest(cam_pos, HIGH_LAMP_SHADOW_COUNT)`;
  после спавна игрока и появления RemotePlayer — `mark_caster` их визуала.
- `ui/debug_panel.gd`: галочка «lamps» off глушит и менеджер (лампы не
  включатся сами), on — менеджер снова работает.
- Тесты (`tests/test_gfx_p16.gd`, часть 1): у лампы на HIGH
  `shadow_caster_mask == LAMP_CASTER_MASK` и слой не совпадает с layers
  травы/мелочи; в дереве с ≥3 лампами после `update_nearest` с тенью
  максимум 2 и это ближайшие; `distance_fade_shadow == 12`; атлас 2048;
  на ULTRA маска дефолтная и dual paraboloid выключен.

## Блок 2 (п. 2). Тени солнца/луны — OFF мелочи на HIGH, дальность 70 м

- `graphics_quality.gd`: `HIGH_SHADOW_MAX_DISTANCE` 120 → **70**
  (в диапазоне 60–80 из SPEC); сплиты — 4 (трёх в 4.7.2 нет, STATUS).
- `gameplay/world/props/prop_meshes.gd`: новая
  `static func small_shadowless(type: StringName, tier: int) -> bool` —
  трава и мелкие типы (`rgrass`, `rflower`, `riris`, `reed`, `fern`,
  `mrock`, `pebble`, `etree_bush`) и всё `gd_grass_*` на HIGH без тени
  солнца; деревья/постройки/валуны — с тенью как раньше.
- `gameplay/world/island_view.gd` (`_build_props`, `_build_tree_lods`
  без изменений, `_build_details`): `cast_shadow = OFF` на HIGH у типов
  из `small_shadowless`; печёные группы — по уровню входа в мир (как
  тени мелочи П14), `set_quality` тени не переключает.
- Мелочь `gc_*` и детальная сетка — уже OFF с П14 (не трогаем).
- Тесты: на HIGH у перечисленных типов `cast_shadow == OFF`, у деревьев
  и построек ON; ULTRA — у всех как раньше (трава с тенью); дальность
  теней HIGH == 70; ULTRA `directional_shadow_max_distance` не изменился.

## Блок 3 (п. 3). Детальная сетка — сдвиг реже, радиус 12 м

- `gameplay/world/terrain_detail.gd`: `RADIUS_HIGH` 16 → **12**
  (ULTRA 24 не трогаем).
- `island_view.gd`: новый порог `RING_MOVE_MIN_M = 1.5` — нода кольца
  сдвигается только когда снапнутый центр ушёл от места последней
  установки ≥1.5 м (сейчас — присвоение каждый кадр); тень кольца уже
  OFF с П14.
- Тесты: `update_viewer` со сдвигом 0.5 м не меняет `position` кольца,
  сдвиг 2 м — меняет; радиус HIGH == 12, ULTRA == 24.

## Блок 4 (п. 4). Трава и мелочь — дальность на HIGH меньше, fade

- Alpha scissor: уже выполняется — листва `canopy.gdshader` пишет
  `ALPHA_SCISSOR_THRESHOLD` (+ `depth_draw_opaque`), трава/мелочь —
  геометрия без альфы вовсе, eztree-материалы задают `alpha_cut`
  (scissor). Alpha-канал травы/мелочи не появляется — «без alpha blend»
  держим тестом по исходникам шейдеров.
- `island_view.gd` `set_quality`: для `gd_grass_*` дальность =
  база × (1.5 ULTRA / **0.85** HIGH / 1.0) — согласовано со спадом травы
  ×0.85 (граница MultiMesh чуть дальше, чем травинки садятся в землю);
  для мелочи наполнения (`gd_stones`, `gd_root`, `gd_branch`,
  `gd_debris`, `gd_fern`) — база × (1.5 / **0.8** / 1.0); у всех
  перечисленных `visibility_range_fade_mode = FADE` (мягкое исчезновение).
- Плотность мелочи на HIGH не меняем (уже ½ ULTRA с П14; точечное
  урезание — по авто-замеру владельца, см. блок 8).
- Тесты: на HIGH `visibility_range_end` у `gd_grass_*` и мелочи меньше
  ULTRA-значения и базы; fade_mode == FADE; в шейдерах растительности нет
  `alpha_blend`/`blend_mix` у травы (scissor только в canopy).

## Блок 5 (п. 5). Occlusion culling

- `project.godot`: `[rendering] occlusion_culling/use_occlusion_culling=true`.
- `cabin_house.gd`: к каждому срубу — `OccluderInstance3D` с
  `BoxOccluder3D` по габариту корпуса (AABB мешей EXT_* минус интерьер,
  чуть уменьшенный, чтобы не съедать видимость из окон) — ставится в
  `_build`, живёт на всех уровнях (дёшев).
- `island_view.gd`: статик `_add_occluder_box(parent, pos, size, yaw)` +
  расстановка по данным запечённого острова:
  - стены/башни руин (`ruin_tower`, `ruin_arch`, `ruin_column`,
    `rock_wall`) — по трансформам групп из `art.prop_groups`;
  - крупные валуны наполнения (`gd_boulder02/03`, `gd_stump01/02`,
    масштаб ≥1.0) — по трансформам из `GroundDetails.build`.
- `prop_meshes.gd` `visibility_range`: дальности мелким типам, у которых
  сейчас 0 (всегда видны): `bench` 70, `boat` 120, `dead_log` 90,
  `log_bridge` 110, `campfire_seat` 60; деревья/валуны/постройки —
  по-прежнему всегда (силуэт острова).
- Тесты: настройка проекта включена; у каждого сруба есть
  OccluderInstance3D с BoxOccluder3D; число окклюдеров руин > 0 и у всех
  размер > 1 м; новые дальности мелких типов < ∞.

## Блок 6 (пп. 6–7). SDFGI и туман

- `graphics_quality.gd`:
  - `HIGH_SDFGI_CASCADES` 4 → **3**;
  - обновление света — уже 16 кадров (максимум в 4.7.2; STATUS);
  - «чтение отражений SDFGI там, где SSR» — отдельного тумблера в
    4.7.2 нет (SSR в форварде фолбэчится на SDFGI/пробы, раздельного
    включения движок не даёт; STATUS);
  - `HIGH_VF_WIDTH/DEPTH` 128/64 → **96/48**.
- Тесты: каскады HIGH == 3 (ULTRA 5 не тронут); туман HIGH 96×48,
  дешевле ULTRA 256×128 и дороже базы 64×64.

## Блок 7 (п. 8). Оранжевый пересвет у скамеек и тонких досок

Причина по коду: вокруг Площади — три сруба с лампами-фонарями
(материал `lamp`: emission тёплый (1.0, 0.8, 0.5) × 2.2) и камень
возрождения прямо на Площади (RespawnStone1 в (0.5, 2, 12.5), glow
`lamp_glow` × 1.5), плюс HangPoint'ы (glow `firefly` × 2.0). SDFGI
захватывает emission в воксели → тёплый оранжевый отскок; доски скамей
(4.5 см) и навеса (5.5 см) тоньше вокселя SDFGI — отскок «протекает»
на них, отсюда пересвет именно у тонких деревянных деталей.

Фикс (дёшево, вид не меняет — излучение видно как раньше):

- `cabin_house.gd`: мешам с материалом `lamp` — `gi_mode =
  GeometryInstance3D.GI_MODE_DISABLED` (не вкладываются в SDFGI);
- `respawn_stone.gd`, `activities/hang_point.gd`: то же для меша Glow;
- если владельцу мало (замер после сборки) — вариант №2: включить
  `sdfgi_use_occlusion` на HIGH (самый дорогой проход SDFGI) — за рамками
  этого блока, только по запросу (STATUS).
- Тесты: у мешей lamp/Glow `gi_mode == GI_MODE_DISABLED`; emission
  материалов не тронут.

## Блок 8 (пп. 9–10). F3: авто-замер эффектов + галочка окклюзии

- `ui/debug_panel.gd`:
  - кнопка «Замер эффектов» на вкладке эффектов: последовательно
    (порядок `EFFECTS`) выключает эффект на `MEASURE_STEP_SEC` 4 с
    (последние 2 с — сбор среднего GPU-мс через уже включённый
    `viewport_get_measured_render_time_gpu`), включает обратно; в конце
    — отсортированный по экономии отчёт (имя, GPU-мс на эффекте, база,
    −мс) в буфер обмена; кнопка на время прогона блокируется;
  - новая галочка «Occlusion» (`&"occl"`): `use_occlusion_culling`
    корневого viewport на лету;
  - `EFFECT_LABELS`/`i18n/strings_bu.csv`: `BU_DBG_AUTOMEASURE`,
    `BU_DBG_OCCL` (+ ru/en).
- Тесты: кнопка и галочка есть; замер обходит все `EFFECTS` и строит
    отсортированный отчёт (окно замера сузим в тесте константой);
    галочка occl переключает viewport и возвращается.

## Блок 9. Тесты, STATUS, сборка

- `tests/test_gfx_p16.gd` — все тесты SPEC П16 (перечислены в блоках);
  правка `tests/test_gfx_high.gd` под новые числа HIGH (70 м, 2048,
  каскады 3, туман 96×48, fade ламп 12); `test_gfx_ultra.gd` не трогаем
  (рецепт ULTRA не изменился — держится существующими тестами).
- Полный GUT зелёный, счёт в отчёт.
- `--selftest-anim` на экспортированной Linux-сборке (этап касается
  персонажей: visual layers героев — по правилу «неясно → считаем
  относящимся»).
- `docs/STATUS.md`: таблица «что изменено на HIGH / ожидаемая экономия /
  что не тронуто», известные ограничения (3 сплита нет, update light 16
  — максимум, отражения SDFGI без отдельного тумблера).
- Пересборка `builds/born-unblessed-windows.zip` с нуля (`unzip -t`,
  sha256), дерево чистое, коммит+push, стоп и короткий отчёт.

## Не трогаем

ULTRA-рецепт, героя (кроме visual layers теней), анимации, вид земли
и воды, небо, туман по виду (только размер сетки), аддоны. Замеров и
съёмок на сервере нет (меряет владелец через F3).
