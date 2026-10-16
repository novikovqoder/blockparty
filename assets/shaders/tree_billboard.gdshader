// «Картинка» дальнего плана для процедурных деревьев Леса (П5.9, блок 4):
// плоский силуэт (крона по профилю + ствол), разворачиваемый на камеру
// вокруг вертикали. Цвет — вершинный градиент генератора × instance-тон;
// лёгкое качание ветром в такт кронам (canopy.gdshader). Нормаль считается
// по производным на грань — квад всегда развёрнут к зрителю.
shader_type spatial;
render_mode specular_disabled, cull_disabled, depth_draw_opaque;

uniform float tree_height = 10.0;
uniform vec2 wind_direction = vec2(0.85, 0.45);
uniform float wind_amplitude = 0.25;
uniform float wind_freq = 0.55;

void vertex() {
	// Центр инстанса и его средний масштаб (деревья почти изотропны).
	vec3 center = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float scale = length(MODEL_MATRIX[0].xyz);
	vec3 camera_world = INV_VIEW_MATRIX[3].xyz;
	vec3 to_cam = camera_world - center;
	to_cam.y = 0.0;
	to_cam /= max(length(to_cam), 0.001);
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), to_cam));
	float t = VERTEX.y / max(tree_height, 0.001);
	float phase = dot(center.xz, wind_direction) * 0.08;
	float sway = 0.6 * sin(TIME * wind_freq + phase)
		+ 0.3 * sin(2.3 * TIME * wind_freq + 1.7 * phase);
	vec3 world = center
		+ right * VERTEX.x * scale
		+ vec3(0.0, VERTEX.y * scale, 0.0)
		+ vec3(wind_direction.x, 0.0, wind_direction.y)
			* sway * wind_amplitude * t * t * scale;
	VERTEX = (INV_VIEW_MATRIX * vec4(world, 1.0)).xyz;
}

void fragment() {
	NORMAL = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	ALBEDO = COLOR.rgb;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float wrap = 0.5;
	float lambert = clamp((ndl + wrap) / (1.0 + wrap), 0.0, 1.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * ALBEDO * lambert;
}
