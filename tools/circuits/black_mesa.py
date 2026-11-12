"""Black Mesa: an indoor lap of the Research Facility, about 2.1 km, that crosses the Lambda
reactor room twice.

The Sector C lobby, then a high walk straight across the reactor room beside the glowing core,
the office switchback, the Anomalous Materials lab wing, the tram tunnel and the accelerator
pipe, a high-security storage hall (a slime-pit jump, a toxic spill and ceiling turrets on the
floor, the crane gantry along its north wall above them: you drop off its end back onto the
road), waste processing with toxic channels and a second slime jump, then down at coolant level
round the core (under the high walk) and back up to the lobby. The broken maintenance catwalk
across the coolant pool cuts the loop round the core: jump its gap or swim.
"""
import math

import numpy as np

from track_gen import UP, _barrier, face, plane_uv

ROOM_C = np.array([110.0, 0.0, 150.0])
ROOM_R = 88.0
LOOP_R = 46.0      # the coolant-level road round the core's south side ...
LOOP_Z = 178.0     # ... about this centre, 28 m south of the core: long straights down to it
CAT_R, CAT_Z = 42.0, 139.0  # the coolant catwalk: its arc inside the loop, close by the core
CORE_R = 14.0
LOOP_STYLES = ("reactor_in", "reactor")  # the coolant-level road's styles, in from the waste's door
# tight bends between walls: their hall's style under its own name with a speed cap for the
# computer drivers' racing line ("vmax", m/s; at full pace they slid into the walls there and
# stuck), dressed as their hall
BENDS = {"office_s": ("office", 20.0), "lab_end": ("lab", 22.0), "tram_turn": ("tram", 14.0),
         "corridor_turn": ("corridor", 15.0)}
POOL_Y = -26.0
ROOF_Y = 22.0
WALK_X, WALK_Y = 85.0, 5.0   # the high walk across the room, west of the core
HALL_Z, HALL_Y = -40.0, -12.0  # the storage hall, heading west
GANTRY_Z = HALL_Z - 14.0       # the crane gantry over the hall's north floor, 5.6 m up, by the wall


def _loop():
    """The road round the core's south side at coolant level, climbing a little."""
    pts = []
    for k, a in enumerate(range(0, 181, 45)):
        r = math.radians(a)
        pts.append((ROOM_C[0] + math.cos(r) * LOOP_R, -13.8 + 0.2 * k, LOOP_Z + math.sin(r) * LOOP_R, 16, "reactor"))
    return pts


# the catwalk's heights round its arc (degrees): at its ends those of the coolant road it shares
# its deck with (the east straight level at -14, the west one climbing past -12.9), a little
# lower at the kicker and the landing, back up to the road over the 20 m after the landing
CAT_Y = {30: -14.0, 60: -14.15, 90: -14.3, 120: -14.2, 135: -13.15, 150: -12.85}


def _catwalk(gap_at=90, span=(0.40, 0.84)):
    """The coolant catwalk's control points: an arc round the core inside the loop, from the east
    straight to the west one, its broken span on the stretch from gap_at degrees: a kicker that
    carries a kart over it from 23 m/s, and from there a landing that widens on the outside of the
    bend (a kart flies straight on while the arc bends away) with a catch fence along it."""
    out = []
    for a, y in sorted(CAT_Y.items()):
        q = math.radians(a)
        fl = {"gap": True, "gap_span": span, "ramp_lift": 1.3} if a == gap_at else {}
        w = {gap_at + 30: 12, gap_at + 45: 10}.get(a, 8)
        st = "catwalk_land" if gap_at <= a < 150 else "catwalk_merge" if a >= 150 else "catwalk"
        out.append((ROOM_C[0] + math.cos(q) * CAT_R, y, CAT_Z + math.sin(q) * CAT_R, w, st, fl))
    return out


CTRL = [
    # the lobby: the start line, the grid behind it
    (0, 0, 0, 22, "lobby"),
    (56, 0, 0, 22, "lobby"),
    # up to the high walk's north door (the lobby's floors run on round its first corner, where the
    # pack arrives three abreast; its walls close in on the straight after it)
    (76.5, 0.8, 8.5, 18, "lobby"),
    (WALK_X, 2.6, 34, 15, "corridor"),
    # across the reactor room, west of the core, over the coolant loop and the catwalk
    (WALK_X, WALK_Y, 60.5, 14, "highwalk"),
    (WALK_X, WALK_Y, 110, 14, "highwalk"),
    (WALK_X, WALK_Y, 150, 14, "highwalk"),
    (WALK_X, WALK_Y, 190, 14, "highwalk"),
    # the office switchback from the south door
    (WALK_X, WALK_Y, 237.5, 14, "office"),
    (92, 3.2, 262, 14, "office"),
    (114, 1.2, 286, 14, "office"),
    (150, 0, 298, 14, "office"),
    # (its S-bend 2 m wider and eased at the same length: the pack comes through it three abreast)
    (192, 0, 296, 15, "office_s"),
    (215, 0, 276.5, 16, "office_s"),
    (223, 0, 254, 16, "office_s"),
    (240, -0.4, 236.5, 16, "office_s"),
    # the lab wing, east
    (270, -0.8, 232, 16, "lab"),
    (320, -2.0, 236, 16, "lab"),
    (368, -3.2, 250, 16, "lab_end"),
    (399, -4.5, 237, 16, "lab_end"),
    # the tram tunnel turns north into the accelerator pipe, then east and round a hairpin
    (412, -6, 206, 15, "tram"),
    (412, -7, 182, 15, "accel"),
    (414, -9.5, 110, 15, "accel"),
    (412, -11.5, 40, 15, "tram"),
    (426, -12, 8, 15, "tram"),
    (472, -12, -4, 15, "tram_turn"),
    (496, -12, -14, 15, "tram_turn"),
    # the storage hall, west (from the hairpin's exit: its walls are out at the floor's full width
    # where the straight begins): the crane gantry swings out over the north floor at floor level,
    # climbs past the slime pit along the north wall; the spill and the turrets on the floor under it
    (496, -12, -33, 15, "storage"),
    (476, HALL_Y, HALL_Z, 20, "storage"),
    (420, HALL_Y, HALL_Z, 20, "storage"),
    (388, HALL_Y, HALL_Z, 20, "storage", {"gap": True, "gap_span": (0.44, 0.875), "ramp_lift": 2.2}),
    (356, HALL_Y, HALL_Z, 20, "storage"),
    (310, HALL_Y, HALL_Z, 20, "storage"),
    (260, HALL_Y, HALL_Z, 20, "storage"),
    (226, HALL_Y, HALL_Z, 20, "storage"),
    (200, HALL_Y, HALL_Z, 20, "storage"),
    # waste processing: round to the south, the second slime jump, into the room's north-east door
    (184, -12.2, HALL_Z, 13, "waste"),
    (162, -12.5, -28, 13, "waste"),
    (157, -13, -6, 13, "waste"),
    # (a low kicker: at full speed a kart lands in the waste, not out over the coolant road's edge)
    (156, -13, 24, 13, "waste", {"gap": True, "gap_span": (0.35, 0.7), "ramp_lift": 1.0}),
    (156, -13.5, 54, 13, "waste"),
    # down at coolant level: south along the east side (railed both sides where the karts come in
    # off the waste's jump), round the core, north along the west
    (156, -14, 66.5, 16, "reactor_in"),
    (156, -14, 105, 16, "reactor"),
    (156, -14, 144, 16, "reactor"),
    (156, -14, LOOP_Z - 22, 16, "reactor"),
] + _loop() + [
    (64, -12.8, LOOP_Z - 22, 16, "reactor"),
    (64, -12.6, 144, 16, "reactor"),
    # out of the north-west door, west and round a hairpin to the lobby
    (64, -12.4, 70, 14, "corridor"),
    (58, -12, 56, 14, "corridor"),
    (40, -11, 44, 14, "corridor"),
    (0, -9, 42, 14, "corridor"),
    (-44, -6.5, 42, 14, "corridor_turn"),
    (-73, -4, 36, 14, "corridor_turn"),
    (-79, -2.5, 21, 15, "corridor_turn"),
    (-73, -1, 6, 18, "corridor_turn"),
    (-56, 0, 0, 22, "lobby"),
]
CTRL = [c if len(c) > 5 else c + ({},) for c in CTRL]

BRANCHES = [
    # the crane gantry: out over the hall's north floor at floor level (it only climbs once clear
    # of the road, so its deck never steps), up along the north wall 5.6 m over the floor past the
    # slime pit, the spill and the turrets (railed on the wall side only: fall off and you land on
    # the road or in the pit), then it swings in over the road and ends: you drop back onto it
    {"id": "crane_gantry", "name": "Crane gantry", "fork": (448, HALL_Z), "merge": (200, HALL_Z), "in_hall": True,
     "kind": "high", "side": 1, "merge_side": 1, "merge_type": "drop",
     "ctrl": [(429, HALL_Y + 0.04, HALL_Z - 9.9, 8, "gantry"),
              (410, HALL_Y + 0.05, GANTRY_Z - 0.1, 8, "gantry"),
              (398, HALL_Y + 0.45, GANTRY_Z - 0.25, 8, "gantry"),
              (380, HALL_Y + 3.7, GANTRY_Z - 0.1, 8, "gantry"),
              (352, HALL_Y + 5.5, GANTRY_Z, 8, "gantry"),
              (282, HALL_Y + 5.6, GANTRY_Z, 8, "gantry"),
              (250, HALL_Y + 5.6, GANTRY_Z + 2.0, 8, "gantry"),
              (230, HALL_Y + 5.6, HALL_Z - 9.0, 8, "gantry", {"gap": True, "gap_span": (0.05, 0.95), "ramp_lift": 0.3,
                                                              "ramp_len": 8}),
              # (a hand over the floor: the spline still falls past this point; the landing is the
              # hall road itself, the build lays it there)
              (219, HALL_Y + 0.35, HALL_Z - 7.0, 8, "gantry")],
     "boosts": [0.45], "risk": 0.35, "ai": {"take": 0.5, "min_skill": 0.8}, "respawn": "main",
     # over its fork boards the HL1 sign "CRANE -> CONTROL"
     "signs": {"panel": "goldsrc/c1a3_sign3"}},
    # the broken maintenance catwalk: off the east straight, round the core's south side inside the
    # loop (the same bend, 90 m shorter), onto the west straight; it broke under the high walk
    {"id": "coolant_jump", "name": "Coolant jump", "fork": (156, CAT_Z), "merge": (64, CAT_Z), "kind": "jump",
     "side": 1, "merge_side": 1, "ctrl": _catwalk(),
     "risk": 0.5, "ai": {"take": 0.6, "min_skill": 0.85}, "respawn": "before", "retry_back": 40.0,
     # over its fork boards the HL1 sign "02 COOLANT SYSTEM ->"
     "signs": {"panel": "goldsrc/c3a2sign08"}},
]

TRACK = {
    "id": "black_mesa",
    "music": ['hl1_song10', 'hl1_song11', 'hl1_song14', 'hl1_song15', 'hl1_song17', 'hl1_song25_remix3'],
    "name": "Black Mesa",
    "ctrl": CTRL,
    "items": [0.048, 0.164, 0.313, 0.400, 0.602, 0.664, 0.789, 0.924],
    # (on straights: a pad in a tight bend between walls threw karts into them, and one before the
    # waste's kicker flew them over its landing and out through the reactor room's door)
    "boosts": [0.097, 0.202, 0.272, 0.359, 0.414, 0.504, 0.715, 0.755, 0.885],
    # (none in the offices' S-bend: blown into its walls, karts stuck there)
    "barrels": [0.496, 0.904],
    "vmax": 34.0,
    # the game's gravity (project.godot): the launch speeds the branches export are the real ones
    "gravity": 15.24,
    "offtrack": 30.0,
    "sky": "sky_day01_01",
    "background": "none",
    "gantry": "blackmesa",
    "env": {"sun_energy": 0.0, "ambient": [0.36, 0.37, 0.4], "ambient_energy": 1.0, "fog_begin": 120.0,
            "fog_end": 700.0, "fog_color": [0.08, 0.09, 0.1], "sdfgi": False, "exposure": 1.15, "glow": 0.6},
    # lap metres of this layout: the offices start at s 310, the labs at s 560, the storage
    # hall's slime pit ends at s 1163 (its landing) and the high walk runs from s 134 to 310
    "hazards": [
        # offices: laser tripmines from the wall to a crate stand just short of the centre (pass on
        # the other side), a slalom of two before the S-bend; one blast per pass of the offices at
        # most (a group), the same in the labs (on their straight: a kart tumbled into the walls
        # of the bends after them got stuck there)
        # (a blast reaches 3.5 m: the kart that tripped it and any right beside it, not the pack)
        {"type": "tripmine", "s": 376, "from": -1, "to": -0.05, "group": "offices", "radius": 3.5, "rearm": 12.0},
        {"type": "tripmine", "s": 430, "from": 1, "to": 0.05, "group": "offices", "radius": 3.5, "rearm": 12.0},
        # lab wing: the same
        {"type": "tripmine", "s": 600, "from": -1, "to": -0.05, "group": "labs", "radius": 3.5, "rearm": 12.0},
        {"type": "tripmine", "s": 636, "from": 1, "to": 0.05, "group": "labs", "radius": 3.5, "rearm": 12.0},
        # storage hall: HL1 ceiling turrets drop down over the floor after the slime pit (the crane
        # gantry passes them by); short bursts and a long cool-down between them
        {"type": "turret", "s": 1241, "lat": -2.5, "mount": "ceiling", "model": "hl1/turret", "scale": 1.5,
         "zone": [1201, 1245], "range": 45, "cone": 70, "lock": 1.0, "burst": 0.6, "shots": 5, "cool": 10.0},
        {"type": "turret", "s": 1295, "lat": 2.5, "mount": "ceiling", "model": "hl1/turret", "scale": 1.5,
         "zone": [1255, 1299], "range": 45, "cone": 70, "lock": 1.0, "burst": 0.6, "shots": 5, "cool": 10.0},
        # the Lambda core discharges onto the core side of the high walk (railed both sides: a hit
        # spins you, it never throws you into the pool)
        {"type": "strike_zone", "style": "arc", "zone": [146, 292], "core": [float(ROOM_C[0]), WALK_Y, float(ROOM_C[2])],
         "every": 1.2, "count": 2, "radius": 4.0, "warn": 1.4, "effect": "shock", "push": 0.0},
    ],
}


def styles(m):
    g = m.goldsrc
    stripe = g("stripes1")
    out = {
        "lobby": {"kind": "tunnel", "road": g("c1a0_labflr"), "road_rep": 3.0, "height": 12.0, "wall": g("fifties_w12"),
                  "side_floor": g("c1a0_labflrb"),
                  "wall_rep": 3.0, "band": g("c2a4e_w1"), "band_h": 2.4, "band_rep": 2.4, "ceil": g("fifties_ceil02"),
                  "ceil_rep": 3.0, "light": g("panellite1", glow=True), "light_every": 9.0,
                  "light_rows": [-0.6, 0.0, 0.6], "light_w": 2.2, "light_l": 3.2, "light_color": [1.0, 0.96, 0.88],
                  "light_energy": 1.6, "wall_gap": 4.0},
        "office": {"kind": "tunnel", "road": g("fifties_flr03"), "road_rep": 2.5, "height": 6.5, "wall": g("fifties_w13"),
                   "wall_rep": 3.0, "band": g("lab1_w6"), "band_h": 1.2, "ceil": g("fifties_ceil01"), "ceil_rep": 2.5,
                   "light": g("litepanel1", glow=True), "light_every": 8.0, "light_rows": [-0.4, 0.4], "light_w": 1.6,
                   "light_l": 2.4, "light_color": [1.0, 0.95, 0.85], "light_energy": 1.3, "wall_gap": 2.0,
                   "portals": False},
        "lab": {"kind": "tunnel", "road": g("lab1_flr4"), "road_rep": 3.0, "height": 8.0, "wall": g("lab1_w4"),
                "wall_rep": 2.5, "band": stripe, "band_h": 0.8, "band_rep": 1.0, "ceil": g("lab1_w8ceil1"),
                "ceil_rep": 2.5, "light": g("skkylite", glow=True), "light_every": 9.0, "light_rows": [-0.45, 0.45],
                "light_color": [0.9, 0.95, 1.0], "light_energy": 1.5, "wall_gap": 3.0},
        "tram": {"kind": "tunnel", "road": g("tnnl_flr1"), "road_rep": 4.0, "height": 9.0, "wall": g("tnnl_w12a"),
                 "wall_rep": 4.0, "band": g("c1a4_w5"), "band_h": 2.0, "band_rep": 2.0, "ceil": g("crete3_ceil01"),
                 "ceil_rep": 3.0, "light": g("~tracklite"), "light_every": 14.0, "light_rows": [-0.85, 0.85],
                 "light_w": 0.8, "light_l": 3.0, "light_color": [1.0, 0.82, 0.55], "light_energy": 1.4, "wall_gap": 1.0},
        # the anomalous materials accelerator: the road rolls once round the pipe, back at its bottom
        # 40 m before the exit (a kart still up the wall there met the exit's bulkhead)
        "accel": {"kind": "tube", "road": g("tnnl_flr4"), "road_rep": 4.0, "wall": g("metal_wall04"),
                  "skin": g("metal_wall04"), "glow": g("skkylite", glow=True), "radius": 11.0, "roll": -360.0,
                  "settle": 14.0, "ring_every": 14.0, "light_color": [0.75, 0.88, 1.0], "light_energy": 1.6},
        "storage": {"kind": "tunnel", "road": g("crete4_flr01"), "road_rep": 4.0, "height": 16.0, "wall": g("silo2_wall1"),
                    "side_floor": g("crete2_flr01"),
                    "wall_rep": 4.0, "band": stripe, "band_h": 1.0, "band_rep": 1.0, "ceil": g("drkmtlt_ceil01"),
                    "ceil_rep": 4.0, "light": g("c3a2_light", glow=True), "light_every": 12.0,
                    "light_rows": [-0.7, 0.0, 0.7], "light_w": 2.0, "light_l": 2.6, "light_color": [1.0, 0.9, 0.75],
                    "light_energy": 1.7, "wall_gap": 9.0,
                    "gap_pit": {"mat": g("!toxicgrn", glow=True), "depth": 6.0, "glow": True, "liquid": "slime"}},
        "waste": {"kind": "tunnel", "road": g("c1a1_flr2a"), "road_rep": 3.0, "height": 9.0, "wall": g("c2a4e_w1"),
                  "wall_rep": 3.0, "ceil": g("crete3_ceil01"), "light": g("~light5a"), "light_every": 12.0,
                  "light_rows": [-0.9, 0.9], "light_w": 0.8, "light_l": 3.2, "light_color": [0.55, 1.0, 0.55],
                  "light_energy": 1.5, "wall_gap": 6.0, "portals": False,
                  "pit": {"mat": g("!toxicgrn", glow=True), "depth": 1.4, "glow": True, "liquid": "slime"},
                  "gap_pit": {"mat": g("!toxicgrn", glow=True), "depth": 4.0, "glow": True, "liquid": "slime"},
                  "barrier": {"kind": "fence", "mat": g("{grate2"), "h": 1.1, "rep": 2.0, "col_h": 3.5}},
        # the coolant-level road's inner railing has stretches torn out: cut the corner there and
        # you drop into the coolant pool (where it stands, it stops a thrown kart up to 3.5 m, and
        # so do the waste's fences: you only swim by running off). The tunnels meet the room's roads at its doorways
        # (reactor_room), so waste, corridor and office build no portals of their own
        "reactor": {"kind": "bridge", "road": g("tnnl_flr4"), "road_rep": 4.0, "skirt": g("metal_wall04"), "room": True,
                    "barrier": {"kind": "fence", "mat": g("{grate2"), "h": 1.2, "rep": 2.0, "sides": "outside",
                                "broken": [70.0, 18.0], "col_h": 3.5},
                    "pit": True, "pillar": g("metal_wall04"),
                    "pillar_floor": POOL_Y, "pillar_every": 26.0, "pillar_size": 1.6,
                    # fall off and you land in the coolant (reactor_room's pool disc)
                    "liquid": {"kind": "water", "y": POOL_Y + 2.0},
                    # the catwalk's noses: a jersey barrier on the gore (no floor past a deck's nose)
                    # under a red warning lamp
                    "cushion": {"model": "props_c17/concrete_barrier001a", "at": "gore", "light": [1.0, 0.3, 0.15]}},
        # the high walk: railings both sides (and an unseen wall over them up to 3.5 m: a kart thrown
        # up by a blast or a bump stays on the walk, 30 m over the pool), its columns stand in the
        # pool clear of the roads below (reactor_room)
        "highwalk": {"kind": "bridge", "road": g("tnnl_flr4"), "road_rep": 4.0, "skirt": g("metal_wall04"), "room": True,
                     "barrier": {"kind": "fence", "mat": g("{grate2"), "h": 1.2, "rep": 2.0, "col_h": 3.5},
                     "pit": False, "pillar_every": 1e9, "liquid": {"kind": "water", "y": POOL_Y + 2.0}},
        # the crane gantry in the storage hall: a deck on legs to the floor with a handrail on its
        # wall side only (drop off its open side and you land on the hall road), over the slime
        # pit's level should a kart come down where the floor is not
        "gantry": {"kind": "bridge", "road": g("drkmtlt_flr01"), "road_rep": 3.0, "skirt": g("drkmtlt_wall07"), "skirt_h": 1.0,
                   "barrier": {"kind": "fence", "mat": g("{grate2"), "h": 1.1, "rep": 2.0, "sides": "right"},
                   "pit": True, "pillar": g("drkmtlt_wall07"), "pillar_floor": HALL_Y - 6.0, "pillar_every": 18.0,
                   "pillar_size": 0.8, "liquid": {"kind": "slime", "y": HALL_Y - 6.0}},
        # the coolant catwalk: a grated deck over the pool, broken in the middle, its handrail only on
        # the outside of the bend (cut the corner and you swim)
        "catwalk": {"kind": "bridge", "road": g("c2a4_flr6"), "road_rep": 3.0, "skirt": g("metal_wall04"), "skirt_h": 1.0,
                    "barrier": {"kind": "fence", "mat": g("{grate2"), "h": 1.1, "rep": 2.0, "sides": "outside",
                                "col_h": 2.5},
                    "pit": True, "pillar": g("metal_wall04"), "pillar_floor": POOL_Y, "pillar_every": 18.0,
                    "pillar_size": 1.0, "liquid": {"kind": "water", "y": POOL_Y + 2.0}},
        # its far side: a tall catch fence on the outside of the bend, so a kart that flew the
        # gap fast and straight comes down against it instead of in the pool
        "catwalk_land": {"kind": "bridge", "road": g("c2a4_flr6"), "road_rep": 3.0, "skirt": g("metal_wall04"),
                         "skirt_h": 1.0,
                         "barrier": {"kind": "fence", "mat": g("{grate2"), "h": 3.6, "rep": 2.0, "sides": "outside"},
                         "pit": True, "pillar": g("metal_wall04"), "pillar_floor": POOL_Y, "pillar_every": 18.0,
                         "pillar_size": 1.0, "liquid": {"kind": "water", "y": POOL_Y + 2.0}},
        "corridor": {"kind": "tunnel", "road": g("crete2_flr01"), "road_rep": 3.0, "height": 8.0, "wall": g("c2a4e_w1"),
                     "wall_rep": 3.0, "band": stripe, "band_h": 0.7, "band_rep": 1.0, "ceil": g("crete3_ceil01"),
                     "light": g("litepanel1", glow=True), "light_every": 10.0, "light_rows": [0.0], "light_w": 1.6,
                     "light_color": [0.95, 0.97, 1.0], "light_energy": 1.4, "wall_gap": 1.0, "portals": False},
    }
    # the coolant road's first stretch in from the waste's door, where karts come down off its jump:
    # railed both sides (its torn stretches begin past it)
    out["reactor_in"] = dict(out["reactor"], barrier={k: v for k, v in out["reactor"]["barrier"].items()
                                                       if k not in ("sides", "broken")})
    # the catwalk's last stretch, where it runs onto the coolant road: railed on the core's side
    # too (a kart that made the jump does not swim while it merges)
    out["catwalk_merge"] = dict(out["catwalk"], barrier={k: v for k, v in out["catwalk"]["barrier"].items()
                                                         if k != "sides"})
    for nm, (hall, vmax) in BENDS.items():
        out[nm] = dict(out[hall], vmax=vmax)
    # (the offices' S-bend has room beside the road: a kart bumped wide there stops short of the wall)
    out["office_s"]["wall_gap"] = 4.0
    return out


def _hall(t, i):
    """The hall sample i belongs to (a bend's own style counts as its hall's)."""
    return BENDS.get(t.style[i], (t.style[i],))[0]


def STARTLINE(m):
    return m.goldsrc("stripes1")


def _ring(mesh, mat, y0, y1, r, ang, rep=4.0):
    """Part of the room's cylinder wall over the angles ang (radians, ascending), facing in."""
    lo = np.stack([ROOM_C[0] + np.cos(ang) * r, np.full(len(ang), y0), ROOM_C[2] + np.sin(ang) * r], 1)
    hi = lo.copy()
    hi[:, 1] = y1
    nrm = np.stack([np.cos(ang), np.zeros(len(ang)), np.sin(ang)], 1)
    mesh.strip(mat, hi, lo, (y1 - y0) / rep, 0.0, ang * r / rep, -nrm, -nrm)


def _strip_facing(mesh, mat, a, b, v, nrm):
    """A quad strip between polylines a and b (u 0..1 from a to b, v along them) facing nrm."""
    k = min(int(np.argmax(np.linalg.norm(b - a, axis=1))), len(a) - 2)
    if np.dot(np.cross(b[k] - a[k], a[k + 1] - a[k]), nrm) < 0:
        a, b = b, a
    n = np.tile(nrm, (len(a), 1))
    mesh.strip(mat, a, b, 0.0, 1.0, v, n, n)


def _ring_hit(p, d):
    """Metres along d (flat) from p to the room's wall circle, the crossing nearest p."""
    w = np.array([p[0] - ROOM_C[0], p[2] - ROOM_C[2]])
    dd = np.array([d[0], d[2]])
    dd /= np.linalg.norm(dd)
    b = w @ dd
    disc = b * b - (w @ w - ROOM_R * ROOM_R)
    t = [-b - math.sqrt(max(disc, 0.0)), -b + math.sqrt(max(disc, 0.0))]
    return min(t, key=abs)


def _doors(t):
    """Where the lap's tunnels meet the reactor room (its styles say "room": the coolant loop, a
    walk across it): per doorway the sample j where the tunnel's walls end, the level direction
    into the room (the passage's roof meets the wall above the door, which is level too, even
    where the road still climbs or falls at the door), the walls' half-width and the roof height."""
    out = []
    for j in range(t.n):
        a, b = t.style[(j - 1) % t.n], t.style[j]
        room_a, room_b = t.styles[a].get("room", False), t.styles[b].get("room", False)
        if room_a == room_b or "tunnel" not in (t.styles[a]["kind"], t.styles[b]["kind"]):
            continue
        tun = a if room_b else b
        st = t.styles[tun]
        f = t.fwd[j] * (1.0 if room_b else -1.0)
        into = np.array([f[0], 0.0, f[2]]) / math.hypot(f[0], f[2])
        h = t.height[(j - 1) % t.n] if room_b else t.height[j]
        out.append((j, into, t.width[j] / 2 + st.get("wall_gap", 0.0), h, st))
    return out


def _doorway(ctx, j, into, w, h, st):
    """The passage from a tunnel's end to the room's wall: its walls (the tunnel's own), roof and
    floor carried on until they meet the circle (and a hand past it, under the wall's straight
    segments), so the doorway is cut exactly where the tunnel's walls arrive; they start a few
    centimetres inside the tunnel's end, so no hairline opens where the two meet. Returns its
    two edge angles."""
    t = ctx.trk
    m = ctx.meshes
    mat = st["wall"]
    rr = t.flat_right[j]
    c = t.pos[j]
    hw = t.width[j] / 2
    # across the passage: the walls, the road's edges (the bridge deck runs on through) and between
    lat = np.unique(np.concatenate([np.linspace(-w, w, 17), [-hw, hw]]))
    near = np.array([c + rr * q - into * 0.03 for q in lat])
    far = np.array([p + into * (max(_ring_hit(p, into), 0.0) + 0.1) for p in near])
    nl = len(lat)
    lip = 0.6
    _strip_facing(m["ceil"], st["ceil"], near + UP * h, far + UP * h, lat / 4.0, -UP)
    for sl, e, sgn in ((slice(0, int(np.searchsorted(lat, -hw)) + 1), int(np.searchsorted(lat, -hw)), 1.0),
                       (slice(int(np.searchsorted(lat, hw)), nl), int(np.searchsorted(lat, hw)), -1.0)):
        if sl.stop - sl.start > 1:
            # the floor beside the deck, with a lip down its front edge into the room and one down
            # its edge along the deck (seen through the railing's grate: under the floor is nothing)
            fl = st.get("side_floor", st["road"])
            _strip_facing(m["road"], fl, near[sl] - UP * 0.01, far[sl] - UP * 0.01, lat[sl] / 4.0, UP)
            _strip_facing(m["walls"], fl, far[sl] - UP * 0.01, far[sl] - UP * lip, lat[sl] / 4.0, into)
            quad = [near[e] - UP * 0.01, far[e] - UP * 0.01, far[e] - UP * lip, near[e] - UP * lip]
            face(m["walls"], fl, quad, rr * sgn, plane_uv(quad, near[e], into, 4.0))
    ang = []
    for e, sgn in ((0, -1.0), (-1, 1.0)):
        p = near[e]
        edge = p + into * _ring_hit(p, into)
        q = edge + into * 0.1
        # the walls reach down past the floor beside them, as deep as its lip
        quad = [p - UP * lip, q - UP * lip, q + UP * h, p + UP * h]
        inward = -rr * sgn
        if np.linalg.norm(q - p) > 0.11:
            face(m["walls"], mat, quad, inward, plane_uv(quad, p, into, 4.0))
            face(m["walls"], mat, quad, -inward, plane_uv(quad, p, into, 4.0))
        ang.append(math.atan2(edge[2] - ROOM_C[2], edge[0] - ROOM_C[0]))
    return ang


def _disc(mesh, mat, y, r_in, r_out, up, segs=64, rep=6.0):
    ang = np.linspace(0, 2 * math.pi, segs + 1)
    a = np.stack([ROOM_C[0] + np.cos(ang) * r_in, np.full(segs + 1, y), ROOM_C[2] + np.sin(ang) * r_in], 1)
    b = np.stack([ROOM_C[0] + np.cos(ang) * r_out, np.full(segs + 1, y), ROOM_C[2] + np.sin(ang) * r_out], 1)
    n = np.tile(UP if up else -UP, (segs + 1, 1))
    u = ang * (r_in + r_out) * 0.5 / rep
    if up:
        mesh.strip(mat, b, a, r_out / rep, r_in / rep, u, n, n)
    else:
        mesh.strip(mat, a, b, r_in / rep, r_out / rep, u, n, n)


def _walk_columns(ctx, every=26.0, size=1.6):
    """The high walk's columns: pairs under its deck down into the pool, every `every` metres
    between its doors, each left out where a road below (the coolant loop, the catwalk) passes
    under it."""
    t = ctx.trk
    mat = ctx.mats.goldsrc("metal_wall04")
    r = ctx.roads
    for ids in t.runs(lambda i: t.style[i] == "highwalk"):
        st = t.styles["highwalk"]
        top = t.pos[ids, 1] - st.get("skirt_h", 1.6) + 0.05
        k0 = int(round(every / 2 / t.step))
        for k in range(k0, len(ids) - k0, int(round(every / t.step))):
            i = ids[k]
            for off in (-0.6, 0.6):
                q = t.pos[i] + t.flat_right[i] * off * t.width[i] / 2
                d = np.hypot(r.pos[:, 0] - q[0], r.pos[:, 2] - q[2]) - r.width / 2
                if ((d < size / 2 + 1.5) & (r.pos[:, 1] < top[k] - 2.0)).any():
                    continue
                h = top[k] - (POOL_Y - 1.0)
                ctx.box(mat, [q[0], POOL_Y - 1.0 + h / 2, q[2]], [size, h, size], ctx.yaw_facing(t.fwd[i]))


def reactor_room(ctx):
    g = ctx.mats.goldsrc
    m = ctx.meshes
    wall = g("babtech7")
    # doorways where the tunnels arrive, carried on to the wall and cut to fit them
    tau = 2 * math.pi
    doors = []
    for j, into, w, h, st in _doors(ctx.trk):
        a0, a1 = _doorway(ctx, j, into, w, h, st)
        a0 %= tau
        doors.append((a0, a0 + (a1 - a0 + math.pi) % tau - math.pi, ctx.trk.pos[j][1], h))
    doors = [(min(a, b), max(a, b), y, h) for a, b, y, h in doors]
    # the circle starts in the middle of the widest stretch of wall, so no doorway straddles it
    edges = sorted((a % tau, b % tau) for a, b, _, _ in doors)
    gaps = [((edges[k][1], edges[(k + 1) % len(edges)][0] + (tau if k + 1 == len(edges) else 0.0)))
            for k in range(len(edges))]
    seam = (sum(max(gaps, key=lambda q: q[1] - q[0])) / 2) if gaps else 0.0
    doors = [(seam + (a - seam) % tau, seam + (a - seam) % tau + b - a, y, h) for a, b, y, h in doors]
    for k, (a0, a1, _, _) in enumerate(doors):
        if any(a0 < b1 and b0 < a1 for b0, b1, _, _ in doors[k + 1:]):
            raise ValueError("black_mesa: two doorways of the reactor room overlap round its wall")
    # every piece of the wall on one grid of angles (every 3 degrees plus the door edges), so the
    # lower arcs, the door fills and the ring above share their vertices; the ring starts above
    # the highest door (a walk across the room comes in well above the spiral's doors)
    top = max([7.0] + [y + h for _, _, y, h in doors])
    grid = np.unique(np.concatenate([seam + np.linspace(0.0, tau, 121)] + [[a, b] for a, b, _, _ in doors]))
    in_door = np.zeros(len(grid) - 1, bool)
    for a0, a1, y, h in doors:
        in_door |= (grid[:-1] >= a0 - 1e-9) & (grid[1:] <= a1 + 1e-9)
        sub = grid[(grid >= a0 - 1e-9) & (grid <= a1 + 1e-9)]
        # under the doorway the wall stops a hand below its floor (the road climbs or falls a little
        # between the door's sample and the wall; the passage's lip and the deck's skirt hide the rest)
        _ring(m["walls"], wall, POOL_Y, y - 0.15, ROOM_R, sub)
        if y + h < top:
            _ring(m["walls"], wall, y + h, top, ROOM_R, sub)
    k = 0
    while k < len(in_door):
        if in_door[k]:
            k += 1
            continue
        e = k
        while e < len(in_door) and not in_door[e]:
            e += 1
        _ring(m["walls"], wall, POOL_Y, top, ROOM_R, grid[k:e + 1])
        k = e
    _ring(m["walls"], wall, top - 0.1, ROOF_Y + 0.1, ROOM_R, grid)
    # coolant pool, roof, the core and its glowing bands; the discs reach just past the wall
    r_out = ROOM_R / math.cos(math.pi / 120) + 0.05
    _disc(m["glow"], g("!waterblue", glow=True), POOL_Y + 2.0, 0.0, r_out, True, segs=120)
    _disc(m["ceil"], g("drkmtlt_ceil01"), ROOF_Y, 0.0, r_out, False, segs=120)
    core = g("~light5a")
    ctx.cylinder(g("c3a2_ceil"), [ROOM_C[0], POOL_Y, ROOM_C[2]], 14.0, ROOF_Y - POOL_Y, segs=40)
    for y in np.arange(POOL_Y + 4.0, ROOF_Y - 2.0, 6.0):
        ctx.cylinder(core, [ROOM_C[0], y, ROOM_C[2]], 14.15, 1.2, segs=40, kind="glow")
    ctx.light([ROOM_C[0], -8.0, ROOM_C[2]], [0.5, 0.75, 1.0], 120.0, 4.5)
    ctx.light([ROOM_C[0], 10.0, ROOM_C[2]], [0.5, 0.75, 1.0], 100.0, 3.0)
    # work lights over the room's roads: the coolant loop and the high walk
    t = ctx.trk
    for nms, up in ((LOOP_STYLES, 8.0), (("highwalk",), 7.0)):
        for ids in t.runs(lambda i, s_=nms: t.style[i] in s_):
            for i in ids[4:-3:15]:
                ctx.light(t.pos[i] + UP * up, [0.85, 0.9, 1.0], 34.0, 1.8)
    _walk_columns(ctx)
    # coolant tanks standing in the pool north of the core, clear of every road and column
    for x, z, model in ((124.0, 92.0, "props_wasteland/coolingtank01"), (101.0, 100.0, "props_wasteland/coolingtank01"),
                    (138.0, 112.0, "props_wasteland/horizontalcoolingtank04"), (70.0, 196.0, "props_wasteland/coolingtank01"),
                    (150.0, 196.0, "props_wasteland/coolingtank01")):
        ctx.add(model, [x, POOL_Y, z], ctx.yaw_facing([x - ROOM_C[0], 0.0, z - ROOM_C[2]]), ground=False)
    # LAMBDA signs on the core
    for k, sign in enumerate(["c3a2sign01", "c3a2sign00", "c3a2sign18", "c3a2sign00"]):
        a = k * math.pi / 2 + 0.3
        d = np.array([math.cos(a), 0, math.sin(a)])
        c = ROOM_C + d * 14.3 + UP * -4.0
        side = np.cross(UP, d)
        w, h = (12.0, 4.5) if k % 2 == 0 else (5.0, 5.0)
        quad = [c - side * w / 2 - UP * h / 2, c + side * w / 2 - UP * h / 2, c + side * w / 2 + UP * h / 2,
                c - side * w / 2 + UP * h / 2]
        tri = [0, 1, 2, 0, 2, 3]
        if np.dot(np.cross(quad[1] - quad[0], quad[2] - quad[0]), d) < 0:
            tri = [0, 2, 1, 0, 3, 2]
        m["deco"].add(g(sign), quad, [d] * 4, [[0, 1], [1, 1], [1, 0], [0, 0]], tri)


def decorate(ctx):
    t = ctx.trk
    g = ctx.mats.goldsrc
    rng = ctx.rng
    reactor_room(ctx)
    runs = {}
    for i in range(t.n):
        runs.setdefault(_hall(t, i), []).append(i)
    # signs along the walls
    signs = {
        "lobby": ["c1a0_wdsign", "signc1a1_1", "c1a1_sign1", "c1a1a_sign1"],
        "office": ["c1a3_sign2", "sign40", "c1a1a_sign1"],
        "lab": ["c1a0_wdsign", "c1a1_sign1", "sign83"],
        "tram": ["trrm_sign1", "trrm_sign2", "c2a2a_sign1"],
        "storage": ["c1a3_sign2", "c2a5_sign2", "c3a1_sign1"],
        "waste": ["c2a2a_sign1", "sign83"],
        "corridor": ["c3a2sign01", "c3a2sign29", "sign40"],
    }
    signed = []
    for style, names in signs.items():
        ids = runs.get(style, [])
        for k, i in enumerate(ids[20::45]):
            sgn = 1 if k % 2 else -1
            nm = names[k % len(names)]
            ctx.wall_sign(i, sgn, g(nm), 5.0, 2.6 if "sign1" in nm or "wdsign" in nm else 2.0, 3.2)
            signed.append((i, sgn))
    # doors along the office, lab and corridor walls, clear of the signs
    doors = {"office": (["c1a0b_dr3b", "c1a0b_dr4b", "babtech_dr1e"], 9),
             "lab": (["c1a0b_dr1a", "c1a0b_dr2a"], 11),
             "corridor": (["c1a0b_dr4b", "babtech_dr1e"], 14)}
    for style, (names, every) in doors.items():
        for k, i in enumerate(runs.get(style, [])[3::every]):
            sgn = -1 if k % 2 else 1
            if not any(abs(i - j) < 4 and sg == sgn for j, sg in signed):
                ctx.wall_sign(i, sgn, g(names[k % len(names)]), 1.4, 2.45, 1.25, inset=0.03)
    # lobby: security desk, columns, vending machines, a scientist waiting (a spectator: he
    # watches the race and reacts). The columns are pilasters on the walls, 0.6 m deep (no slot
    # behind one for a kart to wedge into, no face square across the floor to stop one dead);
    # neither they nor the furniture stand where the walls and the road run in toward the
    # corridors (a kart pushed along the slanting wall climbed a vending machine)
    lob = runs.get("lobby", [])
    cols = lob[6::14]
    for i in cols:
        if _level(t, i, 2):
            for sgn in (-1, 1):
                q = ctx.side(i, sgn, t.wall_gap[i] - 0.28)
                ctx.box(g("fifties_w12"), q + UP * 6.0, [0.6, 12.0, 1.6], ctx.yaw_facing(t.fwd[i]))
                # (the spectators along the walls keep out of it)
                ctx.reserved.append((np.array([q, q]), 1.1))
    if lob:
        i = lob[len(lob) // 3]
        ctx.against_wall(i, 1, "props_lab/securitybank", ground=False)
        ctx.against_wall(i, -1, "props_interiors/vendingmachinesoda01a", ground=False)
        level = [i for i in lob if _level(t, i, 3)]
        for k, m in enumerate(["props_wasteland/controlroom_desk001a", "props_trainstation/trashcan_indoor001a",
                               "props_interiors/vendingmachinesoda01a", "props_trainstation/trashcan_indoor001a"]):
            ctx.against_wall(level[(len(level) // 3 + 9 + 7 * k) % len(level)], 1 if k % 2 else -1, m, ground=False)
        # (between the second column and where the third would stand)
        i = lob[(lob.index(cols[1]) + lob.index(cols[2])) // 2]
        q = ctx.side(i, -1, 2.0)
        ctx.crowd_add(ctx.crowd_group(i, -1, "post", "scientist"), q, ctx.yaw_facing(t.flat_right[i]), "scientist",
                      on="geom", margin=0.4)
    def bent(i, limit, reach=4):
        """The road bends harder than `limit` (1/m) within `reach` samples of i: furniture there
        stands where karts run wide or cut the corner."""
        return np.abs(t.curv[[t.wrap(i + d) for d in range(-reach, reach + 1)]]).max() > limit

    # offices: desks, lockers, file cabinets, shelves and boxes against the walls (a 2 m floor
    # beside the road), a coffee corner with a fridge; none in the tight S-bend
    off = runs.get("office", [])
    office_props = ["props_interiors/furniture_desk01a", "props_c17/lockers001a", "props_lab/filecabinet02",
                    "props_c17/furnitureshelf001a", "props_wasteland/controlroom_filecabinet001a",
                    "props_junk/cardboard_box001a", "props_lab/lockers", "props_c17/furniturefridge001a",
                    "hl1/filecabinet", "props_trainstation/trashcan_indoor001a", "props_c17/shelfunit01a",
                    "props_interiors/furniture_desk01a"]
    for k, i in enumerate(off[5::5]):
        if not bent(i, 0.025):
            ctx.against_wall(i, 1 if k % 2 else -1, office_props[(k // 2) % len(office_props)], ground=False)
    # labs: workspaces, servers, the test chamber crystal on its holder; none in the bend at the
    # lab's end, nor where its walls run in to the tram tunnel's
    lab = runs.get("lab", [])
    lab_props = ["props_lab/workspace001", "props_lab/servers", "props_lab/workspace003", "props_lab/generatorconsole",
                 "props_lab/hev_machine", "props_lab/reciever_cart", "props_lab/workspace002", "props_lab/hev_case",
                 "props_lab/servers", "props_lab/lockers"]
    # (the left wall's middle stays clear: Lamarr hops there and Kleiner and Eli watch)
    bay = set(lab[len(lab) // 2 - 10:len(lab) // 2 + 11])
    for k, i in enumerate(lab[4::6]):
        if not (k % 2 == 0 and i in bay) and not bent(i, 0.018) and i not in lab[-15:]:
            ctx.against_wall(i, 1 if k % 2 else -1, lab_props[(k // 2) % len(lab_props)], ground=False)
    if lab:
        i = lab[len(lab) // 2]
        q = ctx.side(i, 1, 1.6)
        bars = "props_lab/crystalholder_bars"
        if ctx.add(bars, q, 0.0, ground=False):
            # the crystal model shares the holder's origin
            ctx.add("props_lab/crystalholder_crystal", q - UP * ctx.models[bars]["aabb_min"][1], 0.0, ground=False,
                    base=False, solid=False)
            ctx.light(q + UP * 2.0, [1.0, 0.85, 0.4], 18.0, 2.0)
    # tram tunnel: two rails on the floor
    tram = runs.get("tram", [])
    if tram:
        for off in (-1.2, 1.2):
            for a, b in _segments(tram):
                pts = t.pos[a:b] + t.flat_right[a:b] * off + UP * 0.03
                L = pts - t.flat_right[a:b] * 0.12
                R = pts + t.flat_right[a:b] * 0.12
                ctx.meshes["decal"].strip(g("metal_bord03"), L, R, 0, 1, t.s[a:b] / 2.0, t.up[a:b], t.up[a:b])
    # storage hall: the forklifts and the loader parked along the walls, crate stacks against the
    # walls wherever they leave room. Nothing stands out on the floor with a pocket behind it:
    # a kart that runs wide has the open floor and gets back on the road. The north floor under
    # the crane gantry stays bare (a kart that drops off it lands on open floor), and nothing
    # stands where the walls run out from the tram's hairpin
    sto = runs.get("storage", [])
    gantry = _gantry_floor(ctx)
    for k, i in enumerate(sto[10::30]):
        sgn = 1 if k % 2 else -1
        if not (sgn > 0 and i in gantry) and _level(t, i, 3):
            ctx.against_wall(i, sgn, "hl1/forklift" if k % 2 else "hl1/loader", ground=False)
    # a few shipping containers and shelving racks along the south wall first, crates in between
    for k, i in enumerate(sto[22::28]):
        if _level(t, i, 3):
            ctx.against_wall(i, -1, ["props_wasteland/cargo_container01", "props_c17/shelfunit01a"][k % 2],
                             ground=False)
    crates = ["props_junk/wood_crate001a", "props_junk/wood_crate002a"]
    for k, i in enumerate(sto[3::6]):
        for sgn in (-1, 1):
            if (sgn > 0 and i in gantry) or not _level(t, i, 3):
                continue
            y, inset = t.pos[i][1], rng.uniform(0.0, 0.3)
            for lvl in range(int(rng.integers(1, 4))):
                m = crates[(k + lvl) % 2]
                if ctx.against_wall(i, sgn, m, y=y, inset=inset, ground=False) is None:
                    break
                y += ctx.model_size(m)[1]
    _spill(ctx, sto)
    _channel_guides(ctx)
    # waste processing: tanks and pipes against the walls, standing in the toxic channels (the
    # tank is cut down to fit under the roof)
    wst = runs.get("waste", [])
    pit = t.styles["waste"]["pit"]["depth"]
    for k, i in enumerate(wst[4::14]):
        model, sc = [("props_wasteland/coolingtank02", 0.85), ("props_wasteland/pipecluster001a", 1.0),
                     ("props_lab/pipesystem02a", 1.0)][k % 3]
        ctx.against_wall(i, 1 if k % 2 else -1, model, scale=sc, y=t.pos[i][1] - pit - 0.3, ground=False)
    # drums dumped in the channels, half under the slime
    for k, i in enumerate(wst[9::11]):
        q = ctx.side(i, -1 if k % 2 else 1, t.wall_gap[i] * rng.uniform(0.3, 0.7))
        ctx.add(["props_c17/oildrum001", "props_borealis/bluebarrel001"][k % 2], q - UP * (pit + 0.5),
                float(rng.uniform(0, 6.28)), ground=False)
    # corridors: sentry guns watching from the right-hand floor (a metre wide: nobody stands on it),
    # lockers across the road from each
    cor = runs.get("corridor", [])
    for i in cor[33::50]:
        ctx.add("hl1/sentry", ctx.side(i, 1, 0.5), ctx.yaw_facing(-t.flat_right[i]), ground=False)
        ctx.against_wall(cor[(cor.index(i) + 6) % len(cor)], -1, "props_c17/lockers001a", ground=False)


def decorate_branch(ctx, spec):
    """The branches' own dressing: hazard stripes along the rail-less decks' edges (where you
    fall), work lamps over them, and on the catwalk stripes across its broken ends."""
    t = ctx.trk
    g = ctx.mats.goldsrc
    stripe = g("stripes1")
    deck = ~t.gap & ~t.junction
    for run in ctx.runs_of(list(np.flatnonzero(deck))):
        ids = np.array(run)
        if len(ids) < 2:
            continue
        for sgn in (-1, 1):
            e0 = t.pos[ids] + t.right[ids] * (sgn * (t.width[ids] / 2 - 0.05))[:, None] + t.up[ids] * 0.02
            e1 = t.pos[ids] + t.right[ids] * (sgn * (t.width[ids] / 2 - 0.45))[:, None] + t.up[ids] * 0.02
            L, R = (e1, e0) if sgn > 0 else (e0, e1)
            ctx.meshes["decal"].strip(stripe, L, R, 0.0, 0.25, t.s[ids] / 2.0, t.up[ids], t.up[ids])
    for i in range(int(round(12.0 / t.step)), t.n - 4, int(round(26.0 / t.step))):
        ctx.light(t.pos[i] + UP * 3.5, [1.0, 0.9, 0.7], 18.0, 1.4)
    for a, b in t.gaps:
        for j, f in ((a - 1, -1.0), (min(b, t.n - 1), 1.0)):
            if t.hidden[j]:
                continue  # (the gantry's far side is the hall road it drops back onto)
            # a stripe across the deck a metre short of where it broke off, a red lamp over it
            c = t.pos[j] + t.fwd[j] * f * 0.6 + t.up[j] * 0.02
            hw = t.width[j] / 2 - 0.05
            L = np.array([c - t.right[j] * hw - t.fwd[j] * 0.4, c - t.right[j] * hw + t.fwd[j] * 0.4])
            R = L + t.right[j] * 2 * hw
            ctx.meshes["decal"].strip(stripe, L, R, 0.0, hw / 2.0, np.array([0.0, 0.25]), t.up[[j, j]], t.up[[j, j]])
            ctx.light(c + UP * 2.0, [1.0, 0.25, 0.15], 10.0, 1.5)


def _gantry_floor(ctx):
    """Storage samples whose north floor the crane gantry runs over (and 12 m beyond its ends)."""
    t = ctx.trk
    out = set()
    for b in ctx.roads.trks[1:]:
        if "gantry" not in b.style:
            continue
        P = b.pos[:, [0, 2]]
        for i in range(t.n):
            if t.style[i] == "storage":
                q = ctx.side(i, 1, t.wall_gap[i] / 2)
                if np.hypot(P[:, 0] - q[0], P[:, 1] - q[2]).min() < 12.0:
                    out.add(i)
    return out


def _spill(ctx, sto, s0=40.0, s1=120.0, clear=5.0):
    """Toxic sludge spilt over the storage floor from s0 to s1 metres past its slime pit, wall to
    wall but for a strip `clear` metres wide along the south wall: a raised sheet in the verge
    mesh, so karts that wade through it run at offroad speed (the gantry above stays clean)."""
    t = ctx.trk
    g = ctx.mats.goldsrc
    pit = [b for a, b in t.gaps if t.style[a] == "storage"]
    if not pit or not sto:
        return
    k0, k1 = int(round(s0 / t.step)), int(round(s1 / t.step))
    ids = np.array([t.wrap(pit[0] + k) for k in range(k0, k1 + 1)])
    u = np.linspace(0.0, 1.0, len(ids))
    # the spill's ends run out in a curve, its south edge wanders
    end = np.sqrt(np.clip(np.sin(np.pi * u), 0.0, 1.0))
    wall = t.width[ids] / 2 + t.wall_gap[ids] - 0.3
    north = wall
    south = -wall + clear + np.sin(u * 9.0) * 0.8
    mid = (north + south) / 2
    half = (north - south) / 2 * end
    A = t.pos[ids] + t.flat_right[ids] * (mid - half)[:, None] + UP * 0.03
    B = t.pos[ids] + t.flat_right[ids] * (mid + half)[:, None] + UP * 0.03
    A[:, 1] = B[:, 1] = t.pos[ids, 1] + 0.03
    up = np.tile(UP, (len(ids), 1))
    ctx.meshes["verge"].strip(g("toxicgrn", glow=True), A, B, (mid - half) / 4.0, (mid + half) / 4.0, t.s[ids] / 4.0,
                              up, up)


def _channel_guides(ctx, run=42.0):
    """The waste's channel railings carried back across the storage hall's side floors: from each
    wall `run` metres before the channels, slanting in (about 16 degrees) to where the railing
    starts at the road's edge. The floors used to end at a low fence across them over the slime: a
    kart that ran along one nosed into that pocket, or climbed the fence (its top is at the height
    of a kart's underside) into the channel or along the railing's top; now it is led back onto the
    road. Unseen walls over them, facing the road, as on the channel railings."""
    t = ctx.trk
    bar = t.styles["waste"]["barrier"]
    j = next(i for i in range(t.n) if t.style[i] == "waste" and t.style[i - 1] == "storage")
    ids = np.arange(j - int(round(run / t.step)), j + 1)
    u = (t.s[ids] - t.s[ids[0]]) / (t.s[j] - t.s[ids[0]])
    hw = t.width[ids] / 2
    wall = hw[0] + t.wall_gap[ids[0]] + 0.05
    # a few centimetres into the wall at the start, clear of the road on the way, on its edge at the end
    lat = np.maximum(wall + (hw[-1] - wall) * u, hw + 0.3)
    lat[-1] = hw[-1]
    for sgn in (-1, 1):
        base = t.pos[ids] + t.flat_right[ids] * (sgn * lat)[:, None] - UP * 0.01
        d = np.diff(base, axis=0)
        d = np.vstack([d[:1], (d[:-1] + d[1:]) / 2, d[-1:]])
        d[:, 1] = 0.0
        d /= np.linalg.norm(d, axis=1)[:, None]
        # outward, away from the road: the railing's back, its unseen wall faces the other way
        rf = np.stack([-d[:, 2], np.zeros(len(d)), d[:, 0]], 1) * sgn
        v = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(base, axis=0), axis=1))])
        _barrier(ctx.meshes, bar, base, rf, v, sgn)
        # (spectators keep off it)
        ctx.reserved.append((base, 1.0))


def _level(t, i, k):
    """The walls and the road keep their width within k samples of i: not where they run in or out
    where styles meet (furniture against a slanting wall leaves a wedge a kart climbs)."""
    near = [t.wrap(i + d) for d in range(-k, k + 1)]
    return np.ptp(t.wall_gap[near]) < 0.01 and np.ptp(t.width[near]) < 0.01


def _segments(ids):
    """Split a list of indices into contiguous (a, b) slices."""
    out = []
    a = ids[0]
    prev = a
    for i in ids[1:]:
        if i != prev + 1:
            out.append((a, prev + 1))
            a = i
        prev = i
    out.append((a, prev + 1))
    return out


# ---------------------------------------------------------------- spectators (tools/crowds.py)
# Indoors there is no terrain: everyone stands on geometry (on="geom"): the halls' side floors
# against the walls, crate stacks in the storage hall and the gallery round the reactor room
START = (-50.0, 40.0)  # the lobby crowd either side of the line (lap metres)
GALLERY_Y = 2.0  # the reactor gallery's floor
# degrees round the room's wall between its doorways (the high walk's at about -107 and +106,
# the waste's at -59, the corridor's at -121); the north arc looks down on the coolant catwalk
GALLERY_ARCS = ((-98.0, -70.0), (-44.0, 94.0), (118.0, 226.0))
# closer to the roads that cross the room: the core's service ledge on the high walk's side
# (degrees round the core, 180 = west) a hand over the walk, and pump platforms PUMP_W metres
# square in the pool outside the coolant road (fractions of its run; none under the high walk)
CORE_LEDGE = (148.0, 212.0)
CORE_LEDGE_Y = WALK_Y + 0.6
PUMPS = (0.12, 0.4, 0.7, 0.9)
PUMP_W = 5.0
STAFF = ("scientist", "scientist", "scientist", "guard")


def _wall_spot(ctx, i, sgn, inset=0.55):
    """On a hall's side floor against its wall at sample i, where the walls stand there (they run in
    and out where styles meet), or None where that floor is under 2.5 m wide or a pit."""
    t = ctx.trk
    st = ctx.style_of(i)
    if st["kind"] != "tunnel" or st.get("pit") or t.gap[i] or t.wall_gap[i] < 2.5:
        return None
    lat = t.wall_gap[i] - inset + ctx.crowd_rng.uniform(-0.25, 0.1)
    return ctx.side_point(i, sgn, lat, y=t.pos[i][1], jitter=0.4)


def _halls(ctx, ids=None):
    """Hall samples with a side floor people can stand on."""
    t = ctx.trk
    ids = range(t.n) if ids is None else ids
    return [i for i in ids if not t.gap[i] and _wall_spot(ctx, i, 1) is not None]


def _in(ctx, i, w):
    L = ctx.trk.length
    rel = (ctx.s_of(i) + L / 2) % L - L / 2
    return w[0] <= rel <= w[1]


def stands(ctx):
    _gallery(ctx)
    _core_ledge(ctx)
    _pumps(ctx)


def _arc(a0, a1, r, y, c=ROOM_C):
    ang = np.radians(np.linspace(a0, a1, max(8, int((a1 - a0) / 2.5))))
    return np.stack([c[0] + np.cos(ang) * r, np.full(len(ang), y), c[2] + np.sin(ang) * r], 1), ang


def _ledge(ctx, c, wall, edge, a0, a1, y):
    """A 0.4 m thick ledge round the centre c over the angles a0..a1 (degrees), from radius `wall`
    (against what it hangs on) out to its open edge at radius `edge`, railed there and edged with
    a glowing band, so it reads from the roads below."""
    g = ctx.mats.goldsrc
    floor, rail, band = g("c1a0_labflrb"), g("{grate2"), g("~light5a")
    front, ang = _arc(a0, a1, edge, y, c)
    back, _ = _arc(a0, a1, wall, y, c)
    v = ang * max(wall, edge) / 4.0
    out = np.stack([np.cos(ang), np.zeros(len(ang)), np.sin(ang)], 1) * math.copysign(1.0, edge - wall)
    ctx.flat_strip(floor, front, back, v)
    ctx.flat_strip(floor, back - [0, 0.4, 0], front - [0, 0.4, 0], v, down=True)
    ctx.vert_strip(floor, front - [0, 0.4, 0], front, v, out)
    ctx.vert_strip(band, front + out * 0.03 - [0, 0.34, 0], front + out * 0.03 - [0, 0.06, 0], v, out, kind="glow")
    ctx.vert_strip(rail, front + [0, 0.02, 0], front + [0, 1.1, 0], v, out, kind="deco")
    ctx.vert_strip(rail, front + [0, 1.1, 0], front + [0, 0.02, 0], v, -out, kind="deco")
    for k, sgn in ((0, -1.0), (-1, 1.0)):
        tang = np.array([-math.sin(ang[k]), 0.0, math.cos(ang[k])]) * sgn
        ctx.cap_quad(floor, front[k] - [0, 0.4, 0], back[k] - [0, 0.4, 0], back[k], front[k], tang)


def _gallery(ctx):
    """A 3 m ledge on the reactor room's wall with a railing, in arcs between the doorways, lit from
    above and edged with a glowing band, so it reads from the roads below."""
    for a0, a1 in GALLERY_ARCS:
        _ledge(ctx, ROOM_C, ROOM_R - 0.05, ROOM_R - 3.0, a0, a1, GALLERY_Y)
        for a in np.radians(np.arange(a0 + 6.0, a1 - 3.0, 15.0)):
            r = ROOM_R - 2.0
            ctx.light([ROOM_C[0] + math.cos(a) * r, GALLERY_Y + 4.5, ROOM_C[2] + math.sin(a) * r], [1.0, 0.95, 0.85],
                      22.0, 2.6)
    ctx.gallery = list(GALLERY_ARCS)


def _core_ledge(ctx):
    """The core's service ledge on the high walk's side, a hand over the walk's deck and 2-4 m off
    its railing, lit: people watch the walk from close by (and the core's discharges)."""
    _ledge(ctx, ROOM_C, CORE_R + 0.02, CORE_R + 2.3, *CORE_LEDGE, CORE_LEDGE_Y)
    for a in np.radians(np.linspace(*CORE_LEDGE, 4)[1:-1]):
        r = CORE_R + 1.5
        ctx.light([ROOM_C[0] + math.cos(a) * r, CORE_LEDGE_Y + 3.5, ROOM_C[2] + math.sin(a) * r], [1.0, 0.95, 0.85],
                  12.0, 2.0)


def _pumps(ctx):
    """Pump platforms standing in the pool outside the coolant road (PUMPS: fractions of its run),
    their tops a hand over its deck and 4.5 m off its edge, railed and lit: a few people watch
    from each (ctx.pumps: (top centre, sample, side))."""
    t = ctx.trk
    g = ctx.mats.goldsrc
    mat, rail = g("metal_wall04"), g("{grate2")
    loop = [i for i in range(t.n) if t.style[i] in LOOP_STYLES]
    ctx.pumps = []
    for f in PUMPS:
        i = loop[int(round(f * (len(loop) - 1)))]
        sgn = 1 if t.flat_right[i] @ (t.pos[i] - ROOM_C) > 0 else -1
        c = ctx.side(i, sgn, 4.5 + PUMP_W / 2)
        c[1] = t.pos[i][1] + 0.6
        yaw = ctx.yaw_facing(t.fwd[i])
        ctx.box(mat, [c[0], (c[1] + POOL_Y - 1.0) / 2, c[2]], [PUMP_W, c[1] - POOL_Y + 1.0, PUMP_W], yaw)
        cy, sy = math.cos(yaw), math.sin(yaw)
        ax, az = np.array([cy, 0.0, -sy]) * PUMP_W / 2, np.array([sy, 0.0, cy]) * PUMP_W / 2
        corners = [c - ax - az, c + ax - az, c + ax + az, c - ax + az]
        for k in range(4):
            a, b = corners[k], corners[(k + 1) % 4]
            n = (a + b) / 2 - c
            n /= np.linalg.norm(n)
            lo, v = np.array([a, b]) + UP * 0.02, np.array([0.0, PUMP_W / 2.0])
            ctx.vert_strip(rail, lo, lo + UP * 1.08, v, [n, n], kind="deco")
            ctx.vert_strip(rail, lo + UP * 1.08, lo, v, [-n, -n], kind="deco")
        ctx.light(c + UP * 4.0, [1.0, 0.9, 0.75], 14.0, 2.0)
        ctx.pumps.append((c, i, sgn))


def _gallery_people(ctx, gid, a0, a1, n, roles, mood="polite", face=None, c=ROOM_C, r=(ROOM_R - 2.5, ROOM_R - 1.2),
                    y=GALLERY_Y):
    """Up to n people along a ledge's arc (degrees round c, radii r, at height y) looking at `face`
    (default: the coolant road on the far side of the core)."""
    rng = ctx.crowd_rng
    face = np.array([ROOM_C[0], -14.0, ROOM_C[2]]) if face is None else face
    for k in range(n):
        a = math.radians(rng.uniform(a0 + 3, a1 - 3))
        rr = rng.uniform(*r)
        q = np.array([c[0] + math.cos(a) * rr, y, c[2] + math.sin(a) * rr])
        role = roles[k % len(roles)] if isinstance(roles, tuple) else roles
        ctx.crowd_add(gid, q, face, role, mood, margin=0.4, on="geom", lod=[0, 1, 2][k % 3])


def crowds(ctx):
    t = ctx.trk
    rng = ctx.crowd_rng
    halls = _halls(ctx)
    # under the crane gantry nobody stands on the hall's north floor (karts drop off onto it)
    north = _gantry_floor(ctx)
    # the HECU squad's stretch of the storage hall, 140-165 m past its slime pit, and 30 m either
    # side of it where nobody else calls out (their "Freeman!" must not come just after another line)
    pit = [ctx.s_of(b) for a, b in t.gaps if t.style[a] == "storage"]
    squad = [(i, (ctx.s_of(i) - pit[0]) % t.length) for i in range(t.n)] if pit else []
    quiet = {i for i, d in squad if 110.0 <= d <= 195.0}
    # the lobby either side of the line: scientists and a guard now and then against both walls
    for sgn in (-1, 1):
        ids = [i for i in halls if _in(ctx, i, START)]
        if ids:
            gid = ctx.crowd_group(ids[len(ids) // 2], sgn, "line", "scientist", tags=["start"])
            for role, every, chance in (("guard", 12.0, 1.0), ("scientist", 1.3, 0.85)):
                ctx.crowd_line(gid, ids, sgn, every, lambda i, s_: _wall_spot(ctx, i, s_), role, mood="fan",
                               chance=chance, margin=0.4, on="geom", lod=(lambda k: 0) if role == "guard" else None)
    # the other halls: a few people every so often, more in the big storage hall (none round the
    # tight bends, where karts run wide over the floor)
    rest = [i for i in halls if not _in(ctx, i, START) and i not in quiet and abs(t.curv[i]) < 0.02
            and t.style[i] not in BENDS]
    for run in ctx.runs_of(rest):
        gap = ctx.style_of(run[0]).get("wall_gap", 0.0)
        for ch in ctx.chunks(run, int(60 / t.step), int(30 / t.step)):
            for sgn in (-1, 1):
                ch_s = [i for i in ch if not (sgn > 0 and i in north)]
                if len(ch_s) < 2:
                    continue
                gid = ctx.crowd_group(ch_s[len(ch_s) // 2], sgn, "line", "scientist")
                every, chance = (2.5, 0.6) if gap >= 6.0 else (4.0, 0.6)
                for role in STAFF[:2] if gap < 6.0 else STAFF:
                    ctx.crowd_line(gid, ch_s, sgn, every * 2.0, lambda i, s_: _wall_spot(ctx, i, s_), role,
                                   chance=chance, margin=0.4, on="geom")
    # the HECU squad that set up the hall's turrets, by the south wall past the second one
    ids = [i for i, d in squad
           if 140.0 <= d <= 165.0 and t.style[i] == "storage" and _wall_spot(ctx, i, -1) is not None]
    if ids:
        gid = ctx.crowd_group(ids[len(ids) // 2], -1, "post", "hecu", tags=["turrets"])
        ctx.crowd_line(gid, ids, -1, 2.5, lambda i, s_: _wall_spot(ctx, i, s_, 1.2), "hecu", mood="military",
                       margin=0.4, on="geom", lod=lambda k: k % 2)
    # crate stacks in the halls: someone up on the top crate here and there
    gid = None
    for p in list(ctx.props):
        if p["model"] in ("props_junk/wood_crate001a", "props_junk/wood_crate002a") and rng.random() < 0.3:
            q = np.array(p["pos"], float)
            if ctx._nearest(q) in quiet:
                continue
            if gid is None:
                gid = ctx.crowd_group(ctx._nearest(q), 0, "post", "scientist", tags=["crates"])
            ctx.on_top(p, 1, "scientist" if rng.random() < 0.7 else "guard", gid=gid)
    # the lab: a cameo pair (Kleiner and Eli worked here)
    lab = [i for i in halls if _hall(t, i) == "lab"]
    if lab:
        i = lab[len(lab) // 2 + 4]
        gid = ctx.crowd_group(i, -1, "post", "cameo", tags=["lab"], bed="")
        for model, off in (("kleiner", -0.7), ("eli", 0.7)):
            q = _wall_spot(ctx, i, -1)
            if q is not None:
                ctx.crowd_add(gid, q + t.fwd[i] * off, t.pos[i] + [0, 1.0, 0], "cameo", "fan", model=model,
                              margin=0.4, on="geom", lod=0)
    # the reactor gallery: scientists and guards looking down at the coolant road round the core,
    # and at the east arc's north end the alien slaves that came through with the cascade, chanting
    loop = [i for i in range(t.n) if t.style[i] in LOOP_STYLES]
    if getattr(ctx, "gallery", None) and loop:
        watch = [ctx.s_of(loop[0]), ctx.s_of(loop[-1])]
        for a0, a1 in ctx.gallery[1:]:
            gid = ctx.crowd_group(loop[len(loop) // 2], 0, "gallery", "scientist", tags=["gallery"], watch=watch, bed="")
            _gallery_people(ctx, gid, a0 + (14.0 if a0 < 0 else 0.0), a1, 28 if a0 < 0 else 24,
                            ("scientist",) * 6 + ("guard",))
        # (the slaves watch the east straight below them, from the waste's door)
        a0 = ctx.gallery[1][0]
        gid = ctx.crowd_group(loop[0], 0, "gallery", "islave", tags=["gallery"],
                              watch=[ctx.s_of(loop[0]) - 10.0, ctx.s_of(loop[0]) + 70.0], bed="")
        _gallery_people(ctx, gid, a0, a0 + 12.0, 5, "islave", mood="chant")
    # close by the roads: scientists on the core's ledge watching the high walk go past, a crew
    # on each pump platform outside the coolant road
    walk = [i for i in range(t.n) if t.style[i] == "highwalk" and abs(t.pos[i][2] - ROOM_C[2]) < 30.0]
    if walk:
        gid = ctx.crowd_group(walk[len(walk) // 2], 0, "gallery", "scientist", tags=["core"],
                              watch=[ctx.s_of(walk[0]) - 20.0, ctx.s_of(walk[-1])], bed="")
        _gallery_people(ctx, gid, *CORE_LEDGE, 10, ("scientist",) * 4 + ("guard",), mood="excited",
                        face=np.array([WALK_X, WALK_Y + 1.0, ROOM_C[2]]), r=(CORE_R + 0.5, CORE_R + 1.8),
                        y=CORE_LEDGE_Y)
    for c, i, sgn in getattr(ctx, "pumps", []):
        gid = ctx.crowd_group(i, sgn, "post", "scientist", tags=["pump"])
        for k, (a, b) in enumerate(((-1.3, -1.0), (0.9, -1.1), (-0.4, 1.0), (1.5, 0.9))):
            q = c + t.fwd[i] * (a + rng.uniform(-0.3, 0.3)) + t.flat_right[i] * sgn * (b + rng.uniform(-0.3, 0.3))
            ctx.crowd_add(gid, q, t.pos[i] + UP, STAFF[k], "excited", margin=0.4, on="geom", lod=k % 3)
    eggs(ctx)


def crowds_branch(bctx, spec):
    """Onlookers for the coolant catwalk: the gallery's north arc right above its broken span
    watches the jump (their group counts the catwalk's metres)."""
    if spec["id"] != "coolant_jump" or not getattr(bctx, "gallery", None):
        return
    t = bctx.trk
    a, b = t.gaps[0] if t.gaps else (t.n // 2, t.n // 2 + 1)
    gid = bctx.crowd_group(a, 0, "gallery", "scientist", tags=["gallery", "jump"],
                           watch=[float(t.s[a]) - 30.0, float(t.s[min(b, t.n - 1)]) + 20.0], bed="")
    a0, a1 = bctx.gallery[0]
    _gallery_people(bctx, gid, a0, a1, 14, ("scientist", "scientist", "guard"), mood="excited",
                    face=t.pos[(a + b) // 2] - UP * 2.0)


def eggs(ctx):
    t = ctx.trk
    # the Hazard Course hologram by each slime jump: on the storage hall's south floor just past its
    # pit (seen all the way in from the tram), over the waste's toxic channel before its kicker
    for a, b in t.gaps:
        st = t.styles[t.style[a]]
        if st.get("pit"):
            i = t.wrap(a - int(round(26.0 / t.step)))
            q = ctx.side_point(i, -1, st["wall_gap"] * 0.5, y=t.pos[i][1] - st["pit"]["depth"] + 0.3)
        else:
            i = t.wrap(b + int(round(8.0 / t.step)))
            q = _wall_spot(ctx, i, -1, 1.5)
        if q is not None:
            ctx.egg("holo", pos=q, yaw=math.atan2(*(t.pos[t.wrap(i - 10)] - q)[[0, 2]]),
                    gap=[ctx.s_of(a), ctx.s_of(b % t.n)])
    # Lamarr hops along the lab's side floor
    lab = [i for i in _halls(ctx) if _hall(t, i) == "lab"]
    if len(lab) > 20:
        mid = len(lab) // 2
        path = [ctx.side_point(i, -1, t.wall_gap[i] * 0.4, y=t.pos[i][1]) for i in lab[mid - 9:mid + 2:2]]
        ctx.egg("lamarr", path=path)
    # two HL1 zombies wading in the waste's toxic channels (the scientists scream when they notice)
    slime = [i for i in range(t.n) if isinstance(ctx.style_of(i).get("pit"), dict) and not t.gap[i]]
    done = False
    for run in ctx.runs_of(slime):
        st = ctx.style_of(run[0])
        y = -st["pit"]["depth"] + 0.05
        for k in range(len(run) // 3, len(run) - 4, 2):
            for sgn in (1, -1):
                lat = st["wall_gap"] * 0.5
                a = ctx.side_point(run[k], sgn, lat, y=t.pos[run[k]][1] + y)
                b = ctx.side_point(run[k + 3], sgn, lat, y=t.pos[run[k + 3]][1] + y)
                if not any(ctx.in_prop(p, 0.6) for p in (a, (a + b) / 2, b)):
                    done = ctx.egg("zombies", path=[a, b], count=2, model="hl1/zombie")
                if done:
                    break
            if done:
                break
        if done:
            break
    # the G-Man (HL1) at the far end of the long straight of the corridor back to the lobby, seen
    # down it (from 60 m off at most, so he is more than a few pixels tall)
    cor = [i for i in range(t.n) if _hall(t, i) == "corridor" and abs(t.curv[i]) < 0.004]
    runs = sorted(ctx.runs_of(cor), key=len)
    if runs:
        run = runs[-1]
        i = run[-4]
        q = ctx.side_point(i, 1, t.wall_gap[i] - 0.35, y=t.pos[i][1])
        ctx.egg("gman", pos=q, yaw=math.atan2(*(t.pos[run[0]] - q)[[0, 2]]), s=ctx.s_of(i), model="hl1/gman",
                window=[max(ctx.s_of(run[0]) - 10.0, ctx.s_of(i) - 60.0), ctx.s_of(i) - 15.0], chance=0.4)
    _gnome_on_crate(ctx)


def _gnome_on_crate(ctx, near=None, within=1e9):
    """Gnome Chompski on top of the highest crate of a stack nobody stands on (near `near`)."""
    t = ctx.trk
    for k, p in enumerate(ctx.props):
        if p["model"] not in ("props_junk/wood_crate001a", "props_junk/wood_crate002a"):
            continue
        q = np.array(p["pos"], float)
        if near is not None and np.linalg.norm(q - near) > within:
            continue
        q[1] += ctx.models[p["model"]]["aabb_max"][1] * float(p.get("scale", 1.0))
        # another crate on this one: it is not the top of its stack
        if ctx.in_prop(q + [0.0, 0.1, 0.0], 0.0, ignore=k) or ctx._taken_at(q, 1.5):
            continue
        if ctx.egg("gnome", pos=q, yaw=math.atan2(*(t.pos[ctx._nearest(q)] - q)[[0, 2]])):
            return True
    return False
