"""Nova Prospekt: the Combine prison of Half-Life 2 (d2_prison_01-08) on its sea cliff, a lap of
about 2.7 km on two storeys.

From the start in the entry yard the road runs east under the high walkway, through the
gatehouse and the inner yard into cell block A's ground floor, out round a courtyard, south down
the canteen and round the exercise yard, then up the long ramp along the south wall onto the
upper level: the walkway north over the inner yard, the depot's roof round three sides, the
walkway south over the entry yard (both yards pass under the upper level), and on along the
gallery of the ruined cell block, whose floor fell into the antlion caves. Down its ramp into the
collapsed yard, over the caves, out through the west gate onto the cliff road along the outer
wall and the fences, the sea far below, and back in through the laundry to the entry yard.

Two branches: the upper tier of cell block A (a gallery along its north wall, climbing off the
floor and dropping back onto it at the far end) and the ventilation duct across the depot's
roof, a narrow cut of its north-west corner.

The antlion caves (D5): the lap's stretch from the ruined block's gallery to the collapsed yard's
end runs over solid ground with the caves CAVE_Y under it (cave_room()). The drop places are where
the gallery's railing and the yard's walls are broken (the styles "gallery_drop", "slab_drop_l",
"slab_drop_r"): an open edge beside the road, never in its racing line, with the caves' road (the
branch "caves" of kind "cave", entered by falling in: tools/track_gen.py CaveBranch) right under
the edge, its roof open. lap_drops() gives them in that branch's "drops" form, CAVE_ROUTE its way
from a dead end before the first drop past all three and up a rock cutting to its merge on the
cliff road (CAVE_MERGE). The antlion guard (TRACK["hazards"]) charges on the collapsed yard and
shoves karts into D2; Combine floor turrets stand in the canteen.

Set dressing (decorate, decorate_branch): the halls' outsides, the depot, the walls; the walls round
each drop (and the hazard stripe along its edge) and the fence along the caves' cutting; signs,
Breen's screens, light masts, cell doors, bunks, the canteen's tables, the laundry's dryers, the
depot roof's kit, the ruined block's yard, the prison's west wall and its other blocks round the
yards; in the caves grubs and their light, stalactites, hive nests, web sacks, sleeping antlions
and the miners' frames by the way out.
Spectators (crowds): Combine prison guards, prisoners in the courtyards, rebels on the cliff road.
"""
import math

import numpy as np

from track_gen import UP, Trk, _run_heights, _unwrap_s, _wall_gap, carve, face, noise2, smoothstep, wall_strip

# the lower level (the yards and the ground floors), the upper one (the walkways, the depot's
# roof and the galleries) and the antlion caves' floor under the lap's cave stretch (13 m under the
# collapsed yard, 25 m under the gallery)
LOW_Y = 0.0
UP_Y = 12.0
CAVE_Y = -13.0
# the caves' roof over their floor and the rock over that: their lid (floor + CAVE_H + CAVE_COVER -
# 0.15, the ground over the covered caves) lies 0.55 m under the lower level, just under the
# plateau's ground, so the ground over them is the yards' own and the drops are deep enough for it
CAVE_H, CAVE_COVER = 9.0, 3.6
# the plateau the prison stands on: its ground just under the lower roads
PLATEAU = LOW_Y - 0.35
# the cliff tops: west of WEST_X and south of SOUTH_Z the land falls to the sea
WEST_X, SOUTH_Z = -492.0, 318.0
SEA_Y = -40.0
# the depot: its roof (the upper level's north side) round the inside of the U the lap makes
# there, its south face over the yards at DEPOT_FACE_Z (the walkways run off its roof there)
DEPOT_X = (-90.0, 70.0)
DEPOT_N_Z = -160.0
DEPOT_FACE_Z = -50.0
DEPOT_ROOF_Y = UP_Y - 0.4
# the radius of the roof road's two bends round the depot's north corners
DEPOT_R = 40.0


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
        out.append((round(cx + r * math.cos(a), 2), y0 + (y1 - y0) * u, round(cz + r * math.sin(a), 2),
                    w0 + (w1 - w0) * u, style))
    return out


def _ramp(x0, x1, z, y0, y1, w, style, n=7, ease=0.25):
    """Control points up or down a straight ramp along x at z: n points from x0 to x1 (both ends
    included), the height going from y0 to y1 at a steady grade between two eased ends (the first
    and last `ease` of it curve in and out, level at x0 and x1: the spline neither dips before the
    ramp nor overshoots at its top; the steepest grade is 1 / (1 - ease) times the mean), the width
    from w (or (w0, w1))."""
    w0, w1 = w if isinstance(w, tuple) else (w, w)
    a = ease
    out = []
    for k in range(n):
        u = k / (n - 1)
        if u < a:
            e = u * u / (2 * a * (1 - a))
        elif u > 1 - a:
            e = 1 - (1 - u) ** 2 / (2 * a * (1 - a))
        else:
            e = (u - a / 2) / (1 - a)
        out.append((round(x0 + (x1 - x0) * u, 2), round(y0 + (y1 - y0) * e, 3), z, w0 + (w1 - w0) * u, style))
    return out


# (x, y, z, width, style[, flags]): the start first, heading east along the entry yard (+x east,
# +z south; the sea lies west and south of the prison)
CTRL = [
    # the entry yard: the grid, the start line, the high walkway overhead 50 m on
    (-140, LOW_Y, 0, 18, "yard"), (-90, LOW_Y, 0, 18, "yard"), (-44, LOW_Y, 0, 18, "yard"),
    # the gatehouse (its arch gates) into the inner yard, the walkway over it too
    (-16, LOW_Y, 0, 16, "gate"), (16, LOW_Y, 0, 16, "inner"), (70, LOW_Y, 0, 16, "inner"),
    # cell block A's ground floor: a tall hall with its upper tier along the north wall
    (118, LOW_Y, 0, 14, "cellblock"), (180, LOW_Y, 0, 14, "cellblock"), (245, LOW_Y, 0, 14, "cellblock"),
    # out into a courtyard and round to the south
    (312, LOW_Y, 0, 14, "court")] + _arc(312, 30, 30, -60, 0, LOW_Y, 14, "court", 3) + [
    # the canteen, south
    (342, LOW_Y, 48, 14, "canteen"), (342, LOW_Y, 104, 14, "canteen"),
    # the exercise yard round to the west, then the long ramp up along the south wall
    (342, LOW_Y, 162, 14, "court")] + _arc(312, 170, 30, 0, 90, LOW_Y, 14, "court") +     _ramp(286, 124, 200, LOW_Y, UP_Y, 14, "climb") + _arc(110, 160, 40, 90, 180, UP_Y, 14, "walk_turn") + [
    # the walkway north over the inner yard onto the depot's roof
    (70, UP_Y, 100, 14, "walk"), (70, UP_Y, 30, 14, "walk"), (70, UP_Y, -30, 14, "walk"),
    (70, UP_Y, DEPOT_FACE_Z, 14, "roof"), (70, UP_Y, -90, 14, "roof")] + \
    _arc(DEPOT_X[1] - DEPOT_R, DEPOT_N_Z + DEPOT_R, DEPOT_R, 0, -90, UP_Y, 14, "roof_turn") + [
    (10, UP_Y, DEPOT_N_Z, 14, "roof"), (-30, UP_Y, DEPOT_N_Z, 14, "roof")] + \
    _arc(DEPOT_X[0] + DEPOT_R, DEPOT_N_Z + DEPOT_R, DEPOT_R, -90, -180, UP_Y, 14, "roof_turn") + [
    # off the roof south over the entry yard, on along the ruined block's gallery (the caves
    # under it: D1 is where its railing is broken)
    (-90, UP_Y, -90, 14, "roof"), (-90, UP_Y, DEPOT_FACE_Z, 14, "walk"), (-90, UP_Y, 0, 14, "walk"),
    (-90, UP_Y, 40, 14, "gallery"), (-90, UP_Y, 92, 14, "gallery"), (-90, UP_Y, 122, 14, "gallery_drop"),
    (-90, UP_Y, 144, 14, "gallery"), (-90, UP_Y, 190, 14, "gallery")] + \
    _arc(-130, 220, 40, 0, 90, UP_Y, (14, 16), "cave_turn") +     _ramp(-142, -262, 260, UP_Y, LOW_Y, 16, "slope") + [
    # down the ramp into the collapsed yard, the antlion guard's stretch (D2 on the left, D3 on
    # the right: where the yard's floor gave way beside the road). 16 m wide: the guard's shove
    # carries a kart from the middle into D2, which is long (32 m) for the karts it throws as they
    # come by at speed
    (-280, LOW_Y, 260, 16, "slab_drop_l"), (-312, LOW_Y, 260, 16, "slab"), (-340, LOW_Y, 260, 16, "slab"),
    (-376, LOW_Y, 260, 16, "slab_drop_r"), (-398, LOW_Y, 260, 16, "slab"),
    # out through the west gate onto the cliff road, north along the outer wall
    (-412, LOW_Y, 260, 16, "outer")] + _arc(-430, 220, 40, 90, 180, LOW_Y, (16, 14), "outer") + [
    (-470, LOW_Y, 160, 14, "outer"), (-470, LOW_Y, 100, 14, "outer"), (-470, LOW_Y, 50, 14, "outer")] + \
    _arc(-430, 40, 40, 180, 270, LOW_Y, 14, "outer") + [
    # in through the laundry to the entry yard
    (-414, LOW_Y, 0, 14, "laundry"), (-360, LOW_Y, 0, 14, "laundry"),
    (-306, LOW_Y, 0, 18, "yard"), (-230, LOW_Y, 0, 18, "yard"),
]
CTRL = [c if len(c) > 5 else c + ({},) for c in CTRL]

# where the caves' road comes back up onto the lap: the cliff road's right (east) side, heading
# north, 64 m before its bend into the laundry (a straight from s 2190 to 2370 or so)
CAVE_MERGE = (-470.0, 64.0)
# a way for the caves' road (x, y, z): from its dead end (in a covered tunnel, 18 m before the first
# drop) south under the ruined block beside the gallery, its near wall under the gallery's open
# (west) edge at D1; round under the corner and the ramp down to the collapsed yard's south side for
# D2, across under the slab to its north side for D3, on west under the slab's end; then north up a
# rock cutting outside the prison's west wall, climbing 13 m (at most 12 %), and onto the cliff
# road's east verge at CAVE_MERGE. Its centre lies 6 m out past the main road's edge at each drop (a
# cave road 10 m wide with walls 1 m out: its near wall under the edge)
CAVE_ROUTE = [(-102.7, CAVE_Y, 104.0), (-102.7, CAVE_Y, 134.0), (-102.7, CAVE_Y, 168.0), (-106.0, CAVE_Y, 200.0),
              (-122.0, CAVE_Y, 226.0), (-150.0, CAVE_Y, 248.0), (-200.0, CAVE_Y, 266.0), (-250.0, CAVE_Y, 274.0),
              (-272.0, CAVE_Y, 274.0), (-296.0, CAVE_Y, 274.0), (-318.0, CAVE_Y, 274.0), (-334.0, CAVE_Y, 270.5),
              (-350.0, CAVE_Y, 256.0), (-366.0, CAVE_Y, 246.0), (-378.0, CAVE_Y, 246.0), (-398.0, CAVE_Y, 246.0),
              (-412.0, CAVE_Y, 239.0), (-425.0, CAVE_Y, 226.0),
              (-436.0, -11.6, 200.0), (-442.0, -8.3, 170.0), (-445.0, -4.8, 140.0), (-447.0, -1.9, 114.0),
              (-449.5, -1.0, 103.0), (-452.0, -0.5, 92.0)]
# which of the caves' styles each stretch of CAVE_ROUTE takes (point k to k + 1): the narrow cave under
# the drops, the wide hive hall between the gallery and the collapsed yard, the cutting up and the
# dirt road onto the cliff road
CAVE_KINDS = ["cave"] * 3 + ["cave_hall"] * 4 + ["cave"] * 11 + ["cave_cut"] * 5 + ["cave_out"]
# the cutting's walls reach up to the plateau's ground (their tops 0.3 m under the lower level)
CUT_TOP = LOW_Y - 0.3


def _cave_ctrl():
    """The caves' control points from CAVE_ROUTE and CAVE_KINDS: 10 m of road, the cutting's walls
    as tall as its floor lies under the plateau."""
    out = []
    for (x, y, z), kind in zip(CAVE_ROUTE, CAVE_KINDS):
        fl = {"height": round(max(CUT_TOP - y, 0.6), 2)} if kind == "cave_cut" else {}
        out.append((x, y, z, 10, kind, fl))
    return out

BRANCHES = [
    # the upper tier of cell block A: off the floor beside the road along the north wall, up to the
    # tier 5.6 m over the floor, along it past the cells, then it swings in over the road and ends:
    # you drop back onto it (railed on the wall side only: fall off and you land on the hall's floor)
    {"id": "upper_tier", "name": "Upper tier", "fork": (140, 0), "merge": (300, 0), "in_hall": True,
     "kind": "high", "side": -1, "merge_side": -1, "merge_type": "drop",
     "ctrl": [(158, LOW_Y + 0.04, -6.9, 8, "tier"), (174, LOW_Y + 0.05, -12.1, 8, "tier"),
              (184, LOW_Y + 0.45, -12.25, 8, "tier"), (200, LOW_Y + 3.4, -12.1, 8, "tier"),
              (222, LOW_Y + 5.5, -12.0, 8, "tier"), (246, LOW_Y + 5.6, -12.0, 8, "tier"),
              (258, LOW_Y + 5.6, -10.0, 8, "tier"),
              (268, LOW_Y + 5.6, -7.0, 8, "tier", {"gap": True, "gap_span": (0.05, 0.95), "ramp_lift": 0.3,
                                                     "ramp_len": 8}),
              # (a hand over the floor: the landing is the hall's road itself, the build lays it there)
              (278, LOW_Y + 0.35, -5.0, 8, "tier")],
     # (a pad halfway along: the tier is narrower and its swings off and back onto the floor slower
     # than the hall's road, about as quick with it)
     "boosts": [0.5], "risk": 0.35, "ai": {"take": 0.5, "min_skill": 0.8}, "respawn": "main"},
    # the ventilation duct across the depot's roof: off the north edge just past its north-east bend,
    # through the duct (narrow, a long S that a computer driver takes at 27 m/s: about as quick as
    # the corner it cuts) and back onto the west edge, which runs on straight off the roof and over
    # the entry yard (a merge just before a bend bunched the karts up in it)
    {"id": "vent_duct", "name": "Ventilation duct", "fork": (12, DEPOT_N_Z), "merge": (-90, -58), "kind": "alt",
     "side": -1, "merge_side": -1,
     "ctrl": [(-4, UP_Y, -155, 12, "roofb"), (-18, UP_Y, -149, 12, "roofb"), (-32, UP_Y, -140, 11, "duct"),
              (-46, UP_Y, -128, 11, "duct"), (-58, UP_Y, -112, 11, "duct"), (-67, UP_Y, -96, 12, "roofb"),
              (-75, UP_Y, -84, 12, "roofb")],
     "risk": 0.2, "ai": {"take": 0.5, "min_skill": 0.75}, "respawn": "before"},
    # the antlion caves (Episode Two's): a road under the lap that a kart gets into only by falling
    # through one of the three drop places (lap_drops: the gallery's broken railing, the collapsed
    # yard's holes either side), from a dead end under the ruined block to a rock cutting up onto the
    # cliff road ahead of them all. Whoever drives out gets the bonus over the others: a long boost
    # and an item from the pool the last kart draws from (the strongest). A pad in the hive hall and
    # one just past the last drop, where the way out begins, keep a kart that fell in close to the
    # karts that stayed on the lap. A kart stuck down there goes back onto the lap
    {"id": "caves", "name": "Antlion caves", "kind": "cave", "fork": (-90.0, 104.0), "merge": CAVE_MERGE,
     "merge_side": 1, "drops": None, "ctrl": _cave_ctrl(), "boosts": [0.25, 0.7], "respawn": "main",
     "bonus": {"boost": 3.0, "power": 1.25, "best_item": True}},
]
# (the caves' "drops" come from the lap as laid out above: lap_drops(), filled in below it)

TRACK = {
    "id": "nova_prospekt",
    "name": "Nova Prospekt",
    "ctrl": CTRL,
    # Nova Prospekt's own: the entrance (song 19), the crusher block (song 0), the depot (HL1's song
    # 24), and two more of HL2's
    "music": ["hl2_song19", "hl2_song0", "hl1_song24", "hl2_song16", "hl2_song4"],
    # (lap metres of this layout, 2735 m: the entry yard to s 124, the gatehouse 124-156, the inner
    # yard to 258, cell block A 258-452, the canteen 518-632, the ramp up 712-890, the walkway north
    # 890-1163, the depot's roof 1163-1507 (its bends 1233-1315 and 1375-1467), the walkway south
    # 1507-1597, the gallery 1597-1777 (D1 1679-1701), the bend and the ramp down 1777-1991, the
    # collapsed yard 1991-2123 (D2 1991-2023, D3 2087-2109), the cliff road 2123-2463, the laundry
    # 2463-2571; the caves under s 1663-2357)
    # (crates: the entry yard, the canteen, the top of the ramp, the depot's east edge, the walkway
    # over the entry yard, the ramp down, the cliff road and the entry yard again; none on the cliff
    # road's stretch where the caves' road comes back up beside it: CAVE_MERGE)
    "items": [0.03, 0.2, 0.335, 0.44, 0.578, 0.69, 0.815, 0.955],
    # (on straights only, none in a hall before its bend nor on the stretch over the caves: the
    # entry yard, the inner yard, the walkway north, the cliff road, the laundry and the entry yard;
    # none on the ramp up, whose bend at the top a boosted kart came into too fast)
    "boosts": [0.024, 0.075, 0.373, 0.805, 0.91, 0.965],
    "barrels": [],
    "vmax": 38.0,
    "offtrack": 30.0,
    # the game's gravity (project.godot): the launch speeds the branches export are the real ones
    "gravity": 15.24,
    "sky": "sky_day02_09",
    "background": "none",
    "gantry": "combine",
    "water": {"level": SEA_Y},
    "env": {"sun_energy": 1.3, "sun_color": [0.82, 0.92, 1.0], "sun_dir": [-0.35, 0.7, 0.45],
            "ambient": [0.55, 0.6, 0.68], "ambient_energy": 1.0, "fog_color": [0.6, 0.66, 0.72],
            "fog_begin": 220.0, "fog_end": 2200.0, "exposure": 1.0,
            # (no realtime GI, as in Black Mesa: under it the halls, the caves and every face the sun
            # does not reach came out black, the caves' road too dark to drive; the ambient light
            # above lights them as MEDIUM and LOW always did)
            "sdfgi": False},
}


def styles(m):
    concrete = m.hl2("concrete/concretefloor013a")
    cracked = m.hl2("concrete/concretefloor038b")
    kerb = m.hl2("concrete/concretefloor019a")
    facade = m.hl2("concrete/concretewall032d")
    plain = m.hl2("concrete/concretewall032b")
    light = m.hl2("lights/fluorescentcool001a")
    grate = m.hl2("metal/metalfloor007a")
    plates = m.hl2("metal/metalfloor003a")
    rust = m.hl2("metal/metalwall062a")
    chainlink = m.hl2("metal/metalfence004a")
    # the yards' walls: 4.5 m of Nova Prospekt's concrete (and an unseen wall over them up to 5 m: a
    # kart thrown up off the kerb stays in the yard)
    yard_wall = {"kind": "wall", "mat": facade, "h": 4.5, "thick": 0.6, "rep": 4.5, "col_h": 5.0}
    yard = {"kind": "street", "road": concrete, "road_rep": 5.0, "curb": kerb, "walk": 3.5, "walk_mat": cracked,
            "barrier": yard_wall, "uv": "plan"}
    # a hall's lights: fluorescent panels in the ceiling and lamps under them, cold as the prison's
    lamps = {"light": light, "light_color": [0.82, 0.92, 1.0], "light_energy": 1.6}
    # the halls' outsides (decorate: _shells) and their portals: the prison's concrete
    hall = dict(lamps, kind="tunnel", portal=facade, portal_w=2.5, cover=0.0)
    # the upper level's railings: chain-link 1.3 m (an unseen wall over them up to 3.5 m: a kart thrown
    # up off the walkway stays on it, 12 m over the yards)
    railing = {"kind": "fence", "mat": chainlink, "h": 1.3, "rep": 2.5, "col_h": 3.5}
    walk = {"kind": "bridge", "road": plates, "road_rep": 3.0, "skirt": rust, "skirt_h": 1.4, "barrier": railing,
            "pillar": plain, "pillar_every": 22.0, "pillar_size": 1.4, "ground": "nat"}
    # the depot's roof: a block down to the ground (its walls are the depot's), a concrete parapet
    parapet = {"kind": "wall", "mat": m.hl2("concrete/concretewall022a"), "h": 1.1, "thick": 0.5, "rep": 3.0,
               "col_h": 3.5}
    roof = {"kind": "bridge", "road": cracked, "road_rep": 5.0, "skirt": facade, "skirt_h": UP_Y + 0.6,
            "barrier": parapet, "pillar_every": 1e9, "ground": "nat"}
    # the ruined block's gallery along its east wall: chain-link both sides (the wall stands past the
    # left one, decorate: _gallery_wall), the caves under it; no legs (it hangs off the wall)
    gallery = {"kind": "bridge", "road": cracked, "road_rep": 5.0, "skirt": plain, "skirt_h": 1.2, "barrier": railing,
               "pillar_every": 1e9, "ground": "nat"}
    # the collapsed yard over the caves and its ramp down: a slab 16 m wide between 3 m walls (an
    # unseen wall over them up to 6.5 m: the guard's shove sends a kart into a hole, not over a wall,
    # and a kart an item throws up in the pack stays in the yard)
    slab_wall = {"kind": "wall", "mat": facade, "h": 3.0, "thick": 0.6, "rep": 4.5, "col_h": 6.5}
    slab = {"kind": "bridge", "road": cracked, "road_rep": 6.0, "skirt": plain, "skirt_h": 1.6, "barrier": slab_wall,
            "pillar_every": 1e9, "ground": "nat"}
    rock = m.hl2("nature/rockwall_cave02a")
    cave_floor = m.hl2("nature/dirtfloor_mine001a")
    cave = {"kind": "tunnel", "road": cave_floor, "road_rep": 5.0, "side_floor": cave_floor, "height": CAVE_H,
            "wall": rock, "wall_rep": 8.0, "ceil": rock, "ceil_rep": 8.0, "light": rock, "light_rows": [],
            "lamps": False, "wall_gap": 1.0, "rough": 0.6, "cover": CAVE_COVER, "lid_w": 8.5,
            "lid_mat": cracked, "lid_rep": 5.0, "lid_mesh": "verge", "portal": rock, "vmax": 28.0}
    return {
        "yard": yard,
        # the inner yard: a little narrower
        "inner": dict(yard, walk=3.0),
        # the courtyards and the exercise yard the road turns round
        "court": dict(yard, walk=2.5),
        # the gatehouse: a short concrete passage under the wall (its arch gates: the dressing)
        "gate": dict(hall, road=concrete, road_rep=5.0, height=8.0, wall=plain, wall_rep=4.0,
                     band=m.hl2("concrete/concretewall004c"), band_h=1.4, band_rep=2.8,
                     ceil=m.hl2("concrete/concreteceiling004a"), light_every=8.0, light_rows=[0.0], wall_gap=4.4),
        # cell block A's ground floor: a hall 34 m across and 16 m high (the upper tier runs along its
        # north wall over the floor beside the road), the cell blocks' dark metal walls
        "cellblock": dict(hall, road=concrete, road_rep=5.0, side_floor=cracked, height=16.0,
                          wall=m.hl2("metal/metalwall077a"), wall_rep=4.0, band=m.hl2("concrete/concretewall004c"),
                          band_h=2.6, band_rep=2.6, ceil=m.hl2("plaster/plasterceiling008a"), ceil_rep=4.0,
                          light_every=10.0, light_rows=[-0.72, 0.0, 0.72], light_w=1.6, light_l=4.0, wall_gap=10.0),
        # the canteen: its checkered floor, tiled walls
        "canteen": dict(hall, road=m.hl2("tile/tilefloor001a"), road_rep=3.0, side_floor=m.hl2("tile/tilefloor001a"),
                        height=7.0, wall=m.hl2("plaster/plasterwall034a"), wall_rep=3.5, band=m.hl2("tile/tilewall006a"),
                        band_h=1.6, band_rep=1.6, ceil=m.hl2("plaster/plasterceiling008a"), ceil_rep=3.0,
                        light_every=7.0, light_rows=[-0.5, 0.5], light_w=1.2, light_l=3.0, wall_gap=3.0),
        # the laundry and showers: white tiles
        "laundry": dict(hall, road=m.hl2("tile/tilefloor009a"), road_rep=3.0, side_floor=m.hl2("tile/tilefloor009a"),
                        height=7.0, wall=m.hl2("tile/tilewall006a"), wall_rep=2.5, band=m.hl2("plaster/plasterwall026a"),
                        band_h=1.2, band_rep=2.4, ceil=m.hl2("plaster/plasterceiling008a"), ceil_rep=3.0,
                        light_every=7.0, light_rows=[-0.5, 0.5], light_w=1.2, light_l=3.0, wall_gap=3.0),
        # the ramp up along the south wall: a concrete block down to the ground, parapets
        "climb": dict(roof, road=concrete, skirt=facade),
        "walk": walk,
        # the bend at the top of the ramp up: its railings stop a kart up to 6 m (one bumped in the pack
        # coming up the ramp fast went over them onto the ground)
        "walk_turn": dict(walk, barrier=dict(railing, col_h=6.0)),
        "roof": roof,
        # round the depot's two north corners its parapet stops a kart up to 6 m (one rammed into it
        # in the pack went over at 3.5 m)
        "roof_turn": dict(roof, barrier=dict(parapet, col_h=6.0)),
        "gallery": gallery,
        # D1: the gallery's railing torn out on its open side (the caves under it)
        "gallery_drop": dict(gallery, barrier=dict(railing, sides="left"), pit=True),
        # round the corner off the gallery onto the ramp down: walled, over the caves, on concrete piers
        # (none stands on the caves' road: pillar_meshes)
        "cave_turn": dict(slab, barrier=dict(slab_wall, h=2.0), pillar=plain, pillar_every=20.0, pillar_size=1.8),
        "slope": dict(slab, pillar=plain, pillar_every=20.0, pillar_size=1.8),
        "slab": slab,
        # D2 and D3: the yard's floor gave way on one side (no wall there, the caves under it)
        "slab_drop_l": dict(slab, barrier=dict(slab_wall, sides="right"), pit=True),
        "slab_drop_r": dict(slab, barrier=dict(slab_wall, sides="left"), pit=True),
        # the cliff road outside the walls: worn concrete, a grass verge and the chain-link fence on
        # the cliff's side (left: the sea down there); the prison's outer wall beyond the right verge
        # is the dressing's, round the caves' way up to CAVE_MERGE
        "outer": {"kind": "open", "road": m.hl2("concrete/concretefloor006a"), "road_rep": 6.0,
                  "verge": m.hl2("nature/blendsandsand008b"), "verge_w": 3.0, "skirt": m.hl2("nature/cliffface002a"),
                  "barrier": {"kind": "fence", "mat": chainlink, "h": 2.6, "rep": 2.6, "off": 1.0, "sides": "left",
                              "col_h": 3.5}},
        # the upper tier: a grated deck on legs to the hall's floor, railed on the wall side only
        "tier": {"kind": "bridge", "road": grate, "road_rep": 3.0, "skirt": rust, "skirt_h": 0.9,
                 "barrier": dict(railing, h=1.1, col_h=2.5, sides="left"), "pit": True, "pillar": rust,
                 "pillar_floor": LOW_Y, "pillar_every": 16.0, "pillar_size": 0.7},
        # the duct's way off and back onto the roof
        "roofb": dict(roof),
        # the ventilation duct: a narrow metal box on the depot's roof (a computer driver takes its bends
        # at one steady speed)
        "duct": dict(lamps, kind="tunnel", road=grate, road_rep=3.0, height=5.5, wall=rust, wall_rep=3.0,
                     ceil=rust, ceil_rep=3.0, light_every=9.0, light_rows=[0.0], light_w=0.8, light_l=2.4,
                     light_color=[1.0, 0.86, 0.6], light_energy=1.3, wall_gap=0.5, portal=rust, portal_w=1.2,
                     cover=0.0, vmax=27.0),
        # the antlion caves (Episode Two's, ep2_outland_01a-04): rough grey rock walls and roof, a dirt
        # floor out to them, no light panels (the glowing grubs light them: decorate_branch); their lid
        # is the plateau's paving a kart can drive over
        "cave": cave,
        # the hive hall between the gallery and the collapsed yard: the antlions' white crust on the
        # rock, ledges 4.5 m wide either side (nests, eggs, grubs, sleeping antlions)
        "cave_hall": dict(cave, wall=m.hl2("nature/rockwall_antlion01a"), ceil=m.hl2("nature/rockwall_antlion01a"),
                          wall_gap=4.5, side_floor=m.hl2("nature/blenddirtrock_mine01a")),
        # the way out: a rock cutting up to the plateau (its walls' height per control point, _cave_ctrl)
        "cave_cut": {"kind": "trench", "road": cave_floor, "road_rep": 5.0, "wall": m.hl2("nature/rockwall_cave02a"),
                     "wall_rep": 8.0, "lip": 3.0, "lip_mat": m.hl2("concrete/concretefloor038b"), "vmax": 28.0},
        # ... and the antlions' track over the cliff top onto the cliff road
        "cave_out": {"kind": "open", "road": cave_floor, "road_rep": 5.0, "verge": m.hl2("nature/dirtfloor006a"),
                     "verge_w": 2.0, "vmax": 30.0},
    }


def STARTLINE(m):
    return m.hl2("props/hazardstrip001a")


# ---------------------------------------------------------------- the antlion caves' room
# the lap's styles over the caves, which of them are drop places (side +1: the open edge on the
# road's right, -1 its left) and which are the antlion guard's stretch (the ramp down and the
# collapsed yard: 20 m wide, walled but for the drops)
CAVE_STYLES = ("gallery", "gallery_drop", "cave_turn", "slope", "slab", "slab_drop_l", "slab_drop_r")
DROP_SIDES = {"gallery_drop": 1, "slab_drop_l": -1, "slab_drop_r": 1}
GUARD_STYLES = ("slope", "slab", "slab_drop_l", "slab_drop_r")


def _cave_ids(t):
    """The lap's samples over the caves, in lap order."""
    return np.array([i for i in range(t.n) if t.style[i] in CAVE_STYLES])


def _runs_of(ids):
    """Consecutive runs (lists) of sample indices."""
    out = []
    for i in ids:
        if out and i == out[-1][-1] + 1:
            out[-1].append(i)
        else:
            out.append([i])
    return out


def drop_places(t):
    """The drop places on the lap t: per run of a drop style its lap metres (from, to), side, the
    open edge's two ends (x, y, z), its length, the deck's height and the caves' floor under it."""
    out = []
    ids = [i for i in range(t.n) if t.style[i] in DROP_SIDES]
    for run in _runs_of(ids):
        side = DROP_SIDES[t.style[run[0]]]
        a, b = run[0], run[-1]
        ends = [t.pos[i] + t.right[i] * side * t.width[i] / 2 for i in (a, b)]
        out.append({"s": (round(float(t.s[a]), 1), round(float(t.s[b] + t.step), 1)), "side": side,
                    "style": t.style[a], "edge": [[round(float(v), 1) for v in p] for p in ends],
                    "floor_y": CAVE_Y, "deck_y": round(float(t.pos[a, 1]), 2),
                    "length": round(float(t.s[b] + t.step - t.s[a]), 1)})
    return out


class _Names:
    """Material names as they are (no conversion): enough to lay the lap out (lap_drops)."""

    def hl2(self, name):
        return name

    def goldsrc(self, tex, glow=False, scale=4):
        return "goldsrc/" + tex.lower()


def lap_drops():
    """The drop places in the form a cave's spec takes them ("drops": {"s": lap metres of the
    middle, "side", "length"}), from the lap as this module lays it out, so a cave written against
    them stays under them if the route moves."""
    t = Trk(CTRL, styles(_Names()), TRACK.get("step", 2.0))
    return [{"s": round((d["s"][0] + d["s"][1]) / 2, 1), "side": d["side"], "length": d["length"]}
            for d in drop_places(t)]


# the drop places D1 (the gallery), D2 (the collapsed yard's left) and D3 (its right): the caves' drops
DROPS = lap_drops()
BRANCHES[-1]["drops"] = DROPS
_D2 = DROPS[1]
D2_S = (_D2["s"] - _D2["length"] / 2, _D2["s"] + _D2["length"] / 2)
# (lap metres: the canteen s 518-632, the ramp down 1853-1991, the collapsed yard 1991-2123)
TRACK["hazards"] = [
    # the antlion guard, the boss: it bursts up through the collapsed yard's floor on its right side and
    # charges whoever comes down the ramp first, shoving them across the slab into D2, the hole on its
    # left, down into the antlion caves. Its home is on the slab 3 m in from the right wall, 4 m into
    # the hole's stretch, so its runs meet the karts alongside the hole's first half (a shoved kart
    # keeps little of its speed: it goes over the edge about where it was hit); it stands and charges
    # in its zone, 110 m up the ramp from its home, and looks out for karts 72 m further, from the
    # walled bend at the top of the ramp (its first run comes up through the floor after a long
    # warning, about 4 s on NORMAL: a kart at full speed is that far off when the guard picks it,
    # AntlionGuardHazard._intercept). Its shove sends a kart sliding across the slab
    # (20 m/s, its tyres let go: Kart SHOVE_SLIDE) with only a small hop (3.5 m/s): from the middle of
    # the 16 m slab it goes over the edge and drops into the hole, never flying over the hole onto its
    # far rim. It meets a kart 6 to 18 m on from abeam of it, in the hole's first half: one met further
    # on slides past the hole's far end before it reaches the edge. It runs down a kart from behind
    # only when it is still beside it (8 m): one caught further on would be thrown past it too
    {"type": "antlion_guard", "zone": [round(D2_S[0] - 108.0, 1), round(D2_S[1] + 10.0, 1)], "lookout": 72.0,
     "s": round(D2_S[0] + 4.0, 1), "side": 1, "setback": -3.0, "edges": [[round(D2_S[0], 1), round(D2_S[1], 1), -1]],
     "push": 20.0, "lift": 3.5, "chase": 8.0, "lead": [6.0, 18.0]},
    # Nova Prospekt's Combine floor turrets on the canteen's side floors, one each side, facing the
    # oncoming karts (one group: a kart one of them spins is left alone by the other on that pass)
    {"type": "turret", "s": 575.0, "side": -1, "setback": 1.5, "zone": [536.0, 579.0],
     "model": "combine_turrets/floor_turret", "fallback": "hl1/sentry", "scale": 1.4, "group": "canteen"},
    {"type": "turret", "s": 622.0, "side": 1, "setback": 1.5, "zone": [583.0, 626.0],
     "model": "combine_turrets/floor_turret", "fallback": "hl1/sentry", "scale": 1.4, "group": "canteen"},
]


def cave_room(t):
    """The caves' room on the lap t (printed by the build, for the caves' road and the guard): the
    stretch over the caves and the guard's stretch (lap metres) and the drop places."""
    ids = _cave_ids(t)
    guard = [i for i in ids if t.style[i] in GUARD_STYLES]
    return {"cave_s": (round(float(t.s[ids[0]]), 1), round(float(t.s[ids[-1]] + t.step), 1)),
            "guard_s": (round(float(t.s[guard[0]]), 1), round(float(t.s[guard[-1]] + t.step), 1)),
            "drops": drop_places(t), "route": CAVE_ROUTE, "merge": CAVE_MERGE}


def _nearest(P, Q):
    """For each plan point of P (n, 2): the distance to the nearest of Q (m, 2) and its index."""
    dist = np.zeros(len(P))
    idx = np.zeros(len(P), int)
    for a in range(0, len(P), 4096):
        d2 = ((P[a:a + 4096, None, :] - Q[None, :, :]) ** 2).sum(-1)
        idx[a:a + 4096] = d2.argmin(1)
        dist[a:a + 4096] = np.sqrt(d2[np.arange(len(d2)), idx[a:a + 4096]])
    return dist, idx


# ---------------------------------------------------------------- terrain
def _depot_mask(P):
    """Inside the depot: the U the lap's roof stretch makes (up to its centre line, the corners
    round its bends) from its north edge to 6 m short of DEPOT_FACE_Z (the south face's box covers
    the rest)."""
    x, z = P[:, 0], P[:, 1]
    inside = (x >= DEPOT_X[0]) & (x <= DEPOT_X[1]) & (z >= DEPOT_N_Z) & (z <= DEPOT_FACE_Z - 6.0)
    R = DEPOT_R
    ne = (x > DEPOT_X[1] - R) & (z < DEPOT_N_Z + R)
    nw = (x < DEPOT_X[0] + R) & (z < DEPOT_N_Z + R)
    inside &= ~(ne & (np.hypot(x - (DEPOT_X[1] - R), z - (DEPOT_N_Z + R)) > R))
    inside &= ~(nw & (np.hypot(x - (DEPOT_X[0] + R), z - (DEPOT_N_Z + R)) > R))
    return inside


def _natural(P):
    """The headland as it lies: the plateau the prison stands on, its cliffs down to the sea west
    of WEST_X and south of SOUTH_Z, the hills rising north and east of the walls."""
    x, z = P[:, 0], P[:, 1]
    n1 = noise2(x / 150.0, z / 150.0, 5)
    n2 = noise2(x / 40.0, z / 40.0, 11)
    out = np.maximum(WEST_X - x, z - SOUTH_Z) + 6.0 * (n2 - 0.5)
    cliff = smoothstep(0.0, 22.0, out)
    floor = SEA_Y - 8.0 - 0.04 * np.maximum(out - 22.0, 0.0)
    h = PLATEAU * (1.0 - cliff) + floor * cliff
    inland = np.maximum(-240.0 - z, x - 440.0)
    hill = smoothstep(0.0, 220.0, inland) * (28.0 + 40.0 * n1)
    return h + hill * (1.0 - cliff)


def terrain(roads, m):
    layers = {"base": m.hl2("nature/blendsandsand008b"), "dirt": m.hl2("nature/dirtfloor006a"),
              "rock": m.hl2("nature/cliffface002a"), "pave": m.hl2("concrete/concretefloor038b"),
              "sand": m.hl2("nature/blendrockdirt_tunnel03a")}

    def build(f, roads):
        P = f.P
        nat = _natural(P)
        # the depot: its roof a hand under the roof road's deck
        nat = np.where(_depot_mask(P), DEPOT_ROOF_Y, nat)
        # (the antlion caves are dug by their own road: a covered tunnel in this solid ground, open
        # under each drop, CaveBranch caps the ground along it)
        h = carve(f, nat, roads, flat=6.0, blend=20.0)
        # the halls stand on the plateau like buildings (decorate: _shells), not inside a hill: past the
        # ground just outside their walls (the carve's slot) the land stays as it lies
        for v in (f, f.second):
            hall = (v.kind == "tunnel") & (v.dist > v.wall + f.cell + 0.5) & (v.dist < v.wall + 60.0)
            h = np.where(hall, np.minimum(h, nat) if v is f.second else nat, h)
        # beside a deck the ground stays under it for a grid cell past its edge, so no terrain triangle
        # reaches up through its edge
        deck = np.flatnonzero(np.array([roads.kind(i) == "bridge" for i in range(roads.n)]) & ~roads.gap)
        if len(deck):
            d, k = _nearest(P, roads.pos[deck][:, [0, 2]])
            near = d < roads.width[deck][k] / 2 + f.cell + 0.5
            h = np.where(near, np.minimum(h, roads.pos[deck][k, 1] - 0.5), h)
        h = np.minimum(h, f.cap)
        Hm = h.reshape(f.nz, f.nx)
        gz, gx = np.gradient(Hm, f.cell)
        rock = smoothstep(0.6, 1.0, np.sqrt(gx ** 2 + gz ** 2).ravel())
        x, z = P[:, 0], P[:, 1]
        # the prison's ground is paved inside the walls; under them, where the ground falls to the caves'
        # floor (their own road's slot: a drop's opening), the antlions' rock
        inside = (x > WEST_X + 6.0) & (z < SOUTH_Z - 6.0) & (z > -235.0) & (x < 435.0)
        pave = (inside & (h > PLATEAU - 2.0) & (h < DEPOT_ROOF_Y + 1.0)).astype(float) * (1.0 - rock)
        sand = (inside & (h < CAVE_Y + 12.0)).astype(float)
        dirt = (1.0 - pave) * (1.0 - sand) * smoothstep(0.4, 0.7, noise2(x / 60.0, z / 60.0, 21))
        col = np.stack([dirt, rock * (1.0 - sand), pave, sand], 1).astype(np.float32)
        return h, col

    return {"margin": 300.0, "cell": 3.0, "build": build, "layers": layers}


# ---------------------------------------------------------------- set dressing
# the halls' outer walls and roof stand this far out from their inner faces (_shells)
SHELL = 0.8


def _shells(ctx):
    """The outside of every hall (the lap's and the branches'): its walls' outer faces SHELL metres
    out from the inner ones, from under the ground up to a flat roof SHELL metres over its ceiling.
    Its portals (the style's "portal_w" past the walls, "portal_h" over the roof) close its ends."""
    T = SHELL
    for t in ctx.roads.trks:
        for name, st in t.styles.items():
            # (the antlion caves are dug into the rock: no shell, and none may roof over their drops)
            if st["kind"] != "tunnel" or name.startswith("cave"):
                continue
            for ids in t.runs(lambda i, nm=name: t.style[i] == nm, with_gaps=True):
                if len(ids) < 2:
                    continue
                hw = t.width[ids] / 2 + _wall_gap(t, ids, st) + T
                H = _run_heights(t, ids)
                v = _unwrap_s(t, ids)
                mat = ctx.mats.hl2(st.get("shell", "concrete/concretewall032d"))
                roof = ctx.mats.hl2(st.get("shell_roof", "concrete/concretefloor038b"))
                for sgn in (-1, 1):
                    o = t.pos[ids] + t.flat_right[ids] * (sgn * hw)[:, None]
                    bot, top = o.copy(), o.copy()
                    bot[:, 1] = t.pos[ids, 1] - 2.5
                    top[:, 1] = t.pos[ids, 1] + H + T
                    wall_strip(ctx.meshes["walls"], mat, bot, top, v, -sgn, 4.5)
                L = t.pos[ids] - t.flat_right[ids] * hw[:, None]
                R = t.pos[ids] + t.flat_right[ids] * hw[:, None]
                L[:, 1] = t.pos[ids, 1] + H + T
                R[:, 1] = L[:, 1]
                up = UP[None].repeat(len(ids), 0)
                ctx.meshes["walls"].strip(roof, L, R, -hw / 5.0, hw / 5.0, v / 5.0, up, up)


def _depot(ctx):
    """The depot's south face over the yards, from the plateau up to its roof, across the U the
    roof road makes and under both its roads' ends (its roof is the terrain's, DEPOT_ROOF_Y)."""
    x0, x1 = DEPOT_X[0] - 6.0, DEPOT_X[1] + 6.0
    z0, z1 = DEPOT_FACE_Z - 10.0, DEPOT_FACE_Z
    y0, y1 = PLATEAU - 1.0, DEPOT_ROOF_Y
    ctx.box(ctx.mats.hl2("concrete/concretewall032d"), [(x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2],
            [x1 - x0, y1 - y0, z1 - z0], 0.0, rep=4.5)


def _gallery_wall(ctx):
    """The ruined block's east wall along the gallery's left (east) side, 10 m over the gallery, its
    face GALLERY_WALL metres past the road's edge (the cell doors stand against it, past the railing:
    _gallery_doors)."""
    t = ctx.trk
    ids = [i for i in range(t.n) if t.style[i] in ("gallery", "gallery_drop")]
    a, b = t.pos[ids[0]], t.pos[ids[-1]]
    e = a - t.right[ids[0]] * (t.width[ids[0]] / 2 + GALLERY_WALL + 1.0)
    y0, y1 = PLATEAU - 2.0, UP_Y + 10.0
    ctx.box(ctx.mats.hl2("metal/metalwall077a"), [e[0], (y0 + y1) / 2, (a[2] + b[2]) / 2],
            [2.0, y1 - y0, abs(b[2] - a[2]) + 4.0], 0.0, rep=4.0)


def _masts(ctx):
    """Light masts along the cliff road's fence, on the cliff's side, every 60 m."""
    t = ctx.trk
    model = "props_wasteland/lights_industrialcluster01a"
    for s in np.arange(0.0, t.length, 60.0):
        i = int(s / t.step) % t.n
        if t.style[i] != "outer":
            continue
        q = t.pos[i] - t.flat_right[i] * (t.width[i] / 2 + 3.2)
        g = ctx.ground(q[0], q[2])
        ctx.add(model, [float(q[0]), float(g if g is not None else PLATEAU), float(q[2])],
                ctx.yaw_facing(t.flat_right[i]))


def _backdrop(ctx):
    """Nova Prospekt's other wings across the bay to the north-west, on their own headland (the
    prison seen from outside, HL2's d2_prison_01 model), far beyond the cliff road."""
    for model, x, z, yaw in (("props_combine/prison01", -760.0, -360.0, 0.6),
                             ("props_combine/prison01b", -690.0, -520.0, 0.9),
                             ("props_combine/prison01c", -850.0, -230.0, 0.4)):
        g = ctx.ground(x, z)
        ctx.add(model, [x, (g if g is not None else 0.0) - 1.0, z], yaw, tag="far")


# ---------------------------------------------------------------- the dressing's helpers
GALLERY_WALL = 0.4
CELL_DOOR = "props_wasteland/prison_celldoor001a"
WALL_LAMP = "props_wasteland/prison_lamp001a"
MAST = "props_wasteland/lights_industrialcluster01a"
SPEAKER = "props_wasteland/speakercluster01a"
GUARD_MODEL = "combine_soldier_prisonguard"


def _flat(v):
    v = np.array([v[0], 0.0, v[2]], float)
    return v / max(np.linalg.norm(v), 1e-9)


def _style_ids(t, names):
    """The road's samples in the styles `names` (no jump gaps), in order."""
    return [i for i in range(t.n) if t.style[i] in names and not t.gap[i]]


def _cave(ctx):
    """The caves' road (the branch "caves": its cutting), or None."""
    for t in ctx.roads.trks[1:]:
        if "cave_cut" in t.style:
            return t
    return None


def _cave_reach(ctx):
    """Per sample of the caves' road: the caves' plan positions and how far out from their centre
    line their lid (a covered stretch), their cutting's lip or their verge reaches (cached)."""
    out = getattr(ctx, "_np_cave", None)
    if out is None:
        c = _cave(ctx)
        if c is None:
            out = (np.zeros((0, 2)), np.zeros(0))
        else:
            kind = [c.kind(k) for k in range(c.n)]
            extra = np.array([c.wall_gap[k] + 8.5 if kind[k] == "tunnel" else 3.0 if kind[k] == "trench" else 2.0
                              for k in range(c.n)])
            out = (c.pos[:, [0, 2]], c.width / 2 + extra)
        ctx._np_cave = out
    return out


def _over_cave(ctx, q, margin=2.0):
    """True when plan point q lies over the caves, their lid or their cutting's lip (or within margin
    of them): the terrain under the lid is the caves' own slot, so nothing is put on the ground there
    (and nothing stands by the openings or on the way out)."""
    P, reach = _cave_reach(ctx)
    if not len(P):
        return False
    d = np.hypot(P[:, 0] - q[0], P[:, 1] - q[2])
    return bool((d < reach + margin).any())


def _tunnels(ctx):
    """Which samples of every road are halls or tunnels (cached)."""
    m = getattr(ctx, "_np_tun", None)
    if m is None:
        r = ctx.roads
        m = np.array([r.kind(i) == "tunnel" for i in range(r.n)])
        ctx._np_tun = m
    return m


def _clear(ctx, q, rad, height):
    """True when nothing of any road lies within rad metres of plan point q (a hall: its walls and
    shell) between q's height and `height` metres over it: no deck or walkway overhead, no hall's
    roof, no road at its own level."""
    r = ctx.roads
    tun = _tunnels(ctx)
    d = np.hypot(r.pos[:, 0] - q[0], r.pos[:, 2] - q[2])
    reach = r.width / 2 + rad + np.where(tun, r.wall_gap + SHELL + 0.5, 0.0)
    top = r.pos[:, 1] + np.where(tun, r.height + SHELL + 1.0, 0.5)
    hit = (d < reach) & (top > q[1] - 1.5) & (r.pos[:, 1] < q[1] + height)
    return not hit.any()


def _on_ground(ctx, model, q, yaw, tol=0.6, sink=0.0, margin=1.0, **kw):
    """A prop standing on the lowest ground under its footprint at plan point q (`sink` metres into
    it): its placed entry, or None where the ground under it varies by more than tol, it would stand
    over the caves, or the prop is refused (Ctx.add)."""
    if model not in ctx.models:
        ctx.missing.add(model)
        return None
    q = np.array(q, float)
    size = ctx.model_size(model) * kw.get("scale", 1.0)
    if _over_cave(ctx, q, margin + 0.5 * math.hypot(size[0], size[2])):
        return None
    g = ctx.site(model, q, yaw, kw.get("scale", 1.0), tol=tol)
    if g is None:
        return None
    q[1] = g - sink
    return ctx.props[-1] if ctx.add(model, q, yaw, **kw) else None


def _centred(ctx, model, c, yaw, scale=1.0):
    """The plan origin that puts a model's box centred on plan point c when it is turned by yaw."""
    m = ctx.models[model]
    lx = (m["aabb_min"][0] + m["aabb_max"][0]) / 2 * scale
    lz = (m["aabb_min"][2] + m["aabb_max"][2]) / 2 * scale
    cy, sy = math.cos(yaw), math.sin(yaw)
    return np.array([c[0] - lx * cy - lz * sy, c[1], c[2] + lx * sy - lz * cy])


def _quad(ctx, mat, c, n, w, h):
    """A flat panel w x h metres centred on c facing plan direction n, its texture once across it
    (a sign), unseen by the karts' collision."""
    n = _flat(n)
    r = np.cross(-n, UP)
    q = [c - r * (w / 2) - UP * (h / 2), c + r * (w / 2) - UP * (h / 2), c + r * (w / 2) + UP * (h / 2),
         c - r * (w / 2) + UP * (h / 2)]
    tri = [0, 1, 2, 0, 2, 3]
    if np.dot(np.cross(q[1] - q[0], q[2] - q[0]), n) < 0:
        tri = [0, 2, 1, 0, 3, 2]
    ctx.meshes["deco"].add(mat, q, [n] * 4, [[0, 1], [1, 1], [1, 0], [0, 0]], tri)


def _fire(ctx, q, size=1.0, smoke=1.0, light=False):
    """A fire for scripts/fx/ruin_fires.gd with its flames at q (`size` 1: a burning car)."""
    if not hasattr(ctx, "fires"):
        ctx.fires = []
    ctx.fires.append({"pos": [round(float(c), 2) for c in q], "size": round(float(size), 2),
                      "smoke": round(float(smoke), 2), "light": bool(light)})


# ---------------------------------------------------------------- the prison
def _signs(ctx):
    """The Nova Prospekt sign over the gatehouse's gate and, big, on the depot's face over the yards;
    Breen's screens on the depot's face (seen from the start) and on the canteen's wall."""
    t = ctx.trk
    sign = ctx.mats.hl2("props/sign_novaprospekt")
    gate = _style_ids(t, ("gate",))
    if gate:
        i = gate[0]
        st = t.styles["gate"]
        lintel = st.get("portal_h", max(st.get("cover", 0.0), 2.0) + 0.6)
        f = _flat(t.fwd[i])
        _quad(ctx, sign, t.pos[i] - f * 0.08 + UP * (t.height[i] + lintel / 2), -f, 11.2, 1.4)
    _quad(ctx, sign, np.array([-10.0, LOW_Y + 8.6, DEPOT_FACE_Z + 0.06]), (0.0, 0.0, 1.0), 22.4, 2.8)
    ctx.screens = [{"pos": [36.0, LOW_Y + 7.0, DEPOT_FACE_Z + 0.56], "yaw": 0.0, "w": 10.0, "h": 5.6}]
    canteen = _style_ids(t, ("canteen",))
    if canteen:
        i = canteen[len(canteen) // 6]
        q = t.pos[i] + t.flat_right[i] * (t.width[i] / 2 + t.wall_gap[i] - 0.56) + UP * 4.0
        ctx.screens.append({"pos": [float(v) for v in q], "yaw": float(ctx.yaw_facing(-t.flat_right[i])),
                            "w": 5.0, "h": 2.8})


def _yards(ctx):
    """The yards: light masts behind their walls every 45 m (a lamp and a loudspeaker cluster on
    each), Combine barricades and laundry carts against the walls on the pavements."""
    t = ctx.trk
    rng = ctx.rng
    k = 0
    for i in ctx.every(45.0, 20.0):
        if t.style[i] not in ("yard", "inner", "court") or t.junction[i]:
            continue
        st = t.styles[t.style[i]]
        sgn = 1 if k % 2 == 0 else -1
        k += 1
        rf = t.flat_right[i] * sgn
        q = ctx.side(i, sgn, 0.3 + st["walk"] + st["barrier"]["thick"] + 1.8)
        q[1] = ctx.ground(q[0], q[2])
        if not _clear(ctx, q, 1.5, 21.0):
            continue
        if _on_ground(ctx, MAST, q, ctx.yaw_front(MAST, -rf), tol=0.8) is None:
            continue
        ctx.light(q + UP * 17.5 - rf * 1.2, [0.85, 0.92, 1.0], 34.0, 1.3)
        ctx.add(SPEAKER, q + UP * 9.0 - rf * 1.0, ctx.yaw_front(SPEAKER, -rf), ground=False, tag="deco", solid=False)
    # on the pavements, against the walls: barricades by the gatehouse, carts in the inner yard
    for names, models, every in ((("yard",), ["props_combine/combine_barricade_short01a",
                                              "props_combine/combine_barricade_med01a"], 14.0),
                                 (("inner",), ["props_wasteland/laundry_cart001", "props_combine/combine_barricade_short01a"],
                                  18.0)):
        ids = _style_ids(t, names)
        for n, i in enumerate(ids[::max(1, int(every / t.step))]):
            if t.junction[i] or abs(t.curv[i]) > 0.01:
                continue
            st = t.styles[t.style[i]]
            sgn = 1 if n % 2 else -1
            m = models[n % len(models)]
            size = ctx.model_size(m)
            depth = min(size[0], size[2])
            q = ctx.side(i, sgn, 0.3 + st["walk"] - depth / 2 - 0.08)
            q[1] = t.pos[i][1] + st.get("curb_h", 0.16)
            ctx.add(m, q, ctx.yaw_along(m, t.fwd[i]) + float(rng.uniform(-0.04, 0.04)), ground=False)


def _cellblock(ctx):
    """Cell block A: cell doors every 6 m along the south wall's floor and the north wall's upper tier,
    caged lamps over every other one, the pipes along the walls and bunks dragged out against the
    south wall."""
    t = ctx.trk
    ids = _style_ids(t, ("cellblock",))
    for n, i in enumerate(ids[2:-2:3]):
        y = t.pos[i][1]
        if ctx.against_wall(i, 1, CELL_DOOR) is not None and n % 2 == 0:
            ctx.against_wall(i, 1, WALL_LAMP, y=y + 3.0, tag="deco", solid=False)
        if ctx.against_wall(i, -1, CELL_DOOR, y=y + 5.65) is not None and n % 2 == 1:
            ctx.against_wall(i, -1, WALL_LAMP, y=y + 8.6, tag="deco", solid=False)
        if n % 4 == 2:
            ctx.against_wall(i, 1, "props_wasteland/prison_bedframe001a")
        if n % 5 == 0:
            for sgn, h in ((1, 6.4), (-1, 10.8)):
                ctx.against_wall(i, sgn, "props_wasteland/prison_pipes001a", y=y + h, tag="deco", solid=False)


def _canteen(ctx):
    """The canteen: counters at its north end, then tables along both walls, a bench on their road side."""
    t = ctx.trk
    ids = _style_ids(t, ("canteen",))
    for n, i in enumerate(ids[3:-3:3]):
        for sgn in (1, -1):
            if n < 2:
                ctx.against_wall(i, sgn, "props_wasteland/kitchen_counter001a")
                continue
            if ctx.against_wall(i, sgn, "props_wasteland/cafeteria_table001a", inset=0.45) is not None:
                for inset in (1.58,):
                    ctx.against_wall(i, sgn, "props_wasteland/cafeteria_bench001a", inset=inset, tag="deco",
                                     solid=False)


def _laundry(ctx):
    """The laundry: rows of dryers along both walls, laundry carts between them, the showers at its
    far end."""
    t = ctx.trk
    ids = _style_ids(t, ("laundry",))
    rows = ids[2:-8]
    for n, i in enumerate(rows):
        for sgn in (1, -1):
            if (n + (3 if sgn > 0 else 0)) % 7 < 3:
                ctx.against_wall(i, sgn, "props_wasteland/laundry_dryer001")
            elif (n + (3 if sgn > 0 else 0)) % 7 == 4:
                ctx.against_wall(i, sgn, "props_wasteland/laundry_cart001", inset=0.2)
    for i in ids[-6:-2:2]:
        for sgn in (1, -1):
            ctx.against_wall(i, sgn, "props_wasteland/shower_system001a")


def _roof(ctx):
    """The depot's roof inside the U the road makes round it: vents, antennas, a dish and the
    Combine's generators and floodlights."""
    rng = ctx.rng
    kit = ["props_rooftop/roof_vent001", "props_rooftop/antennaclusters01a", "props_rooftop/roof_vent002",
           "props_combine/combine_light001a", "props_rooftop/rooftopcluser01a", "props_rooftop/antenna01a",
           "props_combine/combine_generator01", "props_rooftop/satellitedish02", "props_rooftop/chimneypipe_cluster02a"]
    k = 0
    for x in np.arange(DEPOT_X[0] + 16.0, DEPOT_X[1] - 10.0, 21.0):
        for z in np.arange(DEPOT_N_Z + 14.0, DEPOT_FACE_Z - 8.0, 19.0):
            q = np.array([x + rng.uniform(-4.0, 4.0), DEPOT_ROOF_Y, z + rng.uniform(-4.0, 4.0)])
            g = ctx.ground(q[0], q[2])
            if abs(g - DEPOT_ROOF_Y) > 0.3 or ctx.road_gap_to(q) < 4.0:
                continue
            m = kit[k % len(kit)]
            k += 1
            q[1] = g
            if _clear(ctx, q, 1.0, 6.0):
                _on_ground(ctx, m, q, float(rng.uniform(0, 6.28)), tol=0.4)


def _gallery_doors(ctx):
    """The ruined block's cells along the gallery: their doors on its wall every 4 m, caged lamps
    over every third."""
    t = ctx.trk
    ids = _style_ids(t, ("gallery", "gallery_drop"))
    for n, i in enumerate(ids[2:-2:3]):
        out = -t.flat_right[i]
        q = t.pos[i] + out * (t.width[i] / 2 + GALLERY_WALL - 0.06)
        q[1] = t.pos[i][1]
        yaw = ctx.yaw_front(CELL_DOOR, -out)
        if ctx.add(CELL_DOOR, q, yaw, ground=False) and n % 3 == 0:
            ctx.add(WALL_LAMP, q + UP * 3.0 - out * 0.2, yaw, ground=False, tag="deco", solid=False)


RUINS = ["props_debris/concrete_debris256pile001a", "props_debris/walldestroyed03a", "props_debris/concrete_wallpile01a",
         "props_debris/building_brokenexterior002a", "props_debris/concrete_debris128pile001a",
         "props_debris/walldestroyed09a", "props_debris/beam01a", "props_debris/concrete_floorpile01a",
         "props_debris/walldestroyed05a", "props_debris/concrete_cornerpile01a", "props_wasteland/antlionhill",
         "props_hive/nest_lrg_flat"]


def _ruins(ctx):
    """The ruined block's yard west of the gallery and round the collapsed yard: broken walls, rubble
    and beams, antlion mounds and hive nests where the antlions came up, a few fires (the battle in
    d2_prison_02-05); nothing over the caves' lid or by their openings."""
    rng = ctx.rng
    k = 0
    fires = 0
    for x in np.arange(-388.0, -118.0, 27.0):
        for z in np.arange(34.0, 312.0, 27.0):
            q = np.array([x + rng.uniform(-8.0, 8.0), 0.0, z + rng.uniform(-8.0, 8.0)])
            # (inside the walls only: not out on the cliff road's side of the prison's west wall)
            if q[0] < -404.0 or q[2] > SOUTH_Z - 10.0 or ctx.road_gap_to(q) < 7.0:
                continue
            q[1] = ctx.ground(q[0], q[2])
            if abs(q[1] - PLATEAU) > 0.6 or not _clear(ctx, q, 3.0, 14.0):
                continue
            m = RUINS[k % len(RUINS)]
            k += 1
            sink = 0.4 if "debris" in m else 0.1
            p = _on_ground(ctx, m, q, float(rng.uniform(0, 6.28)), tol=0.8, sink=sink, margin=3.0)
            if p is not None and "pile" in m and fires < 4 and k % 3 == 0:
                _fire(ctx, np.array(p["pos"]) + UP * 0.6, size=0.8, smoke=0.7)
                fires += 1


def _outer_wall(ctx):
    """The prison's west wall along the cliff road's inland side (x -412), broken by the west gate
    where the collapsed yard's slab runs out onto the cliff road (two tall pillars either side), and
    Combine watchtowers at its ends. The caves' cutting comes up outside it, under the cliff road's
    east verge."""
    stone = ctx.mats.hl2("stone/stonewall017b")
    y0, y1 = PLATEAU - 1.2, LOW_Y + 6.5
    x = -412.0
    for z0, z1 in ((12.0, 246.6), (273.4, SOUTH_Z - 4.0)):
        ctx.box(stone, [x, (y0 + y1) / 2, (z0 + z1) / 2], [1.6, y1 - y0, z1 - z0], 0.0, rep=4.0)
    for z in (248.0, 272.0):
        ctx.box(stone, [x, (y0 + y1 + 2.5) / 2, z], [2.6, y1 + 2.5 - y0, 2.6], 0.0, rep=4.0)
    for q in ((-402.0, 30.0), (-402.0, 296.0)):
        _on_ground(ctx, "props_combine/combinetower001", [q[0], 0.0, q[1]], 0.6, tol=1.0)


def _cave_mouth(ctx):
    """Rocks along the caves' cutting where it comes up out of the plateau, and an antlion mound
    between it and the prison's wall."""
    c = _cave(ctx)
    if c is None:
        return
    rng = ctx.rng
    rocks = ["props_wasteland/rockgranite02a", "props_wasteland/rockcliff01b", "props_wasteland/rockgranite03a",
             "props_mining/caverocks_cluster02", "props_wasteland/rockgranite01a"]
    ids = [k for k in range(c.n) if c.style[k] in ("cave_cut", "cave_out")]
    n = 0
    for k in ids[::7]:
        for sgn in (-1, 1):
            q = c.pos[k] + c.flat_right[k] * sgn * (c.width[k] / 2 + 3.0 + 2.5 + rng.uniform(0.5, 4.0))
            q[1] = ctx.ground(q[0], q[2])
            if ctx.road_gap_to(q) < 4.0 or abs(q[1] - PLATEAU) > 0.8:
                continue
            m = rocks[n % len(rocks)]
            n += 1
            if m not in ctx.models:
                # (Episode Two's rocks: not in every install)
                ctx.missing.add(m)
                continue
            g = ctx.site(m, q, 0.0, tol=0.8)
            if g is not None:
                q[1] = g - 0.3
                ctx.add(m, q, float(rng.uniform(0, 6.28)))
    _on_ground(ctx, "props_wasteland/antlionhill", [-424.0, 0.0, 150.0], 1.1, tol=1.2, sink=0.3, margin=1.0)


# ---------------------------------------------------------------- the drops' rims
# round each drop the wall goes round the hole (on the gallery a broken wall of the ruined block, in
# the collapsed yard the yard's own wall): along its far rim and across both its ends, RIM_H metres
# over the road and RIM_T thick, an unseen wall on up to RIM_COL over the road. A kart the guard
# throws across the hole, or one that runs off the edge at speed, meets it and falls in, instead of
# flying on past the caves' walls (rescued outside them: a FALL off the gallery, a scan behind the
# yard's wall). Its inner faces stand where the game's drop box ends (CaveBranch._drop: the main
# road's open edge and the caves' open roof), so a kart against them is still over the drop. Below
# the road it closes the shaft under the gallery (whose ends were open to the plain) and hides its
# rock outside in the block's concrete. A hazard stripe along the road's open edge marks each drop.
RIM_H = {"gallery_drop": 3.5, "slab_drop_l": 3.0, "slab_drop_r": 3.0}
RIM_MAT = {"gallery_drop": "concrete/concretewall032b", "slab_drop_l": "concrete/concretewall032d",
           "slab_drop_r": "concrete/concretewall032d"}
RIM_T = 1.2
RIM_COL = 6.0
# (the caves' rock walls bulge out up to their "rough" past their line, but not within a metre of
# their top: the rim's part under the road stands that much further out)
RIM_ROUGH = 0.65
STRIPE_W = 0.7


def _drop_frame(ctx, dd, c, openk):
    """A drop's frame on the lap (dd: its entry in DROPS): its middle sample's position O, the road's
    flat forward f and its flat right towards the hole r, the road's half width, the deck's height,
    the opening's ends (metres along f from O) and the caves' far wall's offset out along r (its
    nearest to the road)."""
    t = ctx.trk
    # (the lap's samples it spans as CaveBranch._drop takes them)
    run = np.flatnonzero(np.abs(t.s - dd["s"]) <= dd["length"] / 2)
    if len(run) < 2 or t.style[run[0]] not in DROP_SIDES:
        return None
    side = dd["side"]
    im = run[len(run) // 2]
    O = t.pos[im].copy()
    f = _flat(t.fwd[im])
    r = _flat(t.flat_right[im]) * side
    near = openk[np.hypot(c.pos[openk, 0] - O[0], c.pos[openk, 2] - O[2]) < 40.0]
    if not len(near):
        return None
    ks = np.arange(int(near.min()), min(int(near.max()) + 2, c.n))
    far = []
    for k in ks[:-1]:
        sk = 1.0 if float((O - c.pos[k]) @ c.flat_right[k]) > 0.0 else -1.0
        far.append(float((c.pos[k] - c.flat_right[k] * sk * (c.width[k] / 2 + c.wall_gap[k]) - O) @ r))
    # the opening as the game's drop box has it: the main road's open edge (a sample either side) and
    # the caves' open roof (its first open sample to the one that closes it)
    a0 = max(float(t.s[run[0]] - t.step - t.s[im]), float((c.pos[ks[0]] - O) @ f))
    a1 = min(float(t.s[run[-1]] + t.step - t.s[im]), float((c.pos[ks[-1]] - O) @ f))
    # how far along the caves' first and last roofed sections reach at their walls: where the caves bend
    # away from the lap there the section lies askew, and the ends of the rim must reach it (no slit
    # down into the caves between the rim and the roof)
    def ext(k):
        return [float((c.pos[k] + c.flat_right[k] * sg * (c.width[k] / 2 + c.wall_gap[k]) - O) @ f) for sg in (-1.0, 1.0)]
    return {"O": O, "f": f, "r": r, "hw": float(t.width[im] / 2), "y": float(O[1]), "a": (a0, a1),
            "reach": (min(ext(ks[0])), max(ext(ks[-1]))),
            "far": min(far), "style": t.style[run[0]], "s": float(t.s[im])}


def _frame_box(ctx, fr, mat, a, lat, y):
    """A solid box in a drop's frame: a = (from, to) metres along, lat = (from, to) metres out, y =
    (bottom, top)."""
    O, f, r = fr["O"], fr["f"], fr["r"]
    c = O + f * ((a[0] + a[1]) / 2) + r * ((lat[0] + lat[1]) / 2)
    c[1] = (y[0] + y[1]) / 2
    ctx.box(ctx.mats.hl2(mat), c, [abs(lat[1] - lat[0]), y[1] - y[0], abs(a[1] - a[0])],
            ctx.yaw_facing(f), rep=4.0)


def _unseen(ctx, p0, p1, y0, y1):
    """An unseen wall (colonly) from plan points p0 to p1, y0 to y1 high, stopping karts from both
    sides."""
    q = [np.array([p0[0], y0, p0[2]]), np.array([p1[0], y0, p1[2]]), np.array([p1[0], y1, p1[2]]),
         np.array([p0[0], y1, p0[2]])]
    n = np.cross(q[1] - q[0], UP)
    n /= max(float(np.linalg.norm(n)), 1e-9)
    uv = [[0, 0], [1, 0], [1, 1], [0, 1]]
    face(ctx.meshes["colonly"], "colonly", q, n, uv)
    face(ctx.meshes["colonly"], "colonly", q, -n, uv)


def _drop_rims(ctx):
    t = ctx.trk
    c = _cave(ctx)
    if c is None:
        return
    openk = np.array([k for k in range(c.n) if "@open" in c.style[k]], int)
    if not len(openk):
        return
    stripe = ctx.mats.hl2("props/hazardstrip001a")
    for dd in DROPS:
        fr = _drop_frame(ctx, dd, c, openk)
        if fr is None:
            continue
        a0, a1 = fr["a"]
        hw, L1, y = fr["hw"], fr["far"], fr["y"]
        mat = RIM_MAT[fr["style"]]
        top = y + RIM_H[fr["style"]]
        bot = PLATEAU - 1.0
        # the far rim: from a metre under the road's edge up, on the rock's line; under that (only
        # where the deck stands high over the plain: the gallery) further out, clear of its bulges
        high = y - 1.0 > bot + 0.5
        _frame_box(ctx, fr, mat, (a0 - RIM_T, a1 + RIM_T), (L1 + 0.1, L1 + 0.1 + RIM_T), (y - 1.0 if high else bot, top))
        if high:
            _frame_box(ctx, fr, mat, (a0 - RIM_T, a1 + RIM_T), (L1 + RIM_ROUGH, L1 + RIM_ROUGH + RIM_T), (bot, y - 1.0))
        # the two ends, from the road's edge (under the deck from the caves' near wall) to the far rim
        r0, r1 = fr["reach"]
        for a, b in ((min(a0 - RIM_T, r0), a0), (a1, max(a1 + RIM_T, r1))):
            _frame_box(ctx, fr, mat, (a, b), (hw, L1 + RIM_ROUGH + RIM_T), (y - 1.5 if high else bot, top))
            if high:
                _frame_box(ctx, fr, mat, (a, b), (hw - 1.2, L1 + RIM_ROUGH + RIM_T), (bot, y - 1.5))
        # the unseen wall over them
        O, f, r = fr["O"], fr["f"], fr["r"]
        corners = [O + f * a0 + r * hw, O + f * a0 + r * (L1 + 0.1), O + f * a1 + r * (L1 + 0.1), O + f * a1 + r * hw]
        for p0, p1 in zip(corners[:-1], corners[1:]):
            _unseen(ctx, p0, p1, top, y + RIM_COL)
        # the hazard stripe along the open edge, on the road
        q = [O + f * a0 + r * (hw - STRIPE_W), O + f * a1 + r * (hw - STRIPE_W), O + f * a1 + r * (hw - 0.05),
             O + f * a0 + r * (hw - 0.05)]
        for p in q:
            p[1] = y + 0.04
        L = (a1 - a0) / STRIPE_W
        face(ctx.meshes["decal"], stripe, q, UP, [[0, 0], [L, 0], [L, 1], [0, 1]])
        print("  drop rim s %.1f-%.1f: the hole %.1f m wide (out %.1f to %.1f), its walls %.1f m over the road" % (
            fr["s"] + a0, fr["s"] + a1, L1 - hw, hw, L1, top - y))


# ---------------------------------------------------------------- the caves' cutting
# a chain-link fence along both lips of the caves' cutting where it is deeper than a kart's climb
# (and across its mouth, where it comes out from under the plateau by the bend into the cliff road):
# a kart that runs wide off the cliff road or cuts the bend meets it instead of dropping up to 11 m
# into the cutting (the lap's own road is solid; the cutting was the only way into the caves that is
# not a drop)
FENCE_H = 2.4
FENCE_DEEP = 1.2


def _cutting_fence(ctx):
    c = _cave(ctx)
    if c is None:
        return
    mat = ctx.mats.hl2("metal/metalfence004a")
    ks = [k for k in range(c.n) if c.style[k] == "cave_cut" and CUT_TOP - c.pos[k, 1] > FENCE_DEEP]
    if len(ks) < 2:
        return
    ks = np.array(ks)
    off = c.width[ks] / 2 + 0.4
    v = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(c.pos[ks][:, [0, 2]], axis=0), axis=1))])
    for sgn in (-1, 1):
        base = c.pos[ks] + c.flat_right[ks] * (sgn * off)[:, None]
        base[:, 1] = CUT_TOP - 0.2
        top = base + UP * (FENCE_H + 0.2)
        # both faces (chain-link is cut out, drawn one way), 2 cm apart
        out = c.flat_right[ks] * sgn * 0.01
        wall_strip(ctx.meshes["walls"], mat, base - out, top - out, v, sgn, 2.6)
        wall_strip(ctx.meshes["walls"], mat, base + out, top + out, v, -sgn, 2.6)
        _unseen_line(ctx, base, FENCE_H + 0.2, FENCE_H + 1.4)
    # across its mouth (on the plateau over the caves' tunnel where it opens into the cutting)
    k = int(ks[0])
    hw = c.width[k] / 2 + 0.4 + 0.01
    p0 = c.pos[k] - c.flat_right[k] * hw
    p1 = c.pos[k] + c.flat_right[k] * hw
    line = np.array([p0, p1])
    line[:, 1] = CUT_TOP - 0.2
    vv = np.array([0.0, 2.0 * hw])
    for d in (-0.01, 0.01):
        sh = _flat(c.fwd[k]) * d
        wall_strip(ctx.meshes["walls"], mat, line + sh, line + sh + UP * (FENCE_H + 0.2), vv, 1 if d < 0 else -1, 2.6)
    _unseen_line(ctx, line, FENCE_H + 0.2, FENCE_H + 1.4)
    print("  cutting fence: %.0f m each side, deeper than %.1f m (cave u %.0f-%.0f)" % (v[-1], FENCE_DEEP, c.s[ks[0]],
                                                                                       c.s[ks[-1]]))


def _unseen_line(ctx, base, h0, h1):
    """An unseen wall over a polyline (its points' heights the foot), from h0 to h1 over it."""
    for p0, p1 in zip(base[:-1], base[1:]):
        _unseen(ctx, p0, p1, float(p0[1]) + h0, float(p0[1]) + h1)


# ---------------------------------------------------------------- the antlion caves
GRUB = "antlion_grub"
CAVE_LIGHT = [0.45, 0.95, 0.35]
STALACTITES = ["props_mining/stalactite_cluster01", "props_mining/stalactite_cluster02"]
BIG_STALACTITES = ["props_mining/stalactite_static01", "props_mining/stalactite_cluster03",
                   "props_mining/stalactite_static02"]


def _caves(ctx):
    """Episode Two's antlion caves along their road: glowing grubs on the floor by the walls (their
    green light every other cluster), stalactites from the roof (short ones over the road), in the
    hive hall nests with grubs round them, web sacks, rock clusters and sleeping antlions on its
    ledges; by the way out the miners' timber frames and their strings of lamps. (No antlion eggs:
    props_hive/egg's texture is flat grey under $selfillum and drew as glowing white blobs.)"""
    t = ctx.trk
    rng = ctx.rng
    covered = [k for k in range(t.n) if t.kind(k) == "tunnel" and t.styles[t.style[k]].get("roof", True)]
    hall = [k for k in covered if t.wall_gap[k] > 3.0]
    lit = 0
    for n, k in enumerate(range(3, t.n - 3, 7)):
        if t.kind(k) != "tunnel" or t.gap[k]:
            continue
        sgn = 1 if n % 2 else -1
        gap = t.wall_gap[k]
        rf = t.flat_right[k] * sgn
        count = 3 if gap > 3.0 else 1
        first = None
        for g in range(count):
            lat = t.width[k] / 2 + (gap * 0.45 if gap < 2.0 else rng.uniform(0.9, gap - 0.9))
            q = t.pos[k] + rf * lat + t.fwd[k] * (rng.uniform(-1.5, 1.5) if count > 1 else 0.0)
            q[1] = t.pos[k][1]
            yaw = ctx.yaw_facing(t.fwd[k]) + float(rng.uniform(-0.5, 0.5))
            if ctx.add(GRUB, q, yaw, ground=False, tag="deco", on_road=True) and first is None:
                first = q
        if first is not None and n % 2 == 0:
            ctx.light(first + UP * 0.7, CAVE_LIGHT, 12.0, 1.5)
            lit += 1
    # stalactites: short ones over the road, long ones over the hall's ledges
    for n, k in enumerate(covered[2::7]):
        lat = float(rng.uniform(-3.5, 3.5))
        q = t.pos[k] + t.flat_right[k] * lat + UP * (t.height[k] + 0.3)
        ctx.add(STALACTITES[n % 2], q, float(rng.uniform(0, 6.28)), ground=False, base=False, tag="deco")
    for n, k in enumerate(hall[1::4]):
        sgn = 1 if n % 2 else -1
        q = t.pos[k] + t.flat_right[k] * sgn * (t.width[k] / 2 + t.wall_gap[k] * 0.55) + UP * (t.height[k] + 0.3)
        ctx.add(BIG_STALACTITES[n % 3], q, float(rng.uniform(0, 6.28)), ground=False, base=False, tag="deco")
    # the hive hall's ledges: a nest every 20 m or so with grubs round it, web sacks over them, rocks
    # and three sleeping antlions
    sleepers = 0
    for n, k in enumerate(hall[4:-4:10]):
        if t.wall_gap[k] < 4.0:
            continue
        sgn = -1 if n % 2 else 1
        rf = t.flat_right[k] * sgn
        mid = t.width[k] / 2 + t.wall_gap[k] / 2
        c = t.pos[k] + rf * mid
        c[1] = t.pos[k][1]
        nest = "props_hive/nest_med_flat" if n % 2 == 0 else "props_hive/nest_sm_flat"
        ctx.add(nest, c, float(rng.uniform(0, 6.28)), ground=False, tag="deco", on_road=True)
        for e in range(4):
            a = rng.uniform(0, 6.28)
            q = c + np.array([math.cos(a), 0.0, math.sin(a)]) * rng.uniform(1.8, 2.2)
            if abs((q - t.pos[k]) @ t.flat_right[k]) < t.width[k] / 2 + 0.5:
                continue
            ctx.add(GRUB, q, float(a), ground=False, tag="deco", on_road=True)
        ctx.add("props_hive/websackceiling01", c + UP * (t.height[k] + 0.15), float(rng.uniform(0, 6.28)),
                ground=False, base=False, tag="deco")
        j = min(k + 4, t.n - 1)
        q = t.pos[j] + t.flat_right[j] * sgn * (t.width[j] / 2 + t.wall_gap[j] * 0.55)
        q[1] = t.pos[j][1]
        if n % 3 == 1 and sleepers < 3:
            if ctx.add("antlion", q - UP * 0.25, ctx.yaw_facing(t.fwd[j]) + float(rng.uniform(-1.0, 1.0)),
                       ground=False, tag="deco", on_road=True):
                sleepers += 1
        else:
            ctx.add("props_mining/caverocks_cluster0%d" % (1 + n % 2), q - UP * 0.3, float(rng.uniform(0, 6.28)),
                    ground=False, tag="deco", on_road=True)
    # the dead end: rocks piled against its face
    k = 1
    for sgn in (-1, 1):
        q = t.pos[k] + t.flat_right[k] * sgn * (t.width[k] / 2 - 1.2) - t.fwd[k] * 1.0
        q[1] = t.pos[k][1] - 0.3
        ctx.add("props_mining/caverocks_cluster02", q, float(rng.uniform(0, 6.28)), ground=False, tag="deco",
                on_road=True)
    # the way out: under the slab's end the miners' timber frames every 8 m (wall to wall, overhead:
    # nobody hits them) and their strings of lamps along both walls, warm lights
    out = [k for k in covered if t.pos[k][0] < -372.0]
    for n, k in enumerate(out[::4]):
        yaw = ctx.yaw_facing(t.fwd[k])
        frame = "props_mining/struts_tunnel320_01"
        if frame in ctx.models:
            c = _centred(ctx, frame, t.pos[k], yaw, 1.42)
            c[1] = t.pos[k][1] - 0.05
            ctx.add(frame, c, yaw, scale=1.42, ground=False, base=False, tag="far")
        else:
            # (Episode Two's frames: not in every install; the lamps still light the way out)
            ctx.missing.add(frame)
        if n % 2 == 0:
            ctx.light(t.pos[k] + UP * 6.0, [1.0, 0.78, 0.45], 16.0, 1.4)
    for n, k in enumerate(out[2::9]):
        for sgn in (-1, 1):
            q = t.pos[k] + t.flat_right[k] * sgn * (t.width[k] / 2 + t.wall_gap[k] - 0.3) + UP * (t.height[k] - 2.0)
            ctx.add("props_mining/lamps01", q, ctx.yaw_facing(-t.fwd[k]), ground=False, base=False, tag="deco",
                    solid=False)


def decorate_branch(ctx, spec):
    if spec["id"] == "caves":
        n0, l0 = len(ctx.props), len(ctx.lights)
        _caves(ctx)
        print("  caves: dressed with %d props, %d lights" % (len(ctx.props) - n0, len(ctx.lights) - l0))


def decorate(ctx):
    room = cave_room(ctx.trk)
    print("  caves: lap s %.0f-%.0f over them, the guard's stretch s %.0f-%.0f" % (room["cave_s"] + room["guard_s"]))
    for dp in room["drops"]:
        print("  caves: drop place s %.0f-%.0f side %+d (%s), open edge %s - %s, the caves' floor at %.0f" % (
            dp["s"][0], dp["s"][1], dp["side"], dp["style"], dp["edge"][0], dp["edge"][1], dp["floor_y"]))
    _shells(ctx)
    _depot(ctx)
    _gallery_wall(ctx)
    _outer_wall(ctx)
    _drop_rims(ctx)
    _cutting_fence(ctx)
    _masts(ctx)
    _backdrop(ctx)
    for part in (_signs, _yards, _cellblock, _canteen, _laundry, _roof, _gallery_doors, _ruins, _cave_mouth):
        n0, l0 = len(ctx.props), len(ctx.lights)
        part(ctx)
        print("  dressing %-15s %3d props, %2d lights" % (part.__name__.strip("_"), len(ctx.props) - n0,
                                                          len(ctx.lights) - l0))
    _blocks(ctx)


# ---------------------------------------------------------------- the prison's blocks
# the prison's other buildings on its plateau, so the lap runs between blocks instead of across an
# open paved plain: cell blocks, stores and workshops in a grid of BLOCK_CELL metres, each a box of
# Nova Prospekt's concrete BLOCK_W across (a smaller one where that does not fit) with a flat roof
# and on one in four a vent or an aerial, BLOCK_H high (most under the upper level's 12 m: from
# the walkways and the depot's roof you look out over their roofs). One stands only on flat plateau
# inside the walls, BLOCK_CLEAR metres or more off every road (a hall's outside walls counted, every
# level: none under a walkway), off the caves and their cutting, the hazards' corridors, every prop
# and the ruined block's yard (its rubble, mounds and fires are the battle's; the caves under it)
BLOCK_CELL = 30.0
BLOCK_W = (14.0, 25.0)
BLOCK_H = (6.5, 14.0)
BLOCK_CLEAR = 6.0
BLOCK_AREA = (-400.0, 428.0, -228.0, SOUTH_Z - 12.0)   # x from, to; z from, to
RUINED_YARD = (-392.0, -112.0, 26.0, SOUTH_Z)          # x from, to; z from, to
# (Nova Prospekt's concretes and the outer wall's stone; no plaster: its flat white drew as blank boxes)
BLOCK_WALLS = ("concrete/concretewall032d", "concrete/concretewall032b", "concrete/concretewall004c",
               "stone/stonewall017b")
BLOCK_KIT = ("props_rooftop/roof_vent001", "props_rooftop/roof_vent002", "props_rooftop/antenna01a",
             "props_rooftop/chimneypipe_cluster02a", "props_rooftop/rooftopcluser01a")


def _block_fits(ctx, cx, cz, hx, hz, reach):
    """True when a block of half sizes hx, hz centred on (cx, cz) may stand there (see BLOCK_CLEAR)."""
    r = ctx.roads
    pts = [(cx + a * hx, cz + b * hz) for a in np.linspace(-1.0, 1.0, 5) for b in np.linspace(-1.0, 1.0, 5)]
    P = np.array(pts)
    d = np.hypot(r.pos[None, :, 0] - P[:, None, 0], r.pos[None, :, 2] - P[:, None, 1]) - reach[None, :]
    if (d < BLOCK_CLEAR).any():
        return False
    for x, z in pts:
        q = np.array([x, PLATEAU, z])
        if abs(ctx.ground(x, z) - PLATEAU) > 0.5 or _over_cave(ctx, q, 4.0):
            return False
    for poly, hw in getattr(ctx, "reserved", []):
        Q = poly[:, [0, 2]]
        for a, b in zip(Q[:-1], Q[1:]):
            ab = b - a
            u = np.clip(((P - a) @ ab) / max(float(ab @ ab), 1e-9), 0.0, 1.0)
            if (np.linalg.norm(P - (a + u[:, None] * ab), axis=1) < hw + 2.0).any():
                return False
    for pr in ctx.props:
        p = pr["pos"]
        if abs(p[0] - cx) < hx + 3.0 and abs(p[2] - cz) < hz + 3.0:
            return False
    return ctx.free([cx, PLATEAU + 6.0, cz], [2.0 * hx + 2.0, 12.0, 2.0 * hz + 2.0])


def _blocks(ctx):
    r = ctx.roads
    rng = np.random.default_rng(1729)
    reach = r.width / 2 + np.where(_tunnels(ctx), r.wall_gap + SHELL, 0.0)
    roof = ctx.mats.hl2("concrete/concretefloor038b")
    x0, x1, z0, z1 = BLOCK_AREA
    n = 0
    for cx in np.arange(x0 + BLOCK_CELL / 2, x1, BLOCK_CELL):
        for cz in np.arange(z0 + BLOCK_CELL / 2, z1, BLOCK_CELL):
            if RUINED_YARD[0] < cx < RUINED_YARD[1] and RUINED_YARD[2] < cz < RUINED_YARD[3]:
                continue
            # (a little off the grid and of all sizes, so the rows do not line up like a chessboard)
            jx, jz = rng.uniform(-3.0, 3.0, 2)
            wx, wz = rng.uniform(*BLOCK_W, 2)
            h = float(rng.uniform(*BLOCK_H))
            mat = BLOCK_WALLS[int(rng.integers(0, len(BLOCK_WALLS)))]
            kit = BLOCK_KIT[int(rng.integers(0, len(BLOCK_KIT)))] if rng.uniform() < 0.25 else None
            ky = float(rng.uniform(0, 6.28))
            for f in (1.0, 0.7):
                bx, bz, sx, sz = cx + jx, cz + jz, wx * f, wz * f
                if not _block_fits(ctx, bx, bz, sx / 2, sz / 2, reach):
                    continue
                y0, y1 = PLATEAU - 1.0, PLATEAU + h
                ctx.box(ctx.mats.hl2(mat), [bx, (y0 + y1) / 2, bz], [sx, y1 - y0, sz], 0.0, rep=4.0)
                q = [np.array([bx - sx / 2, y1 + 0.05, bz - sz / 2]), np.array([bx + sx / 2, y1 + 0.05, bz - sz / 2]),
                     np.array([bx + sx / 2, y1 + 0.05, bz + sz / 2]), np.array([bx - sx / 2, y1 + 0.05, bz + sz / 2])]
                face(ctx.meshes["deco"], roof, q, UP, [[0, 0], [sx / 5.0, 0], [sx / 5.0, sz / 5.0], [0, sz / 5.0]])
                if kit is not None:
                    ctx.add(kit, [bx, y1, bz], ky, ground=False, tag="deco", solid=False)
                n += 1
                break
    print("  dressing blocks          %3d buildings" % n)


# ---------------------------------------------------------------- spectators
def _pavement_spot(ctx, i, sgn):
    """On a yard's pavement towards its wall (the crowd's rules stand it on the pavement)."""
    st = ctx.style_of(i)
    if st["kind"] != "street":
        return None
    q = ctx.side_point(i, sgn, 0.3 + st["walk"] - ctx.crowd_rng.uniform(0.6, 1.3), jitter=0.5)
    return None if _over_cave(ctx, q) else q


def _hall_spot(ctx, i, sgn, back=2.0):
    """On a hall's side floor `back` metres out from its wall (clear of the doors and bunks against it)."""
    t = ctx.trk
    st = ctx.style_of(i)
    if st["kind"] != "tunnel" or t.wall_gap[i] < back + 2.5:
        return None
    return ctx.side_point(i, sgn, t.wall_gap[i] - back + ctx.crowd_rng.uniform(-0.4, 0.4), y=t.pos[i][1], jitter=0.4)


def crowds(ctx):
    """Nova Prospekt's Combine prison guards: along both pavements of the entry yard at the start and
    in the inner yard, on the floor of cell block A, up on the depot's roof behind its parapet; the
    prisoners in the courtyards; rebels and freed prisoners out on the cliff road by the laundry; the
    G-Man on the depot's roof."""
    t = ctx.trk
    rng = ctx.crowd_rng
    guard = dict(mood="military", model=GUARD_MODEL)
    # the start: guards on both pavements of the entry yard
    ids = [i for i in ctx.lap_ids(-70.0, 70.0) if t.style[i] == "yard"]
    for ch in ctx.chunks(ids, int(35 / t.step), int(30 / t.step)):
        for sgn in (-1, 1):
            gid = ctx.crowd_group(ch[len(ch) // 2], sgn, "line", "combine", tags=["start"])
            ctx.crowd_line(gid, ch, sgn, 2.5, lambda i, s: _pavement_spot(ctx, i, s), "combine", chance=0.75,
                           margin=0.6, **guard)
    # the inner yard: a squad either side
    ids = _style_ids(t, ("inner",))
    for ch in ctx.chunks(ids, int(40 / t.step), int(24 / t.step)):
        sgn = 1 if ch[0] % 2 else -1
        gid = ctx.crowd_group(ch[len(ch) // 2], sgn, "line", "combine", tags=["yard"])
        ctx.crowd_line(gid, ch, sgn, 3.0, lambda i, s: _pavement_spot(ctx, i, s), "combine", chance=0.8,
                       margin=0.6, **guard)
    # cell block A: guards on its floor along the south wall, out of the karts' way
    ids = _style_ids(t, ("cellblock",))
    for ch in ctx.chunks(ids, int(45 / t.step), int(24 / t.step)):
        gid = ctx.crowd_group(ch[len(ch) // 2], 1, "post", "combine", tags=["cellblock"])
        ctx.crowd_line(gid, ch, 1, 4.0, lambda i, s: _hall_spot(ctx, i, s, 2.5), "combine", chance=0.8, margin=0.5,
                       on="geom", **guard)
    # the courtyards: prisoners on the pavements, watching
    ids = _style_ids(t, ("court",))
    for ch in ctx.chunks(ids, int(36 / t.step), int(16 / t.step)):
        sgn = -1 if ch[0] % 3 else 1
        gid = ctx.crowd_group(ch[len(ch) // 2], sgn, "line", "refugee", tags=["court"])
        ctx.crowd_line(gid, ch, sgn, 2.0, lambda i, s: _pavement_spot(ctx, i, s), "refugee", chance=0.7, margin=0.6,
                       mood=["fan", "excited"][int(rng.integers(0, 2))])
    # the depot's roof: guards behind the parapet on the inside of the U (the road's left)
    ids = _style_ids(t, ("roof",))
    for ch in ctx.chunks(ids, int(50 / t.step), int(14 / t.step)):
        i = ch[len(ch) // 2]
        gid = ctx.crowd_group(i, -1, "cluster", "combine", tags=["roof"])
        c = ctx.side_point(i, -1, 4.5)
        ctx.crowd_cluster(gid, c, 4, 2.5, "combine", t.pos[i] + UP, ref_y=t.pos[i][1], dy=(-1.5, 0.5), margin=1.0,
                          **guard)
    # the cliff road by the laundry: rebels and the prisoners they freed on its inland side
    for s0 in (2395.0, 2430.0):
        i = int(round(s0 / t.step)) % t.n
        if t.style[i] != "outer":
            continue
        c = ctx.shoulder_spot(i, 1, 4.0, 7.0)
        if _over_cave(ctx, c, 4.0):
            continue
        gid = ctx.crowd_group(i, 1, "cluster", "rebel", tags=["cliff"])
        ctx.crowd_cluster(gid, c, 5, 3.0, "rebel", t.pos[i] + UP, mood="excited", ref_y=t.pos[i][1], dy=(-1.0, 1.5),
                          margin=4.0)
        ctx.crowd_cluster(gid, c, 3, 3.5, "refugee", t.pos[i] + UP, mood="fan", ref_y=t.pos[i][1], dy=(-1.0, 1.5),
                          margin=4.0)
    eggs(ctx)


def eggs(ctx):
    # the G-Man where he is seen best: on the depot's roof watching the karts come round it, else on
    # the cliff top by the road outside the walls, else down in the ruined block's yard under the gallery
    for lo, hi, off in ((1180.0, 1460.0, (5.0, 30.0)), (2140.0, 2300.0, (6.0, 40.0)), (1600.0, 1670.0, (8.0, 40.0))):
        g = ctx.gman_spot(lo, hi, off=off)
        if g is not None and not _over_cave(ctx, np.asarray(g["pos"], float), 4.0):
            ctx.egg("gman", pos=g["pos"], yaw=g["yaw"], s=g["s"], model="gman_high", window=g["window"], chance=0.4)
            break
