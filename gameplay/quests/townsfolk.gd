# Житель острова (П5.5): NPC на модели KayKit того же персонажа в
# нейтральном цвете песка (не из 6 цветов игроков — не путать с людьми).
# Стоит на месте; когда игрок подходит ближе quest_npc_wave_range — машет
# (Тимьян сидит и не встаёт). Значок над головой: «!» — задание доступно,
# «…» — идёт, ничего — выполнено сегодня. Если локальный игрок играет тем
# же персонажем, житель скрыт и заменён табличкой «Записка от …» —
# только локальное отображение, по сети не передаётся. E — диалог
# (QuestDialog открывается сигналом EventBus).
class_name Townsfolk
extends Interactable

const B: Balance = preload("res://gameplay/balance.tres")
const PAL: Palette = preload("res://assets/palette.tres")

## Группа жителей (хост валидирует дистанцию диалога по узлам группы).
const TOWNSFOLK_GROUP: StringName = &"townsfolk"
## Нейтральный цвет жителей: тёплый песок, вне player_colors.
const NPC_COLOR: Color = Color("d9c3a0")
## Пауза между взмахами одному и тому же игроку, с.
const WAVE_COOLDOWN: float = 5.0
## Значки над головой: доступно / идёт.
const BADGE_AVAILABLE: String = "!"
const BADGE_ACTIVE: String = "…"
## Радиус капсулы-коллизии жителя, м; высота — до макушки модели
## (CharacterModel.HEAD_TOP_Y). Как у игрока: точка опоры у ступней,
## центр капсулы на половине высоты. Тело на слое 1 — его чувствует маска
## игрока (collision_mask = 1), сквозь жителя не пройти; Area3D самого
## узла остаётся триггером подсказки «E».
const COLLISION_RADIUS: float = 0.35

## Номер персонажа (0 Финн, 1 Луми, 2 Тимьян — как CharacterModel).
@export var character: int = 0
## Идентификатор задания жителя.
@export var quest_id: String = ""
## Тимьян сидит у костра (поза SIT, под ним пень).
@export var sitting: bool = false

var _model: CharacterModel
var _badge: Label3D
var _note: Node3D
var _wave_cooldown: float = 0.0
## Житель скрыт подменой на табличку (локальный игрок — тот же персонаж).
var _hidden: bool = false


func _ready() -> void:
	super()
	add_to_group(TOWNSFOLK_GROUP)
	use_radius = B.quest_npc_use_radius
	EventBus.quest_state.connect(_on_quest_state)
	_build_model()
	_build_collision()
	_build_badge()
	_build_note()
	# Хост-офлайн: применяем сразу своё состояние (клиент получит rpc).
	_on_quest_state(Net.quests.state())


func _process(delta: float) -> void:
	if _wave_cooldown > 0.0:
		_wave_cooldown -= delta
		return
	if sitting or _model == null or not _model.visible:
		return
	if _nearest_player_distance() <= B.quest_npc_wave_range:
		_wave_cooldown = WAVE_COOLDOWN
		_model.play_one_shot(Protocol.AnimState.WAVE, 2.0)


## «E — поговорить» (житель скрыт подменой — табличка говорит тем же E).
func hint_key() -> String:
	return "HINT_TALK"


func use(_player: Node3D) -> void:
	EventBus.quest_talk_requested.emit(quest_id)


## Применить состояние заданий от хоста: значок над головой.
func _on_quest_state(state: Dictionary) -> void:
	var quest: Variant = state.get(quest_id)
	var stage: int = QuestAuthority.DONE
	if quest is Dictionary:
		stage = int(quest["stage"])
	_badge.text = BADGE_AVAILABLE if stage == QuestAuthority.AVAILABLE \
		else BADGE_ACTIVE
	_badge.visible = stage != QuestAuthority.DONE and not _hidden


## Ближайший игрок (свой и чужие) — для взмаха при подходе.
func _nearest_player_distance() -> float:
	var best := INF
	for group: StringName in [Player.GROUP, RemotePlayer.GROUP]:
		for node in get_tree().get_nodes_in_group(group):
			var body := node as Node3D
			if body == null:
				continue
			best = minf(best, global_position.distance_to(body.global_position))
	return best


## Физическая форма жителя (баг vfx-fix): капсула по габариту модели,
## нижняя точка у ступней — Area3D самого узла остаётся триггером «E».
func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = 1  # слой мира: коллизию чувствует маска игрока
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = COLLISION_RADIUS
	capsule.height = CharacterModel.HEAD_TOP_Y
	shape.shape = capsule
	shape.position = Vector3(0.0, CharacterModel.HEAD_TOP_Y * 0.5, 0.0)
	body.add_child(shape)
	add_child(body)


## Модель персонажа в нейтральном цвете; Тимьян сидит на пне.
func _build_model() -> void:
	_model = CharacterModel.new()
	_model.name = "Model"
	_model.setup(character)
	_model.setup_body_color(NPC_COLOR)
	add_child(_model)
	if sitting:
		_model.set_state(Protocol.AnimState.SIT)
		var stump := MeshInstance3D.new()
		stump.name = "Stump"
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.24
		cyl.bottom_radius = 0.3
		cyl.height = B.campfire_seat_floor
		stump.mesh = cyl
		stump.position = Vector3(0.0, B.campfire_seat_floor * 0.5, 0.0)
		var material := StandardMaterial3D.new()
		material.albedo_color = PAL.trunk
		stump.material_override = material
		add_child(stump)


## Значок «!» / «…» над головой.
func _build_badge() -> void:
	_badge = Label3D.new()
	_badge.name = "Badge"
	_badge.text = BADGE_AVAILABLE
	_badge.font_size = 44
	_badge.outline_size = 6
	_badge.modulate = PAL.coin
	_badge.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_badge.no_depth_test = true
	_badge.fixed_size = false
	_badge.pixel_size = 0.004
	_badge.position = Vector3(0.0, CharacterModel.HEAD_TOP_Y + 0.55, 0.0)
	add_child(_badge)


## Табличка «Записка от …»: показывается вместо жителя, когда локальный
## игрок играет тем же персонажем (по сети ничего не меняется).
func _build_note() -> void:
	_note = Node3D.new()
	_note.name = "Note"
	var post := MeshInstance3D.new()
	post.name = "Post"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.04
	cyl.bottom_radius = 0.05
	cyl.height = 1.05
	post.mesh = cyl
	post.position = Vector3(0.0, 0.525, 0.0)
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = PAL.trunk
	post.material_override = post_mat
	_note.add_child(post)

	var board := MeshInstance3D.new()
	board.name = "Board"
	var box := BoxMesh.new()
	box.size = Vector3(0.72, 0.42, 0.05)
	board.mesh = box
	board.position = Vector3(0.0, 0.95, 0.0)
	var board_mat := StandardMaterial3D.new()
	board_mat.albedo_color = PAL.planks
	board.material_override = board_mat
	_note.add_child(board)

	var label := Label3D.new()
	label.name = "Text"
	label.text = tr("QUEST_NOTE") % _npc_name()
	label.font_size = 22
	label.outline_size = 4
	label.modulate = Color(0.25, 0.17, 0.1)
	label.pixel_size = 0.004
	label.position = Vector3(0.0, 0.95, 0.04)
	_note.add_child(label)

	add_child(_note)
	_hidden = Save.load_character() == character
	_note.visible = _hidden
	_model.visible = not _hidden
	if _hidden:
		_badge.visible = false


## Имя жителя из characters.json по текущей локали (как в UI выбора).
func _npc_name() -> String:
	return CharacterData.pick_text(CharacterData.get_character(character)["name"])
