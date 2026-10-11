# Маяк мирового события (раздел 7 SPEC): башню строит генератор острова
# (предмет «beacon»), узел добавляет лампу в фонаре и луч в небо, когда
# маяк зажжён. Зажигают двое разных игроков нажатием E в пределах 3 с;
# при одном игроке в мире — удержанием E 8 с (запасной путь, раздел 7).
# Попытка в одиночку в многопользовательском мире — подсказка «Нужен
# второй игрок». Подтверждает хост (ActivityAuthority), узел шлёт запрос
# и рисует результат. Дети island.tscn; порядок имён Beacon1..5 — как
# _beacons у IslandGen.
class_name Beacon
extends Interactable

const B: Balance = preload("res://gameplay/balance.tres")
const PAL: Palette = preload("res://assets/palette.tres")

## Группа узлов маяков (хост находит башни; GROUP занято базовым
## Interactable.GROUP для подсказки E).
const BEACON_GROUP: StringName = &"beacon_tower"

## Высота фонаря башни (лампа и низ луча), м — как в prop_meshes._beacon.
const LAMP_Y: float = 3.45
## Размер стеклянного бокса лампы, м (совпадает с тёмным «стеклом» башни).
const LAMP_SIZE: Vector3 = Vector3(0.52, 0.42, 0.52)
## Луч в небо: длина и радиусы, м.
const BEAM_LENGTH: float = 60.0
const BEAM_BOTTOM_R: float = 0.18
const BEAM_TOP_R: float = 0.34
## Вращающийся световой конус (блок д, только «Высокое качество»):
## прожектор из фонаря, обегающий горизонт. Радиус/угол/скорость.
const CONE_RANGE: float = 38.0
const CONE_ANGLE: float = 22.0
const CONE_SPEED: float = 0.9

var _lit: bool = false
var _lamp: MeshInstance3D
var _beam: MeshInstance3D
var _light: OmniLight3D
var _cone: SpotLight3D
var _high_tier: bool = false

## Индекс в порядке имени узла — как сортирует хост.
var _index: int = 0


func _ready() -> void:
	super()
	add_to_group(BEACON_GROUP)
	_index = _compute_index()
	use_radius = 2.8
	# Уровень качества фиксируется на входе в мир (world_scene применяет
	# его в _ready) — конус живёт только в «Высоком качестве».
	_high_tier = GraphicsQuality.tier_from_settings() == GraphicsQuality.Tier.HIGH
	EventBus.beacons_state.connect(_on_beacons_state)
	_build_visual()
	set_lit(false)


## Вращение конуса: обегает горизонт, пока маяк горит (блок д).
func _process(delta: float) -> void:
	if _cone.visible:
		_cone.rotate_y(delta * CONE_SPEED)


func _on_beacons_state(lit: Array, _lighters: Array, _starfall_started_at: float) -> void:
	set_lit(lit.has(_index))


## «E — зажечь маяк»: пока не горит. Удержание показывается только
## одиночке (hold_time), паре хватает нажатий в пределах 3 с.
func hint_key() -> String:
	return "" if _lit else "HINT_BEACON"


## Запасной путь (раздел 7): один игрок в мире — держать E 8 секунд;
## когда игроков больше, пара зажигает двумя нажатиями.
func hold_time(_player: Node3D) -> float:
	return B.beacon_solo_hold if Net.in_world_count() <= 1 else 0.0


func use(_player: Node3D) -> void:
	# В многопользовательском мире первый нажал — ждём второго 3 с.
	if Net.in_world_count() > 1:
		EventBus.toast_requested.emit("TOAST_NEED_SECOND")
	Net.request_beacon_light(_index)


## Применить состояние от хоста (rpc_beacons / world_state): лампа
## светится, луч и свет видны с любой точки острова. Повторный вызов
## с тем же состоянием — холостой.
func set_lit(lit: bool) -> void:
	if lit == _lit:
		return
	_lit = lit
	_beam.visible = lit
	_light.visible = lit
	_cone.visible = lit and _high_tier
	var material := _lamp.material_override as StandardMaterial3D
	material.emission_enabled = lit
	material.emission = PAL.beacon_glow
	material.emission_energy_multiplier = 1.6
	material.albedo_color = PAL.beacon_glow if lit else PAL.beacon_glow.darkened(0.45)


## Позиция среди маяков группы в порядке имени (тот же порядок у хоста).
func _compute_index() -> int:
	var siblings: Array = []
	for node in get_tree().get_nodes_in_group(BEACON_GROUP):
		if node is Beacon:
			siblings.append(node)
	siblings.sort_custom(
		func(a: Beacon, b: Beacon) -> bool:
			return (a as Node).name.naturalcasecmp_to((b as Node).name) < 0
	)
	return siblings.find(self)


## Лампа в фонаре башни, луч в небо и точечный свет (ночь, раздел 7).
func _build_visual() -> void:
	_lamp = MeshInstance3D.new()
	_lamp.name = "Lamp"
	var box := BoxMesh.new()
	box.size = LAMP_SIZE
	_lamp.mesh = box
	_lamp.position = Vector3(0.0, LAMP_Y, 0.0)
	_lamp.material_override = _lamp_material()
	add_child(_lamp)

	_beam = MeshInstance3D.new()
	_beam.name = "Beam"
	var cyl := CylinderMesh.new()
	cyl.top_radius = BEAM_TOP_R
	cyl.bottom_radius = BEAM_BOTTOM_R
	cyl.height = BEAM_LENGTH
	_beam.mesh = cyl
	_beam.position = Vector3(0.0, LAMP_Y + BEAM_LENGTH * 0.5, 0.0)
	var beam_mat := StandardMaterial3D.new()
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.albedo_color = Color(PAL.beacon_glow, 0.3)
	beam_mat.emission_enabled = true
	beam_mat.emission = PAL.beacon_glow
	beam_mat.emission_energy_multiplier = 0.8
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam.material_override = beam_mat
	add_child(_beam)

	_light = OmniLight3D.new()
	_light.name = "Glow"
	_light.position = Vector3(0.0, LAMP_Y, 0.0)
	_light.omni_range = 7.0
	_light.light_color = PAL.beacon_glow
	_light.light_energy = 1.2
	add_child(_light)

	# Вращающийся прожектор (блок д): в фонаре, наклонён вниз — фонарь
	# сидит на ~8 м, пятно ложится в ~12–20 м от башни. Спад 0.8 и энергия
	# с запасом: на такой дистанции обратные квадраты быстро съедают свет.
	# В HIGH конус дополнительно виден в объёмном тумане (Forward+).
	_cone = SpotLight3D.new()
	_cone.name = "Cone"
	_cone.position = Vector3(0.0, LAMP_Y, 0.0)
	_cone.spot_range = CONE_RANGE
	_cone.spot_angle = CONE_ANGLE
	_cone.spot_attenuation = 0.8
	_cone.light_color = PAL.beacon_glow
	_cone.light_energy = 12.0
	_cone.shadow_enabled = false
	_cone.rotation_degrees = Vector3(-25.0, 0.0, 0.0)
	_cone.visible = false
	add_child(_cone)


func _lamp_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = PAL.beacon_glow.darkened(0.45)
	return material
