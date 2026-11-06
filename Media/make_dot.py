# dot.tga: 32x32 white disc with a thin black outline, for tinting. The white takes the tint, the
# outline stays black, so a dot reads on any map. Plain Python, no image libraries.
import math, os, struct

N, OUTLINE, SAMPLES = 32, 3, 4
CENTER, RADIUS = N / 2, N / 2 - 1


def pixel(px, py):
    white = black = 0
    for sy in range(SAMPLES):
        for sx in range(SAMPLES):
            d = math.hypot(px + (sx + 0.5) / SAMPLES - CENTER, py + (sy + 0.5) / SAMPLES - CENTER)
            if d <= RADIUS - OUTLINE:
                white += 1
            elif d <= RADIUS:
                black += 1
    shown = white + black
    if shown == 0:
        return (0, 0, 0, 0)
    v = round(255 * white / shown)
    return (v, v, v, round(255 * shown / (SAMPLES * SAMPLES)))


header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, N, N, 32, 0x28)
body = bytearray()
for y in range(N):
    for x in range(N):
        r, g, b, a = pixel(x, y)
        body += bytes((b, g, r, a))
path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "dot.tga")
with open(path, "wb") as f:
    f.write(header + body)
