# Остров (раздел 6 SPEC): сцена gameplay/world/island.tscn собирается оффлайн
# tools/generate_island.gd из детерминированных данных IslandGen (рельеф
# и предметы — запечённый IslandArt в IslandView, вода, расщелина с HangPoint,
# камни духа, руины, пирс, костёр, монеты, мобы, ограждения) и коммитится.
# Этот скрипт — тонкая обвязка корня: точки появления по --dev-spawn
# и название зоны для F3/карты; вся геометрия уже в сцене, рантайм ничего
# не строит. Данные зон — @export (видны в tscn).
class_name Island
extends Node3D

const B: Balance = preload("res://gameplay/balance.tres")

## Зоны острова: {name: String, center: Vector2, radius: float} — для карты,
## названий мест и проверки «внутри зоны» (радиус круга).
@export var zones: Array[Dictionary] = []
## Точка появления по имени зоны (--dev-spawn, Session.spawn_zone).
@export var spawn_zones: Dictionary = {}
## Граница мира, м (невидимые ограждения по периметру).
@export var world_bounds: float = 127.5


func _ready() -> void:
	EventBus.player_emoted.connect(_on_player_emoted)


## Маркеры эмоций (разделы 9.1, 9.7): «Сюда!» — светящийся столбик в точку,
## куда смотрела камера отправителя; «Помогите!» — стрелка над самим игроком
## (видна дальше пузыря). Остальные эмоции — только пузырь над головой.
func _on_player_emoted(peer: int, emote: int, marker: Vector3) -> void:
	match emote:
		Protocol.Emote.HERE:
			_spawn_marker(marker)
		Protocol.Emote.HELP:
			var node := _peer_node(peer)
			if node != null:
				_spawn_marker(node.global_position)


func _spawn_marker(at: Vector3) -> void:
	var node := EmoteMarker.new()
	add_child(node)
	node.global_position = at
	node.show_for(B.emote_marker_time)


## Узел игрока по peer (свой — группа player, чужие — remote_player).
func _peer_node(peer: int) -> Node3D:
	if peer == Net.local_peer_id:
		var own := get_tree().get_first_node_in_group(Player.GROUP)
		return own as Node3D
	for node in get_tree().get_nodes_in_group(RemotePlayer.GROUP):
		var remote := node as RemotePlayer
		if remote != null and remote.peer_id == peer:
			return remote
	return null

## Позиция появления в зоне (неизвестная зона — Площадь).
func spawn_point(zone_name: String) -> Vector3:
	var point: Variant = spawn_zones.get(zone_name, spawn_zones.get("plaza"))
	if point is Vector3:
		return point
	return Vector3.ZERO


## Имя зоны, в которой стоит позиция (пусто — между зонами). Название для UI
## локализуется по ключу ZONE_<ИМЯ> (i18n/strings.csv).
func zone_name_at(pos: Vector3) -> String:
	var best: String = ""
	var best_distance: float = 1e9
	for zone: Dictionary in zones:
		var center: Vector2 = zone["center"]
		var distance: float = Vector2(pos.x, pos.z).distance_to(center)
		if distance <= float(zone["radius"]) and distance < best_distance:
			best = zone["name"]
			best_distance = distance
	return best
