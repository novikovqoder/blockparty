# Житель острова: NPC на модели CharacterModel того же персонажа в
# нейтральном цвете песка (не из 6 цветов игроков — не путать с людьми).
# Стоит на месте; когда игрок подходит ближе WAVE_RANGE — машет
# (Тимьян сидит и не встаёт). П5.9 переделка П4: задания жителей удалены —
# житель не интерактивен (без значка «!» и диалога), осталась живая
# реакция на подход игрока. Подмена жителя табличкой при совпадении
# с персонажем игрока убрана (П5.8): внешность игрока теперь редактируется
# свободно, совпадений с жителями больше не бывает.
class_name Townsfolk
extends Node3D

## Группа жителей (спавн и тесты находят их по группе).
const TOWNSFOLK_GROUP: StringName = &"townsfolk"
## Нейтральный цвет жителей: тёплый песок, вне player_colors.
const NPC_COLOR: Color = Color("d9c3a0")
## Пауза между взмахами одному и тому же игроку, с.
const WAVE_COOLDOWN: float = 5.0
## Дистанция, с которой житель машет при подходе игрока, м.
const WAVE_RANGE: float = 6.0
## Радиус капсулы-коллизии жителя, м; высота — до макушки модели
## (CharacterModel.HEAD_TOP_Y). Как у игрока: точка опоры у ступней,
## центр капсулы на половине высоты. Тело на слое 1 — его чувствует маска
## игрока (collision_mask = 1), сквозь жителя не пройти.
const COLLISION_RADIUS: float = 0.35

## Номер персонажа (0 Финн, 1 Луми, 2 Тимьян — как CharacterModel).
@export var character: int = 0
## Тимьян сидит у костра (поза SIT, под ним пень).
@export var sitting: bool = false

var _model: CharacterModel
var _wave_cooldown: float = 0.0


func _ready() -> void:
	add_to_group(TOWNSFOLK_GROUP)
	_build_model()
	_build_collision()


func _process(delta: float) -> void:
	if _wave_cooldown > 0.0:
		_wave_cooldown -= delta
		return
	if sitting or _model == null or not _model.visible:
		return
	if _nearest_player_distance() <= WAVE_RANGE:
		_wave_cooldown = WAVE_COOLDOWN
		_model.play_one_shot(Protocol.AnimState.WAVE, 2.0)


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
## нижняя точка у ступней.
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
		# Доработка-2 П5.13, П6: пень — бревенчатый меш с корой ambientCG
		# (PropMeshes._stump, тот же стиль, что коряги и мостик), не цилиндр
		# плоского цвета. Низ меша — в origin, высота = campfire_seat_floor.
		var stump := MeshInstance3D.new()
		stump.name = "Stump"
		stump.mesh = PropMeshes.mesh(&"stump", 0)
		add_child(stump)
