extends RefCounted
# П10 (уборка мира): тесты «наследия» — жители, костёр, сидения, запечённый
# остров с ними — гоняются при выключенном bu_legacy_hidden (в balance.tres
# он true: в мире Born Unblessed наследия нет). before_all выключает,
# after_all возвращает дефолт игры. Флаг переключается статикой класса:
# перезагрузки скриптов в GUT создают копии ресурса, статика одна на всех.


static func legacy_off() -> void:
	Balance.set_legacy_hidden(false)


static func legacy_restore() -> void:
	Balance.set_legacy_hidden(true)
