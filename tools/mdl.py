"""Source MDL/VVD/VTX (v44-v48) -> glTF 2.0 (.gltf + .bin) with skeleton, skins and metadata.

Coordinates: Source is Z-up, X-forward, units = inches. Output is glTF Y-up,
metres: (x, y, z)_src -> (x, z, -y) * 0.0254. Source front faces are clockwise,
so triangle winding is flipped.
"""
import json
import math
import os
import struct

import numpy as np

import keyvalues

SCALE = 0.0254


def cstr(data, off):
    e = data.index(b"\0", off)
    return data[off:e].decode("latin-1")


def conv_v(v):
    """Source vector(s) -> glTF space (metres)."""
    v = np.asarray(v, dtype=np.float64)
    return np.stack([v[..., 0], v[..., 2], -v[..., 1]], axis=-1) * SCALE


def conv_dir(v):
    v = np.asarray(v, dtype=np.float64)
    return np.stack([v[..., 0], v[..., 2], -v[..., 1]], axis=-1)


P = np.array([[1, 0, 0], [0, 0, 1], [0, -1, 0]], dtype=np.float64)


def conv_mat34(m):
    """3x4 Source matrix (rotation + translation in source units) -> 4x4 glTF matrix."""
    R = np.array(m, dtype=np.float64).reshape(3, 4)
    out = np.eye(4)
    out[:3, :3] = P @ R[:, :3] @ P.T
    out[:3, 3] = P @ R[:, 3] * SCALE
    return out


def quat_to_mat(q):
    x, y, z, w = q
    return np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ])


def mat_to_quat(m):
    t = m[0, 0] + m[1, 1] + m[2, 2]
    if t > 0:
        s = math.sqrt(t + 1.0) * 2
        w = 0.25 * s
        x = (m[2, 1] - m[1, 2]) / s
        y = (m[0, 2] - m[2, 0]) / s
        z = (m[1, 0] - m[0, 1]) / s
    elif m[0, 0] > m[1, 1] and m[0, 0] > m[2, 2]:
        s = math.sqrt(1.0 + m[0, 0] - m[1, 1] - m[2, 2]) * 2
        w = (m[2, 1] - m[1, 2]) / s
        x = 0.25 * s
        y = (m[0, 1] + m[1, 0]) / s
        z = (m[0, 2] + m[2, 0]) / s
    elif m[1, 1] > m[2, 2]:
        s = math.sqrt(1.0 + m[1, 1] - m[0, 0] - m[2, 2]) * 2
        w = (m[0, 2] - m[2, 0]) / s
        x = (m[0, 1] + m[1, 0]) / s
        y = 0.25 * s
        z = (m[1, 2] + m[2, 1]) / s
    else:
        s = math.sqrt(1.0 + m[2, 2] - m[0, 0] - m[1, 1]) * 2
        w = (m[1, 0] - m[0, 1]) / s
        x = (m[0, 2] + m[2, 0]) / s
        y = (m[1, 2] + m[2, 1]) / s
        z = 0.25 * s
    q = np.array([x, y, z, w])
    return q / np.linalg.norm(q)


class MDL:
    def __init__(self, data):
        self.d = d = data
        ident, self.version = struct.unpack_from("<4si", d, 0)
        if ident != b"IDST":
            raise ValueError("not MDL")
        self.name = cstr(d, 12)
        self.eye = struct.unpack_from("<3f", d, 80)
        self.hull_min = struct.unpack_from("<3f", d, 104)
        self.hull_max = struct.unpack_from("<3f", d, 116)
        self.flags = struct.unpack_from("<i", d, 152)[0]
        (nb, bi, nbc, bci, nhs, hsi, nla, lai, nls, lsi, alv, ei, nt, ti, ncd, cdi,
         nsr, nsf, si, nbp, bpi, nat, ati) = struct.unpack_from("<23i", d, 156)
        self.surfaceprop = cstr(d, struct.unpack_from("<i", d, 308)[0])
        kvi, kvs = struct.unpack_from("<ii", d, 312)
        self.keyvalues = d[kvi : kvi + kvs].rstrip(b"\0").decode("latin-1") if kvs else ""
        self.mass = struct.unpack_from("<f", d, 328)[0]
        self.contents = struct.unpack_from("<i", d, 332)[0]
        # bones
        self.bones = []
        for i in range(nb):
            o = bi + i * 216
            name = cstr(d, o + struct.unpack_from("<i", d, o)[0])
            parent = struct.unpack_from("<i", d, o + 4)[0]
            pos = struct.unpack_from("<3f", d, o + 32)
            quat = struct.unpack_from("<4f", d, o + 44)
            rot = struct.unpack_from("<3f", d, o + 60)
            p2b = struct.unpack_from("<12f", d, o + 96)
            bflags = struct.unpack_from("<i", d, o + 160)[0]
            self.bones.append(dict(name=name, parent=parent, pos=pos, quat=quat, rot=rot,
                                   pose_to_bone=p2b, flags=bflags))
        # textures
        self.textures = []
        for i in range(nt):
            o = ti + i * 64
            self.textures.append(cstr(d, o + struct.unpack_from("<i", d, o)[0]))
        self.cdtextures = [cstr(d, struct.unpack_from("<i", d, cdi + i * 4)[0]) for i in range(ncd)]
        self.skins = []
        for f in range(nsf):
            self.skins.append(list(struct.unpack_from("<%dh" % nsr, d, si + f * nsr * 2)))
        # attachments
        self.attachments = []
        for i in range(nat):
            o = ati + i * 92
            name = cstr(d, o + struct.unpack_from("<i", d, o)[0])
            bone = struct.unpack_from("<i", d, o + 8)[0]
            m = struct.unpack_from("<12f", d, o + 12)
            self.attachments.append(dict(name=name, bone=bone, local=m))
        # body parts
        self.bodyparts = []
        for i in range(nbp):
            o = bpi + i * 16
            bname = cstr(d, o + struct.unpack_from("<i", d, o)[0])
            nm, base, mi = struct.unpack_from("<iii", d, o + 4)
            models = []
            for j in range(nm):
                mo = o + mi + j * 148
                mname = d[mo : mo + 64].split(b"\0")[0].decode("latin-1")
                (mtype,) = struct.unpack_from("<i", d, mo + 64)
                (brad,) = struct.unpack_from("<f", d, mo + 68)
                nmesh, meshi, nverts, vidx, tidx, natt, atti, neye, eyei = struct.unpack_from("<9i", d, mo + 72)
                meshes = []
                for k in range(nmesh):
                    me = mo + meshi + k * 116
                    mat, mdlidx, mnv, mvo, nflex, flexi, mattype, matparam, meshid = struct.unpack_from("<9i", d, me)
                    meshes.append(dict(material=mat, numverts=mnv, vertexoffset=mvo,
                                       materialtype=mattype, materialparam=matparam))
                eyes = []
                for k in range(neye):
                    eo = mo + eyei + k * 172
                    ename = cstr(d, eo + struct.unpack_from("<i", d, eo)[0])
                    ebone = struct.unpack_from("<i", d, eo + 4)[0]
                    org = struct.unpack_from("<3f", d, eo + 8)
                    zoff, radius = struct.unpack_from("<ff", d, eo + 20)
                    up = struct.unpack_from("<3f", d, eo + 28)
                    fwd = struct.unpack_from("<3f", d, eo + 40)
                    tex = struct.unpack_from("<i", d, eo + 52)[0]
                    iris_scale = struct.unpack_from("<f", d, eo + 60)[0]
                    eyes.append(dict(name=ename, bone=ebone, org=org, zoffset=zoff, radius=radius,
                                     up=up, forward=fwd, texture=tex, iris_scale=iris_scale))
                models.append(dict(name=mname, numverts=nverts, vertexstart=vidx // 48,
                                   meshes=meshes, eyeballs=eyes))
            self.bodyparts.append(dict(name=bname, base=base, models=models))

    def bone_world(self):
        """Model-space 4x4 (Source units) for each bone from pos/quat chain."""
        out = []
        for b in self.bones:
            m = np.eye(4)
            m[:3, :3] = quat_to_mat(b["quat"])
            m[:3, 3] = b["pos"]
            if b["parent"] >= 0:
                m = out[b["parent"]] @ m
            out.append(m)
        return out


def read_vvd(data):
    ident, ver, chk, nlods = struct.unpack_from("<4siii", data, 0)
    lodverts = struct.unpack_from("<8i", data, 16)
    nfix, fixstart, vstart, tstart = struct.unpack_from("<4i", data, 48)
    total = lodverts[0]
    vt = np.dtype([("w", "<f4", 3), ("b", "u1", 3), ("nb", "u1"), ("pos", "<f4", 3),
                   ("nrm", "<f4", 3), ("uv", "<f4", 2)])
    nall = (tstart - vstart) // 48 if tstart > vstart else total
    verts = np.frombuffer(data, dtype=vt, count=nall, offset=vstart)
    if nfix:
        parts = []
        for i in range(nfix):
            lod, src, n = struct.unpack_from("<3i", data, fixstart + i * 12)
            if lod >= 0:
                parts.append(verts[src : src + n])
        verts = np.concatenate(parts)
    else:
        verts = verts[:total]
    return verts


def read_vtx(data, mdl):
    """Returns indices per [bodypart][model][mesh] (LOD 0) as arrays of mesh-local vertex ids."""
    ver, vcs, mbs, mbt, mbv, chk, nlods, mrl, nbp, bpo = struct.unpack_from("<iiHHiiiiii", data, 0)
    sg_size = 25
    out = []
    for i in range(nbp):
        bo = bpo + i * 8
        nm, mo = struct.unpack_from("<ii", data, bo)
        bp = []
        for j in range(nm):
            mdo = bo + mo + j * 8
            nl, lo = struct.unpack_from("<ii", data, mdo)
            lodo = mdo + lo  # LOD 0
            nmesh, meo, sw = struct.unpack_from("<iif", data, lodo)
            meshes = []
            for k in range(nmesh):
                mho = lodo + meo + k * 9
                nsg, sgo = struct.unpack_from("<ii", data, mho)
                tri_ids = []
                for g in range(nsg):
                    go = mho + sgo + g * sg_size
                    nv, vo, ni, io, ns, so = struct.unpack_from("<6i", data, go)
                    vids = np.frombuffer(data, dtype=np.dtype([("bw", "u1", 3), ("nb", "u1"), ("id", "<u2"), ("bid", "i1", 3)]),
                                         count=nv, offset=go + vo)["id"].astype(np.int64)
                    idx = np.frombuffer(data, dtype="<u2", count=ni, offset=go + io).astype(np.int64)
                    for s in range(ns):
                        st = go + so + s * 27
                        sni, sio, snv, svo, snb, sflags = struct.unpack_from("<iiiihB", data, st)
                        sidx = idx[sio : sio + sni]
                        if sflags & 2:  # tristrip
                            tris = []
                            for t in range(len(sidx) - 2):
                                a, b, c = sidx[t], sidx[t + 1], sidx[t + 2]
                                if t & 1:
                                    a, b = b, a
                                tris.extend([a, b, c])
                            sidx = np.array(tris, dtype=np.int64)
                        tri_ids.append(vids[sidx])
                meshes.append(np.concatenate(tri_ids) if tri_ids else np.zeros(0, np.int64))
            bp.append(meshes)
        out.append(bp)
    return out


class GLTFBuilder:
    def __init__(self):
        self.g = {"asset": {"version": "2.0", "generator": "hl2kart srcmdl"}, "scenes": [{"nodes": [0]}],
                  "scene": 0, "nodes": [], "meshes": [], "materials": [], "textures": [], "images": [],
                  "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}],
                  "accessors": [], "bufferViews": [], "buffers": []}
        self.bin = bytearray()
        self.images = {}

    def view(self, arr, target=None):
        while len(self.bin) % 4:
            self.bin.append(0)
        off = len(self.bin)
        b = arr.tobytes()
        self.bin += b
        bv = {"buffer": 0, "byteOffset": off, "byteLength": len(b)}
        if target:
            bv["target"] = target
        self.g["bufferViews"].append(bv)
        return len(self.g["bufferViews"]) - 1

    def accessor(self, arr, ctype, typ, target=None, minmax=False, normalized=False):
        bv = self.view(np.ascontiguousarray(arr), target)
        acc = {"bufferView": bv, "componentType": ctype, "count": int(arr.shape[0]), "type": typ}
        if normalized:
            acc["normalized"] = True
        if minmax:
            acc["min"] = [float(x) for x in arr.min(axis=0)]
            acc["max"] = [float(x) for x in arr.max(axis=0)]
        self.g["accessors"].append(acc)
        return len(self.g["accessors"]) - 1

    def image(self, uri):
        if uri in self.images:
            return self.images[uri]
        self.g["images"].append({"uri": uri})
        self.g["textures"].append({"source": len(self.g["images"]) - 1, "sampler": 0})
        self.images[uri] = len(self.g["textures"]) - 1
        return self.images[uri]

    def node(self, n):
        self.g["nodes"].append(n)
        return len(self.g["nodes"]) - 1

    def save(self, path_gltf):
        base = os.path.splitext(os.path.basename(path_gltf))[0]
        self.g["buffers"] = [{"uri": base + ".bin", "byteLength": len(self.bin)}]
        for k in ("textures", "images", "materials"):
            if not self.g[k]:
                del self.g[k]
        if "textures" not in self.g:
            self.g.pop("samplers", None)
        with open(path_gltf, "w") as f:
            json.dump(self.g, f, indent=0)
        with open(os.path.splitext(path_gltf)[0] + ".bin", "wb") as f:
            f.write(self.bin)


def gltf_material(b, matinfo, rel_to_assets):
    """Build a glTF material dict from MaterialLib info."""
    m = {"name": matinfo["name"], "extras": {"source": {k: v for k, v in matinfo.items()
                                                      if k not in ("params",)}}}
    pbr = {"metallicFactor": 0.0, "roughnessFactor": 0.55 if matinfo.get("phong") else 0.9}
    if "albedo" in matinfo:
        pbr["baseColorTexture"] = {"index": b.image(rel_to_assets(matinfo["albedo"]))}
    col = matinfo.get("color")
    if col:
        try:
            c = [float(x) for x in col.strip("[]{} ").split()]
            if max(c) > 1.0:
                c = [x / 255.0 for x in c]
            pbr["baseColorFactor"] = c[:3] + [1.0]
        except ValueError:
            pass
    m["pbrMetallicRoughness"] = pbr
    if "normal" in matinfo:
        m["normalTexture"] = {"index": b.image(rel_to_assets(matinfo["normal"]))}
    if matinfo.get("translucent") or matinfo.get("additive"):
        m["alphaMode"] = "BLEND"
    elif matinfo.get("alphatest"):
        m["alphaMode"] = "MASK"
        m["alphaCutoff"] = float(matinfo.get("alphatestreference", 0.5) or 0.5)
    if matinfo.get("nocull"):
        m["doubleSided"] = True
    if matinfo["shader"] in ("unlitgeneric", "sprite", "eyerefract") or matinfo.get("additive"):
        m.setdefault("extensions", {})["KHR_materials_unlit"] = {}
        b.g.setdefault("extensionsUsed", [])
        if "KHR_materials_unlit" not in b.g["extensionsUsed"]:
            b.g["extensionsUsed"].append("KHR_materials_unlit")
    return m


def convert(fs, matlib, mdl_path, out_root, bodygroups=None, skin=0, force=False):
    """Convert models/xxx.mdl -> <out_root>/models/xxx.gltf. Returns metadata dict."""
    mdl_path = mdl_path.lower().replace("\\", "/")
    base = mdl_path[:-4]
    out_gltf = os.path.join(out_root, base + ".gltf")
    out_json = os.path.join(out_root, base + ".json")
    if not force and os.path.exists(out_gltf) and os.path.exists(out_json):
        with open(out_json) as f:
            return json.load(f)
    data = fs.read(mdl_path)
    if data is None:
        raise FileNotFoundError(mdl_path)
    mdl = MDL(data)
    vvd = read_vvd(fs.read(base + ".vvd"))
    vtxdata = fs.read(base + ".dx90.vtx") or fs.read(base + ".vtx") or fs.read(base + ".dx80.vtx")
    vtx = read_vtx(vtxdata, mdl)

    os.makedirs(os.path.dirname(out_gltf), exist_ok=True)
    gdir = os.path.dirname(out_gltf)

    def rel_to_assets(rel):
        return os.path.relpath(os.path.join(out_root, rel), gdir).replace("\\", "/")

    # materials
    skin_tab = mdl.skins[skin] if mdl.skins and skin < len(mdl.skins) else list(range(len(mdl.textures)))
    mat_infos = []
    for ti, tname in enumerate(mdl.textures):
        full = matlib.resolve(tname, mdl.cdtextures)
        mat_infos.append(matlib.material(full) if full else {"name": tname, "shader": "missing"})
    skins_named = []
    for fam in mdl.skins:
        row = []
        for ref in fam:
            if ref < len(mdl.textures):
                full = matlib.resolve(mdl.textures[ref], mdl.cdtextures)
                if full:
                    matlib.material(full)
                row.append(full or mdl.textures[ref])
        skins_named.append(row)

    b = GLTFBuilder()
    root = b.node({"name": os.path.basename(base), "children": []})

    world = mdl.bone_world()
    skinned = len(mdl.bones) > 1
    joint_nodes = []
    if skinned:
        first = len(b.g["nodes"])
        for i, bone in enumerate(mdl.bones):
            t = conv_v(bone["pos"])
            q = bone["quat"]
            qg = [q[0], q[2], -q[1], q[3]]
            joint_nodes.append(b.node({"name": bone["name"], "translation": [float(x) for x in t],
                                       "rotation": [float(x) for x in qg]}))
        for i, bone in enumerate(mdl.bones):
            if bone["parent"] >= 0:
                b.g["nodes"][joint_nodes[bone["parent"]]].setdefault("children", []).append(joint_nodes[i])
            else:
                b.g["nodes"][root]["children"].append(joint_nodes[i])
        ibm = np.zeros((len(mdl.bones), 4, 4), dtype=np.float32)
        for i, bone in enumerate(mdl.bones):
            M = conv_mat34(bone["pose_to_bone"])
            ibm[i] = M.T  # column-major
        ibm_acc = b.accessor(ibm.reshape(-1, 16), 5126, "MAT4")
        b.g["skins"] = [{"joints": joint_nodes, "inverseBindMatrices": ibm_acc,
                         "skeleton": joint_nodes[0]}]

    mat_index = {}
    eyes_meta = []
    bodygroups = bodygroups or {}
    for bpi, bp in enumerate(mdl.bodyparts):
        choice = bodygroups.get(bp["name"], 0)
        if choice >= len(bp["models"]):
            choice = 0
        model = bp["models"][choice]
        if not model["meshes"]:
            continue
        prims = []
        for mi, mesh in enumerate(model["meshes"]):
            ids = vtx[bpi][choice][mi]
            if len(ids) == 0:
                continue
            gidx = model["vertexstart"] + mesh["vertexoffset"] + ids
            uniq, inv = np.unique(gidx, return_inverse=True)
            v = vvd[uniq]
            pos = conv_v(v["pos"]).astype(np.float32)
            nrm = conv_dir(v["nrm"]).astype(np.float32)
            nl = np.linalg.norm(nrm, axis=1, keepdims=True)
            nrm = (nrm / np.where(nl > 0, nl, 1)).astype(np.float32)
            uv = v["uv"].astype(np.float32)
            tris = inv.reshape(-1, 3)[:, [0, 2, 1]].reshape(-1)
            attrs = {
                "POSITION": b.accessor(pos, 5126, "VEC3", 34962, minmax=True),
                "NORMAL": b.accessor(nrm, 5126, "VEC3", 34962),
                "TEXCOORD_0": b.accessor(uv, 5126, "VEC2", 34962),
            }
            if skinned:
                bones = v["b"].astype(np.uint16)
                w = v["w"].astype(np.float32).copy()
                nb = v["nb"]
                for c in range(3):
                    w[nb <= c, c] = 0.0
                    bones[nb <= c, c] = 0
                s = w.sum(axis=1, keepdims=True)
                w = w / np.where(s > 0, s, 1)
                j4 = np.zeros((len(v), 4), np.uint16)
                j4[:, :3] = bones
                w4 = np.zeros((len(v), 4), np.float32)
                w4[:, :3] = w
                attrs["JOINTS_0"] = b.accessor(j4, 5123, "VEC4", 34962)
                attrs["WEIGHTS_0"] = b.accessor(w4, 5126, "VEC4", 34962)
            # eyeballs: project the iris onto a second UV set like the Eyes shader does
            if mesh["materialtype"] == 1 and mesh["materialparam"] < len(model["eyeballs"]):
                eb = model["eyeballs"][mesh["materialparam"]]
                bw = world[eb["bone"]]
                org = (bw @ np.array(list(eb["org"]) + [1.0]))[:3]
                up = bw[:3, :3] @ np.array(eb["up"])
                fwd = bw[:3, :3] @ np.array(eb["forward"])
                right = np.cross(fwd, up)
                right /= np.linalg.norm(right) or 1
                up = np.cross(right, fwd)
                up /= np.linalg.norm(up) or 1
                rel = v["pos"].astype(np.float64) - org
                s = eb["iris_scale"]
                u2 = 0.5 + (rel @ right) * s
                v2 = 0.5 - (rel @ up) * s
                attrs["TEXCOORD_1"] = b.accessor(np.stack([u2, v2], 1).astype(np.float32), 5126, "VEC2", 34962)
                eyes_meta.append(dict(name=eb["name"], radius=eb["radius"], iris_scale=s,
                                      org=[float(x) for x in conv_v(org)]))
            ind = tris.astype(np.uint32 if len(uniq) > 65535 else np.uint16)
            iacc = b.accessor(ind, 5125 if ind.dtype == np.uint32 else 5123, "SCALAR", 34963)
            tex = skin_tab[mesh["material"]] if mesh["material"] < len(skin_tab) else mesh["material"]
            if tex not in mat_index:
                info = mat_infos[tex] if tex < len(mat_infos) else {"name": "missing", "shader": "missing"}
                if mesh["materialtype"] == 1:
                    info = dict(info)
                    info["eyeball"] = True
                b.g["materials"].append(gltf_material(b, info, rel_to_assets))
                mat_index[tex] = len(b.g["materials"]) - 1
            prims.append({"attributes": attrs, "indices": iacc, "material": mat_index[tex]})
        if not prims:
            continue
        b.g["meshes"].append({"name": bp["name"], "primitives": prims})
        n = {"name": "body_" + bp["name"], "mesh": len(b.g["meshes"]) - 1}
        if skinned:
            n["skin"] = 0
        b.g["nodes"][root]["children"].append(b.node(n))

    b.save(out_gltf)

    def att_world(a):
        m = np.eye(4)
        m[:3, :] = np.array(a["local"]).reshape(3, 4)
        w = world[a["bone"]] @ m if a["bone"] < len(world) else m
        g = np.eye(4)
        g[:3, :3] = P @ w[:3, :3] @ P.T
        g[:3, 3] = P @ w[:3, 3] * SCALE
        return g

    meta = {
        "name": mdl.name, "version": mdl.version, "source": mdl_path,
        "hull_min": [float(x) for x in conv_v(mdl.hull_min)],
        "hull_max": [float(x) for x in conv_v(mdl.hull_max)],
        "mass": mdl.mass, "surfaceprop": mdl.surfaceprop, "keyvalues": mdl.keyvalues,
        "bones": [b_["name"] for b_ in mdl.bones],
        "bone_parents": [b_["parent"] for b_ in mdl.bones],
        "attachments": {a["name"]: {"bone": mdl.bones[a["bone"]]["name"] if a["bone"] < len(mdl.bones) else "",
                                    "origin": [float(x) for x in att_world(a)[:3, 3]],
                                    "basis": [[float(x) for x in r] for r in att_world(a)[:3, :3]]}
                        for a in mdl.attachments},
        "bodyparts": [{"name": bp["name"], "models": [m["name"] for m in bp["models"]]} for bp in mdl.bodyparts],
        "skins": skins_named,
        "materials": [mi["name"] for mi in mat_infos],
        "eyes": eyes_meta,
    }
    # aabb from actual vertex positions (hull in mdl can be loose)
    try:
        allp = conv_v(vvd["pos"])
        meta["aabb_min"] = [float(x) for x in allp.min(axis=0)]
        meta["aabb_max"] = [float(x) for x in allp.max(axis=0)]
    except Exception:  # noqa
        pass
    with open(out_json, "w") as f:
        json.dump(meta, f, indent=1)
    return meta
