# Цветовая палитра кубического мира (раздел 16 SPEC): мягкие пастельные тона.
# Блоки MeshLibrary острова берут цвета отсюда (раздел 6), персонаж и HUD —
# тоже, чтобы заменить весь визуал одним ресурсом.
# Экземпляр: assets/palette.tres; доступ — `const PAL: Palette = preload(...)`.
class_name Palette
extends Resource

@export_group("Блоки острова (раздел 6)")
@export var grass: Color = Color("a7d9a0")
@export var grass_half: Color = Color("b5e2ae")
@export var dirt: Color = Color("b98a63")
@export var stone: Color = Color("adb5bd")
@export var stone_half: Color = Color("bcc3ca")
@export var sand: Color = Color("f2dfb0")
@export var snow: Color = Color("f1f5f9")
@export var trunk: Color = Color("8a6248")
@export var leaves: Color = Color("7fc97f")
@export var planks: Color = Color("dbb989")
@export var ruin_brick: Color = Color("c3b8a3")
@export var ruin_brick_dark: Color = Color("8d8577")
@export var beacon_glow: Color = Color("ffe08a")
@export var water: Color = Color("7fc8e8")

@export_group("Персонаж и HUD")
@export var player_body: Color = Color("f2f7f5")
@export var player_accent: Color = Color("4cc9f0")
@export var coin: Color = Color("ffd166")
@export var firefly: Color = Color("fff3b0")
@export var hud_text: Color = Color("1d3557")
@export var hud_panel: Color = Color(0.09, 0.13, 0.18, 0.85)

@export_group("Мобы и костёр (П2, раздел 8)")
@export var bird: Color = Color("6a7fcb")
@export var critter: Color = Color("e8955c")
@export var fire: Color = Color("ff9a3d")
