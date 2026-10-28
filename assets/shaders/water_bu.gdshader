// Вода Born Unblessed (SPEC П14 4, П15 — третья итерация): свой шейдер
// вместо Boujie — текстур аддона нет вовсе (пена и рябь процедурные).
// П15-ДОП «вода по туториалу» (gameidea.org, локальная копия в
// docs/ground_water3/TUTORIAL_gameidea_water.html): волны sea_octave —
// октавы value-шума, острые гребни и плоские впадины (Герстнер убран):
// 3 октавы на геометрию в vertex(), 4-5 на нормаль во fragment();
// шаг конечных разностей растёт с расстоянием, вдали нормаль плавно
// переходит к геометрической. Полная версия для HIGH/ULTRA: экранная
// текстура + буфер глубины дают толщину воды под пикселем → поглощение
// Бера ПО КАНАЛАМ (красный гаснет первым) и объёмный цвет (П15-ДОП
// блок 3: дно тонируется им, apparent_seabed туториала), преломление —
// смещение выборки экрана по нормали волн с маской мелководья
// ref_depth_mask (на сверхмелком смещения нет) и проверкой глубины
// выборки; каустика — произведение двух встречно прокручивающихся
// слоёв шума (туториал sample1 · sample2), процедурная, без текстуры.
// Композит собирается вручную и пишется в EMISSION (один альфа-канал
// блендинга не передаст поканальное поглощение; ALBEDO = 0 гасит
// диффуз — исключение П15 4: пена несёт ALBEDO и освещается светом
// сцены). П15 3: отражение неба — движковое (IBL radiance Sky3D с
// френелем F0 ≈ 0.02), ручного двухцветного неба нет; дорожка светила —
// спекуляр движка.
// Пена — тоже туториал: маска мелководья (толщина) + гребни по
// нормали, анимированный Вороной с domain warp и emergence-пульсацией;
// второй смещённый проход Вороного — тёмная кромка, третий мелкий —
// пузырьки. Наше, чего в туториале нет: SDF-карта берега и накат
// (плавная линия из карты высот, П15 9.3-9.4), мягкая кромка последних
// сантиметров толщины, круги вокруг ног, рябь поверх волн, гашение
// вершинного смещения вдали (грубые кольца Ocean). Дешёвая версия для
// SIMPLE/NORMAL — water_bu_cheap.gdshader (без экранной выборки).
// Сетка: море —
// Ocean-кольца аддона, озеро — PlaneMesh; ноды воды без поворота и
// масштаба, координаты сразу мировые.
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled,
	specular_schlick_ggx;

// Экранная и глубинная текстуры сцены (только HIGH/ULTRA — материал
// с ними не должен попадать на SIMPLE/NORMAL: копия экрана не бесплатна).
// Объявления в одну строку: аудит сэмплеров требует фильтр на строке
// с uniform.
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;

group_uniforms Colors;
// Рассеянный цвет воды (in-scatter): мелководье и глубина; яркость по
// часам ведёт WaterArea.update_sky (ночь — тёмная вода).
uniform vec4 color_shallow : source_color = vec4(0.10, 0.14, 0.10, 1.0);
uniform vec4 color_deep : source_color = vec4(0.016, 0.035, 0.028, 1.0);
// Поглощение Бера по каналам, 1/м (SPEC П14 4.1): красный гаснет первым.
// Константы озера (торфяная) и моря (стальная) ставит WaterArea.
uniform vec3 absorption = vec3(1.6, 0.75, 0.45);
group_uniforms;

group_uniforms Surface;
// П15 2: roughness растёт с расстоянием — гашение субпиксельных волн
// переводит их наклон в шероховатость (Toksvig-подобно). Вблизи — почти
// зеркало, у горизонта — матовое зеркало неба.
uniform float roughness_near : hint_range(0.0, 1.0) = 0.03;
uniform float roughness_far : hint_range(0.0, 1.0) = 0.16;
// П15 3: отражение — движковое (IBL radiance неба Sky3D), френель
// Шлика движка с F0 ≈ 0.02 (SPECULAR × 0.08).
uniform float specular : hint_range(0.0, 1.0) = 0.25;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
// Сила преломления (панель F3 «Преломление воды»: 0 — без смещения
// выборки, толщина и Бер остаются).
uniform float refraction_amount : hint_range(0.0, 4.0) = 1.0;
// Слои ряби: 2 на HIGH, 3 на ULTRA (F3 «Рябь воды» — 0).
uniform float ripple_layers : hint_range(0.0, 3.0) = 2.0;
// Сила и масштаб ряби (ползунки F3 «Вода»): 1 — номинал уровня.
uniform float ripple_strength : hint_range(0.0, 2.0) = 1.0;
uniform float ripple_scale : hint_range(0.5, 2.0) = 1.0;
// Высота вьюпорта в пикселях (для пиксельной фильтрации ряби): built-in
// SCREEN_PIXEL_SIZE в 4.7.2 из fragment-кода не виден — WaterArea ставит
// размер и обновляет его при ресайзе окна.
uniform float screen_px_height = 720.0;
group_uniforms;

group_uniforms Waves;
// Волны sea_octave (туториал gameidea): height — суммарная высота, м;
// choppiness — острота гребней (степень); speed — скорость дрейфа
// паттерна; freq — базовая частота (1/м). Озеро спокойнее моря —
// константы ставит WaterArea, ползунки F3 множат.
uniform float sea_height : hint_range(0.0, 2.0) = 0.35;
uniform float sea_choppiness : hint_range(0.0, 10.0) = 4.0;
uniform float sea_speed : hint_range(0.0, 3.0) = 0.8;
uniform float sea_freq : hint_range(0.0, 0.5) = 0.08;
// Октавы нормали во fragment: 5 ULTRA / 4 HIGH (цена, П15-ДОП п. 6);
// геометрия всегда 3 (ITER_GEOMETRY ниже).
uniform int iter_fragment = 4;
group_uniforms;

group_uniforms Foam;
// П15 4 + 9.3 + П15-ДОП блок 2: пена — где мелко (толщина из буфера
// глубины), на гребнях волн (нормаль) и в полосе берега: линия берега
// — по карте расстояния до береговой линии (SDF: суша > 0, вода < 0,
// метры), запечённой из карты высот (ShoreBand.sdf_texture), НЕ по
// толщине: линия — плавная кривая, не рёбра треугольников земли.
uniform sampler2D shore_sdf : filter_linear_mipmap;
// Количество пены (море 1.0, озеро ~0.15 — почти без пены) и ширина
// полосы у кромки, м (2-8 см; ползунки F3 «Вода»).
uniform float foam_amount : hint_range(0.0, 2.0) = 1.0;
uniform float foam_width : hint_range(0.02, 0.3) = 0.06;
// Амплитуда наката, м (море 0.1-0.4, озеро чуть-чуть): линия пены
// ползёт туда-обратно (П15 9.4).
uniform float runup_amp : hint_range(0.0, 0.6) = 0.35;
// П15-ДОП блок 2 (туториал): цвет пены и тёмной кромки-тени, сила
// кромки (0 — без ободка) и плотность пузырьков внутри комьев.
uniform vec4 foam_color : source_color = vec4(0.76, 0.77, 0.79, 1.0);
uniform vec4 foam_edge_color : source_color =
	vec4(0.02, 0.03, 0.05, 1.0);
uniform float foam_edge : hint_range(0.0, 1.0) = 0.8;
uniform float foam_bubbles : hint_range(0.0, 4.0) = 0.8;
group_uniforms;

group_uniforms Effects;
// П15 5: каустика на дне — процедурные анимированные блики на мелком
// (толщина < 1.5 м), гаснут с глубиной, с расстоянием и в темноте
// (добавка пропорциональна свету, отражённому от дна: ночью и в тени
// дно тёмное — бликов нет). 0 — выключено (галочка F3 «Каустика»);
// ползунок F3 «Вода» меняет яркость.
uniform float caustic_brightness : hint_range(0.0, 4.0) = 1.0;
// П15 6: круги вокруг ног героя — до 4 источников uniform-массивом:
// xy — позиция XZ, z — время старта (сек с запуска движка), w — сила
// (0 — слот пуст). Ведёт WaterArea по локальному игроку в зоне,
// по сети не идут. ripple_fx_amount — выключатель галочкой F3
// «Круги на воде».
uniform vec4 ripple_sources[4];
uniform float ripple_fx_amount : hint_range(0.0, 1.0) = 1.0;
group_uniforms;

group_uniforms Fades;
// Растворение к горизонту цветом неба (дальняя плоскость Ocean за 700 м
// уходит в дымку без резкой границы; «Простая графика» приближает).
uniform float distance_fade_min = 700.0;
uniform float distance_fade_max = 1400.0;
// Смещение вершин гаснет вдали (внешние кольца Ocean с квадами до 16 м).
uniform float vertex_wave_fade_min = 380.0;
uniform float vertex_wave_fade_max = 800.0;
// Depth-буфер вдали неточен: толщина сменяется «глубокой» константой.
uniform float depth_fog_fade_min = 70.0;
uniform float depth_fog_fade_max = 130.0;
// Дальняя толщина-заглушка, м (за пределами надёжной глубины).
uniform float far_thickness = 8.0;
group_uniforms;

// Волны туториала: октавы sea_octave, матрица сжатия_uv между октавами.
const int ITER_GEOMETRY = 3;
const int ITER_FRAGMENT_MAX = 5;
const mat2 octave_m = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6));
// Нормали fragment: минимальный шаг разностей (м) и дистанция, с которой
// нормаль сглаживается к геометрической (туториал: normal_epsilon /
// normal_smoothness_dist; шаг дальше растёт как dist × 0.005).
const float NORMAL_EPS_M = 0.01;
const float NORMAL_SMOOTH_DIST = 50.0;
// П15 1-2: пороги пиксельной фильтрации ряби — мельче 2 пикселей слой
// гасится полностью, крупнее 4 — учитывается целиком (Toksvig/LEAN).
const float FILTER_MIN_PX = 2.0;
const float FILTER_MAX_PX = 4.0;
// Период наката линии пены, сек (такт морской зыби; спектра волн больше
// нет — раньше период брался от самой длинной волны Герстнера).
const float RUNUP_PERIOD_SEC = 7.0;

// Пена туториала (П15-ДОП блок 2): цвета — uniform (пресеты F3,
// блок 5), пороги и масштабы — константы. Мелководье: пена при
// толщине < FOAM_DEPTH_START м (толщина вдоль взгляда, как у Бера).
// Гребни: пена при nrm.y < FOAM_CREST_THRESHOLD (острые гребни
// sea_octave круче плоских впадин), вес × FOAM_CREST_AMOUNT.
// Вороной: FOAM_NOISE_SCALE — масштаб комьев, FOAM_NOISE_SPEED —
// темп их жизни, FOAM_CUTOFF — порог массы, FOAM_EDGE_OFFSET — сдвиг
// выборки кромки (м), VORONOI_SCALE — масштаб пузырьков. Порог
// гребней поднят с туториальных 0.7: наши волны ниже и длинее.
const float FOAM_DEPTH_START = 0.8;
const float FOAM_DEPTH_END = 0.0;
const float FOAM_CREST_THRESHOLD = 0.85;
const float FOAM_CREST_AMOUNT = 2.0;
const float FOAM_NOISE_SCALE = 2.0;
const float FOAM_NOISE_SPEED = 1.0;
const float FOAM_CUTOFF = 0.7;
const vec2 FOAM_EDGE_OFFSET = vec2(0.02, 0.02);
const float VORONOI_SCALE = 9.0;
// Мягкий край воды (П15 9.2): последние сантиметры толщины (5-15 см)
// плавно гасят всё, кроме дна, — вода у кромки полностью прозрачная.
const float EDGE_SOFT_M = 0.12;
// Круги от ног (П15 6): гауссовы кольца, скорость фронта, время жизни
// и ширина пакета, м; второе кольцо отстаёт на RING_TRAIL_M и слабее.
const float RING_LIFE_SEC = 2.2;
const float RING_SPEED_M = 0.85;
const float RING_W = 0.20;
const float RING_TRAIL_M = 0.32;
// Каустика (П15 5, П15-ДОП блок 3 — туториал): блики на дне живут на
// мелком у берега — дальше (и глубже) гаснут; само пятно — произведение
// двух встречно дрейфующих слоёв шума, CAUSTIC_SCALE — их масштаб, m,
// CAUSTIC_SPEED — скорость дрейфа (второй слой крупнее ×0.7 и медленнее
// ×0.8, направление — по другой оси).
const float CAUSTIC_MAX_DEPTH_M = 1.5;
const float CAUSTIC_MAX_DIST_M = 50.0;
const float CAUSTIC_SCALE = 1.3;
const float CAUSTIC_SPEED = 0.15;
// Преломление (П15-ДОП блок 3): дистанционный спад силы (м, туториал
// refraction_distance_fade) и маска по толщине (м): на сверхмелком у
// кромки смещения нет — границы пикселей не рвут дно «призраками».
const float REFRACTION_FADE_M = 5.0;
const float REF_DEPTH_M = 0.5;

// Value-шум и октавы волн (туториал gameidea): hash12 → value noise →
// sea_octave (острые гребни: 1 - pow(wv.x·wv.y, 0.65) в степени
// choppiness; плоские впадины). Два прохода навстречу друг другу
// (uv ± time·speed) убирают скольжение паттерна в одну сторону.
float hash12(vec2 p) {
	uvec2 q = uvec2(ivec2(p)) * uvec2(1597334677u, 3812015801u);
	uint n = (q.x ^ q.y) * 1597334677u;
	return float(n) * (1.0 / 4294967295.0);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return -1.0 + 2.0 * mix(
		mix(hash12(i + vec2(0.0, 0.0)), hash12(i + vec2(1.0, 0.0)), u.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x),
		u.y);
}

float sea_octave(vec2 uv, float choppy) {
	uv += vnoise(uv);
	vec2 wv = 1.0 - abs(sin(uv));
	vec2 swv = abs(cos(uv));
	wv = mix(wv, swv, wv);
	return pow(1.0 - pow(wv.x * wv.y, 0.65), choppy);
}

// Высота волн в точке xz (туториал: map/map_detailed; здесь — сразу
// высота h, нормаль считается разностями). Каждая октава: частота ×1.9,
// амплитуда ×0.22, choppiness → 1 (гребни верхних октав мягче).
float wave_height_geo(vec2 xz, float time) {
	float freq = sea_freq;
	float amp = sea_height;
	float choppy = sea_choppiness;
	vec2 uv = xz;
	uv.x *= 0.75;
	float h = 0.0;
	for (int i = 0; i < ITER_GEOMETRY; i++) {
		float d = sea_octave((uv + time * sea_speed) * freq, choppy);
		d += sea_octave((uv - time * sea_speed) * freq, choppy);
		h += d * amp;
		uv *= octave_m;
		freq *= 1.9;
		amp *= 0.22;
		choppy = mix(choppy, 1.0, 0.2);
	}
	return h;
}

float wave_height_detailed(vec2 xz, float time, int iterations) {
	float freq = sea_freq;
	float amp = sea_height;
	float choppy = sea_choppiness;
	vec2 uv = xz;
	uv.x *= 0.75;
	float h = 0.0;
	for (int i = 0; i < ITER_FRAGMENT_MAX; i++) {
		if (i >= iterations) {
			break;
		}
		float d = sea_octave((uv + time * sea_speed) * freq, choppy);
		d += sea_octave((uv - time * sea_speed) * freq, choppy);
		h += d * amp;
		uv *= octave_m;
		freq *= 1.9;
		amp *= 0.22;
		choppy = mix(choppy, 1.0, 0.2);
	}
	return h;
}

// Нормаль волн конечными разностями высоты (шаг eps растёт с
// расстоянием — детали мелких октав вдали гаснут, а не мерцают).
vec3 wave_normal_detailed(vec2 xz, float eps) {
	float h0 = wave_height_detailed(xz, TIME, iter_fragment);
	float hx = wave_height_detailed(xz + vec2(eps, 0.0), TIME,
		iter_fragment);
	float hz = wave_height_detailed(xz + vec2(0.0, eps), TIME,
		iter_fragment);
	return normalize(vec3(h0 - hx, eps, h0 - hz));
}

// Симплекс-шум 2D (Ian McEwan / Ashima Arts, публичный webgl-noise) —
// тот же, что в шейдере земли.
vec3 mod289(vec3 x) {
	return x - floor(x * (1.0 / 289.0)) * 289.0;
}
vec2 mod289(vec2 x) {
	return x - floor(x * (1.0 / 289.0)) * 289.0;
}
vec3 permute(vec3 x) {
	return mod289(((x * 34.0) + 10.0) * x);
}
float snoise(vec2 v) {
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
	vec3 m = max(0.5 - vec3(dot(x0, x0), dot(x12.xy, x12.xy),
		dot(x12.zw, x12.zw)), 0.0);
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

// Наклон одного слоя ряби (конечные разности шума): направление и
// скорость у каждого слоя свои.
vec2 ripple_slope(vec2 p, vec2 dir, float scale, float speed, float t) {
	vec2 uv = p * scale + dir * (t * speed);
	float e = 0.35;
	float h0 = snoise(uv);
	float hx = snoise(uv + vec2(e, 0.0));
	float hz = snoise(uv + vec2(0.0, e));
	return vec2(hx - h0, hz - h0) / e;
}

// П15 2: вес слоя ряби по её экранному размеру (λ на дистанции dist):
// мельче FILTER_MIN_PX пикселей — 0 (наклон уйдёт в roughness),
// крупнее FILTER_MAX_PX — 1. Пикселей на радиан (px_per_rad) считается
// в теле fragment: built-in SCREEN_PIXEL_SIZE в функциях недоступен.
float wave_weight(float lambda_m, float dist, float px_per_rad) {
	return smoothstep(FILTER_MIN_PX, FILTER_MAX_PX,
		px_per_rad * lambda_m / max(dist, 0.001));
}

// --- Пена туториала (П15-ДОП блок 2): шумы Вороного и 3D value ---
// Хэш 3D — тот же ряд, что hash12, с третьим измерением; hash22
// роняет точку в ячейку сетки Вороного.
float hash13(vec3 p) {
	uvec3 q = uvec3(ivec3(p)) * uvec3(1597334677u, 3812015801u, 2798796415u);
	uint n = (q.x ^ q.y ^ q.z) * 1597334677u;
	return float(n) * (1.0 / 4294967295.0);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

// Вороной: квадрат расстояния до ближайшей точки сетки; точки
// дрейфуют по синусу от TIME — комья пены живут, а не стоят.
float voronoi(vec2 uv) {
	vec2 n = floor(uv);
	vec2 f = fract(uv);
	float m_dist = 1.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = hash22(n + g);
			o = 0.5 + 0.5 * sin(TIME * FOAM_NOISE_SPEED + 6.2831 * o);
			vec2 r = g - f + o;
			float d = dot(r, r);
			m_dist = min(m_dist, d);
		}
	}
	return m_dist;
}

// 3D value-шум — emergence пены: комья появляются и исчезают волнами.
float noise3d(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(
			mix(hash13(i + vec3(0.0, 0.0, 0.0)),
				hash13(i + vec3(1.0, 0.0, 0.0)), f.x),
			mix(hash13(i + vec3(0.0, 1.0, 0.0)),
				hash13(i + vec3(1.0, 1.0, 0.0)), f.x),
			f.y),
		mix(
			mix(hash13(i + vec3(0.0, 0.0, 1.0)),
				hash13(i + vec3(1.0, 0.0, 1.0)), f.x),
			mix(hash13(i + vec3(0.0, 1.0, 1.0)),
				hash13(i + vec3(1.0, 1.0, 1.0)), f.x),
			f.y),
		f.z);
}

// Масса пены: три октавы Вороного (между октавами — поворот и сдвиг),
// pow заостряет комья — редкие пузыри, между ними вода.
float fbm_voronoi(vec2 uv) {
	float v = 0.0;
	float a = 0.5;
	vec2 shift = vec2(100.0);
	mat2 rot = mat2(vec2(cos(0.5), sin(0.5)), vec2(-sin(0.5), cos(0.5)));
	for (int i = 0; i < 3; i++) {
		float val = 1.0 - voronoi(uv);
		val = pow(val, 2.0);
		v += a * val;
		uv = rot * uv * 2.0 + shift;
		a *= 0.5;
	}
	return v;
}

varying vec3 world_pos;
// Геометрическая нормаль волн из vertex (3 октавы): к ней fragment
// плавно сводит детальную нормаль вдали (переход без мерцания).
varying vec3 vertex_normal_world;

void vertex() {
	// Исходная мировая позиция (до смещения): по ней fragment считает
	// детальную нормаль волн.
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Гашение волн вдали: внешние кольца Ocean грубые, дальше — плоскость.
	vec3 cam_pos = INV_VIEW_MATRIX[3].xyz;
	float wave_fade = 1.0 - smoothstep(
		vertex_wave_fade_min, vertex_wave_fade_max,
		distance(wp.xz, cam_pos.xz));
	// Волны туториала: смещение по Y всеми геометрическими октавами;
	// ноды воды без поворота/масштаба: мировое смещение = локальному.
	VERTEX.y += wave_height_geo(wp.xz, TIME) * wave_fade;
	// Нормаль геометрии конечными разностями (шаг — как в туториале).
	float vertex_eps = 0.1;
	float h_c = wave_height_geo(wp.xz, TIME) * wave_fade;
	float h_x = wave_height_geo(wp.xz + vec2(vertex_eps, 0.0), TIME)
		* wave_fade;
	float h_z = wave_height_geo(wp.xz + vec2(0.0, vertex_eps), TIME)
		* wave_fade;
	vertex_normal_world = normalize(
		vec3(h_c - h_x, vertex_eps, h_c - h_z));
	world_pos = wp;
}

void fragment() {
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - world_pos);
	float dist = length(CAMERA_POSITION_WORLD - world_pos);
	// Пикселей на радиан по вертикали экрана: PROJECTION_MATRIX[1][1] =
	// 1/tan(fov/2), высота экрана — uniform screen_px_height.
	float px_per_rad = screen_px_height / (2.0 * PROJECTION_MATRIX[1][1]);

	// Толщина воды под пикселем: глубина сцены минус глубина поверхности
	// (оба — дистанции вдоль взгляда; на мелком у берега → 0).
	float scene_raw = texture(depth_tex, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, scene_raw);
	vec4 view_pos = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_pos.xyz /= view_pos.w;
	float surf_dist = -VERTEX.z;
	// Знак толщины живёт до блока пены: предмет над водой в кадре
	// (отрицательная) пеной не покрывается — как проверка туториала
	// distorted_bg_depth > water_linear_depth.
	float thickness_signed = -view_pos.z - surf_dist;
	float thickness = max(thickness_signed, 0.0);
	// Вдали depth-буфер неточен: толщина сменяется «глубокой» константой.
	float depth_fade = 1.0 - smoothstep(
		depth_fog_fade_min, depth_fog_fade_max, surf_dist);
	thickness = mix(far_thickness, thickness, depth_fade);
	// П15 9.2: мягкий край — последние 5-15 см толщины плавно гасят
	// всё, кроме дна (отражение, френель, рассеяние, рябь); у самой
	// кромки вода полностью прозрачная, линия пересечения не читается.
	float edge = smoothstep(0.0, EDGE_SOFT_M, thickness);

	// Нормаль волн (туториал): детальная — конечными разностями
	// октав fragment, шаг растёт с расстоянием (мелкие октавы гаснут,
	// а не мерцают); вдали — плавный переход к геометрической нормали
	// vertex. Доля сведения (lost) уходит в roughness — зеркало вблизи,
	// мягко-матовое у горизонта (П15 2).
	float lod_eps = max(NORMAL_EPS_M, dist * 0.005);
	vec3 nrm = wave_normal_detailed(world_pos.xz, lod_eps);
	float smooth_factor = clamp(
		(dist - NORMAL_SMOOTH_DIST) / 200.0, 0.0, 1.0);
	nrm = normalize(mix(nrm, vertex_normal_world, smooth_factor));
	float lost = smooth_factor;

	// Рябь (SPEC 4.3, П15 2): 2-3 слоя шума, длины 1.5/0.75/0.3 м —
	// мельче и слабее прежних; та же пиксельная фильтрация, к дали
	// гаснет и сама по себе (двойная защита от мерцания).
	if (ripple_layers > 0.5 && ripple_strength > 0.001) {
		float scale = ripple_scale;
		vec2 slope = ripple_slope(world_pos.xz,
			vec2(0.84, 0.54), 0.667 * scale, 0.35, TIME) * 0.020;
		float lambda_ripple = 1.5 / scale;
		float weight = wave_weight(lambda_ripple, dist, px_per_rad);
		slope *= weight;
		float ripple_lost = 1.0 - weight;
		if (ripple_layers > 1.5) {
			float w2 = wave_weight(0.75 / scale, dist, px_per_rad);
			slope += ripple_slope(world_pos.xz,
				vec2(-0.47, 0.88), 1.333 * scale, -0.50, TIME)
				* 0.016 * w2;
			ripple_lost = min(ripple_lost + (1.0 - w2) * 0.4, 1.0);
		}
		if (ripple_layers > 2.5) {
			float w3 = wave_weight(0.30 / scale, dist, px_per_rad);
			slope += ripple_slope(world_pos.xz,
				vec2(0.36, -0.93), 3.333 * scale, 0.80, TIME)
				* 0.012 * w3;
			ripple_lost = min(ripple_lost + (1.0 - w3) * 0.6, 1.0);
		}
		nrm = normalize(nrm + vec3(slope.x, 0.0, slope.y)
			* ripple_strength * 2.2);
		lost = max(lost, ripple_lost);
	}

	// П15 6: круги вокруг ног героя — до 4 источников (WaterArea ведёт
	// слоты по локальному игроку в зоне, без сети): расходящиеся
	// гауссовы кольца ряби (наклон — производная пакета по радиусу)
	// и немного пены у фронта. Возмущение подчиняется общему гашению
	// кромки, как и рябь.
	float rings_foam = 0.0;
	if (ripple_fx_amount > 0.001) {
		for (int i = 0; i < 4; i++) {
			vec4 src = ripple_sources[i];
			float age = TIME - src.z;
			if (src.w <= 0.001 || age < 0.0 || age > RING_LIFE_SEC) {
				continue;
			}
			vec2 rel = world_pos.xz - src.xy;
			float d = max(length(rel), 1e-4);
			float fade = src.w * (1.0 - age / RING_LIFE_SEC);
			float r1 = age * RING_SPEED_M;
			// exp(-q²) — гауссово кольцо (без pow: база отрицательна).
			float q1 = (d - r1) / RING_W;
			float ring1 = exp(-q1 * q1);
			float q2 = (d - max(r1 - RING_TRAIL_M, 0.0)) / RING_W;
			float ring2 = exp(-q2 * q2);
			float ring = ring1 + 0.55 * ring2;
			float slope_r = -2.0 * (d - r1) / (RING_W * RING_W) * ring1;
			nrm.xz += (rel / d) * slope_r * fade
				* 0.05 * ripple_fx_amount;
			rings_foam = max(rings_foam,
				ring * fade * 0.35 * ripple_fx_amount);
		}
		nrm = normalize(nrm);
	}
	// П15 9.2: рябь и наклон волн гаснут к кромке — вода у края гладкая
	// и прозрачная (edge = 0 на толщине < ~5 см).
	nrm = normalize(mix(vec3(0.0, 1.0, 0.0), nrm, edge));
	float rough = mix(roughness_near, roughness_far, lost);

	// Преломление (П15-ДОП блок 3, туториал): смещение UV — только
	// детальной частью нормали (детальная минус геометрическая: вдали,
	// куда нормаль сведена к геометрической, смещения нет само), сила
	// падает с дистанцией (ref_dist_factor) и гасится маской мелководья
	// ref_depth_mask — на сверхмелком у кромки дно не преломляется
	// (пиксели границы не рвутся «призраками»). Защита от предметов над
	// водой — наша: смещённая точка ближе поверхности — прямая выборка.
	vec2 normal_offset = nrm.xz - vertex_normal_world.xz;
	float ref_dist_factor = clamp(
		REFRACTION_FADE_M / max(0.1, surf_dist), 0.0, 1.0);
	float ref_depth_mask = smoothstep(0.0, REF_DEPTH_M, thickness);
	vec2 refr_off = normal_offset * 0.05 * refraction_amount
		* ref_dist_factor * ref_depth_mask;
	vec2 refr_uv = SCREEN_UV + refr_off;
	float check_raw = texture(depth_tex, refr_uv).r;
	vec3 check_ndc = vec3(refr_uv * 2.0 - 1.0, check_raw);
	vec4 check_pos = INV_PROJECTION_MATRIX * vec4(check_ndc, 1.0);
	check_pos.xyz /= check_pos.w;
	if (-check_pos.z < surf_dist - 0.05) {
		refr_uv = SCREEN_UV;
	}
	vec3 bottom = texture(screen_tex, refr_uv).rgb;

	// П15 5 + П15-ДОП блок 3: каустика на дне — анимированные блики на
	// мелком: два встречно дрейфующих слоя шума, произведение (туториал:
	// sample1 · sample2 — яркие пятна редки, между ними тёмные; прежний
	// pow(...,5) одного поля ушёл). Гаснет с глубиной (толщина), с
	// расстоянием (мерцание) и в темноте: добавка пропорциональна свету,
	// отражённому от дна, — ночью и в тени дно тёмное, бликов нет, днём
	// на светлом песке — максимум. Процедурная, текстура не нужна.
	float caustic_mask = caustic_brightness
		* (1.0 - smoothstep(CAUSTIC_MAX_DEPTH_M * 0.25,
			CAUSTIC_MAX_DEPTH_M, thickness))
		* (1.0 - smoothstep(CAUSTIC_MAX_DIST_M * 0.4,
			CAUSTIC_MAX_DIST_M, surf_dist));
	if (caustic_mask > 0.001) {
		vec2 cuv1 = world_pos.xz * CAUSTIC_SCALE;
		cuv1.x += TIME * CAUSTIC_SPEED;
		vec2 cuv2 = world_pos.xz * (CAUSTIC_SCALE * 0.7);
		cuv2.y -= TIME * CAUSTIC_SPEED * 0.8;
		float caustic = (0.5 + 0.5 * snoise(cuv1))
			* (0.5 + 0.5 * snoise(cuv2));
		float bottom_luma = dot(bottom, vec3(0.299, 0.587, 0.114));
		bottom += vec3(0.9, 0.95, 1.0)
			* caustic * caustic_mask * bottom_luma * 1.2;
	}

	// Поглощение Бера по каналам (SPEC 4.1) + объёмный цвет туториала
	// (П15-ДОП блок 3): volume = mix(мелководье, глубина, depth_ratio)
	// по толщине — им тонируется дно (apparent_seabed = screen_color ·
	// volume; у кромки тонировка спадает — там вода прозрачная, П15 9.2)
	// и он же — рассеянный цвет толщи (in-scatter растёт с 1 − transmit,
	// красный гаснет первым — дно на мелком видно чисто, с глубиной
	// уходит в цвет воды). Композит вручную: один альфа блендинга не
	// передаст поканальное поглощение.
	vec3 transmit = exp(-absorption * thickness);
	float depth_ratio = 1.0 - exp(-thickness * 0.9);
	vec3 volume = mix(color_shallow.rgb, color_deep.rgb, depth_ratio);
	vec3 scatter = volume;
	vec3 water = bottom * mix(vec3(1.0), volume, edge) * transmit
		+ scatter * (1.0 - transmit) * edge;

	// Пена туториала (П15-ДОП блок 2), только smoothstep: где пена
	// может быть — сумма трёх слагаемых: мелководье (толщина Бера),
	// гребни волн (нормаль: острые гребни sea_octave круче впадин) и
	// наша SDF-полоса берега с накатом (туториал знает только глубину —
	// у нас линия берега плавная кривая карты высот, П15 9.3-9.4).
	// Предмет над водой в кадре пеной не покрывается; всё умножается
	// на foam_amount (озеро ≈ 0.15 — почти без пены).
	float underwater = thickness_signed > 0.0 ? 1.0 : 0.0;
	float depth_foam = smoothstep(FOAM_DEPTH_START, FOAM_DEPTH_END,
		thickness);
	float crest_foam = smoothstep(FOAM_CREST_THRESHOLD,
		FOAM_CREST_THRESHOLD - 0.1, nrm.y) * FOAM_CREST_AMOUNT;
	float n_coarse = snoise(world_pos.xz * 1.667
		- vec2(TIME * 0.05, TIME * 0.06));
	float sdf = texture(shore_sdf,
		(world_pos.xz + vec2(128.0)) / 256.0).r;
	float runup = runup_amp * (0.5 - 0.5
		* cos(TIME * TAU / RUNUP_PERIOD_SEC));
	float shore_line = -sdf - (runup + n_coarse * 0.20);
	float shore_band = 1.0 - smoothstep(0.0, foam_width, shore_line);
	float foam_level = clamp(depth_foam + crest_foam + shore_band,
		0.0, 1.0) * foam_amount * underwater;

	// Масса пены (П15-ДОП блок 6): Вороной — самое дорогое место
	// шейдера, считается только там, где пена возможна (маска
	// foam_level или круги от ног); открытая вода платит только
	// масками.
	float foam_mask = 0.0;
	float foam_edge_mask = 0.0;
	if (foam_level > 0.001 || rings_foam > 0.001) {
		// Domain warp: течение крутит пену двумя шумами (второй — со
		// сдвигом фазы). Emergence: 3D-шум пульсирует — комья
		// появляются волнами; у берега и на гребнях принудительно
		// полный.
		vec2 flow_uv = world_pos.xz * 0.5
			+ TIME * 0.05 * FOAM_NOISE_SPEED;
		vec2 warp = vec2(vnoise(flow_uv),
			vnoise(flow_uv + vec2(5.2, 1.3))) * 0.5;
		float emergence = noise3d(vec3(world_pos.xz * 0.5,
			TIME * 0.2 * FOAM_NOISE_SPEED));
		emergence = smoothstep(0.0, 1.0, emergence * 0.5 + 0.5);
		float eff_emergence = mix(emergence, 1.0, foam_level);

		// Масса пены: fbm-Вороной + foam_level, порог — мягкий
		// smoothstep. Кромка-тень: тот же Вороной из смещённой точки —
		// там, где он есть, а массы нет, тёмный ободок (фальшивая
		// толщина пены).
		float foam_noise = fbm_voronoi(
			world_pos.xz * FOAM_NOISE_SCALE + warp) * eff_emergence;
		float foam_shadow_noise = fbm_voronoi(
			(world_pos.xz + FOAM_EDGE_OFFSET) * FOAM_NOISE_SCALE + warp)
			* eff_emergence;
		foam_mask = smoothstep(FOAM_CUTOFF + 0.5, FOAM_CUTOFF + 0.6,
			foam_noise + foam_level);
		float shadow_shape = smoothstep(FOAM_CUTOFF + 0.5,
			FOAM_CUTOFF + 0.6, foam_shadow_noise + foam_level);
		foam_edge_mask = clamp(shadow_shape - foam_mask, 0.0, 1.0)
			* foam_edge;

		// Пузырьки: мелкий Вороной рвёт плотность массы изнутри.
		float voronoi_val = 1.0 - sqrt(voronoi(
			world_pos.xz * VORONOI_SCALE + warp));
		voronoi_val = smoothstep(0.2, 0.8, voronoi_val);
		float bubble_alpha = 1.0 - clamp(
			(1.0 - voronoi_val) * foam_bubbles, 0.0, 1.0);
		foam_mask *= bubble_alpha;

		// Круги вокруг ног — тоже пена (локально, без Вороного).
		foam_mask = max(foam_mask, rings_foam);
	}
	float foam = clamp(foam_mask + foam_edge_mask, 0.0, 1.0);

	// П15 3: отражение — движковое: движок сам кладёт на воду radiance
	// настоящего неба Sky3D (облака, солнце, луна), отфильтрованную по
	// ROUGHNESS, с френелем Шлика и F0 ≈ 0.02 (SPECULAR 0.25); дорожка
	// светила — спекуляр движка. ALBEDO = 0 гасит диффузный ambient —
	// окружение не «подсвечивает» толщу (исключение — пена: её ALBEDO
	// освещается светом сцены, в тени пена не светится). Здесь остаётся
	// «пропущенный свет» (дно × поглощение + рассеяние): френель Шлика —
	// та же формула, что у движка — гасит его навстречу отражению: под
	// острым углом видно небо, сверху — толща. Пена гасит эмиссию воды
	// и отражение; мягкий край (9.2) гасит и эмиссию, и отражение —
	// дно остаётся. Вдали эмиссия растворяется, остаётся зеркало неба,
	// и горизонт сводит туман.
	float fresnel = 0.02 + 0.98
		* pow(1.0 - max(dot(nrm, view_dir), 0.0), 5.0);
	float dist_fade = 1.0 - smoothstep(
		distance_fade_min, distance_fade_max, surf_dist);
	EMISSION = water * (1.0 - fresnel) * dist_fade
		* (1.0 - foam) * edge;
	// Пена освещается светом сцены: ALBEDO — цвет массы поверх
	// тёмной кромки (ободок виден только там, где массы нет).
	ALBEDO = foam_edge_color.rgb * foam_edge_mask * (1.0 - foam_mask)
		+ foam_color.rgb * foam_mask;
	ALPHA = clamp(max(edge, foam * 0.6), 0.0, 1.0);
	// Пена шершавая (туториал): roughness → 0.8 по массе и кромке.
	ROUGHNESS = mix(rough, 0.8, foam);
	SPECULAR = specular * edge * (1.0 - foam);
	METALLIC = metallic;
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);
}
