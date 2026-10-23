# Костёр на площади (раздел 6 SPEC): место сбора — каменное кострище
# и лавки расставлены генератором острова (лавки — предмет «bench»),
# здесь огонь целиком (доработка П5.13, «живой огонь»):
#   • кострище и поленья — CC0-модели Poly Haven (stone_fire_pit,
#     dry_branches_medium_01; децимированы tools/decimate_polyhaven.gd
#     в вершинно-цветные .res, тон поднят из фотосканной темноты);
#   • пламя — шейдер fire.gdshader с анимированным симплекс-шумом:
#     гуляющие вершины, тающие языками края, дыхание высоты;
#   • искры (раздел 16) и лёгкий дым (smoke.gdshader, мягкие клубы);
#   • мерцающий тёплый свет OmniLight3D — отсветы на земле, лавках
#     и персонажах вокруг.
# Сидение у костра — П5 (раздел 9.6): от campfire_company_size сидящих
# огонь разгорается — свет, искры и дым сильнее, один игрок оставляет
# его спокойным.
class_name Campfire
extends Node3D

const PAL: Palette = preload("res://assets/palette.tres")
const B: Balance = preload("res://gameplay/balance.tres")
const FIRE_SHADER: Shader = preload("res://assets/shaders/fire.gdshader")
const LOWPOLY: Shader = preload("res://assets/shaders/lowpoly.gdshader")
# CC0 Poly Haven (см. assets/third_party/LICENSES.md): сырые сканы
# децимированы в вершинно-цветные меши, тон поднимается при сборке.
const FIRE_PIT_MESH: ArrayMesh = preload(
	"res://assets/third_party/polyhaven.com/stone_fire_pit/fire_pit_lo.res")
const BRANCH_MESH: ArrayMesh = preload(
	"res://assets/third_party/polyhaven.com/dry_branches_medium_01/branch_lo.res")

## Параметры спокойного огня / разгоревшегося (раздел 9.6).
const CALM_ENERGY: float = 0.6
const CALM_RANGE: float = 10.0
const CALM_SPARKS: int = 12
const CALM_SMOKE: int = 5
const COMPANY_ENERGY: float = 1.05
const COMPANY_RANGE: float = 14.0
const COMPANY_SPARKS: int = 26
const COMPANY_SMOKE: int = 9
## Коллизия очага (баг vfx-fix; доработка П5.13 — по габариту каменного
## кострища): цилиндр накрывает кольцо камней и угли — игрок не проходит
## сквозь огонь и не встаёт на камни.
const HEARTH_RADIUS: float = 1.2
const HEARTH_HEIGHT: float = 0.7
## Пламя (блок д): конус над углями, м.
const FLAME_HEIGHT: float = 0.75
const FLAME_RADIUS: float = 0.24
## Кострище: модель ⌀1.45 м растягивается до ⌀2.5 (кольцо камней лавок
## масштаба площади), слегка притапливается «врастает» и проворачивается
## на несимметричный угол.
const PIT_SCALE: float = 1.72
const PIT_YAW: float = 0.7
## Шатёр поленьев над углями: три ветки, наклон к центру, м.
const LOG_TILT: float = 0.96
const LOG_SCALE: float = 0.75
const LOG_BASE_R: float = 0.5
const LOG_BASE_Y: float = 0.3

var _light: OmniLight3D
var _sparks: GPUParticles3D
var _smoke: GPUParticles3D
## Базовая энергия света (calm/company); мерцание ходит вокруг неё.
var _base_energy: float = CALM_ENERGY


func _ready() -> void:
	# П10 (уборка мира): костра на Площади нет — ни очага, ни огня, ни света;
	# код и ассеты остаются, выключили флаг — костёр вернулся. Процесс гасим
	# сразу: мерцание света дотягивало кадр до queue_free с пустым _light.
	if Balance.legacy_hidden():
		set_process(false)
		queue_free()
		return
	_build()
	EventBus.campfire_seats.connect(_on_campfire_seats)


## Тёплое мерцание света (блок д): два неравных такта — дыхание огня
## без машинной периодичности. Амплитуда небольшая, у земли почти штиль.
func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	_light.light_energy = _base_energy * (
		1.0 + 0.13 * sin(t * 7.3) + 0.07 * sin(t * 12.1 + 1.7)
	)


func _build() -> void:
	# Твёрдый очаг (баг vfx-fix): камни и угли — не призраки.
	var hearth := CylinderShape3D.new()
	hearth.radius = HEARTH_RADIUS
	hearth.height = HEARTH_HEIGHT
	SolidBody.add(self, hearth, Vector3(0.0, HEARTH_HEIGHT * 0.5, 0.0))
	var prop_material := ShaderMaterial.new()
	prop_material.shader = LOWPOLY
	# Кострище (CC0 Poly Haven): каменное кольцо «врастает» в площадь.
	var pit := MeshInstance3D.new()
	pit.name = "FirePit"
	pit.mesh = _lifted(FIRE_PIT_MESH, 0.3, PAL.stone, 0.25)
	pit.material_override = prop_material
	pit.rotation.y = PIT_YAW
	pit.position = Vector3(0.0, 0.3, 0.0)
	pit.scale = Vector3.ONE * PIT_SCALE
	add_child(pit)
	# Уголь: огранённый камень с углями — чуть живее бокса (раздел 16).
	var ember := MeshInstance3D.new()
	# Имя нужно аудиту поверхностей (П8): безымянный меш не отличить от
	# забытой белой заглушки.
	ember.name = "Ember"
	var ember_mesh := SphereMesh.new()
	ember_mesh.radius = 0.22
	ember_mesh.height = 0.44
	ember_mesh.radial_segments = 5
	ember_mesh.rings = 1
	ember.mesh = ember_mesh
	var ember_material := StandardMaterial3D.new()
	ember_material.albedo_color = PAL.fire
	ember_material.emission_enabled = true
	ember_material.emission = PAL.fire
	ember_material.emission_energy_multiplier = 1.8
	ember.material_override = ember_material
	ember.position = Vector3(0.0, 0.3, 0.0)
	add_child(ember)
	# Шатёр поленьев (CC0 Poly Haven): три сухие ветки наклонены к центру,
	# вершины сходятся над углями — огонь «ест» настоящую древесину.
	var logs := Node3D.new()
	logs.name = "Logs"
	add_child(logs)
	var branch := _lifted(BRANCH_MESH, 0.22, PAL.trunk, 0.2)
	for i: int in 3:
		var log := MeshInstance3D.new()
		log.mesh = branch
		log.material_override = prop_material
		var yaw: float = TAU * i / 3.0 + 0.9
		# Порядок Эйлера YXZ: наклон к центру (X), затем разворот вокруг
		# огня (Y); база ветки — на камнях у углей.
		log.rotation = Vector3(LOG_TILT, yaw, 0.0)
		log.position = Vector3(
			cos(yaw) * LOG_BASE_R, LOG_BASE_Y, sin(yaw) * LOG_BASE_R)
		log.scale = Vector3.ONE * LOG_SCALE
		logs.add_child(log)
	# Пламя (доработка П5.13): шейдерный конус с анимированным шумом —
	# вершины гуляют, кромка тает языками, высота дышит.
	var flame := MeshInstance3D.new()
	flame.name = "Flame"
	var cone := CylinderMesh.new()
	cone.top_radius = 0.04
	cone.bottom_radius = FLAME_RADIUS
	cone.height = FLAME_HEIGHT
	cone.radial_segments = 10
	flame.mesh = cone
	var flame_mat := ShaderMaterial.new()
	flame_mat.shader = FIRE_SHADER
	flame_mat.set_shader_parameter("base_color", PAL.fire.darkened(0.15))
	flame_mat.set_shader_parameter("tip_color", Color(1.0, 0.88, 0.42))
	flame_mat.set_shader_parameter("height", FLAME_HEIGHT)
	flame_mat.set_shader_parameter("speed", 2.6)
	flame_mat.set_shader_parameter("tongue_scale", 5.5)
	flame_mat.set_shader_parameter("tongue_noise", 0.38)
	flame.material_override = flame_mat
	flame.position = Vector3(0.0, 0.42 + FLAME_HEIGHT * 0.5, 0.0)
	add_child(flame)
	# Искры над углями (раздел 16: «искры костра») и лёгкий дым.
	_sparks = Fx.fire_sparks(self, Vector3(0.0, 0.55, 0.0), PAL.fire)
	_smoke = Fx.campfire_smoke(self, Vector3(0.0, 1.3, 0.0), CALM_SMOKE)
	_light = OmniLight3D.new()
	_light.light_color = PAL.fire
	_light.omni_range = CALM_RANGE
	_light.light_energy = CALM_ENERGY
	_light.position = Vector3(0.0, 0.7, 0.0)
	add_child(_light)


## Сколько сидящих сейчас (раздел 9.6): двое и больше — огонь сильнее.
func _on_campfire_seats(seats: Array) -> void:
	var seated := 0
	for peer: int in seats:
		if peer != 0:
			seated += 1
	if seated >= B.campfire_company_size:
		_base_energy = COMPANY_ENERGY
		_light.omni_range = COMPANY_RANGE
		_sparks.amount = COMPANY_SPARKS
		_smoke.amount = COMPANY_SMOKE
	else:
		_base_energy = CALM_ENERGY
		_light.omni_range = CALM_RANGE
		_sparks.amount = CALM_SPARKS
		_smoke.amount = CALM_SMOKE


## Копия вершинно-цветного меша с поднятым тоном: децимированные сканы
## Poly Haven несут линейные цвета фотографии (средняя яркость ~0.1 —
## фото снято в сумраке очага), а сцена ждёт читаемые камни и древесину.
## Яркость нормируется к target (линейная люма), тон подтягивается к
## цвету палитры на mix. Детерминировано: те же вершины — тот же тон.
static func _lifted(
	mesh: ArrayMesh, target_luma: float, toward: Color, mix: float,
) -> ArrayMesh:
	var arrays := mesh.surface_get_arrays(0)
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var mean := 0.0
	for color: Color in colors:
		mean += color.get_luminance()
	mean /= maxf(1.0, float(colors.size()))
	var gain: float = clampf(target_luma / maxf(mean, 0.001), 1.0, 4.0)
	var linear_toward := toward.srgb_to_linear()
	for i: int in colors.size():
		colors[i] = (colors[i] * gain).lerp(linear_toward, mix)
	arrays[Mesh.ARRAY_COLOR] = colors
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out
