# Маркер эмоции (разделы 9.1, 9.7 SPEC): «Сюда!» ставит светящийся столбик
# со стрелкой вниз в точку, куда смотрела камера отправителя (5 с);
# «Помогите!» — ту же стрелку над самим игроком (стрелка на упавшего,
# видна дальше пузыря). Создаётся миром по событию player_emoted и
# удаляется по таймеру. Модель из примитивов — заменяется сценой (П8).
class_name EmoteMarker
extends Node3D

const PAL: Palette = preload("res://assets/palette.tres")
const B: Balance = preload("res://gameplay/balance.tres")

var _left: float = 0.0


func _ready() -> void:
	# Столб света: тонкий цилиндр высотой 2.2 м от земли.
	var beam := MeshInstance3D.new()
	beam.name = "Beam"
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = 0.05
	beam_mesh.bottom_radius = 0.05
	beam_mesh.height = 2.2
	beam.mesh = beam_mesh
	beam.material_override = _glow()
	beam.position = Vector3(0.0, 1.1, 0.0)
	add_child(beam)
	# Стрелка вниз на верхушке: конус, остриё к земле.
	var arrow := MeshInstance3D.new()
	arrow.name = "Arrow"
	var arrow_mesh := CylinderMesh.new()
	arrow_mesh.top_radius = 0.02
	arrow_mesh.bottom_radius = 0.3
	arrow_mesh.height = 0.6
	arrow.mesh = arrow_mesh
	arrow.material_override = _glow()
	arrow.rotation.x = PI  # остриё вниз
	arrow.position = Vector3(0.0, 2.5, 0.0)
	add_child(arrow)


## Запустить таймер жизни маркера (раздел 9.7: emote_marker_time).
func show_for(seconds: float) -> void:
	_left = seconds
	set_process(true)


func _process(delta: float) -> void:
	_left -= delta
	if _left <= 0.0:
		queue_free()


func _glow() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = PAL.coin
	material.emission_enabled = true
	material.emission = PAL.coin
	material.emission_energy_multiplier = 2.2
	return material
