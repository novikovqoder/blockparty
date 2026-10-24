# Сторонние ресурсы (CC0, CC-BY 4.0 и MIT)

Правила использования — раздел «Скачивание ресурсов» в CLAUDE.md и план
доработки графики (docs/VISUAL_PLAN.md): ресурсы только CC0, код аддонов —
CC0 или MIT (с автором и лицензией), только с разрешённых сайтов, в проекте
лежат лишь реально используемые файлы (архивы не хранятся). Исключения из
«только CC0» — модель сруба Kless (CC-BY 4.0, следующая строка), а с этапа П9
ещё два (обе строки внизу таблицы, помечены «исключение»): иллюстрации меню
Born Unblessed (созданы владельцем с помощью ИИ) и шрифты Cormorant/Manrope
(SIL OFL 1.1) — все по явному решению владельца; атрибуция Kless — дословно,
как требует лицензия, также в титрах игры (экран Credits). Извлечённые
из glb текстуры (`*_texture.png` и подобные) создаёт сам Godot при импорте —
это та же встроенная текстура модели. Наборы KayKit (П4.5), затем
Quaternius Universal Base Characters + Modular Character Outfits и
Universal Animation Library (П5.7–П5.8) использовались как блочные
персонажи и их анимации — вычищены вместе с редактором внешности
(born-unblessed): персонаж один, герой Born Unblessed (MakeHuman + Mixamo,
см. assets/hero_bu/LICENSES_hero_bu.md).

| Набор | Автор | Страница набора | Лицензия | Дата | Файлы |
| --- | --- | --- | --- | --- | --- |
| Log Cabin (Free Download) | Kless | https://sketchfab.com/3d-models/log-cabin-free-download-6zquz | CC-BY 4.0 | 2026-10-18 | Дословная атрибуция лицензии: **"Log Cabin (Free Download)" (https://skfb.ly/6ZQuZ) by Kless is licensed under Creative Commons Attribution (http://creativecommons.org/licenses/by/4.0/).** — `visual/cabin/log_cabin.glb` — дом жителей деревни (сруб, очередь владельца после доработки П5.13): исходник 36 МБ/585k треугольников обработан вне репозитория (декимация до 42k снаружи + 14k интерьер + 27k коллизия, встроенные текстуры удалены — материалы назначает `gameplay/world/props/cabin_house.gd` из CC0-наборов ниже); исходный glb в репозитории не хранится. Единственный не-CC0 ресурс проекта — по решению владельца; та же строка — в титрах игры (экран Credits) |
| Bark001 | ambientCG | https://ambientcg.com/view?id=Bark001 | CC0 | 2026-10-16 | `ambientcg.com/Bark001/Bark001_2K-JPG_Color.jpg` (сет «1K» у Bark001 — 512×1024, ниже планки качества П5.9; взят 2K-сет из локальной библиотеки); `Bark001_2K-JPG_NormalGL.jpg` добавлен 2026-10-22 — нормали брёвен сруба деревни (`cabin_house.gd`), источник — локальная библиотека |
| Bark002 | ambientCG | https://ambientcg.com/view?id=Bark002 | CC0 | 2026-10-16 | `ambientcg.com/Bark002/Bark002_1K-JPG_Color.jpg` |
| Bark003 | ambientCG | https://ambientcg.com/view?id=Bark003 | CC0 | 2026-10-16 | `ambientcg.com/Bark003/Bark003_1K-JPG_Color.jpg` |
| Grass001 | ambientCG | https://ambientcg.com/view?id=Grass001 | CC0 | 2026-10-17 | `ambientcg.com/Grass001/Grass001_1K-JPG_Color.jpg` — текстура травы земли Леса (П5.9 переделка, П2); CC0-замена ground/grass.jpg демо ez-tree, лицензия которого не описана в textures/LICENSE.md репозитория |
| forest_ground_05 (спрайт частиц) | Poly Haven | https://polyhaven.com/a/forest_ground_05 | CC0 | 2026-10-23 | `assets/vfx/particles/dirt.png` — спрайт комьев земли (нарезка 64×64 с круглой маской из `forest_ground_05_diffuse_2k.jpg`, частицы бега П9); исходник — та же загрузка от 2026-10-17 |
| Grass001 (спрайты частиц) | ambientCG | https://ambientcg.com/view?id=Grass001 | CC0 | 2026-10-23 | `assets/vfx/particles/grass.png`, `leaf.png` — спрайты травинок и листа (нарезка `tools/make_vfx_textures.gd` из `Grass001_1K-JPG_Color.jpg`, частицы бега П9 и листья Леса); исходник — та же загрузка от 2026-10-17 |
| `assets/vfx/particles/soft.png` | сделано для проекта | — | CC0 (как и весь код проекта) | 2026-10-23 | процедурное радиальное пятно (белый с прозрачным краем) — маска мягких частиц: пыль приземления, искры костра, светлячки, пыльца (`tools/make_vfx_textures.gd`) |
| forest_ground_05 | Poly Haven | https://polyhaven.com/a/forest_ground_05 | CC0 | 2026-10-17 | `polyhaven.com/forest_ground_05/forest_ground_05_diffuse_2k.jpg`, `forest_ground_05_nor_gl_2k.jpg` — грунт и нормали земли Леса; CC0-замена ground/dirt_color.jpg + dirt_normal.jpg демо ez-tree (лицензия не описана в textures/LICENSE.md репозитория); П12 добавил `forest_ground_05_orm_2k.jpg` (24.10, собран `tools/make_orm_textures.gd`) — полный PBR слоя подстилки земли |
| ez-tree | Dan Greenheck | https://github.com/dgreenheck/ez-tree | MIT | 2026-10-17 | `assets/visual/trees/models/` — 60 GLB (пресеты Pine/Oak/Aspen/Ash/Bush с вариациями seed, по три уровня детализации), сгенерированные самим ez-tree конвейером вне репозитория (~/eztree_gen); `assets/visual/trees/leaves/{ash,aspen,oak,pine}.png` — из `src/app/public/textures/leaves/` репозитория; текст лицензии — `assets/visual/trees/LICENSE-ez-tree.txt` |
| Sky3D 2.1 | Cory Petkovsek, J. Cuéllar и контрибьюторы | https://github.com/TokisanGames/Sky3D | MIT | 2026-10-16 | `addons/sky_3d/` — небо мира (П5.9 блок 6): атмосферное рассеяние, облака, луна, звёзды; текст лицензий — `addons/sky_3d/LICENSE.txt` и `addons/sky_3d/shaders/LICENSE`. Правки кода аддона: (1) прелоады текстур звёздного неба в `src/SkyDome.gd` перенаправлены на процедурные текстуры проекта (см. следующую строку) — штатные Milkyway.jpg/StarField.jpg аддона (панорама ESO/S. Brunier, CC BY 4.0) в проект НЕ вносились и удалены из копии; (2) в `shaders/SkyMaterial.gdshader` шести сэмплерам (луна, звёзды, шум, облака) добавлен явный хинт `filter_linear` — планка качества П5.9 (никаких фильтров Nearest без явного объявления) |
| Текстуры звёздного неба | сделано для проекта (`tools/make_star_textures.gd`) | — | CC0 (как и весь код проекта) | 2026-10-16 | `assets/visual/sky_starmap.png`, `assets/visual/sky_starfield.png` — процедурная полоса «млечного пути» и россыпь звёзд, детерминированная генерация |
| Terrain3D 1.0.2 | Cory Petkovsek, Roope Palmroos и контрибьюторы | https://github.com/TokisanGames/Terrain3D | MIT | 2026-10-18 | `addons/terrain_3d/` — рельеф острова вне сектора Леса (П5.13, блок 3): сглаженные нормали, LOD-клипмап, дырки рендера из control-карты; коллизия аддона выключена (физика остаётся на HeightMapShape3D). Текст лицензии — `addons/terrain_3d/LICENSE.txt`. Вершинная часть `gameplay/world/terrain3d_ground.gdshader` — облегчённый шейдер аддона `extras/shaders/lightweight.gdshader` (MIT, с атрибуцией в комментарии), фрагментная часть наша. Код аддона не правил. Удалён из проекта в тот же день (доработка П5.13, пункт 1): весь остров рисуют чанки из карты высот с материалом ForestGround |
| stone_fire_pit | Poly Haven | https://polyhaven.com/a/stone_fire_pit | CC0 | 2026-10-18 | `polyhaven.com/stone_fire_pit/fire_pit_lo.res` — каменное кострище площади (доработка П5.13, живой огонь): децимация 3 887 → 1 943 треугольника с запеченным цветом (`tools/decimate_polyhaven.gd`, тон поднят `Campfire._lifted`); исходный gltf 1k в проекте не хранится, источник — локальная библиотека |
| dry_branches_medium_01 | Poly Haven | https://polyhaven.com/a/dry_branches_medium_01 | CC0 | 2026-10-18 | `polyhaven.com/dry_branches_medium_01/branch_lo.res` — сухие ветки-поленья шатра над углями костра: децимация 16 803 → 1 047 треугольников с запеченным цветом; исходный gltf 1k в проекте не хранится, источник — локальная библиотека |
| webgl-noise (симплекс-шум) | Ian McEwan, Ashima Arts | https://github.com/ashima/webgl-noise | MIT | 2026-10-18 | GLSL-функции simplex2d/simplex3d в `assets/shaders/{canopy,forest_ground,rock_moss,fire,smoke}.gdshader` (анимированные шумом пламя и дым костра — доработка П5.13; остальное — П5.9): классический порт из webgl-noise `noise2D`/`noise3D`, атрибуция также в комментариях шейдеров |

Наборы Kenney (шаг 3 П4.5) использовались как геометрия предметов окружения;
П5.13, блок 1 убрал их из окружения почти полностью — лавки, колонны и арки
руин, навесы площади, камни и растительность процедурные (`prop_meshes.gd`,
`rock_gen.gd`, `forest_plants.gd`); Castle Kit удалён. П5.13, блок 5 убрал и
последнее — брёвна валежника Nature Kit (log/log_large) заменены процедурной
корягой `_snag` (`prop_meshes.gd`); файлов kenney в проекте больше нет.
Сканы Poly Haven (П5.7, блок 2) — фотограмметрия деревьев, кустов, камней и
брёвен Леса: скачанные glb децимированы до бюджетов low-poly и запечены в
`.res` с цветом текстуры в вершинах (`tools/decimate_polyhaven.gd`;
оригинальные glb в проекте не хранятся, страницы ассетов — в таблице).
П5.9 (блок 3) заменил фотосканы травы и папоротника процедурными пучками
`gameplay/world/props/forest_plants.gd` — наборы grass_medium_02 и fern_02
удалены.
П5.9 (блок 4) заменил фотосканы деревьев, кустов и валежника процедурным
портом генератора EZ-Tree; переделка П5.9 убрала порт — деревья генерирует
сам ez-tree (MIT, © Dan Greenheck, github.com/dgreenheck/ez-tree) в
Node.js-конвейере вне репозитория (пресеты Pine/Oak/Aspen/Ash/Bush с
вариациями seed, экспорт GLB в `assets/visual/trees/`, чтение —
`gameplay/world/props/eztree_meshes.gd`). Наборы island_tree_01–03,
shrub_02–04 и dead_tree_trunk удалены; кора — текстуры ambientCG (таблица
выше), текстуры листвы — из репозитория ez-tree (MIT). Валежник и мостик —
процедурные брёвна с корой ambientcg (`_snag`/`_log_bridge` в
`prop_meshes.gd`). Исходники ez-tree в проекте не хранятся.
П5.9 (блок 5) заменил фотосканы крупных камней Леса процедурными глыбами
`gameplay/world/props/rock_gen.gd` (искажённая шумом сфера, мох по верхним
граням красит `assets/shaders/rock_moss.gdshader`) — наборы rock_07,
rock_09 и boulder_01 удалены.
HDRI-панорамы Poly Haven (П5.7, блок 3) удалены в П5.9 (блок 6): небо
мира теперь рисует аддон Sky3D (атмосферное рассеяние вместо запечённых
панорам), шейдер `assets/shaders/sky.gdshader` и наборы kloofendal /
grasslands_sunset / rogland_clear_night исключены из проекта.
| Boujie Water Shader 1.0.0 | Zach Bernal | https://github.com/Chrisknyfe/boujie_water_shader | MIT | 2026-10-18 | `addons/boujie_water_shader/` — вода мира (доработка-2 П5.13, П3): волны Герстнера, цвет по глубине, береговая пена, френель, LOD-океан; текст лицензии — `addons/boujie_water_shader/LICENSE.md`, скриншоты аддона в проект не вносились. Правки кода аддона: (1) в `shader/water.gdshader` выключены дефайны REFRACTION/REFRACTION_SCALING/SNELLS_WINDOW — SPEC «Простая графика» (README аддона прямо допускает отключение дефайнов), depth-цвет/пена/френель остались; (2) трём сэмплерам текстур добавлен явный хинт `filter_linear_mipmap` — планка качества (никаких фильтров без явного объявления) |
| old_stone_wall_02 | Poly Haven | https://polyhaven.com/a/old_stone_wall_02 | CC0 | 2026-10-19 | `polyhaven.com/old_stone_wall_02/old_stone_wall_02_diffuse_2k.jpg`, `old_stone_wall_02_nor_gl_2k.jpg` — кладка руин и каменных стен (доработка-2 П5.13, П4): трипланарный шейдер `assets/shaders/ruin_masonry.gdshader`, источник — локальная библиотека |
| Moss001 | ambientCG | https://ambientcg.com/get?file=Moss001_1K-JPG.zip | CC0 | 2026-10-19 | `ambientcg.com/Moss001/Moss001_1K-JPG_Color.jpg` — текстура мха поверхностей (доработка-2 П5.13, П4: мох кладки руин; 1K намеренно — 2K-нормаль >10 МБ без LFS), источник — локальная библиотека; П12 добавил `Moss001_1K-JPG_NormalGL.jpg` и `Moss001_1K-JPG_ORM.jpg` (24.10) — слой мха земли (вес w.b), ORM собран `tools/make_orm_textures.gd` |
| Planks007 | ambientCG | https://ambientcg.com/get?file=Planks007_2K-JPG.zip | CC0 | 2026-10-19 | `ambientcg.com/Planks007/Planks007_2K-JPG_Color.jpg`, `Planks007_2K-JPG_NormalGL.jpg` — дерево сундука руин (доработка-2 П5.13, П4) и настилов у воды (доработка-2 П5.13, П5: причал, сваи, кнехты, ступени лестниц смотровых — `assets/shaders/planks_wood.gdshader`), источник — локальная библиотека |
| dikhololo_night | Poly Haven | https://polyhaven.com/a/dikhololo_night | CC0 | 2026-10-19 | Ночное HDRI — источник звёздного неба (доработка-2 П5.13, П9): `assets/visual/sky_starfield.png` (звёзды — чёткие точки из снимка) и `sky_starmap.png` (Млечный Путь — фон снимка), генератор `tools/make_star_textures.gd`. Сам .hdr (4K) — в локальной библиотеке `library/polyhaven/hdris/`, в git не входит |
| Fabric085 | ambientCG | https://ambientcg.com/view?id=Fabric085 | CC0 | 2026-10-22 | `ambientcg.com/Fabric085/Fabric085_2K-JPG_Color.jpg` — ткань штор интерьера сруба деревни (`cabin_house.gd`), источник — локальная библиотека |
| PaintedWood006A | ambientCG | https://ambientcg.com/view?id=PaintedWood006A | CC0 | 2026-10-22 | `ambientcg.com/PaintedWood006A/PaintedWood006A_2K-JPG_Color.jpg` — крашеное дерево стен интерьера сруба деревни (`cabin_house.gd`), источник — локальная библиотека |
| leafy_grass | Poly Haven | https://polyhaven.com/a/leafy_grass | CC0 | 2026-10-24 | `polyhaven.com/leafy_grass/leafy_grass_diffuse_1k.jpg`, `leafy_grass_nor_gl_1k.jpg`, `leafy_grass_orm_1k.jpg` — слой травы лугов земли П12 (база при s < 0.5); ORM (R AO / G Roughness / B Height) собран `tools/make_orm_textures.gd`, источник — локальная библиотека |
| mud_forest | Poly Haven | https://polyhaven.com/a/mud_forest | CC0 | 2026-10-24 | `polyhaven.com/mud_forest/mud_forest_diffuse_1k.jpg`, `mud_forest_nor_gl_1k.jpg`, `mud_forest_orm_1k.jpg` — слой грязи низин земли П12 (вес w.g: мокрая земля, лужи); ORM собран `tools/make_orm_textures.gd`, источник — локальная библиотека |
| rock_face_03 | Poly Haven | https://polyhaven.com/a/rock_face_03 | CC0 | 2026-10-24 | `polyhaven.com/rock_face_03/rock_face_03_diffuse_2k.jpg`, `rock_face_03_nor_gl_2k.jpg`, `rock_face_03_orm_2k.jpg` — слой скалы крутых склонов земли П12 (вес w.r); ORM собран `tools/make_orm_textures.gd`, источник — локальная библиотека |
| rocky_trail | Poly Haven | https://polyhaven.com/a/rocky_trail | CC0 | 2026-10-24 | `polyhaven.com/rocky_trail/rocky_trail_diffuse_2k.jpg`, `rocky_trail_nor_gl_2k.jpg`, `rocky_trail_orm_2k.jpg` — слой гравия тропы и Площади земли П12 (вес w.a); ORM собран `tools/make_orm_textures.gd`, источник — локальная библиотека |
| Иллюстрации меню Born Unblessed | владелец проекта (сгенерировано ИИ, ChatGPT) | — | **исключение** (не CC0): право владельца, ИИ-контент | 2026-10-22 | `assets/menu_bu/bu_bg.jpg` (панорама собора 5974×1882), `bu_knight.png`, `bu_chains.png`, `bu_rubble.png` — слои фона главного меню Born Unblessed (П9). Решение владельца из SPEC П9; для Steam-релиза раскрыть использование ИИ-контента |
| Шрифты Cormorant и Manrope | Cormorant — Christian Thalmann (Catharsis Fonts); Manrope — Mikhail Sharanda | https://github.com/CatharsisFonts/Cormorant, https://github.com/sharanda/manrope | **исключение**: SIL Open Font License 1.1 | 2026-10-22 | `ui/theme_bu/fonts/Cormorant-Variable.ttf` (заголовки меню), `Manrope-Variable.ttf` (текст), тексты лицензий — `Cormorant-OFL.txt`, `Manrope-OFL.txt` рядом (П9). OFL разрешает встраивание в коммерческие игры; решение владельца из SPEC П9 |
