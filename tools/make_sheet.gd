extends SceneTree
## Склейка PNG-кадров в сетку (контактный лист) для визуальных проверок:
## кадры серии footfx → пары «было–стало» и «замедленный клип»-ленты.
## Godot вместо ImageMagick: на сервере нет ни magick, ни PIL.
## Запуск:
##   godot --headless -s res://tools/make_sheet.gd -- --cols 2 \
##     --out docs/screenshots/footfx/pair.png a.png b.png [c.png ...]
## Кадры укладываются слева направо, сверху вниз; между кадрами и по краям
## — разделительная рамка 4 пикселя (тёмная), чтобы соседние кадры не
## сливались. Выход: 0 — лист собран; 4 — не задан --out или нет кадров.
## Файлы промежуточные (сами кадры серии) в git не идут — только готовые
## листы из docs/screenshots.

const BORDER: int = 4
const EDGE: int = 4

var _out: String = ""
var _cols: int = 2
var _files: PackedStringArray = []


func _initialize() -> void:
	var positional := true
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--":
			positional = true
		elif arg.begins_with("--out="):
			_out = arg.substr(6)
		elif arg.begins_with("--cols="):
			_cols = maxi(1, arg.substr(7).to_int())
		elif positional:
			_files.append(arg)
	if _out.is_empty() or _files.is_empty():
		push_error("SHEET FAIL: нужен --out=... и хотя бы один кадр")
		quit(4)
		return

	var cell := Image.create(1, 1, false, Image.FORMAT_RGB8)
	var first := true
	for path: String in _files:
		var img := Image.load_from_file(path)
		if img == null:
			push_error("SHEET FAIL: не читается %s" % path)
			quit(4)
			return
		if first or img.get_size() != cell.get_size():
			if first:
				cell = img
				first = false
				continue
			# Кадры разного размера — сводим к первому (масштаб ближайшим).
			img.resize(cell.get_width(), cell.get_height(),
				Image.INTERPOLATE_NEAREST)

	var rows: int = ceili(float(_files.size()) / float(_cols))
	var cw: int = cell.get_width() + BORDER
	var ch: int = cell.get_height() + BORDER
	var sheet := Image.create(
		EDGE * 2 + cw * _cols - BORDER,
		EDGE * 2 + ch * rows - BORDER, false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.12, 0.12, 0.12))
	for i: int in _files.size():
		var img := Image.load_from_file(_files[i])
		var col: int = i % _cols
		var row: int = i / _cols
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()),
			Vector2i(EDGE + cw * col, EDGE + ch * row))

	DirAccess.make_dir_recursive_absolute(_out.get_base_dir())
	var err := sheet.save_png(_out)
	if err != OK:
		push_error("SHEET FAIL: save_png %s (err %d)" % [_out, err])
		quit(4)
		return
	print("SHEET PASS: %s — %d кадров, сетка %d×%d" % [
		_out, _files.size(), _cols, rows])
	quit(0)
