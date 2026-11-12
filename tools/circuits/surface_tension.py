"""Surface Tension: the New Mexico desert outside Black Mesa, about 2.5 km.

From the start on the mesa the highway runs out to the canyon's edge, jumps a stretch the
floods washed out and drops into the red-rock canyon by a hairpin on its wall; a rail-less
dirt road stays up on the rim instead and drops back in at the hairpin's foot (rim_drop).
The road runs north up the west bank of the river, where the washed-out ford jumps it
(washout), crosses the gorge on a steel bridge and comes back south through the HECU camp by
a landed Osprey, rolls twice round the dam's water main, climbs a cliff road and crosses the
crest of the dam. A viaduct then carries it over the start straight, Suzuka style, and a loop
to the north brings it home. An Apache guards the canyon's edge, sentry guns the camp and
mortars the dam; Black Mesa's survivors and the marines watch from the roadside.
"""
import math

import numpy as np

from track_gen import UP, carve, face, noise2, smoothstep

RIVER = [(320.0, 70.0), (400.0, -60.0), (470.0, -160.0), (478.0, -300.0), (476.0, -420.0), (470.0, -560.0),
         (440.0, -760.0)]
RIVER_Y = -2.0
DAM_Z = 112.0
LAKE_Y = 24.0
RIM_VERGE = 2.0  # the rim road's verge: past it the canyon side falls away
RIM_TOP = 31.5  # the mesa top beside the rim road
# level run-off past the carve's own on the outside of bends below a canyon wall (lap metres from,
# to, side, metres): out of the hairpin's foot
APRONS = [(520.0, 610.0, -1, 12.0)]

CTRL = [
    # the start straight on the mesa (the viaduct crosses it at s 120), then out to the canyon's edge
    (20, 30, 0, 18, "start"),
    (80, 30, -2, 18, "highway"),
    (150, 30, -10, 17, "highway"),
    # level, unbanked mesa road: the washed-out stretch, then the rim road leaves on the left
    (196, 30, -30, 17, "mesa"),
    (240, 30, -62, 17, "mesa", {"gap": True, "gap_span": (0.38, 0.62), "ramp_lift": 2.0}),
    (280, 29.5, -94, 17, "mesa"),
    # down into the canyon by a hairpin on its wall
    (318, 27.6, -126, 16, "canyon"),
    (330, 25.5, -160, 15, "canyon"),
    (330, 23, -196, 15, "canyon"),
    (296, 21.2, -212, 15, "canyon"),
    (266, 19.6, -228, 15, "canyon"),
    (254, 18.4, -252, 15, "canyon"),       # the hairpin's foot: the rim road comes down here
    (266, 17, -280, 15, "canyon"),
    (300, 15, -296, 15, "canyon"),
    (340, 13, -304, 15, "canyon"),
    (370, 11, -314, 15, "canyon"),
    # north up the west bank of the river (the washout leaves on the right) to the gorge bridge
    (388, 10, -327, 15, "turnin"),
    (395.5, 9.2, -348, 15, "turnin"),
    (397, 9, -380, 15, "canyon"),
    (399, 9, -410, 15, "canyon"),
    (404, 10, -436, 14, "canyon"),
    (436, 11, -468, 14, "gorge"),
    (494, 13, -484, 14, "gorge"),
    (550, 14, -466, 14, "gorge"),
    # back south down the east bank (the washout comes in on the right) through the HECU camp
    (580, 15, -438, 17, "canyon"),
    (604, 16, -406, 18, "camp"),
    (638, 17, -344, 18, "camp"),
    (654, 18, -284, 18, "camp", {"gap": True, "gap_span": (0.005, 0.14), "ramp_lift": 2.2}),
    (662, 20, -212, 17, "camp"),
    (642, 22, -122, 14, "pipe"),
    (602, 24, -42, 14, "pipe"),
    (566, 28, 30, 15, "cliffrail"),
    (488, 32, 84, 15, "cliff"),
    (390, 34, DAM_Z, 16, "dam"),
    (262, 34, DAM_Z, 16, "dam"),
    # off the dam's west end, up onto the viaduct over the start straight and a loop to the
    # north back to the line
    (180, 34.6, DAM_Z - 1, 17, "approach"),
    (152, 36.6, 88, 17, "approach"),
    (146, 38.5, 50, 16, "viaduct"),
    (136, 41.5, -4, 16, "viaduct"),
    (128, 39, -64, 16, "highway"),
    (92, 36, -100, 17, "highway"),
    (30, 33, -110, 17, "highway"),
    (-30, 31, -96, 18, "highway"),
    (-78, 30, -62, 18, "highway"),
    (-86, 30, -14, 18, "highway"),
    (-46, 30, -1.6, 18, "start"),
]
CTRL = [c if len(c) > 5 else c + ({},) for c in CTRL]

BRANCHES = [
    # the rim road: a rail-less dirt road along the canyon's rim inside the hairpin, then a jump
    # down onto the road at the hairpin's foot (short of it is the canyon floor)
    {"id": "rim_drop", "name": "Rim drop", "fork": (276, -91), "merge": (262, -268), "kind": "ledge",
     "merge_type": "drop",
     "ctrl": [(290, 28.8, -136, 10, "rimtop"), (270, 31, -176, 10, "rim"),
              (264, 31.5, -204, 10, "rim", {"gap": True, "gap_span": (0.04, 0.97), "ramp_lift": 1.6}),
              (257, 19.2, -238, 12, "canyon"), (256.8, 18.7, -248, 12, "canyon")],
     # (its danger sign well out on the level mesa top, which karts cut across on the bends)
     "risk": 0.5, "ai": {"take": 0.5, "min_skill": 0.85}, "danger_out": 7.0},
    # the washed-out ford: off the west bank, a boost pad out of the turn and a jump over the
    # river instead of the trip up to the gorge bridge and back (short of it is the river). The
    # ford's causeway runs out into the river and its far half is gone: a 30 m jump, late enough
    # on the branch that a kart put back after a fall gets up to speed again on the way to it
    {"id": "washout", "name": "Washout", "fork": (397, -366), "merge": (611, -395), "kind": "jump", "side": 1,
     "ctrl": [(417, 9.1, -396, 12, "turnin"),
              (441, 10, -404, 11, "ramp", {"gap": True, "gap_span": (0.52, 0.94), "ramp_lift": 3.0, "ramp_len": 20}),
              (504, 7.5, -410, 12, "canyon"), (552, 13.6, -420, 12, "canyon"), (573.5, 15.15, -420, 12, "canyon"),
              (593, 15.8, -411, 12, "canyon")],
     "boosts": [0.22], "risk": 0.7, "ai": {"take": 0.5, "min_skill": 0.88}, "retry_back": 60.0},
]

TRACK = {
    "id": "surface_tension",
    "music": ['hl1_song20', 'hl1_song21', 'hl1_song24', 'hl1_song26', 'hl1_song14'],
    "name": "Surface Tension",
    "ctrl": CTRL,
    # (the camp's row past the camp jump's landing: from a row before it the items flew at karts on
    # its kicker, and one spun there falls short)
    "items": [0.042, 0.153, 0.242, 0.355, 0.497, 0.572, 0.721, 0.878],
    "boosts": [0.024, 0.181, 0.232, 0.282, 0.387, 0.479, 0.542, 0.588, 0.629, 0.757, 0.849, 0.927],
    # (none on the dam: a mortar going off with a barrel there threw karts over its walls; the
    # camp's at its gate, before the sentry guns: from there on to the camp jump's kicker the road
    # is clear, so a kart a gun spins does not slide into a blast, and none is thrown tumbling onto
    # the kicker)
    "barrels": [0.077, 0.424, 0.9],
    "vmax": 40.0,
    "offtrack": 45.0,
    # the game's gravity (project.godot): the launch speeds the branches export are the real ones
    "gravity": 15.24,
    "sky": "hl1_desert",
    "background": "none",
    "gantry": "military",
    "water": {"level": RIVER_Y},
    # the reservoir: up to the dam body under the crest road, its far shores inside the water
    "waters": [{"center": [326.0, DAM_Z + 147.0], "size": [300.0, 296.0], "level": LAKE_Y}],
    "env": {"sun_energy": 2.1, "sun_color": [1.0, 0.9, 0.74], "sun_dir": [0.45, 0.75, -0.35],
            "ambient": [0.66, 0.58, 0.5], "ambient_energy": 1.0, "fog_color": [0.86, 0.74, 0.6],
            "fog_begin": 300.0, "fog_end": 2200.0, "exposure": 1.0, "sdfgi": True},
    # (lap metres: the viaduct over the start straight at s 120, the washed-out jump at s 256, the
    # camp from s 1033, the dam from s 1699)
    "hazards": [
        # the Apache hangs low over the mesa road ahead and rockets the karts coming up the start
        # straight under the viaduct; its rockets land well short of the washed-out jump's kicker
        # (its ramp from s 240) by 60 m and more, so a kart it tumbles has the run-up to get back up
        # to speed
        {"type": "apache", "zone": [62, 178], "hover": [[184, -12, 16], [198, 10, 20], [176, 6, 14]],
         "max_d": 140.0, "every": 3.5},
        # HECU sentry guns among the camp's barricades (clear of the camp jump and the water main,
        # the first one well before the jump's kicker, so a kart it spins gets back up to speed):
        # one camp, so a kart one of them spins is left alone by the others on that pass
        {"type": "turret", "s": 1095, "side": 1, "setback": 2.5, "zone": [1055, 1100], "model": "hl1/sentry",
         "scale": 1.3, "range": 38, "cone": 65, "lock": 0.85, "burst": 0.5, "group": "camp"},
        {"type": "turret", "s": 1244, "side": -1, "setback": 2.5, "zone": [1204, 1249], "model": "hl1/sentry",
         "scale": 1.3, "range": 38, "cone": 65, "lock": 0.85, "burst": 0.5, "group": "camp"},
        {"type": "turret", "s": 1294, "side": 1, "setback": 2.5, "zone": [1254, 1299], "model": "hl1/sentry",
         "scale": 1.3, "range": 38, "cone": 65, "lock": 0.85, "burst": 0.5, "group": "camp"},
        # a mortar barrage on the walled crest of the dam (no falling off it)
        {"type": "strike_zone", "style": "mortar", "zone": [1722, 1907], "every": 2.2, "count": 1, "radius": 5.5,
         "warn": 1.8, "effect": "tumble"},
    ],
}


def styles(m):
    g = m.goldsrc
    asphalt = m.hl2("concrete/concretefloor037a")
    concrete = m.hl2("concrete/concretewall008a")
    g("out_w3"), g("out_w4"), g("c2a5g_sign1"), g("metal_wall04")  # the start arch
    highway = {"kind": "open", "road": asphalt, "road_u": "full", "road_len": 1.0, "verge": g("out_snd2c"),
               "verge_w": 5.0}
    # the desert's dirt roads: dusty ruts, no grass between them
    canyon = {"kind": "open", "road": m.hl2("nature/dirtroad001b"), "road_u": "full", "road_len": 2.0,
              "verge": g("out_snd2c"), "verge_w": 4.0, "skirt": g("out_rk3")}
    # the dam's concrete parapet: upright (a jersey barrier's sloping foot throws a kart that runs
    # into it at speed up and over it), and a kart thrown up off the road (a mortar, a rocket, two
    # blasts at once) meets it up to 6 m
    parapet = {"kind": "wall", "mat": concrete, "h": 1.1, "thick": 0.7, "rep": 3.0, "col_h": 6.0}
    cliff = {"kind": "open", "road": asphalt, "road_u": "full", "verge": g("out_snd2c"), "verge_w": 3.0, "pit": True,
             "skirt": g("out_rk3"), "drop": {"side": -1, "y": LAKE_Y + 0.8}}
    river_rail = {"kind": "fence", "mat": m.hl2("metal/metalrail013c"), "h": 1.1, "rep": 2.4, "off": canyon["verge_w"],
                  "col_h": 2.5, "sides": "right"}
    return {
        "highway": dict(highway, bank=True),
        # the start straight, its grid level and unbanked (no kart creeps down a bank before GO!)
        "start": highway,
        # the mesa road out to the canyon's edge: level, where the rim road leaves it
        "mesa": highway,
        # off the dam to the viaduct, the parapets both sides: they run on from the dam's to the
        # viaduct's, so no kart that runs wide gets outside them before the deck (and off its end)
        "approach": dict(highway, bank=True, barrier=parapet),
        # over the start straight: a concrete deck on piers, left as it stands by the ground
        "viaduct": {"kind": "bridge", "road": asphalt, "road_u": "full", "skirt": concrete, "skirt_h": 2.0,
                    "barrier": parapet, "pillar": concrete, "pillar_every": 28.0, "pillar_size": 2.0,
                    "ground": "keep"},
        # the rim road: a narrow dirt road on the canyon's edge, nothing between it and the drop
        # (from where the drop is deep enough to fall from; up to there the canyon floor is still
        # close below: "rimtop")
        "rimtop": dict(canyon, verge_w=RIM_VERGE),
        "rim": dict(canyon, verge_w=RIM_VERGE, pit=True),
        # the west bank's road out of the bend before the washout and the washout itself along the
        # river: a rusty rail at the verge's outer edge on the river side (a kart that runs on past
        # the bend or the turn in would go on down the bank into the water), up to its kicker; out
        # of the bend and into the turn computer drivers are held to 28 m/s, so one that turns in
        # from the bend's inside does not run on across the branch into the rail
        "turnin": dict(canyon, barrier=river_rail, vmax=28.0),
        "ramp": dict(canyon, barrier=river_rail),
        "canyon": canyon,
        "gorge": {"kind": "bridge", "road": m.hl2("metal/metalgrate013a"), "road_rep": 3.0,
                  "skirt": m.hl2("metal/metaltruss009a"), "skirt_h": 3.5,
                  "barrier": {"kind": "fence", "mat": m.hl2("metal/metaltruss002a"), "h": 2.2, "rep": 3.0,
                              "col_h": 4.5},
                  "pillar": m.hl2("metal/metaltruss009a"), "pillar_every": 34.0, "pillar_size": 2.4,
                  "pillar_offsets": [-0.8, 0.8]},
        "camp": {"kind": "open", "road": g("out_snd2c"), "road_rep": 5.0, "verge": g("out_snd2"), "verge_w": 6.0},
        # the cliff road has no barrier: over the left edge it falls to the lake's beach (dry, just
        # above the water, which ends at the lake's rectangle) ...
        "cliff": cliff,
        # ... except on the bend out of the water main, where a kart still finding its feet after
        # the pipe's rolls would run off it
        "cliffrail": dict(cliff, barrier=dict(parapet, sides="left")),
        # the dam's water main, laid in a cut through the mountain: two rolls round the pipe, the
        # lane back at the bottom well before the exit ("settle")
        "pipe": {"kind": "tube", "road": m.hl2("nature/dirtroad001b"), "road_u": "full", "road_len": 2.0,
                 "ground": "rest", "settle": 16.0,
                 "wall": m.hl2("metal/metalpipe010a"), "skin": m.hl2("metal/metalpipe010a"),
                 "glow": m.hl2("lights/fluorescent001a"), "radius": 12.0, "roll": 720.0,
                 "ring_every": 14.0, "light_color": [1.0, 0.85, 0.6], "light_energy": 1.8},
        # the crest of the dam: its ends (the west one bends round onto the shore) rest on the land
        "dam": {"kind": "bridge", "road": asphalt, "road_u": "full", "skirt": concrete, "skirt_h": 2.0,
                "barrier": parapet, "pillar_every": 1e9, "dip_fade": 34.0},
    }


def _poly_dist(P, poly):
    best = np.full(len(P), 1e9)
    pts = np.asarray(poly, float)
    for a, b in zip(pts[:-1], pts[1:]):
        ab = b - a
        t = np.clip(((P - a) @ ab) / (ab @ ab), 0.0, 1.0)
        q = a + t[:, None] * ab
        best = np.minimum(best, np.linalg.norm(P - q, axis=1))
    return best


def _branch_trk(roads, bid):
    """The road of branch `bid` in a RoadSet (its trks follow BRANCHES), or None."""
    k = [b["id"] for b in BRANCHES].index(bid) + 1
    return roads.trks[k] if len(roads.trks) > k else None


def _nearest(P, Q):
    """For each plan point of P (n, 2): the distance to the nearest of Q (m, 2) and its index."""
    dist = np.zeros(len(P))
    idx = np.zeros(len(P), int)
    for a in range(0, len(P), 4096):
        d2 = ((P[a:a + 4096, None, :] - Q[None, :, :]) ** 2).sum(-1)
        idx[a:a + 4096] = d2.argmin(1)
        dist[a:a + 4096] = np.sqrt(d2[np.arange(len(d2)), idx[a:a + 4096]])
    return dist, idx


def _inside(P, poly):
    """Which plan points of P lie inside the polygon poly (m, 2) (even-odd rule)."""
    out = np.zeros(len(P), bool)
    for (x1, z1), (x2, z2) in zip(poly, np.roll(poly, -1, axis=0)):
        if z1 == z2:
            continue
        cross = (z1 > P[:, 1]) != (z2 > P[:, 1])
        x = x1 + (P[:, 1] - z1) * (x2 - x1) / (z2 - z1)
        out ^= cross & (P[:, 0] < x)
    return out


def _hairpin(f, lap, rim):
    """The canyon inside the hairpin the rim road cuts across: which cells lie between the rim
    road and the hairpin (the polygon of the rim's centre line, its jump and the lap back from
    the landing to the fork), the floor there (sloping smoothly between the heights of the
    hairpin's legs round it: the nearest leg's height alone would step where the nearest leg
    changes), how far each cell is from the rim road's centre, whether it lies on the rim road's
    left (away from the canyon) and how far it is from the rim's jump."""
    i0 = int(np.argmin(((lap.pos - rim.pos[0]) ** 2).sum(1)))
    i1 = int(np.argmin(((lap.pos - rim.pos[-1]) ** 2).sum(1)))
    ids = np.arange(i0, i1 + 1)
    inside = _inside(f.P, np.vstack([rim.pos[:, [0, 2]], lap.pos[ids[::-1]][:, [0, 2]]]))
    Q = lap.pos[ids][:, [0, 2]]
    floor = np.zeros(len(f.P))
    for a in range(0, len(f.P), 4096):
        d2 = ((f.P[a:a + 4096, None, :] - Q[None, :, :]) ** 2).sum(-1)
        w = 1.0 / (d2 + 16.0) ** 1.5
        floor[a:a + 4096] = (w * lap.pos[ids][:, 1]).sum(1) / w.sum(1) - 0.4
    road = np.flatnonzero(~rim.gap)
    d_rim, j = _nearest(f.P, rim.pos[road][:, [0, 2]])
    left = ((f.P - rim.pos[road][j][:, [0, 2]]) * rim.flat_right[road][j][:, [0, 2]]).sum(1) < 0.0
    d_gap, _ = _nearest(f.P, rim.pos[rim.gap][:, [0, 2]]) if rim.gap.any() else (np.full(len(f.P), 1e9), None)
    return inside, floor, d_rim, left, d_gap


def terrain(trk, m):
    g = m.goldsrc
    layers = {"base": g("out_snd2"), "dirt": g("out_snd2c"), "rock": g("out_rk3"),
              "pave": m.hl2("concrete/concretewall008a"), "sand": m.hl2("nature/sandfloor010a")}

    def build(f, trk):
        P = f.P
        # mesas: a terraced plateau of red rock
        n1 = noise2(P[:, 0] / 160.0, P[:, 1] / 160.0, 5)
        n2 = noise2(P[:, 0] / 45.0, P[:, 1] / 45.0, 8)
        terr = np.floor(n1 * 4.0) / 4.0 + smoothstep(0.0, 1.0, (n1 * 4.0) % 1.0) * 0.25
        plateau = 42.0 + terr * 46.0 + n2 * 6.0
        # the river valley: a canyon cut down to the water
        rd = _poly_dist(P, RIVER)
        valley = smoothstep(120.0, 22.0, rd)
        nat = plateau * (1 - valley) + (RIVER_Y - 5.0) * valley
        # the reservoir behind the dam: a lake bed north of the crest, its shores rising out of the
        # water inside the water's rectangle (WATERS)
        (wx, wz), (sx, sz) = TRACK["waters"][0]["center"], TRACK["waters"][0]["size"]
        lake = (smoothstep(DAM_Z + 10.0, DAM_Z + 30.0, P[:, 1]) * smoothstep(sx / 2, sx / 2 - 30.0, np.abs(P[:, 0] - wx)) *
                smoothstep(wz + sz / 2, wz + sz / 2 - 30.0, P[:, 1]))
        nat = nat * (1 - lake) + (LAKE_Y - 8.0) * lake
        # inside the hairpin the canyon floor lies at the road's height down there; on the rim
        # road's other side the mesa top is level with it for a while before the plateau rises
        rim = _branch_trk(trk, "rim_drop")
        if rim is not None:
            inside, floor, d_rim, left, d_gap = _hairpin(f, trk.main, rim)
            nat = np.where(inside, floor, nat)
            shelf = np.where(left & ~inside, smoothstep(110.0, 45.0, d_rim), 0.0)
            nat = nat - np.maximum(nat - RIM_TOP, 0.0) * shelf
        # run-off on the outside of the bends where a kart that runs wide meets a canyon wall
        lap = trk.main
        for s0, s1, sgn, width in APRONS:
            ids = np.flatnonzero((lap.s >= s0) & (lap.s <= s1))
            d, k = _nearest(P, lap.pos[ids][:, [0, 2]])
            out = ((P - lap.pos[ids][k][:, [0, 2]]) * lap.flat_right[ids][k][:, [0, 2]]).sum(1) * sgn > 0.0
            edge = lap.width[ids][k] / 2 + 8.0 + width
            nat = nat - np.maximum(nat - lap.pos[ids][k, 1], 0.0) * np.where(out, smoothstep(edge + 20.0, edge, d), 0.0)
        h = carve(f, nat, trk, flat=8.0, blend=26.0, gap_floor=RIVER_Y + 2.0)
        if rim is not None:
            # the rim road's canyon side falls steeply from its verge to that floor (over three grid
            # cells, so the cliff does not step where it runs across the grid), and the floor runs
            # on under its jump (no pit there: short of the road is the canyon floor)
            edge = rim.width.max() / 2 + RIM_VERGE + 0.5
            fall = floor + (h - floor) * smoothstep(edge + 12.0, edge, d_rim)
            h = np.where(inside, np.minimum(h, fall), h)
            h = np.where(d_gap < 25.0, np.maximum(h, floor), h)
        # the river runs on under the gorge bridge and the washed-out ford: no bank of a deck's or a
        # jump's shoulders dams it, clear of the grounded roads' beds and verges
        grounded = np.flatnonzero(np.array([trk.kind(i) not in ("bridge", "tube") for i in range(trk.n)]) & ~trk.gap)
        d, k = _nearest(P, trk.pos[grounded][:, [0, 2]])
        bank = d > trk.width[grounded][k] / 2 + 10.0
        h = np.where((rd < 22.0) & (f.cat == 2) & bank, np.minimum(h, nat), h)
        # the dam holds the lake back: on its lake side (left) the bed runs up to the dam body; on the
        # other the land falls to the river valley's floor where that lies lower
        by_dam = (f.style == "dam") & (np.abs(f.lat) > f.half + 1.0)
        shore = (smoothstep(sx / 2, sx / 2 - 30.0, np.abs(P[:, 0] - wx)) *
                 smoothstep(wz + sz / 2, wz + sz / 2 - 30.0, P[:, 1]))
        h = np.where(by_dam & (f.lat < 0.0), h - np.maximum(h - (LAKE_Y - 8.0), 0.0) * shore, h)
        h = np.where(by_dam & (f.lat > 0.0), np.minimum(h, np.maximum(nat, RIVER_Y - 5.0)), h)
        # beside a deck the ground stays under it for a grid cell past its edge, so no terrain
        # triangle reaches up through its edge (where a deck leaves a cutting, or another road's
        # shoulder climbs beside it)
        deck = np.flatnonzero(np.array([trk.kind(i) == "bridge" for i in range(trk.n)]) & ~trk.gap)
        if len(deck):
            d, k = _nearest(P, trk.pos[deck][:, [0, 2]])
            near = d < trk.width[deck][k] / 2 + f.cell + 0.5
            h = np.where(near, np.minimum(h, trk.pos[deck][k, 1] - 0.5), h)
        # no lone spike of ground by a road: where the carves of two roads meet (a deck's end and
        # another road's shoulder) a single cell can stand metres above all four neighbours
        Hm = h.reshape(f.nz, f.nx)
        by_road = (f.dist < f.half + 40.0).reshape(f.nz, f.nx)
        for _ in range(2):
            pad = np.pad(Hm, 1, mode="edge")
            nb = np.maximum(np.maximum(pad[:-2, 1:-1], pad[2:, 1:-1]), np.maximum(pad[1:-1, :-2], pad[1:-1, 2:]))
            Hm = np.where(by_road & (Hm > nb + 2.5), nb, Hm)
        h = Hm.ravel()
        # level pads for the big set pieces by the road (PADS), each at the road's height beside it
        # or, where the ground under it lies lower, at that (a wreck on the canyon floor lies on
        # the floor, not on a mound at the road's height)
        for model, q, yaw, i, (x0, x1, z0, z1), sink in _pad_sites(trk.main):
            c, s_ = math.cos(yaw), math.sin(yaw)
            d = P - q[[0, 2]]
            lx, lz = d[:, 0] * c - d[:, 1] * s_, d[:, 0] * s_ + d[:, 1] * c
            out = np.maximum(np.maximum(np.maximum(x0 - 2.5 - lx, lx - x1 - 2.5), 0.0),
                             np.maximum(np.maximum(z0 - 2.5 - lz, lz - z1 - 2.5), 0.0))
            pad = smoothstep(6.0, 0.0, out)
            level = min(trk.main.pos[i][1] - 0.3, float(np.median(h[out <= 0.0])))
            h = h * (1 - pad) + level * pad
        # (a pad's edge never rises over a road that drops away beside it)
        h = np.minimum(h, f.cap)
        # the ground's layers: rock on steep slopes, dirt by the roads, sand at the water's edges
        # (the slope blurred over the neighbouring cells, so the rock's edge does not follow the
        # grid's steps where a cliff runs across it)
        Hm = h.reshape(f.nz, f.nx)
        gz, gx = np.gradient(Hm, f.cell)
        slope = np.sqrt(gx ** 2 + gz ** 2)
        for _ in range(2):
            pad = np.pad(slope, 1, mode="edge")
            slope = (pad[:-2, 1:-1] + pad[2:, 1:-1] + pad[1:-1, :-2] + pad[1:-1, 2:] + 4.0 * slope) / 8.0
        rock = smoothstep(0.35, 0.75, slope.ravel())
        dirt = smoothstep(f.half + 10.0, f.half + 2.0, f.dist) * (1 - rock)
        sand = smoothstep(RIVER_Y + 4.0, RIVER_Y + 1.0, h) + smoothstep(LAKE_Y + 1.0, LAKE_Y - 1.0, h) * lake
        sand = np.clip(sand, 0, 1)
        pave = np.zeros_like(h)
        col = np.stack([dirt, rock, pave, sand], 1).astype(np.float32)
        return h, col

    return {"margin": 380.0, "cell": 4.0, "build": build, "layers": layers}


# set pieces on ground that terrain() levels for them, beside the road with their nose (+Z) to
# it: (model, stretch, lap metres, side, metres from the road's edge to the origin, footprint
# (x0, x1, z0, z1), how deep it sits in the ground, extra yaw): the Osprey landed by the camp,
# the wreck of another on the canyon floor inside the hairpin
PADS = [("hl1/osprey", "camp", 1216.0, 1, 13.0, (-14.9, 14.9, -11.8, 6.6), 0.0, 0.0),
        ("hl1/dead_osprey", "canyon", 382.0, -1, 18.0, (-8.3, 14.7, -11.7, 6.6), 1.2, 0.5)]


def _pad_sites(trk):
    """Where each of PADS stands: (model, origin, yaw, sample, footprint, depth). The sample is the
    one of its stretch nearest the given lap metres that keeps well clear of jumps."""
    out = []
    gaps = np.flatnonzero(trk.gap)
    for model, style, s, sgn, off, rect, sink, turn in PADS:
        ok = [i for i in range(trk.n) if trk.style[i] == style and (not len(gaps) or np.abs(gaps - i).min() > 25)]
        if not ok:
            continue
        i = min(ok, key=lambda k: abs(trk.s[k] - s))
        rf = trk.flat_right[i] * sgn
        out.append((model, trk.pos[i] + rf * (trk.width[i] / 2 + off), math.atan2(-rf[0], -rf[2]) + turn, i, rect, sink))
    return out


def cactus(ctx, base, height, rng, mats):
    """A saguaro: trunk and two arms in the HL1 cactus texture; the trunk collides."""
    tex = mats.goldsrc("out_cac1")
    r = 0.42 * height / 6.0
    ctx.cylinder(tex, base, r, height, segs=10, kind="walls", rep=1.5)
    a = rng.uniform(0, 2 * math.pi)
    for side in (-1, 1):
        d = np.array([math.cos(a), 0.0, math.sin(a)]) * side
        y0 = rng.uniform(0.35, 0.55) * height
        elbow = np.asarray(base, float) + UP * y0 + d * (r + 0.7)
        # the horizontal stub, then the arm going up (decoration only)
        ctx.box(tex, np.asarray(base, float) + UP * y0 + d * (r * 0.5 + 0.35), [r * 1.6, r * 1.6, 1.4 * 0.9],
                math.atan2(d[0], d[2]), kind="deco", rep=1.5)
        ctx.cylinder(tex, elbow, r * 0.75, rng.uniform(0.3, 0.45) * height, segs=8, kind="deco", rep=1.5)


def _on_ground(ctx, i, sgn, dist, model, yaw, tol=0.5):
    """A spot `dist` metres past the road edge whose ground is level under the whole model, at
    least 10 samples from a jump: the point with its height, or None."""
    t = ctx.trk
    if any(t.gap[(i + k) % t.n] for k in range(-10, 11)):
        return None
    q = ctx.side(i, sgn, dist)
    g = ctx.site(model, q, yaw, tol=tol)
    if g is None:
        return None
    q[1] = g
    return q


def _flare(ctx, i, back, sgn, wide=2.5):
    """A guard rail in the railing that starts at sample i (a deck's at its edge, or an open road's
    rail out at its verge's edge), on the open road before it: from `wide` metres past the verge's
    outer edge `back` metres before (or from the foot of a slope rising a little further out, into
    it, leaving no gap a kart could wedge in) in to the railing's line, so a kart out wide is led in
    behind the railing instead of past its end (and off the deck, or down the bank)."""
    t = ctx.trk
    bar = t.styles[t.style[i]]["barrier"]
    n = int(round(back / t.step))
    j0 = t.wrap(i - n)
    vw = t.styles[t.style[j0]].get("verge_w", 0.0)
    thick = min(bar.get("thick", 0.1), 0.4)
    end = bar.get("off", 0.2) if t.kind(i) == "open" else 0.0
    rise = [d for d in np.arange(vw + wide, vw + wide + 5.5, 0.5)
            if ctx.ground(*ctx.side(j0, sgn, d)[[0, 2]]) > t.pos[j0][1] + 1.2]
    start = rise[0] + 0.5 if rise else vw + wide
    pts = []
    for k in range(n + 1):
        j = t.wrap(i - n + k)
        out = (start + thick - end) * (1.0 - k / n) + end + thick / 2
        pts.append(t.pos[j] + t.right[j] * sgn * t.width[j] / 2 + t.flat_right[j] * sgn * out)
    for a, b in zip(pts[:-1], pts[1:]):
        foot = min(ctx.ground(a[0], a[2]), ctx.ground(b[0], b[2]), a[1], b[1]) - 0.3
        top = max(a[1], b[1]) + bar.get("h", 1.2)
        along = b - a
        ctx.box(bar["mat"], [(a[0] + b[0]) / 2, (foot + top) / 2, (a[2] + b[2]) / 2],
                [thick, top - foot, math.hypot(along[0], along[2]) + 0.05], ctx.yaw_facing(along),
                rep=bar.get("rep", 3.0))


def decorate(ctx):
    t = ctx.trk
    g = ctx.mats.goldsrc
    rng = ctx.rng
    by = {}
    for i in range(t.n):
        by.setdefault(t.style[i], []).append(i)
    # guard rails flaring in from the verges onto the decks an open road runs onto (the gorge
    # bridge, the dam's crest; on the gorge's right from far out over the level sand, fencing it
    # off from the gorge for a kart that leaves the washout over it; over the cliff road's drop
    # from the verge's own edge: one standing out over the fall left a slot between it and the
    # cliff's edge that a kart thrown off the road dropped into and could not drive out of), and
    # into the river rail on the outside of the bend before the washout
    for style in ("gorge", "dam"):
        ids = by.get(style, [])
        if ids and t.kind(t.wrap(ids[0] - 1)) == "open":
            drop = t.styles[t.style[t.wrap(ids[0] - 1)]].get("drop", {}).get("side", 0)
            for sgn in (-1, 1):
                if style == "gorge" and sgn > 0:
                    _flare(ctx, ids[0], 60.0, sgn, wide=12.0)
                else:
                    _flare(ctx, ids[0], 40.0, sgn, wide=0.0 if sgn == drop else 2.5)
    if by.get("turnin"):
        _flare(ctx, by["turnin"][0], 30.0, 1)
    # the dam body under the crest road (its upstream face a metre into the lake, past the water's
    # edge), and lamps along it standing on the parapet, over the road
    dam = by.get("dam", [])
    if dam:
        a, b = t.pos[dam[0]], t.pos[dam[-1]]
        mid = (a + b) / 2
        length = np.linalg.norm(b - a) + 30.0
        yaw = math.atan2(b[0] - a[0], b[2] - a[2])
        top = mid[1] - 2.0
        ctx.box(ctx.mats.hl2("concrete/concretewall008a"), [mid[0], (top + RIVER_Y - 8.0) / 2, mid[2] - 8.0],
                [18.0, top - RIVER_Y + 8.0, length], yaw, kind="walls", rep=6.0)
        bar = t.styles["dam"]["barrier"]
        for k, i in enumerate(dam[4::14]):
            for sgn in (-1, 1):
                # on the wall's top over the deck's edge (lower on a bank's low side)
                q = (t.pos[i] + t.right[i] * sgn * t.width[i] / 2 + t.flat_right[i] * sgn * bar["thick"] / 2 +
                     UP * bar["h"])
                ctx.add("props_c17/lamppost03a_on", q, ctx.yaw_facing(t.flat_right[i] * sgn), ground=False)
        # the TURBINE board stands on the lake side's parapet, readable from both sides
        i = dam[len(dam) // 2]
        rf = -t.flat_right[i]
        c = ctx.side(i, -1, bar["thick"] / 2) + UP * (bar["h"] + 0.8)
        f, u = t.fwd[i] * 2.4, UP * 0.8
        q = [c - f - u, c + f - u, c + f + u, c - f + u]
        face(ctx.meshes["deco"], g("c2a5_sign1"), q, -rf, [[0, 1], [1, 1], [1, 0], [0, 0]])
        face(ctx.meshes["deco"], g("c2a5_sign1"), q, rf, [[1, 1], [0, 1], [0, 0], [1, 0]])
    # the Osprey on its pad by the camp, the wreck of another in the canyon
    for model, q, yaw, i, rect, sink in _pad_sites(t):
        q[1] = ctx.ground(q[0], q[2]) - sink
        ctx.add(model, q, yaw)
    # highway and mesa road: power poles and Black Mesa signs, clear of every road (the viaduct
    # and the loop run close by) and of the washed-out stretch's gully
    hw = sorted(by.get("highway", []) + by.get("start", []) + by.get("mesa", []) + by.get("approach", []))
    for k, i in enumerate(hw[::25]):
        q = ctx.side(i, 1, 9.0)
        if ctx.road_gap_to(q) < 3.0 or any(t.gap[t.wrap(i + d)] for d in range(-15, 16)):
            continue
        q[1] = ctx.ground(q[0], q[2])
        ctx.add("props_c17/utilitypole01a", q, ctx.yaw_facing(t.fwd[i]))
    for k, i in enumerate(hw[30::120]):
        q = ctx.side(i, -1, 7.0)
        if ctx.road_gap_to(q) < 4.0:
            continue
        q[1] = ctx.ground(q[0], q[2])
        sign = ["c2a5g_sign1", "c2a5_sign2", "c2a5w_sign"][k % 3]
        ctx.box(g(sign), q + UP * 3.4, [0.3, 2.4, 5.0], ctx.yaw_facing(t.fwd[i]), kind="deco", rep=5.0)
        for off in (-2.2, 2.2):
            # each post from just under the ground at its own foot up to the board
            p = q + t.fwd[i] * off
            lo, hi = ctx.ground(p[0], p[2]) - 0.3, q[1] + 2.4
            p[1] = (lo + hi) / 2
            ctx.box(ctx.mats.hl2("wood/woodbeam001a"), p, [0.25, hi - lo, 0.25], 0.0, kind="walls", rep=2.4)
    # the washed-out stretch: barricades and cones on both verges before the kicker
    for a, b in t.gaps:
        if t.style[a] != "mesa":
            continue
        for d, m in ((-14, "props_wasteland/barricade002a"), (-10, "props_junk/trafficcone001a"),
                     (-6, "props_junk/trafficcone001a")):
            i = t.wrap(a + d)
            for sgn in (-1, 1):
                q = ctx.side(i, sgn, t.styles["mesa"]["verge_w"] + 1.0)
                q[1] = ctx.ground(q[0], q[2])
                ctx.add(m, q, ctx.yaw_front(m, -t.flat_right[i] * sgn))
    # canyon: boulders fallen from its walls, at the foot of the slope (where the ground has risen
    # 2.5 m over the road, within 26 m of its edge), not out on the level where a kart that runs
    # wide meets them
    can = sorted(by.get("canyon", []) + by.get("turnin", []))
    for k, i in enumerate(can[::9]):
        sgn = 1 if k % 2 else -1
        rise = [ctx.ground(*ctx.side(i, sgn, d)[[0, 2]]) - t.pos[i][1] for d in np.arange(6.0, 26.0, 1.0)]
        foot = next((6.0 + d for d, r in enumerate(rise) if r > 2.5), None)
        yaw = rng.uniform(0, 6.28)
        if foot is None:
            continue
        q = ctx.side(i, sgn, foot + 1.5)
        q[1] = ctx.ground(q[0], q[2]) - 0.3
        ctx.add(["props_wasteland/rockgranite02a", "props_wasteland/rockgranite03a", "props_wasteland/rockcliff01b",
                 "props_wasteland/rockgranite01a"][k % 4], q, yaw)
    # HECU camp, on level ground past the verges (the marines are spectators: crowds()):
    # barricades along the road, stacks of crates a few metres on, now and then a floodlight
    camp = by.get("camp", [])
    if camp:
        vw = t.styles["camp"]["verge_w"]
        crate = "props_junk/wood_crate001a"
        for k, i in enumerate(camp[::12]):
            sgn = 1 if k % 2 else -1
            m = ["props_wasteland/barricade001a", "props_c17/concrete_barrier001a", "props_wasteland/barricade002a"][k % 3]
            q = _on_ground(ctx, i, sgn, vw + 1.0, m, ctx.yaw_facing(t.fwd[i]))
            if q is not None:
                ctx.add(m, q, ctx.yaw_facing(t.fwd[i]))
            j = t.wrap(i + 3)
            q3 = _on_ground(ctx, j, sgn, vw + rng.uniform(1.5, 2.5), crate, 0.3, tol=0.3)
            for lvl in range(1 + k % 2):
                if q3 is None or not ctx.add(crate, q3, 0.3, ground=False):
                    break
                q3 = q3 + UP * ctx.model_size(crate)[1]
            if k % 3 == 1:
                m = "props_c17/light_floodlight02_off"
                yaw = ctx.yaw_front(m, -t.flat_right[i] * sgn)
                q4 = _on_ground(ctx, t.wrap(i - 3), sgn, vw + 1.5, m, yaw, tol=0.6)
                if q4 is not None:
                    ctx.add(m, q4, yaw, ground=False)
            # a pair of oil drums by the crates
            for d_ in (0.0, 0.9):
                q5 = _on_ground(ctx, t.wrap(i + 5), sgn, vw + 1.2 + d_, "props_c17/oildrum001", 0.0, tol=0.3)
                if q5 is not None:
                    ctx.add("props_c17/oildrum001", q5 + t.fwd[i] * d_ * 0.6, rng.uniform(0, 6.28), ground=False)
    # an Apache far over the gorge, unless the hazard's own is about (one helicopter at a time)
    gor = by.get("gorge", [])
    if gor and not any(h["type"] == "apache" for h in TRACK.get("hazards", [])):
        mid = t.pos[gor[len(gor) // 2]]
        ctx.add("hl1/apache", [mid[0] + 60.0, mid[1] + 70.0, mid[2] - 120.0], 2.4, ground=False, tag="far", base=False)
    # saguaros all over the desert, last so they keep out of everything placed above, and clear
    # of the verges by a run-off (a solid trunk there catches every kart that runs wide): 24 m
    # where the ground lies level with the nearest road (a kart drives on into it), 6 m up a slope
    # or down a drop; each trunk goes down to the lowest ground round it
    placed = 0
    for k in range(3000):
        i = int(rng.integers(0, t.n))
        if t.kind(i) in ("tunnel", "bridge", "tube"):
            continue
        sgn = 1 if rng.random() < 0.5 else -1
        q = ctx.side(i, sgn, rng.uniform(6.0, 70.0))
        height = rng.uniform(4.5, 8.5)
        r = 0.42 * height / 6.0
        ring = [ctx.ground(q[0] + math.cos(a) * r, q[2] + math.sin(a) * r) for a in np.linspace(0, 2 * math.pi, 8, False)]
        gq = ctx.ground(q[0], q[2])
        edge = np.hypot(*(ctx.roads.pos[:, [0, 2]] - q[[0, 2]]).T) - ctx.roads.width / 2
        j = int(np.argmin(edge))
        run_off = t.styles[t.style[i]].get("verge_w", 0.0) + (24.0 if abs(gq - ctx.roads.pos[j][1]) < 3.0 else 6.0)
        if edge[j] < run_off or abs(gq - t.pos[i][1]) > 14.0 or gq < RIVER_Y + 2.0:
            continue
        # no saguaro on a slope steeper than 0.8, nor through a prop
        if (max(ring) - min(ring)) / (2 * r) > 0.8 or not ctx.free(q + UP * height / 2, [r * 2 + 3.0, height, r * 2 + 3.0]):
            continue
        q[1] = min(ring) - 0.3
        cactus(ctx, q, height, rng, ctx.mats)
        placed += 1
        if placed > 110:
            break


def decorate_branch(ctx, spec):
    """The rim road: boulders along its mesa side, out of reach of a kart that cuts the bends over
    the level mesa top (nothing on the canyon side: no rail). The washout: cones along the run-up
    to its kicker and broken barriers beside both ends of the gap, where the old road fell into
    the river."""
    t = ctx.trk
    rng = ctx.rng
    if spec["id"] == "rim_drop":
        rocks = ["props_wasteland/rockgranite02a", "props_wasteland/rockgranite03a", "props_wasteland/rockcliff01b"]
        for k, i in enumerate(range(8, t.n, 12)):
            if t.gap[i] or t.side_off[i, 0]:
                continue
            q = ctx.side(i, -1, RIM_VERGE + rng.uniform(13.0, 19.0))
            q[1] = ctx.ground(q[0], q[2]) - 0.3
            ctx.add(rocks[k % 3], q, rng.uniform(0, 6.28))
    elif spec["id"] == "washout":
        vw = t.styles["ramp"]["verge_w"]
        ramp = [i for i in range(t.n) if t.style[i] == "ramp" and not t.gap[i]]
        for i in ramp[::3]:
            for sgn in (-1, 1):
                q = t.surface(i, sgn * (t.width[i] / 2 + vw * 0.6), 0.02)
                ctx.add("props_junk/trafficcone001a", q, rng.uniform(0, 6.28), physics=True, ground=False)
        bar = "props_c17/concrete_barrier001a"
        for a, b in t.gaps:
            for i, back in ((a - 3, -1.0), (b + 2, 1.0)):
                for sgn in (-1, 1):
                    # (out past the rail at the verge's edge)
                    q = ctx.side(i, sgn, vw + 1.6)
                    yaw = ctx.yaw_front(bar, t.fwd[i]) + rng.uniform(-0.5, 0.5)
                    g = ctx.site(bar, q, yaw, tol=0.6)
                    if g is not None:
                        q[1] = g - 0.1
                        ctx.add(bar, q, yaw)


def _open(ctx, i):
    t = ctx.trk
    return t.kind(i) == "open" and not t.gap[i] and not t.pit[i]


START = (-60.0, 40.0)  # lap metres of the start's rally crowd


def crowds(ctx):
    """Black Mesa's survivors and the HECU (crowds design 5.4): a rally crowd of scientists and
    guards at the start, little groups stranded on the canyon's shoulders and floor, both sides
    of the jump landings (marines in the camp), the marines along the camp, a few on the cliff
    road's inner side and the eggs."""
    t = ctx.trk
    rng = ctx.crowd_rng
    # the start: a rally crowd either side of the highway, the front row ready to jump back
    for sgn in (-1, 1):
        ids = [i for i in ctx.lap_ids(*START) if _open(ctx, i)]
        for ch in ctx.chunks(ids, int(34 / t.step), int(34 / t.step)):
            gid = ctx.crowd_group(ch[len(ch) // 2], sgn, "line", "scientist", tags=["start"])
            for role, lo, hi, every, dodge in (("scientist", 2.5, 3.5, 2.0, True), ("guard", 2.5, 3.5, 10.0, True),
                                               ("scientist", 4.0, 5.5, 2.0, False)):
                ctx.crowd_line(gid, ch, sgn, every, lambda i, s, a=lo, b=hi: ctx.shoulder_spot(i, s, a, b), role,
                               mood="excited" if dodge else "fan", chance=0.8, dodge=dodge, dy=(-1.5, 3.0))
    # the canyon: little groups on the shoulders where the ground is level with the road
    canyon = [i for i in range(t.n) if _open(ctx, i) and t.style[i] in ("canyon", "turnin")]
    for i in canyon[6::max(1, len(canyon) // 12)]:
        sgn = 1 if rng.random() < 0.5 else -1
        c = ctx.shoulder_spot(i, sgn, 2.0, 5.0)
        gid = ctx.crowd_group(i, sgn, "cluster", "scientist", tags=["canyon"])
        ctx.crowd_cluster(gid, c, int(rng.integers(3, 6)), 2.5, "scientist", t.pos[i] + UP,
                          mood=["fan", "polite"][int(rng.integers(0, 2))], ref_y=t.pos[i][1], dy=(-0.5, 3.0),
                          margin=5.0)
    # jump landings: 28 m past the gaps, both sides (marines in the camp)
    for a, b in t.gaps:
        i = (b + int(28 / t.step)) % t.n
        if not _open(ctx, i):
            continue
        role = "hecu" if t.style[i] == "camp" else "scientist"
        for sgn in (-1, 1):
            gid = ctx.crowd_group(i, sgn, "cluster", role, tags=["jump"])
            ctx.crowd_cluster(gid, ctx.shoulder_spot(i, sgn, 3.0, 4.5), 8, 3.5, role, t.pos[i] + UP,
                              mood="excited" if role == "scientist" else "military", ref_y=t.pos[i][1], dy=(-1.0, 3.0),
                              margin=4.0)
    # the HECU camp: marines by the barricades and crates
    camp = [i for i in range(t.n) if t.style[i] == "camp" and not t.gap[i]]
    for sgn in (-1, 1):
        for ch in ctx.chunks(camp, int(60 / t.step), int(60 / t.step)):
            gid = ctx.crowd_group(ch[len(ch) // 2], sgn, "post", "hecu", tags=["camp"], bed="")
            ctx.crowd_line(gid, ch, sgn, 5.0, lambda i, s: ctx.shoulder_spot(i, s, 1.5, 6.0), "hecu", mood="military",
                           chance=0.9, dy=(-1.5, 3.5))
    # the cliff road: a few people on the inner side only (the other side is the drop)
    cliff = [i for i in range(t.n) if t.style[i] in ("cliff", "cliffrail") and not t.gap[i]]
    inner = -t.styles["cliff"]["drop"]["side"]
    for ch in ctx.chunks(cliff, int(50 / t.step), int(6 / t.step)):
        i = ch[len(ch) // 2]
        gid = ctx.crowd_group(i, inner, "cluster", "scientist", tags=["cliff"])
        ctx.crowd_cluster(gid, ctx.shoulder_spot(i, inner, 2.0, 4.0), 3, 2.5, "scientist", t.pos[i] + UP,
                          ref_y=t.pos[i][1], dy=(-0.5, 3.0), margin=4.0)
    eggs(ctx)
    _feet_on_faces(ctx)


def crowds_branch(ctx, spec):
    """On the branches (their own metres): scientists on the mesa top watching the karts launch
    off the rim, and both banks of the washout's landing lined with survivors and a guard."""
    t = ctx.trk
    for a, b in t.gaps:
        if spec["id"] == "rim_drop":
            i = max(a - int(22 / t.step), 0)
            gid = ctx.crowd_group(i, -1, "cluster", "scientist", tags=["jump"], watch=[t.s[i] - 10.0, t.s[b - 1]])
            ctx.crowd_cluster(gid, ctx.side_point(i, -1, RIM_VERGE + 6.0), 7, 3.5, "scientist", t.pos[a] + UP,
                              mood="excited", ref_y=t.pos[i][1], dy=(-1.0, 2.5), margin=5.0)
        else:
            i = min(b + int(18 / t.step), t.n - 1)
            for sgn in (-1, 1):
                gid = ctx.crowd_group(i, sgn, "cluster", "scientist", tags=["jump"],
                                      watch=[t.s[a] - 20.0, t.s[i] + 10.0])
                ctx.crowd_cluster(gid, ctx.shoulder_spot(i, sgn, 2.5, 4.5), 6, 3.0, "scientist", t.pos[b] + UP,
                                  mood="excited", ref_y=t.pos[i][1], dy=(-1.5, 2.5), margin=4.0)
                ctx.crowd_cluster(gid, ctx.shoulder_spot(i, sgn, 3.0, 5.0), 1, 2.0, "guard", t.pos[b] + UP,
                                  mood="excited", ref_y=t.pos[i][1], dy=(-1.5, 2.5), margin=4.0)
    _feet_on_faces(ctx)


def _feet_on_faces(ctx):
    """Everyone placed so far on the ground, and the G-Man, stands on the terrain's own faces (the
    triangles the game draws and collides with), not on the height field's smooth surface: on a
    twisted grid cell up the canyon's slopes the two part by a few decimetres, burying feet or
    floating them. A spectator on a cell where they part by more than 0.3 m is left out."""
    f = ctx.field

    def faces(p):
        i = min(max((p[0] - f.xs[0]) / f.cell, 0.0), f.nx - 1.001)
        j = min(max((p[2] - f.zs[0]) / f.cell, 0.0), f.nz - 1.001)
        i0, j0 = int(i), int(j)
        fx, fz = i - i0, j - j0
        a, b, c, d = f.H[j0, i0], f.H[j0, i0 + 1], f.H[j0 + 1, i0], f.H[j0 + 1, i0 + 1]
        # (the faces split each cell along its b-c diagonal: terrain_mesh)
        return float(a + fx * (b - a) + fz * (c - a) if fx + fz <= 1.0 else d + (1 - fx) * (c - d) + (1 - fz) * (b - d))

    keep = []
    for m in ctx.crowds:
        if m["_on"] == "ground":
            y = faces(m["pos"])
            if abs(y - ctx.ground(m["pos"][0], m["pos"][2])) > 0.3:
                continue
            m["pos"][1] = round(y, 3)
        keep.append(m)
    ctx.crowds[:] = keep
    for e in ctx.crowd_eggs:
        if e["kind"] == "gman":
            e["pos"][1] = round(faces(e["pos"]), 3)


def eggs(ctx):
    t = ctx.trk
    rng = ctx.crowd_rng
    # the G-Man (HL1) on the canyon's floor inside the bend before the washout, where the chase
    # camera coming along the canyon sees him longest (clear of the zombies by the wreck in the
    # hairpin)
    g = ctx.gman_spot(520.0, 720.0)
    if g is not None:
        ctx.egg("gman", pos=g["pos"], yaw=g["yaw"], s=g["s"], model="hl1/gman", window=g["window"], chance=0.4)
    # boids circling over the canyon, over open ground (no road under their circle's centre)
    canyon = [i for i in range(t.n) if t.style[i] in ("canyon", "turnin") and not t.gap[i]]
    for i in canyon[len(canyon) // 4::max(1, len(canyon) // 2)][:2]:
        sgn = 1 if rng.random() < 0.5 else -1
        spots = [ctx.side_point(i, s, d) for d in (25.0, 35.0, 45.0) for s in (sgn, -sgn)]
        c = next((q for q in spots if ctx.road_gap_xz(q) > 8.0), None)
        if c is not None:
            ctx.egg("birds", species="boid", center=c, radius=18.0, count=6)
    # two zombies loose on the canyon floor inside the hairpin, by the wrecked Osprey (the
    # scientists there scream)
    for model, q, yaw, i, rect, sink in _pad_sites(t):
        if model == "hl1/dead_osprey":
            fw = t.fwd[i] * np.array([1.0, 0.0, 1.0])
            fw /= np.linalg.norm(fw)
            path = [q + fw * d - t.flat_right[i] * 4.0 for d in (-20.0, -8.0, 4.0)]
            for p in path:
                p[1] = ctx.ground(p[0], p[2])
            ctx.egg("zombies", path=path, count=2, model="hl1/zombie")
    # Gnome Chompski among the HECU camp's crates (or behind its barricades)
    camp = [i for i in range(t.n) if t.style[i] == "camp" and not t.gap[i]]
    if camp and not _gnome_on_crate(ctx, t.pos[camp[len(camp) // 2]], 80.0):
        i = camp[len(camp) // 3]
        q = ctx.ground_spot(ctx.side_point(i, -1, 9.0), 0.0, 5.0, t.pos[i][1] - 1.0, t.pos[i][1] + 2.0, margin=6.0,
                            tries=120)
        if q is not None:
            ctx.egg("gnome", pos=q, yaw=math.atan2(*(t.pos[i] - q)[[0, 2]]))


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
