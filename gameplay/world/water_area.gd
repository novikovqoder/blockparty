# Вода (раздел 6 SPEC): Area3D-зона плавания + поверхность на шейдере
# Boujie Water Shader (доработка-2 П5.13, П3 — готовый аддон MIT вместо
# самописного). Персонаж в зоне плавает на поверхности со скоростью шага
# (само плавание — в Player.enter_water/exit_water); этой зоне всё равно,
# кто в ней плавает, поэтому связь — только вызовы методов тел.
# Поверхности строится в _ready при входе в дерево (сцена острова
# собирается оффлайн tools/generate_island.gd, меши воды в пакет не
# попадают):
#   море  — нода Ocean аддона: кольца LOD с изломами-швами без щелей,
#     следует за камерой (CameraFollower3D; паттерн волн в мировых
#     координатах — движение бесшовно), дальняя плоскость уходит за
#     дистанцию растворения — никаких резких границ;
#   озеро — плоскость тем же шейдером спокойнее (волны меньше) и на
#     LAKE_LIFT выше моря: копланарные поверхности мерцали (z-fighting).
# Преломление и окно Снелла шейдера выключены (SPEC «Простая графика»,
# правка дефайнов в шейдере аддона — README это прямо допускает).
# П12 F: палитра Born Unblessed — бирюза PAL.water/PAL.water_deep больше не
# используется (SPEC П12 4.1); шейдер — копии аддона в assets/shaders/
# (без нарисованных волн ocean_albedo, SPEC 4.2), преломление — вторая
# копия на HIGH/ULTRA (4.4), аддон не тронут. SSR П11 на воде двойных
# отражений не даёт: шейдер пишет EMISSION без light(), экранное
# отражение движок поверх не подмешивает — френель даёт только небо.
# Не делает: подводное плавание (вне MVP), течение и волны для лодочек.
class_name WaterArea
extends Area3D

const WATER_PLAIN: Shader = preload(
	"res://assets/shaders/water_plain.gdshader")
const WATER_REFRACTION: Shader = preload(
	"res://assets/shaders/water_refraction.gdshader")
const FOAM_TEX: Texture2D = preload(
	"res://addons/boujie_water_shader/shader/foam_1.png")
const REFRACTION_TEX: Texture2D = preload(
	"res://addons/boujie_water_shader/shader/refraction.png")

# --- Палитра воды BU (SPEC П12 4.1) ---
## Озеро и пруды: тёмная торфяная вода — глубина почти чёрная с зелёно-
## бурым отливом, мелководье прозрачное (дно видно).
const LAKE_DEEP: Color = Color(0.016, 0.035, 0.028, 0.94)
const LAKE_SHALLOW: Color = Color(0.10, 0.14, 0.10, 0.30)
const LAKE_ALBEDO: Color = Color(0.05, 0.075, 0.06, 0.72)
## Море: холодная стально-серо-синяя.
const SEA_DEEP: Color = Color(0.02, 0.03, 0.045, 0.94)
const SEA_SHALLOW: Color = Color(0.09, 0.12, 0.14, 0.35)
const SEA_ALBEDO: Color = Color(0.055, 0.07, 0.08, 0.72)
## Круги на воде при входе — цвет пены, не бирюза палитры.
const RING_COLOR: Color = Color(0.87, 0.92, 0.93)

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
var _albedo_base := Color.BLACK


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


## Шейдер воды по уровню графики (SPEC П12 4.4): преломление — копия
## water_refraction — только на HIGH/ULTRA, остальным — water_plain.
static func shader_for_tier(tier: int) -> Shader:
	return WATER_REFRACTION if tier >= GraphicsQuality.Tier.HIGH \
		else WATER_PLAIN


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


## В нормальном рендере — копия шейдера Boujie Water в палитре BU (море —
## заметные волны, озеро — мелкая рябь; преломление — только HIGH/ULTRA,
## SPEC П12 4.4); в headless (dummy-рендер) — плоская полупрозрачная
## заглушка без волн.
func _surface_material(calm: bool) -> Material:
	if WorldMaterials.want_flat():
		var flat := StandardMaterial3D.new()
		flat.albedo_color = Color(
			LAKE_SHALLOW if calm else SEA_SHALLOW, 0.55)
		flat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		return flat
	var material := ShaderMaterial.new()
	var shader := shader_for_tier(GraphicsQuality.tier_from_settings())
	var refraction := shader == WATER_REFRACTION
	material.shader = shader
	material.set_shader_parameter("freeze_time", false)
	# Палитра BU (4.1): озеро/пруды — торфяная, море — стальная серо-синяя.
	_deep_base = LAKE_DEEP if calm else SEA_DEEP
	_shallow_base = LAKE_SHALLOW if calm else SEA_SHALLOW
	_albedo_base = LAKE_ALBEDO if calm else SEA_ALBEDO
	material.set_shader_parameter("albedo", _albedo_base)
	material.set_shader_parameter("albedo_fresnel",
		Color(0.42, 0.47, 0.50, 1.0))  # до первого update_sky
	material.set_shader_parameter("color_deep", _deep_base)
	material.set_shader_parameter("color_shallow", _shallow_base)
	material.set_shader_parameter("texture_foam", FOAM_TEX)
	if refraction:
		# Дефолты префаба аддона: тихое искажение дна, сходит на нет к 200 м.
		material.set_shader_parameter("texture_refraction", REFRACTION_TEX)
		material.set_shader_parameter("refraction", 0.09)
		material.set_shader_parameter("refraction_texture_channel",
			Vector4(1.0, 0.0, 0.0, 0.0))
		material.set_shader_parameter("refraction_opacity", 0.7)
		material.set_shader_parameter("refraction_scaling_distance_min", 200.0)
	material.set_shader_parameter("specular", 0.55)
	# Почти зеркало (4.3): рябь и френель не размазываются микрошероховатостью.
	material.set_shader_parameter("roughness", 0.03)
	material.set_shader_parameter("metallic", 0.0)
	material.set_shader_parameter("vertex_displace_from_mesh_normal", false)
	material.set_shader_parameter("normal_wave_from_mesh_normal", false)
	# Трипланарные UV в мировых координатах — тот же масштаб, что у префаба
	# аддона (пена и рябь дна ~36 м).
	material.set_shader_parameter("uv_blend_sharpness", 2.0)
	material.set_shader_parameter("uv_tri_scale", Vector3(36.0, 36.0, 36.0))
	material.set_shader_parameter("uv_tri_offset", Vector3.ZERO)
	# Глубинный цвет: закон Бера на глубине, мелководье прозрачно; озеро
	# плотнее моря — торфяная мгла глотает свет быстрее (4.5).
	material.set_shader_parameter("beers_law", 2.8 if calm else 2.2)
	material.set_shader_parameter("depth_offset", -0.75)
	# Пена у кромки (4.6): тонкая полоса прибоя у берега и камней.
	material.set_shader_parameter("shore_start_blend", 0.25 if calm else 0.4)
	material.set_shader_parameter("shore_end_blend", 0.8 if calm else 1.4)
	# Дальний растворение: вода мягко уходит в дымку неба задолго до края
	# меша (far_edge 1500) — резкой границы не видно. «Простая графика»
	# приближает (set_fade_distance от world_scene при far 70).
	material.set_shader_parameter("distance_fade_min", 700.0)
	material.set_shader_parameter("distance_fade_max", 1400.0)
	material.set_shader_parameter("near_fade_min", 0.8)
	material.set_shader_parameter("near_fade_max", 1.2)
	material.set_shader_parameter("foam_fade_min", 280.0)
	material.set_shader_parameter("foam_fade_max", 620.0)
	material.set_shader_parameter("shore_fade_min", 280.0)
	material.set_shader_parameter("shore_fade_max", 620.0)
	material.set_shader_parameter("vertex_wave_fade_min", 380.0)
	material.set_shader_parameter("vertex_wave_fade_max", 800.0)
	# Depth-буфер вдали неточен: глубинные эффекты гаснут до горизонта.
	material.set_shader_parameter("depth_fog_fade_min", 70.0)
	material.set_shader_parameter("depth_fog_fade_max", 130.0)
	if calm:
		# Озеро (4.5): почти гладь — едва заметная рябь двух масштабов
		# (~6 и ~4.5 м) с ползущими по ним бликами, пена редкая и слабая.
		_waves(material, 2, [0.05, 0.04], [0.05, 0.035],
			[35.0, 120.0], [0.16, 0.22], [0.5, 0.35], [0.0, 90.0])
		_waves(material, 1, [0.04], [0.9], [70.0], [0.10], [0.2], [0.0], true)
		_waves(material, 2, [0.08, 0.06], [0.5, 0.4],
			[310.0, 90.0], [0.8, 0.5], [0.3, 0.25], [0.0, 120.0],
			false, true)
	else:
		# Море (4.5): умеренные четыре волны Герстнера — крупнее озера,
		# но без шторма; гребни пенятся (4.6) слабыми короткими всплесками.
		_waves(material, 4, [0.28, 0.24, 0.20, 0.16], [0.30, 0.22, 0.16, 0.10],
			[20.0, 140.0, 250.0, 60.0], [0.045, 0.060, 0.085, 0.100],
			[1.0, 0.8, 1.2, 0.6], [0.0, 30.0, 60.0, 15.0])
		_waves(material, 3, [0.20, 0.15, 0.35], [0.9, 1.1, 0.6],
			[25.0, 315.0, 144.0], [0.02, 0.05, 0.06], [0.8, 1.2, 0.6],
			[0.0, 90.0, 40.0], true)
		_waves(material, 2, [0.09, 0.08], [0.7, 0.5],
			[315.0, 90.0], [0.6, 0.4], [0.5, 0.3], [0.0, 0.0],
			false, true)
	_water_materials.append(material)
	return material


## Параметры группы волн шейдера (Vertex/Foam/UV): до восьми значений,
## хвост дополняется нулями — шейдер читает только Count первых.
func _waves(
	material: ShaderMaterial, count: int,
	steepness: Array, amplitude: Array, directions: Array,
	frequencies: Array, speeds: Array, phases: Array,
	foam: bool = false, uv: bool = false,
) -> void:
	var prefix: String = "Foam" if foam else ("UV" if uv else "")
	var names: Array[String] = [
		"%sWaveCount", "%sWaveSteepnesses", "%sWaveAmplitudes",
		"%sWaveDirectionsDegrees", "%sWaveFrequencies", "%sWaveSpeeds",
		"%sWavePhases",
	]
	var values: Array = [count, steepness, amplitude, directions,
		frequencies, speeds, phases]
	for i: int in names.size():
		var param: String = names[i] % prefix
		if values[i] is int:
			material.set_shader_parameter(param, values[i])
		else:
			var packed := PackedFloat32Array()
			for v: float in values[i]:
				packed.append(v)
			while packed.size() < 8:
				packed.append(0.0)
			material.set_shader_parameter(param, packed)


## «Простая графика» (раздел 15): камера far 70 — растворение воды
## приближается, чтобы край не обрезался видимым обрывом.
func set_fade_distance(fade_min: float, fade_max: float) -> void:
	for material: ShaderMaterial in _water_materials:
		material.set_shader_parameter("distance_fade_min", fade_min)
		material.set_shader_parameter("distance_fade_max", fade_max)
		material.set_shader_parameter("foam_fade_min", fade_min * 0.4)
		material.set_shader_parameter("foam_fade_max", fade_min * 0.85)
		material.set_shader_parameter("shore_fade_min", fade_min * 0.4)
		material.set_shader_parameter("shore_fade_max", fade_min * 0.85)


## Растворение воды по уровню графики (баг-фикс П13 п. 5): 46–66 м —
## «Простая графика» (камера far 70, Доработка-2 П5.13 П3); прочие уровни —
## базовая дальность шейдера (700–1400 м, пена 280–620) без видимого
## обрыва: дальняя плоскость воды уходит за горизонт.
const FADE_SIMPLE_MIN: float = 46.0
const FADE_SIMPLE_MAX: float = 66.0
const FADE_BASE_MIN: float = 700.0
const FADE_BASE_MAX: float = 1400.0
const FOAM_BASE_MIN: float = 280.0
const FOAM_BASE_MAX: float = 620.0


func set_tier_fade(tier: int) -> void:
	if tier == GraphicsQuality.Tier.SIMPLE:
		set_fade_distance(FADE_SIMPLE_MIN, FADE_SIMPLE_MAX)
		return
	for material: ShaderMaterial in _water_materials:
		material.set_shader_parameter("distance_fade_min", FADE_BASE_MIN)
		material.set_shader_parameter("distance_fade_max", FADE_BASE_MAX)
		material.set_shader_parameter("foam_fade_min", FOAM_BASE_MIN)
		material.set_shader_parameter("foam_fade_max", FOAM_BASE_MAX)
		material.set_shader_parameter("shore_fade_min", FOAM_BASE_MIN)
		material.set_shader_parameter("shore_fade_max", FOAM_BASE_MAX)


## Преломление воды на лету (панель замера F3, П13 3.2): включено на
## HIGH/ULTRA (SPEC П12 4.4) — переключает шейдер копии материалов
## (параметры ShaderMaterial переживают смену шейдера).
func set_refraction(on: bool) -> void:
	var shader := WATER_REFRACTION if on else WATER_PLAIN
	for material: ShaderMaterial in _water_materials:
		material.shader = shader


## Отражение неба и яркость глубинных цветов (П5.13, блок 2; доработка-2
## П3 — Boujie Water): френелевский цвет поверхности берёт горизонт неба
## (закат — тёплая вода без «бордовой полосы»), глубинные цвета гаснут
## вместе с яркостью неба — ночью вода тёмная сама, а не подсвеченная
## эмиссией глубины. Дорожку светила даёт спекуляр шейдера от солнца/луны.
func update_sky(
	sky_top: Color, sky_horizon: Color, light_dir: Vector3, glint: Color,
) -> void:
	if _water_materials.is_empty():
		return
	# Спад яркости от дневного горизонта (0.75 — типичная светлота дня).
	var luma := clampf(sky_horizon.get_luminance() / 0.75, 0.10, 1.0)
	for material: ShaderMaterial in _water_materials:
		material.set_shader_parameter("albedo_fresnel",
			Color(sky_horizon, 1.0))
		material.set_shader_parameter("color_deep",
			Color(_deep_base * luma, _deep_base.a))
		material.set_shader_parameter("color_shallow",
			Color(_shallow_base * luma, _shallow_base.a))
		material.set_shader_parameter("albedo",
			Color(_albedo_base * luma, _albedo_base.a))
