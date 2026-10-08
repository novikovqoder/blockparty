# Доска прогресса маяков (раздел 7 SPEC): «Маяки: 3 / 5» на площади у
# костра. Полотно доски строит генератор (предмет «board»), узел — только
# текст на нём; обновляется сигналом beacons_state (зажигание и Звездопад
# решает хост). Ставится в island.tscn на месте poi.campfire.board,
# лицом к костру (юг).
class_name BeaconBoard
extends Label3D

## Высота полотна доски над её основанием, м (prop_meshes._board).
const BOARD_TEXT_Y: float = 1.15


func _ready() -> void:
	pixel_size = 0.008
	font_size = 40
	outline_size = 6
	modulate = Color(0.24, 0.17, 0.1)
	double_sided = false
	# Полотно доски тонкое по Z, текст — на южной стороне (к костру).
	rotation.y = PI
	text = _format(0)
	EventBus.beacons_state.connect(_on_beacons_state)


func _on_beacons_state(lit: Array, _lighters: Array, _starfall_started_at: float) -> void:
	text = _format(lit.size())


## «Маяки: 3 / 5» — текст через tr() (правило проекта); всего маяков —
## по числу узлов группы в сцене (не подписывается руками).
func _format(lit_count: int) -> String:
	var total := get_tree().get_nodes_in_group(Beacon.BEACON_GROUP).size()
	return tr("BOARD_BEACONS") % [lit_count, total]
