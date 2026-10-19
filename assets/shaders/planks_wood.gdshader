// Дерево настилов (доработка-2 П5.13, П5): причал, сваи, кнехты, ступени
// лестниц смотровых — текстура плах ambientCG Planks007 (CC0) трипланаром
// по мировой позиции и производной нормали (меши предметов не несят UV).
// Вершинный цвет меша тонирует доски (щели/прогоны читаются и цветом,
// и текстурой). Свет — та же двухступенчатая toon-модель lowpoly.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert,
	specular_schlick_ggx;

uniform sampler2D wood_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D wood_normal : filter_linear_mipmap_anisotropic;

// Тон дерева (линейный множитель: текстура серо-коричневая, палитра
// тёплая светлая — плахи высветляются).
uniform vec3 tint = vec3(1.28, 1.18, 1.02);
// Размер тайла плах, м (2K-карта ≈ 1.6 м досок).
uniform float tile_m = 1.6;
uniform float normal_strength = 0.7;
uniform float wood_roughness = 0.88;
uniform float wood_specular = 0.02;

// Тон теневой стороны граней — дефолт uniform shadow_tint lowpoly.
const vec3 SHADOW_TINT = vec3(0.82, 0.87, 0.98);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Плоская нормаль грани (меш без нормалей — как lowpoly.gdshader).
	vec3 face_n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));

	vec3 tri_w = pow(abs(face_n), vec3(4.0));
	tri_w /= (tri_w.x + tri_w.y + tri_w.z);
	vec2 uv_top = world_pos.xz / tile_m;
	vec2 uv_x = world_pos.zy / tile_m;
	vec2 uv_z = world_pos.xy / tile_m;

	ALBEDO = tint * COLOR.rgb * (
		tri_w.y * texture(wood_tex, uv_top).rgb
		+ tri_w.x * texture(wood_tex, uv_x).rgb
		+ tri_w.z * texture(wood_tex, uv_z).rgb);
	ROUGHNESS = wood_roughness;

	// Нормали волокон — как у кладки: две компоненты карты в мировом
	// базисе доминирующей плоскости, тангентного пространства нет.
	float sx = sign(face_n.x);
	float sz = sign(face_n.z);
	vec2 n_top = texture(wood_normal, uv_top).rg * 2.0 - 1.0;
	vec2 n_x = texture(wood_normal, uv_x).rg * 2.0 - 1.0;
	vec2 n_z = texture(wood_normal, uv_z).rg * 2.0 - 1.0;
	vec3 perturb = normal_strength * (
		tri_w.y * (n_top.x * vec3(1.0, 0.0, 0.0) + n_top.y * vec3(0.0, 0.0, 1.0))
		+ tri_w.x * (n_x.x * vec3(0.0, 0.0, sx) + n_x.y * vec3(0.0, 1.0, 0.0))
		+ tri_w.z * (n_z.x * vec3(sz, 0.0, 0.0) + n_z.y * vec3(0.0, 1.0, 0.0)));
	vec3 world_n = normalize(face_n + perturb);
	NORMAL = normalize((VIEW_MATRIX * vec4(world_n, 0.0)).xyz);
}

// Свет — toon-модель lowpoly.gdshader: дерево в одном стиле с миром.
void light() {
	float ndl = dot(NORMAL, LIGHT);
	float step1 = smoothstep(0.0, 0.35, ndl);
	float step2 = smoothstep(0.35, 0.75, ndl);
	float shade = 0.35 * step1 + 0.65 * step2;
	vec3 tinted = mix(ALBEDO * SHADOW_TINT, ALBEDO, shade);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * tinted * shade;
	vec3 half_v = normalize(LIGHT + VIEW);
	float ndh = max(dot(NORMAL, half_v), 0.0);
	float a2 = ROUGHNESS * ROUGHNESS;
	a2 *= a2;
	float d_ggx = a2 / (3.14159 * pow(ndh * ndh * (a2 - 1.0) + 1.0, 2.0));
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * d_ggx * wood_specular;
}
