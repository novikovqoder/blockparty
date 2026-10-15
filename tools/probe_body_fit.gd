# Д4 (тело под одеждой): прогон BodyFitCheck по всем комбинациям одежды
# (Peasant/Ranger × оба пола) с замерами — ДО/ПОСЛЕ запекания.
#   godot --headless --path . -s res://tools/probe_body_fit.gd
# character_model.gd тянет GraphicsQuality → autoload Settings, а в режиме
# -s autoload-идентификаторы регистрируются только после старта: сцена,
# BodyFitCheck и модель грузятся в рантайме (parse-time типы CharacterModel/
# BodyFitCheck здесь нельзя — graphics_quality.gd не соберётся).
extends SceneTree

const MODEL_PATH: String = "res://gameplay/player/character_model.tscn"
const CHECK_PATH: String = "res://gameplay/player/body_fit_check.gd"


func _init() -> void:
	await create_timer(0.01).timeout
	var model_scene := load(MODEL_PATH) as PackedScene
	var check := load(CHECK_PATH) as GDScript
	var fails := 0
	for gender: int in Appearance.GENDERS:
		for top: int in Appearance.OUTFITS.size():
			var model := model_scene.instantiate() as Node3D
			root.add_child(model)
			var ap := Appearance.default_for(gender)
			ap.top = top
			ap.legs = top
			ap.feet = top
			model.call("setup_appearance", ap)
			var started := Time.get_ticks_msec()
			var result: Dictionary = check.run(model, true)
			var secs := float(Time.get_ticks_msec() - started) / 1000.0
			var m: Dictionary = result["metrics"]
			print("пол %d %s: %s за %.1f с — пар %d, поз %d, макс выступ "
				% [gender, Appearance.OUTFITS[top],
				"OK" if result["ok"] else "FAIL", secs,
				m.get("skin_covered_verts", 0), m.get("poses_checked", 0)]
				+ " %.1f мм (%s), края вне одежды %d/%d" % [
				m.get("poke_max_m", 0.0) * 1000.0,
				m.get("poke_worst_pose", "?"),
				m.get("skin_open_outside", 0), m.get("skin_open_verts", 0)])
			for reason: String in result["reasons"]:
				print("    %s" % reason)
			if not result["ok"]:
				fails += 1
			model.free()
	quit(0 if fails == 0 else 1)
