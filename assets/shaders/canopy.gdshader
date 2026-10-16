// Крона процедурных деревьев Леса (П5.9, блок 4): квады листьев с мягкой
// маской (круглый лист / узкая хвойная лапка) вместо фототекстуры, цвет —
// вершинный (глубина кроны запечена генератором) × instance-тон зоны.
// Свет — wrap-Ламберт с широким переносом (крона читается мягким объёмом,
// а не пучком плоскостей) и просвет солнца сквозь листву: лист,
// подсвеченный с обратной стороны, добавляет тёплого свечения краю кроны.
// Ветер — волны по мировой позиции (согласован с травой grass_field).
shader_type spatial;
render_mode specular_disabled, cull_disabled, depth_draw_opaque;

// 0 — круглый лист лиственных, 1 — узкая хвойная лапка.
uniform float needle_shape : hint_range(0.0, 1.0) = 0.0;
uniform vec2 wind_direction = vec2(0.85, 0.45);
uniform float wind_amplitude = 0.25;
uniform float wind_freq = 0.55;

varying vec3 world_pos;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Качание волнами: две синусоиды от фазы по ветру + высокочастотный
	// рябь; вес растёт с высотой листа — ствол стоит, крона плывёт.
	float phase = dot(world_pos.xz, wind_direction) * 0.08;
	float t = TIME * wind_freq;
	float sway = 0.6 * sin(t + phase) + 0.3 * sin(2.3 * t + 1.7 * phase);
	float weight = smoothstep(0.5, 6.0, VERTEX.y);
	vec3 shift = vec3(wind_direction.x, 0.0, wind_direction.y)
		* sway * wind_amplitude * weight;
	vec4 mv = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	mv.xyz += (VIEW_MATRIX * vec4(shift, 0.0)).xyz;
	VERTEX = (INV_VIEW_MATRIX * mv).xyz;
}

void fragment() {
	vec2 uv = UV - vec2(0.5);
	// Рваный край от мирового положения — соседние листья различимы.
	float noise = hash12(world_pos.xz * 3.7 + uv * 11.0) - 0.5;
	float mask;
	float r = length(uv * vec2(1.25, 1.0)) + noise * 0.14;
	float needle = step(0.5, needle_shape);
	// Лист: круглая мягкая маска; хвоя: вертикальная полоса с зубцами.
	float leaf_mask = smoothstep(0.5, 0.38, r);
	float needle_mask = smoothstep(0.34, 0.22, abs(uv.x) + noise * 0.1)
		* smoothstep(0.55, 0.35, abs(uv.y));
	mask = mix(leaf_mask, needle_mask, needle);
	if (mask < 0.5) {
		discard;
	}
	ALBEDO = COLOR.rgb;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float wrap = 0.5;
	float lambert = clamp((ndl + wrap) / (1.0 + wrap), 0.0, 1.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * ALBEDO * lambert;
	// Просвет насквозь: солнце за кроной относительно камеры.
	float backlight = pow(max(-dot(VIEW, LIGHT), 0.0), 2.5);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * ALBEDO * backlight * 0.55;
}
