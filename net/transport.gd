# Базовый транспорт сети (раздел 8 SPEC): интерфейс host_game()/join_game()/
# close(), сигналы подключения и единая точка отправки RPC — через send(),
# чтобы подкласс (EnetTransport) мог эмулировать плохую сеть. Весь остальной
# код не знает, какой транспорт активен.
# Не делает: сам не создаёт пиров — это делают EnetTransport (этап 2)
# и SteamTransport (этап 4).
class_name Transport
extends Node

## Подключился новый пир (на хосте — каждый клиент, на клиенте — хост).
signal peer_connected(peer_id: int)
## Пир отключился.
signal peer_disconnected(peer_id: int)
## Клиент потерял связь с хостом.
signal server_disconnected
## Не удалось подключиться к хосту.
signal connection_failed

## Активный пир (ENetMultiplayerPeer здесь, SteamMultiplayerPeer на этапе 4).
var peer: MultiplayerPeer = null
## Человекочитаемое имя транспорта для логов.
var transport_name: String = "none"


func host_game(_port: int) -> Error:
	return FAILED  # абстрактный метод


func join_game(_address: String, _port: int) -> Error:
	return FAILED


func close() -> void:
	peer = null


## Отправка RPC: call выполняет непосредственную отправку. Надёжные отправки
## эмулируются только задержкой, ненадёжные — задержкой и потерями.
func send(call: Callable, _unreliable: bool) -> void:
	call.call()


## Подключить сигналы SceneMultiplayer к своим сигналам (вызывается после
## установки multiplayer_peer). Повторное подключение не накапливается.
func wire_multiplayer(multiplayer: MultiplayerAPI) -> void:
	if not multiplayer.peer_connected.is_connected(_on_mp_peer_connected):
		multiplayer.peer_connected.connect(_on_mp_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_mp_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_mp_peer_disconnected)
	if not multiplayer.connected_to_server.is_connected(_on_mp_connected):
		multiplayer.connected_to_server.connect(_on_mp_connected)
	if not multiplayer.connection_failed.is_connected(_on_mp_connection_failed):
		multiplayer.connection_failed.connect(_on_mp_connection_failed)
	if not multiplayer.server_disconnected.is_connected(_on_mp_server_disconnected):
		multiplayer.server_disconnected.connect(_on_mp_server_disconnected)


func _on_mp_peer_connected(peer_id: int) -> void:
	peer_connected.emit(peer_id)


func _on_mp_peer_disconnected(peer_id: int) -> void:
	peer_disconnected.emit(peer_id)


func _on_mp_connected() -> void:
	# Успешное подключение клиента: хост придёт отдельным peer_connected.
	pass


func _on_mp_connection_failed() -> void:
	connection_failed.emit()


func _on_mp_server_disconnected() -> void:
	server_disconnected.emit()
