# Сторонние CC0-ресурсы

Правила использования — раздел «Скачивание ресурсов» в CLAUDE.md: только CC0,
только с разрешённых сайтов, в проекте лежат лишь реально используемые файлы
(архивы не хранятся). Папки наборов Kenney закрыты `.gdignore`: Godot не
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
| Bark001 | ambientCG | https://ambientcg.com/view?id=Bark001 | CC0 | 2026-10-16 | `ambientcg.com/Bark001/Bark001_1K-JPG_Color.jpg` |
| Bark002 | ambientCG | https://ambientcg.com/view?id=Bark002 | CC0 | 2026-10-16 | `ambientcg.com/Bark002/Bark002_1K-JPG_Color.jpg` |
| Bark003 | ambientCG | https://ambientcg.com/view?id=Bark003 | CC0 | 2026-10-16 | `ambientcg.com/Bark003/Bark003_1K-JPG_Color.jpg` |
| rock_07 | Poly Haven | https://polyhaven.com/a/rock_07 | CC0 | 2026-10-11 | `polyhaven.com/rock_07/rock_07_lo.res` |
| rock_09 | Poly Haven | https://polyhaven.com/a/rock_09 | CC0 | 2026-10-11 | `polyhaven.com/rock_09/rock_09_lo.res` |
| boulder_01 | Poly Haven | https://polyhaven.com/a/boulder_01 | CC0 | 2026-10-11 | `polyhaven.com/boulder_01/boulder_01_lo.res` |
| kloofendal_48d_partly_cloudy_puresky | Poly Haven | https://polyhaven.com/a/kloofendal_48d_partly_cloudy_puresky | CC0 | 2026-10-11 | `polyhaven.com/kloofendal_48d_partly_cloudy_puresky/kloofendal_48d_partly_cloudy_puresky_2k.hdr` |
| grasslands_sunset | Poly Haven | https://polyhaven.com/a/grasslands_sunset | CC0 | 2026-10-11 | `polyhaven.com/grasslands_sunset/grasslands_sunset_2k.hdr` |
| rogland_clear_night | Poly Haven | https://polyhaven.com/a/rogland_clear_night | CC0 | 2026-10-11 | `polyhaven.com/rogland_clear_night/rogland_clear_night_2k.hdr` |

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
HDRI-панорамы Poly Haven (П5.7, блок 3) — небо мира: день/закат/ночь
смешиваются по времени суток в `assets/shaders/sky.gdshader`.
Universal Animation Library 1/2 (П5.7 блок 5 → П5.8 часть C) — исходные
скелетные анимации персонажей: `tools/make_ubc_anims.gd` перекладывает клипы
покоя/ходьбы/бега/прыжков/эмоций с универсального рига UAL на общий с ним
риг Universal Base Characters и запекает в `anims_ubc.res` (одна библиотека
на оба тела); движения без аналогов в Standard-наборах (взмах, «за руку»,
вис у кромки, «Помогите!») генерируются процедурно поверх rest/запечённых
баз (подробности — docs/STATUS.md).
