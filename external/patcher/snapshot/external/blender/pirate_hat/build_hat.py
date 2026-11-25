"""The pirate's tricorne, made entirely with geometry nodes (one node tree,
"PirateHat", on the object "PirateHat" - an empty mesh; everything comes
from the nodes).

Reference: the pirate sprite (art/pirate/pirate_idle_s.png / _e.png): a dark
red-brown hat - a rounded crown, the brim turned up into four walls that
meet in four points at the corners, a gold trim
with little gold spikes along the brim's edge, and a skull and crossbones on
the front wall.

How the nodes build it:
  Brim   a Grid in (angle, across) space bent into a surface of revolution:
         out from the crown (a ledge), then up into four walls (front, back,
         left, right) that lean out a little; the outline is drawn out to four
         corner points, which flick up; the front and back walls rise to a
         peak in the middle (triangles), the back one a little higher. Extruded for thickness; the hat is a bit wider
         than deep.
  Crown  a UV sphere's top half, squashed and raised.
  Trim   the brim's outer edge as a curve (same formula, across ~1) swept
         with a small circle; gold balls on the points and gold hooks hanging
         from the front two.
  Slime  liquid-gold goo along the top edges: the edge curve swept with a lumpy
         (noise) radius, and drips hanging from it - tapering stems and bulbs
         instanced on random points, random lengths - all meshed together
         through a filleted distance field so they flow into each other.
  Skull  spheres, a cube and cylinders on the front wall (skull, jaw, eyes,
         nose, two crossed bones).
The shape's numbers are the constants below (re-run to rebuild).

  blender -b --python external/blender/pirate_hat/build_hat.py      (or run in Blender)
Saves external/blender/pirate_hat/pirate_hat.blend and preview renders.
"""
import math
import os

import bpy

HERE = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else \
    "/home/kilon/MEGA/Dimitris/godot/space-atrapos/external/blender/pirate_hat"

# Shape (metres; the pirate is 0.96 m tall, its head about 0.14 m).
R0 = 0.095          # the crown's radius, where the brim starts
R_MID = 0.15        # the walls' middle, from the centre
RC = 0.218          # ... the points
POINTED = 1.6       # how sharply the outline draws out to a point
H_FRONT = 0.085     # wall height: the front wall (at its corners' end)
H_BACK = 0.1        # ... the back wall (rises over the crown, seen from the front)
POINT_RISE = 0.03   # the corners flick up this much higher
PEAK = 0.085        # the front and back walls rise this much to a peak in the middle (triangles)
THICK = 0.008
SKULL = 0.034       # the skull's width (m, before the emblem's 1.35 scale)
SKULL_VOXEL = 0.018 # its SDF resolution (in skull widths): smaller = finer
WIDEN = (1.14, 0.94, 1.0)   # the whole hat: wider than deep
FLARE = 0.045       # how far the walls lean out at the top
POINTS_AT = (45.0, 135.0, 225.0, 315.0)   # degrees: the four corners (front = -Y): front, back, left and right walls
DRIPS = 64          # places along the edge a drip may hang from (about 40% do)
DRIP_R = 0.0038     # m, a drip's radius where it leaves the edge
SLIME_BAND = 0.006  # m, the goo along the edge (radius, plus up to as much again, lumpy)
SLIME_VOXEL = 0.0016  # m, the slime's distance-field resolution
SLIME = (0.95, 0.6, 0.1)   # the slime's colour: liquid gold

LEATHER = (0.2, 0.026, 0.01)
GOLD = (0.95, 0.62, 0.18)
BONE = (0.85, 0.78, 0.62)


# --- node helpers --------------------------------------------------------------------------

class G:
    def __init__(self, tree):
        self.t = tree
        self.x = 0

    def node(self, kind, **props):
        n = self.t.nodes.new(kind)
        for k, v in props.items():
            setattr(n, k, v)
        n.location = (self.x, 0)
        self.x += 40
        return n

    def link(self, a, b):
        self.t.links.new(a, b)

    def math(self, op, a, b=None, c=None):
        n = self.node("ShaderNodeMath", operation=op)
        for i, v in enumerate((a, b, c)):
            if v is None:
                continue
            if isinstance(v, (int, float)):
                n.inputs[i].default_value = v
            else:
                self.link(v, n.inputs[i])
        return n.outputs[0]

    def vmath(self, op, a, b=None):
        n = self.node("ShaderNodeVectorMath", operation=op)
        for i, v in enumerate((a, b)):
            if v is None:
                continue
            if isinstance(v, (tuple, list)):
                n.inputs[i].default_value = v
            elif isinstance(v, (int, float)):
                n.inputs[3].default_value = v   # (scale)
            else:
                self.link(v, n.inputs[i])
        return n.outputs[0]

    def combine(self, x, y, z):
        n = self.node("ShaderNodeCombineXYZ")
        for i, v in enumerate((x, y, z)):
            if isinstance(v, (int, float)):
                n.inputs[i].default_value = v
            else:
                self.link(v, n.inputs[i])
        return n.outputs[0]

    def separate(self, v):
        n = self.node("ShaderNodeSeparateXYZ")
        self.link(v, n.inputs[0])
        return n.outputs[0], n.outputs[1], n.outputs[2]

    def material(self, geo, mat):
        n = self.node("GeometryNodeSetMaterial")
        self.link(geo, n.inputs["Geometry"])
        n.inputs["Material"].default_value = mat
        return n.outputs[0]

    def transform(self, geo, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
        n = self.node("GeometryNodeTransform")
        self.link(geo, n.inputs["Geometry"])
        n.inputs["Translation"].default_value = loc
        n.inputs["Rotation"].default_value = rot
        n.inputs["Scale"].default_value = scale
        return n.outputs[0]

    def join(self, *geos):
        n = self.node("GeometryNodeJoinGeometry")
        for g in reversed(geos):   # (the multi-input socket stacks them)
            self.link(g, n.inputs[0])
        return n.outputs[0]

    def smooth(self, geo):
        n = self.node("GeometryNodeSetShadeSmooth")
        self.link(geo, n.inputs["Geometry"])
        return n.outputs[0]


def brim_point(g, theta, across):
    """The brim surface at (theta, across 0..1) - node sockets in, a position out."""
    period = 2 * math.pi / len(POINTS_AT)
    th0 = math.radians(POINTS_AT[0])
    local = g.math("SUBTRACT", g.math("FLOORED_MODULO", g.math("SUBTRACT", theta, th0 - period / 2), period), period / 2)
    u = g.math("DIVIDE", g.math("ABSOLUTE", local), period / 2)          # 0 at a point .. 1 mid-wall
    pt = g.math("SUBTRACT", 1.0, u)
    # The outline: the walls' middle R_MID out, drawn out to RC at the points.
    ro = g.math("ADD", R_MID, g.math("MULTIPLY", g.math("POWER", pt, POINTED), RC - R_MID))
    near = g.math("POWER", pt, 3.0)
    # Wall height: the front wall a little lower (the face and skull show), the
    # back wall rising behind the crown; the points flick up higher still.
    sn = g.math("SINE", theta)                                    # -1 front .. 1 back
    x = g.math("MINIMUM", g.math("MAXIMUM", g.math("DIVIDE", g.math("ADD", sn, 0.35), 0.7), 0.0), 1.0)
    t = g.math("MULTIPLY", g.math("MULTIPLY", x, x), g.math("SUBTRACT", 3.0, g.math("MULTIPLY", x, 2.0)))   # (smoothstep)
    h = g.math("ADD", H_FRONT, g.math("MULTIPLY", t, H_BACK - H_FRONT))
    # (the front points flick up; the back one less, keeping the top line level)
    rise = g.math("MULTIPLY", g.math("SUBTRACT", 1.0, g.math("MULTIPLY", g.math("MAXIMUM", sn, 0.0), 0.75)), POINT_RISE)
    h = g.math("ADD", h, g.math("MULTIPLY", near, rise))
    # The front and back walls rise to a peak in the middle - a triangle - (straight
    # edges: linear in x = r cos(theta)); the side walls don't.
    tri = g.math("MAXIMUM", g.math("SUBTRACT", 1.0, g.math("DIVIDE", g.math("ABSOLUTE", g.math("COSINE", theta)), 0.7071)), 0.0)
    h = g.math("ADD", h, g.math("MULTIPLY", tri, PEAK))
    # Profile: out from the crown, then turning up into a wall.
    # (out first - a ledge - then up: the walls stand nearly upright)
    q = g.math("MULTIPLY", g.math("MINIMUM", g.math("DIVIDE", across, 0.62), 1.0), math.pi / 2)
    q2 = g.math("MULTIPLY", g.math("MAXIMUM", g.math("DIVIDE", g.math("SUBTRACT", across, 0.3), 0.7), 0.0), math.pi / 2)
    rad = g.math("ADD", R0, g.math("MULTIPLY", g.math("SUBTRACT", ro, R0), g.math("SINE", q)))
    rad = g.math("ADD", rad, g.math("MULTIPLY", g.math("SINE", q2), FLARE))   # (the walls lean out)
    z = g.math("MULTIPLY", h, g.math("SUBTRACT", 1.0, g.math("COSINE", q2)))
    # The walls lean out a little more at the points, which droop slightly.
    z = g.math("SUBTRACT", z, g.math("MULTIPLY", g.math("MULTIPLY", near, across), 0.012))
    x = g.math("MULTIPLY", rad, g.math("COSINE", theta))
    y = g.math("MULTIPLY", rad, g.math("SINE", theta))
    return g.combine(x, y, z), (rad, z, near)


def build():
    # Materials.
    def mat(name, col, metal=0.0, rough=0.6):
        m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
        m.use_nodes = True
        b = m.node_tree.nodes.get("Principled BSDF")
        b.inputs["Base Color"].default_value = (*col, 1)
        b.inputs["Metallic"].default_value = metal
        b.inputs["Roughness"].default_value = rough
        b.inputs["Specular IOR Level"].default_value = 0.35 if metal == 0.0 else 0.5
        if name == "HatBone":   # (old bone: ivory to yellowed, darker in the crevices)
            nt = m.node_tree
            nz = nt.nodes.new("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 60.0; nz.inputs["Detail"].default_value = 8.0
            ramp = nt.nodes.new("ShaderNodeValToRGB")
            ramp.color_ramp.elements[0].color = (0.45, 0.36, 0.22, 1)
            ramp.color_ramp.elements[1].color = (0.8, 0.74, 0.6, 1)
            nt.links.new(nz.outputs["Fac"], ramp.inputs["Fac"])
            ao = nt.nodes.new("ShaderNodeAmbientOcclusion"); ao.inputs["Distance"].default_value = 0.004
            mul = nt.nodes.new("ShaderNodeMix"); mul.data_type = "RGBA"; mul.blend_type = "MULTIPLY"
            mul.inputs["Factor"].default_value = 0.85
            col = lambda socks, nm: [x for x in socks if x.name == nm and x.type == "RGBA"][0]   # (the Mix node's colour sockets)
            nt.links.new(ramp.outputs["Color"], col(mul.inputs, "A"))
            nt.links.new(ao.outputs["AO"], col(mul.inputs, "B"))   # (AO as a grey: dark in the hollows)
            nt.links.new(col(mul.outputs, "Result"), b.inputs["Base Color"])
            bm = nt.nodes.new("ShaderNodeBump"); bm.inputs["Strength"].default_value = 0.15
            nt.links.new(nz.outputs["Fac"], bm.inputs["Height"]); nt.links.new(bm.outputs["Normal"], b.inputs["Normal"])
        if name == "HatLeather":   # (worn leather: a little bump)
            nt = m.node_tree
            nz = nt.nodes.new("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 90.0; nz.inputs["Detail"].default_value = 6.0
            bm = nt.nodes.new("ShaderNodeBump"); bm.inputs["Strength"].default_value = 0.25
            nt.links.new(nz.outputs["Fac"], bm.inputs["Height"]); nt.links.new(bm.outputs["Normal"], b.inputs["Normal"])
        return m
    m_leather = mat("HatLeather", LEATHER, 0.0, 0.75)
    m_gold = mat("HatGold", GOLD, 1.0, 0.32)
    m_bone = mat("HatBone", BONE, 0.0, 0.5)
    m_dark = mat("HatSocket", (0.03, 0.02, 0.02), 0.0, 0.8)
    m_slime = mat("HatSlime", SLIME, 0.55, 0.12)   # (molten-gold goo: wet, half metallic, a faint glow)
    bs = m_slime.node_tree.nodes.get("Principled BSDF")
    bs.inputs["Transmission Weight"].default_value = 0.1
    bs.inputs["Emission Color"].default_value = (*SLIME, 1)
    bs.inputs["Emission Strength"].default_value = 0.25
    bs.inputs["Coat Weight"].default_value = 0.6
    bs.inputs["Subsurface Weight"].default_value = 0.3

    tree = bpy.data.node_groups.get("PirateHat")
    if tree:
        bpy.data.node_groups.remove(tree)
    tree = bpy.data.node_groups.new("PirateHat", "GeometryNodeTree")
    tree.interface.new_socket("Geometry", in_out="OUTPUT", socket_type="NodeSocketGeometry")
    g = G(tree)
    out = g.node("NodeGroupOutput")

    # --- Brim: a grid in (angle, across) space -------------------------------------------
    grid = g.node("GeometryNodeMeshGrid")
    grid.inputs["Size X"].default_value = 2 * math.pi
    grid.inputs["Size Y"].default_value = 1.0
    grid.inputs["Vertices X"].default_value = 241
    grid.inputs["Vertices Y"].default_value = 14
    pos = g.node("GeometryNodeInputPosition").outputs[0]
    gx, gy, _ = g.separate(pos)
    theta = g.math("ADD", gx, math.pi)
    across = g.math("ADD", gy, 0.5)
    p, _ = brim_point(g, theta, across)
    setp = g.node("GeometryNodeSetPosition")
    g.link(grid.outputs["Mesh"], setp.inputs["Geometry"])
    g.link(p, setp.inputs["Position"])
    weld = g.node("GeometryNodeMergeByDistance")   # (the seam at 0 / 360 deg)
    g.link(setp.outputs[0], weld.inputs["Geometry"])
    weld.inputs["Distance"].default_value = 0.0005
    ext = g.node("GeometryNodeExtrudeMesh")        # thickness
    g.link(weld.outputs[0], ext.inputs["Mesh"])
    ext.inputs["Offset Scale"].default_value = THICK
    ext.inputs["Individual"].default_value = False
    brim = g.material(g.smooth(ext.outputs["Mesh"]), m_leather)

    # --- Crown: a squashed dome with a dent along the top --------------------------------
    sph = g.node("GeometryNodeMeshUVSphere")
    sph.inputs["Segments"].default_value = 64
    sph.inputs["Rings"].default_value = 32
    sph.inputs["Radius"].default_value = 1.0
    pos2 = g.node("GeometryNodeInputPosition").outputs[0]
    sx, sy, sz = g.separate(pos2)
    zc = g.math("MAXIMUM", sz, -0.25)
    dent = g.math("MULTIPLY", g.math("MULTIPLY", g.math("POWER", g.math("MAXIMUM", zc, 0.0), 3.0),
                                     g.math("EXPONENT", g.math("MULTIPLY", g.math("MULTIPLY", sx, sx), -18.0))), 0.03)
    cp = g.combine(g.math("MULTIPLY", sx, R0 * 1.06), g.math("MULTIPLY", sy, R0 * 0.98),
                   g.math("MULTIPLY", g.math("SUBTRACT", zc, dent), 0.165))
    setc = g.node("GeometryNodeSetPosition")
    g.link(sph.outputs["Mesh"], setc.inputs["Geometry"])
    g.link(cp, setc.inputs["Position"])
    crown = g.material(g.smooth(g.transform(setc.outputs[0], loc=(0, 0, 0.035), scale=(1.08, 1.08, 1.0))), m_leather)
    # A band round the crown's foot.
    band = g.node("GeometryNodeMeshCylinder")
    band.inputs["Vertices"].default_value = 64
    band.inputs["Radius"].default_value = R0 * 1.075
    band.inputs["Depth"].default_value = 0.016
    band_g = g.material(g.smooth(g.transform(band.outputs["Mesh"], loc=(0, 0, 0.014), scale=(1.06, 0.98, 1))),
                        bpy.data.materials["HatSocket"])

    # --- Gold trim: the brim's outer edge, swept with a little circle --------------------
    circ = g.node("GeometryNodeCurvePrimitiveCircle")
    circ.inputs["Resolution"].default_value = 240
    circ.inputs["Radius"].default_value = 1.0
    pos3 = g.node("GeometryNodeInputPosition").outputs[0]
    cx, cy, _ = g.separate(pos3)
    th3 = g.math("ARCTAN2", cy, cx)
    p3, _ = brim_point(g, th3, 0.985)
    sett = g.node("GeometryNodeSetPosition")
    g.link(circ.outputs["Curve"], sett.inputs["Geometry"])
    g.link(p3, sett.inputs["Position"])
    prof = g.node("GeometryNodeCurvePrimitiveCircle")
    prof.inputs["Resolution"].default_value = 8
    prof.inputs["Radius"].default_value = 0.0065
    sweep = g.node("GeometryNodeCurveToMesh")
    g.link(sett.outputs[0], sweep.inputs["Curve"])
    g.link(prof.outputs["Curve"], sweep.inputs["Profile Curve"])
    trim = g.material(g.smooth(sweep.outputs["Mesh"]), m_gold)

    # --- Slime: a goopy band along the top edges and drips hanging from it -------------
    # (all meshed together through a distance field, so the drips flow out of
    # the band and their bulbs swell smoothly)
    def sock(socks, name, typ):
        return [x for x in socks if x.name == name and x.type == typ][0]

    def rand(lo, hi, seed):
        r = g.node("FunctionNodeRandomValue", data_type="FLOAT")
        sock(r.inputs, "Min", "VALUE").default_value = lo
        sock(r.inputs, "Max", "VALUE").default_value = hi
        sock(r.inputs, "Seed", "INT").default_value = seed
        return sock(r.outputs, "Value", "VALUE")

    # The band: the edge curve just outside the trim, thick and lumpy (a noisy radius).
    edge = g.node("GeometryNodeSetPosition")
    g.link(sett.outputs[0], edge.inputs["Geometry"])
    pos5 = g.node("GeometryNodeInputPosition").outputs[0]
    g.link(g.vmath("ADD", pos5, (0, 0, 0.003)), edge.inputs["Position"])
    noise = g.node("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 22.0
    noise.inputs["Detail"].default_value = 2.0
    rad = g.node("GeometryNodeSetCurveRadius")
    g.link(edge.outputs[0], rad.inputs["Curve"])
    g.link(g.math("ADD", SLIME_BAND * 0.5, g.math("MULTIPLY", noise.outputs["Fac"], SLIME_BAND)), rad.inputs["Radius"])
    bprof = g.node("GeometryNodeCurvePrimitiveCircle")
    bprof.inputs["Resolution"].default_value = 10
    bprof.inputs["Radius"].default_value = 1.0
    band_s = g.node("GeometryNodeCurveToMesh")
    g.link(rad.outputs[0], band_s.inputs["Curve"])
    g.link(bprof.outputs["Curve"], band_s.inputs["Profile Curve"])
    g.link(g.node("GeometryNodeInputRadius").outputs[0], band_s.inputs["Scale"])
    band_s.inputs["Fill Caps"].default_value = True
    # The drips: points along the edge (some skipped), each a tapering stem down
    # from the band and a bulb at its end, random lengths.
    rs = g.node("GeometryNodeResampleCurve")
    g.link(edge.outputs[0], rs.inputs["Curve"])
    rs.inputs["Count"].default_value = DRIPS
    c2p = g.node("GeometryNodeCurveToPoints")
    c2p.mode = "EVALUATED"
    g.link(rs.outputs[0], c2p.inputs["Curve"])
    keep = g.node("FunctionNodeRandomValue", data_type="BOOLEAN")
    sock(keep.inputs, "Probability", "VALUE").default_value = 0.42
    sock(keep.inputs, "Seed", "INT").default_value = 7
    drop = g.node("GeometryNodeDeleteGeometry", domain="POINT")
    g.link(c2p.outputs["Points"], drop.inputs["Geometry"])
    g.link(sock(keep.outputs, "Value", "BOOLEAN"), drop.inputs["Selection"])
    pts = drop.outputs[0]
    # Each drip remembers where it hangs (its angle), how far down the wall it
    # runs (a share of the wall) and how thick it is.
    pp = g.node("GeometryNodeInputPosition").outputs[0]
    ppx, ppy, _ = g.separate(pp)
    def store(geo, name, value):
        st = g.node("GeometryNodeStoreNamedAttribute", data_type="FLOAT", domain="POINT")
        g.link(geo, st.inputs["Geometry"])
        st.inputs["Name"].default_value = name
        g.link(value, sock(st.inputs, "Value", "VALUE"))
        return st.outputs[0]
    pts = store(pts, "drip_th", g.math("ARCTAN2", ppy, ppx))
    pts = store(pts, "drip_k", rand(0.07, 0.34, 3))   # (no lower than across 0.64: the upright wall, not the brim curling in)
    pts = store(pts, "drip_w", rand(0.75, 1.35, 5))
    def attr(name):
        a = g.node("GeometryNodeInputNamedAttribute", data_type="FLOAT")
        a.inputs["Name"].default_value = name
        return sock(a.outputs, "Attribute", "VALUE")
    over = []   # raycast nodes: their target (the skull and bones) is linked once it's built

    def over_skull(pos, clear):
        """pos moved out over the skull and bones where it would be inside them:
        a ray from well outside, straight in (toward the hat's axis), and the
        point set `clear` out from where it meets them."""
        th = attr("drip_th")
        outd = g.combine(g.math("COSINE", th), g.math("SINE", th), 0.0)
        rc = g.node("GeometryNodeRaycast")
        g.link(g.vmath("ADD", pos, g.vmath("SCALE", outd, 0.06)), rc.inputs["Source Position"])
        g.link(g.vmath("SCALE", outd, -1.0), rc.inputs["Ray Direction"])
        rc.inputs["Ray Length"].default_value = 0.06
        over.append(rc)
        lifted = g.vmath("ADD", rc.outputs["Hit Position"], g.vmath("SCALE", outd, clear))
        # (only where the skull is further out than the point - otherwise as it was)
        dot = g.node("ShaderNodeVectorMath", operation="DOT_PRODUCT")
        g.link(g.vmath("SUBTRACT", lifted, pos), dot.inputs[0])
        g.link(outd, dot.inputs[1])
        further = g.math("GREATER_THAN", dot.outputs["Value"], 0.0)
        hit = g.math("MULTIPLY", rc.outputs["Is Hit"], further)
        sw = g.node("GeometryNodeSwitch", input_type="VECTOR")
        g.link(hit, sw.inputs["Switch"])
        g.link(pos, sw.inputs["False"])
        g.link(lifted, sw.inputs["True"])
        return sw.outputs[0]

    def on_wall(across):
        """A point on the brim's outer face at (drip_th, across), just outside it."""
        th = attr("drip_th")
        p, _ = brim_point(g, th, across)
        # (the wall's outer face is THICK out from the surface formula; a drip sits
        # on it, its whole thickness outside)
        off = THICK + DRIP_R * 1.35 + 0.0012
        out = g.combine(g.math("MULTIPLY", g.math("COSINE", th), off), g.math("MULTIPLY", g.math("SINE", th), off), 0.0)
        return g.vmath("ADD", p, out)
    # The stems: a line per drip, bent down along the wall's face, tapering.
    line = g.node("GeometryNodeCurvePrimitiveLine")
    i1 = g.node("GeometryNodeInstanceOnPoints")
    g.link(pts, i1.inputs["Points"])
    g.link(line.outputs[0], i1.inputs["Instance"])
    lines = g.node("GeometryNodeRealizeInstances")
    g.link(i1.outputs[0], lines.inputs[0])
    rs2 = g.node("GeometryNodeResampleCurve")
    g.link(lines.outputs[0], rs2.inputs["Curve"])
    rs2.inputs["Count"].default_value = 28   # (enough to bend smoothly over the skull)
    fac = g.node("GeometryNodeSplineParameter").outputs["Factor"]
    down = g.node("GeometryNodeSetPosition")
    g.link(rs2.outputs[0], down.inputs["Geometry"])
    g.link(over_skull(on_wall(g.math("SUBTRACT", 0.985, g.math("MULTIPLY", fac, attr("drip_k")))), DRIP_R * 0.8),
           down.inputs["Position"])
    rad2 = g.node("GeometryNodeSetCurveRadius")
    g.link(down.outputs[0], rad2.inputs["Curve"])
    g.link(g.math("MULTIPLY", g.math("MULTIPLY", DRIP_R, g.math("SUBTRACT", 1.0, g.math("MULTIPLY", fac, 0.5))), attr("drip_w")),
           rad2.inputs["Radius"])
    sprof = g.node("GeometryNodeCurvePrimitiveCircle")
    sprof.inputs["Resolution"].default_value = 8
    sprof.inputs["Radius"].default_value = 1.0
    stems = g.node("GeometryNodeCurveToMesh")
    g.link(rad2.outputs[0], stems.inputs["Curve"])
    g.link(sprof.outputs["Curve"], stems.inputs["Profile Curve"])
    g.link(g.node("GeometryNodeInputRadius").outputs[0], stems.inputs["Scale"])
    stems.inputs["Fill Caps"].default_value = True
    # The bulbs, where each drip ends.
    ends = g.node("GeometryNodeSetPosition")
    g.link(pts, ends.inputs["Geometry"])
    g.link(over_skull(on_wall(g.math("SUBTRACT", 0.985, attr("drip_k"))), DRIP_R * 1.1), ends.inputs["Position"])
    bulb = g.node("GeometryNodeMeshUVSphere")
    bulb.inputs["Segments"].default_value = 16
    bulb.inputs["Rings"].default_value = 10
    bulb.inputs["Radius"].default_value = 1.0
    i2 = g.node("GeometryNodeInstanceOnPoints")
    g.link(ends.outputs[0], i2.inputs["Points"])
    g.link(g.transform(bulb.outputs["Mesh"], loc=(0, 0, -0.3), scale=(1.0, 1.0, 1.3)), i2.inputs["Instance"])
    br = g.math("MULTIPLY", rand(0.75, 1.0, 9), g.math("MULTIPLY", attr("drip_w"), DRIP_R * 1.15))
    g.link(g.combine(br, br, br), i2.inputs["Scale"])
    goo = g.node("GeometryNodeRealizeInstances")
    g.link(g.join(band_s.outputs["Mesh"], stems.outputs["Mesh"], i2.outputs[0]), goo.inputs[0])
    sdf_s = g.node("GeometryNodeMeshToSDFGrid")
    g.link(goo.outputs[0], sdf_s.inputs["Mesh"])
    sdf_s.inputs["Voxel Size"].default_value = SLIME_VOXEL
    sdf_s.inputs["Band Width"].default_value = 4
    fil_s = g.node("GeometryNodeSDFGridFillet")
    g.link(sdf_s.outputs[0], fil_s.inputs["Grid"])
    fil_s.inputs["Iterations"].default_value = 4
    mesh_s = g.node("GeometryNodeGridToMesh")
    g.link(fil_s.outputs[0], mesh_s.inputs["Grid"])
    mesh_s.inputs["Threshold"].default_value = 0.0
    slime = g.material(g.smooth(mesh_s.outputs["Mesh"]), m_slime)

    # Gold tips on the three points (small spheres).
    tips = []
    for a in POINTS_AT:
        th = math.radians(a)
        t = g.node("GeometryNodeMeshUVSphere")
        t.inputs["Radius"].default_value = 0.011
        t.inputs["Segments"].default_value = 16
        t.inputs["Rings"].default_value = 8
        rr, zz = _outline(th, 1.0)
        tips.append(g.transform(t.outputs["Mesh"], loc=(rr * math.cos(th), rr * math.sin(th), zz)))
        if math.sin(th) < 0:   # the front points: a gold hook hanging from each (the sprite's drips)
            hk = g.node("GeometryNodeMeshCone")
            hk.inputs["Vertices"].default_value = 10
            hk.inputs["Radius Bottom"].default_value = 0.0075
            hk.inputs["Depth"].default_value = 0.075
            # (cone tip down, leaning out from the hat)
            tips.append(g.transform(hk.outputs["Mesh"], loc=(rr * math.cos(th) * 1.075, rr * math.sin(th) * 1.075, zz - 0.022),
                                    rot=(0, math.pi + 0.35 * math.copysign(1, math.cos(th)), 0)))
    tips_g = g.material(g.smooth(g.join(*tips)), m_gold)

    # --- Skull and crossbones on the front wall ------------------------------------------
    th = -math.pi / 2
    rr, zz = _outline(th, 0.88)
    face = (0.0, -rr - 0.006, zz)
    tilt = math.radians(-8)   # (the wall leans out)
    # The skull: sculpted from signed-distance fields (see skull_unit), one unit
    # wide, scaled onto the wall; the crossbones behind it.
    sk = g.transform(skull_unit(g, m_bone, m_dark), loc=(face[0], face[1] - 0.002, face[2] + 0.003),
                     scale=(SKULL, SKULL * 0.8, SKULL))
    parts_bone = []
    for s in (-1, 1):
        bone = g.node("GeometryNodeMeshCylinder")
        bone.inputs["Radius"].default_value = 0.0028
        bone.inputs["Depth"].default_value = 0.062
        parts_bone.append(g.transform(bone.outputs["Mesh"], loc=(face[0], face[1] + 0.006, face[2] - 0.004),
                                      rot=(0, math.radians(90 + s * 38), 0)))
        for e in (-1, 1):
            ang = math.radians(s * 38)
            for side in (-1, 1):   # (each bone end: two knobs, like a real joint)
                k = g.node("GeometryNodeMeshUVSphere")
                k.inputs["Radius"].default_value = 0.0042
                dx = e * 0.031 * math.cos(ang) + side * 0.0032 * math.sin(ang)
                dz = -e * 0.031 * math.sin(ang) + side * 0.0032 * math.cos(ang)
                parts_bone.append(g.transform(k.outputs["Mesh"], loc=(face[0] + dx, face[1] + 0.006, face[2] - 0.004 + dz)))
    skull = g.join(sk, g.material(g.smooth(g.join(*parts_bone)), m_bone))
    sockets = None
    emblem = skull
    # Lean the emblem with the wall: rotate about its own centre.
    emblem = g.transform(g.transform(emblem, loc=(-face[0], -face[1], -face[2])), loc=(face[0], face[1] - 0.004, face[2]), rot=(tilt, 0, 0),
                         scale=(1.35, 0.9, 1.35))

    for rc in over:   # (the drips run over the skull and bones, not through them)
        g.link(emblem, rc.inputs["Target Geometry"])
    hat = g.join(brim, crown, band_g, trim, slime, tips_g, emblem)
    hat = g.transform(hat, scale=WIDEN)   # (wider side to side than front to back)
    g.link(hat, out.inputs[0])

    # The object.
    ob = bpy.data.objects.get("PirateHat")
    if ob is None:
        me = bpy.data.meshes.new("PirateHat")
        ob = bpy.data.objects.new("PirateHat", me)
        bpy.context.scene.collection.objects.link(ob)
    for md in list(ob.modifiers):
        ob.modifiers.remove(md)
    md = ob.modifiers.new("PirateHat", "NODES")
    md.node_group = tree
    for m in (m_leather, m_gold, m_bone, m_dark):
        if m.name not in [s.material.name for s in ob.material_slots if s.material]:
            ob.data.materials.append(m)
    return ob


def skull_unit(g, m_bone, m_dark):
    """A human skull one unit wide, facing -Y, centred on the origin: bone
    shapes (cranium, brow, cheekbones, upper jaw, lower jaw, chin) as signed
    distance fields joined smoothly, the eye sockets, nose cavity and the gap
    between the jaws carved out, then meshed; teeth along both jaws, and
    shadowy dark hollows deep in the sockets and the nose."""
    def ellipsoid(c, r, rot=(0, 0, 0)):
        sp = g.node("GeometryNodeMeshUVSphere")
        sp.inputs["Segments"].default_value = 32
        sp.inputs["Rings"].default_value = 16
        sp.inputs["Radius"].default_value = 1.0
        return g.transform(sp.outputs["Mesh"], loc=c, rot=rot, scale=r)

    def box(c, size, rot=(0, 0, 0)):
        cb = g.node("GeometryNodeMeshCube")
        cb.inputs["Size"].default_value = size
        return g.transform(cb.outputs["Mesh"], loc=c, rot=rot)

    def sdf(mesh):
        n = g.node("GeometryNodeMeshToSDFGrid")
        g.link(mesh, n.inputs["Mesh"])
        n.inputs["Voxel Size"].default_value = SKULL_VOXEL
        n.inputs["Band Width"].default_value = 4
        return n.outputs[0]

    def boolean(op, a, bs):
        n = g.node("GeometryNodeSDFGridBoolean", operation=op)
        if a is not None:
            g.link(a, n.inputs["Grid 1"])
        for b in reversed(bs):
            g.link(b, n.inputs["Grid 2"])
        return n.outputs[0]

    bone = [
        ellipsoid((0, 0.08, 0.2), (0.5, 0.56, 0.5)),            # the cranium
        ellipsoid((0, -0.3, 0.1), (0.4, 0.2, 0.17)),            # the brow ridge
        ellipsoid((0, -0.27, -0.12), (0.31, 0.26, 0.24)),       # the face / upper jaw
        ellipsoid((0.3, -0.24, -0.06), (0.13, 0.2, 0.1), (0, 0.3, 0)),    # cheekbones
        ellipsoid((-0.3, -0.24, -0.06), (0.13, 0.2, 0.1), (0, -0.3, 0)),
        ellipsoid((0.38, -0.02, -0.06), (0.06, 0.24, 0.07)),    # the arches back to the ears
        ellipsoid((-0.38, -0.02, -0.06), (0.06, 0.24, 0.07)),
        ellipsoid((0, -0.26, -0.43), (0.25, 0.2, 0.1)),         # the lower jaw
        ellipsoid((0, -0.36, -0.47), (0.12, 0.09, 0.08)),       # the chin
        ellipsoid((0.25, -0.1, -0.33), (0.07, 0.16, 0.16)),     # the jaw's corners
        ellipsoid((-0.25, -0.1, -0.33), (0.07, 0.16, 0.16)),
    ]
    solid = boolean("UNION", None, [sdf(m) for m in bone])
    fil = g.node("GeometryNodeSDFGridFillet")   # (rounds the joins off, like bone)
    g.link(solid, fil.inputs["Grid"])
    fil.inputs["Iterations"].default_value = 3
    holes = [
        ellipsoid((0.17, -0.44, 0.0), (0.13, 0.26, 0.115), (0, -0.2, 0)),    # eye sockets: rounded squares,
        ellipsoid((-0.17, -0.44, 0.0), (0.13, 0.26, 0.115), (0, 0.2, 0)),    # tilted a little outward
        box((0.17, -0.45, 0.0), (0.2, 0.4, 0.17), (0, -0.2, 0)),
        box((-0.17, -0.45, 0.0), (0.2, 0.4, 0.17), (0, 0.2, 0)),
        ellipsoid((0.46, -0.12, 0.08), (0.06, 0.2, 0.14)),      # the temples
        ellipsoid((-0.46, -0.12, 0.08), (0.06, 0.2, 0.14)),
        ellipsoid((0.035, -0.46, -0.17), (0.045, 0.2, 0.095), (0, -0.35, 0)),   # the nose: two lobes leaning
        ellipsoid((-0.035, -0.46, -0.17), (0.045, 0.2, 0.095), (0, 0.35, 0)),   # together - an upside-down heart
        box((0, -0.42, -0.355), (0.38, 0.3, 0.035)),            # the gap between the jaws
        ellipsoid((0.33, -0.1, -0.2), (0.06, 0.14, 0.06)),      # the hollows under the cheekbones
        ellipsoid((-0.33, -0.1, -0.2), (0.06, 0.14, 0.06)),
    ]
    carved = boolean("DIFFERENCE", fil.outputs[0], [sdf(m) for m in holes])
    mesh = g.node("GeometryNodeGridToMesh")
    g.link(carved, mesh.inputs["Grid"])
    mesh.inputs["Threshold"].default_value = 0.0   # (the surface of a distance field: 0, not the default 0.1)
    head = g.material(g.smooth(mesh.outputs["Mesh"]), m_bone)
    # Teeth: rounded little blocks along an arc, upper and lower rows.
    teeth = []
    for row, z in ((0, -0.315), (1, -0.393)):
        for k in range(8):
            a = (k - 3.5) / 3.5 * 0.85
            front = 1.0 - abs(k - 3.5) / 3.5                                  # (the front teeth longer)
            t = ellipsoid((0.25 * math.sin(a), -0.27 - 0.17 * math.cos(a), z + (0.01 if row == 0 else -0.01)),
                          (0.026, 0.028, (0.05 if row == 0 else 0.045) + 0.012 * front))
            teeth.append(t)
    teeth_g = g.material(g.smooth(g.join(*teeth)), m_bone)
    # Dark hollows deep inside the sockets and the nose (they read as shadow).
    dark = [ellipsoid((0.17, -0.27, 0.0), (0.12, 0.07, 0.1)), ellipsoid((-0.17, -0.27, 0.0), (0.12, 0.07, 0.1)),
            ellipsoid((0, -0.4, -0.16), (0.06, 0.06, 0.08)), box((0, -0.3, -0.355), (0.32, 0.1, 0.06))]
    dark_g = g.material(g.join(*dark), m_dark)
    return g.join(head, teeth_g, dark_g)


def _outline(th, across):
    """brim_point's radius and height in plain Python (to place things on the brim)."""
    period = 2 * math.pi / len(POINTS_AT)
    th0 = math.radians(POINTS_AT[0])
    local = ((th - (th0 - period / 2)) % period) - period / 2
    pt = 1.0 - abs(local) / (period / 2)
    ro = R_MID + (pt ** POINTED) * (RC - R_MID)
    near = pt ** 3
    sn = math.sin(th)
    x = min(max((sn + 0.35) / 0.7, 0.0), 1.0)
    h = H_FRONT + x * x * (3 - 2 * x) * (H_BACK - H_FRONT) + near * POINT_RISE * (1 - 0.75 * max(sn, 0.0))
    h += max(0.0, 1 - abs(math.cos(th)) / 0.7071) * PEAK
    q = min(across / 0.62, 1.0) * math.pi / 2
    q2 = max((across - 0.3) / 0.7, 0.0) * math.pi / 2
    rad = R0 + (ro - R0) * math.sin(q) + math.sin(q2) * FLARE
    z = h * (1 - math.cos(q2)) - near * across * 0.012
    return rad, z


def stage():
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x = sc.render.resolution_y = 800
    sc.render.film_transparent = True
    sc.view_settings.view_transform = "Standard"
    for name, loc, energy, size in (("Key", (1.2, -1.4, 1.6), 120, 1.0), ("Rim", (-1.2, 1.4, 1.2), 140, 1.0), ("Fill", (-1.6, -1.0, 0.4), 50, 2.0)):
        l = bpy.data.objects.get(name)
        if l is None:
            l = bpy.data.objects.new(name, bpy.data.lights.new(name, "AREA"))
            sc.collection.objects.link(l)
        l.data.energy = energy
        l.data.size = size
        l.location = loc
        l.rotation_euler = (0, 0, 0)
        c = l.constraints.get("Aim") or l.constraints.new("TRACK_TO")
        c.name = "Aim"
        c.target = bpy.data.objects["PirateHat"]
    w = sc.world or bpy.data.worlds.new("World")
    sc.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.2, 0.19, 0.22, 1)
    cam = bpy.data.objects.get("Camera")
    if cam is None:
        cam = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
        sc.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 0.7
    sc.camera = cam
    return cam


def render_views(cam, prefix="preview"):
    sc = bpy.context.scene
    out = []
    for name, az, el in (("front", -90, 30), ("q45", -45, 30), ("side", 0, 30), ("back", 90, 30)):
        a, e = math.radians(az), math.radians(el)
        tgt = (0, 0, 0.05)
        d = 3.0
        cam.location = (tgt[0] + d * math.cos(e) * math.cos(a), tgt[1] + d * math.cos(e) * math.sin(a), tgt[2] + d * math.sin(e))
        cam.rotation_euler = (math.pi / 2 - e, 0, a + math.pi / 2)
        sc.render.filepath = os.path.join(HERE, "%s_%s.png" % (prefix, name))
        bpy.ops.render.render(write_still=True)
        out.append(sc.render.filepath)
    return out


def render_skull(cam):
    """A close-up of the skull, straight on (preview_skull.png)."""
    sc = bpy.context.scene
    rr, zz = _outline(-math.pi / 2, 0.88)
    cam.location = (0, -3.0, zz + 0.003)
    cam.rotation_euler = (math.pi / 2, 0, 0)
    old = cam.data.ortho_scale
    cam.data.ortho_scale = 0.09
    sc.render.filepath = os.path.join(HERE, "preview_skull.png")
    bpy.ops.render.render(write_still=True)
    cam.data.ortho_scale = old


if __name__ == "__main__":
    bpy.ops.wm.read_homefile(use_empty=True)   # (a new, empty file)
    ob = build()
    cam = stage()
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, "pirate_hat.blend"))
    render_views(cam)
    render_skull(cam)
