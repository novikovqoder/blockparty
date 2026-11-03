// Кора деревьев Леса, сгенерированных EZ-Tree (П5.9, переделка под
// реальную демо-сцену): CC0-текстура ambientcg (тип — из пресета ez-tree),
// тайлинг по UV меша (обороты вокруг ствола запечены генератором в UV.x,
// вертикальная плотность — uv_scale.y = 1/textureScale.y, как repeat.y
// у three.js), тон — инстанс-тон острова (П17 п.2 — с вариацией по дереву).
// П17 п.2: PBR-карты — нормали (NORMAL_MAP, рельеф бороздок в диффузном
// свете) и шероховатость; спекуляр включён умеренно (SPECULAR 0.3, без
// него карта шероховатости не действовала бы) — формула Блинна-Фонга как
// в стандартном материале движка, в нашем light().
// Ветвей ветер в демо нет — качаются только листья (canopy.gdshader).
shader_type spatial;

uniform sampler2D bark_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : filter_linear_mipmap_anisotropic;
uniform sampler2D roughness_tex : filter_linear_mipmap_anisotropic;
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform float bark_specular = 0.3;

void fragment() {
	vec2 bark_uv = UV * uv_scale;
	ALBEDO = texture(bark_tex, bark_uv).rgb * COLOR.rgb;
	NORMAL_MAP = texture(normal_tex, bark_uv).rgb;
	ROUGHNESS = texture(roughness_tex, bark_uv).r;
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
	// Спекуляр по шероховатости карты (экспонента — как в fallback'е
	// движка): мягкий отблеск на бороздках, не «пластик». SPECULAR в
	// light() не читается — сила из uniform bark_specular.
	vec3 half_vec = normalize(LIGHT + VIEW);
	float gloss = pow(1.0 - clamp(ROUGHNESS, 0.0, 1.0), 2.0);
	float exponent = mix(1.0, 128.0, gloss);
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION
		* pow(max(dot(NORMAL, half_vec), 0.0), exponent) * bark_specular;
}
