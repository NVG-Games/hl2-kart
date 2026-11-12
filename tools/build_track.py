"""Procedural race track built from Half-Life 2 materials and props.

Writes hl2kart/assets/track/<name>.gltf (+.bin) with visual+collision meshes (and pins its
import options in <name>.gltf.import) and <name>.json with the racing line, the shortcuts
(branches), spawn grid, item rows, hazards, spectators and prop placements. Coordinates are
Godot's: Y up, metres; the loop runs clockwise seen from above.
"""
import json
import math
import os
import sys
from types import SimpleNamespace

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import branches  # noqa: E402
import hazards  # noqa: E402
import materials  # noqa: E402
import srcfs  # noqa: E402
from crowds import H17Ctx  # noqa: E402
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
    # out along the cliffs round the flooded quarry (the quarry jump cuts across it), then the
    # dirt road climbs back north to the canal
    (300, -4, 736, 18, "coast", {}),
    (268, -3, 752, 17, "coast", {}),
    (212, -1, 780, 16, "coast", {}),
    (160, 0, 772, 16, "dirt", {}),
    (132, -1, 725, 17, "dirt", {}),
    (128, -1, 669, 17, "dirt", {}),
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

# shortcuts off the lap (Branch; their track JSON entries by tools/branches.py). "fork" / "merge":
# (x, z) by the lap, unscaled like CTRL; "ctrl": (x, y, z, width) in between; "theme": the road;
# "jump": a kicker of `lift` metres over `ramp` metres and a gap of `gap` metres starting `at`
# metres from the fork; "items" / "boosts": crate rows and pads at fractions of the branch's length;
# the rest as tools/branches.py's entry() reads it (risk, ai, respawn, retry_back).
BRANCHES = [
    # over the inside of the headland on a dirt track: two crests with airtime, back before the beach jump
    # (down from the second crest it bends in close to the coast road and runs in beside it, so a kart
    # off it joins the lap's traffic at a shallow angle instead of cutting across to the far barrier)
    {"id": "headland", "name": "Headland trail", "kind": "trail", "theme": "dirt",
     "fork": (525, 394), "merge": (514, 692),
     "ctrl": [(558, -7.9, 425, 10), (564, -7.4, 450, 10), (569, -3.4, 482, 10), (571, -0.6, 505, 10),
              (571, -2.2, 525, 10), (572, -2.6, 550, 10), (572, 1.0, 582, 10), (574, -3.0, 610, 10),
              (565, -5.0, 639, 10), (544, -5.5, 668, 10)],
     "items": [0.27], "boosts": [0.49], "risk": 0.3, "ai": {"take": 0.6, "min_skill": 0.8}, "respawn": "main"},
    # straight on along the old quarry road where the coast road swings out round the cliffs, over
    # the flooded pit: it takes a flat-out run (a pad on the run-up helps), short of that it is a swim.
    # It peels off the beach jump's landing straight in one gentle bend and runs dead straight from
    # there over the kicker, the gap and its landing (no lip off a bend to throw karts sideways);
    # the bend to the dirt road comes after. A kart that falls in is put back past the gap: the run-up
    # from the nose is too short to retry from a standstill.
    {"id": "quarry", "name": "Quarry jump", "kind": "jump", "theme": "dirt",
     "fork": (370, 710), "merge": (124, 625),
     "ctrl": [(310, -4.3, 705, 12), (250, -4.0, 704, 12), (200, -3.4, 702, 12), (165, -2.2, 690, 12),
              (140, -1.4, 662, 12)],
     "jump": {"at": 95.0, "gap": 26.0, "lift": 2.2, "ramp": 16.0}, "boosts": [0.3],
     "risk": 0.55, "ai": {"take": 0.7, "min_skill": 0.84}, "respawn": "after"},
]

# track hazards (tools/hazards.py), in lap metres, each clear of the branches' junctions
HAZARDS = [
    # the force field across the Combine checkpoint pulses: shut one second in three, flickering for
    # 0.7 s before; its posts stand on the kerbs, off the road (a post between two lanes in the middle
    # of it wedged karts that a spin or a late change of lane put on it, for the scanner to fetch)
    {"type": "field_gate", "s": 505, "lanes": 1, "edge": 0.8, "pattern": [[1], [0], [0]], "step": 1.0, "warn": 0.7},
    # the gunship leaves its patrol and strafes the coast road round the headland head-on, one side at
    # a time (the headland trail ducks under it)
    {"type": "air_strafe", "zone": [770, 990], "period": 40, "first": 35},
    # Sandtraps-style hopper mines on the dirt road up to the canal, gaps between them
    {"type": "minefield", "mines": [[1497, -4.5], [1512, 4.5], [1526, -0.5], [1541, 5.0], [1556, -5.0],
                                    [1580, 3.5], [1595, -3.0]]},
]

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
VERGE_SKIRT = 0.6  # a face under the verge's outer edge reaches this far down (verge_strip)
STARTLINE_MAT = "concrete/concretefloor033y"
KERB_H = 0.18  # city kerb and pavement height above the road edge
KERB_W = 0.35
WALK_W = 6.0  # pavement behind the kerb; the invisible wall stands 0.3 m behind it
FACADE = KERB_W + WALK_W + 0.55  # building fronts, from the road edge
SKIRT = 1.2  # faces closing the open edges of raised slabs reach this far down
CANAL_KERB = 0.18  # canal wall top above the floor where the trench starts: flush with the city kerb
CANAL_TOP = 7.06  # ... and at full depth
CANAL_LIP = 7.5  # drivable concrete shelf on top of the canal walls
BARRIER_COL = 2.5  # the coast barrier's unseen wall reaches this far over its top
CLEAR = 0.06  # the terrain stays at least this far under every track surface
DECK_LIP = 0.4  # the top of a jump deck's end face: seen, never hit (jump_walls)
GRAVITY = 15.24  # the game's (project.godot 3d/default_gravity): what a jump really takes
CRATE_TILT = math.radians(4.0)  # banked road: item crates take the local up from here
BOX_GAP = 2.4  # item crates in a row at least this far apart (a spinning crate's diagonal, its trigger)
UP = np.array([0.0, 1.0, 0.0])


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
        self.flat = np.zeros(n)  # 1 where the road is kept unbanked (the jump, a branch's junction)
        self._frames()
        if self.gap.any():
            # the jump's run-up, kicker and landing are level: a banked lip throws karts sideways
            self.unbank([(self.gap_start - int(40 / self.step), self.gap_end + int(20 / self.step))])
        self.junction = np.zeros(n, bool)  # shared with a branch (fork to nose, nose to merge)
        self.side_off = np.zeros((n, 2), bool)  # left / right verge (and barrier) left out there

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
        bank = bank * (1.0 - self.flat)
        self.bank = bank
        self.flat_right = right
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

    def unbank(self, spans, ramp=20):
        """No banking over the cyclic sample spans (a, b) too (the jump, the branches' junctions),
        easing back in over `ramp` samples either side: a branch leaves and rejoins a level road."""
        idx = np.arange(self.n)
        w = self.flat.copy()
        for a, b in spans:
            inside = (idx - a) % self.n <= (b - a) % self.n
            out = np.minimum((a - idx) % self.n, (idx - b) % self.n)
            w = np.maximum(w, np.where(inside, 1.0, 1.0 - smoothstep(0.0, ramp, out)))
        self.flat = w
        self._frames()

    def nearest(self, p, hint, window=30):
        """Sample nearest p (in plan) within `window` samples of `hint`."""
        ids = (hint + np.arange(-window, window + 1)) % self.n
        return int(ids[np.argmin(((self.pos[ids][:, [0, 2]] - p[[0, 2]]) ** 2).sum(1))])

    def edge(self, i, off):
        return self.pos[i] + self.right[i] * off

    def run_ids(self, a, b, stop=None):
        """Samples a strip covers for the cyclic run [a, b): the next run's first sample too, so runs
        join, except at the jump, where the deck ends square at the takeoff crest, and where `stop`
        marks that sample (a verge left out at a junction runs on as the branch's)."""
        end = b % self.n
        return np.arange(a, b if self.gap[end] or (stop is not None and stop[end]) else b + 1) % self.n

    def canal_rise(self, ids):
        """How far the canal wall tops (and the shelf on them) stand over the road edge: kerb height
        where the trench starts, CANAL_TOP at full depth."""
        return CANAL_KERB + (CANAL_TOP - CANAL_KERB) * self.depth[ids]


# ---------------------------------------------------------------- branches
NOSE_DY = 2.5  # a branch this far above or below the lap has left it: its nose
NOSE_MIN = 15.0  # each nose at least this far from its branch end (the game hands over in 10 m)
JUNCTION_SPAN = 45  # lap samples a junction's shared stretch may take (kept unbanked)


def fork_sample(trk, where):
    """Lap sample of a fork or merge at (x, z) (unscaled, like CTRL): one the exported path keeps
    (every third), so the game's lap metres of it are exact."""
    q = np.array(where, float) * LAYOUT_SCALE
    i = int(np.argmin(((trk.pos[:, [0, 2]] - q) ** 2).sum(1)))
    return min(3 * int(round(i / 3.0)), 3 * ((trk.n - 1) // 3))


def make_branches(trk):
    """The BRANCHES off the lap, the lap kept level where they leave and rejoin it."""
    ends = [(fork_sample(trk, spec["fork"]), fork_sample(trk, spec["merge"])) for spec in BRANCHES]
    trk.unbank([(a - 6, a + JUNCTION_SPAN) for a, _ in ends] + [(b - JUNCTION_SPAN, b + 6) for _, b in ends])
    return [Branch(trk, spec, k) for k, spec in enumerate(BRANCHES)]


class Branch:
    """A shortcut off the lap (a BRANCHES entry; the game's TrackBranch): an open road from its fork
    on the lap to its merge back on it, sampled like the lap (3k + 1 samples about 2 m apart, so
    the exported path ends on its last one). At both ends its outer edge lies on the lap's edge, its
    centre line runs along the lap's and its cross-section is the lap's own: the two roads share the
    lap's surface up to where their edges part, a gore fills between them up to the nose, where both
    verges fit side by side (or the branch is NOSE_DY above or below the lap), and the lap's verge on
    that side is left out over the stretch. A "jump" is a kicker and a gap like the lap's."""

    def __init__(self, main, spec, index):
        self.main, self.spec, self.index, self.id = main, spec, index, spec["id"]
        ctrl = [(x * LAYOUT_SCALE, y, z * LAYOUT_SCALE, w) for x, y, z, w in spec["ctrl"]]
        self.i0, self.i1 = fork_sample(main, spec["fork"]), fork_sample(main, spec["merge"])
        self.side0, self.side1 = self._side_of(self.i0, ctrl[0]), self._side_of(self.i1, ctrl[-1])
        a = main.edge(self.i0, self.side0 * (main.width[self.i0] - ctrl[0][3]) / 2)
        b = main.edge(self.i1, self.side1 * (main.width[self.i1] - ctrl[-1][3]) / 2)
        pts = [a] + [np.array(c[:3], float) for c in ctrl] + [b]
        dense, seg, tt = branches.catmull_rom_open(pts, self._phantom(a, ctrl[0], self.i0),
                                                   self._phantom(b, ctrl[-1], self.i1))
        d = np.linalg.norm(np.diff(dense, axis=0), axis=1)
        s = np.concatenate([[0.0], np.cumsum(d)])
        self.length = float(s[-1])
        self.n = 3 * max(1, int(round(self.length / (3 * main.step)))) + 1
        self.step = self.length / (self.n - 1)
        self.s = np.linspace(0.0, self.length, self.n)
        k = np.clip(np.searchsorted(s, self.s, side="right") - 1, 0, len(dense) - 2)
        f = np.clip((self.s - s[k]) / np.maximum(d[k], 1e-9), 0.0, 1.0)
        self.pos = dense[k] * (1 - f[:, None]) + dense[k + 1] * f[:, None]
        self.seg = seg[k]
        segt = np.clip(tt[k] + f / 200.0, 0.0, 1.0)
        wid = [ctrl[0][3]] + [c[3] for c in ctrl] + [ctrl[-1][3]]
        sm = segt * segt * (3 - 2 * segt)
        self.width = np.array([wid[j] for j in self.seg]) * (1 - sm) + np.array([wid[j + 1] for j in self.seg]) * sm
        self.theme = [spec.get("theme", "dirt")] * self.n
        self.depth = np.zeros(self.n)
        self.hidden = np.zeros(self.n, bool)  # nothing left undrawn (hazards.py and crowds.py read it)
        self.gap = np.zeros(self.n, bool)
        self.gaps = []
        jump = spec.get("jump")
        if jump:
            at, ramp = jump["at"], jump["ramp"]
            self.gap = (self.s >= at) & (self.s < at + jump["gap"])
            u = (self.s - (at - ramp)) / ramp
            kick = (u > 0.0) & (self.s < at)
            self.pos[kick, 1] += jump["lift"] * u[kick] ** 2
            g = np.flatnonzero(self.gap)
            self.gaps = [(int(g[0]), int(g[-1]) + 1)]
            self.gap_start, self.gap_end = self.gaps[0]
        # level (easing back over 20 m) from the fork over a jump's run-up to 25 m past its landing,
        # where a banked lip or deck would throw karts sideways, and under each boost pad, which is
        # flat and would cut into a road that twists under it
        spans = [(0.0, jump["at"] + jump["gap"] + 25.0)] if jump else []
        spans += [(self.s[j] - 6.0, self.s[j] + 6.0) for j in branch_pads(self)]
        self.flat = np.zeros(self.n)
        for u0, u1 in spans:
            self.flat = np.maximum(self.flat, 1.0 - smoothstep(0.0, 20.0, np.maximum(u0 - self.s, self.s - u1)))
        self._frames()
        self.junction = np.zeros(self.n, bool)
        self.side_off = np.zeros((self.n, 2), bool)
        self.trim_in = np.full((self.n, 3), np.nan)  # the inner edge snapped onto the lap's edge,
        self.inner = np.zeros(self.n, int)  # on that side (-1 left, +1 right),
        self.trim_j = np.zeros(self.n, int)  # on the lap's edge segment from this sample
        self.zones = {end: self._junction(end) for end in ("fork", "merge")}
        self._cut_sides()

    def _side_of(self, i, c):
        return 1 if (np.array(c[:3], float) - self.main.pos[i]) @ self.main.flat_right[i] > 0 else -1

    def _phantom(self, p, c, i):
        """The next control point c mirrored about the lap's tangent line at sample i through p:
        the centripetal spline then leaves p (or meets it) exactly along that line."""
        f = self.main.fwd[i]
        d = np.array(c[:3], float) - p
        return p - (2.0 * (f @ d) * f - d)

    def _frames(self):
        """Frames like the lap's on an open road, banked in its bends (none at either end, where the
        lap is level, nor where `flat` says so), with the lap's own cross-sections at the two end
        samples."""
        n, m = self.n, self.main
        p = self.pos
        f = np.empty_like(p)
        f[1:-1] = p[2:] - p[:-2]
        f[0], f[-1] = p[1] - p[0], p[-1] - p[-2]
        f /= np.linalg.norm(f, axis=1, keepdims=True)
        right = np.stack([-f[:, 2], np.zeros(n), f[:, 0]], 1)
        right /= np.linalg.norm(right, axis=1, keepdims=True)
        h = f[:, [0, 2]]
        idx = np.arange(n)
        hn, hp = h[np.minimum(idx + 3, n - 1)], h[np.maximum(idx - 3, 0)]
        self.curv = (hp[:, 0] * hn[:, 1] - hp[:, 1] * hn[:, 0]) / (6 * self.step)
        bank = np.clip(self.curv * 120.0, -0.17, 0.17) if self.theme[0] in ("coast", "dirt") else np.zeros(n)
        for _ in range(30):
            bank = (np.concatenate([bank[:1], bank[:-1]]) + bank * 2 + np.concatenate([bank[1:], bank[-1:]])) / 4
        bank *= smoothstep(0.0, 25.0, idx) * smoothstep(0.0, 25.0, n - 1 - idx) * (1.0 - self.flat)
        self.bank = bank
        c, s_ = np.cos(bank), np.sin(bank)
        up0 = np.cross(right, f)
        self.fwd = f
        self.flat_right = right
        self.right = right * c[:, None] - up0 * s_[:, None]
        self.up = np.cross(self.right, f)
        self.up /= np.linalg.norm(self.up, axis=1, keepdims=True)
        for k, i in ((0, self.i0), (n - 1, self.i1)):
            for key in ("fwd", "right", "up", "flat_right"):
                getattr(self, key)[k] = getattr(m, key)[i]

    def edge(self, k, off):
        return self.pos[k] + self.right[k] * off

    def _junction(self, end):
        """One end's shared stretch, walking from the fork (or back from the merge): where the edges
        part (k_sep, the first sample whose inner edge is off the lap) and the nose (k_nose and the
        lap sample abreast of it, i_nose). Marks both roads' junction samples and, while the branch
        still lies on the lap, snaps its inner edge onto the lap's edge (trim_in)."""
        m = self.main
        fork = end == "fork"
        side = self.side0 if fork else self.side1
        i = self.i0 if fork else self.i1
        gore = 2 * VERGE_W + 1.0  # both verges side by side and a metre
        z = {"side": side, "k_sep": None, "k_nose": None, "i_nose": None}
        for k in (range(self.n) if fork else range(self.n - 1, -1, -1)):
            i = m.nearest(self.pos[k], i)
            lat = float((self.pos[k] - m.pos[i]) @ m.flat_right[i]) * side
            gap = lat - self.width[k] / 2 - m.width[i] / 2
            if z["k_sep"] is None and gap > 0.0:
                z["k_sep"] = k
            if gap >= gore or abs(self.pos[k, 1] - m.pos[i, 1]) > NOSE_DY:
                z["k_nose"], z["i_nose"] = k, i
                break
            self.junction[k] = True
            m.junction[i] = True
            if gap < 0.0:
                hit = self._on_edge(i, side, k)
                if hit is not None:
                    self.trim_in[k], self.trim_j[k], self.inner[k] = hit[0], hit[1], -side
        if z["k_nose"] is None or z["k_sep"] is None:
            raise ValueError("branch %s: the %s %s" % (self.id, end, "never leaves the lap" if z["k_nose"] is None else
                                                       "is %.1f m off the lap before its edges part" % NOSE_DY))
        u = self.s[z["k_nose"]] if fork else self.length - self.s[z["k_nose"]]
        if u < NOSE_MIN or (m.n + (z["i_nose"] - self.i0 if fork else self.i1 - z["i_nose"])) % m.n > JUNCTION_SPAN:
            raise ValueError("branch %s: its %s nose is %.0f m along (%d lap samples)" % (
                self.id, end, u, (z["i_nose"] - self.i0 if fork else self.i1 - z["i_nose"]) % m.n))
        # where the verges start again (end, at a merge): the gore's end edge, from the lap's edge at
        # i_cut to the branch's inner edge at k_cut, lies behind both verges' first cross-sections,
        # so neither runs on over the gore
        sgn = 1 if fork else -1
        i_cut, k_cut = z["i_nose"], z["k_nose"]
        for _ in range(12):
            e_m = m.edge(i_cut, side * m.width[i_cut] / 2)
            e_b = self.edge(k_cut, -side * self.width[k_cut] / 2)
            if (e_b - m.pos[i_cut]) @ m.fwd[i_cut] * sgn > 0.0:
                i_cut = (i_cut + sgn) % m.n
            elif (e_m - self.pos[k_cut]) @ self.fwd[k_cut] * sgn > 0.0:
                k_cut += sgn
            else:
                break
        z["i_cut"], z["k_cut"] = i_cut, k_cut
        return z

    def _on_edge(self, i, side, k):
        """Where branch sample k's cross-section (along its right) crosses the lap's edge on `side`
        near lap sample i: a point on that edge's polyline (the lap's own strip vertices) and the
        lap sample its segment starts from."""
        m = self.main
        c, r = self.pos[k], self.right[k]
        best = None
        for j in range(i - 4, i + 4):
            j0, j1 = j % m.n, (j + 1) % m.n
            a = m.edge(j0, side * m.width[j0] / 2)
            e = m.edge(j1, side * m.width[j1] / 2) - a
            det = e[0] * r[2] - r[0] * e[2]
            if abs(det) < 1e-9:
                continue
            w = a - c
            s = (e[0] * w[2] - w[0] * e[2]) / det
            u = (r[0] * w[2] - w[0] * r[2]) / det
            if -1e-6 <= u <= 1.0 + 1e-6 and (best is None or abs(s) < abs(best[0])):
                best = (s, a + e * min(max(u, 0.0), 1.0), j0)
        return None if best is None else best[1:]

    def _cut_sides(self):
        """The verges left out over the shared stretches: the lap's on the branch's side from the
        fork to the nose and from the merge's nose to the merge, the branch's on its inner side. The
        samples at the ends of a cut keep theirs, so the strips run on into the other road's."""
        m = self.main
        for end, z in self.zones.items():
            col_m, col_b = (z["side"] + 1) // 2, (1 - z["side"]) // 2
            if end == "fork":
                for d in range(1, (z["i_cut"] - self.i0) % m.n):
                    m.side_off[(self.i0 + d) % m.n, col_m] = True
                self.side_off[:z["k_cut"], col_b] = True
            else:
                for d in range(1, (self.i1 - z["i_cut"]) % m.n):
                    m.side_off[(z["i_cut"] + d) % m.n, col_m] = True
                self.side_off[z["k_cut"] + 1:, col_b] = True

    def jumps(self):
        """(first gap sample, end, gap metres, lift, ramp, drop, launch speed) per jump."""
        out = []
        jump = self.spec.get("jump")
        for a, b in self.gaps:
            gap = (b - a + 1) * self.step
            drop = float(self.pos[a - 1, 1] - self.pos[min(b, self.n - 1), 1])
            out.append((a, b, gap, jump["lift"], jump["ramp"], drop,
                        branches.launch_speed(gap, jump["lift"], jump["ramp"], drop, GRAVITY)))
        return out

    def summary(self):
        m = self.main
        stretch = ((self.i1 - self.i0) % m.n) * m.step
        need = max([j[-1] for j in self.jumps()], default=0.0) * branches.SPEED_MARGIN
        return ("  branch %-9s fork s %.0f merge s %.0f  %4.0f m vs %4.0f m on the lap (saves %+.0f m)  noses %.0f / %.0f m"
                "  jumps %s  need %.1f m/s%s" % (
                    self.id, m.s[self.i0], m.s[self.i1], self.length, stretch, stretch - self.length,
                    self.s[self.zones["fork"]["k_nose"]], self.length - self.s[self.zones["merge"]["k_nose"]],
                    ", ".join("%.0f m" % j[2] for j in self.jumps()) or "none", need,
                    " (boost)" if need > branches.TOP_SPEED else ""))


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


def curtain(mesh, mat, top, drop, facing, u0=0.0):
    """Vertical face hanging `drop` metres (one value or one per point) under the polyline `top`, its
    front toward `facing` (one vector or one per point): closes the open edge of a raised slab. Its
    texture starts u0 down (the lower part of a face split in two)."""
    top = np.asarray(top, np.float64)
    drop = np.broadcast_to(np.asarray(drop, np.float64), (len(top),))
    low = top - np.array([0.0, 1.0, 0.0]) * drop[:, None]
    nrm = np.broadcast_to(np.asarray(facing, np.float64), top.shape)
    v = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(top, axis=0), axis=1))]) / 4.0
    du = float(drop.max()) / 4.0
    if np.dot(np.cross(low[0] - top[0], top[1] - top[0]), nrm[0]) >= 0:
        mesh.strip(mat, top, low, u0, u0 + du, v, nrm, nrm)
    else:
        mesh.strip(mat, low, top, u0 + du, u0, v, nrm, nrm)


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


class Surfaces:
    """Top-down height raster of the drivable track meshes (road, kerbs, pavements, verges, canal
    shelf): where the ground is on the track, and how low the terrain must stay under it."""

    def __init__(self, meshes, keys=("road", "verge"), res=0.25):
        tri = []
        for k in keys:
            for pt in meshes[k].parts.values():
                p = np.concatenate(pt["p"]).astype(np.float64)
                tri.append(p[np.concatenate(pt["i"]).reshape(-1, 3)])
        tri = np.concatenate(tri)
        nrm = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
        tri = tri[np.abs(nrm[:, 1]) > 0.25 * np.linalg.norm(nrm, axis=1)]
        lo = tri.reshape(-1, 3).min(0) - 2.0
        hi = tri.reshape(-1, 3).max(0) + 2.0
        self.x0, self.z0, self.res = lo[0], lo[2], res
        nx = int((hi[0] - lo[0]) / res) + 1
        nz = int((hi[2] - lo[2]) / res) + 1
        self.top = np.full((nz, nx), -np.inf, np.float32)
        self.low = np.full((nz, nx), np.inf, np.float32)
        for t in tri:
            ia, ib = int((t[:, 0].min() - self.x0) / res), int((t[:, 0].max() - self.x0) / res) + 1
            ja, jb = int((t[:, 2].min() - self.z0) / res), int((t[:, 2].max() - self.z0) / res) + 1
            X, Z = np.meshgrid(self.x0 + np.arange(ia, ib + 1) * res, self.z0 + np.arange(ja, jb + 1) * res)
            (ax, ay, az), (bx, by, bz), (cx, cy, cz) = t
            den = (bz - cz) * (ax - cx) + (cx - bx) * (az - cz)
            if abs(den) < 1e-12:
                continue
            l1 = ((bz - cz) * (X - cx) + (cx - bx) * (Z - cz)) / den
            l2 = ((cz - az) * (X - cx) + (ax - cx) * (Z - cz)) / den
            l3 = 1.0 - l1 - l2
            inside = (l1 >= -1e-6) & (l2 >= -1e-6) & (l3 >= -1e-6)
            y = l1 * ay + l2 * by + l3 * cy
            s = (slice(ja, jb + 1), slice(ia, ib + 1))
            self.top[s] = np.where(inside, np.maximum(self.top[s], y), self.top[s])
            self.low[s] = np.where(inside, np.minimum(self.low[s], y), self.low[s])

    def at(self, x, z):
        """Height of the highest track surface at (x, z), or None off the track."""
        i = int(round((x - self.x0) / self.res))
        j = int(round((z - self.z0) / self.res))
        if 0 <= j < self.top.shape[0] and 0 <= i < self.top.shape[1] and np.isfinite(self.top[j, i]):
            return float(self.top[j, i])
        return None

    def clamp_under(self, xs, zs, H, margin):
        """Terrain heights H on the grid xs, zs, lowered so no terrain triangle comes within `margin`
        of a track surface above it. Each offending spot pulls its triangle's corners down by their
        share of it (least squares): the corner that pokes through moves, its neighbours hardly."""
        low = self.low
        for shift in ((0, 1), (0, -1), (1, 0), (-1, 0)):  # a cell of slack for the raster sampling
            low = np.minimum(low, np.roll(self.low, shift, (0, 1)))
        jj, ii = np.nonzero(np.isfinite(low))
        cell = xs[1] - xs[0]
        fi = (self.x0 + ii * self.res - xs[0]) / cell
        fj = (self.z0 + jj * self.res - zs[0]) / cell
        i0 = np.clip(np.floor(fi).astype(np.int64), 0, len(xs) - 2)
        j0 = np.clip(np.floor(fj).astype(np.int64), 0, len(zs) - 2)
        fx, fz = fi - i0, fj - j0
        # corners and weights of the triangles a, c, b (fx + fz <= 1) and b, c, d terrain_mesh() writes
        lo = fx + fz <= 1.0
        dj = [np.where(lo, 0, 0), np.where(lo, 0, 1), np.where(lo, 1, 1)]
        di = [np.where(lo, 0, 1), np.where(lo, 1, 0), np.where(lo, 0, 1)]
        w = [np.where(lo, 1 - fx - fz, 1 - fz), np.where(lo, fx, 1 - fx), np.where(lo, fz, fx + fz - 1)]
        over = sum(w[k] * H[j0 + dj[k], i0 + di[k]] for k in range(3)) - (low[jj, ii] - margin)
        bad = over > 0.0
        share = over[bad] / sum(wk[bad] ** 2 for wk in w)
        drop = np.zeros_like(H)
        for k in range(3):
            np.maximum.at(drop, ((j0 + dj[k])[bad], (i0 + di[k])[bad]), share * w[k][bad])
        return H - drop


def heightfield(xs, zs, H):
    """Height of the terrain mesh at (x, z): the triangles terrain_mesh() writes, exactly."""
    cell = xs[1] - xs[0]

    def h(x, z):
        fi = (x - xs[0]) / cell
        fj = (z - zs[0]) / cell
        i = min(max(int(np.floor(fi)), 0), len(xs) - 2)
        j = min(max(int(np.floor(fj)), 0), len(zs) - 2)
        fx, fz = fi - i, fj - j
        if fx + fz <= 1.0:
            return float(H[j, i] + (H[j, i + 1] - H[j, i]) * fx + (H[j + 1, i] - H[j, i]) * fz)
        d = H[j + 1, i + 1]
        return float(d + (H[j + 1, i] - d) * (1 - fx) + (H[j, i + 1] - d) * (1 - fz))

    return h


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


def inlet(trk, P, h):
    """Terrain at points P (x, z) cut by the water inlet the coast jump crosses: open water right up
    to both abutments (a short kart drops straight in), its banks rising under the deck ends behind
    them, the channel widening out to the sea on the left."""
    g0, g1 = trk.gap_start - 1, trk.gap_end % trk.n
    mid = (trk.pos[g0] + trk.pos[g1])[[0, 2]] / 2
    along = (trk.pos[g1] - trk.pos[g0])[[0, 2]]
    span = np.linalg.norm(along) / 2
    along /= 2 * span
    d = P - mid
    u = np.abs(d @ along)
    v = d @ np.array([along[1], -along[0]])
    deck = trk.width[g0] / 2 + VERGE_W
    out = np.clip(v - deck, 0, None)
    wid = (span + 0.5 + np.clip(out - 6.0, 0, None) * 0.25
           + (noise2(P[:, 0] / 14, P[:, 1] / 14, 31) - 0.5) * 6 * smoothstep(4, 20, out))
    cut = smoothstep(wid + 4.5 + out * 0.1, wid, u) * smoothstep(-deck - 14.0, -deck - 4.0, v)
    return h * (1 - cut) + (SEA_LEVEL - 6) * cut


def pond_frame(br):
    """The pond under a branch's jump: its middle (x, z), the unit vector along the jump and half the
    distance from the takeoff crest to the landing."""
    g0, g1 = br.gap_start - 1, br.gap_end
    mid = (br.pos[g0] + br.pos[g1])[[0, 2]] / 2
    along = (br.pos[g1] - br.pos[g0])[[0, 2]]
    span = np.linalg.norm(along) / 2
    return mid, along / (2 * span), span


def in_pond(br, x, z, margin=3.0):
    """(x, z) is on the pond under a branch's jump, its banks or within `margin` of them."""
    if not br.gaps:
        return False
    mid, along, span = pond_frame(br)
    d = np.array([x, z]) - mid
    return (abs(d @ along) < span + 5.0 + margin and
            abs(d @ np.array([along[1], -along[0]])) < br.width[br.gap_start] / 2 + VERGE_W + 18.0 + margin)


def pond(br, P, h):
    """Terrain at points P (x, z) cut by the flooded pit a branch's jump crosses: open water right
    up to both abutments and a few metres past the verges either side, its banks rising steeply all
    round (under the deck ends behind the abutments)."""
    mid, along, span = pond_frame(br)
    d = P - mid
    u = np.abs(d @ along)
    v = np.abs(d @ np.array([along[1], -along[0]]))
    deck = br.width[br.gap_start] / 2 + VERGE_W
    # the far corners rounded off, the shores a little ragged
    wid = (span + 0.5 - 0.08 * np.clip(v - deck, 0, None) ** 2
           + (noise2(P[:, 0] / 14, P[:, 1] / 14, 37) - 0.5) * 5 * smoothstep(deck, deck + 8, v))
    side = deck + 6.0 + (noise2(P[:, 0] / 11, P[:, 1] / 11, 41) - 0.5) * 6
    cut = smoothstep(wid + 4.5, wid, u) * smoothstep(side + 9.0, side, v)
    return h * (1 - cut) + (SEA_LEVEL - 6) * cut


def build_terrain(trk, x0, z0, x1, z1, cell, surfaces=None, brs=()):
    nx = int((x1 - x0) / cell) + 1
    nz = int((z1 - z0) / cell) + 1
    xs = x0 + np.arange(nx) * cell
    zs = z0 + np.arange(nz) * cell
    X, Z = np.meshgrid(xs, zs)
    P = np.stack([X.ravel(), Z.ravel()], 1)
    # every road's samples, the lap's first, then the branches' (their corridors are carved too)
    roads = [trk] + list(brs)
    rp = np.concatenate([r.pos[:, [0, 2]] for r in roads])
    road_right = np.concatenate([r.right for r in roads])
    road_depth = np.concatenate([r.depth for r in roads])
    # nearest road sample per point (chunked brute force): each road's nearest, then the road whose edge
    # is nearest, so a wide road's verge keeps to its own ground beside a narrower road
    hw = np.concatenate([r.width for r in roads]) / 2
    ends = np.cumsum([0] + [r.n for r in roads])
    near = np.zeros(len(P), np.int64)
    dist = np.zeros(len(P))
    for a in range(0, len(P), 4096):
        q = P[a : a + 4096]
        d2 = ((q[:, None, :] - rp[None, :, :]) ** 2).sum(-1)
        rows = np.arange(len(q))
        ks = np.stack([r0 + np.argmin(d2[:, r0:r1], axis=1) for r0, r1 in zip(ends[:-1], ends[1:])], 1)
        ds = np.sqrt(d2[rows[:, None], ks])
        pick = np.argmin(ds - hw[ks], axis=1)
        near[a : a + 4096] = ks[rows, pick]
        dist[a : a + 4096] = ds[rows, pick]
    lat = ((P - rp[near]) * road_right[near][:, [0, 2]]).sum(1)
    theme = np.concatenate([np.array(r.theme) for r in roads])[near]
    half = hw[near]
    road_h = np.concatenate([r.pos[:, 1] for r in roads])[near]
    rp = rp[:trk.n]

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
    right_y = road_right[near][:, 1]
    surf = road_h + right_y * np.clip(lat, -half, half)
    under = surf - 0.35 - np.abs(right_y) * 1.5
    canal = theme == "canal"
    flat = half + 6.0
    t = smoothstep(flat, flat + 28.0, dist)
    h_open = under * (1 - t) + nat * t
    h_open = np.where(theme == "city", np.where(dist < half + 9, under + 0.15, under * (1 - t) + nat * t), h_open)
    # canal: low behind the walls (under the shelf), level with the shelf beyond them, rising into
    # the hills only a cell past the shelf; where the trench starts it eases into an open cutting
    shelf = surf + CANAL_KERB + (CANAL_TOP - CANAL_KERB) * road_depth[near] - 0.08
    tc = smoothstep(half + CANAL_LIP + 4.5, half + 45.0, dist)
    h_canal = np.where(dist < half + 4.5, under, shelf * (1 - tc) + np.maximum(nat, shelf) * tc)
    h_canal = h_open + (h_canal - h_open) * smoothstep(0.0, 0.3, road_depth[near])
    h = np.where(canal, h_canal, h_open)
    if trk.gap.any():
        h = np.minimum(h, inlet(trk, P, h))
    for br in brs:
        if br.gaps:
            h = np.minimum(h, pond(br, P, h))
    H = h.reshape(nz, nx)
    # nothing pokes through the track, whatever the 3 m grid does between theme rules
    if surfaces is not None:
        H = surfaces.clamp_under(xs, zs, H, CLEAR)
        h = H.ravel()

    # blend weights: r = dirt/gravel, g = rock (slopes), b = pavement, a = sand (beach)
    gz, gx = np.gradient(H, cell)
    slope = np.sqrt(gx ** 2 + gz ** 2).ravel()
    dirt = np.clip(smoothstep(half + 7, half + 1.5, dist) * (theme != "city") +
                   (noise2(P[:, 0] / 22, P[:, 1] / 22, 5) - 0.55) * 1.5, 0, 1)
    rock = smoothstep(0.55, 0.95, slope)
    # the city's paving, fading out over the first 60 m of the roads beyond its ends, and a fringe of
    # it round the whole city (cut off where the nearest road sample stopped being a city one, it
    # ended along straight lines there)
    dk = np.abs(np.arange(trk.n)[:, None] - np.flatnonzero(is_city)[None, :])
    from_city = np.concatenate([np.minimum(dk, trk.n - dk).min(1) * trk.step] + [np.full(br.n, 1e9) for br in brs])
    pave = np.clip(smoothstep(140, 100, city_d) * (1 - smoothstep(0, 60, from_city[near])) + city_w * 0.6, 0, 1)
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
def v_along(s, wl):
    """V of a road texture stretched across the road: one repeat per `wl` metres along it (the
    width times TEX_LEN, so it changes with the width). Integrated, so the texels stay square where
    the road narrows or widens (s / wl smears or even runs backwards far along the lap)."""
    return s[0] / wl[0] + np.concatenate([[0.0], np.cumsum(np.diff(s) / (0.5 * (wl[1:] + wl[:-1])))])


def build_road(trk, meshes):
    n = trk.n
    road = meshes["road"]
    walls = meshes["walls"]
    side = meshes["side"]
    inv = meshes["colonly"]
    gap = trk.gap
    theme = np.array(trk.theme)
    # road surface per theme run (cyclic); each sample's v and the v its strip gains to the next one
    # are kept for the branches' seam fillers (seam())
    trk.road_v, trk.road_dv = np.zeros(n), np.zeros(n)
    for th in THEME_ROAD:
        mask = (theme == th) & (~gap)
        for a, b in cyc_runs(mask):
            ids = trk.run_ids(a, b)
            hw = trk.width[ids] / 2
            L = trk.pos[ids] - trk.right[ids] * hw[:, None]
            R = trk.pos[ids] + trk.right[ids] * hw[:, None]
            # (a wrapped run goes on past the line)
            v = v_along(trk.s[ids] + np.where(ids < a, trk.length, 0.0), trk.width[ids] * TEX_LEN[th])
            own = ids[:b - a]  # (not the next run's first sample, where the strips join)
            trk.road_v[own] = v[:len(own)]
            trk.road_dv[ids[:-1]] = np.diff(v)
            road.strip(THEME_ROAD[th], L, R, 0.0, 1.0, v, trk.up[ids], trk.up[ids])

    # verges: gentle drivable slopes from the tarmac edge down to the ground, so a
    # kart that ran wide can always climb back on (no kerb step, no wall); a branch's road
    # takes the place of one over its junctions
    open_mask = np.isin(theme, ["coast", "dirt"]) & (~gap)
    for sgn in (-1, 1):
        cut = trk.side_off[:, (sgn + 1) // 2]
        for a, b in cyc_runs(open_mask & ~cut):
            ids = trk.run_ids(a, b, cut)
            verge_strip(meshes, trk, ids, sgn, trk.s[ids] / 4.0)

    # city: kerbs, pavements with a face on their outer edge, invisible walls
    mask = (theme == "city") & (~gap)
    for a, b in cyc_runs(mask):
        ids = trk.run_ids(a, b)
        hw = trk.width[ids] / 2
        vv = (trk.s[ids] + np.where(ids < a, trk.length, 0.0)) / 3.0  # (on past the line)
        for sgn in (-1, 1):
            r = trk.right[ids] * sgn
            e0 = trk.pos[ids] + r * hw[:, None]
            e1 = e0 + np.array([0, KERB_H, 0])
            e2 = e1 + r * KERB_W
            e3 = e2 + r * WALK_W
            if sgn > 0:
                side.strip(CURB_MAT, e0, e1, 0.0, 0.06, vv, -r, -r)
                road.strip(CURB_MAT, e1, e2, 0.06, 0.12, vv, trk.up[ids], trk.up[ids])
                road.strip(SIDEWALK_MAT, e2, e3, 0.0, 2.0, vv, trk.up[ids], trk.up[ids])
            else:
                side.strip(CURB_MAT, e1, e0, 0.06, 0.0, vv, -r, -r)
                road.strip(CURB_MAT, e2, e1, 0.12, 0.06, vv, trk.up[ids], trk.up[ids])
                road.strip(SIDEWALK_MAT, e3, e2, 2.0, 0.0, vv, trk.up[ids], trk.up[ids])
            curtain(side, CURB_MAT, e3, SKIRT, r)
            # square ends where the city stops (the canal shelf carries on flush instead)
            for j, f, nxt in ((0, -1.0, theme[(a - 1) % n]), (len(ids) - 1, 1.0, theme[ids[-1]])):
                if nxt != "canal":
                    curtain(side, CURB_MAT, [e1[j], e3[j]], SKIRT, trk.fwd[ids[j]] * f)
            w0 = e3 + r * 0.3
            w1 = w0 + np.array([0, 6.0, 0])
            if sgn > 0:
                inv.strip("colonly", w0, w1, 0, 1, vv, -r, -r)
            else:
                inv.strip("colonly", w1, w0, 0, 1, vv, -r, -r)

    # canal: the walls grow out of the ground where the trench starts and stop where it ends,
    # under a concrete shelf as wide everywhere (the ground behind the walls stays low under it)
    mask = (theme == "canal") & (~gap)
    for a, b in cyc_runs(mask):
        ids = trk.run_ids(a, b)
        hw = trk.width[ids] / 2
        rise = trk.canal_rise(ids)
        vv = trk.s[ids] / 6.0
        # the shelf is drivable ground, so a kart up on the bank can roll back in
        up_n = np.tile([0.0, 1.0, 0.0], (len(ids), 1))
        for sgn in (-1, 1):
            r = trk.right[ids] * sgn
            base = trk.pos[ids] + r * hw[:, None] - np.array([0, 0.6, 0])
            r = r * [1.0, 0.0, 1.0]
            r /= np.linalg.norm(r, axis=1, keepdims=True)
            top = base + np.array([0.0, 1.0, 0.0]) * (0.6 + rise)[:, None]
            uh = (0.6 + rise) / (0.6 + CANAL_TOP)
            lip = top + r * CANAL_LIP
            if sgn > 0:
                walls.strip(CANAL_WALL_MAT, base, top, 0.0, uh, vv, -r, -r)
                meshes["verge"].strip(CANAL_WALL_MAT, top, lip, 1.0, 1.4, vv, up_n, up_n)
            else:
                walls.strip(CANAL_WALL_MAT, top, base, uh, 0.0, vv, -r, -r)
                meshes["verge"].strip(CANAL_WALL_MAT, lip, top, 1.4, 1.0, vv, up_n, up_n)
            curtain(walls, CANAL_WALL_MAT, lip, SKIRT, r)
            for j, f in ((0, -1.0), (len(ids) - 1, 1.0)):
                curtain(walls, CANAL_WALL_MAT, [top[j], lip[j]], SKIRT, trk.fwd[ids[j]] * f)

    # coast: jersey barrier on the sea (outer = left) side
    cut = trk.side_off[:, 0]
    mask = (theme == "coast") & (~gap) & ~cut
    for a, b in cyc_runs(mask):
        ids = trk.run_ids(a, b, cut)
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
        # an unseen wall on it up to BARRIER_COL: a kart bumped or thrown at it goes no further
        # (over the top it was trapped between the barrier and the sea)
        w0 = rings[3]
        inv.strip("colonly", w0 + up * BARRIER_COL, w0, 0, 1, vv, -r, -r)
        # close both ends of the barrier so nothing can slip inside it
        for j, sgn in ((0, -1.0), (len(ids) - 1, 1.0)):
            cap = np.array([rings[k][j] for k in range(len(prof))])
            ctr = cap.mean(0)
            pts = np.vstack([cap, ctr[None]])
            nrm = np.tile(trk.fwd[ids[j]] * sgn, (len(pts), 1))
            uv = np.array([[pp[0] * 0.1, pp[1] * 0.1] for pp in pts[:, [0, 2]]])
            tri = []
            for k in range(len(prof) - 1):
                # (wound to face out of the end it closes, as its normals do)
                tri += [k + 1, k, len(prof)] if sgn > 0 else [k, k + 1, len(prof)]
            walls.add(BARRIER_MAT, pts, nrm, uv, tri)
    if trk.gap.any():
        jump_walls(trk, meshes)

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


def verge_edges(trk, ids, sgn):
    """A verge's edges on side sgn over samples ids (of the lap or a branch), VERGE_W out from the road
    edge and down to the ground: inner, outer and the level way out."""
    r = trk.right[ids] * sgn
    flat = r * [1.0, 0.0, 1.0]
    flat /= np.linalg.norm(flat, axis=1, keepdims=True)
    E = trk.pos[ids] + r * (trk.width[ids] / 2)[:, None]
    O = E + flat * VERGE_W - np.array([0.0, 1.0, 0.0]) * (VERGE_DROP + np.abs(r[:, 1]) * 1.5)[:, None]
    return E, O, flat


def verge_strip(meshes, trk, ids, sgn, v):
    """The verge on side sgn over samples ids (of the lap or a branch), with a skirt under its
    outer edge (seen, never hit): where the 3 m terrain grid dips a little more than the verge's
    drop, no gap shows under it."""
    E, O, flat = verge_edges(trk, ids, sgn)
    if sgn > 0:
        meshes["verge"].strip(VERGE_MAT, E, O, 0.0, 1.0, v)
    else:
        meshes["verge"].strip(VERGE_MAT, O, E, 1.0, 0.0, v)
    curtain(meshes["decal"], VERGE_MAT, O, VERGE_SKIRT, flat)


def verge_cap(mesh, trk, j, sgn, facing):
    """A face from the verge's cross-section at sample j (side sgn) down into the ground, toward
    `facing`: where a verge stops at a junction's nose."""
    E, O, _ = verge_edges(trk, np.array([j]), sgn)
    curtain(mesh, VERGE_MAT, [E[0], O[0]], SKIRT, facing)


def jump_walls(trk, meshes):
    """A jump's decks (the lap's or a branch's) end in an abutment across road and verges, down past
    the water's floor (1 cm in from the deck end, so a barrier's end cap stays in front of it), with
    wing walls under the verge edges along the stretch where the banks rise under the deck. The
    abutment's top DECK_LIP metres are only seen (a decal): a kart pressed into the deck by the kicker
    or by its landing sinks a little into the road, and a solid face's top edge there would stop it
    dead and throw it up into the gap."""
    n = trk.n
    floor = SEA_LEVEL - 7.0
    for ids, f in ((np.arange(trk.gap_start - 6, trk.gap_start) % n, 1.0),
                   (np.arange(trk.gap_end, trk.gap_end + 6) % n, -1.0)):
        j = ids[-1] if f > 0 else ids[0]
        ends = []
        for sgn in (-1, 1):
            E, O, flat = verge_edges(trk, ids, sgn)
            curtain(meshes["side"], SKIRT_MAT, O, O[:, 1] - floor, flat)
            k = -1 if f > 0 else 0
            ends += [O[k], E[k]] if sgn < 0 else [E[k], O[k]]
        top = np.array(ends) - trk.fwd[j] * f * 0.01
        low = top - np.array([0.0, DECK_LIP, 0.0])
        curtain(meshes["decal"], SKIRT_MAT, top, DECK_LIP, trk.fwd[j] * f)
        curtain(meshes["side"], SKIRT_MAT, low, low[:, 1] - floor, trk.fwd[j] * f, u0=DECK_LIP / 4.0)


def zipper(A, B):
    """Triangles (index triples into A + B) between two polylines walked side by side, each one
    advancing by its share of its own plan length: the faces between two edges whose vertices do
    not pair up (the lap's samples and a branch's), on both edges' own vertices."""
    def frac(P):
        d = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(P[:, [0, 2]], axis=0), axis=1))])
        return d / max(d[-1], 1e-9)

    ta, tb = frac(A), frac(B)
    i = j = 0
    tri = []
    while i < len(A) - 1 or j < len(B) - 1:
        if j == len(B) - 1 or (i < len(A) - 1 and ta[i + 1] <= tb[j + 1]):
            tri.append((i, i + 1, len(A) + j))
            i += 1
        else:
            tri.append((i, len(A) + j + 1, len(A) + j))
            j += 1
    return tri


def sheet(mesh, mat, P, tri, uv, nrm):
    """Triangles over points P, each wound to face nrm; slivers left out."""
    idx = []
    for a, b, c in tri:
        cr = np.cross(P[b] - P[a], P[c] - P[a])
        if np.linalg.norm(cr) > 1e-6:
            idx += [a, b, c] if cr @ nrm > 0 else [a, c, b]
    if idx:
        mesh.add(mat, P, np.tile(nrm, (len(P), 1)), uv, idx)


def build_branch(br, meshes):
    """A branch's road (from the lap's edge where it still lies on the lap), its verges (none on the
    inner side over the shared stretches), the gore between the two roads from where their edges
    part to each nose (hazard stripes where the lap is tarmac) with a face down into the ground at
    the nose, and a jump's abutments and wing walls."""
    m = br.main
    th = br.theme[0]
    for a, b in runs(~br.gap):
        ids = np.arange(a, b)
        hw = br.width[ids] / 2
        L = br.pos[ids] - br.right[ids] * hw[:, None]
        R = br.pos[ids] + br.right[ids] * hw[:, None]
        trim = ~np.isnan(br.trim_in[ids, 0])
        L = np.where((trim & (br.inner[ids] < 0))[:, None], br.trim_in[ids], L)
        R = np.where((trim & (br.inner[ids] > 0))[:, None], br.trim_in[ids], R)
        v = v_along(br.s[ids], br.width[ids] * TEX_LEN[th])
        meshes["road"].strip(THEME_ROAD[th], L, R, 0.0, 1.0, v, br.up[ids], br.up[ids])
    for sgn in (-1, 1):
        for a, b in runs(~br.gap & ~br.side_off[:, (sgn + 1) // 2]):
            ids = np.arange(a, b)
            if len(ids) > 1:
                verge_strip(meshes, br, ids, sgn, br.s[ids] / 4.0)
    for end, z in br.zones.items():
        fork = end == "fork"
        side, k_end, i_end, k_sep = z["side"], z["k_cut"], z["i_cut"], z["k_sep"]
        k_t = k_sep - 1 if fork else k_sep + 1
        if np.isnan(br.trim_in[k_t, 0]):
            print("  !! %s %s: no gore (the branch is not on the lap before its edges part)" % (br.id, end))
            continue
        seam(br, np.arange(0, k_t + 1) if fork else np.arange(k_t, br.n), side, meshes["road"])
        j0, p0 = br.trim_j[k_t], br.trim_in[k_t]
        inner = [br.edge(k, -side * br.width[k] / 2) for k in range(min(k_sep, k_end), max(k_sep, k_end) + 1)]
        span = (i_end - j0 if fork else j0 - i_end) % m.n
        if span > JUNCTION_SPAN:
            print("  !! %s %s: no gore (the branch leaves the lap's edge past its nose)" % (br.id, end))
            continue
        if fork:
            A = [p0] + [m.edge((j0 + d) % m.n, side * m.width[(j0 + d) % m.n] / 2) for d in range(1, span + 1)]
            B = [p0] + inner
        else:
            A = [m.edge((i_end + d) % m.n, side * m.width[(i_end + d) % m.n] / 2) for d in range(span + 1)] + [p0]
            B = inner + [p0]
        A, B = np.array(A), np.array(B)
        P = np.vstack([A, B])
        # hazard stripes on tarmac; on a dirt road the verges' plain dirt (the road's own has wheel
        # tracks that would run across the gore at their own angle)
        mat, rep = ("props/hazardstrip001a", 3.0) if m.theme[i_end] in ("coast", "city") else (VERGE_MAT, 4.0)
        sheet(meshes["road"], mat, P, zipper(A, B), (P[:, [0, 2]] - p0[[0, 2]]) / rep, UP)
        a, b = (A[-1], B[-1]) if fork else (A[0], B[0])
        low = min(a[1], b[1]) - 0.6
        q = [a, b, np.array([b[0], low, b[2]]), np.array([a[0], low, a[2]])]
        nrm = m.fwd[i_end] * (1.0 if fork else -1.0)
        tri = [0, 1, 2, 0, 2, 3] if np.dot(np.cross(q[1] - q[0], q[2] - q[0]), nrm) >= 0 else [0, 2, 1, 0, 3, 2]
        w = float(np.linalg.norm(b - a))
        meshes["side"].add(SKIRT_MAT, q, [nrm] * 4, [[0, 0], [w / 4, 0], [w / 4, 0.15], [0, 0.15]], tri)
        # the verges that stop there (the lap's, the branch's inner one) close with a face too, and
        # each runs back to the gore's end face over the small wedge between its first cross-section
        # and that face (a skirt under the wedge's outer edge, as under the verge's)
        for road, j, sgn, e, other in ((m, i_end, side, a, b), (br, k_end, -side, b, a)):
            verge_cap(meshes["side"], road, j, sgn, road.fwd[j] * (-1.0 if fork else 1.0))
            o = verge_edges(road, np.array([j]), sgn)[1][0]
            d = (other - e) * [1.0, 0.0, 1.0]
            x = e + d / np.linalg.norm(d) * np.linalg.norm((o - e) * [1.0, 0.0, 1.0])
            x[1] = o[1]
            wedge = np.array([e, x, o])
            sheet(meshes["verge"], VERGE_MAT, wedge, [(0, 1, 2)], (wedge[:, [0, 2]] - e[[0, 2]]) / 4.0, UP)
            out = np.cross(UP, o - x)
            out *= (1.0 if out @ (x + o - 2 * e) > 0 else -1.0) / np.linalg.norm(out)
            curtain(meshes["decal"], VERGE_MAT, [x, o], VERGE_SKIRT, out)
    if br.gaps:
        jump_walls(br, meshes)


def seam(br, ks, side, mesh):
    """Over a shared stretch (branch samples ks) the branch's inner edge runs straight from one of its
    points on the lap's edge to the next, past the lap's own edge vertices in between: in a bend that
    leaves hairline slivers (a few millimetres) between the two roads. They get the lap's road, on
    both edges' own vertices, with the lap's texture coordinates (build_road's road_v and road_dv)."""
    m = br.main
    ks = ks[~np.isnan(br.trim_in[ks, 0])]
    if len(ks) < 2:
        return
    j0, j1 = br.trim_j[ks[0]], br.trim_j[ks[-1]]
    js = [(j0 + d) % m.n for d in range(1, (j1 - j0) % m.n + 1)]
    u = 1.0 if side > 0 else 0.0

    def v(j, frac=0.0):
        return m.road_v[j] + frac * m.road_dv[j]

    def on_edge(k):
        j = br.trim_j[k]
        a, b = m.edge(j, side * m.width[j] / 2), m.edge((j + 1) % m.n, side * m.width[(j + 1) % m.n] / 2)
        return v(j, np.linalg.norm(br.trim_in[k] - a) / max(np.linalg.norm(b - a), 1e-9))

    A = np.array([br.trim_in[ks[0]]] + [m.edge(j, side * m.width[j] / 2) for j in js] + [br.trim_in[ks[-1]]])
    B = br.trim_in[ks]
    uv = [(u, on_edge(ks[0]))] + [(u, v(j)) for j in js] + [(u, on_edge(ks[-1]))] + [(u, on_edge(k)) for k in ks]
    sheet(mesh, THEME_ROAD[m.theme[j0]], np.vstack([A, B]), zipper(A, B), np.array(uv), np.array([0.0, 1.0, 0.0]))


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


def lap_line(trk, brs):
    """The lap's racing line and target speeds: over each junction's shared stretch 3 m in from the
    edge its branch leaves or joins on, easing in and out over 20 m, so a computer driver that stays
    on the lap clears the nose."""
    line, off, vt = racing_line(trk)
    for br in brs:
        for end, z in br.zones.items():
            a, b = (br.i0, z["i_nose"]) if end == "fork" else (z["i_nose"], br.i1)
            span = (b - a) % trk.n
            d = np.arange(-10, span + 11)
            ids = (a + d) % trk.n
            lim = trk.width[ids] / 2 - 3.0 + np.maximum(0, np.maximum(-d, d - span)) * 0.4
            off[ids] = np.minimum(off[ids] * z["side"], lim) * z["side"]
    return trk.pos + trk.right * off[:, None], off, vt


def branch_line(br):
    """A branch's racing line and target speeds (racing_line over the branch with the lap's samples
    beyond its ends): its first and last 6 samples keep to its centre line, so a computer driver's
    target slides onto it inside the shared stretch."""
    m, pad, pins = br.main, 16, 6
    lat0 = br.side0 * (m.width[br.i0] - br.width[0]) / 2
    lat1 = br.side1 * (m.width[br.i1] - br.width[-1]) / 2
    pre = np.arange(br.i0 - pad, br.i0) % m.n
    post = np.arange(br.i1 + 1, br.i1 + 1 + pad) % m.n
    held = br.gap.copy()
    held[:pins] = held[-pins:] = True
    lane = SimpleNamespace(
        n=br.n + 2 * pad, step=br.step,
        pos=np.vstack([m.pos[pre] + m.right[pre] * lat0, br.pos, m.pos[post] + m.right[post] * lat1]),
        right=np.vstack([m.right[pre], br.right, m.right[post]]),
        width=np.concatenate([np.full(pad, br.width[0]), br.width, np.full(pad, br.width[-1])]),
        gap=np.concatenate([np.ones(pad, bool), held, np.ones(pad, bool)]))
    line, off, vt = racing_line(lane)
    keep = slice(pad, pad + br.n)
    return line[keep], off[keep], vt[keep]


# ---------------------------------------------------------------- props
def load_models():
    with open(os.path.join(ASSETS, "data", "models.json")) as f:
        return json.load(f)


def pick_one(options):
    return options[int(RNG.integers(0, len(options)))]


def yaw_facing(dirv):
    """Yaw that turns a model's front (+Z) toward dirv."""
    return math.atan2(dirv[0], dirv[2])


class Site:
    """Where props go: the ground under them (track surfaces over the terrain) and the footprints
    already taken, so nothing solid stands in anything else. `props` and `lights` are what the JSON
    gets; signs add their boards to `meshes`."""

    def __init__(self, trk, models, terrain_h, surfaces, meshes):
        self.trk, self.models, self.terrain_h, self.surfaces, self.meshes = trk, models, terrain_h, surfaces, meshes
        self.props = []
        self.lights = []
        self.taken = []  # (kind, footprint)

    def ground(self, x, z):
        """Height of what stands at (x, z): a track surface, else the terrain."""
        g = self.terrain_h(x, z)
        s = self.surfaces.at(x, z)
        return g if s is None else max(g, s)

    def footprint(self, model, x, z, yaw, scale=1.0, pad=0.0):
        """The model's box from above, origin at (x, z) turned by yaw: centre, x and z axes, half sizes."""
        mm = self.models[model]
        a = np.array(mm["aabb_min"]) * scale
        b = np.array(mm["aabb_max"]) * scale
        ax = np.array([math.cos(yaw), -math.sin(yaw)])
        az = np.array([math.sin(yaw), math.cos(yaw)])
        c = (a + b) / 2
        return np.array([x, z]) + ax * c[0] + az * c[2], ax, az, (b - a)[[0, 2]] / 2 + pad

    @staticmethod
    def points(fp):
        """Points spread over a footprint, corners included, at most 3 m apart."""
        c, ax, az, h = fp
        ku, kw = (int(np.ceil(e / 1.5)) + 1 for e in h)
        return [c + ax * h[0] * u + az * h[1] * w for u in np.linspace(-1, 1, ku) for w in np.linspace(-1, 1, kw)]

    def heights(self, fp):
        """Ground heights at the points of a footprint."""
        return [self.ground(p[0], p[1]) for p in self.points(fp)]

    def free(self, fp, kinds):
        """True when the footprint overlaps no taken one of these kinds."""
        c1, x1, z1, h1 = fp
        for kind, (c2, x2, z2, h2) in self.taken:
            if kind in kinds and all(
                    h1[0] * abs(x1 @ e) + h1[1] * abs(z1 @ e) + h2[0] * abs(x2 @ e) + h2[1] * abs(z2 @ e) > abs((c2 - c1) @ e)
                    for e in (x1, z1, x2, z2)):
                return False
        return True

    def add(self, model, pos, yaw=0.0, physics=False, scale=1.0, tag=None, ground=True, pitch=0.0):
        """A prop with its origin at pos."""
        if model not in self.models:
            return False
        self.props.append({"model": model, "pos": [float(v) for v in pos], "yaw": float(yaw), "physics": physics,
                           "scale": scale, "tag": tag, "ground": ground, "pitch": float(pitch)})
        return True

    def stand(self, model, x, z, yaw=0.0, physics=False, scale=1.0, tag=None, base=None, sink=0.0,
              foot="box", take=None):
        """Stand a model at (x, z) with its lowest point on `base`, by default the ground: the lowest
        under its footprint (foot "box"; physics props the highest, so they settle instead of popping
        out) or under its origin (foot "origin": trees, posts). `sink` buries it a little; `take`
        registers the footprint under that kind."""
        if model not in self.models:
            return False
        fp = self.footprint(model, x, z, yaw, scale)
        if base is None:
            base = self.ground(x, z) if foot == "origin" else (max if physics else min)(self.heights(fp))
        y = base - sink - self.models[model]["aabb_min"][1] * scale + (0.02 if physics else 0.0)
        if take:
            self.taken.append((take, fp))
        return self.add(model, [x, y, z], yaw, physics, scale, tag)

    def light(self, pos, color, range_, energy):
        """A point light (the game's Track._spawn_lights)."""
        self.lights.append({"pos": [float(v) for v in pos], "color": [float(c) for c in color], "range": float(range_),
                            "energy": float(energy)})


def place_props(trk, site, keep_clear=(), brs=()):
    """Set dressing: city rows, street furniture, the Combine checkpoint, coast and dirt dressing, canal
    bridges, the branches' dressing and loose physics clutter, which stays 8 m clear of the samples in
    keep_clear and of the branches' junctions. Nothing stands on a branch's road or in its pond."""
    models = site.models
    n = trk.n
    theme = np.array(trk.theme)
    road_pts = np.concatenate([trk.pos] + [br.pos for br in brs])
    road_w = np.concatenate([trk.width] + [br.width for br in brs])

    def clear_of_road(x, z, margin):
        d = np.sqrt(((road_pts[:, [0, 2]] - np.array([x, z])) ** 2).sum(1))
        return (d - road_w / 2).min() > margin

    def dry(x, z):
        return all(not in_pond(br, x, z) for br in brs)

    def flat_right(i):
        r = trk.right[i]
        return np.array([r[0], 0.0, r[2]]) / math.hypot(r[0], r[2])

    # per sample: how many samples to the nearest one of another theme (how far into its run it is)
    idx = np.arange(n)
    into_run = np.zeros(n, np.int64)
    for th in set(trk.theme):
        other = idx[theme != th]
        d = np.abs(idx[theme == th][:, None] - other[None, :])
        into_run[theme == th] = np.minimum(d, n - d).min(1)

    def kerb_clearance(pts):
        """How far the points (x, z) stand from the edge of the city road, or None when one of them is
        beside another theme (or the last metres of the city)."""
        out = np.inf
        for p in pts:
            d = np.sqrt(((road_pts[:, [0, 2]] - p) ** 2).sum(1))
            k = int(np.argmin(d))
            if theme[k] != "city" or into_run[k] < 3:
                return None
            out = min(out, d[k] - trk.width[k] / 2)
        return out

    # ----- combine checkpoint at the gate control point: tall barricades across both pavements, a
    #       light, a booth behind each pavement facing the road, a short barricade further on
    gate_i = [i for i in range(n) if trk.flags[i].get("gate")]
    if gate_i:
        i = gate_i[len(gate_i) // 2]
        hw = trk.width[i] / 2
        f = trk.fwd[i]
        booth = models["props_combine/combine_booth_med01a"]["aabb_max"][2]
        for sgn in (-1, 1):
            r = flat_right(i) * sgn
            for k in range(3):
                # a slanted line from the kerb out to the wall, each one further back and turned: a kart
                # that runs up the pavement glances off them back onto the road instead of ramming one
                q = trk.pos[i] + r * (hw + 1.75 + k * 2.5) - f * (k * 2.4)
                site.stand("props_combine/combine_barricade_tall01a", q[0], q[2], yaw_facing(f * 0.83 + r * 0.56),
                           tag="gate", take="solid")
            q = trk.pos[i] + r * (hw + 4.0) + f * 10
            site.stand("props_combine/combine_light001a", q[0], q[2], yaw_facing(-r), take="solid")
            q = trk.pos[i] + r * (hw + KERB_W + WALK_W + 0.3 + booth) - f * 10
            site.stand("props_combine/combine_booth_med01a", q[0], q[2], yaw_facing(-r), take="solid")
        q = trk.pos[i] - flat_right(i) * (hw + 2.5) + f * 18
        site.stand("props_combine/combine_barricade_short01a", q[0], q[2], yaw_facing(trk.right[i]), tag="gate",
                   take="solid")

    # ----- city buildings along both sides: fronts in a row at the back of the pavement, never into
    #       each other, the road or past the end of the city, on the lowest ground under them
    bld = ["props_buildings/row_res_1_fullscale", "props_buildings/row_res_2_fullscale",
           "props_buildings/row_corner_1_fullscale", "props_buildings/building_002a",
           "props_buildings/row_church_fullscale"]

    def row_building(m, i, sgn):
        """Stand building m with its near end about at sample i, its front at the back of the pavement
        (set further back where the road curves away from a long front); the sample after its far
        end, or None."""
        mm = models[m]
        a, b = np.array(mm["aabb_min"]), np.array(mm["aabb_max"])
        half = (b[0] - a[0]) / 2
        first = i + int(round(half / trk.step))
        for c in range(first, first + 8):
            c %= n
            r = flat_right(c) * sgn
            yaw = yaw_facing(-r)
            ax = np.array([math.cos(yaw), 0.0, -math.sin(yaw)])
            ctr = trk.pos[c] + r * (trk.width[c] / 2 + FACADE + (b[2] - a[2]) / 2)
            o = ctr - ax * (a[0] + b[0]) / 2 + r * (a[2] + b[2]) / 2
            ce, fx, fz, fh = site.footprint(m, o[0], o[2], yaw)
            gap = kerb_clearance([ce + fx * fh[0] * u + fz * fh[1] for u in np.linspace(-1, 1, 13)])
            if gap is None or gap < FACADE - 6.0:
                return None
            o = o + r * max(0.0, FACADE - gap)
            fp = site.footprint(m, o[0], o[2], yaw, pad=0.2)
            if not site.free(fp, ("building", "solid")):
                continue
            hs = site.heights(fp)
            if max(hs) - min(hs) > 3.0:
                return None
            site.stand(m, o[0], o[2], yaw, tag="building", base=min(hs), sink=0.3, take="building")
            return c + int(np.ceil(half / trk.step))
        return None

    for sgn in (-1, 1):
        i = 0
        k = 0
        last = None
        while i < n:
            if theme[i] != "city" or abs(trk.curv[i]) > 0.02:
                i += 1
                continue
            # the next model in turn, else any other that fits (the narrow tower never twice running)
            for j in range(len(bld)):
                m = bld[(k + j + (sgn > 0) * 3) % len(bld)]
                nxt = None if m == last == "props_buildings/building_002a" else row_building(m, i, sgn)
                if nxt is not None:
                    k += j + 1
                    i = nxt
                    last = m
                    break
            else:
                i += 3
    # tower blocks behind the rows, on level ground, clear of the rows and of each other
    for j in range(14):
        i = RNG.integers(0, n)
        if theme[i] != "city":
            continue
        sgn = RNG.choice([-1, 1])
        q = trk.pos[i] + trk.right[i] * sgn * (trk.width[i] / 2 + 70 + RNG.uniform(0, 60))
        m = ["props_buildings/project_building01", "props_buildings/project_building02",
             "props_buildings/project_building03"][j % 3]
        yaw = yaw_facing(-trk.right[i] * sgn)
        fp = site.footprint(m, q[0], q[2], yaw, pad=4.0)
        hs = site.heights(fp)
        if (clear_of_road(q[0], q[2], 40) and all(clear_of_road(p[0], p[1], 20) for p in site.points(fp))
                and site.free(fp, ("building", "solid")) and max(hs) - min(hs) < 6.0):
            site.stand(m, q[0], q[2], yaw, tag="building", base=min(hs), sink=0.3, take="building")

    # ----- city street furniture: lamps at the kerb with their arms over the road (none at the start
    #       gantry), clutter on the pavement, all of it clear of the buildings and the checkpoint
    for i in range(0, n, int(34 / trk.step)):
        if theme[i] != "city" or into_run[i] < 3 or min(trk.s[i], trk.length - trk.s[i]) < 8.0:
            continue
        for sgn in (-1, 1):
            r = flat_right(i) * sgn
            q = trk.pos[i] + r * (trk.width[i] / 2 + 1.0)
            if site.free(site.footprint("props_c17/lamppost03a_off", q[0], q[2], yaw_facing(r)), ("building", "solid")):
                site.stand("props_c17/lamppost03a_off", q[0], q[2], yaw_facing(r), foot="origin", take="small")
    for i in range(5, n, int(23 / trk.step)):
        if theme[i] != "city" or RNG.random() < 0.35:
            continue
        sgn = RNG.choice([-1, 1])
        r = flat_right(i) * sgn
        lat = trk.width[i] / 2 + 5.0 + RNG.uniform(0, 0.8)
        pick = RNG.choice(["props_vehicles/car002a_physics", "props_vehicles/car003a_physics",
                           "props_vehicles/car004a_physics", "props_vehicles/car005a_physics",
                           "props_junk/trashdumpster01a", "props_c17/bench01a", "props_junk/trashbin01a",
                           "props_c17/furniturecouch001a", "props_junk/cardboard_box001a",
                           "props_junk/garbage_bag001a", "props_trainstation/trashcan_indoor001a",
                           "props_c17/oildrum001", "props_trainstation/payphone001a"])
        fwd = trk.fwd[i] * RNG.choice([-1, 1])
        if into_run[i] < 4:
            continue
        yaw = yaw_facing(fwd) + (math.pi / 2 if "car0" in pick else 0)
        phys = pick in ("props_junk/cardboard_box001a", "props_junk/garbage_bag001a", "props_c17/oildrum001",
                        "props_junk/trashbin01a", "props_trainstation/trashcan_indoor001a")
        # the whole thing on the pavement, its far side short of the shop fronts
        q = trk.pos[i] + r * lat
        c, ax, az, h = site.footprint(pick, q[0], q[2], yaw)
        r2 = r[[0, 2]]
        reach = (c - q[[0, 2]]) @ r2 + h[0] * abs(ax @ r2) + h[1] * abs(az @ r2)
        q = trk.pos[i] + r * min(lat, trk.width[i] / 2 + KERB_W + WALK_W - 0.1 - reach)
        if site.free(site.footprint(pick, q[0], q[2], yaw), ("building", "solid", "small")):
            site.stand(pick, q[0], q[2], yaw, physics=phys, take=None if phys else "small")

    # ----- coast and dirt: pylons first, then fences, the thumper and containers, then rocks, trees
    #       and beach dressing round all of them
    for i in range(0, n, int(70 / trk.step)):
        if theme[i] in ("coast", "dirt"):
            q = trk.pos[i] + trk.right[i] * (trk.width[i] / 2 + 34)
            if clear_of_road(q[0], q[2], 20):
                site.stand("props_wasteland/powertower01", q[0], q[2], yaw_facing(trk.fwd[i]), sink=0.2, take="solid")
    for i in range(0, n, int(25 / trk.step)):
        if theme[i] != "dirt":
            continue
        sgn = 1 if (i // 7) % 2 else -1
        q = trk.pos[i] + trk.right[i] * sgn * (trk.width[i] / 2 + 10.0)
        if clear_of_road(q[0], q[2], 4.0):
            site.stand("props_wasteland/wood_fence01a", q[0], q[2], yaw_facing(trk.fwd[i]), sink=0.1, take="solid")
    # the thumper with its containers across the road, just past the verges (the valley's banks rise
    # steeply further out): the dirt sample nearest the middle of its run where all three keep clear
    # of every road and stand on level ground, the containers lying along the road
    dirt_ids = [i for i in range(n) if theme[i] == "dirt"]
    for i in sorted(dirt_ids, key=lambda i: abs(i - dirt_ids[len(dirt_ids) // 2])):
        f = trk.fwd[i]
        q = trk.pos[i] - trk.right[i] * (trk.width[i] / 2 + VERGE_W + 2.5)
        spots = [("props_combine/combinethumper002", trk.pos[i] + trk.right[i] * (trk.width[i] / 2 + 14), 0.3),
                 ("props_wasteland/cargo_container01", q, yaw_facing(f) + 0.1),
                 ("props_wasteland/cargo_container01b", q + f * 11.5, yaw_facing(f) - 0.15)]
        if not all(clear_of_road(p[0], p[2], 10.0 if "thumper" in m else 6.5) and np.ptp(site.heights(
                site.footprint(m, p[0], p[2], yaw))) < 1.0 for m, p, yaw in spots):
            continue
        for m, p, yaw in spots:
            if site.free(site.footprint(m, p[0], p[2], yaw), ("building", "solid")):
                site.stand(m, p[0], p[2], yaw, tag="thumper" if "thumper" in m else None, sink=0.1, take="solid")
        break
    for br in brs:
        branch_props(br, site, brs)
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
            if not clear_of_road(q[0], q[2], 7):
                continue
            h = site.terrain_h(q[0], q[2])
            if h < SEA_LEVEL + 0.5:
                if RNG.random() < 0.15 and dry(q[0], q[2]):
                    pick = RNG.choice(["props_wasteland/rockgranite02a", "props_wasteland/rockgranite03a",
                                       "props_foliage/rock_coast02a", "props_foliage/rock_coast02c"])
                    yaw = RNG.uniform(0, 6.28)
                    if site.free(site.footprint(pick, q[0], q[2], yaw), ("building", "solid")):
                        site.add(pick, [q[0], h, q[2]], yaw)
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
            yaw = RNG.uniform(0, 6.28)
            reach = np.abs(np.array([models[pick]["aabb_min"], models[pick]["aabb_max"]])[:, [0, 2]]).max()
            if not site.free(site.footprint(pick, q[0], q[2], yaw), ("building", "solid")) or not clear_of_road(
                    q[0], q[2], reach + 1.0):
                continue  # (nor a canopy over any road)
            if "rock" in pick:
                # rocks sit half buried, their middle on the ground
                site.add(pick, [q[0], h, q[2]], yaw)
            elif "driftwood" in pick:
                # a 10 m log lies along the ground, on its lowest point: only where that is level
                hs = site.heights(site.footprint(pick, q[0], q[2], yaw))
                if np.ptp(hs) < 0.5:
                    site.stand(pick, q[0], q[2], yaw, base=min(hs), sink=0.1)
            else:
                site.stand(pick, q[0], q[2], yaw, foot="origin", sink=0.15)
    # sea dressing: buoys, boats, channel markers
    for k in range(18):
        x, z = RNG.uniform(600, 950) * LAYOUT_SCALE, RNG.uniform(560, 950) * LAYOUT_SCALE
        if site.terrain_h(x, z) < SEA_LEVEL - 3:
            site.add(RNG.choice(["props_wasteland/buoy01", "props_docks/channelmarker01a", "props_wasteland/boat_fishing01a",
                                 "props_canal/boat001a"]), [x, SEA_LEVEL - 0.3, z], RNG.uniform(0, 6.28), tag="float")

    # ----- canal: bridges across the full-depth trench, resting on the shelves either side
    deep = [i for i in range(n) if theme[i] == "canal" and trk.depth[i] > 0.99]
    for i in deep[6::40]:
        q = trk.pos[i]
        site.stand("props_canal/canal_bridge01", q[0], q[2], yaw_facing(trk.fwd[i]), tag="bridge",
                   base=float(trk.pos[i, 1] + trk.canal_rise(i)), take="solid")

    # ----- physics clutter on the racing surface edges (cones, drums, crates, melons), never at a
    #       crate row, a boost pad, a junction, the grid or on the run from the grid past the line
    keep = np.zeros(n, bool)
    for i in list(keep_clear) + list(np.flatnonzero(trk.junction)):
        keep[np.arange(i - 4, i + 5) % n] = True
    keep[np.arange(-int(60 / trk.step), int(30 / trk.step)) % n] = True

    def cluster(i, sgn, items, spread=3.0):
        r = trk.right[i] * sgn
        base = trk.pos[i] + r * (trk.width[i] / 2 - 1.8)
        for it in items:
            q = base + trk.fwd[i] * RNG.uniform(-spread, spread) - r * RNG.uniform(0, 2.0)
            site.stand(it, q[0], q[2], RNG.uniform(0, 6.28), physics=True)

    for i in range(0, n, int(55 / trk.step)):
        if RNG.random() < 0.3 or trk.gap[i] or keep[i]:
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
    # cones guarding the jump approach, tractor tyres on the verges at the takeoff
    if trk.gap.any():
        for k in range(6):
            i = (trk.gap_start - 8 - k * 4) % n
            for sgn in (-1, 1):
                q = trk.pos[i] + trk.right[i] * sgn * (trk.width[i] / 2 - 0.8)
                site.stand("props_junk/trafficcone001a", q[0], q[2], 0, physics=True)
        i = (trk.gap_start - 2) % n
        for sgn in (-1, 1):
            q = trk.pos[i] + trk.right[i] * sgn * (trk.width[i] / 2 + 2.5)
            site.stand("props_vehicles/tire001a_tractor", q[0], q[2], 0)
    return site.props


def branch_props(br, site, brs):
    """A branch's dressing: a crash cushion at its fork's nose (a jersey barrier's end on the gore's
    wide end, against its end face, tyres in front of it; at a merge the karts drive away from the
    nose, and a cushion on its gore only caught those cutting across), its signs (branch_signs), cones
    lining a jump's run-up and tractor tyres on the verges at its takeoff, cones at the edges of a trail."""
    m = br.main
    z = br.zones["fork"]
    i, k, side = z["i_cut"], z["k_cut"], z["side"]
    # the gore's end face (build_branch) and the way back onto the gore, square to it
    a, b = m.edge(i, side * m.width[i] / 2), br.edge(k, -side * br.width[k] / 2)
    mid = (a + b) / 2
    back = np.cross(UP, b - a)
    back *= (-1.0 if back @ (m.fwd[i] + br.fwd[k]) > 0 else 1.0) / np.linalg.norm(back)
    c = mid + back * 1.6
    site.stand("props_c17/concrete_barrier001a", c[0], c[2], yaw_facing(back), tag="cushion", sink=0.05, take="solid")
    rb = np.array([-back[2], 0.0, back[0]])
    for off in (-0.75, 0.0, 0.75):
        q = mid + back * 3.7 + rb * off
        site.stand("props_vehicles/tire001c_car", q[0], q[2], yaw_facing(rb), physics=True)
    branch_signs(br, site, brs)
    after = br.zones["fork"]["k_nose"] + 3
    for a, b in br.gaps:
        for j in range(a - 8, max(after, a - 32), -4):
            for sgn in (-1, 1):
                q = br.edge(j, sgn * (br.width[j] / 2 - 0.8))
                site.stand("props_junk/trafficcone001a", q[0], q[2], 0, physics=True)
        j = a - 2
        for sgn in (-1, 1):
            q = br.pos[j] + br.flat_right[j] * sgn * (br.width[j] / 2 + 2.5)
            site.stand("props_vehicles/tire001a_tractor", q[0], q[2], 0)
    if br.spec.get("kind") == "trail":
        # cones at the edges over each crest (where the karts leave the ground)
        y = br.pos[:, 1]
        crest = [k for k in range(after + 5, br.zones["merge"]["k_nose"] - 8) if y[k] >= y[k - 5:k + 6].max()]
        for k in crest:
            for sgn in (-1, 1):
                q = br.edge(k, sgn * (br.width[k] / 2 - 0.6))
                site.stand("props_junk/trafficcone001a", q[0], q[2], 0, physics=True)


# ---------------------------------------------------------------- signs
# where a branch leaves the lap, in City 17's Combine look (tools/track_gen.py build_signs' "combine"
# preset): a lit chevron board on its side of the lap SIGN_AT metres before its fork (the first spot
# that is clear; none with a jump between it and the fork, whose arrow it would seem to be) and two
# smaller ones beyond the branch's outer edge at its mouth, all pointing the way it goes; and a danger
# sign before a risky branch's kicker. Boards: width, height (metres), chevrons.
SIGN_AT = (70.0, 60.0, 80.0, 50.0, 90.0, 100.0)
SIGN_BOARD, SIGN_MOUTH = (4.0, 1.6, 3), (2.4, 1.2, 2)
SIGN_BOARD_MAT, SIGN_CHEVRON_MAT, SIGN_POST_MAT = "metal/citadel_metalwall072a", "lights/white001", "metal/metalpipe010a"
SIGN_LIGHT = (0.6, 0.8, 1.0)
DANGER_MAT = "decals/decalsigndanger001e"


def box(mesh, mat, center, size, yaw, rep):
    """A box turned by yaw about Y with all six faces, its texture `rep` metres a repeat."""
    c = np.asarray(center, float)
    hx, hy, hz = np.asarray(size, float) / 2
    ax = np.array([math.cos(yaw), 0.0, -math.sin(yaw)]) * hx
    az = np.array([math.sin(yaw), 0.0, math.cos(yaw)]) * hz
    ay = UP * hy
    for nrm, u, w in ((ax, ay, az), (-ax, ay, az), (az, ay, ax), (-az, ay, ax), (ay, az, ax), (-ay, az, ax)):
        o = c + nrm
        lu, lw = np.linalg.norm(u) * 2 / rep, np.linalg.norm(w) * 2 / rep
        sheet(mesh, mat, np.array([o - u - w, o - u + w, o + u + w, o + u - w]), [(0, 1, 2), (0, 2, 3)],
              np.array([[0, lu], [lw, lu], [lw, 0], [0, 0]]), nrm / np.linalg.norm(nrm))


def sign_clear(site, brs, road, i, pts, fp):
    """No point of pts within 0.3 m of another road's verge (or of `road` itself more than 12 m
    from sample i) in plan, less than 4 m under or over it, and the footprint fp free of anything
    solid."""
    for r in [road.main if isinstance(road, Branch) else road] + list(brs):
        dk = np.abs(np.arange(r.n) - i)
        if isinstance(r, Track):
            dk = np.minimum(dk, r.n - dk)
        own = (dk <= int(round(12.0 / r.step))) if r is road else np.zeros(r.n, bool)
        for p in pts:
            d = np.hypot(r.pos[:, 0] - p[0], r.pos[:, 2] - p[2]) - r.width / 2 - VERGE_W
            if ((d < 0.3) & ~own & ~r.gap & (np.abs(r.pos[:, 1] - p[1]) < 4.0)).any():
                return False
    return site.free(fp, ("building", "solid", "small"))


def sign(site, brs, road, i, sgn, size, facing=None):
    """A lit chevron board `size` (width, height, chevrons) beside sample i of an open road (the
    lap's coast or dirt, a branch) on side sgn, pointing that way: on two posts just beyond the verge,
    its bottom 2.2 m over the road, facing `facing` (by default back along the road, turned a little
    toward it). Seen, never hit (solid posts there caught karts running wide out of a branch's first
    bend); its footprint is kept clear of props and people. False where it does not fit (where the
    land beyond the verge falls away too)."""
    width, height, count = size
    if road.gap[i] or road.theme[i] not in ("coast", "dirt"):
        return False
    hw = road.width[i] / 2
    rf = road.flat_right[i] * sgn
    f = road.fwd[i] * [1.0, 0.0, 1.0]
    n = -f / np.linalg.norm(f) - rf * 0.25 if facing is None else np.asarray(facing, float) * [1.0, 0.0, 1.0]
    n /= np.linalg.norm(n)
    a = rf - n * (rf @ n)
    a /= np.linalg.norm(a)
    edge = road.edge(i, sgn * hw)
    c = road.pos[i] + rf * (hw + VERGE_W + 0.5 + width / 2)
    c[1] = max(road.pos[i, 1], edge[1]) + 2.2 + height / 2
    posts = [(c + a * x, site.ground(*(c + a * x)[[0, 2]])) for x in (-(width / 2 - 0.35), width / 2 - 0.35)]
    if min(g for _, g in posts) < edge[1] - 6.0:
        return False
    bottom = [c - UP * (height / 2) + a * x for x in (-width / 2, 0.0, width / 2)]
    fp = (c[[0, 2]], a[[0, 2]] / np.linalg.norm(a[[0, 2]]), n[[0, 2]], np.array([width / 2 + 0.3, 0.6]))
    if not sign_clear(site, brs, road, i, [p for p, _ in posts] + bottom, fp):
        return False
    site.taken.append(("solid", fp))
    deco = site.meshes["deco"]
    yaw = math.atan2(-a[2], a[0])
    box(deco, SIGN_BOARD_MAT, c - n * 0.06, [width + 0.16, height + 0.16, 0.08], yaw, 2.0)
    # glowing chevrons (">", two bars each) side by side on its face
    step = width / count
    cw, hh, th = step * 0.5, height * 0.36, step * 0.22
    for k in range(count):
        b0 = (k - (count - 1) / 2) * step - (cw + th) / 2
        for s in (1.0, -1.0):
            q = [(b0, s * hh), (b0 + th, s * hh), (b0 + cw + th, 0.0), (b0 + cw, 0.0)]
            sheet(site.meshes["glow"], SIGN_CHEVRON_MAT, np.array([c + a * x + UP * y + n * 0.03 for x, y in q]),
                  [(0, 1, 2), (0, 2, 3)], np.array([[(x - b0) / (cw + th), 0.5 - y / (2 * hh)] for x, y in q]), n)
    for p, g in posts:
        # (just behind the board, into the ground)
        foot, q = min(g, c[1] - height / 2) - 0.3, p - n * 0.16
        box(deco, SIGN_POST_MAT, [q[0], (foot + c[1]) / 2, q[2]], [0.12, c[1] - foot, 0.12], yaw, 1.0)
    site.light(c + n * 1.5, SIGN_LIGHT, 10.0, 1.2)
    return True


def danger_sign(site, road, k, sgn):
    """A danger sign on a post 0.6 m past the verge beside sample k of a road (side sgn), its face
    2.5 m over the road's edge, facing back along it; seen, never hit, its post kept clear of props
    and people."""
    f = road.fwd[k] * [1.0, 0.0, 1.0]
    f /= np.linalg.norm(f)
    q = road.pos[k] + road.flat_right[k] * sgn * (road.width[k] / 2 + VERGE_W + 0.6)
    g = site.ground(q[0], q[2])
    c = np.array([q[0], max(g, road.edge(k, sgn * road.width[k] / 2)[1]) + 2.5, q[2]]) - f * 0.08
    box(site.meshes["deco"], SIGN_POST_MAT, [q[0], (g - 0.3 + c[1] - 0.6) / 2, q[2]], [0.12, c[1] - 0.3 - g, 0.12],
        yaw_facing(f), 1.0)
    site.taken.append(("small", (q[[0, 2]], f[[2, 0]] * [1.0, -1.0], f[[0, 2]], np.array([0.3, 0.3]))))
    r = road.flat_right[k] * 0.6
    quad = np.array([c - r - UP * 0.6, c + r - UP * 0.6, c + r + UP * 0.6, c - r + UP * 0.6])
    # the front and the back 2 cm apart: the cut-out decal is drawn two-sided, and in one plane the
    # back's mirrored text won from the front
    sheet(site.meshes["deco"], DANGER_MAT, quad - f * 0.01, [(0, 1, 2), (0, 2, 3)],
          np.array([[0, 1], [1, 1], [1, 0], [0, 0]]), -f)
    sheet(site.meshes["deco"], DANGER_MAT, quad + f * 0.01, [(0, 1, 2), (0, 2, 3)],
          np.array([[1, 1], [0, 1], [0, 0], [1, 0]]), f)


def branch_signs(br, site, brs):
    """A branch's signs: its advance board on the lap (SIGN_AT; where none fits the first mouth
    board is as big), its mouth boards, a danger sign before a risky branch's kicker on the side
    across from them, past the fork's nose (no verge there before it)."""
    m = br.main
    lead = False
    for d in SIGN_AT:
        i = (br.i0 - int(round(d / m.step))) % m.n
        between = (i + np.arange(-6, (br.i0 - i) % m.n + 1)) % m.n
        if m.gap[between].any() or m.junction[(i + np.arange(-6, 7)) % m.n].any():
            continue
        if sign(site, brs, m, i, br.side0, SIGN_BOARD):
            lead = True
            break
    k_nose = br.zones["fork"]["k_nose"]
    for frac in (0.35, 0.7):
        size = SIGN_MOUTH if lead or frac > 0.5 else SIGN_BOARD
        # (a little further on where the branch is still too close to the lap there)
        any(sign(site, brs, br, int(round(k_nose * frac)) + dk, br.side0, size, facing=-m.fwd[br.i0])
            for dk in (0, 2, 4))
    if br.spec.get("risk", 0.0) >= 0.5:
        for a, _, _, _, ramp, _, _ in br.jumps():
            u = max(br.s[a] - ramp - 30.0, br.s[k_nose] + 4.0)
            danger_sign(site, br, int(np.searchsorted(br.s, u)), -br.side0)


# ---------------------------------------------------------------- spectators (tools/crowds.py)
START = (-60.0, 40.0)  # lap metres of the start's dense crowd


def road_view(br):
    """A branch as tools/crowds.py's spot rules and placement read a road."""
    return SimpleNamespace(pos=br.pos, base=br.pos, fwd=br.fwd, flat_right=br.flat_right, width=br.width,
                           mag=np.zeros(br.n), pit=br.gap.copy(), hidden=br.hidden, gap=br.gap, s=br.s, n=br.n,
                           step=br.step, length=br.length, closed=False, style=list(br.theme), styles=H17Ctx.STYLES,
                           height=np.zeros(br.n), gaps=br.gaps, theme=br.theme)


def place_crowds(trk, site, brs=()):
    """Highway 17's spectators (crowds design 5.4) on site.ground: at the back of the city pavement
    (they hop out of the way of karts that come up it) and densely at the start, Combine officers past
    the checkpoint's barricades and by its booths, a rebel camp and vortigaunts on the inland bank after
    the beach jump, rebels behind the dirt road's fences and on the containers by the thumper, refugees
    on the shelf over the canal walls, a crowd round the quarry jump and a few at the headland trail's
    crests. Every spot passes the spot rules on every road (people never stand in a prop: in_prop tests
    the same boxes as site.taken). Returns the track JSON keys."""
    ctx = H17Ctx(trk, site, SEA_LEVEL)
    views = [road_view(br) for br in brs]
    ctx.roads = [ctx.trk] + views
    t = ctx.trk
    rng = ctx.crowd_rng
    back = KERB_W + WALK_W - 0.25  # the back of the pavement, 0.55 m in front of the invisible wall

    def pavement(i, sgn):
        return ctx.side_point(i, sgn, back, jitter=0.4)

    city = [i for i in range(t.n) if t.theme[i] == "city" and not t.gap[i]]
    start = set(ctx.lap_ids(*START))
    for sgn in (-1, 1):
        ids = [i for i in city if i in start]
        for ch in ctx.chunks(ids, int(34 / t.step), int(34 / t.step)):
            gid = ctx.crowd_group(ch[len(ch) // 2], sgn, "line", "citizen", tags=["start"])
            ctx.crowd_line(gid, ch, sgn, 1.1, pavement, "citizen", chance=0.75, dodge=True, on="geom")
        rest = [i for i in city if i not in start]
        for ch in ctx.chunks(rest, int(90 / t.step), int(30 / t.step)):
            gid = ctx.crowd_group(ch[len(ch) // 2], sgn, "line", "citizen")
            ctx.crowd_line(gid, ch, sgn, 6.0, pavement, "citizen", mood="polite", chance=0.6, dodge=True, on="geom")
    _checkpoint(ctx, back)
    # the beach jump: a rebel camp and vortigaunts on the higher bank 20 m past the landing (across the
    # road from the quarry's fork), watching from the kicker's lip to past their camp (the vortigaunts
    # bow to Gordon: the player's racer gets them over that whole stretch)
    if t.gap.any():
        g_end = int(np.where(t.gap)[0][-1])
        j = (g_end + int(20 / t.step)) % t.n
        inland = max((-1, 1), key=lambda s: ctx.ground(*ctx.side_point(j, s, 12.0)[[0, 2]]))
        c = ctx.side_point(j, inland, 4.5 + 7.0)
        gid = ctx.crowd_group(j, inland, "cluster", "rebel", tags=["jump"],
                              watch=(ctx.s_of(t.gap_start) - 5.0, ctx.s_of(j) + 20.0))
        ctx.crowd_cluster(gid, c, 14, 6.0, "rebel", t.pos[j] + UP, mood="excited", ref_y=t.pos[j][1], dy=(-1.0, 3.0),
                          margin=VERGE_W + 1.0)
        ctx.crowd_cluster(gid, c, 4, 7.0, "vort", t.pos[j] + UP, mood="chant", ref_y=t.pos[j][1], dy=(-1.0, 3.0),
                          margin=VERGE_W + 1.0)

    # the dirt road: rebels behind the fences (10 m out) where the bank is flat enough, else on the
    # shoulder in front of them, off every road's verge; more by the thumper, a few on its containers
    def dirt_spot(i, sgn):
        for lat in (11.0, 12.0, 13.0, 14.0, 9.0, 8.0, 7.0, 6.0):
            q = ctx.side_point(i, sgn, lat + rng.uniform(-0.4, 0.4), jitter=1.0)
            if ctx.crowd_ok(q, VERGE_W + 1.0, dy=(-1.0, 3.0)):
                return q
        return None

    dirt = [i for i in range(t.n) if t.theme[i] == "dirt" and not t.gap[i]]
    thumper = next((np.array(p["pos"], float) for p in ctx.props if p.get("tag") == "thumper"), None)
    for sgn in (-1, 1):
        for ch in ctx.chunks(dirt, int(60 / t.step), int(30 / t.step)):
            near = thumper is not None and np.linalg.norm(t.pos[ch[len(ch) // 2]] - thumper) < 90.0
            gid = ctx.crowd_group(ch[len(ch) // 2], sgn, "line", "rebel", tags=["thumper"] if near else [])
            ctx.crowd_line(gid, ch, sgn, 3.0 if near else 6.0, dirt_spot, "rebel", chance=0.6, dy=(-1.0, 3.0))
    if thumper is not None:
        boxes = [p for p in ctx.props if p["model"].startswith("props_wasteland/cargo_container")
                 and np.linalg.norm(np.array(p["pos"]) - thumper) < 90.0]
        if boxes:
            i = ctx._nearest(np.array(boxes[0]["pos"], float))
            gid = ctx.crowd_group(i, 0, "cluster", "rebel", tags=["thumper"])
            for p in boxes:
                ctx.on_top(p, 3, "rebel", "excited", gid=gid)
    _gman(ctx)
    # the canal: refugees on the shelf over the walls (full depth only: the mouths are low), looking down
    canal = [i for i in range(t.n) if t.theme[i] == "canal" and t.depth[i] > 0.6 and not t.gap[i]]
    for sgn in (-1, 1):
        for ch in ctx.chunks(canal, int(50 / t.step), int(30 / t.step)):
            gid = ctx.crowd_group(ch[len(ch) // 2], sgn, "lip", "refugee", tags=["lip"])
            ctx.crowd_line(gid, ch, sgn, 3.0, lambda i, s: ctx.side_point(i, s, rng.uniform(0.8, 3.2), jitter=0.6),
                           "refugee", chance=0.6, margin=0.4, on="geom")
    for br, view in zip(brs, views):
        _branch_crowds(ctx.crowd_route(view, br.id), br)
    _eggs(ctx)
    # whoever ended up on a verge or the canal shelf stands on track geometry, not on the terrain
    for m in ctx.crowds:
        if m["_on"] == "ground" and site.surfaces.at(m["pos"][0], m["pos"][2]) is not None:
            m["_on"] = m["on"] = "geom"
    ctx.check_crowds()
    return ctx.crowd_export()


def _branch_crowds(bctx, br):
    """People along a branch (their groups count its metres): citizens on both banks of the quarry
    pond either side of the jump, rebels on the banks at a trail's crests."""
    t = bctx.trk
    if br.gaps:
        a, b = br.gaps[0]
        for j, role, mood in ((a - 6, "rebel", "excited"), (b + 6, "citizen", "fan")):
            for sgn in (-1, 1):
                c = bctx.side_point(j, sgn, VERGE_W + 6.0)
                gid = bctx.crowd_group(j, sgn, "cluster", role, tags=["jump"])
                bctx.crowd_cluster(gid, c, 7, 4.5, role, t.pos[(a + b) // 2] + UP, mood=mood, ref_y=t.pos[j][1],
                                   dy=(-1.5, 4.0), margin=VERGE_W + 1.0)
    if br.spec.get("kind") == "trail":
        y = br.pos[:, 1]
        kf, km = br.zones["fork"]["k_nose"], br.zones["merge"]["k_nose"]
        for k in [k for k in range(kf + 8, km - 8) if y[k] >= y[k - 5:k + 6].max()]:
            sgn = 1 if k % 2 else -1
            gid = bctx.crowd_group(k, sgn, "cluster", "rebel", tags=["jump"])
            bctx.crowd_cluster(gid, bctx.side_point(k, sgn, VERGE_W + 4.0), 5, 3.5, "rebel", t.pos[k] + UP,
                               mood="excited", ref_y=y[k], dy=(-2.0, 4.0), margin=VERGE_W + 1.0)


def _checkpoint(ctx, back):
    """Combine officers at the gate: past the barricade line on both pavements (where a kart can
    reach them they hop aside) and by the booths behind the invisible wall, facing the road. They
    watch the road from 25 m before the gate (they condemn Gordon, salute Breen: the player's racer
    gets them from there, near enough for their line to be heard) to 15 m past it."""
    t = ctx.trk
    gate = [i for i in range(t.n) if t.flags[i].get("gate")]
    if not gate:
        return
    i = gate[len(gate) // 2]
    for sgn in (-1, 1):
        gid = ctx.crowd_group(i, sgn, "post", "metrocop", tags=["gate", "egg_cp"], bed="",
                              watch=(ctx.s_of(i) - 25.0, ctx.s_of(i) + 15.0))
        placed = 0
        for along in (4.0, 6.5, 9.0, -8.0, -11.0, 12.0):
            for lat in (2.4, back - 0.4, back + 1.6, back + 3.4):
                if placed >= 5:
                    break
                q = t.pos[i] + t.flat_right[i] * sgn * (t.width[i] / 2 + lat) + t.fwd[i] * along
                q[1] = ctx.ground(q[0], q[2])
                if ctx.crowd_add(gid, q, t.pos[i] + UP, "metrocop", "loyal", lod=0, dodge=lat < back + 0.3,
                                 margin=0.4 if lat < back + 0.3 else 1.5, on="geom"):
                    placed += 1


def _eggs(ctx):
    t = ctx.trk
    # seagulls on the shore: the flattest ground a little above the sea, within sight of the coast road
    coast = [i for i in range(t.n) if t.theme[i] == "coast" and not t.gap[i]]
    for i in coast[len(coast) // 4::max(1, len(coast) // 2)][:2]:
        c = ctx.ground_spot(t.pos[i], 12.0, 140.0, ctx.water_level + 0.6, ctx.water_level + 6.0, margin=10.0,
                            tries=2500)
        if c is not None:
            ctx.egg("birds", species="seagull", center=c, radius=4.0, count=7)
    # crows pecking by the dirt road's fences, on the flattest ground near one
    fences = [p for p in ctx.props if p["model"] == "props_wasteland/wood_fence01a"]
    for p in fences[1::3][:3]:
        q = np.array(p["pos"], float)
        c = ctx.ground_spot(q, 1.5, 6.0, q[1] - 3.0, q[1] + 1.0, margin=4.0, tries=300)
        if c is not None:
            ctx.egg("birds", species="crow", center=c, radius=2.0, count=5)
    # pigeons on a city pavement away from the start
    city = [i for i in range(t.n) if t.theme[i] == "city" and not t.gap[i]]
    i = city[len(city) // 2]
    ctx.egg("birds", species="pigeon", center=ctx.side_point(i, 1, KERB_W + 3.0), radius=2.5, count=8)
    # Gnome Chompski on the roof of a checkpoint booth, looking down the road
    for p in ctx.props:
        if "combine_booth" in p["model"]:
            q = np.array(p["pos"], float)
            q[1] += ctx.models[p["model"]]["aabb_max"][1] * float(p.get("scale", 1.0))
            ctx.egg("gnome", pos=q, yaw=math.atan2(*(t.pos[ctx._nearest(q)] - q)[[0, 2]]))
            break


def _gman(ctx):
    """The G-Man on the canal shelf beside one of the bridges, seen from the floor 25-90 m before it
    (placed before the refugees: they keep away from him)."""
    t = ctx.trk
    rng = ctx.crowd_rng
    for p in ctx.props:
        if p.get("tag") != "bridge":
            continue
        q = np.array(p["pos"], float)
        i = ctx._nearest(q)
        if t.theme[i] != "canal" or t.depth[i] < 0.99:
            continue
        half = ctx.models[p["model"]]["aabb_max"][2]  # the deck's half width along the canal
        for along in (-(half + 2.0), half + 2.0):
            j = ctx._nearest(q + t.fwd[i] * along)
            sgn = 1 if rng.random() < 0.5 else -1
            g = ctx.side_point(j, sgn, rng.uniform(2.0, CANAL_LIP - 2.0))
            if ctx.crowd_ok(g, 0.4, on="geom") and ctx.egg(
                    "gman", pos=g, yaw=math.atan2(*(t.pos[j] - g)[[0, 2]]), s=ctx.s_of(j), model="gman_high",
                    window=[ctx.s_of(j) - 90.0, ctx.s_of(j) - 25.0], chance=0.4):
                return


# ---------------------------------------------------------------- gameplay data
def start_grid(trk):
    """The 8 starting slots, 10 m to 55.5 m behind the line in two staggered columns: (sample, slot)."""
    grid = []
    for k in range(8):
        i = int(round(-(10 + k * 6.5) / trk.step)) % trk.n
        p = trk.pos[i] + trk.right[i] * (-1 if k % 2 == 0 else 1) * 4.5 + trk.up[i] * 0.8
        grid.append((i, {"pos": p.tolist(), "fwd": trk.fwd[i].tolist()}))
    return grid


def near_junction(trk, i, pad=4):
    """Lap sample i is within `pad` samples of a branch's shared stretch."""
    return bool(trk.junction[(i + np.arange(-pad, pad + 1)) % trk.n].any())


def crate_rows(trk):
    """Sample of each item crate row, spread round the lap, never over the jump gap or at a
    branch's junction."""
    rows = []
    for frac in (0.07, 0.19, 0.31, 0.43, 0.6, 0.71, 0.83, 0.94):
        i = int(frac * trk.n)
        while trk.gap[i % trk.n] or near_junction(trk, i % trk.n):
            i += 5
        rows.append(i % trk.n)
    return rows


def branch_rows(br):
    """Sample of each crate row on a branch (its "items" fractions), clear of its jump."""
    rows = []
    for frac in br.spec.get("items", []):
        i = int(frac * (br.n - 1))
        while br.gap[max(i - 8, 0):i + 9].any():
            i += 5
        rows.append(min(i, br.n - 1))
    return rows


def branch_pads(br):
    """Sample of each boost pad on a branch (its "boosts" fractions), never over its jump."""
    return [j for j in (int(f * (br.n - 1)) for f in br.spec.get("boosts", [])) if not br.gap[j]]


def pad_samples(trk, line, grid):
    """Sample of each boost pad on the long straights, never on the starting grid (a kart parked on
    one would launch during the countdown): such a pad slides back up the lap until it is 12 m clear.
    None within 24 m of the jump's gap (its kicker, its landing) or at a branch's junction."""
    pads = []
    grid_pts = [np.array(g["pos"]) for _, g in grid]
    for frac in (0.03, 0.11, 0.2, 0.3, 0.4, 0.515, 0.66, 0.75, 0.86, 0.93):
        i = int(frac * trk.n)
        if trk.gap[i]:
            continue
        for k in range(60):
            j = (i - k) % trk.n
            if (not trk.gap[(j + np.arange(-12, 12)) % trk.n].any() and not near_junction(trk, j)
                    and min(np.linalg.norm(line[j] - q) for q in grid_pts) >= 12.0):
                pads.append(j)
                break
        else:
            print("  boost pad at %.3f dropped: it sat on the starting grid" % frac)
    return pads


def seagull_orbits(trk, terrain_h, count=10):
    """Circles over open water off the coast road for the seagulls BackgroundLife flies: [x, y, z,
    radius] each, spread along the coast, clear of the land (the birds bob 3 m)."""
    out = []
    ang = np.linspace(0, 2 * np.pi, 24, endpoint=False)
    for i in range(0, trk.n, 6):
        if trk.theme[i] != "coast" or len(out) == count:
            continue
        rad = 28.0 + (len(out) % 4) * 6.0
        for off in (60.0, 85.0, 110.0, 135.0, 160.0):
            c = trk.pos[i] - trk.right[i] * (trk.width[i] / 2 + off)
            ring = [(c[0] + math.cos(t) * rad, c[2] + math.sin(t) * rad) for t in ang] + [(c[0], c[2])]
            near = np.sqrt(((trk.pos[:, [0, 2]] - [c[0], c[2]]) ** 2).sum(1)).min()
            if (near > rad + 35.0 and all(terrain_h(x, z) < SEA_LEVEL - 1.0 for x, z in ring)
                    and all(math.hypot(c[0] - o[0], c[2] - o[2]) > 45.0 for o in out)):
                out.append([round(float(c[0]), 2), SEA_LEVEL + 9.0 + (len(out) % 4) * 3.0, round(float(c[2]), 2), rad])
                break
    return out


def crates(trk, i, count):
    """A row of up to `count` item crates across sample i (of the lap or a branch), 1.2 m over the
    road, at least BOX_GAP apart (fewer on a narrow road); on banked road they lean with it (local up)."""
    w = trk.width[i] / 2 - 2.5
    count = min(count, 1 + int(2 * w / BOX_GAP))
    up = trk.up[i].tolist() if abs(trk.bank[i]) > CRATE_TILT else []
    return [(trk.pos[i] + trk.right[i] * (-w + 2 * w * k / (count - 1)) + trk.up[i] * 1.2).tolist() + up
            for k in range(count)]


def path_data(trk, line, vt, closed):
    """A road as the game reads it (TrackPath): every third sample (a branch's 3k + 1 end on its last)."""
    ids = np.arange(0, trk.n, 3)
    return {
        "closed": closed,
        "step": trk.step * 3,
        "length": float(trk.length),
        "center": trk.pos[ids].round(3).tolist(),
        "line": line[ids].round(3).tolist(),
        "fwd": trk.fwd[ids].round(4).tolist(),
        "right": trk.right[ids].round(4).tolist(),
        "up": trk.up[ids].round(4).tolist(),
        "width": trk.width[ids].round(2).tolist(),
        "speed": vt[ids].round(2).tolist(),
        "gap": trk.gap[ids].astype(int).tolist(),
        "pit": trk.gap[ids].astype(int).tolist(),
        "mag": [0.0] * len(ids),
        "theme": [trk.theme[i] for i in ids],
    }


def branch_entry(br, lap, line, vt):
    """The branch's track JSON entry (tools/branches.py): fork and merge in the game's lap metres,
    the noses, the path with s_main (branches.s_main: the game's own progress at the junctions and
    where the branch runs within 20 m of the lap's edge, smooth in between) and what its jump takes."""
    m = br.main
    path = path_data(br, line, vt, False)
    ids = np.arange(0, br.n, 3)
    fork_i, merge_i = br.i0 // 3, br.i1 // 3
    span = (br.i0 + np.arange(-20, (br.i1 - br.i0) % m.n + 21)) % m.n
    d = np.sqrt(((br.pos[ids][:, None, [0, 2]] - m.pos[span][None, :, [0, 2]]) ** 2).sum(-1))
    near = (d - (br.width[ids][:, None] + m.width[span][None, :]) / 2).min(1) < 20.0
    kf, km = br.zones["fork"]["k_nose"], br.zones["merge"]["k_nose"]
    path["s_main"] = branches.s_main(lap, br.pos[ids], near, fork_i, merge_i, (kf // 3, -(-km // 3))).round(2).tolist()
    need = branches.SPEED_MARGIN * max([j[-1] for j in br.jumps()], default=0.0)
    fork_s, merge_s = fork_i * lap.step, merge_i * lap.step
    return branches.entry(
        br.spec, br.index, path, fork_s=round(fork_s, 2), merge_s=round(merge_s, 2), fork_i=fork_i,
        merge_i=merge_i, fork_nose_u=round(float(br.s[kf]), 2), merge_nose_u=round(float(br.s[km]), 2),
        fork_nose_i=int(round(br.zones["fork"]["i_nose"] / 3.0)) % lap.n,
        merge_nose_i=int(round(br.zones["merge"]["i_nose"] / 3.0)) % lap.n, side=int(br.side0),
        merge_side=int(br.side1), length=round(br.length, 2), saves=round(merge_s - fork_s - br.length, 2),
        need_speed=round(need, 2), need_boost=bool(need > branches.TOP_SPEED))


def gameplay(trk, line, off, vt, grid, rows, pads, brs=(), blines=()):
    """The track JSON's race data: grid, item crates (5 across the lap, up to 4 across a branch) and
    boost pads (on the racing line, on the surface in its local frame), the lap's path and the branches."""
    data = {"grid": [g for _, g in grid]}
    data["item_boxes"] = [c for i in rows for c in crates(trk, i, 5)]
    data["boost_pads"] = [{"pos": line[j].tolist(), "fwd": trk.fwd[j].tolist(), "up": trk.up[j].tolist()} for j in pads]
    data["path"] = path_data(trk, line, vt, True)
    if brs:
        lap = branches.LapPath(data["path"]["center"], data["path"]["fwd"], trk.length)
        data["branches"] = []
        for br, (bl, bvt) in zip(brs, blines):
            data["item_boxes"] += [c for i in branch_rows(br) for c in crates(br, i, 4)]
            data["boost_pads"] += [{"pos": bl[j].tolist(), "fwd": br.fwd[j].tolist(), "up": br.up[j].tolist()}
                                   for j in branch_pads(br)]
            data["branches"].append(branch_entry(br, lap, bl, bvt))
    return data


def import_options(path, options):
    """Pin Godot import options in <path>.import, keeping the rest of what Godot wrote there (or a
    stub Godot completes on its first import). Track meshes need uncompressed positions and no LODs:
    16-bit positions round the two sides of a seam differently and open hairline cracks."""
    lines = []
    if os.path.exists(path + ".import"):
        with open(path + ".import") as f:
            lines = f.read().splitlines()
    if "[params]" not in lines:
        lines = (lines or ["[remap]", "", 'importer="scene"', "importer_version=1"]) + ["", "[params]", ""]
    for key, value in options.items():
        at = [k for k, ln in enumerate(lines) if ln.split("=", 1)[0] == key]
        if at:
            lines[at[0]] = "%s=%s" % (key, value)
        else:
            lines.insert(lines.index("[params]") + 1, "%s=%s" % (key, value))
    with open(path + ".import", "w", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


def main():
    name = sys.argv[1] if len(sys.argv) > 1 else "city17_circuit"
    os.makedirs(OUT_DIR, exist_ok=True)
    fs = srcfs.GameFS()
    lib = materials.MaterialLib(fs, ASSETS)
    trk = Track()
    trk.depth = trk.canal_depth()
    brs = make_branches(trk)
    print("track length %.0fm, %d samples" % (trk.length, trk.n))
    for br in brs:
        print(br.summary())
    meshes = {k: Mesh() for k in ("road", "verge", "walls", "side", "colonly", "decal", "terrain", "glow", "deco")}
    build_road(trk, meshes)
    for br in brs:
        build_branch(br, meshes)
    surfaces = Surfaces(meshes)
    cell = 3.0
    xs, zs, H, col = build_terrain(trk, -480, -380, 960, 960, cell, surfaces, brs)
    terrain_mesh(meshes["terrain"], xs, zs, H, col, cell)
    line, off, vt = lap_line(trk, brs)
    blines = [branch_line(br)[::2] for br in brs]
    grid = start_grid(trk)
    rows = crate_rows(trk)
    pads = pad_samples(trk, line, grid)
    # everything that stands on the circuit goes through the site: ground heights, free footprints
    site = Site(trk, load_models(), heightfield(xs, zs, H), surfaces, meshes)
    props = place_props(trk, site, rows + pads + [i for i, _ in grid], brs)
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
    import_options(os.path.join(OUT_DIR, name + ".gltf"), {"meshes/force_disable_compression": "true",
                                                          "meshes/generate_lods": "false"})

    data = gameplay(trk, line, off, vt, grid, rows, pads, brs, blines)
    hctx = hazards.H17Ctx(trk, props, site.ground, site.models)
    hctx.roads = SimpleNamespace(trks=[trk] + brs, pos=np.concatenate([r.pos for r in [trk] + brs]),
                                 route=np.concatenate([np.full(r.n, k) for k, r in enumerate([trk] + brs)]))
    data["hazards"] = hazards.lint(hctx, hazards.resolve(hctx, hazards.check(HAZARDS)), data, strict=True)
    data["props"] = props
    data["lights"] = site.lights
    # the start arch's pillars stand behind the kerb and the pavement (StartGantry)
    data["gantry_clear"] = KERB_W + WALK_W
    data.update(place_crowds(trk, site, brs))
    data["seagulls"] = seagull_orbits(trk, site.terrain_h)
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
