"""Floor plan of a converted BSP world for laying out race lines: walkable
triangles coloured by height (higher floors drawn on top), steep faces dark,
a labelled 10 m grid in Godot X/Z, and optional path overlay.

usage: python floorplan.py <map_key> <out.png> [px_per_m] [ymin ymax] [path.json]
"""
import json
import os
import sys
import numpy as np
from PIL import Image, ImageDraw

ASSETS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets")


def load_tris(key):
    info = json.load(open(os.path.join(ASSETS, "maps", key, "world.json")))
    out = []
    for kind, fn in info.get("collision", {}).items():
        a = np.fromfile(os.path.join(ASSETS, "maps", key, fn), np.float32).reshape(-1, 3, 3)
        out.append(a)
    return info, np.concatenate(out)


def render(key, out, ppm=4.0, ymin=-1e9, ymax=1e9, path=None):
    info, tris = load_tris(key)
    keep = (tris[:, :, 1].mean(1) >= ymin) & (tris[:, :, 1].mean(1) <= ymax)
    tris = tris[keep]
    lo = tris.reshape(-1, 3).min(0)
    hi = tris.reshape(-1, 3).max(0)
    W = int((hi[0] - lo[0]) * ppm) + 80
    H = int((hi[2] - lo[2]) * ppm) + 80
    img = Image.new("RGB", (W, H), (20, 20, 28))
    dr = ImageDraw.Draw(img)
    n = np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])
    ln = np.linalg.norm(n, axis=1) + 1e-9
    ny = np.abs(n[:, 1]) / ln
    yc = tris[:, :, 1].mean(1)
    order = np.argsort(yc)
    y0, y1 = yc.min(), yc.max()

    def px(p):
        return (40 + (p[0] - lo[0]) * ppm, 40 + (p[2] - lo[2]) * ppm)

    for i in order:
        t = tris[i]
        pts = [px(p) for p in t]
        if ny[i] > 0.7:
            f = (yc[i] - y0) / max(y1 - y0, 1e-3)
            col = (int(40 + 200 * f), int(170 - 60 * abs(f - 0.5) * 2), int(220 - 180 * f))
            dr.polygon(pts, fill=col)
        else:
            dr.line(pts + [pts[0]], fill=(10, 10, 10), width=1)
    # grid
    for gx in range(int(np.floor(lo[0] / 10)) * 10, int(hi[0]) + 10, 10):
        x = 40 + (gx - lo[0]) * ppm
        dr.line([(x, 0), (x, H)], fill=(255, 255, 255) if gx % 50 == 0 else (90, 90, 90), width=1)
        if gx % 20 == 0:
            dr.text((x + 2, 2), str(gx), fill=(255, 255, 0))
    for gz in range(int(np.floor(lo[2] / 10)) * 10, int(hi[2]) + 10, 10):
        y = 40 + (gz - lo[2]) * ppm
        dr.line([(0, y), (W, y)], fill=(255, 255, 255) if gz % 50 == 0 else (90, 90, 90), width=1)
        if gz % 20 == 0:
            dr.text((2, y + 2), str(gz), fill=(255, 255, 0))
    for e in info.get("entities", []):
        if e.get("classname", "").startswith("info_player"):
            x, y = px(e["origin_m"])
            dr.ellipse([x - 5, y - 5, x + 5, y + 5], outline=(255, 0, 255), width=2)
    if path:
        pts = [px(p) for p in path]
        dr.line(pts + [pts[0]], fill=(255, 40, 40), width=3)
        for i, p in enumerate(pts):
            dr.text((p[0] + 3, p[1] + 3), str(i), fill=(255, 255, 255))
    img.save(out)
    print("floor heights %.1f .. %.1f m, x %.0f..%.0f z %.0f..%.0f" % (y0, y1, lo[0], hi[0], lo[2], hi[2]))


if __name__ == "__main__":
    a = sys.argv
    ppm = float(a[3]) if len(a) > 3 else 4.0
    ymin = float(a[4]) if len(a) > 5 else -1e9
    ymax = float(a[5]) if len(a) > 5 else 1e9
    path = json.load(open(a[6])) if len(a) > 6 else None
    render(a[1], a[2], ppm, ymin, ymax, path)
