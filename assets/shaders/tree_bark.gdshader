// Кора деревьев Леса, сгенерированных EZ-Tree (П5.9, переделка под
// реальную демо-сцену): CC0-текстура ambientcg (тип — из пресета ez-tree),
// тайлинг по UV меша (обороты вокруг ствола запечены генератором в UV.x,
// вертикальная плотность — uv_scale.y = 1/textureScale.y, как repeat.y
// у three.js), тон — инстанс-тон острова (П17 п.2 — с вариацией по дереву).
// П18 Сборка 1 п.1 «Материалы как в демо»: свой light() убран — свет
// считает стандартный PBR Godot (у демо MeshStandardMaterial): Ламберт по
// NORMAL_MAP, спекуляр по ROUGHNESS из карты, METALLIC = 0 (демо:
// metalness 0, roughnessMap при скаляре 1.0). Ветвей ветер в демо нет —
// качаются только листья (canopy.gdshader).
shader_type spatial;

uniform sampler2D bark_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : filter_linear_mipmap_anisotropic;
uniform sampler2D roughness_tex : filter_linear_mipmap_anisotropic;
uniform vec2 uv_scale = vec2(1.0, 1.0);

void fragment() {
	vec2 bark_uv = UV * uv_scale;
	ALBEDO = texture(bark_tex, bark_uv).rgb * COLOR.rgb;
	NORMAL_MAP = texture(normal_tex, bark_uv).rgb;
	ROUGHNESS = texture(roughness_tex, bark_uv).r;
	METALLIC = 0.0;
}
