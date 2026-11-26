"""Run by Blender when opening dinosaur.blend by hand:  blender dinosaur.blend --python tools/open_view.py
Shows the model textured (Material Preview) and starts playing the current animation."""
import bpy


def setup():
    for win in bpy.context.window_manager.windows:
        for area in win.screen.areas:
            if area.type == "VIEW_3D":
                area.spaces.active.shading.type = "MATERIAL"
                with bpy.context.temp_override(window=win, area=area, region=[r for r in area.regions if r.type == "WINDOW"][0]):
                    bpy.ops.view3d.view_all()
    return None


bpy.app.timers.register(setup, first_interval=0.5)
