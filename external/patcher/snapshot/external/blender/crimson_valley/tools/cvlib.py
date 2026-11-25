"""Shared geometry of the Crimson Valley scene: the camera model and picture <-> world mapping.

numpy only, so both the analysis tools (CPython) and the Blender build scripts can import it.

The picture is 1672 x 941. World: X right, Y forward (into the picture), Z up, metres; the river's
water is the plane z = 0 and the camera stands at (0, 0, cam_h) looking along +Y, pitched down a little.
Pixel (u, v): u right, v down, pixel centres at integer + 0.5 are NOT used - (u, v) is the continuous
picture coordinate with (0, 0) the top-left corner, so pixel [row j, column i] has centre (i + 0.5, j + 0.5)."""
import json
import math
import os

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
ANALYSIS = os.path.join(ROOT, "analysis")
REFERENCE = os.path.join(ROOT, "reference", "reference.png")
W, H = 1672, 941


class Camera:
    """Pinhole camera, no roll. f in pixels; pitch > 0 looks down."""

    def __init__(self, f=1114.6667, cx=W / 2, cy=H / 2, pitch=0.0345, cam_h=20.0, w=W, h=H,
                 sensor_width=36.0, **_):
        self.f, self.cx, self.cy, self.pitch, self.cam_h, self.w, self.h = f, cx, cy, pitch, cam_h, w, h
        self.sensor_width = sensor_width
        cp, sp = math.cos(pitch), math.sin(pitch)
        self.right = np.array([1.0, 0.0, 0.0])
        self.up = np.array([0.0, sp, cp])
        self.fwd = np.array([0.0, cp, -sp])
        self.pos = np.array([0.0, 0.0, cam_h])

    @property
    def lens_mm(self):
        return self.f * self.sensor_width / self.w

    @property
    def horizon_v(self):
        return self.cy - self.f * math.tan(self.pitch)

    def to_dict(self):
        return {"f": self.f, "cx": self.cx, "cy": self.cy, "pitch": self.pitch, "cam_h": self.cam_h,
                "w": self.w, "h": self.h, "sensor_width": self.sensor_width, "lens_mm": self.lens_mm,
                "horizon_v": self.horizon_v}

    def rays(self, u, v):
        """World direction (not normalised, forward component 1 in camera space) for picture points."""
        u = np.asarray(u, dtype=np.float64)
        v = np.asarray(v, dtype=np.float64)
        x = (u - self.cx) / self.f
        y = (self.cy - v) / self.f
        return x[..., None] * self.right + y[..., None] * self.up + self.fwd

    def unproject(self, u, v, z):
        """World points for picture points at depth z (distance along the camera's forward axis)."""
        return self.pos + self.rays(u, v) * np.asarray(z, dtype=np.float64)[..., None]

    def project(self, p):
        """World points -> (u, v, z)."""
        d = np.asarray(p, dtype=np.float64) - self.pos
        z = d @ self.fwd
        u = self.cx + self.f * (d @ self.right) / z
        v = self.cy - self.f * (d @ self.up) / z
        return u, v, z

    def ground_z(self, v, height=0.0):
        """Depth at which the ray through picture row v meets the horizontal plane z = height
        (inf at and above that plane's horizon)."""
        v = np.asarray(v, dtype=np.float64)
        y = (self.cy - v) / self.f
        denom = math.sin(self.pitch) - y * math.cos(self.pitch)      # -(ray z)
        with np.errstate(divide="ignore"):
            z = np.where(denom > 1e-9, (self.cam_h - height) / np.maximum(denom, 1e-9), np.inf)
        return z


def load_camera(path=None):
    path = path or os.path.join(ANALYSIS, "camera.json")
    with open(path) as fh:
        return Camera(**json.load(fh))


def pixel_grid(w=W, h=H):
    """(u, v) of every pixel centre, arrays of shape (h, w)."""
    v, u = np.mgrid[0:h, 0:w].astype(np.float64)
    return u + 0.5, v + 0.5
