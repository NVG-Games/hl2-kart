"""Lay a race circuit through a converted BSP world.

1. Navigation graph from the collision triangles: every 1 m cell may hold
   several floors (multi-level maps); a floor is a node if there is headroom
   above it; neighbours connect when the height change is small enough.
2. A* through the author's waypoints (closing the loop), preferring the middle
   of corridors (distance-to-edge transform), then smoothing + resampling.
3. Track data for the game: centre / racing line / widths / AI speeds, the
   start grid, item crate rows, boost pads, kill height, invisible barriers.

usage: python bsp_track.py <track_def.json>
"""
import heapq
import json
import math
import os
import sys
from collections import defaultdict
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.normpath(os.path.join(HERE, "..", "assets"))
CELL = 1.0
CLEAR = 2.3
STACK = 0.6  # floors closer than this in one cell are one (stairs, kerbs)


KNOCK = ["post0", "bollard", "bench", "payphone", "trashcan", "trashbin", "garbage", "lamppost", "cone",
         "chair", "table", "crate", "box0", "bottle", "paint", "cardboard", "newspaper", "pallet", "barrel"]
TRUNK = ["tree", "pole", "lamp", "antenna", "pipe", "column", "post"]
PROP_PAD = 0.6
BOX_TRIS = [(0, 1, 3), (0, 3, 2), (4, 6, 7), (4, 7, 5), (0, 4, 5), (0, 5, 1),
            (2, 3, 7), (2, 7, 6), (0, 2, 6), (0, 6, 4), (1, 5, 7), (1, 7, 3)]


def prop_boxes(info):
    """Solid static props as boxes (their tops are floors, bottoms ceilings)."""
    out = []
    for p in info.get("props", []):
        if not p.get("solid") or p.get("aabb_min") is None:
            continue
        key = p["model"]
        if any(k in key for k in KNOCK):
            continue
        lo = np.array(p["aabb_min"], np.float64)
        hi = np.array(p["aabb_max"], np.float64)
        if np.linalg.norm(hi - lo) < 0.3:
            continue
        if any(k in key for k in TRUNK):
            c = (lo + hi) * 0.5
            r = np.clip(min(hi[0] - lo[0], hi[2] - lo[2]) * 0.08, 0.15, 0.6)
            lo = np.array([c[0] - r, lo[1], c[2] - r])
            hi = np.array([c[0] + r, hi[1], c[2] + r])
        # keep the race line a little clear of solid props (thin posts slip between 1 m cells)
        scale = np.linalg.norm(np.array(p["basis"][0:3]))
        pad = PROP_PAD / max(scale, 1e-3)
        lo = lo - np.array([pad, 0, pad])
        hi = hi + np.array([pad, 0, pad])
        b = np.array(p["basis"]).reshape(3, 3).T  # columns
        o = np.array(p["origin"])
        corners = np.array([[x, y, z] for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])])
        w = corners @ b.T + o
        for t in BOX_TRIS:
            out.append(w[list(t)])
    return np.array(out) if out else np.zeros((0, 3, 3))


def load_tris(key, with_props=True):
    info = json.load(open(os.path.join(ASSETS, "maps", key, "world.json")))
    parts = []
    for fn in info.get("collision", {}).values():
        parts.append(np.fromfile(os.path.join(ASSETS, "maps", key, fn), np.float32).reshape(-1, 3, 3))
    if with_props:
        pb = prop_boxes(info)
        if len(pb):
            parts.append(pb.astype(np.float32))
    return info, np.concatenate(parts).astype(np.float64)


def rasterize(tris, lo, nx, nz):
    """-> dict cell -> sorted floor heights, dict cell -> ceiling heights"""
    floors = defaultdict(list)
    ceils = defaultdict(list)
    n = np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])
    ln = np.linalg.norm(n, axis=1) + 1e-12
    ny = n[:, 1] / ln
    for t, y in zip(tris, ny):
        if abs(y) < 0.3:
            continue
        xs = t[:, 0]
        zs = t[:, 2]
        i0 = max(0, int(math.floor((xs.min() - lo[0]) / CELL)))
        i1 = min(nx - 1, int(math.floor((xs.max() - lo[0]) / CELL)))
        k0 = max(0, int(math.floor((zs.min() - lo[1]) / CELL)))
        k1 = min(nz - 1, int(math.floor((zs.max() - lo[1]) / CELL)))
        if i1 < i0 or k1 < k0:
            continue
        ii, kk = np.meshgrid(np.arange(i0, i1 + 1), np.arange(k0, k1 + 1), indexing="ij")
        px = lo[0] + (ii.ravel() + 0.5) * CELL
        pz = lo[1] + (kk.ravel() + 0.5) * CELL
        a, b, c = t
        v0 = np.array([c[0] - a[0], c[2] - a[2]])
        v1 = np.array([b[0] - a[0], b[2] - a[2]])
        d00 = v0 @ v0
        d01 = v0 @ v1
        d11 = v1 @ v1
        den = d00 * d11 - d01 * d01
        if abs(den) < 1e-12:
            continue
        v2x = px - a[0]
        v2z = pz - a[2]
        d20 = v2x * v0[0] + v2z * v0[1]
        d21 = v2x * v1[0] + v2z * v1[1]
        u = (d11 * d20 - d01 * d21) / den
        v = (d00 * d21 - d01 * d20) / den
        inside = (u >= -1e-4) & (v >= -1e-4) & (u + v <= 1 + 1e-4)
        if not inside.any():
            continue
        h = a[1] + u * (c[1] - a[1]) + v * (b[1] - a[1])
        target = floors if y > 0 else ceils
        for i, k, hh in zip(ii.ravel()[inside], kk.ravel()[inside], h[inside]):
            target[(int(i), int(k))].append(float(hh))
    return floors, ceils


class Nav:
    def __init__(self, tris, step_up=0.55, clear=CLEAR):
        allp = tris.reshape(-1, 3)
        self.lo = np.array([allp[:, 0].min() - 2, allp[:, 2].min() - 2])
        hi = np.array([allp[:, 0].max() + 2, allp[:, 2].max() + 2])
        self.nx = int((hi[0] - self.lo[0]) / CELL) + 1
        self.nz = int((hi[1] - self.lo[1]) / CELL) + 1
        floors, ceils = rasterize(tris, self.lo, self.nx, self.nz)
        self.nodes = {}  # (i, k, level) -> height
        self.cell_levels = defaultdict(list)
        for cell, hs in floors.items():
            hs.sort()
            groups = []
            for h in hs:
                if groups and h - groups[-1][-1] < STACK:
                    groups[-1].append(h)
                else:
                    groups.append([h])
            cs = sorted(ceils.get(cell, []))
            for gi, g in enumerate(groups):
                top = max(g)
                above = [c for c in cs if c > top + 0.15]
                nxt = groups[gi + 1][0] if gi + 1 < len(groups) else 1e9
                room = min(above[0] if above else 1e9, nxt) - top
                if room < clear:
                    continue
                lvl = len(self.cell_levels[cell])
                self.cell_levels[cell].append(top)
                self.nodes[(cell[0], cell[1], lvl)] = top
        self.step_up = step_up
        self.adj = {}
        for (i, k, l), h in self.nodes.items():
            nb = []
            for di in (-1, 0, 1):
                for dk in (-1, 0, 1):
                    if di == 0 and dk == 0:
                        continue
                    c2 = (i + di, k + dk)
                    for l2, h2 in enumerate(self.cell_levels.get(c2, [])):
                        if abs(h2 - h) <= step_up * (1.42 if di and dk else 1.0):
                            nb.append((c2[0], c2[1], l2))
            self.adj[(i, k, l)] = nb
        # distance to the edge of the drivable area (multi-source BFS)
        self.free = {}
        q = []
        for n, nb in self.adj.items():
            if len(nb) < 8:
                self.free[n] = 0.0
                q.append(n)
        head = 0
        while head < len(q):
            n = q[head]
            head += 1
            d = self.free[n]
            for m in self.adj[n]:
                if m not in self.free:
                    self.free[m] = d + CELL
                    q.append(m)

    def pos(self, n):
        return np.array([self.lo[0] + (n[0] + 0.5) * CELL, self.nodes[n], self.lo[1] + (n[1] + 0.5) * CELL])

    def nearest(self, x, z, y=None, min_free=1.5):
        i = int((x - self.lo[0]) / CELL)
        k = int((z - self.lo[1]) / CELL)
        best = None
        bd = 1e18
        for r in range(0, 40):
            for di in range(-r, r + 1):
                for dk in range(-r, r + 1):
                    if max(abs(di), abs(dk)) != r:
                        continue
                    c = (i + di, k + dk)
                    for l, h in enumerate(self.cell_levels.get(c, [])):
                        n = (c[0], c[1], l)
                        if self.free.get(n, 0) < min_free:
                            continue
                        d = (di * di + dk * dk) * CELL * CELL + (0 if y is None else (h - y) ** 2 * 4)
                        if d < bd:
                            bd = d
                            best = n
            if best is not None and r > 3:
                break
        if best is None:
            raise SystemExit("no drivable floor near %.1f, %.1f" % (x, z))
        return best

    def astar(self, a, b, center_weight=6.0, avoid=None):
        def hcost(n):
            return math.hypot(n[0] - b[0], n[1] - b[1]) * CELL

        openq = [(hcost(a), 0.0, a)]
        g = {a: 0.0}
        came = {}
        while openq:
            f, gc, n = heapq.heappop(openq)
            if n == b:
                path = [n]
                while n in came:
                    n = came[n]
                    path.append(n)
                return path[::-1]
            if gc > g.get(n, 1e18):
                continue
            for m in self.adj[n]:
                step = math.hypot(m[0] - n[0], m[1] - n[1]) * CELL
                fr = self.free.get(m, 0.0)
                pen = center_weight / (fr + 0.6)
                if avoid is not None and m in avoid:
                    pen += 40.0
                ng = gc + step * (1.0 + pen)
                if ng < g.get(m, 1e18):
                    g[m] = ng
                    came[m] = n
                    heapq.heappush(openq, (ng + hcost(m), ng, m))
        raise SystemExit("no route between %s and %s" % (a, b))


def smooth_loop(pts, iters=4):
    p = np.array(pts, np.float64)
    for _ in range(iters):
        q = np.roll(p, -1, axis=0)
        a = p * 0.75 + q * 0.25
        b = p * 0.25 + q * 0.75
        p = np.empty((len(a) * 2, 3))
        p[0::2] = a
        p[1::2] = b
    return p


def resample_loop(p, step):
    seg = np.linalg.norm(np.roll(p, -1, axis=0) - p, axis=1)
    L = seg.sum()
    n = max(16, int(round(L / step)))
    cum = np.concatenate([[0], np.cumsum(seg)])
    out = []
    j = 0
    for i in range(n):
        s = L * i / n
        while cum[j + 1] < s:
            j += 1
        t = (s - cum[j]) / max(seg[j], 1e-9)
        out.append(p[j] * (1 - t) + p[(j + 1) % len(p)] * t)
    return np.array(out), L


def build(defn):
    key = defn["map"]
    info, tris = load_tris(key)
    nav = Nav(tris, defn.get("step_up", 0.55), defn.get("clear", CLEAR))
    print("nav: %d nodes" % len(nav.nodes))
    wps = defn["waypoints"]
    nodes = [nav.nearest(w[0], w[1], w[2] if len(w) > 2 else None, defn.get("min_free", 1.5)) for w in wps]
    route = []
    used = set()
    for i in range(len(nodes)):
        a_, b_ = nodes[i], nodes[(i + 1) % len(nodes)]
        if len(wps[i]) > 3 and wps[i][3] == "d":
            # straight lane (two-way corridors): follow the line, not the middle of the corridor
            pa, pb = nav.pos(a_), nav.pos(b_)
            steps = max(2, int(np.linalg.norm(pb - pa) / CELL))
            seg = [a_]
            for k in range(1, steps):
                q = pa + (pb - pa) * k / steps
                m = nav.nearest(q[0], q[2], q[1], 0.5)
                if m != seg[-1]:
                    seg.append(m)
            seg.append(b_)
        else:
            seg = nav.astar(a_, b_, defn.get("center_weight", 6.0), used)
        route.extend(seg[:-1])
        used.update(seg)
    raw = np.array([nav.pos(n) for n in route])
    frees = np.array([nav.free.get(n, 0.0) for n in route])
    sm = smooth_loop(raw, 3)
    step = defn.get("sample_step", 3.0)
    center, L = resample_loop(sm, step)
    n = len(center)
    # heights: nav height of the closest route node (smoothing cuts corners)
    d2 = ((center[:, None, [0, 2]] - raw[None, :, [0, 2]]) ** 2).sum(-1)
    idx = np.argsort(d2, axis=1)[:, :6]
    for i in range(n):
        cand = raw[idx[i]]
        center[i, 1] = cand[np.argmin(np.abs(cand[:, 1] - center[i, 1])), 1]
    raw_h = center[:, 1].copy()
    # stairs on the race line get invisible ramps (like the clip ramps HL1/HL2 put on stairs)
    ramps = []
    jump = np.abs(np.diff(np.concatenate([raw_h, raw_h[:1]])))
    stair = jump > defn.get("ramp_step", 0.18)
    i = 0
    while i < n:
        if not stair[i]:
            i += 1
            continue
        a_ = i
        while i < n and (stair[i] or (i + 1 < n and stair[min(i + 1, n - 1)]) or (i + 2 < n and stair[min(i + 2, n - 1)])):
            i += 1
        b_ = min(i + 1, n - 1)
        a0 = max(a_ - 1, 0)
        h0, h1 = raw_h[a0], raw_h[b_]
        lo_end, hi_end = (a0, b_) if h0 <= h1 else (b_, a0)
        seg = list(range(a0, b_ + 1))
        hmax = raw_h[seg].max()
        for j in seg:
            t = (j - a0) / max(b_ - a0, 1)
            center[j, 1] = max(h0 + (h1 - h0) * t, raw_h[j]) + 0.02
        ramps.append(seg)
        i = b_ + 1
    if defn.get("smooth_heights", True):
        for _ in range(3):
            center[:, 1] = np.maximum(0.25 * np.roll(center[:, 1], 1) + 0.5 * center[:, 1] + 0.25 * np.roll(center[:, 1], -1), raw_h - 0.05)
    wfree = np.array([frees[idx[i]].min() for i in range(n)])
    width = np.clip(wfree * 2.0 + 1.0, defn.get("min_width", 6.0), defn.get("max_width", 22.0))
    # parts of the lap that run side by side (hairpins) must not overlap
    gap_s = defn.get("neighbour_gap", 30.0)
    d_all = np.linalg.norm(center[:, None, [0, 2]] - center[None, :, [0, 2]], axis=2)
    ii = np.arange(n)
    sep = np.abs(ii[:, None] - ii[None, :])
    sep = np.minimum(sep, n - sep) * step
    d_all[sep < gap_s] = 1e9
    near = d_all.min(axis=1)
    width = np.minimum(width, np.maximum(near - defn.get("lane_divider", 1.5), defn.get("min_width", 6.0)))
    for _ in range(4):
        width = np.minimum(width, 0.5 * (np.roll(width, 1) + np.roll(width, -1)) + 1.5)
    fwd = np.roll(center, -1, axis=0) - np.roll(center, 1, axis=0)
    fwd /= np.linalg.norm(fwd, axis=1, keepdims=True) + 1e-9
    up = np.tile(np.array([0.0, 1.0, 0.0]), (n, 1))
    right = np.cross(fwd, up)
    right /= np.linalg.norm(right, axis=1, keepdims=True) + 1e-9
    up = np.cross(right, fwd)
    up /= np.linalg.norm(up, axis=1, keepdims=True)
    # curvature -> racing line (inside of bends) and AI speed
    ahead = max(1, int(12.0 / step))
    curv = np.zeros(n)
    for i in range(n):
        a = fwd[(i - ahead) % n]
        b = fwd[(i + ahead) % n]
        ang = math.atan2(np.cross(a, b)[1], a @ b)
        curv[i] = ang / (2 * ahead * step)
    k = np.convolve(np.concatenate([curv[-8:], curv, curv[:8]]), np.ones(9) / 9, "same")[8:-8]
    # a bend can not be wider than twice its radius (the inner edge would fold over)
    width = np.minimum(width, np.maximum(1.6 / np.maximum(np.abs(curv), 1e-4), defn.get("min_width", 6.0)))
    off = np.clip(-k * 260.0, -1, 1) * (width * 0.25)
    line = center + right * off[:, None]
    vmax = defn.get("vmax", 40.0)
    speed = np.clip(np.sqrt(9.0 / np.maximum(np.abs(k), 1e-4)), 11.0, vmax)
    # start line: waypoint 0 sits at the start; rotate arrays so s=0 is there
    s0 = int(np.argmin(np.linalg.norm(center[:, [0, 2]] - np.array(wps[0][:2])[None, :], axis=1)))
    roll = -s0

    def R(a):
        return np.roll(a, roll, axis=0)

    center, line, fwd, right, up, width, speed = map(R, (center, line, fwd, right, up, width, speed))
    gap = np.zeros(n, np.int32)
    path = {"step": L / n, "length": float(L), "center": center.tolist(), "line": line.tolist(),
            "fwd": fwd.tolist(), "right": right.tolist(), "up": up.tolist(), "width": width.tolist(),
            "speed": speed.tolist(), "gap": gap.tolist(), "theme": [defn.get("theme", "bsp")] * n}
    # start grid: 2 staggered columns behind the line
    grid = []
    for g in range(8):
        back = 8.0 + g * 6.0
        i = int(round(-back / (L / n))) % n
        col = -1 if g % 2 == 0 else 1
        lat = col * min(3.5, width[i] * 0.25)
        p = center[i] + right[i] * lat + up[i] * 0.9
        grid.append({"pos": p.tolist(), "fwd": fwd[i].tolist()})
    # item crate rows and boost pads
    boxes = []
    for s in defn.get("item_rows", [0.3, 0.62, 0.86]):
        i = int(s * n) % n
        cnt = 4 if width[i] > 11 else 3
        for c in range(cnt):
            lat = (c - (cnt - 1) / 2) * min(3.2, width[i] / (cnt + 0.5))
            p = center[i] + right[i] * lat + up[i] * 1.2
            boxes.append(p.tolist())
    pads = []
    for s in defn.get("boost", []):
        i = int(s * n) % n
        pads.append({"pos": (line[i] + up[i] * 0.06).tolist(), "fwd": fwd[i].tolist(), "up": up[i].tolist()})
    # invisible barriers along both edges (posts every sample), kept off the floor so wheels ride under
    barriers = []
    margin = defn.get("barrier_margin", 1.0)
    sides = [-1, 1]
    if defn.get("barriers", True) == "inner":
        # only the fence on the inside of the loop: open plazas keep their rock walls outside
        def inside(q):
            xs, zs = center[:, 0], center[:, 2]
            x2, z2 = np.roll(xs, -1), np.roll(zs, -1)
            hit = ((zs > q[2]) != (z2 > q[2])) & (q[0] < (x2 - xs) * (q[2] - zs) / np.where(z2 == zs, 1e-9, z2 - zs) + xs)
            return hit.sum() % 2 == 1
        votes = sum(1 if inside(center[i] + right[i] * (width[i] * 0.5 + margin)) else -1 for i in range(0, n, 3))
        sides = [1 if votes > 0 else -1]
    if defn.get("barriers", True):
        for side in sides:
            pts = []
            for i in range(n):
                p = center[i] + right[i] * side * (width[i] * 0.5 + margin)
                # drop posts that would stand inside any part of the track (hairpins, close passes)
                dd = np.linalg.norm(center[:, [0, 2]] - p[[0, 2]], axis=1) - width * 0.5
                if dd.min() < 0.4:
                    pts.append(None)
                else:
                    pts.append(p.tolist())
            barriers.append(pts)
    ramp_quads = []
    for seg in ramps:
        seg = [(j + roll) % n for j in seg]
        for j0, j1 in zip(seg[:-1], seg[1:]):
            q = []
            for j in (j0, j1):
                hw = width[j] * 0.5 + margin + 0.5
                q.append((center[j] - right[j] * hw).tolist())
                q.append((center[j] + right[j] * hw).tolist())
            ramp_quads.append(q)
    floor_min = center[:, 1].min()
    data = {"type": "bsp", "map": key, "name": defn["name"], "path": path, "grid": grid, "item_boxes": boxes,
            "boost_pads": pads, "barriers": barriers, "ramps": ramp_quads, "barrier_height": defn.get("barrier_height", 3.0),
            "sea_level": float(defn.get("kill_y", floor_min - 12.0)), "sky": defn.get("sky", info.get("sky", "")),
            "offtrack": defn.get("offtrack", 18.0), "music": defn.get("music", []),
            "ambient": defn.get("ambient", [0.6, 0.6, 0.6]), "sun": defn.get("sun", info.get("sun")),
            "kart_light": defn.get("kart_light", 1.0), "props": [], "theme": defn.get("theme", "bsp")}
    out = os.path.join(ASSETS, "track", defn["id"] + ".json")
    with open(out, "w") as f:
        json.dump(data, f)
    print("%s: lap %.0f m, %d samples, width %.1f..%.1f m, floors %.1f..%.1f, %d stair ramps" % (
        defn["id"], L, n, width.min(), width.max(), center[:, 1].min(), center[:, 1].max(), len(ramps)))
    return data




def navplan(key, out, ppm=3.0, step_up=0.55, clear=CLEAR, wps=None, bbox=None, track=None):
    """Picture of the drivable graph: colour = height, brightness = room to the walls."""
    from PIL import Image, ImageDraw
    info, tris = load_tris(key)
    nav = Nav(tris, step_up, clear)
    W = int(nav.nx * CELL * ppm) + 60
    H = int(nav.nz * CELL * ppm) + 60
    img = Image.new("RGB", (W, H), (15, 15, 20))
    dr = ImageDraw.Draw(img)
    hs = np.array(list(nav.nodes.values()))
    h0, h1 = np.percentile(hs, 2), np.percentile(hs, 98)
    order = sorted(nav.nodes.items(), key=lambda kv: kv[1])
    for n, h in order:
        f = np.clip((h - h0) / max(h1 - h0, 1e-3), 0, 1)
        fr = min(nav.free.get(n, 0) / 6.0, 1.0)
        c = (int((60 + 190 * f) * (0.35 + 0.65 * fr)), int((200 - 120 * f) * (0.35 + 0.65 * fr)), int((230 - 200 * f) * (0.35 + 0.65 * fr)))
        x = 30 + n[0] * CELL * ppm
        y = 30 + n[1] * CELL * ppm
        dr.rectangle([x, y, x + ppm, y + ppm], fill=c)

    def px(x, z):
        return (30 + (x - nav.lo[0]) * ppm, 30 + (z - nav.lo[1]) * ppm)

    x0 = int(math.floor(nav.lo[0] / 10)) * 10
    for gx in range(x0, int(nav.lo[0] + nav.nx * CELL) + 10, 10):
        X = px(gx, 0)[0]
        dr.line([(X, 0), (X, H)], fill=(255, 255, 255) if gx % 50 == 0 else (70, 70, 70))
        if gx % 20 == 0:
            dr.text((X + 2, 2), str(gx), fill=(255, 255, 0))
    z0 = int(math.floor(nav.lo[1] / 10)) * 10
    for gz in range(z0, int(nav.lo[1] + nav.nz * CELL) + 10, 10):
        Y = px(0, gz)[1]
        dr.line([(0, Y), (W, Y)], fill=(255, 255, 255) if gz % 50 == 0 else (70, 70, 70))
        if gz % 20 == 0:
            dr.text((2, Y + 2), str(gz), fill=(255, 255, 0))
    for e in info.get("entities", []):
        if e.get("classname", "").startswith("info_player"):
            x, y = px(e["origin_m"][0], e["origin_m"][2])
            dr.ellipse([x - 5, y - 5, x + 5, y + 5], outline=(255, 0, 255), width=2)
    if wps:
        for i, w in enumerate(wps):
            x, y = px(w[0], w[1])
            dr.ellipse([x - 4, y - 4, x + 4, y + 4], fill=(255, 50, 50))
            dr.text((x + 5, y - 5), str(i), fill=(255, 255, 255))
    if track:
        c = track["path"]["center"]
        pts = [px(p[0], p[2]) for p in c]
        dr.line(pts + [pts[0]], fill=(255, 40, 40), width=2)
        for side in track.get("barriers", []):
            for p in side:
                if p is None:
                    continue
                x, y = px(p[0], p[2])
                dr.point((x, y), fill=(255, 255, 0))
        for p in track.get("item_boxes", []):
            x, y = px(p[0], p[2])
            dr.ellipse([x - 3, y - 3, x + 3, y + 3], fill=(0, 255, 0))
        for g in track.get("grid", []):
            x, y = px(g["pos"][0], g["pos"][2])
            dr.ellipse([x - 3, y - 3, x + 3, y + 3], fill=(60, 60, 255))
    if bbox:
        a = px(bbox[0], bbox[1])
        b = px(bbox[2], bbox[3])
        img = img.crop((int(a[0]), int(a[1]), int(b[0]), int(b[1])))
        d2 = ImageDraw.Draw(img)
        for gx in range(int(bbox[0] // 10 * 10), int(bbox[2]) + 1, 10):
            d2.text((px(gx, 0)[0] - a[0] + 2, 2), str(gx), fill=(255, 255, 0))
        for gz in range(int(bbox[1] // 10 * 10), int(bbox[3]) + 1, 10):
            d2.text((2, px(0, gz)[1] - a[1] + 2), str(gz), fill=(255, 255, 0))
    img.save(out)
    print("nav %d nodes, heights %.1f..%.1f" % (len(nav.nodes), h0, h1))
    return nav


if __name__ == "__main__":
    if sys.argv[1] == "plan":
        bb = [float(x) for x in sys.argv[6].split(",")] if len(sys.argv) > 6 else None
        navplan(sys.argv[2], sys.argv[3], float(sys.argv[4]) if len(sys.argv) > 4 else 3.0,
                float(sys.argv[5]) if len(sys.argv) > 5 else 0.55, bbox=bb)
    elif sys.argv[1] == "show":
        d = json.load(open(sys.argv[2]))
        t = json.load(open(os.path.join(ASSETS, "track", d["id"] + ".json")))
        bb = [float(x) for x in sys.argv[5].split(",")] if len(sys.argv) > 5 else None
        navplan(d["map"], sys.argv[3], float(sys.argv[4]), d.get("step_up", 0.55), d.get("clear", CLEAR),
                wps=d["waypoints"], bbox=bb, track=t)
    else:
        build(json.load(open(sys.argv[1])))
