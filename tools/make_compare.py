#!/usr/bin/env python3
"""Склейка «было | стало» из двух PNG-кадров одинакового размера (П5.9).

На сервере нет PIL/ImageMagick, поэтому декодер и энкодер PNG — чистый
Python (модуль zlib): читаются 8-битные RGB/RGBA-кадры Godot (фильтры
строк 0–4), пишется RGB без фильтра. Кадры стыкуются горизонтально,
между ними разделитель DIVIDER px (по образцу склеек П5.7/П5.8).

Запуск: python3 tools/make_compare.py before.png after.png -o compare.png
"""
import argparse
import struct
import sys
import zlib
from pathlib import Path

DIVIDER = 6
DIVIDER_RGB = (30, 30, 30)


def read_png(path: Path) -> tuple[int, int, list[bytes]]:
    """PNG → (ширина, высота, строки RGB по 3·w байт)."""
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        sys.exit(f"{path}: не PNG")
    pos = 8
    width = height = 0
    color_type = bit_depth = 0
    idat = bytearray()
    while pos < len(data):
        length, ctype = struct.unpack(">I4s", data[pos:pos + 8])
        chunk = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if ctype == b"IHDR":
            width, height, bit_depth, color_type = struct.unpack(
                ">IIBB", chunk[:10])
        elif ctype == b"IDAT":
            idat.extend(chunk)
        elif ctype == b"IEND":
            break
    if bit_depth != 8 or color_type not in (2, 6):
        sys.exit(f"{path}: не поддерживается (глубина {bit_depth}, "
                 f"тип цвета {color_type}; нужно 8 бит RGB/RGBA)")
    channels = 3 if color_type == 2 else 4
    bpp = channels
    raw = zlib.decompress(bytes(idat))
    stride = width * channels
    if len(raw) < stride * height:
        sys.exit(f"{path}: данных меньше, чем строк изображения")
    rows: list[bytes] = []
    prev = bytearray(stride)
    offset = 0
    for _y in range(height):
        filter_type = raw[offset]
        line = bytearray(raw[offset + 1:offset + 1 + stride])
        offset += 1 + stride
        if filter_type == 1:  # Sub
            for i in range(bpp, stride):
                line[i] = (line[i] + line[i - bpp]) & 0xFF
        elif filter_type == 2:  # Up
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif filter_type == 3:  # Average
            for i in range(stride):
                left = line[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 0xFF
        elif filter_type == 4:  # Paeth
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                b = prev[i]
                c = prev[i - bpp] if i >= bpp else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                nearest = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                line[i] = (line[i] + nearest) & 0xFF
        prev = line
        if channels == 3:
            rows.append(bytes(line))
        else:  # RGBA → RGB
            rows.append(bytes(line[0::4] + line[1::4] + line[2::4]))
    return width, height, rows


def write_png(path: Path, width: int, height: int, rows: list[bytes]) -> None:
    def chunk(ctype: bytes, payload: bytes) -> bytes:
        return (struct.pack(">I", len(payload)) + ctype + payload
                + struct.pack(">I", zlib.crc32(ctype + payload) & 0xFFFFFFFF))

    raw = bytearray()
    for row in rows:
        raw.append(0)  # фильтр None
        raw.extend(row)
    out = bytearray(b"\x89PNG\r\n\x1a\n")
    out.extend(chunk(b"IHDR", struct.pack(">IIBBBBB", width, height,
                                          8, 2, 0, 0, 0)))
    out.extend(chunk(b"IDAT", zlib.compress(bytes(raw), 9)))
    out.extend(chunk(b"IEND", b""))
    path.write_bytes(out)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("before", type=Path)
    parser.add_argument("after", type=Path)
    parser.add_argument("-o", "--out", required=True, type=Path)
    args = parser.parse_args()
    w1, h1, rows1 = read_png(args.before)
    w2, h2, rows2 = read_png(args.after)
    if (w1, h1) != (w2, h2):
        sys.exit(f"размеры не совпадают: {w1}x{h1} и {w2}x{h2}")
    gap = bytes(DIVIDER_RGB * DIVIDER)
    merged = [rows1[y] + gap + rows2[y] for y in range(h1)]
    args.out.parent.mkdir(parents=True, exist_ok=True)
    write_png(args.out, w1 * 2 + DIVIDER, h1, merged)
    print(f"{args.out.name}: {w1 * 2 + DIVIDER}x{h1} "
          f"({args.out.stat().st_size / 1024:.0f} КБ)")


if __name__ == "__main__":
    main()
