# Генерация трёх реалистичных персонажей (П5.7, блок 4): MPFB в headless
# Blender. Собирает Финна, Луми и Тимьяна из базовых CC0-ассетов MakeHuman
# (лицензии — assets/third_party/LICENSES.md). Каждый: своё телосложение,
# возраст и лицо (макросы + таргеты), кожа, волосы, одежда, обувь и фирменная
# деталь в реалистичном исполнении (у Финна — ушки на кепке, у Луми — ракушка
# на ленте шляпы, у Тимьяна — панама с веточкой). Материал верха одежды
# называется PlayerColor — цвет игрока перекрашивает только его.
#
# Бюджет 20–30 тыс. треугольников: тело (прокси generic, 22 тыс. после
# запекания) и крупная одежда/зубы декиматируются по ролям. Рядом с каждой
# детальной версией в тот же glb кладётся копия с суффиксом _LOD (те же
# материалы, общий риг) — «Простая» графика и дальние дистанции.
# Текстуры ассетов 2048² на ходу ужимаются до 1024² (мелкие части — 512²):
# glb получается ~6–9 МБ вместо 24.
#
# Экспорт: glb (риг game_engine, анимации ретаргетятся отдельно, блок 5).
# Запуск:
#   ~/tools/blender/blender --background --python tools/make_characters.py
import bpy
import importlib
import os
import sys

ASSETS = os.path.expanduser("~/mpfb_assets")
OUT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..",
	"assets/third_party/makehumancommunity.org"))

## Доля треугольников после декимации полной версии, по роли меша.
RATIOS: dict = {
	"body": 0.55, "teeth": 0.18, "hair": 0.7,
	"shoes": 0.5, "clothes": 0.5, "hatwear": 1.0, "keep": 1.0,
}
## Дополнительная декимация _LOD-копий относительно полной версии.
LOD_RATIOS: dict = {
	"body": 0.35, "teeth": 0.5, "hair": 0.45,
	"shoes": 0.45, "clothes": 0.4, "hatwear": 0.6, "keep": 0.6,
}


def dynamic_import(absolute_package_str, key):
	# Extension-формат Blender требует относительных импортов — пакет может
	# оказаться в любом месте иерархии модулей (quirk из примеров MPFB).
	for amod in list(sys.modules.keys()):
		if amod.endswith(absolute_package_str):
			mpfb_mod = importlib.import_module(amod)
			if not hasattr(mpfb_mod, key):
				raise AttributeError(f"{amod} has no {key}")
			return getattr(mpfb_mod, key)
	raise ValueError(f"no module ending with {absolute_package_str}")


bpy.ops.preferences.addon_enable(module="bl_ext.user_default.mpfb")
prefs = bpy.context.preferences.addons["bl_ext.user_default.mpfb"].preferences
prefs.mh_user_data = ASSETS

HumanService = dynamic_import("mpfb.services.humanservice", "HumanService")
TargetService = dynamic_import("mpfb.services.targetservice", "TargetService")
AssetService = dynamic_import("mpfb.services.assetservice", "AssetService")
ObjectService = dynamic_import("mpfb.services.objectservice", "ObjectService")
ExportService = dynamic_import("mpfb.services.exportservice", "ExportService")
LocationService = dynamic_import("mpfb.services.locationservice", "LocationService")
HumanObjectProperties = dynamic_import("mpfb.entities.objectproperties", "HumanObjectProperties")

TARGETS = LocationService.get_mpfb_data("targets")

# Общие детали тела: глаза, брови, ресницы, зубы, язык (системные CC0).
BODY_PARTS = [
	("eyes", "low-poly.mhclo", "Eyes"),
	("eyebrows", "eyebrow001.mhclo", "Eyebrows"),
	("eyelashes", "eyelashes01.mhclo", "Eyelashes"),
	("tongue", "tongue01.mhclo", "Tongue"),
	("teeth", "teeth_base.mhclo", "Teeth"),
]

# Трое персонажей. Макросы: gender (0 муж, 1 жен), age, weight, height,
# muscle, proportions; race — доли asian/caucasian/african (сумма 1).
# Шкала age (macro.json MPFB): 0.1875 = ребёнок, 0.5 = «young» (взрослый
# примерно 25 лет), 1 = старик — взрослым нужен age ~= 0.5, НЕ меньше.
# targets — точная настройка лица (путь от data/targets, вес).
# Верх одежды получает материал PlayerColor (цвет игрока).
CHARACTERS = [
	dict(
		name="finn",
		macros=dict(gender=0.0, age=0.5, weight=0.45, height=0.55,
			muscle=0.5, proportions=0.45, cupsize=0.0, firmness=0.5,
			race=dict(asian=0.0, caucasian=1.0, african=0.0)),
		targets=[
			("nose/nose-volume-incr.target.gz", 0.25),
			("head/head-oval.target.gz", 0.6),
			("mouth/mouth-scale-horiz-incr.target.gz", 0.2),
		],
		skin="young_caucasian_male",
		proxy="male_generic",
		hair="short02",
		clothes=[("namuhekam_male_polo_shirt", "PlayerColor"),
			("cortu_cargo_pants", None), ("shoes01", None)],
		hat="fedora01",
		# Финн — круглые меховые ушки по бокам тульи шляпы (базовая федора
		# MakeHuman, CC0): сплюснутые сферы, тёплый коричневый «мех».
		details="ears",
	),
	dict(
		name="lumi",
		macros=dict(gender=1.0, age=0.5, weight=0.4, height=0.35,
			muscle=0.35, proportions=0.55, cupsize=0.4, firmness=0.55,
			race=dict(asian=0.65, caucasian=0.35, african=0.0)),
		targets=[
			("head/head-round.target.gz", 0.7),
			("cheek/l-cheek-volume-incr.target.gz", 0.25),
			("cheek/r-cheek-volume-incr.target.gz", 0.25),
			("eyes/l-eye-scale-incr.target.gz", 0.3),
			("eyes/r-eye-scale-incr.target.gz", 0.3),
		],
		skin="young_asian_female",
		proxy="female_generic",
		hair="ponytail01",
		clothes=[("toigo_fisherman_sweater", "PlayerColor"),
			("toigo_wool_pants", None), ("shoes01", None)],
		hat="aethelraed_unraed_cloche_hat",
		# Сторонний клош пристёгнут к морфам головы неточно: на взрослой
		# голове (age 0.5) поля садятся на глаза — приподнимаем до бровей.
		hat_lift=0.075,
		# Луми — ракушка на ленте шляпы: сплюснутый конус-веер сбоку.
		details="shell",
	),
	dict(
		name="thyme",
		macros=dict(gender=0.0, age=0.62, weight=0.6, height=0.52,
			muscle=0.42, proportions=0.5, cupsize=0.0, firmness=0.4,
			race=dict(asian=0.0, caucasian=0.8, african=0.2)),
		targets=[
			("head/head-rectangular.target.gz", 0.5),
			("nose/nose-scale-horiz-incr.target.gz", 0.3),
			("chin/chin-height-incr.target.gz", 0.2),
		],
		skin="middleage_caucasian_male",
		proxy="male_generic",
		hair="short04",
		clothes=[("elvs_crude_t-shirt_male", "PlayerColor"),
			("toigo_wool_pants", None), ("shoes01", None)],
		hat=None,
		# Тимьян — панама с веточкой зелени: тулья + поля примитивами,
		# на тулье стебель с двумя листиками.
		details="sprout_hat",
	),
]


def find(subdir, fname):
	path = AssetService.find_asset_absolute_path(fname, asset_subdir=subdir)
	if path is None:
		raise RuntimeError(f"ассет не найден: {subdir}/{fname}")
	return path


def apply_macros(basemesh, macros):
	race = macros.pop("race")
	for key, value in macros.items():
		HumanObjectProperties.set_value(key, value, entity_reference=basemesh)
	HumanObjectProperties.set_value("asian", race["asian"], entity_reference=basemesh)
	HumanObjectProperties.set_value("caucasian", race["caucasian"], entity_reference=basemesh)
	HumanObjectProperties.set_value("african", race["african"], entity_reference=basemesh)
	macros["race"] = race
	TargetService.reapply_macro_details(basemesh)


def flat_material(name, color, rough=0.8):
	mat = bpy.data.materials.new(name)
	mat.use_nodes = True
	bsdf = mat.node_tree.nodes["Principled BSDF"]
	bsdf.inputs["Base Color"].default_value = (*color, 1.0)
	bsdf.inputs["Roughness"].default_value = rough
	return mat


def add_primitive(kind, name, size, location, rotation, mat):
	# Примитивы фирменных деталей: создаются в мировых координатах, потом
	# привязываются к кости head рига и едут вместе с ней.
	if kind == "sphere":
		bpy.ops.mesh.primitive_uv_sphere_add(radius=size["r"], location=location,
			rotation=rotation, segments=16, ring_count=12)
	elif kind == "cone":
		bpy.ops.mesh.primitive_cone_add(radius1=size["r1"], radius2=size.get("r2", 0.0),
			depth=size["depth"], location=location, rotation=rotation,
			vertices=16)
	elif kind == "cylinder":
		bpy.ops.mesh.primitive_cylinder_add(radius=size["r"], depth=size["depth"],
			location=location, rotation=rotation, vertices=16)
	obj = bpy.context.active_object
	obj.name = name
	obj.scale = size.get("scale", (1.0, 1.0, 1.0))
	obj.data.materials.append(mat)
	bpy.ops.object.shade_smooth()
	return obj


def attach_to_armature(obj, armature):
	# Привязка детали скиннингом, а не parent_type='BONE': glTF-экспортёр
	# Blender считает bind-позу BONE-парента неверно (детали улетали на
	# несколько метров). Так привязаны шляпы/волосы MPFB — они экспортируются
	# корректно: вершины в группе кости head с весом 1.0 + Armature modifier.
	vg = obj.vertex_groups.new(name="head")
	vg.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
	obj.parent = armature
	mod = obj.modifiers.new("Armature", "ARMATURE")
	mod.object = armature


def world_bounds(asset_name):
	# Мировой AABB объекта-ассета (шляпы, волос): детали размещаются
	# относительно фактической геометрии, а не зашитой высоты — так рост
	# и макросы телосложения ничего не ломают. Ось Z — высота, лицо в −Y.
	import mathutils
	obj = next((o for o in bpy.data.objects if o.type == "MESH"
		and asset_name in o.name.lower()), None)
	if obj is None:
		raise RuntimeError(f"объект для деталей не найден: {asset_name}")
	points = [obj.matrix_world @ mathutils.Vector(corner)
		for corner in obj.bound_box]
	low = mathutils.Vector((min(p.x for p in points), min(p.y for p in points),
		min(p.z for p in points)))
	high = mathutils.Vector((max(p.x for p in points), max(p.y for p in points),
		max(p.z for p in points)))
	return low, high


def make_details(spec, armature):
	fur = flat_material("Fur", (0.24, 0.16, 0.10), 0.95)
	shell = flat_material("Shell", (0.93, 0.88, 0.80), 0.4)
	straw = flat_material("Straw", (0.82, 0.72, 0.50), 0.9)
	leaf = flat_material("Leaf", (0.20, 0.45, 0.16), 0.7)
	stem = flat_material("Stem", (0.25, 0.38, 0.18), 0.8)
	objects = []
	if spec == "ears":
		# Круглые «ушки» на боках тульи федоры (АABB включает широкие поля,
		# поэтому прижимаем к тулье, выше полей).
		low, high = world_bounds("fedora01")
		z = high.z - (high.z - low.z) * 0.30
		y = (low.y + high.y) * 0.5
		for side in (-1.0, 1.0):
			ear = add_primitive("sphere", "Detail_ear_" + ("l" if side < 0 else "r"),
				dict(r=0.034, scale=(1.0, 0.5, 0.8)),
				(side * (high.x * 0.78 + 0.005), y, z),
				(0.0, 0.0, 0.15 * side), fur)
			objects.append(ear)
	elif spec == "shell":
		# Ракушка-веер на ленте у правого борта шляпы: тонкий гранёный
		# конус, раскрыв наружу и чуть вверх.
		low, high = world_bounds("cloche_hat")
		z = low.z + (high.z - low.z) * 0.45
		y = low.y + (high.y - low.y) * 0.22
		shell_obj = add_primitive("cone", "Detail_shell",
			dict(r1=0.045, r2=0.008, depth=0.012, scale=(1.0, 1.0, 1.0)),
			(high.x - 0.004, y, z),
			(1.5708, 0.0, -0.6), shell)
		objects.append(shell_obj)
	elif spec == "sprout_hat":
		# Панама над волосами: тулья (цилиндр) и поля (тонкий широкий
		# цилиндр), поверх тульи — стебель с двумя листиками.
		low, high = world_bounds("short04")
		brim_z = high.z + 0.012
		crown_z = brim_z + 0.038
		crown = add_primitive("cylinder", "Detail_hat_crown",
			dict(r=0.085, depth=0.07),
			(0.0, (low.y + high.y) * 0.5, crown_z), (0.0, 0.0, 0.0), straw)
		brim = add_primitive("cylinder", "Detail_hat_brim",
			dict(r=0.145, depth=0.008),
			(0.0, (low.y + high.y) * 0.5, brim_z), (0.0, 0.0, 0.0), straw)
		top = crown_z + 0.035
		stalk = add_primitive("cylinder", "Detail_sprout_stalk",
			dict(r=0.003, depth=0.045),
			(0.045, low.y + (high.y - low.y) * 0.3, top + 0.018),
			(0.0, 0.35, 0.0), stem)
		leaf_l = add_primitive("sphere", "Detail_sprout_leaf_l",
			dict(r=0.022, scale=(1.0, 0.35, 0.5)),
			(0.032, low.y + (high.y - low.y) * 0.3, top + 0.045),
			(0.0, 0.0, 0.5), leaf)
		leaf_r = add_primitive("sphere", "Detail_sprout_leaf_r",
			dict(r=0.022, scale=(1.0, 0.35, 0.5)),
			(0.062, low.y + (high.y - low.y) * 0.3, top + 0.042),
			(0.0, 0.0, -0.5), leaf)
		objects = [crown, brim, stalk, leaf_l, leaf_r]
	for obj in objects:
		attach_to_armature(obj, armature)
	return objects


def rename_hat_meshes(export_root):
	# Шляпы-ассеты (федора, cloche) переименовываются в Detail_hat: в Godot
	# все декоративные части головы начинаются с Detail_ — по префиксу они
	# исключаются из замера макушки (fit-scale) и не тонируются цветом игрока.
	for obj in collect_tree(export_root):
		if obj.type != "MESH":
			continue
		lower = obj.name.lower()
		if "fedora" in lower or "cloche" in lower:
			obj.name = "Detail_hat_LOD" if "_LOD" in obj.name else "Detail_hat"


def make_materials_opaque():
	# MPFB заводит альфу текстуры в сокет Alpha узла Principled BSDF (и
	# blend_method=BLEND), и glTF-экспортёр выносит это в alphaMode=BLEND:
	# в Godot вся одежда оказалась «прозрачной» (сортировка, без теней).
	# Все меши MakeHuman — сплошная геометрия, альфа не нужна: связь
	# снимается, константа 1.0 экспортируется как OPAQUE.
	for mat in bpy.data.materials:
		mat.blend_method = "OPAQUE"
		if not mat.use_nodes:
			continue
		for node in mat.node_tree.nodes:
			if node.type != "BSDF_PRINCIPLED":
				continue
			for link in list(mat.node_tree.links):
				if link.to_socket == node.inputs["Alpha"]:
					mat.node_tree.links.remove(link)
			node.inputs["Alpha"].default_value = 1.0


def rename_top_material(item_dir, material_name):
	# Материал верха одежды переименован в PlayerColor: в Godot цвет игрока
	# применяется только к нему (куртка/свитер/поло — не штаны и не кожа).
	for obj in bpy.data.objects:
		if obj.type != "MESH" or item_dir not in obj.name.lower():
			continue
		for slot in obj.material_slots:
			if slot.material is not None:
				slot.material.name = material_name
				return slot.material
	return None


def bake_shape_keys(obj):
	# Смесь shape keys (макросы/таргеты формы тела) запекается в вершины
	# меша, ключи удаляются: после этого применима декимация, а glTF не
	# тащит morph targets. Оператора shape_key_apply в Blender 4.5 нет —
	# смесь считается вручную: basis + Σ value_i·(key_i − basis).
	import numpy
	kb = obj.data.shape_keys
	if kb is None or len(kb.key_blocks) <= 1:
		if kb is not None and len(kb.key_blocks) == 1:
			obj.shape_key_remove(kb.key_blocks[0])
		return
	base = numpy.empty(len(kb.key_blocks[0].data) * 3, dtype=numpy.float32)
	kb.key_blocks[0].data.foreach_get("co", base)
	result = base.copy()
	for block in kb.key_blocks[1:]:
		co = numpy.empty(len(block.data) * 3, dtype=numpy.float32)
		block.data.foreach_get("co", co)
		if block.value != 0.0:
			result += block.value * (co - base)
	obj.data.vertices.foreach_set("co", result)
	obj.data.update()
	while obj.data.shape_keys is not None:
		obj.shape_key_remove(obj.data.shape_keys.key_blocks[0])


def mesh_role(name, tris):
	# Роль меша по имени (суффиксы копий .001/_export отрезаются не полностью —
	# поэтому точные имена проверяются раньше «жадного» base) и размеру:
	# тело одно заметно крупнее остального.
	lower = name.lower()
	if "teeth" in lower:
		return "teeth"
	if "shoes" in lower:
		return "shoes"
	for hair in ("hair", "short0", "ponytail", "bob0", "braid", "afro", "long0"):
		if hair in lower:
			return "hair"
	for wear in ("cap", "cloche", "fedora", "hat"):
		if wear in lower:
			return "hatwear"
	for item in ("polo", "shirt", "sweater", "pants", "jeans", "t-shirt", "suit", "top"):
		if item in lower:
			return "clothes"
	if tris > 15000 or "base" in lower or "generic" in lower:
		return "body"
	return "keep"


def tris_of(obj):
	return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def decimate(obj, ratio):
	# Деструктивная декимация меша (вершинные группы сохраняются — скиннинг
	# остаётся корректным); ratio — доля оставшихся треугольников.
	if ratio >= 0.999:
		return
	bake_shape_keys(obj)
	mod = obj.modifiers.new("Decimate", "DECIMATE")
	mod.ratio = ratio
	mod.use_collapse_triangulate = True
	bpy.ops.object.select_all(action="DESELECT")
	obj.select_set(True)
	bpy.context.view_layer.objects.active = obj
	bpy.ops.object.modifier_apply(modifier=mod.name)


def scale_images():
	# Текстуры ассетов 2048² → 1024², мелкие части (зубы, глаза, язык) — 512²:
	# масштаб применяется в памяти, glb-экспорт пакует уменьшенные копии.
	for img in bpy.data.images:
		if img.size[0] == 0:
			continue
		limit = 512 if any(t in img.name.lower()
			for t in ("teeth", "eye", "tongue", "eyebrow", "eyelash")) else 1024
		big = max(img.size)
		if big > limit:
			factor = limit / big
			img.scale(max(1, round(img.size[0] * factor)),
				max(1, round(img.size[1] * factor)))


def collect_tree(root):
	objects = [root]
	for child in ObjectService.get_list_of_children(root):
		objects.extend(collect_tree(child))
	return objects


def build_character(spec):
	bpy.ops.wm.read_factory_settings(use_empty=True)
	basemesh = HumanService.create_human()
	apply_macros(basemesh, dict(spec["macros"]))
	for rel, weight in spec["targets"]:
		TargetService.load_target(basemesh, os.path.join(TARGETS, rel), weight=weight)

	# Топология тела: прокси generic прячет базовый меш за маской,
	# после запекания тело ~22 тыс. треугольников декиматируется до ~12 тыс.
	proxy = HumanService.add_mhclo_asset(
		find("proxymeshes", spec["proxy"] + ".proxy"), basemesh,
		asset_type="Proxymeshes", subdiv_levels=0, material_type="NONE")
	mask = basemesh.modifiers.new("Hide base mesh", "MASK")
	mask.vertex_group = "body"
	mask.invert_vertex_group = True

	skin = find("skins", spec["skin"] + ".mhmat")
	HumanService.set_character_skin(skin, basemesh, bodyproxy=proxy,
		skin_type="GAMEENGINE")

	HumanService.add_builtin_rig(basemesh, "game_engine")

	for subdir, fname, atype in BODY_PARTS:
		HumanService.add_mhclo_asset(find(subdir, fname), basemesh,
			asset_type=atype, subdiv_levels=0, material_type="GAMEENGINE")
	HumanService.add_mhclo_asset(find("hair", spec["hair"] + ".mhclo"), basemesh,
		asset_type="Hair", subdiv_levels=0, material_type="GAMEENGINE")

	top_dir = None
	for item_dir, material_name in spec["clothes"]:
		HumanService.add_mhclo_asset(find("clothes", item_dir + ".mhclo"),
			basemesh, asset_type="Clothes", subdiv_levels=0, material_type="GAMEENGINE")
		if material_name is not None:
			top_dir = (item_dir, material_name)
	if top_dir is not None:
		rename_top_material(*top_dir)

	if spec["hat"] is not None:
		HumanService.add_mhclo_asset(find("clothes", spec["hat"] + ".mhclo"),
			basemesh, asset_type="Clothes", subdiv_levels=0, material_type="GAMEENGINE")

	scale_images()

	export_root = ExportService.create_character_copy(basemesh,
		name_suffix="_export")
	export_basemesh = ObjectService.find_object_of_type_amongst_nearest_relatives(
		export_root, "Basemesh")
	ExportService.bake_modifiers_remove_helpers(
		export_basemesh, bake_masks=True, bake_subdiv=True,
		remove_helpers=True, also_proxy=True)

	# Подъём шляпы-ассета (спека hat_lift): после запекания, до декимации
	# и деталей — ракушка/ушки считают позицию от поднятой геометрии.
	# Поднимаем и копию в export-дереве, и исходник: make_details меряет
	# мир через bpy.data.objects и может найти любой из них.
	lift = float(spec.get("hat_lift", 0.0))
	if lift != 0.0:
		for obj in bpy.data.objects:
			if obj.type == "MESH" and "cloche" in obj.name.lower():
				obj.location.z += lift

	# Полная версия: декимация по ролям до бюджета 20–30 тыс. треугольников.
	meshes = [o for o in collect_tree(export_root) if o.type == "MESH"]
	for obj in meshes:
		# Форма тела живёт в shape keys (макросы/таргеты): смесь запекается
		# в вершины, ключи удаляются — декимация применяется, а glTF не
		# тащит morph targets.
		bake_shape_keys(obj)
	full_tris = 0
	for obj in meshes:
		role = mesh_role(obj.name, tris_of(obj))
		decimate(obj, RATIOS[role])
		full_tris += tris_of(obj)

	# _LOD-копии: те же материалы (glb хранит текстуры один раз), тот же риг.
	lod_tris = 0
	for obj in meshes:
		if "_LOD" in obj.name:
			continue
		bpy.ops.object.select_all(action="DESELECT")
		obj.select_set(True)
		bpy.context.view_layer.objects.active = obj
		bpy.ops.object.duplicate()
		dup = bpy.context.active_object
		dup.name = obj.name + "_LOD"
		role = mesh_role(obj.name, tris_of(dup))
		decimate(dup, LOD_RATIOS[role])
		lod_tris += tris_of(dup)

	# Фирменные детали — в export-дереве: позиции считаются от уже запечённых
	# мешей, привязка к арматуре копии (вершины в группе кости head).
	armature = next((o for o in collect_tree(export_root)
		if o.type == "ARMATURE"), None)
	if armature is None:
		raise RuntimeError("риг game_engine не найден")
	make_details(spec["details"], armature)
	rename_hat_meshes(export_root)
	make_materials_opaque()

	# Служебный Icosphere MPFB остаётся в дереве копии — в glb он не нужен.
	for obj in list(bpy.data.objects):
		if obj.name.startswith("Icosphere"):
			print(f"удаляю служебный объект {obj.name} "
				f"(parent: {obj.parent.name if obj.parent else None})")
			bpy.data.objects.remove(obj, do_unlink=True)

	bpy.ops.object.select_all(action="DESELECT")
	export_root.select_set(True)
	for child in collect_tree(export_root):
		if child != export_root:
			child.select_set(True)
	bpy.context.view_layer.objects.active = export_root

	glb = os.path.join(OUT, spec["name"], spec["name"] + ".glb")
	os.makedirs(os.path.dirname(glb), exist_ok=True)
	bpy.ops.export_scene.gltf(filepath=glb, use_selection=True,
		export_format="GLB", export_animations=False,
		export_apply=False, export_yup=True, export_materials="EXPORT")

	size_mb = os.path.getsize(glb) / (1024 * 1024)
	print(f"{spec['name']}: полная ~{full_tris} треугольников, "
		f"LOD ~{lod_tris}, glb {size_mb:.1f} МБ")


if __name__ == "__main__":
	for character in CHARACTERS:
		build_character(character)
