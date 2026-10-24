"""Themed procedural circuits in the manner of Highway 17 (tools/build_track.py).

A circuit is a closed Catmull-Rom spline through control points. Each control
point names the cross-section style of the stretch that starts there (a City 17
street, an open road, a tunnel or hall, a bridge, a trench) and flags such as a
jump gap. The builder turns that into visible, colliding geometry only: every
wall the karts can hit is drawn. Terrain, props, lights, item crates and boost
pads come from the circuit's own module in tools/circuits/.

Writes assets/track/<id>.gltf (+.bin), <id>.json and <id>_height.bin.

usage: python track_gen.py <circuit> [<circuit> ...]     (ct17, black_mesa, xen, surface_tension)
"""
import importlib
import json
import math
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import materials  # noqa: E402
import srcfs  # noqa: E402
import goldsrc_bsp as gb  # noqa: E402
from build_track import Mesh, catmull_rom_closed, cyc_runs, noise2, smoothstep, racing_line  # noqa: E402
from mdl import GLTFBuilder, gltf_material  # noqa: E402

ASSETS = os.path.normpath(os.path.join(HERE, "..", "assets"))
OUT_DIR = os.path.join(ASSETS, "track")
UP = np.array([0.0, 1.0, 0.0])
MESH_KINDS = ("road", "verge", "walls", "side", "ceil", "decal", "deco", "glow", "terrain")


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
class Trk:
    """Samples every `step` metres along the closed spline with frames, widths,
    styles and per-control flags; gap samples have no road (a jump)."""

    def __init__(self, ctrl, styles, step=2.0):
        self.ctrl = ctrl
        self.styles = styles
        pts = [(c[0], c[1], c[2]) for c in ctrl]
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
        self.gap = np.zeros(n, bool)
        self._apply_gaps()
        self._frames()

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
                j = (first - ramp + k) % self.n
                u = (k + 1) / ramp
                self.pos[j, 1] += lift * u * u
            self.gaps.append((first, last + 1))

    def _frames(self):
        n = self.n
        f = np.roll(self.pos, -1, axis=0) - np.roll(self.pos, 1, axis=0)
        f /= np.linalg.norm(f, axis=1, keepdims=True)
        self.fwd = f
        right = np.stack([-f[:, 2], np.zeros(n), f[:, 0]], 1)
        right /= np.linalg.norm(right, axis=1, keepdims=True)
        h = np.stack([f[:, 0], f[:, 2]], 1)
        hn = np.roll(h, -3, axis=0)
        hp = np.roll(h, 3, axis=0)
        cross = hp[:, 0] * hn[:, 1] - hp[:, 1] * hn[:, 0]
        self.curv = cross / (6 * self.step)
        banked = np.array([self.styles[s].get("bank", False) for s in self.style])
        bank = np.where(banked, np.clip(self.curv * 120.0, -0.15, 0.15), 0.0)
        for _ in range(30):
            bank = (np.roll(bank, 1) + bank * 2 + np.roll(bank, -1)) / 4
        c, s_ = np.cos(bank), np.sin(bank)
        up0 = np.cross(right, f)
        self.right = right * c[:, None] - up0 * s_[:, None]
        self.up = np.cross(self.right, f)
        self.up /= np.linalg.norm(self.up, axis=1, keepdims=True)
        self.flat_right = right

    def edge(self, i, off):
        return self.pos[i] + self.right[i] * off

    def runs(self, pred, with_gaps=False):
        """Cyclic index runs (arrays, wrapped) where pred(i) holds and the road exists."""
        mask = np.array([pred(i) and (with_gaps or not self.gap[i]) for i in range(self.n)])
        return [np.arange(a, b + 1) % self.n for a, b in cyc_runs(mask)]

    def style_runs(self, kinds):
        kinds = (kinds,) if isinstance(kinds, str) else kinds
        return self.runs(lambda i: self.kind(i) in kinds)


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


def box_wall(mesh, mat, base_in, base_out, h, v, side, rep):
    """A solid wall with an inner face, a top and an outer face (closed ends left to the caller)."""
    up = UP * h
    wall_strip(mesh, mat, base_in, base_in + up, v, side, rep)
    wall_strip(mesh, mat, base_out, base_out + up, v, -side, rep)
    a, b = (base_in + up, base_out + up) if side > 0 else (base_out + up, base_in + up)
    mesh.strip(mat, a, b, 0.0, 0.25, v / rep)


def build_geometry(trk, mats, meshes, ctx):
    n = trk.n
    S = trk.styles

    # road surface, per style
    for name, st in S.items():
        for ids in trk.runs(lambda i, nm=name: trk.style[i] == nm):
            hw = trk.width[ids] / 2
            L = trk.pos[ids] - trk.right[ids] * hw[:, None]
            R = trk.pos[ids] + trk.right[ids] * hw[:, None]
            if st.get("road_u") == "full":
                # one texture across the whole width (painted lanes), stretched along by road_len
                v = _unwrap_s(trk, ids) / (trk.width[ids] * st.get("road_len", 1.0))
                meshes["road"].strip(st["road"], L, R, 0.0, 1.0, v, trk.up[ids], trk.up[ids])
            else:
                rep = _uvlen(st, "road", 6.0)
                v = _unwrap_s(trk, ids) / rep
                meshes["road"].strip(st["road"], L, R, -hw / rep, hw / rep, v, trk.up[ids], trk.up[ids])
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
    # faces where the road ends at a jump
    for a, b in trk.gaps:
        for j, sgn in (((a - 1) % n, 1.0), (b % n, -1.0)):
            st = S[trk.style[j]]
            hw = trk.width[j] / 2 + 0.5
            c = trk.pos[j]
            Lp = c - trk.right[j] * hw
            Rp = c + trk.right[j] * hw
            d = UP * st.get("gap_face", 4.0)
            f = trk.fwd[j] * sgn
            mat = st.get("skirt", st["road"])
            meshes["side"].add(mat, [Lp, Rp, Rp - d, Lp - d], [f] * 4, [[0, 0], [2, 0], [2, 0.6], [0, 0.6]],
                               [0, 1, 2, 0, 2, 3] if sgn > 0 else [0, 2, 1, 0, 3, 2])
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


def _unwrap_s(trk, ids):
    s = trk.s[ids].copy()
    for k in range(1, len(s)):
        if s[k] < s[k - 1] - trk.length * 0.5:
            s[k:] += trk.length
    return s


def _lane_lines(trk, ids, meshes, st):
    """Painted lane dashes down the middle (a decal strip every other 6 m)."""
    mat = st["lines"]
    s = _unwrap_s(trk, ids)
    on = (np.floor(s / 6.0) % 2) == 0
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


def _street(trk, ids, st, meshes):
    """Kerb, pavement and a visible barrier (railing, wall or fence) at the back of the pavement."""
    hw = trk.width[ids] / 2
    v = _unwrap_s(trk, ids)
    curb_h = st.get("curb_h", 0.16)
    walk = st.get("walk", 4.0)
    for sgn in (-1, 1):
        r = trk.right[ids] * sgn
        rf = trk.flat_right[ids] * sgn
        e0 = trk.pos[ids] + r * hw[:, None]
        e1 = e0 + UP * curb_h
        e2 = e1 + rf * 0.3
        e3 = e2 + rf * walk
        rep = _uvlen(st, "walk", 3.0)
        if sgn > 0:
            meshes["side"].strip(st["curb"], e0, e1, 0.0, 0.06, v / 3.0, -r, -r)
            meshes["road"].strip(st["curb"], e1, e2, 0.06, 0.12, v / 3.0, trk.up[ids], trk.up[ids])
            meshes["road"].strip(st["walk_mat"], e2, e3, 0.0, walk / rep, v / rep, trk.up[ids], trk.up[ids])
        else:
            meshes["side"].strip(st["curb"], e1, e0, 0.06, 0.0, v / 3.0, -r, -r)
            meshes["road"].strip(st["curb"], e2, e1, 0.12, 0.06, v / 3.0, trk.up[ids], trk.up[ids])
            meshes["road"].strip(st["walk_mat"], e3, e2, walk / rep, 0.0, v / rep, trk.up[ids], trk.up[ids])
        bar = st.get("barrier")
        if bar:
            _barrier(meshes, bar, e3, rf, v, sgn)


def _barrier(meshes, bar, base, rf, v, sgn):
    """Barrier along a polyline: "wall" (solid, thick), "fence" (thin, both faces) or "jersey"."""
    kind = bar.get("kind", "wall")
    h = bar.get("h", 1.2)
    mat = bar["mat"]
    rep = bar.get("rep", 3.0)
    if kind == "jersey":
        prof = [(0.0, 0.0), (0.0, 0.25), (0.22, 0.55), (0.32, 1.05), (0.62, 1.05), (0.72, 0.55), (0.95, 0.25), (0.95, -1.0)]
        rings = [base + rf * dx + UP * dy for dx, dy in prof]
        for k in range(len(rings) - 1):
            A, B = rings[k], rings[k + 1]
            if sgn > 0:
                meshes["walls"].strip(mat, A, B, prof[k][1] * 0.5 + 0.5, prof[k + 1][1] * 0.5 + 0.5, v / 4.0)
            else:
                meshes["walls"].strip(mat, B, A, prof[k + 1][1] * 0.5 + 0.5, prof[k][1] * 0.5 + 0.5, v / 4.0)
        return
    t = bar.get("thick", 0.4 if kind == "wall" else 0.05)
    b_in = base - UP * 0.3
    b_out = b_in + rf * t
    box_wall(meshes["walls"], mat, b_in, b_out, h + 0.3, v, sgn, rep)


def _open(trk, ids, st, meshes):
    """Drivable verges sloping down to the terrain, so a kart that ran wide climbs back on."""
    hw = trk.width[ids] / 2
    v = _unwrap_s(trk, ids)
    vw = st.get("verge_w", 4.5)
    drop = st.get("verge_drop", 0.27)
    for sgn in (-1, 1):
        r = trk.right[ids] * sgn
        rf = trk.flat_right[ids] * sgn
        E = trk.pos[ids] + r * hw[:, None]
        dd = drop + np.abs(trk.right[ids][:, 1]) * 1.5
        O = E + rf * vw - UP * dd[:, None]
        if sgn > 0:
            meshes["verge"].strip(st["verge"], E, O, 0.0, vw / 4.0, v / 4.0)
        else:
            meshes["verge"].strip(st["verge"], O, E, vw / 4.0, 0.0, v / 4.0)
        bar = st.get("barrier")
        if bar and (bar.get("sides", "both") == "both" or (bar["sides"] == "right") == (sgn > 0)):
            _barrier(meshes, bar, E + rf * bar.get("off", 0.2), rf, v, sgn)


def _tunnel(trk, ids, st, meshes, ctx):
    """Walls, ceiling and light panels; a hall is a tunnel with a big width and height.
    Optional side pits (liquid behind a railing), a pit under any jump gap, and
    portals (end walls around the opening) where the tunnel meets the outside."""
    hw = trk.width[ids] / 2 + st.get("wall_gap", 0.0)
    H = _run_heights(trk, ids)
    v = _unwrap_s(trk, ids)
    rep = _uvlen(st, "wall", 4.0)
    pit = st.get("pit")
    gapm = trk.gap[ids]
    gp = st.get("gap_pit", {})
    drop = pit["depth"] if pit else 0.0
    if gapm.any():
        drop = max(drop, gp.get("depth", 3.0))
    if pit:
        road_hw = trk.width[ids] / 2
        for sgn in (-1, 1):
            rf = trk.flat_right[ids] * sgn
            E = trk.pos[ids] + rf * road_hw[:, None]
            low = E - UP * pit["depth"]
            pw = st.get("pit_wall", st["wall"])
            if sgn > 0:
                meshes["side"].strip(pw, E, low, 0.0, pit["depth"] / 4.0, v / 4.0, rf, rf)
            else:
                meshes["side"].strip(pw, low, E, pit["depth"] / 4.0, 0.0, v / 4.0, rf, rf)
            W = trk.pos[ids] + rf * hw[:, None] - UP * pit["depth"]
            a, b = (low, W) if sgn > 0 else (W, low)
            meshes["glow" if pit.get("glow") else "verge"].strip(pit["mat"], a, b, 0.0, 1.0, v / 4.0,
                                                                 UP[None].repeat(len(ids), 0), UP[None].repeat(len(ids), 0))
            if st.get("barrier"):
                _barrier(meshes, st["barrier"], E, rf, v, sgn)
    if not pit and st.get("wall_gap", 0.0) > 0.05:
        # floor between the road edge and the walls (halls are wider than the road)
        road_hw = trk.width[ids] / 2
        fmat = st.get("side_floor", st["road"])
        frep = _uvlen(st, "road", 4.0)
        for sgn in (-1, 1):
            rf = trk.flat_right[ids] * sgn
            E = trk.pos[ids] + rf * road_hw[:, None] - UP * 0.01
            W = trk.pos[ids] + rf * (hw + 0.3)[:, None] - UP * 0.01
            a, b = (E, W) if sgn > 0 else (W, E)
            ua, ub = (road_hw / frep, (hw + 0.3) / frep) if sgn > 0 else ((hw + 0.3) / frep, road_hw / frep)
            meshes["road"].strip(fmat, a, b, ua, ub, v / frep, trk.up[ids], trk.up[ids])
    if gapm.any():
        # the floor of the pit under a jump, wall to wall
        pmat = gp.get("mat", st["wall"])
        for a, b in _bool_runs(gapm):
            sub = slice(max(a - 1, 0), min(b + 1, len(ids)))
            Lp = trk.pos[ids][sub] - trk.flat_right[ids][sub] * hw[sub, None] - UP * gp.get("depth", 3.0)
            Rp = trk.pos[ids][sub] + trk.flat_right[ids][sub] * hw[sub, None] - UP * gp.get("depth", 3.0)
            meshes["glow" if gp.get("glow") else "verge"].strip(pmat, Lp, Rp, 0.0, 1.0, v[sub] / 4.0,
                                                                UP[None].repeat(len(Lp), 0), UP[None].repeat(len(Lp), 0))
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
        lid_w = st.get("lid_w", 7.0)
        lid_y = (H + cover - 0.15)[:, None]
        Lc = trk.pos[ids] - trk.flat_right[ids] * (hw + lid_w)[:, None]
        Rc = trk.pos[ids] + trk.flat_right[ids] * (hw + lid_w)[:, None]
        Lc[:, 1:2] = trk.pos[ids][:, 1:2] + lid_y
        Rc[:, 1:2] = trk.pos[ids][:, 1:2] + lid_y
        lrep = _uvlen(st, "lid", 4.0)
        meshes["walls"].strip(st.get("lid_mat", st["ceil"]), Lc, Rc, -(hw + lid_w) / lrep, (hw + lid_w) / lrep,
                              v / lrep, UP[None].repeat(len(ids), 0), UP[None].repeat(len(ids), 0))
    # portals: an end wall above and around the opening, when the next stretch is not a tunnel
    n = trk.n
    for end, sgn_f in ((ids[0], -1.0), (ids[-1], 1.0)):
        nb = (end + int(sgn_f)) % n
        if trk.kind(nb) == "tunnel":
            continue
        if not st.get("portals", True):
            continue
        k = 0 if sgn_f < 0 else -1
        c = trk.pos[end]
        rr = trk.flat_right[end]
        f = trk.fwd[end] * sgn_f
        pw = st.get("portal_w", st.get("lid_w", 7.0) + 8.0)
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


def _bridge(trk, ids, st, meshes, ctx):
    """Deck edges dropping a skirt, railings both sides, pillars down to the ground."""
    hw = trk.width[ids] / 2
    v = _unwrap_s(trk, ids)
    skirt = st.get("skirt_h", 1.6)
    for sgn in (-1, 1):
        r = trk.right[ids] * sgn
        rf = trk.flat_right[ids] * sgn
        E = trk.pos[ids] + r * hw[:, None]
        low = E - UP * skirt
        nrm = rf
        if sgn > 0:
            meshes["side"].strip(st["skirt"], E, low, 0.0, skirt / 4.0, v / 4.0, nrm, nrm)
        else:
            meshes["side"].strip(st["skirt"], low, E, skirt / 4.0, 0.0, v / 4.0, nrm, nrm)
        bar = st.get("barrier")
        if bar:
            _barrier(meshes, bar, E, rf, v, sgn)
    # underside
    L = trk.pos[ids] - trk.right[ids] * hw[:, None] - UP * skirt
    R = trk.pos[ids] + trk.right[ids] * hw[:, None] - UP * skirt
    meshes["side"].strip(st["skirt"], R, L, 0, 1, v / 4.0, -UP[None].repeat(len(ids), 0), -UP[None].repeat(len(ids), 0))
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


def pillar_meshes(trk, meshes, pillars, ground_h):
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
            corners = [c + (fwd * a + right * b) * sz / 2 for a, b in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
            for q in range(4):
                p0, p1 = corners[q], corners[(q + 1) % 4]
                bot0 = np.array([p0[0], g - 1.0, p0[2]])
                bot1 = np.array([p1[0], g - 1.0, p1[2]])
                nrm = np.cross(p1 - p0, UP)
                nrm /= np.linalg.norm(nrm) + 1e-9
                hh = p0[1] - bot0[1]
                meshes["walls"].add(mat, [bot0, bot1, p1, p0], [nrm] * 4,
                                    [[0, hh / 4], [sz / 4, hh / 4], [sz / 4, 0], [0, 0]], [0, 2, 1, 0, 3, 2])


# ---------------------------------------------------------------- terrain
class Field:
    """Heightfield over the circuit's bounds with nearest-road lookups."""

    def __init__(self, trk, margin, cell):
        lo = trk.pos[:, [0, 2]].min(0) - margin
        hi = trk.pos[:, [0, 2]].max(0) + margin
        self.cell = cell
        self.nx = int((hi[0] - lo[0]) / cell) + 1
        self.nz = int((hi[1] - lo[1]) / cell) + 1
        self.xs = lo[0] + np.arange(self.nx) * cell
        self.zs = lo[1] + np.arange(self.nz) * cell
        X, Z = np.meshgrid(self.xs, self.zs)
        self.P = np.stack([X.ravel(), Z.ravel()], 1)
        rp = trk.pos[:, [0, 2]]
        near = np.zeros(len(self.P), np.int64)
        dist = np.zeros(len(self.P))
        for a in range(0, len(self.P), 4096):
            q = self.P[a:a + 4096]
            d2 = ((q[:, None, :] - rp[None, :, :]) ** 2).sum(-1)
            k = np.argmin(d2, axis=1)
            near[a:a + 4096] = k
            dist[a:a + 4096] = np.sqrt(d2[np.arange(len(q)), k])
        self.near = near
        self.dist = dist
        self.lat = ((self.P - rp[near]) * trk.flat_right[near][:, [0, 2]]).sum(1)
        self.kind = np.array([trk.kind(i) for i in range(trk.n)])[near]
        self.style = np.array(trk.style)[near]
        self.road_h = trk.pos[near, 1]
        self.half = trk.width[near] / 2
        self.gap = trk.gap[near]
        self.tunnel_top = trk.pos[near, 1] + trk.height[near]
        self.H = None
        self.col = None

    def dist_to(self, trk, mask):
        """Distance from every cell to the nearest road sample where mask is true."""
        rp = trk.pos[np.asarray(mask, bool)][:, [0, 2]]
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


def carve(field, nat, trk, flat=6.0, blend=28.0, tunnel_cover=3.0, gap_floor=None):
    # tunnel_cover must match the tunnel styles' "cover" so the lid sits under the raised ground
    """Natural heights -> heights that meet the road: flat shoulders beside it, the
    natural land further out, cover over tunnels and a dip under jumps and bridges."""
    f = field
    under = f.road_h - 0.35
    t = smoothstep(f.half + flat, f.half + flat + blend, f.dist)
    h = under * (1 - t) + nat * t
    # walled cuttings: the ground beyond the walls stays at the natural level
    cut = (f.kind == "trench") & (f.dist > f.half + 0.5)
    h = np.where(cut, np.maximum(h, np.minimum(nat, f.road_h + f.tunnel_top - f.road_h)), h)
    tun = f.kind == "tunnel"
    # a tunnel runs inside a hill. A heightfield can not overhang, so the ground stays at
    # road level inside the tunnel walls and rises only outside them; the tunnel's own
    # lid (see _tunnel) closes the slot over it and the portals cover the steps.
    roof = f.tunnel_top + tunnel_cover
    tc = smoothstep(f.half + 4.0, f.half + 30.0, f.dist)
    inside = tun & (f.dist < f.half + 1.5)
    h = np.where(tun & ~inside, np.maximum(h, roof * (1 - tc) + nat * tc), h)
    h = np.where(inside, under, h)
    br = (f.kind == "bridge") | f.gap
    if gap_floor is not None:
        dip = smoothstep(f.half + 20.0, f.half * 0.3, f.dist) * br
        h = h * (1 - dip) + np.minimum(nat, gap_floor) * dip
    else:
        h = np.where(br & (f.dist < f.half + 8.0), np.minimum(h, f.road_h - 8.0), h)
    return h


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
    if void_y is not None:
        # nothing at all where the ground sank into the void: the sky shows below floating land
        hv = H.ravel()
        keep = (hv[tri] > void_y).any(1)
        tri = tri[keep]
    mesh.add("terrain", p, nrm, uv, tri.reshape(-1), col)


# ---------------------------------------------------------------- decoration context
class Ctx:
    def __init__(self, trk, models, rng):
        self.trk = trk
        self.models = models
        self.rng = rng
        self.props = []
        self.lights = []
        self.pillars = []
        self.field = None
        self.startline = "concrete/concretefloor033y"
        self.missing = set()

    def add(self, model, pos, yaw=0.0, physics=False, scale=1.0, tag=None, ground=True, pitch=0.0):
        if model not in self.models:
            self.missing.add(model)
            return False
        p = [float(pos[0]), float(pos[1]), float(pos[2])]
        self.props.append({"model": model, "pos": p, "yaw": float(yaw), "physics": physics, "scale": float(scale),
                           "tag": tag, "ground": ground, "pitch": float(pitch)})
        return True

    def light(self, pos, color, rng_, energy=1.2):
        self.lights.append({"pos": [float(x) for x in pos], "color": [float(c) for c in color],
                            "range": float(rng_), "energy": float(energy)})

    def ground(self, x, z):
        g = self.field.sample(x, z) if self.field is not None else None
        return 0.0 if g is None else g

    def clear_of_road(self, q, margin):
        d = np.sqrt(((self.trk.pos[:, [0, 2]] - np.array([q[0], q[2]])) ** 2).sum(1))
        ok = d - self.trk.width / 2 > margin
        return bool(ok.all())

    def road_gap_to(self, q):
        d = np.sqrt(((self.trk.pos[:, [0, 2]] - np.array([q[0], q[2]])) ** 2).sum(1))
        return float((d - self.trk.width / 2).min())

    def footprint(self, model, q, yaw, step=4.0):
        """Ground outline of a model placed at q with yaw (points every `step` metres)."""
        m = self.models[model]
        x0, x1 = m["aabb_min"][0], m["aabb_max"][0]
        z0, z1 = m["aabb_min"][2], m["aabb_max"][2]
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

    def fits(self, model, q, yaw, margin):
        """True when the whole ground outline stays `margin` metres off every part of the road."""
        rp = self.trk.pos[:, [0, 2]]
        hw = self.trk.width / 2
        for x, z in self.footprint(model, q, yaw):
            d = np.sqrt(((rp - np.array([x, z])) ** 2).sum(1)) - hw
            if d.min() < margin:
                return False
        return True

    def wall_sign(self, i, sgn, mat, w, h, y, inset=0.04):
        """A sign on the tunnel wall at sample i (sgn +1 right wall), centre y metres above the road."""
        t = self.trk
        st = t.styles[t.style[i]]
        hw = t.width[i] / 2 + st.get("wall_gap", 0.0)
        rf = t.flat_right[i] * sgn
        c = t.pos[i] + rf * (hw - inset) + UP * y
        f = t.fwd[i] * (w / 2) * sgn
        u = UP * (h / 2)
        quad = [c - f - u, c + f - u, c + f + u, c - f + u]
        tri = [0, 1, 2, 0, 2, 3]
        if np.dot(np.cross(quad[1] - quad[0], quad[2] - quad[0]), -rf) < 0:
            tri = [0, 2, 1, 0, 3, 2]
        self.meshes["deco"].add(mat, quad, [-rf] * 4, [[0, 1], [1, 1], [1, 0], [0, 0]], tri)

    def box(self, mat, center, size, yaw=0.0, kind="walls", rep=4.0):
        """Box (yaw around Y) with all six faces; kind "walls" collides, "deco" does not."""
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
                  ground=False, tag=None, yaw_off=0.0):
        """Buildings / containers / trucks shoulder to shoulder along runs of `styles`,
        front facing the road, each spaced by its own width."""
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
            edge = t.pos[i] + r * (t.width[i] / 2 + setback)
            yaw = self.yaw_facing(-r) + yaw_off
            if self.fits(m, q, yaw, setback - 0.8):
                q[1] = self.ground(q[0], q[2]) if ground else t.pos[i][1]
                self.add(m, q, yaw, tag=tag, ground=ground)
                placed += 1
                k += 1
                i += max(1, int((wdt + gap) / t.step))
            else:
                i += 3
        return placed


# ---------------------------------------------------------------- gameplay
def gameplay(trk, line, vt, defn):
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
    rows = []
    for frac in defn.get("items", [0.15, 0.4, 0.62, 0.85]):
        i = int(frac * n) % n
        while trk.gap[i % n] or trk.gap[(i + 8) % n] or trk.gap[(i - 8) % n]:
            i += 5
        i %= n
        cnt = 5 if trk.width[i] >= 16 else 4
        w = trk.width[i] / 2 - 2.5
        for k in range(cnt):
            o = -w + 2 * w * k / (cnt - 1)
            p = trk.pos[i] + trk.right[i] * o + trk.up[i] * 1.2
            rows.append(p.tolist())
    data["item_boxes"] = rows
    pads = []
    for frac in defn.get("boosts", []):
        i = int(frac * n) % n
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
        "theme": [trk.kind(i) for i in ids],
    }
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
    os.makedirs(OUT_DIR, exist_ok=True)
    mats = Mats()
    styles = mod.styles(mats)
    trk = Trk(defn["ctrl"], styles, defn.get("step", 2.0))
    print("%s: %.0f m, %d samples" % (name, trk.length, trk.n))
    models = json.load(open(os.path.join(ASSETS, "data", "models.json")))
    ctx = Ctx(trk, models, np.random.default_rng(defn.get("seed", 17)))
    ctx.mats = mats
    ctx.startline = mod.STARTLINE(mats) if hasattr(mod, "STARTLINE") else mats.hl2("concrete/concretefloor033y")
    meshes = {k: Mesh() for k in MESH_KINDS}
    ctx.meshes = meshes
    build_geometry(trk, mats, meshes, ctx)
    field = None
    layers = None
    if hasattr(mod, "terrain"):
        tdef = mod.terrain(trk, mats)
        field = Field(trk, tdef.get("margin", 300.0), tdef.get("cell", 3.0))
        H, col = tdef["build"](field, trk)
        field.H = H.reshape(field.nz, field.nx)
        field.col = col
        layers = tdef["layers"]
        terrain_mesh(meshes["terrain"], field, field.H, col, tdef.get("void"))
    ctx.field = field
    pillar_meshes(trk, meshes, ctx.pillars, (lambda x, z: field.sample(x, z)) if field else (lambda x, z: None))
    line, off, vt = racing_line(trk)
    vt = np.minimum(vt, defn.get("vmax", 40.0))
    mod.decorate(ctx)
    if ctx.missing:
        print("  models not extracted:", sorted(ctx.missing))
    print("  props %d, lights %d" % (len(ctx.props), len(ctx.lights)))
    write_gltf(name, meshes, mats, layers or {"base": styles[trk.style[0]]["road"]})
    data = gameplay(trk, line, vt, defn)
    data["props"] = ctx.props
    data["lights"] = ctx.lights
    data["screens"] = getattr(ctx, "screens", [])
    for k in ("sky", "env", "water", "waters", "background", "gantry", "kill_y", "music", "offtrack", "citadel"):
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
