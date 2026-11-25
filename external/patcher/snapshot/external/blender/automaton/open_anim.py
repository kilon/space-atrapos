"""Opens a skin's .blend ready to look at its animations: the 3D view on the
character from the game's side, the Dope Sheet's Action Editor under it, the
"walk" action playing in a loop (pick another in the Action Editor's list -
whichever part is selected, it plays on the rig; the timeline fits its length).

  blender automaton.blend --python open_anim.py
"""
import bpy

arm = bpy.data.objects.get("Rig")
# The model is a few main parts (Head, Torso, Arm.L / .R, Leg.L / .R, Rifle - the
# pirate's Coat too), skinned to the rig: click one to edit it. The Action
# Editor works on the ACTIVE object - with a part active, an action picked there
# would go to the part (which has no bones: nothing would move) - so an action
# given to a part is handed to the rig at once (_to_rig).
if arm:
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm


def _to_rig(scene, *args):
    r = bpy.data.objects.get("Rig")
    if r is None:
        return
    for ob in scene.objects:
        if ob.type == "MESH" and ob.animation_data and ob.animation_data.action:
            a = ob.animation_data.action
            ob.animation_data.action = None
            rd = r.animation_data or r.animation_data_create()
            rd.action = a
            try:
                if a.slots:
                    rd.action_slot = a.slots[0]
            except Exception:
                pass


bpy.app.handlers.depsgraph_update_post.append(_to_rig)


def _fit_range(scene, *args):
    """The timeline as long as the action picked (each has its own length)."""
    r = bpy.data.objects.get("Rig")
    a = r.animation_data.action if r and r.animation_data else None
    if a is not None and scene.frame_end != int(a.get("frames", 30)):
        scene.frame_start = 1
        scene.frame_end = int(a.get("frames", 30))


bpy.app.handlers.frame_change_pre.append(_fit_range)
act = bpy.data.actions.get("walk") or (bpy.data.actions[0] if bpy.data.actions else None)
sc = bpy.context.scene
sc.render.fps = 30
if arm and act:
    ad = arm.animation_data or arm.animation_data_create()
    ad.action = act
    try:
        if not ad.action_slot and act.slots:
            ad.action_slot = act.slots[0]
    except Exception:
        pass
    sc.frame_start = 1
    sc.frame_end = int(act.get("frames", 30))
    sc.frame_set(1)


def _later():
    for win in bpy.context.window_manager.windows:
        for area in win.screen.areas:
            if area.type == "DOPESHEET_EDITOR":
                area.spaces[0].mode = "ACTION"
            if area.type == "VIEW_3D":
                sp = area.spaces[0]
                sp.shading.type = "MATERIAL"
                for region in area.regions:
                    if region.type == "WINDOW":
                        with bpy.context.temp_override(window=win, area=area, region=region):
                            bpy.ops.view3d.view_axis(type="FRONT")
                            bpy.ops.view3d.view_all()
    try:
        bpy.ops.screen.animation_play()
    except Exception:
        pass
    return None


bpy.app.timers.register(_later, first_interval=1.0)
