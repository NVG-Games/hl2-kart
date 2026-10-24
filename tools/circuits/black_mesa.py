"""Black Mesa: an indoor lap of the Research Facility, about 1.9 km.

The Sector C lobby, office corridors, the Anomalous Materials lab wing, the
tram tunnel, a high-security storage hall, waste processing with toxic channels
and a jump over a slime pit, then a spiral bridge around the glowing Lambda
reactor core and back up to the lobby.
"""
import math

import numpy as np

from track_gen import UP

K = 1.18  # plan scale of the layout below
ROOM_C = np.array([90.0 * K, 0.0, 100.0 * K])
ROOM_R = 75.0 * K
SPIRAL_R = 48.0 * K
POOL_Y = -26.0
ROOF_Y = 22.0


def _spiral():
    pts = []
    angs = list(range(35, -180, -25)) + [-175]
    for k, a in enumerate(angs):
        r = math.radians(a)
        y = -14.0 + 10.0 * k / (len(angs) - 1)
        pts.append((ROOM_C[0] + math.cos(r) * SPIRAL_R, y, ROOM_C[2] + math.sin(r) * SPIRAL_R, 14, "reactor",
                    {"spiral": True}))
    return pts


CTRL = [
    (0, 0, 0, 22, "lobby"),
    (95, 0, 0, 22, "lobby"),
    (150, 0, -22, 14, "office"),
    (178, 0, -78, 14, "office"),
    (168, 0, -140, 14, "office"),
    (205, -1.5, -195, 16, "lab"),
    (280, -4, -218, 16, "lab"),
    (350, -8, -195, 15, "tram"),
    (420, -11, -145, 15, "tram"),
    (462, -12, -65, 15, "tram"),
    (468, -12, 25, 15, "tram"),
    (432, -12, 110, 20, "storage"),
    (345, -12, 160, 20, "storage"),
    (262, -13, 168, 13, "waste", {"gap": True, "gap_span": (0.42, 0.62), "ramp_lift": 1.4}),
    (190, -14, 152, 13, "waste"),
    (155, -14, 142, 14, "reactor"),
] + _spiral() + [
    (15, -4, 100, 14, "corridor"),
    (-35, -3, 85, 14, "corridor"),
    (-62, -1, 45, 14, "corridor"),
    (-55, 0, 8, 18, "corridor"),
    (-30, 0, 0, 22, "lobby"),
]
CTRL = [c if len(c) > 5 else c + ({},) for c in CTRL]
CTRL = [c if c[5].get("spiral") else (c[0] * K, c[1], c[2] * K) + tuple(c[3:]) for c in CTRL]

TRACK = {
    "id": "black_mesa",
    "music": ['hl1_song10', 'hl1_song11', 'hl1_song14', 'hl1_song15', 'hl1_song17', 'hl1_song25_remix3'],
    "name": "Black Mesa",
    "ctrl": CTRL,
    "items": [0.1, 0.33, 0.56, 0.8],
    "boosts": [0.02, 0.4, 0.66],
    "vmax": 34.0,
    "offtrack": 30.0,
    "sky": "sky_day01_01",
    "background": "none",
    "gantry": "blackmesa",
    "env": {"sun_energy": 0.0, "ambient": [0.36, 0.37, 0.4], "ambient_energy": 1.0, "fog_begin": 120.0,
            "fog_end": 700.0, "fog_color": [0.08, 0.09, 0.1], "sdfgi": False, "exposure": 1.15, "glow": 0.6},
}


def styles(m):
    g = m.goldsrc
    stripe = g("stripes1")
    return {
        "lobby": {"kind": "tunnel", "road": g("c1a0_labflr"), "road_rep": 3.0, "height": 12.0, "wall": g("fifties_w12"),
                  "side_floor": g("c1a0_labflrb"),
                  "wall_rep": 3.0, "band": g("c2a4e_w1"), "band_h": 2.4, "band_rep": 2.4, "ceil": g("fifties_ceil02"),
                  "ceil_rep": 3.0, "light": g("panellite1", glow=True), "light_every": 9.0,
                  "light_rows": [-0.6, 0.0, 0.6], "light_w": 2.2, "light_l": 3.2, "light_color": [1.0, 0.96, 0.88],
                  "light_energy": 1.6, "wall_gap": 4.0},
        "office": {"kind": "tunnel", "road": g("fifties_flr03"), "road_rep": 2.5, "height": 6.5, "wall": g("fifties_w13"),
                   "wall_rep": 3.0, "band": g("lab1_w6"), "band_h": 1.2, "ceil": g("fifties_ceil01"), "ceil_rep": 2.5,
                   "light": g("litepanel1", glow=True), "light_every": 8.0, "light_rows": [-0.4, 0.4], "light_w": 1.6,
                   "light_l": 2.4, "light_color": [1.0, 0.95, 0.85], "light_energy": 1.3, "wall_gap": 1.0},
        "lab": {"kind": "tunnel", "road": g("lab1_flr4"), "road_rep": 3.0, "height": 8.0, "wall": g("lab1_w4"),
                "wall_rep": 2.5, "band": stripe, "band_h": 0.8, "band_rep": 1.0, "ceil": g("lab1_w8ceil1"),
                "ceil_rep": 2.5, "light": g("skkylite", glow=True), "light_every": 9.0, "light_rows": [-0.45, 0.45],
                "light_color": [0.9, 0.95, 1.0], "light_energy": 1.5, "wall_gap": 3.0},
        "tram": {"kind": "tunnel", "road": g("tnnl_flr1"), "road_rep": 4.0, "height": 9.0, "wall": g("tnnl_w12a"),
                 "wall_rep": 4.0, "band": g("c1a4_w5"), "band_h": 2.0, "band_rep": 2.0, "ceil": g("crete3_ceil01"),
                 "ceil_rep": 3.0, "light": g("~tracklite"), "light_every": 14.0, "light_rows": [-0.85, 0.85],
                 "light_w": 0.8, "light_l": 3.0, "light_color": [1.0, 0.82, 0.55], "light_energy": 1.4, "wall_gap": 1.0},
        "storage": {"kind": "tunnel", "road": g("crete4_flr01"), "road_rep": 4.0, "height": 16.0, "wall": g("silo2_wall1"),
                    "side_floor": g("crete2_flr01"),
                    "wall_rep": 4.0, "band": stripe, "band_h": 1.0, "band_rep": 1.0, "ceil": g("drkmtlt_ceil01"),
                    "ceil_rep": 4.0, "light": g("c3a2_light", glow=True), "light_every": 12.0,
                    "light_rows": [-0.7, 0.0, 0.7], "light_w": 2.0, "light_l": 2.6, "light_color": [1.0, 0.9, 0.75],
                    "light_energy": 1.7, "wall_gap": 9.0},
        "waste": {"kind": "tunnel", "road": g("c1a1_flr2a"), "road_rep": 3.0, "height": 9.0, "wall": g("c2a4e_w1"),
                  "wall_rep": 3.0, "ceil": g("crete3_ceil01"), "light": g("~light5a"), "light_every": 12.0,
                  "light_rows": [-0.9, 0.9], "light_w": 0.8, "light_l": 3.2, "light_color": [0.55, 1.0, 0.55],
                  "light_energy": 1.5, "wall_gap": 6.0,
                  "pit": {"mat": g("!toxicgrn", glow=True), "depth": 1.4, "glow": True},
                  "gap_pit": {"mat": g("!toxicgrn", glow=True), "depth": 4.0, "glow": True},
                  "barrier": {"kind": "fence", "mat": g("{grate2"), "h": 1.1, "rep": 2.0}},
        "reactor": {"kind": "bridge", "road": g("tnnl_flr4"), "road_rep": 4.0, "skirt": g("metal_wall04"),
                    "barrier": {"kind": "fence", "mat": g("{grate2"), "h": 1.2, "rep": 2.0}, "pillar": g("metal_wall04"),
                    "pillar_floor": POOL_Y, "pillar_every": 26.0, "pillar_size": 1.6},
        "corridor": {"kind": "tunnel", "road": g("crete2_flr01"), "road_rep": 3.0, "height": 8.0, "wall": g("c2a4e_w1"),
                     "wall_rep": 3.0, "band": stripe, "band_h": 0.7, "band_rep": 1.0, "ceil": g("crete3_ceil01"),
                     "light": g("litepanel1", glow=True), "light_every": 10.0, "light_rows": [0.0], "light_w": 1.6,
                     "light_color": [0.95, 0.97, 1.0], "light_energy": 1.4, "wall_gap": 1.0},
    }


def STARTLINE(m):
    return m.goldsrc("stripes1")


def _ring(mesh, mat, y0, y1, r, a0, a1, segs, inward=True, rep=4.0):
    """Part of a cylinder wall around the room centre between angles a0..a1 (radians)."""
    ang = np.linspace(a0, a1, segs + 1)
    lo = np.stack([ROOM_C[0] + np.cos(ang) * r, np.full(segs + 1, y0), ROOM_C[2] + np.sin(ang) * r], 1)
    hi = lo.copy()
    hi[:, 1] = y1
    nrm = np.stack([np.cos(ang), np.zeros(segs + 1), np.sin(ang)], 1)
    u = (ang - a0) * r / rep
    if inward:
        mesh.strip(mat, hi, lo, (y1 - y0) / rep, 0.0, u, -nrm, -nrm)
    else:
        mesh.strip(mat, lo, hi, 0.0, (y1 - y0) / rep, u, nrm, nrm)


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


def reactor_room(ctx):
    g = ctx.mats.goldsrc
    m = ctx.meshes
    wall = g("babtech7")
    # doorways: the waste tunnel comes in at 35 degrees, the exit corridor leaves at 180
    doors = [(math.radians(35.0), -14.0), (math.radians(180.0), -4.0)]
    half = math.radians(7.5)
    edges = sorted([(a - half, a + half, y) for a, y in doors])
    # wall below the door tops: arcs between the doorways; above them: the full ring
    # walk the circle from -90 degrees so no doorway straddles the seam
    start = -math.pi / 2
    arcs = []
    for a0, a1, y in edges:
        arcs.append((start, a0))
        start = a1
    arcs.append((start, 1.5 * math.pi))
    for a0, a1 in arcs:
        if a1 > a0:
            _ring(m["walls"], wall, POOL_Y, -2.0 + 9.0, ROOM_R, a0, a1, max(4, int((a1 - a0) * 20)))
    _ring(m["walls"], wall, 7.0, ROOF_Y, ROOM_R, -math.pi, math.pi, 120)
    for a0, a1, y in edges:
        _ring(m["walls"], wall, POOL_Y, y - 0.5, ROOM_R, a0, a1, 6)
        _ring(m["walls"], wall, y + 9.0, 7.0 + 0.1, ROOM_R, a0, a1, 6)
    # coolant pool, roof, the core and its glowing bands
    _disc(m["glow"], g("!waterblue", glow=True), POOL_Y + 2.0, 0.0, ROOM_R, True)
    _disc(m["ceil"], g("drkmtlt_ceil01"), ROOF_Y, 0.0, ROOM_R, False)
    core = g("~light5a")
    ctx.cylinder(g("c3a2_ceil"), [ROOM_C[0], POOL_Y, ROOM_C[2]], 14.0, ROOF_Y - POOL_Y, segs=40)
    for y in np.arange(POOL_Y + 4.0, ROOF_Y - 2.0, 6.0):
        ctx.cylinder(core, [ROOM_C[0], y, ROOM_C[2]], 14.15, 1.2, segs=40, kind="glow")
    ctx.light([ROOM_C[0], -8.0, ROOM_C[2]], [0.5, 0.75, 1.0], 120.0, 4.5)
    ctx.light([ROOM_C[0], 10.0, ROOM_C[2]], [0.5, 0.75, 1.0], 100.0, 3.0)
    for k in range(12):
        a = k * math.pi / 6
        r = SPIRAL_R
        ctx.light([ROOM_C[0] + math.cos(a) * r, 2.0, ROOM_C[2] + math.sin(a) * r], [0.85, 0.9, 1.0], 34.0, 1.8)
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
        runs.setdefault(t.style[i], []).append(i)
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
    for style, names in signs.items():
        ids = runs.get(style, [])
        for k, i in enumerate(ids[20::45]):
            sgn = 1 if k % 2 else -1
            nm = names[k % len(names)]
            ctx.wall_sign(i, sgn, g(nm), 5.0, 2.6 if "sign1" in nm or "wdsign" in nm else 2.0, 3.2)
    # lobby: security desk, columns, vending machines, a scientist waiting
    lob = runs.get("lobby", [])
    for k, i in enumerate(lob[6::14]):
        for sgn in (-1, 1):
            q = ctx.side(i, sgn, 1.6)
            ctx.box(g("fifties_w12"), q + UP * 6.0, [1.6, 12.0, 1.6], ctx.yaw_facing(t.fwd[i]))
    if lob:
        i = lob[len(lob) // 3]
        q = ctx.side(i, 1, 2.5)
        ctx.add("props_lab/securitybank", q, ctx.yaw_facing(-t.flat_right[i]), ground=False)
        q = ctx.side(i, -1, 2.6)
        ctx.add("props_interiors/vendingmachinesoda01a", q, ctx.yaw_facing(t.flat_right[i]), ground=False)
        q = ctx.side(lob[len(lob) // 2], -1, 2.0)
        ctx.add("hl1/scientist", q, ctx.yaw_facing(t.flat_right[lob[len(lob) // 2]]), ground=False)
    # offices: desks, lockers, file cabinets against the walls
    off = runs.get("office", [])
    office_props = ["props_interiors/furniture_desk01a", "props_c17/lockers001a", "props_lab/filecabinet02",
                    "props_wasteland/controlroom_desk001a", "props_interiors/vendingmachinesoda01a"]
    for k, i in enumerate(off[5::16]):
        sgn = 1 if k % 2 else -1
        q = ctx.side(i, sgn, 0.6)
        ctx.add(office_props[k % len(office_props)], q, ctx.yaw_facing(-t.flat_right[i] * sgn), ground=False)
    # labs: workspaces, servers, the test chamber crystal on its holder
    lab = runs.get("lab", [])
    lab_props = ["props_lab/workspace001", "props_lab/servers", "props_lab/workspace003", "props_lab/generatorconsole",
                 "props_lab/hev_machine", "props_lab/workspace002"]
    for k, i in enumerate(lab[4::12]):
        sgn = 1 if k % 2 else -1
        q = ctx.side(i, sgn, 1.4)
        ctx.add(lab_props[k % len(lab_props)], q, ctx.yaw_facing(-t.flat_right[i] * sgn), ground=False)
    if lab:
        i = lab[len(lab) // 2]
        q = ctx.side(i, 1, 1.6)
        ctx.add("props_lab/crystalholder_bars", q, 0.0, ground=False)
        ctx.add("props_lab/crystalholder_crystal", q + UP * 1.0, 0.0, ground=False)
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
    # storage hall: crate stacks, forklifts and the loader between the road and the walls
    sto = runs.get("storage", [])
    crates = ["props_junk/wood_crate001a", "props_junk/wood_crate002a", "props_junk/wood_pallet001a",
              "props_junk/plasticcrate01a"]
    for k, i in enumerate(sto[3::6]):
        for sgn in (-1, 1):
            base = ctx.side(i, sgn, 3.0 + rng.uniform(0, 3.0))
            for lvl in range(int(rng.integers(1, 4))):
                ctx.add(crates[(k + lvl) % 2], base + UP * (lvl * 1.1), rng.uniform(-0.2, 0.2), ground=False)
    for k, i in enumerate(sto[10::30]):
        sgn = 1 if k % 2 else -1
        q = ctx.side(i, sgn, 6.0)
        ctx.add("hl1/forklift" if k % 2 else "hl1/loader", q, ctx.yaw_facing(t.fwd[i]), ground=False)
    # waste processing: pipes and tanks behind the toxic channels
    wst = runs.get("waste", [])
    for k, i in enumerate(wst[4::14]):
        sgn = 1 if k % 2 else -1
        q = ctx.side(i, sgn, 4.5) - UP * 1.4
        ctx.add(["props_wasteland/coolingtank02", "props_wasteland/pipecluster001a", "props_lab/pipesystem02a"][k % 3],
                q, ctx.yaw_facing(-t.flat_right[i] * sgn), ground=False)
    # corridor back to the lobby: sentry guns watching, a scientist or two
    cor = runs.get("corridor", [])
    for k, i in enumerate(cor[8::25]):
        sgn = 1 if k % 2 else -1
        q = ctx.side(i, sgn, 0.5)
        ctx.add("hl1/sentry" if k % 2 else "hl1/scientist", q, ctx.yaw_facing(-t.flat_right[i] * sgn), ground=False)


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
