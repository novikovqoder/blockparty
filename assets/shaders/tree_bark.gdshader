// Кора деревьев Леса, сгенерированных EZ-Tree (П5.9, переделка под
// реальную демо-сцену): CC0-текстура ambientcg (тип — из пресета ez-tree),
// тайлинг по UV меша (обороты вокруг ствола запечены генератором в UV.x,
// вертикальная плотность — uv_scale.y = 1/textureScale.y, как repeat.y
// у three.js), тон — инстанс-тон острова. Ветвей ветер в демо нет —
// качаются только листья (canopy.gdshader).
shader_type spatial;
render_mode specular_disabled;

uniform sampler2D bark_tex : source_color, filter_linear_mipmap_anisotropic;
uniform vec2 uv_scale = vec2(1.0, 1.0);

void fragment() {
	ALBEDO = texture(bark_tex, UV * uv_scale).rgb * COLOR.rgb;
}

void light() {
	// Чуть расширенный Ламберт: кора скруглённая, не гранёная.
	float ndl = dot(NORMAL, LIGHT);
	float wrap = 0.15;
	float lambert = clamp((ndl + wrap) / (1.0 + wrap), 0.0, 1.0);
	// Слабый небесный заполнитель: ствол в тени кроны без него уходил бы
	// в уголь.
	float sky_fill = clamp(0.5 + 0.5 * NORMAL.y, 0.0, 1.0) * 0.15;
	float lit = max(lambert * ATTENUATION, sky_fill);
	DIFFUSE_LIGHT += LIGHT_COLOR * ALBEDO * lit;
}
