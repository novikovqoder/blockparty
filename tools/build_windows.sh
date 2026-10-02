#!/usr/bin/env bash
# Headless-экспорт Windows-сборки и упаковка в builds/blockparty-windows.zip.
#
# Использование:
#   tools/build_windows.sh          экспорт пресета «Windows Desktop» (x86_64)
#                                   в builds/windows/blockparty.exe, затем zip
#
# Требования: godot в PATH, установленные шаблоны экспорта текущей версии,
# python3 (упаковка zip — стандартным модулем zipfile, утилита zip в системе
# отсутствует). steam_appid.txt кладётся рядом с exe (для запуска вне
# Steam-девпака Steam ищет его в каталоге игры; прод-сборку Steamworks
# переупакует сам — appid в архиве черновой, из корня проекта).
set -euo pipefail
cd "$(dirname "$0")/.."

PRESET="Windows Desktop"
OUT_DIR="builds/windows"
ZIP_PATH="builds/blockparty-windows.zip"
EXE="$OUT_DIR/blockparty.exe"

STEAM_DIR="addons/godotsteam/win64"
GODOTSTEAM_DLL="$STEAM_DIR/libgodotsteam.windows.template_release.x86_64.dll"
STEAM_API_DLL="$STEAM_DIR/steam_api64.dll"

command -v godot >/dev/null || { echo "ОШИБКА: godot не найден в PATH" >&2; exit 1; }
command -v python3 >/dev/null || { echo "ОШИБКА: python3 не найден" >&2; exit 1; }
[[ -f "$GODOTSTEAM_DLL" && -f "$STEAM_API_DLL" ]] || {
  echo "ОШИБКА: DLL GodotSteam не найдены в addons/godotsteam/win64/" >&2
  exit 1
}

echo "==> Экспорт пресета «$PRESET» (headless)"
rm -rf "$OUT_DIR" "$ZIP_PATH"
mkdir -p "$OUT_DIR"
godot --headless --export-release "$PRESET"
[[ -f "$EXE" ]] || { echo "ОШИБКА: экспорт не создал $EXE" >&2; exit 1; }

# Godot кладёт DLL из godotsteam.gdextension (библиотека + dependencies) рядом
# с exe сам; если по какой-то причине их нет — докопируем и скажем об этом.
for dll in "$GODOTSTEAM_DLL" "$STEAM_API_DLL"; do
  name="$(basename "$dll")"
  if [[ ! -f "$OUT_DIR/$name" ]]; then
    echo "==> WARN: $name не скопирован экспортёром, добавляю вручную"
    cp "$dll" "$OUT_DIR/"
  fi
done

cp steam_appid.txt "$OUT_DIR/"

echo "==> Упаковка $ZIP_PATH"
# Файлы кладутся в корень архива (без каталога windows/).
python3 - "$ZIP_PATH" "$OUT_DIR" <<'PY'
import pathlib
import sys
import zipfile

zip_path, out_dir = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(out_dir.iterdir()):
        if path.is_file():
            archive.write(path, path.name)
PY

# Контроль: обязательные файлы должны быть в архиве.
python3 - "$ZIP_PATH" blockparty.exe "$(basename "$GODOTSTEAM_DLL")" \
         "$(basename "$STEAM_API_DLL")" steam_appid.txt <<'PY'
import pathlib
import sys
import zipfile

zip_path = pathlib.Path(sys.argv[1])
required = sys.argv[2:]
with zipfile.ZipFile(zip_path) as archive:
    names = set(archive.namelist())
missing = [name for name in required if name not in names]
for name in missing:
    print(f"ОШИБКА: в архиве нет {name}", file=sys.stderr)
if missing:
    sys.exit(1)
print(f"==> Готово: {zip_path} — {len(names)} файл(ов), обязательные на месте")
PY

echo "==> Содержимое:"
python3 -m zipfile -l "$ZIP_PATH"
ls -lh "$ZIP_PATH" | awk '{print "    " $9 " — " $5}'
