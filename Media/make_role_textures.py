# Role textures (64x64, white with a black outline, tinted in game) from the same outlines.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from PIL import Image, ImageDraw
from shapes import cross, shield, sword
SS = 8; N = 64 * SS; PAD = 6 * SS; OUT = 3 * SS
def draw(shape, name, out):
    img = Image.new("RGBA", (N, N), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    scale = (N - 2 * PAD) / 1000
    polys = [[(PAD + x * scale, N - PAD - y * scale) for (x, y) in c] for c in shape()]
    for p in polys:
        d.polygon(p, fill=(0, 0, 0, 255)); d.line(p + [p[0]], fill=(0, 0, 0, 255), width=2 * OUT, joint="curve")
    for p in polys:
        d.polygon(p, fill=(255, 255, 255, 255))
    img = img.resize((64, 64), Image.LANCZOS)
    img.save(os.path.join(out, name + ".tga"))
    img.resize((192, 192), Image.NEAREST).save("/tmp/" + name + ".png")
out = sys.argv[1]
draw(cross, "role_healer", out); draw(shield, "role_tank", out); draw(sword, "role_damage", out)
