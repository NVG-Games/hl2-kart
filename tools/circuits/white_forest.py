"""White Forest: Episode Two's forest (ep2_outland_05-12), the logging roads through the pines on
the way to the White Forest base, a lap of about 2.7 km.

From the start on the plateau's broken asphalt the road runs north beside the railway (a train
can race the karts along that stretch, a fence between them), swings away from it and down into a
rock cutting, turns east under the railway's girder bridge and climbs out onto the gorge road: a
long level straight between guard rails and then concrete parapets onto the see-saw bridge over the
river gorge (EP2's span on its pivot; this module leaves its road out for the see-saw hazard to
build, see SEESAW). Past the gorge the road bends south along the east hill and down into the valley,
under the high bridge the Combine column marches over (COLUMN_PATH), round the hairpin at the
valley's end and back north under the same bridge, west through a cutting in the ridge, down onto
the riverside road, through the sawmill's yard, over the river on the mill bridge and up the west
bank to the plateau, across the railway at a level crossing and round onto the start straight.

Two branches: the logging trail (from the gorge road's straight through the pines to the east
hill's road, a jump over a dry gully on the way) and the sawmill shed (straight through the long
shed while the yard road swings round the log stacks).

The railway (RAIL_LINES, rail top heights): the main line comes out of a tunnel portal at the south
edge, crosses the lap once at grade (the level crossing on the west bank's climb), runs north
beside the start straight, over the cutting on its girder bridge and into a tunnel portal at the
north edge; sidings beside it (the parallel stretch's far side, the south yard, by the north
portal) and the sawmill's log siding hold the standing trains. The generator lays the bed, the
sleepers and both rails along every line (_railway), the girder bridge (_rail_bridge) and the
portals (_rail_portals).

The traps (HAZARDS): the see-saw bridge, the Combine column on its bridge (it halts over each leg
of the valley and fires on red strips of the road before it) and the main line's freight train (the
level crossing's barrier arms, beside the start straight, over the girder bridge). The vortigaunts
pull a kart that left the road back onto it. The set dressing (_dress): pines along every road and
the tree line on the hills beyond, standing and derailed trains on the sidings, the fallen bridge's
cars in the gorge, the sawmill's log stacks, the rebels' camp, rocks and logs; rebels and
vortigaunts watch (crowds), the wind blows in the pines (TRACK["background"] "forest").
"""
import math
import os

import numpy as np

import hazards
from track_gen import UP, _run_heights, _unwrap_s, _wall_gap, carve, face, noise2, plane_uv, smoothstep, wall_strip

# the water: the river's surface (and the game's sea level, a plane at this height: the land is
# above it everywhere but in the river's bed)
RIVER_Y = 0.0
# the plateau west of the river (the railway's and the start straight's level) and its ground
PLATEAU_Y = 20.0
# the river from north to south (x, z): deep in its gorge under the see-saw, out in the open past
# the riverside road, under the mill bridge and on south
RIVER = [(58.0, -720.0), (34.0, -590.0), (50.0, -460.0), (40.0, -350.0), (40.0, -250.0), (30.0, -180.0),
         (44.0, -110.0), (32.0, -40.0), (16.0, 30.0), (22.0, 110.0), (12.0, 190.0), (8.0, 260.0), (10.0, 330.0),
         (-6.0, 420.0), (10.0, 520.0), (-10.0, 640.0), (0.0, 760.0)]

# ---------------------------------------------------------------- the see-saw bridge
# Episode Two's see-saw (seesawbridge/bridgemetalnondynamic, its 49.08 m span drawn 41 m long) over
# the river gorge on the gorge road's level straight, its pivot over the river: the lap's style
# "seesaw" runs 101 m (the span and a 30 m hinged flap at either end) from "stretch_x"[0] to [1], 12 m
# wide, and the generator leaves its road out (the style's "seesaw" key) for the see-saw hazard to
# build (scripts/hazards/seesaw_hazard.gd). The flaps are that long because the karts reach the span
# at up to 40 m/s off the gorge road's boost pad: with 16 m flaps a flap tipped 2 degrees bent so
# sharply (a 52 m radius) that a fast kart bottomed out in its hollow and was thrown up off its crest;
# 30 m flaps bend at a 175 m radius. West of it the concrete approach deck (the style "approach_w",
# 30 m), east of it the exit deck ("approach_e", 21 m), parapets on both, on piers over the gorge's
# sides; the gorge road on land beyond them (guard rails at the road's edge, in line with the
# parapets). Everything from x -95 to +195 is level at SEESAW["y"] and straight along +x; under the
# stretch the gorge's ground lies 12 m and more below the road.
SEESAW = {"pivot": (40.0, PLATEAU_Y, -300.0), "dir": (1.0, 0.0, 0.0), "length": 41.0, "width": 12.0,
          "y": PLATEAU_Y,
          # the stretch the hazard builds, the span in its middle, the approach decks (x; z = the pivot's)
          "stretch_x": (-10.5, 90.5), "span_x": (19.5, 60.5), "west_deck_x": (-40.5, -10.5),
          "east_deck_x": (90.5, 111.5)}
# WF_STATIC_SEESAW=1 builds a plain static deck with parapets over the stretch (the road and its
# collision as any deck's): for testing the layout without the see-saw hazard
SEESAW_STATIC = os.environ.get("WF_STATIC_SEESAW", "") == "1"

# ---------------------------------------------------------------- the Combine column's bridge
# A concrete bridge high over the hairpin valley, east to west across both its legs (the lap passes
# under it twice: heading south on the east leg and north on the west leg), from the knoll on the
# ridge west of the valley to the east hill. The column marches along COLUMN_PATH: its points
# (x, y, z) are the walking surface (the deck's top, a forest track on the hills at either end).
COLUMN_Z = -60.0
COLUMN_Y = 31.0
COLUMN_DECK_X = (172.0, 344.0)        # abutment to abutment
COLUMN_W = 7.0                        # deck width between its parapets
COLUMN_PIERS = (204.0, 250.0, 312.0)  # pier x (between the legs' verges, none on a road)
COLUMN_PATH = [(150.0, COLUMN_Y, COLUMN_Z), (172.0, COLUMN_Y, COLUMN_Z), (258.0, COLUMN_Y, COLUMN_Z),
               (344.0, COLUMN_Y, COLUMN_Z), (396.0, COLUMN_Y, COLUMN_Z)]


# ---------------------------------------------------------------- the railway
# The rails' top is at the points' heights (where a car's wheels run: a car model stands with its
# bottom there). Every line is a polyline of points RAIL_STEP metres apart, given from one end to
# the other; "kind" says what it is for:
#   main     the main line, out of the south portal (RAIL_PORTALS["south"]), north across the lap at
#            grade (the level crossing on the west bank's climb, RAIL_CROSSING), beside the start
#            straight (the parallel stretch, RAIL_PARALLEL: the road 16 m to its west, a fence
#            between), over the cutting on the girder bridge (RAIL_BRIDGE: the lap passes under it)
#            and into the north portal. The moving trains run here, portal to portal.
#   siding   a dead-end or passing track beside the main line for standing trains, curving out of
#            the main line at a turnout end (its first or last point on the main line); the
#            sawmill's log siding stands on its own in the yard
# None of them comes nearer the lap's road than its fence or verge but at RAIL_CROSSING.
RAIL_STEP = 4.0
RAIL_X = -284.0            # the main line's straight (x), from RAIL_BEND_Z north
RAIL_BEND_Z = 150.0        # south of here it bends east toward the south portal
RAIL_R = 900.0             # ... on this radius
RAIL_NORTH_Z = -520.0      # the north portal's mouth
RAIL_SOUTH_Z = 580.0       # the south portal's mouth (z; x on the bend)


def _bend_x(z):
    """The main line's x at z on its bend south of RAIL_BEND_Z (the straight north of it)."""
    d = max(z - RAIL_BEND_Z, 0.0)
    return RAIL_X + RAIL_R - math.sqrt(RAIL_R * RAIL_R - d * d)


def _main_line():
    """The main line from the south portal to the north portal, RAIL_STEP apart."""
    out = []
    # the bend, by its angle from the straight's end (equal steps along it)
    phi_end = math.asin((RAIL_SOUTH_Z - RAIL_BEND_Z) / RAIL_R)
    k = int(math.ceil(phi_end * RAIL_R / RAIL_STEP))
    for j in range(k, 0, -1):
        phi = phi_end * j / k
        out.append((round(RAIL_X + RAIL_R - RAIL_R * math.cos(phi), 3), PLATEAU_Y,
                    round(RAIL_BEND_Z + RAIL_R * math.sin(phi), 3)))
    z = RAIL_BEND_Z
    while z >= RAIL_NORTH_Z - 1e-6:
        out.append((RAIL_X, PLATEAU_Y, round(z, 3)))
        z -= RAIL_STEP
    return out


def _offset_line(z0, z1, off, ease=36.0, join0=True, join1=False):
    """A track `off` metres east (+) or west (-) of the main line from z0 north to z1 (z0 > z1),
    following its bend; with join0 / join1 it turns out of the main line over `ease` metres at that
    end (a turnout), else it starts or ends there (a buffer stop)."""
    out = []
    z = z0
    total = z0 - z1
    while z >= z1 - 1e-6:
        u = z0 - z
        w = 1.0
        if join0:
            w = min(w, smoothstep(0.0, ease, u))
        if join1:
            w = min(w, smoothstep(0.0, ease, total - u))
        out.append((round(_bend_x(z) + off * w, 3), PLATEAU_Y, round(z, 3)))
        z -= RAIL_STEP
    return out


def _straight_line(a, b):
    """A track straight from a to b ((x, y, z) each), RAIL_STEP apart, its height running evenly."""
    a, b = np.array(a, float), np.array(b, float)
    n = max(int(math.ceil(np.linalg.norm(b[[0, 2]] - a[[0, 2]]) / RAIL_STEP)), 1)
    return [tuple(round(float(c), 3) for c in a + (b - a) * k / n) for k in range(n + 1)]


RAIL_LINES = {
    "main": {"kind": "main", "points": _main_line()},
    # the parallel stretch's far side: a passing loop 5 m east of the main line (the moving train runs
    # between it and the road)
    "parallel_loop": {"kind": "siding", "points": _offset_line(160.0, -175.0, 5.0, join1=True)},
    # the south yard inside the main line's bend, south of the level crossing: two tracks off it
    "south_yard_1": {"kind": "siding", "points": _offset_line(560.0, 372.0, 4.6, join0=False, join1=True)},
    "south_yard_2": {"kind": "siding", "points": _offset_line(540.0, 410.0, 9.2, join0=False, join1=True, ease=60.0)},
    # by the north portal, west of the main line: a dead end for derailed and standing cars
    "north_siding": {"kind": "siding", "points": _offset_line(-330.0, -500.0, -4.6)},
    # the sawmill's log siding along the river bank, west of the shed (no turnout: the old logging line)
    "mill_siding": {"kind": "siding", "points": _straight_line((50.0, 10.2, 20.0), (49.0, 9.0, 205.0))},
}
for _nm, _ln in RAIL_LINES.items():
    _ln["points"] = [list(p) for p in _ln["points"]]
# where the main line crosses the lap at grade (x, z), passes over it (the girder bridge across the
# cutting: x, z of its middle, and the deck's ends along the line) and runs beside it (z from, to)
RAIL_CROSSING = (_bend_x(318.0), 318.0)
RAIL_BRIDGE = {"center": (RAIL_X, -300.0), "z": (-311.5, -288.5), "rail_y": PLATEAU_Y}
RAIL_PARALLEL = (150.0, -110.0)
# the tunnel mouths the main line runs out of and into: (x, z) and the way out of the tunnel (x, z)
RAIL_PORTALS = {"north": {"at": (RAIL_X, RAIL_NORTH_Z), "out": (0.0, 1.0)},
                "south": {"at": (_bend_x(RAIL_SOUTH_Z), RAIL_SOUTH_Z),
                          "out": (-math.sin(math.asin((RAIL_SOUTH_Z - RAIL_BEND_Z) / RAIL_R)),
                                  -math.cos(math.asin((RAIL_SOUTH_Z - RAIL_BEND_Z) / RAIL_R)))}}


def _arc(cx, cz, r, a0, a1, y, w, style, n=4):
    """Control points round a bend: n points from angle a0 to a1 (degrees; x = cx + r cos a,
    z = cz + r sin a) on a circle of radius r, at height y (or (y0, y1) along it) and width w
    (or (w0, w1))."""
    y0, y1 = y if isinstance(y, tuple) else (y, y)
    w0, w1 = w if isinstance(w, tuple) else (w, w)
    out = []
    for k in range(n):
        u = k / (n - 1)
        a = math.radians(a0 + (a1 - a0) * u)
        out.append((round(cx + r * math.cos(a), 2), round(y0 + (y1 - y0) * u, 3), round(cz + r * math.sin(a), 2),
                    w0 + (w1 - w0) * u, style))
    return out


# (x, y, z, width, style[, flags]): the start first, heading north (-z) on the plateau (+x east,
# +z south; the river runs north to south through the middle, the railway along the west)
CTRL = [
    # the start straight beside the railway (on the right, past the fence)
    (-300, PLATEAU_Y, 60, 13, "start"), (-300, PLATEAU_Y, 10, 13, "start"),
    (-300, PLATEAU_Y, -40, 13, "railside"), (-300, PLATEAU_Y, -90, 13, "railside"),
    # away from the railway to the left and down into the rock cutting
    (-303, 19.6, -122, 13, "railside"), (-309, 18.6, -150, 13, "cut", {"height": 1.5}),
    (-320, 17.0, -176, 13, "cut", {"height": 3.1}),
    (-336, 15.0, -207, 13, "cut", {"height": 5.1})] + \
    [(x, y, z, w, s, {"height": round(PLATEAU_Y + 0.1 - y, 2)})
     for x, y, z, w, s in _arc(-285, -240, 60, 180, 270, (13.4, 12.0), 13, "cut")] + [
    # east along the cutting under the girder bridge (at the bend's end) and up out of it
    (-245, 12.3, -300, 13, "cut", {"height": 7.8}), (-205, 14.4, -300, 13, "cut", {"height": 5.7}),
    (-170, 16.9, -300, 13, "cut", {"height": 3.2}), (-148, 18.4, -300, 13, "cut", {"height": 1.7}),
    # the gorge road: level and straight from here past the see-saw, narrowing to 8 m between
    # parapets onto the approach deck
    (-130, 19.6, -300, 13, "gorge"), (-95, PLATEAU_Y, -300, 12.4, "gorge"), (-66, PLATEAU_Y, -300, 12, "gorge"),
    (SEESAW["west_deck_x"][0], PLATEAU_Y, -300, 12, "approach_w"),
    (SEESAW["stretch_x"][0], PLATEAU_Y, -300, SEESAW["width"], "seesaw"),
    (SEESAW["stretch_x"][1], PLATEAU_Y, -300, SEESAW["width"], "approach_e"),
    (SEESAW["east_deck_x"][1], PLATEAU_Y, -300, 12, "gorge"),
    (140, PLATEAU_Y, -300, 12.6, "forest"), (165, PLATEAU_Y, -300, 13, "forest"),
    (195, PLATEAU_Y, -300, 13, "forest")] + \
    _arc(220, -240, 60, 270, 360, (20.3, 21.6), 13, "forest") + [
    # the east leg south, down into the valley under the column's bridge
    (280, 21.6, -195, 13, "forest"), (280, 20.5, -145, 13, "forest"), (280, 19.0, -95, 13, "forest"),
    (280, 17.9, -50, 13, "forest")] + \
    _arc(250, -20, 30, 0, 180, 17.2, 13, "hairpin", 5) + [
    # back north up the west leg, under the bridge again
    (220, 17.1, -55, 13, "forest"), (220, 17.4, -100, 13, "forest")] + \
    _arc(180, -140, 40, 0, -90, (17.6, 17.4), 13, "forest")[:-1] + [
    # west through the cutting in the ridge
    (180, 17.4, -180, 13, "ridgecut", {"height": 5.0}), (150, 17.0, -180, 13, "ridgecut", {"height": 8.5})] + \
    _arc(125, -140, 40, -90, -180, (16.4, 15.0), 13, "riverside") + [
    # the riverside road south (the river on the right), into the sawmill's yard: the road swings
    # left round the log stacks while the shed's branch runs on through the shed
    (85, 14.2, -105, 13, "riverside"), (85, 13.4, -70, 13, "riverside"), (85, 12.6, -38, 13, "riverside"),
    (85, 12.1, -10, 13, "yard"), (97, 11.6, 26, 13, "yard"), (114, 11.1, 60, 13, "yard"), (114, 10.5, 112, 13, "yard"),
    (97, 10.0, 146, 13, "yard"), (85, 9.6, 172, 13, "yard"), (85, 9.2, 210, 13, "riverside"),
    (85, 8.9, 245, 13, "riverside")] + \
    _arc(45, 275, 40, 0, 90, (8.7, 8.5), 13, "millturn") + [
    # over the river on the mill bridge and up the west bank onto the plateau
    (34, 8.5, 315, 13, "millbridge"), (-16, 8.7, 315, 13, "climb"),
    (-62, 9.8, 314, 13, "climb"), (-118, 12.8, 311, 13, "climb"), (-170, 16.4, 312, 13, "climb"),
    (-212, 19.3, 316, 13, "crossing"), (-240, PLATEAU_Y, 318, 13, "crossing"), (-266, PLATEAU_Y, 319, 13, "crossing"),
    (-290, PLATEAU_Y, 320, 13, "crossing")] + \
    _arc(-290, 275, 45, 90, 180, PLATEAU_Y, 13, "forest", 3)[1:] + [
    # round onto the start straight, the railway coming alongside on the right
    (-332, PLATEAU_Y, 236, 13, "forest"), (-318, PLATEAU_Y, 200, 13, "forest"), (-303, PLATEAU_Y, 160, 13, "railside"),
    (-300, PLATEAU_Y, 120, 13, "start"),
]
CTRL = [c if len(c) > 5 else c + ({},) for c in CTRL]

BRANCHES = [
    # the logging trail: off the gorge road's straight to the right through the pines, over a dry
    # gully (a jump: short of the far side you drop into it; 40 m of straight trail to land on past
    # it, however fast you come) and on onto the east leg; narrower and rougher than the road round
    # the bend, about as quick for a driver who carries the speed over the gully
    {"id": "logging_trail", "name": "Logging trail", "fork": (165, -300), "merge": (280, -122), "kind": "jump",
     "ctrl": [(184, 20.0, -294, 8, "trail"), (199, 20.1, -284, 8, "trail"), (210, 20.2, -270, 8, "trail"),
              (219, 20.3, -252, 8, "trail", {"gap": True, "gap_span": (0.35, 0.65), "ramp_lift": 1.2,
                                              "ramp_len": 14}),
              (231, 20.3, -228, 8, "trail"), (242, 20.4, -206, 8, "trail"), (253, 20.6, -186, 8, "trail"),
              (262, 20.8, -166, 8, "trail")],
     "items": [0.65], "risk": 0.45, "ai": {"take": 0.5, "min_skill": 0.75}, "retry_back": 50.0},
    # the sawmill shed: off the riverside road to the right and straight through the long shed (saw
    # benches, log carriages) while the yard road swings left round the log stacks
    {"id": "sawmill_shed", "name": "Sawmill shed", "fork": (85, -110), "merge": (85, 255), "kind": "alt",
     "side": 1, "merge_side": 1,
     "ctrl": [(79, 13.8, -88, 9, "shedyard"), (69, 13.2, -64, 9, "shedyard"), (65, 12.7, -40, 9, "shedyard"),
              (65, 12.1, 0, 9, "shed"), (65, 11.0, 90, 9, "shedyard"), (65, 10.2, 145, 9, "shedyard"),
              (65, 9.6, 198, 9, "shedyard"), (73, 9.2, 230, 9, "shedyard")],
     "items": [0.5], "risk": 0.15, "ai": {"take": 0.5, "min_skill": 0.6}},
]

# the lap metres where the main line crosses the lap at grade (RAIL_CROSSING: where its line crosses
# the road's middle; tools/hazards.py refuses a crossing whose line misses the road there)
CROSSING_S = 2421.7
# the hazards (TRACK["hazards"]), in this order (their seeds follow it):
#   the see-saw bridge (scripts/hazards/seesaw_hazard.gd): the span on its pivot over the gorge, built
#   with hazards off too (level and still); the resolver finds its stretch from any s inside it
#   the Combine column (combine_column_hazard.gd) on its bridge over the valley, trimmed to the deck
#   between the legs' hills: it halts over the east leg (s 1183) and over the west leg (s 1355) and
#   stands watch over the stretch before each (its zones start past the logging trail's merge and
#   end before the hairpin's crate row and the west leg's pad)
#   the main line's train (train_hazard.gd, "cross"): one freight train runs the whole line from the
#   south portal to the north one, across the lap at the level crossing (barrier arms, a long
#   warning, never the same kart held two laps running), then north beside the start straight
#   behind its fence (racing the karts) and over the cutting on the girder bridge; the module lays
#   its rails, portals and bridge itself ("rails" none, no portals, its points as they are). Always
#   the same way: run after run the crossing then shuts a period apart (one way then the other, a
#   run that crosses late would be followed by one that crosses early, the road open only 19 s
#   between them)
HAZARDS = [
    {"type": "seesaw", "s": 728.5, "length": SEESAW["length"]},
    # (the column marches only the deck between and just past the two posts, and stands each watch
    # 30 s: more of its cycle on watch, where 24 s watches and 140 m of deck left it marching while
    # most packs went by. Its phase puts its first watch over the east leg from 24 s into the race,
    # as the pack comes down it on the first lap. At a watch the soldiers step up to the railing on
    # the road's side ("edge": the railing's inner face, metres from the deck's line), where the
    # karts below see them)
    {"type": "column", "s": 1183.0, "zone": [1124.0, 1190.0],
     "deck": [[205.0, COLUMN_Y, COLUMN_Z], [295.0, COLUMN_Y, COLUMN_Z]],
     "posts": [{"s": 1355.0, "zone": [1290.0, 1362.0]}], "watch": 30.0, "phase": 45.0, "edge": COLUMN_W / 2},
    {"type": "train", "mode": "cross", "s": CROSSING_S, "line": RAIL_LINES["main"]["points"], "rails": "none",
     "portals": False, "smooth": 0, "dirs": "ab"},
]

TRACK = {
    "id": "white_forest",
    "name": "White Forest",
    "ctrl": CTRL,
    # Episode Two's own score (the vlvx songs 20 and up), and one more from Episode One
    "music": ["vlvx_song20", "vlvx_song22", "vlvx_song24", "vlvx_song27", "vlvx_song15"],
    # (crates: the start straight, the gorge road before the see-saw, the east leg past the column's
    # zone, the west leg, the sawmill's yard, the climb out of the valley and the drift onto the start
    # straight; none on the see-saw's stretch, in a branch's shared stretch or where the column's
    # strips land)
    "items": [0.055, 0.215, 0.44, 0.52, 0.69, 0.8, 0.965],
    # (pads on straights only: the start straight, the climb out of the cutting, the west leg out of
    # the hairpin, the mill bridge and the drift onto the start straight; none on the see-saw, and
    # none in the 250 m before the level crossing: a kart on a boost can not stop for its arms)
    "boosts": [0.03, 0.21, 0.5, 0.79, 0.955],
    "barrels": [],
    "vmax": 38.0,
    "offtrack": 40.0,
    # the game's gravity (project.godot): the launch speeds the branches export are the real ones
    "gravity": 15.24,
    "sky": "sky_day01_06",
    # (no Citadel: the wind in the pines and distant birds instead, scripts/fx/forest_life.gd)
    "background": "forest",
    "gantry": "combine",
    "gantry_clear": 3.0,
    "water": {"level": RIVER_Y},
    "env": {"sun_energy": 1.5, "sun_color": [1.0, 0.92, 0.78], "sun_dir": [0.45, 0.6, 0.55],
            "ambient": [0.56, 0.6, 0.55], "ambient_energy": 1.0, "fog_color": [0.62, 0.66, 0.62],
            "fog_begin": 180.0, "fog_end": 1900.0, "exposure": 1.0,
            # (no realtime GI: under the pines, in the shed and in the cuttings it turned the faces the
            # sun does not reach black; the ambient light above lights them as MEDIUM and LOW do)
            "sdfgi": False},
    "hazards": HAZARDS,
}


def styles(m):
    asphalt = m.hl2("concrete/forest_road01")
    broken = m.hl2("concrete/forest_road01a")
    dirt_road = m.hl2("nature/dirtroad001b")
    grass = m.hl2("nature/blendgrassdirt01")
    dirt = m.hl2("nature/forest_dirt_02")
    rock = m.hl2("nature/cliff01a")
    concrete = m.hl2("concrete/concretewall066a")
    beam = m.hl2("wood/woodbeam001a")
    planks = m.hl2("wood/woodfloor005a")
    # the forest roads' guard rail, a kart thrown up meets its unseen wall up to 2.5 m
    rail = {"kind": "fence", "mat": m.hl2("metal/metalrail013a"), "h": 1.0, "rep": 2.4, "col_h": 2.5}
    # the gorge's concrete parapets: upright and high enough that a kart rammed into them in the pack
    # stays on the deck (its unseen wall up to 4 m)
    parapet = {"kind": "wall", "mat": m.hl2("concrete/concretewall064a"), "h": 1.1, "thick": 0.5, "rep": 3.0,
               "col_h": 4.0}
    # the mill bridge's wooden rails: an unseen wall over them up to 4 m (a kart an item or the pack
    # throws up stays on the deck instead of dropping into the river)
    wood_rail = {"kind": "fence", "mat": m.hl2("wood/woodwall009a"), "h": 1.0, "rep": 2.0, "col_h": 4.0}
    # the plateau and the hills: EP2's broken asphalt, the forest's grass and needles on the verges
    forest = {"kind": "open", "road": asphalt, "road_u": "full", "road_len": 1.6, "verge": grass, "verge_w": 4.0,
              "skirt": rock}
    deck = {"kind": "bridge", "road": broken, "road_u": "full", "road_len": 1.2, "skirt": concrete, "skirt_h": 1.6,
            "barrier": parapet, "pillar": concrete, "pillar_every": 20.0, "pillar_size": 2.0, "ground": "nat"}
    cut = {"kind": "trench", "road": asphalt, "road_u": "full", "road_len": 1.6, "wall": rock, "wall_rep": 8.0,
           "lip": 3.0, "lip_mat": dirt}
    # the see-saw's stretch (the seesaw agent's style): tools/track_gen.py leaves its road out and the
    # see-saw hazard builds the span that moves, its flaps and its side walls; with WF_STATIC_SEESAW a
    # plain deck between parapets stands in for it
    plates = m.hl2("metal/metalfloor001a")
    # (the land under it is the gorge as it lies, "nat": a dip would raise it to 8 m under the road)
    seesaw = {"kind": "bridge", "seesaw": True, "road": plates, "skirt": plates, "ground": "nat"}
    if SEESAW_STATIC:
        seesaw = dict(deck, road=plates, road_u=None, road_rep=3.0, pillar_every=1e9)
        seesaw.pop("road_u")
    return {
        # the start straight, its grid level and unbanked; the fence on the right keeps the karts off
        # the railway
        "start": dict(forest, barrier=dict(rail, sides="right", off=3.0)),
        "railside": dict(forest, barrier=dict(rail, sides="right", off=3.0)),
        "forest": forest,
        # the rock cuttings: EP2's cliff faces both sides, the needles on their lips
        "cut": cut,
        "ridgecut": cut,
        # the gorge road on the plateau: guard rails both sides (they stand at the road's edge, in line
        # with the approach decks' parapets)
        "gorge": dict(forest, road=broken, barrier=dict(rail, off=0.0, col_h=4.0)),
        # the narrow road on land at either end of the approach decks: a deck on the ground (its
        # parapets run on into the decks')
        # the see-saw's concrete approach decks over the gorge, on piers
        "approach_w": deck,
        "approach_e": deck,
        "seesaw": seesaw,
        # the valley's hairpin under the bend of the east hill: a computer driver takes it at one
        # steady speed
        "hairpin": dict(forest, verge_w=5.0, vmax=22.0),
        # the riverside road: broken asphalt, the river down the bank on its right behind a guard rail
        # at the road's edge (a kart that overshoots the bend onto it would slide down into the water;
        # its unseen wall stops one an item throws up to 4 m)
        "riverside": dict(forest, road=broken, barrier=dict(rail, sides="right", off=0.0, col_h=4.0)),
        # the bend onto the mill bridge: rails both sides at the road's edge, in line with the bridge's
        # (a kart that runs wide out of the bend stays on the road instead of sliding down the bank)
        "millturn": dict(forest, road=broken, barrier=dict(rail, off=0.0, col_h=4.0)),
        # the sawmill's yard: hard dirt between the log stacks
        "yard": {"kind": "open", "road": dirt_road, "road_u": "full", "road_len": 2.0, "verge": dirt,
                 "verge_w": 5.0},
        # the mill bridge over the river: planks on timber trestles, wooden rails
        "millbridge": {"kind": "bridge", "road": planks, "road_rep": 4.0, "skirt": beam, "skirt_h": 1.2,
                       "barrier": wood_rail, "pillar": beam, "pillar_every": 9.0, "pillar_size": 0.7,
                       "pillar_offsets": [-0.85, 0.0, 0.85], "ground": "nat"},
        # up the west bank: broken asphalt, a guard rail on the valley's side
        "climb": dict(forest, road=broken, barrier=dict(rail, sides="left", off=1.0)),
        # the level crossing and its approaches: nothing between the road and the line (the crossing's
        # barriers and signals are the trains' hazard)
        "crossing": dict(forest, road=broken, verge_drop=0.02),
        # the logging trail: a dirt track through the pines
        "trail": {"kind": "open", "road": dirt_road, "road_u": "full", "road_len": 2.0, "verge": dirt, "verge_w": 3.0,
                  "skirt": rock, "vmax": 30.0},
        # the sawmill shed's way in and out across the yard, and the shed itself: a long timber hall
        "shedyard": {"kind": "open", "road": dirt_road, "road_u": "full", "road_len": 2.0, "verge": dirt,
                     "verge_w": 3.0},
        # (a plank ceiling: the beam texture across its whole width ran in long streaks down the hall;
        # its posts and tie beams are _shells')
        "shed": {"kind": "tunnel", "road": planks, "road_rep": 4.0, "side_floor": planks, "height": 7.0,
                 "wall": m.hl2("wood/woodwall009a"), "wall_rep": 3.0, "ceil": m.hl2("wood/woodceiling002a"),
                 "ceil_rep": 3.0,
                 "light": m.hl2("lights/fluorescentcool001a"), "light_every": 9.0, "light_rows": [0.0],
                 "light_w": 0.9, "light_l": 2.6, "light_color": [1.0, 0.85, 0.62], "light_energy": 1.3,
                 "wall_gap": 1.5, "portal": m.hl2("wood/woodwall009a"), "portal_w": 1.5, "cover": 0.0,
                 "vmax": 26.0},
    }


def STARTLINE(m):
    return m.hl2("props/hazardstrip001a")


# ---------------------------------------------------------------- terrain
# styles whose road lies off the land (decks over the gorge and the river) or below it (cuttings):
# the land's own heights come from the others (_base)
OFF_LAND = ("cut", "ridgecut", "approach_w", "seesaw", "approach_e", "millbridge")
# the rock ridge between the hairpin valley and the river: a line (x, z) along its crest, the
# crest's height, and the knoll at its south end the column's bridge starts from
RIDGE = [(148.0, -228.0), (150.0, -190.0), (158.0, -120.0), (166.0, -60.0), (160.0, -16.0)]
RIDGE_Y = 27.5
# the dry gully the logging trail jumps (its middle under the jump's gap, across the trail), its
# half length along itself and how far it sinks under the trail
GULLY_HALF, GULLY_DEPTH = 22.0, 7.0


def _nearest(P, Q):
    """For each plan point of P (n, 2): the distance to the nearest of Q (m, 2) and its index."""
    dist = np.zeros(len(P))
    idx = np.zeros(len(P), int)
    for a in range(0, len(P), 4096):
        d2 = ((P[a:a + 4096, None, :] - Q[None, :, :]) ** 2).sum(-1)
        idx[a:a + 4096] = d2.argmin(1)
        dist[a:a + 4096] = np.sqrt(d2[np.arange(len(d2)), idx[a:a + 4096]])
    return dist, idx


def _poly_dist(P, poly):
    """Plan distance from each point of P (n, 2) to the polyline poly, and the index of the nearest
    segment."""
    best = np.full(len(P), 1e9)
    seg = np.zeros(len(P), int)
    pts = np.asarray(poly, float)
    for k, (a, b) in enumerate(zip(pts[:-1], pts[1:])):
        ab = b - a
        t = np.clip(((P - a) @ ab) / (ab @ ab), 0.0, 1.0)
        d = np.linalg.norm(P - (a + t[:, None] * ab), axis=1)
        closer = d < best
        best = np.where(closer, d, best)
        seg = np.where(closer, k, seg)
    return best, seg


def _anchors(roads):
    """Points (x, z, ground y) the land is drawn through: the roads that lie on it every ~20 m, the
    plateau beside the cuttings, the railway's bed, the ridge's crest and the hills the column's
    bridge rests on."""
    out = []
    for t in roads.trks:
        for i in range(0, t.n, 10):
            st = t.style[i]
            if t.gap[i]:
                continue
            if st in OFF_LAND:
                if st in ("cut", "ridgecut"):
                    # the land the cutting runs through: the walls' tops either side
                    top = t.pos[i, 1] + t.height[i] - 0.1
                    for sgn in (-1, 1):
                        q = t.pos[i] + t.flat_right[i] * sgn * (t.width[i] / 2 + 12.0)
                        out.append((q[0], q[2], top))
                continue
            out.append((t.pos[i, 0], t.pos[i, 2], t.pos[i, 1] - 0.35))
    for ln in RAIL_LINES.values():
        for p in ln["points"][::8]:
            out.append((p[0], p[2], p[1] - 0.8))
    for x, z in RIDGE:
        out.append((x, z, RIDGE_Y))
    for x in (COLUMN_PATH[0][0], COLUMN_DECK_X[0], COLUMN_DECK_X[1], COLUMN_PATH[-1][0]):
        out.append((x, COLUMN_Z, COLUMN_Y - 0.4))
    return np.array(out, float)


def _base(P, A):
    """The land through the anchors A (x, z, y): inverse-distance weights (power 2, a 40 m core: no
    bump round each anchor), smooth between them and level far out."""
    out = np.zeros(len(P))
    for a in range(0, len(P), 4096):
        d2 = ((P[a:a + 4096, None, :] - A[None, :, :2]) ** 2).sum(-1)
        w = 1.0 / (d2 + 1600.0)
        out[a:a + 4096] = (w * A[None, :, 2]).sum(1) / w.sum(1)
    return out


def _river(P, h):
    """The river's bed and banks cut into the land h: its bed RIVER_Y - 3 within 11 m of its line,
    the banks rising to the land over a width that runs from the gorge's (north of z -230: 78 m,
    steep up to the rim: under the see-saw's 81 m stretch the ground lies 12 m and more below the
    road) to the open valley's (south of z -120: 30 m)."""
    d, seg = _poly_dist(P, RIVER)
    z = P[:, 1]
    gorge = smoothstep(-120.0, -230.0, z)
    W = 30.0 + 48.0 * gorge
    k = smoothstep(11.0, W, d) ** (1.0 + 1.2 * gorge)
    bed = RIVER_Y - 3.0
    # its ends close in the hills short of the land's edge: the river comes out of them and goes back
    # into them (open to the land's edge, it ran out onto the water plane, a flat sea to the horizon
    # seen up and down the gorge); its distance is "none" (1e9) where it has closed
    edge = np.minimum(np.minimum(P[:, 0] - P[:, 0].min(), P[:, 0].max() - P[:, 0]),
                      np.minimum(z - z.min(), z.max() - z))
    open_ = smoothstep(40.0, 170.0, edge)
    cut = np.minimum(h, bed + (h - bed) * k)
    return h + (cut - h) * open_, np.where(open_ > 0.5, d, 1e9)


def _gully(P):
    """How far (0..1 of GULLY_DEPTH) the dry gully under the logging trail's jump sinks each point:
    a trough across the trail at the gap, rounded at its ends."""
    br = next(b for b in BRANCHES if b["id"] == "logging_trail")
    c = next(k for k, p in enumerate(br["ctrl"]) if len(p) > 5 and p[5].get("gap"))
    a, b = np.array(br["ctrl"][c][:3])[[0, 2]], np.array(br["ctrl"][c + 1][:3])[[0, 2]]
    u0, u1 = br["ctrl"][c][5]["gap_span"]
    mid = a + (b - a) * (u0 + u1) / 2
    along = (b - a) / np.linalg.norm(b - a)
    across = np.array([-along[1], along[0]])
    q = P - mid
    x = np.abs(q @ across)
    y = np.abs(q @ along)
    half_w = np.linalg.norm(b - a) * (u1 - u0) / 2 + 1.0
    return smoothstep(half_w + 5.0, half_w - 1.0, y) * smoothstep(GULLY_HALF, GULLY_HALF - 8.0, x)


def _portal_hill(P, h):
    """The hillside each tunnel portal of the railway stands in: behind its mouth the land rises
    over the tunnel to 12 m over the rails, beside the mouth to the wing walls' tops."""
    for p in RAIL_PORTALS.values():
        at, out = np.array(p["at"], float), np.array(p["out"], float)
        side = np.array([-out[1], out[0]])
        q = P - at
        back = -(q @ out)
        lat = np.abs(q @ side)
        top = PLATEAU_Y + 12.0 + 6.0 * smoothstep(10.0, 80.0, back)
        w = smoothstep(-2.0, 8.0, back) * smoothstep(80.0, 30.0, lat) * smoothstep(160.0, 90.0, back)
        h = np.maximum(h, top * w + h * (1.0 - w))
        # the wing walls' tops (8 m over the rails) a few metres in front of the mouth
        w2 = smoothstep(4.0, -2.0, back) * smoothstep(-14.0, -2.0, back) * smoothstep(5.5, 9.0, lat) * \
            smoothstep(48.0, 30.0, lat)
        h = np.maximum(h, (PLATEAU_Y + 8.0) * w2 + h * (1.0 - w2))
    return h


def _rail_bed(P, h, under_road):
    """The ground along every railway line held to its bed: a hand under the ballast's top in the
    middle, never over it, and never more than 0.3 m under the ballast's foot (no slot shows under
    it), blending back to the land over 10 m; not under the girder bridge (the cutting) nor where a
    road is (under_road: the level crossing, the road's own)."""
    for nm, ln in RAIL_LINES.items():
        Q = np.array(ln["points"], float)
        d, k = _nearest(P, Q[:, [0, 2]])
        y = Q[k, 1]
        lo, hi = y - 1.05, y - 0.3
        core = smoothstep(4.0, 2.4, d)
        near = smoothstep(14.0, 2.4, d)
        free = np.ones(len(P), bool)
        if nm == "main":
            z0, z1 = RAIL_BRIDGE["z"]
            free = ~((Q[k, 2] > z0 - 1.0) & (Q[k, 2] < z1 + 1.0))
        free &= ~under_road
        target = np.clip(h, lo, hi) * core + (y - 0.8) * (1.0 - core)
        w = np.where(free, np.maximum(core, near * 0.85), 0.0)
        h = h + (np.where(core > 0.0, target, y - 0.8) - h) * w
    return h


def terrain(roads, m):
    layers = {"base": m.hl2("nature/blendgrassdirt01"), "dirt": m.hl2("nature/forest_dirt_02"),
              "rock": m.hl2("nature/cliff01a"), "pave": m.hl2("nature/forest_gravel_01"),
              "sand": m.hl2("nature/forest_mud_01")}

    def build(f, roads):
        P = f.P
        x, z = P[:, 0], P[:, 1]
        A = _anchors(roads)
        base = _base(P, A)
        # forest hills further out from every road and railway line, rolling under the pines: big
        # hills and the valleys between them, a smaller roll over those, a few metres of hummocks
        rail_d = np.full(len(P), 1e9)
        for ln in RAIL_LINES.values():
            rail_d = np.minimum(rail_d, _nearest(P, np.array(ln["points"])[:, [0, 2]])[0])
        d_free = np.minimum(np.maximum(f.dist - f.half, 0.0), np.maximum(rail_d - 3.0, 0.0))
        n1 = noise2(x / 240.0, z / 240.0, 41)
        n2 = noise2(x / 75.0, z / 75.0, 43)
        n3 = noise2(x / 22.0, z / 22.0, 45)
        hills = smoothstep(22.0, 150.0, d_free) * (4.0 + 34.0 * n1 ** 1.4 + 9.0 * (n2 - 0.5)) + \
            2.0 * (n3 - 0.5) * smoothstep(8.0, 30.0, d_free)
        nat = base + hills
        # the ridge between the valley and the river: its crest RIDGE_Y (a few metres either way),
        # rounding off down to the land either side
        dr, _ = _poly_dist(P, RIDGE)
        crest = RIDGE_Y + 3.0 * (noise2(x / 45.0, z / 45.0, 49) - 0.5)
        nat = np.maximum(nat, nat + (crest - nat) * np.exp(-(dr / 34.0) ** 2))
        # the hills at either end of the column's bridge, level with its deck along its path
        dc, _ = _poly_dist(P, [(p[0], p[2]) for p in COLUMN_PATH])
        out = (x < COLUMN_DECK_X[0] + 4.0) | (x > COLUMN_DECK_X[1] - 4.0)
        top = COLUMN_Y - 0.35
        nat = np.where(out, np.maximum(nat, top - 0.25 * np.maximum(dc - 9.0, 0.0) ** 1.35), nat)
        nat = _portal_hill(P, nat)
        nat, d_river = _river(P, nat)
        # the dry gully across the logging trail's jump
        nat = nat - GULLY_DEPTH * _gully(P)
        h = carve(f, nat, roads, flat=6.0, blend=26.0)
        under_road = f.dist < f.half + 1.0
        h = _rail_bed(P, h, under_road)
        # the sawmill's shed stands on the yard like a building, not in a hill: past the ground just
        # outside its walls (the carve's slot) the land stays as it lies
        for v in (f, f.second):
            hall = (v.kind == "tunnel") & (v.dist > v.wall + f.cell + 0.5) & (v.dist < v.wall + 40.0)
            h = np.where(hall, np.minimum(h, nat), h)
        # (and the river's bed stays under the water wherever a road's carve reached it: the mill
        # bridge's ends)
        h = np.where(d_river < 11.0, np.minimum(h, RIVER_Y - 1.5), h)
        # beside a deck the ground stays under it for a grid cell past its edge, so no terrain
        # triangle reaches up through its edge
        deck = np.flatnonzero(np.array([roads.kind(i) == "bridge" for i in range(roads.n)]) & ~roads.gap)
        if len(deck):
            d, k = _nearest(P, roads.pos[deck][:, [0, 2]])
            near = d < roads.width[deck][k] / 2 + f.cell + 0.5
            h = np.where(near, np.minimum(h, roads.pos[deck][k, 1] - 0.5), h)
        h = np.minimum(h, f.cap)
        # the layers: cliff rock where it is steep, the needles under the pines, gravel along the
        # railway and in the sawmill's yard, mud on the river's banks
        Hm = h.reshape(f.nz, f.nx)
        gz, gx = np.gradient(Hm, f.cell)
        slope = np.sqrt(gx ** 2 + gz ** 2)
        for _ in range(2):
            pad = np.pad(slope, 1, mode="edge")
            slope = (pad[:-2, 1:-1] + pad[2:, 1:-1] + pad[1:-1, :-2] + pad[1:-1, 2:] + 4.0 * slope) / 8.0
        rock = smoothstep(0.65, 1.05, slope.ravel())
        yard = np.isin(f.style, ("yard", "shedyard", "shed")) & (f.dist < f.half + 30.0)
        pave = np.maximum(smoothstep(5.0, 3.0, rail_d), yard * smoothstep(f.half + 30.0, f.half + 10.0, f.dist)) * \
            (1.0 - rock)
        sand = smoothstep(26.0, 14.0, d_river) * (1.0 - rock) * (1.0 - pave)
        dirt = (1.0 - rock) * (1.0 - pave) * (1.0 - sand) * \
            np.maximum(smoothstep(0.42, 0.68, noise2(x / 55.0, z / 55.0, 47)),
                       smoothstep(f.half + 6.0, f.half, f.dist) * 0.6)
        col = np.stack([dirt, rock, pave, sand], 1).astype(np.float32)
        return h, col

    return {"margin": 300.0, "cell": 3.0, "build": build, "layers": layers}


# ---------------------------------------------------------------- the railway's structures
# the ballast's top under the rails' top, its half widths at the top and at its foot, how far its
# foot reaches under the top; the sleepers' strip (wood/woodtrack001a, its rails 0.67 m out) and
# the steel rails standing on it
BALLAST_TOP, BALLAST_HW, BALLAST_FOOT_HW, BALLAST_FOOT = 0.2, 1.75, 2.5, 0.55
SLEEPER_W = 2.8
RAIL_LAT, RAIL_HW = 0.67, 0.04


def _line_frames(Q):
    """Plan tangents and their right-hand sides (unit, y 0) along a polyline (k, 3)."""
    d = np.gradient(Q, axis=0)
    d[:, 1] = 0.0
    d /= np.linalg.norm(d, axis=1, keepdims=True)
    side = np.stack([-d[:, 2], np.zeros(len(d)), d[:, 0]], 1)
    return d, side


def _on_road(ctx, Q, margin):
    """Which points of a polyline lie on a road (plan, within its half width + margin) at about the
    road's height (the level crossing; not the cutting under the girder bridge)."""
    r = ctx.roads
    d = np.sqrt(((Q[:, None, [0, 2]] - r.pos[None, :, [0, 2]]) ** 2).sum(-1)) - r.width[None, :] / 2
    near = (d < margin) & (np.abs(Q[:, None, 1] - r.pos[None, :, 1]) < 2.0)
    return near.any(1)


def _railway(ctx):
    """Every line of RAIL_LINES: the ballast bed (a gravel prism the karts would ride over as rough
    ground), the sleepers (wood/woodtrack001a, its own flat rails) and both steel rails standing on
    them; on the girder bridge the sleepers lie on its deck; across the road (the level crossing)
    only the rails, flush with the road and a hand of planking between them."""
    gravel = ctx.mats.hl2("nature/forest_gravel_01")
    track = ctx.mats.hl2("wood/woodtrack001a")
    steel = ctx.mats.hl2("metal/metalrail013a")
    planks = ctx.mats.hl2("wood/woodfloor005a")
    for nm, ln in RAIL_LINES.items():
        Q = np.array(ln["points"], float)
        d, side = _line_frames(Q)
        v = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(Q, axis=0), axis=1))])
        # (the crossing: the road and its verges, which lie flush with it there)
        road = _on_road(ctx, Q, 4.6)
        bridge = np.zeros(len(Q), bool)
        if nm == "main":
            z0, z1 = RAIL_BRIDGE["z"]
            bridge = (Q[:, 2] > z0) & (Q[:, 2] < z1)
        up = UP[None].repeat(len(Q), 0)
        # the ballast, its top and both slopes (none on the bridge's deck or on the road)
        for a, b in _mask_runs(~road & ~bridge):
            q, s_, vv, u = Q[a:b], side[a:b], v[a:b], up[a:b]
            top = q - UP * BALLAST_TOP
            L, R = top - s_ * BALLAST_HW, top + s_ * BALLAST_HW
            Lf = q - UP * (BALLAST_TOP + BALLAST_FOOT) - s_ * BALLAST_FOOT_HW
            Rf = q - UP * (BALLAST_TOP + BALLAST_FOOT) + s_ * BALLAST_FOOT_HW
            ctx.meshes["verge"].strip(gravel, L, R, -BALLAST_HW / 2.0, BALLAST_HW / 2.0, vv / 4.0, u, u)
            ctx.meshes["verge"].strip(gravel, Lf, L, 0.0, 0.4, vv / 4.0, u, u)
            ctx.meshes["verge"].strip(gravel, R, Rf, 0.4, 0.0, vv / 4.0, u, u)
            # its ends: the prism's cross-section, facing out along the line
            for k, out in ((0, -d[a]), (-1, d[b - 1])):
                quad = [L[k], R[k], Rf[k], Lf[k]]
                face(ctx.meshes["verge"], gravel, quad, out, plane_uv(quad, quad[0], s_[k], 4.0))
        for a, b in _mask_runs(~road):
            q, s_, vv, u = Q[a:b], side[a:b], v[a:b], up[a:b]
            sl = q - UP * (BALLAST_TOP - 0.04)
            ctx.meshes["decal"].strip(track, sl - s_ * SLEEPER_W / 2, sl + s_ * SLEEPER_W / 2, 0.0, 1.0, vv / SLEEPER_W,
                                      u, u)
            for lat in (-RAIL_LAT, RAIL_LAT):
                c = q + s_ * lat
                lo = c - UP * (BALLAST_TOP - 0.05)
                ctx.meshes["deco"].strip(steel, c - s_ * RAIL_HW, c + s_ * RAIL_HW, 0.0, 0.1, vv / 2.0, u, u)
                for sgn in (-1, 1):
                    e = s_ * (sgn * RAIL_HW)
                    if sgn > 0:
                        ctx.meshes["deco"].strip(steel, c + e, lo + e, 0.0, 0.1, vv / 2.0, s_, s_)
                    else:
                        ctx.meshes["deco"].strip(steel, lo + e, c + e, 0.1, 0.0, vv / 2.0, -s_, -s_)
        # across the road: planking between the rails and both rails' tops flush with it
        for a, b in _mask_runs(road):
            a, b = max(a - 1, 0), min(b + 1, len(Q))
            q, s_, vv, u = Q[a:b] + UP * 0.02, side[a:b], v[a:b], up[a:b]
            ctx.meshes["decal"].strip(planks, q - s_ * 1.05, q + s_ * 1.05, 0.0, 1.0, vv / 2.1, u, u)
            for lat in (-RAIL_LAT, RAIL_LAT):
                c = q + s_ * lat + UP * 0.005
                ctx.meshes["decal"].strip(steel, c - s_ * RAIL_HW, c + s_ * RAIL_HW, 0.0, 0.1, vv / 2.0, u, u)


def _mask_runs(mask):
    """(a, b) index runs where mask holds."""
    out, i, n = [], 0, len(mask)
    while i < n:
        if mask[i]:
            j = i
            while j < n and mask[j]:
                j += 1
            out.append((i, j))
            i = j
        else:
            i += 1
    return [(a, b) for a, b in out if b - a > 1]


def _rail_bridge(ctx):
    """The main line's girder bridge over the rock cutting (RAIL_BRIDGE): two steel plate girders
    either side of the track, the deck between them carrying the sleepers, resting on concrete
    bearings on the cutting's lips."""
    steel = ctx.mats.hl2("metal/metalwall048a")
    concrete = ctx.mats.hl2("concrete/concretewall008a")
    x = RAIL_BRIDGE["center"][0]
    z0, z1 = RAIL_BRIDGE["z"]
    y = RAIL_BRIDGE["rail_y"]
    L = z1 - z0
    zc = (z0 + z1) / 2
    for sgn in (-1, 1):
        ctx.box(steel, [x + sgn * 2.15, y - 0.55, zc], [0.35, 2.0, L], 0.0, rep=2.0)
        # the girders' bottom flanges and the stiffeners every 2 m (seen, not hit)
        ctx.box(steel, [x + sgn * 2.15, y - 1.5, zc], [0.8, 0.1, L], 0.0, kind="deco", rep=2.0)
        for zz in np.arange(z0 + 1.0, z1 - 0.5, 2.0):
            ctx.box(steel, [x + sgn * (2.15 - 0.25 * sgn), y - 0.6, zz], [0.15, 1.7, 0.12], 0.0, kind="deco", rep=1.0)
    ctx.box(steel, [x, y - BALLAST_TOP - 0.25, zc], [4.0, 0.5, L], 0.0, rep=2.0)
    for zz in (z0 + 1.2, z1 - 1.2):
        g = ctx.ground(x, zz)
        top = y - 1.55
        ctx.box(concrete, [x, (top + g - 1.0) / 2, zz], [6.0, top - g + 1.0, 2.4], 0.0, rep=3.0)


def _rail_portals(ctx):
    """The tunnel mouths the main line runs out of at either end of the map (tools/hazards.py's
    portal: piers, wing walls, a lintel and the dark back wall)."""
    for p in RAIL_PORTALS.values():
        at = np.array([p["at"][0], PLATEAU_Y, p["at"][1]])
        d = np.array([p["out"][0], 0.0, p["out"][1]])
        hazards.portal(ctx, at, d)


# ---------------------------------------------------------------- the column's bridge
COLUMN_DECK_T = 1.4   # the deck's depth under its top
COLUMN_PARAPET = (1.1, 0.4)


def _column_bridge(ctx):
    """The concrete bridge the Combine column marches over (COLUMN_PATH): its deck from abutment to
    abutment, parapets both sides, the piers down to the valley's floor and the abutments into the
    hills."""
    mat = ctx.mats.hl2("concrete/concretewall066a")
    top = ctx.mats.hl2("concrete/concretefloor006a")
    x0, x1 = COLUMN_DECK_X
    xc, L = (x0 + x1) / 2, x1 - x0
    z = COLUMN_Z
    w = COLUMN_W + 2 * COLUMN_PARAPET[1]
    ctx.box(mat, [xc, COLUMN_Y - COLUMN_DECK_T / 2, z], [L, COLUMN_DECK_T, w], 0.0, rep=4.0)
    # its walking surface, a hand over the slab's top
    q = [np.array([x0, COLUMN_Y + 0.01, z - COLUMN_W / 2]), np.array([x1, COLUMN_Y + 0.01, z - COLUMN_W / 2]),
         np.array([x1, COLUMN_Y + 0.01, z + COLUMN_W / 2]), np.array([x0, COLUMN_Y + 0.01, z + COLUMN_W / 2])]
    face(ctx.meshes["walls"], top, q, UP, [[p[0] / 5.0, p[2] / 5.0] for p in q])
    # its railings: a low concrete kerb and steel posts and rails on it, not a solid parapet: from the
    # road 11 m below the column marching in the deck's middle shows through them (a parapet as high as
    # their chests hid every soldier from the karts)
    h, t = COLUMN_PARAPET
    steel = ctx.mats.hl2("metal/metalrail013a")
    kerb = 0.3
    n = int(L / 2.5)
    for sgn in (-1, 1):
        zr = z + sgn * (COLUMN_W / 2 + t / 2)
        ctx.box(mat, [xc, COLUMN_Y + kerb / 2, zr], [L, kerb, t], 0.0, rep=3.0)
        for y, s in ((h - 0.05, 0.1), (kerb + (h - kerb) * 0.5, 0.07)):
            ctx.box(steel, [xc, COLUMN_Y + y, zr], [L, s, s], 0.0, kind="deco", rep=2.4)
        for k in range(n + 1):
            ctx.box(steel, [x0 + 0.2 + (L - 0.4) * k / n, COLUMN_Y + (kerb + h) / 2, zr], [0.1, h - kerb, 0.1], 0.0,
                    kind="deco", rep=2.4)
    for px in COLUMN_PIERS:
        g = min(ctx.ground(px + dx, z + dz) for dx in (-1.5, 1.5) for dz in (-3.0, 3.0))
        bot = COLUMN_Y - COLUMN_DECK_T
        ctx.box(mat, [px, (bot + g - 1.5) / 2, z], [2.6, bot - g + 1.5, 4.5], 0.0, rep=4.0)
        ctx.box(mat, [px, bot - 0.6, z], [3.4, 1.2, w], 0.0, rep=4.0)
    for ax in (x0, x1):
        g = min(ctx.ground(ax + dx, z + dz) for dx in (-3.0, 3.0) for dz in (-4.0, 4.0))
        ctx.box(mat, [ax, (COLUMN_Y + g - 2.0) / 2, z], [5.0, COLUMN_Y - g + 2.0, w + 1.0], 0.0, rep=4.0)


# ---------------------------------------------------------------- the sawmill shed
SHELL = 0.6
SHED_BAY = 4.5


def _shells(ctx):
    """The outside of the sawmill's shed (the branch's "shed" stretch): its timber walls' outer faces
    SHELL metres out from the inner ones, from under the yard up to its pitched tin roof; inside, its
    frame: a post against each wall and a tie beam across under the ceiling every SHED_BAY metres
    (between the ceiling's lights), none of it in reach of a kart."""
    wall = ctx.mats.hl2("wood/woodwall009a")
    roof = ctx.mats.hl2("metal/metalroof004a")
    beam = ctx.mats.hl2("wood/woodbeam001a")
    for t in ctx.roads.trks:
        st = t.styles.get("shed")
        if st is None:
            continue
        for ids in t.runs(lambda i: t.style[i] == "shed", with_gaps=True):
            if len(ids) < 2:
                continue
            hw = t.width[ids] / 2 + _wall_gap(t, ids, st) + SHELL
            H = _run_heights(t, ids)
            v = _unwrap_s(t, ids)
            eave = t.pos[ids, 1] + H + SHELL
            inner = hw - SHELL
            bay = np.floor((v - v[0] + SHED_BAY / 2) / SHED_BAY)
            for k in range(1, len(ids) - 1):
                if bay[k] == bay[k - 1]:
                    continue
                i = ids[k]
                yaw = ctx.yaw_facing(t.flat_right[i])
                c = t.pos[i].copy()
                c[1] += H[k] - 0.25
                ctx.box(beam, c, [0.25, 0.4, 2.0 * inner[k]], yaw, kind="deco", rep=3.0)
                for sgn in (-1, 1):
                    q = t.pos[i] + t.flat_right[i] * (sgn * (inner[k] - 0.06))
                    q[1] += H[k] / 2 - 0.1
                    ctx.box(beam, q, [0.3, H[k] + 0.2, 0.14], yaw, kind="deco", rep=3.0)
            for sgn in (-1, 1):
                o = t.pos[ids] + t.flat_right[ids] * (sgn * hw)[:, None]
                bot, tp = o.copy(), o.copy()
                bot[:, 1] = t.pos[ids, 1] - 2.0
                tp[:, 1] = eave
                wall_strip(ctx.meshes["walls"], wall, bot, tp, v, -sgn, 3.0)
            # the roof: from each eave (a metre out) up to the ridge over the middle
            ridge = t.pos[ids].copy()
            ridge[:, 1] = eave + 2.6
            up = UP[None].repeat(len(ids), 0)
            for sgn in (-1, 1):
                e = t.pos[ids] + t.flat_right[ids] * (sgn * (hw + 1.0))[:, None]
                e[:, 1] = eave - 0.4
                a, b = (ridge, e) if sgn > 0 else (e, ridge)
                ctx.meshes["walls"].strip(roof, a, b, 0.0, (hw + 1.0) / 3.0, v / 3.0, up, up)
            # the gables over each end's portal: from the eaves up to the ridge
            for k, sgn_f in ((0, -1.0), (-1, 1.0)):
                i = ids[k]
                c = t.pos[i].copy()
                c[1] = eave[k]
                r = t.flat_right[i] * (hw[k] + 1.0)
                q = [c - r, c + r, c + UP * 2.6]
                face(ctx.meshes["walls"], wall, q, t.fwd[i] * sgn_f, plane_uv(q, q[0], t.flat_right[i], 3.0))


# ---------------------------------------------------------------- guard rails onto the decks
def _flare(ctx, i, back, sgn, wide=2.0, bar=None, end=0.0):
    """A rail that leads in to the railing starting at sample i (a deck's, at its edge) from `wide`
    metres past the verge's outer edge `back` metres before, so a kart out wide is led onto the deck
    instead of into the railing's end (as tools/circuits/city17_circuit.py builds them). None where
    it would come within 2 m of another road; returns whether it was built."""
    t = ctx.trk
    bar = bar or t.styles[t.style[i]]["barrier"]
    n = int(round(back / t.step))
    j0 = t.wrap(i - n)
    vw = t.styles[t.style[j0]].get("verge_w", 0.0)
    thick = min(bar.get("thick", 0.1), 0.4)
    start = vw + wide
    pts = []
    for k in range(n + 1):
        j = t.wrap(i - n + k)
        out = (start + thick - end) * (1.0 - k / n) + end + thick / 2
        pts.append(t.pos[j] + t.right[j] * sgn * t.width[j] / 2 + t.flat_right[j] * sgn * out)
    r = ctx.roads
    own = next(k for k, tr in enumerate(r.trks) if tr is t)
    other = np.flatnonzero((r.route != own) & ~r.gap)
    if len(other):
        P = np.array(pts)[:, [0, 2]]
        d = np.sqrt(((P[:, None, :] - r.pos[other][None, :, [0, 2]]) ** 2).sum(-1)) - r.width[other][None, :] / 2
        if d.min() < 2.0:
            return False
    for a, b in zip(pts[:-1], pts[1:]):
        foot = min(ctx.ground(a[0], a[2]), ctx.ground(b[0], b[2]), a[1], b[1]) - 0.3
        top = max(a[1], b[1]) + bar.get("h", 1.2)
        along = b - a
        ctx.box(bar["mat"], [(a[0] + b[0]) / 2, (foot + top) / 2, (a[2] + b[2]) / 2],
                [thick, top - foot, math.hypot(along[0], along[2]) + 0.05], ctx.yaw_facing(along),
                rep=bar.get("rep", 3.0))
    h, col_h = bar.get("h", 1.2), bar.get("col_h", 0.0)
    if col_h > h + 0.05:
        P = np.array(pts) - np.array([t.flat_right[t.wrap(i - n + k)] * sgn * thick / 2 for k in range(n + 1)])
        v = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(P, axis=0), axis=1))])
        wall_strip(ctx.meshes["colonly"], "colonly", P + UP * h, P + UP * col_h, v, sgn, bar.get("rep", 3.0))
    return True


def _deck_flares(ctx, styles, back=30.0, wide=2.0):
    """Rails flaring in from the verges (from `wide` metres past their outer edge, `back` metres
    before) to the railing of each stretch of `styles` (a deck, or a road whose rails start there)
    where the open road before it has no rail of its own on that side."""
    t = ctx.trk
    for style in styles:
        for run in ctx.runs_of([i for i in range(t.n) if t.style[i] == style], t.n):
            prev = t.wrap(run[0] - 1)
            if t.kind(prev) != "open" or t.gap[run[0]]:
                continue
            bar = t.styles[t.style[prev]].get("barrier")
            for sgn in (-1, 1):
                if bar and (bar.get("sides", "both") == "both" or (bar["sides"] == "right") == (sgn > 0)):
                    continue
                _flare(ctx, run[0], back, sgn, wide=wide)


def decorate(ctx):
    """The layout's own structures first: the railway's beds, rails, girder bridge and portals, the
    column's bridge, the sawmill shed's outside and the guard rails that lead in to the mill turn's
    and the mill bridge's rails; then the set dressing (_dress)."""
    _railway(ctx)
    _rail_bridge(ctx)
    _rail_portals(ctx)
    _column_bridge(ctx)
    _shells(ctx)
    _deck_flares(ctx, ("millbridge",))
    # (onto the mill turn's outer rail a long one from well out past the verge: karts run wide off the
    # riverside road there as the sawmill shed's branch merges, and one that passed outside a short
    # flare was caught between the rail and the bank and had to be rescued)
    _deck_flares(ctx, ("millturn",), back=50.0, wide=7.0)
    # (into the ridge's cutting: its rock walls start at the road's edge out of open ground, and karts
    # knocked wide before it hit a wall's end or climbed the bank outside it and stuck there until the
    # watchdog rescued them; a low rock wall leads in from well out past the verge, like the mill turn's)
    t = ctx.trk
    lead = {"mat": ctx.mats.hl2("nature/cliff01a"), "h": 1.4, "thick": 0.6, "rep": 4.0, "col_h": 3.5}
    for run in ctx.runs_of([i for i in range(t.n) if t.style[i] == "ridgecut"], t.n):
        for sgn in (-1, 1):
            if not _flare(ctx, run[0], 50.0, sgn, wide=7.0, bar=lead):
                print("white_forest: no lead-in wall on the %s of the ridge's cutting" % ("right" if sgn > 0 else "left"))
    _dress(ctx)


# ---------------------------------------------------------------- set dressing
# The forest round the layout. The big pieces first (the standing and derailed trains, the wreck in
# the gorge, the sawmill's yard, the rebels' camp, the Combine's barricade under the column's bridge,
# rocks, logs, poles, the sign), then the pines between them: a row of them a few metres past the
# verges and fewer further back (real models, a trunk a kart can hit), and past those the forest as
# Episode Two draws its far hills, crossed cards of a tree line (one mesh, seen, never hit). The
# spectators (crowds) stand in clearings left for them.

# every railway line's points: plan distances to the nearest line (the points lie 4 m apart, so a
# distance taken to the nearest point is up to 2 m too long; the margins below allow for it)
RAIL_ALL = np.concatenate([np.array(ln["points"], float) for ln in RAIL_LINES.values()])
# the sawmill's yard (x0, x1, z0, z1): the log stacks, the mill siding and the shed, no trees
YARD = (40.0, 135.0, -60.0, 250.0)
# the logging trail's dry gully (its middle, plan) and the ground round it kept free of trees (a
# kart that drops into it drives out, the karts on the landing see the gully ahead)
GULLY_C, GULLY_R = (225.0, -240.0), 25.0
# the rebels' camp inside the bend onto the start straight (plan centre, radius of its clearing)
CAMP, CAMP_R = (-302.0, 284.0), 14.0
# the rock mass inside the hairpin, and the Combine's barricade between the valley's legs under the
# column's bridge (plan centres)
HAIRPIN_ROCK = (250.0, -21.0)
BARRICADE = (250.0, -46.0)
# where the spectators stand (crowds): (lap metres from, to, side +1 right / -1 left / 0 both, metres
# past the lap road's edge) kept free of trees, whose crowns they would stand under
CROWD_CLEAR = [(2674.0, 2864.0, -1, 21.0),    # the start, west of the road (the railway's fence east)
               (350.0, 386.0, 1, 10.0), (455.0, 491.0, -1, 10.0),   # the cutting's lips
               (570.0, 640.0, 0, 12.0),       # the gorge road before the see-saw, behind its rails
               (803.0, 846.0, -1, 14.0),      # past the see-saw's exit deck, watching it
               # outside the hairpin and its exit onto the west leg: a glade (karts run wide there,
               # up to 20 m off the road, and stopped dead against the pines that stood there)
               (1235.0, 1365.0, -1, 30.0),
               (1585.0, 1632.0, -1, 14.0),    # the riverside road, the hill side
               (2085.0, 2118.0, -1, 14.0),    # outside the mill turn
               (2362.0, 2398.0, -1, 17.0)]    # waiting by the level crossing, south of the road
# the pines (weights) along the roads, the dead and dry ones among them, the scales they come in (the
# lighter models most: tree_pine_tall_02 is 800 triangles, tree_pine06 and the HL2 pines over 2000)
TREES = [("props_foliage/tree_pine_tall_02", 6.0), ("props_foliage/tree_pine_01", 4.0), ("props_foliage/tree_pine_02", 4.0),
         ("props_foliage/tree_pine06", 2.0), ("props_foliage/tree_pine05", 2.0), ("props_foliage/tree_pine04", 1.0),
         ("props_foliage/tree_pine_tall_01", 1.0), ("props_foliage/tree_pine_large", 1.0)]
DEAD_TREES = ["props_foliage/tree_dead02", "props_foliage/tree_dry01", "props_foliage/tree_dry02"]
TREE_SCALES = (0.9, 1.0, 1.1, 1.2)
# the game draws a prop no further than 420 m unless its box is over 25 m across (Track._spawn_props):
# a tree is scaled up only while it stays under that
TREE_BIG = 24.5


def _lap_i(t, s):
    """The lap's sample at lap metres s."""
    return int(round((s % t.length) / t.step)) % t.n


def _stand(ctx, model, q, yaw, tol=0.6, sink=0.0, **kw):
    """A prop standing on the ground at plan point q, on the lowest ground under its footprint and
    `sink` metres into it: its placed entry, or None where that ground varies by more than tol or the
    prop is refused (Ctx.add)."""
    if model not in ctx.models:
        ctx.missing.add(model)
        return None
    q = np.array(q, float)
    g = ctx.site(model, q, yaw, kw.get("scale", 1.0), tol=tol)
    if g is None:
        return None
    q[1] = g - sink
    return ctx.props[-1] if ctx.add(model, q, yaw, **kw) else None


def _centred(ctx, model, c, yaw, scale=1.0):
    """The plan origin that puts a model's box centred on plan point c when it is turned by yaw (big
    HL2 models are rarely centred on their origin)."""
    m = ctx.models[model]
    lx = (m["aabb_min"][0] + m["aabb_max"][0]) / 2 * scale
    lz = (m["aabb_min"][2] + m["aabb_max"][2]) / 2 * scale
    cy, sy = math.cos(yaw), math.sin(yaw)
    return np.array([c[0] - lx * cy - lz * sy, c[1], c[2] + lx * sy - lz * cy])


def _fire(ctx, q, size=1.0, smoke=1.0, light=False):
    """A fire for scripts/fx/ruin_fires.gd with its flames at q (the camp's fire in a drum)."""
    ctx.fires.append({"pos": [round(float(c), 2) for c in q], "size": round(float(size), 2),
                      "smoke": round(float(smoke), 2), "light": bool(light)})


def _plan_info(ctx, P):
    """For plan points P (n, 2): metres to the nearest edge of any road (a branch's too), the lap's
    nearest sample to each, the side of the lap it is on (+1 right), metres past the lap road's own
    edge, and metres to the nearest railway line."""
    r = ctx.roads
    R, hw = r.pos[:, [0, 2]], r.width / 2
    gap = np.empty(len(P))
    for a in range(0, len(P), 2048):
        d = np.sqrt(((P[a:a + 2048, None, :] - R[None, :, :]) ** 2).sum(-1)) - hw[None, :]
        gap[a:a + 2048] = d.min(1)
    t = ctx.trk
    d, li = _nearest(P, t.pos[:, [0, 2]])
    rel = P - t.pos[li][:, [0, 2]]
    side = np.where((rel * t.flat_right[li][:, [0, 2]]).sum(1) >= 0.0, 1, -1)
    rail, _ = _nearest(P, RAIL_ALL[:, [0, 2]])
    return gap, li, side, d - t.width[li] / 2, rail


def _excluded(P, extra=0.0):
    """Which plan points P (n, 2) are kept free of trees (`extra` metres more round each place for
    the tree line's cards): the sawmill's yard, the logging trail's gully, the level crossing (the
    train's arms and signals), the rebels' camp, the rock mass in the hairpin, the barricade, the
    tunnel portals' mouths and the column's bridge (its deck over the trees' crowns)."""
    x, z = P[:, 0], P[:, 1]
    out = (x > YARD[0] - extra) & (x < YARD[1] + extra) & (z > YARD[2] - extra) & (z < YARD[3] + extra)
    for (cx, cz), r in ((GULLY_C, GULLY_R), (RAIL_CROSSING, 35.0), (CAMP, CAMP_R), (HAIRPIN_ROCK, 14.0),
                        (BARRICADE, 10.0)):
        out |= np.hypot(x - cx, z - cz) < r + extra
    for p in RAIL_PORTALS.values():
        out |= np.hypot(x - p["at"][0], z - p["at"][1]) < 25.0 + extra
    out |= (x > COLUMN_DECK_X[0] - 12.0 - extra) & (x < COLUMN_DECK_X[1] + 12.0 + extra) & \
        (np.abs(z - COLUMN_Z) < COLUMN_W / 2 + 12.0 + extra)
    return out


def _crowd_clear(ctx, li, side, lgap):
    """Which points (their lap sample, side and metres past the lap's edge) lie in a clearing the
    spectators stand in (CROWD_CLEAR)."""
    t = ctx.trk
    s = t.s[li]
    out = np.zeros(len(li), bool)
    for s0, s1, sgn, gmax in CROWD_CLEAR:
        inside = ((s - s0) % t.length) <= (s1 - s0)
        out |= inside & ((side == sgn) | (sgn == 0)) & (lgap < gmax)
    return out


def _grid(ctx, x0, x1, z0, z1, step, jitter):
    """Plan points on a grid `step` metres apart over the box, each moved up to `jitter` metres."""
    xs, zs = np.meshgrid(np.arange(x0, x1, step), np.arange(z0, z1, step))
    P = np.stack([xs.ravel(), zs.ravel()], 1)
    return P + ctx.rng.uniform(-jitter, jitter, P.shape)


def _sidings(ctx):
    """The standing trains (tools/hazards.py lay_consist: every car with both bogies on its rails,
    coupled): a long freight train on the passing loop beyond the main line along the start straight
    (the moving train runs between it and the road), two trains in the south yard inside the main
    line's bend, a train on the north siding by the north portal with its last wagon derailed beside
    the track, tilted, and the sawmill's ore cars on the log siding. Cars within 4.5 m of the main
    line stand in its corridor: they carry the hazard's tag. Returns the cars placed."""
    L = RAIL_LINES
    tr = "props_trainstation/"
    n = 0
    # the passing loop: its turnout to the main line starts 36 m before its north end, the first train
    # stands clear of it, a short cut of wagons further south
    n += hazards.lay_consist(ctx, L["parallel_loop"]["points"],
                             [tr + c for c in ("diesel", "train_boxcar", "train_boxcar", "train_orecar", "train_orecar",
                                               "train003", "train_boxcar_damaged", "train_orecar", "boxcar2a")],
                             start=282.0, facing=1, tag="hazard")
    n += hazards.lay_consist(ctx, L["parallel_loop"]["points"],
                             [tr + c for c in ("train_boxcar", "train003", "train_orecar", "train003_damaged1",
                                               "train_boxcar")],
                             start=124.0, facing=1, tag="hazard")
    # the south yard: a locomotive and its freight on the track nearer the main line, odd wagons on
    # the other
    n += hazards.lay_consist(ctx, L["south_yard_1"]["points"],
                             [tr + c for c in ("train_engine", "train_boxcar", "train_boxcar", "train_orecar",
                                               "train_orecar", "train_boxcar_damaged")],
                             start=146.0, facing=1, tag="hazard")
    n += hazards.lay_consist(ctx, L["south_yard_2"]["points"],
                             [tr + c for c in ("train_outro_car01", "boxcar2a", "train003", "train003_damaged1")],
                             start=64.0, facing=1)
    # the north siding: a train facing the turnout, its last wagon off the rails on the side away
    # from the main line (right of the way it faces: west)
    n += hazards.lay_consist(ctx, L["north_siding"]["points"],
                             [tr + c for c in ("train_engine", "train_boxcar", "train_orecar", "train_boxcar",
                                               "train_orecar", "train_boxcar_damaged")],
                             start=44.0, facing=-1, tag="hazard",
                             derail={"car": -1, "off": 3.6, "yaw": 0.32, "lean": 0.38, "dip": 0.06})
    # the sawmill's log siding: ore cars waiting to be loaded
    n += hazards.lay_consist(ctx, L["mill_siding"]["points"],
                             [tr + c for c in ("train_orecar", "train_orecar", "train003", "train_orecar")],
                             start=150.0, facing=1)
    return n


def _lay_on_side(ctx, m, c, yaw, bottom):
    """Car model m (its long axis x) lying on its side at plan point c, its lowest point at `bottom`:
    turned a quarter about its long axis (pitch, Godot's YXZ order: (x, y, z) -> (x, -z, y)) so its +z
    side lies on the ground. Episode Two's wrecked_train maps that side onto a plain grey patch of its
    texture (it stood against a wall), which stood up as a white slab. No collision (tag "far": none
    is ever in reach of a kart); its footprint is blocked so no tree grows through it."""
    mm = ctx.models[m]
    lo, hi = np.array(mm["aabb_min"], float), np.array(mm["aabb_max"], float)
    lx, lz = (lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2
    cy, sy = math.cos(yaw), math.sin(yaw)
    q = np.array([c[0] - lx * cy - lz * sy, bottom + hi[2], c[1] + lx * sy - lz * cy])
    ctx.add(m, q, yaw, ground=False, base=False, tag="far", pitch=math.pi / 2)
    ctx.block([c[0], bottom + (hi[2] - lo[2]) / 2, c[1]], [hi[0] - lo[0], hi[2] - lo[2], hi[1] - lo[1]], yaw)


def _wrecks(ctx):
    """Wrecks off the rails: two cars of Episode Two's derailed train on their sides west of the
    north siding (beside the girder bridge's line, out of the moving train's way); in the see-saw's
    gorge the cars that fell with the old bridge lying in the river north of the span, a car on its
    side south of it, log jams and rocks on the banks (seen from the span, never reached: its walls
    and the decks' parapets keep the karts up there)."""
    rng = ctx.rng
    wreck = "props_trainstation/wrecked_train"
    if wreck in ctx.models:
        c = (-301.0, -452.0)
        g = min(ctx.ground(c[0] + dx, c[1] + dz) for dx in (-7.0, 0.0, 7.0) for dz in (-3.0, 3.0))
        _lay_on_side(ctx, wreck, c, math.pi / 2 + 0.42, g - 0.3)
        # (in the gorge: its side 2 m out of the water)
        _lay_on_side(ctx, wreck, (43.0, -262.0), math.pi / 2 + 0.15, RIVER_Y - 1.6)
    else:
        ctx.missing.add(wreck)
    m = "props_trainstation/passengercar001"
    if m in ctx.models:
        yaw = math.pi / 2 - 0.3
        _stand(ctx, m, _centred(ctx, m, np.array([-304.0, 0.0, -405.0]), yaw), yaw, tol=2.5, sink=0.4)
    else:
        ctx.missing.add(m)
    # (tag "far": no collision, nothing keeps them off; the river's bed lies RIVER_Y - 3 in its channel)
    for m, c, yaw, bottom in (("map1_bridge/traincars", (38.0, -352.0), math.pi / 2, RIVER_Y - 4.5),
                              ("props_forest/riverlogs", (37.0, -226.0), 0.6, RIVER_Y - 3.0),
                              ("props_forest/riverlogs", (47.0, -400.0), 2.3, RIVER_Y - 3.0),
                              ("props_forest/riverlogs", (36.0, -72.0), 1.1, RIVER_Y - 3.0),
                              ("props_forest/riverlogs", (10.0, 352.0), 4.0, RIVER_Y - 3.0)):
        if m not in ctx.models:
            ctx.missing.add(m)
            continue
        q = _centred(ctx, m, np.array([c[0], 0.0, c[1]]), yaw)
        q[1] = bottom - ctx.models[m]["aabb_min"][1]
        ctx.add(m, q, yaw, ground=False, base=False, tag="far")
    # rocks on the gorge's banks either side of the span (clear of it: the see-saw keeps 8.5 m)
    for m, c, sc in (("cliffs/rockcluster01", (6.0, -336.0), 1.0), ("cliffs/rockcluster01", (74.0, -266.0), 1.2),
                     ("cliffs/rocks_xlarge01", (12.0, -268.0), 1.4), ("cliffs/rocks_xlarge01", (70.0, -334.0), 1.3),
                     ("props_foliage/forestrock_single01", (60.0, -350.0), 1.5),
                     ("props_foliage/forestrock_single01", (22.0, -246.0), 1.4)):
        if ctx.ground(*c) > RIVER_Y - 0.5:
            _stand(ctx, m, [c[0], 0.0, c[1]], rng.uniform(0, 6.28), tol=8.0, sink=1.2, scale=sc)
    # pilings beside the mill bridge in the river, a log jam under it
    for x, z in ((0.0, 302.0), (14.0, 300.0), (4.0, 330.0), (16.0, 331.0)):
        g = ctx.ground(x, z)
        if g < RIVER_Y - 1.0:
            ctx.add("props_docks/piling_cluster01a", [x, g, z], rng.uniform(0, 6.28), ground=False)


def _sawmill(ctx):
    """The sawmill's yard between the shed and the yard road: rows of stacked logs (two high here and
    there), sawhorses with logs on them, fuel drums and crates, the mill's old truck; trail fences
    along the riverside road's hill side and stacks of logs beside the log siding."""
    rng = ctx.rng
    logs = "props_forest/sawmill_logs"
    placed = 0
    for x in (80.0, 87.0, 94.0):
        for z in np.arange(24.0, 146.0, 9.0):
            q = np.array([x + rng.uniform(-0.8, 0.8), 0.0, z + rng.uniform(-1.0, 1.0)])
            yaw = rng.uniform(-0.12, 0.12)
            if logs not in ctx.models or not ctx.fits(logs, q, yaw, 6.5):
                continue
            p = _stand(ctx, logs, q, yaw, tol=0.8, sink=0.05)
            if p is None:
                continue
            placed += 1
            if rng.random() < 0.45:
                # (a second stack on it: its bottom on the first one's top)
                h = ctx.models[logs]["aabb_max"][1] - ctx.models[logs]["aabb_min"][1]
                if ctx.add(logs, np.array(p["pos"]) + UP * h, yaw + rng.uniform(-0.08, 0.08), ground=False, base=False):
                    placed += 1
    # sawhorses with a sawn log across them by the shed's east side (their beams across the log)
    horse = "props_forest/sawhorse"
    for z in (32.0, 58.0, 118.0):
        tops = []
        for dz in (-1.4, 1.4):
            p = _stand(ctx, horse, [76.0, 0.0, z + dz], math.pi / 2, tol=0.5)
            if p is not None:
                tops.append(p["pos"][1] + ctx.models[horse]["aabb_max"][1])
        if len(tops) == 2:
            ctx.add("props_forest/log", [76.0, max(tops), z], math.pi / 2, ground=False)
    for m, c, yaw in (("props_vehicles/truck001a", (98.0, 152.0), 2.2), ("props_c17/oildrum001", (101.0, 18.0), 0.0),
                      ("props_c17/oildrum001", (102.0, 19.2), 0.0), ("props_c17/oildrum001", (100.8, 19.6), 0.0),
                      ("props_junk/wood_crate001a", (79.0, 150.0), 0.3), ("props_junk/wood_crate002a", (80.5, 151.2), 1.0),
                      ("props_junk/wood_pallet001a", (82.0, 148.0), 0.2)):
        if m in ctx.models and ctx.fits(m, np.array([c[0], 0.0, c[1]]), yaw, 5.5):
            _stand(ctx, m, [c[0], 0.0, c[1]], yaw, tol=0.8)
    # stacked logs beside the log siding, opposite the shed
    for z in (40.0, 70.0, 175.0, 196.0):
        _stand(ctx, logs, [43.0, 0.0, z], math.pi / 2 + rng.uniform(-0.1, 0.1), tol=0.9, sink=0.05)
    return placed


def _camp(ctx):
    """The rebels' camp inside the bend onto the start straight (out of the level crossing's way): their
    truck, a fire in a drum, hay bales to sit on, crates and drums, a table. Returns its centre and the
    lap sample it faces (crowds)."""
    t = ctx.trk
    c = np.array([CAMP[0], 0.0, CAMP[1]])
    c[1] = ctx.ground(c[0], c[2])
    i = int(np.argmin(((t.pos[:, [0, 2]] - c[[0, 2]]) ** 2).sum(1)))
    road = ctx.yaw_facing(t.pos[i] - c)
    hay = "props_outland/haybale"
    for m, dx, dz, yaw in (("props_vehicles/truck001a", 7.0, -6.0, 0.9), ("props_c17/oildrum001", 0.0, 0.0, 0.0),
                           (hay, 2.4, 1.6, 0.3), (hay, -2.2, 2.0, 2.6), (hay, -1.8, -2.4, 1.1), (hay, 2.6, -1.8, 4.0),
                           ("props_junk/wood_crate001a", -6.0, 4.0, 0.2), ("props_junk/wood_crate001a", -6.2, 5.2, 0.9),
                           ("props_junk/wood_crate002a", -4.8, 5.0, 0.4), ("props_borealis/bluebarrel001", -7.0, -2.0, 0.0),
                           ("props_borealis/bluebarrel001", -7.6, -1.2, 0.0), ("props_vehicles/tire001a_tractor", 5.0, 4.5, 1.2),
                           ("props_wasteland/cafeteria_table001a", 0.5, 6.0, road + 1.57),
                           ("props_c17/bench01a", 0.5, 7.6, road + 1.57)):
        _stand(ctx, m, c + np.array([dx, 0.0, dz]), yaw, tol=0.7)
    _fire(ctx, c + UP * 1.3, size=0.4, smoke=0.6, light=True)
    return c, i


def _valley(ctx):
    """The valley under the column's bridge: a mass of rock inside the hairpin (well off its inner
    verge), and the Combine's barricade between the legs by the bridge's middle pier, its lamp."""
    rng = ctx.rng
    m = "cliffs/rockcluster01"
    q = np.array([HAIRPIN_ROCK[0], 0.0, HAIRPIN_ROCK[1]])
    if m in ctx.models:
        for sc, turn in ((0.85, 0.5), (0.75, 2.1), (0.65, 3.6)):
            o = _centred(ctx, m, q, turn, sc)
            if ctx.fits(m, o, turn, 10.0):
                _stand(ctx, m, o, turn, tol=6.0, sink=1.2, scale=sc)
                break
    _stand(ctx, "props_foliage/tree_dead02", q + np.array([-3.0, 0.0, -9.0]), rng.uniform(0, 6.28), tol=3.0, sink=0.3)
    b = np.array([BARRICADE[0], 0.0, BARRICADE[1]])
    for m, dx, dz, yaw in (("props_combine/combine_barricade_tall01a", -9.0, 0.0, 0.0),
                           ("props_combine/combine_barricade_med01a", -6.5, 0.3, 0.1),
                           ("props_combine/combine_barricade_tall01a", -4.0, 0.0, -0.1),
                           ("props_combine/combine_barricade_med01a", 4.5, 0.2, 0.15),
                           ("props_combine/combine_barricade_tall01a", 7.0, 0.0, 0.0),
                           ("props_combine/combine_light001a", 9.5, 1.2, math.pi)):
        _stand(ctx, m, b + np.array([dx, 0.0, dz]), yaw, tol=0.8)


def _poles(ctx):
    """Wooden utility poles: along the railway's far side past the standing freight, and up the west
    bank's climb on the hill side (they are knocked over by a kart, like any pole)."""
    t = ctx.trk
    pole = "props_forest/utilitypole01b"
    # (its cross arm along the model's z: turned square to the line of poles the wires run along)
    for z in np.arange(140.0, -290.0, -45.0):
        q = np.array([RAIL_X + 14.0, 0.0, z])
        if pole in ctx.models and ctx.fits(pole, q, math.pi / 2, 4.0):
            _stand(ctx, pole, q, math.pi / 2, tol=1.0)
    for s in np.arange(2186.0, 2366.0, 40.0):
        i = _lap_i(t, s)
        q = ctx.side(i, 1, t.styles[t.style[i]].get("verge_w", 4.0) + 3.5)
        _stand(ctx, pole, q, ctx.yaw_facing(t.flat_right[i]), tol=1.2)


def _sign(ctx):
    """Episode Two's White Forest sign on a post on the start straight's west verge, turned to the
    karts coming up it."""
    t = ctx.trk
    m = "props_forest/whiteforestsign"
    if m not in ctx.models:
        ctx.missing.add(m)
        return
    i = _lap_i(t, 150.0)
    q = ctx.side(i, -1, t.styles[t.style[i]].get("verge_w", 4.0) + 2.0)
    g = ctx.ground(q[0], q[2])
    face = -t.fwd[i] * 0.85 + t.flat_right[i] * 0.5
    sc = 3.0
    if ctx.add(m, [q[0], g + 2.6, q[2]], ctx.yaw_front(m, face), scale=sc, ground=False, base=False):
        back = -face / np.linalg.norm(face) * 0.12
        ctx.box(ctx.mats.hl2("wood/woodbeam001a"), [q[0] + back[0], g + 1.2, q[2] + back[2]], [0.2, 3.0, 0.2],
                ctx.yaw_facing(face), rep=1.0)


def _scatter(ctx, models, band, prob, step, sink=0.2, tol=1.5, scales=(1.0,), margin=None, level=None):
    """Props scattered on the ground beside the roads: on a grid `step` metres apart, those `band`
    metres past the nearest road's edge (any road), with chance `prob` (more in clumps), out of the
    trees' exclusions and the spectators' clearings, `margin` metres off every road's edge (its whole
    footprint), off the railway, on dry ground; `level` keeps them within that many metres of the
    nearest road's height (the cover on the roadside, not down a bank). Returns the number placed."""
    t = ctx.trk
    rng = ctx.rng
    lo = ctx.roads.pos[:, [0, 2]].min(0) - band[1] - 2.0
    hi = ctx.roads.pos[:, [0, 2]].max(0) + band[1] + 2.0
    P = _grid(ctx, lo[0], hi[0], lo[1], hi[1], step, step * 0.42)
    gap, li, side, lgap, rail = _plan_info(ctx, P)
    clump = noise2(P[:, 0] / 55.0, P[:, 1] / 55.0, 63)
    # (nothing solid within 14 m of the outside of a bend: see _trees)
    a, b = t.fwd[(li - 5) % t.n], t.fwd[(li + 5) % t.n]
    turn = a[:, 2] * b[:, 0] - a[:, 0] * b[:, 2]
    wide = (np.abs(turn) > 0.2) & (side == np.sign(turn)) & (lgap < 14.0) & (margin is not None)
    keep = (gap > band[0]) & (gap < band[1]) & (rail > 7.0) & ~_excluded(P) & ~_crowd_clear(ctx, li, side, lgap) & \
        ~wide & (rng.random(len(P)) < prob * (0.3 + 1.4 * clump))
    n = 0
    for (x, z), j in zip(P[keep], np.flatnonzero(keep)):
        g = ctx.ground(x, z)
        if g < RIVER_Y + 0.8:
            continue
        if level is not None and abs(g - t.pos[li[j]][1]) > level:
            continue
        m = models[int(rng.integers(0, len(models)))]
        if m not in ctx.models:
            ctx.missing.add(m)
            continue
        yaw = rng.uniform(0, 6.28)
        sc = scales[int(rng.integers(0, len(scales)))]
        if margin is not None and not ctx.fits(m, np.array([x, g, z]), yaw, margin):
            continue
        if _stand(ctx, m, [x, 0.0, z], yaw, tol=tol, sink=sink, scale=sc) is not None:
            n += 1
    return n


def _trees(ctx):
    """The pines along every road: a row a few metres past the verges (thinned in clumps and glades)
    and fewer further back, a dead or dry one now and then. A tree keeps its crown and three metres
    more off the road's edge (none hangs over the road), off the railway (the trains pass under no
    branch), off the river and steep ground, out of the clearings and away from the next trunk;
    its trunk is a box later props keep out of. Returns the number placed."""
    t = ctx.trk
    rng = ctx.rng
    lo = ctx.roads.pos[:, [0, 2]].min(0) - 40.0
    hi = ctx.roads.pos[:, [0, 2]].max(0) + 40.0
    P = _grid(ctx, lo[0], hi[0], lo[1], hi[1], 6.0, 2.6)
    gap, li, side, lgap, rail = _plan_info(ctx, P)
    clump = noise2(P[:, 0] / 70.0, P[:, 1] / 70.0, 61)
    prob = np.where(gap < 15.0, 0.34, 0.09) * (0.3 + 1.4 * clump)
    # on the outside of the lap's bends (tighter than about 100 m) the first pines stand further back:
    # a kart that runs wide there finds open ground before the trunks
    a, b = t.fwd[(li - 5) % t.n], t.fwd[(li + 5) % t.n]
    turn = a[:, 2] * b[:, 0] - a[:, 0] * b[:, 2]
    wide = (np.abs(turn) > 0.2) & (side == np.sign(turn)) & (lgap < 14.0)
    keep = (gap > 6.8) & (gap < 34.0) & (rail > 6.0) & ~_excluded(P) & ~_crowd_clear(ctx, li, side, lgap) & \
        ~wide & (rng.random(len(P)) < prob)
    P, gap, rail = P[keep], gap[keep], rail[keep]
    names = [m for m, _w in TREES]
    w = np.array([wt for _m, wt in TREES])
    trunks = {}
    n = 0
    for k in rng.permutation(len(P)):
        x, z = P[k]
        m = DEAD_TREES[int(rng.integers(0, len(DEAD_TREES)))] if rng.random() < 0.12 else \
            names[int(rng.choice(len(names), p=w / w.sum()))]
        if m not in ctx.models:
            ctx.missing.add(m)
            continue
        mm = ctx.models[m]
        lo_, hi_ = np.array(mm["aabb_min"]), np.array(mm["aabb_max"])
        sc = TREE_SCALES[int(rng.integers(0, len(TREE_SCALES)))]
        if np.linalg.norm(hi_ - lo_) * sc > TREE_BIG:
            sc = 1.0
        crown = float(np.abs([lo_[0], hi_[0], lo_[2], hi_[2]]).max()) * sc
        if gap[k] < max(7.0, crown + 3.0) or rail[k] < crown + 2.5:
            continue
        g = ctx.ground(x, z)
        if g < RIVER_Y + 1.0:
            continue
        around = [ctx.ground(x + dx, z + dz) for dx, dz in ((1.5, 0.0), (-1.5, 0.0), (0.0, 1.5), (0.0, -1.5))]
        if max(around) - min(around) > 2.0:
            continue
        cell = (int(x // 8.0), int(z // 8.0))
        near = [o for a in (-1, 0, 1) for b in (-1, 0, 1) for o in trunks.get((cell[0] + a, cell[1] + b), ())]
        if any(math.hypot(ox - x, oz - z) < max(4.0, 0.5 * (crown + oc)) for ox, oz, oc in near):
            continue
        if not ctx.free([x, g + 3.0, z], [1.2, 6.0, 1.2]):
            continue
        if ctx.add(m, [x, g - 0.25, z], rng.uniform(0, 6.28), scale=sc, solid=False):
            ctx.block([x, g + 3.0, z], [1.0, 6.0, 1.0])
            trunks.setdefault(cell, []).append((x, z, crown))
            n += 1
    return n


def _treeline(ctx):
    """The forest beyond the pines as Episode Two draws its far hills: crossed cards of its tree line
    (nature/clifftrees_cardboard02a, cut out and seen from both sides) standing on the hills from 30 m
    past the roads out to the land's edge, in clumps with glades between; one mesh with no collision
    and no shadow, lit like the ground under it. Returns the number of cards."""
    rng = ctx.rng
    mat = ctx.mats.hl2("nature/clifftrees_cardboard02a")
    if not ctx.mats.info(mat).get("albedo"):
        # (Episode Two's card: without it no cards, not thousands of grey slabs)
        return 0
    f = ctx.field
    P = _grid(ctx, f.xs[0] + 20.0, f.xs[-1] - 20.0, f.zs[0] + 20.0, f.zs[-1] - 20.0, 19.0, 7.0)
    gap, li, side, lgap, rail = _plan_info(ctx, P)
    clump = noise2(P[:, 0] / 90.0, P[:, 1] / 90.0, 67)
    keep = (gap > 32.0) & (gap < 290.0) & (rail > 14.0) & ~_excluded(P, 20.0) & (clump > 0.3)
    up = [UP] * 4
    n = 0
    for x, z in P[keep]:
        g = ctx.ground(x, z)
        if g < RIVER_Y + 1.5:
            continue
        w = rng.uniform(16.0, 26.0)
        # (not through a wreck, a portal's wing wall or anything else built there)
        if not ctx.free([x, g + 4.0, z], [w * 0.5, 8.0, w * 0.5]):
            continue
        h = w * 0.62
        a0 = rng.uniform(0.0, math.pi)
        for ang in (a0, a0 + math.pi / 2):
            d = np.array([math.cos(ang), 0.0, math.sin(ang)]) * (w / 2)
            ends = []
            for e in (-1.0, 1.0):
                ex, ez = x + d[0] * e, z + d[2] * e
                ends.append(np.array([ex, min(ctx.ground(ex, ez), g) - 1.3, ez]))
            quad = [ends[0], ends[1], ends[1] + UP * h, ends[0] + UP * h]
            ctx.meshes["deco"].add(mat, quad, up, [[0.0, 1.0], [1.0, 1.0], [1.0, 0.0], [0.0, 0.0]], [0, 1, 2, 0, 2, 3])
            n += 1
    return n


def _dress(ctx):
    """The set dressing (see the header above RAIL_ALL); prints what it placed."""
    ctx.fires = []
    n0 = len(ctx.props)
    cars = _sidings(ctx)
    _wrecks(ctx)
    yard = _sawmill(ctx)
    ctx.camp = _camp(ctx)
    _valley(ctx)
    _poles(ctx)
    _sign(ctx)
    rocks = _scatter(ctx, ["props_foliage/rock_forest03", "props_foliage/rock_forest04", "props_foliage/forestrock_cluster01",
                           "cliffs/rocks_large01", "cliffs/rocks_large01_veg", "cliffs/rocks_medium01",
                           "props_foliage/forestrock_single01"], (7.0, 28.0), 0.03, 6.0, sink=0.35, tol=1.6,
                     scales=(0.8, 1.0, 1.25), margin=6.0)
    logs = _scatter(ctx, ["props_foliage/tree_stump01", "props_foliage/tree_stump01", "props_forest/log",
                          "props_foliage/fallentree02", "props_foliage/fallentree_dry01"], (7.5, 24.0), 0.022, 6.0,
                    sink=0.15, tol=1.2, margin=6.5)
    trees = _trees(ctx)
    cover = _scatter(ctx, ["props_foliage/ferns02", "props_foliage/fern01", "props_foliage/grass_cluster02",
                           "props_foliage/grass_cluster03", "props_foliage/shrub_small"], (4.8, 10.0), 0.09, 5.0,
                     sink=0.05, tol=0.8, margin=4.6, level=1.5)
    cards = _treeline(ctx)
    print("  dressing: %d props (%d trees, %d train cars, %d log stacks, %d rocks, %d stumps and logs, %d ferns "
          "and grass), %d tree-line cards" % (len(ctx.props) - n0, trees, cars, yard, rocks, logs, cover, cards))


def decorate_branch(ctx, spec):
    """The sawmill shed's floor beside its road: sawhorses, sawn logs and fuel drums against its walls,
    off the road (the pines along both branches come from _trees, which dresses every road)."""
    t = ctx.trk
    if spec["id"] != "sawmill_shed":
        return
    ids = [i for i in range(t.n) if t.style[i] == "shed" and not t.junction[i]]
    kit = ("props_forest/sawhorse", "props_forest/log", "props_c17/oildrum001", "props_forest/log")
    for k, i in enumerate(ids[3:-3:5]):
        ctx.against_wall(i, 1 if k % 2 else -1, kit[k % len(kit)], inset=0.1)


# ---------------------------------------------------------------- spectators
def _open(ctx, i):
    t = ctx.trk
    return t.kind(i) == "open" and not t.gap[i] and not t.pit[i]


def crowds(ctx):
    """White Forest's people (the rebels' base is near): rebels along the start's west shoulder with
    citizens behind them and a circle of vortigaunts chanting further back; rebels on the cutting's
    lips, behind the gorge road's rails watching the see-saw and past its exit, outside the hairpin,
    on the riverside road's hill side, among the sawmill's log stacks (vortigaunts with them),
    outside the mill turn and waiting by the level crossing; the rebels and their vortigaunts round
    the camp fire; Combine soldiers at their barricade under the column's bridge. Then the eggs."""
    t = ctx.trk

    def shoulder(lo, hi):
        return lambda i, s: ctx.shoulder_spot(i, s, lo, hi)

    # the start: the west shoulder (the railway's fence is on the other side)
    ids = [i for i in ctx.lap_ids(-50.0, 120.0) if _open(ctx, i)]
    for ch in ctx.chunks(ids, int(30 / t.step), int(30 / t.step)):
        gid = ctx.crowd_group(ch[len(ch) // 2], -1, "line", "rebel", tags=["start"])
        ctx.crowd_line(gid, ch, -1, 3.0, shoulder(2.5, 3.5), "rebel", mood="excited", chance=0.8, dodge=True,
                       dy=(-1.5, 3.0))
        ctx.crowd_line(gid, ch, -1, 5.0, shoulder(5.0, 6.5), "citizen", chance=0.5, dy=(-1.5, 3.0))
    i = _lap_i(t, 70.0)
    gid = ctx.crowd_group(i, -1, "cluster", "vort", tags=["start"], bed="alien")
    ctx.crowd_cluster(gid, ctx.side_point(i, -1, 14.0), 5, 2.6, "vort", t.pos[i] + UP, mood="chant",
                      ref_y=t.pos[i][1], dy=(-1.5, 3.0), margin=6.0)
    # the cutting's lips, looking down at the karts in it
    for s0, s1, sgn in ((352.0, 384.0, 1), (457.0, 489.0, -1)):
        ids = [i for i in ctx.lap_ids(s0, s1) if t.kind(i) == "trench"]
        if ids:
            gid = ctx.crowd_group(ids[len(ids) // 2], sgn, "lip", "rebel", tags=["cutting"])
            ctx.crowd_line(gid, ids, sgn, 2.2, ctx.lip_spot, "rebel", mood="excited", chance=0.6, margin=0.3, on="geom")
    # behind the gorge road's rails before the see-saw (watching it), and past its exit deck
    for s0, s1, sides, watch in ((574.0, 638.0, (-1, 1), (590.0, 790.0)), (806.0, 844.0, (-1,), (700.0, 850.0))):
        ids = [i for i in ctx.lap_ids(s0, s1) if _open(ctx, i)]
        for sgn in sides:
            for ch in ctx.chunks(ids, int(22 / t.step), int(10 / t.step)):
                gid = ctx.crowd_group(ch[len(ch) // 2], sgn, "line", "rebel", tags=["seesaw"], watch=watch)
                ctx.crowd_line(gid, ch, sgn, 2.5, shoulder(0.8, 2.5), "rebel", chance=0.7, dy=(-1.5, 2.0))
    # clusters on the open ground: outside the hairpin, the riverside road's hill side, outside the
    # mill turn, south of the road by the level crossing (out of its arms' and signals' way)
    for s, sgn, lat, n, tag in ((1287.0, -1, 22.0, 8, "hairpin"), (1608.0, -1, 8.5, 7, "river"),
                                (2101.0, -1, 7.0, 7, "mill"), (2380.0, -1, 9.0, 8, "crossing")):
        i = _lap_i(t, s)
        gid = ctx.crowd_group(i, sgn, "cluster", "rebel", tags=[tag], watch=[s - 60.0, s + 50.0])
        ctx.crowd_cluster(gid, ctx.side_point(i, sgn, lat), n, 3.5, "rebel", t.pos[i] + UP, mood="excited",
                          ref_y=t.pos[i][1], dy=(-2.0, 3.0), margin=4.5)
    # the sawmill's yard: rebels among the log stacks, vortigaunts with them
    for c, n, role in (((99.0, 85.0), 7, "rebel"), ((98.0, 126.0), 3, "vort")):
        q = np.array([c[0], 0.0, c[1]])
        i = ctx._nearest(np.array([c[0], 11.0, c[1]]))
        gid = ctx.crowd_group(i, 0, "cluster", role, tags=["yard"], bed="alien" if role == "vort" else "human")
        ctx.crowd_cluster(gid, q, n, 3.0, role, t.pos[i] + UP, mood="chant" if role == "vort" else "fan",
                          ref_y=t.pos[i][1], dy=(-2.0, 2.0), margin=4.5)
    # the rebels' camp: round the fire, their vortigaunts with them
    camp = getattr(ctx, "camp", None)
    if camp is not None:
        c, i = camp
        gid = ctx.crowd_group(i, 1, "cluster", "rebel", tags=["camp"], watch=[t.s[i] - 60.0, t.s[i] + 30.0])
        ctx.crowd_cluster(gid, c, 7, 5.5, "rebel", t.pos[i] + UP, mood="fan", ref_y=t.pos[i][1], dy=(-2.0, 3.0),
                          margin=4.0)
        ctx.crowd_cluster(gid, c, 3, 6.5, "vort", c + UP, mood="chant", ref_y=t.pos[i][1], dy=(-2.0, 3.0), margin=4.0)
    # Combine soldiers at their barricade between the valley's legs, watching the east leg come down
    i = _lap_i(t, 1183.0)
    gid = ctx.crowd_group(i, 1, "cluster", "combine", tags=["barricade"])
    ctx.crowd_cluster(gid, np.array([BARRICADE[0], 0.0, BARRICADE[1] - 4.0]), 5, 3.5, "combine",
                      np.array([280.0, 19.0, -20.0]), mood="military", ref_y=t.pos[i][1], dy=(-3.0, 3.0), margin=4.5)
    eggs(ctx)


def crowds_branch(ctx, spec):
    """Rebels past the logging trail's gully watching who makes the jump."""
    t = ctx.trk
    if spec["id"] != "logging_trail":
        return
    for a, b in t.gaps:
        i = min(b + int(14 / t.step), t.n - 1)
        gid = ctx.crowd_group(i, -1, "cluster", "rebel", tags=["jump"], watch=[t.s[a] - 30.0, t.s[i] + 10.0])
        ctx.crowd_cluster(gid, ctx.side_point(i, -1, 7.0), 6, 2.5, "rebel", t.pos[b] + UP, mood="excited",
                          ref_y=t.pos[i][1], dy=(-2.0, 2.5), margin=4.5)


def eggs(ctx):
    """The G-Man where the gorge road is seen best, crows pecking in the clearings, Gnome Chompski on a
    crate at the rebels' camp."""
    t = ctx.trk
    g = ctx.gman_spot(560.0, 660.0)
    if g is not None:
        ctx.egg("gman", pos=g["pos"], yaw=g["yaw"], s=g["s"], model="gman_high", window=g["window"], chance=0.4)
    camp = getattr(ctx, "camp", None)
    spots = [(104.0, 40.0), (-318.0, 30.0)] + ([(camp[0][0] + 9.0, camp[0][2] - 9.0)] if camp is not None else [])
    for x, z in spots:
        c = np.array([x, ctx.ground(x, z), z])
        if ctx.road_gap_xz(c) > 10.0 and ctx.in_prop(c, 1.5) is None:
            ctx.egg("birds", species="crow", center=c, radius=4.0, count=6)
    if camp is not None:
        crates = [p for p in ctx.props if p["model"] == "props_junk/wood_crate001a"]
        crates.sort(key=lambda p: math.hypot(p["pos"][0] - camp[0][0], p["pos"][2] - camp[0][2]))
        for p in crates[:3]:
            q = np.array(p["pos"], float)
            q[1] += ctx.models[p["model"]]["aabb_max"][1]
            k = next(j for j, o in enumerate(ctx.props) if o is p)
            if ctx.in_prop(q + [0.0, 0.1, 0.0], 0.0, ignore=k) is None and ctx.egg("gnome", pos=q, yaw=0.0):
                break
