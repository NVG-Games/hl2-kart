"""Xen: floating islands in the border world, a figure-8 of about 2.4 km in the void.

Start on the island with the healing pool and cross the low root bridge. The east lobe runs
counter-clockwise: the glowing cave that rolls once round, the fungus islands climbing north,
the crystal plateau and its chasm, the rail-less ledge down to the arch, which passes 13 m over
the root bridge. The west lobe runs clockwise round the bay, a big square of void, and back up
the long bridge to the start.

Two branches: the high root leaves the plateau right after the chasm for a narrow rail-less root
over the void that drops onto a deck joining the arch; the island hop leaves the bay's east side
and crosses it over two floating rocks, two hops over the void, onto the long bridge.
"""
import math

import numpy as np

from crowds import LOD_CYCLE
from track_gen import UP, carve, noise2, smoothstep

VOID = -75.0
# metres of wide island past a jump of the lap (see terrain)
LANDING = 110.0

CTRL = [
    (0, 20, 0, 18, "island"),
    (90, 20, -6, 18, "island"),
    (165, 18, 4, 17, "island"),
    # the root bridge: the low pass of the figure-8
    (215, 15, 22, 13, "bridge"),
    (262, 14, 36, 13, "bridge"),
    (318, 15, 50, 17, "island"),
    (368, 15.5, 64, 15, "cave"),
    (436, 16.5, 62, 15, "cave"),
    (488, 17.5, 34, 18, "island"),
    (512, 19, -36, 18, "island"),
    (502, 22, -110, 17, "island"),
    (462, 28, -186, 17, "island"),
    # the crystal plateau and its chasm
    # (straight from the kicker to well past the landing: a kart flies on where the road goes. 12 m
    # across and a steep kicker: a kart still slow from a spin clears it at 16 m/s)
    (430, 30, -214, 17, "island", {"gap": True, "gap_span": (0.40, 0.556), "ramp_lift": 2.4}),
    (372, 31, -233, 17, "island"),
    (304, 31, -246, 17, "island"),
    (226, 30, -234, 17, "island"),
    (198, 29.5, -176, 17, "island"),
    (204, 29, -138, 12, "ledge"),
    (221, 28, -90, 12, "ledge"),
    # the arch: the high pass, 13 m over the root bridge
    (240, 27, -20, 13, "arch"),
    (246, 27, 40, 13, "arch"),
    # the bay: down its east side, along the bottom, up the long bridge on its west side
    (252, 23, 104, 17, "island"),
    (250, 19, 176, 17, "island"),
    (232, 15, 236, 17, "island"),
    (180, 12, 266, 18, "island"),
    (100, 10, 274, 18, "island"),
    (16, 9, 272, 18, "island"),
    (-48, 10, 250, 13, "bridge"),
    (-84, 11.5, 196, 13, "bridge"),
    (-96, 13, 140, 13, "bridge"),
    (-90, 16, 84, 17, "island"),
    (-60, 20, 20, 18, "island"),
]
CTRL = [c if len(c) > 5 else c + ({},) for c in CTRL]
K = 1.16  # plan scale of the layout above
CTRL = [(c[0] * K, c[1], c[2] * K) + tuple(c[3:]) for c in CTRL]

# each branch leaves on an arc, runs straight and joins on an arc (the control points lie on them).
# The island hop's kickers want 25 m/s at each lip: flat out it is easy, slowed by a hit or a bump
# it is the void (and on EASY's 27 m/s top it takes everything a kart has). Their ramps are long for
# their height: on a 16 m one a heavy kart at full speed sank onto its chassis 4 m before the lip and
# was flipped back over it
HOP = {"gap": True, "gap_span": (0.2, 0.9), "ramp_lift": 2.8, "ramp_len": 26}
BRANCHES = [
    # across the bay: off its east side to the right, over two floating rocks, onto the long bridge
    # (where it still lies on the lap, at the fork and at the merge, its heights are the lap's)
    {"id": "island_hop", "name": "Island hop", "fork": (252.8 * K, 132.5 * K), "merge": (-96.3 * K, 130.5 * K),
     "kind": "jump",
     "ctrl": [(248.8 * K, 20.68, 146.2 * K, 11, "rock"), (244.4 * K, 19.95, 159.1 * K, 11, "rock"),
              (237.2 * K, 19.2, 170.7 * K, 11, "rock"), (227.6 * K, 18.4, 180.4 * K, 11, "rock"),
              (216 * K, 17.7, 187.7 * K, 11, "rock"), (203.1 * K, 17.0, 192.2 * K, 11, "rock"),
              (190.3 * K, 16.3, 193.6 * K, 11, "rock"), (164.5 * K, 15.5, 193.8 * K, 11, "rock", HOP),
              (138.6 * K, 15.2, 194 * K, 11, "rock"), (112.7 * K, 15.2, 194.2 * K, 11, "rock"),
              (86.9 * K, 15.2, 194.4 * K, 11, "rock"), (61 * K, 15, 194.6 * K, 11, "rock", HOP),
              (35.2 * K, 14.8, 194.7 * K, 11, "rock"), (9.3 * K, 14.6, 194.9 * K, 11, "rock"),
              (-16.6 * K, 14.3, 195.1 * K, 11, "rock"), (-34.7 * K, 14.0, 195.2 * K, 11, "rock"),
              (-48.3 * K, 13.6, 193.8 * K, 11, "rock"), (-61.2 * K, 13.05, 189.3 * K, 11, "bridge"),
              (-72.8 * K, 12.3, 182 * K, 11, "bridge"), (-82.4 * K, 12.01, 172.3 * K, 11, "bridge"),
              (-89.6 * K, 12.32, 160.7 * K, 11, "bridge"), (-94.1 * K, 12.71, 147.8 * K, 11, "bridge")],
     # (a retry after a fall starts 50 m before the hop: its kicker climbs 2.8 m, and from a
     # standstill 45 m of run-up came within 0.05 m/s of the speed a retry must reach)
     "risk": 0.6, "ai": {"take": 0.6, "min_skill": 0.8}, "offtrack": 20.0, "retry_back": 50.0},
    # stay up after the chasm: a hard left across a rock off the plateau (the bend on firm ground),
    # then a rail-less root over the void straight down the middle of the east lobe, and a drop onto
    # a deck that joins the arch
    {"id": "high_root", "name": "High root", "fork": (306.7 * K, -245.9 * K), "merge": (240.3 * K, -18.5 * K),
     "kind": "ledge",
     "ctrl": [(280.1 * K, 30.88, -230.6 * K, 9, "rock"), (272.8 * K, 31.5, -215.2 * K, 9, "root"),
              (267.3 * K, 32, -186.4 * K, 9, "root"),
              (261.8 * K, 32.5, -157.6 * K, 9, "root", {"gap": True, "gap_span": (0.45, 0.85), "ramp_lift": 1.6}),
              (256.3 * K, 28.4, -128.8 * K, 11, "arch"), (250.8 * K, 28.1, -100 * K, 11, "arch"),
              (245.3 * K, 27.8, -71.2 * K, 11, "arch"), (241.2 * K, 27.31, -50.1 * K, 11, "arch")],
     "items": [0.4], "risk": 0.7, "ai": {"take": 0.55, "min_skill": 0.82}},
]

TRACK = {
    "id": "xen",
    "music": ['hl1_song3', 'hl1_song5', 'hl1_song6', 'hl1_song9', 'hl1_song19'],
    "name": "Xen",
    "ctrl": CTRL,
    # (the plateau's row comes early: what it hands out is used on the wide plateau, not in the
    # bend onto the rail-less ledge, where a gravity gun's punt threw karts into the void; the row
    # before the chasm comes 200 m before its kicker, so less of what it hands out is fired at
    # karts on the run-up)
    "items": [0.055, 0.17, 0.30, 0.455, 0.63, 0.71, 0.79, 0.87, 0.955],
    "boosts": [0.025, 0.115, 0.18, 0.26, 0.37, 0.53, 0.61, 0.74, 0.82, 0.93],
    "vmax": 38.0,
    "offtrack": 40.0,
    "kill_y": -25.0,
    # the game's gravity (project.godot): the launch speeds the branches export are the real ones
    "gravity": 15.24,
    "sky": "hl1_xen8",
    "background": "none",
    "gantry": "xen",
    # the start line's pillars stand past the verge karts run on
    "gantry_clear": 5.0,
    "env": {"sun_energy": 1.1, "sun_color": [0.75, 1.0, 0.8], "sun_dir": [0.3, 0.8, 0.45],
            "ambient": [0.5, 0.42, 0.62], "ambient_energy": 1.15, "fog_color": [0.32, 0.2, 0.42],
            "fog_begin": 220.0, "fog_end": 1700.0, "fog_sky": 0.0, "exposure": 1.1, "glow": 0.7, "sdfgi": False},
    # lap metres, clear of the junctions: the alien slaves at the far end of the crystal plateau, the
    # tentacle 28 m before the end of the long walled bridge. The houndeye packs sit on the inside
    # of a long bend on the climbing island after the cave and in the bay, where the racing line
    # passes them: they notice a kart 45 m off, so their blast comes as it arrives, and a kart that
    # heeds the chirp and the charge-up and moves to the far side is out of reach
    "hazards": [
        {"type": "houndeyes", "s": 690, "side": -1, "setback": 2.5, "count": 3, "radius": 13.0, "notice": 45.0},
        {"type": "vortigaunt", "s": 1140, "side": 1, "setback": 2.0, "zone": [1102, 1145]},
        {"type": "vortigaunt", "s": 1200, "side": -1, "setback": 2.0, "zone": [1160, 1205]},
        {"type": "houndeyes", "s": 1760, "side": 1, "setback": 2.5, "count": 3, "radius": 13.0, "notice": 45.0},
        # a tentacle rises out of the void beside the walled bridge and slams across the racing line
        {"type": "tentacle", "s": 2246, "side": 1, "out": 4.0, "depth": 24.0, "reach": 0.2, "scale": 1.5},
    ],
}


def styles(m):
    g = m.goldsrc
    road = g("xeno_6flr")
    # where a branch leaves or joins: a gore of pebbled ground (nothing a boost pad's glow could be
    # taken for) and a glowing fungus at its nose: on an island just past the nose, out of the gore
    # a kart cuts across to the other road; at a deck's nose on the gore's wide end (past it there is
    # no floor). Like all small Xen growth a kart that cuts it close drives through it: a solid
    # crystal there pinned karts that left their choice of road late
    cushion = {"model": "hl1/fungus_small", "scale": 2.0, "sink": 0.1, "light": [1.0, 0.65, 0.3]}
    junction = {"gore_mat": g("xeno_13c"), "cushion": cushion}
    over_void = {"gore_mat": g("xeno_13c"), "cushion": dict(cushion, at="gore")}
    # (a hit throws a kart higher than the walls stand: unseen, they stop it up to 3 m)
    wall = {"kind": "wall", "mat": g("xeno_8w1"), "h": 0.9, "thick": 0.6, "rep": 2.5, "col_h": 3.0}
    # a deck's jump faces go no deeper than its skirt
    deck = {"kind": "bridge", "road": g("xeno_6flr2"), "road_rep": 5.0, "skirt": g("xeno_6aw1"), "skirt_h": 3.0,
            "pillar_every": 1e9, "gap_face_max": 3.0}
    return {
        # (a jump's faces and the skirts under the verges are rock, like the cliffs)
        "island": dict(junction, kind="open", road=road, road_rep=5.0, verge=g("xeno_16b"), verge_w=5.0,
                       skirt=g("c4a1a_swmpwl")),
        "bridge": dict(deck, barrier=wall, **over_void),
        # the bridge up to the crystal fields has no railings, only a low rim of rock: a kart that
        # slides at it stays on, one thrown over it falls into the void
        "ledge": dict(deck, pit=True, barrier={"kind": "wall", "mat": g("c4a1a_swmpwl"), "h": 0.6, "thick": 0.8,
                                               "rep": 2.5}, **over_void),
        # the high root has not even that: drive straight or fall
        "root": dict(deck, pit=True, **over_void),
        "arch": dict(deck, barrier=wall, **over_void),
        # the floating rocks a branch hops across: small islands of their own
        "rock": {"kind": "open", "road": road, "road_rep": 5.0, "verge": g("xeno_16b"), "verge_w": 3.0, "pit": True,
                 "skirt": g("c4a1a_swmpwl"), "island_r": (18.0, 30.0)},
        # the cave is a living tube floating over the void: the road rolls once all the way round
        # (its lane is back at the bottom 40 m before the exit, so karts leave it upright)
        "cave": {"kind": "tube", "road": g("xeno_6flr2"), "road_rep": 5.0, "wall": g("xeno_6a"),
                 "skin": g("xeno_14"), "glow": g("crys_2top", glow=True), "radius": 12.0, "roll": 360.0,
                 "settle": 14.0, "ring_every": 16.0, "light_color": [0.55, 1.0, 0.65], "light_energy": 1.6},
    }


def STARTLINE(m):
    return m.goldsrc("crys_2top", glow=True)


def _pool_site(trk):
    """Centre of the healing pool beside the start straight, 24 m off the left edge of the road,
    and the height of the level ground the terrain makes for it."""
    i = int(0.04 * trk.n)
    c = trk.pos[i] - trk.flat_right[i] * (trk.width[i] / 2 + 24.0)
    return c, trk.pos[i][1] - 0.35


def terrain(trk, m):
    g = m.goldsrc
    layers = {"base": g("xeno_14"), "dirt": g("xeno_16a"), "rock": g("c4a1a_swmpwl"), "pave": g("xeno_13e"),
              "sand": g("xeno_21")}

    def build(f, trk):
        P = f.P
        land = np.array([(trk.kind(i) in ("open", "tunnel")) and not trk.gap[i] for i in range(trk.n)])
        # (a branch's deck still lying on the lap at its fork or merge is no void: the island goes on
        # under the lap's road and verge there)
        void = np.array([(trk.gap[i] or trk.kind(i) in ("bridge", "tube")) and not (trk.route[i] > 0 and trk.junction[i])
                         for i in range(trk.n)])
        d_void = f.dist_to(trk, void)
        # each island reaches 28..62 m from its road, a little less toward a chasm, but always
        # carries its own road and verges right up to where a bridge, the cave or a jump begins.
        # A style's "island_r" (r0, r1) makes rocks instead (the floating rocks a branch hops
        # across, see _rock). Islands and rocks stop short of each other as they do of the void,
        # so the rocks float apart from the islands of the lap
        noise = noise2(P[:, 0] / 70.0, P[:, 1] / 70.0, 9)
        sizes = {trk.styles[s].get("island_r") for s in trk.style}
        groups = []
        for size in sorted(sizes, key=str):
            mask = land & np.array([trk.styles[s].get("island_r") == size for s in trk.style])
            if mask.any():
                groups.append((size, mask, f.dist_to(trk, mask)))
        member = np.zeros(len(P))
        for size, mask, d_land in groups:
            d_other = np.full(len(P), 1e9)
            for size2, _, d2 in groups:
                if size2 != size:
                    d_other = np.minimum(d_other, d2)
            # a void of 9 m or more between island and rock, unless their roads are close (a
            # junction: there the land is one)
            apart = np.maximum(smoothstep(10.0, 22.0, d_other - d_land + 4.0), smoothstep(55.0, 40.0, d_other + d_land))
            if size is None:
                edge = 24.0 + noise * 30.0
                m_ = smoothstep(edge + 6.0, edge - 6.0, d_land) * smoothstep(6.0, 18.0, d_void - d_land + 4.0)
                # the road and its verges always on land, which ends a few metres past the last of
                # them under a deck or the cave (they leave the island's edge instead of resting on a
                # slope of ground under them)
                m_ = np.maximum(m_, smoothstep(22.0, 16.0, d_land) * smoothstep(-2.0, 6.0, d_void - d_land + 8.0))
            else:
                m_ = _rock(f, trk, mask, size) * smoothstep(0.0, 6.0, d_void - d_land + 3.0)
            member = np.maximum(member, m_ * apart)
        # past the lap's chasm the landing island reaches 30 m beyond the road edge on both sides,
        # 60 m on the outside of the bend that follows, narrowing back over the last 30 of its 110 m
        # (to the high root's fork): a kart that leaves the kicker crooked, or is thrown wide in the
        # bend after it, still comes down on land (one still tumbling from a hit when it reaches the
        # kicker flies on straight and comes down 50-60 m out, past the bend)
        lap = trk.main
        wide = np.zeros(trk.n)
        outside = np.zeros(trk.n)
        for a, b in lap.gaps:
            ids = [lap.wrap(b + k) for k in range(int(LANDING / lap.step))]
            outside[ids] = -np.sign(np.mean(lap.curv[ids]))
            for k, i in enumerate(ids):
                wide[i] = 30.0 * (1.0 - smoothstep(LANDING - 30.0, LANDING, k * lap.step))
        w = wide[f.near] * np.where(np.sign(f.lat) == outside[f.near], 2.0, 1.0)
        member = np.maximum(member, (w > 0.0) * smoothstep(f.half + w + 8.0, f.half + w, f.dist))
        # and beside any open road its verge and a grid cell past it are land, however close a deck
        # leaving it runs (a branch's beyond its fork)
        member = np.maximum(member, _verges(f, trk, land))
        # level ground for the healing pool (all of it, and the grid cells round its rim), with island
        # all round it
        c, py = _pool_site(trk.main)
        d_pool = np.hypot(P[:, 0] - c[0], P[:, 1] - c[2])
        pool = smoothstep(18.0, 13.0, d_pool)
        member = np.maximum(member, smoothstep(30.0, 22.0, d_pool))
        hills = (noise2(P[:, 0] / 55.0, P[:, 1] / 55.0, 3) - 0.35) * 22.0
        hills *= smoothstep(f.half + 10.0, f.half + 45.0, f.dist)
        # (the chasm's landing stays low: a kart thrown far out comes down on gently rolling ground,
        # not against a hillside)
        hills = np.where(w > 0.0, np.minimum(hills, 1.5), hills)
        top = f.road_h - 0.35 + np.maximum(hills, -2.0)
        nat = top * member + VOID * (1.0 - member)
        h = carve(f, nat, trk, flat=7.0, blend=18.0, gap_floor=VOID)
        # off the islands nothing rises out of the void: no fins of ground beside a bridge, the
        # cave or a jump, where the carve's shoulders would otherwise reach
        keep = smoothstep(0.3, 0.7, member)
        h = h * keep + np.minimum(h, nat) * (1.0 - keep)
        # nor under the cave once its mouth has rounded: there it floats free of its islands
        h = np.where(_under_pipe(f, trk), np.minimum(h, VOID), h)
        # and a jump cuts clean through its island: no ledge of half-dug ground at the chasm's ends
        h = np.where(f.gap, np.minimum(h, VOID), h)
        h = h * (1 - pool) + py * pool
        Hm = h.reshape(f.nz, f.nx)
        gz, gx = np.gradient(Hm, f.cell)
        slope = np.sqrt(gx ** 2 + gz ** 2).ravel()
        rock = smoothstep(0.5, 1.1, slope)
        dirt = smoothstep(f.half + 9.0, f.half + 1.0, f.dist) * (1 - rock)
        pave = np.clip((noise2(P[:, 0] / 30.0, P[:, 1] / 30.0, 21) - 0.55) * 3.0, 0, 1) * (1 - rock) * (1 - dirt)
        sand = np.clip((noise2(P[:, 0] / 45.0, P[:, 1] / 45.0, 33) - 0.6) * 3.0, 0, 1) * (1 - rock)
        col = np.stack([dirt, rock, pave, sand], 1).astype(np.float32)
        return h, col

    # the islands' cliffs end 15 m above the void floor, cut along their own smooth contour
    return {"margin": 140.0, "cell": 4.0, "build": build, "layers": layers, "void": VOID + 15.0}


def _verges(f, trk, mask):
    """1 on the cells under the road samples `mask`, their verges and a cell past them (so the ground
    under a verge's edge is the verge's, not half a cliff), fading out over the next two metres:
    each sample's own cross-section, so nothing reaches past the end of an island's road into a
    jump. Where the road runs on onto a deck or into the cave, the land reaches a cell under it."""
    out = np.zeros(len(f.P))
    for i in np.flatnonzero(mask):
        reach = trk.width[i] / 2 + trk.styles[trk.style[i]].get("verge_w", 4.5) + f.cell
        c = trk.base[i, [0, 2]]
        i0, i1 = np.searchsorted(f.xs, [c[0] - reach - 8.0, c[0] + reach + 8.0])
        j0, j1 = np.searchsorted(f.zs, [c[1] - reach - 8.0, c[1] + reach + 8.0])
        sub = (np.arange(j0, j1)[:, None] * f.nx + np.arange(i0, i1)[None, :]).ravel()
        d = f.P[sub] - c
        fw = trk.fwd[i, [0, 2]] / np.linalg.norm(trk.fwd[i, [0, 2]])
        road = trk.trks[int(trk.route[i])]
        ext = []
        for k in (int(trk.ridx[i]) - 1, int(trk.ridx[i]) + 1):
            on = road.closed or 0 <= k < road.n
            k = road.wrap(k)
            ext.append(f.cell if on and not road.gap[k] and road.kind(k) in ("bridge", "tube") else 0.0)
        along = d @ fw
        m = (along >= -road.step - ext[0]) & (along <= road.step + ext[1])
        lat = np.abs(d[m] @ trk.flat_right[i, [0, 2]])
        out[sub[m]] = np.maximum(out[sub[m]], smoothstep(reach + 2.0, reach, lat))
    return out


def _under_pipe(f, trk):
    """Cells under the round part of a tube (past its mouths, within its skin in plan)."""
    out = np.zeros(len(f.P), bool)
    for t in trk.trks:
        for ids, R in t.tube_runs:
            st = t.styles[t.style[ids[0]]]
            m = int(round(min(st.get("mouth", 14.0), len(ids) * t.step * 0.2) / t.step)) + 2
            mid = np.zeros(t.n, bool)
            mid[ids[m:len(ids) - m]] = True
            out |= f.dist_to(t, mid) < R + 1.0
    return out


def _rock(f, trk, mask, size):
    """Membership of the field's cells in the rocks along the road samples `mask` (one style's,
    with "island_r" (r0, r1)): each run of samples is a rock r0..r1 metres wide with a lumpy
    outline, narrowing to its road and verges where it ends at a jump (it stays wide where it
    meets the lap's island or a deck)."""
    r0, r1 = size
    ids = np.flatnonzero(mask)
    st = trk.styles[trk.style[int(ids[0])]]
    core = float(max(trk.width[ids])) / 2 + st.get("verge_w", 4.5) + 1.0
    cuts = np.flatnonzero((np.diff(trk.route[ids]) != 0) | (np.diff(trk.ridx[ids]) != 1)) + 1
    pos, rad = [], []
    for run in np.split(ids, cuts):
        t = np.linspace(0.0, 1.0, len(run))
        road = trk.trks[int(trk.route[run[0]])]
        a, b = int(trk.ridx[run[0]]), int(trk.ridx[run[-1]])
        jump0 = a > 0 and road.gap[a - 1]
        jump1 = b < road.n - 1 and road.gap[b + 1]
        lo, hi = (0.0 if jump0 else 0.5), (1.0 if jump1 else 0.5)
        shape = np.sin(np.pi * (lo + (hi - lo) * t)) ** 0.6
        q = trk.base[run]
        lump = noise2(q[:, 0] / 18.0, q[:, 2] / 18.0, 41)
        rad.append(core + (r0 + (r1 - r0) * lump - core) * shape)
        pos.append(q[:, [0, 2]])
    pos, rad = np.concatenate(pos), np.concatenate(rad)
    out = np.full(len(f.P), -1e9)
    for a in range(0, len(f.P), 4096):
        q = f.P[a:a + 4096]
        d = np.sqrt(((q[:, None, :] - pos[None, :, :]) ** 2).sum(-1)) - rad[None, :]
        out[a:a + 4096] = d.min(1)
    return smoothstep(3.0, -3.0, out)


def _disc(ctx, mat, c, r, segs=32):
    ang = np.linspace(0, 2 * math.pi, segs + 1)
    rim = np.stack([c[0] + np.cos(ang) * r, np.full(segs + 1, c[1]), c[2] + np.sin(ang) * r], 1)
    ctr = np.tile(np.asarray(c, float), (segs + 1, 1))
    n = np.tile(UP, (segs + 1, 1))
    ctx.meshes["glow"].strip(mat, rim, ctr, r / 4.0, 0.0, ang * r / 4.0, n, n)


def decorate(ctx):
    t = ctx.trk
    g = ctx.mats.goldsrc
    rng = ctx.rng
    island = [i for i in range(t.n) if t.kind(i) == "open" and not t.gap[i]]
    # the healing pool beside the start straight, on the level ground terrain() made for it
    c, py = _pool_site(t)
    c[1] = py + 0.08
    _disc(ctx, g("!fluid3", glow=True), c, 9.0)
    ctx.light(c + UP * 2.0, [0.5, 1.0, 0.7], 26.0, 2.0)
    # nothing grows in it
    ctx.block(c + UP * 2.0, [20.0, 4.0, 20.0])
    _wings(ctx)
    # light stalks along the road edges, glowing, on firm ground under their whole footprint: on the
    # inside of a bend (a kart that runs wide does not pin itself on one), either side on a straight
    for k, i in enumerate(island[::22]):
        bend = float(np.mean(t.curv[[t.wrap(i + d) for d in range(-10, 11)]]))
        sgn = int(np.sign(bend)) if abs(bend) > 0.002 else (1 if k % 2 else -1)
        q = ctx.side(i, sgn, 6.5)
        yaw = rng.uniform(0, 6.28)
        gq = ctx.site("hl1/light", q, yaw, 2.2)
        if gq is None or abs(gq - t.pos[i][1]) > 3.0:
            continue
        q[1] = gq
        if ctx.add("hl1/light", q, yaw, scale=2.2) and k % 3 == 0:
            ctx.light(q + UP * 3.0, [1.0, 0.9, 0.6], 16.0, 1.2)
    # trees, fungi, hair and crystals scattered over the islands, clear of the road, each with
    # firm ground under its whole footprint (none hangs over a cliff edge, none on a cliff's rim),
    # its stem at most half a metre into a slope
    flora = [("hl1/tree", 2.6, 2.0), ("hl1/fungus_large", 2.2, 1.0), ("hl1/fungus", 2.0, 1.0),
             ("hl1/fungus_small", 2.4, 0.8), ("hl1/hair", 3.5, 0.0), ("hl1/uplant2", 3.0, 0.0),
             ("hl1/uplant3", 3.0, 0.0)]
    for k in range(900):
        i = island[int(rng.integers(0, len(island)))]
        sgn = 1 if rng.random() < 0.5 else -1
        q = ctx.side(i, sgn, rng.uniform(9.0, 48.0))
        m, sc, _ = flora[int(rng.integers(0, len(flora)))]
        sc *= rng.uniform(0.8, 1.3)
        yaw = rng.uniform(0, 6.28)
        gq = ctx.site(m, q, yaw, sc, tol=0.7)
        if gq is None or gq < t.pos[i][1] - 8.0 or ctx.road_gap_to(q) < 7.0 or ctx.slope(q[0], q[2]) > 0.8:
            continue
        q[1] = max(gq, ctx.ground(q[0], q[2]) - 0.2) - 0.2
        ctx.add(m, q, yaw, scale=sc)
    cry = [("hl1/crystal", [0.75, 0.5, 1.0]), ("hl1/crystal", [0.5, 1.0, 0.6]), ("hl1/crystal", [1.0, 0.65, 0.3])]
    for k in range(40):
        i = island[int(rng.integers(0, len(island)))]
        sgn = 1 if rng.random() < 0.5 else -1
        q = ctx.side(i, sgn, rng.uniform(10.0, 30.0))
        m, col = cry[k % 3]
        sc = rng.uniform(3.0, 5.0)
        yaw = rng.uniform(0, 6.28)
        gq = ctx.site(m, q, yaw, sc, tol=0.8)
        if gq is None or gq < t.pos[i][1] - 6.0 or ctx.road_gap_to(q) < 8.0:
            continue
        q[1] = max(gq, ctx.ground(q[0], q[2]) - 0.1) - 0.3
        if ctx.add(m, q, yaw, scale=sc) and k % 2 == 0:
            ctx.light(q + UP * 4.0, col, 20.0, 1.6)
    # inside the cave: crystals growing from the floor of the pipe wherever the lane has rolled
    # well away from it. A kart knocked off the lane slides down there: they are seen, never hit
    for ids, R in t.tube_runs:
        for k in range(6, len(ids) - 6, 12):
            near = ids[k - 4:k + 5]
            off = np.abs((t.theta[near] + np.pi) % (2 * np.pi) - np.pi)
            if off.min() < (t.width[ids[k]] / 2 + 4.0) / R:
                continue
            i = ids[k]
            if ctx.add("hl1/crystal", t.base[i], rng.uniform(0, 6.28), scale=2.2, tag="deco", ground=False,
                       solid=False):
                ctx.light(t.base[i] + t.base_up[i] * 3.0, cry[k % 3][1], 18.0, 1.4)
    # far away: floating rocks and the Nihilanth over the void
    lo = t.pos[:, [0, 2]].min(0)
    hi = t.pos[:, [0, 2]].max(0)
    mid = (lo + hi) / 2
    for k in range(46):
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(420.0, 1100.0)
        q = [mid[0] + math.cos(a) * r, rng.uniform(-120.0, 220.0), mid[1] + math.sin(a) * r]
        ctx.add("hl1/big_rock", q, rng.uniform(0, 6.28), scale=rng.uniform(40.0, 140.0), ground=False, tag="far",
                base=False)
    ctx.add("hl1/nihilanth", [mid[0] + 150.0, 260.0, mid[1] - 1300.0], math.pi, scale=8.0, ground=False, tag="far",
            base=False)
    for k in range(6):
        a = rng.uniform(0, 2 * math.pi)
        q = [mid[0] + math.cos(a) * 260, rng.uniform(60, 120), mid[1] + math.sin(a) * 260]
        ctx.add("hl1/floater", q, rng.uniform(0, 6.28), scale=2.0, ground=False, tag="far", base=False)
    # nearer, floaters drifting over the void beside the road
    for k in range(60):
        if sum(p["model"] == "hl1/floater" for p in ctx.props) >= 16:
            break
        i = int(rng.integers(0, t.n))
        q = ctx.side(i, 1 if rng.random() < 0.5 else -1, rng.uniform(45.0, 110.0)) + UP * rng.uniform(6.0, 26.0)
        if ctx.ground(q[0], q[2]) > VOID + 20.0 or ctx.road_gap_to(q) < 40.0:
            continue
        ctx.add("hl1/floater", q, rng.uniform(0, 6.28), scale=rng.uniform(1.6, 2.4), ground=False, tag="far", base=False)
    _gman_rock(ctx)
    _seams(ctx)


def _seams(ctx):
    """Where a branch lies on a deck of the lap (the island hop's merge onto the long bridge), a
    strip of the deck's road 5 cm under the lap's edge it meets: the two roads' edges join there
    in a seam that let a pixel-wide line of the void show through."""
    t = ctx.trk
    for b in ctx.roads.trks[1:]:
        edge = {}
        for k in np.flatnonzero(b.junction):
            i = int(np.argmin(((t.pos - b.pos[k]) ** 2).sum(1)))
            if t.kind(i) == "bridge":
                edge[i] = 1.0 if (b.pos[k] - t.pos[i]) @ t.flat_right[i] > 0 else -1.0
        if len(edge) < 2:
            continue
        ids = np.array(sorted(edge))
        sgn = np.array([edge[i] for i in ids])[:, None]
        e = t.pos[ids] + t.right[ids] * sgn * (t.width[ids] / 2)[:, None] - t.up[ids] * 0.05
        a, c = e - t.right[ids] * sgn * 0.6, e + t.right[ids] * sgn * 0.6
        v = t.s[ids] / 4.0
        up = t.up[ids]
        mat = t.styles[t.style[ids[0]]]["road"]
        if np.dot(np.cross(c[0] - a[0], a[1] - a[0]), up[0]) >= 0:
            ctx.meshes["deco"].strip(mat, a, c, 0.0, 0.3, v, up, up)
        else:
            ctx.meshes["deco"].strip(mat, c, a, 0.3, 0.0, v, up, up)


def _wings(ctx):
    """Where an island's road runs onto a walled deck, a wall from the end of each of the deck's
    railings back out across the verge and 3 m past it: a kart on the verge is turned onto the
    deck instead of driving off the island's end beside it, and meets the wall at a slant, never
    its end."""
    t = ctx.trk
    for name, st in t.styles.items():
        bar = st.get("barrier")
        if st["kind"] != "bridge" or not bar:
            continue
        for ids in t.runs(lambda i, nm=name: t.style[i] == nm):
            i0 = int(ids[0])
            prev = t.styles[t.style[t.wrap(i0 - 1)]]
            if prev["kind"] != "open" or (not t.closed and i0 == 0):
                continue
            j = t.wrap(i0 - int(round(20.0 / t.step)))
            for sgn in (-1, 1):
                a = t.pos[i0] + t.flat_right[i0] * sgn * (t.width[i0] / 2 + bar.get("thick", 0.6) / 2)
                b = t.pos[j] + t.flat_right[j] * sgn * (t.width[j] / 2 + prev.get("verge_w", 4.5) + 3.0)
                b[1] = ctx.ground(b[0], b[2])
                d = a - b
                d[1] = 0.0
                y0 = min(a[1], b[1]) - 0.5
                y1 = max(a[1], b[1]) + bar.get("h", 0.9)
                c = (a + b) / 2
                c[1] = (y0 + y1) / 2
                ctx.box(bar["mat"], c, [bar.get("thick", 0.6), y1 - y0, float(np.linalg.norm(d)) + 0.6],
                        ctx.yaw_facing(d), rep=bar.get("rep", 2.5))


def _lap_s(ctx, xz):
    """Lap metres of the lap sample nearest a plan point (x, z)."""
    t = ctx.trk
    return ctx.s_of(int(np.argmin(((t.pos[:, [0, 2]] - np.asarray(xz)) ** 2).sum(1))))


GMAN_ROCK = 4.5  # scale of the G-Man's floating rock (about 3.5 m across)


def _gman_rock(ctx):
    """The G-Man's floating rock, a few metres off the road over the void beside the arch, on the
    stretch every racer drives (past where the high root joins the lap again, before the island hop
    leaves it: by the bay a racer on the island hop never saw him). His spots start 75 m past the
    high root's merge, as his window starts up to 72 m before his spot (he is first shown 70 m off).
    Of the rock tops there, the one the chase camera sees him on best (crowds' gman_spot: shown
    from 70 m, recognisable within 29 m). The rock is placed here and his spot kept on ctx.gman for
    eggs() (None when no spot works)."""
    t = ctx.trk
    br = {b["id"]: b for b in BRANCHES}
    lo, hi = _lap_s(ctx, br["high_root"]["merge"]) + 75.0, _lap_s(ctx, br["island_hop"]["fork"]) - 10.0
    spots = []
    for i in ctx.lap_ids(lo, hi)[::3]:
        for sgn in (-1, 1):
            for off in (4.0, 6.0, 8.0, 11.0):
                q = t.pos[i] + t.flat_right[i] * sgn * (t.width[i] / 2 + off)
                if ctx.ground(q[0], q[2]) < VOID + 20.0:
                    spots += [q + UP * 0.5, q + UP * 2.0]
    ctx.gman = ctx.gman_spot(lo, hi, spots=spots)
    if ctx.gman:
        top = ctx.models["hl1/big_rock"]["aabb_max"][1] * GMAN_ROCK * 0.92
        ctx.add("hl1/big_rock", ctx.gman["pos"] - UP * top, ctx.gman["yaw"], scale=GMAN_ROCK, ground=False,
                tag="far", base=False)


def decorate_branch(ctx, spec):
    """The branches' rocks (the island hop's, the one the high root leaves the plateau over): light
    stalks by the road, fungi, hair and crystals on firm ground."""
    t = ctx.trk
    rng = ctx.rng
    _wings(ctx)
    rock = [i for i in range(t.n) if t.style[i] == "rock" and not t.gap[i] and not t.junction[i]]
    if not rock:
        return
    for k, i in enumerate(rock[::11]):
        sgn = 1 if k % 2 else -1
        q = ctx.side(i, sgn, 4.5)
        yaw = rng.uniform(0, 6.28)
        gq = ctx.site("hl1/light", q, yaw, 2.0)
        if gq is None or abs(gq - t.pos[i][1]) > 1.5:
            continue
        q[1] = gq
        if ctx.add("hl1/light", q, yaw, scale=2.0) and k % 2 == 0:
            ctx.light(q + UP * 3.0, [1.0, 0.9, 0.6], 16.0, 1.2)
    flora = [("hl1/fungus_large", 1.8), ("hl1/fungus", 2.0), ("hl1/fungus_small", 2.4), ("hl1/hair", 3.5),
             ("hl1/uplant3", 3.0), ("hl1/crystal", 3.0)]
    for k in range(220):
        i = rock[int(rng.integers(0, len(rock)))]
        q = ctx.side(i, 1 if rng.random() < 0.5 else -1, rng.uniform(7.0, 24.0))
        m, sc = flora[int(rng.integers(0, len(flora)))]
        sc *= rng.uniform(0.8, 1.25)
        yaw = rng.uniform(0, 6.28)
        gq = ctx.site(m, q, yaw, sc, tol=0.7)
        if gq is None or abs(gq - t.pos[i][1]) > 3.0 or ctx.road_gap_to(q) < 6.0 or ctx.slope(q[0], q[2]) > 0.8:
            continue
        q[1] = max(gq, ctx.ground(q[0], q[2]) - 0.2) - 0.2
        if ctx.add(m, q, yaw, scale=sc) and m == "hl1/crystal":
            ctx.light(q + UP * 3.5, [1.0, 0.65, 0.3], 16.0, 1.4)


# ---------------------------------------------------------------- spectators
START = (-40.0, 30.0)  # lap metres round the start line


def crowds(ctx):
    """Vortigaunt circles on the islands (3-6 facing the road or each other), denser at the start and
    after the chasm jump; HL1 alien slaves chanting by the crystals. The game lights the circles
    nearest the camera (dark models on dark ground vanish otherwise). Only open islands, never on a
    deck, the ledge or in the cave."""
    t = ctx.trk
    rng = ctx.crowd_rng
    island = [i for i in range(t.n) if t.kind(i) == "open" and not t.gap[i]]
    hot = set(i for i in ctx.lap_ids(*START) if i in island)
    landing = set()
    for a, b in t.gaps:
        s = ctx.s_of(b % t.n)
        landing |= set(i for i in ctx.lap_ids(s + 5.0, s + 35.0) if i in island)
    # circles: six at the start, three after the chasm, the rest spread over the islands
    picks = [(i, ["start"]) for i in sorted(hot)[::max(1, len(hot) // 6)][:6]]
    picks += [(i, ["jump"]) for i in sorted(landing)[::4][:3 * len(t.gaps)]]
    picks += [(i, []) for i in island[::max(1, len(island) // 36)]]
    for i, tags in picks:
        _circle(ctx, i, 1 if rng.random() < 0.5 else -1, tags, int(rng.integers(3, 7)))
    # alien slaves chanting by the crystals near the road
    crystals = [p for p in ctx.props if p["model"] == "hl1/crystal"]
    crystals.sort(key=lambda p: ctx.road_gap_xz(np.array(p["pos"], float)))
    used = 0
    for p in crystals:
        if used >= 5:
            break
        q = np.array(p["pos"], float)
        gap = ctx.road_gap_xz(q)
        if gap < 8.0 or gap > 30.0:
            continue
        i = ctx._nearest(q)
        gid = ctx.crowd_group(i, 0, "cluster", "islave", tags=["crystal"], bed="alien")
        if _cluster(ctx, gid, q, 4, 4.5, "islave", q + UP, t.pos[i][1], (-2.0, 3.0), margin=4.0):
            used += 1
    eggs(ctx)


def _circle(ctx, i, sgn, tags, n, out=(6.0, 10.0)):
    """A vortigaunt circle beside sample i of the context's road, `out` metres past its verge: half
    of them face the road, the others the middle of the circle."""
    t = ctx.trk
    rng = ctx.crowd_rng
    verge = ctx.style_of(i).get("verge_w", 4.5)
    c = ctx.side_point(i, sgn, verge + rng.uniform(*out))
    gid = ctx.crowd_group(i, sgn, "cluster", "vort", tags=tags, bed="alien")
    face = t.pos[i] + UP if rng.random() < 0.5 else c + UP
    _cluster(ctx, gid, c, n, 2.2, "vort", face, t.pos[i][1], (-1.5, 2.5), lod=lambda k: 0 if k < 3 else (1 if k < 5 else 2))


def _cluster(ctx, gid, center, n, radius, role, face, ref_y, dy, margin=2.5, lod=None):
    """ctx.crowd_cluster (up to n chanting people within `radius` of center, at ref_y + dy[0]..dy[1])
    with each one's feet on the terrain as it is drawn and collides (_surface), not on the
    bilinear height between its grid points, which on a saddle lies up to 0.3 m under it."""
    rng = ctx.crowd_rng
    placed = 0
    for _ in range(n * 6):
        if placed >= n:
            break
        a = rng.uniform(0, 2 * math.pi)
        r = radius * math.sqrt(rng.uniform(0, 1))
        q = np.array([center[0] + math.cos(a) * r, 0.0, center[2] + math.sin(a) * r])
        q[1] = _surface(ctx, q[0], q[2])
        if not dy[0] <= q[1] - ref_y <= dy[1]:
            continue
        if ctx.crowd_add(gid, q, face, role, "chant", margin=margin, on="ground",
                         lod=lod(placed) if lod else LOD_CYCLE[len(ctx.crowds) % 20]):
            placed += 1
    return placed


def _surface(ctx, x, z):
    """Height of the terrain mesh at (x, z): each grid cell is two triangles split along the
    diagonal from its +x corner to its +z corner (track_gen.terrain_mesh)."""
    f = ctx.field
    gi = min(max((x - f.xs[0]) / f.cell, 0.0), f.nx - 1.001)
    gj = min(max((z - f.zs[0]) / f.cell, 0.0), f.nz - 1.001)
    i0, j0 = int(gi), int(gj)
    fx, fz = gi - i0, gj - j0
    a, b, c, d = f.H[j0, i0], f.H[j0, i0 + 1], f.H[j0 + 1, i0], f.H[j0 + 1, i0 + 1]
    if fx + fz <= 1.0:
        return float(a + (b - a) * fx + (c - a) * fz)
    return float(d + (c - d) * (1.0 - fx) + (b - d) * (1.0 - fz))


def crowds_branch(bctx, spec):
    """Circles on the island hop's floating rocks, either side of the road in the middle of each
    rock a hop lands on (past the high root's drop there is only deck: nobody stands there)."""
    t = bctx.trk
    rng = bctx.crowd_rng
    for a, b in t.gaps:
        run = [i for i in range(b, t.n) if t.style[i] == "rock" and not t.gap[i]]
        run = run[:next((k for k in range(1, len(run)) if run[k] != run[k - 1] + 1), len(run))]
        if len(run) < 10:
            continue
        i = run[int(len(run) * 0.45)]
        # (a rock's edge is open: nobody within 6 m of its road)
        for sgn in (-1, 1):
            _circle(bctx, i, sgn, ["jump"], int(rng.integers(3, 6)), (6.5, 9.0))


def eggs(ctx):
    t = ctx.trk
    # where the Nihilanth laughs from when someone falls into the void
    for p in ctx.props:
        if p["model"] == "hl1/nihilanth":
            ctx.egg("nihilanth", pos=p["pos"])
            break
    # the G-Man on his floating rock beside the arch (see _gman_rock), facing the karts coming
    g = ctx.gman
    if g:
        ctx.egg("gman", pos=g["pos"], yaw=g["yaw"], s=g["s"], model="hl1/gman", window=g["window"], chance=0.4)
    # Gnome Chompski alone on an island, a little off the road
    island = [i for i in range(t.n) if t.kind(i) == "open" and not t.gap[i]]
    for i in island[len(island) // 3::7]:
        sgn = 1 if i % 2 else -1
        q = ctx.ground_spot(ctx.side_point(i, sgn, ctx.style_of(i).get("verge_w", 4.5) + 6.0), 0.0, 4.0,
                            t.pos[i][1] - 1.0, t.pos[i][1] + 2.0, margin=6.0, tries=60)
        if q is not None and ctx.egg("gnome", pos=q, yaw=math.atan2(*(t.pos[i] - q)[[0, 2]])):
            break
    # boids circling over the void of each lobe
    for c in (np.array([420.0, 55.0, -110.0]), np.array([100.0, 45.0, 110.0])):
        ctx.egg("birds", species="boid", center=c, radius=40.0, count=8)
