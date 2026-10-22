# Сторонние ресурсы (CC0, CC-BY 4.0 и MIT)

Правила использования — раздел «Скачивание ресурсов» в CLAUDE.md и план
доработки графики (docs/VISUAL_PLAN.md): ресурсы только CC0, код аддонов —
CC0 или MIT (с автором и лицензией), только с разрешённых сайтов, в проекте
лежат лишь реально используемые файлы (архивы не хранятся). Единственное
исключение из «только CC0» — модель сруба Kless (CC-BY 4.0, следующая
строка): явное решение владельца, атрибуция — дословно, как требует
лицензия, также в титрах игры (экран Credits). Извлечённые
из glb текстуры (`*_texture.png` и подобные) создаёт сам Godot при импорте —
это та же встроенная текстура модели. Наборы KayKit (персонажи и анимации,
раздел 16 SPEC v2.3) удалены после перехода на персонажей Quaternius
Universal Base Characters + Modular Character Outfits и клипы Universal
Animation Library (П5.7–П5.8).

| Набор | Автор | Страница набора | Лицензия | Дата | Файлы |
| --- | --- | --- | --- | --- | --- |
| Log Cabin (Free Download) | Kless | https://sketchfab.com/3d-models/log-cabin-free-download-6zquz | CC-BY 4.0 | 2026-10-18 | Дословная атрибуция лицензии: **"Log Cabin (Free Download)" (https://skfb.ly/6ZQuZ) by Kless is licensed under Creative Commons Attribution (http://creativecommons.org/licenses/by/4.0/).** — `visual/cabin/log_cabin.glb` — дом жителей деревни (сруб, очередь владельца после доработки П5.13): исходник 36 МБ/585k треугольников обработан вне репозитория (декимация до 42k снаружи + 14k интерьер + 27k коллизия, встроенные текстуры удалены — материалы назначает `gameplay/world/props/cabin_house.gd` из CC0-наборов ниже); исходный glb в репозитории не хранится. Единственный не-CC0 ресурс проекта — по решению владельца; та же строка — в титрах игры (экран Credits) |
| Universal Animation Library 1/2 (Standard) | Quaternius | https://quaternius.com/packs/universalanimationlibrary.html, https://quaternius.com/packs/universalanimationlibrary2.html | CC0 | 2026-10-12 | `quaternius.com/universal_animation_library/anims_ubc.res` — 19 скелетных клипов, переложенных с универсального рига UAL на риг Universal Base Characters (`tools/make_ubc_anims.gd`; линейки Quaternius Universal делят один риг); исходные glb наборов и архивы в репозитории не хранятся |
| Universal Base Characters (Standard) | Quaternius | https://quaternius.com/packs/universalbasecharacters.html | CC0 | 2026-10-12 | `quaternius.com/universal_base_characters/baked/` — риг 65 костей (тела Superhero Male/Female, глаза, брови) и причёски (Long, Buns, Buzzed, BuzzedFemale, SimpleParted, Beard), запечённые `tools/make_ubc_characters.gd` в сцены `ubc_male.res`/`ubc_female.res` (срез головы, меши + `_lod1` + скины, материалы, текстуры — кожа обесцвечена под палитры); исходные gltf и архивы в репозитории не хранятся |
| Modular Character Outfits — Fantasy (Standard) | Quaternius | https://quaternius.com/packs/modularcharacteroutfits.html | CC0 | 2026-10-12 | внутри `quaternius.com/universal_base_characters/baked/` — модульная одежда Peasant/Ranger (верх, руки, низ, обувь, капюшон) из частей Male/Female, собранная тем же запеканием в `meshes/` и сцены `ubc_*.res`; исходные gltf и архивы в репозитории не хранятся |
| Bark001 | ambientCG | https://ambientcg.com/view?id=Bark001 | CC0 | 2026-10-16 | `ambientcg.com/Bark001/Bark001_2K-JPG_Color.jpg` (сет «1K» у Bark001 — 512×1024, ниже планки качества П5.9; взят 2K-сет из локальной библиотеки); `Bark001_2K-JPG_NormalGL.jpg` добавлен 2026-10-22 — нормали брёвен сруба деревни (`cabin_house.gd`), источник — локальная библиотека |
| Bark002 | ambientCG | https://ambientcg.com/view?id=Bark002 | CC0 | 2026-10-16 | `ambientcg.com/Bark002/Bark002_1K-JPG_Color.jpg` |
| Bark003 | ambientCG | https://ambientcg.com/view?id=Bark003 | CC0 | 2026-10-16 | `ambientcg.com/Bark003/Bark003_1K-JPG_Color.jpg` |
| Grass001 | ambientCG | https://ambientcg.com/view?id=Grass001 | CC0 | 2026-10-17 | `ambientcg.com/Grass001/Grass001_1K-JPG_Color.jpg` — текстура травы земли Леса (П5.9 переделка, П2); CC0-замена ground/grass.jpg демо ez-tree, лицензия которого не описана в textures/LICENSE.md репозитория |
| forest_ground_05 | Poly Haven | https://polyhaven.com/a/forest_ground_05 | CC0 | 2026-10-17 | `polyhaven.com/forest_ground_05/forest_ground_05_diffuse_2k.jpg`, `forest_ground_05_nor_gl_2k.jpg` — грунт и нормали земли Леса; CC0-замена ground/dirt_color.jpg + dirt_normal.jpg демо ez-tree (лицензия не описана в textures/LICENSE.md репозитория) |
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
Universal Animation Library 1/2 (П5.7 блок 5 → П5.8 часть C) — исходные
скелетные анимации персонажей: `tools/make_ubc_anims.gd` перекладывает клипы
покоя/ходьбы/бега/прыжков/эмоций с универсального рига UAL на общий с ним
риг Universal Base Characters и запекает в `anims_ubc.res` (одна библиотека
на оба тела); движения без аналогов в Standard-наборах (взмах, «за руку»,
вис у кромки, «Помогите!») генерируются процедурно поверх rest/запечённых
баз (подробности — docs/STATUS.md).
| Boujie Water Shader 1.0.0 | Zach Bernal | https://github.com/Chrisknyfe/boujie_water_shader | MIT | 2026-10-18 | `addons/boujie_water_shader/` — вода мира (доработка-2 П5.13, П3): волны Герстнера, цвет по глубине, береговая пена, френель, LOD-океан; текст лицензии — `addons/boujie_water_shader/LICENSE.md`, скриншоты аддона в проект не вносились. Правки кода аддона: (1) в `shader/water.gdshader` выключены дефайны REFRACTION/REFRACTION_SCALING/SNELLS_WINDOW — SPEC «Простая графика» (README аддона прямо допускает отключение дефайнов), depth-цвет/пена/френель остались; (2) трём сэмплерам текстур добавлен явный хинт `filter_linear_mipmap` — планка качества (никаких фильтров без явного объявления) |
| old_stone_wall_02 | Poly Haven | https://polyhaven.com/a/old_stone_wall_02 | CC0 | 2026-10-19 | `polyhaven.com/old_stone_wall_02/old_stone_wall_02_diffuse_2k.jpg`, `old_stone_wall_02_nor_gl_2k.jpg` — кладка руин и каменных стен (доработка-2 П5.13, П4): трипланарный шейдер `assets/shaders/ruin_masonry.gdshader`, источник — локальная библиотека |
| Moss001 | ambientCG | https://ambientcg.com/get?file=Moss001_1K-JPG.zip | CC0 | 2026-10-19 | `ambientcg.com/Moss001/Moss001_1K-JPG_Color.jpg` — текстура мха поверхностей (доработка-2 П5.13, П4: мох кладки руин; 1K намеренно — 2K-нормаль >10 МБ без LFS), источник — локальная библиотека |
| Planks007 | ambientCG | https://ambientcg.com/get?file=Planks007_2K-JPG.zip | CC0 | 2026-10-19 | `ambientcg.com/Planks007/Planks007_2K-JPG_Color.jpg`, `Planks007_2K-JPG_NormalGL.jpg` — дерево сундука руин (доработка-2 П5.13, П4) и настилов у воды (доработка-2 П5.13, П5: причал, сваи, кнехты, ступени лестниц смотровых — `assets/shaders/planks_wood.gdshader`), источник — локальная библиотека |
| dikhololo_night | Poly Haven | https://polyhaven.com/a/dikhololo_night | CC0 | 2026-10-19 | Ночное HDRI — источник звёздного неба (доработка-2 П5.13, П9): `assets/visual/sky_starfield.png` (звёзды — чёткие точки из снимка) и `sky_starmap.png` (Млечный Путь — фон снимка), генератор `tools/make_star_textures.gd`. Сам .hdr (4K) — в локальной библиотеке `library/polyhaven/hdris/`, в git не входит |
| Fabric085 | ambientCG | https://ambientcg.com/view?id=Fabric085 | CC0 | 2026-10-22 | `ambientcg.com/Fabric085/Fabric085_2K-JPG_Color.jpg` — ткань штор интерьера сруба деревни (`cabin_house.gd`), источник — локальная библиотека |
| PaintedWood006A | ambientCG | https://ambientcg.com/view?id=PaintedWood006A | CC0 | 2026-10-22 | `ambientcg.com/PaintedWood006A/PaintedWood006A_2K-JPG_Color.jpg` — крашеное дерево стен интерьера сруба деревни (`cabin_house.gd`), источник — локальная библиотека |
