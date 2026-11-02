# cross.tga: 64x64 plus sign, white with a thin (4px of 64) black outline. Tinted in game:
# the white takes the tint (green / red), the outline stays black.
import sys, os
from PIL import Image, ImageDraw
N, ARM, OUT = 64, 18, 4
img = Image.new("RGBA", (N, N), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
def plus(arm, inset, color):
    a0 = (N - arm) // 2; a1 = a0 + arm - 1
    d.rectangle([a0, inset, a1, N - 1 - inset], fill=color)
    d.rectangle([inset, a0, N - 1 - inset, a1], fill=color)
plus(ARM + 2 * OUT, 0, (0, 0, 0, 255))
plus(ARM, OUT, (255, 255, 255, 255))
img.save(os.path.join(sys.argv[1] if len(sys.argv) > 1 else ".", "cross.tga"))
