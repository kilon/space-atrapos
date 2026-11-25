"""The lights of the Crimson Valley scene: part "lighting".

  tools/cv part lighting --with sky,clouds,planet,moons,terrain,rocks,water --render renders/lighting/a.png

The picture's light is a painter's, not one sun: the hill the camera stands on (the left arch, its
wall, the slabs and boulders) is lit warm from behind the camera's right shoulder, while the spires,
ridges, arch and towers across the valley are lit from the left. So there are two low warm suns, each
linked (light linking) to the rocks it lights:
  CV_Sun_Near    from the right, low (azimuth 118, elevation 9)  -> near_hill, outcrop
  CV_Sun_Valley  from the left (azimuth 240, elevation 24)      -> everything else
The sky (CV_World) is the cool fill. Azimuth: where the light comes from, degrees clockwise seen from
above, 0 = ahead of the camera, 90 = its right, 180 = behind it, 270 = its left."""
import math

import bpy

import common

NEAR = ("near_hill", "outcrop")
SUNS = {"CV_Sun_Near": dict(az=118.0, el=9.0, strength=3.6, color=(1.0, 0.62, 0.36)),
        "CV_Sun_Valley": dict(az=240.0, el=24.0, strength=4.2, color=(1.0, 0.66, 0.42))}


def build(col):
    for name, s in SUNS.items():
        light = bpy.data.lights.new(name, "SUN")
        light.energy = s["strength"]
        light.color = s["color"]
        light.angle = math.radians(3.0)
        ob = bpy.data.objects.new(name, light)
        col.objects.link(ob)
        common.aim_sun(ob, s["az"], s["el"])


def finalize(scene):
    near = bpy.data.collections.get("CV_Lit_Near") or bpy.data.collections.new("CV_Lit_Near")
    valley = bpy.data.collections.get("CV_Lit_Valley") or bpy.data.collections.new("CV_Lit_Valley")
    for ob in scene.objects:
        if ob.type != "MESH" or ob.name.startswith(("CV_Clouds", "CV_Planet", "CV_Moon", "CV_Haze", "CV_Fog")):
            continue
        # plants and the terrain take both suns (they are spread over both sides)
        both = ob.name.startswith(("CV_Veg", "CV_Terrain"))
        is_near = ob.get("cv_group") in NEAR
        for target in ([near, valley] if both else [near if is_near else valley]):
            if ob.name not in target.objects:
                target.objects.link(ob)
    a, b = scene.objects.get("CV_Sun_Near"), scene.objects.get("CV_Sun_Valley")
    if a and b:
        a.light_linking.receiver_collection = near
        b.light_linking.receiver_collection = valley
