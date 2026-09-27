# NetworkManager: выбор транспорта (ENet для разработки, Steam для прода),
# подключение и хранение пиров, RPC-протокол, снапшоты (раздел 8 SPEC).
# Не делает на этапе 0: реальное подключение — этап 2; сейчас только определяет
# режим по аргументам командной строки и логирует его.
extends Node

## Активный режим сети: "none" | "dev-host" | "dev-join" | "steam".
var mode: String = "none"


func _ready() -> void:
	if Dev.host_mode and Dev.join_address != "":
		Log.warn("--dev-host и --dev-join вместе: клиентский режим проигнорирован", "Net")
	if Dev.host_mode:
		mode = "dev-host"
		Log.info("Режим разработки: хост ENet, порт %d (реализация — этап 2)" % Dev.DEV_PORT, "Net")
	elif Dev.join_address != "":
		mode = "dev-join"
		Log.info("Режим разработки: клиент ENet, адрес %s:%d (реализация — этап 2)" % [Dev.join_address, Dev.DEV_PORT], "Net")
	else:
		Log.info("Сеть не запущена (Steam-режим появится на этапе 4)", "Net")
	if Dev.net_lag_ms > 0 or Dev.net_loss_percent > 0:
		Log.info("Эмуляция сети: задержка %d мс, потеря %d%%" % [Dev.net_lag_ms, Dev.net_loss_percent], "Net")
	if Dev.log_net:
		Log.info("Подробный лог сетевых RPC включён", "Net")
