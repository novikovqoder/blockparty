# Внешность игрока (П5.8, часть B): компактный набор индексов вариантов
# редактора внешности — тело (пол), причёска, цвета волос/кожи/глаз, верх,
# низ, обувь, головной убор. Значения — индексы списков вариантов ниже;
# по сети уходит байтами (to_bytes/from_bytes, часть B3), хост проверяет
# диапазоны validated(). Одежда собирается из запечённых сцен
# assets/third_party/quaternius.com/universal_base_characters/baked/
# (UBC + Modular Character Outfits, лицензии CC0 — LICENSES.md).
#
# Персонаж всегда одет: «без» можно только головной убор (HAT_NONE),
# верх и низ выбираются всегда — тело под одеждой удалено при запекании,
# видны только голова (срез), глаза, брови и причёска.
class_name Appearance
extends RefCounted

## Пол: 0 — мужское тело, 1 — женское.
const GENDER_MALE: int = 0
const GENDER_FEMALE: int = 1
const GENDERS: int = 2

## Причёски — индексы мешей hair_* запечённой сцены. Паки дают две
## «стрижки под ноль» (Buzzed/BuzzedFemale) и бороду (только мужское
## тело): списки по полу фильтруют variants_for().
const HAIRS: PackedStringArray = [
	"long", "buns", "buzzed", "buzzed_female", "simple_parted", "beard",
]
## Допустимые причёски по полу (индексы HAIRS).
const HAIRS_MALE: PackedInt32Array = [0, 1, 2, 4, 5]
const HAIRS_FEMALE: PackedInt32Array = [0, 1, 3, 4]

## Комплекты одежды (верх+руки / низ / обувь): peasant, ranger.
const OUTFITS: PackedStringArray = ["peasant", "ranger"]

## Головной убор: «без», капюшон Ranger или процедурные уборы жителей
## (П5.8, часть E: панама Тимьяна с веточкой, шляпа Луми с ракушкой,
## кепка Финна с «ушками» — меши строит tools/make_hats.gd).
const HAT_NONE: int = 0
const HAT_HOOD: int = 1
const HAT_PANAMA: int = 2
const HAT_BRIM: int = 3
const HAT_CAP: int = 4
const HATS: int = 5

## Палитра волос, ~10 естественных цветов (albedo-тон материалов hair_*).
const HAIR_COLORS: PackedColorArray = [
	Color("141210"), Color("2a1a10"), Color("452a16"), Color("66452a"),
	Color("8a6a45"), Color("ab8a5c"), Color("cfae76"), Color("e6cf9b"),
	Color("a94a1e"), Color("d8d5d2"),
]

## Палитра кожи, ~8 оттенков от светлого до тёмного: кожа запечена
## обесцвеченной (яркость), тон — умножение albedo (assets/palette.gd).
const SKIN_COLORS: PackedColorArray = [
	Color("f2d6bd"), Color("eac6a4"), Color("ddaf87"), Color("c9976e"),
	Color("b08258"), Color("8f6440"), Color("6f4b2e"), Color("523721"),
]

## Палитра глаз, ~6 цветов: радужка перекрашивается по насыщенности
## (белок не трогается), CharacterModel._eye_texture.
const EYE_COLORS: PackedColorArray = [
	Color("5a3a1e"), Color("37582f"), Color("6f7a84"),
	Color("4b7aa6"), Color("33507e"), Color("7a5c33"),
]

## Число байтов сетевой структуры (часть B3): по байту на индекс.
const NET_SIZE: int = 9

var gender: int = GENDER_MALE
var hair: int = 0
var top: int = 0
var legs: int = 0
var feet: int = 0
var hat: int = HAT_NONE
var hair_color: int = 0
var skin: int = 0
var eye_color: int = 0


## Допустимые причёски для пола.
static func hair_variants(for_gender: int) -> PackedInt32Array:
	return HAIRS_FEMALE if for_gender == GENDER_FEMALE else HAIRS_MALE


## Значения по умолчанию для пола (валидная комбинация).
static func default_for(for_gender: int) -> Appearance:
	var ap := Appearance.new()
	ap.gender = clampi(for_gender, 0, GENDERS - 1)
	ap.hair = 4 if ap.gender == GENDER_MALE else 0
	return ap


## Копия с исправленными индексами: диапазоны clamp, причёска заменяется
## на допустимую для пола. Правило применяет и хост к структуре из сети
## (раздел 10 SPEC), и редактор при загрузке user://.
func validated() -> Appearance:
	var out := duplicate()
	out.gender = clampi(gender, 0, GENDERS - 1)
	var variants := hair_variants(out.gender)
	var best: int = variants[0]
	var best_dist := 1 << 30
	for index: int in variants:
		var dist: int = absi(index - out.hair)
		if dist < best_dist:
			best = index
			best_dist = dist
	out.hair = best
	out.top = clampi(top, 0, OUTFITS.size() - 1)
	out.legs = clampi(legs, 0, OUTFITS.size() - 1)
	out.feet = clampi(feet, 0, OUTFITS.size() - 1)
	out.hat = clampi(hat, 0, HATS - 1)
	out.hair_color = clampi(hair_color, 0, HAIR_COLORS.size() - 1)
	out.skin = clampi(skin, 0, SKIN_COLORS.size() - 1)
	out.eye_color = clampi(eye_color, 0, EYE_COLORS.size() - 1)
	return out


## Независимая копия.
func duplicate() -> Appearance:
	var out := Appearance.new()
	out.gender = gender
	out.hair = hair
	out.top = top
	out.legs = legs
	out.feet = feet
	out.hat = hat
	out.hair_color = hair_color
	out.skin = skin
	out.eye_color = eye_color
	return out


## Случайная внешность (детерминированный RNG — RandomNumberGenerator
## с фиксированным seed, как требует CLAUDE.md для генерации).
static func random(rng: RandomNumberGenerator) -> Appearance:
	var ap := Appearance.new()
	ap.gender = rng.randi_range(0, GENDERS - 1)
	var variants := hair_variants(ap.gender)
	ap.hair = variants[rng.randi_range(0, variants.size() - 1)]
	ap.top = rng.randi_range(0, OUTFITS.size() - 1)
	ap.legs = rng.randi_range(0, OUTFITS.size() - 1)
	ap.feet = rng.randi_range(0, OUTFITS.size() - 1)
	ap.hat = rng.randi_range(0, HATS - 1)
	ap.hair_color = rng.randi_range(0, HAIR_COLORS.size() - 1)
	ap.skin = rng.randi_range(0, SKIN_COLORS.size() - 1)
	ap.eye_color = rng.randi_range(0, EYE_COLORS.size() - 1)
	return ap


func same(other: Appearance) -> bool:
	return gender == other.gender and hair == other.hair and top == other.top \
		and legs == other.legs and feet == other.feet and hat == other.hat \
		and hair_color == other.hair_color and skin == other.skin \
		and eye_color == other.eye_color


# --- Сеть (часть B3: компактная структура индексов) ---

## Внешность байтами — по байту на индекс, порядок фиксирован.
func to_bytes() -> PackedByteArray:
	return PackedByteArray([
		gender, hair, top, legs, feet, hat, hair_color, skin, eye_color,
	])


## Из байтов (без валидации — диапазоны проверяет хост отдельным
## вызовом validated(); обрезка по фактической длине).
static func from_bytes(bytes: PackedByteArray) -> Appearance:
	var ap := Appearance.new()
	if bytes.size() < NET_SIZE:
		return ap
	ap.gender = bytes[0]
	ap.hair = bytes[1]
	ap.top = bytes[2]
	ap.legs = bytes[3]
	ap.feet = bytes[4]
	ap.hat = bytes[5]
	ap.hair_color = bytes[6]
	ap.skin = bytes[7]
	ap.eye_color = bytes[8]
	return ap
