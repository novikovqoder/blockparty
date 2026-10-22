# Дом жителей — сруб «Log Cabin» Kless (CC-BY 4.0, строка атрибуции в
# assets/third_party/LICENSES.md и титрах). Очередь владельца после
# доработки П5.13: готовая модель вместо процедурных коробок-срубов.
# Модель обработана tools-скриптом вне репозитория (декимация 585k →
# 42k снаружи + 14k интерьер + 27k коллизия, дверь в западной стене
# крыла — реальный сквозной проём 0.85×2.0 м) и лежит штатным Godot-импортом:
#   assets/visual/cabin/log_cabin.glb — меши EXT_* (оболочка),
#   INT_* (интерьер, скрывается дальше INTERIOR_RANGE_M — издалека
#   дом рисуется только корпусом), TERRACE_deck (вариативная терраса)
#   и COLL (грубая геометрия физики: стены, пол, потолок, мебель).
# Здесь обёртка: текстуры CC0 2K (ambientCG/Poly Haven, та же кора и
# доски, что у валежника и причала Леса), тёплый свет внутри и у
# входа (паттерн костра), коллизия слоем 1 — её чувствуют игрок,
# боты и SpringArm камеры (внутри дома камера сама прижимается).
class_name CabinHouse
extends Node3D

const MODEL: PackedScene = preload("res://assets/visual/cabin/log_cabin.glb")

# CC0-текстуры (assets/third_party/LICENSES.md): 2K-карты, у коры и
# досок — те же наборы, что в Лесу и на причале (единый стиль).
const BARK_COLOR: Texture2D = preload(
	"res://assets/third_party/ambientcg.com/Bark001/Bark001_2K-JPG_Color.jpg")
const BARK_NORMAL: Texture2D = preload(
	"res://assets/third_party/ambientcg.com/Bark001/Bark001_2K-JPG_NormalGL.jpg")
const PLANKS_COLOR: Texture2D = preload(
	"res://assets/third_party/ambientcg.com/Planks007/Planks007_2K-JPG_Color.jpg")
const PLANKS_NORMAL: Texture2D = preload(
	"res://assets/third_party/ambientcg.com/Planks007/Planks007_2K-JPG_NormalGL.jpg")
const STONE_COLOR: Texture2D = preload(
	"res://assets/third_party/polyhaven.com/old_stone_wall_02/old_stone_wall_02_diffuse_2k.jpg")
const STONE_NORMAL: Texture2D = preload(
	"res://assets/third_party/polyhaven.com/old_stone_wall_02/old_stone_wall_02_nor_gl_2k.jpg")
const MOSS_COLOR: Texture2D = preload(
	"res://assets/third_party/ambientcg.com/Moss001/Moss001_1K-JPG_Color.jpg")
const WALLPAPER_COLOR: Texture2D = preload(
	"res://assets/third_party/ambientcg.com/PaintedWood006A/PaintedWood006A_2K-JPG_Color.jpg")
const CURTAIN_COLOR: Texture2D = preload(
	"res://assets/third_party/ambientcg.com/Fabric085/Fabric085_2K-JPG_Color.jpg")

## Интерьер не рисуется дальше этого расстояния (пункт 2 очереди
## владельца): издалека — только внешний облик дома.
const INTERIOR_RANGE_M: float = 30.0
## Центр дверного проёма (локальные координаты модели): единственный
## сквозной проход — в западной стене восточного крыла, вход направлен
## на +X (с крытой террасы в комнату крыла). Замерено по геометрии COLL
## (tools/probe_cabin.gd): проём 0.85 м по z (−5.65…−4.80), открыт до
## потолка; пол террасы у порога — y=0.62, пол дома — y=0.16.
const DOOR_LOCAL: Vector3 = Vector3(1.1, 0.62, -5.23)
## Лампа крыльца (в модели — Object_6): подсвет входа снаружи.
const PORCH_LIGHT_LOCAL: Vector3 = Vector3(0.3, 2.45, -5.7)
## Внутренний тёплый свет (паттерн костра, без теней): крыло у входа
## и основная комната. Ночь в доме — уютная, не чёрная.
const WING_LIGHT_LOCAL: Vector3 = Vector3(2.2, 2.2, -5.4)
const HALL_LIGHT_LOCAL: Vector3 = Vector3(-0.5, 2.3, 1.6)
## Габарит вариативной террасы (локальные координаты модели): треугольники
## COLL с центром внутри него уходят в отдельное тело, включаемое вместе
## с террасой — вариант «без террасы» не оставляет невидимого пола.
## Меряется по мешу TERRACE_deck при сборке (с запасом на стену дома).

## Оттенки наружного дерева (брёвна, обшивка, крыша) — вариации фасадов.
const WOOD_TINTS: Array[Color] = [
	Color(1.0, 1.0, 1.0),
	Color(1.0, 0.93, 0.8),
	Color(0.9, 0.87, 0.84),
]

@export var variant: int = 0
@export var terrace: bool = true

static var _material_cache: Dictionary = {}


func _ready() -> void:
	_build()


## Позиция дверного проёма в мире (для теста входа и навигации ботов).
func door_world_pos() -> Vector3:
	return global_transform * DOOR_LOCAL


## Направление «из двери наружу» в мире (на террасу, локально −X).
func door_world_dir() -> Vector3:
	return -(global_transform.basis * Vector3(1.0, 0.0, 0.0)).normalized()


func _build() -> void:
	var model := MODEL.instantiate()
	model.name = "Cabin"
	add_child(model)
	var tint: Color = WOOD_TINTS[clampi(variant, 0, WOOD_TINTS.size() - 1)]
	var terrace_box := AABB()
	for child: Node in model.get_children():
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		if mi.name == "TERRACE_deck":
			terrace_box = mi.mesh.get_aabb().grow(0.05)
	for child: Node in model.get_children():
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var mat_name: String = _material_name(mi)
		if mi.name.begins_with("INT_"):
			mi.visibility_range_end = INTERIOR_RANGE_M
			mi.visibility_range_end_margin = 2.0
		elif mi.name == "TERRACE_deck":
			mi.visible = terrace
		elif mi.name == "COLL":
			# Коллизия строится из меша здесь же; сам меш не должен жить
			# в дереве ни кадра (и рендер, и аудит поверхностей его не видят).
			_attach_collision(mi, terrace_box)
			model.remove_child(mi)
			mi.queue_free()
			continue
		if mat_name != "":
			mi.material_override = _material(mat_name, tint)
	# Лампа крыльца светится всегда (материал emission), тёплый свет
	# у входа и внутри — как у костра, без теней (дешёвая ночь).
	_add_light(PORCH_LIGHT_LOCAL, Color(1.0, 0.8, 0.55), 1.2, 5.0, "PorchLight")
	_add_light(WING_LIGHT_LOCAL, Color(1.0, 0.82, 0.6), 0.9, 5.5, "WingLight")
	_add_light(HALL_LIGHT_LOCAL, Color(1.0, 0.82, 0.6), 1.0, 8.0, "HallLight")


func _material_name(mi: MeshInstance3D) -> String:
	if mi.mesh.get_surface_count() == 0:
		return ""
	var mat := mi.mesh.surface_get_material(0)
	return "" if mat == null else mat.resource_name


func _material(name: String, tint: Color) -> Material:
	var key := "%s|%d" % [name, clampi(variant, 0, WOOD_TINTS.size() - 1)]
	if _material_cache.has(key):
		return _material_cache[key]
	var mat := StandardMaterial3D.new()
	mat.resource_name = "%s_v%d" % [name, clampi(variant, 0, WOOD_TINTS.size() - 1)]
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.roughness = 0.85
	match name:
		"logs_bark":
			mat.albedo_texture = BARK_COLOR
			_normal(mat, BARK_NORMAL, 1.5)
			mat.albedo_color = tint
			mat.roughness = 0.95
		"planks_wall":
			mat.albedo_texture = PLANKS_COLOR
			_normal(mat, PLANKS_NORMAL, 1.0)
			mat.albedo_color = tint * Color(0.96, 0.9, 0.82)
		"planks_roof":
			mat.albedo_texture = PLANKS_COLOR
			_normal(mat, PLANKS_NORMAL, 1.2)
			mat.albedo_color = tint * Color(0.62, 0.55, 0.48)
		"planks_floor":
			mat.albedo_texture = PLANKS_COLOR
			_normal(mat, PLANKS_NORMAL, 1.0)
			mat.albedo_color = Color(0.85, 0.78, 0.68)
		"stone_wall":
			mat.albedo_texture = STONE_COLOR
			_normal(mat, STONE_NORMAL, 1.2)
			mat.roughness = 0.9
		"moss":
			mat.albedo_texture = MOSS_COLOR
			mat.albedo_color = Color(0.9, 1.0, 0.85)
		"wood_frame":
			mat.albedo_texture = PLANKS_COLOR
			_normal(mat, PLANKS_NORMAL, 1.0)
			mat.albedo_color = Color(0.55, 0.47, 0.4)
		"wallpaper":
			mat.albedo_texture = WALLPAPER_COLOR
			mat.albedo_color = Color(0.95, 0.95, 0.95)
		"curtain":
			mat.albedo_texture = CURTAIN_COLOR
			mat.albedo_color = Color(0.85, 0.62, 0.5)
		"glass":
			# Легитимно нетекстурная поверхность (аудит: whitelist имени).
			mat.albedo_color = Color(0.78, 0.86, 0.9, 0.35)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.roughness = 0.15
		"lamp":
			# Светящийся фонарь крыльца: emission без карты.
			mat.albedo_color = Color(0.2, 0.15, 0.1)
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.8, 0.5)
			mat.emission_energy_multiplier = 2.2
		_:
			return null
	_material_cache[key] = mat
	return mat


func _normal(mat: StandardMaterial3D, tex: Texture2D, strength: float) -> void:
	mat.normal_enabled = true
	mat.normal_texture = tex
	mat.normal_scale = strength


func _add_light(local: Vector3, color: Color, energy: float, range_m: float, light_name: String) -> void:
	var light := OmniLight3D.new()
	light.name = light_name
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_m
	light.position = local
	add_child(light)


## Коллизия по мешу COLL: StaticBody3D слоем 1 (маска игрока и SpringArm
## камеры), форма — вогнутая (ConcavePolygonShape3D) из треугольников.
## Треугольники вариативной террасы (центр внутри её габарита) уходят в
## отдельное тело, включаемое вместе с видимостью террасы — вариация
## «без террасы» не оставляет невидимого пола и перил.
func _attach_collision(coll_mi: MeshInstance3D, terrace_box: AABB) -> void:
	var mesh := coll_mi.mesh
	var house_tris: Array[Vector3] = []
	var terrace_tris: Array[Vector3] = []
	for surface: int in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var verts := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var indices := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
		if indices.is_empty():
			continue
		for i: int in range(0, indices.size(), 3):
			var a := verts[indices[i]]
			var b := verts[indices[i + 1]]
			var c := verts[indices[i + 2]]
			if terrace_box.has_point((a + b + c) / 3.0):
				terrace_tris.append(a)
				terrace_tris.append(b)
				terrace_tris.append(c)
			else:
				house_tris.append(a)
				house_tris.append(b)
				house_tris.append(c)
	var house_shape := ConcavePolygonShape3D.new()
	house_shape.set_faces(PackedVector3Array(house_tris))
	var body := SolidBody.add(self, house_shape)
	body.name = "HouseSolid"
	if terrace:
		var terrace_shape := ConcavePolygonShape3D.new()
		terrace_shape.set_faces(PackedVector3Array(terrace_tris))
		var terrace_body := SolidBody.add(self, terrace_shape)
		terrace_body.name = "TerraceSolid"
