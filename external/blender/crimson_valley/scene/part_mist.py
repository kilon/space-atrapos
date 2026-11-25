"""Haze and mist: part "mist".

  tools/cv part mist --with sky,clouds,planet,terrain,rocks,water,lighting --render renders/mist/a.png

CV_Haze is the air: one low slab (50 m) of thin, even scattering over the whole valley, lit by the sky only, so things fade with
distance into the sky's light as in the picture (the far spires almost gone, the near hill clear).
CV_Fog_* are the mist banks: boxes of denser, noise-broken fog lying low between the ridges left of
centre, over the far plain and at the feet of the waterfalls. They are placed from picture points
(BANKS: a picture point on the ground at the bank's centre, its size in metres)."""
import bpy
import numpy as np

import common

HAZE = 0.0015            # scattering per metre
# picture u, v of the bank's middle, size x, y (along the view), z in metres, density
BANKS = [(470, 470, 170, 120, 30, 0.07), (330, 420, 260, 200, 45, 0.04), (640, 520, 90, 60, 16, 0.07),
         (820, 452, 500, 500, 24, 0.018), (1150, 470, 260, 160, 18, 0.03), (1420, 432, 130, 60, 22, 0.07),
         (1560, 770, 34, 26, 14, 0.16), (1425, 705, 20, 16, 9, 0.14), (1300, 520, 30, 20, 9, 0.08)]


def volume(name, density, color, noise=0.0, scale=0.03):
    mat, N, L = common.new_material(name)
    out = N.new("ShaderNodeOutputMaterial")
    vol = N.new("ShaderNodeVolumePrincipled")
    vol.inputs["Color"].default_value = common.rgba(color)
    vol.inputs["Density"].default_value = density
    vol.inputs["Anisotropy"].default_value = 0.3
    if noise:
        tc = N.new("ShaderNodeTexCoord")
        no = N.new("ShaderNodeTexNoise"); no.noise_type = "FBM"
        no.inputs["Scale"].default_value = scale; no.inputs["Detail"].default_value = 5.0
        L.new(tc.outputs["Object"], no.inputs["Vector"])
        # soft box: fade to the sides and upwards (Generated runs 0..1 across the box)
        sep = N.new("ShaderNodeSeparateXYZ"); L.new(tc.outputs["Generated"], sep.inputs[0])
        def bell(sock):
            a = N.new("ShaderNodeMath"); a.operation = "PINGPONG"; a.inputs[1].default_value = 0.5
            L.new(sock, a.inputs[0])
            b = N.new("ShaderNodeMapRange"); b.interpolation_type = "SMOOTHSTEP"; b.inputs["From Max"].default_value = 0.4
            L.new(a.outputs[0], b.inputs["Value"])
            return b
        bx, by = bell(sep.outputs["X"]), bell(sep.outputs["Y"])
        up = N.new("ShaderNodeMapRange"); up.interpolation_type = "SMOOTHSTEP"
        up.inputs["From Min"].default_value = 1.0; up.inputs["From Max"].default_value = 0.15
        L.new(sep.outputs["Z"], up.inputs["Value"])
        cut = N.new("ShaderNodeMapRange")
        cut.inputs["From Min"].default_value = 0.38; cut.inputs["From Max"].default_value = 0.68
        L.new(no.outputs["Fac"], cut.inputs["Value"])
        m = cut
        for other in (bx, by, up):
            mm = N.new("ShaderNodeMath"); mm.operation = "MULTIPLY"
            L.new(m.outputs[0], mm.inputs[0]); L.new(other.outputs[0], mm.inputs[1])
            m = mm
        ds = N.new("ShaderNodeMath"); ds.operation = "MULTIPLY"; ds.inputs[1].default_value = density
        L.new(m.outputs[0], ds.inputs[0])
        L.new(ds.outputs[0], vol.inputs["Density"])
    L.new(vol.outputs["Volume"], out.inputs["Volume"])
    return mat


def box(col, name, centre, size, mat):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=centre)
    ob = bpy.context.active_object
    ob.name = name
    ob.scale = size
    for c in list(ob.users_collection):
        c.objects.unlink(ob)
    col.objects.link(ob)
    ob.data.materials.append(mat)
    ob.display_type = "WIRE"
    ob.visible_shadow = False
    return ob


def build(col):
    cm = common.cam_model()
    box(col, "CV_Haze", (0.0, 4500.0, 24.0), (12000.0, 9400.0, 50.0), volume("CV_Haze", HAZE, "#e9d6d6"))
    for k, (u, v, sx, sy, sz, dens) in enumerate(BANKS):
        d = float(cm.ground_z(np.array(float(v)), 0.0))
        p = cm.unproject(np.array(float(u)), np.array(float(v)), np.array(d))
        box(col, f"CV_Fog_{k + 1}", (p[0], p[1], sz / 2 - 0.5), (sx, sy, sz), volume(f"CV_Fog_{k + 1}", dens, "#f2e6e4", noise=1.0, scale=4.0 / max(sx, sy) * 8))
