"""The reference picture's camera, as assumed for the spinosaurus (plain maths: used by build_spino.py
inside Blender and by the tools outside it).

The animal's frame: x forward (to the snout), y to its left, z up, metres, the ground at z = 0. The
picture shows its right side from a little in front (YAW) and a little above (ELEV); nothing in the
picture fixes these exactly, so they are a judgement: with them the animal's sizes are read off the
picture - U(px, py, y) is the point of the plane y = const seen at a pixel (the animal's spine,
sail and head lie on y = 0, a limb on its own plane) - and a render through the same camera lands
where the picture has it."""
import math

W, H = 1774, 887
YAW, ELEV, DIST = 22.0, 5.0, 22.0
K = 0.0075                      # metres per pixel on the plane y = 0 at the picture's centre
F = DIST / K                    # focal length in pixels
CX, CY = W / 2, H / 2
_y, _e = math.radians(YAW), math.radians(ELEV)
D = (math.sin(_y) * math.cos(_e), -math.cos(_y) * math.cos(_e), math.sin(_e))      # from the target to the camera
FW = (-D[0], -D[1], -D[2])
RIGHT = (math.cos(_y), math.sin(_y), 0.0)
UP = (-math.sin(_y) * math.sin(_e), math.cos(_y) * math.sin(_e), math.cos(_e))
Z0 = 0.0                        # the height of the point at the picture's centre (set below)


def location():
    return (D[0] * DIST, D[1] * DIST, Z0 + D[2] * DIST)


def _ray(px, py):
    a, b = (px - CX) / F, (CY - py) / F
    return tuple(FW[i] + RIGHT[i] * a + UP[i] * b for i in range(3))


def U(px, py, y=0.0):
    """The point of the plane y = const seen at the pixel."""
    c, d = location(), _ray(px, py)
    t = (y - c[1]) / d[1]
    return (c[0] + d[0] * t, y, c[2] + d[2] * t)


def depth(p):
    c = location()
    return sum((p[i] - c[i]) * FW[i] for i in range(3))


def P(p):
    """The pixel a point is seen at."""
    c = location()
    v = [p[i] - c[i] for i in range(3)]
    z = sum(v[i] * FW[i] for i in range(3))
    return (CX + F * sum(v[i] * RIGHT[i] for i in range(3)) / z, CY - F * sum(v[i] * UP[i] for i in range(3)) / z)


def mpp(p):
    """Metres per pixel at a point."""
    return depth(p) / F


Z0 = -U(350, 866, -0.76)[2]     # the near foot stands on the ground
