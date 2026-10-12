# Библиотека ассетов (library/)

Локальная CC0-коллекция: Poly Haven (модели glTF 1K, HDRI 2K уличные, текстуры 1K все + 2K природы/построек), ambientCG (1K JPG все + 2K JPG категорий природы/построек), OpenGameArt (6 страниц, проверка CC0). Папка `library/` игнорируется Godot (`.gdignore`) и git (`.gitignore`); в репозитории — только этот скрипт и инструкция.

## Запуск
    python3 tools/fetch_library.py all      # всё по порядку: PH → ambientCG → OGA → каталог
    python3 tools/fetch_library.py ph       # только Poly Haven
    python3 tools/fetch_library.py acg      # только ambientCG
    python3 tools/fetch_library.py oga      # только OpenGameArt
    python3 tools/fetch_library.py catalog  # пересобрать catalog.csv/catalog.html из manifest.json

Запускать с низким приоритетом, если параллельно идёт работа над игрой:
    nice -n 19 ionice -c3 python3 tools/fetch_library.py all

## Продолжение после обрыва
Повторный запуск пропускает скачанное: прогресс — в `library/manifest.json`, файлы сверяются по размеру. Просто запусти ту же команду ещё раз.

## Обновление
Скрипт берёт актуальные списки из API при каждом запуске: новые ассеты источников докачаются, старые не трогаются. Правила отбора (категории 2K, уличные HDRI) — константы `STRICT_CATS`, `ACG_PREFIX` в начале скрипта.

## Каталог
`library/catalog.csv` — имя, источник, категория, ссылка, автор, лицензия, размер, путь, анимации. `library/catalog.html` — галерея с превью и фильтром.

## Перенос в игру
Только по одобрению владельца, отдельной задачей, с записью каждого файла в `assets/third_party/LICENSES.md`.
