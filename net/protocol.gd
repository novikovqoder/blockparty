# Сетевые константы протокола (раздел 8 SPEC): версии, лимиты, каналы,
# параметры снапшотов, интерполяции, синхронизации часов и старта забега.
# Правило проекта: все сетевые числа — здесь, геймплейные — в balance.tres.
# Не делает: данные лобби Steam (ключи из раздела 9 — этап 4).
class_name Protocol
extends RefCounted

## Версия протокола: несовместимые лобби не видны друг другу (раздел 8).
const PROTOCOL_VERSION: int = 2

## Максимум игроков в забеге; код должен работать до MAX_PLAYERS_HARD (раздел 8).
const MAX_PLAYERS: int = 12
const MAX_PLAYERS_HARD: int = 16
## Минимум для старта забега: 2 в режиме разработки (раздел 8).
const MIN_PLAYERS_TO_START: int = 2

# --- Каналы (раздел 8) ---

## 0: reliable — события игры, старт/финиш, награды.
const CHANNEL_RELIABLE: int = 0
## 1: unreliable ordered — снапшоты движения (и ping часов).
const CHANNEL_SNAPSHOT: int = 1
## 2: unreliable ordered — голосовые пакеты (этап 5).
const CHANNEL_VOICE: int = 2

# --- Снапшоты (раздел 8) ---

## Частота отправки снапшота своего персонажа, Гц.
const SNAPSHOT_HZ: float = 20.0
## Максимальный размер снапшота, байт (бюджет из раздела 8 — «около 20»).
const SNAPSHOT_MAX_BYTES: int = 20

# --- Интерполяция чужих игроков (раздел 8) ---

## Отрисовка с задержкой, мс.
const INTERP_DELAY_MS: int = 100
## Экстраполяция не дольше, мс; затем персонаж замирает.
const EXTRAPOLATION_MS: int = 150
## Расхождение больше этого — телепорт без сглаживания, px.
const TELEPORT_DISTANCE: float = 256.0

# --- Синхронизация часов (раздел 8) ---

## Частота ping/pong, с.
const CLOCK_PING_INTERVAL: float = 1.0
## Сглаживание смещения: скользящее среднее по последним замерам.
const CLOCK_WINDOW: int = 8

# --- Старт забега (раздел 8) ---

## Хост шлёт rpc_go, даже если не все сказали rpc_client_ready через это время, с.
const START_READY_TIMEOUT: float = 15.0
## Старт GO назначается на это число секунд позже времени хоста (отсчёт 3-2-1).
const GO_DELAY: float = 3.0

# --- Авторитет хоста (раздел 6) ---

## Допуск к перезарядке атаки при проверке попадания на хосте, с.
const HIT_COOLDOWN_TOLERANCE: float = 0.25

# --- Эмуляция плохой сети (раздел 16; аргументы --net-lag, --net-loss) ---

## --net-lag задаёт RTT: задерживается каждая отправка на половину.
const NET_LAG_IS_RTT: bool = true
## Джиттер задержки — доля от половины лага в обе стороны.
const NET_JITTER_FRACTION: float = 0.2

# --- Состояния аниматора в снапшоте (раздел 4; uint8) ---

enum AnimState {
	IDLE = 0,
	RUN = 1,
	JUMP = 2,
	FALL = 3,
	ATTACK = 4,
	HANG = 5,
}

# --- Флаги снапшота (uint8, раздел 8: направление, на земле, висит, говорит) ---

const FLAG_FACING_RIGHT: int = 1 << 0
const FLAG_ON_FLOOR: int = 1 << 1
const FLAG_HANGING: int = 1 << 2
const FLAG_TALKING: int = 1 << 3
