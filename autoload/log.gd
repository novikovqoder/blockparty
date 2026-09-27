# Логирование: пишет сообщения в консоль и в user://logs/ (один файл на запуск,
# хранятся последние 10). Уровни: debug, info, warn, error.
# Не делает: метрики плейтеста (runs.jsonl — этап 6), конфигурацию уровней.
extends Node

## Сколько прошлых логов хранить в user://logs/.
const MAX_LOG_FILES: int = 10

var _file: FileAccess
var _file_path: String = ""


func _init() -> void:
	var dir_path: String = "user://logs"
	DirAccess.make_dir_recursive_absolute(dir_path)
	var stamp: String = Time.get_datetime_string_from_system().replace("T", "_").replace(":", "")
	_file_path = dir_path.path_join("game_%s.log" % stamp)
	_file = FileAccess.open(_file_path, FileAccess.WRITE)
	if _file == null:
		# Лог в консоль обязан работать даже если файл не открылся.
		push_warning("Log: не удалось открыть файл лога %s (код %d)" % [_file_path, FileAccess.get_open_error()])
	_trim_old_logs(dir_path)


func debug(message: String, tag: String = "") -> void:
	_write("DEBUG", message, tag)


func info(message: String, tag: String = "") -> void:
	_write("INFO", message, tag)


func warn(message: String, tag: String = "") -> void:
	_write("WARN", message, tag)


func error(message: String, tag: String = "") -> void:
	_write("ERROR", message, tag)


func get_log_path() -> String:
	return _file_path


func _write(level: String, message: String, tag: String) -> void:
	var prefix: String = ""
	if tag != "":
		prefix = "[%s] " % tag
	var line: String = "[%10.3f] [%s] %s%s" % [float(Time.get_ticks_msec()) / 1000.0, level, prefix, message]
	if level == "ERROR":
		printerr(line)
	else:
		print(line)
	if _file != null:
		_file.store_line(line)
		_file.flush()


## Удаляет самые старые game_*.log, оставляя MAX_LOG_FILES штук.
func _trim_old_logs(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	var names: Array[String] = []
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if name.begins_with("game_") and name.ends_with(".log"):
			names.append(name)
		name = dir.get_next()
	dir.list_dir_end()
	names.sort()  # имена начинаются с даты, поэтому сортировка хронологическая
	while names.size() > MAX_LOG_FILES:
		var oldest: String = names.pop_front()
		var err: int = dir.remove(dir_path.path_join(oldest))
		if err != OK:
			push_warning("Log: не удалось удалить старый лог %s (код %d)" % [oldest, err])
