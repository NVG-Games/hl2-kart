"""Surface Tension: the New Mexico desert outside Black Mesa, about 2 km.

From the desert highway the road drops into a red-rock canyon, jumps a washed-out
stretch, crosses the river gorge on a steel bridge, runs through the HECU camp
by a landed Osprey, bores through a mesa in an old mine tunnel, climbs a cliff
road and comes home across the crest of the dam.
"""
import math

import numpy as np

from track_gen import UP, carve, noise2, smoothstep

RIVER = [(320.0, 70.0), (400.0, -60.0), (470.0, -160.0), (478.0, -300.0), (476.0, -420.0), (470.0, -560.0),
         (440.0, -760.0)]
RIVER_Y = -2.0
DAM_Z = 112.0
LAKE_Y = 30.5

CTRL = [
    (0, 30, 0, 18, "highway"),
    (130, 30, -5, 18, "highway"),
    (232, 30, -42, 17, "highway"),
    (296, 25, -112, 15, "canyon"),
    (322, 19, -200, 15, "canyon"),
    (306, 15, -292, 15, "canyon", {"gap": True, "gap_span": (0.42, 0.6), "ramp_lift": 2.0}),
    (352, 12, -372, 15, "canyon"),
    (425, 13, -412, 14, "gorge"),
    (528, 14, -420, 14, "gorge"),
    (602, 16, -382, 18, "camp"),
    (652, 18, -302, 18, "camp"),
    (662, 20, -212, 17, "camp"),
    (642, 22, -122, 14, "mine"),
    (602, 24, -42, 14, "mine"),
    (566, 28, 30, 15, "cliff"),
    (488, 32, 84, 15, "cliff"),
    (390, 34, DAM_Z, 16, "dam"),
    (262, 34, DAM_Z, 16, "dam"),
    (160, 32, 86, 17, "highway"),
    (68, 30, 42, 18, "highway"),
    (-40, 30, 22, 18, "highway"),
    (-70, 30, 5, 18, "highway"),
]
CTRL = [c if len(c) > 5 else c + ({},) for c in CTRL]

TRACK = {
    "id": "surface_tension",
    "music": ['hl1_song20', 'hl1_song21', 'hl1_song24', 'hl1_song26', 'hl1_song14'],
    "name": "Surface Tension",
    "ctrl": CTRL,
    "items": [0.1, 0.32, 0.56, 0.8],
    "boosts": [0.03, 0.47, 0.88],
    "vmax": 40.0,
    "offtrack": 45.0,
    "sky": "hl1_desert",
    "background": "none",
    "gantry": "military",
    "water": {"level": RIVER_Y},
    "waters": [{"center": [326.0, DAM_Z + 150.0], "size": [300.0, 290.0], "level": LAKE_Y}],
    "env": {"sun_energy": 2.1, "sun_color": [1.0, 0.9, 0.74], "sun_dir": [0.45, 0.75, -0.35],
            "ambient": [0.66, 0.58, 0.5], "ambient_energy": 1.0, "fog_color": [0.86, 0.74, 0.6],
            "fog_begin": 300.0, "fog_end": 2200.0, "exposure": 1.0, "sdfgi": True},
}


def styles(m):
    g = m.goldsrc
    asphalt = m.hl2("concrete/concretefloor037a")
    concrete = m.hl2("concrete/concretewall008a")
    g("out_w3"), g("out_w4"), g("c2a5g_sign1"), g("metal_wall04")  # the start arch
    return {
        "highway": {"kind": "open", "road": asphalt, "road_u": "full", "road_len": 1.0, "verge": g("out_snd2c"),
                    "verge_w": 5.0, "bank": True},
        "canyon": {"kind": "open", "road": m.hl2("nature/dirtroad001a"), "road_u": "full", "road_len": 1.6,
                   "verge": g("out_snd2c"), "verge_w": 4.0, "skirt": g("out_rk3")},
        "gorge": {"kind": "bridge", "road": m.hl2("metal/metalgrate013a"), "road_rep": 3.0,
                  "skirt": m.hl2("metal/metaltruss009a"), "skirt_h": 3.5,
                  "barrier": {"kind": "fence", "mat": m.hl2("metal/metaltruss002a"), "h": 2.2, "rep": 3.0},
                  "pillar": m.hl2("metal/metaltruss009a"), "pillar_every": 34.0, "pillar_size": 2.4,
                  "pillar_offsets": [-0.8, 0.8]},
        "camp": {"kind": "open", "road": g("out_snd2c"), "road_rep": 5.0, "verge": g("out_snd2"), "verge_w": 6.0},
        "mine": {"kind": "tunnel", "road": m.hl2("nature/dirtroad001a"), "road_u": "full", "road_len": 1.6,
                 "height": 8.5, "wall": g("out_rk3"), "wall_rep": 5.0, "ceil": m.hl2("wood/woodceiling003a"),
                 "ceil_rep": 3.0, "light": m.hl2("lights/fluorescent001a"), "light_every": 13.0, "light_w": 0.6,
                 "light_l": 2.0, "light_color": [1.0, 0.78, 0.5], "light_energy": 1.6, "wall_gap": 1.0, "cover": 6.0,
                 "lid_w": 10.0, "lid_mat": g("out_rk3"), "portal": g("out_rk3")},
        "cliff": {"kind": "open", "road": asphalt, "road_u": "full", "verge": g("out_snd2c"), "verge_w": 3.0,
                  "barrier": {"kind": "jersey", "mat": m.hl2("concrete/concretewall064a"), "sides": "left"}},
        "dam": {"kind": "bridge", "road": asphalt, "road_u": "full", "skirt": concrete, "skirt_h": 2.0,
                "barrier": {"kind": "wall", "mat": concrete, "h": 1.1, "thick": 0.7, "rep": 3.0},
                "pillar_every": 1e9},
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
        # the reservoir behind the dam: a lake bed north of the crest
        lake = smoothstep(DAM_Z + 10.0, DAM_Z + 30.0, P[:, 1]) * smoothstep(210.0, 150.0, np.abs(P[:, 0] - 326.0))
        nat = nat * (1 - lake) + (LAKE_Y - 8.0) * lake
        h = carve(f, nat, trk, flat=8.0, blend=26.0, tunnel_cover=6.0, gap_floor=RIVER_Y + 2.0)
        # the dam keeps the lake: nothing of the downstream valley pokes north of it
        Hm = h.reshape(f.nz, f.nx)
        gz, gx = np.gradient(Hm, f.cell)
        slope = np.sqrt(gx ** 2 + gz ** 2).ravel()
        rock = smoothstep(0.45, 0.9, slope)
        dirt = smoothstep(f.half + 10.0, f.half + 2.0, f.dist) * (1 - rock)
        sand = smoothstep(RIVER_Y + 4.0, RIVER_Y + 1.0, h) + smoothstep(LAKE_Y + 1.0, LAKE_Y - 1.0, h) * lake
        sand = np.clip(sand, 0, 1)
        pave = np.zeros_like(h)
        col = np.stack([dirt, rock, pave, sand], 1).astype(np.float32)
        return h, col

    return {"margin": 380.0, "cell": 4.0, "build": build, "layers": layers}


def cactus(ctx, base, height, rng, mats):
    """A saguaro: trunk and two arms in the HL1 cactus texture; the trunk collides."""
    tex = mats.goldsrc("out_cac1")
    r = 0.42 * height / 6.0
    ctx.cylinder(tex, base, r, height, segs=10, kind="walls", rep=1.5)
    ctx.meshes["deco"]  # arms are decoration only
    for side in (-1, 1):
        a = rng.uniform(0, 2 * math.pi) if side < 0 else a + math.pi
        d = np.array([math.cos(a), 0.0, math.sin(a)])
        y0 = rng.uniform(0.35, 0.55) * height
        elbow = np.asarray(base, float) + UP * y0 + d * (r + 0.7)
        # the horizontal stub, then the arm going up
        ctx.box(tex, np.asarray(base, float) + UP * y0 + d * (r * 0.5 + 0.35), [r * 1.6, r * 1.6, 1.4 * 0.9],
                math.atan2(d[0], d[2]), kind="deco", rep=1.5)
        ctx.cylinder(tex, elbow, r * 0.75, rng.uniform(0.3, 0.45) * height, segs=8, kind="deco", rep=1.5)


def decorate(ctx):
    t = ctx.trk
    g = ctx.mats.goldsrc
    rng = ctx.rng
    by = {}
    for i in range(t.n):
        by.setdefault(t.style[i], []).append(i)
    # the dam body under the crest road, and lamps along it
    dam = by.get("dam", [])
    if dam:
        a, b = t.pos[dam[0]], t.pos[dam[-1]]
        mid = (a + b) / 2
        length = np.linalg.norm(b - a) + 30.0
        yaw = math.atan2(b[0] - a[0], b[2] - a[2])
        top = mid[1] - 2.0
        ctx.box(ctx.mats.hl2("concrete/concretewall008a"), [mid[0], (top + RIVER_Y - 8.0) / 2, mid[2] - 9.0],
                [16.0, top - RIVER_Y + 8.0, length], yaw, kind="walls", rep=6.0)
        for k, i in enumerate(dam[4::14]):
            for sgn in (-1, 1):
                q = ctx.side(i, sgn, 0.4)
                ctx.add("props_c17/lamppost03a_on", q + UP * 0.0, ctx.yaw_facing(-t.flat_right[i] * sgn), ground=False)
        i = dam[len(dam) // 2]
        q = ctx.side(i, -1, 1.2) + UP * 1.1
        ctx.box(g("c2a5_sign1"), q + UP * 1.2, [0.2, 1.6, 4.8], ctx.yaw_facing(t.fwd[i]), kind="deco", rep=4.8)
    # saguaros all over the desert (never on the road)
    placed = 0
    for k in range(1400):
        i = int(rng.integers(0, t.n))
        if t.kind(i) in ("tunnel", "bridge"):
            continue
        sgn = 1 if rng.random() < 0.5 else -1
        q = ctx.side(i, sgn, rng.uniform(6.0, 70.0))
        gq = ctx.ground(q[0], q[2])
        if ctx.road_gap_to(q) < 5.0 or abs(gq - t.pos[i][1]) > 14.0 or gq < RIVER_Y + 2.0:
            continue
        q[1] = gq - 0.2
        cactus(ctx, q, rng.uniform(4.5, 8.5), rng, ctx.mats)
        placed += 1
        if placed > 110:
            break
    # highway: power poles and Black Mesa signs
    hw = by.get("highway", [])
    for k, i in enumerate(hw[::25]):
        q = ctx.side(i, 1, 9.0)
        q[1] = ctx.ground(q[0], q[2])
        ctx.add("props_c17/utilitypole01a", q, ctx.yaw_facing(t.fwd[i]))
    for k, i in enumerate(hw[30::120]):
        q = ctx.side(i, -1, 7.0)
        q[1] = ctx.ground(q[0], q[2])
        sign = ["c2a5g_sign1", "c2a5_sign2", "c2a5w_sign"][k % 3]
        ctx.box(g(sign), q + UP * 3.4, [0.3, 2.4, 5.0], ctx.yaw_facing(t.fwd[i]), kind="deco", rep=5.0)
        for off in (-2.2, 2.2):
            ctx.box(ctx.mats.hl2("wood/woodbeam001a"), q + t.fwd[i] * off + UP * 1.2, [0.25, 2.4, 0.25], 0.0,
                    kind="walls", rep=2.4)
    # canyon: the Osprey wreck and boulders
    can = by.get("canyon", [])
    if can:
        i = can[len(can) // 3]
        q = ctx.side(i, 1, 22.0)
        q[1] = ctx.ground(q[0], q[2])
        ctx.add("hl1/dead_osprey", q, 1.1)
    for k, i in enumerate(can[::9]):
        sgn = 1 if k % 2 else -1
        q = ctx.side(i, sgn, rng.uniform(5.0, 14.0))
        q[1] = ctx.ground(q[0], q[2])
        ctx.add(["props_wasteland/rockgranite02a", "props_wasteland/rockgranite03a", "props_wasteland/rockcliff01b",
                 "props_wasteland/rockgranite01a"][k % 4], q, rng.uniform(0, 6.28))
    # HECU camp: the Osprey on its pad, marines, barricades and crates
    camp = by.get("camp", [])
    if camp:
        i = camp[len(camp) // 2]
        q = ctx.side(i, 1, 26.0)
        q[1] = ctx.ground(q[0], q[2])
        ctx.add("hl1/osprey", q, ctx.yaw_facing(t.fwd[i]) + 0.4)
        for k, i in enumerate(camp[::12]):
            sgn = 1 if k % 2 else -1
            q = ctx.side(i, sgn, 4.0)
            q[1] = ctx.ground(q[0], q[2])
            ctx.add(["props_wasteland/barricade001a", "props_c17/concrete_barrier001a",
                     "props_wasteland/barricade002a"][k % 3], q, ctx.yaw_facing(t.fwd[i]))
            if k % 3 == 0:
                q2 = ctx.side(i, sgn, 9.0)
                q2[1] = ctx.ground(q2[0], q2[2])
                ctx.add("hl1/hgrunt", q2, ctx.yaw_facing(-t.flat_right[i] * sgn), ground=False)
            if k % 2 == 0:
                q3 = ctx.side(i, sgn, 12.0)
                q3[1] = ctx.ground(q3[0], q3[2])
                for lvl in range(2):
                    ctx.add("props_junk/wood_crate001a", q3 + UP * (lvl * 1.0), 0.3, ground=False)
    # mine: timber frames along the tunnel
    mine = by.get("mine", [])
    beam = ctx.mats.hl2("wood/woodbeam001a")
    for k, i in enumerate(mine[2::8]):
        hw_ = t.width[i] / 2 + 0.8
        for sgn in (-1, 1):
            q = t.pos[i] + t.flat_right[i] * sgn * hw_ + UP * 4.2
            ctx.box(beam, q, [0.5, 8.4, 0.5], ctx.yaw_facing(t.fwd[i]), kind="walls", rep=2.0)
        ctx.box(beam, t.pos[i] + UP * 8.2, [hw_ * 2 + 0.5, 0.5, 0.5], ctx.yaw_facing(t.flat_right[i]), kind="deco",
                rep=2.0)
    # gorge bridge: the river below gets rocks and the Apache overhead
    gor = by.get("gorge", [])
    if gor:
        mid = t.pos[gor[len(gor) // 2]]
        ctx.add("hl1/apache", [mid[0] + 60.0, mid[1] + 70.0, mid[2] - 120.0], 2.4, ground=False, tag="far")
