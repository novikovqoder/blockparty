# Группа предметов «тип:вариант» в запечённом острове (island_art.res) —
# чистые данные: меш-эталон и по экземпляру трансформ с тоном зоны.
# MultiMesh собирается в рантайме (to_multimesh): инстанс-данные самого
# MultiMesh не переживают запекание headless-скриптом — set_instance_transform
# уходит в пустой RenderingServer, buffer остаётся нулевым, и после
# ResourceSaver все предметы схлопывались в невидимые точки. Массивы же
# сериализуются надёжно, а в игре рендер-сервер настоящий.
class_name PropGroup
extends Resource

## Меш-эталон группы (PropMeshes/Cc0Meshes, «ногами» в origin).
@export var mesh: Mesh
## Трансформы экземпляров: поворот по yaw, масштаб, позиция на рельефе.
@export var transforms: Array[Transform3D] = []
## Тон зоны для каждого экземпляра (шейдер lowpoly умножает на цвет вершин).
@export var colors: PackedColorArray = PackedColorArray()


## Собрать MultiMesh группы в рантайме (IslandView._build_props).
func to_multimesh() -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i: int in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_color(i, colors[i])
	return mm
