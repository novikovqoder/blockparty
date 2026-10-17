# Процедурная растительность Леса (П5.9, блок 3): пучки травы, папоротники
# и цветы — ArrayMesh с нормалями строго вверх (трава затеняется как земля,
# шейдер grass_field.gdshader), высотой травинки в UV.y (градиент
# основание → кончик) и цветом в вершинах. Вариант задаёт вариацию,
# ГПСЧ сеется от (тип, вариант) — детерминизм без randi()/randf() вне rng.
# Каждая травинка — сужающаяся полоса из сегментов с наклоном от центра
# пучка: пучок читается объёмом, а не «щёточкой». Цветы — стебель плюс
# крест из двух квадов-лепестков; цвет варианта — из visual_palette.tres
# (жёлтый/фиолетовый/белый).
class_name ForestPlants
extends RefCounted

const VPAL: VisualPalette = preload("res://assets/visual_palette.tres")

## Цвета лепестков по вариантам (жёлтый, фиолетовый, белый).
static var _flower_colors: PackedColorArray


static func _rng(type: String, variant: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([type, variant])
	return rng


## Пучок травы: 10–14 травинок высотой 0.22–0.42 м в круге ~0.3 м.
static func grass_clump(variant: int) -> ArrayMesh:
	var rng := _rng("rgrass", variant)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var blades: int = 10 + variant % 3
	for b: int in blades:
		var angle: float = TAU * float(b) / float(blades) + rng.randf_range(-0.3, 0.3)
		var dist: float = rng.randf_range(0.02, 0.14)
		var start := Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		var height: float = rng.randf_range(0.22, 0.42)
		# Наклон травинки — от центра пучка наружу плюс собственный вихр.
		var lean := Vector3(cos(angle), 0.0, sin(angle)) \
			* rng.randf_range(0.1, 0.35) \
			+ Vector3(rng.randf_range(-0.08, 0.08), 0.0, rng.randf_range(-0.08, 0.08))
		var side := Vector3(-sin(angle), 0.0, cos(angle))
		_strip(verts, normals, colors, uvs, indices, start, lean, side,
			height, 0.020, 0.004, 3, Color.WHITE, Color.WHITE)
	return _mesh(verts, normals, colors, uvs, indices)


## Папоротник: 6–9 дугообразных вай высотой 0.35–0.6 м, тёмное основание.
static func fern(variant: int) -> ArrayMesh:
	var rng := _rng("fern", variant)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var fronds: int = 6 + variant % 3
	var dark: Color = VPAL.grass_base.lerp(Color.BLACK, 0.25)
	var light: Color = VPAL.grass_tip.lerp(VPAL.grass_base, 0.45)
	for f: int in fronds:
		var angle: float = TAU * float(f) / float(fronds) + rng.randf_range(-0.2, 0.2)
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		var length: float = rng.randf_range(0.45, 0.7)
		var height: float = rng.randf_range(0.3, 0.5)
		# Вайя: сначала тянется вверх, потом опадает наружу (арка).
		var lean := dir * (length / maxf(height, 0.1)) * 0.8
		var side := Vector3(-sin(angle), 0.0, cos(angle))
		_strip(verts, normals, colors, uvs, indices, Vector3.ZERO, lean, side,
			height, 0.008, 0.004, 4, dark, light, 0.6)
	return _mesh(verts, normals, colors, uvs, indices)


## Ирис (доработка под эталон): розетка мечевидных листьев и 1–2 цветочных
## стебля 0.40–0.55 м с фиолетовыми «парусами» — три вертикальных лепестка
## вокруг оси стебля (наклон наружу) и жёлтый язычок-«борода» в центре.
## Лепестки — те же полосы _strip (нормали вверх, UV.y — высота): ветер
## качает их вместе со всей поляной.
static func iris(variant: int) -> ArrayMesh:
	var rng := _rng("risis", variant)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var leaf_dark: Color = VPAL.grass_base.lerp(Color.BLACK, 0.15)
	var leaf_light: Color = VPAL.grass_tip.lerp(VPAL.grass_base, 0.35)
	# Розетка листьев: 5–6 жёстких мечей наружу, заметно выше травы вокруг
	# (доработка 2: ирис должен читаться с тропы, а не теряться в кочках).
	var leaves: int = 5 + variant % 2
	for l: int in leaves:
		var angle: float = TAU * float(l) / float(leaves) + rng.randf_range(-0.2, 0.2)
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		_strip(verts, normals, colors, uvs, indices,
			Vector3(dir.x * 0.02, 0.0, dir.z * 0.02),
			dir * rng.randf_range(0.36, 0.52), Vector3(-dir.z, 0.0, dir.x),
			rng.randf_range(0.42, 0.6), 0.018, 0.008, 3, leaf_dark, leaf_light)
	# Цветочные стебли с парусами.
	var stems: int = 1 + variant % 2
	for s: int in stems:
		var angle: float = TAU * float(s) / float(stems) + rng.randf_range(-0.5, 0.5)
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		var height: float = rng.randf_range(0.5, 0.68)
		_strip(verts, normals, colors, uvs, indices,
			Vector3(dir.x * 0.03, 0.0, dir.z * 0.03),
			dir * 0.08, Vector3(-dir.z, 0.0, dir.x),
			height, 0.008, 0.005, 3, leaf_dark, leaf_light)
		var top := Vector3(dir.x * 0.03, height - 0.05, dir.z * 0.03)
		# Три паруса вокруг стебля; нижний — темнее и чуть шире (как нижний
		# лепесток ириса), два верхних — светлее к кончикам.
		var petal_dark: Color = VPAL.flower_purple.lerp(Color.BLACK, 0.25)
		var petal_light: Color = VPAL.flower_purple.lerp(Color.WHITE, 0.18)
		for p: int in 3:
			var yaw: float = TAU * float(p) / 3.0 + rng.randf_range(-0.2, 0.2)
			var out_dir := Vector3(cos(angle + yaw), 0.0, sin(angle + yaw))
			var is_lip: bool = p == 0
			_strip(verts, normals, colors, uvs, indices, top,
				out_dir * (0.06 if is_lip else 0.13),
				Vector3(-out_dir.z, 0.0, out_dir.x),
				rng.randf_range(0.13, 0.17) if not is_lip else 0.09,
				0.06 if is_lip else 0.048, 0.014,
				2, petal_dark, petal_light if not is_lip else petal_dark)
		# Жёлтая «борода» в центре цветка.
		_strip(verts, normals, colors, uvs, indices,
			top + Vector3(0.0, 0.01, 0.0), dir * 0.02,
			Vector3(-dir.z, 0.0, dir.x), 0.045, 0.012, 0.006, 1,
			VPAL.flower_yellow, VPAL.flower_yellow)
	return _mesh(verts, normals, colors, uvs, indices)


## Камыш (П5.13, блок 1): 7–10 стеблей 0.6–1.0 м от общего корня, над
## верхушкой — короткий коричневый початок-«карандаш» (чуть шире стебля).
## Нормали вверх и UV.y-высота, как у травы: качается вместе с поляной
## (grass_field.gdshader), у кромки воды читается плотной полосой.
## Коричневый початка — локальная константа: в VisualPalette тёплого
## коричневого нет, палитра — про траву и камни.
static func reed(variant: int) -> ArrayMesh:
	var rng := _rng("reed", variant)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var stems: int = 7 + variant % 3
	var stem_dark: Color = VPAL.grass_base.lerp(Color.BLACK, 0.22)
	var stem_light: Color = VPAL.grass_base.lerp(VPAL.grass_tip, 0.3)
	var cob: Color = Color(0.36, 0.23, 0.10)
	for s: int in stems:
		var angle: float = TAU * float(s) / float(stems) + rng.randf_range(-0.3, 0.3)
		var dist: float = rng.randf_range(0.02, 0.16)
		var start := Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		var height: float = rng.randf_range(0.6, 1.0)
		var lean := Vector3(cos(angle), 0.0, sin(angle)) \
			* rng.randf_range(0.14, 0.34) \
			+ Vector3(rng.randf_range(-0.06, 0.06), 0.0, rng.randf_range(-0.06, 0.06))
		var side := Vector3(-sin(angle), 0.0, cos(angle))
		_strip(verts, normals, colors, uvs, indices, start, lean, side,
			height, 0.011, 0.006, 3, stem_dark, stem_light)
		# Початок начинается чуть ниже верхушки стебля — сплошной стебель.
		var top := start + lean + Vector3.UP * (height - 0.05)
		_strip(verts, normals, colors, uvs, indices, top, lean * 0.25, side,
			0.2, 0.017, 0.012, 1, cob, cob.lerp(Color.WHITE, 0.12))
	return _mesh(verts, normals, colors, uvs, indices)


## Цветок: стебель 0.15–0.28 м и крест из двух квадов-лепестков.
static func flower(variant: int) -> ArrayMesh:
	var rng := _rng("rflower", variant)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var petal: Color = _petal_color(variant)
	var stem: Color = VPAL.grass_base.lerp(Color.BLACK, 0.1)
	var height: float = rng.randf_range(0.15, 0.28)
	_strip(verts, normals, colors, uvs, indices, Vector3.ZERO,
		Vector3(rng.randf_range(-0.05, 0.05), 0.0, rng.randf_range(-0.05, 0.05)),
		Vector3(1.0, 0.0, 0.0), height, 0.007, 0.003, 2, stem, stem)
	# Крест лепестков: два квада 0.07 м на верхушке.
	var size: float = 0.035
	for angle: float in [rng.randf_range(0.0, PI), PI / 2.0 + rng.randf_range(0.0, PI)]:
		var side := Vector3(cos(angle), 0.0, sin(angle))
		_quad(verts, normals, colors, uvs, indices,
			Vector3(0.0, height, 0.0), side, size, petal)
	return _mesh(verts, normals, colors, uvs, indices)


static func _petal_color(variant: int) -> Color:
	match variant % 3:
		0:
			return VPAL.flower_yellow
		1:
			return VPAL.flower_purple
		_:
			return VPAL.flower_white


## Полоса-травинка из segments сегментов: сужается к кончику, изгибается
## наружу lean (квадратично), цвет — от base_color у земли к tip_color.
## UV.y — отношение высоты (градиент в шейдере).
static func _strip(
		verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray, uvs: PackedVector2Array,
		indices: PackedInt32Array,
		start: Vector3, lean: Vector3, side: Vector3, height: float,
		width_base: float, width_tip: float, segments: int,
		base_color: Color, tip_color: Color, width_mid_bulge: float = 0.0,
) -> void:
	var base: int = verts.size()
	for s: int in segments + 1:
		var t: float = float(s) / float(segments)
		var center := start + lean * (t * t) + Vector3.UP * (height * t)
		var bulge: float = 1.0 + width_mid_bulge * 4.0 * t * (1.0 - t)
		var width: float = lerpf(width_base, width_tip, t) * bulge
		var color: Color = base_color.lerp(tip_color, t)
		for half: float in [-0.5, 0.5]:
			verts.append(center + side * (width * half))
			normals.append(Vector3.UP)
			colors.append(color)
			uvs.append(Vector2(0.5 + half, t))
	for s: int in segments:
		var i0: int = base + s * 2
		indices.append_array([i0, i0 + 1, i0 + 2, i0 + 1, i0 + 3, i0 + 2])


## Квад-лепесток горизонтальный (нормаль вверх), центр в center.
static func _quad(
		verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray, uvs: PackedVector2Array,
		indices: PackedInt32Array,
		center: Vector3, side: Vector3, size: float, color: Color,
) -> void:
	var base: int = verts.size()
	var forward := Vector3(side.z, 0.0, -side.x)
	for corner: Vector2 in [
		Vector2(-1.0, -1.0), Vector2(1.0, -1.0), Vector2(1.0, 1.0), Vector2(-1.0, 1.0),
	]:
		verts.append(center
			+ side * (size * corner.x) + forward * (size * corner.y))
		normals.append(Vector3.UP)
		colors.append(color)
		uvs.append(Vector2(0.5 + 0.5 * corner.x, 0.5 + 0.5 * corner.y))
	indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])


static func _mesh(
		verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray, uvs: PackedVector2Array,
		indices: PackedInt32Array,
) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
