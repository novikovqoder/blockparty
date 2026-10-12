# Локальное сохранение user://save.json: внешность игрока (редактор
# П5.8, часть B), счётчики выполненных заданий жителей (П5.5, на будущее
# для «Встреч» П7). Монеты, косметика и блок-лист допишутся на своих этапах.
# Файл маленький и правится руками: значения вне диапазона молча
# превращаются в дефолтные, битый файл равен отсутствию.
extends Node

const PATH: String = "user://save.json"


## Запомнить внешность из редактора (валидную комбинацию — validated()).
func save_appearance(value: Appearance) -> void:
	var data := _read_all()
	var fixed := value.validated()
	data["appearance"] = [
		fixed.gender, fixed.hair, fixed.top, fixed.legs, fixed.feet,
		fixed.hat, fixed.hair_color, fixed.skin, fixed.eye_color,
	]
	_write_all(data)


## Сохранённая внешность; нет файла или мусор в поле — дефолтная
## (мужское тело, допустимые индексы — Appearance.default_for).
func load_appearance() -> Appearance:
	var saved: Variant = _read_all().get("appearance")
	if saved is Array and (saved as Array).size() >= Appearance.NET_SIZE:
		var bytes := PackedByteArray()
		for value: Variant in saved:
			bytes.append(clampi(int(value), 0, 255))
		return Appearance.from_bytes(bytes).validated()
	return Appearance.default_for(0)


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
