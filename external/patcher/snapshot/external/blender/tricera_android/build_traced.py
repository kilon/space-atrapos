"""The triceratops android, traced from the model sheet (reference/reference.png: left view and front
view, T-pose, 1980s anime style).

  python -I tools/partition.py && python -I tools/build_parts.py      (the analysis Python; cut-outs in masks/)
  blender -b --factory-startup --python external/blender/tricera_android/build_traced.py
Saves tricera_android.blend and renders/front.png, renders/left.png (orthographic, framed like the sheet).

Nine parts (collection "TriceraAndroid"): Head, Frill, Torso, Kilt, Arm.L / .R, Leg.L / .R, Cape - each a
mesh carved from the sheet's own outlines of it in the two views (tools/build_parts.py explains how), so
from the front and from the left the model's outlines are the drawing's. The drawing is also the paint:
every part carries its cut-out from both views, laid on from the front and from the side and blended by
which way the surface faces; unlit (the drawing has its cel shading in it), with an ink outline (an
inverted hull). The android faces -Y, feet on z = 0, 2.2 m tall, 0.00228 m per sheet pixel."""
import math
import os

import bpy
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
NAMES = {"cape": "Cape", "frill": "Frill", "legR": "Leg.R", "legL": "Leg.L", "armR": "Arm.R", "armL": "Arm.L",
         "torso": "Torso", "kilt": "Kilt", "head": "Head"}
K, FX, SX, GROUND = 0.00228, 1037.0, 262.0, 985.0


def ink():
    m = bpy.data.materials.new("TRI_Ink")
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (0.01, 0.006, 0.008, 1)
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    m.use_backface_culling = True
    return m


def paint(key):
    m = bpy.data.materials.new("TRI_" + NAMES[key])
    nt = m.node_tree
    nt.nodes.clear()
    N, L = nt.nodes, nt.links
    out = N.new("ShaderNodeOutputMaterial")
    tex = []
    for tag in ("front", "side"):
        uv = N.new("ShaderNodeUVMap")
        uv.uv_map = "UV_" + tag
        t = N.new("ShaderNodeTexImage")
        t.image = bpy.data.images.load(os.path.join(HERE, "tex", f"{key}_{tag}.png"))
        t.image.pack()
        t.extension = "EXTEND"
        L.new(uv.outputs["UV"], t.inputs["Vector"])
        tex.append(t)
    w = N.new("ShaderNodeAttribute")
    w.attribute_name = "wside"
    mix = N.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    L.new(w.outputs["Fac"], mix.inputs[0])
    L.new(tex[0].outputs["Color"], mix.inputs[6])
    L.new(tex[1].outputs["Color"], mix.inputs[7])
    em = N.new("ShaderNodeEmission")
    L.new(mix.outputs[2], em.inputs["Color"])
    L.new(em.outputs[0], out.inputs["Surface"])
    return m


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    col = bpy.data.collections.new("TriceraAndroid")
    sc.collection.children.link(col)
    inkm = ink()
    for key, name in NAMES.items():
        d = np.load(os.path.join(HERE, "meshes", key + ".npz"))
        me = bpy.data.meshes.new(name)
        v, f = d["verts"], d["faces"]
        me.vertices.add(len(v)); me.vertices.foreach_set("co", v.ravel())
        me.loops.add(f.size); me.loops.foreach_set("vertex_index", f.ravel())
        me.polygons.add(len(f))
        me.polygons.foreach_set("loop_start", np.arange(0, f.size, 3, dtype=np.int32))
        me.polygons.foreach_set("loop_total", np.full(len(f), 3, dtype=np.int32))
        me.update(calc_edges=True)
        me.polygons.foreach_set("use_smooth", np.ones(len(f), bool))
        for tag in ("front", "side"):
            uv = me.uv_layers.new(name="UV_" + tag)
            uv.data.foreach_set("uv", d["uv_" + tag][f.ravel()].ravel())
        at = me.attributes.new("wside", "FLOAT", "POINT")
        at.data.foreach_set("value", d["wside"])
        ob = bpy.data.objects.new(name, me)
        col.objects.link(ob)
        me.materials.append(paint(key))
        me.materials.append(inkm)
        s = ob.modifiers.new("Ink", "SOLIDIFY")
        s.thickness, s.offset, s.use_flip_normals, s.use_rim, s.material_offset = -0.0035, -1.0, True, False, 1
    # stage: the sheet's purple, two orthographic cameras framed like the sheet's two views
    sc.render.engine = "BLENDER_EEVEE"
    sc.view_settings.view_transform = "Standard"
    w = bpy.data.worlds.new("TRI_World")
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.314, 0.0, 0.807, 1)
    sc.world = w
    zc = (GROUND - 512.0) * K
    for name, loc, rot, cx, wpx in (("TRI_CamFront", (0, -8, zc), (math.pi / 2, 0, 0), 1037.0, 1000),
                                    ("TRI_CamLeft", (8, 0, zc), (math.pi / 2, 0, math.pi / 2), 290.0, 520)):
        cd = bpy.data.cameras.new(name)
        cd.type = "ORTHO"
        cd.ortho_scale = max(wpx, 1024) * K
        cam = bpy.data.objects.new(name, cd)
        cam.location, cam.rotation_euler = loc, rot
        if name == "TRI_CamLeft":
            cam.location.y = (cx - SX) * K
        cam["res"] = (wpx, 1024)
        col.objects.link(cam)
    sc.camera = bpy.data.objects["TRI_CamFront"]


def previews():
    sc = bpy.context.scene
    for cam, name in (("TRI_CamFront", "front"), ("TRI_CamLeft", "left")):
        ob = bpy.data.objects[cam]
        sc.camera = ob
        sc.render.resolution_x, sc.render.resolution_y = ob["res"]
        sc.render.filepath = os.path.join(HERE, "renders", name + ".png")
        bpy.ops.render.render(write_still=True)
    sc.camera = bpy.data.objects["TRI_CamFront"]
    sc.render.resolution_x, sc.render.resolution_y = bpy.data.objects["TRI_CamFront"]["res"]


if __name__ == "__main__":
    build()
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, "tricera_android.blend"))
    previews()
