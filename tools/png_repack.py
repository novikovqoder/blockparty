#!/usr/bin/env python3
"""Пережимка PNG-кадров из builds/shots_pose/ в чистый RGB для внешнего
анализа (сырые скриншоты Godot RGBA анализатор парсит нестабильно):
  python3 tools/png_repack.py <in.png> <out.png>
Самопроверка агента, в git не нужна для игры."""
import struct
import sys
import zlib


def decode(path: str):
    data = open(path, "rb").read()
    pos = 8
    idat = b""
    w = h = bpp = None
    while pos < len(data):
        ln, typ = struct.unpack(">I4s", data[pos:pos + 8])
        pos += 8
        chunk = data[pos:pos + ln]
        pos += ln + 4
        if typ == b"IHDR":
            w, h, _, ct = struct.unpack(">IIBB", chunk[:10])
            bpp = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[ct]
        elif typ == b"IDAT":
            idat += chunk
        elif typ == b"IEND":
            break
    raw = zlib.decompress(idat)
    stride = w * bpp
    out = bytearray()
    prev = bytearray(stride)
    p = 0
    for _ in range(h):
        f = raw[p]
        p += 1
        line = bytearray(raw[p:p + stride])
        p += stride
        if f == 1:
            for i in range(bpp, stride):
                line[i] = (line[i] + line[i - bpp]) & 255
        elif f == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 255
        elif f == 3:
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 255
        elif f == 4:
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                b = prev[i]
                c = prev[i - bpp] if i >= bpp else 0
                q = a + b - c
                pa, pb, pc = abs(q - a), abs(q - b), abs(q - c)
                r = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + r) & 255
        out += line
        prev = line
    return w, h, bpp, out


def main() -> None:
    src, dst = sys.argv[1], sys.argv[2]
    w, h, bpp, pix = decode(src)
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        row = pix[y * w * bpp:(y + 1) * w * bpp]
        for x in range(w):
            i = x * bpp
            raw += bytes((row[i], row[i + 1], row[i + 2]))

    def chunk(typ: bytes, payload: bytes) -> bytes:
        head = struct.pack(">I4s", len(payload), typ) + payload
        return head + struct.pack(">I", zlib.crc32(typ + payload) & 0xFFFFFFFF)

    png = bytearray(b"\x89PNG\r\n\x1a\n")
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    open(dst, "wb").write(png)
    print("ok", dst, len(png))


if __name__ == "__main__":
    main()
