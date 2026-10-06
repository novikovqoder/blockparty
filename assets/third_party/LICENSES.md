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

Наборы Kenney используются как геометрия предметов окружения (шаг 3 этапа
П4.5): модели перекрашиваются в палитры игры вершинными цветами и нормируются
под размеры процедурных мешей — см. `gameplay/world/props/cc0_meshes.gd`.
Наборы KayKit — персонажи игрока (раздел 16 SPEC, v2.3): три модели на общем
риге Rig_Medium и скелетные клипы анимаций на том же риге.
