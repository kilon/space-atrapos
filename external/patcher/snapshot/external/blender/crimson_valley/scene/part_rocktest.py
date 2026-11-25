"""A test of the rock material library (mat_rock.py), not part of the scene: part "rocktest".

WORK IN PROGRESS - first version.

  tools/cv part rocktest --no-save --no-sun --render renders/rocktest/a.png --scale 50 --samples 48 [options]

Options (after the part's name, anywhere): --rt-layout=picture|lab  --rt-az=235  --rt-el=16  --rt-sun=10
--rt-sky=0.3  --rt-only=name,name  --rt-border=x0,y0,x1,y1  --rt-flat (no relief modifier)  --rt-px=1
"""
import os

import bpy
import numpy as np

import common
import mat_rock

W, H = common.W, common.H


def options():
    o = {"layout": "picture", "az": "235", "el": "16", "sun": "10", "sky": "0.3", "only": "", "border": "",
         "flat": "", "px": "1", "plain": ""}
    for a in common.args_after_dashes():
        if a.startswith("--rt-"):
            k, _, v = a[5:].partition("=")
            o[k] = v or "1"
    return o


def load_mask(name):
    """An analysis mask as a bool array (H, W), row 0 at the top."""
    img = bpy.data.images.load(os.path.join(common.ANALYSIS, name + ".png"))
    img.colorspace_settings.name = "Non-Color"
    buf = np.empty(img.size[0] * img.size[1] * img.channels, dtype=np.float32)
    img.pixels.foreach_get(buf)
    a = buf.reshape(img.size[1], img.size[0], img.channels)[::-1, :, 0]
    bpy.data.images.remove(img)
    return a > 0.5


def sheet(name, mask, depth, col, attributes=None, cut=0.04):
    """A stand-in for a rock mesh: one vertex per picture pixel of `mask`, at the given depth (metres
    along the camera axis), joined into quads that face the camera; none across depth steps."""
    cm = common.cam_model()
    vv, uu = np.nonzero(mask)
    idx = -np.ones(mask.shape, dtype=np.int64)
    idx[vv, uu] = np.arange(len(vv))
    P = cm.unproject(uu + 0.5, vv + 0.5, depth[vv, uu])
    a, b, c, d = idx[:-1, :-1], idx[:-1, 1:], idx[1:, 1:], idx[1:, :-1]
    z = np.stack([depth[:-1, :-1], depth[:-1, 1:], depth[1:, 1:], depth[1:, :-1]])
    ok = (a >= 0) & (b >= 0) & (c >= 0) & (d >= 0) & ((z.max(0) - z.min(0)) < cut * z.min(0) + 0.15)
    faces = np.stack([a[ok], d[ok], c[ok], b[ok]], axis=1)
    at = {"ref_uv": np.stack([(uu + 0.5) / W, 1.0 - (vv + 0.5) / H], axis=1),
          "dist": np.linalg.norm(P - cm.pos, axis=1)}
    for k, m in (attributes or {}).items():
        at[k] = m[vv, uu].astype(np.float32)
    return common.mesh_object(name, P, faces, col, attributes=at)


def soft(mask, n=2):
    """A mask as 0..1 floats, blurred a little."""
    m = mask.astype(np.float32)
    for _ in range(n):
        m = (m + np.roll(m, 1, 0) + np.roll(m, -1, 0) + np.roll(m, 1, 1) + np.roll(m, -1, 1)) / 5.0
    return m


def picture_layout(col, opt):
    """Sheets cut out of the picture's own depth, one per kind of rock."""
    depth = np.load(os.path.join(common.ANALYSIS, "depth.npy")).astype(np.float64)
    rock = ~load_mask("sky") & ~load_mask("floor") & ~load_mask("water") & (depth > 0)
    veg, moss = soft(load_mask("veg")), soft(load_mask("moss"))
    v, u = np.mgrid[0:H, 0:W]

    def box(x0, y0, x1, y1):
        return (u >= x0) & (u < x1) & (v >= y0) & (v < y1)
    boulder = rock & box(505, 585, 765, 860) & (depth > 24) & (depth < 45)
    regions = [
        ("boulder", "boulder", {}, boulder),
        ("slab", "slab", {}, rock & box(0, 560, 840, H) & (depth < 60) & ~boulder),
        ("outcrop", "boulder", {}, rock & box(840, 740, 1260, H) & (depth < 60)),
        ("arch", "sandstone", {}, rock & box(0, 0, 700, 600) & (depth < 110)),
        ("spire", "spire", {}, rock & (u < 900) & (depth >= 110) & (depth < 400)),
        ("far", "far", {}, rock & (u < 900) & (depth >= 400)),
        ("cliff", "cliff", {}, rock & (u >= 900) & (v < 640) & (depth >= 100)),
        ("nearcliff", "cliff", {"scale": 0.35}, rock & (u >= 1250) & (v >= 430) & (depth < 100)),
    ]
    only = [s for s in opt["only"].split(",") if s]
    taken = np.zeros((H, W), bool)
    for name, preset, over, mask in regions:
        mask = mask & ~taken
        taken |= mask
        if only and name not in only:
            continue
        ob = sheet("CV_RockTest_" + name, mask, depth, col, {"veg": veg, "moss": moss})
        dress(ob, name, preset, over, opt)
        print(f"  {ob.name}: {len(ob.data.vertices)} verts, preset {preset}")


def dress(ob, name, preset, over, opt):
    over = dict(over, px_scale=float(opt["px"]))
    if opt["plain"]:
        mat, nodes, links = common.new_material("CV_RockTest_plain")
        b = nodes.new("ShaderNodeBsdfPrincipled")
        b.inputs["Base Color"].default_value = common.rgba(mat_rock.PRESETS[preset].get("base", mat_rock.DEFAULTS["base"]))
        b.inputs["Roughness"].default_value = 0.85
        links.new(b.outputs[0], nodes.new("ShaderNodeOutputMaterial").inputs[0])
    else:
        mat = mat_rock.rock_material("CV_RockTest_" + name, preset=preset, **over)
    ob.data.materials.append(mat)
    if not opt["flat"]:
        mat_rock.displace_modifiers(ob, preset, **over)


def build(col):
    opt = options()
    print("rocktest options:", opt)
    picture_layout(col, opt)
    scene = bpy.context.scene
    sun = common.preview_sun(scene, azimuth_deg=float(opt["az"]), elevation_deg=float(opt["el"]),
                             strength=float(opt["sun"]))
    sun.name = sun.data.name = "CV_RockTestSun"
    common.preview_world(scene, strength=float(opt["sky"]))
    if opt["border"]:
        x0, y0, x1, y1 = [float(s) for s in opt["border"].split(",")]
        r = scene.render
        r.use_border, r.use_crop_to_border = True, False
        r.border_min_x, r.border_max_x = x0 / W, x1 / W
        r.border_min_y, r.border_max_y = 1.0 - y1 / H, 1.0 - y0 / H
