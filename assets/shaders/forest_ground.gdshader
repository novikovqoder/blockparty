// Земля острова (П12 «Земля и вода»: полный PBR по тем же весам ForestGround).
// Наследие П5.9/П5.13, что сохраняется: смешивание базы симплекс-шумом
// (пятнистость демо ez-tree), трипланар по мировой нормали рельефа
// (relief_normal), карта тона border_map и краевой toon-переход,
// wrap-Ламберт внутри сектора. Меняет П12:
//   6 слоёв текстур с полным PBR (albedo + nor_gl + ORM, где ORM =
//   R: AO, G: Roughness, B: Height — tools/make_orm_textures.gd):
//     база-подстилка forest_ground_05 (s ≥ 0.5), трава leafy_grass (s < 0.5,
//     на SIMPLE не сэмплится — луга красит карта тона), скала rock_face_03
//     (w.r), грязь mud_forest (w.g), мох Moss001 (w.b), гравий rocky_trail
//     (w.a — тропа и Площадь);
//   height-blend: побеждает слой с выше картой высоты (softmax по
//   h_eff = вес + ORM.b × HEIGHT_TEX, мягкость BLEND_SHARP) — грязь утекает
//   между камнями, мох лезет поверх;
//   ROUGHNESS и AO — взвешенная сумма каналов ORM (AO — умножением ALBEDO
//   с силой AO_MIX, эквивалент AO_LIGHT_AFFECT: в кастомном light() модели
//   встроенного AO-выхода Godot 4 нет);
//   разбивка тайлинга: поворот UV на 0/90/180/270° и зеркало по ячейке
//   CELL_M метров (без интерполяции — это выбор преобразования, а не
//   решётчатый value-noise) + крупная вариация тона симплексом
//   TONE_VAR_SCALE метров (SPEC 2.4: с высоты не видно сетки);
//   мокрая земля в низинах (вес w.g: темнее + roughness ниже) и лужи при
//   w.g ≥ PUDDLE_START (roughness ≈ 0.05, плавный край) — те же значения,
//   что ForestGround.PUDDLE_WET, всплески FootFx совпадают с лужами;
//   параллакс по высоте ORM.b — только на HIGH/ULTRA и до ~25 м с затуханием
//   (SPEC 2.6); SIMPLE: без AO-канала, луж, параллакса и слоя травы.
// Тинты слоёв — плоские цвета поверх карт (mix с TINT_MIX): яркость и тон
// каждого слоя подбирает владелец (константы в forest_terrain.gd).
// Текстуры — CC0: polyhaven (forest_ground_05, leafy_grass, rock_face_03,
// mud_forest, rocky_trail), ambientcg (Moss001); ORM собирает скрипт.
// Свет: внутри — wrap-Ламберт, у края — toon-модель соседних low-poly
// чанков; влажная земля и лужи блещут GGX-спекуляром (вес лужи считает
// vertex по весу влаги — light() видит только varyings).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert,
	specular_schlick_ggx;

// Уровень качества (GraphicsQuality.Tier): 0 SIMPLE, 1 NORMAL, 2 HIGH,
// 3 ULTRA. Ветвление по uniform — драйвер разворачивает дёшево.
uniform int quality = 2;
const int QUALITY_SIMPLE = 0;
const int QUALITY_HIGH = 2;

// Тинты слоёв (source_color): плоский цвет миксуется с картой (TINT_MIX).
uniform vec3 litter_tint : source_color = vec3(0.83, 0.84, 1.07);
uniform vec3 grass_tint : source_color = vec3(0.96, 0.76, 1.08);
uniform vec3 rock_tint : source_color = vec3(0.53, 0.54, 0.55);
uniform vec3 mud_tint : source_color = vec3(0.31, 0.26, 0.20);
uniform vec3 moss_tint : source_color = vec3(0.33, 0.44, 0.24);
uniform vec3 gravel_tint : source_color = vec3(0.61, 0.50, 0.36);
// Доля плоского тинта в цвете слоя: 0 — чистая карта, 1 — плоский цвет.
uniform float tint_mix = 0.35;

// Слои земли: albedo (source_color), нормаль и ORM (данные — без
// source_color; ORM: R AO, G Roughness, B Height).
uniform sampler2D litter_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D litter_normal : filter_linear_mipmap_anisotropic;
uniform sampler2D litter_orm : filter_linear_mipmap_anisotropic;
uniform sampler2D grass_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D grass_normal : filter_linear_mipmap_anisotropic;
uniform sampler2D grass_orm : filter_linear_mipmap_anisotropic;
uniform sampler2D rock_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D rock_normal : filter_linear_mipmap_anisotropic;
uniform sampler2D rock_orm : filter_linear_mipmap_anisotropic;
uniform sampler2D mud_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D mud_normal : filter_linear_mipmap_anisotropic;
uniform sampler2D mud_orm : filter_linear_mipmap_anisotropic;
uniform sampler2D moss_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D moss_normal : filter_linear_mipmap_anisotropic;
uniform sampler2D moss_orm : filter_linear_mipmap_anisotropic;
uniform sampler2D gravel_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D gravel_normal : filter_linear_mipmap_anisotropic;
uniform sampler2D gravel_orm : filter_linear_mipmap_anisotropic;

// Пятнистость базы — параметры демо ez-tree (GrassOptions: scale 100,
// patchiness 0.7): n = 0.5 + 0.5 * simplex2d(world.xz / noise_scale),
// s = smoothstep(patchiness ± 0.1) — вес подстилки против травы.
uniform float noise_scale = 100.0;
uniform float patchiness = 0.7;
// Повтор текстуры, м на тайл (демо: uv / 30).
uniform float tile_m = 30.0;
// Разбивка тайлинга (SPEC 2.4): ячейка поворота UV. Ячейка = тайл —
// поворот происходит на бесшовных стыках тайла.
const float CELL_M = 30.0;
// Крупная вариация тона: масштаб в метрах и амплитуда (~10%).
const float TONE_VAR_SCALE = 70.0;
const float TONE_VAR_AMP = 0.10;

// Детальная нормаль грунта (наследие П1): второй мелкий масштаб карты
// подстилки, вблизи земля читается зернистой, к дальним планам гаснет.
uniform float detail_tile_m = 6.0;
uniform float detail_fade_start = 45.0;
uniform float detail_fade_end = 90.0;
uniform float normal_strength = 1.0;

// Height-blend (SPEC 2.2): вклад карты высоты в эффективную высоту слоя
// и резкость softmax (больше — резче граница победителя).
const float HEIGHT_TEX = 0.35;
const float BLEND_SHARP = 6.0;
// Вес слоя ниже порога — слой не сэмплится вовсе (веса почти не
// пересекаются, на поляне читается только подстилка).
const float LAYER_EPS = 0.004;

// Мокрая земля и лужи (SPEC 2.5): темнее, roughness ниже; лужа при
// w.g ≥ PUDDLE_START (то же значение, что ForestGround.PUDDLE_WET —
// совпадает со всплесками FootFx).
uniform float wet_darken = 0.65;
uniform float wet_rough_factor = 0.55;
const float PUDDLE_START = 0.9;
const float PUDDLE_ROUGH = 0.05;
// Спекуляр влажной земли и лужи (диэлектрик F ≈ 0.04, GGX в light()).
uniform float wet_specular = 0.03;
const float PUDDLE_SPEC = 0.22;

// Параллакс (SPEC 2.6): HIGH/ULTRA, до PARALLAX_FAR м с затуханием.
uniform float parallax_scale = 0.06;
const float PARALLAX_NEAR = 15.0;
const float PARALLAX_FAR = 25.0;

// AO-канал: вклад в ALBEDO (в кастомном light() нет встроенного AO-выхода,
// поэтому эквивалент AO_LIGHT_AFFECT — доля затемнения альбедо).
const float AO_MIX = 0.5;
// Roughness SIMPLE (без ORM-канала — по цене прежней земли).
const float SIMPLE_ROUGH = 0.95;

// Карты покраски острова (256 × 256, пиксель = 1 м, край — clamp).
uniform sampler2D weight_map : filter_linear_mipmap_anisotropic;
uniform sampler2D border_map : source_color, filter_linear_mipmap_anisotropic;
// Карта честных нормалей рельефа (П5.9 переделка, П3): сглаженное поле из
// карты высот, кодировка n·0.5+0.5 (данные, не цвет).
uniform sampler2D relief_normal : filter_linear_mipmap_anisotropic;

// Тон теневой стороны граней — тот же, что дефолт uniform shadow_tint
// шейдера lowpoly (соседние чанки): у края Лес считается светом соседа.
const vec3 SHADOW_TINT = vec3(0.82, 0.87, 0.98);

varying vec3 world_pos;
// Вес края сектора (border_map.a) и вес влаги (weight_map.g) — оба нужны
// в light(), а туда из fragment() varyings не передаются.
varying float edge_w;
varying float puddle_v;

// Симплекс-шум 2D (Ian McEwan / Ashima Arts, публичный webgl-noise) —
// тот же, что в шейдере земли демо.
vec3 mod289(vec3 x) {
	return x - floor(x * (1.0 / 289.0)) * 289.0;
}
vec2 mod289(vec2 x) {
	return x - floor(x * (1.0 / 289.0)) * 289.0;
}
vec3 permute(vec3 x) {
	return mod289(((x * 34.0) + 1.0) * x);
}
float simplex2d(vec2 v) {
	const vec4 C = vec4(
		0.211324865405187, 0.366025403784439,
		-0.577350269189626, 0.024390243902439);
	vec2 i = floor(v + dot(v, C.yy));
	vec2 x0 = v - i + dot(i, C.xx);
	vec2 i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
	vec4 x12 = x0.xyxy + C.xxzz;
	x12.xy -= i1;

	i = mod289(i);
	vec3 p = permute(permute(i.y + vec3(0.0, i1.y, 1.0))
		+ i.x + vec3(0.0, i1.x, 1.0));

	vec3 m = max(0.5 - vec3(dot(x0, x0), dot(x12.xy, x12.xy), dot(x12.zw, x12.zw)), 0.0);
	m = m * m;
	m = m * m;

	vec3 x = 2.0 * fract(p * C.www) - 1.0;
	vec3 h = abs(x) - 0.5;
	vec3 ox = floor(x + 0.5);
	vec3 a0 = x - ox;

	m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);

	vec3 g;
	g.x = a0.x * x0.x + h.x * x0.y;
	g.yz = a0.yz * x12.xz + h.yz * x12.yw;
	return 130.0 * dot(m, g);
}

// Псевдослучай по целочисленной ячейке (без интерполяции): выбор
// поворота UV и зеркала в разбивке тайлинга. Это не решётчатый
// value-noise (нет билинейного сглаживания — нет «полос» из аудита П5.9),
// внутри ячейки UV непрерывен.
float cell_hash(vec2 cell) {
	vec3 p3 = fract(vec3(dot(cell, vec2(127.1, 311.7)),
		dot(cell, vec2(269.5, 183.3)), 71.7) * 0.013);
	p3 += dot(p3, p3.yzx + 19.19);
	return fract((p3.x + p3.y) * p3.z);
}

// Разбивка тайлинга (SPEC 2.4): координаты плоскости в метрах
// поворачиваются на 0/90/180/270° и зеркалятся по случайной ячейке
// CELL_M = тайлу — сетка повторов основного слоя не читается.
vec2 tile_break(vec2 plane_m) {
	vec2 cell = floor(plane_m / CELL_M);
	float r1 = cell_hash(cell);
	float r2 = cell_hash(cell + vec2(-37.7, 11.3));
	vec2 uv = plane_m;
	if (r1 >= 0.75) {
		uv = vec2(-uv.y, uv.x);
	} else if (r1 >= 0.5) {
		uv = vec2(-uv.x, -uv.y);
	} else if (r1 >= 0.25) {
		uv = vec2(uv.y, -uv.x);
	}
	if (r2 >= 0.5) {
		uv.x = -uv.x;
	}
	return uv;
}

// Трипланарная выборка albedo слоя по трём плоскостям (мировые zy, xz, xy
// с весами tri_w = x zy-плоскость, y xz-плоскость (верх), z xy-плоскость).
vec3 layer_albedo(sampler2D tex, vec3 tri_w, vec2 uv_x, vec2 uv_top, vec2 uv_z) {
	return (
		tri_w.y * texture(tex, uv_top).rgb
		+ tri_w.x * texture(tex, uv_x).rgb
		+ tri_w.z * texture(tex, uv_z).rgb);
}

// Возмущение нормали слоя в мировом базисе (компоненты карты (x, y) ложатся
// на касательные оси доминирующей плоскости) — та же схема, что у базы
// в принятом Лесе (П5.13, П1), по два масштаба: базовый тайл + детальный.
vec3 layer_perturb(
	sampler2D tex, vec3 tri_w, float detail_w,
	float sx, float sz,
	vec2 uv_x, vec2 uv_top, vec2 uv_z,
	vec2 duv_x, vec2 duv_top, vec2 duv_z) {
	vec2 nx = texture(tex, uv_x).rg * 2.0 - 1.0
		+ (texture(tex, duv_x).rg * 2.0 - 1.0) * detail_w;
	vec2 ntop = texture(tex, uv_top).rg * 2.0 - 1.0
		+ (texture(tex, duv_top).rg * 2.0 - 1.0) * detail_w;
	vec2 nz = texture(tex, uv_z).rg * 2.0 - 1.0
		+ (texture(tex, duv_z).rg * 2.0 - 1.0) * detail_w;
	return (
		tri_w.y * (ntop.x * vec3(1.0, 0.0, 0.0) + ntop.y * vec3(0.0, 0.0, 1.0))
		+ tri_w.x * (nx.x * vec3(0.0, 0.0, sx) + nx.y * vec3(0.0, 1.0, 0.0))
		+ tri_w.z * (nz.x * vec3(sz, 0.0, 0.0) + nz.y * vec3(0.0, 1.0, 0.0)));
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 sector_uv = (world_pos.xz + vec2(128.0)) / 256.0;
	edge_w = textureLod(border_map, sector_uv, 0.0).a;
	// Вес лужи для спекуляра light(): во fragment он считается так же
	// (smoothstep от w.g ≥ PUDDLE_START), на SIMPLE луж нет.
	float wet = textureLod(weight_map, sector_uv, 0.0).g;
	puddle_v = quality == QUALITY_SIMPLE
		? 0.0
		: smoothstep(PUDDLE_START, 1.0, wet);
}

void fragment() {
	vec2 sector_uv = (world_pos.xz + vec2(128.0)) / 256.0;
	vec4 w = texture(weight_map, sector_uv);
	vec4 border = texture(border_map, sector_uv);

	// Нормаль рельефа из карты высот — основа и для трипланарных весов,
	// и для нормалей слоёв: сглаженное поле, одинаковое на всех уровнях
	// тесселяции.
	vec3 relief_world = normalize(texture(relief_normal, sector_uv).xyz * 2.0 - 1.0);
	vec3 tri_w = pow(abs(relief_world), vec3(4.0));
	tri_w /= (tri_w.x + tri_w.y + tri_w.z);

	// Параллакс (HIGH/ULTRA, до 25 м с затуханием): смещение координат
	// верхней плоскости по высоте подстилки (ORM.b) против взгляда.
	// ORM читается до основных сэмплов — один лишний фетч только вблизи.
	vec2 parallax_off = vec2(0.0);
	if (quality >= QUALITY_HIGH) {
		float dist = length(-VERTEX);
		float p_amt = (1.0 - smoothstep(PARALLAX_NEAR, PARALLAX_FAR, dist))
			* step(0.05, tri_w.y);
		if (p_amt > 0.001) {
			vec3 wdir = normalize(
				(INV_VIEW_MATRIX * vec4(normalize(-VERTEX), 0.0)).xyz);
			float h0 = texture(litter_orm, world_pos.xz / tile_m).b;
			parallax_off = wdir.xz / max(abs(wdir.y), 0.2)
				* (h0 - 0.5) * parallax_scale * p_amt;
		}
	}

	// Координаты трёх плоскостей с разбивкой тайлинга и параллаксом
	// (параллакс — только верхней плоскости, на склонах гасится весом).
	vec2 top_m = tile_break(world_pos.xz + parallax_off);
	vec2 x_m = tile_break(world_pos.zy);
	vec2 z_m = tile_break(world_pos.xy);
	vec2 uv_top = top_m / tile_m;
	vec2 uv_x = x_m / tile_m;
	vec2 uv_z = z_m / tile_m;
	vec2 duv_top = top_m / detail_tile_m;
	vec2 duv_x = x_m / detail_tile_m;
	vec2 duv_z = z_m / detail_tile_m;

	// Пятнистость базы (схема демо ground.js): вес подстилки s.
	float n = 0.5 + 0.5 * simplex2d(world_pos.xz / noise_scale);
	float s = smoothstep(patchiness - 0.1, patchiness + 0.1, n);
	bool with_grass = quality != QUALITY_SIMPLE;

	// --- База: подстилка (+ трава вне SIMPLE), ORM — верхняя плоскость ---
	vec3 litter_col = mix(
		layer_albedo(litter_tex, tri_w, uv_x, uv_top, uv_z), litter_tint, tint_mix);
	vec3 litter_orm_v = texture(litter_orm, uv_top).rgb;
	vec3 grass_col = vec3(0.0);
	vec3 grass_orm_v = vec3(0.5, 0.9, 0.5);
	if (with_grass) {
		vec3 grass_map = layer_albedo(grass_tex, tri_w, uv_x, uv_top, uv_z);
		grass_col = mix(grass_map, grass_tint, tint_mix);
		grass_orm_v = texture(grass_orm, uv_top).rgb;
	}
	vec3 base_orm_v = mix(grass_orm_v, litter_orm_v, with_grass ? s : 1.0);
	vec3 base_col = mix(grass_col, litter_col, with_grass ? s : 1.0);

	// --- Весы слоёв и height-blend (SPEC 2.2) ---
	// Участники: база (остаточный вес), скала w.r, грязь w.g, мох w.b,
	// гравий w.a. Эффективная высота = вес + карта высоты × HEIGHT_TEX;
	// softmax с резкостью BLEND_SHARP переносит долю на слой с выше
	// картой — на границе пятен решает текстура, крупная форма весов
	// сохраняется.
	float total = clamp(w.r + w.g + w.b + w.a, 0.0, 1.0);
	float w_base = 1.0 - total;
	float w_rock = w.r;
	float w_mud = w.g;
	float w_moss = w.b;
	float w_gravel = w.a;
	// ORM верхних плоскостей слоёв (данные; на весах почти не пересекаются,
	// сэмплы только у включённых слоёв).
	float h_rock = 0.0;
	float h_mud = 0.0;
	float h_moss = 0.0;
	float h_gravel = 0.0;
	vec3 col_rock = vec3(0.0);
	vec3 col_mud = vec3(0.0);
	vec3 col_moss = vec3(0.0);
	vec3 col_gravel = vec3(0.0);
	vec3 perturb_rock = vec3(0.0);
	vec3 perturb_mud = vec3(0.0);
	vec3 perturb_moss = vec3(0.0);
	vec3 perturb_gravel = vec3(0.0);
	float ao_rock = 1.0;
	float ao_mud = 1.0;
	float ao_moss = 1.0;
	float ao_gravel = 1.0;
	float rough_rock = 1.0;
	float rough_mud = 1.0;
	float rough_moss = 1.0;
	float rough_gravel = 1.0;

	// Детальный масштаб нормалей гаснет к дальним планам (наследие П1).
	float detail_w = 0.55 * (1.0 - smoothstep(
		detail_fade_start, detail_fade_end, length(-VERTEX)));
	float sx = sign(relief_world.x);
	float sz = sign(relief_world.z);

	if (w_rock > LAYER_EPS) {
		col_rock = mix(
			layer_albedo(rock_tex, tri_w, uv_x, uv_top, uv_z),
			rock_tint, tint_mix);
		vec3 orm = texture(rock_orm, uv_top).rgb;
		h_rock = orm.b;
		ao_rock = orm.r;
		rough_rock = orm.g;
		perturb_rock = layer_perturb(
			rock_normal, tri_w, detail_w, sx, sz,
			uv_x, uv_top, uv_z, duv_x, duv_top, duv_z);
	}
	if (w_mud > LAYER_EPS) {
		col_mud = mix(
			layer_albedo(mud_tex, tri_w, uv_x, uv_top, uv_z),
			mud_tint, tint_mix);
		vec3 orm = texture(mud_orm, uv_top).rgb;
		h_mud = orm.b;
		ao_mud = orm.r;
		rough_mud = orm.g;
		perturb_mud = layer_perturb(
			mud_normal, tri_w, detail_w, sx, sz,
			uv_x, uv_top, uv_z, duv_x, duv_top, duv_z);
	}
	if (w_moss > LAYER_EPS) {
		col_moss = mix(
			layer_albedo(moss_tex, tri_w, uv_x, uv_top, uv_z),
			moss_tint, tint_mix);
		vec3 orm = texture(moss_orm, uv_top).rgb;
		h_moss = orm.b;
		ao_moss = orm.r;
		rough_moss = orm.g;
		perturb_moss = layer_perturb(
			moss_normal, tri_w, detail_w, sx, sz,
			uv_x, uv_top, uv_z, duv_x, duv_top, duv_z);
	}
	if (w_gravel > LAYER_EPS) {
		col_gravel = mix(
			layer_albedo(gravel_tex, tri_w, uv_x, uv_top, uv_z),
			gravel_tint, tint_mix);
		vec3 orm = texture(gravel_orm, uv_top).rgb;
		h_gravel = orm.b;
		ao_gravel = orm.r;
		rough_gravel = orm.g;
		perturb_gravel = layer_perturb(
			gravel_normal, tri_w, detail_w, sx, sz,
			uv_x, uv_top, uv_z, duv_x, duv_top, duv_z);
	}

	// Softmax по эффективным высотам: w' = w · exp(h_eff · k) / Σ.
	// Экспоненты считаются только у слоёв с весом (иначе вклад 0).
	float k = BLEND_SHARP;
	float e_base = w_base * exp((w_base + base_orm_v.b * HEIGHT_TEX) * k);
	float e_rock = w_rock * exp((w_rock + h_rock * HEIGHT_TEX) * k);
	float e_mud = w_mud * exp((w_mud + h_mud * HEIGHT_TEX) * k);
	float e_moss = w_moss * exp((w_moss + h_moss * HEIGHT_TEX) * k);
	float e_gravel = w_gravel * exp((w_gravel + h_gravel * HEIGHT_TEX) * k);
	float e_sum = e_base + e_rock + e_mud + e_moss + e_gravel;
	float m_base = e_base / e_sum;
	float m_rock = e_rock / e_sum;
	float m_mud = e_mud / e_sum;
	float m_moss = e_moss / e_sum;
	float m_gravel = e_gravel / e_sum;

	vec3 albedo = m_base * base_col
		+ m_rock * col_rock
		+ m_mud * col_mud
		+ m_moss * col_moss
		+ m_gravel * col_gravel;

	// Крупная вариация тона (SPEC 2.4): с высоты земля не «сетка».
	float tone_var = 1.0 + (simplex2d(world_pos.xz / TONE_VAR_SCALE)) * TONE_VAR_AMP;
	albedo *= tone_var;

	// Мокрая земля и лужи (SPEC 2.5): низины темнее и глаже, самые
	// низкие точки — почти зеркало (roughness ≈ 0.05, плавный край).
	float wet = clamp(w.g, 0.0, 1.0);
	float puddle = puddle_v;
	albedo *= mix(1.0, wet_darken, wet);
	albedo *= mix(1.0, wet_darken, puddle * 0.5);

	// Край сектора: тонировка цветом соседней зоны, у границы вес 1 —
	// плоский цвет соседа.
	albedo = mix(albedo, border.rgb, border.a);
	ALBEDO = albedo;

	// Roughness/AO: взвешенные суммы каналов ORM (SIMPLE — без карт).
	float rough = 0.0;
	float ao = 0.0;
	if (quality == QUALITY_SIMPLE) {
		ROUGHNESS = mix(SIMPLE_ROUGH, SIMPLE_ROUGH * wet_rough_factor, wet);
	} else {
		rough = m_base * base_orm_v.g
			+ m_rock * rough_rock
			+ m_mud * rough_mud
			+ m_moss * rough_moss
			+ m_gravel * rough_gravel;
		ao = m_base * base_orm_v.r
			+ m_rock * ao_rock
			+ m_mud * ao_mud
			+ m_moss * ao_moss
			+ m_gravel * ao_gravel;
		rough = mix(rough, rough * wet_rough_factor, wet);
		rough = mix(rough, PUDDLE_ROUGH, puddle);
		ROUGHNESS = mix(rough, SIMPLE_ROUGH, border.a);
		// AO встроен в альбедо (AO_MIX ~ AO_LIGHT_AFFECT, см. шапку);
		// у края сектора — плоский цвет соседа без AO.
		ALBEDO *= mix(mix(1.0, ao, AO_MIX), 1.0, border.a);
	}

	// Нормаль: база + взвешенные возмущения слоёв в мировом базисе.
	vec3 perturb_base = layer_perturb(
		litter_normal, tri_w, detail_w, sx, sz,
		uv_x, uv_top, uv_z, duv_x, duv_top, duv_z);
	vec3 perturb_grass = vec3(0.0);
	if (with_grass) {
		perturb_grass = layer_perturb(
			grass_normal, tri_w, detail_w, sx, sz,
			uv_x, uv_top, uv_z, duv_x, duv_top, duv_z);
	}
	vec3 perturb = m_base * mix(perturb_grass, perturb_base, with_grass ? s : 1.0)
		+ m_rock * perturb_rock
		+ m_mud * perturb_mud
		+ m_moss * perturb_moss
		+ m_gravel * perturb_gravel;
	vec3 ground_world = normalize(relief_world + perturb * normal_strength * (1.0 - edge_w));
	vec3 flat_n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	vec3 ground_view = normalize((VIEW_MATRIX * vec4(ground_world, 0.0)).xyz);
	NORMAL = normalize(mix(ground_view, flat_n, edge_w));
}

// Прямой свет: внутри сектора — мягкий wrap-Ламберт, к краю — в точности
// та же двухступенчатая toon-модель, что в light() шейдера lowpoly.
void light() {
	float ndl = dot(NORMAL, LIGHT);
	float wrap = 0.35;
	float lambert = clamp((ndl + wrap) / (1.0 + wrap), 0.0, 1.0);
	vec3 wrap_diff = LIGHT_COLOR * ATTENUATION * ALBEDO * lambert;
	float step1 = smoothstep(0.0, 0.35, ndl);
	float step2 = smoothstep(0.35, 0.75, ndl);
	float shade = 0.35 * step1 + 0.65 * step2;
	vec3 toon = LIGHT_COLOR * ATTENUATION
		* mix(ALBEDO * SHADOW_TINT, ALBEDO, shade) * shade;
	DIFFUSE_LIGHT += mix(wrap_diff, toon, edge_w);
	// Влажная земля и лужи блещут (D-член GGX, диэлектрик F ≈ 0.04);
	// сила растёт с весом лужи (varying из vertex), у соседа гасится.
	vec3 half_v = normalize(LIGHT + VIEW);
	float ndh = max(dot(NORMAL, half_v), 0.0);
	float a2 = ROUGHNESS * ROUGHNESS;
	a2 *= a2;
	float d_ggx = a2 / (3.14159 * pow(ndh * ndh * (a2 - 1.0) + 1.0, 2.0));
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * d_ggx
		* mix(wet_specular, PUDDLE_SPEC, puddle_v) * (1.0 - edge_w);
}
