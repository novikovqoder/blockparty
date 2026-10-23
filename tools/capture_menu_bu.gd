extends SceneTree
## Снимает скриншоты всех разделов меню Born Unblessed.
## Запуск (нужен дисплей или xvfb-run):
##   godot --path . --resolution 1920x1080 --fixed-fps 30 -s res://tools/capture_menu_bu.gd -- --out=docs/screenshots/menu_bu
## Без аргумента --out кадры пишутся в user://menu_bu_shots/.
## Аргументы доработки П9 (правки меню, приёмка по сборке):
##   --plan=fix   укороченный план: главное меню (подсказки не наезжают,
##                «Продолжить» скрыт при первом запуске) и панель настроек
##                с полупрозрачной прокруткой;
##   --suffix=_fix  суффикс имён кадров (доказательства правок рядом
##                с исходными кадрами П9, не поверх).

const SCENE: String = "res://scenes/menu_bu/main_menu_bu.tscn"

var _menu: MainMenuBU
var _frame: int = 0
var _out: String = "user://menu_bu_shots"
var _suffix: String = ""
## Кадр (при 30 к/с) → действие.
var _plan: Array[Array] = [
	[150, "shot", "01_main"],
	[160, "open", "settings"],
	[250, "shot", "02_settings"],
	[255, "tab", "gfx"],
	[262, "shot", "03_settings_gfx"],
	[270, "open", "credits"],
	[370, "shot", "04_credits"],
	[380, "open", "chapters"],
	[470, "shot", "05_chapters"],
	[480, "open", "main"],
	[560, "shot", "06_main_again"],
	[565, "start", "continue"],
	[598, "shot", "07_continue_zoom"],
	[640, "shot", "08_continue_fade"],
	[650, "quit", ""],
]
## Доработка П9: кадры-доказательства правок меню.
var _plan_fix: Array[Array] = [
	[150, "shot", "01_main"],
	[160, "open", "settings"],
	[250, "shot", "02_settings"],
	[260, "quit", ""],
]


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--suffix="):
			_suffix = a.substr(9)
		elif a == "--plan=fix":
			_plan = _plan_fix
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_resolve(_out)))
	var packed: PackedScene = load(SCENE) as PackedScene
	_menu = packed.instantiate() as MainMenuBU
	root.add_child(_menu)


func _resolve(path: String) -> String:
	if path.begins_with("/") or path.begins_with("user://") or path.begins_with("res://"):
		return path
	return "res://" + path


func _process(_delta: float) -> bool:
	_frame += 1
	for step: Array in _plan:
		if int(step[0]) != _frame:
			continue
		var what: String = String(step[1])
		var arg: String = String(step[2])
		match what:
			"shot":
				var img: Image = root.get_texture().get_image()
				var p: String = _resolve(_out).path_join(arg + _suffix + ".png")
				var err: Error = img.save_png(p)
				print("shot ", p, " err=", err)
			"open":
				var sec: Dictionary[String, MainMenuBU.Section] = {
					"main": MainMenuBU.Section.MAIN, "settings": MainMenuBU.Section.SETTINGS,
					"credits": MainMenuBU.Section.CREDITS, "chapters": MainMenuBU.Section.CHAPTERS,
				}
				_menu.open_section(sec[arg])
			"tab":
				var sp: SettingsPanelBU = _menu.get("_settings_panel") as SettingsPanelBU
				sp.show_tab(StringName(arg))
			"start":
				_menu.call("_start", StringName(arg))
			"quit":
				return true
	return false
