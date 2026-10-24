"""Turn Source 6-face skyboxes into equirectangular panoramas for Godot.

Face layout follows the Quake/Source MakeSkyVec convention:
rt=+X, lf=-X, bk=+Y, ft=-Y, up=+Z, dn=-Z (Source axes, via skytexorder), texture t flipped.
Half-height side faces (512x256) only cover the upper half, like the engine.
Also estimates the sun direction from the brightest sky region.
"""
import json
import os

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.normpath(os.path.join(HERE, "..", "assets"))
SKY = os.path.join(ASSETS, "sky")
W, H = 2048, 1024


def load(name, face):
    p = os.path.join(SKY, name + face + ".png")
    if not os.path.exists(p):
        return None
    return np.asarray(Image.open(p).convert("RGB"), dtype=np.float32) / 255.0


def sample(img, u, v):
    h, w, _ = img.shape
    x = np.clip(u * w - 0.5, 0, w - 1.001)
    y = np.clip(v * h - 0.5, 0, h - 1.001)
    x0 = x.astype(int)
    y0 = y.astype(int)
    fx = (x - x0)[:, None]
    fy = (y - y0)[:, None]
    return (img[y0, x0] * (1 - fx) * (1 - fy) + img[y0, x0 + 1] * fx * (1 - fy) +
            img[y0 + 1, x0] * (1 - fx) * fy + img[y0 + 1, x0 + 1] * fx * fy)


def build(name):
    faces = {f: load(name, f) for f in ("rt", "bk", "lf", "ft", "up", "dn")}
    rt = faces.get("rt")
    if rt is not None and rt.shape[0] * 2 == rt.shape[1]:
        faces["dn"] = None  # half-height skies never show their bottom face in-engine
    jj, ii = np.mgrid[0:H, 0:W]
    u = (ii + 0.5) / W
    v = (jj + 0.5) / H
    lon = (u - 0.5) * 2 * np.pi
    lat = v * np.pi
    # Godot dir: u = atan(x, -z)/(2pi) + 0.5, v = acos(y)/pi
    gx = np.sin(lat) * np.sin(lon)
    gz = -np.sin(lat) * np.cos(lon)
    gy = np.cos(lat)
    # Godot -> Source: sx = gx, sy = -gz, sz = gy
    sx, sy, sz = gx.ravel(), -gz.ravel(), gy.ravel()
    ax = np.abs(np.stack([sx, sy, sz], 1))
    major = np.argmax(ax, 1)
    out = np.zeros((len(sx), 3), np.float32)
    horizon = []
    for f, img in faces.items():
        if img is None or f in ("up", "dn"):
            continue
        horizon.append(img[-1].mean(0) if img.shape[0] < img.shape[1] else img[img.shape[0] // 2].mean(0))
    horizon = np.mean(horizon, 0) if horizon else np.array([0.5, 0.5, 0.5])
    for f, img in faces.items():
        if f == "rt":
            sel = (major == 0) & (sx > 0); d = sx; s = -sy / d; t = sz / d
        elif f == "lf":
            sel = (major == 0) & (sx <= 0); d = -sx; s = sy / d; t = sz / d
        elif f == "bk":
            sel = (major == 1) & (sy > 0); d = sy; s = sx / d; t = sz / d
        elif f == "ft":
            sel = (major == 1) & (sy <= 0); d = -sy; s = -sx / d; t = sz / d
        elif f == "up":
            sel = (major == 2) & (sz > 0); d = sz; t = -sx / d; s = -sy / d
        else:
            sel = (major == 2) & (sz <= 0); d = -sz; t = sx / d; s = -sy / d
        if not sel.any():
            continue
        ss, tt = s[sel], t[sel]
        if img is None:
            out[sel] = horizon * 0.6
            continue
        uu = (ss + 1) * 0.5
        half = img.shape[0] * 2 == img.shape[1] and f not in ("up", "dn")
        if half:
            vv = 1.0 - np.clip(tt, 0, 1)
            col = sample(img, uu, vv)
            below = tt < 0
            fade = np.clip(-tt * 3, 0, 1)[:, None]
            col = np.where(below[:, None], col * (1 - fade) + horizon * 0.55 * fade, col)
        else:
            vv = 1.0 - (tt + 1) * 0.5
            col = sample(img, uu, vv)
        out[sel] = col
    pano = (np.clip(out.reshape(H, W, 3), 0, 1) * 255).astype(np.uint8)
    Image.fromarray(pano).save(os.path.join(SKY, name + "_pano.png"))
    # sun: brightest blurred region in upper hemisphere
    small = np.asarray(Image.fromarray(pano).resize((256, 128), Image.BILINEAR), np.float32).mean(2)
    small[64:] = 0
    small[:4] = 0
    j, i = np.unravel_index(np.argmax(small), small.shape)
    su = (i + 0.5) / 256
    sv = (j + 0.5) / 128
    lon = (su - 0.5) * 2 * np.pi
    lat = sv * np.pi
    sun = [float(np.sin(lat) * np.sin(lon)), float(np.cos(lat)), float(-np.sin(lat) * np.cos(lon))]
    return {"pano": "res://assets/sky/%s_pano.png" % name, "sun_dir": sun,
            "horizon": [float(x) for x in horizon], "sun_brightness": float(small.max() / 255)}


def main():
    names = sorted({f[:-6] for f in os.listdir(SKY) if f.endswith("rt.png") and "_pano" not in f})
    meta = {}
    for n in names:
        meta[n] = build(n)
        print(n, meta[n]["sun_dir"])
    with open(os.path.join(ASSETS, "data", "skies.json"), "w") as f:
        json.dump(meta, f, indent=1)


if __name__ == "__main__":
    main()
