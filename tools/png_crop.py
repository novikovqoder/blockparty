#!/usr/bin/env python3
"""Кроп PNG для визуальной проверки областей (чистый Python, без PIL).

Запуск: python3 tools/png_crop.py in.png -o out.png --box X,Y,W,H [--scale 2]
"""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from make_compare import read_png, write_png


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("src", type=Path)
    parser.add_argument("-o", "--out", required=True, type=Path)
    parser.add_argument("--box", required=True, help="X,Y,W,H")
    parser.add_argument("--scale", type=int, default=1,
                        help="целочисленное увеличение (по умолчанию 1)")
    args = parser.parse_args()
    x, y, w, h = (int(v) for v in args.box.split(","))
    width, height, rows = read_png(args.src)
    if x < 0 or y < 0 or x + w > width or y + h > height:
        sys.exit(f"box {x},{y},{w},{h} вне {width}x{height}")
    crop = [rows[yy][x * 3:(x + w) * 3] for yy in range(y, y + h)]
    if args.scale > 1:
        s = args.scale
        scaled = []
        for row in crop:
            big = bytearray()
            for i in range(0, len(row), 3):
                big.extend(row[i:i + 3] * s)
            scaled.extend([bytes(big)] * s)
        crop = scaled
        w, h = w * s, h * s
    args.out.parent.mkdir(parents=True, exist_ok=True)
    write_png(args.out, w, h, crop)
    print(f"{args.out}: {w}x{h}")


if __name__ == "__main__":
    main()
