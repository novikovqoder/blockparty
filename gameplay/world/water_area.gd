# Вода (раздел 6 SPEC): Area3D-зона плавания + поверхность на своём
# шейдере water_bu (SPEC П14 4 — Boujie Water больше не используется:
# текстур аддона нет вовсе, волны, пена и рябь процедурные). Персонаж
# в зоне плавает на поверхности со скоростью шага (само плавание — в
# Player.enter_water/exit_water); этой зоне всё равно, кто в ней
# плавает, поэтому связь — только вызовы методов тел.
# Поверхности строятся в _ready при входе в дерево (сцена острова
# собирается оффлайн tools/generate_island.gd, меши воды в пакет не
# попадают):
#   море  — нода Ocean аддона как сетка (кольца LOD + дальняя
#     плоскость), следует за камерой (CameraFollower3D; паттерн волн
#     в мировых координатах — движение бесшовно);
#   озеро — плоскость тем же шейдером спокойнее и на LAKE_LIFT выше
#     моря: копланарные поверхности мерцали (z-fighting).
# П14 4: полная версия шейдера (экранная текстура + буфер глубины,
# поглощение Бера по каналам, преломление, пена) — HIGH/ULTRA;
# SIMPLE/NORMAL — water_bu_cheap без экранной выборки. П15-ДОП: волны
# sea_octave по туториалу gameidea (octaves value-шума, Герстнера
# больше нет) — 4 параметра (height/choppiness/speed/frequency), у
# озера и моря свои константы; октав нормалей 5 ULTRA / 4 HIGH, рябь
# (2/3/1 слоя). П15 3: отражение неба — движковое (radiance
# Sky3D с френелем F0 ≈ 0.02, без ambient_light_disabled); SSR движок
# на прозрачную воду не даёт (только opaque) — честно в STATUS.
# П15 4 + 9.2-9.4, П15-ДОП блок 2: пена — по туториалу (маска
# мелководья по толщине + гребни по нормали + Вороной с domain warp,
# emergence-пульсацией, тёмной кромкой и пузырьками), накат — по
# SDF-карте расстояния до берега (ShoreBand.sdf_texture из карты
# высот; море — полоса 2-8 см и накат 10-40 см, озеро — почти без
# пены); кромка воды мягкая — последние 5-15 см толщины гасят всё,
# кроме дна. П15-ДОП блок 5: два пресета палитры — «Туториал»
# (бирюзовая вода gameidea, по умолчанию) и «Born Unblessed» (тёмная
# палитра П12); переключатель — вкладка «Вода» панели F3.
# Не делает: подводное плавание (вне MVP), течение и волны для лодочек.
class_name WaterArea
extends Area3D

const WATER_BU: Shader = preload(
	"res://assets/shaders/water_bu.gdshader")
const WATER_BU_CHEAP: Shader = preload(
	"res://assets/shaders/water_bu_cheap.gdshader")

# --- Палитра воды BU (SPEC П12 4.1, П14 4.1) ---
## Пресет «Born Unblessed» (П15-ДОП блок 5): тёмная палитра П12.
## Озеро и пруды: тёмная торфяная вода — глубина почти чёрная с зелёно-
## бурым отливом, мелководье прозрачное (дно видно).
const LAKE_DEEP: Color = Color(0.016, 0.035, 0.028, 1.0)
const LAKE_SHALLOW: Color = Color(0.10, 0.14, 0.10, 1.0)
## Море: холодная стально-серо-синяя.
const SEA_DEEP: Color = Color(0.02, 0.03, 0.045, 1.0)
const SEA_SHALLOW: Color = Color(0.09, 0.12, 0.14, 1.0)
## Поглощение Бера по каналам, 1/м (SPEC П14 4.1: красный гаснет первым;
## торфяная мгла озера плотнее стального моря). Альфа-каналы палитры
## больше не несут прозрачность — композит воды собирает шейдер.
const LAKE_ABSORPTION: Vector3 = Vector3(1.6, 0.75, 0.45)
const SEA_ABSORPTION: Vector3 = Vector3(1.05, 0.50, 0.34)

## Пресет «Туториал» (П15-ДОП блок 5): бирюзовая вода по туториалу
## gameidea (base_tint/deep/absorption адаптированы под наш объёмный
## цвет); озеро — зеленее и плотнее моря.
const TUT_LAKE_DEEP: Color = Color(0.02, 0.22, 0.13, 1.0)
const TUT_LAKE_SHALLOW: Color = Color(0.32, 0.60, 0.42, 1.0)
const TUT_SEA_DEEP: Color = Color(0.0, 0.20, 0.24, 1.0)
const TUT_SEA_SHALLOW: Color = Color(0.24, 0.60, 0.62, 1.0)
const TUT_LAKE_ABSORPTION: Vector3 = Vector3(0.55, 0.20, 0.09)
const TUT_SEA_ABSORPTION: Vector3 = Vector3(0.35, 0.10, 0.05)

## Пресеты палитры (П15-ДОП блок 5): 4 цвета + поглощение Бера озера
## и моря; переключатель — вкладка «Вода» панели F3, ничего не
## сохраняется. ПО УМОЛЧАНИЮ — «Туториал»; «Born Unblessed» — прежняя
## палитра П12. Имена констант пресета печатает «Скопировать значения»
## (TUT_* / LAKE_*-SEA_*), текст вставляется в этот файл.
const WATER_PRESET_TUTORIAL: StringName = &"tutorial"
const WATER_PRESET_BU: StringName = &"bu"
const WATER_PRESETS: Dictionary = {
	WATER_PRESET_TUTORIAL: {
		"label": "BU_W_PRESET_TUTORIAL",
		"colors": {
			"lake_deep": TUT_LAKE_DEEP,
			"lake_shallow": TUT_LAKE_SHALLOW,
			"sea_deep": TUT_SEA_DEEP,
			"sea_shallow": TUT_SEA_SHALLOW,
		},
		"absorption": {
			"lake": TUT_LAKE_ABSORPTION,
			"sea": TUT_SEA_ABSORPTION,
		},
	},
	WATER_PRESET_BU: {
		"label": "BU_W_PRESET_BU",
		"colors": {
			"lake_deep": LAKE_DEEP,
			"lake_shallow": LAKE_SHALLOW,
			"sea_deep": SEA_DEEP,
			"sea_shallow": SEA_SHALLOW,
		},
		"absorption": {
			"lake": LAKE_ABSORPTION,
			"sea": SEA_ABSORPTION,
		},
	},
}
const WATER_PRESET_DEFAULT: StringName = WATER_PRESET_TUTORIAL
## Активный пресет — общий для всех зон (переключается панелью F3;
## построенные позже поверхности берут его же).
static var _water_preset: StringName = WATER_PRESET_DEFAULT
## Круги на воде при входе — цвет пены, не бирюза палитры.
const RING_COLOR: Color = Color(0.87, 0.92, 0.93)
## Шероховатость воды (П15 2): вблизи — почти зеркало, у горизонта —
## матовое зеркало неба (наклон субпиксельных волн уходит в roughness).
const ROUGHNESS_NEAR: float = 0.03
const ROUGHNESS_FAR: float = 0.16
## Пена по SDF-карте берега (П15 4 + 9.3-9.4): море — выраженная полоса
## у кромки и накат 10-40 см в такт длинной волне; озеро — почти без
## пены, накат чуть-чуть. Ширина полосы 2-8 см.
const SEA_FOAM: float = 1.0
const LAKE_FOAM: float = 0.15
const FOAM_WIDTH: float = 0.06
const SEA_RUNUP: float = 0.35
const LAKE_RUNUP: float = 0.10
## Пена по туториалу (П15-ДОП блок 2): цвет массы (0.75-0.8 — не чисто
## белый, освещается светом сцены), цвет тёмной кромки-тени и номиналы
## силы кромки/пузырьков (ползунки F3 «Вода», блок 5).
const FOAM_COLOR: Color = Color(0.76, 0.77, 0.79, 1.0)
const FOAM_EDGE_COLOR: Color = Color(0.02, 0.03, 0.05, 1.0)
const FOAM_EDGE: float = 0.8
const FOAM_BUBBLES: float = 0.8

# --- Волны sea_octave (П15-ДОП, туториал gameidea) ---
## Четыре параметра волн зоны (height — суммарная высота, м; choppiness —
## острота гребней; speed — скорость дрейфа; freq — базовая частота, 1/м).
## Море — заметная зыбь, озеро — почти гладь (спокойнее по всем осям).
## Стартовые значения — прикидка под наш климат; точный вид владелец
## подбирает ползунками F3 «Вода» («Скопировать значения» печатает их
## обратно в эти константы).
const SEA_WAVE_HEIGHT: float = 0.35
const SEA_WAVE_CHOPPY: float = 4.0
const SEA_WAVE_SPEED: float = 0.8
const SEA_WAVE_FREQ: float = 0.08
const LAKE_WAVE_HEIGHT: float = 0.06
const LAKE_WAVE_CHOPPY: float = 2.5
const LAKE_WAVE_SPEED: float = 0.3
const LAKE_WAVE_FREQ: float = 0.2

## Высота зоны под поверхностью воды, м.
const DEPTH: float = 1.4
## Зона шире этого — море: поверхность строится нодой Ocean с LOD.
const SEA_MIN_SIZE: float = 100.0
## Зеркало озера выше моря, м: близко к нулю, но без копланарного
## мерцания двух полупрозрачных поверхностей (vfx-fix, баг 4).
const LAKE_LIFT: float = 0.03
## Плотность сетки озера, вершин на метр (для мелкой ряби волн).
const LAKE_DENSITY: float = 2.0

## Размер поверхности, м (0 — зона не настроена).
@export var surface_size: Vector2 = Vector2.ZERO
## Уровень воды, абсолютный Y, м.
@export var water_level: float = 0.0
## Насколько зона заканчивается выше поверхности: 0.2 — пруды площадки,
## 0 — море и озеро острова (пляж вплотную к воде, раздел 6).
@export var surface_gap: float = 0.2

var _surface_built: bool = false
## Материалы поверхностей (headless — плоские, тогда пусто): DayCycle
## пишет в них отражение неба и ведёт яркость глубинных цветов по часам.
var _water_materials: Array[ShaderMaterial] = []
## Зона спокойная (озеро/пруды): пена почти выключена, накат минимален.
var _calm: bool = false
## Базовое количество пены зоны (ползунок F3 умножает его).
var _foam_base: float = SEA_FOAM
## Множитель пены от панели F3 (1.0 — номинал).
var _foam_mult: float = FOAM_MULT
## Ширина полосы пены, м (ползунок F3).
var _foam_width: float = FOAM_WIDTH
## Сила тёмной кромки и плотность пузырьков пены (ползунки F3,
## П15-ДОП блок 5).
var _foam_edge: float = FOAM_EDGE
var _foam_bubbles: float = FOAM_BUBBLES
## Базовые (дневные) значения цветов, от которых считается ночной спад.
var _deep_base := Color.BLACK
var _shallow_base := Color.BLACK
## Рябь включена (панель F3): номинал по уровню или 0.
var _ripple_on: bool = true
## Уровень качества построенных поверхностей (волны/рябь/шейдер).
var _tier: int = 0
# --- Круги и каустика (SPEC П15 5-6) ---
## Круги вокруг ног героя: до 4 живых источников в uniform-массиве
## шейдера, слот = (x, z, время старта в секундах TIME шейдера, сила).
## Новый круг — когда герой отошёл от предыдущего на RIPPLE_STEP_M;
## замещается самый старый слот (кольцо живёт ~RING_LIFE_SEC ≈ 2.2 с).
## Локально и без сети: источники не реплицируются (RemotePlayer —
## не Player, в зону коллизии не попадает, круги только у своего героя).
const RIPPLE_SLOTS: int = 4
const RIPPLE_STEP_M: float = 0.55
const RIPPLE_STRENGTH: float = 0.8
## Каустика (номинал яркости, ползунок F3 меняет).
const CAUSTIC_BRIGHTNESS: float = 1.0
## Номиналы ползунков вкладки «Вода» (П15 8.1, панель F3): множители
## от базы. Кнопка «Скопировать значения» печатает эти же имена и
## числа — текст вставляется прямо в константы (цвета и ширина пены
## уже выше: LAKE_/SEA_ палитра, FOAM_WIDTH, ROUGHNESS_*).
const ABSORPTION_MULT: float = 1.0
const WAVE_HEIGHT_MULT: float = 1.0
const WAVE_CHOPPY_MULT: float = 1.0
const WAVE_SPEED_MULT: float = 1.0
const WAVE_FREQ_MULT: float = 1.0
const RIPPLE_STRENGTH_MULT: float = 1.0
const RIPPLE_SCALE_MULT: float = 1.0
const REFRACTION_MULT: float = 1.0
const FOAM_MULT: float = 1.0
var _ripples: PackedVector4Array = PackedVector4Array([
	Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO])
var _ripples_on: bool = true
var _caustic_on: bool = true
var _caustic_brightness: float = CAUSTIC_BRIGHTNESS
var _local_swimmer: Player = null
var _last_ripple_xz := Vector2(INF, INF)
# --- Текущие значения ползунков «Вода» (П15 8.1) ---
## Держатся, чтобы поверхности, построенные после подстройки (площадка
## П1 строит воду в рантайме), получили те же значения, и чтобы
## «Сбросить» в F3 возвращал номиналы. Множители волн общие на озеро
## и море (зона берёт свою базу констант).
var _absorption_mult: float = ABSORPTION_MULT
var _absorption_base := Vector3.ONE
var _wave_h_mult: float = WAVE_HEIGHT_MULT
var _wave_choppy_mult: float = WAVE_CHOPPY_MULT
var _wave_speed_mult: float = WAVE_SPEED_MULT
var _wave_freq_mult: float = WAVE_FREQ_MULT
var _ripple_fx_strength: float = RIPPLE_STRENGTH_MULT
var _ripple_fx_scale: float = RIPPLE_SCALE_MULT
var _refraction_mult: float = REFRACTION_MULT
var _rough_near: float = ROUGHNESS_NEAR
var _rough_far: float = ROUGHNESS_FAR
var _palette_luma: float = 1.0


func _ready() -> void:
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 2  # слой игроков
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	# Группа, не ссылка на сцену: цикл дня находит все поверхности воды
	# и ведёт их отражение неба по часам мира (П5.13, блок 2).
	add_to_group("water_surface")
	# Ресайз окна меняет пиксельный размер волн на экране (П15 2):
	# фильтрация следит за высотой вьюпорта.
	get_viewport().size_changed.connect(_on_viewport_resized)
	if surface_size != Vector2.ZERO:
		_build_surface()


func _on_viewport_resized() -> void:
	for material: ShaderMaterial in _water_materials:
		material.set_shader_parameter(
			"screen_px_height", _screen_px_height())


## Высота вьюпорта в пикселях внутреннего буфера (масштаб 3D учтён):
## для оценки «волна мельче N пикселей» важен порядок, не точность.
func _screen_px_height() -> float:
	var viewport := get_viewport()
	if viewport == null:
		return 720.0
	return float(viewport.size.y) * viewport.scaling_3d_scale


## Построить зону: центр в плоскости XZ, размер, уровень воды (абсолютный Y).
## Коллизия добавляется сразу (сериализуется в сцену), поверхность — при
## входе в дерево, если нода ещё не в нём, иначе сразу (площадка П1 так).
func setup(
	center_xz: Vector2, size: Vector2, level: float, gap: float = 0.2,
) -> void:
	water_level = level
	surface_size = size
	surface_gap = gap
	for child in get_children():
		if child is CollisionShape3D:
			remove_child(child)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, DEPTH + gap, size.y)
	shape.shape = box
	add_child(shape)
	position = Vector3(center_xz.x, level + (gap - DEPTH) * 0.5, center_xz.y)
	if is_inside_tree():
		_build_surface()


func level() -> float:
	return water_level


## Шейдер воды по уровню графики (SPEC П14 4.1/4.7): полная версия с
## экранной текстурой и глубиной — только HIGH/ULTRA, SIMPLE/NORMAL —
## дешёвая water_bu_cheap без экранной выборки.
static func shader_for_tier(tier: int) -> Shader:
	return WATER_BU if tier >= GraphicsQuality.Tier.HIGH \
		else WATER_BU_CHEAP


## Октавы нормалей волн во fragment по уровню (П15-ДОП п. 1/6): 5 ULTRA,
## 4 HIGH (цена — постановка этапа разрешает снижение с 5 до 4);
## SIMPLE/NORMAL — дешёвый шейдер с константой 3, параметр не читает.
static func iter_fragment_for_tier(tier: int) -> int:
	if tier == GraphicsQuality.Tier.ULTRA:
		return 5
	return 4


## Слои процедурной ряби по уровню (SPEC П14 4.3/4.7): 3 ULTRA,
## 2 HIGH, дешёвой версии хватает одного.
static func ripple_layers_for_tier(tier: int) -> int:
	if tier == GraphicsQuality.Tier.ULTRA:
		return 3
	if tier == GraphicsQuality.Tier.HIGH:
		return 2
	return 1



func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		var player := body as Player
		player.enter_water(water_level)
		# Круги на воде при входе в неё (раздел 16); П12 F — цвет пены,
		# не бирюза палитры.
		var pos: Vector3 = player.global_position
		Fx.water_ring(
			get_parent(), Vector3(pos.x, water_level + 0.02, pos.z),
			RING_COLOR,
		)
		# Расходящиеся кольца (П15 6) — вокруг локального героя; круг
		# при входе, дальше — по шагу от последнего.
		_local_swimmer = player
		_last_ripple_xz = Vector2(pos.x, pos.z)
		push_ripple(_last_ripple_xz, 1.0)


func _on_body_exited(body: Node3D) -> void:
	if body is Player:
		(body as Player).exit_water()
		if body == _local_swimmer:
			_local_swimmer = null


func _physics_process(_delta: float) -> void:
	var swimmer := _local_swimmer
	if swimmer == null or not is_instance_valid(swimmer):
		_local_swimmer = null
		return
	if not _ripples_on:
		return
	var xz := Vector2(
		swimmer.global_position.x, swimmer.global_position.z)
	if xz.distance_to(_last_ripple_xz) >= RIPPLE_STEP_M:
		_last_ripple_xz = xz
		push_ripple(xz, RIPPLE_STRENGTH)


## Пустить круг ряби (П15 6): слот с самым старым временем старта
## замещается — одновременно живёт не больше RIPPLE_SLOTS колец.
## Время — TIME шейдера (секунды с запуска движка = ticks_msec/1000).
func push_ripple(xz: Vector2, strength: float) -> void:
	if not _ripples_on or _water_materials.is_empty():
		return
	var now := float(Time.get_ticks_msec()) / 1000.0
	var oldest: int = 0
	for i: int in RIPPLE_SLOTS:
		if _ripples[i].z < _ripples[oldest].z:
			oldest = i
	_ripples[oldest] = Vector4(xz.x, xz.y, now, strength)
	for material: ShaderMaterial in _water_materials:
		material.set_shader_parameter("ripple_sources", _ripples)


func _build_surface() -> void:
	if _surface_built:
		return
	_surface_built = true
	_calm = surface_size.x < SEA_MIN_SIZE
	_foam_base = LAKE_FOAM if _calm else SEA_FOAM
	if surface_size.x >= SEA_MIN_SIZE:
		_build_ocean()
	else:
		_build_lake_plane(surface_size, LAKE_LIFT)


## Море: Ocean аддона (кольца LOD + дальняя плоскость) под камерой.
func _build_ocean() -> void:
	var material := _surface_material(false)
	var ocean := Ocean.new()
	ocean.name = "Ocean"
	ocean.material = material
	ocean.outermost_resolution = 10
	ocean.levels_of_detail = 5
	ocean.unit_size = 1.0
	ocean.far_edge = 1500.0
	ocean.position = Vector3(0.0, water_level - position.y, 0.0)
	add_child(ocean)
	ocean.set_owner(null)  # не сериализовать: строится в рантайме
	# LOD-центр всегда у камеры: паттерн волн в мировых координатах
	# (render_mode world_vertex_coords), движение ноды бесшовно.
	var follower := CameraFollower3D.new()
	follower.name = "CameraFollower3D"
	follower.target_path = ocean.get_path()
	follower.follow_axes = CameraFollower3D.X_AXIS | CameraFollower3D.Z_AXIS
	ocean.add_child(follower)
	follower.set_owner(null)


## Озеро: плоскость с мелкой рябью тем же шейдером (поднята на LAKE_LIFT).
func _build_lake_plane(size: Vector2, lift: float) -> void:
	var surface := MeshInstance3D.new()
	surface.name = "LakeSurface"
	var plane := PlaneMesh.new()
	plane.size = size
	plane.subdivide_width = clampi(int(size.x * LAKE_DENSITY), 2, 192)
	plane.subdivide_depth = clampi(int(size.y * LAKE_DENSITY), 2, 192)
	surface.mesh = plane
	surface.material_override = _surface_material(true)
	surface.position = Vector3(0.0, water_level - position.y + lift, 0.0)
	add_child(surface)
	surface.set_owner(null)  # не сериализовать: строится в рантайме


## В нормальном рендере — свой шейдер water_bu (полная версия на
## HIGH/ULTRA: экранная выборка + глубина + Бер по каналам; дешёвая на
## SIMPLE/NORMAL); в headless (dummy-рендер) — плоская полупрозрачная
## заглушка без волн.
func _surface_material(calm: bool) -> Material:
	# Палитра активного пресета (П15-ДОП блок 5): по умолчанию —
	# «Туториал», панель F3 переключает на «Born Unblessed».
	var preset: Dictionary = WATER_PRESETS[_water_preset]
	var preset_colors: Dictionary = preset["colors"]
	if WorldMaterials.want_flat():
		var flat := StandardMaterial3D.new()
		flat.albedo_color = Color(
			preset_colors["lake_shallow"] if calm
				else preset_colors["sea_shallow"], 0.55)
		flat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		return flat
	# База пены зоны (П15 4): озеро/пруды — почти без пены. Ставится и
	# при прямом вызове (тесты), не только из _build_surface.
	_foam_base = LAKE_FOAM if calm else SEA_FOAM
	_tier = GraphicsQuality.tier_from_settings()
	var material := ShaderMaterial.new()
	material.shader = shader_for_tier(_tier)
	# Цвета — из пресета (озеро/пруды своего тона, море — своего).
	# Ползунок «Вода» (П15 8.1) меняет базовые цвета — ночной спад
	# update_sky считается от них, подстройка живёт и ночью.
	_deep_base = preset_colors["lake_deep"] if calm \
		else preset_colors["sea_deep"]
	_shallow_base = preset_colors["lake_shallow"] if calm \
		else preset_colors["sea_shallow"]
	material.set_shader_parameter("color_deep", _deep_base)
	material.set_shader_parameter("color_shallow", _shallow_base)
	# Поглощение Бера по каналам (П14 4.1): озеро плотнее моря;
	# множитель прозрачности — ползунок (П15 8.1).
	var preset_abs: Dictionary = preset["absorption"]
	_absorption_base = preset_abs["lake"] if calm else preset_abs["sea"]
	material.set_shader_parameter("absorption",
		_absorption_base * _absorption_mult)
	# Волны sea_octave (П15-ДОП): 4 параметра зоны (море — зыбь, озеро —
	# почти гладь) × множители ползунков «Вода»; октавы нормалей — по
	# уровню (5 ULTRA / 4 HIGH, дешёвая версия параметр не читает).
	_apply_wave_params(material, calm)
	material.set_shader_parameter("iter_fragment",
		iter_fragment_for_tier(_tier))
	# Рябь (4.3/4.7) и преломление (4.2): 2–3 слоя на HIGH/ULTRA,
	# один дешёвой версии; сила ряби, её масштаб и сила преломления —
	# ползунки «Вода» (номинал 1.0), галочка замера гасит слоями.
	material.set_shader_parameter(
		"ripple_layers", float(ripple_layers_for_tier(_tier)))
	material.set_shader_parameter("ripple_strength", _ripple_fx_strength)
	material.set_shader_parameter("ripple_scale", _ripple_fx_scale)
	material.set_shader_parameter("refraction_amount", _refraction_mult)
	# П15 3: френель движка F0 ≈ 0.02 (SPECULAR × 0.08 = 0.02).
	material.set_shader_parameter("specular", 0.25)
	# Почти зеркало вблизи, мягко-матовое у горизонта (П15 2: гашение
	# субпиксельных волн переводит их наклон в рост roughness);
	# границы — ползунки «Вода».
	material.set_shader_parameter("roughness_near", _rough_near)
	material.set_shader_parameter("roughness_far", _rough_far)
	material.set_shader_parameter("metallic", 0.0)
	# Пена (П15 4 + 9.3-9.4, П15-ДОП блок 2 — туториал): карта
	# расстояния до береговой линии запекается из карты высот острова
	# (море и озеро на одном уровне — карта одна); море — полоса у
	# кромки и накат, озеро — почти без пены. Масса пены — Вороной
	# туториала (глубина + гребни + SDF-полоса), кромка и пузырьки —
	# цвет и номиналы силы. Дешёвая версия пены не рисует — параметры
	# там не читаются.
	material.set_shader_parameter("shore_sdf",
		ShoreBand.sdf_texture(ShoreBand.ART, IslandGen.SEA_LEVEL))
	material.set_shader_parameter("foam_amount", _foam_base * _foam_mult)
	material.set_shader_parameter("foam_width", _foam_width)
	material.set_shader_parameter("runup_amp",
		LAKE_RUNUP if calm else SEA_RUNUP)
	material.set_shader_parameter("foam_color", FOAM_COLOR)
	material.set_shader_parameter("foam_edge_color", FOAM_EDGE_COLOR)
	material.set_shader_parameter("foam_edge", _foam_edge)
	material.set_shader_parameter("foam_bubbles", _foam_bubbles)
	# Высота экрана для пиксельной фильтрации волн (П15 2): built-in
	# SCREEN_PIXEL_SIZE из fragment в 4.7.2 не виден — размер вьюпорта
	# (с учётом масштаба 3D) несёт uniform.
	material.set_shader_parameter("screen_px_height", _screen_px_height())
	# Растворение к горизонту: эмиссия гаснет (вдали остаётся движковое
	# отражение неба, горизонт сводит туман); «Простая графика»
	# приближает (set_fade_distance от world_scene при far 70).
	material.set_shader_parameter("distance_fade_min", 700.0)
	material.set_shader_parameter("distance_fade_max", 1400.0)
	# Смещение вершин гаснет вдали (внешние кольца Ocean грубые).
	material.set_shader_parameter("vertex_wave_fade_min", 380.0)
	material.set_shader_parameter("vertex_wave_fade_max", 800.0)
	# П15-ДОП2, п. 2: «глубокая» константа — мягкий потолок толщины
	# (tanh в fragment): глубже всё плавно сходится к ней, цвет глубокой
	# воды одинаков внутри карты и за её краем (юбка дна, п. 1).
	material.set_shader_parameter("far_thickness", 16.0)
	# Каустика и круги (П15 5-6): параметры читает только полная версия
	# шейдера (HIGH/ULTRA), дешёвая их не имеет; текущее состояние
	# тумблеров F3 переносится и на построенные позже поверхности.
	material.set_shader_parameter("ripple_sources", _ripples)
	material.set_shader_parameter(
		"ripple_fx_amount", 1.0 if _ripples_on else 0.0)
	material.set_shader_parameter("caustic_brightness",
		_caustic_brightness if _caustic_on else 0.0)
	_water_materials.append(material)
	return material


## «Простая графика» (раздел 15): камера far 70 — растворение воды
## приближается, чтобы край не обрезался видимым обрывом.
func set_fade_distance(fade_min: float, fade_max: float) -> void:
	for material: ShaderMaterial in _water_materials:
		material.set_shader_parameter("distance_fade_min", fade_min)
		material.set_shader_parameter("distance_fade_max", fade_max)


## Растворение воды по уровню графики (баг-фикс П13 п. 5): 46–66 м —
## «Простая графика» (камера far 70, Доработка-2 П5.13 П3); прочие уровни —
## базовая дальность шейдера (700–1400 м) без видимого обрыва: дальняя
## плоскость воды уходит за горизонт.
const FADE_SIMPLE_MIN: float = 46.0
const FADE_SIMPLE_MAX: float = 66.0
const FADE_BASE_MIN: float = 700.0
const FADE_BASE_MAX: float = 1400.0


func set_tier_fade(tier: int) -> void:
	if tier == GraphicsQuality.Tier.SIMPLE:
		set_fade_distance(FADE_SIMPLE_MIN, FADE_SIMPLE_MAX)
		return
	for material: ShaderMaterial in _water_materials:
		material.set_shader_parameter("distance_fade_min", FADE_BASE_MIN)
		material.set_shader_parameter("distance_fade_max", FADE_BASE_MAX)


## Преломление воды на лету (панель замера F3, П14 4.2): сила смещения
## выборки экрана — 0 выключает смещение (толщина и поглощение Бера
## остаются); у дешёвой версии экранной выборки нет — параметр там
## не читается.
func set_refraction(on: bool) -> void:
	for material: ShaderMaterial in _water_materials:
		material.set_shader_parameter(
			"refraction_amount", 1.0 if on else 0.0)


## Рябь воды на лету (панель замера F3, П14 4.3): 0 слоёв — гладкая
## поверхность (волны Герстнера остаются), обратно — номинал уровня.
func set_ripple(on: bool) -> void:
	_ripple_on = on
	var layers: float = float(ripple_layers_for_tier(_tier)) if on else 0.0
	for material: ShaderMaterial in _water_materials:
		material.set_shader_parameter("ripple_layers", layers)


## Пена на лету (ползунки F3 «Вода», П15 8.1): множитель количества
## (озеро остаётся почти без пены — база 0.15) и ширина полосы, м.
func set_foam(mult: float, width: float) -> void:
	_foam_mult = maxf(mult, 0.0)
	_foam_width = clampf(width, 0.02, 0.3)
	for material: ShaderMaterial in _water_materials:
		material.set_shader_parameter(
			"foam_amount", _foam_base * _foam_mult)
		material.set_shader_parameter("foam_width", _foam_width)


## Сила тёмной кромки и плотность пузырьков пены (ползунки F3,
## П15-ДОП блок 5); построенные позже поверхности берут те же.
func set_foam_edge(edge: float, bubbles: float) -> void:
	_foam_edge = clampf(edge, 0.0, 1.0)
	_foam_bubbles = clampf(bubbles, 0.0, 4.0)
	for material: ShaderMaterial in _water_materials:
		material.set_shader_parameter("foam_edge", _foam_edge)
		material.set_shader_parameter("foam_bubbles", _foam_bubbles)


## Круги на воде на лету (галочка F3 «Круги на воде», П15 7): 0 —
## слоты не обновляются и шейдер их не рисует; повторная галочка
## возвращает.
func set_ripples(on: bool) -> void:
	_ripples_on = on
	for material: ShaderMaterial in _water_materials:
		material.set_shader_parameter(
			"ripple_fx_amount", 1.0 if on else 0.0)


## Каустика на лету (галочка F3 «Каустика», П15 7): выключена —
## яркость 0; ползунок яркости (П15 8.1) помнит значение и после
## возврата галочки восстанавливается.
func set_caustic(on: bool) -> void:
	_caustic_on = on
	_apply_caustic_brightness()


func set_caustic_brightness(value: float) -> void:
	_caustic_brightness = clampf(value, 0.0, 4.0)
	_apply_caustic_brightness()


func _apply_caustic_brightness() -> void:
	var value := _caustic_brightness if _caustic_on else 0.0
	for material: ShaderMaterial in _water_materials:
		material.set_shader_parameter("caustic_brightness", value)


# --- Ползунки вкладки «Вода» (П15 8.1) ---
# Пишут uniform'ы всех построенных поверхностей зоны и запоминаются
# для построенных позже; ничего не сохраняют в настройки и не идут
# в сеть — только подбор на глаз (панель F3, П15 8.4). Панель зовёт
# каждую зону из группы water_surface с полным набором — зона берёт
# свои (озеро/море) значения.

## Цвета мелководья и глубины (озеро и море раздельно): меняют базу,
## от которой считает ночной спад update_sky.
func set_palette(
	lake_deep: Color, lake_shallow: Color,
	sea_deep: Color, sea_shallow: Color,
) -> void:
	_deep_base = lake_deep if _calm else sea_deep
	_shallow_base = lake_shallow if _calm else sea_shallow
	_apply_palette()


# --- Пресеты палитры (П15-ДОП блок 5) ---

## Активный пресет воды (все зоны строят поверхности по нему).
static func water_preset() -> StringName:
	return _water_preset


## Выбрать пресет (панель F3): сам ставит общий идентификатор, живые
## зоны обновляет apply_water_preset (панель обходит группу
## water_surface — той же рассылкой, что и ползунки).
static func set_water_preset(id: StringName) -> void:
	if not WATER_PRESETS.has(id):
		return
	_water_preset = id


## Применить активный пресет к зоне: базы цветов и поглощения — из
## пресета, дальше — обычное применение (ползунки сохраняют свои
## множители, ночной спад — свою яркость).
func apply_water_preset() -> void:
	var preset: Dictionary = WATER_PRESETS[_water_preset]
	var preset_colors: Dictionary = preset["colors"]
	var preset_abs: Dictionary = preset["absorption"]
	_deep_base = preset_colors["lake_deep"] if _calm \
		else preset_colors["sea_deep"]
	_shallow_base = preset_colors["lake_shallow"] if _calm \
		else preset_colors["sea_shallow"]
	_absorption_base = preset_abs["lake"] if _calm \
		else preset_abs["sea"]
	for material: ShaderMaterial in _water_materials:
		material.set_shader_parameter("absorption",
			_absorption_base * _absorption_mult)
	_apply_palette()


## Поглощение (прозрачность) — общий множитель констант Бера зоны.
func set_absorption_mult(mult: float) -> void:
	_absorption_mult = maxf(mult, 0.0)
	for material: ShaderMaterial in _water_materials:
		material.set_shader_parameter("absorption",
			_absorption_base * _absorption_mult)


## Волны sea_octave (П15-ДОП): множители высоты, остроты гребней,
## скорости и частоты к константам зоны (озеро и море — своя база,
## множители общие). Высота 0 — гладь.
func set_wave_params(
	height: float, choppy: float, speed: float, freq: float,
) -> void:
	_wave_h_mult = maxf(height, 0.0)
	_wave_choppy_mult = maxf(choppy, 0.0)
	_wave_speed_mult = maxf(speed, 0.0)
	_wave_freq_mult = maxf(freq, 0.0)
	for material: ShaderMaterial in _water_materials:
		_apply_wave_params(material, _calm)


## Параметры волн зоны (база констант озеро/море × множители ползунков)
## в материал — при постройке поверхности и на лету из F3.
func _apply_wave_params(material: ShaderMaterial, calm: bool) -> void:
	material.set_shader_parameter("sea_height",
		(LAKE_WAVE_HEIGHT if calm else SEA_WAVE_HEIGHT) * _wave_h_mult)
	material.set_shader_parameter("sea_choppiness",
		(LAKE_WAVE_CHOPPY if calm else SEA_WAVE_CHOPPY)
			* _wave_choppy_mult)
	material.set_shader_parameter("sea_speed",
		(LAKE_WAVE_SPEED if calm else SEA_WAVE_SPEED) * _wave_speed_mult)
	material.set_shader_parameter("sea_freq",
		(LAKE_WAVE_FREQ if calm else SEA_WAVE_FREQ) * _wave_freq_mult)


## Сила и масштаб ряби (мелкие волны-шум поверх волн).
func set_ripple_fx(strength: float, scale: float) -> void:
	_ripple_fx_strength = clampf(strength, 0.0, 2.0)
	_ripple_fx_scale = clampf(scale, 0.5, 2.0)
	for material: ShaderMaterial in _water_materials:
		material.set_shader_parameter(
			"ripple_strength", _ripple_fx_strength)
		material.set_shader_parameter(
			"ripple_scale", _ripple_fx_scale)


## Сила преломления (0 — без смещения выборки экрана); булева
## set_refraction панели замера (0/1) отдельная.
func set_refraction_amount(value: float) -> void:
	_refraction_mult = clampf(value, 0.0, 4.0)
	for material: ShaderMaterial in _water_materials:
		material.set_shader_parameter(
			"refraction_amount", _refraction_mult)


## Шероховатость вблизи и у горизонта (границы roughness фильтрации).
func set_roughness(near: float, far: float) -> void:
	_rough_near = clampf(near, 0.0, 1.0)
	_rough_far = clampf(far, 0.0, 1.0)
	for material: ShaderMaterial in _water_materials:
		material.set_shader_parameter("roughness_near", _rough_near)
		material.set_shader_parameter("roughness_far", _rough_far)


## Яркость глубинных цветов по часам (П5.13, блок 2; П15 3 — отражение
## теперь движковое): глубинные цвета гаснут вместе с яркостью неба —
## ночью вода тёмная сама, а не подсвеченная эмиссией глубины. Отражение
## неба и дорожка светила шейдером больше не крашутся (radiance Sky3D
## кладёт движок); параметры неба приняты ради единого вызова DayCycle.
func update_sky(
	sky_top: Color, sky_horizon: Color, light_dir: Vector3, glint: Color,
) -> void:
	# Спад яркости от дневного горизонта (0.75 — типичная светлота дня).
	# Люма хранится: ползунок «Вода» меняет базовые цвета — применяются
	# сразу с текущей ночной поправкой.
	_palette_luma = clampf(sky_horizon.get_luminance() / 0.75, 0.10, 1.0)
	if _water_materials.is_empty():
		return
	_apply_palette()


func _apply_palette() -> void:
	for material: ShaderMaterial in _water_materials:
		material.set_shader_parameter("color_deep",
			Color(_deep_base * _palette_luma, 1.0))
		material.set_shader_parameter("color_shallow",
			Color(_shallow_base * _palette_luma, 1.0))
