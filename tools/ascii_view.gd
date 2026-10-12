# Отладочный просмотр PNG в ASCII (headless, без внешних сервисов):
#   godot --headless -s tools/ascii_view.gd -- <png> [ширина]
extends SceneTree
const RAMP: String = " .:-=+*#%@"

func _init() -> void:
	await create_timer(0.01).timeout
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("путь к png?")
		quit(1)
		return
	var img := Image.load_from_file(args[0])
	if img == null:
		push_error("не читается " + args[0])
		quit(1)
		return
	var w: int = args[1].to_int() if args.size() > 1 else 96
	var h: int = maxi(2, int(float(w) * float(img.get_height()) / float(img.get_width()) * 0.45))
	img.resize(w, h)
	var colors := {}
	var lines: PackedStringArray = []
	for y: int in h:
		var row := ""
		for x: int in w:
			var c := img.get_pixel(x, y)
			var lum: float = c.get_luminance() * c.a
			row += RAMP[clampi(int(lum * float(RAMP.length() - 1)), 0, RAMP.length() - 1)]
			var key := c.to_html(true)
			colors[key] = colors.get(key, 0) + 1
		lines.append(row)
	print("\n".join(lines))
	var top: Array = colors.keys()
	top.sort_custom(func(a, b): return colors[a] > colors[b])
	var summary: PackedStringArray = []
	for i: int in mini(6, top.size()):
		summary.append("%s x%d" % [top[i], colors[top[i]]])
	print("цвета: " + ", ".join(summary))
	quit(0)
