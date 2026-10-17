// Кора процедурных деревьев Леса (П5.9, доработка под эталон EZ-Tree):
// CC0-текстура ambientcg, тайлинг по UV меша (обороты по окружности —
// в UV.x меша, плотность по вертикали — uv_scale), тон — вершинный.
// Ветер — то же качание волнами, что у кроны (canopy.gdshader), без
// дрожи: ветки и крона движутся вместе, листва не «отрывается» от веток.
// Вес растёт с высотой — комель неподвижен, верхушки живут.
shader_type spatial;
render_mode specular_disabled;

uniform sampler2D bark_tex : source_color, filter_linear_mipmap_anisotropic;
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform vec2 wind_direction = vec2(0.85, 0.45);
uniform float wind_amplitude = 0.25;
uniform float wind_freq = 0.55;

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float phase = dot(world_pos.xz, wind_direction) * 0.08;
	float t = TIME * wind_freq;
	float gust = 0.75 + 0.25 * sin(dot(world_pos.xz, vec2(0.05, 0.035)) + TIME * 0.6);
	float sway = (0.6 * sin(t + phase) + 0.3 * sin(2.3 * t + 1.7 * phase)) * gust;
	float weight = smoothstep(0.5, 6.0, VERTEX.y);
	vec3 shift = vec3(wind_direction.x, 0.0, wind_direction.y)
		* sway * wind_amplitude * weight;
	vec4 mv = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	mv.xyz += (VIEW_MATRIX * vec4(shift, 0.0)).xyz;
	VERTEX = (INV_VIEW_MATRIX * mv).xyz;
}

void fragment() {
	ALBEDO = texture(bark_tex, UV * uv_scale).rgb * COLOR.rgb;
}

void light() {
	// Чуть расширенный Ламберт: кора скруглённая, не гранёная.
	float ndl = dot(NORMAL, LIGHT);
	float wrap = 0.15;
	float lambert = clamp((ndl + wrap) / (1.0 + wrap), 0.0, 1.0);
	// Слабый небесный заполнитель — как у кроны, но тише: ствол глубже
	// в кроне и без него уходил бы в уголь в тени дерева.
	float sky_fill = clamp(0.5 + 0.5 * NORMAL.y, 0.0, 1.0) * 0.15;
	float lit = max(lambert * ATTENUATION, sky_fill);
	DIFFUSE_LIGHT += LIGHT_COLOR * ALBEDO * lit;
}
