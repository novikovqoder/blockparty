# Локальное сохранение user://save.json: выбранный персонаж (раздел 15,
# П4.6), счётчики выполненных заданий жителей (П5.5, на будущее для
# «Встреч» П7). Монеты, косметика и блок-лист допишутся на своих этапах.
# Файл маленький и правится руками: значения вне диапазона молча
# превращаются в дефолтные, битый файл равен отсутствию.
extends Node

const PATH: String = "user://save.json"
## Дефолтный персонаж — первый (раздел 15).
const DEFAULT_CHARACTER: int = 0


## Запомнить выбранный персонаж (0…2).
func save_character(index: int) -> void:
	var data := _read_all()
	data["character"] = clampi(index, 0, CharacterModel.count() - 1)
	_write_all(data)


## Выбранный персонаж; нет файла или неверное число — первый.
func load_character() -> int:
	var index := int(_read_all().get("character", DEFAULT_CHARACTER))
	return index if index >= 0 and index < CharacterModel.count() \
		else DEFAULT_CHARACTER


## Счётчик выполненных заданий жителей (П5.5): +1 по id задания.
func bump_quest_done(quest_id: String) -> void:
	var data := _read_all()
	var counts: Dictionary = data.get("quests_done", {})
	counts[quest_id] = int(counts.get(quest_id, 0)) + 1
	data["quests_done"] = counts
	_write_all(data)


## Сколько раз выполнено задание с этим id.
func quest_done_count(quest_id: String) -> int:
	return int(_read_all().get("quests_done", {}).get(quest_id, 0))


func _write_all(data: Dictionary) -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Save: не открыть %s на запись" % PATH)
		return
	file.store_string(JSON.stringify(data, "\t"))


func _read_all() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {}
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}
