# Shared outlines (1000-unit box, y up) for the role fonts and role textures.
def cross():
    t = 340; a = (1000 - t) // 2; b = a + t
    return [[(a,0),(a,a),(0,a),(0,b),(a,b),(a,1000),(b,1000),(b,b),(1000,b),(1000,a),(b,a),(b,0)]]

def shield():
    # heater shield: flat top with rounded shoulders, straight sides, curved to a point
    import math
    pts = [(500,1000),(860,960),(900,900),(900,560)]
    # right curve down to the point
    for i in range(1, 9):
        t = i / 9
        x = 900 - 400 * (t ** 1.6)
        y = 560 - 560 * (1 - (1 - t) ** 1.8)
        pts.append((round(x), round(y)))
    pts.append((500,0))
    left = [(1000 - x, y) for (x, y) in reversed(pts[1:-1])]
    return [pts + left]

def sword():
    blade = [(400,330),(400,820),(500,1000),(600,820),(600,330)]
    guard = [(220,240),(220,340),(780,340),(780,240)]
    grip = [(445,90),(445,240),(555,240),(555,90)]
    pommel = [(380,0),(380,100),(620,100),(620,0)]
    return [blade, guard, grip, pommel]
