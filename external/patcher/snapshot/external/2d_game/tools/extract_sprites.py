#!/usr/bin/env python3
"""Cuts the sprites out of the reference sheets in external/images/ as PNG images.

Every ship / station on a sheet is cut out of its grid cell, NPC turnaround
views and head portraits off their boards and pedestals, tile-set pieces out
of their panels. Backgrounds (dark or green-screen), pedestals and shadows
are removed; edges get a soft alpha. The result is data/sprites/<key>.png,
which Godot imports and the game uses directly as sprite textures.

    python3 tools/extract_sprites.py              # every sheet
    python3 tools/extract_sprites.py minoan       # sheets whose file contains "minoan"
    python3 tools/extract_sprites.py --only ship_traced_minoa_labrys
    python3 tools/extract_sprites.py female_bow --npc-preview out.png
    python3 tools/extract_sprites.py tile_set_2 --tiles-preview out.png

Needs: python3 with numpy and Pillow.
"""
import math
import os
import sys
import tempfile
from collections import deque

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IMAGES = os.path.join(ROOT, "external", "images")
OUT = os.environ.get("SPRITES_OUT") or os.path.join(ROOT, "data", "sprites")   # (SPRITES_OUT: try a cut elsewhere)

MINOA = ["labrys", "taurus", "kraken", "lily", "horns", "xspiral", "nautilus", "trident", "leaper", "rosette", "dolphin", "olive"]
PIRATES = ["reaver", "bonescythe", "corsair", "ironwheel", "ribcage", "banner", "maw", "twinaxe", "scythe", "skullbarge", "skullsun", "galleon"]
ATHENS = ["glaukopis", "parthenon_wheel", "noctua", "parthenon", "laurel", "athena", "owlstar", "dromeus", "pteryx", "tholos", "doru", "pentathlon"]
SPARTA = ["lambda", "hoplite", "leonidas", "thermopylae", "phalanx", "krypteia", "helot", "dory", "aspis", "lykourgos", "xiphos", "gorgo"]
INDIE = ["ember", "skylance", "bulwark", "crescent", "violet_dart", "halo", "hornet", "tidewing", "nightjar", "atlas", "aether", "bastion"]
IONIA = ["thales", "miletos", "anaximander", "ephesos", "lyra", "artemision", "trireme", "pegasus", "samos", "herakleitos", "didyma", "phokaia"]
IONIA_STATIONS = ["lyre", "garden", "waves", "laurel", "crescent", "pegasus", "isle", "star", "isles", "armillary", "dome", "column"]
STATIONS = ["wheel", "star", "forge", "crescents", "violet_sun", "halo", "gateway", "lotus", "trident", "solar", "vortex", "foundry"]
# The Minoans' own stations (external/prompt_templates/stations__minoan_prompt_template.txt;
# the sheet doesn't exist yet - skipped until it does).
MINOA_STATIONS = ["palace", "horns", "labrys", "octopus", "dolphins", "spiral", "lily", "nautilus", "rosette", "bull", "wave", "meander"]
# The Athenians' own (external/prompt_templates/stations__athenian_prompt_template.txt; skipped until it exists).
ATHENS_STATIONS = ["parthenon", "owl", "athena", "nike", "olive", "propylaia", "agora", "trireme", "aegis", "lyceum", "theatre", "lighthouse"]
# The Spartans' own (external/prompt_templates/stations__spartan_prompt_template.txt; skipped until it exists).
# The Mycenaeans' own (external/prompt_templates/stations__mycenaean_prompt_template.txt; skipped until it exists).
MYCENAE_STATIONS = ["lion_gate", "mask", "tholos", "megaron", "cyclopean", "shield", "boar", "chariot", "griffin", "forge", "treasury", "mine"]
# The Cycladic civilisation (external/prompt_templates/ships__cycladic_ / stations__cycladic_prompt_template.txt;
# not in the game yet - skipped until the sheets exist).
CYCLADES = ["figurine", "harpist", "longboat", "pan", "spiral", "obsidian", "kandila", "marble", "quarry", "oarsman", "voyager", "sanctuary"]
CYCLADES_STATIONS = ["figure", "pan", "circle", "harbour", "spiral", "quarry", "obsidian", "harp", "kandila", "sanctuary", "sun", "lighthouse"]
SPARTA_STATIONS = ["lambda", "helmet", "hoplon", "phalanx", "citadel", "arsenal", "agoge", "thermopylae", "dory", "barracks", "forge", "watchtower"]

# file, columns, rows, kind ("ship" = nose right on the sheet, turned nose-up; "station"), keys
SHEETS = [
    ("minoan_ships_1.png", 4, 3, "ship", ["ship_traced_minoa_" + k for k in MINOA]),
    ("pirate_ships_1.png", 4, 3, "ship", ["ship_traced_pirate_" + k for k in PIRATES]),
    ("athenian_ships_1.png", 4, 3, "ship", ["ship_traced_athens_" + k for k in ATHENS]),
    ("spartan_ships_1.png", 3, 4, "ship", ["ship_traced_sparta_" + k for k in SPARTA]),
    ("player_ships_1.png", 4, 3, "ship", ["ship_traced_" + k for k in INDIE]),
    ("stations_1.png", 4, 3, "station", ["station_" + k for k in STATIONS]),
    ("palyer_ship_1.png", 1, 1, "ship", ["ship_player"]),
    ("ioanian_spaceships_1.png", 3, 4, "ship", ["ship_traced_ionia_" + k for k in IONIA]),
    ("ionian_spacestations_1.png", 4, 3, "station", ["station_ionia_" + k for k in IONIA_STATIONS]),
    ("minoan_spacestations_1.png", 4, 3, "station", ["station_minoa_" + k for k in MINOA_STATIONS]),
    ("athenian_spacestations_1.png", 4, 3, "station", ["station_athens_" + k for k in ATHENS_STATIONS]),
    ("spartan_spacestations_1.png", 4, 3, "station", ["station_sparta_" + k for k in SPARTA_STATIONS]),
    ("mycenaean_spacestations_1.png", 4, 3, "station", ["station_mycenae_" + k for k in MYCENAE_STATIONS]),
    ("cycladic_ships_1.png", 4, 3, "ship", ["ship_traced_cyclades_" + k for k in CYCLADES]),
    ("cycladic_spacestations_1.png", 4, 3, "station", ["station_cyclades_" + k for k in CYCLADES_STATIONS]),
]

FG_THRESHOLD = 26        # brightest channel above this = part of the ship (not the black sheet)
## Sheets on a pure black background whose ships have very dark panels: a lower threshold
## (the player ship's dark hull plates beside the cockpit are 5-26; its background is 0-1).
FG_BY_SHEET = {"palyer_ship_1.png": 4}
## Sheets whose ships have pieces drawn apart from them that reach into the next cell
## (the pirates' flags): each piece goes to the nearest hull (sheet_owners), not to
## the cell its centre is in. Not for every sheet: where dark panels split a hull into
## pieces, its biggest piece isn't the whole hull and the rest can be nearer another.
NEAREST_HULL_SHEETS = {"pirate_ships_1.png"}


def components(mask):
    """8-connected components of a boolean mask: list of (pixel index arrays)."""
    h, w = mask.shape
    lab = np.zeros(mask.shape, np.int32)
    flat = mask.ravel()
    labf = lab.ravel()
    comps = []
    for start in np.flatnonzero(flat):
        if labf[start]:
            continue
        n = len(comps) + 1
        labf[start] = n
        q = deque([start])
        pix = []
        while q:
            p = q.popleft()
            pix.append(p)
            y, x = divmod(p, w)
            for dy in (-1, 0, 1):
                yy = y + dy
                if yy < 0 or yy >= h:
                    continue
                for dx in (-1, 0, 1):
                    xx = x + dx
                    if 0 <= xx < w:
                        qq = yy * w + xx
                        if flat[qq] and not labf[qq]:
                            labf[qq] = n
                            q.append(qq)
        comps.append(np.array(pix))
    return comps


def sheet_owners(img, cells, threshold):
    """Which ship every piece of a sheet belongs to: a map of cell indices (-1:
    background or specks). First, as for any sheet, each piece goes to the cell
    its centre is in; then a piece clearly apart from the rest of its cell's ship
    (> 12 px) and at least 3x nearer another cell's ship moves to that one - a
    flag drawn apart from its ship can reach into the next cell (the pirate
    skullbarge's flag reaches into the banner's)."""
    H, W = img.shape[:2]
    fg = img.max(axis=2) > threshold
    comps = components(fg)
    cell_of = []
    for c in comps:
        ys, xs = np.divmod(c, W)
        mx, my = xs.mean(), ys.mean()
        cell_of.append(next((k for k, (x0, y0, x1, y1) in enumerate(cells) if x0 <= mx < x1 and y0 <= my < y1), -1))
    big = {}
    for i, c in enumerate(comps):
        k = cell_of[i]
        if k >= 0 and len(c) > big.get(k, 0):
            big[k] = len(c)
    keep = [cell_of[i] >= 0 and len(c) >= max(120, 0.015 * big[cell_of[i]]) for i, c in enumerate(comps)]
    rng = np.random.default_rng(1)

    def pts(pix, n):
        pix = pix if len(pix) <= n else rng.choice(pix, n, replace=False)
        return np.stack(np.divmod(pix, W), 1).astype(np.float32)

    def dist(a, b):
        return float(np.sqrt(((a[:, None, :] - b[None, :, :]) ** 2).sum(-1).min()))

    members = {k: [i for i in range(len(comps)) if keep[i] and cell_of[i] == k] for k in range(len(cells))}
    owner_of = list(cell_of)
    for i, c in enumerate(comps):
        k = cell_of[i]
        if not keep[i] or len(c) == big.get(k):
            continue   # (specks; each ship's biggest piece stays)
        mine = pts(c, 300)
        rest = [j for j in members[k] if j != i]
        if not rest:
            continue
        d_own = dist(mine, pts(np.concatenate([comps[j] for j in rest]), 6000))
        if d_own <= 12.0:
            continue
        for k2, js in members.items():
            if k2 == k or not js:
                continue
            d = dist(mine, pts(np.concatenate([comps[j] for j in js]), 6000))
            if d * 3.0 < d_own:
                owner_of[i] = k2
                d_own = d
    owner = np.full(H * W, -1, np.int32)
    for i, c in enumerate(comps):
        if keep[i]:
            owner[c] = owner_of[i]
    return owner.reshape(H, W)


def cut_one(img, cell, kind, key, tmp, threshold=FG_THRESHOLD, owner=None, index=-1):
    x0, y0, x1, y1 = cell
    margin = 50
    H, W = img.shape[:2]
    cx0, cy0, cx1, cy1 = max(0, x0 - margin), max(0, y0 - margin), min(W, x1 + margin), min(H, y1 + margin)
    crop = img[cy0:cy1, cx0:cx1].astype(np.int32)
    fg = crop.max(axis=2) > threshold
    if owner is not None:
        # The sheet's pieces that are this ship's (sheet_owners) - wherever they reach.
        own = owner == index
        ys, xs = np.nonzero(own)
        if len(ys) == 0:
            return None
        cx0, cy0 = max(0, min(cx0, xs.min() - 4)), max(0, min(cy0, ys.min() - 4))
        cx1, cy1 = min(W, max(cx1, xs.max() + 5)), min(H, max(cy1, ys.max() + 5))
        crop = img[cy0:cy1, cx0:cx1].astype(np.int32)
        mask = own[cy0:cy1, cx0:cx1].copy()
    else:
        # Keep the ship's own pieces: big components whose centre lies in the cell.
        comps = components(fg)
        if not comps:
            return None
        big = max(len(c) for c in comps)
        w = crop.shape[1]
        mask = np.zeros(fg.shape, bool)
        for c in comps:
            if len(c) < max(120, 0.015 * big):
                continue
            ys, xs = np.divmod(c, w)
            mx, my = xs.mean() + cx0, ys.mean() + cy0
            if x0 <= mx < x1 and y0 <= my < y1:
                mask.ravel()[c] = True
    # Very dark parts (grilles, shadow) fall below the threshold: close hairline
    # crevices, then fill enclosed pockets of "background" - but keep big
    # openings (the gaps in rings).
    ksize = max(3, int(round(5 * max(mask.shape) / 450.0)) | 1)
    m8 = Image.fromarray((mask * 255).astype(np.uint8))
    mask = np.asarray(m8.filter(ImageFilter.MaxFilter(ksize)).filter(ImageFilter.MinFilter(ksize))) > 127
    total = mask.sum()
    hh, ww = mask.shape
    for c in components(~mask):
        ys, xs = np.divmod(c, ww)
        if len(c) < 0.02 * total and ys.min() > 0 and xs.min() > 0 and ys.max() < hh - 1 and xs.max() < ww - 1:
            mask.ravel()[c] = True
    return save_sprite(crop, mask, kind, key)


# --- Tile sets ----------------------------------------------------------------
# A panel sheet: pieces laid out in labelled panels on a dark board.
# Panels (x0, y0, x1, y1) and the names of their pieces, left to right.
TILE_SETS = []


# --- Grid tile sheets (magenta background, one piece per cell) ---------------------------
# The Minoan palace sheet (prompt: external/prompt_templates/building__minoan_prompt_template.txt):
# 8 columns x 6 rows; row bands are found automatically. Pieces are kept at
# their sheet size (MinoanTiles scales them so a wall spans one tile edge).
WAREHOUSE_SHEET = ("minoan_warehouse_tile_sheet.png", "tile_wh_", [
    ["floor_slate","floor_slate_worn","floor_slabs","floor_loading","floor_grating","floor_tech","floor_checker","floor_concrete"],
    ["wallx_cream","wallx_slate","wallx_bull","wallx_spiral","wallx_techslot","wallx_techwindow","wallx_door","wallx_shutter"],
    ["wally_cream","wally_slate","wally_bull","wally_spiral","wally_techslot","wally_techwindow","wally_door","wally_shutter"],
    ["roof_terrace","roof_tech","roof_solar","roof_vents","roof_hatch","roof_skylight","roof_gold","roof_slate"],
    ["column_red","pillar","horns","antenna","roof_cap","tech_unit","crane","banner"],
    ["crate","crates_stack","container","supply_crates","pithos","forklift","shelves","power_cell"]])
PALACE_SHEET = ("minoan_palace_tile_sheet.png", "tile_palace_", [
    ["floor_stone", "floor_stone_b", "floor_slabs", "floor_mosaic_spiral", "floor_mosaic_dolphin", "floor_tech", "floor_courtyard", "floor_worn"],
    ["wallx_red", "wallx_stone", "wallx_bull", "wallx_leapers", "wallx_dolphins", "wallx_window", "wallx_techwindow", "wallx_door"],
    ["wally_red", "wally_stone", "wally_bull", "wally_leapers", "wally_dolphins", "wally_window", "wally_techwindow", "wally_door"],
    ["roof_terrace", "roof_tech", "roof_skylight", "roof_solar", "roof_garden", "roof_vents", "roof_gold", "roof_dark"],
    ["column_red", "column_gold", "horns", "dome", "antenna", "roof_cap", "banner", "hologram"],
    ["urn_large", "amphora", "olive_tree", "cypress", "brazier", "crates", "container", "lilies"],
])
# More pieces for the Minoan buildings (2026-11-09): floors, ground, frescoed and
# arched walls, platforms, columns, statues and fountains. Its walls are drawn one
# way only (wally_ - running up-right); the other way (wallx_) is them mirrored.
EXTRA_SHEET = ("minoan_extra_tile_sheet.png", "tile_xt_", [
    ["floor_plain", "floor_meander", "floor_sun", "floor_star", "floor_waves", "floor_lotus", "floor_ring", "floor_tech_dark"],
    ["ground_dirt", "ground_meadow", "ground_cobbles", "ground_snow", "ground_lava", "pool", "waterfall", "ground_sand"],
    ["wally_arcade", "wally_arches", "wally_banner", "wally_warrior", "wally_griffin", "wally_ship", "wally_palm", "wally_sky"],
    ["wally_slit", "wally_portal", "stairs", "ramp", "balustrade", "plinth", "cross_pad", "octagon_pad"],
    ["octagon_star", "triangle_plate", "curved_wall", "round_dais", "column_fluted", "pillar_tech", "obelisk", "sphinx"],
    ["lion", "brazier", "crystal_lamp", "crystal_shrine", "portal", "fountain", "planter_palm", "rose_arbor"],
])
MIRROR_WALLS = {"minoan_extra_tile_sheet.png"}   # sheets whose wally_ pieces also make the wallx_ ones
# The forest planet's terrain (2026-11-09): Greek ground in 1980s anime style -
# flat ground, ledge blocks with limestone cliffs, ramps and steps, water and
# shore, trees and small props (PlanetSurface builds the ground from them).
FOREST_SHEET = ("forest_terrain_tile_set.png", "tile_fo_", [
    ["grass", "grass_flowers", "grass_dry", "forest_floor", "path_straight", "path_corner", "path_paved", "limestone_ground"],
    ["block_corner", "block_left", "block_right", "block_inner", "block_left_end", "block_right_end", "block_double", "ledge_back"],
    ["ramp_ne", "ramp_nw", "ramp_sw", "ramp_se", "steps_ne", "steps_nw", "scree", "rock_slope"],
    ["sea", "shallows", "sand", "sand_grass", "shore_left", "shore_right", "shore_corner", "river"],
    ["olive", "olive_old", "cypress", "cypress_pair", "holm_oak", "aleppo_pine", "plane_tree", "olive_young"],
    ["oleander", "myrtle", "lavender", "boulder", "boulders", "column_fallen", "column_stump", "stone_wall"],
])
# The ice planet's terrain (2026-11-10): the same layout as the forest's
# (ground, ledge blocks, ramps, water and its edges), then crystals and frozen
# trees, and frozen Greek ruins.
ICE_SHEET = ("ice_terrain_tile_set.png", "tile_ic_", [
    ["snow", "snow_sparkle", "snow_drifts", "snow_packed", "path_straight", "path_corner", "path_paved", "rock_ground"],
    ["block_corner", "block_left", "block_right", "block_inner", "block_left_end", "block_right_end", "block_double", "ledge_back"],
    ["ramp_ne", "ramp_nw", "ramp_sw", "ramp_se", "steps_ne", "steps_nw", "ice_rubble", "rock_slope"],
    ["deep_ice", "frozen_lake", "snow_plain", "snow_ice", "shore_left", "shore_right", "shore_corner", "stream"],
    ["crystals", "crystal_spire", "crystal_sprout", "ice_rock", "frost_bush", "dead_tree", "snow_pine", "frost_shrub"],
    ["column_stump", "column", "column_fallen", "capital", "arch", "colonnade", "ruined_steps", "ruined_wall"],
])
# The volcanic planet's terrain (2026-11-10; prompt:
# external/prompt_templates/terrain__volcanic_prompt_template.txt): the ice
# sheet's layout - basalt, ash and sulphur ground, basalt ledge blocks, magma
# for water, volcanic features, scorched Greek ruins.
VOLCANIC_SHEET = ("volcanic_terrain_tile_set.png", "tile_vo_", [
    ["basalt", "basalt_cracks", "ash", "sulphur", "path_straight", "path_corner", "path_paved", "rock_ground"],
    ["block_corner", "block_left", "block_right", "block_inner", "block_left_end", "block_right_end", "block_double", "ledge_back"],
    ["ramp_ne", "ramp_nw", "ramp_sw", "ramp_se", "steps_ne", "steps_nw", "rubble", "rock_slope"],
    ["magma_lake", "magma", "ash_flat", "pahoehoe", "shore_left", "shore_right", "shore_corner", "lava_river"],
    ["fumarole", "obsidian_spire", "magma_vent", "basalt_boulder", "sulphur_crystals", "charred_tree", "basalt_columns", "lava_rock"],
    ["column_stump", "column", "column_fallen", "capital", "arch", "colonnade", "ruined_steps", "ruined_wall"],
])
# The forest planet's wildlife (2026-11-10): 12 animals, 4 poses each (stand,
# two walk / flight frames, a special pose), all facing down-left; two
# animals a row (SurfaceProps.Creature). Their painted purple contact shadows
# are background too (the game draws its own).
FOREST_CREATURES = ("forest_creatures.png", "creature_fo_", [
    [a + "_" + p for a in pair for p in ("stand", "move_a", "move_b", "act")]
    for pair in [("goat", "sheep"), ("boar", "deer"), ("wolf", "fox"), ("hare", "tortoise"), ("owl", "eagle"), ("donkey", "snake")]])
# More of the forest planet's wildlife (2026-11-10): alien beasts, same layout.
FOREST_CREATURES_2 = ("forest_creatures_2.png", "creature_fo_", [
    [a + "_" + p for a in pair for p in ("stand", "move_a", "move_b", "act")]
    for pair in [("tigrokeros", "mykelephas"), ("harpyx", "selas"), ("hoplorhino", "aeromanta"),
                 ("toad", "pangolin"), ("mantis", "capslug"), ("drakaina", "jelly")]])
# ... and its giant insects (2026-11-10), same layout.
FOREST_CREATURES_3 = ("forest_creatures_3.png", "creature_fo_", [
    [a + "_" + p for a in pair for p in ("stand", "move_a", "move_b", "act")]
    for pair in [("scarab", "moth"), ("phasma", "pillbug"), ("spider", "dragonfly"),
                 ("centipede", "leafbug"), ("rhinobeetle", "firefly"), ("mykospider", "grub")]])
# The ice planets' wildlife (2026-11-10): crystal beasts, same layout.
ICE_CREATURES = ("ice_creatures.png", "creature_ic_", [
    [a + "_" + p for a in pair for p in ("stand", "move_a", "move_b", "act")]
    for pair in [("icestag", "frostbeast"), ("frostwolf", "icehare"), ("strider", "scuttler"),
                 ("frostray", "shardcrawler"), ("bubblespider", "starcrawler"), ("icewyrm", "wisp")]])
# The volcanic planet's wildlife (2026-11-11; prompt:
# external/prompt_templates/creatures__volcanic_prompt_template.txt): big, alien
# predators, the ice sheet's layout.
VOLCANIC_CREATURES = ("volcanic_creatures.png", "creature_vo_", [
    [a + "_" + p for a in pair for p in ("stand", "move_a", "move_b", "act")]
    for pair in [("magmabehemoth", "cinderstalker"), ("obsidianmantis", "bloater"), ("lavaserpent", "ventcrab"),
                 ("pyrohound", "ashwraith"), ("basaltgolem", "emberqueen"), ("cratermaw", "fumaroletitan")]])
## Grid sheets whose pieces aren't on even columns: assigned left to right.
ORDERED_SHEETS = set()
SHADOW_SHEETS = {"forest_creatures.png", "forest_creatures_2.png", "forest_creatures_3.png", "ice_creatures.png", "volcanic_creatures.png"}
# The gas giants' terrain (2026-11-10): metal platforms hovering in the clouds -
# the forest sheet's layout (deck tiles, platform blocks with their undersides,
# ramps and stairs, open sky and railed edges, tall structures, small props).
# The sky cells (faint vapour) aren't saved: the set draws nothing for open sky.
GAS_SHEET = ("gas_giant_platform_tile_set.png", "tile_gg_", [
    ["deck", "deck_lit", "deck_rusty", "deck_solar", "deck_stripes", "deck_stripes_corner", "deck_grating", "deck_heavy"],
    ["block_corner", "block_left", "block_right", "block_inner", "block_left_end", "block_right_end", "block_double", "ledge_back"],
    ["ramp_ne", "ramp_nw", "ramp_sw", "ramp_se", "steps_ne", "steps_nw", "scrap_heap", "bulkhead"],
    ["-sky", "-sky_wisps", "edge_hazard", "edge_rings", "rail_left", "rail_right", "rail_corner", "bridge"],
    ["antenna", "radar", "vent_stack", "fuel_tank", "crane", "cooling_tower", "beacon", "pipes"],
    ["containers", "crate", "barrels", "machinery", "container_fallen", "railing", "lamp_post", "robot"],
])
# A second take on the same prompt (its row 2 is full blocks with every deck
# on top, not the edge variants): more deck tiles and props, "_b".
GAS_SHEET_2 = ("gas_giant_platform_tile_set_2.png", "tile_gg_", [
    ["deck_b", "deck_lit_b", "deck_rusty_b", "deck_solar_b", "deck_stripes_b", "deck_stripes_corner_b", "deck_grating_b", "deck_heavy_b"],
    ["cube_deck", "cube_lit", "cube_rusty", "cube_solar", "cube_stripes", "cube_stripes_corner", "cube_grating", "cube_heavy"],
    ["ramp_ne_b", "ramp_nw_b", "ramp_sw_b", "ramp_se_b", "steps_ne_b", "steps_nw_b", "scrap_heap_b", "bulkhead_b"],
    ["-sky_b", "-sky_wisps_b", "edge_hazard_b", "edge_rings_b", "rail_left_b", "rail_right_b", "rail_corner_b", "bridge_b"],
    ["antenna_b", "radar_b", "vent_stack_b", "fuel_tank_b", "crane_b", "cooling_tower_b", "beacon_b", "pipes_b"],
    ["containers_b", "crate_b", "barrels_b", "machinery_b", "container_fallen_b", "railing_b", "lamp_post_b", "robot_b"],
])
# The gas giants' storms (2026-11-10), drifting over the cloud bands (GasSky;
# the bands themselves are cut by tools/gas_sky.py): 4 columns x 3 rows.
STORM_SHEET = ("gas_giant_storms.png", "sky_gg_", [
    ["storm_red", "storm_white", "storm_salmon", "storm_brown"],
    ["eddy_cream", "eddy_rust", "oval_white", "hotspot"],
    ["festoon_cream", "festoon_brown", "ovals_three", "filament"],
])
GRID_SHEETS = [PALACE_SHEET, WAREHOUSE_SHEET, EXTRA_SHEET, FOREST_SHEET, ICE_SHEET, VOLCANIC_SHEET, GAS_SHEET, GAS_SHEET_2, STORM_SHEET, FOREST_CREATURES, FOREST_CREATURES_2,
               FOREST_CREATURES_3, ICE_CREATURES, VOLCANIC_CREATURES]
# Glow effects on black (alpha from brightness): 8 x 2 cells.
FX_SHEETS = [
    # The Minoan androids' weapons (2026-11-10): 6 x 3 cells - the bow's arrows, the
    # rifle's bolts, the labrys's slashes.
    ("minoan_android_fx.png", "fx_android_", [
        ["arrow", "arrow_trail", "arrow_stuck", "bow_flash", "arrow_impact", "arrow_sparks"],
        ["bolt", "bolt_heavy", "muzzle", "muzzle_small", "bolt_impact", "bolt_sparks"],
        ["slash", "slash_wide", "shockwave", "debris", "axe_sparks", "dust"]]),
    ("minoan_fx_laser_rifle.png", "fx_rifle_", [
        ["bolt","bolt_heavy","trail","muzzle","muzzle_small","steam","spark","casing"],
        ["impact","impact_big","impact_metal","shield_ripple","sparks","charge","flare","smoke"]]),
]

# The jump gates in space (2026-11-10): one sheet on black, not a grid - each
# piece is cut from its box [x0, y0, x1, y1]. "solid" pieces (the ring, idle and
# powered; the vortex frames) get a brightness mask with small dark holes filled
# (the ring's big opening stays clear); "glow" pieces get alpha from brightness.
GATE_SHEET = ("stargate_1.png", "gate_", [
    ("ring", "solid", [170, 0, 750, 475]), ("ring_lit", "solid", [800, 0, 1370, 475]),
    ("vortex1", "solid", [230, 465, 570, 785]), ("vortex2", "solid", [595, 465, 930, 785]), ("vortex3", "solid", [960, 465, 1300, 785]),
    ("emitter", "glow", [260, 790, 440, 1024]), ("burst", "glow", [500, 780, 1000, 1000]), ("sparkle", "glow", [1050, 790, 1300, 1000]),
])


def extract_boxes(img, pieces):
    """[(name, RGBA image)] for GATE_SHEET-style sheets (see there)."""
    out = []
    for nm, mode, (x0, y0, x1, y1) in pieces:
        cell = img[y0:y1, x0:x1].astype(np.float32)
        bright = cell.max(axis=2)
        if mode == "glow":
            a = np.clip((bright - 10.0) / 245.0, 0.0, 1.0)
        else:
            m = bright > 16
            keep = np.zeros(m.shape, bool)
            comps = components(m)
            big = max(len(c) for c in comps)
            for c in comps:
                if len(c) > 0.01 * big:
                    keep.ravel()[c] = True
            for c in components(~keep):   # dark panel lines inside the hull: holes to fill
                if len(c) < 3000:
                    keep.ravel()[c] = True
            core = np.asarray(Image.fromarray((keep * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(3))) > 127
            a = np.where(core, 1.0, np.where(keep, 0.6, 0.0))
            # Glow painted on the black (the powered emitters' halo): dim cyan,
            # not grey hull - faded out by its brightness, not kept as dark blots.
            halo = (cell[:, :, 2] - cell[:, :, 0] > 15) & (bright < 120)
            a = np.where(halo, np.minimum(a, np.clip((bright - 16.0) / 104.0, 0.0, 1.0)), a)
            cell = np.where(halo[:, :, None], cell / np.maximum(a[:, :, None], 0.05), cell).clip(0, 255)
        ys, xs = np.nonzero(a > 0.03)
        by0, by1, bx0, bx1 = max(0, ys.min() - 2), ys.max() + 3, max(0, xs.min() - 2), xs.max() + 3
        cell, a = cell[by0:by1, bx0:bx1], a[by0:by1, bx0:bx1]
        rgb = cell if mode == "solid" else np.where(a[:, :, None] > 0.004, cell / np.maximum(a[:, :, None], 0.004), 0).clip(0, 255)
        out.append((nm, Image.fromarray(np.dstack([rgb, a * 255]).astype(np.uint8), "RGBA")))
    return out


def extract_fx(img, names):
    """Glowing effects on black: [(name, RGBA image)], alpha = brightness, colour un-premultiplied."""
    h, w = img.shape[:2]
    out = []
    rows = len(names)
    for r, row in enumerate(names):
        for c, nm in enumerate(row):
            x0, x1 = int(c * w / len(row)), int((c + 1) * w / len(row))
            y0, y1 = int(r * h / rows), int((r + 1) * h / rows)
            cell = img[y0:y1, x0:x1].astype(np.float32)
            a = cell.max(axis=2)
            a = np.clip((a - 10.0) / 245.0, 0.0, 1.0)   # the board's near-black -> clear
            ys, xs = np.nonzero(a > 0.03)
            if len(ys) == 0:
                continue
            by0, by1, bx0, bx1 = max(0, ys.min() - 2), ys.max() + 3, max(0, xs.min() - 2), xs.max() + 3
            cell, a = cell[by0:by1, bx0:bx1], a[by0:by1, bx0:bx1]
            rgb = np.where(a[:, :, None] > 0.004, cell / np.maximum(a[:, :, None], 0.004), 0).clip(0, 255)
            out.append((nm, Image.fromarray(np.dstack([rgb, a * 255]).astype(np.uint8), "RGBA")))
    return out


def magenta_mask(rgb, shadows=False):
    """Background = pure-ish magenta (#FF00FF and its anti-aliased tints);
    with `shadows`, also the darker purple of shadows painted on it."""
    r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    if shadows:
        # (a shadow is magenta darkened: green stays near zero - pink and purple art keeps more)
        return (r - g > 40) & (b - g > 40) & (np.abs(r - b) < 70) & (g < 0.25 * np.minimum(r, b) + 8)
    return (r - g > 110) & (b - g > 110)


def extract_grid(img, names, shadows=False, ordered=False):
    """Pieces of a magenta grid sheet: [(name, crop, mask)] - rows by the
    background bands between them, 8 equal columns per row."""
    rgb = img.astype(np.int32)
    fg = ~magenta_mask(rgb, shadows)
    rows_occ = fg.sum(axis=1) > 3
    bands, start = [], None
    for y, v in enumerate(rows_occ):
        if v and start is None:
            start = y
        if not v and start is not None:
            if y - start > 20:
                bands.append((start, y))
            start = None
    if start is not None:
        bands.append((start, len(rows_occ)))
    # Rows drawn touching (a tall vase reaching the row above): fewer bands than
    # rows - split the tallest band at its emptiest line until they match.
    occ_rows = fg.sum(axis=1)
    split_at = set()
    while len(bands) < len(names):
        i = max(range(len(bands)), key=lambda k: bands[k][1] - bands[k][0])
        y0, y1 = bands[i]
        m0, m1 = y0 + (y1 - y0) // 4, y1 - (y1 - y0) // 4
        cut = m0 + int(np.argmin(occ_rows[m0:m1]))
        bands[i:i + 1] = [(y0, cut), (cut + 1, y1)]
        split_at.add(cut)
    out = []
    W = rgb.shape[1]
    for (y0, y1), row in zip(bands, names):
        # Each shape in the row goes to the column holding its centre (pieces
        # may overhang their cell: a long rifle reaches into its neighbour).
        ya, yb = max(0, y0 - 2), y1 + 2
        # (a band split from its neighbour: whole pieces, those centred in it)
        if y0 - 1 in split_at or y1 in split_at:
            ya, yb = max(0, y0 - (y1 - y0) // 2), min(fg.shape[0], y1 + (y1 - y0) // 2)
        band = fg[ya:yb].copy()
        if y0 - 1 in split_at or y1 in split_at:
            for cc in components(band):
                cy = (np.asarray(cc) // band.shape[1]).mean() + ya
                if not (y0 <= cy < y1):
                    band.ravel()[cc] = False
        bw = band.shape[1]
        n = len(row)
        # Neighbours drawn touching (floor tiles corner to corner) are one shape:
        # a shape over more than one cell's centre is split at the emptiest
        # column near each cell boundary between.
        occ = band.sum(axis=0)
        win = max(2, W // (4 * n))
        splits = [k * W // n - win + int(np.argmin(occ[k * W // n - win:k * W // n + win])) for k in range(1, n)]
        comps = []
        for cc in components(band):
            xs = np.asarray(cc) % bw
            centres = [c for c in range(n) if xs.min() <= (c + 0.5) * W / n <= xs.max()]
            if len(centres) <= 1:
                comps.append(cc)
                continue
            col = np.searchsorted(splits, xs, side="right")
            for c in np.unique(col):
                comps.append(np.asarray(cc)[col == c])
        big = max(len(cc) for cc in comps) if comps else 1
        owner = {}
        for cc in comps:
            if len(cc) < 0.004 * big and len(cc) < 40:
                continue
            cx = (np.asarray(cc) % bw).mean()
            owner.setdefault(min(len(row) - 1, int(cx * len(row) / W)), []).append(cc)
        if ordered:
            # Not on an even grid: the pieces left to right (shapes overlapping
            # sideways - a rifle and its steam - are one piece), one per name.
            spans = []
            for cc in comps:
                if len(cc) < 0.004 * big and len(cc) < 40:
                    continue
                xs = np.asarray(cc) % bw
                spans.append([xs.min(), xs.max(), [cc]])
            spans.sort(key=lambda t: t[0])
            pieces = []
            for sp in spans:
                if pieces and sp[0] <= pieces[-1][1] + 6:
                    pieces[-1][1] = max(pieces[-1][1], sp[1])
                    pieces[-1][2] += sp[2]
                else:
                    pieces.append(sp)
            if len(pieces) == len(row):
                owner = {c: pieces[c][2] for c in range(len(row))}
            else:
                print("  (row %s: %d pieces for %d names - by columns)" % (row[0], len(pieces), len(row)))
        for c, nm in enumerate(row):
            mine = owner.get(c, [])
            if not mine:
                continue
            biggest = max(len(cc) for cc in mine)
            keep_b = np.zeros(band.shape, bool)
            for cc in mine:
                if len(cc) > 0.02 * biggest:
                    keep_b.ravel()[cc] = True
            xs = np.nonzero(keep_b.any(0))[0]
            x0, x1 = xs.min(), xs.max() + 1
            crop = rgb[ya:yb, x0:x1].copy()
            keep = keep_b[:, x0:x1]
            # Despill: magenta fringe (red and blue raised together) at the edges.
            edge = keep & ~(np.asarray(Image.fromarray((keep * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(5))) > 127)
            spill = np.minimum(crop[:, :, 0], crop[:, :, 2]) - crop[:, :, 1]
            fix = edge & (spill > 30)
            for ch in (0, 2):
                crop[:, :, ch] = np.where(fix, crop[:, :, ch] - spill * 0.6, crop[:, :, ch])
            out.append((nm, crop.clip(0, 255), keep))
    return out


def save_sprite(crop, mask, kind, key):
    """Writes a cut-out as data/sprites/<key>.png: cropped to the figure, the
    green board's colour cast removed, a soft 1-px alpha edge. Ships are
    turned nose-up (they point right on the sheets); tile pieces are stored at
    2x (MinoanTiles assembles them at that resolution)."""
    ys, xs = np.nonzero(mask)
    if len(ys) == 0:
        return 0
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    rgb = crop[y0:y1, x0:x1].astype(np.int32)
    m = mask[y0:y1, x0:x1]
    # Despill: on green boards the edges carry green; never greener than red/blue allow.
    g_lim = np.maximum(rgb[:, :, 0], rgb[:, :, 2]) + 8
    green_board = (rgb[~m][:, 1] - np.maximum(rgb[~m][:, 0], rgb[~m][:, 2]) > 40).mean() > 0.5 if (~m).any() else False
    if green_board:
        rgb[:, :, 1] = np.minimum(rgb[:, :, 1], g_lim)
    # Soft edge: solid inside, the outline pixel half-covered, nothing outside.
    core = np.asarray(Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(3))) > 127
    alpha = np.where(core, 255, np.where(m, 150, 0))
    im = Image.fromarray(np.dstack([rgb.clip(0, 255), alpha.clip(0, 255)]).astype(np.uint8), "RGBA")
    if kind == "ship":
        im = im.rotate(90, expand=True)
        if max(im.size) > 512:
            k = 512 / max(im.size)
            im = im.resize((round(im.width * k), round(im.height * k)), Image.LANCZOS)
    elif kind == "station":
        if max(im.size) > 640:
            k = 640 / max(im.size)
            im = im.resize((round(im.width * k), round(im.height * k)), Image.LANCZOS)
    elif kind == "tile":
        im = im.resize((im.width * 2, im.height * 2), Image.LANCZOS)
    # kind "piece": kept at its sheet size
    os.makedirs(OUT, exist_ok=True)
    im.save(os.path.join(OUT, key + ".png"))
    return im.size


def extract_tiles(img, panels):
    """Cut every piece out of the panels: [(name, crop, mask)]."""
    out = []
    for rect, names in panels:
        x0, y0, x1, y1 = rect
        crop = img[y0:y1, x0:x1].astype(np.int32)
        # Board colour: the median of the panel's border pixels.
        border = np.concatenate([crop[0], crop[-1], crop[:, 0], crop[:, -1]])
        bg = np.median(border, axis=0)
        fg = np.sqrt(((crop - bg) ** 2).sum(axis=2)) > 34
        if bg[1] > bg[0] + 60 and bg[1] > bg[2] + 60:
            # Green board: glow fading into it (dark green) is background too.
            gx = crop[:, :, 1] - np.maximum(crop[:, :, 0], crop[:, :, 2])
            fg &= ~((gx > 12) & (crop[:, :, 1] < 170) & (crop[:, :, 2] < crop[:, :, 1] * 0.6))
        # Merge pieces that nearly touch (an antenna pair, a pot and its plant).
        near = fg
        if names is None or names in ("prop", "decor"):   # decor only: building blocks that touch must stay apart
            near = np.asarray(Image.fromarray((fg * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(5))) > 127
        comps = [c for c in components(near) if len(c) > 250]
        w = crop.shape[1]
        boxes = []
        for c in comps:
            ys, xs = np.divmod(c, w)
            if xs.max() - xs.min() < 12 or ys.max() - ys.min() < 12:
                continue   # the panel's border line, not a piece
            boxes.append((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1, c))
        # Reading order: rows, then left to right.
        if isinstance(names, str):
            boxes.sort(key=lambda b: (int(((b[1] + b[3]) / 2) // 70), b[0]))
        else:
            boxes.sort(key=lambda b: (0 if names is not None else int((b[1] + b[3]) / 2 > (y1 - y0) * 0.55), b[0]))
        for i, (bx0, by0, bx1, by1, c) in enumerate(boxes):
            m = np.zeros(fg.shape, bool)
            m.ravel()[c] = True
            m &= fg
            m = np.asarray(Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.MinFilter(3))) > 127
            nm = "%s_%d" % (names, i) if isinstance(names, str) else names[i] if names is not None and i < len(names) else "piece_%d_%d" % (y0, i)
            out.append((nm, crop[by0:by1, bx0:bx1], m[by0:by1, bx0:bx1]))
    return out


# --- NPC turnaround sheets ----------------------------------------------------------
# (sheet, key prefix, turnaround strip (x0, y0, x1, y1), view names left to right)
V8 = ["front", "front34", "side", "back34", "back", "back34b", "oppside", "opp34"]
# The citizens' character sheets: only their head-details panels are cut
# (the conversation portraits). (sheet, key prefix, turnaround strip
# (x0, y0, x1, y1), views left to right, head-details panel (x0, y0, x1, y1)).
NPC_SHEETS = [
    ("minoan_npc_triceratops_gun.png", "npc_minoan_gunner_", (390, 28, 1525, 287), V8, (406, 412, 760, 746)),
    ("minoan_npc_triceratops_female_bow.png", "npc_minoan_archer_", (505, 25, 1528, 285), V8, (465, 360, 770, 694)),
    ("minoan_npc_android.png", "npc_minoan_android_", (400, 15, 1525, 255), V8, (470, 372, 958, 703)),
]


def find_figures(img, strip, n):
    """Column windows of the n figures in a turnaround strip (gaps between
    them are the widest runs of background)."""
    x0, y0, x1, y1 = strip[:4]
    a = img[y0:y1, x0:x1].astype(np.int32)
    bg = np.median(a[:3].reshape(-1, 3), axis=0)
    fg = np.sqrt(((a - bg) ** 2).sum(axis=2)) > 40
    if bg[1] > bg[0] + 60 and bg[1] > bg[2] + 60:
        fg &= ~(a[:, :, 1] - np.maximum(a[:, :, 0], a[:, :, 2]) > 18)
    col = fg.sum(axis=0) > 4
    runs, start = [], None
    for x, v in enumerate(col):
        if v and start is None:
            start = x
        if not v and start is not None:
            runs.append([start, x]); start = None
    if start is not None:
        runs.append([start, len(col)])
    runs = [r for r in runs if r[1] - r[0] > 3]
    # Merge across the narrowest gaps until n figures remain (horns / capes
    # can leave small gaps inside one figure).
    while len(runs) > n:
        gaps = [runs[i + 1][0] - runs[i][1] for i in range(len(runs) - 1)]
        k = int(np.argmin(gaps))
        runs[k] = [runs[k][0], runs[k + 1][1]]
        del runs[k + 1]
    if len(runs) < n:
        # Figures touch (guns, bows): split evenly.
        cw = (x1 - x0) / n
        return [(int(x0 + i * cw), int(x0 + (i + 1) * cw)) for i in range(n)]
    out = []
    for i, (a0, a1) in enumerate(runs):
        lo = (runs[i - 1][1] + a0) // 2 if i else max(0, a0 - 12)
        hi = (a1 + runs[i + 1][0]) // 2 if i < len(runs) - 1 else min(x1 - x0, a1 + 12)
        out.append((x0 + lo, x0 + hi))
    return out


def extract_head(img, panel):
    """The head-details picture of a sheet, cut off its green panel: (crop, mask)."""
    x0, y0, x1, y1 = panel
    crop = img[y0:y1, x0:x1].astype(np.int32)
    flat = crop.reshape(-1, 3)
    greens = flat[(flat[:, 1] > flat[:, 0] + 60) & (flat[:, 1] > flat[:, 2] + 60)]
    bg = np.median(greens, axis=0) if len(greens) > 100 else np.median(np.concatenate([crop[:, -3:].reshape(-1, 3), crop[-3:].reshape(-1, 3)]), axis=0)
    raw = np.sqrt(((crop - bg) ** 2).sum(axis=2)) > 30
    if bg[1] > bg[0] + 60 and bg[1] > bg[2] + 60:
        raw &= ~(crop[:, :, 1] - np.maximum(crop[:, :, 0], crop[:, :, 2]) > 12)
        crop[:, :, 1] = np.minimum(crop[:, :, 1], np.maximum(crop[:, :, 0], crop[:, :, 2]) + 8)   # despill
    # Panel frame lines / title letters: drop thin pieces and small specks.
    raw = np.asarray(Image.fromarray((raw * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(3)).filter(ImageFilter.MaxFilter(3))) > 127
    comps = components(raw)
    big = max(comps, key=len)
    m = np.zeros(raw.shape, bool)
    m.ravel()[big] = True
    h, w = m.shape
    for c in components(~m):
        ys, xs = np.divmod(c, w)
        if ys.min() > 0 and xs.min() > 0 and ys.max() < h - 1 and xs.max() < w - 1 and len(c) < 400:
            m.ravel()[c] = True
    return crop, m


def extract_npc_views(img, strip, views):
    """Cuts each figure of a turnaround strip off the board and its pedestal:
    the body is the closed silhouette of everything that differs from the
    board (dark armour included, holes filled); the feet zone is rebuilt by
    _clean_feet from a colour model of the pedestal."""
    x0, y0, x1, y1 = strip[:4]
    windows = strip[4] if len(strip) > 4 and strip[4] else find_figures(img, strip, len(views))
    ped_top = strip[5] if len(strip) > 5 else 0.72   # where the pedestal starts (fraction of the height)
    out = []
    cw = (x1 - x0) / len(views)
    bg = np.median(img[y0:y0 + 4, x0:x1].reshape(-1, 3).astype(np.int32), axis=0)   # the board
    for i, name in enumerate(views):
        # A window wider than the slot: capes and horns reach past it; the
        # figure is the piece nearest the slot's centre.
        sx0, sx1 = windows[i] if windows else (int(x0 + i * cw), int(x0 + (i + 1) * cw))
        sw = sx1 - sx0
        pad = int(sw * 0.3)
        wx0 = max(0, sx0 - pad)
        wx1 = min(img.shape[1], sx1 + pad)
        crop = img[y0:y1, wx0:wx1].astype(np.int32)
        h, w = crop.shape[:2]
        centre = (sx0 + sx1) / 2.0 - wx0
        raw = np.sqrt(((crop - bg) ** 2).sum(axis=2)) > 20
        if bg[1] > bg[0] + 60 and bg[1] > bg[2] + 60:
            # A green-screen board (shades vary): anything clearly green is background.
            raw &= ~(crop[:, :, 1] - np.maximum(crop[:, :, 0], crop[:, :, 2]) > 12)
        zone = int(h * max(0.5, ped_top - 0.08))
        # Body: close the outline, fill what it encloses (above the feet zone).
        body = raw.copy()
        body[zone:] = False
        body = np.asarray(Image.fromarray((body * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(7)).filter(ImageFilter.MinFilter(7))) > 127
        rawf = raw.ravel()
        for c in components(~body):
            ys, xs = np.divmod(c, w)
            # Enclosed: fill - unless it's the board showing through (inside a
            # drawn bow, between arm and body): mostly background-coloured.
            if ys.min() > 0 and xs.min() > 0 and ys.max() < zone - 1 and xs.max() < w - 1 and rawf[c].mean() > 0.35:
                body.ravel()[c] = True
        # Stay within a pixel of what differs from the board (no halo / filled notches).
        near = np.asarray(Image.fromarray((raw * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3))) > 127
        inner = np.asarray(Image.fromarray((body * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(5))) > 127
        body &= near | inner
        # The figure's piece: the biggest one near the slot centre (plus pieces
        # mostly inside the slot, like a horn tip).
        comps = components(body)
        def score(c):
            xs = c % w
            return len(c) - 40.0 * abs(xs.mean() - centre)
        main = max(comps, key=score)
        m = np.zeros((h, w), bool)
        m.ravel()[main] = True
        for c in comps:
            ys, xs = np.divmod(c, w)
            thin = min(np.ptp(xs), np.ptp(ys)) < 6   # a panel border line, not a horn tip
            if c is not main and not thin and len(c) > 0.01 * len(main) and sx0 - wx0 <= xs.mean() <= sx1 - wx0:
                m.ravel()[c] = True
        m = _clean_feet(crop, m, bg, ped_top, sx0 - wx0, sx1 - wx0)
        if bg[1] > bg[0] + 60 and bg[1] > bg[2] + 60:
            # Despill (after the cut-out: it darkens the green board).
            crop = crop.copy()
            crop[:, :, 1] = np.minimum(crop[:, :, 1], np.maximum(crop[:, :, 0], crop[:, :, 2]) + 8)
        out.append((name, crop, m))
    return out


def _clean_feet(crop, m, bg, ped_top, slot0, slot1):
    """Rebuilds the feet / lower legs from the pixels, using a colour model of
    this sheet's pedestal: sampled from the platform's outer edges (no feet
    there), then only pixels close to it are dropped - toes, gold greaves and
    dark armour stay; the platform, its cast shadow and the board seen
    between the legs go."""
    h, w = m.shape
    crop = crop.astype(np.int32)
    zone = int(h * max(0.5, ped_top - 0.08))          # feet zone starts here
    diff = np.sqrt(((crop - bg) ** 2).sum(axis=2))
    raw = diff > 20
    if bg[1] > bg[0] + 60 and bg[1] > bg[2] + 60:
        raw &= ~(crop[:, :, 1] - np.maximum(crop[:, :, 0], crop[:, :, 2]) > 12)
    # Pedestal samples: lower rows, outer quarters of the figure's slot.
    sw = slot1 - slot0
    rows = slice(int(h * (ped_top + 0.06)), h)
    cols = np.zeros(w, bool)
    cols[max(0, slot0):max(0, slot0 + sw // 4)] = True
    cols[min(w, slot1 - sw // 4):min(w, slot1)] = True
    samp = crop[rows][:, cols][raw[rows][:, cols]]
    if len(samp) < 30:
        # No pedestal on this sheet: the feet are simply what isn't background,
        # attached to the body.
        out = m.copy()
        out[zone:] = raw[zone:]
        comps = components(out)
        big = max(comps, key=len)
        keep = np.zeros(out.shape, bool)
        keep.ravel()[big] = True
        for c in components(~keep):
            ys, xs = np.divmod(c, w)
            if ys.min() > 0 and xs.min() > 0 and ys.max() < h - 1 and xs.max() < w - 1 and len(c) < 120:
                keep.ravel()[c] = True
        return keep
    # A small palette of the pedestal (median cut), plus the board colour.
    q = Image.fromarray(samp.reshape(-1, 1, 3).astype(np.uint8)).quantize(colors=8, method=Image.Quantize.MEDIANCUT)
    pal = np.array(q.getpalette()[:24]).reshape(-1, 3)
    pal = np.vstack([pal, bg.reshape(1, 3)])
    low = crop[zone:]
    dist = np.sqrt(((low[:, :, None, :] - pal[None, None, :, :]) ** 2).sum(axis=3)).min(axis=2)
    mx, mn = low.max(axis=2), low.min(axis=2)
    sat = mx - mn
    pedlike = (dist < 26) & (sat < 70)
    # The pedestal's cast shadow / board between the legs: very dark, unsaturated,
    # connected to pedestal-like pixels.
    dark = (mx < 48) & (sat < 28)
    lh = h - zone
    # The soles: the lowest rows with clearly warm, saturated pixels (tan feet,
    # gold sandals). Above a thin band at sole level only the true background
    # goes (dark armour looks like the pedestal's shadowed sides); in the band
    # the pedestal model applies; below the soles everything goes.
    solid_warm = (low[:, :, 0] > low[:, :, 2] + 35) & (low[:, :, 1] > low[:, :, 2] + 15) & (mx > 120) & (sat > 70)
    wy = np.nonzero(solid_warm.sum(axis=1) >= 3)[0]
    sole = int(wy.max()) if len(wy) else lh - 1
    band = max(0, sole - int(h * 0.13))
    ry = np.arange(lh)[:, None]
    shade = (sat < 38) & (mx < 135)    # the platform's shaded top / cast shadow
    # Dark armour has the coloured ankle band / foot below it in its column;
    # the platform's shadow has nothing coloured below it.
    colourful = (sat > 60) & (mx > 100)
    lowest = np.full(w, -1)
    for x in range(w):
        ys = np.nonzero(colourful[:, x])[0]
        if len(ys):
            lowest[x] = ys.max()
    below_foot = ry > (lowest[None, :] - 1)
    # Grey bits not touching anything coloured (platform edge lines, shadow
    # dashes beside the feet) go too.
    near_col = np.asarray(Image.fromarray((colourful * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(9))) > 127
    below_foot |= ~near_col
    removable = ~raw[zone:] | ((pedlike | dark | shade) & (ry >= band) & below_foot) | (ry > sole + 2)
    # Flood the removable pixels from the bottom edge and the zone's sides.
    gone = np.zeros((lh, w), bool)
    qd = deque()
    for x in range(w):
        if removable[lh - 1, x]:
            gone[lh - 1, x] = True
            qd.append((lh - 1, x))
    for y in range(lh):
        for x in (0, w - 1):
            if removable[y, x] and not gone[y, x]:
                gone[y, x] = True
                qd.append((y, x))
    # (pedestal-like pixels anywhere in the zone also seed it)
    for y, x in zip(*np.nonzero((pedlike | shade) & (ry >= band))):
        if not gone[y, x]:
            gone[y, x] = True
            qd.append((y, x))
    while qd:
        y, x = qd.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            yy, xx = y + dy, x + dx
            if 0 <= yy < lh and 0 <= xx < w and not gone[yy, xx] and removable[yy, xx]:
                gone[yy, xx] = True
                qd.append((yy, xx))
    feet = raw[zone:] & ~gone
    # Unsaturated pixels in the sole band far from anything coloured: platform
    # edge lines and shadow dashes, whatever their exact grey.
    feet &= ~((ry >= band) & ~near_col & (sat < 70))
    # Tidy: close hairline cracks inside the feet, drop specks.
    feet = np.asarray(Image.fromarray((feet * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.MinFilter(3))) > 127
    feet &= ~gone | (feet & ~removable)
    out = m.copy()
    out[zone:] = feet
    # Keep what's connected to the body; fill only small holes in the feet zone
    # (the gap between the legs stays open).
    comps = components(out)
    big = max(comps, key=len)
    keep = np.zeros(out.shape, bool)
    for c in comps:
        ys = c // w
        if c is big or (len(c) > 25 and ys.min() < zone):
            keep.ravel()[c] = True
    rawf = raw.ravel()
    for c in components(~keep):
        ys, xs = np.divmod(c, w)
        if ys.min() > 0 and xs.min() > 0 and ys.max() < h - 1 and xs.max() < w - 1 and (len(c) < 120 or ys.max() < zone) \
                and (len(c) < 60 or rawf[c].mean() > 0.35):   # (board seen through a bow / arm stays open)
            keep.ravel()[c] = True
    return keep


def main():
    args = sys.argv[1:]
    only = None
    if "--only" in args:
        only = args[args.index("--only") + 1]
        args = [a for a in args if a not in ("--only", only)]
    flt = args[0] if args else ""
    if "--npc-preview" in sys.argv:
        fname, prefix, strip, views, _head = next((t for t in NPC_SHEETS if flt and flt in t[0]), NPC_SHEETS[0])
        img = np.asarray(Image.open(os.path.join(IMAGES, fname)).convert("RGB"))
        figs = extract_npc_views(img, strip, views)
        sheet = Image.new("RGB", (280 * len(figs), 640), (60, 120, 60))
        for i, (nm, crop, m) in enumerate(figs):
            ys, xs = np.nonzero(m)
            cut = np.where(m[:, :, None], crop, (60, 120, 60)).astype(np.uint8)[:, xs.min():xs.max() + 1]
            ci = Image.fromarray(cut)
            sheet.paste(ci.resize((ci.width * 2, ci.height * 2)), (i * 280, 0))
        sheet.save([a for a in sys.argv[1:] if a.endswith(".png")][0])
        return
    if "--tiles-preview" in sys.argv:
        ts = next((t for t in TILE_SETS if flt and flt in t[0]), None)
        if ts is None:
            print("no tile set matches", flt)
            return
        img = np.asarray(Image.open(os.path.join(IMAGES, ts[0])).convert("RGB"))
        pieces = extract_tiles(img, ts[2])
        sheet = Image.new("RGB", (1600, 1200), (40, 40, 40))
        from PIL import ImageDraw
        d = ImageDraw.Draw(sheet)
        x = y = 0
        rowh = 0
        for i, (nm, crop, m) in enumerate(pieces):
            ci = Image.fromarray(np.where(m[:, :, None], crop, 30).astype(np.uint8))
            if x + ci.width + 10 > 1600:
                x, y = 0, y + rowh + 26
                rowh = 0
            sheet.paste(ci, (x, y + 18))
            d.text((x, y), "%d %s" % (i, nm), fill=(255, 255, 0))
            x += max(ci.width, 120) + 10
            rowh = max(rowh, ci.height)
        sheet.save([a for a in sys.argv[1:] if a.endswith(".png")][0])
        print(len(pieces), "pieces")
        return
    with tempfile.TemporaryDirectory() as tmp:
        # Tile sets: every piece of every panel.
        for fname, prefix, strip, views, head in NPC_SHEETS:
            if flt not in fname or not os.path.exists(os.path.join(IMAGES, fname)):
                continue
            img = np.asarray(Image.open(os.path.join(IMAGES, fname)).convert("RGB"))
            # The head-details picture: the conversation portrait.
            hc, hm = extract_head(img, head)
            if not only or only == prefix + "portrait":
                print("%-40s %s" % (prefix + "portrait", save_sprite(hc, hm, "npc", prefix + "portrait")))
            # (Their turnaround views are only references: the guard is drawn
            # from its own sprite sheets, art/guard/.)
        for fname, prefix, names in GRID_SHEETS:
            if flt not in fname or not os.path.exists(os.path.join(IMAGES, fname)):
                continue
            img = np.asarray(Image.open(os.path.join(IMAGES, fname)).convert("RGB"))
            for nm, crop, m in extract_grid(img, names, fname in SHADOW_SHEETS, fname in ORDERED_SHEETS):
                if nm.startswith("-"):
                    continue   # (a cell the game doesn't use: named for the grid, not saved)
                if only and prefix + nm != only:
                    continue
                print("%-40s %s" % (prefix + nm, save_sprite(crop, m, "piece", prefix + nm)))
                if fname in MIRROR_WALLS and nm.startswith("wally_"):
                    mx = prefix + "wallx_" + nm[len("wally_"):]
                    print("%-40s %s" % (mx, save_sprite(crop[:, ::-1].copy(), m[:, ::-1].copy(), "piece", mx)))
        for fname, prefix, names in FX_SHEETS:
            if flt not in fname or not os.path.exists(os.path.join(IMAGES, fname)):
                continue
            img = np.asarray(Image.open(os.path.join(IMAGES, fname)).convert("RGB"))
            for nm, im in extract_fx(img, names):
                if only and prefix + nm != only:
                    continue
                im.save(os.path.join(OUT, prefix + nm + ".png"))
                print("%-40s %s" % (prefix + nm, im.size))
        fname, prefix, pieces = GATE_SHEET
        if flt in fname and os.path.exists(os.path.join(IMAGES, fname)):
            img = np.asarray(Image.open(os.path.join(IMAGES, fname)).convert("RGB"))
            for nm, im in extract_boxes(img, pieces):
                if only and prefix + nm != only:
                    continue
                im.save(os.path.join(OUT, prefix + nm + ".png"))
                print("%-40s %s" % (prefix + nm, im.size))
        for fname, prefix, panels in TILE_SETS:
            if flt not in fname or not os.path.exists(os.path.join(IMAGES, fname)):
                continue
            img = np.asarray(Image.open(os.path.join(IMAGES, fname)).convert("RGB"))
            for nm, crop, m in extract_tiles(img, panels):
                if only and prefix + nm != only:
                    continue
                print("%-40s %s" % (prefix + nm, save_sprite(crop, m, "tile", prefix + nm)))
        for fname, cols, rows, kind, keys in SHEETS:
            path = os.path.join(IMAGES, fname)
            if flt not in fname or not os.path.exists(path):
                continue
            img = np.asarray(Image.open(path).convert("RGB"))
            H, W = img.shape[:2]
            th = FG_BY_SHEET.get(fname, FG_THRESHOLD)
            cells = [(W * (i % cols) // cols, H * (i // cols) // rows, W * (i % cols + 1) // cols, H * (i // cols + 1) // rows)
                     for i in range(len(keys))]
            owner = sheet_owners(img, cells, th) if fname in NEAREST_HULL_SHEETS else None
            for i, key in enumerate(keys):
                if only and key != only:
                    continue
                print("%-40s %s" % (key, cut_one(img, cells[i], kind, key, tmp, th, owner, i)))


if __name__ == "__main__":
    main()
