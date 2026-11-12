"""Plots of a generated track's JSON (assets/track/<id>.json): the plan, every junction close up
and the heights along the lap. It costs nothing to run and catches most layout mistakes before
Godot is started: noses too near or too far from their fork, roads crossing at one level, crates
and pads on the wrong road, a branch drawn against the wrong lap metres.

  plan:      the lap coloured by kind (street grey, open green, tunnel brown, deck blue, cutting
             sand, pipe cyan; jumps red, open edges orange), each branch over it in magenta with
             its noses (red), the item crate rows (yellow) and boost pads (cyan), lap metres
             every 200 m; upper roads are drawn over lower ones
  junctions: each fork and merge, 140 m across, the roads' edges and racing lines, the noses
  profile:   heights along the lap, each branch against the lap metres it counts as (s_main)

usage: python track_plot.py <id | track.json> [...] [--out DIR]   (writes <id>_plan.png,
       <id>_junctions.png and <id>_profile.png into DIR, default the current folder)
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
TRACKS = os.path.normpath(os.path.join(HERE, "..", "assets", "track"))
KIND = {"street": (190, 190, 196), "open": (110, 190, 90), "tunnel": (160, 115, 70), "bridge": (90, 150, 255),
        "trench": (200, 170, 120), "tube": (40, 225, 255)}
BG, GRID, TEXT = (22, 24, 28), (40, 42, 48), (235, 235, 235)
GAP, EDGE, NOSE, BRANCH = (255, 50, 50), (255, 150, 40), (255, 80, 60), (255, 0, 255)


def _arr(p, key):
    return np.array(p[key], float)


def _roads(data):
    """(name, path dict, is_branch, branch entry) for the lap and each branch."""
    out = [("lap", data["path"], False, None)]
    for b in data.get("branches", []):
        out.append((b["id"], b["path"], True, b))
    return out


def _quads(p):
    """Per segment of a path: (mean height, polygon (4, 2) in plan, kind, gap, pit)."""
    c, r, w = _arr(p, "center"), _arr(p, "right"), _arr(p, "width")
    n = len(c)
    closed = p.get("closed", True)
    L, R = c - r * w[:, None] / 2, c + r * w[:, None] / 2
    out = []
    for i in range(n if closed else n - 1):
        j = (i + 1) % n
        poly = np.array([L[i], R[i], R[j], L[j]])[:, [0, 2]]
        out.append(((c[i, 1] + c[j, 1]) / 2, poly, p["theme"][i], p["gap"][i], p.get("pit", p["gap"])[i]))
    return out


def _tint(col, to, k):
    return tuple(int(a * (1 - k) + b * k) for a, b in zip(col, to))


class View:
    """World plan (x, z) to image pixels over a box."""

    def __init__(self, lo, hi, size, pad=20):
        self.lo, self.pad = np.asarray(lo, float), pad
        self.sc = min((size[0] - 2 * pad) / max(hi[0] - lo[0], 1e-6), (size[1] - 2 * pad) / max(hi[1] - lo[1], 1e-6))

    def __call__(self, q):
        q = np.asarray(q, float)
        return (self.pad + (q[..., 0] - self.lo[0]) * self.sc, self.pad + (q[..., 1] - self.lo[1]) * self.sc)

    def pts(self, poly):
        x, y = self(poly)
        return list(zip(np.atleast_1d(x).tolist(), np.atleast_1d(y).tolist()))


def _grid(dr, v, lo, hi, every):
    for gx in np.arange(math.floor(lo[0] / every) * every, hi[0] + every, every):
        dr.line(v.pts(np.array([[gx, lo[1]], [gx, hi[1]]])), fill=GRID)
    for gz in np.arange(math.floor(lo[1] / every) * every, hi[1] + every, every):
        dr.line(v.pts(np.array([[lo[0], gz], [hi[0], gz]])), fill=GRID)


def _draw_roads(dr, v, data, outline=False):
    segs = []
    for name, p, is_branch, _ in _roads(data):
        for y, poly, kind, gap, pit in _quads(p):
            col = KIND.get(kind, (255, 255, 255))
            if gap:
                col = GAP
            elif pit:
                col = _tint(col, EDGE, 0.5)
            if is_branch:
                col = _tint(col, BRANCH, 0.45)
            segs.append((y + (0.01 if is_branch else 0.0), poly, col))
    segs.sort(key=lambda s: s[0])
    for _, poly, col in segs:
        dr.polygon(v.pts(poly), fill=col, outline=(0, 0, 0) if outline else None)


def _nose_lines(dr, v, b, width=3):
    p = b["path"]
    c, r, w = _arr(p, "center"), _arr(p, "right"), _arr(p, "width")
    step = p["step"]
    for u in (b["fork_nose_u"], b["merge_nose_u"]):
        k = min(int(round(u / step)), len(c) - 1)
        e = np.array([c[k] - r[k] * w[k] / 2, c[k] + r[k] * w[k] / 2])[:, [0, 2]]
        dr.line(v.pts(e), fill=NOSE, width=width)


def _items(dr, v, data, rad=3):
    for e in data.get("item_boxes", []):
        x, y = v(np.array([e[0], e[2]]))
        dr.rectangle([x - rad, y - rad, x + rad, y + rad], fill=(255, 230, 60))
    for pad in data.get("boost_pads", []):
        x, y = v(np.array([pad["pos"][0], pad["pos"][2]]))
        dr.polygon([(x, y - rad - 2), (x - rad - 1, y + rad), (x + rad + 1, y + rad)], fill=(60, 230, 255))


def plan(data, path, size=1600):
    allp = np.vstack([_arr(p, "center")[:, [0, 2]] for _, p, _, _ in _roads(data)])
    lo, hi = allp.min(0) - 40, allp.max(0) + 40
    v = View(lo, hi, (size, size))
    im = Image.new("RGB", (size, size), BG)
    dr = ImageDraw.Draw(im)
    _grid(dr, v, lo, hi, 100.0)
    _draw_roads(dr, v, data)
    lap = data["path"]
    c = _arr(lap, "center")
    step = lap["length"] / len(c)
    for s in range(0, int(lap["length"]), 200):
        x, y = v(c[int(s / step), [0, 2]])
        dr.ellipse([x - 4, y - 4, x + 4, y + 4], fill=(255, 255, 0))
        dr.text((x + 6, y - 6), "%d (y%.0f)" % (s, c[int(s / step), 1]), fill=(255, 255, 150))
    for b in data.get("branches", []):
        _nose_lines(dr, v, b)
        bc = _arr(b["path"], "center")
        x, y = v(bc[len(bc) // 2, [0, 2]])
        dr.text((x + 8, y), "%s (%s, %.0f m, saves %+.0f m)" % (b["id"], b["kind"], b["length"], b["saves"]), fill=(255, 150, 255))
    _items(dr, v, data)
    x, y = v(c[0, [0, 2]])
    dr.rectangle([x - 7, y - 7, x + 7, y + 7], outline=(255, 255, 255), width=3)
    dr.text((10, 10), "%s: lap %.0f m, %d branches; grid 100 m" % (data.get("name", ""), lap["length"],
                                                                 len(data.get("branches", []))), fill=TEXT)
    im.save(path)


def junctions(data, path, cell=520, radius=70.0):
    brs = data.get("branches", [])
    if not brs:
        return False
    im = Image.new("RGB", (cell * 2, cell * len(brs)), BG)
    lap = data["path"]
    lc = _arr(lap, "center")
    for row, b in enumerate(brs):
        p = b["path"]
        bc = _arr(p, "center")
        for col, (end, k, s_nose) in enumerate((("fork", 0, b["fork_nose_u"]), ("merge", len(bc) - 1, b["merge_nose_u"]))):
            ctr = bc[k, [0, 2]]
            lo, hi = ctr - radius, ctr + radius
            v = View(lo, hi, (cell, cell), pad=0)
            sub = Image.new("RGB", (cell, cell), BG)
            dr = ImageDraw.Draw(sub)
            _grid(dr, v, lo, hi, 10.0)
            _draw_roads(dr, v, data, outline=True)
            dr.line(v.pts(_arr(lap, "line")[:, [0, 2]]), fill=(255, 255, 0), width=1)
            dr.line(v.pts(lc[:, [0, 2]]), fill=(120, 120, 0), width=1)
            dr.line(v.pts(_arr(p, "line")[:, [0, 2]]), fill=(255, 120, 255), width=2)
            _nose_lines(dr, v, b)
            _items(dr, v, data, rad=4)
            u = s_nose if end == "fork" else b["length"] - s_nose
            dr.text((6, 6), "%s %s: nose %.0f m from the %s, side %+d" % (b["id"], end, u, end,
                                                                         b["side"] if end == "fork" else b["merge_side"]),
                    fill=TEXT)
            dr.text((6, cell - 18), "grid 10 m; yellow: lap racing line, magenta: branch line", fill=(160, 160, 160))
            im.paste(sub, (col * cell, row * cell))
    im.save(path)
    return True


def profile(data, path, size=(1600, 520)):
    lap = data["path"]
    c = _arr(lap, "center")
    n = len(c)
    step = lap["length"] / n
    ys = [c[:, 1]] + [_arr(b["path"], "center")[:, 1] for b in data.get("branches", [])]
    ymin, ymax = min(y.min() for y in ys) - 2.0, max(y.max() for y in ys) + 2.0
    W, H = size
    im = Image.new("RGB", (W, H), BG)
    dr = ImageDraw.Draw(im)

    def px(s, y):
        return 30 + (W - 60) * s / lap["length"], H - 30 - (y - ymin) / (ymax - ymin) * (H - 70)

    for s in range(0, int(lap["length"]), 100):
        dr.line([px(s, ymin), px(s, ymax)], fill=GRID)
        dr.text(px(s, ymin), "%d" % s, fill=(140, 140, 140))
    for i in range(n - 1):
        col = GAP if lap["gap"][i] else (KIND["tube"] if lap["mag"][i] > 0 else TEXT)
        dr.line([px(i * step, c[i, 1]), px((i + 1) * step, c[i + 1, 1])], fill=col, width=2)
    for b in data.get("branches", []):
        p = b["path"]
        bc, sm = _arr(p, "center"), _arr(p, "s_main")
        for k in range(len(bc) - 1):
            col = GAP if p["gap"][k] else BRANCH
            dr.line([px(sm[k], bc[k, 1]), px(sm[k + 1], bc[k + 1, 1])], fill=col, width=2)
        for u in (b["fork_nose_u"], b["merge_nose_u"]):
            k = min(int(round(u / p["step"])), len(bc) - 1)
            x, y = px(sm[k], bc[k, 1])
            dr.ellipse([x - 4, y - 4, x + 4, y + 4], outline=NOSE, width=2)
        x, y = px(sm[len(sm) // 2], bc[len(bc) // 2, 1])
        dr.text((x + 4, y - 14), b["id"], fill=(255, 150, 255))
    dr.text((10, 8), "%s: heights along the lap (y %.0f..%.0f m); branches against their lap metres (s_main), "
                     "noses circled" % (data.get("name", ""), ymin + 2, ymax - 2), fill=TEXT)
    im.save(path)


def main():
    args = sys.argv[1:]
    out = "."
    if "--out" in args:
        k = args.index("--out")
        out = args[k + 1]
        args = args[:k] + args[k + 2:]
    os.makedirs(out, exist_ok=True)
    for a in args:
        src = a if a.endswith(".json") else os.path.join(TRACKS, a + ".json")
        data = json.load(open(src))
        name = os.path.splitext(os.path.basename(src))[0]
        data.setdefault("name", name)
        plan(data, os.path.join(out, name + "_plan.png"))
        made = junctions(data, os.path.join(out, name + "_junctions.png"))
        profile(data, os.path.join(out, name + "_profile.png"))
        print("%s: plots in %s%s" % (name, out, "" if made else " (no branches: no junctions)"))


if __name__ == "__main__":
    main()
