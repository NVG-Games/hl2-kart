"""Spectators for the circuits: where people stand, the stands they stand on, the easter eggs.

A circuit module's stands(ctx) builds grandstands and terraces (track geometry) and reserves
their plots before decorate(ctx) puts up the buildings; its crowds(ctx) then places the people
in groups and the easter eggs. CrowdMixin gives the generator's Ctx (track_gen.py) that API;
H17Ctx does the same for Highway 17 (build_track.py). Every spot passes the rules of
crowd_ok(): off every road and out of tubes, clear of the hazards' corridors, not over a pit, out
of the water, on the ground (or on geometry the caller vouches for), clear of props, not inside
something built (a box of Ctx.boxes walled round by built faces: a column, a block of flats), with
nothing built over the feet up to head height, standable and spaced out. A spot on the ground
under a built floor a little above it (a branch's pavement, a walkway) stands on that floor
instead. check_crowds() asserts the rules again on everything placed before the track JSON is
written. Stands leave out the samples where a junction cuts the side treatment or another road or
a hazard corridor lies on their ground (stand_ok); on a closed lap they run on across the start
line. People within DODGE_PAST metres past an open road's verge (no barrier between) hop out of a
kart's way unless told otherwise. gman_spot() finds where the G-Man is seen best from the road.

Track JSON keys (crowd_export): "crowd_groups", "crowds", "crowd_eggs", read by the game's
CrowdDirector (scripts/crowd/). A spectator standing on geometry rather than the terrain carries
"on": "geom" (the game's tests/crowd_check.gd skips its ground test). Groups and eggs by a branch
(placed through crowd_route()) carry "route": the branch id, and their "s", "watch", "window" and
"gap" count that branch's metres; everything else counts lap metres.
"""
import copy
import math

import numpy as np

UP = np.array([0.0, 1.0, 0.0])

# deterministic picks per role; keys the content does not have are logged and left out
CROWD_PALETTE = {
    "citizen": ["humans/group01/male_%02d" % i for i in range(1, 10)] +
               ["humans/group01/female_%02d" % i for i in (1, 2, 3, 4, 6, 7)],
    "refugee": ["humans/group02/male_%02d" % i for i in (1, 3, 5, 7, 9)] +
               ["humans/group02/female_%02d" % i for i in (2, 4, 6)],
    "rebel": ["humans/group03/male_%02d" % i for i in (1, 2, 4, 6, 8)] +
             ["humans/group03/female_%02d" % i for i in (1, 3, 7)],
    "metrocop": ["police"], "combine": ["combine_soldier"],
    "scientist": ["hl1/sci_glasses", "hl1/sci_einstein", "hl1/sci_luther", "hl1/sci_slick"],
    "guard": ["hl1/guard"], "vort": ["vortigaunt"], "islave": ["hl1/islave_hd"],
    "hecu": ["hl1/marine_mask", "hl1/marine_cmdr", "hl1/marine_shot"], "zombie": ["zombie/classic"],
    "cameo": ["kleiner"],
}
ROLES = set(CROWD_PALETTE)
FAR_MODEL = "humans/group01/male_cheaple"  # one material, 16 bones: back tiers and far rings
MOODS = ("fan", "polite", "excited", "loyal", "military", "chant", "scared")
KINDS = ("stand", "terrace", "line", "cluster", "lip", "post", "gallery")
EGGS = ("gman", "holo", "lamarr", "zombies", "birds", "gnome", "nihilanth")
# lod 0 stays on FEW (45 %), 1 on FULL (25 % more), 2 only with FULL and HIGH graphics
LOD_CYCLE = (0, 1, 2, 0, 0, 2, 1, 0, 2, 0, 1, 0, 2, 0, 1, 2, 0, 1, 0, 2)
# spectators may stand on these props: top above the prop's origin (box-shaped: their AABB top)
FLAT_TOPS = {"props_wasteland/cargo_container01": 1.72, "props_wasteland/cargo_container01b": 1.72,
             "props_junk/wood_crate001a": 0.51, "props_junk/wood_crate002a": 0.51}
SPACING = 0.85  # metres between two people standing (0.75 seated)
EGG_CLEAR = 12.0  # the G-Man and the zombies keep this far from any spectator
EGG_BODY = 1.2  # ... and nobody stands this close to the hologram, Lamarr's path or the gnome
DODGE_PAST = 5.0  # metres past an open road's verge within which people hop out of a kart's way
# the built meshes that collide in the game (Track._build_geometry): rays test people against them
SOLID = ("road", "verge", "walls", "side", "ceil")
LIFT = 1.2  # a floor built this far above the ground under a spot (a pavement) is stood on instead
BODY = (0.15, 1.9)  # metres over the feet that nothing built may cross (up to head height)
# the CrowdEggs rules for the G-Man (scripts/crowd/crowd_eggs.gd): shown in view 25-70 m off the
# camera, seen once 40 px of 900 tall, gone when the camera comes within 15 m; the chase camera
CAM_BACK, CAM_UP, CAM_FOV = 8.6, 3.3, 70.0
GMAN_SHOW, GMAN_NEAR, GMAN_SEEN, GMAN_H = (25.0, 70.0), 15.0, 40.0 / 900.0, 1.8
# per-preset budget of people in the worst view (FEW, FULL, FULL + HIGH graphics): [range m, max]
VIEW_BUDGET = ((0, 110.0, 90), (1, 150.0, 160), (2, 150.0, 220))
MAX_PEOPLE = 450  # per circuit, all roads (tests/crowd_check.gd fails over it)


def _r3(v):
    return [round(float(x), 3) for x in v]


def _in_poly(x, z, poly):
    """Point in a plan polygon (N,2)."""
    inside = False
    n = len(poly)
    for k in range(n):
        x1, z1 = poly[k]
        x2, z2 = poly[(k + 1) % n]
        if (z1 > z) != (z2 > z) and x < x1 + (z - z1) * (x2 - x1) / (z2 - z1):
            inside = not inside
    return inside


class _Grid:
    """Spatial hash of points (plan) for spacing and prop lookups."""

    def __init__(self, cell):
        self.cell = cell
        self.cells = {}

    def key(self, x, z):
        return int(math.floor(x / self.cell)), int(math.floor(z / self.cell))

    def add(self, x, z, item):
        self.cells.setdefault(self.key(x, z), []).append(item)

    def near(self, x, z, r=0.0):
        kx, kz = self.key(x, z)
        m = int(math.ceil(r / self.cell))
        for i in range(kx - 1 - m, kx + 2 + m):
            for j in range(kz - 1 - m, kz + 2 + m):
                yield from self.cells.get((i, j), ())


class _Solids:
    """The triangles of the built meshes that collide in the game (SOLID kinds), filed by plan
    cell: what is built over a point, and whether a line of sight crosses any of it."""

    CELL = 4.0

    def __init__(self, meshes):
        tris, ny = [], []
        for kind in SOLID:
            m = meshes.get(kind)
            for part in (m.parts.values() if m is not None else ()):
                if not part["p"]:
                    continue
                P = np.concatenate(part["p"]).astype(np.float64)
                N = np.concatenate(part["n"]).astype(np.float64)
                I = np.concatenate(part["i"]).reshape(-1, 3)
                tris.append(P[I])
                n = N[I].mean(1)
                ny.append(n[:, 1] / np.maximum(np.linalg.norm(n, axis=1), 1e-9))
        self.T = np.concatenate(tris) if tris else np.zeros((0, 3, 3))
        self.ny = np.concatenate(ny) if ny else np.zeros(0)
        c0 = np.floor(self.T[:, :, [0, 2]].min(1) / self.CELL).astype(np.int64)
        c1 = np.floor(self.T[:, :, [0, 2]].max(1) / self.CELL).astype(np.int64)
        nx = c1[:, 0] - c0[:, 0] + 1
        cnt = nx * (c1[:, 1] - c0[:, 1] + 1)
        tri = np.repeat(np.arange(len(self.T)), cnt)
        k = np.arange(int(cnt.sum())) - np.repeat(np.cumsum(cnt) - cnt, cnt)
        key = self._key(np.repeat(c0[:, 0], cnt) + k % np.repeat(nx, cnt), np.repeat(c0[:, 1], cnt) + k // np.repeat(nx, cnt))
        order = np.argsort(key, kind="stable")
        self.keys, first = np.unique(key[order], return_index=True)
        self.tri = tri[order]
        self.first = np.append(first, len(order))

    @staticmethod
    def _key(cx, cz):
        return np.asarray(cx, np.int64) * 1000003 + np.asarray(cz, np.int64)

    def _cells(self, keys):
        """The triangles filed under any of the plan cells `keys`."""
        keys = np.atleast_1d(np.asarray(keys, np.int64))
        if not len(self.keys):
            return np.zeros(0, np.int64)
        j = np.minimum(np.searchsorted(self.keys, keys), len(self.keys) - 1)
        j = j[self.keys[j] == keys]
        if not len(j):
            return np.zeros(0, np.int64)
        return np.unique(np.concatenate([self.tri[self.first[i]:self.first[i + 1]] for i in j]))

    def over(self, x, z):
        """Heights of the built surfaces over the plan point (x, z) and how far each faces up
        (its normal's y: 1 a floor, -1 a ceiling); walls standing upright have no height there."""
        ids = self._cells(self._key([math.floor(x / self.CELL)], [math.floor(z / self.CELL)]))
        T = self.T[ids]
        a, b, c = T[:, 0], T[:, 1], T[:, 2]
        e1, e2 = b - a, c - a
        det = e1[:, 0] * e2[:, 2] - e2[:, 0] * e1[:, 2]
        ok = np.abs(det) > 1e-9
        px, pz = x - a[:, 0], z - a[:, 2]
        with np.errstate(divide="ignore", invalid="ignore"):
            u = (px * e2[:, 2] - e2[:, 0] * pz) / det
            v = (e1[:, 0] * pz - px * e1[:, 2]) / det
            ok &= (u >= -1e-6) & (v >= -1e-6) & (u + v <= 1.0 + 1e-6)
            y = a[:, 1] + u * e1[:, 1] + v * e2[:, 1]
        return y[ok], self.ny[ids][ok]

    def crossed(self, p, q):
        """Does the segment p-q pass through a built triangle?"""
        p, q = np.asarray(p, float), np.asarray(q, float)
        d = q - p
        n = max(2, int(math.hypot(d[0], d[2]) / (self.CELL * 0.5)) + 2)
        f = np.linspace(0.0, 1.0, n)
        cx = np.floor((p[0] + d[0] * f) / self.CELL).astype(np.int64)
        cz = np.floor((p[2] + d[2] * f) / self.CELL).astype(np.int64)
        ids = self._cells(np.unique(self._key(cx, cz)))
        if not len(ids):
            return False
        T = self.T[ids]
        e1, e2 = T[:, 1] - T[:, 0], T[:, 2] - T[:, 0]
        h = np.cross(d, e2)
        det = (e1 * h).sum(1)
        ok = np.abs(det) > 1e-12
        with np.errstate(divide="ignore", invalid="ignore"):
            inv = 1.0 / det
            s = p - T[:, 0]
            u = (s * h).sum(1) * inv
            qv = np.cross(s, e1)
            v = (qv * d).sum(1) * inv
            t = (qv * e2).sum(1) * inv
            ok &= (u >= 0.0) & (v >= 0.0) & (u + v <= 1.0) & (t > 1e-3) & (t < 1.0 - 1e-3)
        return bool(ok.any())


class CrowdMixin:
    """Spectator placement for the generator's Ctx. Needs from the host: trk (Trk), models,
    props, ground(x, z), field (None: no terrain), meshes (a Mesh per kind) for stands, mats
    (hl2 / goldsrc names); optionally block() (props then keep out of stands and plots),
    side_width(style) (metres a style's side treatment takes past its road edge: stands keep
    off it) and roads: every road the spot rules keep people off, main first, as a list of Trk
    (or an object whose .trks is that list); without it the main road only."""

    def crowd_init(self, defn, seed=None):
        """Start empty: `defn` is the circuit's TRACK (seed, water level, lakes)."""
        self.crowds, self.crowd_groups, self.crowd_eggs = [], [], []
        self.crowd_plots = []  # plots kept free of buildings (grandstands), plan polygons
        self.crowd_route_id = None  # the branch id on a crowd_route() view, None on the main road
        self.crowd_rng = np.random.default_rng(defn.get("seed", 17) + 1 if seed is None else seed)
        self.water_level = float(defn.get("water", {}).get("level", -1000.0))
        self.waters = list(defn.get("waters", []))
        self.missing = getattr(self, "missing", set())
        self.canopies = []  # grandstand roofs: {"pos", "i", "sgn"} (a gnome may sit on one)
        self._steps = {}
        self._reach = {}
        self._taken = _Grid(2.0)
        self._boxes = None
        self._mouths = None
        self._egg_spots = []  # the G-Man's and the zombies' spots: nobody stands near them
        self._egg_points = []  # every egg's spots but the birds' and the Nihilanth's: eggs keep apart
        self._egg_bodies = []  # the hologram's, Lamarr's and the gnome's spots: nobody within EGG_BODY
        self._own = set()  # ids of the boxes the stands blocked (Ctx.boxes): people stand inside those
        # (shared with crowd_route copies) [mesh size, _Solids] of the collision meshes, [box count,
        # cells] of Ctx.boxes, the lap's crate centres
        self._solids = [None, None]
        self._box_cells = [None, None]
        self._crates = [None]
        self._crate_fracs = list(defn.get("items", []))  # the lap's crate rows (lap fractions)

    def crowd_route(self, trk, route_id):
        """The same placement (people, groups, eggs, spacing, stands: all shared) along a
        branch's road `trk` (an open Trk), for the circuit's per-branch crowds: sample ids, lap
        helpers and terraces then mean that road, and its groups and eggs get "route": route_id."""
        c = copy.copy(self)
        c.trk = trk
        c.crowd_route_id = route_id
        return c

    # ---------------------------------------------------------------- lap helpers
    def _closed(self, t=None):
        return getattr(self.trk if t is None else t, "closed", True)

    def s_of(self, i):
        """Metres of sample i along the ctx's road (lap metres on the main loop)."""
        return float(self.trk.s[i])

    def lap_ids(self, s0, s1):
        """Sample ids with distance in [s0, s1] along the road (wrapping on the loop; negative s0 =
        before the line)."""
        t = self.trk
        shifts = (0.0, -t.length, t.length) if self._closed() else (0.0,)
        out = []
        for i in range(t.n):
            s = self.s_of(i)
            if any(s0 <= s + sh <= s1 for sh in shifts):
                out.append(i)
        return out

    def ids_where(self, pred):
        return [i for i in range(self.trk.n) if pred(i)]

    def style_of(self, i):
        t = self.trk
        return t.styles[t.style[i]]

    @staticmethod
    def chunks(ids, every, length):
        """Runs of `length` samples starting every `every` samples along contiguous ids."""
        out = []
        for run in CrowdMixin.runs_of(ids):
            for a in range(0, len(run), every):
                if len(run[a:a + length]) >= 2:
                    out.append(run[a:a + length])
        return out

    @staticmethod
    def runs_of(ids, n=None):
        """Split sample ids into contiguous runs (lists). With `n` (a closed lap of n samples) a run
        ending on sample n - 1 runs on into one starting on sample 0 (a stand across the line)."""
        out = []
        for i in ids:
            if out and i == out[-1][-1] + 1:
                out[-1].append(i)
            else:
                out.append([i])
        if n is not None and len(out) > 1 and out[-1][-1] == n - 1 and out[0][0] == 0:
            out[0] = out.pop() + out[0]
        return out

    def _runs(self, ids):
        """runs_of(ids) along the ctx's road: on the lap across the start line."""
        return self.runs_of(sorted(ids), self.trk.n if self._closed() else None)

    def _run_s(self, run):
        """Metres along the road of the samples of a run, counted on across the start line."""
        s = self.trk.s[np.asarray(run)].astype(float)
        if self._closed():
            s = s + self.trk.length * np.concatenate([[0], np.cumsum(np.diff(s) < 0)])
        return s

    def side_point(self, i, sgn, lat, y=None, jitter=0.0):
        """Point `lat` metres past the road edge on side sgn (+1 right) at sample i, moved up
        to `jitter` metres along the road; y from the ground unless given."""
        t = self.trk
        q = t.pos[i] + t.flat_right[i] * sgn * (t.width[i] / 2 + lat)
        if jitter:
            q = q + t.fwd[i] * self.crowd_rng.uniform(-jitter, jitter)
        q[1] = self.ground(q[0], q[2]) if y is None else y
        return q

    # ---------------------------------------------------------------- road and the rules
    def crowd_roads(self):
        """Every road the spot rules keep people off (the host's `roads`, else the main road)."""
        r = getattr(self, "roads", None)
        if r is None:
            return [self.trk]
        return list(getattr(r, "trks", r))

    def road_gap_xz(self, q, dy_max=8.0):
        """Plan distance from q to the nearest road edge of any road. Tube samples count by
        their whole pipe (half = mag + 2.5); roads more than dy_max above or below q (an
        overpass) do not count, tubes always do."""
        best = 1e9
        for r in self.crowd_roads():
            base = getattr(r, "base", r.pos)
            d = np.hypot(base[:, 0] - q[0], base[:, 2] - q[2])
            tube = r.mag > 0
            half = np.where(tube, np.maximum(r.width / 2, r.mag + 2.5), r.width / 2)
            far = (np.abs(base[:, 1] - q[1]) > dy_max) & ~tube
            best = min(best, float(np.where(far, 1e9, d - half).min()))
        return best

    @staticmethod
    def _nearest_on(t, q):
        base = getattr(t, "base", t.pos)
        return int(np.argmin((base[:, 0] - q[0]) ** 2 + (base[:, 2] - q[2]) ** 2 + 4.0 * (base[:, 1] - q[1]) ** 2))

    def _nearest(self, q):
        return self._nearest_on(self.trk, q)

    def _tube_mouths(self):
        if self._mouths is None:
            self._mouths = []
            for r in self.crowd_roads():
                base = getattr(r, "base", r.pos)
                tube = r.mag > 0
                if self._closed(r):
                    edges = np.where(tube != np.roll(tube, 1))[0]
                    self._mouths += [base[k] for k in edges] + [base[k - 1] for k in edges]
                else:
                    edges = np.where(tube[1:] != tube[:-1])[0]
                    self._mouths += [base[k] for k in edges] + [base[k + 1] for k in edges]
        return self._mouths

    def _prop_boxes(self):
        """Rotated AABB of every prop (rebuilt when props were added)."""
        if self._boxes is None or self._boxes[0] != len(self.props):
            g = _Grid(16.0)
            for k, p in enumerate(self.props):
                m = self.models.get(p["model"])
                if m is None or p.get("tag") == "far":
                    continue
                sc = float(p.get("scale", 1.0))
                a = np.array(m["aabb_min"]) * sc
                b = np.array(m["aabb_max"]) * sc
                pos = np.array(p["pos"], float)
                r = float(np.hypot(*np.maximum(np.abs(a), np.abs(b))[[0, 2]]))
                g.add(pos[0], pos[2], (k, pos, float(p.get("yaw", 0.0)), a, b, r))
            self._boxes = (len(self.props), g)
        return self._boxes[1]

    def in_prop(self, q, margin=0.45, ignore=None):
        """The prop whose footprint (rotated AABB + margin) and height range hold q, or None."""
        for k, pos, yaw, a, b, r in self._prop_boxes().near(q[0], q[2], 48.0):
            if k == ignore or abs(pos[0] - q[0]) > r + 2 or abs(pos[2] - q[2]) > r + 2:
                continue
            c, s = math.cos(yaw), math.sin(yaw)
            dx, dz = q[0] - pos[0], q[2] - pos[2]
            lx = dx * c - dz * s
            lz = dx * s + dz * c
            if a[0] - margin < lx < b[0] + margin and a[2] - margin < lz < b[2] + margin \
                    and pos[1] + a[1] - 2.0 < q[1] < pos[1] + b[1] + 0.5:
                return self.props[k]["model"]
        return None

    def _in_hazard(self, q):
        """Inside a corridor tools/hazards.py keeps clear (ctx.reserved: (polyline, half width) per
        train line, strider, turret, houndeye pack...): nobody stands where a hazard works."""
        p = np.array([q[0], q[2]], float)
        for poly, half in getattr(self, "reserved", ()):
            P = np.asarray(poly, float)[:, [0, 2]]
            for a, b in zip(P[:-1], P[1:]):
                ab = b - a
                u = min(max(float((p - a) @ ab) / max(float(ab @ ab), 1e-9), 0.0), 1.0)
                if np.linalg.norm(p - (a + u * ab)) < half:
                    return True
        return False

    def _wet(self, q):
        if self.water_level > -500.0 and q[1] < self.water_level + 0.5:
            return True
        for w in self.waters:
            cx, cz = w["center"]
            sx, sz = w["size"]
            if abs(q[0] - cx) < sx / 2 and abs(q[2] - cz) < sz / 2 and q[1] < float(w["level"]) + 0.5:
                return True
        return False

    def slope(self, x, z):
        d = 1.0
        gx = (self.ground(x + d, z) - self.ground(x - d, z)) / (2 * d)
        gz = (self.ground(x, z + d) - self.ground(x, z - d)) / (2 * d)
        return math.hypot(gx, gz)

    # ---------------------------------------------------------------- what is built (rays)
    def solids(self):
        """The host's collision meshes as a _Solids (None without meshes: Highway 17), rebuilt
        when they grew."""
        meshes = getattr(self, "meshes", None)
        if not meshes:
            return None
        size = sum(len(p["i"]) for k in SOLID if k in meshes for p in meshes[k].parts.values())
        if self._solids[0] != size:
            self._solids[:] = [size, _Solids(meshes)]
        return self._solids[1]

    def built_over(self, q, lo=BODY[0], hi=BODY[1]):
        """Heights of what is built over the plan point of q from lo to hi metres above it (a
        pavement over the feet, a beam at head height); empty when there is nothing."""
        s = self.solids()
        if s is None:
            return []
        y, _ = s.over(q[0], q[2])
        return sorted(float(h) for h in y[(y > q[1] + lo) & (y <= q[1] + hi)])

    def _floor_over(self, q):
        """The built floor up to LIFT metres over a spot on the ground (a branch's pavement, a
        walkway) with room to stand on it, or None."""
        s = self.solids()
        if s is None:
            return None
        y, ny = s.over(q[0], q[2])
        up = y[(ny > 0.5) & (y > q[1] + 0.05) & (y <= q[1] + LIFT)]
        if not len(up):
            return None
        f = float(up.max())
        return None if ((y > f + BODY[0]) & (y <= f + BODY[1])).any() else f

    def walled_in(self, q, reach=6.0):
        """Is someone standing at q inside something built (a column, a block of flats): a face
        straight over the chest and built faces at least six ways of eight round it within `reach`
        metres? A wall behind or beside, a niche, a stand under the sky are not."""
        s = self.solids()
        if s is None:
            return False
        c = np.asarray(q, float) + UP * 1.2
        if not s.crossed(c, c + UP * 60.0):
            return False
        return sum(s.crossed(c, c + np.array([math.cos(a), 0.0, math.sin(a)]) * reach)
                   for a in np.arange(8) * math.pi / 4) >= 6

    def in_box(self, q, margin=0.3):
        """Would someone standing at q be inside one of the boxes built so far (Ctx.boxes: a
        column, a building's block, a solid prop), `margin` metres round it? The stands' own
        blocks (their people stand in them) do not count."""
        boxes = getattr(self, "boxes", None)
        if not boxes:
            return False
        if self._box_cells[0] != len(boxes):
            cells = {}
            for b in boxes:
                if id(b) in self._own:
                    continue
                cen, half, ax, az = b[:4]
                ext = np.abs(ax) * half[0] + np.abs(az) * half[1] + 1.0
                lo, hi = np.floor((cen - ext) / 8.0).astype(int), np.floor((cen + ext) / 8.0).astype(int)
                for i in range(lo[0], hi[0] + 1):
                    for j in range(lo[1], hi[1] + 1):
                        cells.setdefault((i, j), []).append(b)
            self._box_cells[:] = [len(boxes), cells]
        p = np.array([q[0], q[2]], float)
        for cen, half, ax, az, y0, y1 in self._box_cells[1].get((math.floor(q[0] / 8.0), math.floor(q[2] / 8.0)), ()):
            if y1 < q[1] + BODY[0] or y0 > q[1] + BODY[1]:
                continue
            d = p - cen
            if abs(d @ ax) < half[0] + margin and abs(d @ az) < half[1] + margin:
                return True
        return False

    def kart_reach(self, q):
        """A kart running wide off an open road (any road) reaches spot q: no further past its edge
        than the verge and DODGE_PAST metres, no barrier between."""
        for r in self.crowd_roads():
            k = self._nearest_on(r, q)
            st = r.styles[r.style[k]]
            if st.get("kind") != "open":
                continue
            lat = math.hypot(q[0] - r.pos[k][0], q[2] - r.pos[k][2]) - r.width[k] / 2
            if lat > st.get("verge_w", 4.5) + DODGE_PAST:
                continue
            bar = st.get("barrier")
            right = float(np.dot(np.asarray(q, float) - r.pos[k], r.flat_right[k])) > 0.0
            if bar and bar.get("sides", "both") in ("both", "right" if right else "left") and lat > bar.get("off", 0.2):
                continue
            return True
        return False

    def _crate_centres(self):
        """The lap's item crates as track_gen's item_rows lays them (the main road's "items"
        rows; none in a pipe)."""
        if self._crates[0] is None:
            t = self.crowd_roads()[0]
            out = []
            for frac in self._crate_fracs:
                i = int(frac * t.n) % t.n
                while t.gap[i % t.n] or t.gap[(i + 8) % t.n] or t.gap[(i - 8) % t.n]:
                    i += 5
                i %= t.n
                if t.mag[i] > 0:
                    continue
                cnt = 5 if t.width[i] >= 16 else 4
                w = t.width[i] / 2 - 2.5
                for k in range(cnt):
                    out.append(t.pos[i] + t.flat_right[i] * (-w + 2 * w * k / (cnt - 1)) + UP * 1.2)
            self._crates[0] = np.array(out).reshape(-1, 3)
        return self._crates[0]

    def _prop_crossed(self, p, q):
        """Does the segment p-q pass through a prop (its rotated bounding box)?"""
        mid = (p + q) / 2
        for k, pos, yaw, a, b, r in self._prop_boxes().near(mid[0], mid[2], float(np.linalg.norm(q - p)) / 2 + 2.0):
            c, s_ = math.cos(yaw), math.sin(yaw)
            ends = []
            for v in (p, q):
                dx, dz = v[0] - pos[0], v[2] - pos[2]
                ends.append(np.array([dx * c - dz * s_, v[1] - pos[1], dx * s_ + dz * c]))
            d = ends[1] - ends[0]
            t0, t1 = 0.0, 1.0
            for ax in range(3):
                if abs(d[ax]) < 1e-9:
                    if not a[ax] <= ends[0][ax] <= b[ax]:
                        break
                    continue
                ta, tb = (a[ax] - ends[0][ax]) / d[ax], (b[ax] - ends[0][ax]) / d[ax]
                t0, t1 = max(t0, min(ta, tb)), min(t1, max(ta, tb))
                if t0 > t1:
                    break
            else:
                return True
        return False

    def sight(self, p, q):
        """Nothing between points p and q: no built mesh that collides, no prop, no crate of the
        lap's rows, not the ground."""
        p, q = np.asarray(p, float), np.asarray(q, float)
        s = self.solids()
        if s is not None and s.crossed(p, q):
            return False
        C = self._crate_centres()
        if len(C):
            d = q - p
            u = np.clip(((C - p) @ d) / max(float(d @ d), 1e-9), 0.0, 1.0)
            if (np.linalg.norm(p + u[:, None] * d - C, axis=1) < 0.7).any():
                return False
        if self._prop_crossed(p, q):
            return False
        if getattr(self, "field", None) is not None:
            for f in np.linspace(0.05, 0.95, max(3, int(np.linalg.norm(q - p) / 2.0))):
                x = p + (q - p) * f
                if self.ground(x[0], x[2]) > x[1] + 0.05:
                    return False
        return True

    def crowd_fail(self, q, margin=1.5, on="ground", slope_max=0.45, dy=None, ignore=None, prop_margin=0.45):
        """Why spot q breaks the rules ("" if it does not). on="ground": the feet on the
        terrain (within 0.3 m); on="geom": q.y given by geometry (tiers, lips, decks, gallery).
        dy: allowed height range above the nearest road sample (rally ground spots). Either way
        nothing built may stand over the feet up to head height ("under geometry") and the body
        must not be inside something built ("box": in a box of Ctx.boxes and walled in)."""
        if self.road_gap_xz(q) < margin:
            return "road"
        if self._in_hazard(q):
            return "hazard"
        if any(math.hypot(e[0] - q[0], e[2] - q[2]) < EGG_CLEAR for e in self._egg_spots) or any(
                math.hypot(e[0] - q[0], e[2] - q[2]) < EGG_BODY and abs(e[1] - q[1]) < 2.0 for e in self._egg_bodies):
            return "egg"
        if any(np.hypot(m[0] - q[0], m[2] - q[2]) < 15.0 for m in self._tube_mouths()):
            return "tube mouth"
        if self._wet(q):
            return "water"
        # a pit beside any road (slime channels, a ledge, a cliff): nobody on that side close up
        for r in self.crowd_roads():
            k = self._nearest_on(r, q)
            # plan distance past the edge (beside the nearest sample it is the lateral one; past the
            # end of a branch it grows with the overshoot)
            edge = math.hypot(q[0] - r.pos[k][0], q[2] - r.pos[k][2]) - r.width[k] / 2
            st = r.styles[r.style[k]]
            if (isinstance(st.get("pit"), dict) and edge < st.get("wall_gap", 0.0) + 0.3) or \
                    (r.pit[k] and edge < 6.0 and q[1] < r.pos[k][1] + 0.5):
                return "pit"
        i = self._nearest(q)
        t = self.trk
        if on == "ground":
            if getattr(self, "field", None) is None:
                return "no terrain"
            g = self.ground(q[0], q[2])
            if abs(g - q[1]) > 0.3:
                return "off the ground"
            if self.slope(q[0], q[2]) > slope_max:
                return "slope"
        if dy is not None and not (dy[0] <= q[1] - t.pos[i][1] <= dy[1]):
            return "height"
        if self.in_prop(q, prop_margin, ignore=ignore):
            return "prop"
        if self.in_box(q) and self.walled_in(q):
            return "box"
        if self.built_over(q):
            return "under geometry"
        return ""

    def crowd_ok(self, q, margin=1.5, on="ground", slope_max=0.45, dy=None, ignore=None):
        """Spot q passes the rules (see crowd_fail)."""
        return self.crowd_fail(q, margin, on, slope_max, dy, ignore) == ""

    def _taken_at(self, q, r):
        for p in self._taken.near(q[0], q[2]):
            if abs(p[1] - q[1]) < 1.5 and math.hypot(p[0] - q[0], p[2] - q[2]) < r:
                return True
        return False

    # ---------------------------------------------------------------- reserved plots
    def reserve(self, ids, sgn, near, far):
        """Plot beside samples `ids` (side sgn) from `near` to `far` metres past the road edge,
        kept free of buildings: blocked as tall boxes (Ctx.block: add() refuses a prop through
        them, so building rows and the grid skip the plot) and kept for reserved_hit()."""
        t = self.trk
        ids = np.asarray(ids)
        hw = t.width[ids] / 2
        a = t.pos[ids] + t.flat_right[ids] * sgn * (hw + near)[:, None]
        b = t.pos[ids] + t.flat_right[ids] * sgn * (hw + far)[:, None]
        self.crowd_plots.append(np.vstack([a[:, [0, 2]], b[::-1][:, [0, 2]]]))
        y = t.pos[ids][:, 1]
        self._block(ids, sgn, np.full(len(ids), near), np.full(len(ids), far), y - 3.0, y + 80.0)

    def _block(self, ids, sgn, lat0, lat1, y0, y1):
        """Boxes from lat0 to lat1 metres past the road edge and from y0 to y1 at each sample:
        later props must not pass through them (hosts with Ctx.block)."""
        if not hasattr(self, "block"):
            return
        t = self.trk
        for k, i in enumerate(ids):
            rf = t.flat_right[i] * sgn
            c = t.pos[i] + rf * (t.width[i] / 2 + (lat0[k] + lat1[k]) / 2)
            c[1] = (y0[k] + y1[k]) / 2
            self.block(c, [t.step * 1.05, y1[k] - y0[k], lat1[k] - lat0[k]], math.atan2(rf[0], rf[2]))
            # (the stand's own: its people stand in it)
            self._own.add(id(self.boxes[-1]))

    def reserved_hit(self, pts):
        """Does a footprint outline (list of (x, z), from Ctx.footprint) touch a reserved plot?"""
        if not self.crowd_plots:
            return False
        fp = np.asarray(pts, float)
        for poly in self.crowd_plots:
            lo, hi = poly.min(0), poly.max(0)
            if (fp[:, 0].max() < lo[0] or fp[:, 0].min() > hi[0] or fp[:, 1].max() < lo[1]
                    or fp[:, 1].min() > hi[1]):
                continue
            if any(_in_poly(x, z, poly) for x, z in fp) or any(_in_poly(x, z, fp) for x, z in poly):
                return True
        return False

    # ---------------------------------------------------------------- stands
    def street_back(self, i):
        """(metres from the road edge to the back face of the street barrier, its height) at
        sample i, or None where there is no street or the barrier is over 2 m (a wall)."""
        st = self.style_of(i)
        if st["kind"] != "street":
            return None
        bar = st.get("barrier")
        walk = 0.3 + st.get("walk", 4.0)
        if not bar:
            return walk, 0.0
        kind = bar.get("kind", "wall")
        h = 1.05 if kind == "jersey" else bar.get("h", 1.2)
        if h > 2.0:
            return None
        thick = 0.95 if kind == "jersey" else bar.get("thick", 0.4 if kind == "wall" else 0.05)
        return walk + thick, h

    def stand_ok(self, i, sgn, near, far):
        """A stand fits beside sample i on side sgn from `near` to `far` metres past the road edge:
        the side treatment is there (a junction cuts it), and neither a hazard corridor nor another
        road (a branch, a hairpin's other leg) with its own side treatment reaches that ground."""
        t = self.trk
        side_off = getattr(t, "side_off", None)
        if side_off is not None and side_off[i, (sgn + 1) // 2]:
            return False
        Q = np.array([t.pos[i] + t.flat_right[i] * sgn * (t.width[i] / 2 + lat)
                      for lat in (near, (near + far) / 2, far)])
        if any(self._in_hazard(q) for q in Q):
            return False
        for r in self.crowd_roads():
            base = getattr(r, "base", r.pos)
            d = np.hypot(base[None, :, 0] - Q[:, None, 0], base[None, :, 2] - Q[:, None, 2])
            hit = (d < self._stand_reach(r)) & (np.abs(base[None, :, 1] - Q[:, None, 1]) <= 8.0)
            hit &= ~getattr(r, "hidden", np.zeros(r.n, bool))
            if r is t:
                # its own road beside it: the stand starts at that road's barrier
                dk = np.abs(np.arange(r.n) - i)
                hit &= (np.minimum(dk, r.n - dk) if self._closed(r) else dk) > 15
            if hit.any():
                return False
        return True

    def _stand_reach(self, r):
        """Per sample of road r, how far from its centre line a stand keeps: half the road (a pipe
        whole), its side treatment (the host's side_width(style), else none) and 0.3 m."""
        key = id(r)
        if key not in self._reach:
            side_w = getattr(self, "side_width", None)
            tw = np.array([side_w(r.styles[s]) for s in r.style]) if side_w else 0.0
            self._reach[key] = np.maximum(r.width / 2, r.mag + 2.5) + tw + 0.3
        return self._reach[key]

    def _stand_back(self, i, start):
        """Metres past the road edge where a stand at sample i begins (the barrier's back face)."""
        return start if start is not None else self.street_back(i)[0]

    def _mat(self, name):
        m = getattr(self, "mats", None)
        if m is None:
            return name
        return m.goldsrc(name[8:]) if name.startswith("goldsrc/") else m.hl2(name)

    def _step_key(self, i, sgn):
        return self.crowd_route_id, int(i), sgn

    def terrace(self, ids, sgn, steps=2, rise=0.45, depth=0.8, mat="concrete/concretewall008a", start=None,
                curb=0.16):
        """Steps behind the barrier along contiguous `ids` on side sgn, from the barrier's back
        face (or `start` metres past the road edge) outward, each `rise` higher and `depth`
        deep; the bottom 0.5 m under the lowest of road and terrain. Built as strips that
        follow the road (no overlapping boxes), left out where no stand fits (stand_ok).
        Returns the step tops per sample {i: [y0, y1, ...]}; terrace_spot() finds places on
        them."""
        t = self.trk
        mat = self._mat(mat)
        ids = [i for i in ids if (start is not None or self.street_back(i) is not None) and
               self.stand_ok(i, sgn, self._stand_back(i, start), self._stand_back(i, start) + steps * depth)]
        tops = {}
        for run in self._runs(ids):
            if len(run) < 2:
                continue
            run = np.asarray(run)
            back = np.array([self._stand_back(i, start) for i in run])
            rf = t.flat_right[run] * sgn
            hw = t.width[run] / 2
            road_y = t.pos[run][:, 1]
            far = t.pos[run] + rf * (hw + back + steps * depth * 0.5)[:, None]
            g = np.array([self.ground(p[0], p[2]) if getattr(self, "field", None) is not None else y
                          for p, y in zip(far, road_y)])
            bottom = np.minimum(road_y, g) - 0.5
            v = self._run_s(run) / 4.0
            fwd = t.fwd[run]

            def at(lat, y):
                p = t.pos[run] + rf * (hw + lat)[:, None]
                p[:, 1] = y
                return p

            for k in range(steps):
                lat0 = back + k * depth
                top = road_y + curb + rise * (k + 1)
                low = bottom if k == 0 else top - rise
                self.vert_strip(mat, at(lat0, low), at(lat0, top), v, -rf)           # riser, toward the road
                self.flat_strip(mat, at(lat0, top), at(lat0 + depth, top), v)        # tread
                for end, nrm in ((0, -fwd[0]), (-1, fwd[-1])):
                    self.cap_quad(mat, at(lat0, bottom)[end], at(lat0 + depth, bottom)[end],
                              at(lat0 + depth, top)[end], at(lat0, top)[end], nrm)
            lat_end = back + steps * depth
            self.vert_strip(mat, at(lat_end, road_y + curb + rise * steps), at(lat_end, bottom), v, rf)
            for k, i in enumerate(run):
                tops[int(i)] = [float(road_y[k] + curb + rise * (s + 1)) for s in range(steps)]
                self._steps[self._step_key(i, sgn)] = (float(back[k]), rise, depth, steps, float(road_y[k] + curb),
                                                       float(bottom[k]))
            self._block(run, sgn, back, back + steps * depth, bottom, road_y + curb + rise * steps)
        return tops

    def grandstand(self, ids, sgn, tiers=4, rise=0.5, depth=0.9, back_h=2.6, roof=True,
                   tier_mat="concrete/concretewall008a", back_mat="metal/citadel_metalwall072a", start=None):
        """terrace() with more tiers, a back wall (walls) and a canopy over it (deco); its plot
        is reserved first so no building lands on it. Returns the tier tops like terrace()."""
        t = self.trk
        ids = [i for i in ids if start is not None or self.street_back(i) is not None]
        if len(ids) < 2:
            return {}
        b0 = start if start is not None else min(self.street_back(i)[0] for i in ids)
        ids = [i for i in ids if self.stand_ok(i, sgn, b0 - 0.2, b0 + tiers * depth + 1.5)]
        for run in self._runs(ids):
            self.reserve(run, sgn, b0 - 0.2, b0 + tiers * depth + 1.5)
        tops = self.terrace(ids, sgn, tiers, rise, depth, tier_mat, start)
        bm = self._mat(back_mat)
        for run in self._runs(tops):
            if len(run) < 2:
                continue
            run = np.asarray(run)
            rf = t.flat_right[run] * sgn
            hw = t.width[run] / 2
            back = np.array([self._steps[self._step_key(i, sgn)][0] for i in run])
            bottom = np.array([self._steps[self._step_key(i, sgn)][5] for i in run])
            top = t.pos[run][:, 1] + 0.16 + rise * tiers
            v = self._run_s(run) / 4.0
            w0 = back + tiers * depth
            hi = top + back_h

            def at(lat, y):
                p = t.pos[run] + rf * (hw + lat)[:, None]
                p[:, 1] = y
                return p

            # back wall: 0.4 m thick from the top tier up, its outer face down to the bottom
            self.vert_strip(bm, at(w0, top), at(w0, hi), v, -rf)
            self.flat_strip(bm, at(w0, hi), at(w0 + 0.4, hi), v)
            self.vert_strip(bm, at(w0 + 0.4, hi), at(w0 + 0.4, bottom), v, rf)
            for end, nrm in ((0, -t.fwd[run[0]]), (-1, t.fwd[run[-1]])):
                self.cap_quad(bm, at(w0, bottom)[end], at(w0 + 0.4, bottom)[end], at(w0 + 0.4, hi)[end], at(w0, hi)[end],
                          nrm)
            if roof:
                # canopy: from over the back wall out past the front tier, seen from below
                c0, c1 = back - 0.4, w0 + 0.4
                self.flat_strip(bm, at(c0, hi + 0.25), at(c1, hi + 0.25), v, kind="deco")
                self.flat_strip(bm, at(c1, hi), at(c0, hi), v, kind="deco", down=True)
                self.vert_strip(bm, at(c0, hi), at(c0, hi + 0.25), v, -rf, kind="deco")
                k = len(run) // 2
                self.canopies.append({"pos": at((c0 + c1) * 0.5, hi + 0.25)[k], "i": int(run[k]), "sgn": sgn})
        return tops

    def terrace_spot(self, i, sgn, step, jitter=0.3):
        """A place on step `step` of the terrace / tier at sample i (None if there is none)."""
        st = self._steps.get(self._step_key(i, sgn))
        if st is None or step >= st[3]:
            return None
        back, rise, depth, steps, base, _bottom = st
        q = self.side_point(i, sgn, back + step * depth + depth * 0.5 + self.crowd_rng.uniform(-0.12, 0.12),
                            y=base + rise * (step + 1), jitter=jitter)
        return q

    # ---------------------------------------------------------------- geometry helpers (stands, galleries)
    def vert_strip(self, mat, a, b, v, nrm, kind="walls"):
        """Vertical strip between polylines a and b (one above the other) facing nrm (per point)."""
        hgt = np.abs(b[:, 1] - a[:, 1])
        n = np.asarray(nrm, float)
        lo, hi = (a, b) if np.dot(np.cross(b[0] - a[0], self._along(a)), n[0]) > 0 else (b, a)
        self.meshes[kind].strip(mat, lo, hi, 0.0, float(hgt.mean()) / 4.0, v, n, n)

    def flat_strip(self, mat, a, b, v, kind="walls", down=False):
        """Horizontal strip between polylines a and b, facing up (or down)."""
        want = -UP if down else UP
        lo, hi = (a, b) if np.dot(np.cross(b[0] - a[0], self._along(a)), want) > 0 else (b, a)
        w = float(np.linalg.norm(b[0] - a[0]))
        n = np.tile(want, (len(a), 1))
        self.meshes[kind].strip(mat, lo, hi, 0.0, w / 4.0, v, n, n)

    @staticmethod
    def _along(a):
        d = a[1] - a[0] if len(a) > 1 else np.array([0.0, 0.0, 1.0])
        return d / (np.linalg.norm(d) + 1e-9)

    def cap_quad(self, mat, p0, p1, p2, p3, nrm, kind="walls"):
        """One quad (p0..p3 around it) facing nrm."""
        q = [p0, p1, p2, p3]
        n = np.asarray(nrm, float)
        tri = [0, 1, 2, 0, 2, 3]
        if np.dot(np.cross(q[1] - q[0], q[2] - q[0]), n) < 0:
            tri = [0, 2, 1, 0, 3, 2]
        w = float(np.linalg.norm(p1 - p0))
        h = float(abs(p2[1] - p1[1]))
        self.meshes[kind].add(mat, q, [n] * 4, [[0, h / 4], [w / 4, h / 4], [w / 4, 0], [0, 0]], tri)

    # ---------------------------------------------------------------- people
    def crowd_group(self, i, sgn, kind, role, tags=(), watch=None, bed="human"):
        """A new group anchored at sample i on side sgn (0: both / off the road). `watch`:
        the stretch [s0, s1] of the road they look at (default: from where its members stand)."""
        assert kind in KINDS and role in ROLES, (kind, role)
        g = {"id": len(self.crowd_groups), "s": round(self.s_of(i), 1), "side": int(sgn), "kind": kind,
             "role": role, "watch": [float(watch[0]), float(watch[1])] if watch else None, "bed": bed,
             "tags": list(tags), "_wrap": self.trk.length if self._closed() else None}
        if self.crowd_route_id is not None:
            g["route"] = self.crowd_route_id
        self.crowd_groups.append(g)
        return g["id"]

    def _pick(self, role):
        pal = [m for m in CROWD_PALETTE.get(role, []) if m in self.models]
        if not pal:
            for m in CROWD_PALETTE.get(role, []):
                self.missing.add(m)
            return None
        return pal[int(self.crowd_rng.integers(0, len(pal)))]

    def crowd_add(self, gid, q, face, role, mood="fan", model=None, pose="stand", lod=0, dodge=None,
                  margin=1.5, on="ground", dy=None, ignore=None):
        """One spectator at q facing the point `face` (or the yaw `face`). model None: the
        role's palette. dodge: within a kart's reach (pavements, open shoulders), at least
        4.5 m from the road edge; None: so on the ground where a kart running wide off an open road
        reaches (kart_reach). A spot on the ground under a built floor up to LIFT metres over it (a
        pavement) stands on that floor. Returns False when the spot breaks a rule or is taken."""
        assert role in ROLES and mood in MOODS, (role, mood)
        q = np.asarray(q, float)
        if dodge is None:
            dodge = on == "ground" and self.kart_reach(q)
        if on == "ground":
            f = self._floor_over(q)
            if f is not None:
                q = np.array([q[0], f, q[2]])
                on = "geom"
        if dodge:
            margin = max(margin, 4.5)
        if self.crowd_fail(q, margin, on, dy=dy, ignore=ignore):
            return False
        if self._taken_at(q, 0.75 if pose == "sit" else SPACING):
            return False
        key = model if model is not None and model in self.models else self._pick(role)
        if model is not None and model not in self.models:
            self.missing.add(model)
        if key is None:
            return False
        if np.isscalar(face):
            yaw = float(face)
        else:
            d = np.asarray(face, float) - q
            yaw = math.atan2(d[0], d[2])
        yaw += float(self.crowd_rng.normal(0.0, 0.18))
        i = self._nearest(q)
        m = {"pos": _r3(q), "yaw": round(yaw, 3), "model": key, "role": role, "mood": mood, "pose": pose,
             "group": int(gid), "seed": int(self.crowd_rng.integers(0, 1 << 30)), "lod": int(lod),
             "dodge": bool(dodge), "_s": self.s_of(i), "_on": on, "_margin": margin, "_ignore": ignore}
        if on != "ground":
            m["on"] = on  # stands on geometry, not the terrain (the game's crowd_check skips the ground test)
        self.crowds.append(m)
        self._taken.add(q[0], q[2], q)
        return True

    def crowd_line(self, gid, ids, sgn, every, spot, role, mood="fan", chance=1.0, lod=None, face_road=True, **kw):
        """People along `ids` every `every` metres (closer than the sample step: several per
        sample, spread along the road) at spot(i, sgn) (a point or None), facing the road 6 m
        ahead or behind. lod: callable(k) or None for the default mix."""
        t = self.trk
        k = max(1, int(round(every / t.step)))
        per = max(1, int(round(t.step / every)))
        n = 0
        for i in list(ids)[::k]:
            if t.gap[i]:
                continue
            for j in range(per):
                if self.crowd_rng.random() > chance:
                    continue
                q = spot(i, sgn)
                if q is None:
                    continue
                if per > 1:
                    q = q + t.fwd[i] * ((j - (per - 1) / 2) * t.step / per)
                look = t.pos[i] + t.fwd[i] * self.crowd_rng.uniform(-6.0, 6.0) + UP * 1.0
                face = look if face_road else float(self.crowd_rng.uniform(0, 2 * math.pi))
                if self.crowd_add(gid, q, face, role, mood,
                                  lod=lod(n) if lod else LOD_CYCLE[len(self.crowds) % 20], **kw):
                    n += 1
        return n

    def crowd_cluster(self, gid, center, n, radius, role, face, mood="fan", ref_y=None, dy=(-1.0, 4.0), margin=2.5,
                      lod=None, **kw):
        """Up to n people on the ground within `radius` of center (rally style), at
        ref_y + dy[0]..dy[1] when ref_y is given, facing `face` (a point or a yaw)."""
        placed = 0
        for _ in range(n * 6):
            if placed >= n:
                break
            a = self.crowd_rng.uniform(0, 2 * math.pi)
            r = radius * math.sqrt(self.crowd_rng.uniform(0, 1))
            q = np.array([center[0] + math.cos(a) * r, 0.0, center[2] + math.sin(a) * r])
            q[1] = self.ground(q[0], q[2])
            if ref_y is not None and not (dy[0] <= q[1] - ref_y <= dy[1]):
                continue
            if self.crowd_add(gid, q, face, role, mood, margin=margin, on="ground",
                              lod=lod(placed) if lod else LOD_CYCLE[len(self.crowds) % 20], **kw):
                placed += 1
        return placed

    def on_top(self, prop, n, role, mood="fan", gid=None, face=None):
        """Up to n people on a flat-topped prop just placed (FLAT_TOPS), facing `face`."""
        key = prop["model"]
        if key not in FLAT_TOPS or key not in self.models:
            return 0
        m = self.models[key]
        sc = float(prop.get("scale", 1.0))
        a, b = np.array(m["aabb_min"]) * sc, np.array(m["aabb_max"]) * sc
        pos = np.array(prop["pos"], float)
        yaw = float(prop.get("yaw", 0.0))
        c, s = math.cos(yaw), math.sin(yaw)
        top = pos[1] + FLAT_TOPS[key] * sc
        k_prop = next((k for k, p in enumerate(self.props) if p is prop), None)
        placed = 0
        for _ in range(n * 6):
            if placed >= n:
                break
            lx = self.crowd_rng.uniform(a[0] + 0.4, b[0] - 0.4)
            lz = self.crowd_rng.uniform(a[2] + 0.4, b[2] - 0.4)
            q = np.array([pos[0] + lx * c + lz * s, top, pos[2] - lx * s + lz * c])
            look = face if face is not None else self.trk.pos[self._nearest(q)] + UP
            if self.crowd_add(gid, q, look, role, mood, margin=0.4, on="geom", ignore=k_prop,
                              lod=LOD_CYCLE[len(self.crowds) % 20]):
                placed += 1
        return placed

    # ---------------------------------------------------------------- spot helpers for the circuits
    def behind_barrier(self, i, sgn, step=0, jitter=0.35):
        """On terrace step `step` behind the street barrier at sample i (built by terrace())."""
        return self.terrace_spot(i, sgn, step, jitter)

    def lip_spot(self, i, sgn, inset=(0.6, 0.6)):
        """On the lip above a trench wall (canal, cutting), looking down into it."""
        t = self.trk
        st = self.style_of(i)
        if st["kind"] != "trench":
            return None
        lip = st.get("lip", 4.0)
        lat = self.crowd_rng.uniform(inset[0], max(inset[0], lip - inset[1]))
        return self.side_point(i, sgn, lat, y=t.pos[i][1] + t.height[i], jitter=0.4)

    def wall_spot(self, i, sgn, min_gap=2.5):
        """On a hall's side floor against its wall (wall_gap >= min_gap, no pit beside the road)."""
        st = self.style_of(i)
        gap = st.get("wall_gap", 0.0)
        if st["kind"] != "tunnel" or gap < min_gap or st.get("pit"):
            return None
        lat = gap - 0.55 + self.crowd_rng.uniform(-0.25, 0.1)
        return self.side_point(i, sgn, lat, y=self.trk.pos[i][1], jitter=0.4)

    def ground_spot(self, center, r_min, r_max, ylo, yhi, slope_max=0.35, margin=8.0, tries=400):
        """The flattest place on the ground between r_min and r_max metres (plan) from center
        with ylo <= height <= yhi that passes the rules (a beach, a shore), or None."""
        best, best_slope = None, slope_max
        for _ in range(tries):
            a = self.crowd_rng.uniform(0, 2 * math.pi)
            r = self.crowd_rng.uniform(r_min, r_max)
            q = np.array([center[0] + math.cos(a) * r, 0.0, center[2] + math.sin(a) * r])
            q[1] = self.ground(q[0], q[2])
            if not ylo <= q[1] <= yhi:
                continue
            sl = self.slope(q[0], q[2])
            if sl < best_slope and self.crowd_ok(q, margin, slope_max=slope_max):
                best, best_slope = q, sl
        return best

    def shoulder_spot(self, i, sgn, near, far):
        """On the ground near..far metres past the verge of an open road."""
        st = self.style_of(i)
        return self.side_point(i, sgn, st.get("verge_w", 4.5) + self.crowd_rng.uniform(near, far), jitter=0.8)

    # ---------------------------------------------------------------- eggs
    def egg(self, kind, **kw):
        """An easter egg for the game's CrowdEggs: gman (pos, yaw, s, model, window, chance),
        holo (pos, yaw, gap), lamarr (path), zombies (path, count, model), birds (species,
        center, radius, count), gnome (pos, yaw), nihilanth (pos). The G-Man and the zombies
        keep EGG_CLEAR metres from every spectator: spectators placed later keep away from
        them, and the egg is refused if someone already stands that close. The eggs on the
        ground keep EGG_CLEAR apart too (zombies must not shamble through the hologram). The
        hologram, Lamarr and the gnome take their spots from whoever stands within EGG_BODY of
        them, and nobody stands there later. Returns False when refused."""
        assert kind in EGGS, kind
        pts = [np.asarray(kw[k], float) for k in ("pos", "center") if k in kw] + \
              [np.asarray(p, float) for p in kw.get("path", [])]
        apart = kind not in ("birds", "nihilanth")
        if apart and any(math.hypot(p[0] - e[0], p[2] - e[2]) < EGG_CLEAR for p in pts for e in self._egg_points):
            return False
        if kind in ("gman", "zombies"):
            for p in pts:
                for m in self._taken.near(p[0], p[2], EGG_CLEAR):
                    if math.hypot(m[0] - p[0], m[2] - p[2]) < EGG_CLEAR:
                        return False
            self._egg_spots += pts
        if kind in ("holo", "lamarr", "gnome"):
            self._egg_bodies += pts
            self._make_way(pts)
        if apart:
            self._egg_points += pts
        e = {"kind": kind}
        if self.crowd_route_id is not None:
            e["route"] = self.crowd_route_id
        for k, v in kw.items():
            if k in ("pos", "center"):
                e[k] = _r3(v)
            elif k == "path":
                e[k] = [_r3(p) for p in v]
            elif isinstance(v, (list, tuple, np.ndarray)):
                e[k] = [round(float(x), 3) for x in v]
            elif isinstance(v, (float, np.floating)):
                e[k] = round(float(v), 3)
            else:
                e[k] = v
        self.crowd_eggs.append(e)
        return True

    def _make_way(self, pts):
        """Take out the people standing within EGG_BODY (plan, a storey up or down) of the points pts."""
        def near(q):
            return any(math.hypot(q[0] - p[0], q[2] - p[2]) < EGG_BODY and abs(q[1] - p[1]) < 2.0 for p in pts)

        gone = [m for m in self.crowds if near(m["pos"])]
        if not gone:
            return
        self.crowds[:] = [m for m in self.crowds if not near(m["pos"])]
        for cell in self._taken.cells.values():
            cell[:] = [q for q in cell if not near(q)]
        print("  crowds: %d made way for an egg at %s" % (len(gone), _r3(pts[0])))

    # ---------------------------------------------------------------- the G-Man's spot
    def gman_spot(self, lo, hi, off=(6.0, 45.0), spots=None, lift=1.0, speed=28.0):
        """Where the G-Man is seen best from the ctx's road under CrowdEggs' rules (shown once in
        view 25-70 m from the chase camera, recognisable at 40 px of 900, gone when it comes within
        15 m): of the ground spots `off` metres past the road edge beside its metres lo..hi, both
        sides (or of `spots`, points on geometry the caller vouches for), the one passing the spot
        rules with room to spare and nobody within EGG_CLEAR that the chase camera coming up the
        road at `speed` m/s sees longest, recognisable for a while, with nothing in between
        (walls, props, the ground, the lap's crate rows); a spot `lift` metres above the road scores
        a little more (he shows over the kerbs and crates). Returns {"pos", "yaw", "s", "window",
        "view_s", "seen_s"} (for egg("gman", pos=, yaw=, s=, window=, ...)) or None."""
        t = self.trk
        if spots is not None:
            cands = [(np.asarray(q, float), "geom") for q in spots]
        else:
            cands = [(self.side_point(i, sgn, float(lat)), "ground") for i in self.lap_ids(lo, hi)[::3]
                     for sgn in (-1, 1) for lat in np.arange(off[0], off[1] + 0.1, 4.0)]

        def at(s):
            k = int(round(s / t.step))
            return k % t.n if self._closed() else min(max(k, 0), t.n - 1)

        tan_h = math.tan(math.radians(CAM_FOV / 2))
        cos_v = math.cos(math.radians(CAM_FOV / 2 - 5.0))
        dt = 3.0 / speed
        best = None
        for q, on in cands:
            if self.crowd_fail(q, 1.0 if on == "geom" else 6.0, on) or any(
                    math.hypot(m[0] - q[0], m[2] - q[2]) < EGG_CLEAR for m in self._taken.near(q[0], q[2], EGG_CLEAR)):
                continue
            i = self._nearest(q)
            chest = q + UP * GMAN_H * 0.75
            # the chase camera coming up the road from 150 m before him, every 3 m, as the game shows him:
            # in view 25-70 m off with nothing between, gone within 15 m, after 8 s, or out of view
            # once he has stood there 3 s (and 3 s since he was big enough to be seen)
            shown, t_on, seen_at, view_s, seen_s, first, last, face = False, 0.0, None, 0.0, 0.0, None, None, None
            for back in np.arange(150.0, -12.0, -3.0):
                s = self.s_of(i) - back
                if not self._closed() and not 0.0 <= s <= t.length:
                    continue
                j = at(s)
                cam = t.pos[j] - t.fwd[j] * CAM_BACK + UP * CAM_UP
                look = t.pos[at(s + 22.0)] + UP * 1.4 - cam
                to = chest - cam
                d = float(np.linalg.norm(to))
                if d < GMAN_NEAR:
                    break
                vis = float(to @ look) > cos_v * d * float(np.linalg.norm(look)) and \
                    (shown or GMAN_SHOW[0] <= d <= GMAN_SHOW[1]) and self.sight(cam, chest)
                if shown:
                    t_on += dt
                    if t_on > 8.0 or (not vis and t_on >= 3.0 and (seen_at is None or t_on - seen_at >= 3.0)):
                        break
                elif vis:
                    shown, first = True, s + CAM_BACK
                if shown and vis:
                    view_s += dt
                    last = s + CAM_BACK
                    if GMAN_H / (2.0 * d * tan_h) >= GMAN_SEEN:
                        seen_s += dt
                        if seen_at is None:
                            seen_at, face = t_on, cam
            if seen_s <= 0.0:
                continue
            score = view_s + 2.0 * seen_s + (0.5 if q[1] >= t.pos[i][1] + lift else 0.0)
            if best is None or score > best[0]:
                d = face - q
                L = t.length if self._closed() else 1e9
                best = (score, {"pos": q, "yaw": math.atan2(d[0], d[2]), "s": self.s_of(i),
                                "window": [round(float((first - 10.0) % L), 1), round(float((last + 5.0) % L), 1)],
                                "view_s": round(view_s, 2), "seen_s": round(seen_s, 2)})
        return best[1] if best else None

    # ---------------------------------------------------------------- check and export
    def check_crowds(self, budget=True):
        """The spot rules again on everything placed; raises on a member on the road, in a
        hazard's corridor, in a tube, in water, over a pit, inside a prop or a built box, or under
        something built. Prints counts per role and lod and the most people one view sees per preset
        (warns over the budgets: per view and MAX_PEOPLE in all)."""
        bad = []
        for m in self.crowds:
            q = np.array(m["pos"], float)
            why = self.crowd_fail(q, m["_margin"] - 0.05, m["_on"], slope_max=0.5, ignore=m["_ignore"], prop_margin=0.4)
            if why in ("road", "hazard", "tube mouth", "water", "pit", "prop", "box", "under geometry"):
                bad.append((m["model"], m["pos"], why))
        for e in self.crowd_eggs:
            for k in ("pos", "center"):
                if k in e and e["kind"] != "nihilanth" and self.road_gap_xz(np.array(e[k], float)) < 0.5:
                    bad.append((e["kind"], e[k], "egg on the road"))
        roles, lods = {}, [0, 0, 0]
        for m in self.crowds:
            roles[m["role"]] = roles.get(m["role"], 0) + 1
            lods[m["lod"]] += 1
        worst = self.worst_views()
        print("  crowds: %d people in %d groups, %d eggs; lod %s; roles %s" % (
            len(self.crowds), len({m["group"] for m in self.crowds}), len(self.crowd_eggs), lods,
            dict(sorted(roles.items()))))
        print("  crowds: most in one view (FEW / FULL / HIGH): %s" % " / ".join(str(w) for w in worst))
        if budget:
            for (lod, rng_, cap), w in zip(VIEW_BUDGET, worst):
                if w > cap:
                    print("  !! crowds: %d in one view at lod <= %d (budget %d)" % (w, lod, cap))
            if len(self.crowds) > MAX_PEOPLE:
                print("  !! crowds: %d people (budget %d)" % (len(self.crowds), MAX_PEOPLE))
        if bad:
            raise ValueError("crowd spots break the rules: %s" % bad[:12])

    def worst_views(self):
        """Most people within range ahead of a chase camera anywhere on any road, per preset."""
        if not self.crowds:
            return [0, 0, 0]
        P = np.array([m["pos"] for m in self.crowds])
        L = np.array([m["lod"] for m in self.crowds])
        out = []
        for lod, rng_, _ in VIEW_BUDGET:
            best = 0
            for t in self.crowd_roads():
                for i in range(0, t.n, 3):
                    cam = t.pos[i] - t.fwd[i] * 8.6 + UP * 3.3
                    d = P - cam
                    dist = np.linalg.norm(d, axis=1)
                    ahead = (d @ t.fwd[i]) > -0.25 * dist
                    best = max(best, int(((dist < rng_) & ahead & (L <= lod)).sum()))
            out.append(best)
        return out

    def crowd_export(self):
        """The track JSON keys: groups get their centre, radius and (if not given) the stretch of
        their road their members watch; groups nobody joined are left out."""
        groups = []
        keep = {}
        for g in self.crowd_groups:
            mem = [m for m in self.crowds if m["group"] == g["id"]]
            if not mem:
                continue
            P = np.array([m["pos"] for m in mem])
            c = P.mean(0)
            out = {k: v for k, v in g.items() if not k.startswith("_")}
            out["id"] = len(groups)
            keep[g["id"]] = out["id"]
            out["center"] = _r3(c)
            out["radius"] = round(float(np.hypot(P[:, 0] - c[0], P[:, 2] - c[2]).max()) + 1.0, 2)
            if out["watch"] is None:
                w = g["_wrap"]
                rel = [m["_s"] - g["s"] if w is None else ((m["_s"] - g["s"] + w / 2) % w) - w / 2 for m in mem]
                out["watch"] = [round(g["s"] + min(rel) - 10.0, 1), round(g["s"] + max(rel) + 10.0, 1)]
            groups.append(out)
        crowds = []
        for m in self.crowds:
            if m["group"] in keep:
                crowds.append({k: v for k, v in m.items() if not k.startswith("_")} | {"group": keep[m["group"]]})
        return {"crowd_groups": groups, "crowds": crowds, "crowd_eggs": list(self.crowd_eggs)}


class _TrackView:
    """Another module's track as the placement API reads it: its own attributes, plus or over
    them the ones given (the track itself is left as it is)."""

    def __init__(self, trk, **extra):
        self._trk = trk
        self.__dict__.update(extra)

    def __getattr__(self, name):
        return getattr(self._trk, name)


class H17Ctx(CrowdMixin):
    """Highway 17 (build_track.py) dressed like a track_gen Ctx for the placement API: its
    themes become styles (city: kerb and a 6 m pavement before the invisible wall, canal: a
    trench whose wall tops carry a 7.5 m shelf, coast and dirt: open roads); people stand on
    site.ground (the pavement, the shelf and the verges over the terrain) and keep clear of
    site.props (in_prop tests the same boxes site.taken holds)."""

    STYLES = {"city": {"kind": "street", "walk": 6.0},
              "canal": {"kind": "trench", "lip": 7.5},
              "coast": {"kind": "open", "verge_w": 4.5},
              "dirt": {"kind": "open", "verge_w": 4.5}}

    def __init__(self, trk, site, sea_level, seed=1998):
        f = trk.fwd
        fr = np.stack([-f[:, 2], np.zeros(trk.n), f[:, 0]], 1)
        # the canal's wall tops (and the shelf) over the road: kerb height at the mouths
        rise = trk.canal_rise(np.arange(trk.n)) if hasattr(trk, "depth") else np.zeros(trk.n)
        self.trk = _TrackView(trk, base=trk.pos, mag=np.zeros(trk.n), pit=trk.gap.copy(),
                              flat_right=fr / np.linalg.norm(fr, axis=1, keepdims=True), style=list(trk.theme),
                              styles=self.STYLES, height=rise)
        self.site = site
        self.models = site.models
        self.props = site.props
        self.field = True
        self.crowd_init({"water": {"level": sea_level}, "seed": seed - 1})

    def ground(self, x, z):
        return float(self.site.ground(x, z))
