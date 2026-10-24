"""GoldSrc (Half-Life 1) studio model v10 -> glTF with skeleton, for HL1 characters.

Vertices are stored per-bone in bone space; the bind pose is built from each
bone's default value[6] (position + Euler roll/pitch/yaw, HLSDK AngleQuaternion).
Textures are 8-bit paletted (palette follows the pixels); palette index 255 is
transparent on "masked" textures. Biped bone names are renamed to the
ValveBiped convention so the game's posing code works unchanged.
"""
import json
import math
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import numpy as np
from PIL import Image

from mdl import GLTFBuilder, P, SCALE, conv_dir, conv_v, mat_to_quat

NF_CHROME = 2
NF_FULLBRIGHT = 4
NF_ADDITIVE = 32
NF_MASKED = 64

BIPED_RENAME = {
    "Bip01": "ValveBiped.Bip01",
    "Bip01 Pelvis": "ValveBiped.Bip01_Pelvis",
    "Bip01 Spine": "ValveBiped.Bip01_Spine",
    "Bip01 Spine1": "ValveBiped.Bip01_Spine1",
    "Bip01 Spine2": "ValveBiped.Bip01_Spine2",
    "Bip01 Spine3": "ValveBiped.Bip01_Spine4",
    "Bip01 Neck": "ValveBiped.Bip01_Neck1",
    "Bip01 Head": "ValveBiped.Bip01_Head1",
    "Bip01 L Arm": "ValveBiped.Bip01_L_Clavicle",
    "Bip01 L Arm1": "ValveBiped.Bip01_L_UpperArm",
    "Bip01 L Arm2": "ValveBiped.Bip01_L_Forearm",
    "Bip01 L Hand": "ValveBiped.Bip01_L_Hand",
    "Bip01 R Arm": "ValveBiped.Bip01_R_Clavicle",
    "Bip01 R Arm1": "ValveBiped.Bip01_R_UpperArm",
    "Bip01 R Arm2": "ValveBiped.Bip01_R_Forearm",
    "Bip01 R Hand": "ValveBiped.Bip01_R_Hand",
    "Bip01 L Leg": "ValveBiped.Bip01_L_Thigh",
    "Bip01 L Leg1": "ValveBiped.Bip01_L_Calf",
    "Bip01 L Foot": "ValveBiped.Bip01_L_Foot",
    "Bip01 L Toe0": "ValveBiped.Bip01_L_Toe0",
    "Bip01 R Leg": "ValveBiped.Bip01_R_Thigh",
    "Bip01 R Leg1": "ValveBiped.Bip01_R_Calf",
    "Bip01 R Foot": "ValveBiped.Bip01_R_Foot",
    "Bip01 R Toe0": "ValveBiped.Bip01_R_Toe0",
}


def rename_bone(n):
    """Old Character Studio names via the table, newer biped names map 1:1 onto ValveBiped."""
    if n in BIPED_RENAME:
        return BIPED_RENAME[n]
    if n.startswith("Bip01 "):
        return "ValveBiped.Bip01_" + n[6:].replace(" ", "_")
    return n.replace(" ", "_")


def cstr(b):
    return b.split(b"\0")[0].decode("latin-1")


def angle_quat(a):
    """HLSDK AngleQuaternion: a = (roll X, pitch Y, yaw Z) radians -> (x, y, z, w)."""
    sy, cy = math.sin(a[2] * 0.5), math.cos(a[2] * 0.5)
    sp, cp = math.sin(a[1] * 0.5), math.cos(a[1] * 0.5)
    sr, cr = math.sin(a[0] * 0.5), math.cos(a[0] * 0.5)
    return (sr * cp * cy - cr * sp * sy, cr * sp * cy + sr * cp * sy,
            cr * cp * sy - sr * sp * cy, cr * cp * cy + sr * sp * sy)


def quat_mat(q):
    x, y, z, w = q
    return np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ])


class GoldSrcModel:
    def __init__(self, data, tex_data=None):
        d = self.d = data
        ident, ver = struct.unpack_from("<4si", d, 0)
        if ident != b"IDST" or ver != 10:
            raise ValueError("not a GoldSrc v10 model")
        self.name = cstr(d[8:72])
        self.eye = struct.unpack_from("<3f", d, 76)
        (self.numbones, self.boneindex, _, _, _, _, _, _, _, _,
         self.numtex, self.texindex, self.texdataindex, self.numskinref, self.numskinfam, self.skinindex,
         self.numbodyparts, self.bodypartindex, self.numatt, self.attindex) = struct.unpack_from("<20i", d, 140)
        self.bones = []
        for i in range(self.numbones):
            o = self.boneindex + i * 112
            name = cstr(d[o:o + 32])
            parent = struct.unpack_from("<i", d, o + 32)[0]
            value = struct.unpack_from("<6f", d, o + 64)
            self.bones.append({"name": name, "parent": parent, "value": value})
        t = d
        tnum, tidx = self.numtex, self.texindex
        if self.numtex == 0 and tex_data:
            # textures live in the companion <name>T.mdl
            t = tex_data
            tnum, tidx = struct.unpack_from("<2i", t, 180)
            self.numskinref, self.numskinfam, self.skinindex = struct.unpack_from("<3i", t, 192)
        self.tex_src = t
        self.textures = []
        for i in range(tnum):
            o = tidx + i * 80
            name = cstr(t[o:o + 64])
            flags, w, h, pix = struct.unpack_from("<4i", t, o + 64)
            self.textures.append({"name": name, "flags": flags, "w": w, "h": h, "pix": pix})
        self.skins = []
        for f in range(self.numskinfam):
            self.skins.append(list(struct.unpack_from("<%dh" % self.numskinref, t, self.skinindex + f * self.numskinref * 2)))
        self.bodyparts = []
        for i in range(self.numbodyparts):
            o = self.bodypartindex + i * 76
            bname = cstr(d[o:o + 64])
            nm, base, mi = struct.unpack_from("<3i", d, o + 64)
            models = []
            for j in range(nm):
                mo = mi + j * 112
                mname = cstr(d[mo:mo + 64])
                nmesh, meshi, nverts, vinfo, vidx, nnorms, ninfo, nidx = struct.unpack_from("<8i", d, mo + 72)
                models.append({"name": mname, "nmesh": nmesh, "meshi": meshi, "nverts": nverts, "vinfo": vinfo,
                               "vidx": vidx, "nnorms": nnorms, "ninfo": ninfo, "nidx": nidx})
            self.bodyparts.append({"name": bname, "models": models})
        self.attachments = []
        for i in range(self.numatt):
            o = self.attindex + i * 88
            name = cstr(d[o:o + 32])
            bone = struct.unpack_from("<i", d, o + 36)[0]
            org = struct.unpack_from("<3f", d, o + 40)
            self.attachments.append({"name": name, "bone": bone, "org": org})

    def bone_world(self):
        out = []
        for b in self.bones:
            m = np.eye(4)
            m[:3, :3] = quat_mat(angle_quat(b["value"][3:6]))
            m[:3, 3] = b["value"][0:3]
            if b["parent"] >= 0:
                m = out[b["parent"]] @ m
            out.append(m)
        return out

    def texture_image(self, i):
        t = self.textures[i]
        w, h = t["w"], t["h"]
        src = self.tex_src
        idx = np.frombuffer(src, dtype=np.uint8, count=w * h, offset=t["pix"]).reshape(h, w)
        pal = np.frombuffer(src, dtype=np.uint8, count=768, offset=t["pix"] + w * h).reshape(256, 3)
        rgb = pal[idx]
        a = np.full((h, w), 255, np.uint8)
        if t["flags"] & NF_MASKED:
            a[idx == 255] = 0
        return Image.fromarray(np.dstack([rgb, a]), "RGBA"), bool(t["flags"] & NF_MASKED)


def convert(src_path, out_key, assets_root, bodygroups=None, face_fix=0.0):
    """Convert a GoldSrc .mdl (and its T.mdl textures if separate) into assets/models/<out_key>.gltf."""
    with open(src_path, "rb") as f:
        data = f.read()
    tpath = src_path[:-4] + "T.mdl"
    if not os.path.exists(tpath):
        tpath = src_path[:-4] + "t.mdl"
    tex_data = open(tpath, "rb").read() if os.path.exists(tpath) else None
    m = GoldSrcModel(data, tex_data)
    world = m.bone_world()
    # GoldSrc models face +X; turn them to face Source -Y like HL2 characters
    rz = np.eye(4)
    c, s = math.cos(math.radians(face_fix)), math.sin(math.radians(face_fix))
    rz[:3, :3] = [[c, -s, 0], [s, c, 0], [0, 0, 1]]
    world = [rz @ w for w in world]
    names = [rename_bone(b_["name"]) for b_ in m.bones]

    out_gltf = os.path.join(assets_root, "models", out_key + ".gltf")
    os.makedirs(os.path.dirname(out_gltf), exist_ok=True)
    gdir = os.path.dirname(out_gltf)
    tex_dir = os.path.join(assets_root, "materials", "goldsrc", out_key)
    os.makedirs(tex_dir, exist_ok=True)

    b = GLTFBuilder()
    root = b.node({"name": os.path.basename(out_key), "children": []})
    joints = []
    for i, bone in enumerate(m.bones):
        local = world[i] if bone["parent"] < 0 else np.linalg.inv(world[bone["parent"]]) @ world[i]
        t = conv_v(local[:3, 3])
        q = mat_to_quat(P @ local[:3, :3] @ P.T)
        joints.append(b.node({"name": names[i], "translation": [float(x) for x in t], "rotation": [float(x) for x in q]}))
    for i, bone in enumerate(m.bones):
        if bone["parent"] >= 0:
            b.g["nodes"][joints[bone["parent"]]].setdefault("children", []).append(joints[i])
        else:
            b.g["nodes"][root]["children"].append(joints[i])
    ibm = np.zeros((len(m.bones), 4, 4), np.float32)
    for i in range(len(m.bones)):
        g = np.eye(4)
        g[:3, :3] = P @ world[i][:3, :3] @ P.T
        g[:3, 3] = P @ world[i][:3, 3] * SCALE
        ibm[i] = np.linalg.inv(g).T
    b.g["skins"] = [{"joints": joints, "inverseBindMatrices": b.accessor(ibm.reshape(-1, 16), 5126, "MAT4"),
                     "skeleton": joints[0]}]

    skin = m.skins[0] if m.skins else list(range(len(m.textures)))
    mat_index = {}
    mats_meta = {}
    bodygroups = bodygroups or {}
    d = m.d
    all_pos = []
    for bp in m.bodyparts:
        choice = min(bodygroups.get(bp["name"], 0), len(bp["models"]) - 1)
        mod = bp["models"][choice]
        if mod["nmesh"] == 0:
            continue
        verts = np.frombuffer(d, "<f4", mod["nverts"] * 3, mod["vidx"]).reshape(-1, 3).astype(np.float64)
        vbone = np.frombuffer(d, np.uint8, mod["nverts"], mod["vinfo"])
        norms = np.frombuffer(d, "<f4", mod["nnorms"] * 3, mod["nidx"]).reshape(-1, 3).astype(np.float64)
        nbone = np.frombuffer(d, np.uint8, mod["nnorms"], mod["ninfo"])
        wv = np.array([(world[vbone[i]] @ np.append(verts[i], 1.0))[:3] for i in range(len(verts))])
        wn = np.array([world[nbone[i]][:3, :3] @ norms[i] for i in range(len(norms))])
        prims = []
        for k in range(mod["nmesh"]):
            mo = mod["meshi"] + k * 20
            numtris, triidx, skinref, _, _ = struct.unpack_from("<5i", d, mo)
            ti = skin[skinref] if skinref < len(skin) else skinref
            tex = m.textures[ti]
            tw, th = tex["w"], tex["h"]
            corners = []  # (vertidx, normidx, s, t)
            tris = []
            p = triidx
            while True:
                n = struct.unpack_from("<h", d, p)[0]
                p += 2
                if n == 0:
                    break
                fan = n < 0
                n = abs(n)
                cmd = [struct.unpack_from("<4h", d, p + 8 * j) for j in range(n)]
                p += 8 * n
                base = len(corners)
                corners.extend(cmd)
                for j in range(2, n):
                    if fan:
                        a, bb, cc = base, base + j - 1, base + j
                    elif j % 2 == 0:
                        a, bb, cc = base + j - 2, base + j - 1, base + j
                    else:
                        a, bb, cc = base + j - 1, base + j - 2, base + j
                    tris.append((a, cc, bb))  # GoldSrc front faces are clockwise
            if not tris:
                continue
            cv = np.array([c_[0] for c_ in corners])
            cn = np.array([c_[1] for c_ in corners])
            st = np.array([[c_[2] / tw, c_[3] / th] for c_ in corners], np.float32)
            pos = conv_v(wv[cv]).astype(np.float32)
            nrm = conv_dir(wn[cn])
            nrm = (nrm / np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-9)).astype(np.float32)
            all_pos.append(pos)
            jn = np.zeros((len(cv), 4), np.uint16)
            jn[:, 0] = vbone[cv]
            wt = np.zeros((len(cv), 4), np.float32)
            wt[:, 0] = 1.0
            if ti not in mat_index:
                img, masked = m.texture_image(ti)
                png = os.path.join(tex_dir, os.path.splitext(tex["name"])[0].lower() + ".png")
                img.save(png)
                uri = os.path.relpath(png, gdir).replace("\\", "/")
                b.image(uri)
                mname = "goldsrc/%s/%s" % (out_key, os.path.splitext(tex["name"])[0].lower())
                mat = {"name": mname, "pbrMetallicRoughness": {"metallicFactor": 0.0, "roughnessFactor": 0.9,
                                                                "baseColorTexture": {"index": b.images[uri]}}}
                if masked:
                    mat["alphaMode"] = "MASK"
                    mat["alphaCutoff"] = 0.5
                b.g["materials"].append(mat)
                mat_index[ti] = len(b.g["materials"]) - 1
                rel_png = os.path.relpath(png, assets_root).replace("\\", "/")
                mats_meta[mname] = {"name": mname, "shader": "vertexlitgeneric", "albedo": rel_png,
                                    "albedo_alpha": masked, "halflambert": True,
                                    "alphatest": masked, "selfillum": bool(tex["flags"] & NF_FULLBRIGHT)}
            ind = np.array(tris, np.uint32).reshape(-1)
            attrs = {"POSITION": b.accessor(pos, 5126, "VEC3", 34962, minmax=True),
                     "NORMAL": b.accessor(nrm, 5126, "VEC3", 34962),
                     "TEXCOORD_0": b.accessor(st, 5126, "VEC2", 34962),
                     "JOINTS_0": b.accessor(jn, 5123, "VEC4", 34962),
                     "WEIGHTS_0": b.accessor(wt, 5126, "VEC4", 34962)}
            prims.append({"attributes": attrs, "indices": b.accessor(ind, 5125, "SCALAR", 34963), "material": mat_index[ti]})
        if prims:
            b.g["meshes"].append({"name": bp["name"], "primitives": prims})
            b.g["nodes"][root]["children"].append(b.node({"name": "body_" + bp["name"], "mesh": len(b.g["meshes"]) - 1, "skin": 0}))
    b.save(out_gltf)
    eye = np.array(conv_v((rz @ np.append(m.eye, 1.0))[:3]), dtype=float)
    # player models leave eyeposition at 0; take the eyes from the head bone instead
    if "ValveBiped.Bip01_Head1" in names:
        head = conv_v(world[names.index("ValveBiped.Bip01_Head1")][:3, 3])
        eye = np.array(head) + np.array([0.0, 0.07, 0.09])
    allp = np.concatenate(all_pos)
    # some rigs (HD grunt) put the Head bone at the neck: eyes sit ~0.2 m under the top
    eye[1] = max(eye[1], float(allp[:, 1].max()) - 0.2)
    meta = {"name": m.name, "version": 10, "source": src_path, "bones": names,
            "bone_parents": [bb["parent"] for bb in m.bones],
            "attachments": {"eyes": {"bone": "ValveBiped.Bip01_Head1", "origin": [float(x) for x in eye],
                                     "basis": np.eye(3).tolist()}},
            "aabb_min": [float(x) for x in allp.min(0)], "aabb_max": [float(x) for x in allp.max(0)],
            "mass": 90.0, "surfaceprop": "flesh", "keyvalues": "",
            "bodyparts": [{"name": bp["name"], "models": [mm["name"] for mm in bp["models"]]} for bp in m.bodyparts],
            "skins": [], "materials": list(mats_meta.keys()), "eyes": []}
    with open(os.path.join(assets_root, "models", out_key + ".json"), "w") as f:
        json.dump(meta, f, indent=1)
    return meta, mats_meta


if __name__ == "__main__":
    import sys
    m = GoldSrcModel(open(sys.argv[1], "rb").read())
    print(m.name, "bones:", [b["name"] for b in m.bones])
    print("bodyparts:", [(bp["name"], [x["name"] for x in bp["models"]]) for bp in m.bodyparts])
    print("textures:", [(t["name"], t["w"], t["h"], t["flags"]) for t in m.textures], "eye", m.eye)
