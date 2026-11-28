"""Builds an android skin, rigs it, bakes its animations and renders its sprites.

  blender -b --python build.py -- <skin> model            # the model + previews/<skin>_model.png, saves <skin>.blend
  blender -b <skin>.blend --python build.py -- <skin> clips [names]   # previews/<skin>_<clip>.png (contact sheets)
  blender -b <skin>.blend --python build.py -- <skin> actions         # every clip as an action (30 fps), saved
  blender -b <skin>.blend --python build.py -- <skin> render [names] [--dirs e,se] [--jobs i/n]
                                                           # renders/<skin>/<clip>_<dir>_<frame>.png + meta.json
  blender -b <skin>.blend --python build.py -- <skin> export          # art/<id>_3d/<id>.glb + model.json: the model itself,
                                                           # rigged and animated, for the game (after "actions")

Skins: automaton (automaton.py), pirate (pirate.py). Animations: moves.py.
"""
import importlib
import json
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import kit       # noqa: E402

importlib.reload(kit)


def skin_module(name):
    mod = importlib.import_module(name)
    importlib.reload(mod)
    kit.GUN_HAND_R = mod.GUN_HAND_R
    kit.GUN_HAND_L = mod.GUN_HAND_L
    kit.GUN_FOLD = dict(getattr(mod, "GUN_FOLD", {}))   # (a rifle that folds for its holster: its pieces' bones)
    return mod


def model(name):
    mod = skin_module(name)
    kit.clear()
    kit.build_rig(getattr(mod, "EXTRA_BONES", None))
    kit.TAIL_SOLVER[0] = getattr(mod, "tail_solver", None)
    mod.build()
    kit.bake_decals()
    kit.rig_parts()
    kit.merge_parts()          # (the many pieces into a few main parts, skinned)
    kit.stage()
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, name + ".blend"))


def load(name):
    mod = skin_module(name)
    arm = kit.obj("Rig")
    kit.REST.clear()
    kit.PARENT.clear()
    for b in arm.data.bones:
        kit.REST[b.name] = b.matrix_local.copy()
        kit.PARENT[b.name] = b.parent.name if b.parent else None
    kit.EXTRA.clear()
    kit.EXTRA.update(getattr(mod, "EXTRA_BONES", None) or {})
    kit.TAIL_SOLVER[0] = getattr(mod, "tail_solver", None)
    return mod


def _screen(p, d):
    """A point of the character (armature space, m) in the picture from direction d: px from the ground point, y down."""
    import math
    from mathutils import Matrix
    q = Matrix.Rotation(kit.facing_angle(d), 3, "Z") @ p
    el = math.radians(kit.ELEVATION)
    k = kit.px_per_m()
    return [round(q.x * k, 1), round(-(q.y * math.sin(el) + q.z * math.cos(el)) * k, 1)]


def points(clip):
    """Where things are in the pictures, per direction: the rifle's muzzle (the
    last frame of a clip with the rifle), the hands at the "cast" / "hit" mark."""
    from mathutils import Vector
    out = {}
    poses = clip["poses"]
    if clip.get("gun"):
        p = dict(poses[-1])
        p["air"] = 0.0
        m = kit.solve(p)["gun"]
        tip = m @ Vector((0.0, 0.78, 0.075))
        out["muzzle"] = {d: _screen(tip, d) for d in kit.DIRS}
    for mark in ("cast", "hit"):
        if mark in clip.get("marks", {}) and not clip.get("gun"):
            p = dict(poses[min(len(poses) - 1, clip["marks"][mark] + 1)])
            p["air"] = 0.0
            mats = kit.solve(p)
            hl = mats["fingers.L"].translation
            hr = mats["fingers.R"].translation
            out["hands"] = {d: _screen((hl + hr) * 0.5, d) for d in kit.DIRS}
            out["handR"] = {d: _screen(hr, d) for d in kit.DIRS}
    return out


def export(name, art_id):
    """The model itself for the game (SheetPuppet's model mode): art/<id>_3d/<id>.glb -
    every part joined into ONE mesh, each part's vertices held by its bone, the ink
    outlines as geometry, all the actions as animations - and model.json: the clips
    (frames, loop, marks, how high off the ground per frame, the rifle's muzzle and the
    hands as 3D points), the materials (the cel shading's colours: the game makes its own
    shaders from them) and the size it stands."""
    from mathutils import Vector
    mod = load(name)
    import moves
    importlib.reload(moves)
    clips = moves.clips(name)
    # The cel materials' numbers, as the skin gives them.
    mats = {}
    orig = (kit.mat_toon, kit.mat_glow, kit.mat_outline)

    def rec_toon(mname, color, shade=0.62, hi=0.0, tint=(0.92, 0.9, 1.08)):
        c = kit.hexc(color) if isinstance(color, str) else color
        mats[mname] = {"kind": "toon", "color": list(c), "shade": shade, "hi": hi, "tint": list(tint)}
        return bpy.data.materials.get(mname)

    def rec_glow(mname, color, strength=1.6):
        c = kit.hexc(color) if isinstance(color, str) else color
        mats[mname] = {"kind": "glow", "color": list(c), "strength": strength}
        return bpy.data.materials.get(mname)

    def rec_ink(mname="KIT_Ink", color=(0.012, 0.008, 0.02)):
        mats[mname] = {"kind": "ink", "color": list(color)}
        return bpy.data.materials.get(mname)
    kit.mat_toon, kit.mat_glow, kit.mat_outline = rec_toon, rec_glow, rec_ink
    keep = dict(kit.M)
    for m in ([mod] + ([sys.modules["automaton"]] if name != "automaton" and "automaton" in sys.modules else [])):
        if hasattr(m, "materials"):
            m.materials()
    mod.materials()
    kit.M.clear()
    kit.M.update(keep)
    kit.mat_toon, kit.mat_glow, kit.mat_outline = orig
    # Your own work layered over the generated character (external/blender_overrides/<skin>/:
    # parts replacing or added to these, actions replacing or adding clips) - see overrides.py there.
    arm = kit.obj("Rig")
    ovr = {"parts": {}, "clips": {}, "problems": []}
    try:
        sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), "blender_overrides"))
        import overrides
        importlib.reload(overrides)
        ovr = overrides.apply(name, arm, kit.coll())
    except ImportError:
        pass
    # One mesh: every part in the rest pose, its vertices on its bone.
    if arm.animation_data:
        arm.animation_data.action = None
    for pb in arm.pose.bones:
        pb.location = (0, 0, 0)
        pb.rotation_quaternion = (1, 0, 0, 0)
    arm.data.pose_position = "REST"
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    made = []
    for ob in list(kit.coll().objects):
        if ob.type != "MESH" or ob.parent != arm:
            continue
        if ob.parent_type == "BONE":         # (an older model: rigid parts on bones)
            me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
            me.transform(ob.matrix_world)
            t = bpy.data.objects.new("x_" + ob.name, me)
            kit.coll().objects.link(t)
            t.vertex_groups.new(name=ob.parent_bone).add(list(range(len(me.vertices))), 1.0, "REPLACE")
        else:                                # (a main part, skinned: its outline made geometry, its bones' groups kept)
            arm_mod = ob.modifiers.get("Armature")
            if arm_mod:
                arm_mod.show_viewport = False
            bpy.context.view_layer.update()
            dg = bpy.context.evaluated_depsgraph_get()
            me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
            if arm_mod:
                arm_mod.show_viewport = True
            me.transform(ob.matrix_world)
            t = bpy.data.objects.new("x_" + ob.name, me)
            kit.coll().objects.link(t)
            if len(t.vertex_groups) == 0:     # (the group names live on the mesh in this Blender - else copied)
                for vg in ob.vertex_groups:
                    t.vertex_groups.new(name=vg.name)
            ink = t.vertex_groups.get("ink")
            if ink:
                t.vertex_groups.remove(ink)
        made.append(t)
    bpy.ops.object.select_all(action="DESELECT")
    for t in made:
        t.select_set(True)
    bpy.context.view_layer.objects.active = made[0]
    bpy.ops.object.join()
    body = bpy.context.view_layer.objects.active
    body.name = "Body"
    body.parent = arm
    am = body.modifiers.new("Armature", "ARMATURE")
    am.object = arm
    arm.data.pose_position = "POSE"
    bpy.context.view_layer.update()
    out_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(HERE))), "art", art_id + "_3d")
    os.makedirs(out_dir, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.export_scene.gltf(filepath=os.path.join(out_dir, art_id + ".glb"), export_format="GLB", use_selection=True,
                              export_animations=True, export_animation_mode="ACTIONS", export_force_sampling=True,
                              export_anim_slide_to_zero=True, export_optimize_animation_size=False, export_skins=True,
                              export_yup=True, export_cameras=False, export_lights=False, export_apply=False)
    # The clips' facts.
    info = {}
    for cname, c in clips.items():
        poses = c["poses"]
        pts = {}
        if c.get("gun"):
            p = dict(poses[-1])
            p["air"] = 0.0
            g = kit.solve(p)["gun"]
            tip = g @ Vector((0.0, 0.78, 0.075))
            pts["muzzle"] = [round(v, 4) for v in tip]
        for mark in ("cast", "hit"):
            if mark in c.get("marks", {}) and not c.get("gun"):
                p = dict(poses[min(len(poses) - 1, c["marks"][mark] + 1)])
                p["air"] = 0.0
                ms = kit.solve(p)
                hl, hr = ms["fingers.L"].translation, ms["fingers.R"].translation
                pts["hands"] = [round(v, 4) for v in (hl + hr) * 0.5]
                pts["handR"] = [round(v, 4) for v in hr]
        if c.get("box"):      # (put_down / pick_up: the crate's middle each frame - as the game's model space: (x, up, forward))
            pts["box"] = [[round(b[0], 4), round(b[2], 4), round(b[1], 4)] for b in c["box"]]
        info[cname] = {"n": len(poses), "loop": c.get("loop", False), "gun": c.get("gun", False), "marks": c.get("marks", {}),
                       "air": [round(p.get("air", 0.0), 4) for p in poses], "points": pts}
    for cname in ovr["clips"]:   # (your clips: their length from the action; loop as the clip they replace, or the action's "loop" property)
        a = bpy.data.actions.get(cname)
        if a is None:
            continue
        n = int(round(a.frame_range[1] - a.frame_range[0])) + 1
        old = info.get(cname, {})
        loop = bool(a.get("loop", old.get("loop", False)))
        info[cname] = {"n": n, "loop": loop, "gun": bool(a.get("gun", old.get("gun", False))), "marks": old.get("marks", {}) if n == old.get("n") else {},
                       "air": old.get("air", [0.0] * n) if n == old.get("n") else [0.0] * n, "points": old.get("points", {}) if n == old.get("n") else {},
                       "override": True}
    used = sorted({m.name for m in body.data.materials if m})
    with open(os.path.join(out_dir, "model.json"), "w") as fh:
        json.dump({"fps": kit.FPS, "elevation": kit.ELEVATION, "clips": info, "overrides": ovr,
                   "materials": {k: mats[k] for k in used if k in mats}, "triangles": sum(len(p.vertices) - 2 for p in body.data.polygons)},
                  fh, separators=(",", ":"))
    print("EXPORTED %s: %d verts, %d materials (%s), %d clips" % (art_id, len(body.data.vertices), len(used),
                                                               ",".join(k for k in used if k not in mats) or "all known", len(info)))


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    name, cmd = argv[0], argv[1]
    rest = argv[2:]
    opts = {}
    names = []
    i = 0
    while i < len(rest):
        if rest[i].startswith("--"):
            opts[rest[i][2:]] = rest[i + 1]
            i += 2
        else:
            names.append(rest[i])
            i += 1
    os.makedirs(os.path.join(HERE, "previews"), exist_ok=True)
    if cmd == "model":
        model(name)
        base = {"gun": ("c", (-0.10, 0.30, -0.42), (0.75, 0.55, -0.12), (0, 0, 1), "both")} if "gun" in opts.get("pose", "gun") else {}
        dirs = opts.get("dirs", "s,se,e").split(",")
        kit.preview(os.path.join(HERE, "previews", name + "_model.png"), [(base, d) for d in dirs], res=int(opts.get("res", 640)),
                    ortho=float(opts.get("ortho", 2.3)))
        return
    if cmd == "export":       # (the .blend isn't saved: the joined mesh is only for the file written)
        export(name, opts.get("id", {"automaton": "player"}.get(name, name)))
        return
    load(name)
    import moves
    importlib.reload(moves)
    clips = moves.clips(name)
    pick = [c for c in clips if not names or c in names]
    if cmd == "clips":
        step = int(opts.get("step", 2))
        d = opts.get("dirs", "se").split(",")
        for c in pick:
            poses = clips[c]["poses"]
            sel = poses[::step]
            for dd in d:
                kit.preview(os.path.join(HERE, "previews", "%s_%s_%s.png" % (name, c, dd)), [(p, dd) for p in sel],
                            res=int(opts.get("res", 300)), ortho=float(opts.get("ortho", 2.9)), cols=int(opts.get("cols", 8)),
                            crop=float(opts.get("crop", 0.12)))
    elif cmd == "actions":
        for c in clips:
            kit.bake(c, clips[c]["poses"])
        kit.obj("Rig").animation_data.action = bpy.data.actions.get("idle") or bpy.data.actions[0]
        bpy.context.scene.frame_start = 1
        bpy.context.scene.frame_end = 30
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, name + ".blend"))
    elif cmd == "render":
        out = os.path.join(HERE, "renders", name)
        os.makedirs(out, exist_ok=True)
        kit.stage(int(opts.get("res", kit.RES)))
        dirs = opts.get("dirs", ",".join(kit.DIRS)).split(",")
        ji, jn = [int(x) for x in opts.get("jobs", "0/1").split("/")]
        work = [(c, d) for c in pick for d in dirs]
        for k, (c, d) in enumerate(work):
            if k % jn != ji:
                continue
            kit.render_poses(clips[c]["poses"], out, c, dirs=[d])
        if ji == 0:
            meta = {"ground": kit.ground_px(), "px_per_m": kit.px_per_m(), "res": bpy.context.scene.render.resolution_x, "fps": kit.FPS,
                    "clips": {c: {"frames": len(clips[c]["poses"]), "loop": clips[c].get("loop", False),
                                  "air": [round(p.get("air", 0.0) * kit.px_per_m(), 2) for p in clips[c]["poses"]],
                                  "marks": clips[c].get("marks", {}), "gun": clips[c].get("gun", False),
                                  "points": points(clips[c])} for c in clips}}
            with open(os.path.join(out, "meta.json"), "w") as fh:
                json.dump(meta, fh)


main()
