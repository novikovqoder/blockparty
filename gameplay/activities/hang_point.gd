# Точка цепляния на кромке расщелины (раздел 9.1 SPEC): светящийся кубик
# над кромкой. Когда рядом с точкой висит другой игрок, становится
# интерактивной — удержание E вытягивает его (Сила помощника сокращает
# удержание, раздел 16). Подтверждает хост: узел только шлёт запрос
# rpc_request_pull и рисует подсказку. Дети Crevasse в island.tscn.
class_name HangPoint
extends Interactable

const B: Balance = preload("res://gameplay/balance.tres")
const PAL: Palette = preload("res://assets/palette.tres")

## Кубик-маячок точки, м.
const POINT_SIZE: float = 0.14
## Подъём кубика над кромкой, м.
const POINT_LIFT: float = 0.12
## Висящего ищем от точки не дальше этого, м.
const HANGING_SEARCH: float = 2.0


func _ready() -> void:
	super()
	use_radius = B.pull_radius + 0.5
	_build_glow()


## «E — Вытянуть», если рядом с точкой висит чужой игрок (свой — не может
## тянуть себя; висящего видно по флагу снапшота FLAG_HANGING).
func hint_key() -> String:
	return "HINT_PULL" if hanging_peer_nearby() != 0 else ""


## Удержание E: базовое время делится на множитель Силы помощника —
## сильный тянет быстрее (раздел 17), но вытянуть может любой.
func hold_time(player: Node3D) -> float:
	var strength: int = 3
	if player is Player:
		strength = (player as Player).strength()
	return B.pull_hold_time / B.strength_multipliers[strength - 1]


func use(player: Node3D) -> void:
	var target := hanging_peer_nearby()
	if target == 0:
		return
	if player is Player:
		(player as Player).helper_pull()
	Net.request_pull(target)


## Peer чужого игрока, висящего у этой точки (0 — рядом никто не висит;
## свой персонаж не считается: тянуть может только другой).
func hanging_peer_nearby() -> int:
	for node in get_tree().get_nodes_in_group(RemotePlayer.GROUP):
		var remote := node as RemotePlayer
		if remote == null or not remote.is_hanging():
			continue
		var flat := remote.last_position() - global_position
		flat.y = 0.0
		if flat.length() <= HANGING_SEARCH:
			return remote.peer_id
	return 0


## Светящаяся точка на кромке (как в П1: кубик цвета светлячка).
func _build_glow() -> void:
	var glow := MeshInstance3D.new()
	glow.name = "Glow"
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * POINT_SIZE
	glow.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = PAL.firefly
	material.emission_enabled = true
	material.emission = PAL.firefly
	material.emission_energy_multiplier = 2.0
	glow.material_override = material
	glow.position = Vector3.UP * POINT_LIFT
	add_child(glow)
