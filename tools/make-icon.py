#!/usr/bin/env python3
"""Draws App/Assets.xcassets/AppIcon.appiconset/icon.png: a house in white on
abera.tech's wash blue, rgb(0, 26, 51). The app's first screens are the
household's. Standard library only, so it runs anywhere: python3 tools/make-icon.py"""
import math, struct, zlib, pathlib

SIZE, SS = 1024, 3
BG, FG = (0, 26, 51), (255, 255, 255)

def inside(x, y):
    # The roof: a band 70 px thick under two lines meeting at (512, 210).
    for side in (-1, 1):
        if side * (x - 512) >= 0:
            t = (y - 210) - abs(x - 512) * 0.82
            if 0 <= t <= 70 and 150 <= x <= 874:
                return True
    # The walls, 60 px thick, and the door standing in them.
    if 300 <= x <= 724 and 470 <= y <= 820:
        hollow = 360 <= x <= 664 and 530 <= y <= 760
        door = 450 <= x <= 574 and y >= 600
        return door or not hollow
    return False

rows = []
for y in range(SIZE):
    row = bytearray([0])
    for x in range(SIZE):
        hits = sum(inside(x + (i + 0.5) / SS, y + (j + 0.5) / SS) for i in range(SS) for j in range(SS))
        a = hits / (SS * SS)
        row += bytes(round(BG[k] + (FG[k] - BG[k]) * a) for k in range(3))
    rows.append(bytes(row))

def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(b"".join(rows), 9)) + chunk(b"IEND", b"")
out = pathlib.Path(__file__).resolve().parent.parent / "App/Assets.xcassets/AppIcon.appiconset/icon.png"
out.write_bytes(png)
print(out, len(png), "bytes")
