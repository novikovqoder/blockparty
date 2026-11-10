// Поверхности района (постапокалипсис): бетон, кирпич, асфальт, металл.
// Обычный PBR по UV в метрах (UV = метры, tile_m — размер повтора) +
// слой мха/грязи пятнами мирового шума (гуще у земли) + тон вершины
// (у панелей дома он свой на каждую панель). Набор текстур — Poly Haven:
// diffuse, nor_gl, arm (AO, шероховатость, металл).
shader_type spatial;
render_mode cull_back;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D arm_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile_m : hint_range(0.1, 32.0) = 2.0;
uniform vec3 tint : source_color = vec3(1.0);
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;
uniform float rough_mult : hint_range(0.0, 2.0) = 1.0;
uniform float metal_mult : hint_range(0.0, 1.0) = 0.0;
// Мох и грязь: доля покрытия, размер пятен (м), усиление у земли (до высоты, м).
uniform float moss_amount : hint_range(0.0, 1.0) = 0.25;
uniform float moss_patch_m : hint_range(0.2, 40.0) = 5.0;
uniform float moss_ground_m : hint_range(0.0, 10.0) = 1.5;
uniform vec3 moss_tint : source_color = vec3(1.0);
// Потёки на стенах (вертикальные тёмные полосы от дождя) и грязь у земли.
uniform float streak_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec3 streak_tint : source_color = vec3(0.36, 0.33, 0.27);

varying vec3 world_pos;
varying vec3 world_nrm;

// Simplex noise 2D: https://github.com/ashima/webgl-noise (MIT) — тот же порт,
// что в ez_lab_ground.gdshader (решётчатый value-noise в проекте запрещён).
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

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = UV / tile_m;
	vec3 base = texture(albedo_tex, uv).rgb * tint * COLOR.rgb;
	vec3 arm = texture(arm_tex, uv).rgb;
	// Пятна: два масштаба шума; у земли и на горизонтальных полках гуще.
	// Плоскость шума наклонена: пятна меняются и по земле, и по стенам.
	vec2 np = vec2(world_pos.x + world_pos.z * 0.7, world_pos.y + world_pos.z * 0.3);
	float n = (0.5 + 0.5 * simplex2d(np / moss_patch_m)) * 0.65
		+ (0.5 + 0.5 * simplex2d(np / (moss_patch_m * 0.23) + 7.3)) * 0.35;
	float low = 1.0 - smoothstep(0.0, max(moss_ground_m, 0.001), world_pos.y);
	float ledge = smoothstep(0.5, 0.95, world_nrm.y);
	float cover = moss_amount + low * 0.35 * step(0.001, moss_ground_m)
		+ ledge * 0.25 * moss_amount;
	float m = smoothstep(1.0 - cover - 0.08, 1.0 - cover + 0.08, n)
		* step(0.001, moss_amount);
	vec3 moss = texture(moss_tex, UV / 1.7).rgb * moss_tint;
	// Потёки: шум, сильно вытянутый по вертикали UV стены (UV.y — высота).
	float wall = 1.0 - smoothstep(0.35, 0.6, abs(world_nrm.y));
	float st = 0.5 + 0.5 * simplex2d(vec2(UV.x * 1.9, UV.y * 0.07) + 31.7);
	float st2 = 0.5 + 0.5 * simplex2d(vec2(UV.x * 0.35, UV.y * 0.3) + 5.1);
	float streak = smoothstep(0.55, 0.85, st) * smoothstep(0.3, 0.7, st2)
		+ (1.0 - smoothstep(0.0, 1.2, world_pos.y)) * 0.6;
	base = mix(base, base * streak_tint * 1.6, clamp(streak, 0.0, 1.0) * streak_amount * wall);
	ALBEDO = mix(base, moss, m * 0.85);
	ROUGHNESS = clamp(mix(arm.g * rough_mult, 0.95, m), 0.03, 1.0);
	METALLIC = arm.b * metal_mult * (1.0 - m);
	AO = arm.r;
	AO_LIGHT_AFFECT = 0.4;
	NORMAL_MAP = texture(normal_tex, uv).rgb;
	NORMAL_MAP_DEPTH = normal_strength * (1.0 - m * 0.6);
}
