// Импосторы дальних деревьев (П17 п.3): вертикальный quad-биллборд,
// кадр атласа (8 азимутов × 2 подъёма, tools/bake_tree_impostors.gd)
// выбирается в vertex по направлению «дерево → камера» в пространстве
// объекта — инстансы повёрнуты произвольным yaw, атлас базы один на все
// варианты (квад масштабируется трансформом). Освещение — по атласу
// нормалей (нормали запечены в базисе кадра: right/up/к камере) тем же
// wrap-Ламбертом с небесным заполнителем и просветом, что у кроны
// (canopy.gdshader) — стык «меш ↔ импостор» на 90 м читается слабо.
// Ветра нет (90+ м), тень не отбрасывает (IslandView).
shader_type spatial;
render_mode specular_disabled, cull_disabled, depth_draw_opaque;

uniform sampler2D atlas_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : filter_linear_mipmap_anisotropic;
uniform float alpha_cut = 0.3;
// Раскладка атласа — как запекал тула (manifest.json рядом с атласами).
uniform int cols = 4;
uniform int rows = 4;
uniform int azimuth_steps = 8;
// Порог подъёма камеры между рядами: sin(17°) между ракурсами 8° и 26°.
uniform float elev_threshold = 0.292;
// Полупиксельный подворот UV внутрь ячейки — без подмешивания соседа.
const float CELL_PAD = 1.0 / 256.0;

varying vec2 frame_uv;
varying vec3 bb_right;
varying vec3 bb_up;
varying vec3 bb_forward;
varying vec3 world_pos;

// П17 п.4 «Туман крон»: тот же тон и старт, что у canopy.gdshader —
// стык «меш ↔ импостор» не должен читаться и по туману (90–400 м).
const vec3 FOG_TINT = vec3(0.435, 0.613, 0.715);
const float FOG_DENSITY = 0.004;

vec4 fog(vec3 position_world, vec3 camera_world) {
	float depth = length(position_world - camera_world);
	float amount = 1.0 - exp(-pow(depth * FOG_DENSITY, 2.0));
	return vec4(FOG_TINT, amount);
}

void vertex() {
	// Направление на камеру в пространстве объекта (yaw инстанса уже
	// учтён — кадры атласа пеклись с дерева без поворота).
	vec3 camera_world = (inverse(VIEW_MATRIX) * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 to_cam = normalize(
		(inverse(MODEL_MATRIX) * vec4(camera_world, 1.0)).xyz);
	// Кадр: ближайший азимут из 8 (шаг 45°) + ряд по подъёму камеры.
	float azimuth = atan(to_cam.x, to_cam.z);
	float step_f = round(azimuth / 6.2831853 * float(azimuth_steps));
	int step = int(mod(step_f + float(azimuth_steps), float(azimuth_steps)));
	int col = step % cols;
	int row = step / cols
		+ (to_cam.y > elev_threshold ? rows / 2 : 0);
	vec2 cell = vec2(float(col), float(row));
	vec2 inner = clamp(UV, vec2(CELL_PAD), vec2(1.0 - CELL_PAD));
	frame_uv = (cell + inner) / vec2(float(cols), float(rows));
	// Цилиндрический биллборд: центр квада на оси дерева, поворот вокруг
	// Y к камере (X-смещение вершины уходит в right, высота не меняется).
	vec3 flat_dir = normalize(vec3(to_cam.x, 0.0, to_cam.z));
	VERTEX = vec3(VERTEX.x * flat_dir.z, VERTEX.y, -VERTEX.x * flat_dir.x);
	// Базис кадра в view-space — для нормалей из атласа (запечены в том
	// же базисе: right = UP × к камере, up, вперёд к камере).
	vec3 right_obj = vec3(flat_dir.z, 0.0, -flat_dir.x);
	bb_right = (VIEW_MATRIX * (MODEL_MATRIX * vec4(right_obj, 0.0))).xyz;
	bb_up = (VIEW_MATRIX * (MODEL_MATRIX * vec4(0.0, 1.0, 0.0, 0.0))).xyz;
	bb_forward = (VIEW_MATRIX * (MODEL_MATRIX * vec4(flat_dir, 0.0))).xyz;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 normal_map = texture(normal_tex, frame_uv).rgb * 2.0 - 1.0;
	NORMAL = normalize(
		bb_right * normal_map.x + bb_up * normal_map.y
		+ bb_forward * normal_map.z);
	vec4 face = texture(atlas_tex, frame_uv);
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ALPHA = face.a;
	ALBEDO = face.rgb * COLOR.rgb;
	FOG = fog(world_pos, CAMERA_POSITION_WORLD);
}

void light() {
	// Тот же свет, что у кроны (canopy.gdshader): wrap-Ламберт, небесный
	// заполнитель теневой стороны и просвет солнца насквозь.
	float ndl = dot(NORMAL, LIGHT);
	float wrap = 0.5;
	float lambert = clamp((ndl + wrap) / (1.0 + wrap), 0.0, 1.0);
	float sky_fill = clamp(0.5 + 0.5 * NORMAL.y, 0.0, 1.0) * 0.25;
	float lit = max(lambert * ATTENUATION, sky_fill);
	DIFFUSE_LIGHT += LIGHT_COLOR * ALBEDO * lit;
	float backlight = pow(max(-dot(VIEW, LIGHT), 0.0), 2.5);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * ALBEDO * backlight * 0.55;
}
