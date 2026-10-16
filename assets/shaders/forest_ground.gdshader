// Земля Леса (П5.9, блок 2): крупные цветовые пятна из палитры вместо
// фототекстур. Сектор [-128..0)² острова красится поверх тех же low-poly
// чанков — меш и коллизия не меняются. Пятна: подстилка с тёмными
// разводами, камень на крутых склонах, влажная земля в низинах, пятна мха,
// тропа и утоптанная Площадь — веса те же, что запекал ForestGround для
// фототекстур П5.7 (карта 128 × 128, 1 пиксель = 1 м), поэтому «карта»
// рельефа и механики не тронуты. Цвета приходят uniform-ами из
// assets/visual_palette.tres (правится без кода). Минимум мелкого
// «фотошума» (SPEC 16 «Визуальная цель»): из шумов остаются только
// крупные пятна (~6 м) и макровариация яркости (~25 м).
// Край сектора гасится border_map: RGB — точный цвет соседнего low-poly
// чанка (TerrainBuilder.point_color), A — вес края: у самой границы цвет
// и свет растворяются в плоской грани соседа, шва нет.
// Свет: внутри — мягкий wrap-Ламберт и сглаженная к вертикали нормаль
// (рельеф читается мягким объёмом, без огранки), у края — в точности
// та же toon-модель и плоская нормаль, что у соседних low-poly чанков.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert,
	specular_schlick_ggx;

// Цвета пятен (source_color — sRGB в линейный переводит движок).
uniform vec3 litter_color : source_color = vec3(0.52, 0.41, 0.29);
uniform vec3 litter_dark_color : source_color = vec3(0.42, 0.31, 0.22);
uniform vec3 wet_color : source_color = vec3(0.31, 0.26, 0.20);
uniform vec3 moss_color : source_color = vec3(0.33, 0.44, 0.24);
uniform vec3 rock_color : source_color = vec3(0.53, 0.54, 0.55);
uniform vec3 path_color : source_color = vec3(0.61, 0.50, 0.36);

// Карты покраски сектора (128 × 128, край — clamp).
uniform sampler2D weight_map : filter_linear;
uniform sampler2D border_map : source_color, filter_linear;

// Крупные тёмные разводы подстилки (~1/patch_scale метров).
uniform float patch_scale = 0.16;
// Макровариация яркости полян и склонов.
uniform float macro_scale = 0.04;
uniform float macro_strength = 0.10;
// Сглаживание огранки рельефа: 0 — плоские грани, 1 — шары.
uniform float soften = 0.55;
// Блик влажной земли (грубость и сила).
uniform float wet_roughness = 0.45;
uniform float wet_specular = 0.03;

// Тон теневой стороны граней — тот же, что дефолт uniform shadow_tint
// шейдера lowpoly (соседние чанки): у края Лес считается светом соседа.
const vec3 SHADOW_TINT = vec3(0.82, 0.87, 0.98);

varying vec3 world_pos;
// Вес края сектора (border_map.a), семплится в vertex: он нужен в light(),
// а туда varyings из fragment() не передаются.
varying float edge_w;

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
	vec2 sector_uv = (world_pos.xz + vec2(128.0)) / 128.0;
	edge_w = textureLod(border_map, sector_uv, 0.0).a;
}

void fragment() {
	vec2 sector_uv = (world_pos.xz + vec2(128.0)) / 128.0;
	vec4 w = texture(weight_map, sector_uv);
	vec4 border = texture(border_map, sector_uv);

	// Подстилка с крупными тёмными разводами.
	float patch = vnoise(world_pos.xz * patch_scale);
	vec3 albedo = mix(litter_color, litter_dark_color,
		smoothstep(0.35, 0.65, patch));

	// Оверлеи по весам карты (веса почти не пересекаются: камень на
	// склонах, влага в низинах, мох не на камне).
	float total = clamp(w.r + w.g + w.b + w.a, 0.0, 1.0);
	vec3 overlay = (
		rock_color * w.r
		+ wet_color * w.g
		+ moss_color * w.b
		+ path_color * w.a);
	albedo = mix(albedo, overlay, total);

	// Макровариация яркости: поляна неоднородна крупными пятнами.
	albedo *= 1.0 + macro_strength * (vnoise(world_pos.xz * macro_scale) - 0.5) * 2.0;

	// Край сектора: тонировка цветом соседней зоны, у границы вес 1 —
	// плоский цвет соседа.
	albedo = mix(albedo, border.rgb, border.a);

	ALBEDO = albedo;
	ROUGHNESS = mix(mix(0.95, wet_roughness, clamp(w.g, 0.0, 1.0)), 0.95, border.a);

	// Нормаль: плоская грань рельефа, сглаженная к вертикали (мягкий
	// объём), у самой границы — в точности плоская грань соседа.
	vec3 flat_n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	NORMAL = normalize(mix(flat_n, vec3(0.0, 1.0, 0.0), soften * (1.0 - edge_w)));
}

// Прямой свет: внутри сектора — мягкий wrap-Ламберт, к краю — в точности
// та же двухступенчатая toon-модель, что в light() шейдера lowpoly.
void light() {
	float ndl = dot(NORMAL, LIGHT);
	float wrap = 0.35;
	float lambert = clamp((ndl + wrap) / (1.0 + wrap), 0.0, 1.0);
	vec3 wrap_diff = LIGHT_COLOR * ATTENUATION * ALBEDO * lambert;
	float step1 = smoothstep(0.0, 0.35, ndl);
	float step2 = smoothstep(0.35, 0.75, ndl);
	float shade = 0.35 * step1 + 0.65 * step2;
	vec3 toon = LIGHT_COLOR * ATTENUATION
		* mix(ALBEDO * SHADOW_TINT, ALBEDO, shade) * shade;
	DIFFUSE_LIGHT += mix(wrap_diff, toon, edge_w);
	// Влажная земля чуть блещет (D-член GGX, диэлектрик F ≈ 0.04);
	// у соседа спекуляра нет — к краю блик гасится.
	vec3 half_v = normalize(LIGHT + VIEW);
	float ndh = max(dot(NORMAL, half_v), 0.0);
	float a2 = ROUGHNESS * ROUGHNESS;
	a2 *= a2;
	float d_ggx = a2 / (3.14159 * pow(ndh * ndh * (a2 - 1.0) + 1.0, 2.0));
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * d_ggx * wet_specular * (1.0 - edge_w);
}
