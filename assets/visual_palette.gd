# Палитры визуального стиля (раздел 16 SPEC «Визуальная цель», П5.9):
# времена суток задают свет и атмосферу (небо, туман, солнце, окружение),
# зона Леса — цвета земли, травы, деревьев и камней. Все цвета правятся
# в инспекторе без кода (экземпляр — assets/visual_palette.tres).
# Времена суток: рассвет — розово-голубая, день — зелёно-жёлтая,
# закат — оранжево-красная, ночь — сине-фиолетовая.
class_name VisualPalette
extends Resource

@export_group("Рассвет (розово-голубая)")
@export var dawn_sky_top: Color = Color("7288b4")
@export var dawn_sky_horizon: Color = Color("eeb59a")
@export var dawn_fog: Color = Color("cfa3a6")
@export var dawn_sun: Color = Color("ffd7b8")
@export var dawn_ambient: Color = Color("959db8")

@export_group("День (зелёно-жёлтая)")
@export var day_sky_top: Color = Color("6b9bd8")
@export var day_sky_horizon: Color = Color("d6e6df")
@export var day_fog: Color = Color("cfe0d4")
@export var day_sun: Color = Color("fff1d6")
@export var day_ambient: Color = Color("b9c9d6")

@export_group("Закат (оранжево-красная)")
@export var dusk_sky_top: Color = Color("4d4a7d")
@export var dusk_sky_horizon: Color = Color("f6875a")
@export var dusk_fog: Color = Color("df9a7e")
@export var dusk_sun: Color = Color("ff8452")
@export var dusk_ambient: Color = Color("8e7ba6")

@export_group("Ночь (сине-фиолетовая)")
@export var night_sky_top: Color = Color("0d1332")
@export var night_sky_horizon: Color = Color("2b3662")
@export var night_fog: Color = Color("252e4d")
@export var night_sun: Color = Color("a9b9e6")
@export var night_ambient: Color = Color("1c2444")

@export_group("Земля Леса (крупные цветовые пятна)")
## Подстилка — основной тон лесной земли.
@export var ground_litter: Color = Color("86684a")
## Тёмные пятна подстилки (крупные разводы).
@export var ground_litter_dark: Color = Color("6b4f38")
## Влажная земля низин.
@export var ground_wet: Color = Color("4f4234")
## Мох.
@export var ground_moss: Color = Color("55703c")
## Камень крутых склонов.
@export var ground_rock: Color = Color("87898c")
## Тропа и утоптанная Площадь.
@export var ground_path: Color = Color("9b7f5c")

@export_group("Трава Леса")
## Основание травинки (тёмное).
@export var grass_base: Color = Color("3f5c2e")
## Кончик травинки (светлый).
@export var grass_tip: Color = Color("a9c465")
## Сухой оттенок variation (примесь к оттенку пучка).
@export var grass_dry: Color = Color("c2b268")

@export_group("Цветы Леса")
@export var flower_yellow: Color = Color("ffd23f")
@export var flower_purple: Color = Color("a07be0")
@export var flower_white: Color = Color("f2f0e4")

@export_group("Деревья Леса")
## Кора хвойных.
@export var bark_conifer: Color = Color("6e5741")
## Кора лиственных.
@export var bark_deciduous: Color = Color("7d6a52")
## Крона: тень внутри, средний тон, свет снаружи.
@export var canopy_dark: Color = Color("2e4d2b")
@export var canopy_mid: Color = Color("4a7038")
@export var canopy_light: Color = Color("7fa14e")
## Оттенок хвойной хвои (примесь к среднему тону кроны ели/сосны).
@export var canopy_conifer: Color = Color("3d6146")

@export_group("Камни Леса")
## Глыба.
@export var rock_rock: Color = Color("83868a")
## Мох на верхних гранях.
@export var rock_moss: Color = Color("5b7440")
