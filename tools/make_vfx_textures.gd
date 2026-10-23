extends SceneTree
## Нарезает спрайты частиц (доработка П9, частицы бега) из CC0-текстур
## проекта: комья земли (forest_ground_05), травинки и лист (Grass001),
## камень (Rock001). Плюс процедурное мягкое пятно soft.png — маска
## дымки/искр/светлячков, чтобы ни одна частица мира не была нетекстурным
## белым квадратом. Выбор участка детерминирован (RandomNumberGenerator
## с фиксированным seed): повторный запуск даёт те же спрайты.
## Запуск:
##   godot --headless -s res://tools/make_vfx_textures.gd
##   godot --headless --import   # (создать .import)
##   godot --headless -s res://tools/make_vfx_textures.gd --mips
##   godot --headless --import   # (переприём с мип-мапами)
## Шаг --mips включает мип-мапы в созданных .import-сайдкарах.

const OUT_DIR: String = "res://assets/vfx/particles"
const SOURCES: Dictionary = {
	"dirt": "res://assets/third_party/polyhaven.com/forest_ground_05/forest_ground_05_diffuse_2k.jpg",
	"grass": "res://assets/third_party/ambientcg.com/Grass001/Grass001_1K-JPG_Color.jpg",
	"stone": "res://assets/third_party/ambientcg.com/Rock001/Rock001_1K-JPG_Color.jpg",
}
## Размер спрайтов, px. Мелкие пятна частиц — 64 px хватает и для бега
## у самых ног (кроп в кадре ~5–10 % высоты экрана).
const SPRITE: int = 64
## Сколько случайных кропов рассматривать на спрайт (берём самый
## контрастный — «комья», а не гладкая замыть).
const CANDIDATES: int = 24
## Фиксированный seed нарезки.
const SEED: int = 20261023

## Лист — вытянутый кроп травы с эллиптической маской.
const LEAF_W: int = 40
const LEAF_H: int = 64
## Мягкое пятно (маска) — белый, альфа тает от центра к краю.
const SOFT: int = 96


func _init() -> void:
	var args := PackedStringArray(OS.get_cmdline_user_args())
	if args.has("--mips"):
		_patch_mips()
		quit(0)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	for name: String in SOURCES:
		var img := _load_image(SOURCES[name])
		if img == null:
			push_error("нет исходника %s" % SOURCES[name])
			quit(1)
			return
		_save(_crop_round(img, rng), "%s/%s.png" % [OUT_DIR, name])
		if name == "grass":
			_save(_crop_leaf(img, rng), "%s/leaf.png" % OUT_DIR)
	_save(_soft(), "%s/soft.png" % [OUT_DIR])
	print("make_vfx_textures: спрайты записаны в %s" % OUT_DIR)
	quit(0)


func _load_image(path: String) -> Image:
	var tex := load(path) as Texture2D
	if tex == null:
		return null
	return tex.get_image()


## Лучший из CANDIDATES случайных кропов с круглой маской альфы:
## края прозрачны, виден «комок», а не квадрат текстуры.
func _crop_round(src: Image, rng: RandomNumberGenerator) -> Image:
	var best: Image = null
	var best_score: float = -1.0
	for i in CANDIDATES:
		var x := rng.randi_range(0, src.get_width() - SPRITE)
		var y := rng.randi_range(0, src.get_height() - SPRITE)
		var crop := src.get_region(Rect2i(x, y, SPRITE, SPRITE))
		var score := _detail(crop)
		if score > best_score:
			best_score = score
			best = crop
	var out := best.duplicate() as Image
	out.convert(Image.FORMAT_RGBA8)
	var c := float(SPRITE - 1) * 0.5
	for py in SPRITE:
		for px in SPRITE:
			var d := Vector2(px - c, py - c).length() / c
			var col := out.get_pixel(px, py)
			# Полный круг до 0.72 радиуса, плавный сход на нет к краю.
			col.a = clampf((1.0 - d) / 0.28, 0.0, 1.0)
			out.set_pixel(px, py, col)
	return out


## Лист: вертикальный кроп с эллиптической маской (трава как лист-пятно).
func _crop_leaf(src: Image, rng: RandomNumberGenerator) -> Image:
	var best: Image = null
	var best_score: float = -1.0
	for i in CANDIDATES:
		var x := rng.randi_range(0, src.get_width() - LEAF_W)
		var y := rng.randi_range(0, src.get_height() - LEAF_H)
		var crop := src.get_region(Rect2i(x, y, LEAF_W, LEAF_H))
		var score := _detail(crop)
		if score > best_score:
			best_score = score
			best = crop
	var out := best.duplicate() as Image
	out.convert(Image.FORMAT_RGBA8)
	for py in LEAF_H:
		for px in LEAF_W:
			var dx := (float(px) + 0.5) / LEAF_W - 0.5
			var dy := (float(py) + 0.5) / LEAF_H - 0.5
			var d := Vector2(dx * 2.0, dy * 2.0).length() * 0.5
			var col := out.get_pixel(px, py)
			col.a = clampf((1.0 - d) / 0.3, 0.0, 1.0)
			out.set_pixel(px, py, col)
	return out


## Процедурное мягкое пятно: белое ядро, альфа тает по радиусу.
func _soft() -> Image:
	var img := Image.create_empty(SOFT, SOFT, false, Image.FORMAT_RGBA8)
	var c := float(SOFT - 1) * 0.5
	for py in SOFT:
		for px in SOFT:
			var d := Vector2(px - c, py - c).length() / c
			var a := clampf((1.0 - d) / 0.55, 0.0, 1.0)
			img.set_pixel(px, py, Color(1.0, 1.0, 1.0, a * a))
	return img


## Суммарный градиент яркости — чем рельефнее кроп, тем лучше.
func _detail(img: Image) -> float:
	var sum: float = 0.0
	for y in range(1, img.get_height() - 1):
		for x in range(1, img.get_width() - 1):
			var l := img.get_pixel(x, y).get_luminance()
			sum += absf(img.get_pixel(x + 1, y).get_luminance() - l)
			sum += absf(img.get_pixel(x, y + 1).get_luminance() - l)
	return sum


func _save(img: Image, path: String) -> void:
	var err := img.save_png(ProjectSettings.globalize_path(path))
	if err != OK:
		push_error("не записался %s (код %d)" % [path, err])
	else:
		print("  %s (%d×%d)" % [path, img.get_width(), img.get_height()])


## Второй шаг конвейера: включить мип-мапы в .import-сайдкарах спрайтов.
func _patch_mips() -> void:
	var dir := DirAccess.open(OUT_DIR)
	if dir == null:
		push_error("нет %s — сначала нарезка без --mips" % OUT_DIR)
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	var patched: int = 0
	while not name.is_empty():
		if name.match("*.import"):
			var path := "%s/%s" % [OUT_DIR, name]
			var cfg := ConfigFile.new()
			if cfg.load(path) == OK and not cfg.get_value("params", "mipmaps/generate", false):
				cfg.set_value("params", "mipmaps/generate", true)
				cfg.save(path)
				patched += 1
		name = dir.get_next()
	print("make_vfx_textures: мип-мапы включены у %d сайдкаров" % patched)
