"""CT17: Combine-held City 17, about 2 km.

The station plaza under the Breencasts, the cobbled old town, a Combine
checkpoint, a jump over the canal, the rail yard, an underpass below the railway
embankment, a short boulevard toward the Citadel and an overpass that crosses
the canal again on the way back down to the plaza.
"""
import numpy as np

from track_gen import carve, noise2, smoothstep

# (x, y, z, width, style, flags): clockwise seen from above, the start first
CTRL = [
    (0, 0, 0, 24, "plaza", {}),
    (110, 0, 0, 24, "plaza"),
    (180, 0, -18, 20, "plaza"),
    (232, 0, -62, 16, "old"),
    (250, 0, -125, 15, "old"),
    (228, 0, -185, 15, "old"),
    (250, 0, -240, 15, "old"),
    (318, 0, -268, 18, "checkpoint"),
    (410, 0, -262, 18, "checkpoint"),
    (490, 0, -222, 20, "avenue", {"gap": True, "gap_span": (0.40, 0.60), "ramp_lift": 2.2}),
    (560, 0, -150, 20, "avenue"),
    (600, 0, -60, 21, "yard"),
    (595, 0, 40, 21, "yard"),
    (575, -1.6, 88, 19, "cut", {"height": 3.6}),
    (545, -4, 125, 18, "underpass"),
    (465, -7, 178, 18, "underpass"),
    (375, -6, 200, 18, "underpass"),
    (330, -3.6, 207, 20, "cut", {"height": 4.6}),
    (275, -0.5, 214, 22, "avenue"),
    (195, 3, 222, 20, "overpass"),
    (100, 6, 210, 20, "overpass"),
    (20, 2, 168, 20, "avenue"),
    (-60, 0, 120, 20, "avenue"),
    (-125, 0, 60, 22, "plaza"),
    (-110, 0, 8, 24, "plaza"),
    (-60, 0, 0, 24, "plaza"),
]
CTRL = [c if len(c) > 5 else c + ({},) for c in CTRL]

# the canal runs straight across the city: under the jump and under the overpass
CANAL = (np.array([640.0, -298.0]), np.array([60.0, 268.0]))
CANAL_HALF = 11.0
WATER = -11.0

TRACK = {
    "id": "ct17",
    "name": "CT17",
    "ctrl": CTRL,
    "items": [0.12, 0.37, 0.6, 0.83],
    "boosts": [0.03, 0.46, 0.79],
    "vmax": 38.0,
    "offtrack": 40.0,
    "sky": "sky_day01_01",
    "water": {"level": WATER},
    "background": "city17",
    "citadel": [-950, -200, 240, 9.0],
    "gantry": "combine",
    "env": {"fog_begin": 260.0, "fog_end": 2600.0},
}


def styles(m):
    curb = m.hl2("concrete/concretefloor019a")
    road = m.hl2("concrete/concretefloor037a")
    concrete = m.hl2("concrete/concretewall008a")
    jersey = {"kind": "jersey", "mat": m.hl2("concrete/concretewall064a")}
    return {
        "plaza": {"kind": "street", "road": m.hl2("stone/stonefloor006d_c17"), "road_rep": 4.0, "curb": curb,
                  "walk": 7.0, "walk_mat": m.hl2("concrete/concretefloor028c_c17"),
                  "barrier": {"kind": "wall", "mat": m.hl2("stone/stonewall022a_c17"), "h": 0.9, "rep": 3.0}},
        "old": {"kind": "street", "road": m.hl2("stone/cobble08a"), "road_rep": 3.0, "curb": curb, "walk": 3.0,
                "walk_mat": m.hl2("concrete/concretefloor028c"),
                "barrier": {"kind": "wall", "mat": m.hl2("stone/stonewall022b_c17"), "h": 1.1, "rep": 3.0}},
        "avenue": {"kind": "street", "road": road, "road_u": "full", "curb": curb, "walk": 4.5,
                   "walk_mat": m.hl2("concrete/concretefloor028c_c17"), "barrier": jersey, "skirt": concrete},
        "checkpoint": {"kind": "street", "road": road, "road_u": "full", "curb": curb, "walk": 3.5,
                       "walk_mat": m.hl2("concrete/concretefloor033k_c17"),
                       "barrier": {"kind": "wall", "mat": m.hl2("metal/citadel_metalwall072a"), "h": 3.2,
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
        "overpass": {"kind": "bridge", "road": road, "road_u": "full", "skirt": concrete, "barrier": jersey,
                     "pillar": concrete, "pillar_every": 22.0, "pillar_size": 1.8},
    }


def _canal_dist(P):
    a, b = CANAL
    ab = b - a
    t = np.clip(((P - a) @ ab) / (ab @ ab), 0.0, 1.0)
    q = a + t[:, None] * ab
    return np.linalg.norm(P - q, axis=1)


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
        h = carve(f, nat, trk, flat=9.0, blend=24.0, tunnel_cover=2.5, gap_floor=WATER - 3.0)
        # the canal cuts through the shoulders too (it passes under the jump and the overpass)
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


BUILDINGS = ["props_buildings/row_res_1_fullscale", "props_buildings/row_res_2_fullscale",
             "props_buildings/row_corner_1_fullscale", "props_buildings/building_002a",
             "props_buildings/row_church_fullscale", "props_buildings/long_building001a",
             "props_buildings/short_building001a", "props_buildings/row_res_2_ascend_fullscale"]
TOWERS = ["props_buildings/project_building01", "props_buildings/project_building02",
          "props_buildings/project_building03"]


def _canal_clear(ctx, model, q, yaw):
    pts = np.array(ctx.footprint(model, q, yaw))
    return bool((_canal_dist(pts) > CANAL_HALF + 4.0).all())


def decorate(ctx):
    t = ctx.trk
    rng = ctx.rng
    # building rows behind the pavements
    for sgn in (-1, 1):
        ctx.row_along({"plaza"}, BUILDINGS, sgn, 7.0 + 2.2, gap=0.5)
        ctx.row_along({"old"}, BUILDINGS[::-1], sgn, 3.0 + 1.8, gap=0.0)
        ctx.row_along({"avenue"}, BUILDINGS[2:] + BUILDINGS[:2], sgn, 4.5 + 2.4, gap=1.0)
        ctx.row_along({"checkpoint"}, ["props_buildings/long_building001a", "props_buildings/short_building001a"],
                      sgn, 3.5 + 3.0, gap=2.0)
    # the rest of the city: tower blocks and rows on a loose grid, clear of the circuit
    for x in np.arange(-520, 1120, 46.0):
        for z in np.arange(-720, 720, 46.0):
            q = np.array([x + rng.uniform(-8, 8), 0.0, z + rng.uniform(-8, 8)])
            gap = ctx.road_gap_to(q)
            if gap < 22 or gap > 430:
                continue
            g = ctx.ground(q[0], q[2])
            if g < -2.0 or g > 6.0:
                continue
            q[1] = g
            m = TOWERS[int(rng.integers(0, 3))] if gap > 120 or rng.random() < 0.25 else BUILDINGS[int(rng.integers(0, len(BUILDINGS)))]
            yaw = float(rng.integers(0, 4)) * np.pi / 2
            if not ctx.fits(m, q, yaw, 14.0) or not _canal_clear(ctx, m, q, yaw):
                continue
            if any(np.hypot(p["pos"][0] - q[0], p["pos"][2] - q[2]) < 30 for p in ctx.props if p.get("tag") == "building"):
                continue
            ctx.add(m, q, yaw, tag="building", ground=False)
    # street lamps and traffic lights on the pavements
    for i in ctx.every(32.0):
        if t.kind(i) != "street" or t.gap[i]:
            continue
        st = t.styles[t.style[i]]
        for sgn in (-1, 1):
            q = ctx.side(i, sgn, 0.3 + st.get("walk", 3.0) * 0.35)
            q[1] = t.pos[i][1] + 0.16
            ctx.add("props_c17/lamppost03a_on", q, ctx.yaw_facing(-t.flat_right[i] * sgn), ground=False)
    # plaza: station arcade columns, benches, the horse statue, Breencast screens
    plaza = [i for i in range(t.n) if t.style[i] == "plaza"]
    for k, i in enumerate(plaza[::18]):
        for sgn in (-1, 1):
            q = ctx.side(i, sgn, 0.3 + 5.6)
            q[1] = t.pos[i][1] + 0.16
            ctx.add("props_trainstation/trainstation_column001", q, ctx.yaw_facing(t.fwd[i]), ground=False)
    for k, i in enumerate(plaza[9::36]):
        sgn = 1 if k % 2 else -1
        q = ctx.side(i, sgn, 0.3 + 3.0)
        q[1] = t.pos[i][1] + 0.16
        ctx.add("props_trainstation/benchoutdoor01a", q, ctx.yaw_facing(-t.flat_right[i] * sgn), ground=False)
    ctx.screens = []
    for frac, sgn in ((0.035, -1), (0.94, 1)):
        i = int(frac * t.n)
        q = ctx.side(i, sgn, 7.0 + 2.0)
        q[1] = t.pos[i][1] + 13.0
        ctx.screens.append({"pos": q.tolist(), "yaw": float(ctx.yaw_facing(-t.flat_right[i] * sgn)), "w": 10.0,
                            "h": 5.6})
    # Combine checkpoint: barricades on the pavement, booths, a watchtower, floodlights
    chk = [i for i in range(t.n) if t.style[i] == "checkpoint"]
    for k, i in enumerate(chk[::7]):
        for sgn in (-1, 1):
            q = ctx.side(i, sgn, 0.3 + 1.7)
            q[1] = t.pos[i][1] + 0.16
            ctx.add("props_combine/combine_barricade_tall01a", q, ctx.yaw_facing(-t.flat_right[i] * sgn), ground=False)
    if chk:
        mid = chk[len(chk) // 2]
        for sgn in (-1, 1):
            q = ctx.side(mid, sgn, 3.5 + 5.0)
            q[1] = 0.0
            ctx.add("props_combine/combine_booth_med01a", q, ctx.yaw_facing(-t.flat_right[mid] * sgn), ground=False)
        q = ctx.side(chk[0], 1, 3.5 + 6.0)
        q[1] = 0.0
        ctx.add("props_combine/combinetower001", q, 0.0, ground=False)
        q = ctx.side(chk[-1], -1, 3.5 + 6.0)
        q[1] = 0.0
        ctx.add("props_combine/combine_bunker01", q, ctx.yaw_facing(t.flat_right[chk[-1]]), ground=False)
    # canal dressing: footbridges and the lock gate where it leaves the city
    a, b = CANAL
    d = (b - a) / np.linalg.norm(b - a)
    for s in (90.0, 300.0, 560.0, 720.0):
        c = a + d * s
        if ctx.road_gap_to([c[0], 0, c[1]]) < 40:
            continue
        ctx.add("props_canal/canal_bridge01", [c[0], 0.0, c[1]], float(np.arctan2(d[0], d[1])) + np.pi / 2, ground=False,
                tag="bridge")
    # rail yard: wagons and engines on sidings, a light tower, signals
    yard = [i for i in range(t.n) if t.style[i] == "yard"]
    cars = ["props_trainstation/boxcar", "props_trainstation/train001", "props_trainstation/tanker",
            "props_trainstation/flatcar", "props_trainstation/boxcar2", "props_trainstation/train002"]
    for k, i in enumerate(yard[::14]):
        for sgn, dist in ((-1, 13.0), (1, 14.0), (1, 22.0)):
            q = ctx.side(i, sgn, dist)
            q[1] = ctx.ground(q[0], q[2])
            ctx.add(cars[(k + int(dist)) % len(cars)], q, ctx.yaw_facing(t.fwd[i]), ground=True)
    if yard:
        i = yard[len(yard) // 2]
        q = ctx.side(i, -1, 32.0)
        q[1] = ctx.ground(q[0], q[2])
        ctx.add("props_trainstation/lighttowercluster01", q, 0.0)
        for i in yard[5::40]:
            q = ctx.side(i, 1, 7.5)
            q[1] = ctx.ground(q[0], q[2])
            ctx.add("props_trainstation/light_signal001a", q, ctx.yaw_facing(-t.fwd[i]))
    # trains parked on the embankment over the underpass
    tun = [i for i in range(t.n) if t.style[i] == "underpass"]
    for k, i in enumerate(tun[12::22]):
        q = t.pos[i].copy()
        q[1] = t.pos[i][1] + t.height[i] + 2.5
        ctx.add(cars[k % len(cars)], q, ctx.yaw_facing(t.fwd[i]), ground=False)
    # the boulevard toward the Citadel: Combine machinery along it
    blv = [i for i in range(t.n) if t.style[i] == "avenue" and t.pos[i][2] > 120]
    for k, i in enumerate(blv[::30]):
        sgn = 1 if k % 2 else -1
        q = ctx.side(i, sgn, 4.5 + 9.0)
        q[1] = ctx.ground(q[0], q[2])
        ctx.add(["props_combine/combinebuttress", "props_combine/combine_generator01",
                 "props_combine/combine_emitter01"][k % 3], q, ctx.yaw_facing(-t.flat_right[i] * sgn))
    # a few physics props at the outside of slow corners (not on the racing line)
    for i in ctx.every(140.0, 60.0):
        if t.gap[i] or abs(t.curv[i]) < 0.012 or t.kind(i) == "tunnel":
            continue
        sgn = 1 if t.curv[i] < 0 else -1
        base = t.pos[i] + t.right[i] * sgn * (t.width[i] / 2 - 1.2)
        for k in range(3):
            q = base + t.fwd[i] * rng.uniform(-3, 3) - t.right[i] * sgn * rng.uniform(0, 1.0)
            ctx.add(["props_junk/trafficcone001a", "props_c17/oildrum001", "props_junk/wood_crate001a"][k],
                    q + t.up[i] * 0.5, rng.uniform(0, 6.28), physics=True, ground=False)
