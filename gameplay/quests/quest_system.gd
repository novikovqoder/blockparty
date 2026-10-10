# Оркестратор заданий жителей (П5.5): создаёт узлы (жители, мята, вехи,
# квестовые маяки) по детерминированной раскладке QuestLayout — остров
# не перегенерируется, хеш арта не меняется. Узлы сами слушают
# EventBus.quest_state; сюда приходят финалы (эффекты — блоки 2–4)
# и локальные счётчики выполненных заданий (user://save.json, П7).
class_name QuestSystem
extends Node3D

const B: Balance = preload("res://gameplay/balance.tres")

## Запечённый арт (высоты и коллайдеры для раскладки).
var _art: IslandArt
## Последнее состояние заданий (для эффектов финалов).
var _state: Dictionary = {}


func _ready() -> void:
	var island := get_parent()
	if island is Island:
		var view := island.get_node_or_null("IslandView") as IslandView
		if view != null:
			_art = view.art
	_spawn_all()
	EventBus.quest_state.connect(_on_quest_state)
	EventBus.quest_reward.connect(_on_quest_reward)
	# Хост-офлайн применяет своё состояние сразу; клиент получит rpc/world_state.
	_on_quest_state(Net.quests.state())


## Создать все узлы заданий: жители у площади, мята в Лесу, вехи по маршруту
## Финна, квестовые маяки (два — у существующих башен мирового события,
## один — на смотровой площадке).
func _spawn_all() -> void:
	var folk_spots := QuestLayout.npc_spots(_art)
	for i: int in folk_spots.size():
		var spot: Dictionary = folk_spots[i]
		var folk := Townsfolk.new()
		folk.name = "Folk%d" % (i + 1)
		folk.character = int(spot["character"])
		folk.quest_id = spot["quest_id"]
		folk.sitting = bool(spot["sitting"])
		add_child(folk)
		folk.global_position = spot["pos"]
		folk.rotation.y = float(spot["yaw"])

	var mint_spots := QuestLayout.mint_positions(_art)
	for i: int in mint_spots.size():
		var mint := MintPatch.new()
		mint.name = "Mint%d" % (i + 1)
		mint.index = i
		add_child(mint)
		mint.global_position = mint_spots[i]

	var flag_spots := QuestLayout.flag_positions(_art)
	for i: int in flag_spots.size():
		var flag := TrailFlag.new()
		flag.name = "Flag%d" % (i + 1)
		flag.index = i
		add_child(flag)
		flag.global_position = flag_spots[i]

	var spots := QuestLayout.quest_beacon_spots(_art)
	for i: int in spots.size():
		var beacon := QuestBeacon.new()
		beacon.name = "QuestBeacon%d" % (i + 1)
		beacon.index = i
		var target: Vector2 = spots[i]["world_target"]
		var pos: Vector3 = spots[i]["pos"]
		if not is_nan(target.x):
			# У подножия существующей башни «Маяков» (переиспользуем объект,
			# новых башен не строим): огонёк в полутора метрах от ствола.
			var tower := _nearest_beacon_tower(target)
			if tower != null:
				var offset := Vector3(1.5, 0.0, 1.5)
				pos = tower.global_position + offset
				pos.y = QuestLayout.ground_height(_art, pos.x, pos.z)
		add_child(beacon)
		beacon.global_position = pos
	Log.info(
		"Задания жителей: узлы созданы (жители %d, мята %d, вехи %d, маяки %d)"
		% [folk_spots.size(), mint_spots.size(), flag_spots.size(), spots.size()],
		"Quest"
	)


func _nearest_beacon_tower(target: Vector2) -> Beacon:
	var best: Beacon = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group(Beacon.BEACON_GROUP):
		var beacon := node as Beacon
		if beacon == null:
			continue
		var distance := Vector2(
			beacon.global_position.x, beacon.global_position.z
		).distance_to(target)
		if distance < best_distance:
			best_distance = distance
			best = beacon
	return best


## Состояние заданий от хоста (включая свой офлайн-мир).
func _on_quest_state(state: Dictionary) -> void:
	_state = state


## Финал задания: локальный счётчик в save.json (П7, «Встречи») и тост.
## Эффекты финалов (пар и светлячки, мини-звездопад, тропа) — блоки 2–4.
func _on_quest_reward(quest_id: String, peers: Array, coins: Array, _extra: Dictionary) -> void:
	if peers.has(Net.local_peer_id):
		Save.bump_quest_done(quest_id)
		var mine := 0
		for i: int in peers.size():
			if int(peers[i]) == Net.local_peer_id:
				mine = int(coins[i])
		Log.info(
			"Задание %s выполнено: +%d монет (участников %d)"
			% [quest_id, mine, peers.size()], "Quest"
		)
		EventBus.toast_requested.emit("QUEST_TOAST_DONE")
