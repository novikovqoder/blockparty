# Модель персонажа игрока (П5.7, блок 4): одна из трёх реалистичных моделей
# (Финн/Луми/Тимьян), собранных tools/make_characters.py из базовых CC0-ассетов
# MakeHuman через MPFB (лицензии — assets/third_party/LICENSES.md; риг MPFB
# game_engine, 52 кости). Что делает setup(character):
# - инстансит glb (точка опоры glb уже у ступней) и масштабирует так, чтобы
#   макушка головы (волосы, без шляпы) встала на HEAD_TOP_Y — как коллизия
#   игрока из раздела 5, управление и физика не меняются;
# - раскладывает пары полная версия/_LOD по дистанции видимости: рядом играют
#   полные меши (~20–30 тыс. треугольников), издали — облегчённые копии из
#   того же glb (detail-части LOD-копий не имеют и видны всегда);
# - цвет игрока не трогает: setup_palette перекрашивает только материал
#   PlayerColor (заметная часть одежды — поло/свитер/футболка), кожа и вещи
#   остаются как собраны. Фирменные детали (ушки на шляпе, ракушка, росток
#   на панаме) запечены в модели с префиксом Detail_ в имени узла.
# Чёрный мультяшный контур (обратная оболочка KayKit-моделей) в П5.7 убран:
# у реалистичных моделей контура нет. Анимации подключает
# set_state/play_one_shot (клипы — CharacterAnims); интерфейс не менялся,
# чтобы player.gd и remote_player.gd не переключали класс второй раз.
class_name CharacterModel
extends Node3D

## glb-модели персонажей (0 — Финн, 1 — Луми, 2 — Тимьян).
const GLBS: PackedStringArray = [
	"res://assets/third_party/makehumancommunity.org/finn/finn.glb",
	"res://assets/third_party/makehumancommunity.org/lumi/lumi.glb",
	"res://assets/third_party/makehumancommunity.org/thyme/thyme.glb",
]
## Целевая высота макушки головы, м — как HeadTop в player.tscn
## и remote_player.gd (коллизия капсулы игрока до 1.6 м).
const HEAD_TOP_Y: float = 1.65
## Дальше этой дистанции модель показывается LOD-копиями, м («Простая»
## графика приближает переключение — уровни качества, П5.7 блок 7).
const LOD_DISTANCE: float = 18.0
## Имя материала одежды в glb: цвет игрока применяется только к нему.
const COLOR_MATERIAL: String = "PlayerColor"
## Префикс узлов декоративных частей (шляпы, фирменные детали): исключаются
## из замера макушки и никогда не тонируются.
const DETAIL_PREFIX: String = "Detail"
## Суффикс узлов облегчённых копий мешей из того же glb.
const LOD_SUFFIX: String = "_LOD"
## Узел меша тела: в позе связки MPFB руки подняты выше макушки, замер роста
## идёт по волосам/лицу, тело из него исключено.
const BODY_MESH: String = "Human_export"
## Плавный переход между клипами, с.
const ANIM_BLEND: float = 0.15
## Число цветовых вариантов игрока (выдаётся по хэшу id).
const PALETTES: int = 6

const PAL: Palette = preload("res://assets/palette.tres")

## Номер персонажа (0…GLBS.size()−1), фиксируется в setup.
var character: int = 0
## Дистанция переключения LOD (меняют уровни качества).
var lod_distance: float = LOD_DISTANCE

var _glb_root: Node3D = null
var _skeleton: Skeleton3D = null
var _player: AnimationPlayer = null
var _scale: float = 1.0
var _state: int = Protocol.AnimState.IDLE
## Сколько ещё играть разовый клип (play_one_shot), с; < 0 — не играет.
var _one_shot_left: float = -1.0


## Номер цветового варианта по хэшу id: один id — всегда один цвет.
## absi — id бывает отрицательным (peer id ENet); по сети ничего не передаётся.
static func palette_index(id: int) -> int:
	return absi(id) % PALETTES


static func count() -> int:
	return GLBS.size()


## Номер персонажа вне диапазона → 0 (то же правило применяет хост к номеру
## из сети, раздел 10 SPEC).
static func valid_index(p_character: int) -> int:
	return p_character if p_character >= 0 and p_character < GLBS.size() else 0


## Построить модель персонажа; вне диапазона — первый.
func setup(p_character: int) -> void:
	character = valid_index(p_character)
	if _glb_root != null:
		_glb_root.queue_free()
	var scene := load(GLBS[character]) as PackedScene
	_glb_root = scene.instantiate() as Node3D
	add_child(_glb_root)
	_skeleton = _find_skeleton(_glb_root)
	_apply_fit_scale()
	_apply_lod_distance()
	_setup_animations()


## Цвет игрока по хэшу id: заметная часть одежды (материал PlayerColor)
## тонируется одним из 6 ярких цветов (PAL.player_colors, раздел 16).
func setup_palette(id: int) -> void:
	setup_body_color(PAL.player_colors[palette_index(id)])


## Тонирование одежды конкретным цветом — игрокам цвет выдаётся по хэшу id
## (setup_palette), жителям П5.5 задаётся нейтральный, не из 6 игроков.
## Дубликат материала один на экземпляр модели (полная версия и _LOD делят
## исходный ресурс) и применяется поверхным материалом каждого surface.
func setup_body_color(color: Color) -> void:
	if _glb_root == null:
		return
	var tinted: StandardMaterial3D = null
	for node in _glb_root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for surface in mi.mesh.get_surface_count():
			var base := mi.mesh.surface_get_material(surface) as StandardMaterial3D
			if base == null or base.resource_name != COLOR_MATERIAL:
				continue
			if tinted == null:
				tinted = base.duplicate() as StandardMaterial3D
				tinted.albedo_color = color
			mi.set_surface_override_material(surface, tinted)


## Дистанция переключения LOD (уровни качества: «Простая» — ближе).
func set_lod_distance(distance: float) -> void:
	lod_distance = distance
	if _glb_root != null:
		_apply_lod_distance()


## Раскладка пар полная версия/_LOD: у мешей с LOD-близнецом рядом (до
## lod_distance) играют полные меши, дальше — облегчённые копии; меши без
## копии (detail-части, уши/ракушка/росток) видны на любой дистанции.
func _apply_lod_distance() -> void:
	for node in _glb_root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if _is_lod(mi):
			mi.visibility_range_begin = lod_distance
		elif mi.get_parent().has_node(String(mi.name) + LOD_SUFFIX):
			mi.visibility_range_end = lod_distance


## Сетевое состояние анимации (Protocol.AnimState): покой/ходьба/бег/фазы
## прыжка выбираются локально по скорости и касанию земли (player.gd),
## ремоуты получают то же состояние в снапшоте. Один и тот же клип не
## перезапускается (взмах не сбивается кадром «всё ещё бег»).
func set_state(state: int) -> void:
	_state = state
	_one_shot_left = -1.0
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


func _setup_animations() -> void:
	# Плеер — ребёнок корня glb; библиотека KayKit пока играет на новом риге
	# без совпадения имён костей (до ретаргетинга П5.7 блок 5 модель стоит
	# в позе связки) — интерфейс состояний не менялся.
	_player = AnimationPlayer.new()
	_player.name = "CharacterAnims"
	_glb_root.add_child(_player)
	_player.add_animation_library(CharacterAnims.LIB_NAME, CharacterAnims.library())
	set_state(Protocol.AnimState.IDLE)


## Макушка головы с учётом масштаба, м: верх волос без шляпы и detail-частей
## (шляпы выше HEAD_TOP_Y — декор, раздел 16); LOD-копии и меш тела (руки
## в позе связки выше макушки) не считаются.
func head_top_height() -> float:
	var top := 0.0
	for node in _glb_root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if _is_lod(mi) or _is_detail(mi) or _is_body(mi):
			continue
		top = maxf(top, _mesh_box(mi).end.y)
	return top


## Нижняя точка модели (подошвы), м — полные меши, без detail-частей.
func lowest_point() -> float:
	var bottom := 0.0
	for node in _glb_root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if _is_lod(mi) or _is_detail(mi):
			continue
		bottom = minf(bottom, _mesh_box(mi).position.y)
	return bottom


## AABB меша в координатах модели: glb-меши стоят в origin скелета, а части
## убора — центрированные примитивы в собственных position/scale узла.
func _mesh_box(mi: MeshInstance3D) -> AABB:
	var to_model := global_transform.affine_inverse()
	return to_model * (mi.global_transform * mi.mesh.get_aabb())


## Число мешей с LOD-близнецом (для тестов): полная версия + копия _LOD.
func lod_pairs() -> int:
	var found := 0
	for node in _glb_root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if not _is_lod(mi) and mi.get_parent().has_node(String(mi.name) + LOD_SUFFIX):
			found += 1
	return found


func _apply_fit_scale() -> void:
	# Масштаб по верху волос (шляпы и меш тела с поднятыми руками
	# исключены): головы всех персонажей на одной высоте (ник, коллайдер
	# головы) при разных шляпах и пропорциях. glb-меши в origin скелета —
	# aabb.end.y без трансформа узла.
	var top := 0.0
	for node in _glb_root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if not _is_lod(mi) and not _is_detail(mi) and not _is_body(mi):
			top = maxf(top, mi.mesh.get_aabb().end.y)
	assert(top > 1.0, "меш головы не найден: некуда подгонять рост")
	_scale = HEAD_TOP_Y / top
	_glb_root.scale = Vector3.ONE * _scale


static func _is_body(mi: MeshInstance3D) -> bool:
	return mi.name == BODY_MESH


func _find_skeleton(root: Node) -> Skeleton3D:
	for node in root.find_children("*", "Skeleton3D", true, false):
		return node as Skeleton3D
	return null


## LOD-копии лежат рядом с полными мешами и помечены суффиксом _LOD.
static func _is_lod(mi: MeshInstance3D) -> bool:
	return (mi.name as String).ends_with(LOD_SUFFIX)


static func _is_detail(mi: MeshInstance3D) -> bool:
	return (mi.name as String).begins_with(DETAIL_PREFIX)
