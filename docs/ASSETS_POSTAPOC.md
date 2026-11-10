# Аудит ассетов для постапокалипсиса (новая игра)

Дата: 2026-11-10. Ветка: `postapoc-assets` (от `born-unblessed`). Задача: заброшенный
городной район (панельные пятиэтажки с входи́мыми подъездами/квартирами, разбитые машины,
мусор, заросшие дворы), стиль — РЕАЛИЗМ. Код проекта не менялся.

## Сводка

- Источники на сервере: `~/blockparty/library/` (ambientCG 31 ГБ, Poly Haven 21 ГБ,
  OpenGameArt 39 МБ + `catalog.csv`/`manifest.json`), а также `~/assets_inbox`,
  `~/assets_manual`, `~/kit_review`, `~/cmp_art`, `~/projects`, `~/shared`,
  `~/stage_boujie`, `~/blockparty/.downloads`, `~/mpfb_assets`, `~/mixamo_raw`,
  `assets/third_party/` в репо.
- **Всё выложенное — CC0**, стиль — фотореалистичные фотосканы (Poly Haven / ambientCG).
- Выложено: **161 набор, ~495 МБ** → `assets_inbox/postapoc/` (LFS). Титры:
  `assets_inbox/postapoc/LICENSES.md`.
- Приоритет выкладки по заданию: текстуры п.4 → уличные модели → интерьер.
- Ключевой вывод: **панельных домов, подъездов, ванн, батарей, разбитых машин и плюща
  в источниках НЕТ** — см. «Пробелы».

## Выложено (assets_inbox/postapoc/)

Форматы: модели — glTF (`.gltf`+`.bin`) с текстурами 1k jpg; текстуры — PBR-наборы
jpg 1K (ambientCG: Color/Displacement/NormalGL; Poly Haven: ao/arm/diffuse/displacement/nor_gl).
Треугольники посчитаны из glTF-accessors. Все наборы CC0, атрибуция не требуется,
но авторы перечислены. Полные таблицы с авторами и ссылками — в
`assets_inbox/postapoc/LICENSES.md` (те же данные).

#### Здания и части (модели)

| Ассет | Папка | ~трис | МБ | Автор | Лицензия | Источник |
|---|---|---|---|---|---|---|
| Modular Urban Apartments Facade | `modular_urban_apartments_facade` | 270045 | 16.2 | James Ray Cock | CC0 | https://polyhaven.com/a/modular_urban_apartments_facade |
| Modular Fire Escape | `modular_fire_escape` | 11322 | 4.6 | Juniix | CC0 | https://polyhaven.com/a/modular_fire_escape |
| Rollershutter Window 01 | `rollershutter_window_01` | 1104 | 2.7 | MP | CC0 | https://polyhaven.com/a/rollershutter_window_01 |
| Rollershutter Window 03 | `rollershutter_window_03` | 1120 | 2.7 | MP | CC0 | https://polyhaven.com/a/rollershutter_window_03 |
| Rollershutter Door | `rollershutter_door` | 1104 | 2.8 | MP | CC0 | https://polyhaven.com/a/rollershutter_door |
| Modular Chainlink Fence | `modular_chainlink_fence` | 89232 | 7.0 | James Ray Cock,Amal Kumar | CC0 | https://polyhaven.com/a/modular_chainlink_fence |
| Modular Electricity Poles | `modular_electricity_poles` | 200610 | 12.5 | James Ray Cock | CC0 | https://polyhaven.com/a/modular_electricity_poles |
| Modular Electric Cables | `modular_electric_cables` | 42078 | 6.2 | Kuutti Siitonen | CC0 | https://polyhaven.com/a/modular_electric_cables |
| Modular Metal Gutter | `modular_metal_gutter` | 16490 | 2.6 | Maxim Domnin | CC0 | https://polyhaven.com/a/modular_metal_gutter |
| Water Manhole Cover | `water_manhole_cover` | 6301 | 2.7 | Raunox | CC0 | https://polyhaven.com/a/water_manhole_cover |
| Large Iron Gate | `large_iron_gate` | 38140 | 3.6 | Josh Dean | CC0 | https://polyhaven.com/a/large_iron_gate |

#### Улица, дворы, мусор (модели)

| Ассет | Папка | ~трис | МБ | Автор | Лицензия | Источник |
|---|---|---|---|---|---|---|
| Metal Trash Can | `metal_trash_can` | 13960 | 5.3 | GurJas Studios | CC0 | https://polyhaven.com/a/metal_trash_can |
| Trashbag | `trashbag` | 4482 | 1.9 | Benny Weimer | CC0 | https://polyhaven.com/a/trashbag |
| Old Tyre | `old_tyre` | 2880 | 2.8 | MP | CC0 | https://polyhaven.com/a/old_tyre |
| Rusted Wheel Rim 01 | `rusted_wheel_rim_01` | 16440 | 3.0 | John Hutcheson | CC0 | https://polyhaven.com/a/rusted_wheel_rim_01 |
| Rusted Wheel Rim 02 | `rusted_wheel_rim_02` | 15256 | 3.0 | John Hutcheson | CC0 | https://polyhaven.com/a/rusted_wheel_rim_02 |
| Concrete Road Barrier | `concrete_road_barrier` | 60928 | 4.3 | Amal Kumar | CC0 | https://polyhaven.com/a/concrete_road_barrier |
| Street Lamp 01 | `street_lamp_01` | 30610 | 2.4 | Josh Dean | CC0 | https://polyhaven.com/a/street_lamp_01 |
| Fire Hydrant | `fire_hydrant` | 86316 | 5.8 | Gonçalo Felício | CC0 | https://polyhaven.com/a/fire_hydrant |
| Painted Wooden Bench | `painted_wooden_bench` | 630 | 2.4 | Kirill Sannikov | CC0 | https://polyhaven.com/a/painted_wooden_bench |
| Covered Car | `covered_car` | 12592 | 2.8 | MP | CC0 | https://polyhaven.com/a/covered_car |
| Can Rusted | `can_rusted` | 3520 | 2.7 | Rahul Chaudhary | CC0 | https://polyhaven.com/a/can_rusted |
| Wine Bottles 01 | `wine_bottles_01` | 28848 | 3.8 | Rico Cilliers,Jurita Burger | CC0 | https://polyhaven.com/a/wine_bottles_01 |
| Metal Jerrycan | `metal_jerrycan` | 20022 | 3.5 | Sean Buckley | CC0 | https://polyhaven.com/a/metal_jerrycan |
| Cardboard Box 01 | `cardboard_box_01` | 16952 | 2.6 | Rahul Chaudhary | CC0 | https://polyhaven.com/a/cardboard_box_01 |
| Old Military Crate | `old_military_crate` | 10476 | 3.1 | Jack Mava | CC0 | https://polyhaven.com/a/old_military_crate |
| Spray Paint Bottles | `spray_paint_bottles` | 5040 | 2.5 | James Ray Cock | CC0 | https://polyhaven.com/a/spray_paint_bottles |
| Korean Fire Extinguisher 01 | `korean_fire_extinguisher_01` | 9913 | 1.5 | UM JOORIN | CC0 | https://polyhaven.com/a/korean_fire_extinguisher_01 |
| Security Camera 01 | `security_camera_01` | 13571 | 2.2 | Alexander Otterbeck,Yann Kervran | CC0 | https://polyhaven.com/a/security_camera_01 |
| Exterior Aircon Unit | `exterior_aircon_unit` | 18986 | 7.3 | Monsta3D | CC0 | https://polyhaven.com/a/exterior_aircon_unit |
| Korean Public Payphone 01 | `korean_public_payphone_01` | 48132 | 5.5 | UM JOORIN | CC0 | https://polyhaven.com/a/korean_public_payphone_01 |
| Old Gas Mask | `old_gas_mask` | 18900 | 2.6 | Michał Wiśniewski | CC0 | https://polyhaven.com/a/old_gas_mask |
| Russian Food Cans 01 | `russian_food_cans_01` | 1348 | 2.0 | Kosan Aziz | CC0 | https://polyhaven.com/a/russian_food_cans_01 |
| Oil Tin | `oil_tin` | 2834 | 2.6 | Niklas | CC0 | https://polyhaven.com/a/oil_tin |
| Barrel_01 | `Barrel_01` | 2682 | 0.7 | Jorge Camacho | CC0 | https://polyhaven.com/a/Barrel_01 |
| Barrel 02 | `Barrel_02` | 2688 | 0.5 | Jorge Camacho | CC0 | https://polyhaven.com/a/Barrel_02 |
| Street Rat | `street_rat` | 57216 | 3.9 | Sean Buckley | CC0 | https://polyhaven.com/a/street_rat |

#### Интерьер (модели)

| Ассет | Папка | ~трис | МБ | Автор | Лицензия | Источник |
|---|---|---|---|---|---|---|
| Old Bed Frame | `old_bed_frame` | 49990 | 4.5 | Luca B | CC0 | https://polyhaven.com/a/old_bed_frame |
| Electric Stove | `electric_stove` | 13914 | 2.4 | Kuutti Siitonen | CC0 | https://polyhaven.com/a/electric_stove |
| Scandinavian Masonry Heater | `scandinavian_masonry_heater` | 9350 | 3.0 | Kuutti Siitonen | CC0 | https://polyhaven.com/a/scandinavian_masonry_heater |
| Vintage Microwave | `vintage_microwave` | 8120 | 2.0 | Adam Nekola | CC0 | https://polyhaven.com/a/vintage_microwave |
| Television 01 | `Television_01` | 1918 | 0.6 | Gabriel Radić | CC0 | https://polyhaven.com/a/Television_01 |
| Television 02 | `television_02` | 2310 | 1.6 | Benny Weimer | CC0 | https://polyhaven.com/a/television_02 |
| Wooden Bookshelf Worn | `wooden_bookshelf_worn` | 10106 | 3.4 | Ulan Cabanilla | CC0 | https://polyhaven.com/a/wooden_bookshelf_worn |
| Worn Metal Rack | `worn_metal_rack` | 6372 | 2.5 | Luca B | CC0 | https://polyhaven.com/a/worn_metal_rack |
| Steel Frame Shelves 01 | `steel_frame_shelves_01` | 4348 | 2.0 | James Ray Cock | CC0 | https://polyhaven.com/a/steel_frame_shelves_01 |
| Painted Wooden Cabinet | `painted_wooden_cabinet` | 2227 | 2.4 | Kirill Sannikov | CC0 | https://polyhaven.com/a/painted_wooden_cabinet |
| Painted Wooden Sofa | `painted_wooden_sofa` | 5826 | 2.6 | Kirill Sannikov | CC0 | https://polyhaven.com/a/painted_wooden_sofa |
| Painted Wooden Table | `painted_wooden_table` | 600 | 2.2 | Kirill Sannikov | CC0 | https://polyhaven.com/a/painted_wooden_table |
| Painted Wooden Chair 01 | `painted_wooden_chair_01` | 724 | 0.6 | Kuutti Siitonen | CC0 | https://polyhaven.com/a/painted_wooden_chair_01 |
| Arm Chair 01 | `ArmChair_01` | 5626 | 0.9 | Kirill Sannikov | CC0 | https://polyhaven.com/a/ArmChair_01 |
| Sofa 01 | `Sofa_01` | 4101 | 0.6 | Kirill Sannikov | CC0 | https://polyhaven.com/a/Sofa_01 |
| Coffee Table 01 | `CoffeeTable_01` | 10404 | 1.1 | Fernando Quinn | CC0 | https://polyhaven.com/a/CoffeeTable_01 |
| Gothic Bed 01 | `GothicBed_01` | 18745 | 1.2 | Kirill Sannikov | CC0 | https://polyhaven.com/a/GothicBed_01 |
| Classic Nightstand 01 | `ClassicNightstand_01` | 2002 | 0.5 | Kirill Sannikov | CC0 | https://polyhaven.com/a/ClassicNightstand_01 |
| Throw Pillows 01 | `throw_pillows_01` | 6362 | 1.4 | Serhii Khromov | CC0 | https://polyhaven.com/a/throw_pillows_01 |
| Ceiling Fan | `ceiling_fan` | 16356 | 2.2 | Ulan Cabanilla | CC0 | https://polyhaven.com/a/ceiling_fan |
| Wheelchair 01 | `wheelchair_01` | 40252 | 1.8 | Garreth Dean | CC0 | https://polyhaven.com/a/wheelchair_01 |
| Vintage Cabinet 01 | `vintage_cabinet_01` | 61096 | 2.7 | Rico Cilliers | CC0 | https://polyhaven.com/a/vintage_cabinet_01 |

#### Растительность поверх построек / дворы (модели)

| Ассет | Папка | ~трис | МБ | Автор | Лицензия | Источник |
|---|---|---|---|---|---|---|
| Moss 01 | `moss_01` | 204 | 1.0 | Rob Tuytel | CC0 | https://polyhaven.com/a/moss_01 |
| Rock Moss Set 01 | `rock_moss_set_01` | 63127 | 2.0 | Kless Gyzen | CC0 | https://polyhaven.com/a/rock_moss_set_01 |
| Rock Moss Set 02 | `rock_moss_set_02` | 57647 | 2.0 | Kless Gyzen | CC0 | https://polyhaven.com/a/rock_moss_set_02 |
| Weed Plant 02 | `weed_plant_02` | 11116 | 2.4 | Rob Tuytel,Rico Cilliers | CC0 | https://polyhaven.com/a/weed_plant_02 |
| Nettle Plant | `nettle_plant` | 31304 | 2.7 | Rob Tuytel,Rico Cilliers | CC0 | https://polyhaven.com/a/nettle_plant |
| Dandelion 01 | `dandelion_01` | 54764 | 3.4 | Rob Tuytel,Rico Cilliers | CC0 | https://polyhaven.com/a/dandelion_01 |
| Grass Medium 01 | `grass_medium_01` | 24730 | 3.3 | Rob Tuytel,Rico Cilliers | CC0 | https://polyhaven.com/a/grass_medium_01 |
| Grass Medium 02 | `grass_medium_02` | 7842 | 0.9 | Rico Cilliers | CC0 | https://polyhaven.com/a/grass_medium_02 |
| Dead Tree Trunk | `dead_tree_trunk` | 101802 | 5.2 | Rob Tuytel | CC0 | https://polyhaven.com/a/dead_tree_trunk |
| Dry Branches Medium 01 | `dry_branches_medium_01` | 16803 | 3.8 | Rico Cilliers | CC0 | https://polyhaven.com/a/dry_branches_medium_01 |
| Shrub 02 | `shrub_02` | 27254 | 2.3 | Rico Cilliers | CC0 | https://polyhaven.com/a/shrub_02 |
| Shrub 03 | `shrub_03` | 8287 | 2.0 | Rico Cilliers | CC0 | https://polyhaven.com/a/shrub_03 |
| Shrub 04 | `shrub_04` | 27327 | 2.2 | Rico Cilliers | CC0 | https://polyhaven.com/a/shrub_04 |
| Pine Roots | `pine_roots` | 162693 | 9.3 | Rob Tuytel | CC0 | https://polyhaven.com/a/pine_roots |

#### Текстуры Poly Haven (polyhaven/textures, все CC0, 1k PBR-наборы)

| Ассет | Папка | МБ | Лицензия | Источник |
|---|---|---|---|---|
| Asphalt 02 | `asphalt_02` | 3.0 | CC0 | https://polyhaven.com/a/asphalt_02 |
| Brick Moss 001 | `brick_moss_001` | 1.0 | CC0 | https://polyhaven.com/a/brick_moss_001 |
| Broken Brick Wall | `broken_brick_wall` | 3.4 | CC0 | https://polyhaven.com/a/broken_brick_wall |
| Brown Mud Dry | `brown_mud_dry` | 4.3 | CC0 | https://polyhaven.com/a/brown_mud_dry |
| Chipped Concrete | `chipped_concrete` | 3.5 | CC0 | https://polyhaven.com/a/chipped_concrete |
| Cobblestone Embedded Asphalt | `cobblestone_embedded_asphalt` | 4.1 | CC0 | https://polyhaven.com/a/cobblestone_embedded_asphalt |
| Concrete Block Wall | `concrete_block_wall` | 3.3 | CC0 | https://polyhaven.com/a/concrete_block_wall |
| Concrete Debris | `concrete_debris` | 4.5 | CC0 | https://polyhaven.com/a/concrete_debris |
| Concrete Floor Damaged 01 | `concrete_floor_damaged_01` | 2.4 | CC0 | https://polyhaven.com/a/concrete_floor_damaged_01 |
| Concrete Floor Worn 001 | `concrete_floor_worn_001` | 0.6 | CC0 | https://polyhaven.com/a/concrete_floor_worn_001 |
| Concrete Moss | `concrete_moss` | 2.3 | CC0 | https://polyhaven.com/a/concrete_moss |
| Concrete Panels | `concrete_panels` | 2.6 | CC0 | https://polyhaven.com/a/concrete_panels |
| Concrete Slab Wall | `concrete_slab_wall` | 2.6 | CC0 | https://polyhaven.com/a/concrete_slab_wall |
| Concrete Tile Facade | `concrete_tile_facade` | 3.2 | CC0 | https://polyhaven.com/a/concrete_tile_facade |
| Cracked Concrete 02 | `cracked_concrete_02` | 3.7 | CC0 | https://polyhaven.com/a/cracked_concrete_02 |
| Cracked Concrete Wall | `cracked_concrete_wall` | 3.4 | CC0 | https://polyhaven.com/a/cracked_concrete_wall |
| Damaged Concrete Floor 03 | `damaged_concrete_floor_03` | 2.4 | CC0 | https://polyhaven.com/a/damaged_concrete_floor_03 |
| Decrepit Wallpaper | `decrepit_wallpaper` | 2.5 | CC0 | https://polyhaven.com/a/decrepit_wallpaper |
| Dirt | `dirt` | 3.5 | CC0 | https://polyhaven.com/a/dirt |
| Dirty Concrete | `dirty_concrete` | 1.6 | CC0 | https://polyhaven.com/a/dirty_concrete |
| Dirty Tiles | `dirty_tiles` | 2.1 | CC0 | https://polyhaven.com/a/dirty_tiles |
| Distressed Painted Planks | `distressed_painted_planks` | 1.4 | CC0 | https://polyhaven.com/a/distressed_painted_planks |
| Factory Brick | `factory_brick` | 3.3 | CC0 | https://polyhaven.com/a/factory_brick |
| Grass Concrete Pavement | `grass_concrete_pavement` | 5.6 | CC0 | https://polyhaven.com/a/grass_concrete_pavement |
| Gravel Road | `gravel_road` | 2.7 | CC0 | https://polyhaven.com/a/gravel_road |
| Green Metal Rust | `green_metal_rust` | 1.7 | CC0 | https://polyhaven.com/a/green_metal_rust |
| Long White Tiles | `long_white_tiles` | 2.5 | CC0 | https://polyhaven.com/a/long_white_tiles |
| Metal Grate Rusty | `metal_grate_rusty` | 3.9 | CC0 | https://polyhaven.com/a/metal_grate_rusty |
| Mossy Brick | `mossy_brick` | 3.4 | CC0 | https://polyhaven.com/a/mossy_brick |
| Old Linoleum Flooring 01 | `old_linoleum_flooring_01` | 2.2 | CC0 | https://polyhaven.com/a/old_linoleum_flooring_01 |
| Old Wood Floor | `old_wood_floor` | 2.8 | CC0 | https://polyhaven.com/a/old_wood_floor |
| Overgrown Concrete Pavers | `overgrown_concrete_pavers` | 2.5 | CC0 | https://polyhaven.com/a/overgrown_concrete_pavers |
| Painted Plaster Wall | `painted_plaster_wall` | 3.0 | CC0 | https://polyhaven.com/a/painted_plaster_wall |
| Painted Worn Brick | `painted_worn_brick` | 3.8 | CC0 | https://polyhaven.com/a/painted_worn_brick |
| Peeling Painted Wall | `peeling_painted_wall` | 3.1 | CC0 | https://polyhaven.com/a/peeling_painted_wall |
| Precast Concrete Wall | `precast_concrete_wall` | 2.9 | CC0 | https://polyhaven.com/a/precast_concrete_wall |
| Rebar Reinforced Concrete | `rebar_reinforced_concrete` | 3.2 | CC0 | https://polyhaven.com/a/rebar_reinforced_concrete |
| Red Brick 03 | `red_brick_03` | 3.3 | CC0 | https://polyhaven.com/a/red_brick_03 |
| Red Brick Plaster Patch 02 | `red_brick_plaster_patch_02` | 3.1 | CC0 | https://polyhaven.com/a/red_brick_plaster_patch_02 |
| Ribbed Concrete Wall | `ribbed_concrete_wall` | 3.5 | CC0 | https://polyhaven.com/a/ribbed_concrete_wall |
| Road Damaged | `road_damaged` | 3.5 | CC0 | https://polyhaven.com/a/road_damaged |
| Road Damaged 2 | `road_damaged_2` | 3.5 | CC0 | https://polyhaven.com/a/road_damaged_2 |
| Rough Concrete | `rough_concrete` | 4.7 | CC0 | https://polyhaven.com/a/rough_concrete |
| Rough Plaster Brick | `rough_plaster_brick` | 3.2 | CC0 | https://polyhaven.com/a/rough_plaster_brick |
| Rough Plaster Broken | `rough_plaster_broken` | 2.5 | CC0 | https://polyhaven.com/a/rough_plaster_broken |
| Rusted Shutter | `rusted_shutter` | 3.9 | CC0 | https://polyhaven.com/a/rusted_shutter |
| Rusty Corrugated Iron | `rusty_corrugated_iron` | 2.3 | CC0 | https://polyhaven.com/a/rusty_corrugated_iron |
| Rusty Metal 03 | `rusty_metal_03` | 2.7 | CC0 | https://polyhaven.com/a/rusty_metal_03 |
| Rusty Metal Sheet | `rusty_metal_sheet` | 2.6 | CC0 | https://polyhaven.com/a/rusty_metal_sheet |
| Rusty Painted Metal | `rusty_painted_metal` | 1.8 | CC0 | https://polyhaven.com/a/rusty_painted_metal |
| Weathered Peeling Timber | `weathered_peeling_timber` | 2.9 | CC0 | https://polyhaven.com/a/weathered_peeling_timber |
| Whitewashed Brick | `whitewashed_brick` | 3.3 | CC0 | https://polyhaven.com/a/whitewashed_brick |
| Wood Peeling Paint Weathered | `wood_peeling_paint_weathered` | 3.8 | CC0 | https://polyhaven.com/a/wood_peeling_paint_weathered |
| Worn Brick Wall | `worn_brick_wall` | 3.7 | CC0 | https://polyhaven.com/a/worn_brick_wall |
| Worn Concrete Floor | `worn_concrete_floor` | 3.2 | CC0 | https://polyhaven.com/a/worn_concrete_floor |
| Worn Cracked Plaster | `worn_cracked_plaster` | 3.0 | CC0 | https://polyhaven.com/a/worn_cracked_plaster |
| Worn Mossy Plasterwall | `worn_mossy_plasterwall` | 3.4 | CC0 | https://polyhaven.com/a/worn_mossy_plasterwall |
| Worn Plaster Wall | `worn_plaster_wall` | 2.3 | CC0 | https://polyhaven.com/a/worn_plaster_wall |

#### Текстуры ambientCG (ambientcg/<Категория>/<ID>, все CC0, 1K PBR)

| Ассет | Папка | МБ | Лицензия | Источник |
|---|---|---|---|---|
| AsphaltDamage001 | `AsphaltDamage001` | 3.9 | CC0 | https://ambientcg.com/view?id=AsphaltDamage001 |
| Carpet002 | `Carpet002` | 5.0 | CC0 | https://ambientcg.com/view?id=Carpet002 |
| CorrugatedSteel001 | `CorrugatedSteel001` | 2.1 | CC0 | https://ambientcg.com/view?id=CorrugatedSteel001 |
| CorrugatedSteel003 | `CorrugatedSteel003` | 3.0 | CC0 | https://ambientcg.com/view?id=CorrugatedSteel003 |
| Door001 | `Door001` | 0.7 | CC0 | https://ambientcg.com/view?id=Door001 |
| Door002 | `Door002` | 2.5 | CC0 | https://ambientcg.com/view?id=Door002 |
| Facade001 | `Facade001` | 1.1 | CC0 | https://ambientcg.com/view?id=Facade001 |
| Facade003 | `Facade003` | 1.2 | CC0 | https://ambientcg.com/view?id=Facade003 |
| Fence002 | `Fence002` | 3.2 | CC0 | https://ambientcg.com/view?id=Fence002 |
| GraffitiSet001 | `GraffitiSet001` | 1.2 | CC0 | https://ambientcg.com/view?id=GraffitiSet001 |
| Leaking001 | `Leaking001` | 1.5 | CC0 | https://ambientcg.com/view?id=Leaking001 |
| Leaking003 | `Leaking003` | 1.6 | CC0 | https://ambientcg.com/view?id=Leaking003 |
| ManholeCover001 | `ManholeCover001` | 3.0 | CC0 | https://ambientcg.com/view?id=ManholeCover001 |
| Moss001 | `Moss001` | 5.4 | CC0 | https://ambientcg.com/view?id=Moss001 |
| Moss002 | `Moss002` | 5.0 | CC0 | https://ambientcg.com/view?id=Moss002 |
| PaintedBricks001 | `PaintedBricks001` | 2.1 | CC0 | https://ambientcg.com/view?id=PaintedBricks001 |
| PaintedBricks003 | `PaintedBricks003` | 2.5 | CC0 | https://ambientcg.com/view?id=PaintedBricks003 |
| PaintedMetal001 | `PaintedMetal001` | 4.3 | CC0 | https://ambientcg.com/view?id=PaintedMetal001 |
| PaintedMetal003 | `PaintedMetal003` | 4.2 | CC0 | https://ambientcg.com/view?id=PaintedMetal003 |
| PaintedPlaster001 | `PaintedPlaster001` | 3.7 | CC0 | https://ambientcg.com/view?id=PaintedPlaster001 |
| PaintedPlaster003 | `PaintedPlaster003` | 3.3 | CC0 | https://ambientcg.com/view?id=PaintedPlaster003 |
| PaintedPlaster005 | `PaintedPlaster005` | 3.6 | CC0 | https://ambientcg.com/view?id=PaintedPlaster005 |
| PavingStones001 | `PavingStones001` | 3.5 | CC0 | https://ambientcg.com/view?id=PavingStones001 |
| PavingStones003 | `PavingStones003` | 3.9 | CC0 | https://ambientcg.com/view?id=PavingStones003 |
| Rust001 | `Rust001` | 1.1 | CC0 | https://ambientcg.com/view?id=Rust001 |
| Rust002 | `Rust002` | 4.0 | CC0 | https://ambientcg.com/view?id=Rust002 |
| Rust003 | `Rust003` | 3.8 | CC0 | https://ambientcg.com/view?id=Rust003 |
| Rust004 | `Rust004` | 4.0 | CC0 | https://ambientcg.com/view?id=Rust004 |
| TireTracks001 | `TireTracks001` | 1.0 | CC0 | https://ambientcg.com/view?id=TireTracks001 |
| Wallpaper001A | `Wallpaper001A` | 3.1 | CC0 | https://ambientcg.com/view?id=Wallpaper001A |

## Найдено в library, подходит по стилю и CC0, но НЕ выложено

Причина — лимит 500 МБ (или дублирование по смыслу уже выложенного). Оригиналы лежат
в `~/blockparty/library/`, пути — в `library/catalog.csv`:

- **Модели:** Modular Factory Facade (16.8 МБ, walls-фасад завода), Overhead Crane (7.6),
  Portable Generator (4.0), Barrel Stove (2.9), Ladder Sectioned (2.9), Old Drill Press,
  Metal Tool Chest, Plastic Crate 02/03, Tool Cart, Industrial Storage Cart, Hand Truck;
  деревья: Island Tree 01–03 (44–82 МБ), Tree Small 02 (97), Fir/Pine Tree (465/914),
  Jacaranda (205) — не влезли в лимит; Root Cluster 01 (9.7), Tree Stump 01/02.
- **Текстуры (примеры тяжёлых):** Park Dirt (36), Mud Cracked Dry Riverbed 002 (31),
  Flower Scattered Dirt (28), Cracked Red Ground (25), Dirt Aerial 02 (17), Rock Wall 01–17
  (21–29 каждый), Old Wooden Floor 01–03, Laminate Floor 01–03, Factory Brick (33),
  Herringbone Brick, крупные Brick Pavement и др.; в ambientCG — остальные ID семейств
  Concrete/PavingStones/Bricks/Planks/Rails/PaintedPlaster (по 4–8 МБ каждый).
- **Удалено из выкладки как дубль по смыслу:** nor_dx/rough/rough_ao-карты и 2K-варианты
  (дублирую GL-нормали и packed-arm), worn_asphalt (≈ asphalt_02 + asphalt_damage),
  dirty_carpet (≈ ambientCG Carpet002), damaged_plaster/wall_bricks_plaster/plaster_brick_01
  (≈ rough_plaster_brick и worn_cracked_plaster), flower_scattered_asphalt
  (≈ overgrown_concrete_pavers + grass_concrete_pavement).

## Не подходит по стилю (в списке для полноты)

- **OpenGameArt (6 наборов, library/opengameart):** только животные. bird и wolf-3d —
  мультяшные/стилизованные (не реализм); deer-female/old-deer-male/rabbit-51722 —
  полу-реализм (.blend/.7z), fish-49204 — CC0 (license.txt внутри zip). Городского
  контента нет. Лицензии по каталогу CC0, файлов лицензий в наборах нет (кроме fish).
- **Kenney:** файлов в репо НЕТ — по `assets/third_party/LICENSES.md` наборы Kenney
  использовались на П4.5 как временная геометрия и удалены. Стиль Kenney (low-poly,
  плоские цвета) под реализм не подходит.
- **Quaternius UBC/MCO (.downloads/ubc, mco):** персонажи CC0 1.0 (License_Standard.txt),
  но low-poly «Fortnite»-стиль — не для сценического реализма (кандидаты только на
  дальние планы; для персонажей уже есть MakeHuman-конвейер).
- **ez-tree (.downloads/ez-tree, MIT):** генератор деревьев, стилизация «под реализм» —
  на грани; может дать сорные деревья/кусты для дворов.

## Прочие источники (не сценические ассеты)

- **MakeHuman/MPFB (`~/assets_inbox`, `~/mpfb_assets`, .downloads):** CC0 — базы тел,
  скины (в т. ч. возрастные/тату), одежда, обувь. Готовая база для выживших/зомби.
- **`~/mixamo_raw` (анимации):** есть паки для зомби/выживших — `Scary Zombie Pack.zip`,
  `Not So Scary Zombie Pack.zip`, `Male Injured Pack.zip`, `Male Drunk Pack.zip`,
  `Creature Pack.zip`. Лицензия Mixamo (Adobe) — не CC0, использовать только по
  правилам Mixamo; в выкладку не включены.
- **Quaternius UAL (.downloads/ual):** анимации Zombie_Idle_Loop, Zombie_Scratch,
  Zombie_Walk_Fwd_Loop, Hit_*, Death01 и др. Файл лицензии в папке отсутствует —
  «не удалось определить» (соседние наборы Quaternius — CC0, но утверждать нельзя).
- **Log Cabin (`~/assets_manual/log_cabin_free_download.glb`, 36.7 МБ, 585k трис):**
  фотореалистичное здание с интерьером, но деревянный сруб; **CC BY 4.0 (Kless)** —
  выкладывать нельзя без указания автора; для панельного района не нужен.
- **Boujie Water Shader (`~/stage_boujie`, MIT):** уже в проекте; лужи/вода.
- **`assets/third_party/` в репо:** только ambientCG+Poly Haven (CC0, фотосканы) —
  мох, кора, краска, доски, старая кладка (old_stone_wall_02 уже используется для руин).
  Меши децимированы до low-poly с запечённым цветом — для новой игры в реализме
  лучше брать оригиналы из library (что и сделано в этой выкладке).

## Пробелы (чего НЕТ ни в одном источнике)

| Категория владельца | Что отсутствует | Суррогаты в выкладке |
|---|---|---|
| Здания и части | **панельные дома/пятиэтажки** (объёмные, входи́мые), подъезды (лестничные клетки, площадки, двери подъездов), квартиры-объёмы, балконы, гаражи, киоски, лестничные пролёты | модульный фасад-притворка apartments, модульная пожарная лестница, рольставни, текстуры панелей/фасадов |
| Интерьер | **ванны**, **батареи/радиаторы**, обои и ковры как модели (есть только текстуры), битое стекло, крупный бытовой хлам россыпью | мебель, плита, печь, микроволновка, телевизоры, картонные коробки, мелкий хлам |
| Улица | **разбитые/ржавые машины** (есть только «машина под тентом»), автобус, качели, качели/горки дворовые, кучи мусора (только урна/мешок/бутылки по отдельности), висящие провода | урна, мешок, покрышка, ржавые диски, барьеры, столбы+кабели, забор, гидрант, люк |
| Текстуры | **битое стекло** | бетон (панели, трещины, сколы, арматура, обломки), кирпич (в т. ч. облупленный/замшелый), облупленная краска (бетон/штукатурка/дерево), ржавчина (8+ сетов), асфальт (обычный/изношенный/разбитый), грязь, мох |
| Растительность на постройках | **плющ** (лианы) | мох (текстуры+модели), сорняки, трава, кусты, корни, сухое дерево |

## Что делать дальше (рекомендация, не сделано)

Панельные дома, подъезды, машины и автобус придётся либо моделировать самим
(Blender, по референсам советской застройки), либо искать отдельные CC0-наборы
на разрешённых сайтах (quaternius/kenney — low-poly, ambientcg/polyhaven — только
текстуры и отдельные пропсы; городских китов CC0 у нас на сервере нет).
