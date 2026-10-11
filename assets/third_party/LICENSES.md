# Сторонние CC0-ресурсы

Правила использования — раздел «Скачивание ресурсов» в CLAUDE.md: только CC0,
только с разрешённых сайтов, в проекте лежат лишь реально используемые файлы
(архивы не хранятся). Папки наборов Kenney закрыты `.gdignore`: Godot не
импортирует эти файлы, их читает напрямую `gameplay/world/props/cc0_meshes.gd`
при запекании острова (в игре меши уже встроены в `island_art.res`). Папки
KayKit `.gdignore` НЕ закрыты: модели персонажей и библиотеки анимаций —
готовые сцены Godot, они импортируются движком и загружаются в рантайме
(раздел 16 SPEC; извлечённые из glb текстуры `*_texture.png` создаёт сам
Godot при импорте — это та же встроенная текстура модели).

| Набор | Автор | Страница набора | Лицензия | Дата | Файлы |
| --- | --- | --- | --- | --- | --- |
| Nature Kit | Kenney | https://kenney.nl/assets/nature-kit | CC0 | 2026-10-05 | `kenney.nl/nature-kit/`: tree_default.glb, tree_oak.glb, tree_detailed.glb, tree_fat.glb, tree_small.glb, tree_pineRoundA.glb, tree_pineDefaultA.glb, tree_pineSmallA.glb, plant_bush.glb, plant_bushSmall.glb, plant_bushDetailed.glb, grass.glb, grass_leafs.glb, grass_large.glb, flower_redA.glb, flower_yellowA.glb, flower_purpleA.glb, rock_largeA.glb, rock_largeB.glb, rock_largeD.glb, rock_tallA.glb, rock_tallB.glb, rock_tallC.glb, rock_smallA.glb, rock_smallB.glb, rock_smallC.glb, log.glb, log_large.glb, plant_flatTall.glb, plant_flatShort.glb |
| Castle Kit | Kenney | https://kenney.nl/assets/castle-kit | CC0 | 2026-10-05 | `kenney.nl/castle-kit/wall-pillar.glb`, `kenney.nl/castle-kit/tower-square-arch.glb`, `kenney.nl/castle-kit/Textures/colormap.png` (атлас цветов моделей) |
| KayKit Adventurers 2.0 FREE | Kay Lousberg | https://kaylousberg.itch.io/kaykit-adventurers | CC0 | 2026-10-06 | `kaykit/adventurers/Knight.glb`, `kaykit/adventurers/Mage.glb`, `kaykit/adventurers/Ranger.glb`; текстуры (извлечены из glb при импорте): `kaykit/adventurers/Knight_knight_texture.png`, `kaykit/adventurers/Mage_mage_texture.png`, `kaykit/adventurers/Ranger_ranger_texture.png` |
| KayKit Character Animations 1.1 | Kay Lousberg | https://kaylousberg.itch.io/kaykit-character-animations | CC0 | 2026-10-06 | `kaykit/animations/Rig_Medium_General.glb`, `kaykit/animations/Rig_Medium_MovementBasic.glb`, `kaykit/animations/Rig_Medium_Simulation.glb` |
| Ground042 (Forest Ground Leaves) | ambientCG | https://ambientcg.com/view?id=Ground042 | CC0 | 2026-10-11 | `ambientcg.com/Ground042_2K/Ground042_2K-JPG_Color.jpg`, `ambientcg.com/Ground042_2K/Ground042_2K-JPG_NormalGL.jpg` |
| Ground044 (Dirt Ground) | ambientCG | https://ambientcg.com/view?id=Ground044 | CC0 | 2026-10-11 | `ambientcg.com/Ground044_2K/Ground044_2K-JPG_Color.jpg`, `ambientcg.com/Ground044_2K/Ground044_2K-JPG_NormalGL.jpg` |
| Moss001 | ambientCG | https://ambientcg.com/view?id=Moss001 | CC0 | 2026-10-11 | `ambientcg.com/Moss001_2K/Moss001_2K-JPG_Color.jpg`, `ambientcg.com/Moss001_2K/Moss001_2K-JPG_NormalGL.jpg` |
| Rock045 | ambientCG | https://ambientcg.com/view?id=Rock045 | CC0 | 2026-10-11 | `ambientcg.com/Rock045_2K/Rock045_2K-JPG_Color.jpg`, `ambientcg.com/Rock045_2K/Rock045_2K-JPG_NormalGL.jpg` |
| Gravel015 | ambientCG | https://ambientcg.com/view?id=Gravel015 | CC0 | 2026-10-11 | `ambientcg.com/Gravel015_2K/Gravel015_2K-JPG_Color.jpg`, `ambientcg.com/Gravel015_2K/Gravel015_2K-JPG_NormalGL.jpg` |
| island_tree_01 | Poly Haven | https://polyhaven.com/a/island_tree_01 | CC0 | 2026-10-11 | `polyhaven.com/island_tree_01/island_tree_01_lo.res`, `polyhaven.com/island_tree_01/island_tree_01_giant.res` |
| island_tree_02 | Poly Haven | https://polyhaven.com/a/island_tree_02 | CC0 | 2026-10-11 | `polyhaven.com/island_tree_02/island_tree_02_lo.res` |
| island_tree_03 | Poly Haven | https://polyhaven.com/a/island_tree_03 | CC0 | 2026-10-11 | `polyhaven.com/island_tree_03/island_tree_03_lo.res` |
| shrub_02 | Poly Haven | https://polyhaven.com/a/shrub_02 | CC0 | 2026-10-11 | `polyhaven.com/shrub_02/shrub_02_lo.res` |
| shrub_03 | Poly Haven | https://polyhaven.com/a/shrub_03 | CC0 | 2026-10-11 | `polyhaven.com/shrub_03/shrub_03_lo.res` |
| shrub_04 | Poly Haven | https://polyhaven.com/a/shrub_04 | CC0 | 2026-10-11 | `polyhaven.com/shrub_04/shrub_04_lo.res` |
| rock_07 | Poly Haven | https://polyhaven.com/a/rock_07 | CC0 | 2026-10-11 | `polyhaven.com/rock_07/rock_07_lo.res` |
| rock_09 | Poly Haven | https://polyhaven.com/a/rock_09 | CC0 | 2026-10-11 | `polyhaven.com/rock_09/rock_09_lo.res` |
| boulder_01 | Poly Haven | https://polyhaven.com/a/boulder_01 | CC0 | 2026-10-11 | `polyhaven.com/boulder_01/boulder_01_lo.res` |
| dead_tree_trunk | Poly Haven | https://polyhaven.com/a/dead_tree_trunk | CC0 | 2026-10-11 | `polyhaven.com/dead_tree_trunk/dead_tree_trunk_lo.res` |
| grass_medium_02 | Poly Haven | https://polyhaven.com/a/grass_medium_02 | CC0 | 2026-10-11 | `polyhaven.com/grass_medium_02/grass_medium_02_lo.res` |
| fern_02 | Poly Haven | https://polyhaven.com/a/fern_02 | CC0 | 2026-10-11 | `polyhaven.com/fern_02/fern_02_2k.gltf`, `polyhaven.com/fern_02/fern_02.bin`, `polyhaven.com/fern_02/textures/fern_02_arm_2k.jpg`, `polyhaven.com/fern_02/textures/fern_02_diff_2k.jpg`, `polyhaven.com/fern_02/textures/fern_02_nor_gl_2k.jpg` |
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
HDRI-панорамы Poly Haven (П5.7, блок 3) — небо мира: день/закат/ночь
смешиваются по времени суток в `assets/shaders/sky.gdshader`.
Наборы KayKit — персонажи игрока (раздел 16 SPEC, v2.3): три модели на общем
риге Rig_Medium и скелетные клипы анимаций на том же риге.
