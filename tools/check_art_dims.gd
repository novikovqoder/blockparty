## Проверка печёного island_art.res под расширенную карту (сборка 1):
## длины массивов соответствуют POINTS 513, зоны содержат крылья.
## Хеши высот/предметов считаются по IslandGen.generate() в тестах GUT
## (блок 3) — здесь только соответствие печёного ресурса новой карте.
extends SceneTree


func _init() -> void:
	# Первый кадр: автолоады уже в дереве, зависимые скрипты компилируются
	# с готовыми глобальными именами (паттерн tools/generate_island.gd).
	await create_timer(0.01).timeout
	_check()


func _check() -> void:
	var art: IslandArt = load("res://gameplay/world/island_art.res")
	var points: int = IslandGen.POINTS
	var ok: bool = true
	if art.heights.size() != points * points:
		push_error("heights %d != %d" % [art.heights.size(), points * points])
		ok = false
	var zone_names: Array[String] = []
	for zone: Dictionary in IslandGen.ZONES:
		zone_names.append(zone["name"])
	for wing: String in ["cliffs", "thicket", "shore", "meadows"]:
		if wing not in zone_names:
			push_error("зоны нет: " + wing)
			ok = false
	print("art.points=%d heights=%d zones=%d chunks=%d colliders=%d groups=%d"
		% [points, art.heights.size(), zone_names.size(), art.chunks.size(),
			art.colliders.size(), art.prop_groups.size()])
	print("ART-CHECK " + ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
