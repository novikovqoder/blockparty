# Процедурные меши предметов (раздел 6 SPEC, «Предметы из gameplay/world/props/»):
# каждое здание/камень — ArrayMesh из огранённых примитивов (6-гранные
# призмы, конусы) с цветом в вершинах; нормали не пишем — шейдер
# lowpoly.gdshader затеняет по производным на грань. Меши собираются из
# «деталей» (box/цилиндр/пирамида) со сдвигом, поворотом и детерминированным
# джиттером — вариант предмета задаёт вариацию, никаких randi()/randf()
# вне rng с сеедом от (тип, вариант). Все модели стоят «ногами» в начале
# координат (origin у земли): позиция предмета из IslandGen — точка на
# рельефе. Деревья, кусты, трава, цветы, камни, брёвна и колонны руин —
# CC0-модели kenney.nl (перекраска и нормировка — cc0_meshes.gd), здесь
# остались только конструкции: стены, башни, пирс, лодки, постройки
# площади.
#
# Два типа размеров: «метровые» (rock_wall, ruin_block, plank_deck,
# pier_post) — scale равен размерам в метрах, mesh — единичный куб;
# остальные — mesh натурального размера, scale — множитель ~0.85–1.25.
# Коллизии — только типы из IslandGen.SOLID_TYPES, упрощённый бокс
# (collision_size): ствол дерева без кроны, стены и настилы — точно.
class_name PropMeshes
extends RefCounted

const PAL: Palette = preload("res://assets/palette.tres")


## Меш предмета: тип и вариант (варианты отличаются джиттером и деталями).
## Типы окружения с CC0-моделью (шаг 3 П4.5) собирает Cc0Meshes: kenney-меш
## перекрашивается в палитры игры и нормируется под размеры процедурной
## модели — коллизии и scale предметов IslandGen не меняются.
static func mesh(type: StringName, variant: int) -> ArrayMesh:
	var cc0 := Cc0Meshes.mesh(type, variant)
	if cc0 != null:
		return cc0
	match String(type):
		"rock_wall":
			return _rock_wall(variant)
		"ruin_block":
			return _ruin_block(variant)
		"ruin_tower":
			return _ruin_tower()
		"ruin_gate":
			return _ruin_gate()
		"pier_post":
			return _pier_post()
		"plank_deck":
			return _plank_deck()
		"boat":
			return _boat()
		"log_bridge":
			return _log_bridge()
		# Деревья Леса (П5.9, переделка) — сгенерированы самим EZ-Tree
		# (~/eztree_gen → GLB в assets/visual/trees): две поверхности
		# (кора + листва) с запечёнными материалами, уровни детализации —
		# EzTreeMeshes.build_set (IslandArt/IslandView).
		"etree_pine", "etree_oak", "etree_aspen", "etree_bush", "etree_giant":
			return EzTreeMeshes.build_set(type, variant)["mesh"]
		# Валежник (П5.9, переделка): CC0-бревно kenney (локальная
		# библиотека) с корой ambientcg — той же, что у мостика через овраг.
		"dead_log":
			return _dead_log(variant)
		# П5.9, блок 3: растительность Леса — процедурные пучки/вайи/цветы
		# и камни во мху (материалы — ForestMat).
		"rgrass":
			return ForestPlants.grass_clump(variant)
		"fern":
			return ForestPlants.fern(variant)
		"rflower":
			return ForestPlants.flower(variant)
		# Доработка под эталон: ирисы — фиолетовые акценты у валунов Леса.
		"riris":
			return ForestPlants.iris(variant)
		"mrock":
			return RockGen.boulder(variant, 0.22 + 0.05 * (variant % 3), 0.65)
		# П5.9, блок 5: крупные глыбы подлеска — тот же генератор, что
		# камешки mrock, покрупнее и площе; мох по верхним граням красит
		# ForestMat (rock_moss.gdshader), как у mrock.
		"rrock":
			return RockGen.boulder(variant, 0.7 + 0.16 * (variant % 3), 0.62)
	push_error("Неизвестный тип предмета: %s" % type)
	return ArrayMesh.new()


## Валежник Леса (П5.9, переделка): CC0-брёвна kenney.nl (nature-kit,
## log/log_large — настоящие модели из локальной библиотеки) с корой
## ambientcg по UV. Бревно лежит длинной стороной вдоль X, низ — в origin.
## Вариант — какая из двух моделей и лёгкий поворот вокруг оси.
static func _dead_log(variant: int) -> ArrayMesh:
	var file := "log_large.glb" if variant % 2 == 0 else "log.glb"
	var path := "res://assets/third_party/kenney.nl/nature-kit".path_join(file)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		push_error("Не читается бревно kenney: " + path)
		return ArrayMesh.new()
	var scene := doc.generate_scene(state)
	var arrays := _merge_log_surfaces(scene, Vector3(2.4, 0.45, 0.6))
	scene.free()
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _log_bark_material())
	return mesh


## Мостик из настоящих брёвен через лесной овраг (П5.7; переделка П5.9,
## П3): семь круглых брёвен-цилиндров с пятаками лежат впритык поперёк
## русла, по краям — перила из тонких кряжей на наклонных стойках.
## Диаметры, перекосы и высоты — вручную заданные таблицы (брёвна «из
## разных деревьев», мостик собран вручную), без rng. Кора — ambientcg
## Bark001 (CC0, та же, что у деревьев), UV — «метры поверхности»
## (окружность и длина делятся на тайл 1 м), тон брёвен — COLOR.
## Низ моста — в origin, ось моста — X, перила — вдоль X по краям Z.
static func _log_bridge() -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	# Настил: бревно 3.1 м, ряд из семи с шагом 0.37 (диаметры ~0.34 —
	# щели настоящего ряда). drift — волна высот, tilt — перекос концов,
	# tints — тон коры.
	var radii: Array[float] = [0.170, 0.178, 0.165, 0.172, 0.169, 0.175, 0.166]
	var drift: Array[float] = [0.012, -0.006, 0.016, 0.0, -0.012, 0.006, -0.004]
	var tilt: Array[float] = [0.010, -0.008, 0.012, -0.005, 0.009, -0.011, 0.006]
	var tints: Array[float] = [0.94, 1.02, 0.97, 1.04, 0.95, 1.00, 0.98]
	var length: float = 3.1
	for i: int in 7:
		var z: float = (float(i) - 3.0) * 0.37
		var y: float = radii[i] + drift[i]
		_log_limb(verts, normals, uvs, colors, indices,
			Vector3(-length * 0.5, y + tilt[i], z),
			Vector3(length * 0.5, y - tilt[i], z),
			radii[i], tints[i])
	# Перила: с обеих сторон стойка-кряж (чуть наклонена наружу) и
	# поручень-жердь поверх, тоном темнее настила — старое дерево.
	for side: int in [-1, 1]:
		for x_at: float in [-1.05, 1.05]:
			_log_limb(verts, normals, uvs, colors, indices,
				Vector3(x_at, 0.04, side * 1.30),
				Vector3(x_at, 0.88, side * 1.36),
				0.055, 0.88)
		_log_limb(verts, normals, uvs, colors, indices,
			Vector3(-1.5, 0.86, side * 1.35),
			Vector3(1.5, 0.86, side * 1.35),
			0.05, 0.90)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := _log_bark_material()
	# UV мостика уже в метрах поверхности (тайл коры 1 × 1 м — бревно
	# ближе к игроку, чем стволы деревьев, кора читается плотнее).
	material.set_shader_parameter("uv_scale", Vector2.ONE)
	mesh.surface_set_material(0, material)
	return mesh


## Бревно-цилиндр между двумя точками: 10 боковых граней, оба торца
## закрыты «пятаками» светлее боков (спил). UV в метрах: u — длина
## пройденной дуги окружности, v — путь вдоль оси (тайл коры — 1 м,
## шов оборота дублированной вершиной не рвётся). Тон — COLOR (tint),
## нормали боков радиальные, пятаков — вдоль оси. Пишет в переданные
## массивы — мостик собирается одной поверхностью.
static func _log_limb(
		verts: PackedVector3Array, normals: PackedVector3Array,
		uvs: PackedVector2Array, colors: PackedColorArray,
		indices: PackedInt32Array,
		from: Vector3, to: Vector3, radius: float, tint: float) -> void:
	const RADIAL: int = 10
	const TILE_M: float = 1.0
	var axis: Vector3 = (to - from).normalized()
	var length: float = from.distance_to(to)
	var helper := Vector3(0.0, 1.0, 0.0) if absf(axis.y) < 0.9 \
		else Vector3(1.0, 0.0, 0.0)
	var right: Vector3 = axis.cross(helper).normalized()
	var up: Vector3 = axis.cross(right).normalized()
	var circumference: float = TAU * radius
	# Боковая поверхность: два кольца по RADIAL + 1 вершину.
	var side: int = verts.size()
	for ring: int in 2:
		var center: Vector3 = from.lerp(to, float(ring))
		for k: int in RADIAL + 1:
			var angle: float = TAU * float(k) / float(RADIAL)
			var dir: Vector3 = right * cos(angle) + up * sin(angle)
			verts.append(center + dir * radius)
			normals.append(dir)
			uvs.append(Vector2(
				circumference * float(k) / float(RADIAL) / TILE_M,
				length * float(ring) / TILE_M))
			colors.append(Color(tint, tint, tint))
	# Порядок вершин — наружу (нормаль треугольника от оси): с cull_back
	# вывернутая грань невидима снаружи.
	for ring: int in 1:
		for k: int in RADIAL:
			var a: int = side + ring * (RADIAL + 1) + k
			var b: int = a + RADIAL + 1
			indices.append(a)
			indices.append(a + 1)
			indices.append(b)
			indices.append(b)
			indices.append(a + 1)
			indices.append(b + 1)
	# Пятаки: центр + веер по кольцу, нормаль вдоль оси, тон светлее
	# (спил дерева); UV — плоские метры поперёк торца.
	for end: int in 2:
		var cap: int = verts.size()
		var center: Vector3 = to if end == 1 else from
		var facing: Vector3 = axis if end == 1 else -axis
		verts.append(center)
		normals.append(facing)
		uvs.append(Vector2.ZERO)
		colors.append(Color(tint * 1.2, tint * 1.14, tint * 1.06))
		for k: int in RADIAL:
			var angle: float = TAU * float(k) / float(RADIAL)
			var dir: Vector3 = right * cos(angle) + up * sin(angle)
			verts.append(center + dir * radius)
			normals.append(facing)
			uvs.append(Vector2(
				radius * cos(angle) / TILE_M, radius * sin(angle) / TILE_M))
			colors.append(Color(tint * 1.2, tint * 1.14, tint * 1.06))
		# Пятак to — веер по кругу, пятак from — тот же веер зеркально
		# (нормаль торца наружу от бревна).
		for k: int in RADIAL:
			indices.append(cap)
			if end == 1:
				indices.append(cap + 1 + k)
				indices.append(cap + 1 + (k + 1) % RADIAL)
			else:
				indices.append(cap + 1 + (k + 1) % RADIAL)
				indices.append(cap + 1 + k)


## Поверхности сцены GLB в один набор массивов с UV и нормалями (кора
## освещается по нормалям kenney-модели), нормированный на target (длина
## вдоль X × толщина × ширина, м) и опущенный на землю. Если модель длиннее
## по Z — координаты меняются местами (бревно ложится длинной стороной
## вдоль X); нормали при неравномерном масштабе делятся на покомпонентный
## scale (обратная транспонированная диагональной матрицы) и нормируются.
static func _merge_log_surfaces(root: Node, target: Vector3) -> Array:
	var parts: Array = []
	_collect_log_surfaces(root, Transform3D.IDENTITY, parts)
	var min_v := Vector3(INF, INF, INF)
	var max_v := Vector3(-INF, -INF, -INF)
	for arrays: Array in parts:
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for v: Vector3 in verts:
			min_v = min_v.min(v)
			max_v = max_v.max(v)
	var size := max_v - min_v
	var swap_xz: bool = size.z > size.x
	var length: float = maxf(size.x, size.z)
	var scale := Vector3(
		target.x / maxf(length, 0.001),
		target.y / maxf(size.y, 0.001),
		target.z / maxf(minf(size.x, size.z), 0.001))
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for arrays: Array in parts:
		var part_verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var part_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var part_uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var base: int = verts.size()
		for v: int in part_verts.size():
			var local := Vector3(
				part_verts[v].x - min_v.x,
				part_verts[v].y - min_v.y,
				part_verts[v].z - min_v.z)
			var normal: Vector3 = part_normals[v] if v < part_normals.size() \
				else Vector3.UP
			if swap_xz:
				local = Vector3(local.z, local.y, local.x)
				normal = Vector3(normal.z, normal.y, normal.x)
			verts.append(local * scale)
			normals.append(
				Vector3(normal.x / scale.x, normal.y / scale.y, normal.z / scale.z).normalized())
			uvs.append(part_uvs[v])
		var part_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for index: int in part_indices:
			indices.append(base + index)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


static func _collect_log_surfaces(node: Node, parent_xf: Transform3D, parts: Array) -> void:
	var xf: Transform3D = parent_xf * node.transform if node is Node3D else parent_xf
	if node is MeshInstance3D:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh != null:
			for surface: int in mesh.get_surface_count():
				var arrays: Array = mesh.surface_get_arrays(surface)
				if arrays.is_empty() \
						or mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
					continue
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				if verts.is_empty() or not (arrays[Mesh.ARRAY_TEX_UV] is PackedVector2Array):
					continue
				for v: int in verts.size():
					verts[v] = xf * verts[v]
					if v < normals.size():
						normals[v] = (xf.basis * normals[v]).normalized()
				parts.append(arrays)
	for child: Node in node.get_children():
		_collect_log_surfaces(child, xf, parts)


## Кора брёвен: та же текстура ambientcg, что у деревьев ez-tree
## (Bark001, CC0), чуть плотнее тайлинг; свет — как у коры деревьев.
static func _log_bark_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = preload("res://assets/shaders/tree_bark.gdshader")
	material.set_shader_parameter("bark_tex", preload(
		"res://assets/third_party/ambientcg.com/Bark001/Bark001_2K-JPG_Color.jpg"))
	material.set_shader_parameter("uv_scale", Vector2(2.0, 1.0))
	return material


## Радиус видимости MultiMesh предмета, м (0 — без ограничения;
# SPEC 16: трава исчезает дальше 40 м).
static func visibility_range(type: StringName) -> float:
	match String(type):
		"grass_tuft":
			return 40.0
		"reed":
			return 40.0
		"flower":
			return 60.0
		"pebble":
			return 80.0
		"bush":
			return 70.0
		"fern":
			return 50.0
		# Реалистичные сканы Леса (П5.7, блок 2): кусты и кочки — как их
		# кенниевские аналоги, деревья видны всегда (силуэт леса издалека).
		# П5.9, блок 4: деревья Леса (etree_*) видны всегда — дальний план
		# держат уровни детализации IslandView._build_tree_lods.
		# П5.9, блок 3: спад густоты травы делает шейдер (травинки
		# «садятся» в землю с 40 м), MultiMesh гасится чуть дальше.
		"rgrass":
			return 60.0
		"rflower":
			return 56.0
		"riris":
			return 56.0
		"mrock":
			return 60.0
	return 0.0


## Параметры ветра для качающихся типов (vfx-fix, блок б): амплитуда, м;
## частота; высота начала качания и размах нарастания, м; направление.
## Пустой словарь — тип не качается (камни, постройки). Трава мелко и часто,
## кусты медленнее, камыши выше, ветви деревьев — широко и размашисто,
## ствол (ниже base) стоит на месте.
static func wind_params(type: StringName) -> Dictionary:
	match String(type):
		"grass_tuft":
			return {
				"wind_amplitude": 0.05, "wind_freq": 1.9,
				"wind_weight_base": 0.02, "wind_weight_span": 0.35,
				"wind_direction": Vector2(0.85, 0.45),
			}
		"flower":
			return {
				"wind_amplitude": 0.04, "wind_freq": 2.2,
				"wind_weight_base": 0.05, "wind_weight_span": 0.25,
				"wind_direction": Vector2(0.85, 0.45),
			}
		"reed":
			return {
				"wind_amplitude": 0.08, "wind_freq": 1.4,
				"wind_weight_base": 0.1, "wind_weight_span": 0.8,
				"wind_direction": Vector2(0.8, 0.5),
			}
		"bush":
			return {
				"wind_amplitude": 0.06, "wind_freq": 1.1,
				"wind_weight_base": 0.15, "wind_weight_span": 0.9,
				"wind_direction": Vector2(0.9, 0.4),
			}
		# П5.9, блок 3: ветер rgrass/fern/rflower — в шейдере grass_field
		# (ForestMat), не общий wind.gdshader.
		"tree_leafy", "tree_spruce":
			return {
				"wind_amplitude": 0.22, "wind_freq": 0.55,
				"wind_weight_base": 1.6, "wind_weight_span": 3.5,
				"wind_direction": Vector2(0.85, 0.45),
			}
		# П5.9, переделка: деревья Леса — ветер листвы в canopy.gdshader
		# (формула ez-tree), ветви и валежник неподвижны (как в демо);
		# трава и цветы — в grass_field (ForestMat).
		"etree_pine", "etree_oak", "etree_aspen", "etree_bush", \
		"etree_giant", "dead_log", "rgrass", "rflower", "riris", "mrock", "rrock":
			return {}
	return {}


## Размер бокса коллизии предмета (Vector3.ZERO — предмет проходим).
## Для «метровых» типов это сам scale; для остальных — доля натурального
## размера, умноженная на масштаб предмета.
static func collision_size(type: StringName, scale: Vector3) -> Vector3:
	match String(type):
		"rock_wall", "ruin_block", "plank_deck", "pier_post":
			return Vector3(maxf(scale.x, 0.05), maxf(scale.y, 0.05), maxf(scale.z, 0.05))
		"tree_leafy", "tree_spruce":
			return Vector3(0.7 * scale.x, 2.8 * scale.y, 0.7 * scale.x)
		# Деревья Леса (П5.9, блок 4): стволы EZ-Tree тоньше сканов — коробка
		# уже; коллизия до высоты кроны не нужна (игрок ниже ветвей).
		"etree_pine", "etree_oak", "etree_aspen":
			return Vector3(0.55 * scale.x, 2.6 * scale.y, 0.55 * scale.x)
		"boulder":
			return Vector3(1.1 * scale.x, 0.6 * scale.y, 1.1 * scale.x)
		"rock_pillar":
			return Vector3(1.15 * scale.x, 1.6 * scale.y, 1.15 * scale.x)
		"ruin_tower":
			return Vector3(1.9, 3.4, 1.9) * scale.x
		"ruin_gate":
			return Vector3.ZERO  # рама проходима; проём закрывает узел RuinGate (П5)
		"ruin_arch":
			return Vector3(2.1, 2.4, 0.6)
		"ruin_column":
			return Vector3(0.95, 1.4, 0.95) * scale.x
		"bench":
			return Vector3(1.9, 0.55, 0.7)
		"boat":
			return Vector3(1.3, 0.5, 2.35)
		# Гигант (П5.9, блок 4): дуб-исполин — толстый ствол без кроны;
		# валежник — лежачий ствол (длина по X до поворота yaw); мостик —
		# ряд семи брёвен (_log_bridge), толщина настила с перилами.
		"etree_giant":
			return Vector3(1.9, 9.0, 1.9) * scale.x
		"dead_log":
			return Vector3(2.4, 0.45, 0.6) * Vector3(scale.x, scale.y, scale.x)
		"log_bridge":
			return Vector3(3.1, 0.45, 4.8)
		"rrock":
			return Vector3(0.85 * scale.x, 0.5 * scale.y, 0.85 * scale.x)
	return Vector3.ZERO


# --- Деревья и растительность: CC0-модели kenney.nl (Cc0Meshes) ---


# --- Камень: стены и руины ---

## Скальная стена («метровый» тип: scale = длина × высота × глубина,
## единичный меш). Верхний ряд валунов ломает ровную кромку.
static func _rock_wall(variant: int) -> ArrayMesh:
	var rng := _rng("rock_wall", variant)
	var parts: Array = [
		_box(Vector3(0.99, 1.0, 0.99), PAL.stone, Vector3(0, 0.5, 0)),
	]
	# Валунчики на кромке: в относительных единицах (0..1 по длине).
	for i: int in 2 + variant % 2:
		var x: float = 0.25 + 0.5 * float(i) / float(1 + variant % 2) \
			+ rng.randf_range(-0.08, 0.08)
		parts.append(_box(
			Vector3(0.28, 0.1 + 0.04 * variant, 0.8),
			PAL.stone.lerp(Color.WHITE, 0.06),
			Vector3(x - 0.5, 1.02, 0), rng.randf_range(-0.1, 0.1)))
	return _merge(parts)


## Блок стены руин («метровый» тип): кладка со сколотой кромкой.
static func _ruin_block(variant: int) -> ArrayMesh:
	var rng := _rng("ruin_block", variant)
	var brick: Color = PAL.ruin_brick
	var parts: Array = [
		_box(Vector3(0.96, 1.0, 0.96), brick, Vector3(0, 0.5, 0)),
		_box(Vector3(0.6, 0.09, 0.55), brick.lerp(Color.WHITE, 0.1),
			Vector3(rng.randf_range(-0.15, 0.15), 0.99,
				rng.randf_range(-0.15, 0.15)), rng.randf_range(-0.2, 0.2)),
	]
	if variant == 2:
		parts.append(_box(Vector3(0.4, 0.5, 0.1), PAL.ruin_dark,
			Vector3(0, 0.25, 0.48)))
	return _merge(parts)


## Башня руин у ворот: гранёное основание, тело, венец с зубцами и проём.
static func _ruin_tower() -> ArrayMesh:
	var brick: Color = PAL.ruin_brick
	var parts: Array = [
		_box(Vector3(1.9, 0.7, 1.9), brick.darkened(0.08), Vector3(0, 0.35, 0)),
		_cyl(0.78, 0.85, 2.0, 6, brick, Vector3(0, 1.7, 0)),
		_cyl(0.98, 0.98, 0.35, 6, brick.lerp(Color.WHITE, 0.1), Vector3(0, 2.85, 0)),
		_box(Vector3(0.6, 1.0, 0.12), PAL.ruin_dark, Vector3(0, 0.5, 0.82)),
	]
	for i: int in 4:
		var angle: float = TAU * float(i) / 4.0 + PI / 4.0
		var off := Vector3(cos(angle), 0.0, sin(angle)) * 0.8
		parts.append(_box(Vector3(0.3, 0.3, 0.24), brick,
			Vector3(off.x, 3.15, off.z), angle))
	return _merge(parts)


## Ворота руин: каменная рама. Проём закрывает отдельный узел RuinGate
## (П5, раздел 9.2) — плита-решётка опускается в пол при открытии.
static func _ruin_gate() -> ArrayMesh:
	var parts: Array = [
		_box(Vector3(0.35, 3.2, 0.45), PAL.ruin_brick, Vector3(-1.05, 1.6, 0)),
		_box(Vector3(0.35, 3.2, 0.45), PAL.ruin_brick, Vector3(1.05, 1.6, 0)),
		_box(Vector3(2.6, 0.5, 0.45), PAL.ruin_brick.lerp(Color.WHITE, 0.08),
			Vector3(0, 3.3, 0)),
	]
	return _merge(parts)


## Обломок колонны: CC0-модель wall-pillar (kenney castle-kit) — см. Cc0Meshes.


# --- Площадь и постройки --


## Свая пирса/опора моста («метровый» тип): гранёный столб единичной
## высоты со шляпкой.
static func _pier_post() -> ArrayMesh:
	var wood: Color = PAL.planks.darkened(0.15)
	return _merge([
		_cyl(0.46, 0.48, 1.0, 6, wood, Vector3(0, 0.5, 0)),
		_cyl(0.52, 0.52, 0.07, 6, PAL.planks, Vector3(0, 0.965, 0)),
	])


## Настил из досок («метровый» тип: scale = ширина × толщина × длина):
## пять прогонов с щелями, единичный меш.
static func _plank_deck() -> ArrayMesh:
	var parts: Array = []
	for i: int in 5:
		var shade: Color = PAL.planks.lerp(Color.WHITE, 0.06 * ((i * 7) % 3) - 0.03)
		parts.append(_box(Vector3(0.96, 1.0, 0.17), shade,
			Vector3(0, 0.5, i * 0.2 - 0.4)))
	return _merge(parts)


## Лодочка-плот: корпус с носом-клином и скамьёй (модель по +Z).
static func _boat() -> ArrayMesh:
	var hull: Color = PAL.trunk.lerp(PAL.planks, 0.4)
	var parts: Array = [
		_box(Vector3(1.15, 0.35, 1.9), hull, Vector3(0, 0.2, -0.15)),
		_prism(Vector3(1.15, 0.35, 0.7), hull, Vector3(0, 0.2, 1.15)),
		_box(Vector3(1.25, 0.07, 0.09), PAL.planks, Vector3(0, 0.4, -0.9)),
		_box(Vector3(1.25, 0.07, 0.09), PAL.planks, Vector3(0, 0.4, 0.55)),
		_box(Vector3(1.05, 0.06, 0.22), PAL.planks.lerp(Color.WHITE, 0.08),
			Vector3(0, 0.42, -0.2)),
	]
	return _merge(parts)


# --- Детали примитивов ---

## Куб заданного размера; pos — центр.
static func _box(
	size: Vector3, color: Color, pos: Vector3, yaw: float = 0.0
) -> Array:
	var prim := BoxMesh.new()
	prim.size = size
	return _prim(prim, color, pos, yaw)


## Призма-клин (наклонная грань к +Z); pos — центр.
static func _prism(
	size: Vector3, color: Color, pos: Vector3, yaw: float = 0.0
) -> Array:
	var prim := PrismMesh.new()
	prim.size = size
	return _prim(prim, color, pos, yaw)


## Гранёный цилиндр/конус (r_top ≈ 0 — конус); pos — центр по высоте.
static func _cyl(
	r_top: float, r_bottom: float, height: float, segments: int, color: Color,
	pos: Vector3, yaw: float = 0.0,
) -> Array:
	var prim := CylinderMesh.new()
	prim.top_radius = r_top
	prim.bottom_radius = r_bottom
	prim.height = height
	prim.radial_segments = segments
	return _prim(prim, color, pos, yaw)


## ГПСЧ детали: сеед от (тип, вариант) — меши не зависят от порядка вызовов.
static func _rng(type: String, variant: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([type, variant])
	return rng


## Массивы поверхности примитива: только вершины с цветом и индексы
## (нормали и UV шейдеру low-poly не нужны), сдвиг/поворот/джиттер
## применяются к вершинам сразу.
static func _prim(
	prim: PrimitiveMesh, color: Color, pos: Vector3, yaw: float,
	rng: RandomNumberGenerator = null, jitter_amount: float = 0.0,
	squash: Vector3 = Vector3.ONE,
) -> Array:
	var arrays: Array = prim.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors := PackedColorArray()
	colors.resize(verts.size())
	colors.fill(color)
	if jitter_amount > 0.0 and rng != null:
		for i: int in verts.size():
			verts[i] += Vector3(
				rng.randf_range(-jitter_amount, jitter_amount),
				rng.randf_range(-jitter_amount, jitter_amount) * 0.5,
				rng.randf_range(-jitter_amount, jitter_amount),
			)
	var basis := Basis(Vector3.UP, yaw)
	for i: int in verts.size():
		verts[i] = (basis * (verts[i] * squash)) + pos
	arrays[Mesh.ARRAY_COLOR] = colors
	for channel: int in [
		Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2,
	]:
		arrays[channel] = null
	return arrays


## Склеить детали в один ArrayMesh (одна поверхность, сдвиг индексов).
static func _merge(parts: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for arrays: Array in parts:
		var base: int = verts.size()
		verts.append_array(arrays[Mesh.ARRAY_VERTEX])
		colors.append_array(arrays[Mesh.ARRAY_COLOR])
		for index: int in arrays[Mesh.ARRAY_INDEX]:
			indices.append(base + index)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
