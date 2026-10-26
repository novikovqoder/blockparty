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
# SIMPLE/NORMAL — water_bu_cheap без экранной выборки. Спектр волн
# Герстнера (16/32/8 по уровню) и рябь (2/3/1 слоя) — константы
# детерминированного RNG. SSR на прозрачную воду движок не даёт
# (только opaque) — небо отражает френель Шлика цветами DayCycle,
# дорожка светила — спекуляр движка.
# Не делает: подводное плавание (вне MVP), течение и волны для лодочек.
class_name WaterArea
extends Area3D

const WATER_BU: Shader = preload(
	"res://assets/shaders/water_bu.gdshader")
const WATER_BU_CHEAP: Shader = preload(
	"res://assets/shaders/water_bu_cheap.gdshader")

# --- Палитра воды BU (SPEC П12 4.1, П14 4.1) ---
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
## Круги на воде при входе — цвет пены, не бирюза палитры.
const RING_COLOR: Color = Color(0.87, 0.92, 0.93)

# --- Спектр волн (SPEC П14 4.3) ---
## Полный спектр — 32 волны; уровень берёт первые N (длинные первые,
## поэтому HIGH = 16 — подмножество ULTRA = 32, SIMPLE/NORMAL — 8).
const MAX_WAVES: int = 32
const SEED_WAVES: int = 20261026
## Ветер (откуда дует), градусы; разброс направлений волн вокруг него.
const WIND_DIR_DEG: float = 35.0
const DIR_SPREAD_SWELL: float = 60.0
const DIR_SPREAD_MEDIUM: float = 75.0
## Длины и амплитуды: озеро — почти гладь (0.6–3 м / суммарно 1–3 см),
## море — зыбь 12–60 м и средние волны 2.5–10 м (суммарно ~0.2 м RMS).
const LAKE_LEN: Vector2 = Vector2(0.6, 3.0)
const SEA_SWELL_LEN: Vector2 = Vector2(12.0, 60.0)
const SEA_MEDIUM_LEN: Vector2 = Vector2(2.5, 10.0)
const RMS_LAKE: float = 0.016
const RMS_SEA: float = 0.18
## Суммарная крутизна спектра (Σ Q·k·A): держит Герстнера от
## самопересечений, бюджет делится поровну между волнами.
const STEEP_TOTAL: float = 0.75
## Гравитация для дисперсионного соотношения глубоководных волн.
const GRAVITY: float = 9.81

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
## Базовые (дневные) значения цветов, от которых считается ночной спад.
var _deep_base := Color.BLACK
var _shallow_base := Color.BLACK
## Рябь включена (панель F3): номинал по уровню или 0.
var _ripple_on: bool = true
## Уровень качества построенных поверхностей (волны/рябь/шейдер).
var _tier: int = 0


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
	if surface_size != Vector2.ZERO:
		_build_surface()


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


## Число волн Герстнера по уровню (SPEC П14 4.3/4.7): 32 ULTRA,
## 16 HIGH, 8 SIMPLE/NORMAL.
static func wave_count_for_tier(tier: int) -> int:
	if tier == GraphicsQuality.Tier.ULTRA:
		return 32
	if tier == GraphicsQuality.Tier.HIGH:
		return 16
	return 8


## Слои процедурной ряби по уровню (SPEC П14 4.3/4.7): 3 ULTRA,
## 2 HIGH, дешёвой версии хватает одного.
static func ripple_layers_for_tier(tier: int) -> int:
	if tier == GraphicsQuality.Tier.ULTRA:
		return 3
	if tier == GraphicsQuality.Tier.HIGH:
		return 2
	return 1


## Спектр волн Герстнера (SPEC П14 4.3) — детерминированный RNG с
## фиксированным seed: [waves_a, waves_b] по 32 волны, длинные первыми.
##   waves_a[i] = (dir.x, dir.y, k = 2π/λ, амплитуда)
##   waves_b[i] = (ω = √(g·k), крутизна Q, фаза, вес пены гребня)
## Амплитуды пропорциональны длине волны и нормализуются к суммарному
## RMS (море ~0.2 м, озеро ~2 см — не шторм); веса пены нормированы так,
## что совпадение фаз зыби даёт сжатие гребня ≈ 0.55 (порог шейдера).
static func wave_spectrum(sea: bool) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_WAVES
	var lengths: Array[float] = []
	var amps: Array[float] = []
	var dirs: Array[float] = []  # радианы
	var phases: Array[float] = []
	var foams: Array[float] = []
	var wind: float = deg_to_rad(WIND_DIR_DEG)
	for i: int in MAX_WAVES:
		# Море: 60% зыби (12–60 м) и 40% средних волн (2.5–10 м);
		# озеро — один диапазон коротких волн.
		var swell: bool = not sea or i % 5 < 3
		var t: float = rng.randf()
		var length: float
		var amp: float
		var foam: float
		var spread: float
		if sea and swell:
			length = lerpf(SEA_SWELL_LEN.x, SEA_SWELL_LEN.y, t)
			amp = lerpf(0.30, 0.80, t)
			foam = 1.0
			spread = DIR_SPREAD_SWELL
		elif sea:
			length = lerpf(SEA_MEDIUM_LEN.x, SEA_MEDIUM_LEN.y, t)
			amp = lerpf(0.04, 0.18, t)
			foam = 0.35
			spread = DIR_SPREAD_MEDIUM
		else:
			length = lerpf(LAKE_LEN.x, LAKE_LEN.y, t)
			amp = lerpf(0.01, 0.03, t)
			foam = 0.0
			spread = DIR_SPREAD_MEDIUM
		# Зыбь держится ближе к ветру, средние волны разбросаны шире.
		dirs.append(wind + deg_to_rad(
			rng.randf_range(-spread, spread)))
		lengths.append(length)
		amps.append(amp)
		phases.append(rng.randf() * TAU)
		foams.append(foam)
	# Длинные волны первыми: HIGH=16 — подмножество ULTRA=32, урезание
	# спектра не меняет первые волны.
	var order := range(MAX_WAVES)
	order.sort_custom(func(a: int, b: int) -> bool:
		return lengths[a] > lengths[b])
	# Нормализация амплитуд к суммарному RMS моря/озера.
	var sum_sq: float = 0.0
	for amp: float in amps:
		sum_sq += amp * amp
	var rms_target: float = RMS_SEA if sea else RMS_LAKE
	var scale: float = rms_target / sqrt(maxf(sum_sq, 1e-9))
	# Крутизна: Q общая на волну, Σ Q·k·A = STEEP_TOTAL (без петель).
	var steep_sum: float = 0.0
	for i: int in MAX_WAVES:
		steep_sum += TAU / lengths[i] * amps[i] * scale
	var q: float = STEEP_TOTAL / maxf(steep_sum, 1e-9)
	# Веса пены: совпадение фаз всех волн с весом даёт сжатие ≈ 0.55.
	var crest_sum: float = 0.0
	for i: int in MAX_WAVES:
		crest_sum += foams[i] * q * TAU / lengths[i] * amps[i] * scale
	var foam_scale: float = 0.55 / maxf(crest_sum, 1e-9) \
		if crest_sum > 1e-6 else 0.0
	var waves_a := PackedVector4Array()
	var waves_b := PackedVector4Array()
	for i: int in order:
		var k: float = TAU / lengths[i]
		var amp: float = amps[i] * scale
		waves_a.append(Vector4(
			cos(dirs[i]), sin(dirs[i]), k, amp))
		waves_b.append(Vector4(
			sqrt(GRAVITY * k), q, phases[i],
			foams[i] * foam_scale))
	return [waves_a, waves_b]


func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		(body as Player).enter_water(water_level)
		# Круги на воде при входе в неё (раздел 16); П12 F — цвет пены,
		# не бирюза палитры.
		var pos: Vector3 = (body as Node3D).global_position
		Fx.water_ring(
			get_parent(), Vector3(pos.x, water_level + 0.02, pos.z),
			RING_COLOR,
		)


func _on_body_exited(body: Node3D) -> void:
	if body is Player:
		(body as Player).exit_water()


func _build_surface() -> void:
	if _surface_built:
		return
	_surface_built = true
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
	if WorldMaterials.want_flat():
		var flat := StandardMaterial3D.new()
		flat.albedo_color = Color(
			LAKE_SHALLOW if calm else SEA_SHALLOW, 0.55)
		flat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		return flat
	_tier = GraphicsQuality.tier_from_settings()
	var material := ShaderMaterial.new()
	material.shader = shader_for_tier(_tier)
	# Палитра BU (П12 4.1): озеро/пруды — торфяная, море — стальная.
	_deep_base = LAKE_DEEP if calm else SEA_DEEP
	_shallow_base = LAKE_SHALLOW if calm else SEA_SHALLOW
	material.set_shader_parameter("color_deep", _deep_base)
	material.set_shader_parameter("color_shallow", _shallow_base)
	# Поглощение Бера по каналам (П14 4.1): озеро плотнее моря.
	material.set_shader_parameter("absorption",
		LAKE_ABSORPTION if calm else SEA_ABSORPTION)
	# Спектр волн (П14 4.3): море — зыбь и средние, озеро — короткие;
	# уровень качества берёт первые N волн (длинные первые).
	var spectrum := wave_spectrum(not calm)
	material.set_shader_parameter("waves_a", spectrum[0])
	material.set_shader_parameter("waves_b", spectrum[1])
	material.set_shader_parameter("wave_count", wave_count_for_tier(_tier))
	# Рябь (4.3/4.7) и преломление (4.2): 2–3 слоя на HIGH/ULTRA,
	# один дешёвой версии; преломление включено (панель F3 гасит).
	material.set_shader_parameter(
		"ripple_layers", float(ripple_layers_for_tier(_tier)))
	material.set_shader_parameter("refraction_amount", 1.0)
	material.set_shader_parameter("specular", 0.55)
	# Почти зеркало (4.3/П14 4.4): рябь и френель не размазываются
	# микрошероховатостью.
	material.set_shader_parameter("roughness", 0.03)
	material.set_shader_parameter("metallic", 0.0)
	# Небо для френеля до первого update_sky (нейтральное дневное).
	material.set_shader_parameter("sky_horizon", Vector3(0.55, 0.62, 0.70))
	material.set_shader_parameter("sky_top", Vector3(0.30, 0.45, 0.68))
	# Растворение к горизонту цветом неба: дальняя плоскость Ocean без
	# резкой границы; «Простая графика» приближает (set_fade_distance
	# от world_scene при far 70).
	material.set_shader_parameter("distance_fade_min", 700.0)
	material.set_shader_parameter("distance_fade_max", 1400.0)
	# Смещение вершин гаснет вдали (внешние кольца Ocean грубые).
	material.set_shader_parameter("vertex_wave_fade_min", 380.0)
	material.set_shader_parameter("vertex_wave_fade_max", 800.0)
	# Depth-буфер вдали неточен: толщина сменяется «глубокой» константой.
	material.set_shader_parameter("depth_fog_fade_min", 70.0)
	material.set_shader_parameter("depth_fog_fade_max", 130.0)
	material.set_shader_parameter("far_thickness", 8.0)
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


## Отражение неба и яркость глубинных цветов (П5.13, блок 2; П14 4.4 —
## свой шейдер): френель Шлика красит отражение реальным небом (закат —
## тёплая вода без «бордовой полосы»), глубинные цвета гаснут вместе с
## яркостью неба — ночью вода тёмная сама, а не подсвеченная эмиссией
## глубины. Дорожку светила даёт спекуляр шейдера от солнца/луны.
func update_sky(
	sky_top: Color, sky_horizon: Color, light_dir: Vector3, glint: Color,
) -> void:
	if _water_materials.is_empty():
		return
	# Спад яркости от дневного горизонта (0.75 — типичная светлота дня).
	var luma := clampf(sky_horizon.get_luminance() / 0.75, 0.10, 1.0)
	for material: ShaderMaterial in _water_materials:
		material.set_shader_parameter("sky_horizon",
			Vector3(sky_horizon.r, sky_horizon.g, sky_horizon.b))
		material.set_shader_parameter("sky_top",
			Vector3(sky_top.r, sky_top.g, sky_top.b))
		material.set_shader_parameter("color_deep",
			Color(_deep_base * luma, 1.0))
		material.set_shader_parameter("color_shallow",
			Color(_shallow_base * luma, 1.0))
