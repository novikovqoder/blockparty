// Вода Born Unblessed (SPEC П14 4, П15 — третья итерация): свой шейдер
// вместо Boujie — текстур аддона нет вовсе (пена и рябь процедурные).
// Полная версия для HIGH/ULTRA: экранная текстура + буфер глубины дают
// толщину воды под пикселем → поглощение Бера ПО КАНАЛАМ (красный гаснет
// первым: дно на мелком видно чётко, к глубине — тёмная торфяная/стальная
// вода), преломление — смещение выборки экрана по нормали волн (с
// проверкой глубины выборки — предметы над водой не рвутся). Композит
// собирается вручную и пишется в EMISSION с ALPHA = 1 и ALBEDO = 0 (один
// альфа-канал блендинга не передаст поканальное поглощение, нулевой
// альбедо гасит диффуз). П15 3: отражение неба — движковое (ранее
// отключавший IBL-отражения флаг рендера убран; движок кладёт
// radiance Sky3D с френелем F0 ≈ 0.02), ручного двухцветного неба
// больше нет; дорожка светила — спекуляр движка.
// П15 1-2: нормали ВСЕГО спектра считаются попиксельно во fragment по
// world_pos (до смещения) — нормаль не зависит от плотности сетки, швов
// на стыках колец Ocean нет; в vertex() — только смещение длинных волн
// (λ > VERTEX_WAVE_M). П15 2: Toksvig-подобная фильтрация с расстоянием —
// волны мельче 2-4 пикселей экрана гаснут, их наклон уходит в рост
// roughness (зеркало вблизи, матовое у горизонта). Рябь мельче и слабее
// (1.5/0.75/0.3 м), та же фильтрация. Дешёвая версия для SIMPLE/NORMAL —
// water_bu_cheap.gdshader (без экранной выборки). Сетка: море —
// Ocean-кольца аддона, озеро — PlaneMesh; ноды воды без поворота и
// масштаба, координаты сразу мировые (MODEL_MATRIX — только перенос).
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
// Высота вьюпорта в пикселях (для пиксельной фильтрации волн): built-in
// SCREEN_PIXEL_SIZE в 4.7.2 из fragment-кода не виден — WaterArea ставит
// размер и обновляет его при ресайзе окна.
uniform float screen_px_height = 720.0;
group_uniforms;

group_uniforms Waves;
// Спектр волн Герстнера (до 32; первые wave_count — по уровню качества,
// самые длинные первыми, поэтому HIGH=16 — подмножество ULTRA=32):
//   waves_a[i] = (dir.x, dir.y, k = 2π/λ, амплитуда_м)
//   waves_b[i] = (ω, крутизна Q, фаза, вес пены гребня)
// Считает WaterArea.wave_spectrum детерминированным RNG (SPEC 4.3).
// П15 1: нормали — во fragment по world_pos (до смещения); смещение
// геометрии — только волны длиннее VERTEX_WAVE_M (короткие живут
// нормалями, поверхность не «рвёт» грубая сетка колец).
uniform vec4 waves_a[32];
uniform vec4 waves_b[32];
uniform int wave_count = 16;
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

// П15 1-2: пороги пиксельной фильтрации волн — мельче 2 пикселей волна
// гасится полностью, крупнее 4 — учитывается целиком (Toksvig/LEAN).
const float FILTER_MIN_PX = 2.0;
const float FILTER_MAX_PX = 4.0;
// Длиннее этой волны — смещение геометрии в vertex() (П15 1).
const float VERTEX_WAVE_M = 20.0;

// Пена без текстур: полоса у кромки (первые сантиметры толщины) и
// гребни морской зыби, разорванные шумом (SPEC П14 4.5).
const float FOAM_SHORE_M = 0.10;
const vec3 FOAM_COLOR = vec3(0.84, 0.88, 0.90);

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

// П15 2: вес волны по её экранному размеру (λ на дистанции dist):
// мельче FILTER_MIN_PX пикселей — 0 (наклон уйдёт в roughness),
// крупнее FILTER_MAX_PX — 1. Пикселей на радиан (px_per_rad) считается
// в теле fragment: built-in SCREEN_PIXEL_SIZE в функциях недоступен.
float wave_weight(float lambda_m, float dist, float px_per_rad) {
	return smoothstep(FILTER_MIN_PX, FILTER_MAX_PX,
		px_per_rad * lambda_m / max(dist, 0.001));
}

varying vec3 world_pos;

void vertex() {
	// Исходная мировая позиция (до смещения): по ней fragment считает
	// нормали всего спектра — Герстнер аналитичен, точка отсчёта не
	// смещена (GPU Gems 1, гл. 1).
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Гашение волн вдали: внешние кольца Ocean грубые, дальше — плоскость.
	vec3 cam_pos = INV_VIEW_MATRIX[3].xyz;
	float wave_fade = 1.0 - smoothstep(
		vertex_wave_fade_min, vertex_wave_fade_max,
		distance(wp.xz, cam_pos.xz));
	// П15 1: только смещение длинных волн — нормали и пена считаются
	// во fragment попиксельно. Ноды воды без поворота/масштаба:
	// мировое смещение = локальному.
	vec3 disp = vec3(0.0);
	for (int i = 0; i < 32; i++) {
		if (i >= wave_count) {
			break;
		}
		vec4 wa = waves_a[i];
		vec4 wb = waves_b[i];
		if (TAU / wa.z <= VERTEX_WAVE_M) {
			continue;
		}
		float amp = wa.w * wave_fade;
		float phi = wa.z * dot(wa.xy, wp.xz) - wb.x * TIME + wb.z;
		float qa = wb.y * amp;
		disp += vec3(
			wa.x * qa * cos(phi), amp * sin(phi), wa.y * qa * cos(phi));
	}
	VERTEX += disp;
	world_pos = wp;
}

void fragment() {
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - world_pos);
	float dist = length(CAMERA_POSITION_WORLD - world_pos);
	// Пикселей на радиан по вертикали экрана: PROJECTION_MATRIX[1][1] =
	// 1/tan(fov/2), высота экрана — uniform screen_px_height.
	float px_per_rad = screen_px_height / (2.0 * PROJECTION_MATRIX[1][1]);

	// П15 1: нормаль всего спектра — попиксельно по world_pos (до
	// смещения). П15 2: волны мельче 2-4 пикселей гаснут (вес wave_weight),
	// их доля наклона (lost) переводится в roughness — зеркальная вода
	// вблизи, мягко-матовая у горизонта, без пятен и мерцания.
	vec3 nrm = vec3(0.0, 1.0, 0.0);
	float crest = 0.0;
	float slope_total = 1e-6;
	float slope_kept = 0.0;
	for (int i = 0; i < 32; i++) {
		if (i >= wave_count) {
			break;
		}
		vec4 wa = waves_a[i];
		vec4 wb = waves_b[i];
		float lambda_m = TAU / wa.z;
		float weight = wave_weight(lambda_m, dist, px_per_rad);
		float phi = wa.z * dot(wa.xy, world_pos.xz)
			- wb.x * TIME + wb.z;
		float s = sin(phi);
		float c = cos(phi);
		float wa_slope = wa.z * wa.w;  // k·A — масштаб наклона волны
		nrm.x -= wa.x * wa_slope * c * weight;
		nrm.z -= wa.y * wa_slope * c * weight;
		nrm.y -= wb.y * wa_slope * s * weight;
		crest += wb.w * wb.y * wa_slope * s * weight;
		slope_total += wa_slope;
		slope_kept += wa_slope * weight;
	}
	nrm = normalize(nrm);
	float lost = clamp(1.0 - slope_kept / slope_total, 0.0, 1.0);

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
	float rough = mix(roughness_near, roughness_far, lost);

	// Толщина воды под пикселем: глубина сцены минус глубина поверхности
	// (оба — дистанции вдоль взгляда; на мелком у берега → 0).
	float scene_raw = texture(depth_tex, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, scene_raw);
	vec4 view_pos = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_pos.xyz /= view_pos.w;
	float surf_dist = -VERTEX.z;
	float thickness = max(-view_pos.z - surf_dist, 0.0);
	// Вдали depth-буфер неточен: толщина — «глубокая» константа.
	float depth_fade = 1.0 - smoothstep(
		depth_fog_fade_min, depth_fog_fade_max, surf_dist);
	thickness = mix(far_thickness, thickness, depth_fade);

	// Преломление: выборка экрана смещена по наклону волн; сила падает
	// с дистанцией. Если смещённая точка ближе поверхности (предмет над
	// водой) — берём прямую выборку, без разрывов.
	vec2 refr_off = nrm.xz * 0.05 * refraction_amount
		* (1.0 - smoothstep(6.0, 60.0, surf_dist));
	vec2 refr_uv = SCREEN_UV + refr_off;
	float check_raw = texture(depth_tex, refr_uv).r;
	vec3 check_ndc = vec3(refr_uv * 2.0 - 1.0, check_raw);
	vec4 check_pos = INV_PROJECTION_MATRIX * vec4(check_ndc, 1.0);
	check_pos.xyz /= check_pos.w;
	if (-check_pos.z < surf_dist - 0.05) {
		refr_uv = SCREEN_UV;
	}
	vec3 bottom = texture(screen_tex, refr_uv).rgb;

	// Поглощение Бера по каналам (SPEC 4.1): красный гаснет первым —
	// дно на мелком видно чисто, с глубиной уходит в цвет воды.
	// Композит вручную и ALPHA = 1: один альфа блендинга не передаст
	// поканальное поглощение.
	vec3 transmit = exp(-absorption * thickness);
	float deep_mix = 1.0 - exp(-thickness * 0.9);
	vec3 scatter = mix(color_shallow.rgb, color_deep.rgb, deep_mix);
	vec3 water = bottom * transmit + scatter * (1.0 - transmit);

	// Пена без текстур (SPEC 4.5, П15 4 — только smoothstep): тонкая
	// разорванная полоса в первых сантиметрах толщины и на гребнях
	// морской зыби. Веса гребней нормированы в WaterArea.wave_spectrum
	// так, что совпадение фаз длинных волн даёт crest ≈ 0.55.
	float foam_noise = snoise(world_pos.xz * 2.6 + vec2(TIME * 0.25));
	float foam = (1.0 - smoothstep(0.01, FOAM_SHORE_M, thickness))
		* smoothstep(0.05, 0.30, foam_noise);
	foam += smoothstep(0.35, 0.55, crest)
		* smoothstep(-0.2, 0.2, foam_noise)
		* (1.0 - smoothstep(60.0, 140.0, surf_dist));
	foam = clamp(foam, 0.0, 1.0);
	water = mix(water, FOAM_COLOR, foam);

	// П15 3: отражение — движковое: отключавший IBL флаг рендера убран,
	// движок сам кладёт на воду radiance настоящего неба Sky3D (облака, солнце,
	// луна), отфильтрованную по ROUGHNESS, с френелем Шлика и
	// F0 ≈ 0.02 (SPECULAR 0.25); дорожка светила — спекуляр движка.
	// ALBEDO = 0 гасит диффузный ambient — окружение не «подсвечивает»
	// толщу. Здесь остаётся «пропущенный свет» (дно × поглощение +
	// рассеяние): френель Шлика — та же формула, что у движка — гасит
	// его навстречу отражению: под острым углом видно небо, сверху —
	// толща. Вдали эмиссия растворяется, остаётся зеркало неба, и
	// горизонт сводит туман (туман и небо у горизонта — одна палитра).
	float fresnel = 0.02 + 0.98
		* pow(1.0 - max(dot(nrm, view_dir), 0.0), 5.0);
	float dist_fade = 1.0 - smoothstep(
		distance_fade_min, distance_fade_max, surf_dist);
	EMISSION = water * (1.0 - fresnel) * dist_fade;
	ALBEDO = vec3(0.0);
	ALPHA = 1.0;
	ROUGHNESS = rough;
	SPECULAR = specular;
	METALLIC = metallic;
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);
}
