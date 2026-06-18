#!/usr/bin/env python3
# Generate a 1024x1024 app icon PNG (no third-party libs).
# Blue rounded tile + 2x2 white panes (evokes "Windows" + a file grid).
import zlib, struct, math, sys

SS = 2                      # supersample factor for anti-aliasing
W = 1024 * SS

def lerp(a, b, t): return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))

def in_round_rect(x, y, x0, y0, x1, y1, r):
    # signed test: inside the rounded rectangle?
    if x < x0 or x > x1 or y < y0 or y > y1: return False
    cx = min(max(x, x0 + r), x1 - r)
    cy = min(max(y, y0 + r), y1 - r)
    dx, dy = x - cx, y - cy
    if (x0 + r <= x <= x1 - r) or (y0 + r <= y <= y1 - r): return True
    return dx * dx + dy * dy <= r * r

TOP = (58, 139, 224)
BOT = (0, 97, 194)
WHITE = (255, 255, 255)

m = 80 * SS                 # tile margin
tr = 200 * SS               # tile corner radius
x0, y0, x1, y1 = m, m, W - m, W - m

# 2x2 panes
cm = 258 * SS               # content margin from canvas edge
gap = 44 * SS
box0, box1 = cm, W - cm
pane = (box1 - box0 - gap) // 2
pr = 34 * SS
panes = [(box0, box0), (box0 + pane + gap, box0),
         (box0, box0 + pane + gap), (box0 + pane + gap, box0 + pane + gap)]

raw = bytearray()
for y in range(W):
    raw.append(0)           # PNG filter type 0 for this scanline
    for x in range(W):
        r = g = b = a = 0
        if in_round_rect(x, y, x0, y0, x1, y1, tr):
            t = (y - y0) / (y1 - y0)
            r, g, b = lerp(TOP, BOT, t)
            a = 255
            for (px, py) in panes:
                if in_round_rect(x, y, px, py, px + pane, py + pane, pr):
                    r, g, b = WHITE
                    break
        raw.extend((r, g, b, a))

# Downsample SSxSS for anti-aliasing -> 1024x1024
N = 1024
stride = W * 4 + 1
out = bytearray()
for oy in range(N):
    out.append(0)
    for ox in range(N):
        ar = ag = ab = aa = 0
        for sy in range(SS):
            base = (oy * SS + sy) * stride + 1 + ox * SS * 4
            for sx in range(SS):
                i = base + sx * 4
                ar += raw[i]; ag += raw[i+1]; ab += raw[i+2]; aa += raw[i+3]
        n = SS * SS
        out.extend((ar // n, ag // n, ab // n, aa // n))

def chunk(tag, data):
    return (struct.pack(">I", len(data)) + tag + data +
            struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff))

png = b"\x89PNG\r\n\x1a\n"
png += chunk(b"IHDR", struct.pack(">IIBBBBB", N, N, 8, 6, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(bytes(out), 9))
png += chunk(b"IEND", b"")
open(sys.argv[1], "wb").write(png)
print("wrote", sys.argv[1])
