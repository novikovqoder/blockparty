class_name MenuSettingsBU
extends RefCounted
## Хранилище настроек меню Born Unblessed: значения, сохранение в user://, применение.
## Самодостаточно. При интеграции можно переключить на автолоад `settings` проекта:
## достаточно заменить load_from_disk()/save_to_disk() и apply_runtime().

signal changed(key: StringName)

const SAVE_PATH: String = "user://settings_bu.cfg"
const SECTION: String = "settings"

const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160),
	Vector2i(1600, 900), Vector2i(1280, 720),
]
const FPS_CAPS: Array[int] = [30, 60, 120, 144, 0]
const LOCALES: Array[String] = ["ru", "en"]

## Названия аудиошин проекта. Если шины нет, громкость просто сохраняется.
const AUDIO_BUSES: Dictionary[StringName, String] = {
	&"master": "Master", &"music": "Music", &"sfx": "SFX", &"amb": "Ambient", &"voice": "Voice",
}

const DEFAULTS: Dictionary[StringName, Variant] = {
	&"mode": 0, &"res": 0, &"quality": 2, &"vsync": true, &"fps": 1,
	&"bright": 50, &"grain": true, &"camshake": 70,
	&"master": 80, &"music": 60, &"sfx": 85, &"amb": 70, &"voice": 90, &"bgsound": false,
	&"sens": 45, &"invert": false,
	&"diff": 1, &"gore": 2, &"hints": true, &"subs": true, &"subsize": 1, &"hitshake": 80,
	&"lang": 0, &"voicelang": 0, &"sublang": 0,
}

var values: Dictionary[StringName, Variant] = {}
var dirty: bool = false


func _init() -> void:
	reset_all()


func reset_all() -> void:
	values = DEFAULTS.duplicate()


func reset_keys(keys: Array[StringName]) -> void:
	for k: StringName in keys:
		if DEFAULTS.has(k):
			values[k] = DEFAULTS[k]
			changed.emit(k)
	dirty = true


func get_int(key: StringName) -> int:
	return int(values.get(key, DEFAULTS.get(key, 0)))


func get_bool(key: StringName) -> bool:
	return bool(values.get(key, DEFAULTS.get(key, false)))


func set_value(key: StringName, value: Variant) -> void:
	if values.get(key) == value:
		return
	values[key] = value
	dirty = true
	changed.emit(key)


## Сила тряски камеры меню, 0..1.
func camera_shake_factor() -> float:
	return clampf(float(get_int(&"camshake")) / 100.0, 0.0, 1.0)


func load_from_disk() -> void:
	reset_all()
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for k: StringName in DEFAULTS.keys():
		if cfg.has_section_key(SECTION, String(k)):
			var v: Variant = cfg.get_value(SECTION, String(k))
			if typeof(v) == typeof(DEFAULTS[k]):
				values[k] = v
	dirty = false


func save_to_disk() -> Error:
	var cfg: ConfigFile = ConfigFile.new()
	for k: StringName in values.keys():
		cfg.set_value(SECTION, String(k), values[k])
	var err: Error = cfg.save(SAVE_PATH)
	if err == OK:
		dirty = false
	return err


## Применяет то, что можно применить сразу: окно, синхронизацию, кадры, громкость, язык.
## Остальное (сложность, кровь, подсказки) читается игрой из values.
func apply_runtime() -> void:
	if DisplayServer.get_name() == "headless":
		_apply_audio()
		_apply_locale()
		return
	match get_int(&"mode"):
		0:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		1:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			var res: Vector2i = RESOLUTIONS[clampi(get_int(&"res"), 0, RESOLUTIONS.size() - 1)]
			DisplayServer.window_set_size(res)
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if get_bool(&"vsync") else DisplayServer.VSYNC_DISABLED
	)
	Engine.max_fps = FPS_CAPS[clampi(get_int(&"fps"), 0, FPS_CAPS.size() - 1)]
	_apply_audio()
	_apply_locale()


func _apply_audio() -> void:
	for k: StringName in AUDIO_BUSES.keys():
		var idx: int = AudioServer.get_bus_index(AUDIO_BUSES[k])
		if idx < 0:
			continue
		var pct: float = clampf(float(get_int(k)) / 100.0, 0.0, 1.0)
		AudioServer.set_bus_mute(idx, pct <= 0.001)
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(pct, 0.0001)))


func _apply_locale() -> void:
	var loc: String = LOCALES[clampi(get_int(&"lang"), 0, LOCALES.size() - 1)]
	TranslationServer.set_locale(loc)
