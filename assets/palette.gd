# Палитры low-poly мира (раздел 16 SPEC): у каждой из шести зон своя гамма
# из 5–7 цветов (ground — тон рельефа, stone — камень зоны, leaf — листва,
# fog — оттенок тумана), цвета рельефа и предметов смешиваются по границам
# зон (веса в terrain.gd). Базовые материалы рельефа (песок у воды, трава,
# камень на склонах, снег на вершинах) — общие, зонный тон подмешивается.
# Персонажи-«мармеладки»: цвет игрока — один из 6 ярких вариантов по хэшу id.
# Экземпляр: assets/palette.tres; доступ — `const PAL: Palette = preload(...)`.
# Порядок зон — IslandGen.ZONES: plaza, forest, ruins, hills, crevasse, lake.
class_name Palette
extends Resource

@export_group("Базовые материалы рельефа (раздел 6)")
@export var sand: Color = Color("eed9a4")
@export var grass: Color = Color("9fce85")
@export var stone: Color = Color("b3bcc4")
@export var snow: Color = Color("f3f6fa")
@export var dirt: Color = Color("b08760")
@export var water: Color = Color("5fc4d4")
@export var water_deep: Color = Color("2e8fa8")

@export_group("Палитры зон (раздел 16)")
## Тон травы/земли зоны — подмешивается к рельефу внутри круга зоны.
@export var zone_ground: PackedColorArray = [
	Color("cdbd72"), Color("5f9e58"), Color("9aa88b"), Color("a9d389"),
	Color("8d8aa0"), Color("e7d5a2"),
]
## Камень зоны: обрывы, стены расщелины, скальные уступы, валуны.
@export var zone_stone: PackedColorArray = [
	Color("c78f6b"), Color("7d8a70"), Color("9aa7b8"), Color("d9cbb0"),
	Color("7b7994"), Color("a8cfc7"),
]
## Листва зоны: кроны деревьев и кустов.
@export var zone_leaf: PackedColorArray = [
	Color("aab45e"), Color("3f7d46"), Color("6f9d6a"), Color("7cc26b"),
	Color("6e7f8d"), Color("77c48f"),
]
## Оттенок тумана в зоне (DayCycle мягко сводит к нему цвет тумана).
@export var zone_fog: PackedColorArray = [
	Color("e9dcbf"), Color("cfe3c2"), Color("ccd5de"), Color("e3e9d2"),
	Color("cfc9dd"), Color("d3ecec"),
]

@export_group("Предметы (раздел 6)")
@export var trunk: Color = Color("8a6248")
@export var planks: Color = Color("d9b077")
@export var ruin_brick: Color = Color("aeb9c2")
@export var ruin_dark: Color = Color("6e7686")
@export var beacon_glow: Color = Color("ffe08a")
## Цветы на лугах (кластеры MultiMesh).
@export var flowers: PackedColorArray = [
	Color("ff8fa3"), Color("ffd166"), Color("c3f584"), Color("bda7ff"),
]

@export_group("Цвета игроков (раздел 16)")
## 6 ярких цветовых вариантов персонажа: тонировка текстуры KayKit
## (albedo_color материала), один и тот же набор для всех трёх персонажей.
## Вариант выдаётся по хэшу id — см. CharacterModel.palette_index.
@export var player_colors: PackedColorArray = [
	Color("ff5a5f"), Color("ffd23f"), Color("8ee04a"),
	Color("2ec4b6"), Color("6a5df0"), Color("f15bb5"),
]
@export var eye: Color = Color("2b2b33")

@export_group("Мобы и огонь (раздел 8)")
@export var bird: Color = Color("6a7fcb")
@export var critter: Color = Color("e8955c")
@export var firefly: Color = Color("ffef9e")
@export var fire: Color = Color("ff9a3d")
@export var coin: Color = Color("ffd166")

@export_group("HUD")
@export var hud_text: Color = Color("1d3557")
@export var hud_panel: Color = Color(0.09, 0.13, 0.18, 0.85)


## Индекс зоны в IslandGen.ZONES (для массивов палитр).
static func zone_index(zone_name: String) -> int:
	match zone_name:
		"plaza": return 0
		"forest": return 1
		"ruins": return 2
		"hills": return 3
		"crevasse": return 4
		"lake": return 5
	return -1
