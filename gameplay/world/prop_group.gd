# Группа предметов «тип:вариант» в запечённом острове (island_art.res) —
# чистые данные: меш-эталон и по экземпляру трансформ с тоном зоны.
# MultiMesh собирается в рантайме (to_multimesh): инстанс-данные самого
# MultiMesh не переживают запекание headless-скриптом — set_instance_transform
# уходит в пустой RenderingServer, buffer остаётся нулевым, и после
# ResourceSaver все предметы схлопывались в невидимые точки. Массивы же
# сериализуются надёжно, а в игре рендер-сервер настоящий.
class_name PropGroup
extends Resource

## Меш-эталон группы (PropMeshes, «ногами» в origin).
@export var mesh: Mesh
## Дальние уровни детализации деревьев (П5.9): [LOD1, LOD2] — генерация
## ez-tree с прореженными секциями и листьями (материалы в мешах).
@export var lods: Array[Mesh] = []
## Трансформы экземпляров: поворот по yaw, масштаб, позиция на рельефе.
@export var transforms: Array[Transform3D] = []
## Тон зоны для каждого экземпляра (шейдер lowpoly умножает на цвет вершин).
@export var colors: PackedColorArray = PackedColorArray()


## Собрать MultiMesh группы в рантайме (IslandView._build_props);
## mesh_override — дальний уровень детализации дерева вместо эталона.
func to_multimesh(mesh_override: Mesh = null) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh_override if mesh_override != null else mesh
	mm.instance_count = transforms.size()
	for i: int in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_color(i, colors[i])
	return mm


## MultiMesh подмножества экземпляров (секторная разбивка деревьев,
## расширение карты, сборка 1 п.4): indices — экземпляры одного
## пространственного сектора группы; меши и порядок — как у to_multimesh.
func to_multimesh_subset(
	mesh_override: Mesh, indices: PackedInt32Array
) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh_override
	mm.instance_count = indices.size()
	for i: int in indices.size():
		mm.set_instance_transform(i, transforms[indices[i]])
		mm.set_instance_color(i, colors[indices[i]])
	return mm
