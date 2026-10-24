"""GoldSrc (Half-Life 1) BSP v30 reader: faces, textures (embedded or WAD3),
lightmaps, entities, brush models. Coordinates are Quake units (Z up)."""
import os
import struct
import numpy as np

LUMPS = ["entities", "planes", "textures", "vertices", "visibility", "nodes", "texinfo", "faces",
         "lighting", "clipnodes", "leaves", "marksurfaces", "edges", "surfedges", "models"]
from steam_paths import HL1_ROOT  # noqa: E402  (env HL1_ROOT or the Steam library)


def parse_entities(text):
    ents = []
    cur = None
    i = 0
    n = len(text)
    while i < n:
        c = text[i]
        if c == "{":
            cur = {}
            i += 1
        elif c == "}":
            if cur is not None:
                ents.append(cur)
            cur = None
            i += 1
        elif c == '"':
            j = text.index('"', i + 1)
            key = text[i + 1:j]
            k = text.index('"', j + 1)
            m = text.index('"', k + 1)
            val = text[k + 1:m]
            if cur is not None:
                cur[key] = val
            i = m + 1
        else:
            i += 1
    return ents


class WAD3:
    def __init__(self, path):
        self.path = path
        d = open(path, "rb").read()
        self.d = d
        magic, n, ofs = struct.unpack_from("<4sii", d, 0)
        assert magic in (b"WAD3", b"WAD2"), path
        self.entries = {}
        for i in range(n):
            filepos, disksize, size, typ, comp, pad1, pad2, name = struct.unpack_from("<iiibbbb16s", d, ofs + i * 32)
            nm = name.split(b"\0")[0].decode("latin1").lower()
            self.entries[nm] = (filepos, size, typ)

    def miptex(self, name):
        e = self.entries.get(name.lower())
        if not e:
            return None
        return self.d[e[0]:e[0] + e[1]]


def decode_miptex(blob):
    """-> (name, w, h, RGBA uint8 array) from a miptex block that holds its pixels."""
    name, w, h, o0, o1, o2, o3 = struct.unpack_from("<16sII4I", blob, 0)
    name = name.split(b"\0")[0].decode("latin1")
    if o0 == 0:
        return name, w, h, None
    idx = np.frombuffer(blob, np.uint8, w * h, o0)
    # palette follows the last mip level: 2-byte count then 256*3
    pal_ofs = o3 + (w // 8) * (h // 8) + 2
    pal = np.frombuffer(blob, np.uint8, 768, pal_ofs).reshape(256, 3)
    rgb = pal[idx].reshape(h, w, 3)
    a = np.full((h, w, 1), 255, np.uint8)
    if name.startswith("{"):
        a[idx.reshape(h, w) == 255] = 0
    return name, w, h, np.concatenate([rgb, a], axis=2)


class BSP30:
    def __init__(self, path):
        self.path = path
        d = open(path, "rb").read()
        self.d = d
        ver = struct.unpack_from("<i", d, 0)[0]
        assert ver == 30, "not a GoldSrc BSP: %d" % ver
        self.lumps = {}
        for i, nm in enumerate(LUMPS):
            ofs, ln = struct.unpack_from("<ii", d, 4 + i * 8)
            self.lumps[nm] = (ofs, ln)
        self._read()

    def lump(self, nm):
        o, l = self.lumps[nm]
        return self.d[o:o + l]

    def _read(self):
        self.entities = parse_entities(self.lump("entities").decode("latin1", "replace"))
        v = self.lump("vertices")
        self.vertices = np.frombuffer(v, np.float32).reshape(-1, 3)
        e = self.lump("edges")
        self.edges = np.frombuffer(e, np.uint16).reshape(-1, 2)
        self.surfedges = np.frombuffer(self.lump("surfedges"), np.int32)
        p = self.lump("planes")
        self.planes = [struct.unpack_from("<4fi", p, i * 20) for i in range(len(p) // 20)]
        t = self.lump("texinfo")
        self.texinfo = []
        for i in range(len(t) // 40):
            vals = struct.unpack_from("<8fii", t, i * 40)
            self.texinfo.append({"s": vals[0:3], "so": vals[3], "t": vals[4:7], "to": vals[7], "miptex": vals[8], "flags": vals[9]})
        f = self.lump("faces")
        self.faces = []
        for i in range(len(f) // 20):
            plane, side, first, num, tex, s0, s1, s2, s3, light = struct.unpack_from("<HHiHH4Bi", f, i * 20)
            self.faces.append({"plane": plane, "side": side, "first": first, "num": num, "texinfo": tex,
                               "styles": (s0, s1, s2, s3), "light": light})
        m = self.lump("models")
        self.models = []
        for i in range(len(m) // 64):
            vals = struct.unpack_from("<9f7i", m, i * 64)
            self.models.append({"mins": vals[0:3], "maxs": vals[3:6], "origin": vals[6:9],
                                "first_face": vals[14], "num_faces": vals[15]})
        tl = self.lump("textures")
        n = struct.unpack_from("<i", tl, 0)[0]
        ofs = struct.unpack_from("<%di" % n, tl, 4)
        self.miptex = []
        for o in ofs:
            if o < 0:
                self.miptex.append({"name": "", "w": 16, "h": 16, "blob": None})
                continue
            name, w, h, o0 = struct.unpack_from("<16sIII", tl, o)
            name = name.split(b"\0")[0].decode("latin1")
            blob = tl[o:] if o0 != 0 else None
            self.miptex.append({"name": name, "w": w, "h": h, "blob": blob})
        self.lighting = self.lump("lighting")

    def face_verts(self, fi):
        f = self.faces[fi]
        idx = []
        for k in range(f["num"]):
            se = self.surfedges[f["first"] + k]
            idx.append(self.edges[se][0] if se >= 0 else self.edges[-se][1])
        return self.vertices[idx]

    def worldspawn(self):
        return self.entities[0] if self.entities else {}

    def wad_names(self):
        w = self.worldspawn().get("wad", "")
        return [os.path.basename(x.replace("\\", "/")).lower() for x in w.split(";") if x.strip()]


def load_wads(names, roots=None):
    roots = roots or [os.path.join(HL1_ROOT, "valve_hd"), os.path.join(HL1_ROOT, "valve")]
    out = []
    for n in names:
        for r in roots:
            p = os.path.join(r, n)
            if os.path.exists(p):
                out.append(WAD3(p))
                break
    return out


if __name__ == "__main__":
    import sys
    b = BSP30(sys.argv[1])
    print("faces", len(b.faces), "models", len(b.models), "entities", len(b.entities), "wads", b.wad_names())
    print("textures:", sorted(set(m["name"].lower() for m in b.miptex)))
    from collections import Counter
    print(Counter(e.get("classname") for e in b.entities).most_common(40))
    mn = b.vertices.min(0)
    mx = b.vertices.max(0)
    print("bounds", mn, mx, "size (m)", (mx - mn) * 0.0254)
