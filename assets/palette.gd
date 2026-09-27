# Цветовая палитра плейсхолдеров (раздел 14 SPEC): яркие пастельные тона,
# весь визуал этапа 1 берёт цвета отсюда, чтобы заменить одним ресурсом.
# Экземпляр: assets/palette.tres; доступ — `const PAL: Palette = preload(...)`.
class_name Palette
extends Resource

@export_group("Фон и земля")
@export var sky_top: Color = Color("8ecae6")
@export var sky_bottom: Color = Color("d9edf5")
@export var ground: Color = Color("a8d5a2")
@export var ground_dark: Color = Color("7fb87a")
@export var pit: Color = Color("22333b")
@export var outline: Color = Color("2f3e46")

@export_group("Объекты")
@export var platform: Color = Color("b8c6db")
@export var hazard: Color = Color("e29578")
@export var cactus: Color = Color("5fa777")
@export var coin: Color = Color("ffd166")
@export var bird: Color = Color("f4a261")
@export var critter: Color = Color("e76f51")
@export var checkpoint: Color = Color("90e0ef")
@export var finish: Color = Color("ffadad")
@export var ladder: Color = Color("d4a373")
@export var plate: Color = Color("cdb4db")
@export var gate: Color = Color("9d4edd")
@export var golden: Color = Color("fff3b0")
@export var marker: Color = Color("ff9f1c")

@export_group("Игрок и HUD")
@export var player_body: Color = Color("f2f7f5")
@export var player_accent: Color = Color("4cc9f0")
@export var hud_text: Color = Color("1d3557")
@export var hud_panel: Color = Color(0.09, 0.13, 0.18, 0.85)
