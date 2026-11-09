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
// П18-ЛАБОРАТОРИЯ: ползунок «цвет коры» (LightTuner). Дефолт-белый —
// нейтральный множитель, картинка мира не меняется.
uniform vec3 bark_tint : source_color = vec3(1.0);
// Тинт коры из пресета ez-tree (как color у MeshStandardMaterial демо).
uniform vec3 preset_tint : source_color = vec3(1.0);

// bu-claude: тот же туман, что у крон (canopy.gdshader, П17 п.4) — раньше
// листва уходила в тёмно-зелёный тон, а ветки в светлый движковый туман и
// читались бледно-серыми «скелетами» на фоне тёмных крон.
const vec3 FOG_TINT = vec3(0.435, 0.613, 0.715);
const float FOG_DENSITY = 0.004;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 bark_uv = UV * uv_scale;
	ALBEDO = texture(bark_tex, bark_uv).rgb * COLOR.rgb * bark_tint * preset_tint;
	NORMAL_MAP = texture(normal_tex, bark_uv).rgb;
	ROUGHNESS = texture(roughness_tex, bark_uv).r;
	METALLIC = 0.0;
	// кора почти не блестит: тонкие ветки не ловят отражение яркого неба
	SPECULAR = 0.25;
	float depth = length(world_pos - CAMERA_POSITION_WORLD);
	FOG = vec4(FOG_TINT, 1.0 - exp(-pow(depth * FOG_DENSITY, 2.0)));
}
