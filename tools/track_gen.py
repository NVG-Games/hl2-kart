"""Themed procedural circuits in the manner of Highway 17 (tools/build_track.py).

A circuit is a closed Catmull-Rom spline through control points. Each control
point names the cross-section style of the stretch that starts there (a City 17
street, an open road, a tunnel or hall, a bridge, a trench) and flags such as a
jump gap. The builder turns that into visible, colliding geometry only: every
wall the karts can hit is drawn. Terrain, props, lights, item crates and boost
pads come from the circuit's own module in tools/circuits/.

A circuit module may also list BRANCHES: shortcuts and other roads that leave the lap at a fork
and rejoin it at a merge (open splines with the same control points and styles, see Branch and
tools/branches.py). Every road then shares the terrain, the props' road checks and the export.

Its TRACK may declare "hazards": traps and shooting NPCs on the lap (tools/hazards.py), which cut
the fences where a train crosses and keep corridors clear of props. Its stands(ctx) and
crowds(ctx) put up the spectators' stands and the spectators and easter eggs (tools/crowds.py:
the placement API on Ctx). build() calls the hooks in this order: stands, stands_branch,
decorate, decorate_branch, crowds, crowds_branch (each *_branch once per branch, on a view of
the context that dresses that branch's road).

Writes assets/track/<id>.gltf (+.bin), <id>.json and <id>_height.bin.

usage: python track_gen.py <circuit> [<circuit> ...]     (ct17, black_mesa, xen, surface_tension)
"""
import copy
import importlib
import json
import math
import os
import sys
from types import SimpleNamespace

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import branches  # noqa: E402
import crowds  # noqa: E402
import hazards  # noqa: E402
import materials  # noqa: E402
import srcfs  # noqa: E402
import goldsrc_bsp as gb  # noqa: E402
from build_track import Mesh, catmull_rom_closed, cyc_runs, noise2, smoothstep, racing_line  # noqa: E402
from mdl import GLTFBuilder, gltf_material  # noqa: E402

ASSETS = os.path.normpath(os.path.join(HERE, "..", "assets"))
OUT_DIR = os.path.join(ASSETS, "track")
UP = np.array([0.0, 1.0, 0.0])
# (colonly: collision the game never draws, see a barrier's "col_h")
MESH_KINDS = ("road", "verge", "walls", "side", "ceil", "decal", "deco", "glow", "terrain", "colonly")
# rules for several roads meeting or passing each other: the terrain between a road and another
# stretch close by (carve), props kept off branch roads and junctions (Ctx.add) and no fall where
# another road lies below (safe_drop). All off, a circuit without branches builds exactly as it
# did before branches existed (the regression check of the branch design)
RULES = {"second_road": True, "road_guard": True, "safe_drop": True}
# a layout that breaks a branch rule stops the build; False reports the problems and builds on
# (drafts of new layouts)
STRICT = True


# ---------------------------------------------------------------- materials
class Mats:
    """HL2 materials (VMT through MaterialLib) and HL1 textures (WAD) under one name space.
    HL1 ones are called "goldsrc/<texture>" and exported as PNG next to the converted maps."""

    def __init__(self):
        self.fs = srcfs.GameFS()
        self.lib = materials.MaterialLib(self.fs, ASSETS)
        self.wads = gb.load_wads(["halflife.wad", "xeno.wad", "liquids.wad", "decals.wad"])
        self.hl1 = {}

    def hl2(self, name):
        info = self.lib.material(name)
        if "albedo" not in info:
            print("  !! missing HL2 material", name)
        return name

    def goldsrc(self, tex, glow=False, scale=4):
        key = "goldsrc/" + tex.lower()
        if key in self.hl1:
            return key
        blob = None
        for w in self.wads:
            blob = w.miptex(tex)
            if blob:
                break
        if blob is None:
            print("  !! missing HL1 texture", tex)
            self.hl1[key] = {"name": key, "shader": "lightmappedgeneric"}
            return key
        _, w, h, rgba = gb.decode_miptex(blob)
        alpha = tex.startswith("{")
        safe = tex.lower().replace("{", "a_").replace("!", "w_").replace("~", "l_").replace("+", "p_").replace("-", "m_")
        rel = "materials/goldsrc/track/%s.png" % safe
        out = os.path.join(ASSETS, rel)
        os.makedirs(os.path.dirname(out), exist_ok=True)
        im = Image.fromarray(rgba, "RGBA")
        if not alpha:
            im = im.convert("RGB")
        # the WAD art is small: a smooth 4x upscale keeps it from smearing into mush up close
        im = im.resize((w * scale, h * scale), Image.LANCZOS)
        im.save(out)
        info = {"name": key, "shader": "lightmappedgeneric", "albedo": rel, "goldsrc": True, "size": [w, h]}
        if alpha:
            info["alphatest"] = True
        if glow or "~" in tex:
            info["selfillum"] = True
        self.hl1[key] = info
        return key

    def info(self, name):
        if name.startswith("goldsrc/"):
            return self.hl1.get(name, {"name": name})
        return self.lib.material(name)

    def save_db(self):
        mpath = os.path.join(ASSETS, "data", "materials.json")
        db = json.load(open(mpath)) if os.path.exists(mpath) else {}
        db.update(self.lib.db)
        for k, v in self.hl1.items():
            db[k] = {kk: vv for kk, vv in v.items() if kk != "name"}
        with open(mpath, "w") as f:
            json.dump(db, f, indent=1)


# ---------------------------------------------------------------- the spline
def tube_roll(st, s, L):
    """The lane's roll round a tube style's pipe (radians) at metres s into a stretch L long: none
    over the entry mouth (the style's "mouth", at most a fifth of it), its "roll" ("profile"
    "screw": round the pipe, "wall": up a wall and back), done "settle" metres before the exit
    mouth (the lane stays at the bottom there, so a kart on the wall slides down before the end)."""
    mouth = min(st.get("mouth", 14.0), L * 0.2)
    u = np.clip((s - mouth) / max(L - 2 * mouth - st.get("settle", 0.0), 1e-3), 0.0, 1.0)
    if st.get("profile", "screw") == "wall":
        e = np.sin(np.pi * u) ** 2          # up the wall and back down
    else:
        e = u * u * (3 - 2 * u)              # all the way round
    return math.radians(st.get("roll", 360.0)) * e


# a pipe's lane is back within TUBE_SETTLE_DEG of its bottom for this many metres before its exit
TUBE_SETTLE, TUBE_SETTLE_DEG = 40.0, 10.0


def tube_checks(trk, name):
    """Lines for the printout: each pipe whose lane is still rolled TUBE_SETTLE_DEG or more round it
    less than TUBE_SETTLE metres before its exit (a kart riding the wall there leaves the mouth high
    up), with the "settle" its style needs."""
    out = []
    for ids, _ in trk.tube_runs:
        st = trk.styles[trk.style[ids[0]]]
        s = np.arange(len(ids)) * trk.step
        L = len(ids) * trk.step

        def clear(style):
            off = np.abs((tube_roll(style, s, L) + math.pi) % (2 * math.pi) - math.pi)
            bad = np.flatnonzero(off >= math.radians(TUBE_SETTLE_DEG))
            return L - s[bad[-1]] if len(bad) else L

        have = clear(st)
        if have >= TUBE_SETTLE:
            continue
        # (at least 20 m left for the roll itself)
        top = L - 2 * min(st.get("mouth", 14.0), L * 0.2) - 20.0
        need = next((x for x in np.arange(2.0, top, 2.0) if clear(dict(st, settle=x)) >= TUBE_SETTLE), None)
        out.append("%s pipe s %.0f-%.0f: its lane is back at the bottom only %.0f m before the exit (%.0f wanted): "
                   "give the style \"settle\": %s" % (name, trk.s[ids[0]], trk.s[ids[-1]], have, TUBE_SETTLE,
                                                     "%.0f" % need if need is not None else "(the pipe is too short)"))
    return out


class Trk:
    """Samples every `step` metres along the spline with frames, widths, styles and per-control
    flags; gap samples have no road (a jump). The lap is closed. A branch's road (Branch) is an
    open spline (closed=False) through its fork and merge points, with pre / post phantom points
    for its end tangents; it is sampled with both ends included, 3k + 1 samples so the exported
    path (every third) ends on its last one, and framed as if the main road ran on beyond its
    ends (pad: the main road's samples before the fork and after the merge, moved onto it)."""

    def __init__(self, ctrl, styles, step=2.0, closed=True, pre=None, post=None, pad=None, follow=None):
        self.ctrl = ctrl
        self.styles = styles
        self.closed = closed
        pts = [(c[0], c[1], c[2]) for c in ctrl]
        if closed:
            dense, seg, tt = catmull_rom_closed(pts, 200)
            d = np.linalg.norm(np.diff(np.vstack([dense, dense[:1]]), axis=0), axis=1)
            s = np.concatenate([[0], np.cumsum(d)])
            self.length = float(s[-1])
            n = int(self.length // step)
            self.step = self.length / n
            target = np.arange(n) * self.step
            idx = np.searchsorted(s, target, side="right") - 1
            frac = (target - s[idx]) / np.maximum(d[idx % len(d)], 1e-9)
            nxt = (idx + 1) % len(dense)
        else:
            dense, seg, tt = branches.catmull_rom_open(pts, pre, post, 200)
            d = np.linalg.norm(np.diff(dense, axis=0), axis=1)
            s = np.concatenate([[0], np.cumsum(d)])
            self.length = float(s[-1])
            n = 3 * max(int(round(self.length / (3 * step))), 1) + 1
            self.step = self.length / (n - 1)
            target = np.linspace(0.0, self.length, n)
            idx = np.clip(np.searchsorted(s, target, side="right") - 1, 0, len(d) - 1)
            frac = (target - s[idx]) / np.maximum(d[idx], 1e-9)
            nxt = idx + 1
        self.pos = dense[idx] * (1 - frac[:, None]) + dense[nxt] * frac[:, None]
        self.seg = seg[idx]
        self.segt = tt[idx] + frac / 200.0
        self.n = n
        self.s = target
        w0 = np.array([ctrl[i][3] for i in self.seg], float)
        w1 = np.array([ctrl[(i + 1) % len(ctrl)][3] for i in self.seg], float)
        sm = self.segt * self.segt * (3 - 2 * self.segt)
        self.width = w0 * (1 - sm) + w1 * sm
        self.style = [ctrl[i][4] for i in self.seg]
        self.flags = [ctrl[i][5] if len(ctrl[i]) > 5 else {} for i in self.seg]
        # tunnel / hall ceiling height, interpolated like the width
        # heights blend only toward a control of the same kind (a tunnel keeps its roof
        # height up to the portal instead of sinking toward the open road after it)
        kinds = [self.styles[c[4]]["kind"] for c in ctrl]
        h0 = np.array([self._h(i) for i in self.seg], float)
        h1 = np.array([self._h((i + 1) % len(ctrl)) if kinds[(i + 1) % len(ctrl)] == kinds[i] else self._h(i)
                       for i in self.seg], float)
        self.height = h0 * (1 - sm) + h1 * sm
        # tunnel / hall walls stand this far beyond the road edge
        self.wall_gap = self._wall_ramps(np.array([self.styles[s].get("wall_gap", 0.0)
                                                   if self.styles[s]["kind"] == "tunnel" else 0.0 for s in self.style]))
        self.gap = np.zeros(n, bool)
        self._apply_gaps()
        # (a branch: its heights where it still lies on the main road, see Branch._follow)
        if follow is not None:
            follow(self)
        self._frames(pad)
        self._tubes()
        # where falling below the road means leaving the track (open edges, jumps)
        self.pit = self.gap | np.array([bool(self.styles[s].get("pit")) for s in self.style])
        # junctions (Branch): side treatments left out per side (column 0 left, 1 right), the
        # inner road edge snapped onto the main road's edge and the side it is on, samples with
        # no road of their own (a drop merge's landing on the main road) and which samples are in
        # a fork's or a merge's shared stretch
        self.side_off = np.zeros((n, 2), bool)
        self.trim_in = np.full((n, 3), np.nan)
        self.inner = np.zeros(n, int)
        self.hidden = np.zeros(n, bool)
        self.junction = np.zeros(n, bool)
        # (sample, side column) where a side treatment starts or ends at a nose: an end face there
        self.noses = set()
        # samples where no barrier stands: a hazard's level crossing (hazards.barrier_cuts, build())
        self.cut = np.zeros(n, bool)

    def wrap(self, i):
        """Sample index i on this road: round the lap, or clamped to an open road's ends."""
        return i % self.n if self.closed else min(max(i, 0), self.n - 1)

    def _wall_ramps(self, gap):
        """Wall gaps per sample from each style's own: where one tunnel style meets another with
        its walls further out, the wider one's walls run in or out over a ramp inside it (about
        14 degrees), so the two meet on one line instead of in a step a kart could hit head on."""
        out = gap.copy()
        n = len(gap)
        tun = [self.styles[s]["kind"] == "tunnel" for s in self.style]
        for j in range(0 if self.closed else 1, n):
            a = (j - 1) % n
            d = gap[a] - gap[j]
            if not (tun[a] and tun[j]) or self.style[a] == self.style[j] or abs(d) < 0.05:
                continue
            k = max(2, int(round(np.clip(4.0 * abs(d), 8.0, 30.0) / self.step)))
            # inside the wider stretch: from the narrower one's line at the meeting sample j out
            # to its own; nested ramps on a short stretch keep the narrower of the two
            first, step_ = ((j - 1) % n, -1) if d > 0 else (j, 1)
            wide = self.style[first]
            for q in range(k + 1):
                i = first + step_ * q
                if not self.closed and not 0 <= i < n:
                    break
                i %= n
                if self.style[i] != wide:
                    break
                u = (q + (1 if d > 0 else 0)) / k
                out[i] = min(out[i], min(gap[a], gap[j]) + abs(d) * smoothstep(0.0, 1.0, u))
        return out

    def _h(self, ci):
        c = self.ctrl[ci]
        fl = c[5] if len(c) > 5 else {}
        st = self.styles[c[4]]
        return fl.get("height", st.get("height", 8.0 if st["kind"] == "tunnel" else 0.0))

    def kind(self, i):
        return self.styles[self.style[i]]["kind"]

    def _apply_gaps(self):
        self.gaps = []
        for ci, c in enumerate(self.ctrl):
            fl = c[5] if len(c) > 5 else {}
            if not fl.get("gap"):
                continue
            a, b = fl.get("gap_span", (0.42, 0.62))
            ids = [i for i in range(self.n) if self.seg[i] == ci and a < self.segt[i] < b]
            if not ids:
                continue
            for i in ids:
                self.gap[i] = True
            first, last = ids[0], ids[-1]
            # kicker ramp on the approach
            ramp = int(fl.get("ramp_len", 16) / self.step)
            lift = fl.get("ramp_lift", 1.8)
            for k in range(ramp):
                j = first - ramp + k
                if not self.closed and j < 0:
                    continue
                j %= self.n
                u = (k + 1) / ramp
                self.pos[j, 1] += lift * u * u
            self.gaps.append((first, last + 1))

    def _frames(self, pad=None):
        """Forward, right (banked) and up, and the plan curvature. On an open spline the cyclic
        neighbours are the pad's (unbanked) main road samples, cut off again afterwards."""
        P = self.pos
        banked = np.array([self.styles[s].get("bank", False) for s in self.style])
        if pad is not None:
            P = np.vstack([pad[0], P, pad[1]])
            banked = np.concatenate([np.zeros(len(pad[0]), bool), banked, np.zeros(len(pad[1]), bool)])
        n = len(P)
        f = np.roll(P, -1, axis=0) - np.roll(P, 1, axis=0)
        f /= np.linalg.norm(f, axis=1, keepdims=True)
        right = np.stack([-f[:, 2], np.zeros(n), f[:, 0]], 1)
        right /= np.linalg.norm(right, axis=1, keepdims=True)
        h = np.stack([f[:, 0], f[:, 2]], 1)
        hn = np.roll(h, -3, axis=0)
        hp = np.roll(h, 3, axis=0)
        cross = hp[:, 0] * hn[:, 1] - hp[:, 1] * hn[:, 0]
        curv = cross / (6 * self.step)
        bank = np.where(banked, np.clip(curv * 120.0, -0.15, 0.15), 0.0)
        for _ in range(30):
            bank = (np.roll(bank, 1) + bank * 2 + np.roll(bank, -1)) / 4
        c, s_ = np.cos(bank), np.sin(bank)
        up0 = np.cross(right, f)
        rb = right * c[:, None] - up0 * s_[:, None]
        up = np.cross(rb, f)
        up /= np.linalg.norm(up, axis=1, keepdims=True)
        keep = slice(len(pad[0]), len(pad[0]) + self.n) if pad is not None else slice(None)
        self.fwd, self.curv, self.right, self.up, self.flat_right = f[keep], curv[keep], rb[keep], up[keep], right[keep]

    def _tubes(self):
        """Tube stretches: the road runs on the inside of a pipe and rolls around it
        (a corkscrew, or up a wall and back), so a kart drives on walls and the
        ceiling. The spline gives the road at the pipe's bottom; the pipe's axis is
        `radius` above it. Keeps the untwisted frames in base/base_up/base_right
        (terrain and the pipe's geometry follow those) and writes mag (the radius,
        0 outside tubes): the game turns gravity towards the pipe wall there."""
        n = self.n
        self.base = self.pos.copy()
        self.base_up = self.up.copy()
        self.base_right = self.right.copy()
        self.theta = np.zeros(n)
        self.mag = np.zeros(n)
        self.tube_runs = []
        for ids in self.runs(lambda i: self.kind(i) == "tube", with_gaps=True):
            st = self.styles[self.style[ids[0]]]
            R = float(st.get("radius", 12.0))
            th = tube_roll(st, np.arange(len(ids)) * self.step, len(ids) * self.step)
            axis = self.pos[ids] + self.up[ids] * R
            rad = -(np.cos(th)[:, None] * self.up[ids] + np.sin(th)[:, None] * self.right[ids])
            self.pos[ids] = axis + rad * R
            self.theta[ids] = th
            self.mag[ids] = R
            self.tube_runs.append((ids, R))
        if not self.tube_runs:
            return
        f = np.roll(self.pos, -1, axis=0) - np.roll(self.pos, 1, axis=0)
        f /= np.linalg.norm(f, axis=1, keepdims=True)
        for ids, R in self.tube_runs:
            for i in ids:
                up = self.base[i] + self.base_up[i] * R - self.pos[i]
                up /= np.linalg.norm(up)
                fw = f[i] - up * np.dot(f[i], up)
                fw /= np.linalg.norm(fw)
                self.fwd[i] = fw
                self.up[i] = up
                self.right[i] = np.cross(fw, up)

    def surface(self, i, lat, h=0.0):
        """A point `lat` metres across the road and `h` above it (on a tube's curve)."""
        if self.mag[i] > 0.0:
            R = self.mag[i]
            a = self.theta[i] + lat / R
            axis = self.base[i] + self.base_up[i] * R
            rad = -(math.cos(a) * self.base_up[i] + math.sin(a) * self.base_right[i])
            return axis + rad * (R - h)
        return self.pos[i] + self.right[i] * lat + self.up[i] * h

    def frame_at(self, i, lat):
        """The surface point `lat` metres across sample i with the local up and forward there. On
        a tube's curve up points at the pipe's axis and forward is the lane's direction in that
        tangent plane; elsewhere they are the road's own."""
        p = self.surface(i, lat)
        if self.mag[i] <= 0.0:
            return p, self.up[i], self.fwd[i]
        up = self.base[i] + self.base_up[i] * self.mag[i] - p
        up /= np.linalg.norm(up)
        f = self.fwd[i] - up * np.dot(self.fwd[i], up)
        return p, up, f / np.linalg.norm(f)

    def axis_dir(self, i):
        """Unit direction of the untwisted centre line (a pipe's axis) at sample i."""
        d = self.base[self.wrap(i + 1)] - self.base[self.wrap(i - 1)]
        return d / np.linalg.norm(d)

    def edge(self, i, off):
        return self.pos[i] + self.right[i] * off

    def side_reach(self, sgn, beyond):
        """Per sample, how far past the road's edge (plan metres) a strip beside it reaches on side
        sgn when it wants `beyond`: on the inside of a tight bend a wide pavement or verge would
        fold back on itself (its outer edge running backwards between two samples), so there it
        keeps to 85 % of the way to that from the centre line, easing in and out."""
        key = (sgn, round(float(beyond), 4))
        cache = self.__dict__.setdefault("_reach", {})
        if key in cache:
            return cache[key]
        n = self.n
        nxt = (np.arange(n) + 1) % n if self.closed else np.minimum(np.arange(n) + 1, n - 1)
        f = self.fwd[:, [0, 2]] / np.linalg.norm(self.fwd[:, [0, 2]], axis=1, keepdims=True)
        ahead = ((self.pos[nxt][:, [0, 2]] - self.pos[:, [0, 2]]) * f).sum(1)
        turn = ((self.flat_right[nxt][:, [0, 2]] - self.flat_right[:, [0, 2]]) * f).sum(1) * sgn
        seg = np.where(turn < -1e-9, 0.85 * ahead / np.maximum(-turn, 1e-9), np.inf)
        room = np.minimum(seg, seg[np.arange(n) - 1 if self.closed else np.maximum(np.arange(n) - 1, 0)])
        room = np.maximum(room - self.width / 2, 0.0)
        out = np.full(n, float(beyond))
        if (out > room).any():
            def near(a, k):
                return np.roll(a, k) if self.closed else a[np.clip(np.arange(n) - k, 0, n - 1)]
            out = np.minimum(out, room)
            for _ in range(3):
                out = np.minimum((near(out, 1) + 2 * out + near(out, -1)) / 4, beyond)
            out = np.minimum(out, room)
        cache[key] = out
        return out

    def runs(self, pred, with_gaps=False):
        """Index runs (arrays; wrapped round the lap) where pred(i) holds and the road exists. A run
        carries the next sample too, so strips join up, unless that sample is a jump gap (a run that
        ends at a kicker stops at its lip) or past an open road's end."""
        mask = np.array([pred(i) and (with_gaps or not self.gap[i]) for i in range(self.n)])
        if not self.closed:
            return [np.arange(a, b + 1 if b < self.n and (with_gaps or not self.gap[b]) else b)
                    for a, b in _bool_runs(mask)]
        return [np.arange(a, b + 1 if with_gaps or not self.gap[b % self.n] else b) % self.n
                for a, b in cyc_runs(mask)]

    def style_runs(self, kinds):
        kinds = (kinds,) if isinstance(kinds, str) else kinds
        return self.runs(lambda i: self.kind(i) in kinds)

    def nearest(self, p, hint, window):
        """Sample nearest p in plan within `window` samples of hint."""
        ids = np.array([self.wrap(hint + k) for k in range(-window, window + 1)])
        return int(ids[np.argmin(((self.pos[ids][:, [0, 2]] - np.asarray(p)[[0, 2]]) ** 2).sum(1))])


# ---------------------------------------------------------------- branches
# a branch's ends may only meet these kinds of main road (a hall takes an in_hall branch)
JUNCTION_KINDS = ("street", "open", "bridge")
# beside the main road the roads part for good where they are this far apart in height (a ramp
# up to a roof or a catwalk)
NOSE_DY = 2.5
# the branch's shared stretch ends within this far of its fork and of its merge
NOSE_MAX = 70.0
# ... and the game counts the main road's own lap metres up to 10 m before it
NOSE_MIN = 15.0
# where a branch still lies on the main road it takes the main road's surface (Branch._follow),
# easing back to its own heights over this far beyond, or at this grade where it was further off
FOLLOW_EASE, FOLLOW_GRADE = 20.0, 0.08
# a branch's inner edge is snapped onto the main road's edge only where their heights agree
SNAP_DY = 0.3


def _treatment(st):
    """Metres a style's side treatment takes beyond its road edge (kerb, pavement and barrier; a
    verge or a fenced margin; a deck's edge and railing), None for kinds no junction may meet."""
    bar = st.get("barrier")
    thick = 0.0
    if bar:
        kind = bar.get("kind", "wall")
        thick = 0.95 if kind == "jersey" else bar.get("thick", 0.4 if kind == "wall" else 0.05)
    if st["kind"] == "street":
        return 0.3 + st.get("walk", 4.0) + thick
    if st["kind"] == "open":
        return max(st.get("verge_w", 4.5), bar.get("off", 0.2) + thick if bar else 0.0)
    if st["kind"] == "bridge":
        return 1.0 + thick
    return None


def gore_gap(st_main, st_branch):
    """The gap between the road edges at a nose: both side treatments side by side and a metre."""
    a, b = _treatment(st_main), _treatment(st_branch)
    return None if a is None or b is None else a + b + 1.0


class Branch:
    """A branch of the lap (an entry of the circuit module's BRANCHES, see tools/branches.py): an
    open spline from its fork to its merge on the main road, with the same control points and
    styles as the lap ("fork" / "merge": (x, z) near the main road or a lap fraction; "ctrl": the
    points in between). It starts inside the main road, its outer edge on the main road's edge
    and along its tangent, and rejoins it the same way. From the fork the two roads share surface
    up to where their edges part; a gore fills between them up to the nose, where both side
    treatments fit side by side (or the branch is 2.5 m above or below the main road); the merge
    mirrors it, unless the branch lands on the main road after its last jump ("merge_type":
    "drop"). In a hall ("in_hall": a catwalk inside a wide tunnel) nothing of the main road is cut:
    the branch climbs from the road's edge over the hall's floor, its nose where it is 2.5 m up."""

    PAD = 16

    def __init__(self, main, spec, styles, step, index, g=branches.G):
        self.main, self.spec, self.index = main, spec, index
        # the gravity its jumps' launch speeds are worked out for (TRACK["gravity"])
        self.g = g
        self.id = spec["id"]
        self.in_hall = bool(spec.get("in_hall", False))
        self.drop = spec.get("merge_type", "gore") == "drop"
        ctrl = [c if len(c) > 5 else tuple(c) + ({},) for c in spec["ctrl"]]
        self.i0 = self._resolve(spec["fork"])
        self.i1 = self._resolve(spec["merge"])
        self.side0 = spec.get("side") or self._side_of(self.i0, ctrl[0])
        self.side1 = spec.get("merge_side") or self._side_of(self.i1, ctrl[-1])
        # the centre across the main road at the ends: the outer edge on the main road's edge (in a
        # hall a hand over it, so what shows of it outside the road stands on the hall's floor)
        self.lat0 = self.side0 * (main.width[self.i0] - ctrl[0][3]) / 2
        self.lat1 = self.side1 * (main.width[self.i1] - ctrl[-1][3]) / 2
        lift = UP * (0.02 if self.in_hall else 0.0)
        a = main.pos[self.i0] + main.right[self.i0] * self.lat0 + lift
        b = main.pos[self.i1] + main.right[self.i1] * self.lat1 + lift
        pad = (self._shifted(range(self.i0 - self.PAD, self.i0), self.lat0) + lift,
               self._shifted(range(self.i1 + 1, self.i1 + 1 + self.PAD), self.lat1) + lift)
        # the phantom points: the next control point mirrored about the main road's tangent line, so
        # the centripetal spline leaves the fork and joins the merge exactly along that tangent
        first = (a[0], a[1], a[2], ctrl[0][3], ctrl[0][4], {})
        last = (b[0], b[1], b[2], ctrl[-1][3], ctrl[-1][4], {})
        self.moved = {}
        self.trk = Trk([first] + ctrl + [last], styles, step, closed=False, pre=self._phantom(a, ctrl[0], self.i0),
                       post=self._phantom(b, ctrl[-1], self.i1), pad=pad, follow=self._follow)
        # the end samples' cross-sections are the main road's own: the kerbs, verges and decks
        # running on from one road into the other meet edge to edge
        for k, i in ((0, self.i0), (self.trk.n - 1, self.i1)):
            for key in ("fwd", "right", "up", "flat_right", "base_up", "base_right"):
                getattr(self.trk, key)[k] = getattr(main, key)[i]
        self.trim_seg = {}
        self.zones = {end: self._junction(end) for end in ("fork", "merge")}
        self._cut_sides()

    def _resolve(self, where):
        """Main sample of a fork or merge given as (x, z) near the road or as a lap fraction: one the
        exported path keeps (every third), so the game's lap metres of it are exact."""
        m = self.main
        if np.isscalar(where):
            i = int(round(where * m.n)) % m.n
        else:
            i = int(np.argmin(((m.pos[:, [0, 2]] - np.asarray(where, float)) ** 2).sum(1)))
        return min(3 * int(round(i / 3.0)), 3 * ((m.n - 1) // 3))

    def _side_of(self, i, c):
        return 1 if (np.array(c[:3], float) - self.main.pos[i]) @ self.main.flat_right[i] > 0 else -1

    def _phantom(self, p, c, i):
        """The phantom point beside end p for its neighbour control point c: c mirrored about the
        main road's tangent line at sample i through p. Equally far from p as c, it makes the
        centripetal Catmull-Rom's tangent at p lie along that line."""
        f = self.main.fwd[i]
        d = np.array(c[:3], float) - p
        return p - (2.0 * (f @ d) * f - d)

    def _shifted(self, ids, lat):
        m = self.main
        return np.array([m.pos[m.wrap(j)] + m.right[m.wrap(j)] * lat for j in ids])

    def _main_y(self, i, p):
        """Height of the main road's surface (its plane at sample i, carried on past its edge) under
        the plan point p."""
        m = self.main
        d = np.asarray(p, float) - m.pos[i]
        f, r = m.fwd[i], m.right[i]
        fl, rl = math.hypot(f[0], f[2]), math.hypot(r[0], r[2])
        along = (d[0] * f[0] + d[2] * f[2]) / max(fl, 1e-9)
        lat = (d[0] * r[0] + d[2] * r[2]) / max(rl, 1e-9)
        return float(m.pos[i, 1] + along * f[1] / max(fl, 1e-9) + lat * r[1] / max(rl, 1e-9))

    def _overlap(self, t, end):
        """(branch sample, main sample) pairs walking from one end while the branch's road still
        overlaps the main road in plan (its edges not yet apart), up to a jump or a pipe."""
        m = self.main
        fork = end == "fork"
        side = self.side0 if fork else self.side1
        i = self.i0 if fork else self.i1
        out = []
        for k in (range(t.n) if fork else range(t.n - 1, -1, -1)):
            if t.gap[k] or t.kind(k) == "tube":
                break
            i = m.nearest(t.pos[k], i, 30)
            lat = float((t.pos[k] - m.pos[i]) @ m.flat_right[i]) * side
            if lat - t.width[k] / 2 - m.width[i] / 2 >= 0.0:
                break
            out.append((k, i))
        return out

    def _follow(self, t):
        """Trk's follow hook, before its frames: where the branch's road still overlaps the main
        road (from either end until their edges part) it lies on the main road's surface (in a hall
        a hand over it), and beyond it eases back to its own heights (FOLLOW_EASE, FOLLOW_GRADE), so
        the two roads meet without a step, a twisted deck or a crack whatever its control points
        say. How far its heights were moved is kept for the printout (moved)."""
        lift = 0.02 if self.in_hall else 0.0
        total = np.zeros(t.n)
        for end in ("fork", "merge"):
            pairs = self._overlap(t, end)
            if not pairs:
                continue
            off = np.zeros(t.n)
            for k, i in pairs:
                off[k] = self._main_y(i, t.pos[k]) + lift - t.pos[k, 1]
            k_last = pairs[-1][0]
            ease = max(FOLLOW_EASE, abs(off[k_last]) / FOLLOW_GRADE)
            # (up to a jump: across its gap the roads may differ, a drop's landing is the main road)
            beyond = np.arange(k_last + 1, t.n) if end == "fork" else np.arange(k_last - 1, -1, -1)
            hit = np.flatnonzero(t.gap[beyond])
            beyond = beyond[:hit[0]] if len(hit) else beyond
            d = np.abs(t.s[beyond] - t.s[k_last])
            off[beyond] = off[k_last] * (1.0 - smoothstep(0.0, ease, d))
            total += off
            ks = [k for k, _ in pairs]
            self.moved[end] = (float(np.abs(off[ks]).max()), float(t.s[min(ks)]), float(t.s[max(ks)]), ease)
        t.pos[:, 1] += total

    def _junction(self, end):
        """One end's shared stretch, walking from the fork (or back from the merge): the main sample
        abreast of each branch sample, the gap between their edges and their height apart. Marks
        both roads' samples (junction) and, where the branch is still on the main road (and level
        with it, SNAP_DY: see _follow), its inner edge snapped onto the main road's (trim_in,
        inner); finds the edges part (k_sep, the first gap > 0) and the nose (k_nose / i_nose). A
        drop merge's landing shows no road at all."""
        m, t = self.main, self.trk
        fork = end == "fork"
        side = self.side0 if fork else self.side1
        ks = range(t.n) if fork else range(t.n - 1, -1, -1)
        i = self.i0 if fork else self.i1
        drop = self.drop and not fork
        gore = None if self.in_hall or drop else gore_gap(m.styles[m.style[i]], t.styles[t.style[ks[0]]])
        z = {"side": side, "gore": gore, "k_sep": None, "k_nose": None, "i_nose": None, "walk": []}
        for k in ks:
            i = m.nearest(t.pos[k], i, 30)
            lat = float((t.pos[k] - m.pos[i]) @ m.flat_right[i]) * side
            gap = lat - t.width[k] / 2 - m.width[i] / 2
            dy = float(t.pos[k, 1] - m.pos[i, 1])
            if z["k_sep"] is None and gap > 0.0:
                z["k_sep"] = k
            # (a drop merge comes down on the main road where its last jump ends: its landing)
            if (gore is not None and gap >= gore) or abs(dy) > NOSE_DY or (drop and t.gap[k]):
                z["k_nose"], z["i_nose"] = k, i
                break
            t.junction[k] = True
            m.junction[i] = True
            z["walk"].append((k, i, gap, lat, dy))
            if drop:
                t.hidden[k] = True
                t.side_off[k] = True
            elif gap < 0.0 and abs(dy) < SNAP_DY:
                p = self._on_edge(i, side, k)
                if p is not None:
                    t.trim_in[k] = p
                    t.inner[k] = -side
        return z

    def _on_edge(self, i, side, k):
        """Where branch sample k's cross-section (along its right) crosses the main road's edge on
        `side` near main sample i: a point on that edge's polyline (the main road strip's own
        vertices), so the trimmed branch road meets it without a crack."""
        m, t = self.main, self.trk
        c, r = t.pos[k], t.right[k]
        best = None
        for j in range(i - 4, i + 4):
            j0, j1 = m.wrap(j), m.wrap(j + 1)
            if j1 == j0:
                continue
            a = m.pos[j0] + m.right[j0] * (side * m.width[j0] / 2)
            e = m.pos[j1] + m.right[j1] * (side * m.width[j1] / 2) - a
            det = e[0] * r[2] - r[0] * e[2]
            if abs(det) < 1e-9:
                continue
            w = a - c
            s = (e[0] * w[2] - w[0] * e[2]) / det
            u = (r[0] * w[2] - w[0] * r[2]) / det
            if -1e-6 <= u <= 1.0 + 1e-6 and (best is None or abs(s) < abs(best[0])):
                best = (s, j0, min(max(u, 0.0), 1.0), a + e * min(max(u, 0.0), 1.0))
        if best is None:
            return None
        self.trim_seg[k] = (best[1], best[2])
        return best[3]

    def _cut_sides(self):
        """Side treatments left out over the shared stretches: the main road's on the branch's side
        from the fork to the nose and from the merge nose to the merge, the branch's on its inner
        side (none in a hall). The samples at the ends of a cut keep theirs, so the strips run on
        into the other road's (at the fork the main road's kerb carries on as the branch's)."""
        m, t = self.main, self.trk
        for end, z in self.zones.items():
            if z["k_nose"] is None or self.in_hall or (self.drop and end == "merge"):
                continue
            col_m, col_b = (z["side"] + 1) // 2, (1 - z["side"]) // 2
            if end == "fork":
                for d in range(1, (z["i_nose"] - self.i0) % m.n):
                    m.side_off[m.wrap(self.i0 + d), col_m] = True
                t.side_off[:z["k_nose"], col_b] = True
            else:
                for d in range(1, (self.i1 - z["i_nose"]) % m.n):
                    m.side_off[m.wrap(z["i_nose"] + d), col_m] = True
                t.side_off[z["k_nose"] + 1:, col_b] = True
            m.noses.add((z["i_nose"], col_m))
            t.noses.add((z["k_nose"], col_b))

    def nose_k(self, end):
        """Branch sample of a nose (the drop merge's: where the branch lands on the main road)."""
        z = self.zones[end]
        if z["k_nose"] is None:
            return 0 if end == "fork" else self.trk.n - 1
        if end == "merge" and self.drop and z["walk"]:
            return z["walk"][-1][0]
        return z["k_nose"]

    def nose_i(self, end):
        """Main sample abreast of a nose."""
        z = self.zones[end]
        if end == "merge" and self.drop and z["walk"]:
            return z["walk"][-1][1]
        return z["i_nose"] if z["i_nose"] is not None else (self.i0 if end == "fork" else self.i1)

    def jumps(self):
        """The branch's jump gaps: (first, end) samples, length, the kicker's lift and length, how
        far the far side lies below the lip, and the launch speed it takes."""
        t = self.trk
        out = []
        for a, b in t.gaps:
            ci = int(t.seg[a])
            fl = t.ctrl[ci][5] if len(t.ctrl[ci]) > 5 else {}
            lift, ramp = fl.get("ramp_lift", 1.8), fl.get("ramp_len", 16)
            gap = (b - a + 1) * t.step
            drop = float(t.pos[a - 1, 1] - t.pos[min(b, t.n - 1), 1])
            out.append((a, b, gap, lift, ramp, drop, branches.launch_speed(gap, lift, ramp, drop, self.g)))
        return out

    def racing(self, defn):
        """The branch's racing line and target speeds (build_track.racing_line on the branch with the
        main road's samples beyond its ends): the first and last 6 samples stay on its centre line,
        so a computer driver's target slides onto it inside the shared stretch; beside an open edge
        it keeps to the middle, as on the lap."""
        m, t = self.main, self.trk
        P, pins = self.PAD, 6
        pre = [m.wrap(j) for j in range(self.i0 - P, self.i0)]
        post = [m.wrap(j) for j in range(self.i1 + 1, self.i1 + 1 + P)]
        held = t.gap.copy()
        held[:pins] = held[-pins:] = True
        lane = SimpleNamespace(
            n=t.n + 2 * P, step=t.step,
            pos=np.vstack([self._shifted(range(self.i0 - P, self.i0), self.lat0), t.pos,
                           self._shifted(range(self.i1 + 1, self.i1 + 1 + P), self.lat1)]),
            right=np.vstack([m.right[pre], t.right, m.right[post]]),
            width=np.concatenate([np.full(P, t.width[0]), t.width, np.full(P, t.width[-1])]),
            gap=np.concatenate([np.ones(P, bool), held, np.ones(P, bool)]))
        line, off, vt = racing_line(lane)
        keep = slice(P, P + t.n)
        line, off, vt = line[keep], off[keep], vt[keep]
        edge = t.pit & ~t.gap
        if edge.any():
            lim = np.maximum(t.width / 2 - 6.5, 0.0)
            off = np.where(edge, np.clip(off, -lim, lim), off)
            line = t.pos + t.right * off[:, None]
        self.line, self.vt = line, np.minimum(vt, style_vmax(t, defn.get("vmax", 40.0)))

    def export(self, lap):
        """The branch's track JSON entry (tools/branches.py): fork / merge in the game's lap metres,
        the noses, the path with s_main (branches.s_main: the game's own progress at the junctions
        and where the branch runs within 20 m of the main road's edge, smooth in between) and what
        its jumps take."""
        m, t = self.main, self.trk
        path = path_data(t, self.line, self.vt)
        ids = np.arange(0, t.n, 3)
        fork_i, merge_i = self.i0 // 3, self.i1 // 3
        # near the main road: its stretch from the fork to the merge within 20 m (edge to edge)
        span = [m.wrap(j) for j in range(self.i0 - 20, self.i0 + (self.i1 - self.i0) % m.n + 21)]
        d = np.sqrt(((t.pos[ids][:, None, [0, 2]] - m.pos[span][None, :, [0, 2]]) ** 2).sum(-1))
        near = (d - (t.width[ids][:, None] + m.width[span][None, :]) / 2).min(1) < 20.0
        noses = (self.nose_k("fork") // 3, -(-self.nose_k("merge") // 3))
        path["s_main"] = branches.s_main(lap, t.pos[ids], near, fork_i, merge_i, noses).round(2).tolist()
        jumps = self.jumps()
        need = branches.SPEED_MARGIN * max([j[-1] for j in jumps]) if jumps else 0.0
        fork_s, merge_s = fork_i * lap.step, merge_i * lap.step
        return branches.entry(
            self.spec, self.index, path, fork_s=round(fork_s, 2), merge_s=round(merge_s, 2), fork_i=fork_i,
            merge_i=merge_i, fork_nose_u=round(float(t.s[self.nose_k("fork")]), 2),
            merge_nose_u=round(float(t.s[self.nose_k("merge")]), 2),
            fork_nose_i=int(round(self.nose_i("fork") / 3.0)) % lap.n,
            merge_nose_i=int(round(self.nose_i("merge") / 3.0)) % lap.n, side=int(self.side0),
            merge_side=int(self.side1), length=round(t.length, 2), saves=round(merge_s - fork_s - t.length, 2),
            need_speed=round(need, 2), need_boost=bool(need > branches.TOP_SPEED))

    def outline(self, end):
        """A shared stretch's plan outline (from the main road's edge out past the branch's outer
        side treatment, fork or merge to the nose) and its lowest and highest road height: no prop
        of the lap's may stand in it (Ctx.keep_off)."""
        m, t = self.main, self.trk
        z = self.zones[end]
        if z["k_nose"] is None or (end == "merge" and self.drop):
            return None
        side = z["side"]
        ks = range(0, z["k_nose"] + 1) if end == "fork" else range(z["k_nose"], t.n)
        a, b = (self.i0, z["i_nose"]) if end == "fork" else (z["i_nose"], self.i1)
        mi = [m.wrap(a + d) for d in range((b - a) % m.n + 1)]
        out = [_treatment(t.styles[t.style[k]]) or 1.0 for k in ks]
        inner = [m.pos[i] + m.flat_right[i] * side * m.width[i] / 2 for i in mi]
        outer = [t.pos[k] + t.flat_right[k] * side * (t.width[k] / 2 + o + 1.0) for k, o in zip(ks, out)]
        pts = np.array(inner + outer[::-1])
        return pts[:, [0, 2]], float(pts[:, 1].min()), float(pts[:, 1].max())

    def summary(self):
        """One line for the build's printout."""
        m, t = self.main, self.trk
        stretch = ((self.i1 - self.i0) % m.n) * m.step
        jumps = self.jumps()
        need = branches.SPEED_MARGIN * max([j[-1] for j in jumps]) if jumps else 0.0
        return ("  branch %-13s fork %.3f merge %.3f  %4.0f m vs %4.0f m on the lap (saves %+.0f m)  noses %.0f / %.0f m"
                "  jumps %s  need %.1f m/s%s" % (
                    self.id, self.i0 / m.n, self.i1 / m.n, t.length, stretch, stretch - t.length,
                    t.s[self.nose_k("fork")], t.length - t.s[self.nose_k("merge")],
                    ", ".join("%.0f m" % j[2] for j in jumps) or "none", need,
                    " (boost)" if need > branches.TOP_SPEED else ""))


def lap_line(trk, defn, brs=()):
    """The lap's racing line and target speeds (build_track.racing_line): beside an open edge it
    keeps to the middle (the apex is where you fall), and over each shared stretch 3 m off the side
    a branch leaves or joins from, easing in and out over 20 m (a computer driver that stays on the
    lap clears the nose)."""
    line, off, vt = racing_line(trk)
    edge = trk.pit & ~trk.gap
    if edge.any():
        lim = np.maximum(trk.width / 2 - 6.5, 0.0)
        off = np.where(edge, np.clip(off, -lim, lim), off)
        line = trk.pos + trk.right * off[:, None]
    for br in brs:
        for end, z in br.zones.items():
            if end == "merge" and br.drop:
                continue
            a, b = (br.i0, br.nose_i("fork")) if end == "fork" else (br.nose_i("merge"), br.i1)
            span = (b - a) % trk.n
            d = np.arange(-10, span + 11)
            ids = np.array([trk.wrap(a + q) for q in d])
            lim = trk.width[ids] / 2 - 3.0 + np.maximum(0, np.maximum(-d, d - span)) * 0.4
            off[ids] = np.minimum(off[ids] * z["side"], lim) * z["side"]
        line = trk.pos + trk.right * off[:, None]
    return line, off, np.minimum(vt, style_vmax(trk, defn.get("vmax", 40.0)))


def style_vmax(trk, vmax):
    """The target speed cap per sample: the circuit's vmax, or a style's own "vmax" where it is
    lower (a run of hairpins a computer driver should take at one steady speed instead of
    sprinting between them)."""
    return np.array([min(vmax, trk.styles[s].get("vmax", vmax)) for s in trk.style])


def safe_drop(trks):
    """No fall where another road lies under a sample a kart could drop from (pit: an open edge or a
    jump): a road surface (a hall's floor too) more than a metre inside its edge and 2..25 m lower,
    on another road or 40 m or more along the same one. The kart lands and drives on, and the game
    moves it onto that road. Returns how many samples changed."""
    changed = 0
    for r, t in enumerate(trks):
        for r2, t2 in enumerate(trks):
            ids = np.flatnonzero(t.pit & (t.mag <= 0.0))
            if not len(ids):
                break
            floor = np.array([t2.wall_gap[j] if t2.kind(j) == "tunnel" and not t2.styles[t2.style[j]].get("pit") else 0.0
                              for j in range(t2.n)])
            half = t2.width / 2 + floor - 1.0
            d = np.sqrt(((t.pos[ids][:, None, [0, 2]] - t2.pos[None, :, [0, 2]]) ** 2).sum(-1))
            dy = t.pos[ids, 1][:, None] - t2.pos[None, :, 1]
            hit = (d < half[None, :]) & (dy >= 2.0) & (dy <= 25.0) & (~t2.gap & ~t2.hidden & (t2.mag <= 0.0))[None, :]
            if r == r2:
                dk = np.abs(ids[:, None] - np.arange(t.n)[None, :])
                hit &= (np.minimum(dk, t.n - dk) if t.closed else dk) > 20
            land = hit.any(1)
            t.pit[ids[land]] = False
            changed += int(land.sum())
    return changed


def _category(t, i):
    """A road sample for crossings: 'tunnel', 'aerial' (a deck, a jump, a pipe) or 'grounded'."""
    k = t.kind(i)
    if k == "tunnel":
        return "tunnel"
    return "aerial" if k in ("bridge", "tube") or t.gap[i] else "grounded"


def crossings(trks, halls=()):
    """Where two stretches cross (their roads overlap in plan, away from the junctions and 40 m or
    more along one road): (road a, sample, road b, sample, clearance, problem or None), one per
    crossing at its closest pass. The upper road must be aerial: at least 8.5 m over a grounded
    one (a pipe below needs 2R + 1.2 m over its own road, a tunnel its height and cover), and its
    skirt + 4 m over another deck or, inside a hall (halls: which of trks are in_hall branches),
    over the hall's road; two grounded roads may only meet level (within 1 m)."""
    out = []
    # a drop merge's last jump comes down onto the road it lands on: no crossing
    landing = []
    for t in trks:
        mask = t.hidden.copy()
        for a, b in t.gaps:
            mask[a:b] |= bool(t.hidden[min(b, t.n - 1)])
        landing.append(mask)
    for r, ta in enumerate(trks):
        for r2 in range(r, len(trks)):
            tb = trks[r2]
            d = np.sqrt(((ta.base[:, None, [0, 2]] - tb.base[None, :, [0, 2]]) ** 2).sum(-1))
            reach = (np.maximum(ta.width, ta.mag * 2)[:, None] + np.maximum(tb.width, tb.mag * 2)[None, :]) / 2
            # (overlapping by a metre: a road beside another just touches it); a branch's shared
            # stretches lie on the lap by design
            hit = (d < reach - 1.0) & ~(tb.junction[None, :] if r == 0 and r2 > 0 else ta.junction[:, None] & tb.junction[None, :])
            hit &= ~landing[r][:, None] & ~landing[r2][None, :]
            if r == r2:
                dk = np.abs(np.arange(ta.n)[:, None] - np.arange(tb.n)[None, :])
                hit &= np.triu((np.minimum(dk, ta.n - dk) if ta.closed else dk) > 20)
            seen = []
            for i, j in sorted(np.argwhere(hit).tolist(), key=lambda q: abs(ta.base[q[0], 1] - tb.base[q[1], 1])):
                if any(abs(i - p) < 30 and abs(j - q) < 30 for p, q in seen):
                    continue
                seen.append((i, j))
                up, lo = ((ta, i), (tb, j)) if ta.base[i, 1] >= tb.base[j, 1] else ((tb, j), (ta, i))
                cu, cl = _category(*up), _category(*lo)
                gap = float(up[0].base[up[1], 1] - lo[0].base[lo[1], 1])
                st_u, st_l = up[0].styles[up[0].style[up[1]]], lo[0].styles[lo[0].style[lo[1]]]
                need = None
                in_hall = up[0] is not trks[0] and up[0] in [t for t, h in zip(trks, halls) if h]
                if cu == "aerial":
                    if cl == "aerial" or (cl == "tunnel" and in_hall):
                        need = st_u.get("skirt_h", 1.6) + 4.0 if lo[0].mag[lo[1]] <= 0.0 else 2 * lo[0].mag[lo[1]] + 1.2
                    elif cl == "tunnel":
                        need = lo[0].height[lo[1]] + st_l.get("cover", 0.0)
                    else:
                        need = 8.5
                elif cl == "tunnel":
                    need = lo[0].height[lo[1]] + st_l.get("cover", 0.0)
                problem = None
                if need is None and gap > 1.0:
                    problem = "%s road %.1f m over a %s one" % (cu, gap, cl)
                elif need is not None and gap < need:
                    problem = "%s road only %.1f m over a %s one (needs %.1f m)" % (cu, gap, cl, need)
                out.append((r, i, r2, j, gap, problem))
    return out


def validate(trk, brs, defn):
    """The branch rules (a layout that breaks one does not build, see STRICT): returns the
    problems, one line each."""
    out = []
    n = trk.n
    for br in brs:
        t = br.trk
        tag = "branch %s:" % br.id
        if not (0.04 < br.i0 / n < br.i1 / n < 0.96):
            out.append("%s fork %.3f and merge %.3f must lie inside 0.04..0.96 of the lap, the merge after the fork"
                       % (tag, br.i0 / n, br.i1 / n))
        for end, z in br.zones.items():
            where = "%s %s" % (tag, end)
            drop = end == "merge" and br.drop
            if z["k_nose"] is None:
                out.append("%s: no nose (the roads never part)" % where)
            else:
                u = t.s[br.nose_k(end)] if end == "fork" else t.length - t.s[br.nose_k(end)]
                if not drop and u > NOSE_MAX:
                    out.append("%s: the nose is %.0f m from the %s (at most %.0f)" % (where, u, end, NOSE_MAX))
                if u < NOSE_MIN:
                    out.append("%s: the nose is only %.0f m from the %s (at least %.0f)" % (where, u, end, NOSE_MIN))
            # where the roads overlap, the branch lies on the main road's surface (Branch._follow)
            lift = 0.02 if br.in_hall else 0.0
            off = [abs(t.pos[k, 1] - lift - br._main_y(i, t.pos[k])) for k, i, gap, _, _ in z["walk"] if gap < 0.0]
            if off and max(off) > 0.05:
                out.append("%s: the branch's road lies %.2f m off the main road's surface where they overlap"
                           % (where, max(off)))
            for k, i, gap, lat, dy in z["walk"][:int(NOSE_MAX / t.step)]:
                mk, bk = trk.kind(i), t.kind(k)
                if br.in_hall:
                    if mk != "tunnel" or trk.wall_gap[i] < t.width[k] + 1.0:
                        out.append("%s: in a hall its floor beside the road (%.1f m) must take the branch and a metre "
                                   "(%.1f m), at s %.0f" % (where, trk.wall_gap[i] if mk == "tunnel" else 0.0,
                                                            t.width[k] + 1.0, trk.s[i]))
                        break
                elif mk not in JUNCTION_KINDS:
                    out.append("%s: the main road is a %s at s %.0f (junctions: %s)" % (where, mk, trk.s[i], ", ".join(JUNCTION_KINDS)))
                    break
                if bk in ("tube", "tunnel") or t.gap[k] or trk.gap[i] or trk.mag[i] > 0.0:
                    out.append("%s: a jump, a pipe or a tunnel inside the shared stretch at u %.0f" % (where, t.s[k]))
                    break
                if not drop and (abs(trk.right[i][1]) > 0.01 or abs(trk.curv[i]) > 1 / 120.0):
                    out.append("%s: the main road banks or bends (radius %.0f m) inside the shared stretch at s %.0f"
                               % (where, 1 / max(abs(trk.curv[i]), 1e-6), trk.s[i]))
                    break
                if lat <= 0.0 and not drop:
                    out.append("%s: the branch's centre crosses the main road's at u %.0f (side %+d)" % (where, t.s[k], z["side"]))
                    break
                if not (br.in_hall or drop) and lat + t.width[k] / 2 < trk.width[i] / 2 - 0.05:
                    out.append("%s: the branch's outer edge runs inside the main road at u %.0f" % (where, t.s[k]))
                    break
        if br.in_hall:
            # all of it inside the hall: beside the road within its walls, under its roof
            i = br.i0
            for k in range(t.n):
                i = trk.nearest(t.pos[k], i, 30)
                lat = abs(float((t.pos[k] - trk.pos[i]) @ trk.flat_right[i]))
                if trk.kind(i) == "tunnel" and (lat + t.width[k] / 2 > trk.width[i] / 2 + trk.wall_gap[i] - 0.5 or
                                                t.pos[k, 1] - trk.pos[i, 1] + 4.5 > trk.height[i]):
                    out.append("%s leaves its hall (through the wall or the roof) at u %.0f" % (tag, t.s[k]))
                    break
        a, b = br.nose_k("fork"), br.nose_k("merge")
        for what in ("items", "boosts", "barrels"):
            for f in br.spec.get(what, []):
                k = int((f if np.isscalar(f) else f[0]) * t.n)
                if not a < k < b or t.gap[max(k - 8, 0):k + 9].any():
                    out.append("%s %s at %.2f must lie between the noses (u %.0f..%.0f), clear of a jump"
                               % (tag, what, f if np.isscalar(f) else f[0], t.s[a], t.s[b]))
        for k in range(t.n):
            tr = _treatment(t.styles[t.style[k]]) or 0.0
            if not t.gap[k] and t.mag[k] <= 0.0 and abs(t.curv[k]) * (t.width[k] / 2 + tr + 2.0) > 1.0:
                out.append("%s too tight at u %.0f: radius %.0f m, needs %.0f" % (tag, t.s[k], 1 / abs(t.curv[k]),
                                                                              t.width[k] / 2 + tr + 2.0))
                break
    for what in ("items", "boosts", "barrels"):
        for f in defn.get(what, []):
            i = int((f if np.isscalar(f) else f[0]) * n) % n
            if any(trk.junction[trk.wrap(i + d)] for d in range(-4, 5)):
                out.append("lap %s at %.3f lies in a branch's shared stretch" % (what, f if np.isscalar(f) else f[0]))
    roads = [trk] + [br.trk for br in brs]
    names = ["lap"] + [br.id for br in brs]
    for r, i, r2, j, gap, problem in crossings(roads, [False] + [br.in_hall for br in brs]):
        if problem:
            out.append("crossing %s s %.0f / %s s %.0f: %s" % (names[r], roads[r].s[i], names[r2], roads[r2].s[j], problem))
    return out


# ---------------------------------------------------------------- geometry
def _uvlen(st, key, default=4.0):
    return float(st.get(key + "_rep", default))


def wall_strip(mesh, mat, bottom, top, v, inner_sign, rep):
    """Vertical wall between two polylines, visible from the road side.
    inner_sign > 0: the wall stands on the right edge (faces left)."""
    hgt = np.linalg.norm(top - bottom, axis=1)
    vv = v / rep
    if inner_sign > 0:
        mesh.strip(mat, bottom, top, 0.0, hgt / rep, vv)
    else:
        mesh.strip(mat, top, bottom, hgt / rep, 0.0, vv)


def face(mesh, mat, pts, nrm, uv, center=False):
    """A flat polygon wound so that it faces nrm: a fan from its first point (convex), or from
    its centroid (center=True, any polygon that is star-shaped about it)."""
    pts = [np.asarray(p, float) for p in pts]
    uv = [list(u) for u in uv]
    if center:
        pts = [np.mean(pts, axis=0)] + pts + [pts[0]]
        uv = [list(np.mean(uv, axis=0))] + uv + [uv[0]]
    tri = []
    for k in range(1, len(pts) - 1):
        a, b = (k, k + 1) if np.dot(np.cross(pts[k] - pts[0], pts[k + 1] - pts[0]), nrm) >= 0 else (k + 1, k)
        tri += [0, a, b]
    mesh.add(mat, pts, [nrm] * len(pts), uv, tri)


def plane_uv(pts, origin, ax_u, rep):
    """UVs of points in a vertical plane: u along ax_u, v down, in metres / rep."""
    return [[np.dot(p - origin, ax_u) / rep, -(p[1] - origin[1]) / rep] for p in pts]


def box_wall(mesh, mat, base_in, base_out, h, v, side, rep):
    """A solid wall with an inner face, a top, an outer face and both end faces."""
    up = UP * h
    wall_strip(mesh, mat, base_in, base_in + up, v, side, rep)
    wall_strip(mesh, mat, base_out, base_out + up, v, -side, rep)
    a, b = (base_in + up, base_out + up) if side > 0 else (base_out + up, base_in + up)
    mesh.strip(mat, a, b, 0.0, 0.25, v / rep)
    if len(base_in) > 1:
        for k, along in ((0, base_in[0] - base_in[1]), (-1, base_in[-1] - base_in[-2])):
            q = [base_in[k], base_out[k], base_out[k] + up, base_in[k] + up]
            face(mesh, mat, q, along / (np.linalg.norm(along) + 1e-9), plane_uv(q, base_in[k], base_out[k] - base_in[k], rep))


def build_geometry(trk, mats, meshes, ctx):
    """A road's geometry, style run by style run; the lap's start line (a branch has none)."""
    S = trk.styles

    # road surface, per style (a tube builds its own, all the way round)
    for name, st in S.items():
        if st["kind"] == "tube":
            continue
        for ids in trk.runs(lambda i, nm=name: trk.style[i] == nm):
            hw = trk.width[ids] / 2
            L = trk.pos[ids] - trk.right[ids] * hw[:, None]
            R = trk.pos[ids] + trk.right[ids] * hw[:, None]
            if st.get("road_u") == "full":
                # one texture across the whole width (painted lanes), stretched along by road_len
                v = _v_full(_unwrap_s(trk, ids), trk.width[ids] * st.get("road_len", 1.0))
                for a, b, La, Ra, ua, ub in _trimmed(trk, ids, L, R, 0.0, 1.0, lambda lat, q: (lat + hw[q]) / (2 * hw[q])):
                    meshes["road"].strip(st["road"], La, Ra, ua, ub, v[a:b], trk.up[ids][a:b], trk.up[ids][a:b])
            else:
                rep = _uvlen(st, "road", 6.0)
                v = _unwrap_s(trk, ids) / rep
                for a, b, La, Ra, ua, ub in _trimmed(trk, ids, L, R, -hw / rep, hw / rep, lambda lat, q: lat / rep):
                    if st.get("uv") == "plan":
                        _plan_strip(meshes["road"], st["road"], La, Ra, rep, trk.up[ids][a:b])
                    else:
                        meshes["road"].strip(st["road"], La, Ra, ua, ub, v[a:b], trk.up[ids][a:b], trk.up[ids][a:b])
            if st.get("lines"):
                _lane_lines(trk, ids, meshes, st)

    for name, st in S.items():
        k = st["kind"]
        runs = trk.runs(lambda i, nm=name: trk.style[i] == nm, with_gaps=(k == "tunnel"))
        for ids in runs:
            if k == "street":
                _street(trk, ids, st, meshes)
            elif k == "open":
                _open(trk, ids, st, meshes)
            elif k == "tunnel":
                _tunnel(trk, ids, st, meshes, ctx)
            elif k == "bridge":
                _bridge(trk, ids, st, meshes, ctx)
            elif k == "trench":
                _trench(trk, ids, st, meshes)
            elif k == "tube":
                _tube(trk, ids, st, meshes, ctx)
    _tunnel_steps(trk, meshes)
    if not trk.closed:
        return
    # start line
    j = 0
    hw = trk.width[j] / 2
    c = trk.pos[j] + trk.up[j] * 0.03
    a0 = c - trk.right[j] * hw - trk.fwd[j] * 1.5
    a1 = c + trk.right[j] * hw - trk.fwd[j] * 1.5
    b0 = c - trk.right[j] * hw + trk.fwd[j] * 1.5
    b1 = c + trk.right[j] * hw + trk.fwd[j] * 1.5
    meshes["decal"].add(ctx.startline, [a0, a1, b1, b0], [trk.up[j]] * 4, [[0, 0], [0, 4], [1, 4], [1, 0]],
                        [0, 1, 2, 0, 2, 3])


def _plan_strip(mesh, mat, a, b, rep, nrm):
    """Mesh.strip between polylines a and b with its texture laid flat on the plan (u, v = x, z in
    `rep` metres): a style's "uv": "plan" for a level square or plaza, whose tiles then never
    stretch on the inside of a tight bend."""
    n = len(a)
    k = np.arange(n - 1)
    p = np.concatenate([a, b])
    mesh.add(mat, p, np.concatenate([nrm, nrm]), p[:, [0, 2]] / rep,
             np.stack([k, k + n, k + 1, k + 1, k + n, k + 1 + n], 1).reshape(-1))


def _trimmed(trk, ids, L, R, ua, ub, u_of):
    """The pieces (a, b, L, R, ua, ub) of a strip between a run's left and right edges that a
    branch draws of itself: where its inner edge is snapped onto the main road's edge (trim_in)
    the strip runs only from there, with u_of(lateral, k) for that vertex's u; where less than
    0.2 m of it shows outside the main road (or it has no road of its own) there is none, and
    each piece starts and ends in a point on the outer edge where it comes out from under the
    main road. A road with nothing trimmed is one piece, as given."""
    inner, hidden = trk.inner[ids], trk.hidden[ids]
    if not inner.any() and not hidden.any():
        return [(0, len(ids), L, R, ua, ub)]
    L, R = L.copy(), R.copy()
    ua = np.array(np.broadcast_to(ua, len(ids)), float)
    ub = np.array(np.broadcast_to(ub, len(ids)), float)
    for q in np.flatnonzero(inner):
        i = ids[q]
        p = trk.trim_in[i]
        u = u_of(float((p - trk.pos[i]) @ trk.right[i]), q)
        if inner[q] < 0:
            L[q], ua[q] = p, u
        else:
            R[q], ub[q] = p, u
    vis = (((R - L) * trk.right[ids]).sum(1) > 0.2) & ~hidden
    out = []
    for a, b in _bool_runs(vis):
        a0 = a - 1 if a > 0 and not hidden[a - 1] else a
        b0 = b + 1 if b < len(ids) and not hidden[b] else b
        for q in {a0, b0 - 1} - set(range(a, b)):
            if inner[q] < 0:
                L[q], ua[q] = R[q], ub[q]
            elif inner[q] > 0:
                R[q], ub[q] = L[q], ua[q]
        if b0 - a0 > 1:
            out.append((a0, b0, L[a0:b0], R[a0:b0], ua[a0:b0], ub[a0:b0]))
    return out


def _unwrap_s(trk, ids):
    s = trk.s[ids].copy()
    for k in range(1, len(s)):
        if s[k] < s[k - 1] - trk.length * 0.5:
            s[k:] += trk.length
    return s


def _v_full(s, wl):
    """V of a texture stretched across the whole road: one repeat per `wl` metres along it, where
    wl changes with the width. Integrated, so the texels stay square where the road narrows or
    widens (s / wl would smear or even run backwards)."""
    return s[0] / wl[0] + np.concatenate([[0.0], np.cumsum(np.diff(s) / (0.5 * (wl[1:] + wl[:-1])))])


def _lane_lines(trk, ids, meshes, st):
    """Painted lane dashes down the middle (a decal strip every other 6 m), none where a branch
    still runs on the main road."""
    mat = st["lines"]
    s = _unwrap_s(trk, ids)
    on = ((np.floor(s / 6.0) % 2) == 0) & (trk.inner[ids] == 0) & ~trk.hidden[ids]
    for a, b in _bool_runs(on):
        if b - a < 2:
            continue
        sub = ids[a:b]
        c = trk.pos[sub] + trk.up[sub] * 0.02
        L = c - trk.right[sub] * 0.12
        R = c + trk.right[sub] * 0.12
        meshes["decal"].strip(mat, L, R, 0.0, 1.0, s[a:b] / 3.0, trk.up[sub], trk.up[sub])


def _bool_runs(mask):
    out, i, n = [], 0, len(mask)
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


def _side_runs(trk, ids, sgn):
    """Where a run keeps its side treatment on side sgn (a junction cuts it): (a, b, cap at a, cap
    at b - 1), capped where the treatment starts or ends at a nose."""
    col = (sgn + 1) // 2
    off = trk.side_off[ids, col]
    if not off.any():
        return [(0, len(ids), False, False)]
    return [(a, b, (int(ids[a]), col) in trk.noses, (int(ids[b - 1]), col) in trk.noses)
            for a, b in _bool_runs(~off) if b - a > 1]


def _nose_cap(mesh, mat, trk, i, top_in, top_out, ends, depth=0.4):
    """The end face of a side treatment at a nose: across its top from the road edge's side
    (top_in: the kerb top, a verge's edge) to its outer edge (top_out), down to `depth` under the
    road edge's height; ends 0 faces back along the road, -1 on along it."""
    low = min(top_in[1], top_out[1]) - depth
    q = [np.array([top_in[0], low, top_in[2]]), np.array([top_out[0], low, top_out[2]]), top_out, top_in]
    face(mesh, mat, q, trk.fwd[i] * (-1.0 if ends == 0 else 1.0), plane_uv(q, q[0], top_out - top_in, 4.0))


def _side_w(trk, ids, sgn, w, extra=0.0):
    """A side strip's width at samples ids on side sgn: `w`, narrower on the inside of a bend too
    tight for it and `extra` metres beyond it (Trk.side_reach)."""
    r = trk.side_reach(sgn, w + extra)[ids]
    return np.where(r >= w + extra, w, np.clip(r - extra, 0.0, w))


def _street(trk, ids, st, meshes):
    """Kerb, pavement and a visible barrier (railing, wall or fence) at the back of the pavement."""
    hw_all = trk.width[ids] / 2
    v_all = _unwrap_s(trk, ids)
    curb_h = st.get("curb_h", 0.16)
    walk = st.get("walk", 4.0)
    for sgn in (-1, 1):
        for a, b, cap0, cap1 in _side_runs(trk, ids, sgn):
            sub, hw, v = ids[a:b], hw_all[a:b], v_all[a:b]
            r = trk.right[sub] * sgn
            rf = trk.flat_right[sub] * sgn
            e0 = trk.pos[sub] + r * hw[:, None]
            e1 = e0 + UP * curb_h
            e2 = e1 + rf * 0.3
            wk = _side_w(trk, sub, sgn, walk, _treatment(st) - walk)
            e3 = e2 + rf * wk[:, None]
            rep = _uvlen(st, "walk", 3.0)
            if sgn > 0:
                meshes["side"].strip(st["curb"], e0, e1, 0.0, 0.06, v / 3.0, -r, -r)
                meshes["road"].strip(st["curb"], e1, e2, 0.06, 0.12, v / 3.0, trk.up[sub], trk.up[sub])
                if st.get("uv") == "plan":
                    _plan_strip(meshes["road"], st["walk_mat"], e2, e3, rep, trk.up[sub])
                else:
                    meshes["road"].strip(st["walk_mat"], e2, e3, 0.0, wk / rep, v / rep, trk.up[sub], trk.up[sub])
            else:
                meshes["side"].strip(st["curb"], e1, e0, 0.06, 0.0, v / 3.0, -r, -r)
                meshes["road"].strip(st["curb"], e2, e1, 0.12, 0.06, v / 3.0, trk.up[sub], trk.up[sub])
                if st.get("uv") == "plan":
                    _plan_strip(meshes["road"], st["walk_mat"], e3, e2, rep, trk.up[sub])
                else:
                    meshes["road"].strip(st["walk_mat"], e3, e2, wk / rep, 0.0, v / rep, trk.up[sub], trk.up[sub])
            bar = st.get("barrier")
            if bar:
                _barrier_runs(trk, sub, meshes, bar, e3, rf, v, sgn)
            for k, cap in ((0, cap0), (-1, cap1)):
                if cap:
                    _nose_cap(meshes["side"], st["curb"], trk, sub[k], e1[k], e3[k], k, 0.4 + curb_h)
            # a street running onto a deck with railings: its barrier turns in across the end of the
            # pavement to the railing, so no kart drives off the pavement beside the deck's start
            nb = trk.styles[trk.style[ids[-1]]]
            if b == len(ids) and bar and nb["kind"] == "bridge" and nb.get("barrier", {}).get("sides", "both") == "both" \
                    and not trk.cut[sub[-1]]:
                fw = trk.fwd[sub[-1]] * np.array([1.0, 0.0, 1.0])
                fw /= np.linalg.norm(fw)
                _barrier(meshes, bar, np.array([e3[-1], e1[-1]]), np.tile(fw, (2, 1)), np.array([0.0, wk[-1] + 0.3]), sgn)
                _nose_cap(meshes["side"], st["curb"], trk, sub[-1], e1[-1], e3[-1], -1, 0.4 + curb_h)


def _barrier(meshes, bar, base, rf, v, sgn):
    """Barrier along a polyline: "wall" (solid, thick), "fence" (thin, both faces) or "jersey".
    "col_h": metres over its foot that it stops karts, where that is more than it stands (an
    unseen wall on its road side up to there: a kart thrown up off a deck, a walk or a ledge
    meets it instead of falling off; the game draws no "colonly" mesh)."""
    kind = bar.get("kind", "wall")
    h = bar.get("h", 1.2)
    mat = bar["mat"]
    rep = bar.get("rep", 3.0)
    top, inset = (1.05, 0.32) if kind == "jersey" else (h, 0.0)
    if bar.get("col_h", 0.0) > top + 0.05:
        line = base + rf * inset
        wall_strip(meshes["colonly"], "colonly", line + UP * top, line + UP * bar["col_h"], v, sgn, rep)
    if kind == "jersey":
        prof = [(0.0, 0.0), (0.0, 0.25), (0.22, 0.55), (0.32, 1.05), (0.62, 1.05), (0.72, 0.55), (0.95, 0.25), (0.95, -1.0)]
        rings = [base + rf * dx + UP * dy for dx, dy in prof]
        # across: metres round the profile, so its flat top gets its share of the texture too
        pu = 0.5 + np.concatenate([[0.0], np.cumsum(np.hypot(*np.diff(np.array(prof), axis=0).T))]) / 2.0
        for k in range(len(rings) - 1):
            A, B = rings[k], rings[k + 1]
            if sgn > 0:
                meshes["walls"].strip(mat, A, B, pu[k], pu[k + 1], v / 4.0)
            else:
                meshes["walls"].strip(mat, B, A, pu[k + 1], pu[k], v / 4.0)
        # both ends closed: the profile itself
        if len(base) > 1:
            for k, along in ((0, base[0] - base[1]), (-1, base[-1] - base[-2])):
                q = [r[k] for r in rings]
                face(meshes["walls"], mat, q, along / (np.linalg.norm(along) + 1e-9), plane_uv(q, q[0], rf[k], 1.0),
                     center=True)
        return
    t = bar.get("thick", 0.4 if kind == "wall" else 0.05)
    b_in = base - UP * 0.3
    b_out = b_in + rf * t
    box_wall(meshes["walls"], mat, b_in, b_out, h + 0.3, v, sgn, rep)


def _barrier_runs(trk, ids, meshes, bar, base, rf, v, sgn):
    """_barrier along the samples ids, broken where a hazard cut it (Trk.cut: a train's level
    crossing); each piece is closed at its ends."""
    cut = trk.cut[ids]
    if not cut.any():
        _barrier(meshes, bar, base, rf, v, sgn)
        return
    for a, b in _bool_runs(~cut):
        if b - a > 1:
            _barrier(meshes, bar, base[a:b], rf[a:b], v[a:b], sgn)


def _open(trk, ids, st, meshes):
    """Drivable verges sloping down to the terrain, so a kart that ran wide climbs back on."""
    hw_all = trk.width[ids] / 2
    v_all = _unwrap_s(trk, ids)
    vw = st.get("verge_w", 4.5)
    drop = st.get("verge_drop", 0.27)
    for sgn in (-1, 1):
        for a, b, cap0, cap1 in _side_runs(trk, ids, sgn):
            sub, hw, v = ids[a:b], hw_all[a:b], v_all[a:b]
            r = trk.right[sub] * sgn
            rf = trk.flat_right[sub] * sgn
            E = trk.pos[sub] + r * hw[:, None]
            dd = drop + np.abs(trk.right[sub][:, 1]) * 1.5
            # (verge and fence draw in together on the inside of a bend too tight for them)
            tw = _treatment(st)
            k_in = _side_w(trk, sub, sgn, tw) / tw
            O = E + rf * (vw * k_in)[:, None] - UP * dd[:, None]
            if sgn > 0:
                meshes["verge"].strip(st["verge"], E, O, 0.0, vw * k_in / 4.0, v / 4.0)
            else:
                meshes["verge"].strip(st["verge"], O, E, vw * k_in / 4.0, 0.0, v / 4.0)
            bar = st.get("barrier")
            if bar and (bar.get("sides", "both") == "both" or (bar["sides"] == "right") == (sgn > 0)):
                _barrier_runs(trk, sub, meshes, bar, E + rf * (bar.get("off", 0.2) * k_in)[:, None], rf, v, sgn)
            for k, cap in ((0, cap0), (-1, cap1)):
                if cap:
                    _nose_cap(meshes["side"], st["verge"], trk, sub[k], E[k], O[k], k)


def _wall_gap(trk, ids, st):
    """How far a tunnel style's walls stand beyond the road edge at samples ids (Trk.wall_gap,
    with its ramps); a sample past the end of the tunnel keeps the style's own."""
    own = st.get("wall_gap", 0.0)
    return np.array([trk.wall_gap[i] if trk.kind(i) == "tunnel" else own for i in np.atleast_1d(ids)])


def _tunnel(trk, ids, st, meshes, ctx):
    """Walls, ceiling and light panels; a hall is a tunnel with a big width and height.
    Optional side pits (liquid behind a railing), a pit under any jump gap, and
    portals (end walls around the opening) where the tunnel meets the outside."""
    hw = trk.width[ids] / 2 + _wall_gap(trk, ids, st)
    H = _run_heights(trk, ids)
    v = _unwrap_s(trk, ids)
    rep = _uvlen(st, "wall", 4.0)
    pit = st.get("pit")
    gapm = trk.gap[ids]
    gp = st.get("gap_pit", {})
    drop = pit["depth"] if pit else 0.0
    if gapm.any():
        drop = max(drop, gp.get("depth", 3.0))
    # beside the road: side pits or a floor out to the walls, both broken off over a jump's pit
    # (it spans the hall wall to wall, so nobody drives round the jump)
    for a0, b0 in _bool_runs(~gapm):
        sub = ids[a0:b0]
        if len(sub) < 2:
            continue
        sv = v[a0:b0]
        shw = hw[a0:b0]
        road_hw = trk.width[sub] / 2
        upv = UP[None].repeat(len(sub), 0)
        for sgn in (-1, 1):
            rf = trk.flat_right[sub] * sgn
            if pit:
                E = trk.pos[sub] + rf * road_hw[:, None]
                low = E - UP * pit["depth"]
                pw = st.get("pit_wall", st["wall"])
                if sgn > 0:
                    meshes["side"].strip(pw, E, low, 0.0, pit["depth"] / 4.0, sv / 4.0, rf, rf)
                else:
                    meshes["side"].strip(pw, low, E, pit["depth"] / 4.0, 0.0, sv / 4.0, rf, rf)
                W = trk.pos[sub] + rf * shw[:, None] - UP * pit["depth"]
                a, b = (low, W) if sgn > 0 else (W, low)
                meshes["glow" if pit.get("glow") else "verge"].strip(pit["mat"], a, b, 0.0, 1.0, sv / 4.0, upv, upv)
                if st.get("barrier"):
                    _barrier_runs(trk, sub, meshes, st["barrier"], E, rf, sv, sgn)
            elif st.get("wall_gap", 0.0) > 0.05:
                # floor between the road edge and the walls (halls are wider than the road)
                fmat = st.get("side_floor", st["road"])
                frep = _uvlen(st, "road", 4.0)
                E = trk.pos[sub] + rf * road_hw[:, None] - UP * 0.01
                W = trk.pos[sub] + rf * (shw + 0.3)[:, None] - UP * 0.01
                a, b = (E, W) if sgn > 0 else (W, E)
                ua, ub = (road_hw / frep, (shw + 0.3) / frep) if sgn > 0 else ((shw + 0.3) / frep, road_hw / frep)
                meshes["road"].strip(fmat, a, b, ua, ub, sv / frep, trk.up[sub], trk.up[sub])
                # the road's edge stands a centimetre over the floor: a riser closes the slot under it
                top = trk.pos[sub] + trk.right[sub] * sgn * road_hw[:, None]
                low = top - UP * 0.03
                a, b = (top, low) if sgn > 0 else (low, top)
                meshes["side"].strip(fmat, a, b, 0.0, 0.03 / frep, sv / frep, rf, rf)
    if gapm.any():
        # the floor of the pit under a jump, wall to wall
        pmat = gp.get("mat", st["wall"])
        for a, b in _bool_runs(gapm):
            sub = slice(max(a - 1, 0), min(b + 1, len(ids)))
            Lp = trk.pos[ids][sub] - trk.flat_right[ids][sub] * hw[sub, None] - UP * gp.get("depth", 3.0)
            Rp = trk.pos[ids][sub] + trk.flat_right[ids][sub] * hw[sub, None] - UP * gp.get("depth", 3.0)
            meshes["glow" if gp.get("glow") else "verge"].strip(pmat, Lp, Rp, 0.0, 1.0, v[sub] / 4.0,
                                                                UP[None].repeat(len(Lp), 0), UP[None].repeat(len(Lp), 0))
            if pit and st.get("barrier"):
                # the railing carries on over the pit, standing on its floor: it still keeps a kart
                # that leaves the kicker crooked out of the side channels
                depth = gp.get("depth", 3.0)
                bar = dict(st["barrier"], h=st["barrier"].get("h", 1.2) + depth)
                if "col_h" in bar:
                    bar["col_h"] += depth
                for sgn in (-1, 1):
                    rf = trk.flat_right[ids][sub] * sgn
                    E = trk.pos[ids][sub] + rf * (trk.width[ids][sub] / 2)[:, None] - UP * depth
                    _barrier_runs(trk, ids[sub], meshes, bar, E, rf, v[sub], sgn)
    for sgn in (-1, 1):
        rf = trk.flat_right[ids] * sgn
        base = trk.pos[ids] + trk.right[ids] * sgn * hw[:, None] - UP * (0.2 + drop)
        top = base + UP * (H[:, None] + 0.2 + drop)
        # optional dado band: a different material on the lower part of the wall
        band = st.get("band_h")
        if band:
            mid = base + UP * band
            wall_strip(meshes["walls"], st["band"], base, mid, v, sgn, _uvlen(st, "band", 2.0))
            wall_strip(meshes["walls"], st["wall"], mid, top, v, sgn, rep)
        else:
            wall_strip(meshes["walls"], st["wall"], base, top, v, sgn, rep)
    Ltop = trk.pos[ids] - trk.flat_right[ids] * hw[:, None] + UP * H[:, None]
    Rtop = trk.pos[ids] + trk.flat_right[ids] * hw[:, None] + UP * H[:, None]
    crep = _uvlen(st, "ceil", 4.0)
    meshes["ceil"].strip(st["ceil"], Rtop, Ltop, hw / crep, -hw / crep, v / crep, -UP[None].repeat(len(ids), 0),
                         -UP[None].repeat(len(ids), 0))
    # light panels in the ceiling (glowing material) and real lights for the karts
    every = st.get("light_every", 12.0)
    lw = st.get("light_w", 1.6)
    ll = st.get("light_l", 4.0)
    rows = st.get("light_rows", [0.0])
    slot = np.floor((v - v[0]) / every)
    for k in range(len(ids)):
        if k > 0 and slot[k] == slot[k - 1]:
            continue
        i = ids[k]
        for row in rows:
            c = trk.pos[i] + trk.flat_right[i] * row * hw[k] + UP * (H[k] - 0.03)
            f = trk.fwd[i] * (ll / 2)
            r = trk.flat_right[i] * (lw / 2)
            quad = [c - f - r, c - f + r, c + f + r, c + f - r]
            meshes["glow"].add(st["light"], quad, [-UP] * 4, [[0, 0], [1, 0], [1, 1], [0, 1]], [0, 2, 1, 0, 3, 2])
        if st.get("lamps", True) and int(slot[k]) % st.get("lamp_every", 2) == 0:
            ctx.light(trk.pos[i] + UP * (H[k] - 1.2), st.get("light_color", [1.0, 0.95, 0.85]),
                      st.get("light_range", max(14.0, hw[k] * 2.2)), st.get("light_energy", 1.4))
    # lid: the ground over the tunnel, facing up (closes the slot the heightfield leaves)
    cover = st.get("cover", 0.0)
    if cover > 0.0:
        lid_w = max(st.get("lid_w", 7.0), ctx.lid_min)
        lid_y = (H + cover - 0.15)[:, None]
        Lc = trk.pos[ids] - trk.flat_right[ids] * (hw + lid_w)[:, None]
        Rc = trk.pos[ids] + trk.flat_right[ids] * (hw + lid_w)[:, None]
        Lc[:, 1:2] = trk.pos[ids][:, 1:2] + lid_y
        Rc[:, 1:2] = trk.pos[ids][:, 1:2] + lid_y
        lrep = _uvlen(st, "lid", 4.0)
        meshes["walls"].strip(st.get("lid_mat", st["ceil"]), Lc, Rc, -(hw + lid_w) / lrep, (hw + lid_w) / lrep,
                              v / lrep, UP[None].repeat(len(ids), 0), UP[None].repeat(len(ids), 0))
    # portals: an end wall above and around the opening, when the next stretch is not a tunnel
    # (those meet in _tunnel_steps); next to a pipe it stands just behind the pipe's bulkhead
    for end, sgn_f in ((ids[0], -1.0), (ids[-1], 1.0)):
        nb = trk.wrap(end + int(sgn_f))
        if trk.kind(nb) == "tunnel":
            continue
        if not st.get("portals", True):
            continue
        k = 0 if sgn_f < 0 else -1
        f = trk.fwd[end] * sgn_f
        c = trk.pos[end] - (f * 0.05 if trk.kind(nb) == "tube" else 0.0)
        rr = trk.flat_right[end]
        pw = st.get("portal_w", max(st.get("lid_w", 7.0), ctx.lid_min) + 8.0)
        ph = st.get("portal_h", max(cover, 2.0) + 0.6)
        h = H[k]
        w2 = hw[k]
        mat = st.get("portal", st["wall"])
        # left block, right block and lintel, as quads facing outward
        quads = [
            [c - rr * (w2 + pw), c - rr * w2, c - rr * w2 + UP * (h + ph), c - rr * (w2 + pw) + UP * (h + ph)],
            [c + rr * w2, c + rr * (w2 + pw), c + rr * (w2 + pw) + UP * (h + ph), c + rr * w2 + UP * (h + ph)],
            [c - rr * w2 + UP * h, c + rr * w2 + UP * h, c + rr * w2 + UP * (h + ph), c - rr * w2 + UP * (h + ph)],
        ]
        for q in quads:
            q = [p - UP * 1.0 if p[1] <= c[1] + 0.01 else p for p in q]
            uv = [[np.dot(p - c, rr) / 4.0, -p[1] / 4.0] for p in q]
            tri = [0, 1, 2, 0, 2, 3] if sgn_f < 0 else [0, 2, 1, 0, 3, 2]
            meshes["walls"].add(mat, q, [f] * 4, uv, tri)


def _section(trk, i, st, h):
    """A tunnel style's cross-section at sample i (roof h above the road) as boxes
    (lat0, lat1, y0, y1) over one side (the other mirrors it): the road, then a floor or a side
    pit out to the wall; over a jump the pit floor from wall to wall."""
    hw = trk.width[i] / 2
    wall = hw + _wall_gap(trk, i, st)[0]
    if trk.gap[i]:
        return [(0.0, wall, -st.get("gap_pit", {}).get("depth", 3.0), h)]
    out = [(0.0, hw, 0.0, h)]
    if wall > hw + 0.01:
        pit = st.get("pit")
        out.append((hw, wall, -pit["depth"] if pit else 0.0, h))
    return out


def _drop(st):
    """How far a tunnel style's walls reach below the road (they hide the edges of its pits)."""
    pit = st.get("pit")
    return 0.2 + max(pit["depth"] if pit else 0.0, st["gap_pit"].get("depth", 3.0) if "gap_pit" in st else 0.0)


def _tunnel_steps(trk, meshes):
    """End faces where a tunnel stretch meets another tunnel style or the open: a step wall where
    the walls jump in or out (a hall meeting a corridor), down to the deeper wall bottom; a header
    where the roof drops; caps on side pits. Whatever one cross-section has that the next one does
    not cover is closed, looking into its own stretch. Pipes close their own mouths (_tube)."""
    n = trk.n
    S = trk.styles
    for j in range(0 if trk.closed else 1, n):
        names = (trk.style[(j - 1) % n], trk.style[j])
        if names[0] == names[1]:
            continue
        rr = trk.flat_right[j]
        nrm = np.cross(UP, rr)
        nrm /= np.linalg.norm(nrm)
        for x, y, sgn in ((0, 1, -1.0), (1, 0, 1.0)):
            stx, sty = S[names[x]], S[names[y]]
            if stx["kind"] != "tunnel" or sty["kind"] == "tube":
                continue
            # the stretch ending at j keeps its own roof height there (see _run_heights)
            hx = trk.height[(j - 1) % n] if x == 0 else trk.height[j]
            hy = trk.height[(j - 1) % n] if y == 0 else trk.height[j]
            bx = _section(trk, j, stx, hx)
            by = _section(trk, j, sty, hy) if sty["kind"] == "tunnel" else None
            low = -max(_drop(stx), _drop(sty) if by else 0.0)
            cuts = sorted({c for b in bx + (by or []) for c in b[:2]})
            boxes = []
            for l0, l1 in zip(cuts[:-1], cuts[1:]):
                m = 0.5 * (l0 + l1)
                bxm = [b for b in bx if b[0] <= m <= b[1]]
                if not bxm:
                    continue
                _, _, x0, x1 = bxm[0]
                if by is None:
                    # into the open: only what lies below the road (side pits) is closed
                    if x0 < -0.01:
                        boxes.append((l0, l1, x0, 0.0, stx.get("pit_wall", stx["wall"])))
                    continue
                bym = [b for b in by if b[0] <= m <= b[1]]
                if not bym:
                    boxes.append((l0, l1, low, x1, stx["wall"]))
                    continue
                _, _, y0, y1 = bym[0]
                if x0 < y0 - 0.01:
                    boxes.append((l0, l1, x0, y0, stx.get("pit_wall", stx["wall"])))
                if x1 > y1 + 0.01:
                    boxes.append((l0, l1, y1, x1, stx["wall"]))
            for l0, l1, y0, y1, mat in boxes:
                # a few cm past every edge into what it meets, so no hairline opens along it
                l0, l1, y0, y1 = (l0 - 0.03 if l0 > 0.0 else 0.0), l1 + 0.03, y0 - 0.03, y1 + 0.03
                for side in (-1.0, 1.0):
                    q = [trk.pos[j] + rr * side * l + UP * yy for l, yy in ((l0, y0), (l1, y0), (l1, y1), (l0, y1))]
                    face(meshes["walls"], mat, q, nrm * sgn, plane_uv(q, trk.pos[j], rr, _uvlen(stx, "wall", 4.0)))
            if by is not None and stx.get("pit") and stx.get("barrier") and not trk.gap[j]:
                # side pits running into a floor beside the road (a hall's): the pits' railing turns
                # across the floor's end, road edge to wall, standing on the floor, so no kart drives
                # off the floor's end into a pit
                hw = trk.width[j] / 2
                span = [(l0, l1) for l0, l1 in zip(cuts[:-1], cuts[1:]) if 0.5 * (l0 + l1) > hw and
                        any(b[0] <= 0.5 * (l0 + l1) <= b[1] and b[2] < -0.01 for b in bx) and
                        any(b[0] <= 0.5 * (l0 + l1) <= b[1] and b[2] > -0.01 for b in by)]
                if span:
                    l0, l1 = min(s[0] for s in span), max(s[1] for s in span)
                    into = -nrm * sgn
                    for side in (-1.0, 1.0):
                        d = rr * side
                        _barrier(meshes, stx["barrier"], np.array([trk.pos[j] + d * l0, trk.pos[j] + d * l1]),
                                 np.tile(into, (2, 1)), np.array([l0, l1]),
                                 1 if into @ np.array([-d[2], 0.0, d[0]]) > 0 else -1)
        if S[names[0]]["kind"] == "tunnel" and S[names[1]]["kind"] == "tunnel":
            # the two roofs (and floors) meet edge to edge on this line: a strip just under the lower
            # roof and just over the floors covers the seam
            low = 0 if trk.height[(j - 1) % n] <= trk.height[j] else 1
            h = min(trk.height[(j - 1) % n], trk.height[j]) - 0.01
            w = trk.width[j] / 2 + trk.wall_gap[j]
            f = nrm * 0.2
            covers = [(h, "ceil", S[names[low]]["ceil"], -UP)]
            if not trk.gap[j] and not any(S[nm].get("pit") for nm in names):
                covers.append((-0.005, "road", S[names[1]].get("side_floor", S[names[1]]["road"]), UP))
            for y, mesh, mat, up in covers:
                q = [trk.pos[j] + rr * w * a + f * b + UP * y for a, b in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
                face(meshes[mesh], mat, q, up, [[p @ rr / 4.0, p @ f / 0.8] for p in q])


def _bridge(trk, ids, st, meshes, ctx):
    """Deck edges dropping a skirt, railings both sides, pillars down to the ground. At a junction
    the lap's deck keeps its skirt (the branch's deck and the gore hang on to it); a branch's
    deck has none on its inner side there and its underside is trimmed like its road."""
    hw = trk.width[ids] / 2
    v = _unwrap_s(trk, ids)
    skirt = st.get("skirt_h", 1.6)
    # a railing on the outside of the bend only leaves the inside open to fall from; "left" or
    # "right" keeps it on that side (a gantry along a wall: its open side faces the floor)
    bar_side = None
    sides = st.get("barrier", {}).get("sides")
    if sides == "outside":
        bar_side = -1 if np.mean(trk.curv[ids]) > 0 else 1
    elif sides in ("left", "right"):
        bar_side = 1 if sides == "right" else -1
    for sgn in (-1, 1):
        r = trk.right[ids] * sgn
        rf = trk.flat_right[ids] * sgn
        E = trk.pos[ids] + r * hw[:, None]
        low = E - UP * skirt
        nrm = rf
        for a, b, _, _ in ([(0, len(ids), False, False)] if trk.closed else _side_runs(trk, ids, sgn)):
            if sgn > 0:
                meshes["side"].strip(st["skirt"], E[a:b], low[a:b], 0.0, skirt / 4.0, v[a:b] / 4.0, nrm[a:b], nrm[a:b])
            else:
                meshes["side"].strip(st["skirt"], low[a:b], E[a:b], skirt / 4.0, 0.0, v[a:b] / 4.0, nrm[a:b], nrm[a:b])
        bar = st.get("barrier")
        for a0, b0, _, _ in _side_runs(trk, ids, sgn):
            if bar and (bar_side is None or bar_side == sgn):
                _barrier_runs(trk, ids[a0:b0], meshes, bar, E[a0:b0], rf[a0:b0], v[a0:b0], sgn)
            elif bar and bar.get("broken"):
                # the other side: a railing with stretches torn out of it ([every, open] metres)
                every, open_ = bar["broken"]
                keep = ((v - v[0]) % every > open_) & ~trk.cut[ids]
                keep[:a0] = False
                keep[b0:] = False
                for a, b in _bool_runs(keep):
                    if b - a > 1:
                        _barrier(meshes, bar, E[a:b], rf[a:b], v[a:b], sgn)
    # underside
    L = trk.pos[ids] - trk.right[ids] * hw[:, None]
    R = trk.pos[ids] + trk.right[ids] * hw[:, None]
    down = -UP[None].repeat(len(ids), 0)
    for a, b, La, Ra, ua, ub in _trimmed(trk, ids, L, R, 1, 0, lambda lat, q: (hw[q] - lat) / (2 * hw[q])):
        meshes["side"].strip(st["skirt"], Ra - UP * skirt, La - UP * skirt, ub, ua, v[a:b] / 4.0, down[a:b], down[a:b])
    every = st.get("pillar_every", 24.0)
    for k in range(0, len(ids), max(1, int(every / trk.step))):
        if k < 2 or k > len(ids) - 3:
            continue
        i = ids[k]
        ctx.pillars.append((trk.pos[i] - UP * skirt, trk.fwd[i], trk.flat_right[i], hw[k], st))


def _run_heights(trk, ids):
    """Roof / wall heights of a run. A run carries one sample of the next stretch
    (so strips join up); that sample keeps this run's height, not the next one's."""
    H = trk.height[ids].copy()
    if len(ids) > 1 and trk.style[ids[-1]] != trk.style[ids[-2]]:
        H[-1] = H[-2]
    return H


def _trench(trk, ids, st, meshes):
    """Retaining walls both sides with a lip on top (a canal or a cutting)."""
    hw = trk.width[ids] / 2
    v = _unwrap_s(trk, ids)
    H = _run_heights(trk, ids)
    rep = _uvlen(st, "wall", 4.0)
    for sgn in (-1, 1):
        r = trk.right[ids] * sgn
        rf = trk.flat_right[ids] * sgn
        base = trk.pos[ids] + r * hw[:, None] - UP * 0.4
        top = base + UP * (H[:, None] + 0.4)
        wall_strip(meshes["walls"], st["wall"], base, top, v, sgn, rep)
        lip = top + rf * st.get("lip", 4.0)
        if sgn > 0:
            meshes["verge"].strip(st.get("lip_mat", st["wall"]), top, lip, 0, 1, v / 4.0, UP[None].repeat(len(ids), 0),
                                  UP[None].repeat(len(ids), 0))
        else:
            meshes["verge"].strip(st.get("lip_mat", st["wall"]), lip, top, 1, 0, v / 4.0, UP[None].repeat(len(ids), 0),
                                  UP[None].repeat(len(ids), 0))


def _grid(mesh, mat, P, N, U, V, twist=None):
    """Quads over a (rows, cols) grid of points: rows run along a pipe, cols round it the way its
    angle grows, which faces the pipe's inside (pass the cols reversed to face out). twist (per
    row, + or -): which way the rows turn, so each quad is split along its shorter diagonal and
    stays close to the curve."""
    r, c = P.shape[:2]
    k = np.arange(r * c).reshape(r, c)
    a, b, cc, d = k[:-1, :-1], k[1:, :-1], k[:-1, 1:], k[1:, 1:]
    tri = np.stack([a, b, cc, cc, b, d], -1)
    if twist is not None:
        alt = np.stack([a, b, d, a, d, cc], -1)
        tri = np.where((np.asarray(twist)[:-1] < 0)[:, None, None], alt, tri)
    mesh.add(mat, P.reshape(-1, 3), N.reshape(-1, 3), np.stack([U.ravel(), V.ravel()], 1), tri.ravel())


def _ray_hit(c, ang, poly):
    """Where a ray from c at angle ang leaves a closed 2D polygon that is star-shaped about c."""
    d = np.array([math.cos(ang), math.sin(ang)])
    best = None
    for p, q in zip(poly, np.roll(poly, -1, axis=0)):
        e = q - p
        den = d[0] * -e[1] + d[1] * e[0]
        if abs(den) < 1e-12:
            continue
        w = p - c
        t = (w[0] * -e[1] + w[1] * e[0]) / den
        u = (d[0] * w[1] - d[1] * w[0]) / den
        if t > 1e-9 and -1e-7 <= u <= 1 + 1e-7 and (best is None or t > best):
            best = t
    return c + d * best


def fill_between(mesh, mat, origin, ax_x, ax_y, inner, outer, c, nrm, rep=4.0):
    """The flat ring between two closed 2D outlines (inner inside outer, both star-shaped about c)
    in the plane origin + ax_x * x + ax_y * y: bulkheads, end rings. Every corner of
    either outline is on a ray of its own, so the face follows both exactly."""
    inner, outer = np.asarray(inner, float), np.asarray(outer, float)
    c = np.asarray(c, float)
    ang = np.unique(np.round([math.atan2(*(p - c)[::-1]) for p in np.vstack([inner, outer])], 9))
    A = np.array([_ray_hit(c, a, inner) for a in ang])
    B = np.array([_ray_hit(c, a, outer) for a in ang])
    # where the outer outline dips inside the inner one (a pipe's flattened floor at a bulkhead's
    # sill) the ring has nothing to close: it is pinched there instead of folding over
    ra, rb = np.linalg.norm(A - c, axis=1), np.linalg.norm(B - c, axis=1)
    B = np.where((rb < ra)[:, None], A, B)
    q = np.vstack([A, B])
    pts = origin + np.outer(q[:, 0], ax_x) + np.outer(q[:, 1], ax_y)
    uv = np.stack([q[:, 0], -q[:, 1]], 1) / rep
    n = len(ang)
    k = np.arange(n)
    k1 = (k + 1) % n
    # the rays turn counter-clockwise in (x, y), so these face ax_x x ax_y
    tri = np.stack([k, k + n, k1, k1, k + n, k1 + n], 1)
    if np.dot(np.cross(ax_x, ax_y), nrm) < 0:
        tri = tri[:, [0, 2, 1, 3, 5, 4]]
    mesh.add(mat, pts, np.tile(nrm, (2 * n, 1)), uv, tri.ravel())


def _tube(trk, ids, st, meshes, ctx):
    """The pipe of a tube stretch (see Trk._tubes): its whole inside is road. The grid twists
    with the lane, so the lane is an exact strip along the helix in the road material (UVs along
    it) and the rest is the pipe's; glowing strips run on the lane's edges and light rings every
    `ring_every` metres. At both mouths the bottom flattens onto the road plane, out to the next
    stretch's walls, so the road runs in without a kerb and no corner opens beside a tunnel, and
    the roll only starts once the pipe is round. Outside: a skin 0.6 m out (flattened with it)
    and an end ring closing the wall at each mouth; a bulkhead round a tunnel's opening. Under
    the pipe the ground drops away ("ground": "dip", the default) or carries it ("rest", see
    carve)."""
    R = float(st.get("radius", 12.0))
    seg_a = 2 * math.pi / int(st.get("segs", 48))
    base, up0, r0 = trk.base[ids], trk.base_up[ids], trk.base_right[ids]
    axis = base + up0 * R
    th = trk.theta[ids]
    m_ = len(ids)
    s = np.arange(m_) * trk.step
    L = m_ * trk.step
    mouth = min(st.get("mouth", 14.0), L * 0.2)
    flat = 1.0 - np.clip(np.minimum(s, L - s) / mouth, 0.0, 1.0)  # 1 at the mouths
    hw = trk.width[ids] / 2
    alpha = hw / R
    # how far round the bottom flattens at each mouth: the lane, or out to the next stretch's walls
    nbs = (trk.wrap(ids[0] - 1), ids[-1])
    a_end = [max(alpha[k], math.asin(min(0.95, (trk.width[ids[k]] / 2 + trk.wall_gap[nb] + 0.3) / R)))
             for k, nb in ((0, nbs[0]), (-1, nbs[1]))]
    a_m = np.where(s < L / 2, a_end[0], a_end[1])
    # angle offsets from the lane's centre: the lane exactly, then round the rest of the pipe
    nl = max(2, int(math.ceil(2 * alpha.max() / seg_a)))
    npp = max(4, int(math.ceil((2 * math.pi - 2 * alpha.min()) / seg_a)))
    tl = np.linspace(-1.0, 1.0, nl + 1)
    off_l = alpha[:, None] * tl[None, :]
    off_p = alpha[:, None] + (2 * math.pi - 2 * alpha)[:, None] * np.linspace(0.0, 1.0, npp + 1)[None, :]
    ring = np.concatenate([off_l, off_p[:, 1:-1]], axis=1)

    def surf(offs, rad):
        phi = th[:, None] + offs
        c, sn = np.cos(phi), np.sin(phi)
        p = axis[:, None, :] - (c[..., None] * up0[:, None, :] + sn[..., None] * r0[:, None, :]) * rad
        # mouths: pull the bottom arc down onto the road plane (the skin follows, 0.6 m below)
        pw = (phi + math.pi) % (2 * math.pi) - math.pi
        k = np.clip(1.0 - (np.abs(pw) - a_m[:, None]) / 0.4, 0.0, 1.0)
        return p - up0[:, None, :] * (rad * (1.0 - c) * k * flat[:, None])[..., None]

    P = surf(ring, R)
    O = surf(ring, R + 0.6)
    # normals from the grid itself (the flattened mouths are not round)
    dk = np.roll(P, -1, axis=1) - np.roll(P, 1, axis=1)
    da = np.gradient(P, axis=0)
    N = np.cross(dk, da)
    N *= np.sign(((axis[:, None, :] - P) * N).sum(-1, keepdims=True))
    N /= np.maximum(np.linalg.norm(N, axis=2, keepdims=True), 1e-9)
    rep = _uvlen(st, "road", 6.0)
    v = _unwrap_s(trk, ids)
    # the lane: across 0..1 (or metres) and along the helix itself
    cl = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(trk.pos[ids], axis=0), axis=1))]) + v[0]
    if st.get("road_u") == "full":
        lu = np.tile((tl + 1.0) / 2.0, (m_, 1))
        lv = _v_full(cl, trk.width[ids] * st.get("road_len", 1.0))
    else:
        lu = off_l * R / rep
        lv = cl / rep
    twist = np.append(np.diff(th), 0.0)
    _grid(meshes["road"], st["road"], P[:, :nl + 1], N[:, :nl + 1], lu, np.tile(lv[:, None], (1, nl + 1)), twist)
    pipe_mat = st.get("wall", st["road"])
    pc = np.concatenate([np.arange(nl, ring.shape[1]), [0]])
    pu = (th[:, None] + off_p) * R / rep
    _grid(meshes["road"], pipe_mat, P[:, pc], N[:, pc], pu, np.tile((v / rep)[:, None], (1, npp + 1)), twist)
    # the outside: the skin, facing away
    oc = np.concatenate([np.arange(ring.shape[1]), [0]])[::-1]
    ou = (th[:, None] + np.concatenate([ring, ring[:, :1] + 2 * math.pi], axis=1)[:, ::-1]) * R / rep
    _grid(meshes["deco"], st.get("skin", pipe_mat), O[:, oc], -N[:, oc], ou, np.tile((v / rep)[:, None], (1, len(oc))),
          -twist)
    # the mouths
    for row, nb, sgn in ((0, nbs[0], 1.0), (m_ - 1, nbs[1], -1.0)):
        ad = trk.axis_dir(ids[row]) * sgn
        org, ex, ey = base[row], r0[row], up0[row]
        to2 = lambda q: np.stack([(q - org) @ ex, (q - org) @ ey], 1)  # noqa: E731
        # the wall's own thickness, between the pipe and the skin
        fill_between(meshes["walls"], pipe_mat, org, ex, ey, to2(P[row]), to2(O[row]), [0.0, R], -ad, 4.0)
        nst = trk.styles[trk.style[nb]]
        if nst["kind"] == "tunnel":
            # a bulkhead closes the pipe round the tunnel's opening (its portal stands behind it)
            w = trk.width[ids[row]] / 2 + trk.wall_gap[nb]
            h = trk.height[nb]
            rect = [[-w, 0.0], [w, 0.0], [w, h], [-w, h]]
            fill_between(meshes["walls"], pipe_mat, org, ex, ey, rect, to2(P[row]), [0.0, h * 0.5], ad, 4.0)
            if (ey - UP) @ ad * h > 0.01:
                # on a slope the bulkhead (square to the pipe) leans into it, away from the tunnel's
                # upright end: its walls and roof run on up to the bulkhead, so no slit opens between
                lo = [org - ex * w, org + ex * w]
                for p, n_ in ((lo[0], ex), (lo[1], -ex)):
                    q = [p, p + UP * h, p + ey * h]
                    face(meshes["walls"], nst["wall"], q, n_, plane_uv(q, p, ad, _uvlen(nst, "wall", 4.0)))
                q = [lo[0] + UP * h, lo[1] + UP * h, lo[1] + ey * h, lo[0] + ey * h]
                face(meshes["ceil"], nst["ceil"], q, -UP, [[(p - org) @ ex / 4.0, (p - org) @ ad / 4.0] for p in q])
    glow = st.get("glow")
    if not glow:
        return
    # lane edges: thin glowing strips just off the surface where the pipe is round, facing in
    round_ = np.where(flat < 1e-6)[0]
    if len(round_) > 1:
        sub = ids[round_[0]:round_[-1] + 1]
        hs = hw[round_[0]:round_[-1] + 1]
        vs = v[round_[0]:round_[-1] + 1]
        for side in (-1.0, 1.0):
            e0 = np.array([trk.surface(i, side * (hs[q] - 0.25), 0.04) for q, i in enumerate(sub)])
            e1 = np.array([trk.surface(i, side * (hs[q] + 0.25), 0.04) for q, i in enumerate(sub)])
            mid = len(sub) // 2
            inward = trk.base[sub[mid]] + trk.base_up[sub[mid]] * R - e0[mid]
            if np.dot(np.cross(e1[mid] - e0[mid], e0[mid + 1] - e0[mid]), inward) < 0:
                e0, e1 = e1, e0
            meshes["glow"].strip(glow, e0, e1, 0.0, 1.0, vs / 4.0, trk.up[sub], trk.up[sub])
    # light rings around the pipe, just inside its wall: where the lane rolls fast the wall's quads,
    # twisted from ring to ring, cut inside the circle by about R (1 - cos(twist / 2)) between them
    phi = np.linspace(-math.pi, math.pi, int(2 * math.pi / seg_a) + 1)
    radial = -(np.cos(phi)[None, :, None] * up0[:, None, :] + np.sin(phi)[None, :, None] * r0[:, None, :])
    every = st.get("ring_every", 18.0)
    for q in range(int(mouth / trk.step) + 1, m_ - 2, max(1, int(every / trk.step))):
        inset = max(0.05, 1.3 * R * (1.0 - math.cos((th[q + 1] - th[q]) / 2)))
        a0 = axis[q] + radial[q] * (R - inset)
        a1 = a0 + (base[q + 1] - base[q]) * 0.35
        nrm = -radial[q]
        meshes["glow"].strip(glow, a0, a1, 0.0, 1.0, phi * R / 2.0 / rep, nrm, nrm)
        if st.get("light_color"):
            ctx.light(axis[q].tolist(), st["light_color"], st.get("light_range", 26.0), st.get("light_energy", 1.4))


def _top_profile(trk, i, st):
    """Points across the whole cross-section's top at sample i, left to right: the road and what
    lies beside it (pavement, verge, a hall's floor or side pits out to its walls)."""
    kind = st["kind"]
    hw = trk.width[i] / 2
    c = trk.pos[i]
    side = []
    for sgn in (-1.0, 1.0):
        r, rf = trk.right[i] * sgn, trk.flat_right[i] * sgn
        e = c + r * hw
        if kind == "street":
            e1 = e + UP * st.get("curb_h", 0.16)
            walk = st.get("walk", 4.0)
            pts = [e, e1, e1 + rf * 0.3, e1 + rf * (0.3 + _side_w(trk, i, int(sgn), walk, _treatment(st) - walk))]
        elif kind == "open":
            tw = _treatment(st)
            vw = st.get("verge_w", 4.5) * _side_w(trk, i, int(sgn), tw) / tw
            pts = [e, e + rf * vw - UP * (st.get("verge_drop", 0.27) + abs(trk.right[i][1]) * 1.5)]
        elif kind == "tunnel":
            wall = c + rf * (hw + _wall_gap(trk, i, st)[0])
            f = -st["pit"]["depth"] if st.get("pit") else 0.0
            pts = [e, e + UP * f, wall + UP * f] if wall @ rf > e @ rf + 0.01 else [e]
        else:
            pts = [e]
        side.append(pts)
    return side[0][::-1] + side[1]


# the deepest a skirt hangs under a verge or a pavement (a style's "skirt_max")
SKIRT_MAX = 15.0


def ground_geometry(trk, meshes, ground, water=None):
    """What needs the finished terrain (ground(x, z) -> height or None): the faces where the road
    ends at a jump, across the whole cross-section and down to the pit floor (halls) or into the
    ground or water under it; skirts under verges and pavements wherever the ground falls away
    from their outer edge; the outer faces and end caps of cutting walls."""
    n = trk.n
    S = trk.styles
    for a, b in trk.gaps:
        for j, sgn in (((a - 1) % n, 1.0), (b % n, -1.0)):
            if trk.hidden[j]:
                # a drop merge's landing: the main road there is the far side, it has no face
                continue
            st = S[trk.style[j]]
            top = np.array(_top_profile(trk, j, st))
            y0 = trk.pos[j][1]
            if st["kind"] == "tunnel":
                bot_y = y0 - st.get("gap_pit", {}).get("depth", 3.0) - 0.2
                mat = st.get("pit_wall", st["wall"])
            elif st["kind"] == "bridge":
                # a deck's end goes down to its underside: nothing of it hangs below the skirt
                bot_y = y0 - min(st.get("skirt_h", 1.6), st.get("gap_face_max", 16.0))
                mat = st.get("skirt", st["road"])
            else:
                g = [ground(p[0], p[2]) for p in np.linspace(top[0], top[-1], 9)]
                low = min([h for h in g if h is not None] + [y0 - st.get("gap_face", 4.0)] +
                          ([water - 0.5] if water is not None else []))
                bot_y = max(low - 0.5, y0 - st.get("gap_face_max", 16.0))
                mat = st.get("skirt", st["road"])
            bot = top.copy()
            bot[:, 1] = bot_y
            u = (top - top[0]) @ trk.flat_right[j] / 4.0
            hv = (top[:, 1] - bot_y) / 4.0
            nrm = np.tile(trk.fwd[j] * sgn, (len(top), 1))
            if sgn > 0:
                meshes["side"].strip(mat, bot, top, hv, 0.0, u, nrm, nrm)
            else:
                meshes["side"].strip(mat, top, bot, 0.0, hv, u, nrm, nrm)
    for name, st in S.items():
        kind = st["kind"]
        if kind not in ("open", "street", "trench"):
            continue
        for ids in trk.runs(lambda i, nm=name: trk.style[i] == nm):
            if len(ids) < 2:
                continue
            v = _unwrap_s(trk, ids)
            hw = trk.width[ids] / 2
            for sgn in (-1, 1):
                rf = trk.flat_right[ids] * sgn
                if kind == "trench":
                    H = _run_heights(trk, ids)
                    edge = trk.pos[ids] + trk.right[ids] * sgn * hw[:, None] + rf * st.get("lip", 4.0)
                    edge[:, 1] = trk.pos[ids][:, 1] + H
                    mat = st["wall"]
                else:
                    edge = np.array([_top_profile(trk, i, st)[-1 if sgn > 0 else 0] for i in ids])
                    mat = st.get("skirt", st.get("verge", st["road"]))
                g = np.array([ground(p[0], p[2]) for p in edge], float)
                if np.isnan(g).all():
                    continue
                g = np.where(np.isnan(g), edge[:, 1], g)
                # a skirt only where the ground lies more than a hand below the edge (and where the
                # verge or pavement is there: a junction cuts it), and no deeper than "skirt_max":
                # where the land under a road is cut away it would hang into the void as one sheet
                drop = np.minimum(np.where(edge[:, 1] - g > 0.3, edge[:, 1] - g + 0.4, 0.0),
                                  st.get("skirt_max", SKIRT_MAX))
                low = edge - UP * drop[:, None]
                for a, b, _, _ in ([(0, len(ids), False, False)] if kind == "trench" else _side_runs(trk, ids, sgn)):
                    if drop[a:b].max() <= 0.0:
                        continue
                    if sgn > 0:
                        meshes["side"].strip(mat, edge[a:b], low[a:b], 0.0, drop[a:b] / 4.0, v[a:b] / 4.0, rf[a:b], rf[a:b])
                    else:
                        meshes["side"].strip(mat, low[a:b], edge[a:b], drop[a:b] / 4.0, 0.0, v[a:b] / 4.0, rf[a:b], rf[a:b])
                if kind == "trench":
                    # the wall's end, from the road's edge out to the lip, down into the ground
                    for k, along in ((0, -trk.fwd[ids[0]]), (-1, trk.fwd[ids[-1]])):
                        inner = trk.pos[ids[k]] + trk.right[ids[k]] * sgn * hw[k]
                        q = [inner - UP * 0.4, low[k], edge[k], inner + UP * (edge[k][1] - inner[1])]
                        face(meshes["walls"], mat, q, along, plane_uv(q, inner, rf[k], 4.0))


def _zipper(A, B):
    """Triangles (index triples into A + B) between two polylines walked side by side, each one
    advancing by its share of its own plan length: the faces between two edges whose vertices do
    not pair up (the main road's samples and a branch's), sharing both edges' own vertices."""
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


def _sheet(mesh, mat, P, tri, uv, nrm):
    """Triangles over points P, each wound to face nrm; slivers left out."""
    idx = []
    for a, b, c in tri:
        cr = np.cross(P[b] - P[a], P[c] - P[a])
        if np.linalg.norm(cr) > 1e-6:
            idx += [a, b, c] if cr @ nrm > 0 else [a, c, b]
    if idx:
        mesh.add(mat, P, np.tile(nrm, (len(P), 1)), uv, idx)


def build_gores(br, meshes, ctx):
    """A branch's junction dressing: the gore between the two roads from where their edges part to
    the nose (road surface in hazard stripes: the main road style's "gore_mat"), closed below at
    the nose (and underneath where the lap is a deck), a crash cushion at each nose (a jersey
    barrier's end; tyres in front of the fork's) and, for a risky branch (risk 0.5 and up), a
    danger sign 30 m before each of its kickers."""
    m, t = br.main, br.trk
    for end, z in br.zones.items():
        if z["gore"] is None or z["k_nose"] is None:
            continue
        fork = end == "fork"
        side, k_nose, i_nose = z["side"], z["k_nose"], z["i_nose"]
        k_sep = z["k_sep"] if z["k_sep"] is not None else k_nose
        k_t = k_sep - 1 if fork else k_sep + 1
        if k_t not in br.trim_seg:
            print("  !! %s %s: no gore (the branch is not on the main road before its edges part)" % (br.id, end))
            continue
        j0, _ = br.trim_seg[k_t]
        p0 = t.trim_in[k_t]
        span = (i_nose - j0) % m.n if fork else (j0 - i_nose) % m.n
        if span > m.n // 2:
            continue
        inner = [t.pos[k] + t.right[k] * (-side * t.width[k] / 2) for k in range(min(k_sep, k_nose), max(k_sep, k_nose) + 1)]
        if fork:
            A = [p0] + [m.edge(m.wrap(j0 + d), side * m.width[m.wrap(j0 + d)] / 2) for d in range(1, span + 1)]
            B = [p0] + inner
        else:
            A = [m.edge(m.wrap(i_nose + d), side * m.width[m.wrap(i_nose + d)] / 2) for d in range(span + 1)] + [p0]
            B = inner + [p0]
        A, B = np.array(A), np.array(B)
        st = m.styles[m.style[i_nose]]
        mat = st.get("gore_mat") or (ctx.mats.goldsrc("stripes1") if st["road"].startswith("goldsrc/")
                                     else ctx.mats.hl2("props/hazardstrip001a"))
        P = np.vstack([A, B])
        ax, ay = m.fwd[i_nose] * np.array([1.0, 0.0, 1.0]), m.flat_right[i_nose]
        uv = np.stack([(P - p0) @ ax / 3.0, (P - p0) @ ay / 3.0], 1)
        tri = _zipper(A, B)
        _sheet(meshes["road"], mat, P, tri, uv, UP)
        # the nose's edge, down below the ground (or the deck's underside), and over a deck the
        # gore's own underside
        a, b = (A[-1], B[-1]) if fork else (A[0], B[0])
        deck = m.kind(i_nose) == "bridge"
        depth = st.get("skirt_h", 1.6) if deck else 0.6
        low = min(a[1], b[1]) - depth
        q = [a, b, np.array([b[0], low, b[2]]), np.array([a[0], low, a[2]])]
        face(meshes["side"], st.get("skirt", st["road"]), q, m.fwd[i_nose] * (1.0 if fork else -1.0),
             plane_uv(q, a, b - a, 4.0))
        if deck:
            _sheet(meshes["side"], st["skirt"], P - UP * depth, tri, uv, -UP)
        # the crash cushion: a jersey barrier's end to the oncoming karts (the island's end at a merge),
        # or what the main road style's "cushion" names ({model, scale, tyres, sink, light, at}); "at":
        # "gore" stands it on the gore's wide end instead (past a deck's nose there is no floor)
        cu = st.get("cushion", {"model": "props_c17/concrete_barrier001a", "tyres": True})
        fb = (m.fwd[i_nose] + t.fwd[k_nose]) * np.array([1.0, 0.0, 1.0])
        fb /= np.linalg.norm(fb)
        mid = (a + b) / 2
        c = mid + fb * ((1.45 if fork else -1.45) * (-1.0 if cu.get("at") == "gore" else 1.0)) - UP * cu.get("sink", 0.4)
        ctx.add(cu["model"], c, ctx.yaw_facing(fb), scale=cu.get("scale", 1.0), ground=False, on_road=True)
        if cu.get("light"):
            ctx.light(c + UP * 2.5, cu["light"], 14.0, 1.2)
        if fork and cu.get("tyres"):
            rb = np.array([-fb[2], 0.0, fb[0]])
            for off in (-0.75, 0.0, 0.75):
                ctx.add("props_vehicles/tire001c_car", mid - fb * 0.6 + rb * off + UP * 0.02, ctx.yaw_facing(rb),
                        physics=True, ground=False, on_road=True)
    if br.spec.get("risk", 0.0) < 0.5:
        return
    for a, b, gap, lift, ramp, drop, v in br.jumps():
        k = max(a - int(ramp / t.step) - int(30.0 / t.step), 0)
        st = t.styles[t.style[k]]
        sgn = br.side0
        # beside an open road past its verge, where a kart that runs wide does not meet the post, which
        # runs a metre into the land there (it lies a little below the road); the branch's
        # "danger_out" puts it that many metres past the road's edge instead (level land beside it
        # that karts cut across)
        open_ = st["kind"] == "open"
        out = -0.3 if st["kind"] == "bridge" else (0.3 + st.get("walk", 4.0) * 0.5 if st["kind"] == "street" else
                                                   st.get("verge_w", 4.5) + 0.6 if open_ else 1.2)
        out = br.spec.get("danger_out", out)
        q = t.pos[k] + t.flat_right[k] * sgn * (t.width[k] / 2 + out)
        ctx.box(ctx.mats.hl2("metal/metalpipe010a"), q + UP * (0.6 if open_ else 1.1), [0.12, 3.2 if open_ else 2.2, 0.12],
                ctx.yaw_facing(t.fwd[k]))
        c = q + UP * 2.5 - t.fwd[k] * 0.08
        r = t.flat_right[k] * 0.6
        quad = [c - r - UP * 0.6, c + r - UP * 0.6, c + r + UP * 0.6, c - r + UP * 0.6]
        # the front and the back 2 cm apart: the cut-out decal is drawn two-sided, and in one plane
        # the back's mirrored text won from the front
        sign = ctx.mats.hl2("decals/decalsigndanger001e")
        face(meshes["deco"], sign, [p - t.fwd[k] * 0.01 for p in quad], -t.fwd[k], [[0, 1], [1, 1], [1, 0], [0, 0]])
        face(meshes["deco"], sign, [p + t.fwd[k] * 0.01 for p in quad], t.fwd[k], [[1, 1], [0, 1], [0, 0], [1, 0]])


# ---------------------------------------------------------------- signage
# what the fork signs and the jump lamps are made of, per world (TRACK "gantry" picks the preset; a
# "signs" dict in TRACK, on the main road's style at the fork or on a branch overrides any of it, its
# "look" naming another preset first): the board (None: the chevrons stand free), the glowing
# chevrons on it, the posts, the light in front of it, the lamp heads beside a jump's lip and their
# light, the stripes across the lip ("lip_glow": glowing ones) and an optional "panel" (a sign's
# material shown over the board, "panel_size" [w, h] metres)
SIGN_LOOKS = {
    "combine": {"board": "metal/citadel_metalwall072a", "chevron": "lights/white001", "post": "metal/metalpipe010a",
                "light": [0.6, 0.8, 1.0], "lamp": "lights/red001", "lamp_light": [1.0, 0.3, 0.15],
                "lip": "props/hazardstrip001a"},
    "blackmesa": {"board": "goldsrc/drkmtlt_wall07", "chevron": "goldsrc/+0~drkmtls2b", "post": "goldsrc/metal_bord03",
                  "light": [1.0, 0.75, 0.35], "lamp": "goldsrc/~spotred", "lamp_light": [1.0, 0.25, 0.1],
                  "lip": "goldsrc/stripes1"},
    "xen": {"board": "goldsrc/xeno_6aw1", "chevron": "goldsrc/crys_3top", "post": "goldsrc/xeno_6aw1",
            "light": [1.0, 0.65, 0.3], "lamp": "goldsrc/crys_3top", "lamp_light": [1.0, 0.65, 0.3],
            "lip": "goldsrc/crys_2top", "lip_glow": True},
    "military": {"board": "goldsrc/metal_wall04", "chevron": "goldsrc/+0~drkmtls2", "post": "goldsrc/metal_bord03",
                 "light": [1.0, 0.7, 0.35], "lamp": "goldsrc/~spotred", "lamp_light": [1.0, 0.25, 0.1],
                 "lip": "goldsrc/stripes1"},
}
# the advance sign stands this far before its fork, the first of these spots that is clear; its
# board's size and the mouth's boards' (width, height in metres) and how many chevrons each shows
SIGN_AT = (70.0, 60.0, 80.0, 50.0, 90.0, 100.0)
SIGN_BOARD, SIGN_MOUTH = (4.0, 1.6, 3), (2.4, 1.2, 2)


def sign_look(defn, *overrides):
    """The look of a sign (SIGN_LOOKS): TRACK "gantry"'s preset, then TRACK's "signs" and each of
    the given "signs" dicts in turn."""
    look = dict(SIGN_LOOKS.get(defn.get("gantry"), SIGN_LOOKS["combine"]))
    for o in (defn.get("signs"),) + overrides:
        if isinstance(o, dict):
            if o.get("look") in SIGN_LOOKS:
                look = dict(SIGN_LOOKS[o["look"]])
            look.update({k: v for k, v in o.items() if k != "look"})
    return look


def _look_mat(mats, name):
    return mats.goldsrc(name[8:]) if name.startswith("goldsrc/") else mats.hl2(name)


def _sign_spot(ctx, t, i, sgn, width, height, facing=None):
    """Where a board `width` x `height` metres stands beside sample i of road t on side sgn, clear of
    its road and run-off: (centre, the way it faces, its axis toward side sgn, its posts as (point,
    foot height), the roof it hangs from or None), or None (a pipe, a jump). It faces `facing` (by
    default back along the road, turned a little toward it). Beyond a street's barrier or an open
    road's verge or fence on two posts (on the verge's outer part where the land beyond drops away),
    over a deck's railing on one post at its edge, on a cutting's lip; in a tunnel or a hall it
    hangs from the roof by the wall, its bottom 3.2 m over the floor (karts pass under it)."""
    st = t.styles[t.style[i]]
    kind = st["kind"]
    if kind == "tube" or t.gap[i] or t.mag[i] > 0.0:
        return None
    hw = t.width[i] / 2
    y = float(t.pos[i][1])
    rf = t.flat_right[i] * sgn
    f = t.fwd[i] * np.array([1.0, 0.0, 1.0])
    f /= np.linalg.norm(f)
    n = -f - rf * 0.25 if facing is None else np.asarray(facing, float) * np.array([1.0, 0.0, 1.0])
    n /= np.linalg.norm(n)
    a = rf - n * (rf @ n)
    a /= np.linalg.norm(a)
    edge = t.pos[i] + t.right[i] * sgn * hw
    bar = st.get("barrier") or {}
    bar_h = (1.05 if bar.get("kind") == "jersey" else bar.get("h", 1.2)) if bar else 0.0
    low = y + max(2.2, bar_h + 0.5)
    if kind == "tunnel":
        c = t.pos[i] + rf * (hw + t.wall_gap[i] - 0.25 - width / 2)
        c[1] = y + min(3.2, t.height[i] - height - 0.8) + height / 2
        return c, n, a, [], y + t.height[i]
    if kind == "bridge":
        # centred over the deck's edge: one post on the railing's line
        foot = edge + rf * (min(bar.get("thick", 0.05), 0.4) * 0.5 if bar else 0.05)
        c = foot + UP * (low - foot[1] + height / 2)
        return c, n, a, [(foot, float(foot[1]))], None
    if kind == "trench":
        lat, low = st.get("lip", 4.0) * 0.5 + width / 2, y + _run_heights(t, np.array([i]))[0] + 2.2
    else:
        lat = (_treatment(st) or 0.0) + (0.3 if kind == "street" else 0.5) + width / 2
    for k in range(2):
        c = t.pos[i] + rf * (hw + lat)
        c[1] = low + height / 2
        posts = []
        for x in ((0.0,) if width < 1.2 else (-(width / 2 - 0.35), width / 2 - 0.35)):
            p = c + a * x
            g = ctx.field.sample(p[0], p[2]) if ctx.field is not None and kind != "trench" and not k else None
            posts.append((p, float(edge[1] - 0.3 * k if kind != "trench" else low - 2.2) if g is None else g))
        if kind != "open" or min(g for _, g in posts) > edge[1] - 6.0 or k:
            return c, n, a, posts, None
        # the land falls away beyond the verge: on the verge's outer part instead (its posts at
        # least 0.65 m off the road, standing on the verge)
        lat = max(st.get("verge_w", 4.5) - 0.2, width + 0.3) - width / 2
    return None


def _clear_spot(ctx, t, i, pts):
    """True when no road comes within 0.3 m of any of the points in plan (less than 4 m under or
    over it; road t's own 12 m either side of sample i do not count) and none of them is in a
    hazard's corridor."""
    r = ctx.roads
    dk = np.abs(r.ridx - i)
    if t.closed:
        dk = np.minimum(dk, t.n - dk)
    skip = (r.route == next(k for k, q in enumerate(r.trks) if q is t)) & (dk <= int(round(12.0 / t.step)))
    for p in pts:
        d = np.hypot(r.pos[:, 0] - p[0], r.pos[:, 2] - p[2]) - np.maximum(r.width / 2, r.mag + 1.0)
        if ((d < 0.3) & ~skip & ~r.gap & ~r.hidden & (np.abs(r.pos[:, 1] - p[1]) < 4.0)).any() or ctx._in_hazard(p):
            return False
    return True


def _chevrons(mesh, mat, c, a, n, width, height, count):
    """`count` glowing chevrons (">", two bars each) side by side on a board centred on c, pointing
    along a, facing n."""
    step = width / count
    cw, hh, th = step * 0.5, height * 0.36, step * 0.22
    for k in range(count):
        b0 = (k - (count - 1) / 2) * step - (cw + th) / 2
        for s in (1.0, -1.0):
            q = [(b0, s * hh), (b0 + th, s * hh), (b0 + cw + th, 0.0), (b0 + cw, 0.0)]
            face(mesh, mat, [c + a * x + UP * y + n * 0.03 for x, y in q], n,
                 [[(x - b0) / (cw + th), 0.5 - y / (2 * hh)] for x, y in q])


def _sign(ctx, look, t, i, sgn, width, height, count, facing=None):
    """A lit chevron board beside sample i of road t on side sgn, pointing that way (_sign_spot;
    an optional "panel" over it), its spot kept clear of props and spectators: False where it
    does not fit."""
    spot = _sign_spot(ctx, t, i, sgn, width, height, facing)
    if spot is None:
        return False
    c, n, a, posts, roof = spot
    bottom = c - UP * (height / 2)
    if not _clear_spot(ctx, t, i, [p for p, _ in posts] + [bottom + a * x for x in (-width / 2, 0.0, width / 2)]):
        return False
    mats = ctx.mats
    yaw = math.atan2(-a[2], a[0])
    board = _look_mat(mats, look["board"]) if look.get("board") else None
    if board:
        ctx.box(board, c - n * 0.06, [width + 0.16, height + 0.16, 0.08], yaw, kind="deco", rep=2.0)
    _chevrons(ctx.meshes["glow"], _look_mat(mats, look["chevron"]), c, a, n, width, height, count)
    top = c[1] + height / 2
    if look.get("panel"):
        # a sign over the board, reading left to right as seen from the road
        pm = _look_mat(mats, look["panel"])
        px = mats.info(pm).get("size")
        pw, ph = look.get("panel_size") or (width, width * px[1] / px[0] if px else width * 0.4)
        pc = c + UP * (height / 2 + 0.12 + ph / 2)
        rv = np.array([n[2], 0.0, -n[0]]) * pw / 2
        q = [pc - rv - UP * ph / 2, pc + rv - UP * ph / 2, pc + rv + UP * ph / 2, pc - rv + UP * ph / 2]
        face(ctx.meshes["deco"], pm, [p + n * 0.02 for p in q], n, [[0, 1], [1, 1], [1, 0], [0, 0]])
        if board:
            ctx.box(board, pc - n * 0.06, [pw + 0.16, ph + 0.16, 0.08], yaw, kind="deco", rep=2.0)
        top = pc[1] + ph / 2
    post = _look_mat(mats, look["post"])
    for p, g in posts:
        # (just behind the board)
        foot, q = min(g, c[1] - height / 2) - 0.3, p - n * 0.16
        ctx.box(post, [q[0], (foot + c[1]) / 2, q[2]], [0.12, c[1] - foot, 0.12], yaw, kind="deco", rep=1.0)
    if roof is not None:
        for x in ((0.0,) if width < 1.2 else (-(width / 2 - 0.35), width / 2 - 0.35)):
            p = c + a * x
            ctx.box(post, [p[0], (top + roof) / 2, p[2]], [0.06, roof - top + 0.1, 0.06], yaw, kind="deco", rep=1.0)
    ctx.light(c + n * 1.5, look["light"], 10.0, 1.2)
    if posts:
        ctx.reserved.append((np.array([p for p, _ in posts] * (2 if len(posts) == 1 else 1)), 1.2))
    return True


def build_signs(trk, brs, ctx, defn):
    """Signs that show where a branch leaves (on its side of the lap; a branch's "signs": False has
    none): a lit chevron board 50-100 m before the fork (SIGN_AT, the first clear spot) and two
    smaller ones beyond the branch's outer edge at its mouth, pointing in; and on every jump of the
    lap stripes across its lip and a lamp each side (none where its control point's flags say
    "lamps": False). Returns (boards, lamps)."""
    boards = lamps = 0
    for br in brs:
        if br.spec.get("signs", True) is False:
            continue
        look = sign_look(defn, trk.styles[trk.style[br.i0]].get("signs"), br.spec.get("signs"))
        for d in SIGN_AT:
            i = trk.wrap(br.i0 - int(round(d / trk.step)))
            if any(trk.junction[q] or trk.gap[q] or trk.mag[q] > 0.0 for q in (trk.wrap(i + k) for k in range(-6, 7))):
                continue
            if _sign(ctx, look, trk, i, br.side0, *SIGN_BOARD):
                boards += 1
                break
        k_nose = br.nose_k("fork")
        for frac in (0.35, 0.7):
            # (a little further on where the branch is still too close to the main road there)
            boards += any(_sign(ctx, look, br.trk, int(round(k_nose * frac)) + dk, br.side0, *SIGN_MOUTH,
                                facing=-trk.fwd[br.i0]) for dk in (0, 2, 4))
    for a, _ in trk.gaps:
        if trk.flags[a].get("lamps", True) is False:
            continue
        j = trk.wrap(a - 1)
        look = sign_look(defn, trk.styles[trk.style[j]].get("signs"))
        ids = np.array([trk.wrap(j - 1), j])
        hw = trk.width[ids] / 2
        lift = trk.up[ids] * 0.03
        L = trk.pos[ids] - trk.right[ids] * hw[:, None] + lift
        R = trk.pos[ids] + trk.right[ids] * hw[:, None] + lift
        ctx.meshes["glow" if look.get("lip_glow") else "decal"].strip(
            _look_mat(ctx.mats, look["lip"]), L, R, -hw / 1.5, hw / 1.5, np.array([0.0, trk.step / 1.5]),
            trk.up[ids], trk.up[ids])
        for sgn in (-1, 1):
            spot = _sign_spot(ctx, trk, j, sgn, 0.6, 0.6, facing=-trk.fwd[j])
            if spot is None:
                continue
            c, n, a_, posts, roof = spot
            if not _clear_spot(ctx, trk, j, [p for p, _ in posts] + [c - UP * 0.3]):
                continue
            yaw = math.atan2(-a_[2], a_[0])
            ctx.box(_look_mat(ctx.mats, look["lamp"]), c, [0.6, 0.6, 0.4], yaw, kind="glow", rep=0.6)
            post = _look_mat(ctx.mats, look["post"])
            for p, g in posts:
                foot = min(g, c[1]) - 0.3
                ctx.box(post, [p[0], (foot + c[1] - 0.2) / 2, p[2]], [0.1, c[1] - 0.2 - foot, 0.1], yaw, kind="deco",
                        rep=1.0)
            if roof is not None:
                ctx.box(post, [c[0], (c[1] + roof) / 2, c[2]], [0.05, roof - c[1], 0.05], yaw, kind="deco", rep=1.0)
            else:
                ctx.reserved.append((np.array([posts[0][0], posts[0][0]]), 1.0))
            ctx.light(c + n * 0.6, look["lamp_light"], 12.0, 1.6)
            lamps += 1
    return boards, lamps


def pillar_meshes(roads, meshes, pillars, ground_h):
    """The bridges' pillars, from under each deck down into the ground; none on another road
    below a deck (the deck spans it there), nor on its verge or pavement (a hall's floor beside
    its road may carry them)."""
    sts = [roads.styles[s] for s in roads.style]
    keep = roads.width / 2 + np.array([(_treatment(st) or 0.0) if st["kind"] in ("open", "street") else 0.0
                                       for st in sts])
    for base, fwd, right, hw, st in pillars:
        g = ground_h(base[0], base[2])
        if g is None:
            g = st.get("pillar_floor")
        if g is None or g > base[1] - 1.0:
            continue
        g = max(g, base[1] - st.get("pillar_max", 60.0))
        mat = st.get("pillar", st["skirt"])
        for off in st.get("pillar_offsets", [-0.6, 0.6]):
            c = base + right * off * hw
            sz = st.get("pillar_size", 1.4)
            d = np.hypot(roads.pos[:, 0] - c[0], roads.pos[:, 2] - c[2])
            if ((d < keep + sz / 2 + 0.25) & (roads.pos[:, 1] < c[1] - 3.0) & ~roads.gap).any():
                continue
            corners = [c + (fwd * a + right * b) * sz / 2 for a, b in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
            for q in range(4):
                p0, p1 = corners[q], corners[(q + 1) % 4]
                bot0 = np.array([p0[0], g - 1.0, p0[2]])
                bot1 = np.array([p1[0], g - 1.0, p1[2]])
                # out of the pillar, the way its faces are wound
                nrm = np.cross(UP, p1 - p0)
                nrm /= np.linalg.norm(nrm) + 1e-9
                hh = p0[1] - bot0[1]
                meshes["walls"].add(mat, [bot0, bot1, p1, p0], [nrm] * 4,
                                    [[0, hh / 4], [sz / 4, hh / 4], [sz / 4, 0], [0, 0]], [0, 2, 1, 0, 3, 2])


# ---------------------------------------------------------------- terrain
class RoadSet:
    """Every road of a circuit as one set of samples, the lap first and then each branch: what the
    terrain (Field, a circuit's terrain builder) and the props' road checks (Ctx) see. The arrays
    are the roads' own, concatenated; route[i] is 0 for the lap and k + 1 for branch k, ridx[i]
    the sample on that road; trks lists the roads (main: the lap)."""

    KEYS = ("pos", "base", "base_up", "base_right", "fwd", "right", "up", "flat_right", "width", "mag", "theta",
            "gap", "pit", "height", "wall_gap", "curv", "s", "junction", "hidden")

    def __init__(self, main, others=()):
        self.trks = [main] + list(others)
        self.main = main
        self.styles = main.styles
        for key in self.KEYS:
            setattr(self, key, np.concatenate([getattr(t, key) for t in self.trks]))
        self.style = [s for t in self.trks for s in t.style]
        self.route = np.concatenate([np.full(t.n, r) for r, t in enumerate(self.trks)])
        self.ridx = np.concatenate([np.arange(t.n) for t in self.trks])
        self.n = len(self.route)

    def kind(self, i):
        return self.styles[self.style[i]]["kind"]

    def axis_dir(self, i):
        return self.trks[self.route[i]].axis_dir(int(self.ridx[i]))


class _View:
    """What a field's cells know of one road sample each (the nearest, or another stretch's)."""


class Field:
    """Heightfield over the circuit's bounds with road lookups: per cell the nearest road sample
    (near, dist and what that road is like there: kind, height, half width, walls, ...) and, in
    `second`, the same for the nearest sample of another stretch (another road, or the same one
    more than 40 m along it), for crossings and roads that pass close by."""

    def __init__(self, roads, margin, cell):
        # tubes twist the road around their pipe: the ground follows the untwisted line
        src = roads.base
        lo = src[:, [0, 2]].min(0) - margin
        hi = src[:, [0, 2]].max(0) + margin
        self.cell = cell
        self.nx = int((hi[0] - lo[0]) / cell) + 1
        self.nz = int((hi[1] - lo[1]) / cell) + 1
        self.xs = lo[0] + np.arange(self.nx) * cell
        self.zs = lo[1] + np.arange(self.nz) * cell
        X, Z = np.meshgrid(self.xs, self.zs)
        self.P = np.stack([X.ravel(), Z.ravel()], 1)
        rp = src[:, [0, 2]]
        route, ridx = roads.route, roads.ridx
        size = np.array([t.n for t in roads.trks])[route]
        loop = np.array([t.closed for t in roads.trks])[route]
        first = np.concatenate([[0], np.cumsum([t.n for t in roads.trks])[:-1]])
        near = np.zeros(len(self.P), np.int64)
        dist = np.zeros(len(self.P))
        near2 = np.zeros(len(self.P), np.int64)
        dist2 = np.zeros(len(self.P))
        for a in range(0, len(self.P), 2048):
            q = self.P[a:a + 2048]
            d2 = ((q[:, None, :] - rp[None, :, :]) ** 2).sum(-1)
            k = np.argmin(d2, axis=1)
            near[a:a + 2048] = k
            dist[a:a + 2048] = np.sqrt(d2[np.arange(len(q)), k])
            # another stretch: a sample of any road nearer than both its neighbours on it (a dip of
            # the distance along that road of its own), away from the nearest sample's dip
            dip = np.zeros(d2.shape, bool)
            for o, t in zip(first, roads.trks):
                blk = d2[:, o:o + t.n]
                lo, hi = np.roll(blk, 1, axis=1), np.roll(blk, -1, axis=1)
                if not t.closed:
                    lo[:, 0] = hi[:, -1] = np.inf
                dip[:, o:o + t.n] = (blk <= lo) & (blk <= hi)
            dk = np.abs(ridx[None, :] - ridx[k][:, None])
            dk = np.where(loop[None, :], np.minimum(dk, size[None, :] - dk), dk)
            d2m = np.where(dip & ~((route[None, :] == route[k][:, None]) & (dk <= 3)), d2, np.inf)
            k2 = np.argmin(d2m, axis=1)
            near2[a:a + 2048] = k2
            dist2[a:a + 2048] = np.sqrt(d2m[np.arange(len(q)), k2])
        self._describe(self, roads, near, dist)
        self.second = _View()
        self._describe(self.second, roads, near2, dist2)
        self.cap = self._road_cap(roads)
        self.H = None
        self.col = None

    def _describe(self, v, roads, near, dist):
        """The road at each cell's sample `near` (dist away) as arrays on v."""
        trk = roads
        src = roads.base
        v.near = near
        v.dist = dist
        v.lat = ((self.P - src[near][:, [0, 2]]) * trk.flat_right[near][:, [0, 2]]).sum(1)
        sts = [trk.styles[s] for s in trk.style]
        v.kind = np.array([st["kind"] for st in sts])[near]
        v.style = np.array(trk.style)[near]
        v.road_h = src[near, 1]
        v.half = np.maximum(trk.width[near] / 2, trk.mag[near] + 1.0)
        v.gap = trk.gap[near]
        v.tunnel_top = src[near, 1] + trk.height[near]
        # the road's tilt across (banking; pipes follow their untwisted line)
        v.bank = trk.base_right[near, 1]
        # walls: a tunnel's, or a pipe's skin
        v.wall = np.where(trk.mag > 0, trk.mag + 0.6, trk.width / 2 + trk.wall_gap)[near]
        cover = np.array([st.get("cover", 0.0) for st in sts])
        v.cover = cover[near]
        v.lip = np.array([st.get("lip", 4.0) if st["kind"] == "trench" else 0.0 for st in sts])[near]
        v.verge = np.array([st.get("verge_w", 4.5) if st["kind"] == "open" else 0.0 for st in sts])[near]
        v.dip = np.concatenate([_dip_weights(t) for t in roads.trks])[near]
        drop = [st.get("drop") for st in sts]
        v.drop_side = np.array([d["side"] if d else 0 for d in drop])[near]
        v.drop_y = np.array([d["y"] if d else 0.0 for d in drop])[near]
        # tunnel 0, grounded 1 (streets, open roads, cuttings, a pipe resting on the ground) or
        # aerial 2 (decks, jumps, floating pipes); decks with "ground": "nat" leave the land under
        # them as it is where that is lower
        aerial = np.array([st["kind"] == "bridge" or (st["kind"] == "tube" and st.get("ground", "dip") != "rest")
                           for st in sts]) | trk.gap
        v.cat = np.where(np.array([st["kind"] == "tunnel" for st in sts]), 0, np.where(aerial, 2, 1))[near]
        v.nat = np.array([st.get("ground") == "nat" for st in sts])[near]

    def _road_cap(self, roads):
        """The highest the ground may reach under every road and its verges: just under the
        surface. The nearest sample alone misses a second road close by (a hairpin's other leg)."""
        cap = np.full(len(self.P), np.inf)
        for trk in roads.trks:
            sts = [trk.styles[s] for s in trk.style]
            for i in range(trk.n):
                if trk.gap[i] or trk.hidden[i]:
                    continue
                hw = max(trk.width[i] / 2, trk.mag[i] + 1.0)
                reach = hw + (sts[i].get("verge_w", 4.5) if sts[i]["kind"] == "open" else 0.0) + 0.5
                c = trk.base[i, [0, 2]]
                i0, i1 = np.searchsorted(self.xs, [c[0] - reach - trk.step, c[0] + reach + trk.step])
                j0, j1 = np.searchsorted(self.zs, [c[1] - reach - trk.step, c[1] + reach + trk.step])
                sub = (np.arange(j0, j1)[:, None] * self.nx + np.arange(i0, i1)[None, :]).ravel()
                d = self.P[sub] - c
                f = trk.fwd[i, [0, 2]] if trk.mag[i] <= 0.0 else trk.axis_dir(i)[[0, 2]]
                f = f / np.linalg.norm(f)
                lat = d @ trk.flat_right[i, [0, 2]]
                m = (np.abs(lat) <= reach) & (np.abs(d @ f) <= trk.step)
                ry = trk.base_right[i, 1]
                h = trk.base[i, 1] + ry * np.clip(lat[m], -hw, hw) - 0.35 - abs(ry) * 1.5
                cap[sub[m]] = np.minimum(cap[sub[m]], h)
        return cap

    def dist_to(self, trk, mask):
        """Distance from every cell to the nearest road sample where mask is true."""
        rp = trk.base[np.asarray(mask, bool)][:, [0, 2]]
        out = np.full(len(self.P), 1e9)
        if len(rp) == 0:
            return out
        for a in range(0, len(self.P), 4096):
            q = self.P[a:a + 4096]
            d2 = ((q[:, None, :] - rp[None, :, :]) ** 2).sum(-1)
            out[a:a + 4096] = np.sqrt(d2.min(1))
        return out

    def sample(self, x, z):
        if self.H is None:
            return None
        i = np.clip((x - self.xs[0]) / self.cell, 0, self.nx - 1.001)
        j = np.clip((z - self.zs[0]) / self.cell, 0, self.nz - 1.001)
        i0, j0 = int(i), int(j)
        fx, fz = i - i0, j - j0
        H = self.H
        return float(H[j0, i0] * (1 - fx) * (1 - fz) + H[j0, i0 + 1] * fx * (1 - fz) +
                     H[j0 + 1, i0] * (1 - fx) * fz + H[j0 + 1, i0 + 1] * fx * fz)


def _dip_weights(trk):
    """Per sample, how far the ground drops away under it (0..1): fully over a jump (unless its
    style has "gap_dip": False: a jump between roofs over a street leaves the ground under it as it
    is); under a bridge or a pipe left to "dip" (the default "ground") it fades in over the
    stretch's first and last "dip_fade" metres, so its ends rest on the land instead of hanging
    over a pit. A deck with "ground": "keep" (an overpass, a roof) or "nat" digs nothing."""
    w = (trk.gap & np.array([bool(trk.styles[s].get("gap_dip", True)) for s in trk.style])).astype(float)
    for name, st in trk.styles.items():
        if st["kind"] not in ("bridge", "tube") or st.get("ground", "dip") != "dip":
            continue
        for ids in trk.runs(lambda i, nm=name: trk.style[i] == nm, with_gaps=True):
            ids = ids[:-1] if trk.style[ids[-1]] != name else ids
            k = np.arange(len(ids))
            d = np.minimum(k, len(ids) - 1 - k) * trk.step
            w[ids] = np.maximum(w[ids], smoothstep(2.0, st.get("dip_fade", 16.0), d))
    return w


def carve(field, nat, trk, flat=6.0, blend=28.0, gap_floor=None):
    """Natural heights -> heights that meet the road: flat shoulders beside it (following its
    bank, just under its verges), the natural land further out, a berm behind cutting walls,
    cover over tunnels, a dip under jumps, bridges and floating pipes, and a fall
    beside a stretch with a "drop" side ({"side": -1 left / 1 right, "y": floor height}).
    Next to a wall (or a pipe's skin) the ground stays at road level for a whole cell beyond it,
    so no terrain triangle that spans the wall line can rise through it onto the road; a tunnel's
    lid covers that slot (see _tunnel). Where another stretch reaches the cell too (a crossing, a
    branch beside the road, a hairpin's other leg) the two are resolved (_second_road)."""
    f = field
    h, _ = _carve_one(f, f, nat, flat, blend, gap_floor)
    if RULES["second_road"]:
        h = _second_road(f, h, nat, flat, blend, gap_floor)
    # whatever the nearest sample said, never above a road that runs over the cell
    return np.minimum(h, f.cap)


def _carve_one(f, r, nat, flat, blend, gap_floor):
    """carve() for one road per cell (r: the field's nearest, or its second): the heights and the
    ground just under that road ("under", a tunnel's floor)."""
    surf = r.road_h + r.bank * np.clip(r.lat, -r.half, r.half)
    under = surf - 0.35 - np.abs(r.bank) * 1.5
    t = smoothstep(r.half + flat, r.half + flat + blend, r.dist)
    h = under * (1 - t) + nat * t
    clear = r.wall + f.cell + 0.5
    # walled cuttings: behind the walls a berm at the wall top carries the lip, then the land
    top = r.tunnel_top - 0.1
    tb = smoothstep(r.half + r.lip + 1.0, r.half + r.lip + 16.0, r.dist)
    berm = top - (top - np.minimum(nat, top)) * tb
    h = np.where((r.kind == "trench") & (r.dist > clear), np.maximum(h, berm), h)
    # a tunnel runs inside a hill. A heightfield can not overhang, so the ground stays at road
    # level inside the walls and rises only outside them (the tunnel's lid covers the slot)
    tun = r.kind == "tunnel"
    roof = r.tunnel_top + r.cover
    tc = smoothstep(clear, clear + 26.0, r.dist)
    inside = r.dist < clear
    h = np.where(tun & ~inside, np.maximum(h, roof * (1 - tc) + nat * tc), h)
    h = np.where(tun & inside, under, h)
    if gap_floor is not None:
        dip = smoothstep(r.half + 20.0, r.half * 0.3, r.dist) * r.dip
        h = h * (1 - dip) + np.minimum(nat, gap_floor) * dip
    else:
        near = r.dist < r.half + 8.0
        h = np.where(near, h * (1 - r.dip) + np.minimum(h, r.road_h - 8.0) * r.dip, h)
    h = np.where(r.nat, np.minimum(h, nat), h)
    edge = r.half + r.verge + 0.5
    out = (r.drop_side != 0) & (r.lat * r.drop_side > edge)
    td = smoothstep(edge + 30.0, edge + 90.0, r.dist)
    h = np.where(out, np.minimum(h, r.drop_y * (1 - td) + nat * td), h)
    return h, under


def _second_road(f, h1, nat, flat, blend, gap_floor):
    """Cells that another stretch's carve reaches too: inside a tunnel's walls the ground is that
    tunnel's floor (either road's) and a grounded road's bed (half + 1.5 m) is its own. Beyond
    those, where the nearest road is aerial (a deck, a jump, a floating pipe), a grounded road's
    carve beats it (a deck's dip or embankment must neither dig a trench beside the road it
    crosses nor bury it; under the deck the cap keeps the ground down) and of two aerial roads the
    lower carve wins, each as far as the other road's own carve reaches (fading out over its
    blend, so nothing steps at its edge); elsewhere the nearest road's carve stands. Prints how
    many cells changed."""
    s = f.second
    reach = s.dist < s.half + flat + blend
    if not reach.any():
        return h1
    h2, under2 = _carve_one(f, s, nat, flat, blend, gap_floor)
    slot1 = (f.cat == 0) & (f.dist < f.wall + f.cell + 0.5)
    slot2 = (s.cat == 0) & (s.dist < s.wall + f.cell + 0.5)
    bed1 = (f.cat == 1) & (f.dist < f.half + 1.5)
    bed2 = (s.cat == 1) & (s.dist < s.half + 1.5)
    target = np.where(s.cat == 1, h2, np.minimum(h1, h2))
    w2 = 1.0 - smoothstep(s.half + flat, s.half + flat + blend, s.dist)
    mix = np.where((f.cat == 2) & (s.cat > 0), h1 + (target - h1) * w2, h1)
    h = np.where(slot1 | bed1, h1, np.where(slot2, under2, np.where(bed2, h2, mix)))
    h = np.where(reach, h, h1)
    moved = np.abs(h - h1) > 1e-6
    if moved.any():
        print("  second road: %d terrain cells changed, by up to %.1f m" % (moved.sum(), np.abs(h - h1).max()))
    return h


def lid_caps(roads, field, lid_min):
    """The highest the ground may reach under every tunnel's lid (see _tunnel): 0.2 m under it,
    so no terrain pokes through the lid where the land beside the tunnel rises to its roof."""
    cap = np.full(len(field.P), np.inf)
    for trk in roads.trks:
        for name, st in trk.styles.items():
            if st["kind"] != "tunnel" or st.get("cover", 0.0) <= 0.0:
                continue
            lid_w = max(st.get("lid_w", 7.0), lid_min)
            for ids in trk.runs(lambda i, nm=name: trk.style[i] == nm, with_gaps=True):
                reach = trk.width[ids] / 2 + _wall_gap(trk, ids, st) + lid_w
                top = trk.pos[ids, 1] + _run_heights(trk, ids) + st["cover"] - 0.15 - 0.2
                for q, i in enumerate(ids):
                    c = trk.pos[i, [0, 2]]
                    r = reach[q] + trk.step
                    i0, i1 = np.searchsorted(field.xs, [c[0] - r, c[0] + r])
                    j0, j1 = np.searchsorted(field.zs, [c[1] - r, c[1] + r])
                    sub = (np.arange(j0, j1)[:, None] * field.nx + np.arange(i0, i1)[None, :]).ravel()
                    d = field.P[sub] - c
                    f = trk.fwd[i, [0, 2]] / np.linalg.norm(trk.fwd[i, [0, 2]])
                    along = d @ f
                    # (over the lid only: not beyond its ends)
                    m = (np.abs(d @ trk.flat_right[i, [0, 2]]) <= reach[q]) & \
                        (along >= (0.0 if q == 0 else -0.75) * trk.step) & \
                        (along <= (0.0 if q == len(ids) - 1 else 0.75) * trk.step)
                    cap[sub[m]] = np.minimum(cap[sub[m]], top[q])
    return cap


def terrain_mesh(mesh, field, H, col, void_y=None):
    nz, nx = H.shape
    X, Z = np.meshgrid(field.xs, field.zs)
    p = np.stack([X.ravel(), H.ravel(), Z.ravel()], 1)
    gz, gx = np.gradient(H, field.cell)
    nrm = np.stack([-gx.ravel(), np.ones(nx * nz), -gz.ravel()], 1)
    nrm /= np.linalg.norm(nrm, axis=1, keepdims=True)
    uv = np.stack([X.ravel(), Z.ravel()], 1) / 4.0
    i = np.arange(nx * nz).reshape(nz, nx)
    a = i[:-1, :-1].ravel()
    b = i[:-1, 1:].ravel()
    c = i[1:, :-1].ravel()
    d = i[1:, 1:].ravel()
    tri = np.stack([a, c, b, b, c, d], 1).reshape(-1, 3)
    # on a knife-edge ridge the slope across a cell says little about its faces: there the faces'
    # own normals (area weighted), so no face is lit as if it looked the other way
    fn = np.cross(p[tri[:, 1]] - p[tri[:, 0]], p[tri[:, 2]] - p[tri[:, 0]])
    acc = np.zeros_like(p)
    for k in range(3):
        np.add.at(acc, tri[:, k], fn)
    acc /= np.maximum(np.linalg.norm(acc, axis=1, keepdims=True), 1e-9)
    nrm = np.where(((acc * nrm).sum(1) < 0.5)[:, None], acc, nrm)
    if void_y is not None:
        # nothing at all where the ground sank into the void: the sky shows below floating land.
        # The faces are cut along their own contour at void_y, so a cliff's foot runs smoothly
        # instead of in the grid's saw-teeth
        p, nrm, uv, col, tri = _cut_below(p, nrm, uv, col, tri, void_y)
    mesh.add("terrain", p, nrm, uv, tri.reshape(-1), col)


def _cut_below(p, nrm, uv, col, tri, y):
    """Triangles cut at height y, keeping what is above: one new vertex (attributes interpolated)
    on each edge that crosses y, shared by the faces on both sides of it."""
    up = p[tri, 1] > y
    k = up.sum(1)
    whole = tri[k == 3]
    cut = (k == 1) | (k == 2)
    part, pu, k = tri[cut], up[cut], k[cut]
    # each cut face turned so its odd corner (the one above, or the one below) comes first; a
    # rotation keeps the winding
    first = np.argmax(np.where(k[:, None] == 1, pu, ~pu), 1)
    o, q, r = np.take_along_axis(part, (first[:, None] + np.arange(3)) % 3, 1).T
    edges = np.sort(np.concatenate([np.stack([o, q], 1), np.stack([o, r], 1)]), 1)
    uniq, inv = np.unique(edges, axis=0, return_inverse=True)
    lo, hi = uniq.T
    t = ((y - p[lo, 1]) / (p[hi, 1] - p[lo, 1]))[:, None]
    if col is None:
        col = np.ones((len(p), 4), np.float32)
    n_ = nrm[lo] + (nrm[hi] - nrm[lo]) * t
    vq = len(p) + inv.reshape(-1)
    eq, er = vq[:len(o)], vq[len(o):]
    p = np.concatenate([p, p[lo] + (p[hi] - p[lo]) * t])
    nrm = np.concatenate([nrm, n_ / np.linalg.norm(n_, axis=1, keepdims=True)])
    uv = np.concatenate([uv, uv[lo] + (uv[hi] - uv[lo]) * t])
    col = np.concatenate([col, col[lo] + (col[hi] - col[lo]) * t])
    one = k == 1
    tri = np.concatenate([whole, np.stack([o, eq, er], 1)[one], np.stack([eq, q, r], 1)[~one],
                          np.stack([eq, r, er], 1)[~one]])
    return p, nrm, uv, col, tri


# ---------------------------------------------------------------- decoration context
# models that stand on a thin pole with an arm or a head overhead: they take up only the pole
POLES = ("lamppost", "utilitypole", "light_signal", "signpole", "traffic_light", "hl1/light")


def _front_z(model):
    """Buildings, HL1 models and characters face their local +Z; other HL2 props face +X."""
    return not model.startswith("props_") or model.startswith("props_buildings/")


def _boxes_overlap(a, b):
    """Two yawed boxes (see Ctx._box) intersect: their heights overlap and no axis of either
    ground rectangle separates them."""
    if a[4] >= b[5] - 0.05 or b[4] >= a[5] - 0.05:
        return False
    d = b[0] - a[0]
    for ax in (a[2], a[3], b[2], b[3]):
        ra = a[1][0] * abs(ax @ a[2]) + a[1][1] * abs(ax @ a[3])
        rb = b[1][0] * abs(ax @ b[2]) + b[1][1] * abs(ax @ b[3])
        if abs(d @ ax) > ra + rb:
            return False
    return True


def _in_poly(pts, poly):
    """Which plan points (M, 2) lie inside a plan polygon (N, 2), by counting edge crossings."""
    x, z = pts[:, 0:1], pts[:, 1:2]
    a, b = poly, np.roll(poly, -1, axis=0)
    dz = np.where(b[:, 1] == a[:, 1], 1e-12, b[:, 1] - a[:, 1])
    cross = ((a[:, 1] > z) != (b[:, 1] > z)) & (x < a[:, 0] + (z - a[:, 1]) * (b[:, 0] - a[:, 0]) / dz)
    return cross.sum(1) % 2 == 1


class Ctx(crowds.CrowdMixin):
    """What the circuit's decorate() works with: trk is the road it dresses (the lap; a branch's in
    a for_route() copy), roads every road (RoadSet), and the props, lights and meshes it adds. The
    spectators' placement API (stands, people, eggs) comes from crowds.CrowdMixin."""

    def __init__(self, trk, models, rng, roads=None):
        self.trk = trk
        self.roads = roads if roads is not None else RoadSet(trk)
        self.models = models
        self.rng = rng
        self.props = []
        self.lights = []
        self.pillars = []
        self.field = None
        self.startline = "concrete/concretefloor033y"
        self.missing = set()
        # what stands here already, as yawed boxes (see _box): props refuse to pass through them
        self.boxes = []
        # lids over tunnels reach this far past the walls (the terrain's slot)
        self.lid_min = 0.0
        # props kept off the branches' roads and junctions (models refused there, for the report),
        # and the junctions' outlines (plan polygon, lowest and highest road height); see keep_off
        self.dropped = []
        self.junctions = []
        self._guard = None
        # the hazards' corridors kept clear of props ((polyline (k, 3), half width) each, hazards.reserve),
        # the circuit's id (the hazards' seeds) and the models refused there or on a stand's plot
        self.reserved = []
        self.track_id = ""
        self.cleared = []

    def for_route(self, trk):
        """The same context dressing another road (a branch: its decorate_branch hook): props,
        lights, meshes and the overlap registry are shared."""
        c = copy.copy(self)
        c.trk = trk
        return c

    def add(self, model, pos, yaw=0.0, physics=False, scale=1.0, tag=None, ground=True, pitch=0.0, base=True,
            solid=True, on_road=False):
        """Place a model. base: pos is where its bottom stands (most HL2 props are centred on their
        origin), so it is lifted by its own depth below the origin. A static prop is refused (False)
        when its origin is on the road, or, when solid, when it would pass through something placed
        before it; it then blocks later ones. Any prop but those meant for the road (on_road: barrels,
        cones, a junction's cushion) is refused where it would stand on a branch's road or in a
        junction (keep_off). Any prop but the far ones and the hazards' own (tag "hazard") is
        refused in a hazard's corridor or on a stand's plot (_reserved_hit)."""
        if model not in self.models:
            self.missing.add(model)
            return False
        if tag not in ("far", "hazard") and self._reserved_hit(model, pos, yaw, scale):
            self.cleared.append(model)
            return False
        m = self.models[model]
        p = np.array(pos, float)
        if base:
            p[1] -= m["aabb_min"][1] * scale
        if not on_road and tag != "far" and RULES["road_guard"] and self.keep_off(model, p, yaw, scale):
            self.dropped.append(model)
            return False
        if not physics and tag != "far":
            if self.road_gap3(p) < 0.3 or self.through_wall(model, p, yaw, scale):
                return False
            if solid:
                box = self._box(model, p, yaw, scale)
                if any(_boxes_overlap(box, b) for b in self.boxes):
                    return False
                self.boxes.append(box)
        self.props.append({"model": model, "pos": [float(c) for c in p], "yaw": float(yaw), "physics": physics,
                           "scale": float(scale), "tag": tag, "ground": ground, "pitch": float(pitch)})
        return True

    def _box(self, model, p, yaw, scale):
        """A placed model as a box turned by yaw: centre, half sizes and axes on the ground, and its
        height range. Poles with arms (lamps, signals) count by their pole only."""
        m = self.models[model]
        lo, hi = np.array(m["aabb_min"]) * scale, np.array(m["aabb_max"]) * scale
        if any(k in model for k in POLES):
            lo[[0, 2]], hi[[0, 2]] = -0.3, 0.3
        c, s_ = math.cos(yaw), math.sin(yaw)
        ax, az = np.array([c, -s_]), np.array([s_, c])
        mid = (lo + hi) / 2
        cen = np.array([p[0], p[2]]) + ax * mid[0] + az * mid[2]
        return cen, np.maximum((hi - lo)[[0, 2]] / 2 - 0.1, 0.05), ax, az, p[1] + lo[1], p[1] + hi[1]

    @staticmethod
    def _plain_box(center, size, yaw):
        c, s_ = math.cos(yaw), math.sin(yaw)
        return (np.array([center[0], center[2]], float), np.array([size[0], size[2]], float) / 2,
                np.array([c, -s_]), np.array([s_, c]), center[1] - size[1] / 2, center[1] + size[1] / 2)

    def block(self, center, size, yaw=0.0):
        """Mark a box (centre, full size, yaw) as taken, for geometry that props must not pass."""
        self.boxes.append(self._plain_box(center, size, yaw))

    def free(self, center, size, yaw=0.0):
        """True when a box (centre, full size, yaw) passes through nothing placed so far."""
        box = self._plain_box(center, size, yaw)
        return not any(_boxes_overlap(box, b) for b in self.boxes)

    def keep_off(self, model, q, yaw, scale=1.0):
        """True when a model at q would stand on a branch's road (its outline or origin within half
        the road's width + 0.5 m in plan, with its height range reaching from a metre under the road
        to 2.5 m over it) or in a junction (where the lap's side treatment is cut for a fork or a
        merge, the gore and the branch beside it): the lap's props stay off the other roads."""
        if self._guard is None:
            r = self.roads
            ids = np.flatnonzero((r.route > 0) & ~r.gap & ~r.hidden)
            self._guard = (r.pos[ids], r.width[ids] / 2 + 0.5)
        pos, half = self._guard
        if not len(pos) and not self.junctions:
            return False
        m = self.models[model]
        y0, y1 = q[1] + m["aabb_min"][1] * scale, q[1] + m["aabb_max"][1] * scale
        pts = np.array([(q[0], q[2])] + self.footprint(model, q, yaw, 2.0, scale))
        if len(pos):
            d2 = ((pts[:, None, :] - pos[None, :, [0, 2]]) ** 2).sum(-1)
            hit = (d2 < half[None, :] ** 2) & (y1 > pos[None, :, 1] - 1.0) & (y0 < pos[None, :, 1] + 2.5)
            if hit.any():
                return True
        for poly, lo, hi in self.junctions:
            if y1 > lo - 1.0 and y0 < hi + 2.5 and _in_poly(pts, poly).any():
                return True
        return False

    def through_wall(self, model, q, yaw, scale=1.0):
        """True when a model standing inside a tunnel reaches through one of its walls."""
        t = self.roads
        i = int(np.argmin(np.linalg.norm(t.pos - q, axis=1)))
        lat = (q - t.pos[i]) @ t.flat_right[i]
        if t.kind(i) != "tunnel" or abs(lat) > t.width[i] / 2 + t.wall_gap[i] or \
                not t.pos[i][1] - 2.0 <= q[1] <= t.pos[i][1] + t.height[i]:
            return False
        for x, z in self.footprint(model, q, yaw, 2.0, scale):
            j = int(np.argmin(((t.pos[:, [0, 2]] - (x, z)) ** 2).sum(1)))
            lat = (x - t.pos[j][0]) * t.flat_right[j][0] + (z - t.pos[j][2]) * t.flat_right[j][2]
            if t.kind(j) == "tunnel" and abs(lat) > t.width[j] / 2 + t.wall_gap[j] - 0.02:
                return True
        return False

    def road_gap3(self, q):
        """Metres from q to the nearest road surface edge of any road, in 3D (a pipe's lane overhead
        or the road far below a bridge does not count as near)."""
        d = np.linalg.norm(self.roads.pos - np.asarray(q, float), axis=1)
        return float((d - self.roads.width / 2).min())

    def ground_span(self, model, q, yaw, scale=1.0):
        """Lowest and highest ground under a model's whole footprint (and its centre) at q."""
        pts = [(q[0], q[2])] + self.footprint(model, q, yaw, 2.0, scale)
        g = [self.ground(x, z) for x, z in pts]
        return min(g), max(g)

    def site(self, model, q, yaw, scale=1.0, tol=0.5):
        """Height to stand a model on at q: the lowest ground under its footprint, or None when the
        ground there varies by more than tol (a slope or a cliff edge would leave part of it in the
        air)."""
        lo, hi = self.ground_span(model, q, yaw, scale)
        return lo if hi - lo <= tol else None

    def yaw_front(self, model, dirv):
        """Yaw that turns a model's front toward dirv: HL2 props face their local +X, buildings and
        HL1 models +Z."""
        y = self.yaw_facing(dirv)
        return y if _front_z(model) else y - math.pi / 2

    def yaw_along(self, model, dirv):
        """Yaw that lays a model's long side along dirv (wagons on a siding)."""
        m = self.models[model]
        long_x = m["aabb_max"][0] - m["aabb_min"][0] > m["aabb_max"][2] - m["aabb_min"][2]
        return self.yaw_facing(dirv) - (math.pi / 2 if long_x else 0.0)

    def against_wall(self, i, sgn, model, scale=1.0, y=None, inset=0.0, **kw):
        """A prop centred on sample i with its back to the tunnel's wall (sgn +1: right wall), or
        `inset` metres off it, its long side along the wall and its front to the road, standing at
        road height (or y). A long one lies along the wall's chord over its length and touches
        the wall where it juts out furthest (a curve, a narrowing), so it leaves no slot a kart
        could wedge into. Refused (None) when it would reach onto the road, past the end of the
        stretch or over a jump's pit; else the origin it was placed at."""
        if model not in self.models:
            self.missing.add(model)
            return None
        t = self.trk
        m = self.models[model]
        lo, hi = np.array(m["aabb_min"]) * scale, np.array(m["aabb_max"]) * scale
        ax = 0 if hi[0] - lo[0] < hi[2] - lo[2] else 2
        depth, length = hi[ax] - lo[ax], hi[2 - ax] - lo[2 - ax]
        k = int(math.ceil(length / 2 / t.step))
        js = [t.wrap(i + d) for d in range(-k, k + 1)]
        if any(t.style[j] != t.style[i] or t.gap[j] for j in js):
            return None
        W = np.array([t.pos[j] + t.flat_right[j] * sgn * (t.width[j] / 2 + t.wall_gap[j]) for j in js])
        d = W[-1] - W[0]
        d[1] = 0.0
        d /= np.linalg.norm(d)
        n = -t.flat_right[i] * sgn
        n -= d * (n @ d)
        n /= np.linalg.norm(n)
        back = ((W - W[0]) @ n).max() + 0.03 + inset
        c = W[0] + d * ((W[k] - W[0]) @ d) + n * (back + depth / 2)
        # the front corners stay off the road
        for e in (-0.5, 0.5):
            p = c + n * (depth / 2) + d * (length * e)
            j = int(np.argmin(((t.pos[js] - p) ** 2).sum(1)))
            if abs((p - t.pos[js[j]]) @ t.flat_right[js[j]]) < t.width[js[j]] / 2:
                return None
        yaw = self.yaw_facing(n) - (math.pi / 2 if ax == 0 else 0.0)
        cl = (lo + hi) / 2
        cy, sy = math.cos(yaw), math.sin(yaw)
        q = c - np.array([cy, 0.0, -sy]) * cl[0] - np.array([sy, 0.0, cy]) * cl[2]
        q[1] = t.pos[i][1] if y is None else y
        return self.props[-1]["pos"] if self.add(model, q, yaw, scale=scale, **kw) else None

    def light(self, pos, color, rng_, energy=1.2):
        self.lights.append({"pos": [float(x) for x in pos], "color": [float(c) for c in color],
                            "range": float(rng_), "energy": float(energy)})

    def ground(self, x, z):
        g = self.field.sample(x, z) if self.field is not None else None
        return 0.0 if g is None else g

    def clear_of_road(self, q, margin):
        d = np.sqrt(((self.roads.pos[:, [0, 2]] - np.array([q[0], q[2]])) ** 2).sum(1))
        ok = d - self.roads.width / 2 > margin
        return bool(ok.all())

    def road_gap_to(self, q):
        """Plan metres from q to the nearest edge of any road."""
        d = np.sqrt(((self.roads.pos[:, [0, 2]] - np.array([q[0], q[2]])) ** 2).sum(1))
        return float((d - self.roads.width / 2).min())

    @staticmethod
    def side_width(st):
        """Metres a style's side treatment takes past its road edge (see _treatment; a hall's floor
        and walls, a cutting's lip): the spectators' stands keep off it."""
        if st["kind"] == "tunnel":
            return st.get("wall_gap", 0.0) + 0.5
        if st["kind"] == "trench":
            return st.get("lip", 4.0)
        return _treatment(st) or 0.0

    def footprint(self, model, q, yaw, step=4.0, scale=1.0):
        """Ground outline of a model placed at q with yaw (points every `step` metres)."""
        m = self.models[model]
        x0, x1 = m["aabb_min"][0] * scale, m["aabb_max"][0] * scale
        z0, z1 = m["aabb_min"][2] * scale, m["aabb_max"][2] * scale
        c, s_ = math.cos(yaw), math.sin(yaw)
        pts = []
        for (ax, az), (bx, bz) in (((x0, z0), (x1, z0)), ((x1, z0), (x1, z1)), ((x1, z1), (x0, z1)), ((x0, z1), (x0, z0))):
            k = max(1, int(math.hypot(bx - ax, bz - az) / step))
            for j in range(k):
                u = j / k
                lx, lz = ax + (bx - ax) * u, az + (bz - az) * u
                # Godot yaw: local +Z -> (sin yaw, cos yaw)
                pts.append((q[0] + lx * c + lz * s_, q[2] - lx * s_ + lz * c))
        return pts

    def _reserved_hit(self, model, q, yaw, scale=1.0):
        """True when a model at q would stand in a hazard's corridor (reserved, tools/hazards.py) or
        on a stand's plot (crowd_plots, tools/crowds.py): both are kept free of set dressing."""
        if hazards.blocked(self, model, q, yaw, scale):
            return True
        return bool(self.crowd_plots) and self.reserved_hit(self.footprint(model, q, yaw, scale=scale))

    def fits(self, model, q, yaw, margin):
        """True when the whole ground outline stays `margin` metres off every part of every road, out
        of the hazards' corridors and the stands' plots."""
        if self._reserved_hit(model, q, yaw):
            return False
        rp = self.roads.pos[:, [0, 2]]
        hw = self.roads.width / 2
        for x, z in self.footprint(model, q, yaw):
            d = np.sqrt(((rp - np.array([x, z])) ** 2).sum(1)) - hw
            if d.min() < margin:
                return False
        return True

    def wall_sign(self, i, sgn, mat, w, h, y, inset=0.04):
        """A sign on the tunnel wall at sample i (sgn +1 right wall), centre y metres above the road,
        flat on the wall where it runs in or out."""
        t = self.trk
        W = [t.pos[j] + t.flat_right[j] * sgn * (t.width[j] / 2 + t.wall_gap[j]) for j in (t.wrap(i - 1), t.wrap(i + 1))]
        d = W[1] - W[0]
        d[1] = 0.0
        d /= np.linalg.norm(d)
        rf = np.array([-d[2], 0.0, d[0]]) * sgn
        c = t.pos[i] + t.flat_right[i] * sgn * (t.width[i] / 2 + t.wall_gap[i]) - rf * inset + UP * y
        f = d * (w / 2) * sgn
        u = UP * (h / 2)
        quad = [c - f - u, c + f - u, c + f + u, c - f + u]
        tri = [0, 1, 2, 0, 2, 3]
        if np.dot(np.cross(quad[1] - quad[0], quad[2] - quad[0]), -rf) < 0:
            tri = [0, 2, 1, 0, 3, 2]
        # u runs from the viewer's left to right on either wall, so the text reads the right way
        self.meshes["deco"].add(mat, quad, [-rf] * 4, [[1, 1], [0, 1], [0, 0], [1, 0]], tri)

    def box(self, mat, center, size, yaw=0.0, kind="walls", rep=4.0):
        """Box (yaw around Y) with all six faces; kind "walls" collides (and props keep out of it),
        "deco" does not."""
        if kind == "walls":
            self.block(center, size, yaw)
        c = np.asarray(center, float)
        sx, sy, sz = (np.asarray(size, float) / 2)
        cy, syw = math.cos(yaw), math.sin(yaw)
        ax = np.array([cy, 0, -syw]) * sx
        az = np.array([syw, 0, cy]) * sz
        ay = UP * sy
        for nrm, u, w in ((ax, ay, az), (-ax, ay, az), (az, ay, ax), (-az, ay, ax), (ay, az, ax), (-ay, az, ax)):
            n_ = nrm / (np.linalg.norm(nrm) + 1e-9)
            o = c + nrm
            q = [o - u - w, o - u + w, o + u + w, o + u - w]
            tri = [0, 1, 2, 0, 2, 3]
            if np.dot(np.cross(q[1] - q[0], q[2] - q[0]), n_) < 0:
                tri = [0, 2, 1, 0, 3, 2]
            lu, lw = np.linalg.norm(u) * 2 / rep, np.linalg.norm(w) * 2 / rep
            self.meshes[kind].add(mat, q, [n_] * 4, [[0, lu], [lw, lu], [lw, 0], [0, 0]], tri)

    def cylinder(self, mat, base, radius, height, segs=24, kind="walls", inward=False, rep=4.0):
        b = np.asarray(base, float)
        if kind == "walls" and not inward:
            self.block(b + UP * (height / 2), [radius * 2, height, radius * 2])
        ang = np.linspace(0, 2 * math.pi, segs + 1)
        lo = np.stack([b[0] + np.cos(ang) * radius, np.full(segs + 1, b[1]), b[2] + np.sin(ang) * radius], 1)
        hi = lo + UP * height
        u = np.linspace(0, 2 * math.pi * radius / rep, segs + 1)
        nrm = np.stack([np.cos(ang), np.zeros(segs + 1), np.sin(ang)], 1)
        # strip(a, b) faces cross(b - a, along): bottom-to-top faces outward around this ring
        if inward:
            self.meshes[kind].strip(mat, hi, lo, height / rep, 0.0, u, -nrm, -nrm)
        else:
            self.meshes[kind].strip(mat, lo, hi, 0.0, height / rep, u, nrm, nrm)

    @staticmethod
    def yaw_facing(dirv):
        return math.atan2(dirv[0], dirv[2])

    def side(self, i, sgn, dist):
        """Point `dist` metres beyond the road edge on side sgn (+1 right), at road height."""
        t = self.trk
        return t.pos[i] + t.flat_right[i] * sgn * (t.width[i] / 2 + dist)

    def every(self, metres, start=0.0):
        k = max(1, int(round(metres / self.trk.step)))
        return range(int(start / self.trk.step) % k, self.trk.n, k)

    def model_size(self, model):
        m = self.models[model]
        return np.array(m["aabb_max"]) - np.array(m["aabb_min"])

    def row_along(self, styles, choices, sgn, setback, gap=1.0, max_curv=0.02, align=True, extra=0.0,
                  ground=False, tag=None, yaw_off=0.0, accept=None):
        """Buildings / containers / trucks shoulder to shoulder along runs of `styles`,
        front facing the road, each spaced by its own width. Each one needs firm ground under its
        whole footprint (ground=True: it stands on the lowest point, the rest within 1 m; else at
        road height, nothing more than 0.5 m below) and accept(ctx, model, q, yaw), if given."""
        t = self.trk
        i, k = 0, 0
        placed = 0
        while i < t.n:
            if t.style[i] not in styles or abs(t.curv[i]) > max_curv or t.gap[i]:
                i += 1
                continue
            m = choices[k % len(choices)] if align else choices[int(self.rng.integers(0, len(choices)))]
            if m not in self.models:
                self.missing.add(m)
                k += 1
                i += 3
                continue
            mm = self.models[m]
            wdt = (mm["aabb_max"][0] - mm["aabb_min"][0]) * (1.0 + extra)
            front = mm["aabb_max"][2]
            r = t.flat_right[i] * sgn
            q = t.pos[i] + r * (t.width[i] / 2 + setback + front)
            yaw = self.yaw_facing(-r) + yaw_off
            ok = self.fits(m, q, yaw, setback - 0.8) and (accept is None or accept(self, m, q, yaw))
            if ok:
                lo, hi = self.ground_span(m, q, yaw)
                ok = (hi - lo <= 1.0) if ground else (lo > t.pos[i][1] - 0.5)
                q[1] = lo if ground else min(t.pos[i][1], lo)
            if ok and self.add(m, q, yaw, tag=tag, ground=ground):
                placed += 1
                k += 1
                i += max(1, int((wdt + gap) / t.step))
            else:
                i += 3
        return placed


# ---------------------------------------------------------------- gameplay
# a boost pad's centre stays this far from every grid slot (pad half-length 3 m + the longest
# kart's half-length 2.7 m + slack): a kart parked on a pad would launch during the countdown
PAD_CLEAR = 12.0
# ... and this far from every item crate (one pass would trigger both, the crate hangs over it)
PAD_BOX_CLEAR = 10.0
PAD_HALF_W = 2.25
# crate centres stand this far off the surface; in a pipe more, for the spinning corners
BOX_H, BOX_H_TUBE = 1.2, 1.5
# ... and at least this far apart across a row (a crate spins 1.09 m round its centre)
BOX_GAP = 2.4
# a crate or pad whose up leans further than this from the vertical carries its own up
TILT_COS = math.cos(math.radians(2.0))
LIQUID_KINDS = {"water": 1, "slime": 2}


def across_lane(trk, i, o):
    """Sample and lateral metres of the point `o` metres square across the lane from sample i. In
    a pipe the lane winds round as a helix, so that point lies on another ring of the pipe (a row
    of crates laid round one ring would cross the lane on a slant)."""
    if trk.mag[i] <= 0.0:
        return i, o
    target = trk.pos[i] + trk.right[i] * o
    near = [trk.wrap(i + k) for k in range(-12, 13) if trk.mag[trk.wrap(i + k)] > 0.0]
    j = min(near, key=lambda q: abs(np.dot(target - trk.base[q], trk.axis_dir(q))))
    R = trk.mag[j]
    w = target - (trk.base[j] + trk.base_up[j] * R)
    phi = math.atan2(-np.dot(w, trk.base_right[j]), -np.dot(w, trk.base_up[j]))
    return j, R * ((phi - trk.theta[j] + math.pi) % (2 * math.pi) - math.pi)


def item_rows(trk, fracs):
    """Rows of item crates across the road at fractions of the lap (of a branch's length), clear of
    jumps. An entry is the crate's centre [x, y, z], or [x, y, z, ux, uy, uz] where the road tilts
    (pipes, banking): (ux, uy, uz) is the surface's up there, and the game stands the crate on it."""
    n = trk.n
    rows = []
    for frac in fracs:
        i = int(frac * n) % n
        while (trk.gap[trk.wrap(i)] or trk.gap[trk.wrap(i + 8)] or trk.gap[trk.wrap(i - 8)]) and (trk.closed or i < n):
            i += 5
        i = trk.wrap(i)
        tube = trk.mag[i] > 0.0
        w = trk.width[i] / 2 - (3.5 if tube else 2.5)
        # spinning crates this far apart never pass through each other (in a pipe they stand in from
        # its wall, nearer each other than their spots on it, and a ring apart): fewer on a narrow road
        gap = BOX_GAP * (1.1 * trk.mag[i] / (trk.mag[i] - BOX_H_TUBE) if tube else 1.0)
        cnt = max(1, min(5 if trk.width[i] >= 16 else 4, int(2 * w / gap + 1e-6) + 1))
        for k in range(cnt):
            j, lat = across_lane(trk, i, -w + 2 * w * k / (cnt - 1) if cnt > 1 else 0.0)
            p, up, _ = trk.frame_at(j, lat)
            c = p + up * (BOX_H_TUBE if tube else BOX_H)
            rows.append(c.tolist() if not tube and up[1] >= TILT_COS else c.tolist() + up.tolist())
    return rows


def pad_entry(trk, line, i, lat, avoid):
    """The boost pad at sample i (`lat` metres across, None = on the racing line), or None where it
    may not go: over a jump, or nearer to a point of avoid [(point, metres)] (grid slots, item
    crates) than its clearance. Beside an open edge it keeps a metre off the drop. In a pipe it lies
    on the lane's centre unless told otherwise, in the frame at its own spot, with "r" (the pipe's
    radius) and "axis" (the pipe's direction) so the game bends it onto the curved floor."""
    if trk.gap[i]:
        return None
    tube = trk.mag[i] > 0.0
    if lat is None:
        lat = 0.0 if tube else float(np.dot(line[i] - trk.pos[i], trk.right[i]))
    if tube or trk.pit[i]:
        lim = max(trk.width[i] / 2 - PAD_HALF_W - 1.0, 0.0)
        lat = float(np.clip(lat, -lim, lim))
    p, up, fwd = trk.frame_at(i, lat)
    if not tube:
        p = p + up * 0.06
    if any(np.linalg.norm(p - q) < r for q, r in avoid):
        return None
    e = {"pos": p.tolist(), "fwd": fwd.tolist(), "up": up.tolist()}
    if tube:
        e["r"] = float(trk.mag[i])
        e["axis"] = trk.axis_dir(i).tolist()
    return e


def liquids(trk):
    """Liquid surfaces with no floor that a kart can fall into, per sample: the height under
    the road (a slime pit under a jump, a pool), beside it (side channels) and the kind
    (1 water, 2 slime); -1000 = none. Water planes (sea, canal, lakes) are not in here: the
    game knows those from "water" / "waters". Styles mark them with "liquid": a pool under the
    whole stretch {"kind", "y"}, or a "liquid" kind on their "pit" / "gap_pit"."""
    n = trk.n
    under = np.full(n, -1000.0)
    side = np.full(n, -1000.0)
    kind = np.zeros(n, int)
    for i in range(n):
        st = trk.styles[trk.style[i]]
        y = float(trk.pos[i, 1])
        pool = st.get("liquid")
        if pool:
            under[i] = side[i] = pool["y"]
            kind[i] = LIQUID_KINDS[pool["kind"]]
        pit = st.get("pit")
        if isinstance(pit, dict) and pit.get("liquid"):
            side[i] = max(side[i], y - pit["depth"])
            kind[i] = LIQUID_KINDS[pit["liquid"]]
        gp = st.get("gap_pit", {})
        if trk.gap[i] and gp.get("liquid"):
            # the pit under a jump runs wall to wall, under the road and beside it: its liquid is
            # the surface there (no side channels), unless a pool stands higher
            under[i] = side[i] = max(y - gp.get("depth", 3.0), pool["y"] if pool else -1000.0)
            kind[i] = LIQUID_KINDS[gp["liquid"]]
    # a kart that falls short of a jump or overshoots it is still over the pit under it
    reach = int(round(8.0 / trk.step))
    src_u, src_k = under.copy(), kind.copy()
    for i in range(n):
        for k in range(1, reach + 1):
            for j in (trk.wrap(i - k), trk.wrap(i + k)):
                if trk.gap[j] and src_k[j] and src_u[j] > under[i]:
                    under[i] = src_u[j]
                    kind[i] = src_k[j]
    return under, side, kind


def boost_pads(trk, line, boosts, avoid, label="lap"):
    """Boost pads at fractions of the lap (of a branch's length) on the racing line, or (fraction,
    metres across); one on (or right beside) the starting grid or a crate row slides back along
    the road until it is clear, or failing that on along it."""
    n = trk.n
    pads = []
    for b in boosts:
        frac, lat = (b, None) if np.isscalar(b) else b
        i = int(frac * n) % n
        if trk.gap[i]:
            continue
        e = None
        for k in [0] + list(range(-1, -61, -1)) + list(range(1, 61)):
            if not trk.closed and not 0 <= i + k < n:
                continue
            e = pad_entry(trk, line, (i + k) % n, lat, avoid)
            if e is not None:
                break
        if e is None:
            print("  boost pad at %.3f of the %s dropped: no clear spot within 120 m" % (frac, label))
            continue
        if k:
            print("  boost pad at %.3f of the %s moved %+.0f m clear of the grid and the crates" % (frac, label, k * trk.step))
        pads.append(e)
    return pads


def path_data(trk, line, vt):
    """A road as the game reads it (TrackPath): every third sample; an open road's last one too."""
    under, side, kind = liquids(trk)
    ids = np.arange(0, trk.n, 3)
    return {
        "closed": trk.closed,
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
        "pit": trk.pit[ids].astype(int).tolist(),
        "mag": trk.mag[ids].round(2).tolist(),
        "liquid": under[ids].round(2).tolist(),
        "liquid_side": side[ids].round(2).tolist(),
        "liquid_kind": kind[ids].tolist(),
        "theme": [trk.kind(i) for i in ids],
    }


def gameplay(trk, line, vt, defn, brs=()):
    """The track JSON's race data: grid, item crates and boost pads (the lap's, then each
    branch's), the lap's path and the branches (Branch.export)."""
    n = trk.n
    data = {}
    grid = []
    for k in range(8):
        back = 10 + k * 6.5
        i = int(round(-back / trk.step)) % n
        col = -1 if k % 2 == 0 else 1
        p = trk.pos[i] + trk.right[i] * col * min(4.5, trk.width[i] * 0.22) + trk.up[i] * 0.8
        grid.append({"pos": p.tolist(), "fwd": trk.fwd[i].tolist()})
    data["grid"] = grid
    data["item_boxes"] = item_rows(trk, defn.get("items", [0.15, 0.4, 0.62, 0.85]))
    for br in brs:
        data["item_boxes"] += item_rows(br.trk, br.spec.get("items", []))
    avoid = [(np.array(g["pos"]), PAD_CLEAR) for g in grid]
    avoid += [(np.array(b[:3]), PAD_BOX_CLEAR) for b in data["item_boxes"]]
    data["boost_pads"] = boost_pads(trk, line, defn.get("boosts", []), avoid)
    for br in brs:
        data["boost_pads"] += boost_pads(br.trk, br.line, br.spec.get("boosts", []), avoid, br.id)
    data["path"] = path_data(trk, line, vt)
    if brs:
        lap = branches.LapPath(data["path"]["center"], data["path"]["fwd"], trk.length)
        data["branches"] = [br.export(lap) for br in brs]
    return data


# ---------------------------------------------------------------- output
def write_gltf(name, meshes, mats, terrain_layers):
    b = GLTFBuilder()
    root = b.node({"name": name, "children": []})

    def rel(p):
        return os.path.relpath(os.path.join(ASSETS, p), OUT_DIR).replace("\\", "/")

    mat_ids = {}

    def mat_index(mname):
        if mname in mat_ids:
            return mat_ids[mname]
        if mname == "terrain":
            base = mats.info(terrain_layers["base"])
            m = {"name": "terrain", "extras": {"source": {"shader": "hl2kart_terrain"}},
                 "pbrMetallicRoughness": {"metallicFactor": 0, "roughnessFactor": 1,
                                          "baseColorTexture": {"index": b.image(rel(base["albedo"]))}}}
        elif mname == "colonly":
            m = {"name": "colonly", "extras": {"source": {"shader": "colonly"}}}
        else:
            m = gltf_material(b, mats.info(mname), rel)
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
            prims.append({"attributes": attrs, "indices": b.accessor(idx.astype(np.uint32), 5125, "SCALAR", 34963),
                          "material": mat_index(mname)})
        if not prims:
            continue
        b.g["meshes"].append({"name": key, "primitives": prims})
        b.g["nodes"][root]["children"].append(b.node({"name": key, "mesh": len(b.g["meshes"]) - 1}))
    b.save(os.path.join(OUT_DIR, name + ".gltf"))
    stamp_bin_hash(os.path.join(OUT_DIR, name + ".gltf"))
    write_import_settings(os.path.join(OUT_DIR, name + ".gltf"))


# how Godot imports a generated track: its 16-bit vertex compression rounds the two sides of a
# seam differently (hairline cracks to the sky along every edge) and LODs thin out the strips
TRACK_IMPORT = {"meshes/force_disable_compression": "true", "meshes/generate_lods": "false"}


def write_import_settings(gltf_path):
    """Set TRACK_IMPORT in <gltf>.import and keep the rest Godot wrote there (uid, other options).
    Without the file a minimal one is written: Godot fills in the rest on the first import, so a
    player's first build is imported the same way."""
    path = gltf_path + ".import"
    lines = open(path).read().split("\n") if os.path.exists(path) else ["[remap]", "", 'importer="scene"', ""]
    if "[params]" not in lines:
        lines += ["[params]", ""]
    start = lines.index("[params]") + 1
    end = next((k for k in range(start, len(lines)) if lines[k].startswith("[")), len(lines))
    todo = dict(TRACK_IMPORT)
    for k in range(start, end):
        key = lines[k].split("=", 1)[0]
        if key in todo:
            lines[k] = "%s=%s" % (key, todo.pop(key))
    while end > start and not lines[end - 1].strip():
        end -= 1
    lines[end:end] = ["%s=%s" % kv for kv in todo.items()]
    with open(path, "w", newline="\n") as f:
        f.write("\n".join(lines).rstrip("\n") + "\n")


def stamp_bin_hash(gltf_path):
    """Godot re-imports a glTF only when its own text changes: record the .bin's hash in it."""
    import hashlib
    g = json.load(open(gltf_path))
    for buf in g.get("buffers", []):
        uri = buf.get("uri", "")
        binp = os.path.join(os.path.dirname(gltf_path), uri)
        if uri and os.path.exists(binp):
            g.setdefault("asset", {}).setdefault("extras", {})[uri] = hashlib.md5(open(binp, "rb").read()).hexdigest()
    with open(gltf_path, "w") as f:
        json.dump(g, f)


def build(module_name):
    mod = importlib.import_module("circuits." + module_name)
    defn = mod.TRACK
    name = defn["id"]
    # traps and shooters on the lap (tools/hazards.py); a spec that breaks their rules stops here
    specs = hazards.check(defn.get("hazards", []))
    os.makedirs(OUT_DIR, exist_ok=True)
    mats = Mats()
    styles = mod.styles(mats)
    step = defn.get("step", 2.0)
    trk = Trk(defn["ctrl"], styles, step)
    # no fence where a train crosses the road
    trk.cut = hazards.barrier_cuts(trk, specs)
    print("%s: %.0f m, %d samples" % (name, trk.length, trk.n))
    # where each stretch sits on the lap (fractions, for placing items and boosts)
    for nm in styles:
        for ids in trk.runs(lambda i, s_=nm: trk.style[i] == s_, with_gaps=True):
            print("  %-10s %.3f-%.3f  %4.0f m" % (nm, ids[0] / trk.n, ids[-1] / trk.n, len(ids) * trk.step))
    for a, b in trk.gaps:
        print("  jump       %.3f-%.3f" % (a / trk.n, b / trk.n))
    brs = [Branch(trk, spec, styles, step, k, defn.get("gravity", branches.G))
           for k, spec in enumerate(getattr(mod, "BRANCHES", []))]
    for br in brs:
        print(br.summary())
        for end, (dy, u0, u1, ease) in br.moved.items():
            if dy > 0.05:
                print("  branch %-13s %s: laid on the lap's surface over u %.0f-%.0f (moved up to %.2f m), eased back "
                      "over %.0f m: give its control points the lap's heights there" % (br.id, end, u0, u1, dy, ease))
    trks = [trk] + [br.trk for br in brs]
    names = ["lap"] + [br.id for br in brs]
    for r, i, r2, j, gap, problem in crossings(trks, [False] + [br.in_hall for br in brs]):
        print("  crossing   %s s %.0f / %s s %.0f: %.1f m apart%s" % (names[r], trks[r].s[i], names[r2], trks[r2].s[j],
                                                                   gap, "" if problem is None else " !!"))
    for r, t in enumerate(trks):
        for line in tube_checks(t, names[r]):
            print("  !!", line)
    problems = validate(trk, brs, defn)
    for p in problems:
        print("  !!", p)
    if problems and STRICT:
        raise ValueError("%s: %d branch rule(s) broken, see above" % (name, len(problems)))
    if RULES["safe_drop"]:
        k = safe_drop(trks)
        if k:
            print("  safe drop: %d samples lie over another road (no fall there)" % k)
    roads = RoadSet(trk, [br.trk for br in brs])
    models = json.load(open(os.path.join(ASSETS, "data", "models.json")))
    ctx = Ctx(trk, models, np.random.default_rng(defn.get("seed", 17)), roads)
    ctx.junctions = [o for br in brs for o in (br.outline("fork"), br.outline("merge")) if o is not None]
    ctx.mats = mats
    ctx.startline = mod.STARTLINE(mats) if hasattr(mod, "STARTLINE") else mats.hl2("concrete/concretefloor033y")
    meshes = {k: Mesh() for k in MESH_KINDS}
    ctx.meshes = meshes
    ctx.crowd_init(defn)
    tdef = mod.terrain(roads, mats) if hasattr(mod, "terrain") else None
    if tdef:
        # the ground climbs a cell and a half beyond a tunnel's wall: its lid must reach that far
        ctx.lid_min = tdef.get("cell", 3.0) * 2.5 + 1.0
    build_geometry(trk, mats, meshes, ctx)
    for br in brs:
        build_geometry(br.trk, mats, meshes, ctx)
        build_gores(br, meshes, ctx)
    field = None
    layers = None
    if tdef:
        field = Field(roads, tdef.get("margin", 300.0), tdef.get("cell", 3.0))
        H, col = tdef["build"](field, roads)
        # whatever the circuit's terrain did, none of it through a tunnel's lid
        field.H = np.minimum(H, lid_caps(roads, field, ctx.lid_min)).reshape(field.nz, field.nx)
        field.col = col
        layers = tdef["layers"]
        terrain_mesh(meshes["terrain"], field, field.H, col, tdef.get("void"))
    ctx.field = field
    ground = (lambda x, z: field.sample(x, z)) if field else (lambda x, z: None)
    for t in trks:
        ground_geometry(t, meshes, ground, defn.get("water", {}).get("level"))
    pillar_meshes(roads, meshes, ctx.pillars, ground)
    line, off, vt = lap_line(trk, defn, brs)
    for br in brs:
        br.racing(defn)
    # the hazards' corridors and the stands' plots first: the set dressing keeps out of them
    ctx.track_id = name
    hazards.reserve(ctx, specs)
    # where each branch leaves and the lap's jump lips, their spots kept clear like the corridors
    print("  signs: %d fork boards, %d jump lamps" % build_signs(trk, brs, ctx, defn))
    if hasattr(mod, "stands"):
        mod.stands(ctx)
    if hasattr(mod, "stands_branch"):
        for br in brs:
            mod.stands_branch(ctx.crowd_route(br.trk, br.id), br.spec)
    mod.decorate(ctx)
    if hasattr(mod, "decorate_branch"):
        for br in brs:
            mod.decorate_branch(ctx.for_route(br.trk), br.spec)
    # hazards on the road: loose clusters of explosive barrels, standing on it in its middle third
    # (a blast by the kerb throws karts over the barriers, where they can not find the road again)
    for t, fracs in [(trk, defn.get("barrels", []))] + [(br.trk, br.spec.get("barrels", [])) for br in brs]:
        for frac in fracs:
            i = int(frac * t.n) % t.n
            hw = t.width[i] / 6
            for k in range(3):
                j = t.wrap(i + k * 3)
                q = t.surface(j, float(ctx.rng.uniform(-hw, hw)), 0.02)
                ctx.add("props_c17/oildrum001_explosive", q.tolist(), float(ctx.rng.uniform(0, 6.28)), physics=True,
                        ground=False, on_road=True)
    # the hazards' own geometry and props (rails, tunnel portals, crossing signals), then the
    # spectators round everything placed; a spot that breaks their rules stops the build
    hz = hazards.resolve(ctx, specs)
    if hasattr(mod, "crowds"):
        mod.crowds(ctx)
        if hasattr(mod, "crowds_branch"):
            for br in brs:
                mod.crowds_branch(ctx.crowd_route(br.trk, br.id), br.spec)
        ctx.check_crowds()
    if ctx.missing:
        print("  models not extracted:", sorted(ctx.missing))
    if ctx.dropped:
        print("  kept off the branches' roads and junctions: %d props (%s)" % (len(ctx.dropped), ", ".join(sorted(set(ctx.dropped)))))
    if ctx.cleared:
        print("  kept out of the hazards' corridors and the stands' plots: %d props (%s)" % (
            len(ctx.cleared), ", ".join(sorted(set(ctx.cleared)))))
    print("  props %d, lights %d" % (len(ctx.props), len(ctx.lights)))
    data = gameplay(trk, line, vt, defn, brs)
    if specs:
        # one line per hazard; one at a junction or on a branch's road stops the build (STRICT)
        data["hazards"] = hazards.lint(ctx, hz, data, STRICT)
    write_gltf(name, meshes, mats, layers or {"base": styles[trk.style[0]]["road"]})
    data["props"] = ctx.props
    data["lights"] = ctx.lights
    data["screens"] = getattr(ctx, "screens", [])
    if hasattr(mod, "crowds"):
        data.update(ctx.crowd_export())
    for k in ("sky", "env", "water", "waters", "background", "gantry", "gantry_clear", "kill_y", "music", "offtrack",
              "citadel"):
        if k in defn:
            data[k] = defn[k]
    data["sea_level"] = defn.get("water", {}).get("level", -1000.0)
    if field is not None:
        data["terrain"] = {"x0": float(field.xs[0]), "z0": float(field.zs[0]), "cell": field.cell,
                           "nx": field.nx, "nz": field.nz}
        data["terrain_layers"] = {k: mats.info(v).get("albedo", "") for k, v in layers.items()}
        field.H.astype(np.float32).tofile(os.path.join(OUT_DIR, name + "_height.bin"))
    with open(os.path.join(OUT_DIR, name + ".json"), "w") as f:
        json.dump(data, f)
    mats.save_db()
    print("  wrote", name)


if __name__ == "__main__":
    for m in sys.argv[1:]:
        build(m)
