# Сундук в руинах (раздел 8 SPEC): закрыт, пока закрыты ворота; открывается
# вместе с ними, узел рисует откинутую крышку и тёплое свечение внутри.
class_name RuinChest
extends Node3D

const PAL: Palette = preload("res://assets/palette.tres")
const WOOD_TEX: Texture2D = preload(
	"res://assets/third_party/ambientcg.com/Planks007/Planks007_2K-JPG_Color.jpg")

## Корпус сундука, м.
const BODY_SIZE: Vector3 = Vector3(0.95, 0.55, 0.6)
## Угол открытой крышки, рад.
const OPEN_ANGLE: float = -1.9
## Высота сундука с крышкой (коллизия, баг vfx-fix), м.
const SOLID_HEIGHT: float = 0.77

var _lid: Node3D
var _open: bool = false


func _ready() -> void:
	EventBus.ruins_state.connect(_on_ruins_state)
	_build_chest()


func _on_ruins_state(open: bool, _plates: Array, _openers: Array) -> void:
	set_open(open)


## Применить состояние от хоста (rpc_ruins / world_state).
func set_open(open: bool) -> void:
	if open == _open:
		return
	_open = open
	var tween := create_tween()
	tween.tween_property(_lid, "rotation:x", OPEN_ANGLE if open else 0.0, 0.5) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Дерево сундука (доработка-2 П5.13, П4): текстура плах ambientCG
## (Planks007, CC0) с тоном палитры; в headless — прежний плоский цвет.
func _wood(dark: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	if WorldMaterials.want_flat():
		material.albedo_color = PAL.trunk.darkened(dark)
		return material
	material.albedo_texture = WOOD_TEX
	material.albedo_color = Color(0.9, 0.78, 0.62).darkened(dark)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.uv1_scale = Vector3(0.8, 0.5, 0.55)
	material.roughness = 0.85
	return material


## Корпус, светящееся нутро и крышка на задней кромке (петля).
func _build_chest() -> void:
	# Твёрдый сундук (баг vfx-fix): бокс по корпусу с крышкой.
	var solid := BoxShape3D.new()
	solid.size = Vector3(BODY_SIZE.x, SOLID_HEIGHT, BODY_SIZE.z)
	SolidBody.add(self, solid, Vector3(0.0, SOLID_HEIGHT * 0.5, 0.0))
	var body := MeshInstance3D.new()
	body.name = "Body"
	var body_mesh := BoxMesh.new()
	body_mesh.size = BODY_SIZE
	body.mesh = body_mesh
	body.material_override = _wood(0.0)
	body.position = Vector3(0.0, BODY_SIZE.y * 0.5, 0.0)
	add_child(body)

	# Нутро чуть выше кромки: видно только при открытой крышке.
	var glow := MeshInstance3D.new()
	glow.name = "Glow"
	var glow_mesh := BoxMesh.new()
	glow_mesh.size = Vector3(BODY_SIZE.x - 0.14, 0.1, BODY_SIZE.z - 0.12)
	glow.mesh = glow_mesh
	var glow_material := StandardMaterial3D.new()
	glow_material.albedo_color = PAL.firefly
	glow_material.emission_enabled = true
	glow_material.emission = PAL.firefly
	glow_material.emission_energy_multiplier = 1.6
	glow.material_override = glow_material
	glow.position = Vector3(0.0, BODY_SIZE.y + 0.02, 0.0)
	add_child(glow)

	# Крышка: pivot на задней кромке, поворот вокруг неё.
	_lid = Node3D.new()
	_lid.name = "Lid"
	_lid.position = Vector3(0.0, BODY_SIZE.y, -BODY_SIZE.z * 0.5)
	add_child(_lid)
	var lid_top := MeshInstance3D.new()
	lid_top.name = "Top"
	var lid_mesh := BoxMesh.new()
	lid_mesh.size = Vector3(BODY_SIZE.x, 0.22, BODY_SIZE.z)
	lid_top.mesh = lid_mesh
	lid_top.material_override = _wood(-0.06)
	lid_top.position = Vector3(0.0, 0.11, BODY_SIZE.z * 0.5)
	_lid.add_child(lid_top)
