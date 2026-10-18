# Режим материалов для headless-прогонов (доработка-2 П5.13, П8). Без рендера
# (godot --headless, сервер, тесты GUT) фабрики материалов отдают плоские
# заглушки — логика игры от рендера не зависит. Но тест аудита поверхностей
# «нет меша без текстуры» должен видеть МИР ТАКИМ, КАК В WINDOWS-СБОРКЕ:
# тест включает textured_headless перед инстанцированием острова, фабрики
# отдают настоящие шейдерные материалы (создание ShaderMaterial и текстур
# в headless безопасно — они не рендерятся), после теста флаг сбрасывается.
class_name WorldMaterials
extends RefCounted


## Headless-прогонам отдавать настоящие материалы (флаг теста аудита).
static var textured_headless: bool = false


## Плоскую заглушку хочет только настоящий headless без флага теста.
static func want_flat() -> bool:
	return DisplayServer.get_name() == "headless" and not textured_headless
