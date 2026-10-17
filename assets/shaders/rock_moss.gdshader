// Камни Леса (П5.9, блоки 3 и 5): глыбы с мхом по верхним граням.
// Мох растёт там, где мировая нормаль смотрит вверх, с рваным краем из
// двух шумов (крупные пятна + мелкая кромка); бока и низ — камень.
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
// порог шума пятен. mrock — редко, rrock — заметно.
uniform float moss_patch_strength = 0.35;
// Блик мокрого камня.
uniform float rock_roughness = 0.65;
uniform float rock_specular = 0.02;

varying vec3 world_pos;
varying vec3 world_normal;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
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
	float patch = vnoise(world_pos.xz * moss_patch_scale);
	float edge = vnoise(world_pos.xz * moss_edge_scale);
	float bias = 0.71 - 0.3 * moss_patch_strength;
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
