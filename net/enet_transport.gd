# Транспорт разработки на ENetMultiplayerPeer (разделы 2, 8 SPEC): localhost,
# несколько копий игры на одном ПК без Steam. Здесь же — эмуляция плохой сети
# из раздела 16: аргументы --net-lag (RTT) и --net-loss задерживают и теряют
# исходящие отправки. Потери применяются только к ненадёжным отправкам
# (снапшоты, ping) — надёжные события ENet доставляет сам.
# Не делает: SteamMultiplayerPeer (этап 4).
class_name EnetTransport
extends Transport

var _lag_ms: int = 0
var _loss_percent: int = 0
var _rng := RandomNumberGenerator.new()
var _pending: Array[Dictionary] = []  # {at: мс, call: Callable}


func setup(lag_ms: int, loss_percent: int) -> void:
	_lag_ms = lag_ms
	_loss_percent = loss_percent
	transport_name = "enet"
	_rng.randomize()


func host_game(port: int) -> Error:
	peer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(port, Protocol.MAX_PLAYERS_HARD - 1)
	if err != OK:
		Log.error("ENet: не удалось открыть сервер на порту %d (код %d)" % [port, err], "Net")
	return err


func join_game(address: String, port: int) -> Error:
	peer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(address, port)
	if err != OK:
		Log.error("ENet: не удалось подключиться к %s:%d (код %d)" % [address, port, err], "Net")
	return err


func close() -> void:
	_pending.clear()
	super()


func send(call: Callable, unreliable: bool) -> void:
	if unreliable and _is_dropped(_loss_percent, _rng.randf()):
		return  # потеря пакета — снапшот устареет, следующий приедет
	var delay_ms: int = compute_delay_ms(_lag_ms, _rng.randf())
	if delay_ms <= 0:
		call.call()
		return
	_pending.append({"at": Time.get_ticks_msec() + delay_ms, "call": call})


func _process(_delta: float) -> void:
	if _pending.is_empty():
		return
	var now: int = Time.get_ticks_msec()
	var i := 0
	while i < _pending.size():
		if int(_pending[i]["at"]) <= now:
			(_pending[i]["call"] as Callable).call()
			_pending.remove_at(i)
		else:
			i += 1


## Потеряна ли отправка: roll — случайное число 0..1.
static func _is_dropped(loss_percent: int, roll: float) -> bool:
	return loss_percent > 0 and roll * 100.0 < float(loss_percent)


## Задержка отправки, мс: --net-lag трактуется как RTT (каждая сторона
## задерживает на половину), джиттер — доля от половины в обе стороны.
## roll — случайное число 0..1.
static func compute_delay_ms(lag_ms: int, roll: float) -> int:
	if lag_ms <= 0:
		return 0
	var half: float = float(lag_ms) * 0.5
	var jitter: float = half * Protocol.NET_JITTER_FRACTION
	return int(round(lerpf(half - jitter, half + jitter, clampf(roll, 0.0, 1.0))))
