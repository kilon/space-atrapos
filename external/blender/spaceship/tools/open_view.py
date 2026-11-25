"""Run by Blender when opening spaceship.blend by hand:  blender spaceship.blend --python tools/open_view.py
Shows the ship through the reference picture's camera in Material Preview."""
import bpy


def setup():
    for win in bpy.context.window_manager.windows:
        for area in win.screen.areas:
            if area.type == "VIEW_3D":
                sp = area.spaces.active
                sp.shading.type = "MATERIAL"
                sp.region_3d.view_perspective = "CAMERA"
    return None


bpy.app.timers.register(setup, first_interval=0.5)
