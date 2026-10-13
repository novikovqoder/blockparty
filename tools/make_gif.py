#!/usr/bin/env python3
"""Сборка GIF из кадров серий world_scene (финал П5.8).

На сервере нет ffmpeg/ImageMagick/gifsicle/PIL, поэтому энкодер — чистый
Python (модуль zlib не нужен: кадры уже сырые). Вход — каталог с файлами
frame_%04d.rgb (RGBA8, порядок байтов Godot Image.get_data(): R,G,B,A),
размер задаётся аргументом --size WxH (окно запуска Godot). Выход —
GIF89a с одной глобальной палитрой на все кадры:

- квантование: гистограмма по 5-битным корзинам каналов (32^3), палитра —
  топ-N корзин по встречаемости во всех кадрах, цвет корзины — центр;
- пиксели непопавших корзин — ближайший цвет палитры (кэш по RGB);
- LZW-сжатие по спецификации GIF (коды 9..12 бит, clear при переполнении).

Запуск: python3 tools/make_gif.py builds/series/clip_walk --size 480x270 \
        --fps 12 --out docs/screenshots/P5.8/clip_walk.gif
"""
import argparse
import sys
import time
from pathlib import Path


def read_frames(frames_dir: Path, width: int, height: int) -> list[bytes]:
    """Кадры → список RGB-байтов (альфа отбрасывается)."""
    expected = width * height * 4
    frames = []
    for path in sorted(frames_dir.glob("frame_*.rgb")):
        raw = path.read_bytes()
        if len(raw) != expected:
            sys.exit(f"{path.name}: {len(raw)} байт, ожидалось {expected} "
                     f"(размер окна ≠ --size?)")
        frames.append(raw[0::4] + raw[1::4] + raw[2::4])
    return frames


def build_palette(frames: list[bytes], max_colors: int) -> list[tuple]:
    """Топ-корзины 5-бит по всем кадрам → палитра [(r, g, b), ...]."""
    histogram: dict[int, int] = {}
    for rgb in frames:
        for r, g, b in zip(rgb[0::3], rgb[1::3], rgb[2::3]):
            key = (r >> 3) << 10 | (g >> 3) << 5 | (b >> 3)
            histogram[key] = histogram.get(key, 0) + 1
    top = sorted(histogram.items(), key=lambda item: -item[1])[:max_colors]
    palette = []
    for key, _count in top:
        palette.append(((key >> 10) * 8 + 4, ((key >> 5) & 31) * 8 + 4,
                        (key & 31) * 8 + 4))
    return palette


def index_builder(palette: list[tuple]):
    """Индекс пикселя: точная корзина из палитры, иначе ближайший цвет."""
    bin_index = {}
    for index, (r, g, b) in enumerate(palette):
        bin_index[(r >> 3) << 10 | (g >> 3) << 5 | (b >> 3)] = index

    def nearest(r: int, g: int, b: int) -> int:
        best, best_dist = 0, 1 << 30
        for index, (pr, pg, pb) in enumerate(palette):
            dist = abs(r - pr) + abs(g - pg) + abs(b - pb)
            if dist < best_dist:
                best, best_dist = index, dist
        return best

    cache: dict[int, int] = {}

    def index_of(r: int, g: int, b: int) -> int:
        key = r << 16 | g << 8 | b
        found = cache.get(key)
        if found is None:
            binned = bin_index.get((r >> 3) << 10 | (g >> 3) << 5 | (b >> 3))
            found = binned if binned is not None else nearest(r, g, b)
            cache[key] = found
        return found

    return index_of


def lzw(indices: list[int], min_code_size: int) -> bytes:
    """LZW GIF: коды LSB-first переменной длины, вывод sub-блоками ≤255.

    Таблица — пары (код, символ) → код; при переполнении (4096) испускается
    clear и таблица начинается заново, кодер и декодер синхронны.
    """
    clear, end = 1 << min_code_size, (1 << min_code_size) + 1
    out = bytearray()
    bit_buffer = 0
    bit_count = 0

    def emit(code: int, size: int) -> None:
        nonlocal bit_buffer, bit_count
        bit_buffer |= code << bit_count
        bit_count += size
        while bit_count >= 8:
            out.append(bit_buffer & 0xFF)
            bit_buffer >>= 8
            bit_count -= 8

    table: dict = {}
    next_code = end + 1
    code_size = min_code_size + 1
    emit(clear, code_size)
    current = indices[0]
    for symbol in indices[1:]:
        candidate = (current, symbol)
        found = table.get(candidate)
        if found is not None:
            current = found
            continue
        emit(current, code_size)
        if next_code < 4096:
            table[candidate] = next_code
            # Определён код 2^size — следующие коды шире на бит.
            if next_code == (1 << code_size) and code_size < 12:
                code_size += 1
            next_code += 1
        else:
            emit(clear, code_size)
            table.clear()
            next_code = end + 1
            code_size = min_code_size + 1
        current = symbol
    emit(current, code_size)
    emit(end, code_size)
    if bit_count > 0:
        out.append(bit_buffer & 0xFF)
    sink = bytearray((min_code_size,))
    for start in range(0, len(out), 255):
        block = out[start:start + 255]
        sink.append(len(block))
        sink.extend(block)
    sink.append(0)
    return bytes(sink)


def write_gif(path: Path, width: int, height: int, palette: list[tuple],
              frames: list[bytes], index_of, delay_cs: int, started: float):
    with path.open("wb") as out:
        out.write(b"GIF89a")
        out.write(width.to_bytes(2, "little") + height.to_bytes(2, "little"))
        out.write(bytes([0x80 | 0x07, 0, 0]))  # GCT, 256 цветов
        for r, g, b in palette:
            out.write(bytes((r, g, b)))
        out.write(b"\0" * 3 * (256 - len(palette)))
        # Бесконечный повтор (расширение NETSCAPE2.0).
        out.write(b"\x21\xFF\x0BNETSCAPE2.0\x03\x01\x00\x00\x00")
        for number, rgb in enumerate(frames):
            indices = [index_of(r, g, b)
                       for r, g, b in zip(rgb[0::3], rgb[1::3], rgb[2::3])]
            block = lzw(indices, 8)
            out.write(b"\x21\xF9\x04" + bytes((0, delay_cs, 0, 0)) + b"\0")
            # Дескриптор кадра: left, top (=0), размер, флаги (без LCT).
            out.write(b"\x2C\x00\x00\x00\x00" + width.to_bytes(2, "little")
                      + height.to_bytes(2, "little") + b"\x00")
            out.write(block)
            elapsed = time.monotonic() - started
            print(f"  кадр {number + 1}/{len(frames)} "
                  f"({elapsed:.0f} с, {len(block)} байт)", flush=True)
        out.write(b"\x3B")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("frames_dir", type=Path,
                        help="каталог с frame_*.rgb")
    parser.add_argument("--size", required=True,
                        help="размер окна Godot при съёмке, WxH")
    parser.add_argument("--fps", type=int, default=12,
                        help="частота кадров серии (по умолчанию 12)")
    parser.add_argument("--colors", type=int, default=255,
                        help="размер палитры (по умолчанию 255)")
    parser.add_argument("--out", type=Path, required=True,
                        help="файл GIF")
    args = parser.parse_args()

    width_s, height_s = args.size.lower().split("x")
    width, height = int(width_s), int(height_s)
    started = time.monotonic()
    frames = read_frames(args.frames_dir, width, height)
    if not frames:
        sys.exit(f"в {args.frames_dir} нет frame_*.rgb")
    print(f"кадров: {len(frames)} {width}x{height} "
          f"({time.monotonic() - started:.1f} с)", flush=True)
    palette = build_palette(frames, args.colors)
    print(f"палитра: {len(palette)} цветов "
          f"({time.monotonic() - started:.1f} с)", flush=True)
    index_of = index_builder(palette)
    delay = max(2, round(100 / args.fps))
    write_gif(args.out, width, height, palette, frames, index_of,
              delay, started)
    size_mb = args.out.stat().st_size / (1024 * 1024)
    print(f"готово: {args.out} ({size_mb:.2f} МБ, "
          f"{time.monotonic() - started:.1f} с)")


if __name__ == "__main__":
    main()
