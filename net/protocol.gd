# Сетевые константы протокола (раздел 10 SPEC): версии, лимиты, каналы,
# параметры 3D-снапшотов, интерполяции, AOI-фильтр хоста и синхронизация
# часов мира. Правило проекта: все сетевые числа — здесь, геймплейные —
# в balance.tres. Не делает: данные лобби Steam (П4), голос (П6).
class_name Protocol
extends RefCounted

## Версия протокола: миры с другой версией не показываются (раздел 10).
## 2 — открытый 3D-мир (ТЗ v2); 1–3 — версии 2D-прототипа.
const PROTOCOL_VERSION: int = 2

## Максимум игроков в мире; код должен работать до MAX_PLAYERS_HARD (раздел 10).
const MAX_PLAYERS: int = 12
const MAX_PLAYERS_HARD: int = 16

# --- Каналы (раздел 10) ---

## 0: reliable — события мира, вход/выход, награды.
const CHANNEL_RELIABLE: int = 0
## 1: unreliable ordered — снапшоты движения (и ping часов).
const CHANNEL_SNAPSHOT: int = 1
## 2: unreliable ordered — голосовые пакеты (этап П6).
const CHANNEL_VOICE: int = 2

# --- Снапшоты (раздел 10) ---

## Частота отправки снапшота своего персонажа, Гц.
const SNAPSHOT_HZ: float = 20.0
## Максимальный размер снапшота, байт (бюджет из раздела 10 — «около 26»).
const SNAPSHOT_MAX_BYTES: int = 26

# --- Интерполяция чужих игроков (раздел 10) ---

## Отрисовка с задержкой, мс.
const INTERP_DELAY_MS: int = 100
## Экстраполяция не дольше, мс; затем персонаж замирает.
const EXTRAPOLATION_MS: int = 150
## Расхождение больше этого — телепорт без сглаживания, м.
const TELEPORT_DISTANCE: float = 5.0

# --- AOI-фильтр хоста (раздел 10: снапшоты по расстоянию между игроками) ---

## До этой дистанции — полная частота снапшотов, м.
const AOI_FULL_DISTANCE: float = 60.0
## До этой дистанции — редкие снапшоты, дальше — только для карты и ников, м.
const AOI_FAR_DISTANCE: float = 150.0
## Частота пересылки по зонам AOI, Гц (20 / 4 / 1).
const AOI_RATE_FULL_HZ: float = SNAPSHOT_HZ
const AOI_RATE_MID_HZ: float = 4.0
const AOI_RATE_FAR_HZ: float = 1.0

# --- Синхронизация часов мира (разделы 7, 10) ---

## Частота ping/pong, с.
const CLOCK_PING_INTERVAL: float = 1.0
## Сглаживание смещения: скользящее среднее по последним замерам.
const CLOCK_WINDOW: int = 8

# --- Эмуляция плохой сети (раздел 18; аргументы --net-lag, --net-loss) ---

## --net-lag задаёт RTT: задерживается каждая отправка на половину.
const NET_LAG_IS_RTT: bool = true
## Джиттер задержки — доля от половины лага в обе стороны.
const NET_JITTER_FRACTION: float = 0.2

# --- Состояния аниматора в снапшоте (раздел 5; uint8) ---

enum AnimState {
	IDLE = 0,
	WALK = 1,
	RUN = 2,
	JUMP = 3,
	FALL = 4,
	LAND = 5,
	BONK = 6,
	HANG = 7,
	PULLED_UP = 8,
	HELP_PULL = 9,
	SIT = 10,
	HOLD_HAND = 11,
	WAVE = 12,
	EMOTE_1 = 13,
	EMOTE_2 = 14,
	EMOTE_3 = 15,
	EMOTE_4 = 16,
	EMOTE_5 = 17,
	EMOTE_6 = 18,
}

# --- Флаги снапшота (uint8; раздел 10: на земле, висит, говорит, сидит,
# --- держит за руку, ведомый) ---

const FLAG_ON_FLOOR: int = 1 << 0
const FLAG_HANGING: int = 1 << 1
const FLAG_TALKING: int = 1 << 2
const FLAG_SITTING: int = 1 << 3
const FLAG_HAND_HELD: int = 1 << 4
const FLAG_LED_BY_HAND: int = 1 << 5
