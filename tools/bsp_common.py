"""Shared pieces of the BSP -> Godot world converters (GoldSrc and Source):
lightmap atlas packing, world glTF writing, collision dump."""
import json
import os
import struct
import numpy as np
from PIL import Image

from mdl import GLTFBuilder


def to_godot(v, scale):
    """Quake/Source units (Z up) -> Godot metres (Y up)."""
    v = np.asarray(v, np.float64)
    return np.stack([v[..., 0], v[..., 2], -v[..., 1]], axis=-1) * scale


class Atlas:
    """Shelf packer for per-face lightmaps (each padded by one replicated luxel)."""

    def __init__(self, width=2048):
        self.w = width
        self.rects = []  # (x, y, img)
        self._x = 0
        self._y = 0
        self._row_h = 0
        self.h = 0

    def add(self, img):
        """img: (h, w, 3) float32 luxels. Returns (x0, y0) of the luxel block (inside the pad)."""
        ph, pw = img.shape[0] + 2, img.shape[1] + 2
        if self._x + pw > self.w:
            self._x = 0
            self._y += self._row_h
            self._row_h = 0
        x, y = self._x, self._y
        self._x += pw
        self._row_h = max(self._row_h, ph)
        self.h = max(self.h, self._y + self._row_h)
        self.rects.append((x, y, img))
        return x + 1, y + 1

    def image(self):
        h = 1
        while h < self.h:
            h *= 2
        out = np.ones((h, self.w, 3), np.float32)
        for x, y, img in self.rects:
            p = np.pad(img, ((1, 1), (1, 1), (0, 0)), mode="edge")
            out[y:y + p.shape[0], x:x + p.shape[1]] = p
        return out


def save_lightmap(atlas_img, path, scale):
    """Store luxels / scale as 8-bit sRGB-ish PNG (shader multiplies back)."""
    v = np.clip(atlas_img / scale, 0.0, 1.0)
    v = np.power(v, 1.0 / 2.2)
    Image.fromarray((v * 255.0 + 0.5).astype(np.uint8)).save(path, optimize=True)


def write_world(out_dir, meshes, materials, lightmap_rel, extra):
    """meshes: {mat_name: {"pos": [], "nrm": [], "uv": [], "uv2": [], "idx": []}} in Godot space.
    Writes world.gltf/.bin and world.json."""
    os.makedirs(out_dir, exist_ok=True)
    b = GLTFBuilder()
    root = b.node({"name": "world", "children": []})
    for mi, (name, m) in enumerate(sorted(meshes.items())):
        if not m["idx"]:
            continue
        pos = np.array(m["pos"], np.float32)
        nrm = np.array(m["nrm"], np.float32)
        uv = np.array(m["uv"], np.float32)
        uv2 = np.array(m["uv2"], np.float32)
        idx = np.array(m["idx"], np.uint32)
        b.g["materials"].append({"name": name, "pbrMetallicRoughness": {"metallicFactor": 0.0, "roughnessFactor": 1.0}})
        prim = {"attributes": {"POSITION": b.accessor(pos, 5126, "VEC3", 34962, minmax=True),
                               "NORMAL": b.accessor(nrm, 5126, "VEC3", 34962),
                               "TEXCOORD_0": b.accessor(uv, 5126, "VEC2", 34962),
                               "TEXCOORD_1": b.accessor(uv2, 5126, "VEC2", 34962)},
                "indices": b.accessor(idx, 5125, "SCALAR", 34963),
                "material": len(b.g["materials"]) - 1}
        if m.get("col") and any(c[3] > 0.0 for c in m["col"]):
            prim["attributes"]["COLOR_0"] = b.accessor(np.array(m["col"], np.float32), 5126, "VEC4", 34962)
        b.g["meshes"].append({"name": name, "primitives": [prim]})
        b.g["nodes"][root]["children"].append(b.node({"name": "m_%d" % mi, "mesh": len(b.g["meshes"]) - 1}))
    b.save(os.path.join(out_dir, "world.gltf"))
    data = dict(extra)
    data["materials"] = materials
    data["lightmap"] = lightmap_rel
    with open(os.path.join(out_dir, "world.json"), "w") as f:
        json.dump(data, f, indent=1)


def write_collision(out_dir, groups):
    """groups: {surface_kind: (N,3,3) float32 triangles}. One .bin per kind."""
    out = {}
    for kind, tris in groups.items():
        if len(tris) == 0:
            continue
        arr = np.asarray(tris, np.float32).reshape(-1, 3)
        fn = "collision_%s.bin" % kind
        arr.tofile(os.path.join(out_dir, fn))
        out[kind] = fn
    return out
