# Данные персонажей (раздел 16 SPEC, «Описания»): имя, девиз, описание и
# «Любит» трёх жителей острова лежат в characters.json — владелец правит
# тексты без правок кода. Каждое текстовое поле двуязычное {ru, en}; язык
# выбирается по текущей локали перевода (как tr()), запасной — ru.
# Номера записей совпадают с CharacterModel: 0 — Финн (Knight), 1 — Луми
# (Mage), 2 — Тимьян (Ranger).
class_name CharacterData
extends RefCounted

const PATH: String = "res://gameplay/player/characters.json"
## Язык, если в записи нет запрошенного.
const FALLBACK_LOCALE: String = "ru"

static var _cache: Array = []


## Все записи файла в порядке персонажей (индекс = номер модели).
static func all() -> Array:
	if _cache.is_empty():
		_load()
	return _cache


static func count() -> int:
	return all().size()


## Запись персонажа; номер вне диапазона → первая (правило CharacterModel).
static func get_character(index: int) -> Dictionary:
	var entries := all()
	if entries.is_empty():
		return {}
	if index < 0 or index >= entries.size():
		index = 0
	return entries[index]


## Текст из двуязычного поля {"ru": …, "en": …} по текущему языку.
static func pick_text(field: Dictionary) -> String:
	if field.is_empty():
		return ""
	var locale: String = TranslationServer.get_locale().left(2)
	if not field.has(locale):
		locale = FALLBACK_LOCALE
	return String(field.get(locale, ""))


## Характеристики персонажа (раздел 16): сила/скорость/прыжок, значения 1–5,
## сумма 9, каждый лучший ровно в одной. Ключи: "strength", "speed", "jump".
## Значения вне 1–5 заменяются серединой (3) — файл правится руками, без кода.
static func stats(index: int) -> Dictionary:
	var raw: Dictionary = get_character(index).get("stats", {})
	var result := {}
	for key: String in ["strength", "speed", "jump"]:
		result[key] = clampi(int(raw.get(key, 3)), 1, 5)
	return result


static func _load() -> void:
	var text := FileAccess.get_file_as_string(PATH)
	if text.is_empty():
		push_warning("CharacterData: не читается %s" % PATH)
		return
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Array:
		for entry: Variant in parsed:
			if entry is Dictionary:
				_cache.append(entry)
	if _cache.is_empty():
		push_warning("CharacterData: в %s нет записей" % PATH)
