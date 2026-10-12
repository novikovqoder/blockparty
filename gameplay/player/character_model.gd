# Модель персонажа игрока (П5.8, часть B): собирается из запечённых сцен
# Quaternius UBC+MCO (assets/third_party/quaternius.com/
# universal_base_characters/baked/, лицензии CC0 — LICENSES.md).
# Что делает setup_appearance(appearance):
# - инстансит сцену пола (ubc_male/ubc_female.tscn, скелет 65 костей +
#   точки крепления HandL/HandR/Back) и включает части по индексам
#   внешности: срез головы, глаза, брови, причёска, верх+руки, низ,
#   обувь, капюшон. Тела под одеждой в сцене нет — оно вырезано при
#   запекании (ридми MCO), персонаж всегда одет: «без» бывает только убор;
# - тонирует материалы: кожа (обесцвеченная при запекании) и волосы/брови
#   — палитры Appearance умножением albedo, радужка глаз перекрашивается
#   по маске насыщенности (белок не трогается);
# - масштабирует так, чтобы макушка головы встала на HEAD_TOP_Y — как
#   коллизия игрока из раздела 5, управление и физика не меняются;
# - раскладывает пары полный меш/_LOD по дистанции видимости (уровни
#   качества приближают переключение).
# Цвет игрока (setup_palette по хэшу id, 6 вариантов) тонирует заметную
# часть верхней одежды: материал cloth_* верха+рук красится цветом,
# текстура снимается (цвет читается издалека; приём П5.7). Кожа, волосы,
# обувь и низ цвет игрока не получают.
# Анимации (часть C): плеер с библиотекой CharacterAnims (UAL на риге
# UBC, клипы «Armature/Skeleton3D:<кость>» от корня сцены пола) — ребёнок
# UbcRoot, как и треки; set_state/play_one_shot переключают клипы.
class_name CharacterModel
extends Node3D

## Сцены полов: скелет + все части (видимость переключает setup).
const SCENES: PackedStringArray = [
	"res://assets/third_party/quaternius.com/universal_base_characters/baked/ubc_male.res",
	"res://assets/third_party/quaternius.com/universal_base_characters/baked/ubc_female.res",
]
## Текстура глаз для перекраски радужки (запечена из UBC).
const EYE_TEXTURE: String = "res://assets/third_party/quaternius.com/" \
	+ "universal_base_characters/baked/textures/eyes.png"
## Целевая высота макушки головы, м — как HeadTop в player.tscn
## и remote_player.gd (коллизия капсулы игрока до 1.6 м).
const HEAD_TOP_Y: float = 1.65
## Дальше этой дистанции модель показывается LOD-копиями, м («Простая»
## графика приближает переключение — уровни качества, П5.7 блок 7).
const LOD_DISTANCE: float = 18.0
## Суффикс узлов облегчённых копий мешей из той же сцены.
const LOD_SUFFIX: String = "_LOD"
## Число цветовых вариантов игрока (выдаётся по хэшу id).
const PALETTES: int = 6
## Плавный переход между клипами, с.
const ANIM_BLEND: float = 0.15

const PAL: Palette = preload("res://assets/palette.tres")

## Внешность, зафиксированная в setup_appearance.
var appearance: Appearance = null
## Номер пресета (0…count()-1) для старого интерфейса setup(character).
var character: int = 0
## Дистанция переключения LOD (меняют уровни качества).
var lod_distance: float = LOD_DISTANCE

var _root: Node3D = null
var _parts: Dictionary = {}
var _player: AnimationPlayer = null
var _scale: float = 1.0
var _state: int = Protocol.AnimState.IDLE
## Сколько ещё играть разовый клип (play_one_shot), с; < 0 — не играет.
var _one_shot_left: float = -1.0

## Кэш перекрашенных текстур глаз (индекс палитры → текстура).
static var _eye_cache: Dictionary = {}


## Номер цветового варианта по хэшу id: один id — всегда один цвет.
## absi — id бывает отрицательным (peer id ENet); по сети ничего не передаётся.
static func palette_index(id: int) -> int:
	return absi(id) % PALETTES


static func count() -> int:
	return 3


## Номер персонажа вне диапазона → 0 (то же правило применяет хост к номеру
## из сети, раздел 10 SPEC).
static func valid_index(p_character: int) -> int:
	return p_character if p_character >= 0 and p_character < count() else 0


## Построить модель персонажа; вне диапазона — первый пресет.
func setup(p_character: int) -> void:
	character = valid_index(p_character)
	var ap := Appearance.default_for(character % Appearance.GENDERS)
	match character:
		1:
			ap.hair = 0  # Луми: длинные волосы
			ap.top = 0
		2:
			ap.hair = 1  # Тимьян: пучки
			ap.top = 1
		_:
			ap.hair = 4  # Финн: пробор
			ap.top = 0
	setup_appearance(ap)


## Собрать модель по внешности (редактор, часть B): выбор проходит
## validated() — хост уже проверил, локально правило то же.
func setup_appearance(ap: Appearance) -> void:
	appearance = ap.validated()
	if _root != null:
		_root.queue_free()
	_parts.clear()
	var scene := load(SCENES[appearance.gender]) as PackedScene
	_root = scene.instantiate() as Node3D
	add_child(_root)
	for node in _root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		# Ключ — имя узла: полная версия и близнец _LOD лежат рядом
		# («полный, затем _LOD»); часть без суффикса — всегда полный меш.
		if _part_of(mi) != "":
			_parts[String(mi.name)] = mi
	_apply_fit_scale()
	_apply_parts()
	_apply_tints()
	_apply_lod_distance()
	_setup_animations()


## Цвет игрока по хэшу id: заметная часть верхней одежды (материалы
## cloth_* верха и рук) красится одним из 6 ярких цветов (PAL.player_colors,
## раздел 16). Жителям П5.5 задаётся нейтральный — setup_body_color.
func setup_palette(id: int) -> void:
	setup_body_color(PAL.player_colors[palette_index(id)])


## Покрасить верхнюю одежду цветом (текстура снимается — цвет читается
## издалека; кожа/волосы/обувь/низ не трогаются).
func setup_body_color(color: Color) -> void:
	if appearance == null:
		return
	var g := "mf"[appearance.gender]
	var dups := {}
	for slot in ["top", "arms"]:
		_tint_part("%s_%s_%s" % [slot, Appearance.OUTFITS[appearance.top], g],
			"cloth_", dups,
			func(base: StandardMaterial3D) -> Material:
				return _dup_tinted(dups, base, color, true))


## Дистанция переключения LOD (уровни качества: «Простая» — ближе).
func set_lod_distance(distance: float) -> void:
	lod_distance = distance
	if _root != null:
		_apply_lod_distance()


## Сетевое состояние анимации (Protocol.AnimState): покой/ходьба/бег/фазы
## прыжка выбираются локально по скорости и касанию земли (player.gd),
## ремоуты получают то же состояние в снапшоте. Один и тот же клип не
## перезапускается, разовый клип не сбивается кадром состояния (приземление
## и взмах доигрывают, состояние включится после).
func set_state(state: int) -> void:
	_state = state
	if _one_shot_left > 0.0:
		return  # разовый клип доигрывает и сам вернёт уже новое состояние
	if _player == null:
		return
	var clip := CharacterAnims.clip_for_state(state)
	if clip == &"" or _playing_clip() == clip:
		return
	_play_clip(clip, 1.0)


## Разовая анимация (взмах «Привет!», «тычок», приземление): клип играет
## целиком и возвращает состояние; скорость подгоняется под duration,
## но не быстрее/медленнее разумных пределов.
func play_one_shot(state: int, duration: float) -> void:
	if _player == null:
		return
	var clip := CharacterAnims.clip_for_state(state)
	if clip == &"":
		return
	var length: float = (_player.get_animation(
		"%s/%s" % [CharacterAnims.LIB_NAME, clip]) as Animation).length
	var speed: float = clampf(length / maxf(duration, 0.05), 0.6, 3.0)
	_one_shot_left = length / speed
	_play_clip(clip, speed)


func _process(delta: float) -> void:
	# Разовый клип закончился — вернуться к состоянию (сетевому/локальному).
	if _one_shot_left > 0.0:
		_one_shot_left -= delta
		if _one_shot_left <= 0.0:
			set_state(_state)


## Клип, играющий сейчас (без имени библиотеки).
func _playing_clip() -> StringName:
	if _player == null or _player.current_animation.is_empty():
		return &""
	var full := _player.current_animation.split("/")
	return StringName(full[full.size() - 1])


func _play_clip(clip: StringName, speed: float) -> void:
	_player.speed_scale = speed
	_player.play("%s/%s" % [CharacterAnims.LIB_NAME, clip], ANIM_BLEND)


## Плеер — ребёнок корня сцены пола: треки библиотеки ubc (CharacterAnims)
## записаны от корня сцены, root_node плеера по умолчанию «..» — родитель.
## Пересобирается в setup_appearance вместе с моделью; сетевое состояние
## сохраняется и включается заново.
func _setup_animations() -> void:
	_player = AnimationPlayer.new()
	_player.name = "CharacterAnims"
	_root.add_child(_player)
	_player.add_animation_library(CharacterAnims.LIB_NAME, CharacterAnims.library())
	set_state(_state)


## Точка крепления предмета (задел на бой после MVP): HandL/HandR/Back.
func attach_point(point_name: String) -> Node3D:
	if _root == null:
		return null
	var found := _root.find_children(point_name, "BoneAttachment3D", true, false)
	return found[0] as Node3D if not found.is_empty() else null


## Макушка головы с учётом масштаба, м: верх головы и причёски, без убора
## (капюшон — декор, раздел 16).
func head_top_height() -> float:
	var top := 0.0
	var g := "mf"[appearance.gender]
	for part: String in ["head_%s" % g, "hair_long", "hair_buns",
			"hair_buzzed", "hair_buzzed_female", "hair_simple_parted",
			"hair_beard"]:
		var mi := _part(part)
		if mi == null or _is_lod(mi):
			continue
		top = maxf(top, mi.mesh.get_aabb().end.y)
	return top * _scale


## Нижняя точка модели (подошвы), м.
func lowest_point() -> float:
	var bottom := 0.0
	for mi: MeshInstance3D in _parts.values():
		if _is_lod(mi) or not _is_required(mi):
			continue
		bottom = minf(bottom, mi.mesh.get_aabb().position.y)
	return bottom * _scale


## Число мешей с LOD-близнецом (для тестов): полная версия + копия _LOD.
func lod_pairs() -> int:
	var found := 0
	for mi: MeshInstance3D in _parts.values():
		if not _is_lod(mi) and mi.get_parent().has_node(String(mi.name) + LOD_SUFFIX):
			found += 1
	return found


# --- Внутреннее ---

## Имя части по узлу (head_m, top_peasant_f, hair_long, …LOD-близнецы
## относятся к той же части).
func _part_of(mi: MeshInstance3D) -> String:
	var name := String(mi.name)
	return name.substr(0, name.length() - LOD_SUFFIX.length()) \
		if name.ends_with(LOD_SUFFIX) else name


func _part(part: String) -> MeshInstance3D:
	return _parts.get(part) as MeshInstance3D


func _is_lod(mi: MeshInstance3D) -> bool:
	return (mi.name as String).ends_with(LOD_SUFFIX)


## Обязательные слоты одежды/тела: всё, что не причёска и не убор.
func _is_required(mi: MeshInstance3D) -> bool:
	var name := _part_of(mi)
	return name.begins_with("head_") or name.begins_with("eyes_") \
		or name.begins_with("brows_") or name.begins_with("top_") \
		or name.begins_with("arms_") or name.begins_with("legs_") \
		or name.begins_with("feet_")


## Видимость частей: тело головы/глаза/брови всегда, одежда по слотам,
## причёска по индексу, капюшон по убору. Пара полный/_LOD переключается
## вместе — дальний вариант включается дистанцией видимости.
func _apply_parts() -> void:
	var g := "mf"[appearance.gender]
	var show := PackedStringArray([
		"head_%s" % g, "eyes_%s" % g, "brows_%s" % g,
		"hair_%s" % Appearance.HAIRS[appearance.hair],
		"top_%s_%s" % [Appearance.OUTFITS[appearance.top], g],
		"arms_%s_%s" % [Appearance.OUTFITS[appearance.top], g],
		"legs_%s_%s" % [Appearance.OUTFITS[appearance.legs], g],
		"feet_%s_%s" % [Appearance.OUTFITS[appearance.feet], g],
	])
	if appearance.hat == Appearance.HAT_HOOD:
		show.append("hood_ranger_%s" % g)
	for part: String in _parts.keys():
		if part.ends_with(LOD_SUFFIX):
			continue  # близнец включается вместе со своей полной версией
		var near := _parts[part] as MeshInstance3D
		var wanted: bool = show.has(part)
		near.visible = wanted
		var lod := _part(part + LOD_SUFFIX)
		if lod != null:
			lod.visible = wanted


## Тон кожи/волос/глаз по палитрам внешности: поверхностные материалы-дубликаты
## на видимых мешах (полная версия и _LOD делят один дубликат — общий
## словарь на вызов).
func _apply_tints() -> void:
	var g := "mf"[appearance.gender]
	var hair := Appearance.HAIR_COLORS[appearance.hair_color]
	var skin := Appearance.SKIN_COLORS[appearance.skin]
	var dups := {}
	for slot in ["top", "arms"]:
		_tint_part("%s_%s_%s" % [slot, Appearance.OUTFITS[appearance.top], g],
			"skin_", dups, _color_builder(dups, skin))
	_tint_part("head_%s" % g, "skin_", dups, _color_builder(dups, skin))
	_tint_part("hair_%s" % Appearance.HAIRS[appearance.hair], "hair_", dups,
		_color_builder(dups, hair))
	_tint_part("brows_%s" % g, "hair_", dups, _color_builder(dups, hair))
	_tint_part("eyes_%s" % g, "eyes", dups, func(base: StandardMaterial3D) -> Material:
		var dup := base.duplicate() as StandardMaterial3D
		dup.albedo_texture = _eye_texture(appearance.eye_color)
		return dup)


## Поверхностное тонирование меша: поверхности, чей базовый материал
## начинается с prefix, получают дубликат от builder (общий на категорию).
func _tint_mesh(mi: MeshInstance3D, prefix: String,
		builder: Callable) -> void:
	if mi == null:
		return
	for surface: int in _surfaces_of(mi):
		var base := _base_material(mi, surface)
		if base == null or not base.resource_name.begins_with(prefix):
			continue
		mi.set_surface_override_material(surface, builder.call(base))


## Тонирование части целиком — полная версия и _LOD-близнец: на дистанции
## переключения LOD персонаж не меняет цвет. Дубликаты материалов общие
## на вызов, пока базовый материал один и тот же ресурс.
func _tint_part(part: String, prefix: String, dups: Dictionary,
		builder: Callable) -> void:
	for name in [part, part + LOD_SUFFIX]:
		_tint_mesh(_parts.get(name) as MeshInstance3D, prefix, builder)


## Дубликат базового материала, окрашенный в color (текстура снимается,
## если цвет должен читаться издалека).
func _color_builder(dups: Dictionary, color: Color) -> Callable:
	return func(base: StandardMaterial3D) -> Material:
		return _dup_tinted(dups, base, color)


func _dup_tinted(dups: Dictionary, base: StandardMaterial3D, color: Color,
		drop_texture: bool = false) -> Material:
	if not dups.has(base):
		var dup := base.duplicate() as StandardMaterial3D
		if drop_texture:
			dup.albedo_texture = null
		dup.albedo_color = color
		dups[base] = dup
	return dups[base]


## Индексы поверхностей меша (полная версия несёт те же материалы, что
## и _LOD — оба берут базовый материал из меша).
func _surfaces_of(mi: MeshInstance3D) -> Array:
	if mi == null or mi.mesh == null:
		return []
	return range(mi.mesh.get_surface_count())


func _base_material(mi: MeshInstance3D, surface: int) -> StandardMaterial3D:
	return mi.mesh.surface_get_material(surface) as StandardMaterial3D


## Перекрашенная текстура глаз: пиксели с насыщенностью выше порога
## (радужка/зрачок) получают тон/насыщенность цвета палитры при своей
## яркости, белок почти без насыщения не меняется. Кэш static.
static func _eye_texture(index: int) -> ImageTexture:
	if _eye_cache.has(index):
		return _eye_cache[index]
	var base := (load(EYE_TEXTURE) as Texture2D).get_image()
	if base.is_compressed():
		base.decompress()
	base.convert(Image.FORMAT_RGBA8)
	var target := Appearance.EYE_COLORS[index]
	var target_s := _saturation_of(target)
	var img := base
	for y: int in img.get_height():
		for x: int in img.get_width():
			var c := img.get_pixel(x, y)
			var mask: float = clampf(_saturation_of(c) / 0.25, 0.0, 1.0)
			if mask <= 0.0:
				continue
			var v := maxf(maxf(c.r, c.g), c.b)
			img.set_pixel(x, y, Color.from_hsv(target.h,
				target_s * mask, v, c.a))
	var texture := ImageTexture.create_from_image(img)
	_eye_cache[index] = texture
	return texture


static func _saturation_of(c: Color) -> float:
	var mx := maxf(maxf(c.r, c.g), c.b)
	var mn := minf(minf(c.r, c.g), c.b)
	return 0.0 if mx <= 0.0 else (mx - mn) / mx


## Масштаб по верху головы/причёски (капюшон исключён): головы на одной
## высоте при разных пропорциях полов. Меши стоят в origin скелета —
## aabb.end.y без трансформа узла.
func _apply_fit_scale() -> void:
	var top := 0.0
	for part in ["head_m", "head_f", "hair_long", "hair_buns", "hair_buzzed",
			"hair_buzzed_female", "hair_simple_parted", "hair_beard"]:
		var mi := _part(part)
		if mi == null:
			continue
		top = maxf(top, mi.mesh.get_aabb().end.y)
	assert(top > 1.0, "меш головы не найден: некуда подгонять рост")
	_scale = HEAD_TOP_Y / top
	_root.scale = Vector3.ONE * _scale


## Раскладка пар полная версия/_LOD: у мешей с LOD-близнецом рядом (до
## lod_distance) играют полные меши, дальше — облегчённые копии.
func _apply_lod_distance() -> void:
	var distance := GraphicsQuality.character_lod_distance(lod_distance)
	for mi: MeshInstance3D in _parts.values():
		if _is_lod(mi):
			mi.visibility_range_begin = distance
		elif mi.get_parent().has_node(String(mi.name) + LOD_SUFFIX):
			mi.visibility_range_end = distance
