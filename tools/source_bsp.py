"""Source engine BSP (v19-v21) reader: faces, texinfo/texdata, displacements,
LDR/HDR lightmaps (ColorRGBExp32), brush models, entities, static props."""
import io
import struct
import zipfile
import numpy as np

from goldsrc_bsp import parse_entities

L_ENTITIES, L_PLANES, L_TEXDATA, L_VERTEXES = 0, 1, 2, 3
L_TEXINFO, L_FACES, L_LIGHTING, L_EDGES, L_SURFEDGES, L_MODELS = 6, 7, 8, 12, 13, 14
L_DISPINFO, L_DISP_VERTS, L_GAME_LUMP, L_PAKFILE = 26, 33, 35, 40
L_TEXDATA_STRING_DATA, L_TEXDATA_STRING_TABLE, L_LIGHTING_HDR, L_FACES_HDR = 43, 44, 53, 58

SURF_SKY2D, SURF_SKY, SURF_TRIGGER, SURF_NODRAW, SURF_HINT, SURF_SKIP, SURF_BUMPLIGHT = 0x2, 0x4, 0x40, 0x80, 0x100, 0x200, 0x800


class SourceBSP:
    def __init__(self, path):
        self.path = path
        d = open(path, "rb").read()
        self.d = d
        ident, ver = struct.unpack_from("<4si", d, 0)
        assert ident == b"VBSP", path
        self.version = ver
        self.lumps = []
        for i in range(64):
            ofs, ln, lver, fourcc = struct.unpack_from("<iii4s", d, 8 + i * 16)
            self.lumps.append((ofs, ln, lver))
        self._read()

    def lump(self, i):
        o, l, _ = self.lumps[i]
        return self.d[o:o + l]

    def _read(self):
        self.entities = parse_entities(self.lump(L_ENTITIES).decode("latin1", "replace"))
        self.vertices = np.frombuffer(self.lump(L_VERTEXES), np.float32).reshape(-1, 3)
        self.edges = np.frombuffer(self.lump(L_EDGES), np.uint16).reshape(-1, 2)
        self.surfedges = np.frombuffer(self.lump(L_SURFEDGES), np.int32)
        p = self.lump(L_PLANES)
        self.planes = [struct.unpack_from("<4fi", p, i * 20) for i in range(len(p) // 20)]
        sd = self.lump(L_TEXDATA_STRING_DATA)
        st = np.frombuffer(self.lump(L_TEXDATA_STRING_TABLE), np.int32)
        names = []
        for o in st:
            e = sd.index(b"\0", o)
            names.append(sd[o:e].decode("latin1"))
        td = self.lump(L_TEXDATA)
        self.texdata = []
        for i in range(len(td) // 32):
            rx, ry, rz, nid, w, h, vw, vh = struct.unpack_from("<3f5i", td, i * 32)
            self.texdata.append({"name": names[nid] if nid < len(names) else "", "w": w, "h": h, "refl": (rx, ry, rz)})
        ti = self.lump(L_TEXINFO)
        self.texinfo = []
        for i in range(len(ti) // 72):
            v = struct.unpack_from("<16fii", ti, i * 72)
            self.texinfo.append({"tv": (v[0:4], v[4:8]), "lv": (v[8:12], v[12:16]), "flags": v[16], "texdata": v[17]})
        fl = self.lump(L_FACES)
        self.faces = []
        for i in range(len(fl) // 56):
            (plane, side, onnode, first, num, tex, disp, fog, s0, s1, s2, s3, light, area,
             m0, m1, z0, z1, orig, nprims, fprim, smooth) = struct.unpack_from("<HBBihhhh4Bif4iiHHI", fl, i * 56)
            self.faces.append({"plane": plane, "side": side, "first": first, "num": num, "texinfo": tex,
                               "disp": disp, "styles": (s0, s1, s2, s3), "light": light,
                               "lm_mins": (m0, m1), "lm_size": (z0, z1)})
        self.lighting = self.lump(L_LIGHTING)
        if len(self.lighting) == 0:
            self.lighting = self.lump(L_LIGHTING_HDR)
        m = self.lump(L_MODELS)
        self.models = []
        for i in range(len(m) // 48):
            v = struct.unpack_from("<9f3i", m, i * 48)
            self.models.append({"mins": v[0:3], "maxs": v[3:6], "origin": v[6:9], "first_face": v[10], "num_faces": v[11]})
        di = self.lump(L_DISPINFO)
        self.dispinfo = []
        for i in range(len(di) // 176):
            sx, sy, sz, vstart, tstart, power, mintess, smooth, contents = struct.unpack_from("<3fiiiifi", di, i * 176)
            mapface = struct.unpack_from("<H", di, i * 176 + 40)[0]
            self.dispinfo.append({"start": (sx, sy, sz), "vstart": vstart, "power": power, "face": mapface})
        dv = self.lump(L_DISP_VERTS)
        self.dispverts = np.frombuffer(dv, np.float32).reshape(-1, 5)

    def skybox_faces(self):
        """Faces of the 3D skybox (the area holding sky_camera) and the camera itself."""
        cam = next((e for e in self.entities if e.get("classname") == "sky_camera"), None)
        if cam is None:
            return set(), None
        org = np.array([float(x) for x in cam["origin"].split()])
        nodes = self.lump(5)
        nn = len(nodes) // 32
        lv = self.lumps[10][2]
        leaves = self.lump(10)
        lsize = 56 if lv == 0 else 32
        nl = len(leaves) // lsize
        n = 0
        while n >= 0:
            planenum, c0, c1 = struct.unpack_from("<iii", nodes, n * 32)
            px, py, pz, pd, _ = self.planes[planenum]
            d = org @ np.array([px, py, pz]) - pd
            n = c0 if d >= 0 else c1
        leaf = -1 - n

        def leaf_area(i):
            v = struct.unpack_from("<h", leaves, i * lsize + 6)[0]
            return v & 0x1FF

        area = leaf_area(leaf)
        lf = np.frombuffer(self.lump(16), np.uint16)
        faces = set()
        for i in range(nl):
            if leaf_area(i) != area:
                continue
            first, num = struct.unpack_from("<HH", leaves, i * lsize + 20)
            faces.update(int(x) for x in lf[first:first + num])
        # displacements are not in the leaf lists: take those inside the skybox room bounds
        if faces:
            pts = np.concatenate([self.face_verts(f) for f in faces])
            lo, hi = pts.min(0) - 64, pts.max(0) + 64
            for di in self.dispinfo:
                st = np.array(di["start"])
                if (st >= lo).all() and (st <= hi).all():
                    faces.add(di["face"])
        box = None
        if faces:
            pts = np.concatenate([self.face_verts(f) for f in faces])
            box = (pts.min(0) - 8, pts.max(0) + 8)
        return faces, {"origin": org, "scale": float(cam.get("scale", "16") or 16), "box": box}

    def face_verts(self, fi):
        f = self.faces[fi]
        idx = []
        for k in range(f["num"]):
            se = self.surfedges[f["first"] + k]
            idx.append(self.edges[se][0] if se >= 0 else self.edges[-se][1])
        return self.vertices[idx].astype(np.float64)

    def luxels(self, f, count):
        """ColorRGBExp32 -> linear float RGB (count samples) at the face's light offset."""
        o = f["light"]
        raw = np.frombuffer(self.lighting, np.uint8, count * 4, o).reshape(-1, 4).astype(np.float64)
        e = raw[:, 3].astype(np.int8).astype(np.float64)
        return raw[:, :3] * (2.0 ** e)[:, None] / 255.0

    def pakfile(self):
        data = self.lump(L_PAKFILE)
        try:
            return zipfile.ZipFile(io.BytesIO(data))
        except zipfile.BadZipFile:
            return None

    def static_props(self):
        gl = self.lump(L_GAME_LUMP)
        o_l, _, _ = self.lumps[L_GAME_LUMP]
        n = struct.unpack_from("<i", gl, 0)[0]
        for i in range(n):
            gid, flags, ver, ofs, ln = struct.unpack_from("<iHHii", gl, 4 + i * 16)
            if gid != struct.unpack("<i", b"prps")[0]:
                continue
            blob = self.d[ofs:ofs + ln]
            p = 0
            nd = struct.unpack_from("<i", blob, p)[0]
            p += 4
            names = []
            for k in range(nd):
                names.append(blob[p:p + 128].split(b"\0")[0].decode("latin1"))
                p += 128
            nl = struct.unpack_from("<i", blob, p)[0]
            p += 4 + nl * 2
            npr = struct.unpack_from("<i", blob, p)[0]
            p += 4
            if npr == 0:
                return []
            size = (len(blob) - p) // npr
            out = []
            for k in range(npr):
                q = p + k * size
                ox, oy, oz, ax, ay, az = struct.unpack_from("<6f", blob, q)
                ptype, fleaf, lcount = struct.unpack_from("<3H", blob, q + 24)
                solid, pflags = struct.unpack_from("<BB", blob, q + 30)
                skin = struct.unpack_from("<i", blob, q + 32)[0]
                fmin, fmax = struct.unpack_from("<2f", blob, q + 36)
                lo = struct.unpack_from("<3f", blob, q + 44)
                out.append({"model": names[ptype], "origin": (ox, oy, oz), "angles": (ax, ay, az), "solid": solid,
                            "skin": skin, "fade": (fmin, fmax), "light_origin": lo, "flags": pflags})
            return out
        return []
