"""The red vegetation of the Crimson Valley scene: part "vegetation".

  tools/cv part vegetation --with sky,clouds,terrain,rocks,water,lighting --render renders/vegetation/a.png

Plants from the prototype library (parts/plants.blend, part_plants.py) instanced where the picture has
red plant cover. The places come from the geometry itself: every camera-facing vertex of the terrain
and the rocks carries the picture's plant cover (the veg attribute) and stands for one picture pixel,
so vertices are drawn at random with a chance that grows with the cover and shrinks close to the camera
(where a pixel is only centimetres wide). Near the camera they become ferns and shrubs at true size;
farther away low carpets, scaled up with distance so the cover stays closed where a plant would be
smaller than a pixel. Moss tufts go where the picture has yellow-green moss.
One object of points per kind (CV_Veg_<kind>), each with a geometry-nodes modifier that instances the
kind's variants at random, turned at random, at the point's scale."""
import os

import bpy
import numpy as np

import common

KINDS = {"fern": "CV_Plants_Fern", "shrub": "CV_Plants_Shrub", "carpet": "CV_Plants_Carpet",
         "bush": "CV_Plants_Bush", "moss": "CV_Plants_Moss"}
FOOT = {"fern": 0.9, "shrub": 0.7, "carpet": 0.7, "bush": 2.2, "moss": 0.35}     # metres a plant covers


def gather():
    """Candidate points: (position, cover, moss, distance) of the camera-facing vertices."""
    out = []
    names = [f for f in sorted(os.listdir(common.MESHES)) if f.endswith(".npz") and f != "water.npz"]
    for f in names:
        m = np.load(os.path.join(common.MESHES, f))
        sel = (m["front"] > 0.5) & ((m["veg"] > 0.2) | (m["moss"] > 0.3))
        uv = m["ref_uv"][sel]
        inside = (uv[:, 0] > -0.03) & (uv[:, 0] < 1.03) & (uv[:, 1] > -0.05) & (uv[:, 1] < 1.03)
        out.append(np.concatenate([m["verts"][sel][inside], m["veg"][sel][inside, None], m["moss"][sel][inside, None],
                                   m["dist"][sel][inside, None]], 1))
    return np.concatenate(out)


def instancer(ob, collection):
    ng = bpy.data.node_groups.new("CV_Scatter_" + collection.name, "GeometryNodeTree")
    ng.interface.new_socket(name="Geometry", in_out="INPUT", socket_type="NodeSocketGeometry")
    ng.interface.new_socket(name="Geometry", in_out="OUTPUT", socket_type="NodeSocketGeometry")
    N, L = ng.nodes, ng.links
    gi, go = N.new("NodeGroupInput"), N.new("NodeGroupOutput")
    ci = N.new("GeometryNodeCollectionInfo")
    ci.inputs["Collection"].default_value = collection
    ci.inputs["Separate Children"].default_value = True
    ci.inputs["Reset Children"].default_value = True
    iop = N.new("GeometryNodeInstanceOnPoints")
    iop.inputs["Pick Instance"].default_value = True
    ri = N.new("FunctionNodeRandomValue")
    ri.data_type = "INT"
    ri.inputs["Min"].default_value = 0
    ri.inputs["Max"].default_value = max(len(collection.objects) - 1, 0)
    rz = N.new("FunctionNodeRandomValue")
    rz.data_type = "FLOAT"
    rz.inputs["Min"].default_value = 0.0
    rz.inputs["Max"].default_value = 6.2832
    rz.inputs["Seed"].default_value = 3
    rot = N.new("ShaderNodeCombineXYZ")
    def val(node):                       # the node's one live "Value" output (it has one per data type)
        return next(o for o in node.outputs if o.enabled)
    L.new(val(rz), rot.inputs["Z"])
    sc = N.new("GeometryNodeInputNamedAttribute")
    sc.data_type = "FLOAT"
    sc.inputs["Name"].default_value = "s"
    L.new(gi.outputs[0], iop.inputs["Points"])
    L.new(ci.outputs[0], iop.inputs["Instance"])
    L.new(val(ri), iop.inputs["Instance Index"])
    L.new(rot.outputs[0], iop.inputs["Rotation"])
    L.new(val(sc), iop.inputs["Scale"])
    L.new(iop.outputs[0], go.inputs[0])
    mod = ob.modifiers.new("Scatter", "NODES")
    mod.node_group = ng


def build(col):
    cm = common.cam_model()
    rng = np.random.default_rng(11)
    # the prototypes, out of sight
    protos = bpy.data.collections.new("CV_Veg_Prototypes")
    col.children.link(protos)
    with bpy.data.libraries.load(common.part_path("plants"), link=False) as (src, dst):
        dst.collections = [c for c in src.collections if c in KINDS.values()]
    kinds = {}
    for c in dst.collections:
        protos.children.link(c)
        c.hide_render = False
        c.hide_viewport = False
        kinds[[k for k, v in KINDS.items() if v == c.name][0]] = c
    protos.hide_render = True
    protos.hide_viewport = True

    P = gather()
    pos, veg, moss, dist = P[:, :3], P[:, 3], P[:, 4], P[:, 5]
    px = dist / cm.f                                    # metres one pixel spans there
    r = rng.random(len(P))
    picks = {}
    # moss
    picks["moss"] = (moss > 0.3) & (r < np.clip((px / 0.25) ** 2, 0, 1) * moss)
    red = veg > 0.2
    kind_r = rng.random(len(P))
    near, mid = dist < 45, (dist >= 45) & (dist < 150)
    is_fern = red & near & (kind_r < 0.14)
    is_shrub = red & ((near & (kind_r >= 0.14) & (kind_r < 0.62)) | (mid & (kind_r < 0.25)))
    is_bush = red & mid & (kind_r > 0.985) & (dist > 55)
    is_carpet = red & ~is_fern & ~is_shrub & ~is_bush
    for k, sel in (("fern", is_fern), ("shrub", is_shrub), ("bush", is_bush), ("carpet", is_carpet)):
        chance = np.clip((px / (0.42 * FOOT[k])) ** 2, 0, 1) * np.clip(veg * 2.5, 0, 1)
        picks[k] = sel & (rng.random(len(P)) < chance)
    for k, sel in picks.items():
        if k not in kinds or not sel.any():
            continue
        p = pos[sel]
        s = np.maximum(1.0, 2.4 * px[sel] / FOOT[k]) * rng.uniform(0.75, 1.3, int(sel.sum()))
        if k == "bush":
            s = rng.uniform(0.8, 1.25, int(sel.sum()))
        ob = common.mesh_object("CV_Veg_" + k, p, [], col, smooth=False, attributes={"s": s})
        instancer(ob, kinds[k])
        ob["cv_light"] = "near" if k in ("fern",) else "valley"
        print(f"  CV_Veg_{k}: {len(p)} plants")
