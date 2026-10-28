# План П15-ДОП «Вода по туториалу»

Ветка `born-unblessed`. Ориентир — туториал gameidea.org «Creating a Stylized
3D Water Shader» (локальная копия: `TUTORIAL_gameidea_water.html`, рядом).
Берём подход туториала почти целиком; всё, чего в нём нет (движковое
отражение неба, SSR-френель, мягкая кромка, круги вокруг ног, дешёвый
шейдер), сохраняем. Землю, героя, небо, туман, коллизию не трогаем.
Рецепт ULTRA не меняем. Аддоны не ставим.

## Что меняется в принципе

Герстнер (спектр 32 волн, RNG) заменяется на волны туториала `sea_octave`
(value-noise октавы: острые гребни, плоские впадины). Спектр
`waves_a/waves_b/wave_count` и его генератор `wave_spectrum()` уходят
целиком. Вместо них 4 параметра зоны (height / choppiness / speed /
frequency), у озера и моря — свои константы.

Хеш высот острова (test_water3 `HEIGHTS_CHECKSUM = 2041845998`) не зависит
от воды — обязан сохраниться.

## Файлы

| Файл | Что делаем |
| --- | --- |
| `assets/shaders/water_bu.gdshader` | блоки 1–4: волны sea_octave, пена Вороным, цвет/Бер/преломление/каустика по туториалу, наше — сохранено |
| `assets/shaders/water_bu_cheap.gdshader` | блоки 1, 4: те же волны (3 октавы vertex + 3 fragment), без экранной выборки |
| `gameplay/world/water_area.gd` | константы волн и пресетов, пресеты цвета, сеттеры, удаление `wave_spectrum` |
| `ui/debug_panel.gd` | ползунки height/choppiness/speed/frequency + пена (кромка, пузырьки), переключатель пресетов, «Скопировать значения» |
| `i18n/strings_bu.csv` | новые ключи BU_W_*, удаление упразднённых |
| `tests/test_water3.gd` | строковые проверки под новый шейдер, пресеты, ползунки, чексумма |
| `tests/test_ground_water2.gd` | тесты спектра → тесты параметров волн по уровням |
| `tests/test_island_scene.gd` | чтение `waves_a` → проверка амплитуды через `sea_height` |
| `tools/probe_water_shader.gd`, `tools/probe_water_shaders.gd` | перевод на новые uniform'ы |
| `docs/STATUS.md` | итог этапа |

## Блок 1 — волны sea_octave (коммит)

`water_bu.gdshader`:
- Убрать: `waves_a[32]`, `waves_b[32]`, `wave_count`, `VERTEX_WAVE_M`
  (вершины смещают все геометрические октавы), `wave_weight()` для волн
  (пиксельная фильтрация волн теперь — через шаг eps по дистанции);
  `snoise` остаётся (рябь, круги, каустика).
- Добавить функции туториала: `hash12`, `vnoise` (value noise 2D),
  `sea_octave`, `map_geometry` (ITER_GEOMETRY = 3), `map_detailed`
  (ITER_FRAGMENT), `get_normal_detailed` (конечные разности).
- Uniform'ы группы Waves: `sea_height`, `sea_choppiness`, `sea_speed`,
  `sea_freq`, `iter_fragment` (int). `const mat2 octave_m` — как в туториале.
- `vertex()`: смещение `VERTEX.y` от `map_geometry` × гашение вдали
  (`vertex_wave_fade` — наше, грубые внешние кольца Ocean) + нормаль
  геометрии конечными разностями (varying `vertex_normal_world`).
- `fragment()`: нормаль = `get_normal_detailed(world_pos, eps, TIME)`,
  `eps = max(normal_epsilon, dist · 0.005)` — шаг растёт с расстоянием
  (детали гаснут плавно, мерцания вдали нет); вдали `smooth_factor`
  смешивает с `vertex_normal_world` (как в туториале). Наш `lost`
  (roughness вблизи/вдали) считаем от `smooth_factor` + гашения ряби —
  схема «зеркало вблизи, матовое у горизонта» сохраняется.
- Рябь и круги — как сейчас, поверх новой нормали.

`water_bu_cheap.gdshader`: те же функции, 3 октавы и в vertex, и во
fragment (const), остальное — без изменений (вуаль, ALPHA 0.82).

`water_area.gd`:
- Удалить: `MAX_WAVES`, `SEED_WAVES`, `WIND_DIR_DEG`, `DIR_SPREAD_*`,
  `LAKE_LEN`, `SEA_SWELL_LEN`, `SEA_MEDIUM_LEN`, `RMS_LAKE`, `RMS_SEA`,
  `STEEP_TOTAL`, `GRAVITY`, `wave_spectrum()`, `wave_count_for_tier()`.
- Новые константы (стартовые, дефолт — прикидка под наш спокойный климат;
  точный вид владелец подберёт ползунками F3): `SEA_HEIGHT ≈ 0.35`,
  `SEA_CHOPPY ≈ 4.0`, `SEA_SPEED ≈ 0.8`, `SEA_FREQ ≈ 0.08`; озеро
  спокойнее: `LAKE_HEIGHT ≈ 0.06`, `LAKE_CHOPPY ≈ 2.5`, `LAKE_SPEED ≈ 0.3`,
  `LAKE_FREQ ≈ 0.2`.
- `iter_fragment_for_tier()`: ULTRA 5, HIGH 4, дешевле — константа 3
  в шейдере (цена: постановка разрешает 4 на HIGH).
- `set_waves()` → `set_wave_params(height, choppy, speed, freq)` —
  множители к константам зоны (озеро и море — своя база, как сейчас).
- `_surface_material()` ставит новые uniform'ы вместо спектра.

Тесты: `test_water3.gd` — строковые проверки Герстнера → sea_octave
(`sea_octave`, `map_detailed`, `octave_m`, eps по дистанции);
`test_ground_water2.gd` — вместо детерминизма спектра: у зоны есть все
4 параметра, озеро спокойнее моря (height ниже); `test_island_scene.gd` —
амплитуда через `sea_height`.

## Блок 2 — пена по туториалу (коммит)

`water_bu.gdshader`:
- Функции туториала: `hash13`, `hash22`, `voronoi` (анимированные точки
  в ячейках), `noise3d`, `fbm_voronoi` (3 октавы, pow 2 — острые сгустки).
- Плотность `foam_level = depth_foam + crest_foam`:
  - мелкое: по толщине (foam_depth_start/end — по туториалу) ПЛЮС наша
    SDF-полоса берега с накатом (`shore_sdf`, runup) — остаётся, это
    плавная линия берега (наш п.4, у туториала её нет);
  - гребни: по нормали (`final_normal.y` ниже порога — гребень).
- Текстура пены: `fbm_voronoi(world_pos.xz · scale + warp)` — анимированный
  Вороной с domain warp (шум двух каналов), emergence-шум 3D гонит сгустки;
  второй смещённый проход — тёмная кромка (`foam_edge_color`), отдельный
  `voronoi` — пузырьки внутри (`voronoi_strength`).
- Всё через smoothstep (запрет `step(` сохраняется); пена — в ALBEDO
  (освещается светом сцены, в тени не светится), кромка — тоже ALBEDO.
  Озеро: `foam_amount ≈ 0.15` гасит foam_level, как сейчас.
- Круги вокруг ног (`rings_foam`) — max, как сейчас.

Новые uniform'ы Foam: `foam_edge_amount`, `foam_bubbles` (сила кромки и
пузырьков), `foam_scale` (масштаб Вороного). Старые `foam_amount`,
`foam_width`, `runup_amp`, `shore_sdf` — остаются.

Тесты: `test_water3.gd` — проверки пены под Вороной, нет `step(`.

## Блок 3 — цвет/глубина/поглощение/преломление/каустика (коммит)

- Объёмный цвет по туториалу: `water_volume = mix(shallow, deep,
  depth_ratio)`; дно тонируется объёмным цветом (у туториала —
  `apparent_seabed = screen_color · volume_color`), композит:
  `water = bottom · volume · transmit + scatter · (1 − transmit) · edge`.
  Поглощение Бера по каналам остаётся нашим.
- Преломление: смещение UV по нормали с дистанционным спадом и маской
  по толщине (`ref_depth_mask` туториала — на сверхмелком смещения нет),
  защита выборки от предметов над водой — наша, остаётся.
- Каустика: два встречно прокручивающихся слоя, произведение (у туториала
  sample1 · sample2) вместо `pow(...,5)`; гаснет с глубиной (толщина),
  с расстоянием и в темноте (`bottom_luma` — наше). Процедурная —
  текстура НЕ нужна, скачивать ничего не будем.
- Всё остальное (edge, far_thickness, depth_fog_fade) — без изменений.

## Блок 4 — сохранить наше (входит в коммиты 1–3)

- Движковое отражение неба (IBL radiance Sky3D) + френель F0 ≈ 0.02 +
  SPECULAR — не трогаем; тест «нет `ambient_light_disabled`» остаётся.
- Мягкая кромка `EDGE_SOFT_M` (П15 п. 9) — остаётся.
- Круги вокруг ног (`ripple_sources`) — остаются.
- Фильтрация нормалей вдали: eps по дистанции + переход к геом. нормали.
- Дешёвый шейдер SIMPLE/NORMAL — той же формулы волн, без экранной выборки.

## Блок 5 — пресеты цвета + F3 (коммит)

`water_area.gd`:
- Пресеты (словарь): `«Туториал»` — бирюзовый (по туториалу: shallow
  ≈ (0.24, 0.60, 0.62), deep ≈ (0.0, 0.20, 0.24), поглощение слабое
  reddish ≈ (0.35, 0.10, 0.05); озеро — зеленее и спокойнее) и
  `«Born Unblessed»` — текущие тёмные константы. Пресет = 4 цвета +
  2 absorption (озеро/море). ПО УМОЛЧАНИЮ — «Туториал».
- `set_preset(id)` + применение ко всем зонам группы water_surface.

`ui/debug_panel.gd` (вкладка «Вода»):
- Переключатель пресетов (две кнопки/OptionButton) наверху вкладки.
- Ползунки: убрать `wave_h_lake/sea`, `wave_l_lake/sea` → добавить
  `wave_height`, `wave_choppy`, `wave_speed`, `wave_freq` (множители
  0–2); пена: `foam_amount` (есть), `foam_edge`, `foam_bubbles` (новые);
  каустика, поглощение, преломление, рябь ×2, roughness ×2, `foam_width`,
  цвета ×4 — остаются.
- «Скопировать значения» — все параметры: цвета, SEA_/LAKE_ волновые
  базовые константы (высота/крутизна/скорость/частота — с учётом множителей
  на момент копирования), пена, absorption, roughness — формат «const
  ИМЯ: тип = значение» для вставки в `water_area.gd`.

`i18n/strings_bu.csv`: ключи BU_W_PRESET, BU_W_PRESET_TUTORIAL,
BU_W_PRESET_BU, BU_W_WAVE_HEIGHT, BU_W_WAVE_CHOPPY, BU_W_WAVE_SPEED,
BU_W_WAVE_FREQ, BU_W_FOAM_EDGE, BU_W_FOAM_BUBBLES (ru/en); упразднённые
wave_h/wave_l — удалить.

## Блок 6 — цена на HIGH

Без замеров на сервере (llvmpipe бессмысленен — правило CLAUDE.md):
- HIGH: 4 октавы fragment (разрешено постановкой), 3 vertex — дешевле
  текущих 16 волн Герстнера попиксельно.
- Вороной-пена считается только где `foam_level > 0` (ветвление).
- Владелец проверит на 780M; F3-авто-замер GPU-мс — инструмент сравнения.

## Блок 7 — тесты + финал (коммит)

- `test_water3.gd`: шейдер-строки обоих шейдеров соответствуют новому
  коду; компиляция на всех уровнях (shader_for_tier по всем тирам);
  пресеты переключаются и меняют uniform'ы; ползунки двигают параметры;
  в шейдере нет `step(` и `ambient_light_disabled`; «Скопировать
  значения» содержит все константы; `HEIGHTS_CHECKSUM` = 2041845998.
- Полный GUT зелёный (счёт в отчёт, известные pending пометить).
- `docs/STATUS.md`: что взято из туториала / наши отличия / константы /
  что не получилось.
- Сборка `builds/born-unblessed-windows.zip` с нуля, `python3 -m zipfile
  -t`, sha256 exe и zip.
- Дерево чистое, СТОП, короткий отчёт.

## Порядок коммитов

1. Туториал + план (этот файл).
2. Блок 1 (волны) — тесты зелёные.
3. Блок 2 (пена).
4. Блок 3 (цвет/преломление/каустика).
5. Блок 5 (пресеты + F3) — блок 4 разложен по 2–4.
6. Блок 7 (тесты-доделки, STATUS, сборка).

После каждого блока — коммит и push.
