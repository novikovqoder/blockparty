# Базовый класс секции уровня (раздел 5 SPEC). Секция — Node2D со своей
# статичной геометрией (пол, блоки, ямы, препятствия), которую строит build()
# в локальных координатах: x от 0 до def.width, пол — верх на y = 576,
# игровая зона — 720 px высотой. Данные спавнов живут в ChunkDef
# (используется планировщиком), мобов/монеты создаёт LevelBuilder по плану.
# Не делает: TileMapLayer-визуал появится вместе с тайлами (раздел 5, 14).
class_name Chunk
extends Node2D

const PAL: Palette = preload("res://assets/palette.tres")

## Высота игровой зоны секции, px.
const ZONE_HEIGHT: float = 720.0
## Y верхнего уровня пола во всех секциях (раздел 5: вход/выход на y = 576).
const FLOOR_Y: float = 576.0

var def: ChunkDef
var offset_x: float = 0.0


func setup(p_def: ChunkDef, p_offset_x: float) -> void:
	def = p_def
	offset_x = p_offset_x
	position.x = offset_x


## Геометрию строит подкласс секции.
func build() -> void:
	pass


## Пол от x0 до x1 (включительно по ширине width), верх на FLOOR_Y.
func add_floor(x0: float, width: float, depth: float = ZONE_HEIGHT - FLOOR_Y) -> void:
	var body := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(width, depth)
	shape.shape = box
	shape.position = Vector2(x0 + width * 0.5, FLOOR_Y + depth * 0.5)
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_child(shape)
	add_child(body)
	# Верхняя полоса — «трава», остальное — «земля».
	var grass := Prim.rect(Vector2(width, 12.0), PAL.ground)
	grass.position = Vector2(x0 + width * 0.5, FLOOR_Y + 6.0)
	add_child(grass)
	var soil := Prim.rect(Vector2(width, depth - 12.0), PAL.ground_dark)
	soil.position = Vector2(x0 + width * 0.5, FLOOR_Y + 12.0 + (depth - 12.0) * 0.5)
	add_child(soil)


## Блок-платформа: верхняя грань на top_y, опционально до пола (уступ).
func add_block(cx: float, top_y: float, width: float, height: float, color: Color = PAL.platform) -> void:
	var body := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(width, height)
	shape.shape = box
	shape.position = Vector2(cx, top_y + height * 0.5)
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_child(shape)
	add_child(body)
	add_child(_outlined(Vector2(width, height), color, Vector2(cx, top_y + height * 0.5)))


## Пропасть от x0 до x1: зона «Висит» и тёмный провал; edge_x — левый край
## (HangPoint из def.hang_points должен совпадать с ним).
func add_pit(x0: float, x1: float) -> void:
	var pit := PitArea.new()
	pit.setup(Rect2(x0, FLOOR_Y, x1 - x0, ZONE_HEIGHT - FLOOR_Y), [Vector2(x0, FLOOR_Y)])
	add_child(pit)


## Декоративный блок без коллизии (фон секции).
func add_deco(cx: float, cy: float, size: Vector2, color: Color) -> void:
	add_child(_outlined(size, color, Vector2(cx, cy)))


func _outlined(size: Vector2, color: Color, center: Vector2) -> Node2D:
	var node := Prim.outlined_rect(size, color, PAL.outline)
	node.position = center
	return node
