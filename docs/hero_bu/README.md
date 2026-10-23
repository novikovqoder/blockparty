# Герой Born Unblessed, экран запуска и экран загрузки — комплект для Godot 4.7.2

Проверено в Godot 4.7.2: всё загружается без ошибок и предупреждений (строгая типизация),
7 тестов GUT зелёные (`tests/test_hero_bu.gd`), скриншоты в `docs/screenshots/hero_bu/`.

Комплект зависит от этапа «Главное меню Born Unblessed»: использует `UiStyleBU`
(`ui/theme_bu/`), `MenuButtonBU` (`scenes/menu_bu/menu_button_bu.gd`) и фон меню
`assets/menu_bu/bu_bg.jpg`.

## Файлы

| Путь | Что это |
| --- | --- |
| `assets/hero_bu/knight_bu.glb` | Модель героя: тело, лицо, волосы, одежда; скелет Mixamo (`mixamorig_*`), рост 1,8 м, ступни на нуле |
| `assets/hero_bu/hero_bu.tscn` | Сцена героя: модель + моргание (`BlinkLidsBU` под `Skeleton3D`) |
| `assets/hero_bu/LICENSES_hero_bu.md` | Источники и лицензии всех частей модели |
| `scripts/hero_bu/blink_lids_bu.gd` | `BlinkLidsBU` — моргание настоящими веками поверх любой анимации |
| `scenes/boot_bu/boot_screen_bu.gd/.tscn` | `BootScreenBU` — экран запуска и окно «Steam не запущен» в стиле меню |
| `scenes/loading_bu/loading_screen_bu.gd` | `LoadingScreenBU` — экран загрузки мира |
| `assets/loading_bu/` | Сюда кладётся картинка экрана загрузки `loading_bg.jpg` (пока нет — берётся затемнённый фон меню) |
| `i18n/strings_bu_boot.csv` | Строки экранов запуска и загрузки, ru/en, ключи `BU_BOOT_*`, `BU_LOAD_*` |
| `tests/test_hero_bu.gd`, `tests/fixtures/slow_world_bu.*` | Тесты GUT и учебный «медленный мир» для теста загрузки |
| `tools/capture_hero_bu.gd` | Скриншоты: экран запуска, «Steam не запущен», загрузка, герой с 4 сторон |

## Герой

- **Скелет** — имена Mixamo с префиксом `mixamorig_` (после импорта Godot), 58 костей:
  тело, пальцы, глаза и веки (`*EyelidUpper/Lower`). Поэтому на героя переносятся анимации
  Mixamo инструментом `tools/retarget_mixamo_bu.gd` из комплекта меча, так же как меч крепится
  через `WeaponMountsBU` (префикс костей определяется сам).
- **Анимаций в модели нет** — только поза покоя (руки вниз, как на концепте).
- **Накидка и капюшон** привязаны к скелету так же, как поверхность под ними (кольчуга, тело,
  голова), поэтому при любых движениях ничего не проходит сквозь ткань. Под капюшоном волосы
  прижаты к голове — героя без капюшона не показываем.
- **Лицо** нарисовано в текстуре кожи (щетина, губы, тени) — менять материал кожи не нужно.
- **Моргание**: `BlinkLidsBU` (SkeletonModifier3D) поворачивает кости верхних век поверх
  анимации. Параметры на узле: `close_angle` (35°), `interval_min/max` (2,5–6 с),
  `blink_time` (0,16 с), `double_chance`, `squint` (лёгкий прищур, 0,12), `auto_blink`.
  Метод `blink(twice)` — моргнуть сейчас. Если герой создаётся кодом из `knight_bu.glb`,
  добавить `BlinkLidsBU.new()` дочерним узлом его `Skeleton3D`.
- Материалы: кожа, глаза, одежда — непрозрачные/с вырезом по альфе; брови — с мягкой
  прозрачностью (BLEND). Отдельной настройки не требуют.

## Экран запуска `BootScreenBU`

Только внешний вид: проверку Steam оставляет существующей сцене запуска.

```gdscript
var boot: BootScreenBU = preload("res://scenes/boot_bu/boot_screen_bu.tscn").instantiate()
add_child(boot)
boot.show_status("BU_BOOT_INIT")          # ключ перевода или готовый текст
# Steam не найден:
boot.show_steam_missing()
boot.offline_requested.connect(_on_offline)   # «Играть офлайн» (режим разработки, ENet)
boot.quit_requested.connect(get_tree().quit)  # «Выход» и Esc
```

Фон — кадр 16:9 вокруг рыцаря из панорамы меню, приглушённый, с виньеткой; появляется из
чёрного за 0,8 с. Кнопки — `MenuButtonBU`, работают мышью, клавиатурой и геймпадом.

## Экран загрузки `LoadingScreenBU`

```gdscript
LoadingScreenBU.open(get_tree(), "res://scenes/world_scene.tscn")
```

1. Появляется из чёрного (меню при старте уходит в чёрный — переход без вспышки).
2. Грузит сцену в фоне (`ResourceLoader.load_threaded_request`), полоса прогресса до 70 %.
3. Подменяет текущую сцену на мир и остаётся поверх (CanvasLayer 100). Если `_ready()` мира
   долго строит остров — на экране стоит картинка, а не серый кадр.
4. Если у корня мира есть сигнал `world_ready` — ждёт его (до `ready_timeout`, 30 с),
   иначе — 3 кадра. Минимальное время показа `min_time` = 1,6 с.
5. Уходит за `fade_out_time` = 0,8 с, сигнал `finished(scene)`, удаляет себя.

Ошибка (сцены нет или не загрузилась) — сигнал `failed(path)`, на экране текст
`BU_LOAD_FAILED`, предупреждение в журнал.

Картинка: `assets/loading_bu/loading_bg.jpg`, 1920×1080 (16:9), обрезается «по ширине»
(`KEEP_ASPECT_COVERED`). Нижняя треть затемняется под название, строку состояния и подсказки —
важное на картинке держать выше середины и не в левом нижнем углу.

Строка состояния и проценты: «Загрузка моделей и текстур» (фоновая загрузка сцены) →
«Построение мира» (подмена сцены, `_ready()` мира) → «Подготовка персонажа» (ждём
`world_ready`) → «Готово». Этапы, которые знает только мир, он ставит сам:
`if LoadingScreenBU.current: LoadingScreenBU.current.set_status("BU_LOAD_CONNECT")`
(«Подключение к миру» у клиента до получения world_state).

Под полосой — короткие строки о мире игры (`BU_LOAD_HINT_1..6`, шрифт Cormorant):
первая выбирается случайно, дальше меняются каждые 7 с. Тексты — в `i18n/strings_bu_boot.csv`.

## Тесты и скриншоты

```
godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_hero_bu.gd -gexit
xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1600x900 \
  -s res://tools/capture_hero_bu.gd -- docs/screenshots/П5.N
```
(тест моргания и загрузки требуют отрисовки — запускать через `xvfb-run -a` без `--headless`).
