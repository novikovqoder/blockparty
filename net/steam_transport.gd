# Транспорт продакшн-сети (разделы 2, 11 SPEC): SteamMultiplayerPeer через
# Steam Datagram Relay. Мир = Steam-лобби, его владелец — хост (listen-server
# как в ENet-режиме, раздел 10). Правило «обращения к Steam только в
# steam_service.gd» здесь касается синглтона Steam; SteamMultiplayerPeer —
# пир мультиплеера, аналог ENetMultiplayerPeer в EnetTransport.
# Эмуляция плохой сети (--net-lag/--net-loss) не применяется: это инструмент
# dev-режима ENet, реальную задержку даёт сам SDR.
# Не делает: голос (П6, канал 2 у пире уже зарезервирован).
class_name SteamTransport
extends Transport

## Лобби-мир, к которому подключён транспорт.
var lobby_id: int = 0


func setup(lobby: int) -> void:
	lobby_id = lobby
	transport_name = "steam"


## Поднять мир: слушать подключения участников лобби (вызывает владелец).
func host_lobby(lobby: int) -> Error:
	var steam_peer := SteamMultiplayerPeer.new()
	var err: Error = steam_peer.host_with_lobby(lobby)
	if err != OK:
		Log.error("Steam: host_with_lobby(%d) не удался (код %d)" % [lobby, err], "Net")
		return err
	peer = steam_peer
	return OK


## Подключиться к миру-лобби: хостом будет его владелец.
func join_lobby(lobby: int) -> Error:
	var steam_peer := SteamMultiplayerPeer.new()
	var err: Error = steam_peer.connect_to_lobby(lobby)
	if err != OK:
		Log.error("Steam: connect_to_lobby(%d) не удался (код %d)" % [lobby, err], "Net")
		return err
	peer = steam_peer
	return OK


func close() -> void:
	if peer is SteamMultiplayerPeer:
		(peer as SteamMultiplayerPeer).close()
	super()
