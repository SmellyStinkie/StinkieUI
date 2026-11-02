# Builds the role symbol fonts for Stinkie UI (needs fontTools):
#   StinkieRoleHealer.ttf: "4" = cross        (scoreboard role flag 4 = healer)
#   StinkieRoleTank.ttf:   "1" = shield       (flag 1 = tank)
#   StinkieRoleDamage.ttf: "2", "8" = sword   (flags 2 / 8 = damage)
# Every other character is blank, so writing the (possibly secret) role number in all three
# fonts shows exactly one icon. Usage: python3 make_role_fonts.py <outdir>
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from shapes import cross, shield, sword

EM = 1000

def glyph(contours):
    p = TTGlyphPen(None)
    for c in contours:
        # TrueType outer contours run clockwise; shapes are listed counter-clockwise or mixed, so normalise
        area = sum(c[i][0] * c[(i + 1) % len(c)][1] - c[(i + 1) % len(c)][0] * c[i][1] for i in range(len(c)))
        pts = c if area < 0 else list(reversed(c))
        p.moveTo(pts[0])
        for q in pts[1:]: p.lineTo(q)
        p.closePath()
    return p.glyph()

# WoW draws a "missing glyph" box for glyphs with no outline, so the characters that must stay
# invisible get a speck 2/1000 of an em wide instead: far below one pixel at any icon size.
def speck():
    return [[(0, 0), (0, 2), (2, 2), (2, 0)]]

def build(path, family, drawn, shape):
    chars = "0123456789-. "
    names = [".notdef"] + ["g%d" % i for i in range(len(chars))]
    cmap = {ord(c): "g%d" % i for i, c in enumerate(chars)}
    glyphs = {".notdef": glyph(speck())}
    metrics = {".notdef": (2, 0)}
    for i, c in enumerate(chars):
        n = "g%d" % i
        if c in drawn:
            glyphs[n] = glyph(shape()); metrics[n] = (EM, 0)
        else:
            glyphs[n] = glyph(speck()); metrics[n] = (2, 0)
    fb = FontBuilder(EM, isTTF=True)
    fb.setupGlyphOrder(names)
    fb.setupCharacterMap(cmap)
    fb.setupGlyf(glyphs)
    fb.setupHorizontalMetrics(metrics)
    fb.setupHorizontalHeader(ascent=EM, descent=0)
    fb.setupNameTable({"familyName": family, "styleName": "Regular"})
    fb.setupOS2(sTypoAscender=EM, sTypoDescender=0, usWinAscent=EM, usWinDescent=0)
    fb.setupPost()
    fb.save(path)

out = sys.argv[1]
build(out + "/StinkieRoleHealer.ttf", "StinkieRoleHealer", "4", cross)
build(out + "/StinkieRoleTank.ttf", "StinkieRoleTank", "1", shield)
build(out + "/StinkieRoleDamage.ttf", "StinkieRoleDamage", "28", sword)
