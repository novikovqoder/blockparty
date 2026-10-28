// Дешёвая вода Born Unblessed (SPEC П14 4.7) для SIMPLE/NORMAL — копия
// water_bu.gdshader без экранной и глубинной текстур (копия экрана не
// бесплатна, уровень экономит): полупрозрачная поверхность цветом
// рассеяния, волны sea_octave (3 октавы и в vertex, и во fragment —
// нормали конечными разностями с шагом по дистанции), один слой ряби,
// пены и преломления нет. П15 3: отражение неба — движковое (IBL
// radiance Sky3D с френелем F0 ≈ 0.02); дорожка светила — спекуляр
// движка. Пиксельная фильтрация гасит субпиксельную рябь, наклон
// уходит в рост roughness с расстоянием. Палитра и uniform-имена —
// те же, что у полной версии (WaterArea ставит одинаковые параметры
// обоим шейдерам; iter_fragment здесь не читается — октавы константа).
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
// Высота вьюпорта в пикселях (для пиксельной фильтрации ряби; в этой
// версии нет screen texture — built-in SCREEN_PIXEL_SIZE недоступен,
// WaterArea ставит размер и обновляет при ресайзе окна).
uniform float screen_px_height = 720.0;
group_uniforms;

group_uniforms Waves;
// Волны sea_octave (туториал gameidea), как у полной версии; озеро
// спокойнее моря — константы ставит WaterArea.
uniform float sea_height : hint_range(0.0, 2.0) = 0.35;
uniform float sea_choppiness : hint_range(0.0, 10.0) = 4.0;
uniform float sea_speed : hint_range(0.0, 3.0) = 0.8;
uniform float sea_freq : hint_range(0.0, 0.5) = 0.08;
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

// Дешёвая версия: октав везде по 3 (без uniform-границы цикла).
const int ITER_GEOMETRY = 3;
const mat2 octave_m = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6));
const float NORMAL_EPS_M = 0.01;
const float NORMAL_SMOOTH_DIST = 50.0;
// П15 1-2: пороги пиксельной фильтрации ряби — те же, что в полной
// версии.
const float FILTER_MIN_PX = 2.0;
const float FILTER_MAX_PX = 4.0;

// Постоянная полупрозрачность дешёвой воды: без depth-буфера толщины
// нет, мелкое/глубокое не различить — лёгкая вуаль цвета рассеяния.
const float CHEAP_ALPHA = 0.82;

// Value-шум и октавы волн (туториал gameidea) — как в полной версии.
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

// Нормаль волн конечными разностями высоты (3 октавы, шаг растёт с
// расстоянием).
vec3 wave_normal_detailed(vec2 xz, float eps) {
	float h0 = wave_height_geo(xz, TIME);
	float hx = wave_height_geo(xz + vec2(eps, 0.0), TIME);
	float hz = wave_height_geo(xz + vec2(0.0, eps), TIME);
	return normalize(vec3(h0 - hx, eps, h0 - hz));
}

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
varying vec3 vertex_normal_world;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 cam_pos = INV_VIEW_MATRIX[3].xyz;
	float wave_fade = 1.0 - smoothstep(
		vertex_wave_fade_min, vertex_wave_fade_max,
		distance(wp.xz, cam_pos.xz));
	VERTEX.y += wave_height_geo(wp.xz, TIME) * wave_fade;
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
	float dist = length(CAMERA_POSITION_WORLD - world_pos);
	// Пикселей на радиан: PROJECTION_MATRIX[1][1] = 1/tan(fov/2);
	// высота экрана — uniform (screen texture в этой версии нет).
	float px_per_rad = screen_px_height / (2.0 * PROJECTION_MATRIX[1][1]);

	// Нормаль волн: детальная (3 октавы, шаг по дистанции), вдали —
	// переход к геометрической нормали vertex (как в полной версии).
	float lod_eps = max(NORMAL_EPS_M, dist * 0.005);
	vec3 nrm = wave_normal_detailed(world_pos.xz, lod_eps);
	float smooth_factor = clamp(
		(dist - NORMAL_SMOOTH_DIST) / 200.0, 0.0, 1.0);
	nrm = normalize(mix(nrm, vertex_normal_world, smooth_factor));
	float lost = smooth_factor;

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
