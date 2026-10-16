# Процедурные деревья Леса (П5.9, блок 4) — порт генератора EZ-Tree
# (MIT, © Dan Greenheck, github.com/dgreenheck/ez-tree) на GDScript.
# Алгоритм скелета и меширования перенесён близко к оригиналу
# (src/lib/tree.js, rng.js): очередь ветвей, секции с эйлеровой
# ориентацией (гнарлайность/твист/сила роста), дочерние ветки
# стратифицированно по длине и радиальному углу с перестановкой слотов.
# ГПСЧ — порт marsaglia-генератора оригинала: деревья воспроизводимы по
# seed, randi()/randf() не используется (правила CLAUDE.md).
# Один скелет мешируется трижды (LOD0/1/2 — прореживание секций и
# листьев) плюс плоская «картинка» дальнего плана (силуэт по профилю
# кроны); меширование RNG не потребляет — уровни детализации совпадают
# по форме. Кора — CC0-текстуры ambientcg.com из third_party, крона —
# шейдер canopy.gdshader (мягкий объём, просвет солнца сквозь листву,
# ветер волнами); глубина кроны запечена в вершинные цвета.
class_name TreeGen
extends RefCounted

const VPAL: VisualPalette = preload("res://assets/visual_palette.tres")
const CANOPY_SHADER: Shader = preload("res://assets/shaders/canopy.gdshader")
const BILLBOARD_SHADER: Shader = \
	preload("res://assets/shaders/tree_billboard.gdshader")

## Файлы коры ambientcg (CC0). У Bark001 сет «1K» — 512×1024, ниже планки
## качества П5.9 (короткая сторона ≥1024), поэтому взят 2K-сет (1024×2048);
## uv_divider компенсирует плотность UV, чтобы тексель на метр не менялся
## (2K-текстура вдвое выше — масштаб UV вдвое меньше).
const BARK_FILES: Dictionary = {
	&"Bark001": {"suffix": "_2K-JPG_Color.jpg", "uv_divider": 4.0},
	&"Bark002": {"suffix": "_1K-JPG_Color.jpg", "uv_divider": 2.0},
	&"Bark003": {"suffix": "_1K-JPG_Color.jpg", "uv_divider": 2.0},
}

## Пресеты в юнитах EZ-Tree (оригинальные pine_large/oak_medium/aspen_small/
## bush_1 с подрезкой под бюджет игры), target_height — нормировка в метры.
## texture_scale: x — число оборотов текстуры по окружности, y — плотность
## по вертикали (тайл на каждые 2/y кольца секций).
const PRESETS: Dictionary = {
	&"etree_pine": {
		"type": "evergreen", "target_height": 11.0,
		"bark": {"texture": "Bark003", "texture_scale": Vector2(6.0, 4.0)},
		"branch": {
			"levels": 1,
			"angle": {1: 129.13, 2: 16.0, 3: 60.0},
			"children": {0: 64, 1: 3, 2: 0},
			"force": {"direction": Vector3(0, 1, 0), "strength": 0.009},
			"gnarliness": {0: 0.05, 1: 0.08, 2: 0.0, 3: 0.0},
			"length": {0: 65.25, 1: 34.85, 2: 27.25, 3: 1.0},
			"radius": {0: 1.27, 1: 0.37, 2: 0.7, 3: 0.7},
			"sections": {0: 12, 1: 10, 2: 8, 3: 6},
			"segments": {0: 8, 1: 6, 2: 4, 3: 3},
			"start": {1: 0.29, 2: 0.14, 3: 0.3},
			"taper": {0: 0.7, 1: 0.7, 2: 0.7, 3: 0.7},
			"twist": {0: 0.0, 1: 0.0, 2: 0.0, 3: 0.0},
		},
		"leaves": {
			"count": 14, "start": 0.076, "angle": 17.0, "size": 3.4,
			"size_variance": 0.2, "billboard": "double", "shape": "needle",
			"wind": 0.22,
		},
	},
	&"etree_oak": {
		"type": "deciduous", "target_height": 8.0,
		"bark": {"texture": "Bark001", "texture_scale": Vector2(4.0, 3.0)},
		"branch": {
			"levels": 3,
			"angle": {1: 54.0, 2: 58.0, 3: 32.0},
			"children": {0: 6, 1: 4, 2: 3},
			"force": {"direction": Vector3(0, 1, 0), "strength": 0.02},
			"gnarliness": {0: 0.0, 1: -0.1, 2: -0.15, 3: 0.09},
			"length": {0: 37.24, 1: 11.08, 2: 12.39, 3: 7.16},
			"radius": {0: 1.41, 1: 0.9, 2: 0.69, 3: 1.19},
			"sections": {0: 8, 1: 6, 2: 3, 3: 1},
			"segments": {0: 7, 1: 5, 2: 3, 3: 3},
			"start": {1: 0.49, 2: 0.06, 3: 0.12},
			"taper": {0: 0.73, 1: 0.42, 2: 0.69, 3: 0.75},
			"twist": {0: -0.23, 1: 0.42, 2: 0.0, 3: 0.0},
		},
		"leaves": {
			"count": 16, "start": 0.16, "angle": 42.0, "size": 3.2,
			"size_variance": 0.55, "billboard": "double", "shape": "leaf",
			"wind": 0.26,
		},
	},
	&"etree_aspen": {
		"type": "deciduous", "target_height": 7.0,
		"bark": {"texture": "Bark002", "texture_scale": Vector2(4.0, 3.0)},
		"branch": {
			"levels": 2,
			"angle": {1: 70.0, 2: 35.0, 3: 7.0},
			"children": {0: 4, 1: 3, 2: 3},
			"force": {"direction": Vector3(0, 1, 0), "strength": 0.011},
			"gnarliness": {0: 0.04, 1: -0.01, 2: 0.12, 3: 0.02},
			"length": {0: 23.99, 1: 3.36, 2: 7.7, 3: 1.0},
			"radius": {0: 0.37, 1: 0.41, 2: 0.7, 3: 0.7},
			"sections": {0: 12, 1: 10, 2: 8, 3: 6},
			"segments": {0: 8, 1: 6, 2: 4, 3: 3},
			"start": {1: 0.45, 2: 0.33, 3: 0.0},
			"taper": {0: 0.37, 1: 0.13, 2: 0.7, 3: 0.7},
			"twist": {0: 0.0, 1: 0.0, 2: 0.0, 3: 0.0},
		},
		"leaves": {
			"count": 13, "start": 0.2, "angle": 30.0, "size": 2.8,
			"size_variance": 0.6, "billboard": "double", "shape": "leaf",
			"wind": 0.24,
		},
	},
	&"etree_bush": {
		"type": "deciduous", "target_height": 1.15,
		"bark": {"texture": "Bark001", "texture_scale": Vector2(3.0, 3.0)},
		"branch": {
			"levels": 3,
			"angle": {1: 21.5, 2: 62.6, 3: 60.0},
			"children": {0: 7, 1: 3, 2: 2},
			"force": {"direction": Vector3(0, 1, 0), "strength": 0.0},
			"gnarliness": {0: 0.11, 1: 0.09, 2: 0.05, 3: 0.09},
			"length": {0: 0.1, 1: 15.3, 2: 5.59, 3: 4.6},
			"radius": {0: 0.58, 1: 0.95, 2: 0.76, 3: 0.7},
			"sections": {0: 6, 1: 6, 2: 10, 3: 10},
			"segments": {0: 4, 1: 4, 2: 4, 3: 3},
			"start": {1: 0.53, 2: 0.33, 3: 0.0},
			"taper": {0: 0.7, 1: 0.7, 2: 0.7, 3: 0.7},
			"twist": {0: 0.3, 1: -0.07, 2: 0.0, 3: 0.0},
		},
		"leaves": {
			"count": 10, "start": 0.0, "angle": 55.0, "size": 3.4,
			"size_variance": 0.6, "billboard": "double", "shape": "leaf",
			"wind": 0.1,
		},
	},
	# Гигант лесной поляны (~14 м): дуб-исполин — ориентир, читается
	# раскидистой кроной с любой стороны (П5.7 блок 2 задал высоту ~11 м;
	# процедурный дуб нормирован до 14 м — «старше» прочего леса).
	&"etree_giant": {
		"type": "deciduous", "target_height": 14.0,
		"bark": {"texture": "Bark001", "texture_scale": Vector2(8.0, 5.0)},
		"branch": {
			"levels": 3,
			"angle": {1: 48.0, 2: 55.0, 3: 30.0},
			"children": {0: 7, 1: 5, 2: 4},
			"force": {"direction": Vector3(0, 1, 0), "strength": 0.03},
			"gnarliness": {0: 0.0, 1: -0.08, 2: -0.12, 3: 0.07},
			"length": {0: 52.0, 1: 20.0, 2: 16.0, 3: 9.0},
			"radius": {0: 2.6, 1: 1.4, 2: 1.0, 3: 1.6},
			"sections": {0: 10, 1: 7, 2: 4, 3: 2},
			"segments": {0: 9, 1: 6, 2: 4, 3: 3},
			"start": {1: 0.45, 2: 0.1, 3: 0.15},
			"taper": {0: 0.75, 1: 0.5, 2: 0.7, 3: 0.75},
			"twist": {0: -0.2, 1: 0.35, 2: 0.0, 3: 0.0},
		},
		"leaves": {
			"count": 18, "start": 0.14, "angle": 40.0, "size": 4.2,
			"size_variance": 0.55, "billboard": "double", "shape": "leaf",
			"wind": 0.3,
		},
	},
	# Валежник (бывший фотоскан dead_tree_trunk): изогнутый ствол,
	# уложенный горизонтально силой роста вдоль +X; веток и листвы нет.
	&"dead_log": {
		"type": "deciduous", "target_height": 3.0, "log_mode": true,
		"bark": {"texture": "Bark003", "texture_scale": Vector2(2.0, 2.0)},
		"branch": {
			"levels": 0,
			"angle": {1: 0.0, 2: 0.0, 3: 0.0},
			"children": {0: 0, 1: 0, 2: 0},
			"force": {"direction": Vector3(1, 0.1, 0), "strength": 0.35},
			"gnarliness": {0: 0.12, 1: 0.0, 2: 0.0, 3: 0.0},
			"length": {0: 30.0, 1: 1.0, 2: 1.0, 3: 1.0},
			"radius": {0: 1.1, 1: 0.7, 2: 0.7, 3: 0.7},
			"sections": {0: 12, 1: 6, 2: 6, 3: 6},
			"segments": {0: 7, 1: 5, 2: 4, 3: 3},
			"start": {1: 0.3, 2: 0.3, 3: 0.3},
			"taper": {0: 0.9, 1: 0.7, 2: 0.7, 3: 0.7},
			"twist": {0: 0.0, 1: 0.0, 2: 0.0, 3: 0.0},
		},
		"leaves": {
			"count": 0, "start": 0.0, "angle": 0.0, "size": 1.0,
			"size_variance": 0.0, "billboard": "single", "shape": "leaf",
			"wind": 0.0,
		},
	},
}

## Уровни детализации (как defaultLODLevels оригинала): прореживание
## секций ветвей, доля радиальных сегментов, шаг и укрупнение листьев.
const LOD_DETAILS: Array[Dictionary] = [
	{},
	{"section_stride": 3, "segment_factor": 0.75, "leaf_stride": 2,
		"leaf_scale": 1.25},
	{"section_stride": 6, "segment_factor": 0.4, "leaf_stride": 2,
		"leaf_scale": 1.3, "billboard": "single"},
]

static var _cache: Dictionary = {}


## Полный набор мешей дерева: {"mesh": LOD0 (кора+крона, 2 поверхности),
## "lods": [LOD1, LOD2], "billboard": картинка дальнего плана}. Валежник
## (log_mode) — одиночный ствол без кроны и LOD. Кэшируется по
## (пресет, вариант): IslandGen просит 3 варианта на тип.
static func build_set(preset: StringName, variant: int) -> Dictionary:
	var key := "%s:%d" % [preset, variant]
	if _cache.has(key):
		return _cache[key]
	var options := _options(preset, variant)
	var tree := _skeleton(options)
	# Валежник нормируется по длине (лежит вдоль +X), дерево — по высоте.
	var basis_dim: float = tree["span"] if options.get("log_mode", false) \
		else tree["height"]
	var scale: float = float(options["_target_height"]) / maxf(basis_dim, 0.001)
	# Валежник лежит на земле: сдвиг вершин на −min_y (кольца ствола
	# опускаются ниже оси на радиус).
	var y_shift := -float(tree["min_y"]) * scale \
		if options.get("log_mode", false) else 0.0
	var mesh := _tree_mesh(tree, options, scale, LOD_DETAILS[0], y_shift)
	if options.get("log_mode", false):
		# Прикорневое кольцо перпендикулярно стволу, растущему от земли
		# вверх: у основания оно горизонтально и не опускается на радиус —
		# оценка min_y по скелету перестраховывается и приподнимает
		# бревно. Выправляем сдвиг по фактическому AABB готового меша.
		var lift: float = mesh.get_aabb().position.y
		if lift > 0.0:
			y_shift -= lift
			mesh = _tree_mesh(tree, options, scale, LOD_DETAILS[0], y_shift)
		var log_set := {"mesh": mesh, "lods": [] as Array[Mesh], "billboard": null}
		_cache[key] = log_set
		return log_set
	# Крона выступает за скелет: квад листа растёт от черешка на весь
	# размер листа, и пышные пресеты (куст — почти сплошная листва)
	# выходят выше целевой высоты. Нормируем по фактическому габариту
	# готового меша — целевая высота и есть высота дерева с кроной.
	var size_y: float = mesh.get_aabb().size.y
	if size_y > 0.001:
		scale *= float(options["_target_height"]) / size_y
		mesh = _tree_mesh(tree, options, scale, LOD_DETAILS[0], 0.0)
	# Типизированный литерал: словарь хранит Array[Mesh] (PropGroup.lods).
	var lods: Array[Mesh] = [
		_tree_mesh(tree, options, scale, LOD_DETAILS[1], 0.0),
		_tree_mesh(tree, options, scale, LOD_DETAILS[2], 0.0),
	]
	var set := {
		"mesh": mesh, "lods": lods,
		"billboard": _billboard_mesh(tree, options, scale),
	}
	_cache[key] = set
	return set


## Меш уровня детализации: поверхность 0 — кора (материал с текстурой
## CC0), поверхность 1 — крона (canopy.gdshader). Материалы живут в меше:
## MultiMesh деревьев рендерится без material_override (уровни LOD и
## билборд — свои материалы).
static func _tree_mesh(
		tree: Dictionary, options: Dictionary, scale: float,
		detail: Dictionary, y_shift: float = 0.0,
) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _surface_arrays(
		_mesh_branches(tree, options, scale, detail, y_shift)))
	mesh.surface_set_material(0, _bark_material(options))
	if (tree["leaves"] as Array).size() > 0:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _surface_arrays(
			_mesh_leaves(tree, options, scale, detail, y_shift)))
		mesh.surface_set_material(1, _canopy_material(options))
	return mesh


# --- Скелет (порт tree.js #generateSkeleton/#growBranch) ---

## Словарь-ветвь очереди роста.
static func _branch(
		origin: Vector3, euler: Vector3, length: float, radius: float,
		level: int, section_count: int, segment_count: int,
) -> Dictionary:
	return {
		"origin": origin, "euler": euler, "length": length,
		"radius": radius, "level": level,
		"section_count": section_count, "segment_count": segment_count,
	}


## Скелет дерева: секции всех ветвей и позиции листьев. Весь расход RNG —
## здесь; меширование детерминировано поверх готового скелета.
static func _skeleton(options: Dictionary) -> Dictionary:
	var rng := EzRng.new(int(options["_seed"]))
	var branch_options: Dictionary = options["branch"]
	var levels: int = branch_options["levels"]
	var tree := {"branches": [], "leaves": [], "height": 0.0,
		"span": 0.0, "min_y": 0.0}
	var queue: Array[Dictionary] = [
		_branch(Vector3.ZERO, Vector3.ZERO, float(branch_options["length"][0]),
			float(branch_options["radius"][0]), 0,
			int(branch_options["sections"][0]),
			int(branch_options["segments"][0])),
	]
	while not queue.is_empty():
		_grow_branch(queue, tree, queue.pop_front(), options, rng, levels)
	var top := 0.0
	var min_y := 0.0
	for branch: Dictionary in tree["branches"]:
		for section: Dictionary in branch["sections"]:
			var origin: Vector3 = section["origin"]
			top = maxf(top, origin.y)
			min_y = minf(min_y, origin.y - float(section["radius"]))
			tree["span"] = maxf(
				tree["span"], Vector2(origin.x, origin.z).length())
	for leaf: Dictionary in tree["leaves"]:
		var origin: Vector3 = leaf["origin"]
		top = maxf(top, origin.y)
		min_y = minf(min_y, origin.y)
	tree["height"] = top
	tree["min_y"] = min_y
	return tree


## Порт #growBranch: растит одну ветвь, ставит секции, ставит в очередь
## дочерние (deciduous — ещё и терминальную) и листья.
static func _grow_branch(
		queue: Array[Dictionary], tree: Dictionary, branch: Dictionary,
		options: Dictionary, rng: EzRng, levels: int,
) -> void:
	var branch_options: Dictionary = options["branch"]
	var leaves_options: Dictionary = options["leaves"]
	var deciduous: bool = options["type"] == "deciduous"
	var section_origin: Vector3 = branch["origin"]
	var section_euler: Vector3 = branch["euler"]
	var section_count: int = branch["section_count"]
	# У лиственных секция короче на (levels − 1): терминальные ветви
	# продолжают ствол, суммарная длина совпадает с параметром length.
	# levels ≤ 1 (валежник, levels 0) — без деления, иначе длина уходит
	# в минус и ствол растёт вниз.
	var section_divisor: float = \
		(float(levels - 1) if deciduous and levels > 1 else 1.0)
	var section_length: float = \
		float(branch["length"]) / float(section_count) / section_divisor

	var sections: Array[Dictionary] = []
	for i: int in section_count + 1:
		var radius: float = branch["radius"]
		if i == section_count and branch["level"] == levels:
			radius = 0.001
		elif deciduous:
			radius *= 1.0 - float(branch_options["taper"][branch["level"]]) \
				* (float(i) / float(section_count))
		else:
			radius *= 1.0 - float(i) / float(section_count)
		sections.append({
			"origin": section_origin, "euler": section_euler,
			"radius": radius,
				"quat": _quat_from_euler(section_euler),

		})
		section_origin += _quat_from_euler(section_euler) \
			* Vector3.UP * section_length

		# Гнарлайность: случайный поворот следующей секции; тонкие ветви
		# гнутся сильнее (1/sqrt(r)).
		var gnarl: float = maxf(1.0, 1.0 / sqrt(maxf(radius, 0.001))) \
			* float(branch_options["gnarliness"][branch["level"]])
		section_euler.x += rng.rand(gnarl, -gnarl)
		section_euler.z += rng.rand(gnarl, -gnarl)

		var quat := _quat_from_euler(section_euler)

		quat *= Quaternion(
			Vector3.UP, float(branch_options["twist"][branch["level"]]))

		# Сила роста: доворот секции к force.direction (strength/radius,
		# не дальше полного угла до цели).
		var force: Dictionary = branch_options["force"]
		var up := quat * Vector3.UP
		var target: Vector3 = force["direction"]
		var axis := up.cross(target)
		var sin_full := axis.length()
		if sin_full > 1e-6:
			axis /= sin_full
			var full_angle := atan2(sin_full, up.dot(target))
			var step: float = float(force["strength"]) / maxf(radius, 0.001)
			quat = Quaternion(
				axis, clampf(step, -full_angle, full_angle)) * quat
		section_euler = quat.get_euler(EulerOrder.EULER_ORDER_XYZ)

	(tree["branches"] as Array).append({
		"sections": sections,
		"segment_count": branch["segment_count"],
		"base_radius": branch["radius"],
	})

	if deciduous:
		var last: Dictionary = sections[sections.size() - 1]
		if branch["level"] < levels:
			queue.push_back(_branch(
				last["origin"], last["euler"],
				float(branch_options["length"][branch["level"] + 1]),
				last["radius"], branch["level"] + 1,
				section_count, branch["segment_count"]))
		else:
			_record_leaf(tree, last["origin"], last["quat"], options, rng)

	if branch["level"] == levels:
		_generate_leaves(tree, sections, options, rng)
	elif branch["level"] < levels:
		_generate_child_branches(
			queue, sections, branch, options, rng, levels)


## Порт generateChildBranches: стратификация по длине родителя, слоты
## радиального угла в случайной перестановке (иначе хвойные «спиралит»).
static func _generate_child_branches(
		queue: Array[Dictionary], sections: Array, branch: Dictionary,
		options: Dictionary, rng: EzRng, levels: int,
) -> void:
	var branch_options: Dictionary = options["branch"]
	var level: int = branch["level"] + 1
	var count: int = branch_options["children"][branch["level"]]
	if count <= 0:
		return
	var radial_offset := rng.rand()
	var start_min: float = branch_options["start"][level]
	var height_step: float = (1.0 - start_min) / float(count)
	var slots := _shuffled_indices(count, rng)
	var evergreen: bool = options["type"] == "evergreen"
	for i: int in count:
		var child_start: float = start_min \
			+ (float(i) + rng.rand()) * height_step
		var section_index: int = int(
			floor(child_start * float(sections.size() - 1)))
		var section_a: Dictionary = sections[section_index]
		var section_b: Dictionary = \
			sections[mini(section_index + 1, sections.size() - 1)]
		var span := float(sections.size() - 1)
		var alpha: float = \
			(child_start - float(section_index) / span) * span
		var child_origin: Vector3 = (section_a["origin"] as Vector3).lerp(
			section_b["origin"], alpha)
		var child_radius: float = float(branch_options["radius"][level]) \
			* ((1.0 - alpha) * float(section_a["radius"])
				+ alpha * float(section_b["radius"]))
		var parent_quat: Quaternion = (section_b["quat"] as Quaternion).slerp(
			section_a["quat"], alpha)
		var radial_jitter := rng.rand(0.5, -0.5)
		var radial_angle := TAU \
			* (radial_offset + (float(slots[i]) + radial_jitter) / float(count))
		var child_quat: Quaternion = parent_quat \
			* Quaternion(Vector3.UP, radial_angle) \
			* Quaternion(Vector3.RIGHT,
				deg_to_rad(float(branch_options["angle"][level])))
		var child_length: float = float(branch_options["length"][level]) \
			* ((1.0 - child_start) if evergreen else 1.0)
		queue.push_back(_branch(
			child_origin, child_quat.get_euler(EulerOrder.EULER_ORDER_XYZ),
			child_length, child_radius, level,
			int(branch_options["sections"][level]),
			int(branch_options["segments"][level])))


## Порт generateLeaves: листья последнего уровня ветвления.
static func _generate_leaves(
		tree: Dictionary, sections: Array, options: Dictionary, rng: EzRng,
) -> void:
	var leaves_options: Dictionary = options["leaves"]
	var count: int = leaves_options["count"]
	if count <= 0:
		return
	var radial_offset := rng.rand()
	var start_min: float = leaves_options["start"]
	var height_step: float = (1.0 - start_min) / float(count)
	var slots := _shuffled_indices(count, rng)
	for i: int in count:
		var leaf_start: float = start_min \
			+ (float(i) + rng.rand()) * height_step
		var section_index: int = int(
			floor(leaf_start * float(sections.size() - 1)))
		var section_a: Dictionary = sections[section_index]
		var section_b: Dictionary = \
			sections[mini(section_index + 1, sections.size() - 1)]
		var span := float(sections.size() - 1)
		var alpha: float = \
			(leaf_start - float(section_index) / span) * span
		var leaf_origin: Vector3 = (section_a["origin"] as Vector3).lerp(
			section_b["origin"], alpha)
		var parent_quat: Quaternion = (section_b["quat"] as Quaternion).slerp(
			section_a["quat"], alpha)
		var radial_jitter := rng.rand(0.5, -0.5)
		var radial_angle := TAU \
			* (radial_offset + (float(slots[i]) + radial_jitter) / float(count))
		var leaf_quat: Quaternion = parent_quat \
			* Quaternion(Vector3.UP, radial_angle) \
			* Quaternion(Vector3.RIGHT,
				deg_to_rad(float(leaves_options["angle"])))
		_record_leaf(tree, leaf_origin, leaf_quat, options, rng)


## Порт #recordLeaf: размер листа варьируется здесь — меширование
## RNG-free, все уровни LOD видят одинаковые листья.
static func _record_leaf(
		tree: Dictionary, origin: Vector3, quat: Quaternion,
		options: Dictionary, rng: EzRng,
) -> void:
	var leaves_options: Dictionary = options["leaves"]
	# Валежник (leaves.count 0): терминальный лист лиственных не ставится.
	if int(leaves_options["count"]) <= 0:
		return
	var size: float = float(leaves_options["size"]) \
		* (1.0 + rng.rand(float(leaves_options["size_variance"]),
			-float(leaves_options["size_variance"])))
	(tree["leaves"] as Array).append({
		"origin": origin, "quat": quat, "size": size,
	})


## Порт shuffledIndices: Фишер—Йетс на ГПСЧ дерева.
static func _shuffled_indices(count: int, rng: EzRng) -> Array[int]:
	var arr: Array[int] = []
	arr.resize(count)
	for k: int in count:
		arr[k] = k
	for k: int in range(count - 1, 0, -1):
		var r: int = int(rng.rand() * float(k + 1))
		var swap := arr[k]
		arr[k] = arr[r]
		arr[r] = swap
	return arr


# --- Меширование (порт #meshSkeleton/#meshBranch/#meshLeaf) ---

## Кора: кольца вершин по секциям (stride — прореживание LOD), UV.x —
## обороты текстуры по окружности, UV.y — чередование 0/1 по кольцам.
static func _mesh_branches(
		tree: Dictionary, options: Dictionary, scale: float,
		detail: Dictionary, y_shift: float = 0.0,
) -> MeshBuffers:
	var section_stride: int = maxi(1, int(detail.get("section_stride", 1)))
	var segment_factor: float = detail.get("segment_factor", 1.0)
	var texture_scale: float = options["bark"]["texture_scale"].x
	var bark_tint: Color = options["_bark_tint"]
	var buffers := MeshBuffers.new()
	for branch: Dictionary in tree["branches"]:
		var sections: Array = branch["sections"]
		var segments: int = maxi(3, int(round(
			float(branch["segment_count"]) * segment_factor)))
		var wraps: int = maxi(1, int(round(
			float(branch["base_radius"]) * texture_scale)))
		var sampled: Array[Dictionary] = []
		for i: int in range(0, sections.size(), section_stride):
			sampled.append(sections[i])
		if (sections.size() - 1) % section_stride != 0:
			sampled.append(sections[sections.size() - 1])
		var base: int = buffers.verts.size()
		for k: int in sampled.size():
			var section: Dictionary = sampled[k]
			var quat: Quaternion = section["quat"]
			var radius: float = float(section["radius"]) * scale
			var first_vertex := Vector3.ZERO
			var first_normal := Vector3.ZERO
			for j: int in segments:
				var angle := TAU * float(j) / float(segments)
				var ring := Vector3(cos(angle), 0.0, sin(angle))
				var vertex: Vector3 = quat * (ring * radius) \
					+ (section["origin"] as Vector3) * scale \
					+ Vector3(0.0, y_shift, 0.0)
				var normal: Vector3 = (quat * ring).normalized()
				if j == 0:
					first_vertex = vertex
					first_normal = normal
				_append(buffers, vertex, normal, bark_tint, Vector2(
					float(j) / float(segments) * float(wraps),
					0.0 if k % 2 == 0 else 1.0))
			# Дубль первой вершины: u=wraps — тот же тексель, шов непрерывен.
			_append(buffers, first_vertex, first_normal, bark_tint,
				Vector2(float(wraps), 0.0 if k % 2 == 0 else 1.0))
		var n := segments + 1
		for i: int in sampled.size() - 1:
			for j: int in segments:
				var v1: int = base + i * n + j
				var v2: int = v1 + 1
				var v3: int = v1 + n
				var v4: int = v2 + n
				buffers.indices.append_array([v1, v3, v2, v2, v3, v4])
	return buffers


## Крона: квады листьев (для «double» — крест из двух), нормали скруглены
## к направлению от черешка (мягкий объём кроны), цвет — глубина в кроне
## (внутренние листья темнее) и вертикальный градиент хвои.
static func _mesh_leaves(
		tree: Dictionary, options: Dictionary, scale: float,
		detail: Dictionary, y_shift: float = 0.0,
) -> MeshBuffers:
	var leaves_options: Dictionary = options["leaves"]
	var leaf_stride: int = maxi(1, int(detail.get("leaf_stride", 1)))
	var leaf_scale: float = detail.get("leaf_scale", 1.0)
	var double_billboard: bool = \
		detail.get("billboard", leaves_options["billboard"]) == "double"
	var buffers := MeshBuffers.new()
	var leaves: Array = tree["leaves"]

	# Центроид и средний радиус кроны — для глубины цвета.
	var centroid := Vector3.ZERO
	for leaf: Dictionary in leaves:
		centroid += leaf["origin"]
	centroid /= maxf(float(leaves.size()), 1.0)
	var avg_radius := 0.0
	for leaf: Dictionary in leaves:
		avg_radius += (leaf["origin"] as Vector3).distance_to(centroid)
	avg_radius /= maxf(float(leaves.size()), 1.0)
	var conifer: bool = leaves_options["shape"] == "needle"
	var dark: Color = VPAL.canopy_conifer if conifer else VPAL.canopy_dark
	var mid: Color = VPAL.canopy_mid.lerp(VPAL.canopy_conifer, 0.55) \
		if conifer else VPAL.canopy_mid
	var light: Color = VPAL.canopy_light.lerp(mid, 0.35) if conifer \
		else VPAL.canopy_light

	for index: int in range(0, leaves.size(), leaf_stride):
		var leaf: Dictionary = leaves[index]
		var raw: Vector3 = leaf["origin"]
		var origin: Vector3 = raw * scale + Vector3(0.0, y_shift, 0.0)
		var quat: Quaternion = leaf["quat"]
		var size: float = float(leaf["size"]) * scale * leaf_scale
		var depth: float = 1.0 - clampf(
			raw.distance_to(centroid) / maxf(avg_radius, 0.001), 0.0, 1.0)
		# Внешние листья светлее; у хвои добавочно светлее верхушка.
		var tone: float = clampf(depth * 0.75, 0.0, 1.0)
		if conifer:
			tone = clampf(
				depth * 0.6 + raw.y / maxf(float(tree["height"]), 0.001) * 0.4,
				0.0, 1.0)
		var color := dark.lerp(mid, tone).lerp(light, tone * tone * 0.35)
		_mesh_leaf(buffers, origin, quat, size, color, double_billboard)
	return buffers


## Порт #meshLeaf: квад от черешка вверх; нормаль каждой вершины — смесь
## нормали квада и направления от черешка в той же системе (roundedNormals
## оригинала) — крона затеняется мягким объёмом, а не пучком плоскостей.
static func _mesh_leaf(
		buffers: MeshBuffers, origin: Vector3, quat: Quaternion, size: float,
		color: Color, double_billboard: bool,
) -> void:
	var base: int = buffers.verts.size()
	var half := size * 0.5
	var rotations: Array[float] = [0.0]
	if double_billboard:
		rotations.append(PI * 0.5)
	for rotation: float in rotations:
		var q_yaw := Quaternion(Vector3.UP, rotation)
		var corners := [
			Vector3(-half, size, 0.0), Vector3(-half, 0.0, 0.0),
			Vector3(half, 0.0, 0.0), Vector3(half, size, 0.0),
		]
		var flat_normal: Vector3 = quat * Vector3.BACK
		for corner: int in 4:
			var offset: Vector3 = quat * (q_yaw * corners[corner])
			_append(buffers, origin + offset,
				(flat_normal + offset).normalized(), color,
				Vector2(float(corner in [1, 2]), float(corner in [0, 1])))
		buffers.indices.append_array(
			[base, base + 1, base + 2, base, base + 2, base + 3])
		base += 4


## «Картинка» дальнего плана: плоский силуэт по профилю кроны (макс.
## радиус листьев по слоям высоты), цвет — кора внизу, крона с
## вертикальным градиентом; шейдер разворачивает квад на камеру.
static func _billboard_mesh(
		tree: Dictionary, options: Dictionary, scale: float,
) -> ArrayMesh:
	var leaves: Array = tree["leaves"]
	# Высота картинки — целевая высота пресета: полный меш нормирован
	# в неё же (см. build_set), дальний план совпадает по силуэту.
	var height: float = float(options["_target_height"])
	var rows := 10
	var profile := PackedFloat32Array()
	profile.resize(rows + 1)
	var trunk_radius: float = float(options["branch"]["radius"][0]) * scale
	var conifer: bool = options["leaves"]["shape"] == "needle"
	var bark_color: Color = options["_bark_tint"] as Color
	var dark: Color = VPAL.canopy_conifer if conifer else VPAL.canopy_dark
	var light: Color = (VPAL.canopy_mid.lerp(VPAL.canopy_conifer, 0.4)
		if conifer else VPAL.canopy_mid.lerp(VPAL.canopy_light, 0.5))
	var canopy_bottom := height
	for leaf: Dictionary in leaves:
		canopy_bottom = minf(canopy_bottom, (leaf["origin"] as Vector3).y * scale)
	var buffers := MeshBuffers.new()
	var columns := 2
	for row: int in rows + 1:
		var t := float(row) / float(rows)
		var y := t * height
		var width := trunk_radius * 2.2
		if y > canopy_bottom and not leaves.is_empty():
			# Максимальный размах листьев слоя (±1 слой на сглаживание).
			var reach := 0.0
			for leaf: Dictionary in leaves:
				var origin: Vector3 = leaf["origin"]
				var ly := origin.y * scale
				if absf(ly - y) <= height / float(rows):
					reach = maxf(reach, sqrt(
						origin.x * origin.x + origin.z * origin.z) * scale \
						+ float(leaf["size"]) * scale * 0.35)
			width = maxf(width, reach * 2.0)
		var color := bark_color.lerp(dark.lerp(light, t),
			clampf((y - canopy_bottom + height * 0.05) / (height * 0.25), 0.0, 1.0))
		for column: int in columns:
			var x := (float(column) / float(columns - 1) - 0.5) * width
			var base: int = buffers.verts.size()
			_append(buffers, Vector3(x, y, 0.0), Vector3.BACK, color,
				Vector2(float(column), 1.0 - t))
			if row < rows and column < columns - 1:
				var stride := columns
				buffers.indices.append_array([
					base, base + stride, base + 1,
					base + 1, base + stride, base + stride + 1,
				])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,
		_surface_arrays(buffers))
	mesh.surface_set_material(0, _billboard_material(options, height))
	return mesh


# --- Материалы ---

## Кора: CC0-текстура ambientcg (third_party), тайлинг по UV меша
## (wraps по окружности), плотнее по вертикали; тон — вершинный/инстанс.
static func _bark_material(options: Dictionary) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.roughness = 1.0
	material.vertex_color_use_as_albedo = true
	# Планка качества П5.9: мип-мапы + анизотропная фильтрация текстур.
	material.texture_filter = \
		BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var bark_name: String = options["bark"]["texture"]
	var file: Dictionary = BARK_FILES.get(StringName(bark_name),
		BARK_FILES[&"Bark002"])
	var texture_path := "res://assets/third_party/ambientcg.com/%s/%s%s" \
		% [bark_name, bark_name, file["suffix"]]
	if ResourceLoader.exists(texture_path):
		material.albedo_texture = load(texture_path)
		material.uv1_scale = Vector3(
			1.0, float(options["bark"]["texture_scale"].y)
				/ float(file["uv_divider"]), 1.0)
		material.albedo_color = options["_bark_tint"]
	return material


## Крона: мягкий wrap-свет, просвет солнца сквозь листву, качание
## ветром от мировой позиции (параметры — из пресета).
static func _canopy_material(options: Dictionary) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = CANOPY_SHADER
	var shape := 1.0 if options["leaves"]["shape"] == "needle" else 0.0
	material.set_shader_parameter("needle_shape", shape)
	material.set_shader_parameter("wind_amplitude",
		float(options["leaves"]["wind"]))
	return material


static func _billboard_material(
		options: Dictionary, height: float,
) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = BILLBOARD_SHADER
	material.set_shader_parameter("tree_height", height)
	material.set_shader_parameter("wind_amplitude",
		float(options["leaves"]["wind"]))
	return material


# --- Служебное ---

## Опции пресета + вычисляемые поля: seed от (пресет, вариант), тон коры
## из палитры (конифер/лиственное).
static func _options(preset: StringName, variant: int) -> Dictionary:
	var options: Dictionary = (PRESETS[preset] as Dictionary).duplicate(true)
	options["_seed"] = hash(["etree", String(preset), variant])
	options["_target_height"] = PRESETS[preset]["target_height"]
	options["_bark_tint"] = VPAL.bark_conifer \
		if options["type"] == "evergreen" else VPAL.bark_deciduous
	return options


## Буферы геометрии одной поверхности. Отдельный класс, а не словарь:
## packed-массивы — copy-on-write, изменение через значение словаря
## ((buffers["verts"] as ...).append) писало бы в откреплённую копию.
class MeshBuffers:
	extends RefCounted
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()


static func _append(
		buffers: MeshBuffers, vertex: Vector3, normal: Vector3,
		color: Color, uv: Vector2,
) -> void:
	buffers.verts.append(vertex)
	buffers.normals.append(normal)
	buffers.colors.append(color)
	buffers.uvs.append(uv)


## Массивы add_surface_from_arrays из буферов.
static func _surface_arrays(buffers: MeshBuffers) -> Array:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = buffers.verts
	arrays[Mesh.ARRAY_NORMAL] = buffers.normals
	arrays[Mesh.ARRAY_COLOR] = buffers.colors
	arrays[Mesh.ARRAY_TEX_UV] = buffers.uvs
	arrays[Mesh.ARRAY_INDEX] = buffers.indices
	return arrays


## Кватернион из эйлеровых углов в порядке XYZ (как three.js 'XYZ'
## оригинала): Quaternion.from_euler не принимает порядок — идём через Basis.
static func _quat_from_euler(euler: Vector3) -> Quaternion:
	return Basis.from_euler(euler, EulerOrder.EULER_ORDER_XYZ) \
		.get_rotation_quaternion()


## ГПСЧ Marsaglia — порт rng.js EZ-Tree (те же константы и порядок
## вызовов: seed пресета даёт ту же последовательность, что в оригинале).
class EzRng:
	extends RefCounted
	var m_w: int = 123456789
	var m_z: int = 987654321

	func _init(seed: int) -> void:
		m_w = (123456789 + seed) & 0xFFFFFFFF
		m_z = (987654321 - seed) & 0xFFFFFFFF

	## Число в [min, max) — как random(max, min) оригинала (порядок
	## аргументов там обратный, симметричные диапазоны эквивалентны).
	func rand(max_v: float = 1.0, min_v: float = 0.0) -> float:
		m_z = (36969 * (m_z & 65535) + (m_z >> 16)) & 0xFFFFFFFF
		m_w = (18000 * (m_w & 65535) + (m_w >> 16)) & 0xFFFFFFFF
		var result: int = (((m_z << 16) & 0xFFFFFFFF) + (m_w & 65535)) \
			& 0xFFFFFFFF
		return (max_v - min_v) * (float(result) / 4294967296.0) + min_v
