"""Procedural race track built from Half-Life 2 materials and props.

Writes hl2kart/assets/track/<name>.gltf (+.bin) with visual+collision meshes and
<name>.json with the racing line, spawn grid, item rows, prop placements.
Coordinates are Godot's: Y up, metres; the loop runs clockwise seen from above.
"""
import json
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import materials  # noqa: E402
import srcfs  # noqa: E402
from mdl import GLTFBuilder, gltf_material  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.normpath(os.path.join(HERE, "..", "assets"))
OUT_DIR = os.path.join(ASSETS, "track")
SEA_LEVEL = -13.0
RNG = np.random.default_rng(1998)

# ---------------------------------------------------------------- layout
# (x, y, z, width, theme, flags)
CTRL = [
    (-90, 0, 0, 22, "city", {}),
    (0, 0, 0, 22, "city", {"start": True}),
    (150, 0, -4, 22, "city", {}),
    (225, 0, 25, 21, "city", {}),
    (262, 0, 100, 20, "city", {}),
    (240, 0, 185, 20, "city", {}),
    (262, 0, 262, 20, "city", {"gate": True}),
    (330, -2, 330, 19, "coast", {}),
    (430, -6, 372, 19, "coast", {}),
    (545, -8, 400, 19, "coast", {}),
    (630, -8, 465, 19, "coast", {}),
    (650, -7, 570, 19, "coast", {}),
    (590, -6, 660, 19, "coast", {}),
    (480, -5, 700, 19, "coast", {"gap": True}),
    (360, -5, 712, 19, "coast", {}),
    (245, -4, 690, 19, "dirt", {}),
    (160, -2, 630, 18, "dirt", {}),
    (110, -1, 545, 18, "dirt", {}),
    (60, -7, 470, 17, "canal", {}),
    (-5, -9, 405, 17, "canal", {}),
    (-90, -9, 345, 17, "canal", {}),
    (-150, -8, 255, 17, "canal", {}),
    (-170, -3, 150, 18, "city", {}),
    (-160, 0, 60, 20, "city", {}),
]

LAYOUT_SCALE = 0.8
CTRL = [(x * LAYOUT_SCALE, y, z * LAYOUT_SCALE, w, th, fl) for (x, y, z, w, th, fl) in CTRL]

THEME_ROAD = {
    "city": "concrete/concretefloor037a",
    "coast": "concrete/forest_road01",
    "dirt": "nature/dirtroad001a",
    "canal": "concrete/concretefloor011a",
}
TEX_LEN = {"city": 1.0, "coast": 1.0, "dirt": 1.6, "canal": 0.5}  # v repeat per width
SIDEWALK_MAT = "concrete/concretefloor028c"
CURB_MAT = "concrete/concretefloor019a"
CANAL_WALL_MAT = "concrete/concretewall008a"
BARRIER_MAT = "concrete/concretewall064a"
SKIRT_MAT = "concrete/concretewall008a"
VERGE_MAT = "nature/dirtfloor003a"
VERGE_W = 4.5
VERGE_DROP = 0.27  # terrain sits 0.35 below the edge; the verge ends 8 cm above it
STARTLINE_MAT = "concrete/concretefloor033y"


def catmull_rom_closed(pts, samples_per_seg=60):
    """Centripetal Catmull-Rom through all points (closed). Returns (N,3) and per-sample segment index + t."""
    P = np.asarray(pts, dtype=np.float64)
    n = len(P)
    out, seg, tt = [], [], []
    for i in range(n):
        p0, p1, p2, p3 = P[(i - 1) % n], P[i], P[(i + 1) % n], P[(i + 2) % n]

        def tj(ti, a, b):
            return ti + max(np.linalg.norm(b - a), 1e-6) ** 0.5

        t0 = 0.0
        t1 = tj(t0, p0, p1)
        t2 = tj(t1, p1, p2)
        t3 = tj(t2, p2, p3)
        for k in range(samples_per_seg):
            t = t1 + (t2 - t1) * k / samples_per_seg
            a1 = (t1 - t) / (t1 - t0) * p0 + (t - t0) / (t1 - t0) * p1
            a2 = (t2 - t) / (t2 - t1) * p1 + (t - t1) / (t2 - t1) * p2
            a3 = (t3 - t) / (t3 - t2) * p2 + (t - t2) / (t3 - t2) * p3
            b1 = (t2 - t) / (t2 - t0) * a1 + (t - t0) / (t2 - t0) * a2
            b2 = (t3 - t) / (t3 - t1) * a2 + (t - t1) / (t3 - t1) * a3
            c = (t2 - t) / (t2 - t1) * b1 + (t - t1) / (t2 - t1) * b2
            out.append(c)
            seg.append(i)
            tt.append(k / samples_per_seg)
    return np.array(out), np.array(seg), np.array(tt)


class Track:
    def __init__(self, step=2.0):
        pts = [(c[0], c[1], c[2]) for c in CTRL]
        dense, seg, tt = catmull_rom_closed(pts, 200)
        d = np.linalg.norm(np.diff(np.vstack([dense, dense[:1]]), axis=0), axis=1)
        s = np.concatenate([[0], np.cumsum(d)])
        self.length = s[-1]
        n = int(self.length // step)
        self.step = self.length / n
        target = np.arange(n) * self.step
        idx = np.searchsorted(s, target, side="right") - 1
        frac = (target - s[idx]) / np.maximum(d[idx % len(d)], 1e-9)
        nxt = (idx + 1) % len(dense)
        self.pos = dense[idx] * (1 - frac[:, None]) + dense[nxt] * frac[:, None]
        self.seg = seg[idx]
        segt = tt[idx] + frac / 200.0
        self.n = n
        self.s = target
        # attributes interpolated between control points
        w0 = np.array([CTRL[i][3] for i in self.seg], float)
        w1 = np.array([CTRL[(i + 1) % len(CTRL)][3] for i in self.seg], float)
        sm = segt * segt * (3 - 2 * segt)
        self.width = w0 * (1 - sm) + w1 * sm
        self.theme = [CTRL[i][4] for i in self.seg]
        self.flags = [CTRL[i][5] for i in self.seg]
        self.segt = segt
        self.gap = np.zeros(n, bool)
        self._apply_gap()
        self._frames()

    def _apply_gap(self):
        # gap occupies the middle of the flagged segment; the approach is a kicker ramp
        for i in range(self.n):
            if self.flags[i].get("gap") and 0.42 < self.segt[i] < 0.62:
                self.gap[i] = True
        if not self.gap.any():
            return
        first = int(np.argmax(self.gap))
        ramp = int(16 / self.step)
        for k in range(ramp):
            j = (first - ramp + k) % self.n
            u = (k + 1) / ramp
            self.pos[j, 1] += 1.8 * u * u
        self.gap_start = first
        self.gap_end = first + int(self.gap.sum())

    def _frames(self):
        n = self.n
        f = np.roll(self.pos, -1, axis=0) - np.roll(self.pos, 1, axis=0)
        f /= np.linalg.norm(f, axis=1, keepdims=True)
        self.fwd = f
        right = np.stack([-f[:, 2], np.zeros(n), f[:, 0]], 1)
        right /= np.linalg.norm(right, axis=1, keepdims=True)
        # signed curvature (positive = turning right)
        h = np.stack([f[:, 0], f[:, 2]], 1)
        hn = np.roll(h, -3, axis=0)
        hp = np.roll(h, 3, axis=0)
        cross = hp[:, 0] * hn[:, 1] - hp[:, 1] * hn[:, 0]
        self.curv = cross / (6 * self.step)
        bank = np.clip(self.curv * 120.0, -0.17, 0.17)
        bank = np.where(np.array([t in ("coast", "dirt") for t in self.theme]), bank, 0.0)
        # smooth bank
        for _ in range(30):
            bank = (np.roll(bank, 1) + bank * 2 + np.roll(bank, -1)) / 4
        self.bank = bank
        # rotate right around fwd by bank (right turn => right edge lower)
        c, s_ = np.cos(bank), np.sin(bank)
        up0 = np.cross(right, f)
        self.right = right * c[:, None] - up0 * s_[:, None]
        self.up = np.cross(self.right, f)
        self.up /= np.linalg.norm(self.up, axis=1, keepdims=True)

    def canal_depth(self, ramp_samples=20):
        """0..1 per sample: how deep the canal trench is (ramps in/out at the mouths)."""
        is_c = np.array([t == "canal" for t in self.theme])
        k = np.zeros(self.n)
        if not is_c.any():
            return k
        idx = np.where(~is_c)[0]
        for i in np.where(is_c)[0]:
            d = np.abs(idx - i)
            d = np.minimum(d, self.n - d).min()
            k[i] = d
        k = np.clip(k / ramp_samples, 0, 1)
        return k * k * (3 - 2 * k)

    def edge(self, i, off):
        return self.pos[i] + self.right[i] * off


# ---------------------------------------------------------------- mesh accumulation
class Mesh:
    def __init__(self):
        self.parts = {}  # material -> dict lists

    def part(self, mat):
        if mat not in self.parts:
            self.parts[mat] = {"p": [], "n": [], "uv": [], "c": [], "i": []}
        return self.parts[mat]

    def add(self, mat, p, n, uv, idx, col=None):
        pt = self.part(mat)
        base = sum(len(a) for a in pt["p"])
        pt["p"].append(np.asarray(p, np.float32))
        pt["n"].append(np.asarray(n, np.float32))
        pt["uv"].append(np.asarray(uv, np.float32))
        if col is None:
            col = np.ones((len(p), 4), np.float32)
        pt["c"].append(np.asarray(col, np.float32))
        pt["i"].append(np.asarray(idx, np.int64) + base)

    def strip(self, mat, a, b, ua, ub, v, na=None, nb=None, closed=False):
        """Quad strip between polylines a and b (N,3) with u coords ua/ub and v (N,)."""
        n = len(a)
        p = np.concatenate([a, b])
        if na is None:
            e1 = np.gradient(a, axis=0)
            e2 = b - a
            nn = np.cross(e2, e1)
            nn /= np.maximum(np.linalg.norm(nn, axis=1, keepdims=True), 1e-9)
            na = nb = nn
        nrm = np.concatenate([na, nb])
        uv = np.concatenate([np.stack([np.full(n, ua) if np.isscalar(ua) else ua, v], 1),
                             np.stack([np.full(n, ub) if np.isscalar(ub) else ub, v], 1)])
        m = n if closed else n - 1
        k = np.arange(m)
        k1 = (k + 1) % n
        tri = np.stack([k, k + n, k1, k1, k + n, k1 + n], 1).reshape(-1)
        self.add(mat, p, nrm, uv, tri)


def runs(mask):
    """Contiguous True runs of a boolean array (non-cyclic), returns list of (start, end_exclusive)."""
    out = []
    i, n = 0, len(mask)
    while i < n:
        if mask[i]:
            j = i
            while j < n and mask[j]:
                j += 1
            out.append((i, j))
            i = j
        else:
            i += 1
    return out


def cyc_runs(mask):
    """Runs on a cyclic array, merging wraparound."""
    r = runs(mask)
    n = len(mask)
    if len(r) >= 2 and r[0][0] == 0 and r[-1][1] == n:
        last = r.pop()
        first = r.pop(0)
        r.append((last[0], first[1] + n))
    elif len(r) == 1 and r[0] == (0, n):
        r = [(0, n + 1)]
    return r


# ---------------------------------------------------------------- terrain
def noise2(x, z, seed=0):
    """Cheap smooth value-noise fbm on numpy arrays."""
    def vnoise(x, z, s):
        xi = np.floor(x).astype(np.int64)
        zi = np.floor(z).astype(np.int64)
        xf = x - xi
        zf = z - zi
        def h(a, b):
            v = (a * 374761393 + b * 668265263 + s * 2147483647) & 0xFFFFFFFF
            v = (v ^ (v >> 13)) * 1274126177 & 0xFFFFFFFF
            return (v & 0xFFFF) / 65535.0
        u = xf * xf * (3 - 2 * xf)
        w = zf * zf * (3 - 2 * zf)
        return (h(xi, zi) * (1 - u) * (1 - w) + h(xi + 1, zi) * u * (1 - w) +
                h(xi, zi + 1) * (1 - u) * w + h(xi + 1, zi + 1) * u * w)
    tot = 0
    amp = 1.0
    f = 1.0
    norm = 0
    for o in range(5):
        tot += vnoise(x * f, z * f, seed + o) * amp
        norm += amp
        amp *= 0.5
        f *= 2.0
    return tot / norm


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def build_terrain(trk, x0, z0, x1, z1, cell):
    nx = int((x1 - x0) / cell) + 1
    nz = int((z1 - z0) / cell) + 1
    xs = x0 + np.arange(nx) * cell
    zs = z0 + np.arange(nz) * cell
    X, Z = np.meshgrid(xs, zs)
    P = np.stack([X.ravel(), Z.ravel()], 1)
    rp = trk.pos[:, [0, 2]]
    # nearest road sample per point (chunked brute force)
    near = np.zeros(len(P), np.int64)
    dist = np.zeros(len(P))
    for a in range(0, len(P), 4096):
        q = P[a : a + 4096]
        d2 = ((q[:, None, :] - rp[None, :, :]) ** 2).sum(-1)
        k = np.argmin(d2, axis=1)
        near[a : a + 4096] = k
        dist[a : a + 4096] = np.sqrt(d2[np.arange(len(q)), k])
    lat = ((P - rp[near]) * trk.right[near][:, [0, 2]]).sum(1)
    theme = np.array(trk.theme)[near]
    half = trk.width[near] / 2
    road_h = trk.pos[near, 1]

    # natural landscape
    hills = noise2(P[:, 0] / 140.0, P[:, 1] / 140.0, 7) * 34 - 8
    ridge = noise2(P[:, 0] / 45.0, P[:, 1] / 45.0, 3) * 6
    nat = hills + ridge
    # distance to city / coast parts of the road
    city_d = np.full(len(P), 1e9)
    coast_d_out = np.full(len(P), -1e9)
    is_city = np.array([t == "city" for t in trk.theme])
    is_coast = np.array([t == "coast" for t in trk.theme])
    for a in range(0, len(P), 4096):
        q = P[a : a + 4096]
        if is_city.any():
            d2 = ((q[:, None, :] - rp[None, is_city, :]) ** 2).sum(-1)
            city_d[a : a + 4096] = np.sqrt(d2.min(1))
        if is_coast.any():
            cp = rp[is_coast]
            d2 = ((q[:, None, :] - cp[None, :, :]) ** 2).sum(-1)
            k = np.argmin(d2, axis=1)
            outward = -trk.right[is_coast][k][:, [0, 2]]
            coast_d_out[a : a + 4096] = ((q - cp[k]) * outward).sum(1)
    city_w = smoothstep(170, 90, city_d)
    nat = nat * (1 - city_w) + 0.1 * city_w
    sea_w = smoothstep(25, 150, coast_d_out) * (coast_d_out > 0) * (theme == "coast")
    # the open sea also covers the south-east corner of the map
    se = smoothstep(0, 220, (P[:, 0] - 560 * LAYOUT_SCALE) * 0.6 + (P[:, 1] - 640 * LAYOUT_SCALE) * 0.8)
    sea_w = np.maximum(sea_w, se * smoothstep(60, 140, np.maximum(coast_d_out, 0) + 60) * (theme != "city"))
    sea_w *= smoothstep(150, 260, city_d + noise2(P[:, 0] / 80, P[:, 1] / 80, 21) * 90)
    nat = nat * (1 - sea_w) + (SEA_LEVEL - 14) * sea_w
    # mountains enclosing the north and west
    cx, cz = 230 * LAYOUT_SCALE, 360 * LAYOUT_SCALE
    rr = np.hypot(P[:, 0] - cx, P[:, 1] - cz)
    nat += smoothstep(560 * LAYOUT_SCALE, 760 * LAYOUT_SCALE, rr) * (1 - sea_w) * (60 + noise2(P[:, 0] / 60, P[:, 1] / 60, 11) * 70)

    # carve the road corridor; follow the banked surface across the width
    h = nat.copy()
    right_y = trk.right[near][:, 1]
    surf = road_h + right_y * np.clip(lat, -half, half)
    under = surf - 0.35 - np.abs(right_y) * 1.5
    canal = theme == "canal"
    wall_top = road_h + 1.0 + 6.0 * trk.depth[near]
    flat = half + 6.0
    t = smoothstep(flat, flat + 28.0, dist)
    h_open = under * (1 - t) + nat * t
    h_open = np.where(theme == "city", np.where(dist < half + 9, under + 0.15, under * (1 - t) + nat * t), h_open)
    # canal: inside the trench low, outside at least wall top
    tc = smoothstep(half + 6.0, half + 40.0, dist)
    h_canal = np.where(dist < half + 4.5, under, wall_top * (1 - tc) + np.maximum(nat, wall_top) * tc)
    # shallow ends of the trench: ground comes right up under the lip (no overhang to get stuck below)
    shallow = (trk.depth[near] < 0.3) & (dist > half - 0.5)
    h_canal = np.where(shallow, np.maximum(h_canal, wall_top - 0.12), h_canal)
    h = np.where(canal, h_canal, h_open)
    # gap: water channel under the jump
    if trk.gap.any():
        gi = np.where(trk.gap)[0]
        gp = rp[gi]
        for a in range(0, len(P), 8192):
            q = P[a : a + 8192]
            d2 = ((q[:, None, :] - gp[None, :, :]) ** 2).sum(-1).min(1)
            gd = np.sqrt(d2)
            dip = smoothstep(55, 18, gd)
            h[a : a + 8192] = h[a : a + 8192] * (1 - dip) + (SEA_LEVEL - 6) * dip
    H = h.reshape(nz, nx)

    # blend weights: r = dirt/gravel, g = rock (slopes), b = pavement, a = sand (beach)
    gz, gx = np.gradient(H, cell)
    slope = np.sqrt(gx ** 2 + gz ** 2).ravel()
    dirt = np.clip(smoothstep(half + 7, half + 1.5, dist) * (theme != "city") +
                   (noise2(P[:, 0] / 22, P[:, 1] / 22, 5) - 0.55) * 1.5, 0, 1)
    rock = smoothstep(0.55, 0.95, slope)
    pave = smoothstep(150, 110, city_d) * (theme == "city") + smoothstep(150, 110, city_d) * 0.0
    pave = np.clip(np.where(theme == "city", smoothstep(140, 100, city_d), 0) + city_w * 0.6, 0, 1)
    sand = smoothstep(SEA_LEVEL + 5, SEA_LEVEL + 1.5, h) * (1 - pave)
    col = np.stack([dirt, rock, pave, sand], 1).astype(np.float32)
    return xs, zs, H, col


def terrain_mesh(mesh, xs, zs, H, col, cell):
    nz, nx = H.shape
    X, Z = np.meshgrid(xs, zs)
    p = np.stack([X.ravel(), H.ravel(), Z.ravel()], 1)
    gz, gx = np.gradient(H, cell)
    nrm = np.stack([-gx.ravel(), np.ones(nx * nz), -gz.ravel()], 1)
    nrm /= np.linalg.norm(nrm, axis=1, keepdims=True)
    uv = np.stack([X.ravel(), Z.ravel()], 1) / 4.0
    i = np.arange(nx * nz).reshape(nz, nx)
    a = i[:-1, :-1].ravel()
    b = i[:-1, 1:].ravel()
    c = i[1:, :-1].ravel()
    d = i[1:, 1:].ravel()
    tri = np.stack([a, c, b, b, c, d], 1).reshape(-1)
    mesh.add("terrain", p, nrm, uv, tri, col)


# ---------------------------------------------------------------- road pieces
def build_road(trk, meshes):
    n = trk.n
    road = meshes["road"]
    walls = meshes["walls"]
    side = meshes["side"]
    inv = meshes["colonly"]
    gap = trk.gap
    theme = np.array(trk.theme)
    v_along = np.zeros(n)
    # road surface per theme run (cyclic)
    for th in THEME_ROAD:
        mask = (theme == th) & (~gap)
        for a, b in cyc_runs(mask):
            ids = np.arange(a, b + 1) % n
            hw = trk.width[ids] / 2
            L = trk.pos[ids] - trk.right[ids] * hw[:, None]
            R = trk.pos[ids] + trk.right[ids] * hw[:, None]
            v = trk.s[ids] / (trk.width[ids] * TEX_LEN[th])
            if b >= n:  # wrapped run: keep v continuous
                v = np.where(ids < a, (trk.s[ids] + trk.length) / (trk.width[ids] * TEX_LEN[th]), v)
            road.strip(THEME_ROAD[th], L, R, 0.0, 1.0, v, trk.up[ids], trk.up[ids])

    # verges: gentle drivable slopes from the tarmac edge down to the ground, so a
    # kart that ran wide can always climb back on (no kerb step, no wall)
    open_mask = np.isin(theme, ["coast", "dirt"]) & (~gap)
    for a, b in cyc_runs(open_mask):
        ids = np.arange(a, b + 1) % n
        hw = trk.width[ids] / 2
        vv = trk.s[ids] / 4.0
        for sgn in (-1, 1):
            r = trk.right[ids] * sgn
            flat = r.copy()
            flat[:, 1] = 0.0
            flat /= np.linalg.norm(flat, axis=1, keepdims=True)
            E = trk.pos[ids] + r * hw[:, None]
            drop = VERGE_DROP + np.abs(trk.right[ids][:, 1]) * 1.5
            O = E + flat * VERGE_W - np.array([0.0, 1.0, 0.0]) * drop[:, None]
            if sgn > 0:
                meshes["verge"].strip(VERGE_MAT, E, O, 0.0, 1.0, vv)
            else:
                meshes["verge"].strip(VERGE_MAT, O, E, 1.0, 0.0, vv)
    # concrete skirts only where the road is lifted off the ground (the jump)
    near_gap = np.zeros(n, bool)
    for g in np.where(gap)[0]:
        near_gap[np.arange(g - 45, g + 45) % n] = True
    for a, b in cyc_runs(open_mask & near_gap):
        ids = np.arange(a, b + 1) % n
        hw = trk.width[ids] / 2
        for sgn in (-1, 1):
            E = trk.pos[ids] + trk.right[ids] * sgn * hw[:, None]
            low = E - np.array([0, 3.0, 0])
            vv = trk.s[ids] / 4.0
            nrm = trk.right[ids] * sgn
            if sgn < 0:
                side.strip(SKIRT_MAT, low, E, 0.55, 0.0, vv, nrm, nrm)
            else:
                side.strip(SKIRT_MAT, E, low, 0.0, 0.55, vv, nrm, nrm)

    # city: curbs + sidewalks + invisible walls
    mask = (theme == "city") & (~gap)
    for a, b in cyc_runs(mask):
        ids = np.arange(a, b + 1) % n
        hw = trk.width[ids] / 2
        for sgn in (-1, 1):
            r = trk.right[ids] * sgn
            e0 = trk.pos[ids] + r * hw[:, None]
            e1 = e0 + np.array([0, 0.18, 0])
            e2 = e1 + r * 0.35
            e3 = e2 + r * 6.0
            vv = trk.s[ids] / 3.0
            if sgn > 0:
                side.strip(CURB_MAT, e0, e1, 0.0, 0.06, vv, -r, -r)
                road.strip(CURB_MAT, e1, e2, 0.06, 0.12, vv, trk.up[ids], trk.up[ids])
                road.strip(SIDEWALK_MAT, e2, e3, 0.0, 2.0, trk.s[ids] / 3.0, trk.up[ids], trk.up[ids])
            else:
                side.strip(CURB_MAT, e1, e0, 0.06, 0.0, vv, -r, -r)
                road.strip(CURB_MAT, e2, e1, 0.12, 0.06, vv, trk.up[ids], trk.up[ids])
                road.strip(SIDEWALK_MAT, e3, e2, 2.0, 0.0, trk.s[ids] / 3.0, trk.up[ids], trk.up[ids])
            w0 = e3 + r * 0.3
            w1 = w0 + np.array([0, 6.0, 0])
            if sgn > 0:
                inv.strip("colonly", w0, w1, 0, 1, vv, -r, -r)
            else:
                inv.strip("colonly", w1, w0, 0, 1, vv, -r, -r)

    # canal walls (both sides, tall, with a top lip)
    mask = (theme == "canal") & (~gap)
    for a, b in cyc_runs(mask):
        ids = np.arange(max(a - 3, 0), b + 4) % n
        hw = trk.width[ids] / 2
        for sgn in (-1, 1):
            r = trk.right[ids] * sgn
            base = trk.pos[ids] + r * hw[:, None] - np.array([0, 0.6, 0])
            top = base + np.array([0.0, 1.0, 0.0]) * (1.6 + 6.0 * trk.depth[ids])[:, None]
            # wide enough to cover the terrain cells that dip behind the wall (3 m grid)
            top = top + np.array([0.0, 0.06, 0.0])
            # no lip where the trench is shallow (the ground is already at wall height there)
            lip_w = 7.5 * smoothstep(0.02, 0.3, trk.depth[ids])
            lip = top + r * lip_w[:, None]
            vv = trk.s[ids] / 6.0
            # the lip on top is drivable ground, so a kart up on the bank can roll back in
            up_n = trk.up[ids] * 0 + [0, 1, 0]
            if sgn > 0:
                walls.strip(CANAL_WALL_MAT, base, top, 0.0, 1.0, vv, -r, -r)
                meshes["verge"].strip(CANAL_WALL_MAT, top, lip, 1.0, 1.4, vv, up_n, up_n)
            else:
                walls.strip(CANAL_WALL_MAT, top, base, 1.0, 0.0, vv, -r, -r)
                meshes["verge"].strip(CANAL_WALL_MAT, lip, top, 1.4, 1.0, vv, up_n, up_n)

    # coast: jersey barrier on the sea (outer = left) side
    mask = (theme == "coast") & (~gap)
    for a, b in cyc_runs(mask):
        ids = np.arange(a, b + 1) % n
        hw = trk.width[ids] / 2
        r = -trk.right[ids]
        up = np.array([0, 1.0, 0])
        e = trk.pos[ids] + r * hw[:, None]
        prof = [(0.0, 0.0), (0.0, 0.25), (0.22, 0.55), (0.32, 1.05), (0.62, 1.05), (0.72, 0.55), (0.95, 0.25), (0.95, -1.0)]
        rings = [e + r * dx + up * dy for dx, dy in prof]
        vv = trk.s[ids] / 4.0
        for k in range(len(rings) - 1):
            A, B = rings[k], rings[k + 1]
            walls.strip(BARRIER_MAT, B, A, prof[k + 1][1] * 0.5 + 0.5, prof[k][1] * 0.5 + 0.5, vv)
        # close both ends of the barrier so nothing can slip inside it
        for j, sgn in ((0, -1.0), (len(ids) - 1, 1.0)):
            cap = np.array([rings[k][j] for k in range(len(prof))])
            ctr = cap.mean(0)
            pts = np.vstack([cap, ctr[None]])
            nrm = np.tile(trk.fwd[ids[j]] * sgn, (len(pts), 1))
            uv = np.array([[pp[0] * 0.1, pp[1] * 0.1] for pp in pts[:, [0, 2]]])
            tri = []
            for k in range(len(prof) - 1):
                tri += [k, k + 1, len(prof)] if sgn > 0 else [k + 1, k, len(prof)]
            walls.add(BARRIER_MAT, pts, nrm, uv, tri)
    # gap ends: concrete slab faces
    if trk.gap.any():
        for j, sgn in ((trk.gap_start - 1, 1), (trk.gap_end, -1)):
            j %= n
            hw = trk.width[j] / 2
            c = trk.pos[j]
            Lp = c - trk.right[j] * hw
            Rp = c + trk.right[j] * hw
            d = np.array([0, 3.0, 0])
            f = trk.fwd[j] * sgn
            side.add(SKIRT_MAT, [Lp, Rp, Rp - d, Lp - d], [f] * 4, [[0, 0], [2, 0], [2, 0.6], [0, 0.6]],
                     [0, 1, 2, 0, 2, 3] if sgn > 0 else [0, 2, 1, 0, 3, 2])

    # start line decal
    j = 0
    hw = trk.width[j] / 2
    c = trk.pos[j] + trk.up[j] * 0.03
    a0 = c - trk.right[j] * hw - trk.fwd[j] * 1.5
    a1 = c + trk.right[j] * hw - trk.fwd[j] * 1.5
    b0 = c - trk.right[j] * hw + trk.fwd[j] * 1.5
    b1 = c + trk.right[j] * hw + trk.fwd[j] * 1.5
    meshes["decal"].add(STARTLINE_MAT, [a0, a1, b1, b0], [trk.up[j]] * 4,
                        [[0, 0], [0, 4], [1, 4], [1, 0]], [0, 1, 2, 0, 2, 3])


# ---------------------------------------------------------------- racing line
def racing_line(trk):
    n = trk.n
    off = np.zeros(n)
    lim = trk.width / 2 - 3.8
    base = trk.pos.copy()
    r = trk.right
    for it in range(400):
        p = base + r * off[:, None]
        mid = (np.roll(p, 1, 0) + np.roll(p, -1, 0)) / 2
        off = off + ((mid - p) * r).sum(1) * 0.8
        off = np.clip(off, -lim, lim)
        off[trk.gap] = 0
    p = base + r * off[:, None]
    # curvature -> target speed (lateral accel budget)
    a = np.roll(p, -4, 0) - p
    b = p - np.roll(p, 4, 0)
    ang = np.arctan2(a[:, 0] * b[:, 2] - a[:, 2] * b[:, 0], (a[:, [0, 2]] * b[:, [0, 2]]).sum(1))
    radius = np.abs(4 * trk.step / np.maximum(np.abs(ang), 1e-4))
    v = np.sqrt(14.0 * radius)
    v = np.clip(v, 12, 40)
    for _ in range(4):  # brake ahead of corners
        v = np.minimum(v, np.roll(v, -3) + 2.5)
    return p, off, v


# ---------------------------------------------------------------- props
def load_models():
    with open(os.path.join(ASSETS, "data", "models.json")) as f:
        return json.load(f)


def pick_one(options):
    return options[int(RNG.integers(0, len(options)))]


def place_props(trk, models, terrain_h):
    props = []

    def add(model, pos, yaw=0.0, physics=False, scale=1.0, tag=None, ground=True, pitch=0.0):
        if model not in models:
            return
        p = [float(pos[0]), float(pos[1]), float(pos[2])]
        props.append({"model": model, "pos": p, "yaw": float(yaw), "physics": physics, "scale": scale,
                      "tag": tag, "ground": ground, "pitch": float(pitch)})

    n = trk.n
    theme = np.array(trk.theme)
    road_pts = trk.pos

    def clear_of_road(q, margin):
        d = np.sqrt(((road_pts[:, [0, 2]] - np.array([q[0], q[2]])) ** 2).sum(1))
        return (d - trk.width / 2).min() > margin

    def yaw_facing(dirv):
        # model front is +Z; yaw that maps +Z onto dirv
        return math.atan2(dirv[0], dirv[2])

    # ----- city buildings along both sides
    bld = ["props_buildings/row_res_1_fullscale", "props_buildings/row_res_2_fullscale",
           "props_buildings/row_corner_1_fullscale",
           "props_buildings/building_002a", "props_buildings/row_church_fullscale",
           "props_buildings/long_building001a", "props_buildings/short_building001a"]
    for sgn in (-1, 1):
        i = 0
        cursor = 0.0
        k = 0
        while i < n:
            if theme[i] != "city" or abs(trk.curv[i]) > 0.02:
                i += 1
                continue
            m = bld[(k + (sgn > 0) * 3) % len(bld)]
            mm = models[m]
            wdt = mm["aabb_max"][0] - mm["aabb_min"][0]
            depth_front = mm["aabb_max"][2]
            r = trk.right[i] * sgn
            setback = trk.width[i] / 2 + 6.9 + depth_front
            q = trk.pos[i] + r * setback
            q[1] = 0.0 if trk.pos[i][1] > -2 else trk.pos[i][1]
            edge = trk.pos[i] + r * (trk.width[i] / 2 + 6.9)
            ok = all(clear_of_road(edge + trk.fwd[i] * o, 5.5) for o in (-wdt * 0.45, 0, wdt * 0.45))
            if ok and clear_of_road(q, depth_front + 4.0):
                add(m, q, yaw_facing(-r), tag="building", ground=False)
                k += 1
                i += max(1, int((wdt * 0.92) / trk.step))
            else:
                i += 3
    # tower blocks behind the rows
    for j in range(14):
        i = RNG.integers(0, n)
        if theme[i] != "city":
            continue
        sgn = RNG.choice([-1, 1])
        q = trk.pos[i] + trk.right[i] * sgn * (trk.width[i] / 2 + 70 + RNG.uniform(0, 60))
        if clear_of_road(q, 40):
            add(["props_buildings/project_building01", "props_buildings/project_building02",
                 "props_buildings/project_building03"][j % 3], [q[0], 0.0, q[2]],
                yaw_facing(-trk.right[i] * sgn), tag="building", ground=False)

    # ----- city street furniture
    for i in range(0, n, int(34 / trk.step)):
        if theme[i] != "city":
            continue
        for sgn in (-1, 1):
            r = trk.right[i] * sgn
            q = trk.pos[i] + r * (trk.width[i] / 2 + 6.1)
            q[1] = trk.pos[i][1] + 0.18
            add("props_c17/lamppost03a_off", q, yaw_facing(-r), ground=False)
    for i in range(5, n, int(23 / trk.step)):
        if theme[i] != "city" or RNG.random() < 0.35:
            continue
        sgn = RNG.choice([-1, 1])
        r = trk.right[i] * sgn
        q = trk.pos[i] + r * (trk.width[i] / 2 + 5.0 + RNG.uniform(0, 0.8))
        q[1] = trk.pos[i][1] + 0.2
        pick = RNG.choice(["props_vehicles/car002a_physics", "props_vehicles/car003a_physics",
                           "props_vehicles/car004a_physics", "props_vehicles/car005a_physics",
                           "props_junk/trashdumpster01a", "props_c17/bench01a", "props_junk/trashbin01a",
                           "props_c17/furniturecouch001a", "props_junk/cardboard_box001a",
                           "props_junk/garbage_bag001a", "props_trainstation/trashcan_indoor001a",
                           "props_c17/oildrum001", "props_trainstation/payphone001a"])
        fwd = trk.fwd[i] * RNG.choice([-1, 1])
        phys = pick in ("props_junk/cardboard_box001a", "props_junk/garbage_bag001a", "props_c17/oildrum001",
                        "props_junk/trashbin01a", "props_trainstation/trashcan_indoor001a")
        add(pick, q, yaw_facing(fwd) + (math.pi / 2 if "car0" in pick else 0), physics=phys, ground=False)

    # ----- combine checkpoint at the gate control point
    gate_i = [i for i in range(n) if trk.flags[i].get("gate")]
    if gate_i:
        i = gate_i[len(gate_i) // 2]
        for sgn in (-1, 1):
            r = trk.right[i] * sgn
            for k in range(3):
                q = trk.pos[i] + r * (trk.width[i] / 2 + 1.0 + k * 3.2) + trk.fwd[i] * (k * 1.0)
                add("props_combine/combine_barricade_tall01a", q, yaw_facing(trk.fwd[i]), ground=False, tag="gate")
            q = trk.pos[i] + r * (trk.width[i] / 2 + 4.0) + trk.fwd[i] * 10
            add("props_combine/combine_light001a", q, yaw_facing(-r))
            q = trk.pos[i] + r * (trk.width[i] / 2 + 7.0) - trk.fwd[i] * 6
            add("props_combine/combine_booth_med01a", q, yaw_facing(-r))
        q = trk.pos[i] + trk.up[i] * 0.0
        add("props_combine/combine_barricade_short01a", trk.pos[i] - trk.right[i] * (trk.width[i] / 2 + 2.5) + trk.fwd[i] * 18,
            yaw_facing(trk.right[i]), tag="gate")

    # ----- coast: rocks, trees, power towers, beach dressing
    for i in range(0, n, 3):
        th = theme[i]
        if th not in ("coast", "dirt"):
            continue
        for sgn in (-1, 1):
            if RNG.random() < 0.55:
                continue
            r = trk.right[i] * sgn
            dist = trk.width[i] / 2 + RNG.uniform(9, 55)
            q = trk.pos[i] + r * dist
            if not clear_of_road(q, 7):
                continue
            h = terrain_h(q[0], q[2])
            if h < SEA_LEVEL + 0.5:
                if RNG.random() < 0.15:
                    add(RNG.choice(["props_wasteland/rockgranite02a", "props_wasteland/rockgranite03a",
                                    "props_foliage/rock_coast02a", "props_foliage/rock_coast02c"]),
                        [q[0], h, q[2]], RNG.uniform(0, 6.28))
                continue
            if sgn > 0 or th == "dirt":
                pick = RNG.choice(["props_foliage/tree_pine04", "props_foliage/tree_pine05", "props_foliage/tree_pine_large",
                                   "props_foliage/tree_deciduous_01a", "props_foliage/tree_poplar_01",
                                   "props_wasteland/rockcliff01b", "props_wasteland/rockcliff_cluster01b",
                                   "props_wasteland/rockgranite01a", "props_foliage/shrub_01a", "props_foliage/bush2",
                                   "props_foliage/tree_dead01", "props_foliage/oak_tree01"])
            else:
                pick = RNG.choice(["props_foliage/rock_coast02a", "props_foliage/rock_coast02c",
                                   "props_foliage/driftwood_01a", "props_wasteland/rockgranite04a",
                                   "props_foliage/shrub_01a"])
            add(pick, [q[0], h, q[2]], RNG.uniform(0, 6.28))
    for i in range(0, n, int(70 / trk.step)):
        if theme[i] in ("coast", "dirt"):
            r = trk.right[i]
            q = trk.pos[i] + r * (trk.width[i] / 2 + 34)
            if clear_of_road(q, 20):
                add("props_wasteland/powertower01", [q[0], terrain_h(q[0], q[2]), q[2]], yaw_facing(trk.fwd[i]))
    # sea dressing: buoys, boats, channel markers
    for k in range(18):
        x, z = RNG.uniform(600, 950) * LAYOUT_SCALE, RNG.uniform(560, 950) * LAYOUT_SCALE
        if terrain_h(x, z) < SEA_LEVEL - 3:
            add(RNG.choice(["props_wasteland/buoy01", "props_docks/channelmarker01a", "props_wasteland/boat_fishing01a",
                            "props_canal/boat001a"]), [x, SEA_LEVEL - 0.3, z], RNG.uniform(0, 6.28), tag="float")

    # ----- dirt road dressing: tyre stacks, fences, containers, a thumper
    for i in range(0, n, int(25 / trk.step)):
        if theme[i] != "dirt":
            continue
        sgn = 1 if (i // 7) % 2 else -1
        r = trk.right[i] * sgn
        q = trk.pos[i] + r * (trk.width[i] / 2 + 10.0)
        add("props_wasteland/wood_fence01a", [q[0], terrain_h(q[0], q[2]), q[2]], yaw_facing(trk.fwd[i]))
    dirt_ids = [i for i in range(n) if theme[i] == "dirt"]
    if dirt_ids:
        i = dirt_ids[len(dirt_ids) // 2]
        q = trk.pos[i] + trk.right[i] * (trk.width[i] / 2 + 22)
        add("props_combine/combinethumper002", [q[0], terrain_h(q[0], q[2]), q[2]], 0.3, tag="thumper")
        q = trk.pos[i] - trk.right[i] * (trk.width[i] / 2 + 16)
        add("props_wasteland/cargo_container01", [q[0], terrain_h(q[0], q[2]), q[2]], 1.2)
        q2 = q + trk.fwd[i] * 8
        add("props_wasteland/cargo_container01b", [q2[0], terrain_h(q2[0], q2[2]), q2[2]], 1.4)

    # ----- canal dressing: bridges over the trench, pipes
    canal_ids = [i for i in range(n) if theme[i] == "canal"]
    for k, i in enumerate(canal_ids[10::40]):
        q = trk.pos[i] + np.array([0, 7.0, 0])
        add("props_canal/canal_bridge01", q, yaw_facing(trk.right[i]), ground=False, tag="bridge")

    # ----- physics clutter on the racing surface edges (cones, drums, crates, melons)
    def cluster(i, sgn, items, spread=3.0):
        r = trk.right[i] * sgn
        base = trk.pos[i] + r * (trk.width[i] / 2 - 1.8)
        for it in items:
            q = base + trk.fwd[i] * RNG.uniform(-spread, spread) - r * RNG.uniform(0, 2.0)
            add(it, q + trk.up[i] * 0.5, RNG.uniform(0, 6.28), physics=True, ground=False)

    for i in range(0, n, int(55 / trk.step)):
        if RNG.random() < 0.3 or trk.gap[i]:
            continue
        sgn = 1 if trk.curv[i] < 0 else -1  # outside of the corner
        th = theme[i]
        if th == "city":
            items = pick_one([["props_junk/trafficcone001a"] * 4,
                          ["props_c17/oildrum001", "props_c17/oildrum001", "props_c17/oildrum001_explosive"],
                          ["props_junk/wood_crate001a", "props_junk/wood_crate001a", "props_junk/wood_crate002a"],
                          ["props_junk/watermelon01"] * 3 + ["props_junk/wood_crate001a"]])
        elif th == "canal":
            items = ["props_borealis/bluebarrel001", "props_c17/oildrum001", "props_junk/wood_crate001a"]
        else:
            items = pick_one([["props_junk/trafficcone001a"] * 5,
                          ["props_vehicles/tire001c_car"] * 3,
                          ["props_c17/oildrum001_explosive", "props_c17/oildrum001"]])
        cluster(i, sgn, items)
    # cones guarding the jump approach
    if trk.gap.any():
        for k in range(6):
            i = (trk.gap_start - 8 - k * 4) % n
            for sgn in (-1, 1):
                q = trk.pos[i] + trk.right[i] * sgn * (trk.width[i] / 2 - 0.8)
                add("props_junk/trafficcone001a", q + trk.up[i] * 0.4, 0, physics=True, ground=False)
        i = (trk.gap_start - 2) % n
        for sgn in (-1, 1):
            q = trk.pos[i] + trk.right[i] * sgn * (trk.width[i] / 2 + 2.5)
            add("props_vehicles/tire001a_tractor", q, 0, ground=True)
    return props


# ---------------------------------------------------------------- gameplay data
def gameplay(trk, line, off, vt):
    n = trk.n
    data = {}
    # spawn grid: 8 slots behind the start line, 2 columns staggered
    grid = []
    for k in range(8):
        back = 10 + k * 6.5
        i = int(round(-back / trk.step)) % n
        col = -1 if k % 2 == 0 else 1
        p = trk.pos[i] + trk.right[i] * col * 4.5 + trk.up[i] * 0.8
        grid.append({"pos": p.tolist(), "fwd": trk.fwd[i].tolist()})
    data["grid"] = grid
    # item crate rows
    rows = []
    for frac in (0.13, 0.36, 0.585, 0.83):
        i = int(frac * n)
        while trk.gap[i % n]:
            i += 5
        i %= n
        w = trk.width[i] / 2 - 2.5
        for k in range(5):
            o = -w + 2 * w * k / 4
            p = trk.pos[i] + trk.right[i] * o + trk.up[i] * 1.2
            rows.append(p.tolist())
    data["item_boxes"] = rows
    # boost pads on long straights
    pads = []
    for frac in (0.06, 0.47, 0.71, 0.93):
        i = int(frac * n)
        if trk.gap[i]:
            continue
        p = line[i] + trk.up[i] * 0.06
        pads.append({"pos": p.tolist(), "fwd": trk.fwd[i].tolist(), "up": trk.up[i].tolist()})
    data["boost_pads"] = pads
    step = 3
    ids = np.arange(0, n, step)
    data["path"] = {
        "step": trk.step * step,
        "length": float(trk.length),
        "center": trk.pos[ids].round(3).tolist(),
        "line": line[ids].round(3).tolist(),
        "fwd": trk.fwd[ids].round(4).tolist(),
        "right": trk.right[ids].round(4).tolist(),
        "up": trk.up[ids].round(4).tolist(),
        "width": trk.width[ids].round(2).tolist(),
        "speed": vt[ids].round(2).tolist(),
        "gap": trk.gap[ids].astype(int).tolist(),
        "theme": [trk.theme[i] for i in ids],
    }
    return data


def main():
    name = sys.argv[1] if len(sys.argv) > 1 else "city17_circuit"
    os.makedirs(OUT_DIR, exist_ok=True)
    fs = srcfs.GameFS()
    lib = materials.MaterialLib(fs, ASSETS)
    trk = Track()
    trk.depth = trk.canal_depth()
    print("track length %.0fm, %d samples" % (trk.length, trk.n))
    meshes = {k: Mesh() for k in ("road", "verge", "walls", "side", "colonly", "decal", "terrain")}
    build_road(trk, meshes)
    cell = 3.0
    xs, zs, H, col = build_terrain(trk, -480, -380, 960, 960, cell)
    terrain_mesh(meshes["terrain"], xs, zs, H, col, cell)
    line, off, vt = racing_line(trk)

    def terrain_h(x, z):
        i = np.clip((x - xs[0]) / cell, 0, len(xs) - 1.001)
        j = np.clip((z - zs[0]) / cell, 0, len(zs) - 1.001)
        i0, j0 = int(i), int(j)
        fx, fz = i - i0, j - j0
        return float(H[j0, i0] * (1 - fx) * (1 - fz) + H[j0, i0 + 1] * fx * (1 - fz) +
                     H[j0 + 1, i0] * (1 - fx) * fz + H[j0 + 1, i0 + 1] * fx * fz)

    models = load_models()
    props = place_props(trk, models, terrain_h)
    print("props", len(props))

    b = GLTFBuilder()
    root = b.node({"name": name, "children": []})
    gdir = OUT_DIR

    def rel(p):
        return os.path.relpath(os.path.join(ASSETS, p), gdir).replace("\\", "/")

    mat_ids = {}

    def mat_index(mname):
        if mname in mat_ids:
            return mat_ids[mname]
        if mname == "terrain":
            tex = {"base": "nature/grassfloor002a", "dirt": "nature/dirtfloor003a", "rock": "nature/rockwall006a",
                   "pave": "concrete/concretefloor028c", "sand": "nature/blendcliffsand01a"}
            info = {}
            for k, v in tex.items():
                mi = lib.material(v)
                info[k] = mi.get("albedo")
                if mi.get("normal"):
                    info[k + "_normal"] = mi.get("normal")
            m = {"name": "terrain", "extras": {"source": {"shader": "hl2kart_terrain", "layers": info}},
                 "pbrMetallicRoughness": {"metallicFactor": 0, "roughnessFactor": 1,
                                          "baseColorTexture": {"index": b.image(rel(info["base"]))}}}
        elif mname == "colonly":
            m = {"name": "colonly", "extras": {"source": {"shader": "colonly"}}}
        else:
            info = lib.material(mname)
            m = gltf_material(b, info, rel)
        b.g["materials"].append(m)
        mat_ids[mname] = len(b.g["materials"]) - 1
        return mat_ids[mname]

    for key, mesh in meshes.items():
        prims = []
        for mname, pt in mesh.parts.items():
            p = np.concatenate(pt["p"]).astype(np.float32)
            nrm = np.concatenate(pt["n"]).astype(np.float32)
            uv = np.concatenate(pt["uv"]).astype(np.float32)
            c = np.concatenate(pt["c"]).astype(np.float32)
            idx = np.concatenate(pt["i"])
            attrs = {"POSITION": b.accessor(p, 5126, "VEC3", 34962, minmax=True),
                     "NORMAL": b.accessor(nrm, 5126, "VEC3", 34962),
                     "TEXCOORD_0": b.accessor(uv, 5126, "VEC2", 34962)}
            if key == "terrain":
                attrs["COLOR_0"] = b.accessor(c, 5126, "VEC4", 34962)
            ind = idx.astype(np.uint32)
            prims.append({"attributes": attrs, "indices": b.accessor(ind, 5125, "SCALAR", 34963),
                          "material": mat_index(mname)})
        if not prims:
            continue
        b.g["meshes"].append({"name": key, "primitives": prims})
        b.g["nodes"][root]["children"].append(b.node({"name": key, "mesh": len(b.g["meshes"]) - 1}))
    b.save(os.path.join(OUT_DIR, name + ".gltf"))

    data = gameplay(trk, line, off, vt)
    data["props"] = props
    data["sea_level"] = SEA_LEVEL
    data["sky"] = "sky_day01_01"
    data["terrain"] = {"x0": float(xs[0]), "z0": float(zs[0]), "cell": cell, "nx": len(xs), "nz": len(zs)}
    with open(os.path.join(OUT_DIR, name + ".json"), "w") as f:
        json.dump(data, f)
    H.astype(np.float32).tofile(os.path.join(OUT_DIR, name + "_height.bin"))
    mpath = os.path.join(ASSETS, "data", "materials.json")
    db = {}
    if os.path.exists(mpath):
        with open(mpath) as f:
            db = json.load(f)
    db.update(lib.db)
    with open(mpath, "w") as f:
        json.dump(db, f, indent=1)
    print("wrote", name)


if __name__ == "__main__":
    main()
