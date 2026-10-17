// Камни Леса (П5.9, блоки 3 и 5): глыбы с мхом по верхним граням.
// Мох растёт там, где мировая нормаль смотрит вверх, с рваным краем из
// двух шумов (крупные пятна + мелкая кромка); бока и низ — камень.
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
// Доля мха на отвесных боках: с высоты глаз (1.5 м) у приплюснутого
// купола виден почти только бок — верхняя грань занимает ничтожную долю
// экрана. Поэтому мох не «шапка вверх», а островки по всей видимой
// поверхности, лишь гуще к верху.
uniform float moss_side_density = 0.6;
// Масштаб островков мха и мелкой рваной кромки, пятна на метр поверхности.
// Островки ~0.17 м (эталон): на боку глыбы радиусом ~0.9 м читаются
// 5–10 отдельных точек мха; кромка в 2.5 раза мельче пятна — рваный край.
uniform float moss_patch_scale = 6.0;
uniform float moss_edge_scale = 14.0;
// Густота пятен (0 — голый камень, 1 — почти сплошной мох): сдвигает
// порог шума пятен. mrock — редко, rrock — заметно. Порог ниже прежнего
// решётчатого (0.71): симплекс колоколообразен и реже достигает краёв.
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
	// Мох — островки с резкой кромкой по всей видимой поверхности
	// (эталон: точки мха на 10–25% камня, не сплошная шапка и не
	// серо-зелёная смазань): порог по крупному шуму, мелкий шум рвёт
	// край, наклон лишь гущает пятна кверху и разрежает бока.
	float up = world_normal.y;
	float slope = mix(moss_side_density, 1.0, smoothstep(0.1, 0.65, up));
	float patch = snoise01(world_pos.xz * moss_patch_scale);
	float edge = snoise01(world_pos.xz * moss_edge_scale);
	// Порог под колоколообразное распределение симплекса (у решётчатого
	// value-noise оно было равномерным): 0.66 вместо 0.71 держит прежнюю
	// долю площади мха (mrock ~30%, rrock ~50% с добавками edge/up).
	float bias = 0.66 - 0.3 * moss_patch_strength;
	float spots = smoothstep(
		bias - 0.03, bias + 0.03,
		patch + 0.15 * (edge - 0.5) + 0.15 * (up - 0.5));
	float moss = slope * spots;
	ALBEDO = mix(rock_color, moss_color, moss) * COLOR.rgb;
	ROUGHNESS = mix(rock_roughness, 0.9, moss);
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
