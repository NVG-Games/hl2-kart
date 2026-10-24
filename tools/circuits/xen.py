"""Xen: floating islands in the border world, about 2 km.

Start on the island with the healing pool, climb an organic bridge to the
crystal fields, jump a chasm down to the fungus island, drive through a glowing
cave, jump again to the lowest island and take the long bridge back up.
"""
import math

import numpy as np

from track_gen import UP, carve, noise2, smoothstep

VOID = -75.0

CTRL = [
    (0, 20, 0, 18, "island"),
    (90, 20, -8, 18, "island"),
    (155, 21, -48, 17, "island"),
    (205, 24, -110, 13, "bridge"),
    (238, 27, -178, 13, "bridge"),
    (262, 28, -242, 17, "island"),
    (325, 29, -292, 17, "island"),
    (405, 30, -290, 17, "island"),
    (455, 31, -238, 17, "island", {"gap": True, "gap_span": (0.38, 0.6), "ramp_lift": 2.4}),
    (505, 19, -148, 18, "island"),
    (528, 17, -58, 18, "island"),
    (510, 16, 32, 17, "island"),
    (458, 15, 100, 15, "cave"),
    (385, 14, 140, 15, "cave"),
    (305, 14, 152, 17, "island"),
    (232, 14, 160, 17, "island", {"gap": True, "gap_span": (0.4, 0.62), "ramp_lift": 2.4}),
    (140, 8, 172, 18, "island"),
    (62, 8, 145, 18, "island"),
    (8, 12, 102, 13, "bridge"),
    (-45, 16, 62, 13, "bridge"),
    (-70, 20, 14, 17, "island"),
    (-45, 20, -2, 18, "island"),
]
CTRL = [c if len(c) > 5 else c + ({},) for c in CTRL]
K = 1.16  # plan scale of the layout above
CTRL = [(c[0] * K, c[1], c[2] * K) + tuple(c[3:]) for c in CTRL]

TRACK = {
    "id": "xen",
    "music": ['hl1_song3', 'hl1_song5', 'hl1_song6', 'hl1_song9', 'hl1_song19'],
    "name": "Xen",
    "ctrl": CTRL,
    "items": [0.1, 0.3, 0.55, 0.82],
    "boosts": [0.03, 0.385, 0.69],
    "vmax": 38.0,
    "offtrack": 40.0,
    "kill_y": -25.0,
    "sky": "hl1_xen8",
    "background": "none",
    "gantry": "xen",
    "env": {"sun_energy": 1.1, "sun_color": [0.75, 1.0, 0.8], "sun_dir": [0.3, 0.8, 0.45],
            "ambient": [0.5, 0.42, 0.62], "ambient_energy": 1.15, "fog_color": [0.32, 0.2, 0.42],
            "fog_begin": 220.0, "fog_end": 1700.0, "fog_sky": 0.0, "exposure": 1.1, "glow": 0.7, "sdfgi": False},
}


def styles(m):
    g = m.goldsrc
    road = g("xeno_6flr")
    return {
        "island": {"kind": "open", "road": road, "road_rep": 5.0, "verge": g("xeno_16b"), "verge_w": 5.0},
        "bridge": {"kind": "bridge", "road": g("xeno_6flr2"), "road_rep": 5.0, "skirt": g("xeno_6aw1"),
                   "skirt_h": 3.0, "barrier": {"kind": "wall", "mat": g("xeno_8w1"), "h": 0.9, "thick": 0.6, "rep": 2.5},
                   "pillar_every": 1e9},
        "cave": {"kind": "tunnel", "road": road, "road_rep": 5.0, "height": 10.0, "wall": g("xeno_6a"),
                 "wall_rep": 5.0, "ceil": g("xeno_10w1"), "ceil_rep": 5.0, "light": g("crys_2top", glow=True),
                 "light_every": 11.0, "light_rows": [-0.6, 0.6], "light_w": 2.4, "light_l": 2.4,
                 "light_color": [0.55, 1.0, 0.65], "light_energy": 1.8, "wall_gap": 1.5, "cover": 4.0, "lid_w": 9.0,
                 "lid_mat": g("xeno_14"), "portal": g("c4a1a_swmpwl")},
    }


def STARTLINE(m):
    return m.goldsrc("crys_2top", glow=True)


def terrain(trk, m):
    g = m.goldsrc
    layers = {"base": g("xeno_14"), "dirt": g("xeno_16a"), "rock": g("c4a1a_swmpwl"), "pave": g("xeno_13e"),
              "sand": g("xeno_21")}

    def build(f, trk):
        P = f.P
        land = np.array([(trk.kind(i) in ("open", "tunnel")) and not trk.gap[i] for i in range(trk.n)])
        void = np.array([trk.gap[i] or trk.kind(i) == "bridge" for i in range(trk.n)])
        d_land = f.dist_to(trk, land)
        d_void = f.dist_to(trk, void)
        # each island reaches 28..62 m from its road, a little less toward a chasm
        edge = 24.0 + noise2(P[:, 0] / 70.0, P[:, 1] / 70.0, 9) * 30.0
        member = smoothstep(edge + 6.0, edge - 6.0, d_land) * smoothstep(6.0, 18.0, d_void - d_land + 4.0)
        hills = (noise2(P[:, 0] / 55.0, P[:, 1] / 55.0, 3) - 0.35) * 22.0
        hills *= smoothstep(f.half + 10.0, f.half + 45.0, f.dist)
        top = f.road_h - 0.35 + np.maximum(hills, -2.0)
        nat = top * member + VOID * (1.0 - member)
        h = carve(f, nat, trk, flat=7.0, blend=18.0, tunnel_cover=4.0, gap_floor=VOID)
        Hm = h.reshape(f.nz, f.nx)
        gz, gx = np.gradient(Hm, f.cell)
        slope = np.sqrt(gx ** 2 + gz ** 2).ravel()
        rock = smoothstep(0.5, 1.1, slope)
        dirt = smoothstep(f.half + 9.0, f.half + 1.0, f.dist) * (1 - rock)
        pave = np.clip((noise2(P[:, 0] / 30.0, P[:, 1] / 30.0, 21) - 0.55) * 3.0, 0, 1) * (1 - rock) * (1 - dirt)
        sand = np.clip((noise2(P[:, 0] / 45.0, P[:, 1] / 45.0, 33) - 0.6) * 3.0, 0, 1) * (1 - rock)
        col = np.stack([dirt, rock, pave, sand], 1).astype(np.float32)
        return h, col

    return {"margin": 140.0, "cell": 4.0, "build": build, "layers": layers, "void": VOID + 2.0}


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
    # the healing pool beside the start straight
    i = int(0.04 * t.n)
    c = ctx.side(i, -1, 26.0)
    c[1] = ctx.ground(c[0], c[2]) + 0.25
    if ctx.road_gap_to(c) > 12:
        _disc(ctx, g("!fluid3", glow=True), c, 9.0)
        ctx.light(c + UP * 2.0, [0.5, 1.0, 0.7], 26.0, 2.0)
    # light stalks along the road edges, glowing
    for k, i in enumerate(island[::22]):
        sgn = 1 if k % 2 else -1
        q = ctx.side(i, sgn, 6.5)
        gq = ctx.ground(q[0], q[2])
        if abs(gq - t.pos[i][1]) > 3.0:
            continue
        q[1] = gq
        ctx.add("hl1/light", q, rng.uniform(0, 6.28), scale=2.2)
        if k % 3 == 0:
            ctx.light(q + UP * 3.0, [1.0, 0.9, 0.6], 16.0, 1.2)
    # trees, fungi, hair and crystals scattered over the islands, clear of the road
    flora = [("hl1/tree", 2.6, 2.0), ("hl1/fungus_large", 2.2, 1.0), ("hl1/fungus", 2.0, 1.0),
             ("hl1/fungus_small", 2.4, 0.8), ("hl1/hair", 3.5, 0.0), ("hl1/uplant2", 3.0, 0.0),
             ("hl1/uplant3", 3.0, 0.0)]
    for k in range(900):
        i = island[int(rng.integers(0, len(island)))]
        sgn = 1 if rng.random() < 0.5 else -1
        q = ctx.side(i, sgn, rng.uniform(9.0, 48.0))
        gq = ctx.ground(q[0], q[2])
        if gq < t.pos[i][1] - 8.0 or ctx.road_gap_to(q) < 7.0:
            continue
        q[1] = gq - 0.2
        m, sc, _ = flora[int(rng.integers(0, len(flora)))]
        ctx.add(m, q, rng.uniform(0, 6.28), scale=sc * rng.uniform(0.8, 1.3))
    cry = [("hl1/crystal", [0.75, 0.5, 1.0]), ("hl1/crystal", [0.5, 1.0, 0.6]), ("hl1/crystal", [1.0, 0.65, 0.3])]
    for k in range(40):
        i = island[int(rng.integers(0, len(island)))]
        sgn = 1 if rng.random() < 0.5 else -1
        q = ctx.side(i, sgn, rng.uniform(10.0, 30.0))
        gq = ctx.ground(q[0], q[2])
        if gq < t.pos[i][1] - 6.0 or ctx.road_gap_to(q) < 8.0:
            continue
        q[1] = gq - 0.3
        m, col = cry[k % 3]
        ctx.add(m, q, rng.uniform(0, 6.28), scale=rng.uniform(3.0, 5.0))
        if k % 2 == 0:
            ctx.light(q + UP * 4.0, col, 20.0, 1.6)
    # inside the cave: crystals in the walls
    cave = [i for i in range(t.n) if t.kind(i) == "tunnel"]
    for k, i in enumerate(cave[6::12]):
        sgn = 1 if k % 2 else -1
        q = ctx.side(i, sgn, 0.6)
        ctx.add("hl1/crystal", q, rng.uniform(0, 6.28), scale=2.2, ground=False)
    # far away: floating rocks and the Nihilanth over the void
    lo = t.pos[:, [0, 2]].min(0)
    hi = t.pos[:, [0, 2]].max(0)
    mid = (lo + hi) / 2
    for k in range(46):
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(420.0, 1100.0)
        q = [mid[0] + math.cos(a) * r, rng.uniform(-120.0, 220.0), mid[1] + math.sin(a) * r]
        ctx.add("hl1/big_rock", q, rng.uniform(0, 6.28), scale=rng.uniform(40.0, 140.0), ground=False, tag="far")
    ctx.add("hl1/nihilanth", [mid[0] + 150.0, 260.0, mid[1] - 1300.0], math.pi, scale=8.0, ground=False, tag="far")
    for k in range(6):
        a = rng.uniform(0, 2 * math.pi)
        q = [mid[0] + math.cos(a) * 260, rng.uniform(60, 120), mid[1] + math.sin(a) * 260]
        ctx.add("hl1/floater", q, rng.uniform(0, 6.28), scale=2.0, ground=False, tag="far")
