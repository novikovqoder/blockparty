// Дешёвая вода Born Unblessed (SPEC П14 4.7) для SIMPLE/NORMAL — копия
// water_bu.gdshader без экранной и глубинной текстур (копия экрана не
// бесплатна, уровень экономит): полупрозрачная поверхность цветом
// рассеяния, 8 волн Герстнера, один слой ряби, пены и преломления нет.
// П15 3: отражение неба — движковое (ранее отключавший IBL-отражения
// флаг рендера убран; движок кладёт radiance Sky3D с френелем
// F0 ≈ 0.02), ручного двухцветного неба нет; дорожка светила — спекуляр
// движка. П15 1-2: нормали спектра —
// во fragment по world_pos (в vertex только смещение волн длиннее 20 м),
// пиксельная фильтрация гасит субпиксельные волны, наклон уходит в
// рост roughness с расстоянием. Спектр и палитра — те же константы
// и uniform-имена полной версии (WaterArea ставит одинаковые параметры
// обоим шейдерам).
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled,
	specular_schlick_ggx;

group_uniforms Colors;
uniform vec4 color_shallow : source_color = vec4(0.10, 0.14, 0.10, 1.0);
uniform vec4 color_deep : source_color = vec4(0.016, 0.035, 0.028, 1.0);
uniform vec3 absorption = vec3(1.6, 0.75, 0.45);
group_uniforms;

group_uniforms Surface;
// П15 2: рост roughness с расстоянием (как у полной версии).
uniform float roughness_near : hint_range(0.0, 1.0) = 0.03;
uniform float roughness_far : hint_range(0.0, 1.0) = 0.16;
// П15 3: движковое отражение, F0 ≈ 0.02 (как у полной версии).
uniform float specular : hint_range(0.0, 1.0) = 0.25;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
// Нет ни преломления, ни depth — параметры приняты (общие имена), не
// используются: материал один и тот же у WaterArea на всех уровнях.
uniform float refraction_amount : hint_range(0.0, 4.0) = 1.0;
uniform float ripple_layers : hint_range(0.0, 3.0) = 1.0;
uniform float ripple_strength : hint_range(0.0, 2.0) = 1.0;
uniform float ripple_scale : hint_range(0.5, 2.0) = 1.0;
// Высота вьюпорта в пикселях (для пиксельной фильтрации волн; в этой
// версии нет screen texture — built-in SCREEN_PIXEL_SIZE недоступен,
// WaterArea ставит размер и обновляет при ресайзе окна).
uniform float screen_px_height = 720.0;
group_uniforms;

group_uniforms Waves;
uniform vec4 waves_a[32];
uniform vec4 waves_b[32];
uniform int wave_count = 8;
group_uniforms;

group_uniforms Fades;
uniform float distance_fade_min = 700.0;
uniform float distance_fade_max = 1400.0;
uniform float vertex_wave_fade_min = 380.0;
uniform float vertex_wave_fade_max = 800.0;
uniform float depth_fog_fade_min = 70.0;
uniform float depth_fog_fade_max = 130.0;
uniform float far_thickness = 8.0;
group_uniforms;

// П15 1-2: пороги пиксельной фильтрации и порог длинных волн — те же,
// что в полной версии.
const float FILTER_MIN_PX = 2.0;
const float FILTER_MAX_PX = 4.0;
const float VERTEX_WAVE_M = 20.0;

// Постоянная полупрозрачность дешёвой воды: без depth-буфера толщины
// нет, мелкое/глубокое не различить — лёгкая вуаль цвета рассеяния.
const float CHEAP_ALPHA = 0.82;

// Симплекс-шум 2D (Ian McEwan / Ashima Arts) — как в water_bu.
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

vec2 ripple_slope(vec2 p, vec2 dir, float scale, float speed, float t) {
	vec2 uv = p * scale + dir * (t * speed);
	float e = 0.35;
	float h0 = snoise(uv);
	float hx = snoise(uv + vec2(e, 0.0));
	float hz = snoise(uv + vec2(0.0, e));
	return vec2(hx - h0, hz - h0) / e;
}

float wave_weight(float lambda_m, float dist, float px_per_rad) {
	return smoothstep(FILTER_MIN_PX, FILTER_MAX_PX,
		px_per_rad * lambda_m / max(dist, 0.001));
}

varying vec3 world_pos;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 cam_pos = INV_VIEW_MATRIX[3].xyz;
	float wave_fade = 1.0 - smoothstep(
		vertex_wave_fade_min, vertex_wave_fade_max,
		distance(wp.xz, cam_pos.xz));
	// П15 1: только смещение длинных волн (нормали — во fragment).
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
	float dist = length(CAMERA_POSITION_WORLD - world_pos);
	// Пикселей на радиан: PROJECTION_MATRIX[1][1] = 1/tan(fov/2);
	// высота экрана — uniform (screen texture в этой версии нет).
	float px_per_rad = screen_px_height / (2.0 * PROJECTION_MATRIX[1][1]);

	// П15 1: нормали спектра попиксельно; П15 2: субпиксельные волны
	// гаснут, наклон уходит в roughness.
	vec3 nrm = vec3(0.0, 1.0, 0.0);
	float slope_total = 1e-6;
	float slope_kept = 0.0;
	for (int i = 0; i < 32; i++) {
		if (i >= wave_count) {
			break;
		}
		vec4 wa = waves_a[i];
		vec4 wb = waves_b[i];
		float weight = wave_weight(TAU / wa.z, dist, px_per_rad);
		float phi = wa.z * dot(wa.xy, world_pos.xz)
			- wb.x * TIME + wb.z;
		float s = sin(phi);
		float c = cos(phi);
		float wa_slope = wa.z * wa.w;
		nrm.x -= wa.x * wa_slope * c * weight;
		nrm.z -= wa.y * wa_slope * c * weight;
		nrm.y -= wb.y * wa_slope * s * weight;
		slope_total += wa_slope;
		slope_kept += wa_slope * weight;
	}
	nrm = normalize(nrm);
	float lost = clamp(1.0 - slope_kept / slope_total, 0.0, 1.0);

	// Один слой ряби (1.5 м, слабее прежнего) с той же фильтрацией.
	if (ripple_layers > 0.5 && ripple_strength > 0.001) {
		float weight = wave_weight(1.5 / ripple_scale, dist, px_per_rad);
		vec2 slope = ripple_slope(world_pos.xz,
			vec2(0.84, 0.54), 0.667 * ripple_scale, 0.35, TIME) * 0.020;
		nrm = normalize(nrm + vec3(slope.x, 0.0, slope.y)
			* weight * ripple_strength * 2.2);
		lost = max(lost, 1.0 - weight);
	}
	float rough = mix(roughness_near, roughness_far, lost);

	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - world_pos);
	// Без depth-буфера: дно не показываем, вода — вуаль рассеянного
	// цвета между мелководьем и глубиной (на глаз середина). Композит —
	// в EMISSION с ALBEDO = 0, ALPHA < 1 — полупрозрачная вуаль.
	// П15 3: отражение — движковое (radiance Sky3D, френель F0 ≈ 0.02);
	// ручной френель Шлика гасит эмиссию навстречу отражению, вдали
	// эмиссия растворяется (туман сводит горизонт).
	vec3 water = mix(color_shallow.rgb, color_deep.rgb, 0.55);

	float fresnel = 0.02 + 0.98
		* pow(1.0 - max(dot(nrm, view_dir), 0.0), 5.0);
	float dist_fade = 1.0 - smoothstep(
		distance_fade_min, distance_fade_max, dist);
	EMISSION = water * (1.0 - fresnel) * dist_fade;
	ALBEDO = vec3(0.0);
	ALPHA = CHEAP_ALPHA;
	ROUGHNESS = rough;
	SPECULAR = specular;
	METALLIC = metallic;
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);
}
