# Сторонние ресурсы (CC0 и MIT)

Правила использования — раздел «Скачивание ресурсов» в CLAUDE.md и план
доработки графики (docs/VISUAL_PLAN.md): ресурсы только CC0, код аддонов —
CC0 или MIT (с автором и лицензией), только с разрешённых сайтов, в проекте
лежат лишь реально используемые файлы (архивы не хранятся). Папки наборов Kenney закрыты `.gdignore`: Godot не
импортирует эти файлы, их читает напрямую `gameplay/world/props/cc0_meshes.gd`
при запекании острова (в игре меши уже встроены в `island_art.res`). Папки
остальных наборов импортируются движком и загружаются в рантайме; извлечённые
из glb текстуры (`*_texture.png` и подобные) создаёт сам Godot при импорте —
это та же встроенная текстура модели. Наборы KayKit (персонажи и анимации,
раздел 16 SPEC v2.3) удалены после перехода на персонажей Quaternius
Universal Base Characters + Modular Character Outfits и клипы Universal
Animation Library (П5.7–П5.8).

| Набор | Автор | Страница набора | Лицензия | Дата | Файлы |
| --- | --- | --- | --- | --- | --- |
| Nature Kit | Kenney | https://kenney.nl/assets/nature-kit | CC0 | 2026-10-05 | `kenney.nl/nature-kit/`: tree_default.glb, tree_oak.glb, tree_detailed.glb, tree_fat.glb, tree_small.glb, tree_pineRoundA.glb, tree_pineDefaultA.glb, tree_pineSmallA.glb, plant_bush.glb, plant_bushSmall.glb, plant_bushDetailed.glb, grass.glb, grass_leafs.glb, grass_large.glb, flower_redA.glb, flower_yellowA.glb, flower_purpleA.glb, rock_largeA.glb, rock_largeB.glb, rock_largeD.glb, rock_tallA.glb, rock_tallB.glb, rock_tallC.glb, rock_smallA.glb, rock_smallB.glb, rock_smallC.glb, log.glb, log_large.glb, plant_flatTall.glb, plant_flatShort.glb |
| Castle Kit | Kenney | https://kenney.nl/assets/castle-kit | CC0 | 2026-10-05 | `kenney.nl/castle-kit/wall-pillar.glb`, `kenney.nl/castle-kit/tower-square-arch.glb`, `kenney.nl/castle-kit/Textures/colormap.png` (атлас цветов моделей) |
| Universal Animation Library 1/2 (Standard) | Quaternius | https://quaternius.com/packs/universalanimationlibrary.html, https://quaternius.com/packs/universalanimationlibrary2.html | CC0 | 2026-10-12 | `quaternius.com/universal_animation_library/anims_ubc.res` — 19 скелетных клипов, переложенных с универсального рига UAL на риг Universal Base Characters (`tools/make_ubc_anims.gd`; линейки Quaternius Universal делят один риг); исходные glb наборов и архивы в репозитории не хранятся |
| Universal Base Characters (Standard) | Quaternius | https://quaternius.com/packs/universalbasecharacters.html | CC0 | 2026-10-12 | `quaternius.com/universal_base_characters/baked/` — риг 65 костей (тела Superhero Male/Female, глаза, брови) и причёски (Long, Buns, Buzzed, BuzzedFemale, SimpleParted, Beard), запечённые `tools/make_ubc_characters.gd` в сцены `ubc_male.res`/`ubc_female.res` (срез головы, меши + `_lod1` + скины, материалы, текстуры — кожа обесцвечена под палитры); исходные gltf и архивы в репозитории не хранятся |
| Modular Character Outfits — Fantasy (Standard) | Quaternius | https://quaternius.com/packs/modularcharacteroutfits.html | CC0 | 2026-10-12 | внутри `quaternius.com/universal_base_characters/baked/` — модульная одежда Peasant/Ranger (верх, руки, низ, обувь, капюшон) из частей Male/Female, собранная тем же запеканием в `meshes/` и сцены `ubc_*.res`; исходные gltf и архивы в репозитории не хранятся |
| Bark001 | ambientCG | https://ambientcg.com/view?id=Bark001 | CC0 | 2026-10-16 | `ambientcg.com/Bark001/Bark001_2K-JPG_Color.jpg` (сет «1K» у Bark001 — 512×1024, ниже планки качества П5.9; взят 2K-сет из локальной библиотеки) |
| Bark002 | ambientCG | https://ambientcg.com/view?id=Bark002 | CC0 | 2026-10-16 | `ambientcg.com/Bark002/Bark002_1K-JPG_Color.jpg` |
| Bark003 | ambientCG | https://ambientcg.com/view?id=Bark003 | CC0 | 2026-10-16 | `ambientcg.com/Bark003/Bark003_1K-JPG_Color.jpg` |
| Sky3D 2.1 | Cory Petkovsek, J. Cuéllar и контрибьюторы | https://github.com/TokisanGames/Sky3D | MIT | 2026-10-16 | `addons/sky_3d/` — небо мира (П5.9 блок 6): атмосферное рассеяние, облака, луна, звёзды; текст лицензий — `addons/sky_3d/LICENSE.txt` и `addons/sky_3d/shaders/LICENSE`. Правки кода аддона: (1) прелоады текстур звёздного неба в `src/SkyDome.gd` перенаправлены на процедурные текстуры проекта (см. следующую строку) — штатные Milkyway.jpg/StarField.jpg аддона (панорама ESO/S. Brunier, CC BY 4.0) в проект НЕ вносились и удалены из копии; (2) в `shaders/SkyMaterial.gdshader` шести сэмплерам (луна, звёзды, шум, облака) добавлен явный хинт `filter_linear` — планка качества П5.9 (никаких фильтров Nearest без явного объявления) |
| Текстуры звёздного неба | сделано для проекта (`tools/make_star_textures.gd`) | — | CC0 (как и весь код проекта) | 2026-10-16 | `assets/visual/sky_starmap.png`, `assets/visual/sky_starfield.png` — процедурная полоса «млечного пути» и россыпь звёзд, детерминированная генерация |

Наборы Kenney используются как геометрия предметов окружения (шаг 3 этапа
П4.5): модели перекрашиваются в палитры игры вершинными цветами и нормируются
под размеры процедурных мешей — см. `gameplay/world/props/cc0_meshes.gd`.
Сканы Poly Haven (П5.7, блок 2) — фотограмметрия деревьев, кустов, камней и
брёвен Леса: скачанные glb децимированы до бюджетов low-poly и запечены в
`.res` с цветом текстуры в вершинах (`tools/decimate_polyhaven.gd`;
оригинальные glb в проекте не хранятся, страницы ассетов — в таблице).
П5.9 (блок 3) заменил фотосканы травы и папоротника процедурными пучками
`gameplay/world/props/forest_plants.gd` — наборы grass_medium_02 и fern_02
удалены.
П5.9 (блок 4) заменил фотосканы деревьев, кустов и валежника портом
генератора EZ-Tree (MIT, © Dan Greenheck, github.com/dgreenheck/ez-tree) —
`gameplay/world/props/tree_gen.gd`; наборы island_tree_01–03, shrub_02–04
и dead_tree_trunk удалены, вместо них кора — текстуры ambientCG (таблица
выше). Код EZ-Tree переписан на GDScript по чтению исходников, файлы
оригинала в проекте не хранятся.
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
