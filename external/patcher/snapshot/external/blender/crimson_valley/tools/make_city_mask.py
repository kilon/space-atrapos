"""The city mask of the Crimson Valley reference: analysis/city.png (1672 x 941, 255 = a pixel of a
building, mast or other built structure; 0 = everything else).

  tools/cv py tools/make_city_mask.py [--overlay renders/city/mask_overlay.png]

The rock builder cuts these pixels out of the rock geometry; scene/part_city.py models what was there.
How the mask is made (all coordinates are picture pixels, read off enlarged crops of the reference):

  SKYLINE   structures that stand against the sky - the huts and the domed pavilion on the arch's deck,
            the spired towers, the terraced hillside with the long gallery under them. A loose outline is
            drawn around each group (its lower edge is the line where the buildings meet the rock) and
            inside it a pixel is city when it is darker than the sky (Lab L < L_SKY: the buildings are
            dark teal-grey, the sky and its clouds are lighter), then holes (lit windows) are filled.
  LIT       sunlit flanks of the towers are as bright as the clouds, so they are traced exactly.
  SOLID     structures that stand in front of rock (the slim lit towers at the lower right, the short
            gallery pieces): exact outlines - the same boxes part_city.py builds.
  MASTS     thin masts and needle tips, too faint to threshold: lines of a given width.

Only what must be REPLACED is in the mask. Lamps and small lights on the rock are not: part_city.py puts
those in front of the rock, which stays."""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi
from skimage import color

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import cvlib  # noqa: E402

W, H = cvlib.W, cvlib.H
L_SKY = 50.0          # Lab lightness under which a pixel inside a skyline outline is building
SS = 4                # polygons are rasterised at 4x and averaged (a pixel is in when half covered)

# ------------------------------------------------------------------------------------------ SKYLINE
# Loose outlines, clockwise from the lower left; the last points (the lower edge) follow the line
# where the buildings meet the rock.
SKYLINE = {
    # the arch's deck, left: an arched kiosk, a long low hall, the domed pavilion and its annexes
    "deck": [(1165, 300.5), (1165, 291), (1168, 287.5), (1176, 287.5), (1178, 289), (1178.5, 283),
             (1192, 282), (1193, 280), (1197, 280), (1198, 282.5), (1204, 284), (1207, 271), (1207, 264),
             (1215, 260), (1217, 258.5), (1219.5, 258.5), (1220, 260), (1223.5, 260), (1223.5, 240),
             (1229, 240), (1228.5, 260), (1238, 262), (1245, 268), (1246.5, 274), (1252, 276),
             (1256, 283), (1258, 284), (1258, 290.5),
             (1245, 291.2), (1228, 292.3), (1212, 293.5), (1205, 295.5), (1180, 298.5)],
    # the tiered tower, the two big spired towers, the cathedral's right wing with its small spire,
    # and the terraced hillside under them down to the long gallery's window row
    "towers": [(1258, 290.5), (1258, 262), (1259.5, 253), (1262, 248), (1263.5, 237), (1267.5, 237),
               (1268.5, 247), (1272, 250), (1273, 238), (1275, 224), (1276, 218.5), (1280, 218.5),
               (1280, 200), (1284, 188), (1287, 170), (1290.5, 170), (1292.5, 186), (1296, 190),
               (1299.5, 205), (1301.5, 222), (1304, 228), (1307, 238), (1309, 243.5), (1310, 226),
               (1313, 222), (1313.5, 210), (1317.5, 210), (1318, 222), (1320, 218), (1321, 200),
               (1324, 188), (1326, 151), (1330, 151), (1331.5, 186), (1334.5, 200), (1336, 212),
               (1338.5, 214), (1339.5, 224), (1345, 226), (1352, 222), (1354.5, 205.5), (1359.5, 205.5),
               (1360.5, 219), (1363, 222), (1364.5, 240), (1372, 262), (1376.5, 268), (1376.5, 288.5),
               (1330, 289.5), (1290, 290.5)],
}

# ---------------------------------------------------------------------------------------------- LIT
LIT = {
    # sunlit right flank and buttress of the left big tower
    "b1_flank": [(1289.6, 186), (1291.8, 188.5), (1294.5, 197), (1296, 207), (1298.6, 209.5), (1299, 226),
                 (1300.5, 229.5), (1303, 236), (1306, 240.5), (1306.5, 252), (1290, 252)],
    # the cathedral's spire: gold left half, cream right half
    "b2_spire": [(1326.6, 152), (1328.6, 152), (1330.2, 170), (1331.2, 188), (1332.2, 200), (1334.8, 203),
                 (1335.6, 212), (1335.6, 226), (1320.8, 226), (1321.4, 203), (1324, 199), (1324.6, 188),
                 (1325.6, 170)],
    # the cathedral's body (windows fill most of it) and its right wing's window rows
    "b2_body": [(1311, 229), (1320.8, 224), (1336, 224), (1340, 227.5), (1350, 227.5), (1359, 229.5),
                (1362, 238), (1348, 249), (1336, 256.5), (1312, 256.5)],
    # the pavilion's lit side, door and terrace
    "pavilion": [(1212, 271), (1241.5, 271), (1243, 277), (1251.5, 279), (1258, 283.5), (1258, 290.6),
                 (1245, 291.2), (1212, 293.4)],
    # the low hall's window row
    "hall": [(1179, 289), (1204, 287), (1211, 287), (1211, 294.5), (1180, 298)],
}

# -------------------------------------------------------------------------------------------- SOLID
SOLID = {
    # the slim lit towers at the lower right, in front of the cliff
    "c1": [(1439.3, 210), (1442.7, 210), (1444.7, 228), (1446.6, 258), (1447, 306.5), (1433.6, 306.5),
           (1435, 262), (1436.6, 235), (1438, 214)],
    "c1_step": [(1433, 304.3), (1453, 304.3), (1453, 307), (1433, 307)],
    "c2": [(1421.8, 253), (1424.3, 246.5), (1426.8, 247.5), (1430, 253.5), (1433.2, 257), (1433.6, 303.6),
           (1421.6, 299)],
    "c3": [(1410.6, 269.2), (1420.8, 268.2), (1421, 290), (1410.6, 290)],
    "c4": [(1454.6, 247.5), (1458, 247.5), (1460.2, 254), (1462.6, 259), (1463, 302), (1452, 302),
           (1452, 262), (1453, 254)],
    "c4_wing": [(1463, 260.5), (1469.6, 262), (1469.6, 301.5), (1463, 302)],
    "c5": [(1471, 287), (1480, 287), (1480, 300.6), (1471, 300.6)],
    # a short window row right of the long gallery
    "gallery_east": [(1381, 282.6), (1394.5, 282.6), (1394.5, 287.6), (1381, 287.6)],
    # the white domed lookout between the rock teeth of the far cliff top
    "lookout": [(1628.4, 168.5), (1630, 165.6), (1633.5, 164.3), (1637, 165.4), (1638.8, 168.5),
                (1638.8, 173.5), (1636.4, 176), (1635.6, 186.5), (1632.4, 187.5), (1630.6, 176), (1629.6, 173)],
}

# -------------------------------------------------------------------------------------------- MASTS
# (x0, y0, x1, y1, width)
MASTS = {
    "pavilion_mast": [(1225.6, 241.5, 1225.6, 264, 1.8), (1225.6, 242, 1227.6, 243.6, 1.6)],
    "b1_needle": [(1288.5, 171, 1288.5, 189, 1.7)],
    "b2_needle": [(1327.6, 152, 1327.9, 172, 1.9)],
    "c1_antenna": [(1441, 176, 1441, 211, 1.9), (1441.4, 197.5, 1441.4, 197.6, 3.2)],
    # the cliff-top masts: a stepped mast on the highest cliff, a short one with a ball further right
    "cliff_mast_a": [(1604.0, 21.5, 1604.0, 37, 1.5), (1604.0, 36, 1604.0, 61, 2.3), (1604.0, 60, 1604.0, 75, 3.4)],
    "cliff_mast_b": [(1651.0, 131, 1651.0, 154, 2.4)],
}


def raster(polys=(), lines=()):
    """Polygons / thick lines -> coverage 0..1 per picture pixel (supersampled)."""
    im = Image.new("L", (W * SS, H * SS), 0)
    d = ImageDraw.Draw(im)
    for p in polys:
        d.polygon([(x * SS, y * SS) for x, y in p], fill=255)
    for x0, y0, x1, y1, w in lines:
        dx, dy = x1 - x0, y1 - y0
        n = max(1e-6, (dx * dx + dy * dy) ** 0.5)
        nx, ny = -dy / n * w / 2, dx / n * w / 2
        ex, ey = dx / n * w / 2, dy / n * w / 2           # square caps
        q = [(x0 - ex + nx, y0 - ey + ny), (x1 + ex + nx, y1 + ey + ny),
             (x1 + ex - nx, y1 + ey - ny), (x0 - ex - nx, y0 - ey - ny)]
        d.polygon([(x * SS, y * SS) for x, y in q], fill=255)
    a = np.asarray(im.resize((W, H), Image.BOX)).astype(np.float32) / 255.0
    return a


def build_mask():
    ref = np.asarray(Image.open(cvlib.REFERENCE).convert("RGB")).astype(np.float32) / 255.0
    L = color.rgb2lab(ref)[..., 0]
    mask = np.zeros((H, W), bool)
    for name, poly in SKYLINE.items():
        zone = raster([poly]) >= 0.5
        m = zone & (L < L_SKY)
        for lit in LIT.values():
            m |= zone & (raster([lit]) >= 0.5)
        m = ndi.binary_closing(m, iterations=1) & zone
        m = ndi.binary_fill_holes(m)
        # keep what hangs together with the group's main body (drops dark flecks of cloud)
        lab, n = ndi.label(m)
        if n > 1:
            sizes = ndi.sum(m, lab, range(1, n + 1))
            m = lab == (1 + int(np.argmax(sizes)))
        mask |= m
    for lit in LIT.values():
        mask |= raster([lit]) >= 0.5
    for poly in SOLID.values():
        mask |= raster([poly]) >= 0.5
    for lines in MASTS.values():
        mask |= raster(lines=lines) >= 0.35
    return mask


def main():
    a = sys.argv[1:]
    overlay = a[a.index("--overlay") + 1] if "--overlay" in a else ""
    mask = build_mask()
    out = os.path.join(cvlib.ANALYSIS, "city.png")
    Image.fromarray((mask * 255).astype(np.uint8)).save(out)
    ys, xs = np.nonzero(mask)
    print("city mask", out, "area", int(mask.sum()), "px, bbox", xs.min(), ys.min(), xs.max(), ys.max())
    if overlay:
        ref = np.asarray(Image.open(cvlib.REFERENCE).convert("RGB")).astype(np.float32)
        edge = mask & ~ndi.binary_erosion(mask)
        o = ref.copy()
        o[mask] = o[mask] * 0.55 + np.array([40, 255, 80]) * 0.45
        o[edge] = (255, 255, 0)
        os.makedirs(os.path.dirname(os.path.abspath(overlay)), exist_ok=True)
        Image.fromarray(o.astype(np.uint8)).save(overlay)
        print("overlay", overlay)


if __name__ == "__main__":
    main()
