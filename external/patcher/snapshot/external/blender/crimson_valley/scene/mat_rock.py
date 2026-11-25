"""Rock materials of the Crimson Valley scene: a library, not a part (import mat_rock; Blender 5.2).

WORK IN PROGRESS - first version.
"""
import json
import math

import bpy

import common

ATTR_OFFSET = "rock_off"     # FLOAT_VECTOR, written by the relief modifier: how far it moved each vertex
ATTR_GEO = "rock_geo"        # FLOAT 0..1, written by the relief modifier: 1 where the relief is real geometry

# ------------------------------------------------------------------------------------------ parameters
DEFAULTS = dict(
    scale=1.0,                # multiplies every length below
    seed=0,                   # shifts the whole pattern
    gain=1.0,                 # multiplies every albedo
    px_scale=1.0,             # the pixel the detail is limited to, in picture pixels (2 = half-size renders)
    dist_from="camera",       # "camera" (the Camera Data node) or "attribute" (the mesh's dist attribute)
    # colours (albedo, sRGB): the tone ramp dark - base - alt - light, and what moves a point along it
    dark="#4a3a30", base="#a17c5a", alt="#9a6540", light="#b89a7c",
    ramp=(0.10, 0.40, 0.62, 0.92),
    tone_strata=0.5, tone_blocks=0.3, tone_noise=0.5,
    var_size=6.0, var=0.25,   # large patches of lighter / darker rock: size (m), amount
    top="#3d3834", top_amount=0.0, top_rough=0.6,      # weathered up-facing surfaces
    crack_dark=0.75,          # how dark the cracks are
    rim=0.0,                  # lighter broken edges along the cracks
    rough=0.85, spec=0.35,
    # the bending of all layers
    warp_size=6.0, warp=0.6,
    # strata: layers `strata` metres thick, their normal tilted `strata_dip` degrees from vertical
    # towards azimuth `strata_az`
    strata=0.5, strata_dip=4.0, strata_az=30.0, strata_relief=0.08, strata_notch=0.05, strata_notch_w=0.02,
    lamination=0.3,
    # blocks: the main fracture network (Voronoi cells `block` metres across, stretched along x, y, z)
    block=2.0, block_stretch=(1.0, 1.0, 1.5), block_rot=(0.0, 0.0, 0.0), block_random=1.0,
    block_relief=0.12, block_tilt=0.10, block_rib=0.0, block_crack=0.08, block_crack_w=0.02,
    # chips: the small fracture network
    chip=0.5, chip_stretch=(1.0, 1.0, 1.0), chip_rot=(0.0, 0.0, 0.0), chip_random=1.0,
    chip_relief=0.03, chip_tilt=0.03, chip_rib=0.0, chip_crack=0.02, chip_crack_w=0.008,
    # grain
    grain=0.10, grain_bump=0.008, grain_color=0.2,
    # stains and wetness
    stains=0.0, stain_size=1.5, wet=0.0,
    # lichen specks
    specks=0.0, speck_size=0.06, speck_color="#b9a274",
    # what the cover attributes blend to
    moss_color="#8d8a2e", soil_color="#3c1a14",
    # shading relief
    bump=1.0, bump_fine=1.0, bump_on_geo=0.4, facet=0.2, bump_filter=0.1,
    # geometric relief (the modifier)
    relief=1.0, relief_max=1.0, relief_chips=True,
)

PRESETS = {
    "sandstone": dict(),
    "slab": dict(dark="#1f1d1c", base="#34312f", alt="#4b3a2c", light="#57534f", top="#3a3b3e", top_amount=0.8,
                 top_rough=0.4, strata=0.12, strata_relief=0.015, strata_notch=0.01, block=0.9,
                 block_stretch=(1.3, 1.3, 0.7), block_relief=0.05, block_crack=0.05, block_crack_w=0.012,
                 chip=0.25, chip_relief=0.012, chip_crack=0.01, grain=0.05, specks=0.25, var_size=3.0,
                 warp_size=3.0, warp=0.25),
    "boulder": dict(dark="#3b2a20", base="#7d5a40", alt="#8e6038", light="#b08e6e", strata=0.0,
                    block=1.2, block_stretch=(1.0, 1.0, 3.0), block_relief=0.10, block_crack=0.08, rim=0.5,
                    chip=0.3, chip_stretch=(1.0, 1.0, 2.0), var_size=4.0),
    "spire": dict(dark="#3d3835", base="#6e5c50", alt="#86694f", light="#a58a72", strata=0.0,
                  block=2.4, block_stretch=(1.0, 1.0, 9.0), block_relief=0.5, block_tilt=0.3, block_rib=0.5,
                  block_crack=0.4, block_crack_w=0.15, chip=0.8, chip_stretch=(1.0, 1.0, 4.0), chip_relief=0.12,
                  chip_crack=0.08, chip_crack_w=0.04, grain=0.5, grain_bump=0.03, var_size=25.0, warp_size=30.0,
                  warp=2.0, relief_max=2.0),
    "cliff": dict(dark="#2e2a29", base="#55473f", alt="#6d5140", light="#8c725e", strata=1.5, strata_relief=0.2,
                  strata_notch=0.15, strata_notch_w=0.1, block=2.6, block_stretch=(1.0, 1.0, 6.0),
                  block_relief=0.4, block_tilt=0.25, block_crack=0.3, block_crack_w=0.12, chip=0.9,
                  chip_stretch=(1.0, 1.0, 3.0), chip_relief=0.1, chip_crack=0.06, chip_crack_w=0.04, grain=0.5,
                  grain_bump=0.03, stains=0.5, stain_size=4.0, var_size=25.0, warp_size=30.0, warp=2.0,
                  relief_max=2.0),
    "far": dict(dark="#5a5350", base="#7d6e65", alt="#8f7866", light="#a8937f", strata=0.0, block=5.0,
                block_stretch=(1.0, 1.0, 8.0), block_relief=0.8, block_tilt=0.5, block_rib=0.8, block_crack=0.6,
                block_crack_w=0.4, chip=0.0, grain=1.5, grain_bump=0.06, var_size=60.0, warp_size=60.0, warp=4.0,
                relief_max=3.0),
}


def params(preset="sandstone", **overrides):
    """The full parameter set of a preset, with overrides (unknown names are an error)."""
    if preset not in PRESETS:
        raise KeyError(f"unknown rock preset {preset!r} (have: {', '.join(PRESETS)})")
    p = dict(DEFAULTS)
    p.update(PRESETS[preset])
    for k, v in overrides.items():
        if k not in DEFAULTS:
            raise KeyError(f"unknown rock parameter {k!r}")
        p[k] = v
    p["preset"] = preset
    return p


# ------------------------------------------------------------------------------------------ node graphs
def _num(v):
    return isinstance(v, (int, float))


def _sock(sockets, identifier):
    for s in sockets:
        if s.identifier == identifier:
            return s
    raise KeyError(identifier)


class G:
    """Builds a node graph in a shader or geometry node tree. Every method returns an output socket -
    or a plain number when all its inputs were numbers (constants are folded)."""
    FOLD = {"ADD": lambda a, b: a + b, "SUBTRACT": lambda a, b: a - b, "MULTIPLY": lambda a, b: a * b,
            "DIVIDE": lambda a, b: a / b if b else 0.0, "MAXIMUM": max, "MINIMUM": min}

    def __init__(self, tree):
        self.t = tree
        self.k = 0

    def node(self, kind, **props):
        n = self.t.nodes.new(kind)
        for a, v in props.items():
            setattr(n, a, v)
        n.location = (220 * (self.k // 8), -170 * (self.k % 8))
        self.k += 1
        return n

    def put(self, sock, v):
        if v is None:
            return
        if isinstance(v, bpy.types.NodeSocket):
            self.t.links.new(v, sock)
        elif sock.type == "VECTOR" and _num(v):
            sock.default_value = (v, v, v)
        elif sock.type == "RGBA" and len(v) == 3:
            sock.default_value = (*v, 1.0)
        else:
            sock.default_value = v

    # --- scalars
    def math(self, op, a, b=None, c=None, clamp=False):
        if op in self.FOLD and _num(a) and _num(b):
            return self.FOLD[op](a, b)
        n = self.node("ShaderNodeMath", operation=op, use_clamp=clamp)
        for i, v in enumerate((a, b, c)):
            self.put(n.inputs[i], v)
        return n.outputs[0]

    def add(self, a, b):
        if _num(a) and a == 0:
            return b
        if _num(b) and b == 0:
            return a
        return self.math("ADD", a, b)

    def sub(self, a, b):
        if _num(b) and b == 0:
            return a
        return self.math("SUBTRACT", a, b)

    def mul(self, a, b):
        for x, y in ((a, b), (b, a)):
            if _num(x) and x == 1:
                return y
            if _num(x) and x == 0:
                return 0.0
        return self.math("MULTIPLY", a, b)

    def div(self, a, b):
        return self.math("DIVIDE", a, b)

    def maxi(self, a, b):
        return self.math("MAXIMUM", a, b)

    def mini(self, a, b):
        return self.math("MINIMUM", a, b)

    def clamp01(self, a):
        if _num(a):
            return min(1.0, max(0.0, a))
        n = self.node("ShaderNodeClamp")
        self.put(n.inputs[0], a)
        return n.outputs[0]

    def ramp(self, x, a, b, c=0.0, d=1.0, kind="SMOOTHSTEP"):
        """x from a..b mapped to c..d, clamped (a > b is fine: a falling ramp)."""
        n = self.node("ShaderNodeMapRange", interpolation_type=kind, clamp=True)
        for i, v in enumerate((x, a, b, c, d)):
            self.put(n.inputs[i], v)
        return n.outputs[0]

    def lerp(self, a, b, t):
        if _num(t):
            if _num(a) and _num(b):
                return a + (b - a) * t
        n = self.node("ShaderNodeMix", data_type="FLOAT", clamp_factor=True)
        self.put(_sock(n.inputs, "Factor_Float"), t)
        self.put(_sock(n.inputs, "A_Float"), a)
        self.put(_sock(n.inputs, "B_Float"), b)
        return _sock(n.outputs, "Result_Float")

    # --- vectors
    def vmath(self, op, a, b=None, scale=None):
        n = self.node("ShaderNodeVectorMath", operation=op)
        self.put(n.inputs[0], a)
        if b is not None:
            self.put(n.inputs[1], b)
        if scale is not None:
            self.put(_sock(n.inputs, "Scale"), scale)
        return n.outputs[1] if op in ("DOT_PRODUCT", "LENGTH", "DISTANCE") else n.outputs[0]

    def sep(self, v):
        n = self.node("ShaderNodeSeparateXYZ")
        self.put(n.inputs[0], v)
        return n.outputs[0], n.outputs[1], n.outputs[2]

    def combine(self, x, y, z):
        n = self.node("ShaderNodeCombineXYZ")
        for i, v in enumerate((x, y, z)):
            self.put(n.inputs[i], v)
        return n.outputs[0]

    # --- colours
    def mix(self, fac, a, b, blend="MIX"):
        n = self.node("ShaderNodeMix", data_type="RGBA", blend_type=blend, clamp_factor=True)
        self.put(_sock(n.inputs, "Factor_Float"), fac)
        self.put(_sock(n.inputs, "A_Color"), a)
        self.put(_sock(n.inputs, "B_Color"), b)
        return _sock(n.outputs, "Result_Color")

    def color_ramp(self, fac, stops):
        """stops: [(position, (r, g, b, a)), ...]"""
        n = self.node("ShaderNodeValToRGB")
        el = n.color_ramp.elements
        while len(el) < len(stops):
            el.new(0.5)
        for e, (pos, c) in zip(el, sorted(stops)):
            e.position = pos
            e.color = c
        self.put(n.inputs[0], fac)
        return n.outputs[0]

    # --- textures
    def noise(self, vec=None, scale=1.0, detail=2.0, rough=0.5, lac=2.0, distortion=0.0, dims="3D",
              kind="FBM", w=None, color=False):
        n = self.node("ShaderNodeTexNoise", noise_dimensions=dims, noise_type=kind, normalize=True)
        if vec is not None:
            self.put(n.inputs["Vector"], vec)
        if w is not None:
            self.put(n.inputs["W"], w)
        self.put(n.inputs["Scale"], scale)
        self.put(n.inputs["Detail"], detail)
        self.put(n.inputs["Roughness"], rough)
        self.put(n.inputs["Lacunarity"], lac)
        self.put(n.inputs["Distortion"], distortion)
        return n.outputs[1] if color else n.outputs[0]

    def voronoi(self, vec=None, feature="F1", dims="3D", randomness=1.0, w=None):
        n = self.node("ShaderNodeTexVoronoi", voronoi_dimensions=dims, feature=feature)
        if vec is not None:
            self.put(n.inputs["Vector"], vec)
        if w is not None:
            self.put(n.inputs["W"], w)
        self.put(n.inputs["Scale"], 1.0)
        self.put(n.inputs["Randomness"], randomness)
        return n

    def attr(self, name, out="Fac"):
        n = self.node("ShaderNodeAttribute", attribute_type="GEOMETRY", attribute_name=name)
        return _sock(n.outputs, out)


def _axes(rot_deg):
    """The three axes of a frame turned by XYZ Euler angles (degrees)."""
    from mathutils import Euler
    m = Euler([math.radians(a) for a in rot_deg], "XYZ").to_matrix()
    return [tuple(m.col[i]) for i in range(3)]


# ------------------------------------------------------------------------------------------ the pattern
class Pattern:
    """The rock's structure as functions of position, shared by the material (colour, bump) and the relief
    modifier (geometry): strata, two fracture networks, each fading out where its features would be
    smaller than a few pixels (px: the size of a pixel at this point, in metres)."""

    def __init__(self, g, P, px, p, geo=False):
        self.g, self.px, self.p, self.geo = g, px, p, geo
        self.S = S = p["scale"]
        # features this many pixels across are left out / drawn in full; cracks are at least this wide
        self.lo, self.hi, self.crack_px = (3.0, 8.0, 1.5) if geo else (2.0, 5.0, 0.7)
        k = p["seed"]
        if k:
            P = g.vmath("ADD", P, (37.7 * k, -21.3 * k, 11.9 * k))
        self.P = P
        if p["warp"] > 0:
            c = g.noise(P, scale=1.0 / (p["warp_size"] * S), detail=1.0, color=True)
            w = g.vmath("SCALE", g.vmath("SUBTRACT", c, (0.5, 0.5, 0.5)), scale=2.0 * p["warp"] * S)
            self.Pw = g.vmath("ADD", P, w)
        else:
            self.Pw = P
        self._cache = {}

    def fade(self, size, lo=None, hi=None):
        """0 where a feature of `size` metres is under lo pixels, 1 where it is over hi."""
        return self.g.ramp(self.px, size / (lo or self.lo), size / (hi or self.hi))

    # --- strata
    def strata(self):
        if "strata" in self._cache:
            return self._cache["strata"]
        g, p = self.g, self.p
        th = p["strata"] * self.S
        dip, az = math.radians(p["strata_dip"]), math.radians(p["strata_az"])
        n = (math.sin(dip) * math.sin(az), math.sin(dip) * math.cos(az), math.cos(dip))
        s = g.vmath("DOT_PRODUCT", self.Pw, tuple(c / th for c in n))
        f1 = g.voronoi(w=s, dims="1D", feature="F1")
        ed = g.voronoi(w=s, dims="1D", feature="DISTANCE_TO_EDGE")
        st = dict(s=s, rand=g.sep(f1.outputs["Color"]), edge=g.mul(ed.outputs["Distance"], th), th=th,
                  fade=self.fade(th))
        self._cache["strata"] = st
        return st

    def strata_height(self):
        """Layers standing out or back, with a parting between them (metres)."""
        g, p, S = self.g, self.p, self.S
        st = self.strata()
        h = g.mul(g.sub(st["rand"][0], 0.5), 2.0 * p["strata_relief"] * S)
        w = g.maxi(p["strata_notch_w"] * S, g.mul(self.px, self.crack_px))
        st["crack"] = g.ramp(st["edge"], 0.0, w, 1.0, 0.0)
        h = g.sub(h, g.mul(st["crack"], p["strata_notch"] * S))
        return g.mul(h, st["fade"])

    # --- fracture networks
    def cells(self, k):
        if k in self._cache:
            return self._cache[k]
        g, p = self.g, self.p
        size = p[k] * self.S
        st = p[k + "_stretch"]
        inv = [1.0 / (size * c) for c in st]
        if any(p[k + "_rot"]):
            ax = _axes(p[k + "_rot"])
            q = g.combine(*[g.vmath("DOT_PRODUCT", self.Pw, tuple(a * inv[i] for a in ax[i])) for i in range(3)])
        else:
            q = g.vmath("MULTIPLY", self.Pw, tuple(inv))
        if k != "block":
            q = g.vmath("ADD", q, (5.2, 1.3, 8.1))
        f1 = g.voronoi(q, feature="F1", randomness=p[k + "_random"])
        ed = g.voronoi(q, feature="DISTANCE_TO_EDGE", randomness=p[k + "_random"])
        smin = size * min(st)
        c = dict(q=q, d1=f1.outputs["Distance"], col=f1.outputs["Color"], rand=g.sep(f1.outputs["Color"]),
                 pos=f1.outputs["Position"], edge=g.mul(ed.outputs["Distance"], smin), size=smin,
                 fade=self.fade(smin))
        w = g.maxi(p[k + "_crack_w"] * self.S, g.mul(self.px, self.crack_px))
        c["w"] = w
        c["crack"] = g.ramp(c["edge"], 0.0, w, 1.0, 0.0)
        self._cache[k] = c
        return c

    def cells_height(self, k):
        """Blocks standing out or back, tilted, rounded, with cracks between them (metres)."""
        g, p, S = self.g, self.p, self.S
        c = self.cells(k)
        h = g.mul(g.sub(c["rand"][0], 0.5), 2.0 * p[k + "_relief"] * S)
        if p[k + "_tilt"]:
            lv = g.vmath("SUBTRACT", c["q"], c["pos"])
            tv = g.vmath("SUBTRACT", c["col"], (0.5, 0.5, 0.5))
            h = g.add(h, g.mul(g.vmath("DOT_PRODUCT", lv, tv), 4.0 * p[k + "_tilt"] * S))
        if p[k + "_rib"]:
            h = g.add(h, g.ramp(c["d1"], 0.0, 0.8, p[k + "_rib"] * S, 0.0))
        h = g.sub(h, g.mul(c["crack"], p[k + "_crack"] * S))
        return g.mul(h, c["fade"])


# ------------------------------------------------------------------------------------------ the material
def rock_material(name, preset="sandstone", **overrides):
    """A procedural Cycles rock material (see the module docstring)."""
    p = params(preset, **overrides)
    S = p["scale"]
    mat, nodes, links = common.new_material(name)
    mat["cv_rock"] = json.dumps({"preset": preset, "overrides": overrides})
    g = G(mat.node_tree)
    f_px = float(common.cam_model().f)

    tc = g.node("ShaderNodeTexCoord")
    geo = g.node("ShaderNodeNewGeometry")
    P = g.vmath("SUBTRACT", tc.outputs["Object"], g.attr(ATTR_OFFSET, "Vector"))
    if p["dist_from"] == "attribute":
        dist = g.attr("dist")
    else:
        dist = g.node("ShaderNodeCameraData").outputs["View Distance"]
    px = g.maxi(g.mul(dist, p["px_scale"] / f_px), 1e-4)
    pat = Pattern(g, P, px, p)
    N = geo.outputs["Normal"]
    up = g.sep(N)[2]
    geo_w = g.attr(ATTR_GEO)

    def col(c):
        r, gr, b = common.srgb_to_linear(c)
        k = p["gain"]
        return (min(1.0, r * k), min(1.0, gr * k), min(1.0, b * k), 1.0)

    # ---- structure
    h_mid, h_fine = 0.0, 0.0
    tone = 0.5
    dark = 0.0                                   # cracks, 0..1
    var = g.noise(P, scale=1.0 / (p["var_size"] * S), detail=3.0, rough=0.55, color=True)
    vr, vg, vb = g.sep(var)
    tone = g.add(tone, g.mul(g.sub(vr, 0.5), 2.0 * p["tone_noise"]))
    Nf = N
    if p["strata"] > 0:
        st = pat.strata()
        h_mid = g.add(h_mid, pat.strata_height())
        tone = g.add(tone, g.mul(g.mul(g.sub(st["rand"][1], 0.5), p["tone_strata"]), st["fade"]))
        dark = g.add(dark, g.mul(g.mul(st["crack"], st["fade"]), 0.6))
        if p["lamination"]:
            lam = g.noise(w=g.mul(st["s"], 7.0), dims="1D", detail=2.0, rough=0.6)
            lf = pat.fade(st["th"] / 7.0)
            tone = g.add(tone, g.mul(g.mul(g.sub(lam, 0.5), p["lamination"]), lf))
            h_fine = g.add(h_fine, g.mul(g.mul(g.sub(lam, 0.5), 0.25 * p["strata_relief"] * S), lf))
    rim = 0.0
    for k in ("block", "chip"):
        if p[k] <= 0:
            continue
        c = pat.cells(k)
        hk = pat.cells_height(k)
        if k == "block":
            h_mid = g.add(h_mid, hk)
            tone = g.add(tone, g.mul(g.mul(g.sub(c["rand"][1], 0.5), p["tone_blocks"]), c["fade"]))
        else:
            h_fine = g.add(h_fine, hk)
            tone = g.add(tone, g.mul(g.mul(g.sub(c["rand"][1], 0.5), 0.4 * p["tone_blocks"]), c["fade"]))
        dark = g.add(dark, g.mul(g.mul(c["crack"], c["fade"]), 1.0 if k == "block" else 0.6))
        if p["rim"]:
            band = g.mul(g.ramp(c["edge"], c["w"], g.mul(c["w"], 3.5), 1.0, 0.0), g.sub(1.0, c["crack"]))
            rim = g.add(rim, g.mul(g.mul(band, c["fade"]), 1.0 if k == "block" else 0.5))
        if p["facet"]:
            tv = g.vmath("SUBTRACT", c["col"], (0.5, 0.5, 0.5))
            amount = g.mul(c["fade"], 2.0 * p["facet"] * (1.0 if k == "block" else 0.5))
            Nf = g.vmath("ADD", Nf, g.vmath("SCALE", tv, scale=amount))
    if Nf is not N:
        Nf = g.vmath("NORMALIZE", Nf)

    # grain: fine noise whose finest octave stays above the pixel size
    gs = p["grain"] * S
    detail = g.math("LOGARITHM", g.div(gs / 2.5, px), 2.0)
    n = g.node("ShaderNodeClamp")
    g.put(n.inputs[0], detail)
    n.inputs[1].default_value, n.inputs[2].default_value = 0.0, 6.0
    grain = g.noise(P, scale=1.0 / gs, detail=n.outputs[0], rough=0.6)
    gf = pat.fade(gs, 1.2, 3.0)
    h_fine = g.add(h_fine, g.mul(g.mul(g.sub(grain, 0.5), 2.0 * p["grain_bump"] * S), gf))

    # ---- colour
    c = g.color_ramp(g.clamp01(tone), [(p["ramp"][0], col(p["dark"])), (p["ramp"][1], col(p["base"])),
                                       (p["ramp"][2], col(p["alt"])), (p["ramp"][3], col(p["light"]))])
    value = g.add(1.0, g.mul(g.sub(vg, 0.5), 2.0 * p["var"]))
    value = g.mul(value, g.add(1.0, g.mul(g.mul(g.sub(grain, 0.5), 2.0 * p["grain_color"]), gf)))
    if p["rim"]:
        c = g.mix(g.mul(g.clamp01(rim), p["rim"]), c, col(p["light"]))
    value = g.mul(value, g.sub(1.0, g.mul(g.clamp01(dark), p["crack_dark"])))
    rough = p["rough"]
    if p["top_amount"]:
        tm = g.mul(g.ramp(g.add(up, g.mul(g.sub(vb, 0.5), 0.6)), 0.35, 0.75), p["top_amount"])
        c = g.mix(tm, c, col(p["top"]))
        rough = g.lerp(rough, p["top_rough"], tm)
    if p["stains"]:
        sv = g.vmath("MULTIPLY", P, tuple(1.0 / (p["stain_size"] * S * k) for k in (1.0, 1.0, 12.0)))
        sn = g.noise(sv, scale=1.0, detail=3.0, rough=0.6)
        sm = g.mul(g.mul(g.ramp(sn, 0.45, 0.7), g.ramp(up, 0.9, 0.3)), p["stains"])
        value = g.mul(value, g.sub(1.0, g.mul(sm, 0.65)))
        rough = g.sub(rough, g.mul(sm, 0.25 * 1.0))
    wet = g.clamp01(g.add(p["wet"], g.attr("wet")))
    value = g.mul(value, g.sub(1.0, g.mul(wet, 0.5)))
    rough = g.lerp(rough, 0.15, wet)
    c = g.vmath("SCALE", c, scale=value)
    if p["specks"]:
        q = g.vmath("SCALE", P, scale=1.0 / (p["speck_size"] * S * 3.0))
        v = g.voronoi(q, feature="F1")
        sr = g.sep(v.outputs["Color"])
        dot = g.mul(g.ramp(v.outputs["Distance"], 0.22, 0.34, 1.0, 0.0), g.ramp(sr[0], 1.0 - p["specks"], 1.02 - p["specks"]))
        dot = g.mul(dot, pat.fade(p["speck_size"] * S, 0.8, 2.0))
        c = g.mix(dot, c, col(p["speck_color"]))
    # plant cover from the picture's masks
    veg = g.attr("veg")
    soil = g.clamp01(g.mul(g.mul(veg, g.add(0.5, vb)), g.ramp(up, -0.3, 0.5, 0.35, 1.0)))
    c = g.mix(soil, c, col(p["soil_color"]))
    moss = g.clamp01(g.mul(g.mul(g.attr("moss"), g.add(0.4, g.mul(vg, 1.2))), g.ramp(up, 0.05, 0.55)))
    c = g.mix(moss, c, col(p["moss_color"]))
    rough = g.lerp(rough, 0.95, g.maxi(soil, moss))

    # ---- relief in the shading
    b1 = g.node("ShaderNodeBump")
    g.put(b1.inputs["Strength"], g.lerp(1.0, p["bump_on_geo"], geo_w))
    b1.inputs["Distance"].default_value = p["bump"]
    b1.inputs["Filter Width"].default_value = p["bump_filter"]
    g.put(b1.inputs["Height"], h_mid)
    g.put(b1.inputs["Normal"], Nf)
    b2 = g.node("ShaderNodeBump")
    b2.inputs["Strength"].default_value = 1.0
    b2.inputs["Distance"].default_value = p["bump_fine"]
    b2.inputs["Filter Width"].default_value = p["bump_filter"]
    g.put(b2.inputs["Height"], h_fine)
    g.put(b2.inputs["Normal"], b1.outputs["Normal"])

    bsdf = g.node("ShaderNodeBsdfPrincipled")
    g.put(bsdf.inputs["Base Color"], c)
    g.put(bsdf.inputs["Roughness"], rough)
    bsdf.inputs["Specular IOR Level"].default_value = p["spec"]
    g.put(bsdf.inputs["Normal"], b2.outputs["Normal"])
    out = g.node("ShaderNodeOutputMaterial")
    links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return mat


# ------------------------------------------------------------------------------------------ the relief
def relief_group(preset="sandstone", **overrides):
    """The geometry-node group that turns the pattern's mid-scale relief into real geometry."""
    p = params(preset, **overrides)
    S = p["scale"]
    cm = common.cam_model()
    tree = bpy.data.node_groups.new("CV_RockRelief_" + preset, "GeometryNodeTree")
    tree.interface.new_socket(name="Geometry", in_out="INPUT", socket_type="NodeSocketGeometry")
    tree.interface.new_socket(name="Geometry", in_out="OUTPUT", socket_type="NodeSocketGeometry")
    s_cam = tree.interface.new_socket(name="Camera", in_out="INPUT", socket_type="NodeSocketVector")
    s_cam.default_value = tuple(float(v) for v in cm.pos)
    s_str = tree.interface.new_socket(name="Strength", in_out="INPUT", socket_type="NodeSocketFloat")
    s_str.default_value = 1.0
    s_pix = tree.interface.new_socket(name="Pixel", in_out="INPUT", socket_type="NodeSocketFloat")
    s_pix.default_value = p["px_scale"] / float(cm.f)
    g = G(tree)
    gin = g.node("NodeGroupInput")
    gout = g.node("NodeGroupOutput")
    P = g.node("GeometryNodeInputPosition").outputs[0]
    N = g.node("GeometryNodeInputNormal").outputs["Normal"]
    ray = g.vmath("SUBTRACT", P, gin.outputs["Camera"])
    dist = g.vmath("LENGTH", ray)
    rd = g.vmath("NORMALIZE", ray)
    px = g.maxi(g.mul(dist, gin.outputs["Pixel"]), 1e-4)
    pat = Pattern(g, P, px, p, geo=True)
    h = 0.0
    if p["strata"] > 0:
        h = g.add(h, pat.strata_height())
    if p["block"] > 0:
        h = g.add(h, pat.cells_height("block"))
    if p["chip"] > 0 and p["relief_chips"]:
        h = g.add(h, pat.cells_height("chip"))
    facing = g.math("ABSOLUTE", g.vmath("DOT_PRODUCT", N, rd))
    w = g.ramp(facing, 0.03, 0.3)
    amount = g.mul(g.mul(h, g.mul(w, gin.outputs["Strength"])), p["relief"])
    amount = g.div(amount, g.maxi(facing, 0.45))
    lim = p["relief_max"] * S
    n = g.node("ShaderNodeClamp")
    g.put(n.inputs[0], amount)
    n.inputs[1].default_value, n.inputs[2].default_value = -lim, lim
    off = g.vmath("SCALE", rd, scale=g.mul(n.outputs[0], -1.0))
    sp = g.node("GeometryNodeSetPosition")
    tree.links.new(gin.outputs["Geometry"], sp.inputs["Geometry"])
    g.put(sp.inputs["Offset"], off)
    s1 = g.node("GeometryNodeStoreNamedAttribute", data_type="FLOAT_VECTOR", domain="POINT")
    tree.links.new(sp.outputs["Geometry"], s1.inputs["Geometry"])
    s1.inputs["Name"].default_value = ATTR_OFFSET
    g.put(s1.inputs["Value"], off)
    s2 = g.node("GeometryNodeStoreNamedAttribute", data_type="FLOAT", domain="POINT")
    tree.links.new(s1.outputs["Geometry"], s2.inputs["Geometry"])
    s2.inputs["Name"].default_value = ATTR_GEO
    g.put(s2.inputs["Value"], w)
    tree.links.new(s2.outputs["Geometry"], gout.inputs[0])
    tree["cv_rock"] = json.dumps({"preset": preset, "overrides": overrides})
    return tree, s_cam, s_str


def displace_modifiers(ob, preset=None, strength=1.0, **overrides):
    """Add the relief modifier of a preset to a mesh object."""
    if preset is None:
        info = json.loads(ob.active_material["cv_rock"])
        preset, overrides = info["preset"], {**info["overrides"], **overrides}
    tree, s_cam, s_str = relief_group(preset, **overrides)
    m = ob.modifiers.new("CV_RockRelief", "NODES")
    m.node_group = tree
    cam = ob.matrix_world.inverted() @ __import__("mathutils").Vector(tuple(float(v) for v in common.cam_model().pos))
    m[s_cam.identifier] = tuple(cam)
    m[s_str.identifier] = float(strength)
    return m
