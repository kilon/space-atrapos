"""The pirate's rifle "AAD-73", modelled from ~/Downloads/gun2.png (a side view,
muzzle to the left) entirely with geometry nodes: one object, "Gun", whose
geometry all comes from the node tree "Gun" on an empty mesh.

The reference is a side view, so the model is laid out on it: every
measurement below is in the reference's pixels (2000 x 667 display size;
x right, y down) and converted with K metres per pixel - the gun is about
0.75 m long. The muzzle points to -X, the side shown in the reference faces -Y
(towards the camera), up is +Z.

How the nodes build it:
  slabs     flat parts (receiver, stock, grip, magazine, side plates, mounts)
            are polygons traced off the reference: a Curve Circle with one
            point per corner, each point set from an Index Switch, filled,
            extruded through the gun's thickness and capped; the receiver,
            stock, grip and magazine are rounded off through a distance field
            (eroded then grown back: soft edges like cast metal).
  round     barrel, shroud, bands, scope tubes, turrets - cylinders and cones;
            the shroud's slots are cut out through a distance field.
  glow      the yellow energy cell under the barrel, the cyan charge
            segments in the receiver window (emissive).
  details   the "AAD-73" plate (String to Curves, filled and extruded), the
            hazard stripes, rivets (instanced along the edges), the trigger
            (a swept curve), the skull-and-octopus emblem on the stock (a
            skull and six curling tentacles, swept curves), the scope rings.
  drips     three drops of molten gold hanging from the under-barrel rail.
Materials: worn red-pink paint with rust and chips, copper, dark gunmetal,
brass, rubber (the grip), the two glows, gold.

  blender -b --factory-startup --python external/blender/gun2/build_gun.py
Saves external/blender/gun2/gun2.blend and preview renders (preview_*.png,
preview_vs_reference.png).
"""
import math
import os

import bpy

HERE = "/home/kilon/MEGA/Dimitris/godot/space-atrapos/external/blender/gun2"
REF = os.path.expanduser("~/Downloads/gun2.png")
K = 0.0005                  # metres per reference pixel
CX, CY = 1000.0, 334.0      # the reference pixel at the origin
EMBLEM = (1494, 207, 1612, 312)   # the emblem on the stock, in the reference (x0, y0, x1, y1)
EMBLEM_RES = 4.0                  # grid points per reference pixel when tracing it
PARTS = []                        # the parts' names (filled by build())
EMBLEM_MIN = 600                  # traced pieces smaller than this (grid cells) are specks, dropped


def P(x, y):
    """A reference pixel (x right, y down) -> (X, Z) in metres."""
    return ((x - CX) * K, (CY - y) * K)


# --- node helpers ------------------------------------------------------------------------------

class G:
    def __init__(self, tree):
        self.t = tree
        self.n = 0

    def node(self, kind, **props):
        n = self.t.nodes.new(kind)
        for k, v in props.items():
            setattr(n, k, v)
        n.location = (40 * (self.n % 60), -40 * (self.n // 60))
        self.n += 1
        return n

    def link(self, a, b):
        self.t.links.new(a, b)

    def _set(self, sock, v):
        if isinstance(v, (int, float, tuple, list, bool)) or v is None:
            if v is not None:
                sock.default_value = v
        else:
            self.link(v, sock)

    def math(self, op, a, b=None):
        n = self.node("ShaderNodeMath", operation=op)
        self._set(n.inputs[0], a)
        if b is not None:
            self._set(n.inputs[1], b)
        return n.outputs[0]

    def vmath(self, op, a, b=None):
        n = self.node("ShaderNodeVectorMath", operation=op)
        self._set(n.inputs[0], a)
        if b is not None:
            if op == "SCALE":
                self._set(n.inputs[3], b)
            else:
                self._set(n.inputs[1], b)
        return n.outputs[0]

    def combine(self, x, y, z):
        n = self.node("ShaderNodeCombineXYZ")
        for i, v in enumerate((x, y, z)):
            self._set(n.inputs[i], v)
        return n.outputs[0]

    def separate(self, v):
        n = self.node("ShaderNodeSeparateXYZ")
        self.link(v, n.inputs[0])
        return n.outputs[0], n.outputs[1], n.outputs[2]

    def pos(self):
        return self.node("GeometryNodeInputPosition").outputs[0]

    def transform(self, geo, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
        n = self.node("GeometryNodeTransform")
        self.link(geo, n.inputs["Geometry"])
        n.inputs["Translation"].default_value = loc
        n.inputs["Rotation"].default_value = rot
        n.inputs["Scale"].default_value = scale
        return n.outputs[0]

    def join(self, *geos):
        n = self.node("GeometryNodeJoinGeometry")
        for g in reversed(geos):
            self.link(g, n.inputs[0])
        return n.outputs[0]

    def material(self, geo, mat):
        n = self.node("GeometryNodeSetMaterial")
        self.link(geo, n.inputs["Geometry"])
        n.inputs["Material"].default_value = mat
        return n.outputs[0]

    def smooth(self, geo, angle=None):
        n = self.node("GeometryNodeSetShadeSmooth")
        self.link(geo, n.inputs["Geometry"])
        if angle is not None:   # (sharp where faces meet at more than `angle`)
            ea = self.node("GeometryNodeInputMeshEdgeAngle")
            n.domain = "EDGE"
            self.link(self.math("LESS_THAN", ea.outputs["Unsigned Angle"], math.radians(angle)), n.inputs["Shade Smooth"])
        return n.outputs[0]

    def merge(self, geo, d=1e-5):
        n = self.node("GeometryNodeMergeByDistance")
        self.link(geo, n.inputs["Geometry"])
        n.inputs["Distance"].default_value = d
        return n.outputs[0]

    # --- shapes ------------------------------------------------------------------

    def polygon_curve(self, pts):
        """A closed curve through reference pixels pts (in the XY plane: X, Z-as-Y)."""
        c = self.node("GeometryNodeCurvePrimitiveCircle")
        c.inputs["Resolution"].default_value = len(pts)
        sw = self.node("GeometryNodeIndexSwitch", data_type="VECTOR")
        while len(sw.index_switch_items) < len(pts):
            sw.index_switch_items.new()
        self.link(self.node("GeometryNodeInputIndex").outputs[0], sw.inputs["Index"])
        for i, (x, y) in enumerate(pts):
            X, Z = P(x, y)
            sw.inputs[str(i)].default_value = (X, Z, 0.0)
        sp = self.node("GeometryNodeSetPosition")
        self.link(c.outputs["Curve"], sp.inputs["Geometry"])
        self.link(sw.outputs[0], sp.inputs["Position"])
        return sp.outputs[0]

    def slab_from_curve(self, curve, y0, y1):
        """A filled outline extruded from depth y0 to y1 (metres), capped both sides."""
        f = self.node("GeometryNodeFillCurve")
        self.link(curve, f.inputs["Curve"])
        f.inputs["Mode"].default_value = "N-gons"
        base = self.transform(f.outputs[0], loc=(0, 0, -y1))   # (turned below: depth z -> Y = -z)
        ex = self.node("GeometryNodeExtrudeMesh")
        self.link(base, ex.inputs["Mesh"])
        self.link(self.combine(0.0, 0.0, y1 - y0), ex.inputs["Offset"])
        ex.inputs["Offset Scale"].default_value = 1.0
        ex.inputs["Individual"].default_value = False
        flip = self.node("GeometryNodeFlipFaces")
        self.link(base, flip.inputs["Mesh"])
        solid = self.merge(self.join(ex.outputs["Mesh"], flip.outputs[0]))
        # (built in X / Z-as-Y / depth-as-Z: turned so height is Z and depth Y, y0..y1)
        return self.transform(solid, rot=(math.pi / 2, 0, 0))

    def slab(self, pts, depth_px, centre_px=0.0):
        """A polygon traced off the reference (pixels), depth_px thick, centred
        centre_px towards the viewer (-Y) from the gun's middle."""
        d = depth_px * K
        c = -centre_px * K
        return self.slab_from_curve(self.polygon_curve(pts), c - d / 2, c + d / 2)

    def cyl_x(self, x0, x1, yc, r_px, verts=48, r1_px=None, depth_c=0.0, fill=True):
        """A cylinder (or cone, r1) along X from reference x0 to x1 at height yc."""
        n = self.node("GeometryNodeMeshCone")
        n.inputs["Vertices"].default_value = verts
        n.inputs["Radius Top"].default_value = (r1_px if r1_px is not None else r_px) * K
        n.inputs["Radius Bottom"].default_value = r_px * K
        n.inputs["Depth"].default_value = abs(x1 - x0) * K
        if not fill:
            n.fill_type = "NONE"
        X0, Z = P(x0, yc)
        X1, _ = P(x1, yc)
        # (the cone runs from its base at 0 up +Z, which is turned to +X: base at x0)
        return self.transform(n.outputs["Mesh"], loc=(X0, -depth_c * K, Z), rot=(0, math.pi / 2, 0))

    def cyl_y(self, x, y, r_px, depth_px, front_px, verts=40):
        """A short cylinder facing the viewer (axis Y) at reference (x, y); its
        front face front_px towards the viewer from the gun's middle."""
        n = self.node("GeometryNodeMeshCylinder")
        n.inputs["Vertices"].default_value = verts
        n.inputs["Radius"].default_value = r_px * K
        n.inputs["Depth"].default_value = depth_px * K
        X, Z = P(x, y)
        return self.transform(n.outputs["Mesh"], loc=(X, -(front_px - depth_px / 2) * K, Z), rot=(math.pi / 2, 0, 0))

    def box(self, x0, y0, x1, y1, depth_px, centre_px=0.0):
        return self.slab([(x0, y0), (x1, y0), (x1, y1), (x0, y1)], depth_px, centre_px)

    def sweep(self, curve, radius_m, res=10, caps=True):
        prof = self.node("GeometryNodeCurvePrimitiveCircle")
        prof.inputs["Resolution"].default_value = res
        prof.inputs["Radius"].default_value = radius_m
        m = self.node("GeometryNodeCurveToMesh")
        self.link(curve, m.inputs["Curve"])
        self.link(prof.outputs["Curve"], m.inputs["Profile Curve"])
        m.inputs["Fill Caps"].default_value = caps
        return m.outputs["Mesh"]

    def path(self, pts, depth_front_px, resample=None):
        """An open curve through reference pixels, at depth depth_front_px towards the viewer."""
        line = self.node("GeometryNodeCurvePrimitiveLine")
        rs = self.node("GeometryNodeResampleCurve")
        self.link(line.outputs[0], rs.inputs["Curve"])
        rs.inputs["Count"].default_value = len(pts)
        sw = self.node("GeometryNodeIndexSwitch", data_type="VECTOR")
        while len(sw.index_switch_items) < len(pts):
            sw.index_switch_items.new()
        self.link(self.node("GeometryNodeInputIndex").outputs[0], sw.inputs["Index"])
        for i, (x, y) in enumerate(pts):
            X, Z = P(x, y)
            sw.inputs[str(i)].default_value = (X, -depth_front_px * K, Z)
        sp = self.node("GeometryNodeSetPosition")
        self.link(rs.outputs[0], sp.inputs["Geometry"])
        self.link(sw.outputs[0], sp.inputs["Position"])
        out = sp.outputs[0]
        # smooth it: a Catmull-Rom-ish spline through the points
        st = self.node("GeometryNodeCurveSplineType", spline_type="CATMULL_ROM")
        self.link(out, st.inputs["Curve"])
        out = st.outputs[0]
        if resample:
            rs2 = self.node("GeometryNodeResampleCurve")
            self.link(out, rs2.inputs["Curve"])
            rs2.inputs["Count"].default_value = resample
            out = rs2.outputs[0]
        return out

    # --- distance fields ----------------------------------------------------------

    def sdf(self, mesh, voxel):
        n = self.node("GeometryNodeMeshToSDFGrid")
        self.link(mesh, n.inputs["Mesh"])
        n.inputs["Voxel Size"].default_value = voxel
        n.inputs["Band Width"].default_value = 4
        return n.outputs[0]

    def offset(self, grid, d):
        n = self.node("GeometryNodeSDFGridOffset")
        self.link(grid, n.inputs["Grid"])
        n.inputs["Distance"].default_value = d
        return n.outputs[0]

    def to_mesh(self, grid):
        n = self.node("GeometryNodeGridToMesh")
        self.link(grid, n.inputs["Grid"])
        n.inputs["Threshold"].default_value = 0.0
        return n.outputs[0]

    def rounded(self, mesh, r, voxel):
        """mesh with its edges rounded by r (eroded then grown back)."""
        return self.to_mesh(self.offset(self.offset(self.sdf(mesh, voxel), r), -r))

    def carve(self, mesh, cutters, voxel):
        a = self.sdf(mesh, voxel)
        n = self.node("GeometryNodeSDFGridBoolean", operation="DIFFERENCE")
        self.link(a, n.inputs["Grid 1"])
        for c in cutters:
            self.link(self.sdf(c, voxel), n.inputs["Grid 2"])
        return self.to_mesh(n.outputs[0])


# --- materials ----------------------------------------------------------------------------------

def _principled(m):
    m.use_nodes = True
    return m.node_tree.nodes.get("Principled BSDF")


def worn(name, base, metal, rough, rust=(0.6, 0.27, 0.07), chips=(0.045, 0.032, 0.028), rust_amt=0.45, chip_amt=0.28, scale=40.0, pits=1.0):
    """Painted / bare metal, worn: rust patches (orange-brown) and dark chips,
    from two noise textures; rust and chips are rough and not metallic."""
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    b = _principled(m)
    nt = m.node_tree
    for n in list(nt.nodes):
        if n.type not in ("BSDF_PRINCIPLED", "OUTPUT_MATERIAL"):
            nt.nodes.remove(n)
    co = nt.nodes.new("ShaderNodeTexCoord")
    n1 = nt.nodes.new("ShaderNodeTexNoise"); n1.inputs["Scale"].default_value = scale; n1.inputs["Detail"].default_value = 10.0
    n1.inputs["Roughness"].default_value = 0.65
    n2 = nt.nodes.new("ShaderNodeTexNoise"); n2.inputs["Scale"].default_value = scale * 3.2; n2.inputs["Detail"].default_value = 6.0
    for n in (n1, n2):
        nt.links.new(co.outputs["Object"], n.inputs["Vector"])
    r1 = nt.nodes.new("ShaderNodeValToRGB")   # rust mask
    r1.color_ramp.elements[0].position = 1.0 - rust_amt
    r1.color_ramp.elements[1].position = 1.0 - rust_amt + 0.06
    nt.links.new(n1.outputs["Fac"], r1.inputs["Fac"])
    r2 = nt.nodes.new("ShaderNodeValToRGB")   # chips mask
    r2.color_ramp.elements[0].position = 1.0 - chip_amt
    r2.color_ramp.elements[1].position = 1.0 - chip_amt + 0.03
    nt.links.new(n2.outputs["Fac"], r2.inputs["Fac"])

    def mix(a, bcol, fac):
        mx = nt.nodes.new("ShaderNodeMix"); mx.data_type = "RGBA"
        A = [s for s in mx.inputs if s.name == "A" and s.type == "RGBA"][0]
        B = [s for s in mx.inputs if s.name == "B" and s.type == "RGBA"][0]
        if isinstance(a, tuple):
            A.default_value = (*a, 1)
        else:
            nt.links.new(a, A)
        B.default_value = (*bcol, 1)
        nt.links.new(fac, mx.inputs["Factor"])
        return [s for s in mx.outputs if s.name == "Result" and s.type == "RGBA"][0]
    # pits: small dark spots all over (Voronoi cells' centres), like the reference's pitted paint
    vo = nt.nodes.new("ShaderNodeTexVoronoi"); vo.inputs["Scale"].default_value = scale * 7.0
    vo.inputs["Randomness"].default_value = 1.0
    nt.links.new(co.outputs["Object"], vo.inputs["Vector"])
    r3 = nt.nodes.new("ShaderNodeValToRGB")
    r3.color_ramp.elements[0].position = 0.12 * pits
    r3.color_ramp.elements[1].position = 0.12 * pits + 0.04
    r3.color_ramp.elements[0].color = (1, 1, 1, 1)
    r3.color_ramp.elements[1].color = (0, 0, 0, 1)
    nt.links.new(vo.outputs["Distance"], r3.inputs["Fac"])
    col = mix(base, rust, r1.outputs["Color"])
    col = mix(col, chips, r2.outputs["Color"])
    col = mix(col, tuple(c * 0.6 for c in chips), r3.outputs["Color"])
    nt.links.new(col, b.inputs["Base Color"])
    # metallic / roughness: bare where painted, rough where rusted or chipped
    worn_mask = nt.nodes.new("ShaderNodeMath"); worn_mask.operation = "MAXIMUM"
    nt.links.new(r1.outputs["Color"], worn_mask.inputs[0]); nt.links.new(r2.outputs["Color"], worn_mask.inputs[1])
    pit_mask = nt.nodes.new("ShaderNodeMath"); pit_mask.operation = "MAXIMUM"
    nt.links.new(worn_mask.outputs[0], pit_mask.inputs[0]); nt.links.new(r3.outputs["Color"], pit_mask.inputs[1])
    worn_mask = pit_mask
    met = nt.nodes.new("ShaderNodeMapRange")
    met.inputs["To Min"].default_value = metal; met.inputs["To Max"].default_value = 0.0
    nt.links.new(worn_mask.outputs[0], met.inputs["Value"])
    nt.links.new(met.outputs["Result"], b.inputs["Metallic"])
    ro = nt.nodes.new("ShaderNodeMapRange")
    ro.inputs["To Min"].default_value = rough; ro.inputs["To Max"].default_value = 0.85
    nt.links.new(worn_mask.outputs[0], ro.inputs["Value"])
    nt.links.new(ro.outputs["Result"], b.inputs["Roughness"])
    bump = nt.nodes.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.35
    nt.links.new(worn_mask.outputs[0], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], b.inputs["Normal"])
    return m


def plain(name, col, metal=0.0, rough=0.5, emit=0.0, transmission=0.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    b = _principled(m)
    b.inputs["Base Color"].default_value = (*col, 1)
    b.inputs["Metallic"].default_value = metal
    b.inputs["Roughness"].default_value = rough
    if emit:
        b.inputs["Emission Color"].default_value = (*col, 1)
        b.inputs["Emission Strength"].default_value = emit
    b.inputs["Transmission Weight"].default_value = transmission
    return m


# --- the gun ---------------------------------------------------------------------------------

def build():
    paint = worn("GunPaint", (0.32, 0.1, 0.1), 0.2, 0.5, rust_amt=0.38, chip_amt=0.42, scale=70.0, pits=1.2)
    copper = worn("GunCopper", (0.42, 0.17, 0.07), 0.8, 0.42, rust=(0.6, 0.3, 0.08), chips=(0.05, 0.035, 0.03), rust_amt=0.42, chip_amt=0.3, scale=55.0)
    steel = worn("GunSteel", (0.1, 0.075, 0.065), 0.7, 0.45, rust=(0.5, 0.22, 0.06), rust_amt=0.38, chip_amt=0.22, scale=55.0)
    brass = worn("GunBrass", (0.78, 0.52, 0.2), 1.0, 0.3, rust=(0.35, 0.18, 0.06), rust_amt=0.3, chip_amt=0.1)
    rubber = worn("GunRubber", (0.06, 0.05, 0.045), 0.0, 0.75, rust=(0.45, 0.2, 0.06), rust_amt=0.2, chip_amt=0.2, scale=60.0, pits=2.2)
    scopem = worn("GunScope", (0.085, 0.05, 0.035), 0.45, 0.5, rust=(0.5, 0.24, 0.07), rust_amt=0.36, chip_amt=0.25, scale=55.0)
    glow_y = plain("GunGlowYellow", (0.85, 0.8, 0.0), 0.0, 0.15, emit=5.0)
    cell = plain("GunCellGlass", (0.75, 0.7, 0.05), 0.0, 0.05, emit=0.9, transmission=0.6)
    glow_c = plain("GunGlowCyan", (0.0, 0.85, 0.85), 0.0, 0.15, emit=2.2)
    glass = plain("GunGlass", (0.03, 0.05, 0.06), 0.0, 0.05)
    gold = plain("GunGold", (0.95, 0.6, 0.1), 0.6, 0.15, emit=0.3)
    decal = plain("GunDecal", (0.85, 0.55, 0.15), 0.4, 0.45)
    stripe = plain("GunStripe", (0.9, 0.5, 0.1), 0.0, 0.55)

    tree = bpy.data.node_groups.get("Gun")
    if tree:
        bpy.data.node_groups.remove(tree)
    tree = bpy.data.node_groups.new("Gun", "GeometryNodeTree")
    tree.interface.new_socket("Geometry", in_out="OUTPUT", socket_type="NodeSocketGeometry")
    g = G(tree)
    out = g.node("NodeGroupOutput")
    parts = []
    # Every piece is tagged with the part it belongs to (a "part" face attribute,
    # an index into PARTS): split_parts() makes one object per part from it.
    cur = ["Misc"]

    def part(name):
        cur[0] = name
        if name not in PARTS:
            PARTS.append(name)

    def M(geo, mat, angle=35):
        st = g.node("GeometryNodeStoreNamedAttribute", data_type="INT", domain="FACE")
        g.link(g.material(g.smooth(geo, angle), mat), st.inputs["Geometry"])
        st.inputs["Name"].default_value = "part"
        [x for x in st.inputs if x.name == "Value" and x.type == "INT"][0].default_value = PARTS.index(cur[0])
        parts.append(st.outputs[0])
    PARTS.clear()
    part("Misc")
    V = 0.0011   # voxel (m) for the rounded parts

    # --- the body: receiver, stock, grip, magazine (rounded through a distance field) ----
    receiver = g.slab([(796, 214), (828, 180), (1210, 180), (1215, 170), (1270, 170), (1275, 180), (1450, 180),
                       (1450, 332), (1300, 332), (1270, 345), (1105, 345), (1095, 333), (850, 333), (800, 292)], 64)
    stock = g.slab([(1445, 154), (1590, 154), (1612, 180), (1690, 182), (1712, 205), (1716, 330), (1708, 385),
                    (1690, 420), (1640, 428), (1590, 410), (1560, 380), (1500, 362), (1445, 352)], 70)
    grip = g.slab([(1262, 330), (1350, 330), (1395, 372), (1418, 450), (1462, 548), (1452, 590), (1420, 607),
                   (1350, 610), (1318, 590), (1300, 540), (1292, 470), (1275, 410)], 58)
    mag = g.slab([(927, 342), (1064, 342), (1060, 588), (1064, 590), (1064, 612), (922, 612), (922, 590), (927, 588)], 46)
    part("Receiver")
    M(g.rounded(receiver, 0.0035, V), paint)
    part("Stock")
    M(g.rounded(stock, 0.004, V), paint)
    part("Grip")
    M(g.rounded(grip, 0.004, V), rubber)
    part("Magazine")
    M(g.rounded(mag, 0.0025, V), steel)
    # The magazine's ribs and the grip's panel.
    for x in (950, 975, 1000, 1025):
        M(g.box(x, 420, x + 12, 575, 6, 25), steel)
    part("Grip")
    M(g.slab([(1300, 395), (1350, 380), (1395, 450), (1430, 548), (1415, 585), (1350, 585), (1320, 545), (1310, 470)], 6, 31), rubber)
    M(g.box(1340, 575, 1460, 600, 8, 30), steel)   # (the grip's base plate)
    part("Magazine")
    M(g.box(948, 358, 1045, 405, 5, 25.5), steel)   # (the magazine's label plate)
    M(g.box(922, 588, 1066, 600, 52, 0), brass)     # (its base's brass edge)
    part("Stock")
    # The butt's edge and the stock's lower chamfer: darker steel strips.
    M(g.slab([(1700, 200), (1717, 206), (1719, 330), (1710, 386), (1692, 422), (1680, 416), (1696, 382), (1703, 330)], 74), steel)
    M(g.slab([(1450, 352), (1500, 362), (1560, 380), (1590, 410), (1640, 428), (1690, 421), (1686, 410), (1640, 416),
              (1594, 400), (1566, 370), (1502, 352), (1450, 342)], 74), steel)
    part("Trigger guard")
    # Lower frame and trigger guard (a loop: outer outline with the inner hole).
    guard_out = g.polygon_curve([(1095, 340), (1272, 340), (1272, 400), (1250, 425), (1110, 432), (1088, 410)])
    guard_in = g.polygon_curve([(1112, 352), (1252, 352), (1252, 395), (1238, 410), (1122, 415), (1108, 400)])
    M(g.slab_from_curve(g.join(guard_out, guard_in), -0.012, 0.012), steel)
    part("Trigger")
    trig = g.path([(1225, 330), (1222, 352), (1212, 375), (1196, 392), (1190, 396)], 0, resample=24)
    M(g.sweep(trig, 0.0045), brass)
    part("Front lever")
    # The front lever under the receiver (a ring).
    lever = g.path([(830, 335), (800, 345), (790, 370), (810, 385), (860, 384), (885, 370)], 0, resample=30)
    M(g.sweep(lever, 0.0035), steel)

    # --- side detail on the receiver (towards the viewer) -------------------------------
    part("Charge window")
    win = g.slab([(918, 215), (1158, 215), (1172, 237), (1158, 260), (918, 260), (904, 237)], 6, 34)   # window frame
    M(win, steel)
    M(g.slab([(925, 220), (1152, 220), (1164, 237), (1152, 255), (925, 255), (913, 237)], 3, 37), glass)
    for k in range(6):
        x = 930 + k * 37
        M(g.box(x, 230, x + 28, 244, 4, 38.5), glow_c)
    part("Name plate")
    plate = g.slab([(842, 285), (1108, 285), (1112, 330), (848, 332)], 6, 34)
    M(plate, paint)
    M(g.slab([(836, 280), (1114, 280), (1118, 336), (842, 338)], 4, 33), steel)   # (its dark frame)
    txt = g.node("GeometryNodeStringToCurves")
    txt.inputs["String"].default_value = "AAD-73"
    txt.inputs["Size"].default_value = 34 * K
    tr = g.node("GeometryNodeRealizeInstances")
    g.link(txt.outputs["Curve Instances"], tr.inputs[0])
    X, Z = P(930, 320)
    tsolid = g.slab_from_curve(tr.outputs[0], 0.0, 2 * K)
    M(g.transform(tsolid, loc=(X, -39 * K, Z)), decal)
    part("Hazard stripes")
    for k in range(3):   # hazard stripes: on the plate's right end and the receiver's front
        x = 1068 + k * 14
        M(g.slab([(x, 288), (x + 7, 288), (x - 6, 328), (x - 13, 328)], 3, 37.5), stripe)
    for k in range(4):
        x = 822 + k * 22
        M(g.slab([(x + 12, 236), (x + 22, 236), (x + 6, 276), (x - 4, 276)], 3, 35.5), stripe)
    part("Side panels")
    # Raised side panels: the stock's, the receiver's front.
    M(g.slab([(1472, 172), (1598, 172), (1614, 192), (1688, 196), (1700, 330), (1690, 382), (1650, 408), (1600, 394),
              (1472, 342)], 4, 36), paint)
    M(g.slab([(805, 222), (835, 192), (905, 192), (905, 280), (840, 280), (808, 260)], 3, 33.5), paint)
    part("Rivets")
    # Rivets along the edges.
    for (x, y) in [(812, 243), (853, 296), (1100, 296), (853, 323), (1100, 323), (1175, 210), (1175, 268), (1440, 192),
                   (1440, 320), (1180, 322), (1460, 175), (1580, 168), (1702, 205), (1690, 388), (1505, 345),
                   (1460, 255), (1640, 410)]:
        M(g.cyl_y(x, y, 6, 4, 36, verts=16), brass)
    part("Knob")
    M(g.cyl_y(1265, 305, 14, 6, 37), steel)      # the knob behind the plate
    M(g.cyl_y(1265, 305, 7, 3, 39.5), brass)
    part("Bolt block")
    # The bolt block on top and the rear sight.
    M(g.box(1205, 155, 1272, 178, 40), steel)
    M(g.box(1215, 150, 1262, 158, 30), steel)

    part("Emblem")
    # --- the emblem on the stock: traced from the reference itself ----------------------
    # A fine grid over the emblem samples the reference picture (packed in the
    # file); the cells that are the emblem's gold paint stay, the rest go; the
    # cut-out gets a little thickness and its stair-stepped edge is smoothed
    # through a distance field. So it is the reference's skull and octopus.
    img = bpy.data.images.get("gun2_reference")
    if img is None:
        img = bpy.data.images.load(REF)
        img.name = "gun2_reference"
    if not img.packed_file:
        img.pack()
    W_REF, H_REF = 2000.0, 667.0           # (the reference's display size, as all our pixel numbers)
    x0, y0, x1, y1 = EMBLEM
    grid = g.node("GeometryNodeMeshGrid")
    grid.inputs["Size X"].default_value = (x1 - x0) * K
    grid.inputs["Size Y"].default_value = (y1 - y0) * K
    grid.inputs["Vertices X"].default_value = int((x1 - x0) * EMBLEM_RES) + 1
    grid.inputs["Vertices Y"].default_value = int((y1 - y0) * EMBLEM_RES) + 1
    gx_, gz_ = P((x0 + x1) / 2, (y0 + y1) / 2)
    em = g.transform(grid.outputs["Mesh"], loc=(gx_, gz_, 0))   # (X, Z-as-Y, as the slabs are built)
    ex_, ey_, _ = g.separate(g.pos())
    u = g.math("DIVIDE", g.math("ADD", g.math("DIVIDE", ex_, K), CX), W_REF)
    v = g.math("SUBTRACT", 1.0, g.math("DIVIDE", g.math("SUBTRACT", CY, g.math("DIVIDE", ey_, K)), H_REF))
    tex = g.node("GeometryNodeImageTexture")
    tex.inputs["Image"].default_value = img
    tex.interpolation = "Linear"
    g.link(g.combine(u, v, 0.0), tex.inputs["Vector"])
    r_, gg_, b_ = g.separate(tex.outputs["Color"])
    # gold paint (linear colour): red over 0.3 and green over 0.11 - the maroon around it has
    # green ~0.01, the orange rust spots ~0.09
    keep = g.math("MULTIPLY", g.math("GREATER_THAN", gg_, 0.11), g.math("GREATER_THAN", r_, 0.3))
    dele = g.node("GeometryNodeDeleteGeometry", domain="FACE")
    g.link(em, dele.inputs["Geometry"])
    g.link(g.math("LESS_THAN", keep, 0.5), dele.inputs["Selection"])
    # stray specks (other bits of gold in the picture): separate pieces under EMBLEM_MIN faces go
    isl = g.node("GeometryNodeInputMeshIsland")
    acc = g.node("GeometryNodeAccumulateField", data_type="FLOAT", domain="FACE")
    acc.inputs[0].default_value = 1.0
    g.link(isl.outputs["Island Index"], acc.inputs["Group ID"] if "Group ID" in acc.inputs else acc.inputs["Group Index"])
    specks = g.node("GeometryNodeDeleteGeometry", domain="FACE")
    g.link(dele.outputs[0], specks.inputs["Geometry"])
    g.link(g.math("LESS_THAN", acc.outputs["Total"], EMBLEM_MIN), specks.inputs["Selection"])
    # thickness: extrude, add the back faces, turn upright (as slab_from_curve does)
    ex = g.node("GeometryNodeExtrudeMesh")
    base = g.transform(specks.outputs[0], loc=(0, 0, 38.0 * K))
    g.link(base, ex.inputs["Mesh"])
    g.link(g.combine(0.0, 0.0, 2.6 * K), ex.inputs["Offset"])
    ex.inputs["Offset Scale"].default_value = 1.0
    ex.inputs["Individual"].default_value = False
    flip = g.node("GeometryNodeFlipFaces")
    g.link(base, flip.inputs["Mesh"])
    solid = g.transform(g.merge(g.join(ex.outputs["Mesh"], flip.outputs[0])), rot=(math.pi / 2, 0, 0))
    M(g.rounded(solid, 0.00025, 0.00018), decal, angle=180)

    part("Muzzle shroud")
    # --- barrel, shroud, bands, energy cell ----------------------------------------------
    shroud = g.cyl_x(226, 440, 263, 68, verts=64)
    bore = g.cyl_x(215, 300, 263, 44, verts=48)
    slots = []
    for yy in (222, 248, 274, 300):   # the slots, through both sides
        sl = g.node("GeometryNodeMeshCube")
        sl.inputs["Size"].default_value = (70 * K, 0.2, 12 * K)
        X, Z = P(340, yy)
        slots.append(g.transform(sl.outputs["Mesh"], loc=(X, 0, Z)))
    M(g.carve(shroud, [bore] + slots, 0.0009), steel)
    M(g.cyl_x(224, 238, 263, 70, verts=64), brass)                 # the muzzle's rim
    part("Barrel bands")
    M(g.cyl_x(438, 462, 263, 72, verts=64), copper)                # bands
    M(g.cyl_x(528, 556, 265, 72, verts=64), copper)
    part("Barrel housing")
    M(g.cyl_x(440, 800, 265, 64, verts=64), copper)                # the barrel housing
    part("Energy cell")
    M(g.cyl_x(560, 800, 292, 27, verts=40, depth_c=44), cell)      # the energy cell (half out of the housing's side):
    M(g.cyl_x(568, 792, 292, 12, verts=24, depth_c=58), glow_y)    # a glass tube with a bright core
    M(g.cyl_x(555, 566, 292, 31, verts=40, depth_c=44), brass)
    M(g.cyl_x(794, 805, 292, 31, verts=40, depth_c=44), brass)
    part("Top rod")
    # Top rod with its clamps; under-barrel rail with lugs.
    M(g.cyl_x(395, 870, 166, 7, verts=20), steel)
    part("Rod clamps")
    M(g.box(395, 155, 432, 190, 40), copper)
    M(g.box(530, 143, 615, 192, 46), copper)
    M(g.box(560, 190, 590, 205, 36), copper)
    part("Under-barrel rail")
    M(g.box(330, 333, 835, 350, 30), copper)
    M(g.box(405, 335, 500, 368, 34), copper)
    M(g.box(580, 335, 665, 370, 36), copper)
    for x in (430, 470, 625):
        M(g.cyl_y(x, 352, 5, 3, 19, verts=12), brass)

    part("Scope")
    # --- scope -------------------------------------------------------------------------
    M(g.cyl_x(806, 900, 82, 50, verts=64), scopem)                  # front bell
    M(g.cyl_x(804, 822, 82, 52, verts=64), brass)                  # its gold rim
    M(g.cyl_x(800, 806, 82, 42, verts=64), glass)                  # the lens
    M(g.cyl_x(895, 1120, 84, 33, verts=48), scopem)                 # the tube
    M(g.cyl_x(1110, 1210, 84, 48, verts=64), scopem)                # rear bell
    M(g.cyl_x(1205, 1212, 84, 40, verts=48), glass)
    M(g.cyl_x(1190, 1206, 84, 50, verts=64), brass)                # its rim
    for x0 in (930, 1150):
        M(g.cyl_x(x0, x0 + 14, 84, 37, verts=48), scopem)           # rings
    M(g.cyl_y(1047, 88, 32, 22, 46, verts=48), scopem)              # side turret
    M(g.cyl_y(1047, 88, 20, 4, 48, verts=32), brass)
    tur = g.node("GeometryNodeMeshCylinder")                       # top turret
    tur.inputs["Vertices"].default_value = 40
    tur.inputs["Radius"].default_value = 34 * K
    tur.inputs["Depth"].default_value = 18 * K
    X, Z = P(1045, 40)
    M(g.transform(tur.outputs["Mesh"], loc=(X, 0, Z)), scopem)
    part("Scope mount")
    M(g.box(948, 118, 1002, 150, 34), scopem)                       # the mount
    M(g.box(952, 145, 1138, 176, 40), scopem)
    part("Scope")
    # Engraved plates on the bells and the tube, the side turret's knurled ring, a second rim.
    for (x0, y0, x1, y1) in ((850, 55, 885, 70), (850, 96, 885, 110), (1140, 58, 1175, 72), (1140, 96, 1175, 110),
                             (900, 66, 925, 78)):
        M(g.box(x0, y0, x1, y1, 6, 47.5 if x0 < 890 or x0 > 1130 else 32), steel)
    for k in range(16):
        a = k / 16 * 2 * math.pi
        M(g.cyl_y(1047 + 31 * math.cos(a), 88 + 31 * math.sin(a), 3.5, 22, 46.5, verts=8), brass)
    M(g.cyl_x(880, 892, 82, 51, verts=64), brass)
    M(g.cyl_x(1124, 1134, 84, 49, verts=64), brass)
    part("Scope mount")
    for x in (975, 1118):
        M(g.cyl_y(x, 160, 7, 3, 21.5, verts=16), brass)

    part("Gold drips")
    # --- drips of molten gold from the under-barrel rail -----------------------------------
    for (x, y0, y1) in ((350, 350, 512), (478, 368, 488), (620, 370, 548)):
        n = 26
        pts = [(x + 0.4 * math.sin(i * 0.7), y0 + (y1 - y0) * (i / (n - 1))) for i in range(n)]
        cv = g.path(pts, 0, resample=40)
        rad = g.node("GeometryNodeSetCurveRadius")
        g.link(cv, rad.inputs["Curve"])
        fac = g.node("GeometryNodeSplineParameter").outputs["Factor"]
        # (thick where it leaves the rail, thinning, then the drop swelling at the end)
        r = g.math("ADD", g.math("MULTIPLY", g.math("SUBTRACT", 1.0, fac), 1.6), g.math("MULTIPLY", g.math("POWER", fac, 14.0), 3.2))
        g.link(g.math("ADD", r, 0.5), rad.inputs["Radius"])
        prof = g.node("GeometryNodeCurvePrimitiveCircle")
        prof.inputs["Resolution"].default_value = 12
        prof.inputs["Radius"].default_value = 3.2 * K
        cm = g.node("GeometryNodeCurveToMesh")
        g.link(rad.outputs[0], cm.inputs["Curve"])
        g.link(prof.outputs["Curve"], cm.inputs["Profile Curve"])
        g.link(g.node("GeometryNodeInputRadius").outputs[0], cm.inputs["Scale"])
        cm.inputs["Fill Caps"].default_value = True
        drop = g.node("GeometryNodeMeshUVSphere")
        drop.inputs["Radius"].default_value = 9 * K
        X, Z = P(x + 0.4 * math.sin((n - 1) * 0.7), y1 - 2)
        M(g.rounded(g.join(cm.outputs["Mesh"], g.transform(drop.outputs["Mesh"], loc=(X, 0, Z), scale=(1, 1, 1.3))), 0.0004, 0.0006),
          gold, angle=180)

    g.link(g.join(*parts), out.inputs[0])

    ob = bpy.data.objects.get("Gun")
    if ob is None:
        ob = bpy.data.objects.new("Gun", bpy.data.meshes.new("Gun"))
        bpy.context.scene.collection.objects.link(ob)
    for md in list(ob.modifiers):
        ob.modifiers.remove(md)
    ob.modifiers.new("Gun", "NODES").node_group = tree
    for m in (paint, copper, steel, brass, rubber, scopem, cell, glow_y, glow_c, glass, gold, decal, stripe):
        if m.name not in [s.material.name for s in ob.material_slots if s.material]:
            ob.data.materials.append(m)
    return ob


def stage():
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x, sc.render.resolution_y = 1500, 500
    sc.render.film_transparent = False
    sc.view_settings.view_transform = "Standard"
    w = sc.world or bpy.data.worlds.new("World")
    sc.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.012, 0.002, 0.014, 1)   # (the reference's deep purple)
    w.node_tree.nodes["Background"].inputs[1].default_value = 1.0
    gun = bpy.data.objects["Gun"]
    for name, loc, energy, size in (("Key", (-0.4, -1.2, 0.9), 18, 1.6), ("Fill", (0.9, -1.0, -0.2), 6, 1.5),
                                    ("Rim", (0.2, 1.2, 0.8), 20, 1.0), ("Top", (0.0, 0.4, 1.2), 6, 0.8)):
        l = bpy.data.objects.get(name)
        if l is None:
            l = bpy.data.objects.new(name, bpy.data.lights.new(name, "AREA"))
            sc.collection.objects.link(l)
        l.data.energy = energy
        l.data.color = {"Key": (1.0, 0.86, 0.7), "Fill": (0.75, 0.6, 0.9), "Rim": (1.0, 0.55, 0.75), "Top": (1.0, 0.9, 0.8)}[name]
        l.data.size = size
        l.location = loc
        c = l.constraints.get("Aim") or l.constraints.new("TRACK_TO")
        c.name = "Aim"
        c.target = gun
    cam = bpy.data.objects.get("Camera")
    if cam is None:
        cam = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
        sc.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    sc.camera = cam
    # Glow around the lights (render only): the compositor's bloom.
    ct = bpy.data.node_groups.get("GunComp") or bpy.data.node_groups.new("GunComp", "CompositorNodeTree")
    ct.nodes.clear()
    if not ct.interface.items_tree:
        ct.interface.new_socket("Image", in_out="OUTPUT", socket_type="NodeSocketColor")
    rl = ct.nodes.new("CompositorNodeRLayers")
    gl = ct.nodes.new("CompositorNodeGlare")
    gl.inputs["Type"].default_value = "Bloom"
    gl.inputs["Threshold"].default_value = 2.5   # (only the glowing lights, not shiny metal)
    gl.inputs["Strength"].default_value = 0.8
    go = ct.nodes.new("NodeGroupOutput")
    ct.links.new(rl.outputs["Image"], gl.inputs["Image"])
    ct.links.new(gl.outputs["Image"], go.inputs[0])
    sc.compositing_node_group = ct
    return cam


def render_views(cam):
    sc = bpy.context.scene
    views = (("side", -90, 0, 1.0), ("q3", -60, 20, 0.85), ("rear", 120, 15, 0.85), ("top", -90, 75, 1.0))
    for name, az, el, sc_ in views:
        a, e = math.radians(az), math.radians(el)
        tgt = (0.0, 0.0, P(1000, 330)[1])
        d = 3.0
        cam.location = (tgt[0] + d * math.cos(e) * math.cos(a), tgt[1] + d * math.cos(e) * math.sin(a), tgt[2] + d * math.sin(e))
        cam.rotation_euler = (math.pi / 2 - e, 0, a + math.pi / 2)
        cam.data.ortho_scale = 2000 * K * sc_
        sc.render.filepath = os.path.join(HERE, "preview_%s.png" % name)
        bpy.ops.render.render(write_still=True)


def split_parts(src, name="AAD-73"):
    """The gun as separate objects, one per part (from the "part" attribute the
    node tree tags every piece with), each with its origin at its middle, all
    in the collection `name` and parented to an empty `name` - move, turn or
    scale that and the whole gun follows. The procedural object `src` stays in
    the file, in a hidden collection "<name> (procedural)" - rebuild from it."""
    import bmesh
    from mathutils import Vector
    sc = bpy.context.scene
    col = bpy.data.collections.get(name) or bpy.data.collections.new(name)
    if col.name not in sc.collection.children:
        sc.collection.children.link(col)
    for ob in list(col.objects):
        bpy.data.objects.remove(ob)
    root = bpy.data.objects.new(name, None)
    root.empty_display_type = "PLAIN_AXES"
    root.empty_display_size = 0.15
    col.objects.link(root)
    ev = src.evaluated_get(bpy.context.evaluated_depsgraph_get())
    whole = bpy.data.meshes.new_from_object(ev)
    made = []
    for idx, pname in enumerate(PARTS):
        bm = bmesh.new()
        bm.from_mesh(whole)
        lay = bm.faces.layers.int.get("part")
        drop = [f for f in bm.faces if f[lay] != idx]
        bmesh.ops.delete(bm, geom=drop, context="FACES")
        loose = [v for v in bm.verts if not v.link_faces]
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
        if not bm.faces:
            bm.free()
            continue
        used = sorted({f.material_index for f in bm.faces})
        remap = {m: i for i, m in enumerate(used)}
        for f in bm.faces:
            f.material_index = remap[f.material_index]
        lo = Vector((min(v.co.x for v in bm.verts), min(v.co.y for v in bm.verts), min(v.co.z for v in bm.verts)))
        hi = Vector((max(v.co.x for v in bm.verts), max(v.co.y for v in bm.verts), max(v.co.z for v in bm.verts)))
        mid = (lo + hi) / 2
        bmesh.ops.translate(bm, verts=bm.verts, vec=-mid)
        me = bpy.data.meshes.new(pname)
        bm.to_mesh(me)
        bm.free()
        for m in used:
            me.materials.append(whole.materials[m])
        if "part" in me.attributes:
            me.attributes.remove(me.attributes["part"])
        ob = bpy.data.objects.new(pname, me)
        ob.location = mid
        ob.parent = root
        col.objects.link(ob)
        made.append(ob)
    bpy.data.meshes.remove(whole)
    # The procedural source: out of the way, kept.
    srcname = name + " (procedural)"
    scol = bpy.data.collections.get(srcname) or bpy.data.collections.new(srcname)
    if scol.name not in sc.collection.children:
        sc.collection.children.link(scol)
    for c in list(src.users_collection):
        c.objects.unlink(src)
    scol.objects.link(src)
    lc = bpy.context.view_layer.layer_collection.children.get(srcname)
    if lc:
        lc.exclude = True
    src.hide_render = True
    return root, made


if __name__ == "__main__":
    bpy.ops.wm.read_homefile(use_empty=True)
    gun = build()
    cam = stage()
    os.makedirs(HERE, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, "gun2.blend"))
    render_views(cam)
    root, made = split_parts(gun)   # (after the renders: they use the procedural object)
    print("split into", len(made), "objects:", ", ".join(o.name for o in made))
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, "gun2.blend"))
