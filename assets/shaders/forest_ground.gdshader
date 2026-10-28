// Земля острова (П12 «Земля и вода»: полный PBR по тем же весам ForestGround).
// П14 1 «Масштаб и цвет»: у каждого слоя свой реальный размер тайла
// (tile_m_<слой>, 2–2.7 м по real-world size Poly Haven; прежний единый
// tile_m = 30 м растягивал сканы в 10–15 раз), против сетки повторов —
// второй крупный масштаб (macro_*) и разбивка тайлинга по ячейке тайла;
// тинты нейтральные ≈ белые (tint_mix ≈ 0.1 — цвет даёт фотоскан);
// бывший «детальный» масштаб нормалей убран (базовый тайл уже мелкий).
// Наследие П5.9/П5.13, что сохраняется: смешивание базы симплекс-шумом
// (пятнистость демо ez-tree), трипланар по мировой нормали рельефа
// (relief_normal), карта тона border_map и краевой toon-переход,
// wrap-Ламберт внутри сектора (wrap-Ламберт и toon-край убраны в П14 2.1 —
// стандартное PBR-освещение Godot). Меняет П12:
//   6 слоёв текстур с полным PBR (albedo + nor_gl + ORM, где ORM =
//   R: AO, G: Roughness, B: Height — tools/make_orm_textures.gd):
//     база-подстилка forest_ground_05 (s ≥ 0.5), трава leafy_grass (s < 0.5,
//     на SIMPLE не сэмплится — луга красит карта тона), скала rock_face_03
//     (w.r), грязь mud_forest (w.g), мох Moss001 (w.b), гравий rocky_trail
//     (w.a — тропа и Площадь);
//   height-blend: побеждает слой с выше картой высоты (softmax по
//   h_eff = вес + ORM.b × HEIGHT_TEX, мягкость BLEND_SHARP) — грязь утекает
//   между камнями, мох лезет поверх;
//   ROUGHNESS и AO — взвешенная сумма каналов ORM: П14 2 подаёт AO в
//   AO-выход движка (AO_LIGHT_AFFECT 0.5), а не умножением альбедо;
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
// Свет (П14 2.1): стандартный PBR Godot — кастомный light() с wrap-Ламбертом,
// toon-краем и своим GGX удалён; нормали, ROUGHNESS, AO и спекуляр луж —
// встроенные выходы шейдера.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert,
	specular_schlick_ggx;

// Уровень качества (GraphicsQuality.Tier): 0 SIMPLE, 1 NORMAL, 2 HIGH,
// 3 ULTRA. Ветвление по uniform — драйвер разворачивает дёшево.
uniform int quality = 2;
const int QUALITY_SIMPLE = 0;
const int QUALITY_HIGH = 2;

// Тинты слоёв (source_color, П14 1.3): нейтральные ≈ белые, без каналов
// > 1 — цвет даёт фотоскан; «мрачнее» — притемнением/насыщенностью.
uniform vec3 litter_tint : source_color = vec3(0.88, 0.86, 0.82);
uniform vec3 grass_tint : source_color = vec3(0.82, 0.88, 0.80);
uniform vec3 rock_tint : source_color = vec3(0.82, 0.83, 0.85);
uniform vec3 mud_tint : source_color = vec3(0.76, 0.70, 0.64);
uniform vec3 moss_tint : source_color = vec3(0.78, 0.88, 0.74);
uniform vec3 gravel_tint : source_color = vec3(0.84, 0.80, 0.74);
// Доля плоского тинта в цвете слоя: 0 — чистая карта, 1 — плоский цвет.
uniform float tint_mix = 0.10;

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
// Реальный размер тайла слоя, м на повтор (П14 1.1): по real-world size
// Poly Haven (forest_ground_05 — 2 м, leafy_grass — 2, rock_face_03 — 2.7,
// mud_forest — 2.3, rocky_trail — 2; Moss001 нет данных — ТЗ 2–3 м).
// Прежний единый tile_m = 30 растягивал фотосканы в 10–15 раз.
uniform float tile_m_litter = 2.0;
uniform float tile_m_grass = 2.0;
uniform float tile_m_rock = 2.7;
uniform float tile_m_mud = 2.3;
uniform float tile_m_moss = 2.0;
uniform float tile_m_gravel = 2.0;
// Второй крупный масштаб того же слоя (П14 1.2): от macro_near до
// macro_far albedo верхней плоскости подмешивается к тому же слою
// в macro_scale раз крупнее — вблизи зернистость скана, вдали нет
// сетки повторов (макро — только верхняя плоскость, склоны вдали
// закрывают нормали рельефа).
uniform float macro_scale = 5.0;
uniform float macro_near = 15.0;
uniform float macro_far = 40.0;
// Крупная вариация тона: масштаб в метрах и амплитуда (~10%).
const float TONE_VAR_SCALE = 70.0;
const float TONE_VAR_AMP = 0.10;

// Сила нормал-карт слоёв (П14 2.2): вблизи ≈ 1.3–1.6 (нормальная фактура
// фотоскана), к дали гаснет — дальние планы не мерцают.
uniform float normal_near = 1.5;
uniform float normal_far = 1.0;
const float NORMAL_FADE_START = 15.0;
const float NORMAL_FADE_END = 45.0;

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
// Спекуляр влажной земли и лужи (П14 2.1): стандартный PBR Godot —
// SPECULAR-выход, без своего GGX.
uniform float wet_specular = 0.2;
const float PUDDLE_SPEC = 0.5;

// Параллакс (SPEC 2.6; П13 1.9): HIGH/ULTRA, гаснет от parallax_near
// до parallax_far (HIGH — 10–15 м, ULTRA — 15–25, ставит ForestGround
// по уровню; раньше — константы 15/25). parallax_scale = 0 выключает
// параллакс на лету (панель замера F3).
uniform float parallax_scale = 0.06;
uniform float parallax_near = 15.0;
uniform float parallax_far = 25.0;

// AO (П14 2.3): канал R из ORM подаётся в AO-выход движка с умеренным
// AO_LIGHT_AFFECT (половинное влияние на прямой свет), а не умножением
// альбедо — нормали и AO читаются стандартным PBR.
const float AO_LIGHT_AFFECT_V = 0.5;
// Roughness SIMPLE (без ORM-канала — по цене прежней земли).
const float SIMPLE_ROUGH = 0.95;

// Карты покраски острова (256 × 256, пиксель = 1 м, край — clamp).
uniform sampler2D weight_map : filter_linear_mipmap_anisotropic;
uniform sampler2D border_map : source_color, filter_linear_mipmap_anisotropic;
// Карта честных нормалей рельефа (П5.9 переделка, П3): сглаженное поле из
// карты высот, кодировка n·0.5+0.5 (данные, не цвет).
uniform sampler2D relief_normal : filter_linear_mipmap_anisotropic;

varying vec3 world_pos;
// Вес лужи (weight_map.g ≥ PUDDLE_START): нужен и в vertex (для early
// гашения на SIMPLE), и в fragment (SPECULAR лужи).
varying float puddle_v;

// Кольцо детальной сетки (П14 3.1): включается материалом кольца
// (TerrainDetail.make_material); у чанков detail_ring = false и ветка
// не сэмплит карту высот. П15 9.1: высота кольца — бикубическая
// Catmull-Rom по height_tex с прижимом к треугольной высоте коллизии
// (та же формула, что у береговой полосы ShoreBand — стык без шва).
uniform bool detail_ring = false;
uniform sampler2D height_tex : filter_linear_mipmap_anisotropic;
uniform float ring_radius = 16.0;
// Прижим бикубики к коллизии, м (тот же лимит, что ShoreBand.TENSION_LIMIT).
const float TENSION_LIMIT = 0.03;
// П15-ДОП2, п. 4: релакс на крутых клетках берега — те же константы,
// что у ShoreBand (синхронизируется тестом): перепад углов клетки от
// WALK_DROP (предел проходимости walk_max_slope_deg 54°, tan(54°) ≈ 1.38
// на кваде 1×1 м) до RELAX_DROP плавно выключает прижим бикубики к
// диагонали чанка, а основу заменяет огибающей чанковых поверхностей —
// кольцо и полоса над крутым берегом не прорезают друг друга.
const float WALK_DROP = 1.4;
const float RELAX_DROP = 2.4;
const float RELAX_TENSION = 0.3;
const float SOFT_EPS = 0.02;
// Средние ORM.b слоёв для центрирования смещения (средняя высота кольца
// над чанками ≈ 0): a = litter, rock, mud; b = moss, gravel, grass.
uniform vec3 orm_mean_a = vec3(0.5, 0.5, 0.5);
uniform vec3 orm_mean_b = vec3(0.5, 0.5, 0.5);

// Амплитуды рельефа слоёв, м (SPEC П14 3.1/3.2 — те же числа, что
// TerrainDetail.AMP_*): подстилка/гравий ±3–5 см, грязь 8–10, скала 15;
// глубина POM во fragment — та же.
const float AMP_LITTER_C = 0.04;
const float AMP_ROCK_C = 0.15;
const float AMP_MUD_C = 0.09;
const float AMP_MOSS_C = 0.03;
const float AMP_GRAVEL_C = 0.05;
// Подъём кольца над чанками (мм) и полоса гашения смещения у кромки, м.
const float RING_LIFT_C = 0.004;
const float RING_EDGE_FADE = 1.5;

// Берег (П14 3.4): полоса мокрой земли над уровнем воды — та же отметка,
// что море и озеро (IslandGen.SEA_LEVEL).
uniform float shore_level = -0.15;
const float SHORE_BAND = 0.55;
const float SHORE_DARKEN = 0.62;

// POM (П14 3.2): шаги марша по доминирующему слою; 8 на HIGH (дефолт),
// 16 ставит ForestGround на ULTRA.
uniform float pom_steps = 8.0;

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
// cell_m = тайлу слоя — сетка повторов не читается, повороты приходятся
// на бесшовные стыки тайла.
vec2 tile_break(vec2 plane_m, float cell_m) {
	vec2 cell = floor(plane_m / cell_m);
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
// UV слоя = разбивка тайлинга (ячейка = тайл слоя) / тайл слоя.
vec3 layer_albedo(
	sampler2D tex, vec3 tri_w, float tile,
	vec2 top_m, vec2 plane_x_m, vec2 plane_z_m) {
	return (
		tri_w.y * texture(tex, tile_break(top_m, tile) / tile).rgb
		+ tri_w.x * texture(tex, tile_break(plane_x_m, tile) / tile).rgb
		+ tri_w.z * texture(tex, tile_break(plane_z_m, tile) / tile).rgb);
}

// Albedo слоя с макро-масштабом (П14 1.2): вдали верхняя плоскость
// подмешивает тот же слой в macro_scale раз крупнее (ячейка поворота —
// макротаил). macro_w уже включает вес верхней плоскости и дальность.
vec3 layer_color(
	sampler2D tex, vec3 tri_w, float tile, float macro_w,
	vec2 top_m, vec2 plane_x_m, vec2 plane_z_m) {
	vec3 col = layer_albedo(tex, tri_w, tile, top_m, plane_x_m, plane_z_m);
	if (macro_w > 0.002) {
		float macro_tile = tile * macro_scale;
		vec3 macro = texture(
			tex, tile_break(world_pos.xz, macro_tile) / macro_tile).rgb;
		col = mix(col, macro, macro_w);
	}
	return col;
}

// Возмущение нормали слоя в мировом базисе (компоненты карты (x, y) ложатся
// на касательные оси доминирующей плоскости) — та же схема, что у базы
// в принятом Лесе (П5.13). Бывший второй «детальный» масштаб убран: при
// реальном тайле 2 м базовая фактура уже мелкая (П14 1.1).
vec3 layer_perturb(
	sampler2D tex, vec3 tri_w,
	float sx, float sz, float tile,
	vec2 top_m, vec2 plane_x_m, vec2 plane_z_m) {
	vec2 nx = texture(tex, tile_break(plane_x_m, tile) / tile).rg * 2.0 - 1.0;
	vec2 ntop = texture(tex, tile_break(top_m, tile) / tile).rg * 2.0 - 1.0;
	vec2 nz = texture(tex, tile_break(plane_z_m, tile) / tile).rg * 2.0 - 1.0;
	return (
		tri_w.y * (ntop.x * vec3(1.0, 0.0, 0.0) + ntop.y * vec3(0.0, 0.0, 1.0))
		+ tri_w.x * (nx.x * vec3(0.0, 0.0, sx) + nx.y * vec3(0.0, 1.0, 0.0))
		+ tri_w.z * (nz.x * vec3(sz, 0.0, 0.0) + nz.y * vec3(0.0, 1.0, 0.0)));
}

// Смещение вершины кольца по высоте слоёв (П14 3.1): веса — карта
// weight_map (та же, что во fragment; база — подстилка, трава в кольце
// не выделена), высота слоя центрируется средним (orm_mean_*) — средняя
// высота кольца ≈ 0, ступни не проваливаются.
float ring_displacement(vec2 m) {
	vec4 w = textureLod(weight_map, (m + vec2(128.0)) / 256.0, 0.0);
	float w_base = clamp(1.0 - (w.r + w.g + w.b + w.a), 0.0, 1.0);
	float d = w_base * (textureLod(litter_orm,
		tile_break(m, tile_m_litter) / tile_m_litter, 0.0).b
		- orm_mean_a.x) * AMP_LITTER_C;
	if (w.r > LAYER_EPS) {
		d += w.r * (textureLod(rock_orm,
			tile_break(m, tile_m_rock) / tile_m_rock, 0.0).b
			- orm_mean_a.y) * AMP_ROCK_C;
	}
	if (w.g > LAYER_EPS) {
		d += w.g * (textureLod(mud_orm,
			tile_break(m, tile_m_mud) / tile_m_mud, 0.0).b
			- orm_mean_a.z) * AMP_MUD_C;
	}
	if (w.b > LAYER_EPS) {
		d += w.b * (textureLod(moss_orm,
			tile_break(m, tile_m_moss) / tile_m_moss, 0.0).b
			- orm_mean_b.x) * AMP_MOSS_C;
	}
	if (w.a > LAYER_EPS) {
		d += w.a * (textureLod(gravel_orm,
			tile_break(m, tile_m_gravel) / tile_m_gravel, 0.0).b
			- orm_mean_b.y) * AMP_GRAVEL_C;
	}
	return d;
}

// POM (П14 3.2): steep parallax по доминирующему слою — марш вдоль
// взгляда от поверхности вглубь карты высот слоя; глубина рельефа —
// амплитуда слоя (те же AMP_*), master — доля parallax_scale от полного
// (0 выключает панель F3). Возвращает смещение координат верхней
// плоскости, м.
vec2 pom_march(
	sampler2D orm, float tile, float amp, vec2 m2, vec2 dir_m, float master) {
	vec2 uv_m = m2;
	vec2 delta_m = -dir_m * (amp * master) / pom_steps;
	float delta_h = 1.0 / pom_steps;
	float ray_h = 1.0;
	for (int i = 0; i < 16; i++) {
		if (float(i) >= pom_steps) {
			break;
		}
		ray_h -= delta_h;
		uv_m += delta_m;
		float tex_h = textureLod(
			orm, tile_break(uv_m, tile) / tile, 0.0).b;
		if (tex_h >= ray_h) {
			break;
		}
	}
	return uv_m - m2;
}

// П15 9.1 + П15-ДОП2, п. 4: бикубическая высота кольца — Catmull-Rom
// 4×4 узла (16 сэмплов height_tex) с прижимом к треугольной высоте
// чанка (диагональ квадрата (x,z)–(x+1,z+1)); на крутых клетках
// (релакс) прижим ослабевает, а основа становится огибающей
// диагональной (печёные чанки) и билинейной (ближние чанки)
// поверхностей: кольцо скользит над чанками и береговой полосой без
// утопания и без ступеней коллизии. Формулы и константы — те же, что
// у ShoreBand (синхронизируется тестом).
float ring_node_h(vec2 node) {
	return textureLod(height_tex, (node + vec2(128.0)) / 256.0, 0.0).r;
}

float ring_catmull(float p0, float p1, float p2, float p3, float t) {
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t);
}

// Перепад клетки (max − min по 4 углам).
float ring_cell_drop(float a, float b, float c, float d) {
	return max(max(a, b), max(c, d)) - min(min(a, b), min(c, d));
}

float ring_ground_h(vec2 wxz, float edge_fade) {
	vec2 p = clamp(wxz, vec2(-126.5), vec2(126.5));
	vec2 base = floor(p);
	vec2 b1 = clamp(base, vec2(-127.0), vec2(126.0));
	float tx = clamp(p.x - b1.x, 0.0, 1.0);
	float tz = clamp(p.y - b1.y, 0.0, 1.0);
	// 16 узлов (b1−1 .. b1+2)²: бикубика и перепады клеток вокруг.
	float n00 = ring_node_h(vec2(b1.x - 1.0, b1.y - 1.0));
	float n10 = ring_node_h(vec2(b1.x, b1.y - 1.0));
	float n20 = ring_node_h(vec2(b1.x + 1.0, b1.y - 1.0));
	float n30 = ring_node_h(vec2(b1.x + 2.0, b1.y - 1.0));
	float n01 = ring_node_h(vec2(b1.x - 1.0, b1.y));
	float n11 = ring_node_h(vec2(b1.x, b1.y));
	float n21 = ring_node_h(vec2(b1.x + 1.0, b1.y));
	float n31 = ring_node_h(vec2(b1.x + 2.0, b1.y));
	float n02 = ring_node_h(vec2(b1.x - 1.0, b1.y + 1.0));
	float n12 = ring_node_h(vec2(b1.x, b1.y + 1.0));
	float n22 = ring_node_h(vec2(b1.x + 1.0, b1.y + 1.0));
	float n32 = ring_node_h(vec2(b1.x + 2.0, b1.y + 1.0));
	float n03 = ring_node_h(vec2(b1.x - 1.0, b1.y + 2.0));
	float n13 = ring_node_h(vec2(b1.x, b1.y + 2.0));
	float n23 = ring_node_h(vec2(b1.x + 1.0, b1.y + 2.0));
	float n33 = ring_node_h(vec2(b1.x + 2.0, b1.y + 2.0));
	float col0 = ring_catmull(n00, n10, n20, n30, tx);
	float col1 = ring_catmull(n01, n11, n21, n31, tx);
	float col2 = ring_catmull(n02, n12, n22, n32, tx);
	float col3 = ring_catmull(n03, n13, n23, n33, tx);
	float cubic = ring_catmull(col0, col1, col2, col3, tz);
	// Треугольная высота чанка (диагональ, как у печёных чанков) и
	// билинейная (ближние чанки 0.5 м) по углам клетки.
	float linear = tx >= tz
		? n11 + (n21 - n11) * tx + (n22 - n21) * tz
		: n11 + (n12 - n11) * tz + (n22 - n12) * tx;
	float bil = mix(mix(n11, n21, tx), mix(n12, n22, tx), tz);
	// Релакс (П15-ДОП2, п. 4): перепад содержащей клетки (её углы
	// n11..n22) — та же клетка и та же формула, что у береговой полосы
	// (ShoreBand.cell_relax): поверхности не расходятся; к краю кольца
	// релакс гасится edge_fade — у края прежняя формула, стык с чанками
	// без губы.
	float drop_cell = ring_cell_drop(n11, n21, n12, n22);
	float relax = smoothstep(WALK_DROP, RELAX_DROP, drop_cell) * edge_fade;
	// Прижим бикубики к чанковой высоте: лимит растёт с релаксом.
	float lim = mix(TENSION_LIMIT, RELAX_TENSION, relax);
	float k = clamp(abs(cubic - linear) / lim, 0.0, 1.0);
	float pinned = mix(cubic, linear, k);
	// Огибающая диагональной и билинейной поверхностей — сглаженный
	// max (C¹), не ниже ни одной; добавка не больше SOFT_EPS/2.
	float env = 0.5 * (linear + bil
		+ sqrt((linear - bil) * (linear - bil) + SOFT_EPS * SOFT_EPS));
	float base_h = mix(linear, env, relax) + 0.001;
	// Сглаженная положительная часть над основой — не ниже чанков.
	float over = pinned - base_h;
	float soft_over = 0.5 * (over + sqrt(over * over + SOFT_EPS * SOFT_EPS));
	return base_h + soft_over;
}

void vertex() {
	if (detail_ring) {
		// Кольцо: плоской вершине ставится бикубическая высота чанков
		// (height_tex, П15 9.1) + сантиметровый рельеф слоёв. Нода без
		// поворота, снап к камере делает IslandView; смещение гаснет
		// к кромке раньше подъёма — у края кольцо совпадает с печёной
		// поверхностью.
		vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		vec2 ring_c = vec2(MODEL_MATRIX[3][0], MODEL_MATRIX[3][2]);
		float ring_d = length(wp.xz - ring_c);
		float disp_fade = 1.0 - smoothstep(
			ring_radius - RING_EDGE_FADE, ring_radius, ring_d);
		float lift = RING_LIFT_C * (1.0 - smoothstep(
			ring_radius - 0.4, ring_radius, ring_d));
		// Релакс крутых клеток гасится к краю кольца вместе со
		// смещением (П15-ДОП2, п. 4): у края — прежняя формула.
		float ground_h = ring_ground_h(wp.xz, disp_fade);
		float target_y = ground_h + lift
			+ ring_displacement(wp.xz) * disp_fade;
		VERTEX.y += target_y - MODEL_MATRIX[3][1];
	}
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 sector_uv = (world_pos.xz + vec2(128.0)) / 256.0;
	// Вес лужи для спекуляра (П14 2.1): во fragment он считается так же
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

	// POM (П14 3.2, HIGH/ULTRA, гаснет к parallax_far): steep parallax
	// по доминирующему слою карты весов — марш вдоль взгляда вглубь
	// карты высот слоя (ORM.b), глубина — амплитуда слоя (те же AMP_*,
	// что у кольца детальной сетки: скала и колея глубже, подстилка
	// мелкая). parallax_scale — общий выключатель F3: доля от полной
	// глубины (0 — марша нет). Шаги pom_steps: 8 HIGH / 16 ULTRA.
	vec2 parallax_off = vec2(0.0);
	float dist_v = length(-VERTEX);
	if (quality >= QUALITY_HIGH) {
		float p_amt = (1.0 - smoothstep(parallax_near, parallax_far, dist_v))
			* step(0.05, tri_w.y);
		if (p_amt > 0.001 && parallax_scale > 0.0001) {
			vec3 wdir = normalize(
				(INV_VIEW_MATRIX * vec4(normalize(-VERTEX), 0.0)).xyz);
			// Направление на камеру в метрах верхней плоскости; марш
			// pom_march идёт в противоположную — от камеры вглубь.
			vec2 dir_m = -wdir.xz / max(abs(wdir.y), 0.2);
			// Доминирующий слой весов задаёт карту высот и амплитуду
			// марша (сэмплер нельзя в переменную — ветка на слой).
			float w_base0 = clamp(
				1.0 - (w.r + w.g + w.b + w.a), 0.0, 1.0);
			float max_w = max(max(w.r, w.g), max(w.b, w.a));
			float master = min(parallax_scale / 0.06, 1.0) * p_amt;
			if (w.r > w_base0 && w.r == max_w) {
				parallax_off = pom_march(rock_orm, tile_m_rock,
					AMP_ROCK_C, world_pos.xz, dir_m, master);
			} else if (w.g > w_base0 && w.g == max_w) {
				parallax_off = pom_march(mud_orm, tile_m_mud,
					AMP_MUD_C, world_pos.xz, dir_m, master);
			} else if (w.b > w_base0 && w.b == max_w) {
				parallax_off = pom_march(moss_orm, tile_m_moss,
					AMP_MOSS_C, world_pos.xz, dir_m, master);
			} else if (w.a > w_base0 && w.a == max_w) {
				parallax_off = pom_march(gravel_orm, tile_m_gravel,
					AMP_GRAVEL_C, world_pos.xz, dir_m, master);
			} else {
				parallax_off = pom_march(litter_orm, tile_m_litter,
					AMP_LITTER_C, world_pos.xz, dir_m, master);
			}
		}
	}

	// Плоскости трипланара в метрах (разбивку тайлинга делают выборки
	// каждого слоя со своим тайлом; параллакс — только верхней плоскости,
	// на склонах гасится весом p_amt).
	vec2 top_m = world_pos.xz + parallax_off;
	vec2 x_m = world_pos.zy;
	vec2 z_m = world_pos.xy;
	// Макро-масштаб (П14 1.2): вдали albedo верхней плоскости подмешивает
	// тот же слой крупнее — сетки повторов на дальних планах нет.
	float macro_w = smoothstep(macro_near, macro_far, dist_v) * tri_w.y;

	// Пятнистость базы (схема демо ground.js): вес подстилки s.
	float n = 0.5 + 0.5 * simplex2d(world_pos.xz / noise_scale);
	float s = smoothstep(patchiness - 0.1, patchiness + 0.1, n);
	bool with_grass = quality != QUALITY_SIMPLE;

	// --- База: подстилка (+ трава вне SIMPLE), ORM — верхняя плоскость ---
	vec3 litter_col = mix(
		layer_color(litter_tex, tri_w, tile_m_litter, macro_w, top_m, x_m, z_m),
		litter_tint, tint_mix);
	vec3 litter_orm_v = texture(
		litter_orm, tile_break(top_m, tile_m_litter) / tile_m_litter).rgb;
	vec3 grass_col = vec3(0.0);
	vec3 grass_orm_v = vec3(0.5, 0.9, 0.5);
	if (with_grass) {
		vec3 grass_map = layer_color(
			grass_tex, tri_w, tile_m_grass, macro_w, top_m, x_m, z_m);
		grass_col = mix(grass_map, grass_tint, tint_mix);
		grass_orm_v = texture(
			grass_orm, tile_break(top_m, tile_m_grass) / tile_m_grass).rgb;
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

	float sx = sign(relief_world.x);
	float sz = sign(relief_world.z);

	if (w_rock > LAYER_EPS) {
		col_rock = mix(
			layer_color(rock_tex, tri_w, tile_m_rock, macro_w, top_m, x_m, z_m),
			rock_tint, tint_mix);
		vec3 orm = texture(
			rock_orm, tile_break(top_m, tile_m_rock) / tile_m_rock).rgb;
		h_rock = orm.b;
		ao_rock = orm.r;
		rough_rock = orm.g;
		perturb_rock = layer_perturb(
			rock_normal, tri_w, sx, sz, tile_m_rock, top_m, x_m, z_m);
	}
	if (w_mud > LAYER_EPS) {
		col_mud = mix(
			layer_color(mud_tex, tri_w, tile_m_mud, macro_w, top_m, x_m, z_m),
			mud_tint, tint_mix);
		vec3 orm = texture(
			mud_orm, tile_break(top_m, tile_m_mud) / tile_m_mud).rgb;
		h_mud = orm.b;
		ao_mud = orm.r;
		rough_mud = orm.g;
		perturb_mud = layer_perturb(
			mud_normal, tri_w, sx, sz, tile_m_mud, top_m, x_m, z_m);
	}
	if (w_moss > LAYER_EPS) {
		col_moss = mix(
			layer_color(moss_tex, tri_w, tile_m_moss, macro_w, top_m, x_m, z_m),
			moss_tint, tint_mix);
		vec3 orm = texture(
			moss_orm, tile_break(top_m, tile_m_moss) / tile_m_moss).rgb;
		h_moss = orm.b;
		ao_moss = orm.r;
		rough_moss = orm.g;
		perturb_moss = layer_perturb(
			moss_normal, tri_w, sx, sz, tile_m_moss, top_m, x_m, z_m);
	}
	if (w_gravel > LAYER_EPS) {
		col_gravel = mix(
			layer_color(gravel_tex, tri_w, tile_m_gravel, macro_w, top_m, x_m, z_m),
			gravel_tint, tint_mix);
		vec3 orm = texture(
			gravel_orm, tile_break(top_m, tile_m_gravel) / tile_m_gravel).rgb;
		h_gravel = orm.b;
		ao_gravel = orm.r;
		rough_gravel = orm.g;
		perturb_gravel = layer_perturb(
			gravel_normal, tri_w, sx, sz, tile_m_gravel, top_m, x_m, z_m);
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

	// Мокрая полоса берега (П14 3.4): по высоте над уровнем воды
	// (shore_level — тот же уровень, что у воды), край без ломаной
	// грани — smoothstep-полоса от кромки. Ниже уровня воды полосы нет
	// (там воду рисует шейдер воды).
	float shore_w = (1.0 - smoothstep(
		0.03, SHORE_BAND, world_pos.y - shore_level))
		* step(0.0, world_pos.y - shore_level);
	albedo *= mix(1.0, SHORE_DARKEN, shore_w);

	// Край сектора: тонировка цветом соседней зоны, у границы вес 1 —
	// плоский цвет соседа.
	albedo = mix(albedo, border.rgb, border.a);
	ALBEDO = albedo;	// Roughness/AO: взвешенные суммы каналов ORM (SIMPLE — без карт).
	float rough = 0.0;
	float ao = 1.0;
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
	}
	// Прибрежный песок у кромки воды темнее и глаже (мокрая полоса).
	ROUGHNESS = mix(ROUGHNESS, 0.32, shore_w * 0.8);
	// П14 2.3: AO из ORM — в AO-выход движка с умеренным влиянием на
	// прямой свет (не умножением альбеда); на SIMPLE без ORM ao = 1.
	AO = ao;
	AO_LIGHT_AFFECT = AO_LIGHT_AFFECT_V;
	// П14 2.1: блеск мокрой земли и луж — стандартный PBR (SPECULAR),
	// у ровной лужи ярче.
	SPECULAR = mix(wet_specular, PUDDLE_SPEC, puddle);

	// Нормаль: база + взвешенные возмущения слоёв в мировом базисе.
	vec3 perturb_base = layer_perturb(
		litter_normal, tri_w, sx, sz, tile_m_litter, top_m, x_m, z_m);
	vec3 perturb_grass = vec3(0.0);
	if (with_grass) {
		perturb_grass = layer_perturb(
			grass_normal, tri_w, sx, sz, tile_m_grass, top_m, x_m, z_m);
	}
	vec3 perturb = m_base * mix(perturb_grass, perturb_base, with_grass ? s : 1.0)
		+ m_rock * perturb_rock
		+ m_mud * perturb_mud
		+ m_moss * perturb_moss
		+ m_gravel * perturb_gravel;
	// П14 2.2: whiteout-смешивание с нормалью рельефа — от возмущения
	// берётся касательная часть (продольная вычитается), базовая нормаль
	// не «проседает»; сила вблизи 1.5, к дали гаснет. Toon-переход на
	// плоскую грань у края сектора убран (П14 2.1) — край тонирован
	// цветом border_map, нормали честные по всему острову.
	vec3 tangent_perturb = perturb
		- relief_world * dot(relief_world, perturb);
	float normal_s = mix(normal_far, normal_near,
		1.0 - smoothstep(NORMAL_FADE_START, NORMAL_FADE_END, dist_v));
	vec3 ground_world = normalize(
		relief_world + tangent_perturb * normal_s);
	NORMAL = normalize((VIEW_MATRIX * vec4(ground_world, 0.0)).xyz);
}
