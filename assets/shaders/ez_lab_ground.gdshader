// Земля лаборатории ezTree (П18-ЛАБОРАТОРИЯ): формула демо
// (src/app/ground.js) на ровной плоскости — микс текстур травы и грунта
// по пятнистости симплекс-шума: n = 0.5 + 0.5·simplex2d(world.xz / scale),
// s = smoothstep(patchiness−0.1, patchiness+0.1, n),
// albedo = mix(grass, dirt, s). Текстуры демо ground/grass.jpg и
// ground/dirt_*.jpg заменены CC0-эквивалентами проекта (Grass001
// ambientCG, forest_ground_05 Poly Haven — замены оформлены ещё на П5.9,
// см. assets/third_party/LICENSES.md). Нормали грунта — на оба слоя, как
// в демо (единый normalMap материала); UV демо world.xz/30 ед. через
// k = 0.38 → 11.4 м на повтор.
// Simplex noise 2D: https://github.com/ashima/webgl-noise (MIT), порт тот
// же, что в forest_ground.gdshader.
shader_type spatial;
render_mode cull_back;

uniform sampler2D grass_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D dirt_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D dirt_normal : filter_linear_mipmap_anisotropic;
// Размер повтора текстур, м (демо 30 ед. × k), и масштаб пятен шума, м
// (демо GrassOptions.scale = 100 ед. × k).
uniform float tex_tile_m : hint_range(0.1, 64.0) = 11.4;
uniform float noise_scale_m : hint_range(1.0, 128.0) = 38.0;
// Пятнистость демо (GrassOptions.patchiness = 0.7).
uniform float patchiness : hint_range(0.0, 1.0) = 0.7;

varying vec3 world_pos;

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
}

void fragment() {
	vec2 uv = world_pos.xz / tex_tile_m;
	vec3 grass_color = texture(grass_tex, uv).rgb;
	vec3 dirt_color = texture(dirt_tex, uv).rgb;
	float n = 0.5 + 0.5 * simplex2d(world_pos.xz / noise_scale_m);
	float s = smoothstep(patchiness - 0.1, patchiness + 0.1, n);
	ALBEDO = mix(grass_color, dirt_color, s);
	NORMAL_MAP = texture(dirt_normal, uv).rgb;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
