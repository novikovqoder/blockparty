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
// Пена — заказ владельца 04.11 «убрать мультяшность»: Вороного,
// тёмную обводку и пузырьки туториала П15-ДОП убрали. Осталось
// только: тонкое кружево у самой кромки в зоне наката — узкая рваная
// полоса из мягкого многослойного симплекс-шума (без чётких клеток),
// полупрозрачная, медленно тает при отливе; и редкие барашки на самых
// высоких гребнях — рождаются и тают за 1-2 с «дыханием» 3D-шума,
// не висят пятнами. Линия кружева — по SDF-карте берега (запечена из
// карты высот, П15 9.3-9.4), не по рёбрам depth. Озеро строится
// с foam_amount = 0 — пены нет совсем. Наше, чего в туториале не
// было: мягкая кромка последних сантиметров толщины, круги вокруг
// ног, рябь поверх волн, гашение вершинного смещения вдали (грубые
// кольца Ocean). Дешёвая версия для SIMPLE/NORMAL —
// water_bu_cheap.gdshader (без экранной выборки).
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
// Заказ 04.11 + П15 4 + 9.3: пена — только кружево у кромки наката
// (линия — по карте расстояния до береговой линии: SDF суша > 0,
// вода < 0, метры, запечена из карты высот ShoreBand.sdf_texture,
// НЕ по толщине: линия — плавная кривая, не рёбра треугольников) и
// редкие барашки на самых высоких гребнях. Вороного, тёмной обводки
// и пузырьков туториала больше нет.
uniform sampler2D shore_sdf : filter_linear_mipmap;
// Количество пены (море 1.0, озеро 0.0 — пены нет совсем) и ширина
// рваной полосы кружева у кромки, м (ползунки F3 «Вода»).
uniform float foam_amount : hint_range(0.0, 2.0) = 1.0;
uniform float foam_width : hint_range(0.02, 0.3) = 0.06;
// Амплитуда наката, м (море 0.1-0.4): линия кружева ползёт
// туда-обратно (П15 9.4).
uniform float runup_amp : hint_range(0.0, 0.6) = 0.35;
// Цвет пены — сероватый, не чисто белый (освещается светом сцены);
// непрозрачность (полупрозрачная — по умолчанию 0.5) и количество
// барашков (0 — совсем нет; ползунки F3 «Вода»).
uniform vec4 foam_color : source_color = vec4(0.76, 0.77, 0.79, 1.0);
uniform float foam_alpha : hint_range(0.05, 1.0) = 0.5;
uniform float foam_crest : hint_range(0.0, 2.0) = 1.0;
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
// П15-ДОП2, п. 2: константа стала мягким потолком (см. fragment):
// глубже всё сходится к ней плавно, без подмены и излома.
uniform float far_thickness = 16.0;
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

// Пена (заказ 04.11): кружево — три слоя симплекса с масштабами
// LACE_SCALE ×1/×2.3/×4.9 и встречным дрейфом (скорости в долях
// мировых метров в секунду умножаются на TIME): суммы 0.55/0.30/0.15
// дают мягкое поле 0..1 без чётких клеток; порог LACE_CUT_* рвёт
// полосу наката кружевом с мягкими краями. LACE_EBB — остаток
// яркости кружева в фазе отлива (sin наката < 0): медленно тает,
// накат возвращает полную силу.
const float LACE_SCALE = 1.1;
const vec2 LACE_DRIFT1 = vec2(0.06, -0.045);
const vec2 LACE_DRIFT2 = vec2(0.09, 0.07);
const vec2 LACE_DRIFT3 = vec2(-0.12, -0.10);
const float LACE_CUT_LO = 0.42;
const float LACE_CUT_HI = 0.78;
const float LACE_EBB = 0.25;
// Барашки: только самые высокие гребни — доля вершинной высоты волны
// от sea_height (CREST_H_*; высота — varying из vertex, вдали гасится
// вместе с волнами) И крутые — nrm.y ниже CREST_STEEP_* (гребни
// sea_octave круче впадин). «Дыхание» — 3D value-шум по времени
// (CREST_LIFE_SPEED): пятно барашка рождается и тает за ~1-2 с,
// не висит. CREST_MAX — вклад барашка в маску пены.
const float CREST_H_LO = 0.5;
const float CREST_H_HI = 0.65;
const float CREST_STEEP_HI = 0.88;
const float CREST_STEEP_LO = 0.78;
const float CREST_LIFE_SPEED = 0.55;
const float CREST_LIFE_LO = 0.42;
const float CREST_LIFE_HI = 0.78;
const float CREST_MAX = 0.9;
// Мягкий край воды (П15 9.2): последние сантиметры толщины (5-15 см)
// плавно гасят всё, кроме дна, — вода у кромки полностью прозрачная.
// bu-claude: шире (0,12 → 0,4 м) — ступенчатый контур чаши озера под самой
// кромкой растворяется в плавном переходе к прозрачной воде.
const float EDGE_SOFT_M = 0.4;
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

// --- Пена (заказ 04.11): 3D value-шум «дыхания» барашков ---
// Вороного туториала убран целиком (вместе с hash22 и fbm-обвязкой):
// остался один 3D value-шум — им барашки рождаются и тают по времени.
// Хэш 3D — тот же ряд, что hash12, с третьим измерением.
float hash13(vec3 p) {
	uvec3 q = uvec3(ivec3(p)) * uvec3(1597334677u, 3812015801u, 2798796415u);
	uint n = (q.x ^ q.y ^ q.z) * 1597334677u;
	return float(n) * (1.0 / 4294967295.0);
}

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

varying vec3 world_pos;
// Геометрическая нормаль волн из vertex (3 октавы): к ней fragment
// плавно сводит детальную нормаль вдали (переход без мерцания).
varying vec3 vertex_normal_world;
// Высота волны в вершине, м (с гашением вдали): барашки живут только
// на самых высоких гребнях — вдали гасятся вместе с волнами.
varying float vertex_wave_h;

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
	vertex_wave_h = h_c;
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
	// П15-ДОП2, п. 2: толщина мягко ограничена сверху — tanh прижимает
	// всё глубокое к «глубокой» константе без излома. Цвет глубокой воды
	// одинаков и над картой, и за её краем: на юбке дна (П15-ДОП2, п. 1)
	// толщина растёт плавно от края, а если под пикселем нет геометрии
	// (луч мимо дна, глубина сцены = дальняя плоскость камеры), толщина
	// получается огромной и tanh даёт ту же глубокую воду — резких
	// переключений нет. Заодно шум depth-буфера вдали сжимается около
	// константы. Мелководье не трогается: при толщине ≪ константы
	// tanh(t/T)·T ≈ t.
	thickness = far_thickness * tanh(thickness / far_thickness);
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
	// bu-claude (как в демо-мире): дно на мелком — в своём цвете, гаснет
	// поканальным поглощением; тон воды добавляется только толщей.
	vec3 water = bottom * mix(vec3(1.0), volume, edge * 0.2) * transmit
		+ scatter * (1.0 - transmit) * edge;

	// Пена (заказ 04.11 «убрать мультяшность»), только smoothstep:
	// тонкое кружево у самой кромки в зоне наката (SDF-полоса берега —
	// линия плавная кривая карты высот, П15 9.3-9.4) и редкие барашки
	// на самых высоких гребнях. Вороного, тёмной обводки и пузырьков
	// туториала больше нет. Предмет над водой пеной не покрывается;
	// всё умножается на foam_amount (озеро 0.0 — пены нет совсем).
	float underwater = thickness_signed > 0.0 ? 1.0 : 0.0;
	float n_coarse = snoise(world_pos.xz * 1.667
		- vec2(TIME * 0.05, TIME * 0.06));
	float sdf = texture(shore_sdf,
		(world_pos.xz + vec2(128.0)) / 256.0).r;
	float runup = runup_amp * (0.5 - 0.5
		* cos(TIME * TAU / RUNUP_PERIOD_SEC));
	float shore_line = -sdf - (runup + n_coarse * 0.20);
	float shore_band = 1.0 - smoothstep(0.0, foam_width, shore_line);

	// Кружево и барашки — только там, где пена вообще возможна
	// (foam_amount > 0 и под водой); открытое море платит только
	// дешёвыми масками, кружево с тремя шумами — за ветвлением полосы.
	float foam_mask = 0.0;
	if (foam_amount > 0.001 && underwater > 0.5) {
		// Кружево: три мягких слоя симплекса со встречным дрейфом рвут
		// полосу наката без клеток; фаза наката (sin) ведёт таяние —
		// при отливе кружево ослабевает до LACE_EBB, накат возвращает
		// полную силу. Медленно, темпом морской зыби.
		if (shore_band > 0.001) {
			vec2 lace_p = world_pos.xz * LACE_SCALE;
			float l1 = 0.5 + 0.5 * snoise(lace_p + TIME * LACE_DRIFT1);
			float l2 = 0.5 + 0.5 * snoise(
				lace_p * 2.3 + TIME * LACE_DRIFT2 + vec2(7.3, 1.9));
			float l3 = 0.5 + 0.5 * snoise(
				lace_p * 4.9 + TIME * LACE_DRIFT3 + vec2(19.1, 11.7));
			float lace = smoothstep(LACE_CUT_LO, LACE_CUT_HI,
				l1 * 0.55 + l2 * 0.30 + l3 * 0.15);
			float tide = LACE_EBB + (1.0 - LACE_EBB) * (0.5 + 0.5
				* sin(TIME * TAU / RUNUP_PERIOD_SEC));
			foam_mask = shore_band * lace * tide;
		}
		// Барашки: самые высокие (доля sea_height вершинной высоты,
		// вдали гасится вместе с волнами) и крутые (нормаль) гребни;
		// «дыхание» 3D-шума рождает и растворяет пятно за ~1-2 с —
		// не висит. Ползунок F3 «Барашки» множит.
		float high = smoothstep(sea_height * CREST_H_LO,
			sea_height * CREST_H_HI, vertex_wave_h);
		float steep = smoothstep(CREST_STEEP_HI, CREST_STEEP_LO, nrm.y);
		float life = noise3d(vec3(world_pos.xz * 1.7,
			TIME * CREST_LIFE_SPEED));
		life = smoothstep(CREST_LIFE_LO, CREST_LIFE_HI, life);
		foam_mask = clamp(max(foam_mask,
			high * steep * life * CREST_MAX * foam_crest)
			* foam_amount, 0.0, 1.0);
	}
	// Круги вокруг ног — тоже пена (локально, без кружева; отдельный
	// тумблер F3 «Круги на воде»).
	foam_mask = max(foam_mask, rings_foam);

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
		* (1.0 - foam_mask) * edge;
	// Пена освещается светом сцены (в тени темнее): ALBEDO — сероватый
	// цвет маски, без обводок; непрозрачность — foam_alpha (0.5 —
	// полупрозрачное кружево, не выше по умолчанию).
	ALBEDO = foam_color.rgb * foam_mask;
	ALPHA = clamp(max(edge, foam_mask * foam_alpha), 0.0, 1.0);
	// Пена шершавая: roughness → 0.8 по массе.
	ROUGHNESS = mix(rough, 0.8, foam_mask);
	SPECULAR = specular * edge * (1.0 - foam_mask);
	METALLIC = metallic;
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);
}
