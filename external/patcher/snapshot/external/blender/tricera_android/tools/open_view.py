"""Run by Blender when opening tricera_android.blend by hand:
  blender tricera_android.blend --python tools/open_view.py
Shows the model as it is meant to be seen: Material Preview shading (the ink outlines are back-face
culled shells, which Solid shading draws as black lumps), looking at the front."""
import bpy


def setup():
    for win in bpy.context.window_manager.windows:
        for area in win.screen.areas:
            if area.type == "VIEW_3D":
                sp = area.spaces.active
                sp.shading.type = "MATERIAL"
                sp.overlay.show_floor = True
                with bpy.context.temp_override(window=win, area=area, region=[r for r in area.regions if r.type == "WINDOW"][0]):
                    bpy.ops.view3d.view_axis(type="FRONT")
                    bpy.ops.view3d.view_all()
    return None


bpy.app.timers.register(setup, first_interval=0.5)
