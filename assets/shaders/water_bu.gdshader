// Вода Born Unblessed (SPEC П14 4): свой шейдер вместо Boujie — текстур
// аддона нет вовсе (пена и рябь процедурные). Полная версия для HIGH/ULTRA:
// экранная текстура + буфер глубины дают толщину воды под пикселем →
// поглощение Бера ПО КАНАЛАМ (красный гаснет первым: дно на мелком видно
// чётко, к глубине — тёмная торфяная/стальная вода), преломление —
// смещение выборки экрана по нормали волн (с проверкой глубины выборки —
// предметы над водой не рвутся). Композит собирается вручную и пишется
// в EMISSION с ALPHA = 1 и ALBEDO = 0 (один альфа-канал блендинга не
// передаст поканальное поглощение, нулевой альбедо гасит диффуз и
// окружение): небо — френель Шлика цветами DayCycle (update_sky),
// дорожка светила — спекуляр движка (луна ночью). Нормали: спектр волн
// Герстнера (массивы
// waves_a/waves_b, считает WaterArea детерминированным RNG) суммируется
// в vertex() (смещение + нормаль + сжатие гребней), поверх во fragment —
// 2–3 слоя процедурной ряби (2D-симплекс), к дали гаснет. Дешёвая версия
// для SIMPLE/NORMAL — water_bu_cheap.gdshader (без экранной выборки).
// Сетка: море — Ocean-кольца аддона (сетка), озеро — PlaneMesh; ноды
// воды без поворота и масштаба, поэтому смещение и нормали считаются
// сразу в мировых координатах (MODEL_MATRIX — только перенос).
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled,
	ambient_light_disabled, specular_schlick_ggx;

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
// Небо для френеля (update_sky): у горизонта и в зените — отражение
// красится ими, ночью оба тёмные.
uniform vec3 sky_horizon : source_color = vec3(0.7, 0.75, 0.8);
uniform vec3 sky_top : source_color = vec3(0.3, 0.45, 0.7);
group_uniforms;

group_uniforms Surface;
uniform float roughness : hint_range(0.0, 1.0) = 0.03;
uniform float specular : hint_range(0.0, 1.0) = 0.5;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
// Сила преломления (панель F3 «Преломление воды»: 0 — без смещения
// выборки, толщина и Бер остаются).
uniform float refraction_amount : hint_range(0.0, 4.0) = 1.0;
// Слои ряби: 2 на HIGH, 3 на ULTRA (F3 «Рябь воды» — 0).
uniform float ripple_layers : hint_range(0.0, 3.0) = 2.0;
group_uniforms;

group_uniforms Waves;
// Спектр волн Герстнера (до 32; первые wave_count — по уровню качества,
// самые длинные первыми, поэтому HIGH=16 — подмножество ULTRA=32):
//   waves_a[i] = (dir.x, dir.y, k = 2π/λ, амплитуда_м)
//   waves_b[i] = (ω, крутизна Q, фаза, вес пены гребня)
// Считает WaterArea.wave_spectrum детерминированным RNG (SPEC 4.3).
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
// скорость у каждого слоя свои, масштаб уменьшается вдвое.
vec2 ripple_slope(vec2 p, vec2 dir, float scale, float speed, float t) {
	vec2 uv = p * scale + dir * (t * speed);
	float e = 0.35;
	float h0 = snoise(uv);
	float hx = snoise(uv + vec2(e, 0.0));
	float hz = snoise(uv + vec2(0.0, e));
	return vec2(hx - h0, hz - h0) / e;
}

varying vec3 world_pos;
varying vec3 wave_normal;
// Сжатие гребней (якобиан Герстнера): к 1 на гребнях зыби — там пена.
varying float crest;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Гашение волн вдали: внешние кольца Ocean грубые, дальше — плоскость.
	vec3 cam_pos = INV_VIEW_MATRIX[3].xyz;
	float wave_fade = 1.0 - smoothstep(
		vertex_wave_fade_min, vertex_wave_fade_max,
		distance(wp.xz, cam_pos.xz));
	// Спектр Герстнера (GPU Gems 1, гл. 1): смещение XZ по направлению
	// волны, Y — синус; нормаль и сжатие — из тех же сумм (один проход).
	vec3 disp = vec3(0.0);
	vec3 nrm = vec3(0.0, 1.0, 0.0);
	float crest_sum = 0.0;
	for (int i = 0; i < 32; i++) {
		if (i >= wave_count) {
			break;
		}
		vec4 wa = waves_a[i];
		vec4 wb = waves_b[i];
		float amp = wa.w * wave_fade;
		float phi = wa.z * dot(wa.xy, wp.xz) - wb.x * TIME + wb.z;
		float s = sin(phi);
		float c = cos(phi);
		float qa = wb.y * amp;
		disp += vec3(wa.x * qa * c, amp * s, wa.y * qa * c);
		nrm.x -= wa.x * wa.z * amp * c;
		nrm.z -= wa.y * wa.z * amp * c;
		nrm.y -= wb.y * wa.z * amp * s;
		crest_sum += wb.w * wb.y * wa.z * amp * s;
	}
	wp += disp;
	// Ноды воды без поворота/масштаба: мировое смещение = локальному,
	// нормаль сразу мировая (осям объекта доверять нельзя — нода едет
	// за камерой, MODEL_MATRIX — перенос).
	VERTEX += disp;
	wave_normal = normalize(nrm);
	crest = crest_sum;
	world_pos = wp;
}

void fragment() {
	// Мировая нормаль: движок даёт NORMAL в пространстве вида — рябь
	// добавляется в мировых координатах (не «плывёт» за камерой).
	vec3 nrm = normalize(
		(INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - world_pos);
	float dist = length(CAMERA_POSITION_WORLD - world_pos);

	// Рябь (SPEC 4.3): 2–3 слоя шума в разных направлениях и скоростях,
	// к дали гаснет (против мерцания); масштабы 2.2 / 1.1 / 0.55 м.
	if (ripple_layers > 0.5 && dist < 120.0) {
		float ripple_fade = 1.0 - smoothstep(30.0, 110.0, dist);
		vec2 slope = vec2(0.0);
		slope += ripple_slope(world_pos.xz,
			vec2(0.84, 0.54), 0.45, 0.35, TIME) * 0.030;
		if (ripple_layers > 1.5) {
			slope += ripple_slope(world_pos.xz,
				vec2(-0.47, 0.88), 0.90, -0.50, TIME) * 0.022;
		}
		if (ripple_layers > 2.5) {
			slope += ripple_slope(world_pos.xz,
				vec2(0.36, -0.93), 1.80, 0.80, TIME) * 0.016;
		}
		nrm = normalize(nrm + vec3(slope.x, 0.0, slope.y)
			* ripple_fade * 2.2);
	}

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

	// Пена без текстур (SPEC 4.5): тонкая разорванная полоса в первых
	// сантиметрах толщины и на гребнях морской зыби. Веса гребней
	// нормированы в WaterArea.wave_spectrum так, что совпадение фаз
	// длинных волн даёт crest ≈ 0.55 — порог ловит только реальные
	// гребни, где сошлись несколько волн зыби.
	float foam_noise = snoise(world_pos.xz * 2.6 + vec2(TIME * 0.25));
	float foam = (1.0 - smoothstep(0.01, FOAM_SHORE_M, thickness))
		* step(0.15, foam_noise);
	foam += smoothstep(0.35, 0.55, crest) * step(0.0, foam_noise)
		* (1.0 - smoothstep(60.0, 140.0, surf_dist));
	water = mix(water, FOAM_COLOR, clamp(foam, 0.0, 1.0));

	// Небо — френель Шлика (SPEC 4.4): под острым углом зеркало, сверху
	// прозрачная вода; цвет отражения — небо у горизонта/в зените (цвета
	// update_sky, ночью тёмные). ROUGHNESS 0.02–0.05, спекуляр движка
	// даёт дорожку солнца/луны. Весь композит — в EMISSION, ALBEDO = 0:
	// диффуз и окружение не подсвечивают толщу.
	float fresnel = 0.02 + 0.98
		* pow(1.0 - max(dot(nrm, view_dir), 0.0), 5.0);
	vec3 refl_dir = reflect(-view_dir, nrm);
	vec3 sky_refl = mix(sky_horizon, sky_top,
		clamp(pow(max(refl_dir.y, 0.0), 0.6), 0.0, 1.0));
	vec3 color = water + sky_refl * fresnel;

	// Растворение к горизонту цветом неба — дальняя плоскость без
	// резкой границы (туман и небо у горизонта одного тона).
	float dist_fade = 1.0 - smoothstep(
		distance_fade_min, distance_fade_max, surf_dist);
	EMISSION = mix(sky_horizon, color, dist_fade);
	ALBEDO = vec3(0.0);
	ALPHA = 1.0;
	ROUGHNESS = roughness;
	SPECULAR = specular;
	METALLIC = metallic;
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);
}
