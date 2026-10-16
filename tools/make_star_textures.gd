# Генератор текстур ночного неба (П5.9 блок 6): небо Sky3D рисует звёзды
# двумя текстурами — фон-«млечный путь» (starmap) и россыпь точек-звёзд
# (starfield). Штатные текстуры аддона — панорама ESO под CC BY 4.0, в
# проект их брать нельзя (план: только CC0/MIT); эти — процедурные, наши,
# детерминированные (RandomNumberGenerator с фикс. seed). Запуск:
#   godot --headless --path . -s tools/make_star_textures.gd
extends SceneTree

const SIZE := Vector2i(2048, 1024)
const SEED := 20261016

var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	_rng.seed = SEED
	_make_starmap("res://assets/visual/sky_starmap.png")
	_rng.seed = SEED + 1
	_make_starfield("res://assets/visual/sky_starfield.png")
	quit(0)


## value-шум на решётке с периодом period_u по X (текстура бесшовна по u).
func _vnoise(x: float, y: float, period_u: int, seed_off: int) -> float:
	var ix := floori(x)
	var iy := floori(y)
	var fx := x - float(ix)
	var fy := y - float(iy)
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var a := _hash(ix % period_u, iy, seed_off)
	var b := _hash((ix + 1) % period_u, iy, seed_off)
	var c := _hash(ix % period_u, iy + 1, seed_off)
	var d := _hash((ix + 1) % period_u, iy + 1, seed_off)
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)


func _hash(x: int, y: int, seed_off: int) -> float:
	var h := (x * 374761393 + y * 668265263 + seed_off * 2246822519) % 1000003
	h = (h * h * h + 27) % 1000003
	return float(h) / 1000003.0


func _fbm(u: float, v: float, seed_off: int) -> float:
	var sum: float = 0.0
	var amp: float = 0.5
	var scale: float = 6.0
	for i: int in 4:
		sum += _vnoise(u * scale, v * scale * 0.5, int(scale), seed_off + i * 17) * amp
		scale *= 2.0
		amp *= 0.5
	return sum


## Фон: мягкая полоса «млечного пути» (наклонённый большой круг) с туманной
## фактурой и лёгкими цветовыми вариациями. Точка текстуры (u, v) — направление
## на сфере; полоса — гауссово сечение вокруг плоскости с нормалью n.
func _make_starmap(path: String) -> void:
	var image := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGB8)
	var n := (Vector3(0.35, 0.72, -0.6).normalized())
	for y: int in SIZE.y:
		var v := float(y) / float(SIZE.y)
		var lat := (0.5 - v) * PI  # v=0 — северный полюс (как в шейдере)
		for x: int in SIZE.x:
			var u := float(x) / float(SIZE.x)
			var lon := u * TAU - PI
			var p := Vector3(
				cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))
			var d := p.dot(n)
			var band := exp(-d * d / (2.0 * 0.13 * 0.13))
			# Фактура полосы: fbm по направлению; полоса плотнее к «ядру».
			var neb := _fbm(u, v, 101)
			var clump := 0.45 + 0.55 * _fbm(u * 2.0 + 3.7, v * 2.0, 55)
			var glow := band * clump * (0.25 + 0.75 * neb)
			# Цвет: холодный фон, тёплые прожилки в ядре полосы.
			var col := Color(0.55, 0.62, 0.78).lerp(
				Color(0.85, 0.78, 0.66), band * 0.35)
			col *= glow * 0.16
			image.set_pixel(x, y, Color(
				clampf(col.r, 0.0, 1.0),
				clampf(col.g, 0.0, 1.0),
				clampf(col.b, 0.0, 1.0)))
	image.save_png(path)
	print("starmap: " + path)


## Россыпь звёзд: ~4000 точек с гауссовым ядром, яркость по степенному
## закону (ярких мало), тон у половины звёзд холодный/тёплый. Полюсные
## искажения не правятся: у шейдера звёзды мелкие, растяжение у полюса
## незаметно.
func _make_starfield(path: String) -> void:
	var image := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGB8)
	image.fill(Color.BLACK)
	var count := 4200
	for i: int in count:
		var u := _rng.randf()
		var v := _rng.randf()
		# Яркость: степенное распределение (много тусклых, мало ярких).
		var mag := pow(_rng.randf(), 3.0)
		var bright := 0.25 + 0.75 * mag
		var radius: float = 0.7 + mag * 1.8
		var tint := _rng.randf()
		var col := Color.WHITE
		if tint < 0.3:
			col = Color(0.72, 0.8, 1.0)
		elif tint > 0.8:
			col = Color(1.0, 0.85, 0.7)
		col *= bright
		var cx := u * SIZE.x
		var cy := v * SIZE.y
		var r := ceili(radius * 3.0)
		for py: int in range(ceili(cy) - r, ceili(cy) + r + 1):
			for px: int in range(int(cx) - r, int(cx) + r + 1):
				var dx := float(px) - cx
				var dy := float(py) - cy
				var dist2 := (dx * dx + dy * dy) / (radius * radius)
				var amp := exp(-dist2 * 0.5) * bright
				if amp < 0.004:
					continue
				var wx := (px + SIZE.x) % SIZE.x  # бесшовно по u
				if py < 0 or py >= SIZE.y:
					continue
				var old := image.get_pixel(wx, py)
				image.set_pixel(wx, py, Color(
					minf(old.r + col.r * amp, 1.0),
					minf(old.g + col.g * amp, 1.0),
					minf(old.b + col.b * amp, 1.0)))
	image.save_png(path)
	print("starfield: " + path)
