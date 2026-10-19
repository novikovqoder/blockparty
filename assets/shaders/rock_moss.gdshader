// Камни Леса (П5.9, блоки 3 и 5): глыбы с мхом по верхним граням.
// Доработка-2 П5.13, П7: мох — только по верхним граням с мягким
// переходом (не «островки по всей поверхности» и не полосы), цвет и
// фактура — текстура ambientCG Moss001 (CC0) трипланаром по мировой
// позиции (меш глыб не несёт UV); кромку пятен рвут два симплекс-шума
// (крупные пятна + мелкая кромка). Бока и низ — камень.
// П5.9 переделка П2: решётчатый value-noise (hash12/vnoise на квадратной
// сетке) заменён симплексом — у решётчатого шума на боках глыб и склонах
// проступали осевые «полосы» (тот же дефект, что владелец видел на земле
// П5.7; планка качества: никаких полосатых паттернов в шейдере).
// Цвета — из visual_palette.tres. Свет — тот же мягкий wrap-Ламберт,
// что у земли и травы Леса, плюс лёгкая шероховатость мокрого камня
// (GGX, слабая) — камень читается объёмом, но не «пластиком».
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert,
	specular_schlick_ggx;

uniform vec3 rock_color : source_color = vec3(0.51, 0.53, 0.54);
uniform vec3 moss_color : source_color = vec3(0.36, 0.45, 0.25);
// Текстура мха (ambientCG Moss001, CC0) и нормировка её среднего тона
// к палитровому moss_color: текстура линейно ~ (0.22, 0.22, 0.11),
// множитель по каналам возвращает итог к тону палитры, сохраняя фактуру.
uniform sampler2D moss_tex : source_color, filter_linear_mipmap_anisotropic;
uniform vec3 moss_tint = vec3(4.5, 4.5, 9.0);
// Тайл фактуры мха, м.
uniform float moss_tile_m = 1.3;
// Масштаб островков мха и мелкой рваной кромки, пятна на метр поверхности.
uniform float moss_patch_scale = 6.0;
uniform float moss_edge_scale = 14.0;
// Густота пятен (0 — голый камень, 1 — почти сплошной мох): сдвигает
// порог шума пятен. mrock — редко, rrock — заметно.
uniform float moss_patch_strength = 0.35;
// Блик мокрого камня.
uniform float rock_roughness = 0.65;
uniform float rock_specular = 0.02;

varying vec3 world_pos;
varying vec3 world_normal;

// Симплекс-шум 2D (Ian McEwan / Ashima Arts, публичный webgl-noise) —
// тот же, что в forest_ground.gdshader; решётчатой структуры нет.
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

float snoise01(vec2 p) {
	return 0.5 + 0.5 * simplex2d(p);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Мох — по верхним граням с мягким переходом (доработка-2 П5.13, П7):
	// маска наклона широкой ступенью (0.15→0.75), порог крупных пятен
	// с широкой кромкой (±0.06) — ни резкой границы, ни «полос»; бока
	// и низ — чистый камень.
	float up = world_normal.y;
	float slope = smoothstep(0.15, 0.75, up);
	float patch = snoise01(world_pos.xz * moss_patch_scale);
	float edge = snoise01(world_pos.xz * moss_edge_scale);
	// Порог под колоколообразное распределение симплекса: moss_patch_
	// strength сдвигает его вниз (rrock гуще, mrock/зубцы реже).
	float bias = 0.62 - 0.5 * moss_patch_strength;
	float spots = smoothstep(
		bias - 0.06, bias + 0.06,
		patch + 0.2 * (edge - 0.5) + 0.1 * (up - 0.5));
	float moss = slope * spots;
	// Фактура мха — Moss001 трипланаром (веса по сглаженной нормали глыбы):
	// на верхних гранях — проекция XZ, на покатых боках у кромки — своя.
	vec3 tri_w = pow(abs(world_normal), vec3(4.0));
	tri_w /= (tri_w.x + tri_w.y + tri_w.z);
	vec2 muv_top = world_pos.xz / moss_tile_m;
	vec2 muv_x = world_pos.zy / moss_tile_m;
	vec2 muv_z = world_pos.xy / moss_tile_m;
	vec3 moss_rgb = moss_color * moss_tint * (
		tri_w.y * texture(moss_tex, muv_top).rgb
		+ tri_w.x * texture(moss_tex, muv_x).rgb
		+ tri_w.z * texture(moss_tex, muv_z).rgb);
	ALBEDO = mix(rock_color, moss_rgb, moss) * COLOR.rgb;
	ROUGHNESS = mix(rock_roughness, 0.95, moss);
}

void light() {
	float ndl = dot(world_normal, LIGHT);
	float wrap = 0.25;
	float lambert = clamp((ndl + wrap) / (1.0 + wrap), 0.0, 1.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * ALBEDO * lambert;
	vec3 half_v = normalize(LIGHT + VIEW);
	float ndh = max(dot(world_normal, half_v), 0.0);
	float a2 = ROUGHNESS * ROUGHNESS;
	a2 *= a2;
	float d_ggx = a2 / (3.14159 * pow(ndh * ndh * (a2 - 1.0) + 1.0, 2.0));
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * d_ggx * rock_specular;
}
