# arrow.tga: 64x64 notched arrowhead pointing up, white with a thin black outline. Tinted in game:
# the white takes the tint, the outline stays black. Plain Python, no image libraries.
import math, os, struct, sys

N, OUTLINE, SAMPLES = 64, 3.5, 4
SHAPE = [(32, 5), (55, 58), (32, 45), (9, 58)]


def inside(x, y):
    hit = False
    for i, (ax, ay) in enumerate(SHAPE):
        bx, by = SHAPE[(i + 1) % len(SHAPE)]
        if (ay > y) != (by > y) and x < (bx - ax) * (y - ay) / (by - ay) + ax:
            hit = not hit
    return hit


def edge_distance(x, y):
    best = 1e9
    for i, (ax, ay) in enumerate(SHAPE):
        bx, by = SHAPE[(i + 1) % len(SHAPE)]
        dx, dy = bx - ax, by - ay
        t = max(0, min(1, ((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy)))
        best = min(best, math.hypot(x - (ax + t * dx), y - (ay + t * dy)))
    return best


def pixel(px, py):
    white = black = 0
    for sy in range(SAMPLES):
        for sx in range(SAMPLES):
            x, y = px + (sx + 0.5) / SAMPLES, py + (sy + 0.5) / SAMPLES
            near = edge_distance(x, y)
            if inside(x, y) and near > OUTLINE:
                white += 1
            elif inside(x, y) or near <= OUTLINE:
                black += 1
    total = SAMPLES * SAMPLES
    shown = white + black
    if shown == 0:
        return bytes((0, 0, 0, 0))
    v = round(255 * white / shown)
    return bytes((v, v, v, round(255 * shown / total)))


# uncompressed 32-bit TGA, top-left origin
header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, N, N, 32, 0x28)
body = b"".join(pixel(x, y) for y in range(N) for x in range(N))
with open(os.path.join(sys.argv[1] if len(sys.argv) > 1 else ".", "arrow.tga"), "wb") as f:
    f.write(header + body)
