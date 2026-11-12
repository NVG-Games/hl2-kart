"""CT17: Combine-held City 17, a figure-8 of about 2.5 km.

The station plaza under the Breencasts, down into a cutting under the old-town flyover, the
underpass below the railway embankment, the Combine pipe over the canal, the rail yard with its
jump and a level crossing, the canal corner over a bridge, the Combine checkpoint, the old-town
switchbacks and up over the flyover to the boulevard toward the Citadel, back to the plaza.

Two branches: a jump straight over the canal instead of the canal corner (it takes speed: short
of the far bank you swim) and the rooftops of the old town instead of its switchbacks, a ramp up
onto the roofs and a jump over the middle street (it takes a boost; short of it you land in the
street). A train crosses the yard, floor turrets guard the checkpoint and a strider watches the
canal corner; the city turns out to watch the race.
"""
import math

import numpy as np

from crowds import FAR_MODEL
from track_gen import UP, _side_w, _treatment, carve, face, noise2, smoothstep

# (x, y, z, width, style, flags): the start first. The west lobe runs clockwise seen from above
# (the plaza, the cutting under the flyover, the underpass), the east lobe counter-clockwise (the
# pipe, the rail yard, the canal corner, the checkpoint, the old town, the flyover)
CTRL = [
    (0, 0, 0, 24, "plaza"), (105, 0, 0, 24, "plaza"), (170, -1.0, 10, 20, "avenue"),
    (222, -4.0, 26, 18, "cut", {"height": 4.6}), (268, -5.0, 38, 18, "cut", {"height": 4.6}),
    (318, -5.5, 50, 18, "underpass"), (362, -5.0, 60, 17, "pipe"), (440, -6.0, 76, 17, "pipe"),
    (506, -3.0, 74, 18, "yard"), (540, -1.0, 62, 20, "yard"), (562, 0, 34, 20, "yard"),
    # (a long kicker: a kart coming at it fast is not thrown high off it)
    (570, 0, 4, 21, "yard", {"gap": True, "gap_span": (0.025, 0.17), "ramp_lift": 1.4, "ramp_len": 24}),
    (584, 0, -82, 20, "yard"),
    (601, 0, -140, 18, "avenue"),
    # north over the canal on its bridge, round the corner and back west along the canal's far side
    (619, 0, -170, 18, "avenue"), (630, 0.4, -198, 16, "canalbridge"), (635, 0.4, -258, 18, "avenue"),
    (625, 0, -296, 18, "avenue"), (591, 0, -309, 17, "approach"),
    # the checkpoint climbs onto the old town's hill
    (480, 0, -300, 18, "checkpoint"), (420, 0, -300, 18, "checkpoint"),
    # the old town: west along the hill, a U-turn east down into the middle street, a wider U-turn
    # west (the switchbacks, each hairpin one steady arc), then round south to the flyover. The
    # rooftops climb off the hill road (5.5 m to the roofs) and jump the middle street 9 m below
    (330, 3.5, -298, 15, "old"), (272, 3.5, -298, 15, "old"),
    (236, 3.5, -298, 15, "switchback"), (219, 2.92, -293.4, 15, "switchback"), (206.6, 2.33, -281, 15, "switchback"),
    (202, 1.75, -264, 15, "switchback"), (206.6, 1.17, -247, 15, "switchback"), (219, 0.58, -234.6, 15, "switchback"),
    (236, 0, -230, 15, "switchback"),
    (252, 0, -230, 15, "switchback"), (272, 0, -224.6, 15, "switchback"), (286.6, 0, -210, 15, "switchback"),
    (292, 0, -190, 15, "switchback"), (286.6, 0, -170, 15, "switchback"), (272, 0, -155.4, 15, "switchback"),
    (252, 0, -150, 15, "switchback"),
    (200, 0, -150, 15, "old"), (139.9, 0, -150, 15, "old"),
    (123.8, 0.2, -145.3, 17, "switchback"), (112.7, 0.5, -132.7, 18, "switchback"), (110.2, 0.9, -116.1, 18, "switchback"),
    (116.9, 1.5, -100.7, 18, "switchback"), (146, 2.5, -66, 18, "avenue"),
    # over the plaza road's cutting
    (206, 5.0, -26, 18, "flyover"), (248, 7.0, 32, 18, "flyover"),
    # the boulevard toward the Citadel and back round to the plaza
    (252, 3.5, 92, 18, "avenue"), (220, 1.0, 136, 20, "avenue"), (150, 1.0, 158, 20, "avenue"),
    (74, 0.5, 156, 20, "avenue"), (4, 1.5, 128, 20, "avenue"), (-52, 0, 86, 20, "avenue"),
    (-88, 0, 40, 22, "plaza"), (-78, 0, 6, 24, "plaza"), (-40, 0, 0, 24, "plaza"),
]
CTRL = [c if len(c) > 5 else c + ({},) for c in CTRL]

# the canal's centre line: from the north-east under the corner's bridge, south-west between the
# corner's two legs, under the Combine pipe and away south
CANAL = [(760.0, -262.0), (601.0, -228.0), (552.0, -216.0), (512.0, -200.0), (484.0, -164.0), (470.0, -110.0),
         (400.0, 68.0), (430.0, 420.0)]
CANAL_HALF = 11.0
WATER = -11.0
FOOTBRIDGE = 1.6  # the footbridges' scale: they span the canal's 36 m from bank top to bank top

TRACK = {
    "id": "ct17",
    "name": "CT17",
    "ctrl": CTRL,
    # five crate rows in the 400 m before the rooftops' decision (a bot needs a boost in hand there)
    "items": [0.0443, 0.1194, 0.1794, 0.2767, 0.3209, 0.3731, 0.3945, 0.4206, 0.6361, 0.6993, 0.8198, 0.9099],
    # (none in the pipe's roll, on the run to the yard's jump or in the old town, whose hairpins and
    # exit bend a boosted kart runs wide in: the first is out on the boulevard)
    "boosts": [0.0292, 0.0798, 0.3802, 0.4585, 0.7209, 0.7802, 0.8696, 0.9494],
    "barrels": [0.1391],
    "vmax": 38.0,
    "offtrack": 40.0,
    "sky": "sky_day01_01",
    "water": {"level": WATER},
    "background": "city17",
    "citadel": [-950, -200, 240, 9.0],
    "gantry": "combine",
    "env": {"fog_begin": 260.0, "fog_end": 2600.0},
    # the jumps' launch speeds under the game's own gravity (project.godot)
    "gravity": 15.24,
}

# the checkpoint stretch starts at this lap metre and the yard jump lands at this one (the hazards
# are placed from them, as on the old layout)
CHECKPOINT_S = 1083.0
YARD_LANDING_S = 632.0
TRACK["hazards"] = [
    # Combine floor turrets on the checkpoint's pavements, between the barricades, facing the oncoming karts
    {"type": "turret", "s": CHECKPOINT_S + 35, "side": -1, "setback": 1.6,
     "zone": [CHECKPOINT_S - 8, CHECKPOINT_S + 40], "model": "combine_turrets/floor_turret", "fallback": "hl1/sentry",
     "scale": 1.4},
    {"type": "turret", "s": CHECKPOINT_S + 91, "side": 1, "setback": 1.6,
     "zone": [CHECKPOINT_S + 48, CHECKPOINT_S + 96], "model": "combine_turrets/floor_turret", "fallback": "hl1/sentry",
     "scale": 1.4},
    {"type": "turret", "s": CHECKPOINT_S + 147, "side": -1, "setback": 1.6,
     "zone": [CHECKPOINT_S + 104, CHECKPOINT_S + 152], "model": "combine_turrets/floor_turret",
     "fallback": "hl1/sentry", "scale": 1.4},
    # a Combine train crosses the rail yard between the jump's landing and the yard's crates
    {"type": "train", "s": YARD_LANDING_S + 46, "angle": 90, "reach": 90,
     "cars": ["props_combine/combinetrain01a", "props_combine/combine_train02a", "props_combine/combine_train02b"],
     "car_axis": ["-x", "z", "z"], "speed": 28, "period": 26, "first": 50, "warn": 4.5},
    # a strider on the canal bank beside the bridge fires its warp cannon at the bridge and the corner
    {"type": "strider", "s": 850, "side": 1, "setback": 28, "zone": [818, 942], "scale": 1.15},
]

BRANCHES = [
    # straight over the canal instead of round the corner: speed-gated, short of the far bank you swim
    {"id": "canal_jump", "name": "Canal jump", "kind": "jump", "fork": (585, -92), "merge": (510, -300),
     "ctrl": [(580, 0, -122, 12, "service"), (571, 0, -150, 12, "service"), (569, 0.3, -182, 11, "ramp"),
              (569, 0.5, -204, 11, "ramp", {"gap": True, "gap_span": (0.03, 0.66), "ramp_lift": 2.8, "ramp_len": 18}),
              (566, 0, -248, 12, "avenue"), (561, 0, -264, 12, "avenue"), (549, 0, -282, 12, "avenue"),
              (531, 0, -294, 12, "avenue")],
     "items": [0.32, 0.72], "risk": 0.55, "ai": {"take": 0.65, "min_skill": 0.85}, "respawn": "before",
     "retry_back": 60.0},
    # up onto the old town's roofs instead of its switchbacks and over the middle street: a boost
    # carries a kart over it, short of the far roof it lands in the street (a safe drop). A bot
    # holding a boost goes for it (take well over 1 against the risk's discount). The ramp climbs
    # off the hill road to the roofs before the level corner at its top; the far roof sweeps round
    # in one long descending curve (a kart that flies far lands in it and slides along its outer
    # parapet) down beside the south street's wall and merges into it. A kart that falls off goes
    # back to the main road (a retry would need the boost it has spent)
    {"id": "rooftops", "name": "Rooftops", "kind": "ledge", "fork": (320, -298), "merge": (156, -150),
     "ctrl": [(303, 3.68, -290, 10, "rooframp"), (288, 3.8, -284.1, 10, "rooframp"), (277, 6.1, -281.5, 10, "rooframp"),
              (266, 8.7, -280.5, 11, "roof"), (253.5, 9.0, -277.2, 12, "roof"), (244.4, 9.0, -268, 12, "roof"),
              (241.5, 9.0, -256, 10, "roof", {"gap": True, "gap_span": (0.3, 0.9), "ramp_lift": 1.8, "ramp_len": 20}),
              (244, 9.0, -214.35, 10, "landing"), (237.8, 7.8, -191.35, 10, "landing"), (221, 5.6, -174.5, 10, "rooframp"),
              (198, 3.0, -168.35, 9, "rooframp"), (175, 0.1, -162.5, 8, "rooframp")],
     "items": [0.70], "risk": 0.5, "ai": {"take": 1.7, "min_skill": 0.8, "commit": 20.0}, "respawn": "main"},
]


def styles(m):
    curb = m.hl2("concrete/concretefloor019a")
    road = m.hl2("concrete/concretefloor037a")
    concrete = m.hl2("concrete/concretewall008a")
    # every barrier stops a kart thrown up off its road up to 3 m (an unseen wall over it, "col_h"):
    # a blast or a hop off a kerb no longer carries one over a jersey onto another level or behind
    # a wall
    jersey = {"kind": "jersey", "mat": m.hl2("concrete/concretewall064a"), "col_h": 3.0}
    avenue = {"kind": "street", "road": road, "road_u": "full", "curb": curb, "walk": 4.5,
              "walk_mat": m.hl2("concrete/concretefloor028c_c17"), "barrier": jersey, "skirt": concrete}
    old = {"kind": "street", "road": m.hl2("stone/cobble08a"), "road_rep": 3.0, "curb": curb, "walk": 3.0,
           "walk_mat": m.hl2("concrete/concretefloor028c"),
           "barrier": {"kind": "wall", "mat": m.hl2("stone/stonewall029b"), "h": 2.0, "rep": 3.0, "col_h": 3.0},
           "cushion": {"model": "props_c17/concrete_barrier001a", "tyres": True, "sink": 1.6}}
    # the roofs: tar on top of a brick block whose walls (with windows) go down to the ground, a
    # brick parapet round them (and an unseen wall over it: a kart that lands wide off the jump
    # slides along it instead of over it)
    parapet = {"kind": "bridge", "road": m.hl2("props/rubberroof002a"), "road_rep": 5.0,
               "skirt": m.hl2("brick/brickwall031b"), "skirt_h": 9.5, "pillar_every": 1e9, "ground": "nat",
               "barrier": {"kind": "wall", "mat": m.hl2("brick/brickwall031b"), "h": 1.2, "thick": 0.45, "rep": 3.0,
                           "col_h": 3.5}, "gap_dip": False}
    return {
        # the plaza's cobbles are laid flat in plan (no stretch round its tight last corner)
        "plaza": {"kind": "street", "road": m.hl2("stone/stonefloor006d_c17"), "road_rep": 4.0, "curb": curb,
                  "walk": 7.0, "walk_mat": m.hl2("concrete/concretefloor028c_c17"), "uv": "plan",
                  "barrier": {"kind": "wall", "mat": m.hl2("stone/stonewall022a_c17"), "h": 0.9, "rep": 3.0,
                              "col_h": 2.5}},
        # the old town's walls stand 2 m: a kart thrown about by a blast stays in the street. Its
        # junctions are the rooftops' noses, where the ramp beside the street is 2.5 m up: the crash
        # cushion stands on the ground under the middle of the nose
        "old": old,
        # the switchbacks and the old town's exit bend (out to the boulevard): no pavement, the wall
        # stands at the kerb, so a kart that runs wide slides along it instead of climbing the kerb
        # and nosing into a wall across a pavement; the walls stop a kart up to 3.5 m (one a blast or
        # a rollermine throws about stays in the street, and the people behind them still look over
        # them). A computer driver takes the hairpins and the short streets between them at one
        # steady speed
        "switchback": dict(old, walk=0.6, barrier=dict(old["barrier"], col_h=3.5), vmax=21.0),
        "avenue": avenue,
        # the avenue's last 110 m before the checkpoint (past the canal jump's merge) has 2.4 m walls
        # instead of jerseys: a kart a blast throws onto a jersey there hops it and lands behind the
        # checkpoint's walls, with no way back to the road
        "approach": dict(avenue, barrier={"kind": "wall", "mat": concrete, "h": 2.4, "rep": 3.0, "col_h": 3.0}),
        # the checkpoint's Combine walls stand 5 m: karts a blast or a mine throws about there (the
        # crates and the turrets bunch them up) stay in it instead of landing in the yards behind
        "checkpoint": {"kind": "street", "road": road, "road_u": "full", "curb": curb, "walk": 3.5,
                       "walk_mat": m.hl2("concrete/concretefloor033k_c17"),
                       "barrier": {"kind": "wall", "mat": m.hl2("metal/citadel_metalwall072a"), "h": 5.0,
                                   "thick": 0.6, "rep": 4.0}},
        "yard": {"kind": "open", "road": m.hl2("concrete/concretefloor011a"), "road_rep": 5.0,
                 "verge": m.hl2("nature/dirtfloor003a"), "verge_w": 5.0,
                 "barrier": {"kind": "fence", "mat": m.hl2("metal/metalfence001a"), "h": 2.6, "off": 5.0,
                             "rep": 2.5}},
        "cut": {"kind": "trench", "road": road, "road_u": "full", "wall": concrete, "wall_rep": 4.0,
                "lip": 3.0, "lip_mat": m.hl2("concrete/concretefloor028c_c17")},
        "underpass": {"kind": "tunnel", "road": road, "road_u": "full", "height": 7.5, "wall": concrete,
                      "wall_rep": 4.0, "band": m.hl2("props/hazardstrip001a"), "band_h": 0.9, "band_rep": 1.8,
                      "ceil": m.hl2("concrete/concretefloor013a"), "light": m.hl2("lights/fluorescentcool001a"),
                      "light_every": 10.0, "light_rows": [-0.45, 0.45], "light_color": [0.85, 0.92, 1.0],
                      "light_energy": 1.6, "portal": concrete, "wall_gap": 0.6, "cover": 2.5, "lid_w": 8.0,
                      "lid_mat": m.hl2("nature/dirtfloor003a")},
        # the corner's bridge over the canal: stone parapets both sides, pillars down into the canal,
        # the street level left as it is under its ends (the canal cuts through)
        "canalbridge": {"kind": "bridge", "road": road, "road_u": "full", "skirt": concrete, "skirt_h": 1.4,
                        "barrier": {"kind": "wall", "mat": m.hl2("stone/stonewall022a_c17"), "h": 1.1, "thick": 0.45,
                                    "rep": 3.0, "col_h": 3.0},
                        "pillar": concrete, "pillar_every": 16.0, "pillar_size": 1.4, "ground": "keep"},
        # a Combine pipe through the city: the road climbs the wall nearly to the roof and comes back.
        # It lies in a cutting, on the ground ("rest"), and spans the canal. The lane is back at the
        # bottom 40 m before the exit ("settle"), so a kart still up the wall slides down inside
        "pipe": {"kind": "tube", "road": road, "road_u": "full", "road_rep": 6.0, "ground": "rest",
                 "wall": m.hl2("metal/citadel_metalwall072a"), "skin": m.hl2("metal/citadel_metalwall072a"),
                 "glow": m.hl2("lights/white001"), "radius": 11.0, "roll": 150.0, "profile": "wall", "settle": 18.0,
                 "ring_every": 12.0, "light_color": [0.55, 0.8, 1.0], "light_energy": 1.6},
        # the old-town flyover over the plaza road's cutting: jersey barriers, pillars down to the
        # ground beside the cutting (none in it)
        "flyover": {"kind": "bridge", "road": road, "road_u": "full", "skirt": concrete, "skirt_h": 1.8,
                    "barrier": jersey, "pillar": concrete, "pillar_every": 20.0, "pillar_size": 1.8, "ground": "keep"},
        # the canal jump's way out of the yard: a concrete track along the fence, a narrow dirt verge
        "service": {"kind": "open", "road": m.hl2("concrete/concretefloor011a"), "road_rep": 5.0,
                    "verge": m.hl2("nature/dirtfloor003a"), "verge_w": 0.8},
        # the canal jump's kicker: an avenue with hazard stripes for kerbs
        "ramp": {"kind": "street", "road": road, "road_u": "full", "curb": m.hl2("props/hazardstrip001a"), "walk": 4.5,
                 "walk_mat": m.hl2("concrete/concretefloor028c_c17"), "barrier": jersey, "skirt": concrete},
        # the ramps up onto the roofs and back down: a concrete deck with jersey barriers, closed
        # below by its walls down to the city's ground (no pillars, no embankment)
        "rooframp": {"kind": "bridge", "road": road, "road_u": "full", "skirt": concrete, "skirt_h": 9.5,
                     "barrier": jersey, "pillar_every": 1e9, "ground": "nat"},
        # the roofs (the jump over the middle street digs no pit: under it are the street and the
        # blocks' yards); the far roof the jump lands on stops a kart that flew long up to 5.5 m
        "parapet": parapet,
        # round the corner at the top and on to the jump a computer driver keeps to the middle (an
        # open edge's line, "pit"): it comes to the kicker straight, not across it from the corner's
        # exit, and leaves the lip heading for the far roof
        "roof": dict(parapet, pit=True),
        "landing": dict(parapet, barrier=dict(parapet["barrier"], col_h=5.5)),
    }


def _canal_dist(P):
    """Plan distance of points P (N, 2) from the canal's centre line."""
    best = np.full(len(P), 1e9)
    pts = np.asarray(CANAL, float)
    for a, b in zip(pts[:-1], pts[1:]):
        ab = b - a
        t = np.clip(((P - a) @ ab) / (ab @ ab), 0.0, 1.0)
        best = np.minimum(best, np.linalg.norm(P - (a + t[:, None] * ab), axis=1))
    return best


def _canal_along(u):
    """A point (x, z) u metres along the canal's centre line and the line's direction there."""
    pts = np.asarray(CANAL, float)
    for a, b in zip(pts[:-1], pts[1:]):
        seg = float(np.linalg.norm(b - a))
        if u <= seg:
            d = (b - a) / seg
            return a + d * u, d
        u -= seg
    return pts[-1], (pts[-1] - pts[-2]) / np.linalg.norm(pts[-1] - pts[-2])


def terrain(trk, m):
    layers = {"base": m.hl2("nature/grassfloor002a"), "dirt": m.hl2("nature/dirtfloor003a"),
              "rock": m.hl2("concrete/concretewall008a"), "pave": m.hl2("concrete/concretefloor028c_c17"),
              "sand": m.hl2("nature/blenddirtmud01")}

    def build(f, trk):
        P = f.P
        # the city is flat; hills rise beyond its edge
        far = smoothstep(260.0, 520.0, f.dist)
        nat = far * (25.0 + noise2(P[:, 0] / 160.0, P[:, 1] / 160.0, 4) * 70.0)
        cd = _canal_dist(P)
        canal = smoothstep(CANAL_HALF + 1.5, CANAL_HALF - 0.5, cd)
        nat = nat * (1 - canal) + (WATER - 3.0) * canal
        h = carve(f, nat, trk, flat=9.0, blend=24.0, gap_floor=WATER - 3.0)
        # the canal cuts through the shoulders too (it passes under the corner's bridge, the canal
        # jump and the pipe)
        h = np.where(canal > 0.5, np.minimum(h, WATER - 3.0), h)
        Hm = h.reshape(f.nz, f.nx)
        gz, gx = np.gradient(Hm, f.cell)
        slope = np.sqrt(gx ** 2 + gz ** 2).ravel()
        rock = smoothstep(0.6, 1.0, slope)
        yard = np.isin(f.style, ["yard"]) & (f.dist < f.half + 40)
        embank = (f.kind == "tunnel") & (f.dist < f.half + 30)
        dirt = np.clip(yard * 0.9 + embank * 0.8 + far, 0, 1)
        pave = np.clip(1.0 - far * 1.4, 0, 1) * (1 - dirt)
        sand = smoothstep(WATER + 0.5, WATER - 1.5, h)
        col = np.stack([dirt, rock, pave, sand], 1).astype(np.float32)
        return h, col

    return {"margin": 560.0, "cell": 4.0, "build": build, "layers": layers}


# (not row_res_2_ascend_fullscale: it steps up a slope, and on the city's level ground one end of
# it hangs 6-10 m in the air)
BUILDINGS = ["props_buildings/row_res_1_fullscale", "props_buildings/row_res_2_fullscale",
             "props_buildings/row_corner_1_fullscale", "props_buildings/building_002a",
             "props_buildings/row_church_fullscale"]
TOWERS = ["props_buildings/project_building01", "props_buildings/project_building02",
          "props_buildings/project_building03"]
WAGONS = ["props_trainstation/boxcar", "props_trainstation/train001", "props_trainstation/tanker",
          "props_trainstation/flatcar", "props_trainstation/boxcar2", "props_trainstation/train002"]


def _canal_clear(ctx, model, q, yaw):
    pts = np.array(ctx.footprint(model, q, yaw, 2.0))
    return bool((_canal_dist(pts) > CANAL_HALF + 4.0).all())


def _lamps(ctx):
    """Street lamps on the pavements of ctx's road, their arms over the road; none under another
    road's jump (the rooftops fly over the old town's middle street at lamp height), none where a
    junction left the pavement out or there is hardly any (the switchbacks) and none on the
    checkpoint's narrow pavements (its turrets and barricades stand there)."""
    t = ctx.trk
    r = ctx.roads
    fly = np.where(r.gap & (r.route != r.trks.index(t)))[0]
    for i in ctx.every(32.0):
        # (a street's end sample: its pavement starts or ends right under the lamp)
        if any(t.kind(t.wrap(i + d)) != "street" for d in (-1, 0, 1)) or t.gap[i] or t.style[i] == "checkpoint":
            continue
        st = t.styles[t.style[i]]
        if st.get("walk", 3.0) < 1.5:
            continue
        for sgn in (-1, 1):
            if t.side_off[i, (sgn + 1) // 2]:
                continue
            q = ctx.side(i, sgn, 0.3 + st.get("walk", 3.0) * 0.35)
            q[1] = t.pos[i][1] + 0.16
            under = np.hypot(r.pos[fly, 0] - q[0], r.pos[fly, 2] - q[2]) < r.width[fly] / 2 + 3.0
            if (under & (r.pos[fly, 1] < q[1] + 14.0)).any():
                continue
            ctx.add("props_c17/lamppost03a_on", q, ctx.yaw_facing(t.flat_right[i] * sgn), ground=False)


def _rails(ctx, P, width=2.8):
    """A siding's track (sleepers and rails) along the ground under the points P (k, 3)."""
    d = np.gradient(P, axis=0)
    d[:, 1] = 0.0
    d /= np.linalg.norm(d, axis=1, keepdims=True)
    side = np.cross(UP, d)
    P = P.copy()
    P[:, 1] = [ctx.ground(p[0], p[2]) + 0.06 for p in P]
    v = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(P, axis=0), axis=1))]) / width
    n = np.repeat(UP[None], len(P), 0)
    # (wound to face up, like its normals)
    ctx.meshes["decal"].strip(ctx.mats.hl2("wood/woodtrack001a"), P + side * width / 2, P - side * width / 2, 1.0, 0.0,
                              v, n, n)


def _yard(ctx):
    """The rail yard: sidings past the fences on both sides with wagons parked along them, clear of
    the train's level crossing (its corridor refuses them), a light tower and signals."""
    t = ctx.trk
    yard = [i for i in range(t.n) if t.style[i] == "yard" and not t.gap[i]]
    if not yard:
        return
    fence = t.styles["yard"]["barrier"]["off"]
    for sgn, dist in ((-1, 14.0), (1, 14.0), (1, 23.0)):
        # the sidings follow the yard road from the end of its bend to the avenue
        ids = [i for i in yard if abs(t.curv[i]) < 0.006]
        if len(ids) < 10:
            continue
        P = np.array([ctx.side(i, sgn, dist) for i in ids])
        _rails(ctx, P)
        for k, i in enumerate(ids[3::12]):
            m = WAGONS[(k + int(dist)) % len(WAGONS)]
            q = ctx.side(i, sgn, max(dist, fence + min(ctx.model_size(m)[[0, 2]]) / 2 + 1.0))
            yaw = ctx.yaw_along(m, t.fwd[i])
            g = ctx.site(m, q, yaw, tol=0.5)
            if g is not None:
                q[1] = g
                ctx.add(m, q, yaw)
    # the light tower: a mast with the lamp cluster on top, past the west siding
    i = yard[len(yard) // 3]
    q = ctx.side(i, -1, 30.0)
    q[1] = ctx.ground(q[0], q[2])
    if ctx.free(q + UP * 8.0, [2.0, 16.0, 2.0]):
        mast = 16.0
        ctx.cylinder(ctx.mats.hl2("metal/metalpipe010a"), q - UP * 0.5, 0.35, mast + 0.5, segs=10, rep=2.0)
        ctx.add("props_trainstation/lighttowercluster01", q + UP * mast, ctx.yaw_facing(t.flat_right[i]), solid=False)
        ctx.light(q + UP * (mast - 1.0), [1.0, 0.95, 0.85], 40.0, 1.6)
    for i in yard[8::40]:
        q = ctx.side(i, 1, 7.5)
        q[1] = ctx.ground(q[0], q[2])
        ctx.add("props_trainstation/light_signal001a", q, ctx.yaw_facing(-t.fwd[i]))


def _canal(ctx):
    """Footbridges over the canal and boats moored on it, away from the roads."""
    total = sum(float(np.linalg.norm(np.subtract(b, a))) for a, b in zip(CANAL[:-1], CANAL[1:]))
    for u in np.arange(60.0, total - 40.0, 150.0):
        c, d = _canal_along(u)
        if ctx.road_gap_to([c[0], 0.0, c[1]]) < 45.0:
            continue
        # across the canal (the model's long span is its x), its deck ends resting on both banks
        # past the canal's sloping sides (the model's bottom is its deck's); none where a bank is not
        # level with the other or dips into the canal
        span = ctx.model_size("props_canal/canal_bridge01")[0] * FOOTBRIDGE / 2 - 1.0
        ends = [ctx.ground(c[0] + d[1] * k, c[1] - d[0] * k) for k in (-span, span)]
        if min(ends) < -0.5 or abs(ends[0] - ends[1]) > 0.6:
            continue
        ctx.add("props_canal/canal_bridge01", [c[0], max(ends), c[1]], float(math.atan2(d[0], d[1])),
                scale=FOOTBRIDGE, ground=False, tag="bridge")
    for u in np.arange(130.0, total - 40.0, 150.0):
        c, d = _canal_along(u)
        q = np.array([c[0], WATER - 0.35, c[1]]) + np.array([-d[1], 0.0, d[0]]) * (CANAL_HALF - 3.0)
        if ctx.road_gap_to(q) < 30.0:
            continue
        ctx.add("props_canal/boat001a", q, float(math.atan2(d[0], d[1])) - math.pi / 2, ground=False, base=False)


def _roofs(ctx):
    """The roofscape beside the rooftops' road: chimney stacks rising from its walls against the
    parapet's outside, an aerial on some, none of them on the road."""
    t = ctx.trk
    brick = ctx.mats.hl2("brick/brickwall017a")
    roof = [k for k in range(t.n) if t.style[k] in ("parapet", "roof", "landing") and not t.gap[k]]
    for n, k in enumerate(roof[4::9]):
        sgn = 1 if n % 2 else -1
        q = ctx.side(k, sgn, 1.25)
        h = 2.6 + (n % 3) * 0.5
        top = t.pos[k][1] + h
        g = ctx.ground(q[0], q[2])
        ctx.box(brick, [q[0], (g - 0.5 + top) / 2, q[2]], [1.5, top - g + 0.5, 1.5], ctx.yaw_facing(t.fwd[k]))
        if n % 4 == 1:
            ctx.cylinder(ctx.mats.hl2("metal/metalpipe010a"), [q[0], top, q[2]], 0.06, 3.5, segs=6, kind="deco")


def _barrier_steps(ctx):
    """Where two street styles meet with their barriers at different distances from the road (a
    wider pavement on one side of the change), a stub of the taller barrier across the step at the
    change: no slot between the two barriers' ends for a kart on the pavement to slip out by."""
    t = ctx.trk
    for i in range(t.n):
        a, b = t.styles[t.style[t.wrap(i - 1)]], t.styles[t.style[i]]
        if a is b or a["kind"] != "street" or b["kind"] != "street" or t.gap[i] or t.cut[i]:
            continue
        if not a.get("barrier") or not b.get("barrier"):
            continue
        for sgn in (-1, 1):
            if t.side_off[i, (sgn + 1) // 2] or t.side_off[t.wrap(i - 1), (sgn + 1) // 2]:
                continue
            offs = [0.3 + _side_w(t, [i], sgn, st.get("walk", 4.0), _treatment(st) - st.get("walk", 4.0))[0]
                    for st in (a, b)]
            if abs(offs[0] - offs[1]) < 0.2:
                continue
            hs = [1.05 if st["barrier"].get("kind") == "jersey" else st["barrier"].get("h", 1.2) for st in (a, b)]
            bar, h = (a, b)[int(np.argmax(hs))]["barrier"], max(hs)
            lo, hi = min(offs), max(offs) + 0.4
            c = ctx.side(i, sgn, (lo + hi) / 2)
            y0 = t.pos[i][1] + 0.16
            ctx.box(bar["mat"], [c[0], y0 + (h - 0.3) / 2, c[2]], [hi - lo, h + 0.3, 0.4], ctx.yaw_facing(t.fwd[i]))


def _pipe_caps(ctx):
    """Where a tunnel runs into the Combine pipe (or out of it), the pipe's end ring stands open
    above the tunnel's roof: from outside you look into the pipe over the portal. A cap of the
    pipe's skin closes the ring above the roof, facing out of the pipe."""
    t = ctx.trk
    for ids in ctx.runs_of([i for i in range(t.n) if t.kind(i) == "tube"]):
        for end, nb, out in ((ids[0], t.wrap(ids[0] - 1), -1.0), (ids[-1], t.wrap(ids[-1] + 1), 1.0)):
            if t.kind(nb) != "tunnel":
                continue
            st = t.styles[t.style[end]]
            r = st["radius"] + 0.6
            up, right = t.base_up[end], t.base_right[end]
            c = t.base[end] + up * st["radius"] - t.fwd[end] * out * 0.05
            # the chord along the tunnel's roof, the arc over the top
            a = math.asin(np.clip((t.height[nb] - st["radius"]) / r, -1.0, 1.0))
            pts = [c + (right * math.cos(th) + up * math.sin(th)) * r for th in np.linspace(a, math.pi - a, 25)]
            face(ctx.meshes["walls"], st["skin"], pts, t.fwd[end] * out, [[p @ right / 4.0, p @ up / 4.0] for p in pts],
                 center=True)


def _prism(ctx, pts, base, top):
    """A block of flats over the plan outline pts ((k, 2), in order round it): brick walls with
    windows from base up to top and a tar roof. It collides like a wall, and the overlap registry
    holds it (one box per slice from each wall to the middle), so no later prop stands in it."""
    P = np.asarray(pts, float)
    c = P.mean(0)
    wall, roof = ctx.mats.hl2("brick/brickwall031b"), ctx.mats.hl2("props/rubberroof002a")
    h = (top - base) / 4.0
    u = 0.0
    for a, b in zip(P, np.roll(P, -1, axis=0)):
        e = b - a
        ln = float(np.hypot(*e))
        if ln < 0.05:
            continue
        nrm = np.array([e[1], 0.0, -e[0]]) / ln
        mid = (a + b) / 2
        if nrm[[0, 2]] @ (mid - c) < 0:
            nrm = -nrm
        q = [np.array([a[0], base, a[1]]), np.array([b[0], base, b[1]]), np.array([b[0], top, b[1]]),
             np.array([a[0], top, a[1]])]
        face(ctx.meshes["walls"], wall, q, nrm, [[u, h], [u + ln / 4, h], [u + ln / 4, 0], [u, 0]])
        u += ln / 4
        inward = c - mid
        depth = float(np.hypot(*inward))
        ctx.block([(mid[0] + c[0]) / 2, (base + top) / 2, (mid[1] + c[1]) / 2], [ln, top - base, depth * 0.9],
                  math.atan2(e[0], e[1]) - math.pi / 2)
    face(ctx.meshes["walls"], roof, [np.array([x, top, z]) for x, z in P], UP, [[x / 4, z / 4] for x, z in P],
         center=True)
    ctx.old_blocks.append(P)


def _old_town(ctx):
    """The old town's blocks filled in: a curved block of flats inside each switchback, behind the
    terrace there (no slot behind the wall for a kart to drop into), then row houses wherever a
    block still has room, facing the nearest street."""
    t = ctx.trk
    st = t.styles["old"]
    back = 0.3 + st["walk"] + 0.4 + 1.1
    old = np.array([s in ("old", "switchback") for s in t.style])
    bend = old & (np.abs(t.curv) > 1.0 / 45.0)
    for run in ctx.runs_of([i for i in range(t.n) if bend[i]]):
        if len(run) < 10:
            continue
        run = run[2:-2]
        sgn = -1 if np.mean(t.curv[run]) < 0 else 1
        arc = [t.pos[i] + t.flat_right[i] * sgn * (t.width[i] / 2 + back) for i in run]
        pts = np.array([p[[0, 2]] for p in arc])
        # (a gentle bend's arc and its chord make a thin slab, not a block of flats: none there)
        px, pz = pts[:, 0], pts[:, 1]
        if abs(px @ np.roll(pz, -1) - pz @ np.roll(px, -1)) / 2 < 150.0:
            continue
        g = min(ctx.ground(x, z) for x, z in pts)
        _prism(ctx, pts, g - 0.5, t.pos[run[0]][1] + 13.0)
    ids = [i for i in range(t.n) if old[i]]
    lo = t.pos[ids][:, [0, 2]].min(0) - 30.0
    hi = t.pos[ids][:, [0, 2]].max(0) + 30.0
    spots = []
    for x in np.arange(lo[0], hi[0], 6.0):
        for z in np.arange(lo[1], hi[1], 6.0):
            gap = ctx.road_gap_to([x, 0.0, z])
            if 5.0 < gap < 40.0:
                spots.append((gap, x, z))
    for gap, x, z in sorted(spots):
        q = np.array([x, 0.0, z])
        i = int(np.argmin(((ctx.roads.pos[:, [0, 2]] - q[[0, 2]]) ** 2).sum(1)))
        yaw = round(ctx.yaw_facing(ctx.roads.pos[i] - q) / (math.pi / 2)) * math.pi / 2
        for m in ("props_buildings/row_res_2_fullscale", "props_buildings/row_res_1_fullscale"):
            if not ctx.fits(m, q, yaw, 4.0) or not _canal_clear(ctx, m, q, yaw):
                continue
            g = ctx.site(m, q, yaw, tol=1.0)
            if g is None:
                continue
            q[1] = g
            if ctx.add(m, q, yaw, tag="building", ground=False):
                break


def decorate_branch(ctx, spec):
    """A branch's dressing (ctx dresses its road): building rows and lamps along its avenues, the
    roofscape along the rooftops."""
    for sgn in (-1, 1):
        ctx.row_along({"avenue", "ramp"}, BUILDINGS[2:] + BUILDINGS[:2], sgn, 4.5 + 2.4, gap=1.0, accept=_canal_clear)
    _lamps(ctx)
    if spec["id"] == "rooftops":
        _roofs(ctx)


def decorate(ctx):
    t = ctx.trk
    rng = ctx.rng
    L = t.length
    # building rows behind the pavements, clear of the canal (rows first: the grid fills round them)
    for sgn in (-1, 1):
        ctx.row_along({"plaza"}, BUILDINGS, sgn, 7.0 + 2.2, gap=0.5, accept=_canal_clear)
        ctx.row_along({"old", "switchback"}, BUILDINGS[::-1], sgn, 3.0 + 1.8, gap=0.0, accept=_canal_clear)
        ctx.row_along({"avenue", "approach"}, BUILDINGS[2:] + BUILDINGS[:2], sgn, 4.5 + 2.4, gap=1.0,
                      accept=_canal_clear)
        ctx.row_along({"checkpoint"}, ["props_buildings/row_res_2_fullscale", "props_buildings/row_res_1_fullscale"],
                      sgn, 3.5 + 3.0, gap=2.0, accept=_canal_clear)
    ctx.old_blocks = []
    _old_town(ctx)
    # the rest of the city: tower blocks and rows on a loose grid, clear of the circuit, each on
    # level ground, fronts (the tower blocks are open at the back) turned to the nearest road of any
    roads = ctx.roads.pos
    for x in np.arange(-520, 1120, 46.0):
        for z in np.arange(-720, 720, 46.0):
            q = np.array([x + rng.uniform(-8, 8), 0.0, z + rng.uniform(-8, 8)])
            gap = ctx.road_gap_to(q)
            if gap < 22 or gap > 430:
                continue
            m = TOWERS[int(rng.integers(0, 3))] if gap > 120 or rng.random() < 0.25 else BUILDINGS[int(rng.integers(0, len(BUILDINGS)))]
            i = int(np.argmin(((roads[:, [0, 2]] - q[[0, 2]]) ** 2).sum(1)))
            yaw = round(ctx.yaw_facing(roads[i] - q) / (np.pi / 2)) * np.pi / 2
            if m in TOWERS:
                # of its four sides, the one fewest road samples within 200 m see the open back of
                # (the nearest road's first)
                d = roads[:, [0, 2]] - q[[0, 2]]
                d = d[np.hypot(d[:, 0], d[:, 1]) < 200.0]
                yaw = min((yaw + k * np.pi / 2 for k in range(4)),
                          key=lambda y: int((d[:, 0] * math.sin(y) + d[:, 1] * math.cos(y) < 0.0).sum()))
            if not ctx.fits(m, q, yaw, 14.0) or not _canal_clear(ctx, m, q, yaw):
                continue
            g = ctx.site(m, q, yaw, tol=0.6)
            if g is None or g < -2.0 or g > 6.0:
                continue
            if any(np.hypot(p["pos"][0] - q[0], p["pos"][2] - q[2]) < 30 for p in ctx.props if p.get("tag") == "building"):
                continue
            q[1] = g
            ctx.add(m, q, yaw, tag="building", ground=False)
    _lamps(ctx)
    # plaza: Breencast screens either side of the line (its pavements are left clear: a kart pushed
    # onto them wedged itself between a column or a bench and the wall)
    ctx.screens = []
    for s, sgn in ((70.0, -1), (L - 120.0, 1)):
        i = int(round(s / t.step)) % t.n
        q = ctx.side(i, sgn, 7.0 + 2.0)
        q[1] = t.pos[i][1] + 13.0
        ctx.screens.append({"pos": q.tolist(), "yaw": float(ctx.yaw_facing(-t.flat_right[i] * sgn)), "w": 10.0,
                            "h": 5.6})
    # Combine checkpoint: barricades backed onto its walls (a kart spun onto the pavement is
    # not wedged behind one), booths, a watchtower, a bunker
    chk = [i for i in range(t.n) if t.style[i] == "checkpoint"]
    walk = t.styles["checkpoint"]["walk"]
    depth = ctx.model_size("props_combine/combine_barricade_tall01a")[2]
    for k, i in enumerate(chk[::7]):
        for sgn in (-1, 1):
            q = ctx.side(i, sgn, walk - depth / 2 - 0.05)
            q[1] = t.pos[i][1] + 0.16
            ctx.add("props_combine/combine_barricade_tall01a", q, ctx.yaw_facing(-t.flat_right[i] * sgn), ground=False)
    if chk:
        mid = chk[len(chk) // 2]
        for sgn in (-1, 1):
            q = ctx.side(mid, sgn, 3.5 + 5.0)
            q[1] = ctx.ground(q[0], q[2])
            ctx.add("props_combine/combine_booth_med01a", q, ctx.yaw_facing(-t.flat_right[mid] * sgn), ground=False)
        q = ctx.side(chk[0], 1, 3.5 + 6.0)
        q[1] = ctx.ground(q[0], q[2])
        ctx.add("props_combine/combinetower001", q, 0.0, ground=False)
        q = ctx.side(chk[-1], -1, 3.5 + 6.0)
        q[1] = ctx.ground(q[0], q[2])
        ctx.add("props_combine/combine_bunker01", q, ctx.yaw_facing(t.flat_right[chk[-1]]), ground=False)
    _canal(ctx)
    _yard(ctx)
    _pipe_caps(ctx)
    _barrier_steps(ctx)
    # trains parked on the embankment over the underpass
    tun = [i for i in range(t.n) if t.style[i] == "underpass"]
    for k, i in enumerate(tun[8::14]):
        m = WAGONS[k % len(WAGONS)]
        q = t.pos[i].copy()
        q[1] = t.pos[i][1] + t.height[i] + 2.5
        ctx.add(m, q, ctx.yaw_along(m, t.fwd[i]), ground=False)
    # the boulevard toward the Citadel: Combine machinery along it, on level ground
    fly = [i for i in range(t.n) if t.style[i] == "flyover"]
    blv = [i for i in range(t.n) if t.style[i] == "avenue" and fly and t.s[i] > t.s[fly[-1]]]
    for k, i in enumerate(blv[::30]):
        sgn = 1 if k % 2 else -1
        m = ["props_combine/combinebuttress", "props_combine/combine_generator01", "props_combine/combine_emitter01"][k % 3]
        q = ctx.side(i, sgn, 4.5 + 9.0)
        yaw = ctx.yaw_facing(-t.flat_right[i] * sgn)
        g = ctx.site(m, q, yaw)
        if g is not None:
            q[1] = g
            ctx.add(m, q, yaw)
    # a few physics props at the back of the pavement on the inside of slow corners (never on the
    # road, out of the way of a kart that runs wide onto the pavement; not in the hairpins or by
    # the turrets), 15 m or more from a crate row or a boost pad
    keep = [f * L for f in TRACK["items"] + TRACK["boosts"]]
    for i in ctx.every(140.0, 60.0):
        if t.gap[i] or abs(t.curv[i]) < 0.012 or t.kind(i) != "street" or t.junction[i]:
            continue
        if t.style[i] in ("switchback", "checkpoint"):
            continue
        if min(abs((t.s[i] - s + L / 2) % L - L / 2) for s in keep) < 15.0:
            continue
        sgn = -1 if t.curv[i] < 0 else 1
        st = t.styles[t.style[i]]
        base = ctx.side(i, sgn, 0.3 + st.get("walk", 3.0) - 0.9)
        base[1] = t.pos[i][1] + st.get("curb_h", 0.16)
        for k in range(3):
            q = base + t.fwd[i] * rng.uniform(-3, 3) + t.flat_right[i] * sgn * rng.uniform(-0.3, 0.3)
            ctx.add(["props_junk/trafficcone001a", "props_c17/oildrum001", "props_junk/wood_crate001a"][k],
                    q + UP * 0.02, rng.uniform(0, 6.28), physics=True, ground=False)


# ---------------------------------------------------------------- spectators (tools/crowds.py)
START = (-34.0, 30.0)  # grandstands either side of the line (lap metres)
PLAZA = ((-75.0, -36.0), (32.0, 60.0))  # two-step terraces beyond them
CP_EVERY = 9.0  # metrocops posted along the plaza terraces
# old-town terrace steps rise to this much under the wall's top: the people on them look over it
# from the waist up (the checkpoint's guards stand on a step behind its 5 m wall)
OLD_RISE = 0.7
OLD_EVERY = 60.0  # a 20 m terrace every this many metres of walled street
JUMP_WATCH = 32.0  # the middle street's terraces this near the rooftops' jump are its watchers'
GMAN_S = (700.0, 950.0)  # the lap metres the G-Man may stand beside (ctx.gman_spot)
GUARD_EVERY, GUARD_LEN, GUARD_DEPTH, GUARD_H = 36.0, 5.0, 1.6, 0.5  # the checkpoint guards' platforms


def _walled(ctx, i):
    """A street with a barrier you can see over (stands go behind it)."""
    return not ctx.trk.gap[i] and ctx.street_back(i) is not None


def _lap_walled(ctx, w):
    return [i for i in ctx.lap_ids(*w) if _walled(ctx, i)]


def _landings(ctx, before=10.0, after=40.0):
    """(gap end sample, sample ids from `before` m ahead of the landing to `after` m past it)."""
    t = ctx.trk
    out = []
    for a, b in t.gaps:
        s = ctx.s_of(b % t.n)
        out.append((b % t.n, ctx.lap_ids(s - before, s + after)))
    return out


def _start_window(ctx, i):
    s = ctx.s_of(i)
    L = ctx.trk.length
    rel = (s + L / 2) % L - L / 2
    return PLAZA[0][0] - 5 <= rel <= PLAZA[1][1] + 5


def _old_walls(ctx):
    """The old town's and the plaza's walled stretches away from the start (one-step terraces; not
    the checkpoint's approach)."""
    t = ctx.trk
    return [i for i in range(t.n) if _walled(ctx, i) and not _start_window(ctx, i) and t.style[i] != "approach"
            and ctx.style_of(i).get("barrier", {}).get("kind") == "wall"]


def _jump_watch(ctx):
    """The walled main-road samples under the rooftops' jump, within JUMP_WATCH of its middle."""
    t = ctx.trk
    roof = ctx.roads.trks[1 + [b["id"] for b in BRANCHES].index("rooftops")]
    a, b = roof.gaps[0]
    mid = roof.pos[(a + b) // 2]
    return [i for i in range(t.n) if _walled(ctx, i) and np.hypot(*(t.pos[i] - mid)[[0, 2]]) < JUMP_WATCH]


def _old_chunks(ctx):
    """The one-step terraces' stretches: 20 m every OLD_EVERY m along the old walls (none over the
    middle street's under the rooftops' jump), and the stretches under the jump (its watchers')."""
    t = ctx.trk
    jump = _jump_watch(ctx)
    old = [ch for ch in ctx.chunks(_old_walls(ctx), int(OLD_EVERY / t.step), int(20 / t.step))
           if not set(ch) & set(jump)]
    return old, ctx.runs_of(jump)


def stands(ctx):
    for sgn in (-1, 1):
        # start / finish: a Combine-built grandstand each side (4 tiers, back wall, canopy)
        ctx.grandstand(_lap_walled(ctx, START), sgn)
        for w in PLAZA:
            ctx.terrace(_lap_walled(ctx, w), sgn, steps=2)
        # the other walled streets: one step in 20 m chunks, raised so the people on it look over
        # the wall
        old, jump = _old_chunks(ctx)
        for ch in old + jump:
            h = ctx.style_of(ch[0])["barrier"].get("h", 2.0)
            ctx.terrace(ch, sgn, steps=1, rise=max(0.6, h - OLD_RISE))


def crowds(ctx):
    t = ctx.trk
    rng = ctx.crowd_rng
    # metrocops posted on the plaza terraces first (egg: they condemn rebels, salute Breen)
    for sgn in (-1, 1):
        for w in PLAZA:
            ids = _lap_walled(ctx, w)
            gid = ctx.crowd_group(ids[len(ids) // 2] if ids else 0, sgn, "post", "metrocop", tags=["start", "egg_cp"],
                                  bed="")
            ctx.crowd_line(gid, ids, sgn, CP_EVERY, lambda i, s: ctx.terrace_spot(i, s, 0), "metrocop", mood="loyal",
                           lod=lambda k: 0, margin=0.4, on="geom")
    # the grandstands: citizens, the back tiers on the one-material background citizen
    for sgn in (-1, 1):
        ids = _lap_walled(ctx, START)
        gid = ctx.crowd_group(ids[len(ids) // 2] if ids else 0, sgn, "stand", "citizen",
                              tags=["start", "grandstand"])
        for tier, chance in enumerate((0.75, 0.6, 0.35, 0.35)):
            far = tier >= 2
            ctx.crowd_line(gid, ids, sgn, 2.0, lambda i, s, k=tier: ctx.terrace_spot(i, s, k), "citizen",
                           mood=["fan", "fan", "excited", "polite"][int(rng.integers(0, 4))], chance=chance,
                           lod=(lambda k: 1) if far else None, margin=0.4, on="geom",
                           model=FAR_MODEL if far else None)
    # either side of them: the plaza crowd on its two steps
    for sgn in (-1, 1):
        for w in PLAZA:
            ids = _lap_walled(ctx, w)
            gid = ctx.crowd_group(ids[len(ids) // 2] if ids else 0, sgn, "terrace", "citizen", tags=["start"])
            ctx.crowd_line(gid, ids, sgn, 2.0, lambda i, s: ctx.terrace_spot(i, s, 0), "citizen", chance=0.65,
                           margin=0.4, on="geom")
            ctx.crowd_line(gid, ids, sgn, 2.0, lambda i, s: ctx.terrace_spot(i, s, 1), "citizen", chance=0.4,
                           lod=lambda k: 2, margin=0.4, on="geom")
    # the old town (and the plaza's far side): refugees on the one-step terraces, a group per chunk
    for ch in _old_chunks(ctx)[0]:
        for sgn in (-1, 1):
            gid = ctx.crowd_group(ch[len(ch) // 2], sgn, "terrace", "refugee")
            ctx.crowd_line(gid, ch, sgn, 1.6, lambda i, s: ctx.terrace_spot(i, s, 0), "refugee",
                           mood=["fan", "polite"][int(rng.integers(0, 2))], chance=0.6, margin=0.4, on="geom")
    # the yard jump's landing: rebels in clusters on the open ground past the fences
    for land, ids in _landings(ctx):
        if t.kind(land) != "open":
            continue
        st = ctx.style_of(land)
        off = st.get("barrier", {}).get("off", 0.0) + 4.0
        j = min(ids[len(ids) // 3:] or [land], key=lambda k: abs(t.curv[k]))
        for sgn in (-1, 1):
            c = ctx.side_point(j, sgn, st.get("verge_w", 4.5) + off + 4.0)
            gid = ctx.crowd_group(j, sgn, "cluster", "rebel", tags=["jump"])
            ctx.crowd_cluster(gid, c, 10, 6.0, "rebel", t.pos[j] + np.array([0, 1.0, 0]), mood="excited",
                              ref_y=t.pos[j][1])
    # the rest of the fenced yard: rebels beyond the fence
    fenced = [i for i in range(t.n) if t.kind(i) == "open" and not t.gap[i]
              and ctx.style_of(i).get("barrier", {}).get("kind") == "fence"]
    for sgn in (-1, 1):
        def beyond(i, s):
            st = ctx.style_of(i)
            return ctx.side_point(i, s, st.get("barrier", {}).get("off", 0.0) + rng.uniform(1.5, 6.0), jitter=1.0)

        for ch in ctx.chunks(fenced, int(40 / t.step), int(40 / t.step)):
            gid = ctx.crowd_group(ch[len(ch) // 2], sgn, "line", "rebel")
            ctx.crowd_line(gid, ch, sgn, 3.0, beyond, "rebel", chance=0.28, margin=2.5, dy=(-1.0, 3.0))
    # the cutting: people on both lips looking down into it
    for ids in ctx.runs_of([i for i in range(t.n) if t.kind(i) == "trench"]):
        for sgn in (-1, 1):
            gid = ctx.crowd_group(ids[len(ids) // 2], sgn, "lip", "citizen", tags=["lip"])
            ctx.crowd_line(gid, ids, sgn, 2.0, ctx.lip_spot, "citizen", chance=0.5, margin=0.3, on="geom")
    _guards(ctx)
    # the Breencast screens: the plaza crowd near one watches it instead now and then
    for scr in getattr(ctx, "screens", []):
        sp = np.array(scr["pos"], float)
        for m in ctx.crowds:
            if m["role"] != "metrocop" and math.hypot(m["pos"][0] - sp[0], m["pos"][2] - sp[2]) < 35.0 \
                    and rng.random() < 0.4:
                m["yaw"] = round(math.atan2(sp[0] - m["pos"][0], sp[2] - m["pos"][2]), 3)
    eggs(ctx)


def _guards(ctx):
    """The checkpoint's guards (its walls are too tall to see over): on platforms behind its walls,
    their tops GUARD_H under the walls' (they show from the chest up over them), every GUARD_EVERY
    m along both walls where there is room: two metrocops each, a Combine soldier on some (egg:
    they condemn rebels and salute Breen)."""
    t = ctx.trk
    st = t.styles["checkpoint"]
    bar = st["barrier"]
    chk = [i for i in range(t.n) if t.style[i] == "checkpoint"]
    for sgn in (-1, 1):
        for n, i in enumerate(chk[int(GUARD_EVERY / 2 / t.step)::int(GUARD_EVERY / t.step)]):
            back = 0.3 + st["walk"] + bar["thick"] + 0.05
            c = ctx.side(i, sgn, back + GUARD_DEPTH / 2)
            top = t.pos[i][1] + bar["h"] - GUARD_H
            g = min(ctx.ground(*ctx.side(i, sgn, back + k)[[0, 2]]) for k in (0.0, GUARD_DEPTH))
            size = [GUARD_DEPTH, top - g + 0.5, GUARD_LEN]
            yaw = ctx.yaw_facing(t.fwd[i])
            centre = [c[0], (top + g - 0.5) / 2, c[2]]
            if not ctx.free(centre, size, yaw):
                continue
            ctx.box(bar["mat"], centre, size, yaw)
            gid = ctx.crowd_group(i, sgn, "post", "metrocop", tags=["checkpoint"], bed="")
            look = t.pos[i] + UP * 1.0
            for k, role in enumerate(("metrocop", "metrocop", "combine")[:3 if n % 2 else 2]):
                q = c + t.fwd[i] * (k - 1) * 1.6
                q[1] = top
                ctx.crowd_add(gid, q, look, role, mood="military" if role == "combine" else "loyal", lod=0,
                              margin=0.4, on="geom")


def crowds_branch(bctx, spec):
    """People watching a branch's jump (their group follows the karts on that branch): on the
    canal's banks beside the canal jump, and on the middle street's terraces under the rooftops'
    jump, looking up."""
    t = bctx.trk
    for a, b in t.gaps:
        mid = (a + b) // 2
        watch = [float(t.s[max(a - 25, 0)]), float(t.s[min(b + 10, t.n - 1)])]
        look = t.pos[mid] + UP * 2.0
        if spec["id"] == "canal_jump":
            for k, sgn in ((a - 6, -1), (a - 6, 1), (min(b + 6, t.n - 1), -1), (min(b + 6, t.n - 1), 1)):
                c = bctx.side_point(k, sgn, 8.0)
                gid = bctx.crowd_group(k, sgn, "cluster", "citizen", tags=["jump"], watch=watch)
                bctx.crowd_cluster(gid, c, 6, 4.0, "citizen", look, mood="excited", ref_y=t.pos[k][1],
                                   dy=(-1.5, 1.5))
        elif spec["id"] == "rooftops":
            # the main road's own terrace steps below the jump
            main = bctx.roads.trks[0]
            under = [i for i in range(main.n) if (bctx._steps.get((None, i, -1)) or bctx._steps.get((None, i, 1)))
                     and np.hypot(*(main.pos[i] - t.pos[mid])[[0, 2]]) < JUMP_WATCH]
            if not under:
                continue
            gid = bctx.crowd_group(mid, 0, "terrace", "citizen", tags=["jump"], watch=watch)
            for i in under:
                for sgn in (-1, 1):
                    st = bctx._steps.get((None, i, sgn))
                    if st is None or bctx.crowd_rng.random() > 0.45:
                        continue
                    back, rise, depth, steps, base, _ = st
                    q = main.pos[i] + main.flat_right[i] * sgn * (main.width[i] / 2 + back + depth * 0.5)
                    q[1] = base + rise
                    bctx.crowd_add(gid, q, look, "citizen", mood="excited", margin=0.4, on="geom")


def _in_blocks(ctx, q):
    """Inside one of the old town's blocks of flats (_prism)."""
    for P in getattr(ctx, "old_blocks", []):
        a, b = P, np.roll(P, -1, axis=0)
        cross = (a[:, 1] > q[2]) != (b[:, 1] > q[2])
        with np.errstate(divide="ignore", invalid="ignore"):
            x = a[:, 0] + (q[2] - a[:, 1]) * (b[:, 0] - a[:, 0]) / (b[:, 1] - a[:, 1])
        if (cross & (q[0] < x)).sum() % 2:
            return True
    return False


def eggs(ctx):
    t = ctx.trk
    rng = ctx.crowd_rng
    # pigeons on the plaza's and the old town's pavements, away from the stands
    walled = [i for i in range(t.n) if _walled(ctx, i) and not _start_window(ctx, i)]
    for k, i in enumerate(walled[len(walled) // 5::max(1, len(walled) // 2)][:2]):
        sgn = 1 if k % 2 else -1
        st = ctx.style_of(i)
        c = ctx.side_point(i, sgn, 0.3 + st.get("walk", 3.0) * 0.6, y=t.pos[i][1] + 0.16)
        ctx.egg("birds", species="pigeon", center=c, radius=2.5, count=8)
    # zombies shambling behind an old-town wall where no building stands
    done = False
    old = [i for i in walled if t.style[i] in ("old", "switchback")]
    for ch in ctx.chunks(old, int(30 / t.step), int(12 / t.step)):
        if done:
            break
        for sgn in (-1, 1):
            back = ctx.street_back(ch[0])
            if back is None:
                continue
            a = ctx.side_point(ch[0], sgn, back[0] + 2.0)
            b = ctx.side_point(ch[-1], sgn, back[0] + 2.0)
            if all(ctx.crowd_ok(p, margin=2.0) and not _in_blocks(ctx, p) for p in (a, (a + b) / 2, b)) and \
                    ctx.egg("zombies", path=[a, b], count=3, model="zombie/classic"):
                done = True
                break
    # the G-Man by the canal corner, ahead of the karts coming round it, clear of the crate rows:
    # seen 25-70 m off for a few seconds, gone when you come close or look away (a kart on the canal
    # jump misses him: where every kart drives, fences and walls hide him too soon)
    g = ctx.gman_spot(*GMAN_S)
    if g is not None:
        ctx.egg("gman", pos=g["pos"], yaw=g["yaw"], s=g["s"], model="gman_high", window=g["window"], chance=0.4)
    # Gnome Chompski on a grandstand canopy
    if ctx.canopies:
        c = ctx.canopies[int(rng.integers(0, len(ctx.canopies)))]
        ctx.egg("gnome", pos=c["pos"], yaw=math.atan2(-t.flat_right[c["i"]][0] * c["sgn"],
                                                      -t.flat_right[c["i"]][2] * c["sgn"]))
