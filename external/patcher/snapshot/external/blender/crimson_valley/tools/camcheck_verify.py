"""Find the camera-check balls in renders/camcheck.png and report how far each is from where it should be."""
import sys, os
import numpy as np
from PIL import Image
from scipy import ndimage as ndi
POINTS = [(100.5, 100.5), (836.0, 470.5), (1500.5, 800.5), (300.5, 880.5), (1560.5, 60.5), (836.0, 432.0), (1150.5, 620.5), (50.5, 900.5)]
img = np.asarray(Image.open(sys.argv[1]).convert("L")).astype(np.float64)
lab, n = ndi.label(img > 40)
cms = ndi.center_of_mass(img, lab, range(1, n + 1))
cms = [(x + 0.5, y + 0.5) for y, x in cms]
worst = 0.0
for (u, v) in POINTS:
    d = [np.hypot(u - x, v - y) for x, y in cms]
    k = int(np.argmin(d)); worst = max(worst, d[k])
    print(f"expected ({u:7.1f},{v:6.1f})  found ({cms[k][0]:7.2f},{cms[k][1]:6.2f})  off {d[k]:.2f} px")
print("blobs", n, "worst", round(worst, 2), "px")
