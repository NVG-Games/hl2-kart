"""Half-Life 2 BSP -> Godot world (same output as goldsrc_world.py): brush faces
and displacements with their baked lightmaps (atlas, UV2), VMT materials,
collision, static props (converted MDLs + placement), sky, sun, entities.
Several maps can be merged through shared info_landmark entities.

usage: python source_world.py <out_key> <scale> <map> [<map> ...]
"""
import json
import math
import os
import re
import sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import srcfs  # noqa: E402
import source_bsp as sb  # noqa: E402
import mdl as mdlconv  # noqa: E402
from materials import MaterialLib  # noqa: E402
from bsp_common import Atlas, to_godot, save_lightmap, write_world, write_collision  # noqa: E402

ASSETS = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets"))
MAPS = os.path.join(srcfs.HL2_ROOT, "hl2", "maps")
SKIP_FLAGS = sb.SURF_SKY | sb.SURF_SKY2D | sb.SURF_NODRAW | sb.SURF_TRIGGER | sb.SURF_HINT | sb.SURF_SKIP
STATIC_BRUSH = {"worldspawn", "func_brush", "func_detail", "func_illusionary", "func_breakable_surf", "func_wall",
                "func_lod", "func_breakable", "func_reflective_glass", "func_movelinear", "func_rotating"}
SOLID_BRUSH = {"worldspawn", "func_brush", "func_detail", "func_wall", "func_breakable", "func_lod"}
P = np.array([[1, 0, 0], [0, 0, 1], [0, -1, 0]], dtype=np.float64)
LM_SCALE = 4.0


def angle_matrix(pitch, yaw, roll):
    sp, cp = math.sin(math.radians(pitch)), math.cos(math.radians(pitch))
    sy, cy = math.sin(math.radians(yaw)), math.cos(math.radians(yaw))
    sr, cr = math.sin(math.radians(roll)), math.cos(math.radians(roll))
    return np.array([[cp * cy, sr * sp * cy - cr * sy, cr * sp * cy + sr * sy],
                     [cp * sy, sr * sp * sy + cr * cy, cr * sp * sy - sr * cy],
                     [-sp, sr * cp, cr * cp]])


def base_material(name, mapname):
    """Cubemap / WVT patches in the pakfile point back at the stock material."""
    n = name.lower().replace("\\", "/")
    pre = "maps/%s/" % mapname.lower()
    if n.startswith(pre):
        n = n[len(pre):]
        n = re.sub(r"_wvt_patch$", "", n)
        n = re.sub(r"_-?\d+_-?\d+_-?\d+$", "", n)
    return n


def map_path(m):
    for g in ("hl2", "episodic", "ep2"):
        p = os.path.join(srcfs.HL2_ROOT, g, "maps", m + ".bsp")
        if os.path.exists(p):
            return p
    raise FileNotFoundError(m)


def landmark_offsets(bsps):
    offs = [np.zeros(3)]
    for i in range(1, len(bsps)):
        prev = {e.get("targetname"): e for e in bsps[i - 1].entities if e.get("classname") == "info_landmark"}
        cur = {e.get("targetname"): e for e in bsps[i].entities if e.get("classname") == "info_landmark"}
        common = [k for k in cur if k in prev]
        if not common:
            raise SystemExit("no shared landmark")
        a = np.array([float(x) for x in prev[common[0]]["origin"].split()])
        b = np.array([float(x) for x in cur[common[0]]["origin"].split()])
        offs.append(offs[-1] + a - b)
    return offs


def disp_mesh(bsp, fi, di, corners):
    """-> positions (n*n,3), base positions, alphas, triangles"""
    d = bsp.dispinfo[di]
    n = (1 << d["power"]) + 1
    start = np.array(d["start"])
    k = int(np.argmin(np.linalg.norm(corners - start, axis=1)))
    c = np.roll(corners, -k, axis=0)
    dv = bsp.dispverts[d["vstart"]:d["vstart"] + n * n]
    pos = np.zeros((n * n, 3))
    base = np.zeros((n * n, 3))
    for i in range(n):
        f = i / (n - 1)
        e0 = c[0] + (c[1] - c[0]) * f
        e1 = c[3] + (c[2] - c[3]) * f
        for j in range(n):
            g = j / (n - 1)
            b = e0 + (e1 - e0) * g
            idx = i * n + j
            base[idx] = b
            pos[idx] = b + dv[idx, 0:3] * dv[idx, 3]
    alpha = dv[:, 4] / 255.0
    tris = []
    for i in range(n - 1):
        for j in range(n - 1):
            a = i * n + j
            b = a + 1
            cc = a + n
            dd = cc + 1
            if (i + j) % 2 == 0:
                tris += [(a, cc, dd), (a, dd, b)]
            else:
                tris += [(a, cc, b), (b, cc, dd)]
    return pos, base, alpha, tris


def convert(out_key, scale, mapnames, props=True, offroad=(), lm_scale=LM_SCALE, fill_mat="concrete/concretefloor026a"):
    unit = 0.0254 * scale
    fs = srcfs.GameFS()
    lib = MaterialLib(fs, ASSETS)
    bsps = [sb.SourceBSP(map_path(m)) for m in mapnames]
    offs = landmark_offsets(bsps)
    out_dir = os.path.join(ASSETS, "maps", out_key)
    os.makedirs(out_dir, exist_ok=True)
    meshes = {}
    materials = {}
    coll = {"road": [], "offroad": []}
    atlas = Atlas(4096)
    white = atlas.add(np.full((2, 2, 3), 1.0, np.float32))
    wuv = (white[0] + 1.0, white[1] + 1.0)
    fill_info = lib.material(fill_mat)
    fill_faces = []  # (godot verts, plane normal) of skybox floors next to the playable area
    entities = []
    prop_list = []
    sky = ""
    sun = None
    for bsp, off, mname in zip(bsps, offs, mapnames):
        ws = bsp.entities[0]
        sky_faces, sky_cam = bsp.skybox_faces()
        sky = sky or ws.get("skyname", "sky_day01_01")
        model_ent = {0: ws}
        for e in bsp.entities:
            m = e.get("model", "")
            if m.startswith("*"):
                model_ent[int(m[1:])] = e
            elif "origin" in e:
                o = np.array([float(x) for x in e["origin"].split()]) + off
                ee = {k: v for k, v in e.items() if k in ("classname", "targetname", "angles", "_light", "pitch", "skyname")}
                ee["origin_m"] = [float(x) for x in to_godot(o, unit)]
                entities.append(ee)
                if e.get("classname") == "light_environment" and sun is None:
                    col = [float(x) for x in e.get("_light", "255 255 255 200").split()]
                    ang = [float(x) for x in e.get("angles", "0 0 0").split()]
                    pitch = float(e.get("pitch", ang[0]) or ang[0])
                    amb = [float(x) for x in e.get("_ambient", "128 128 128 50").split()]
                    sun = {"color": [c / 255.0 for c in col[:3]], "pitch": pitch, "yaw": ang[1],
                           "brightness": col[3] / 255.0 if len(col) > 3 else 1.0,
                           "ambient": [c / 255.0 for c in amb[:3]]}
        for mi, model in enumerate(bsp.models):
            ent = model_ent.get(mi)
            if ent is None:
                continue
            cl = ent.get("classname", "")
            if cl not in STATIC_BRUSH:
                continue
            solid = cl in SOLID_BRUSH
            R = np.eye(3)
            eo = np.zeros(3)
            ent_in_sky = False
            if mi:
                eo = np.array([float(x) for x in ent.get("origin", "0 0 0").split()])
                a = [float(x) for x in ent.get("angles", "0 0 0").split()]
                R = angle_matrix(*a)
                if sky_cam and sky_cam["box"] is not None:
                    c = (np.array(model["mins"]) + np.array(model["maxs"])) * 0.5 + eo
                    ent_in_sky = bool((c >= sky_cam["box"][0]).all() and (c <= sky_cam["box"][1]).all())
            for fi in range(model["first_face"], model["first_face"] + model["num_faces"]):
                f = bsp.faces[fi]
                if f["texinfo"] < 0:
                    continue
                in_sky = (mi == 0 and fi in sky_faces) or ent_in_sky
                ti = bsp.texinfo[f["texinfo"]]
                if ti["flags"] & SKIP_FLAGS:
                    # 2D-sky floors at street level: in-game the 3D skybox fills them, here a road texture does
                    if (ti["flags"] & sb.SURF_SKY) and mi == 0 and fi not in sky_faces:
                        pl = bsp.planes[f["plane"]]
                        nz = pl[2] * (-1.0 if f["side"] else 1.0)
                        if nz > 0.7:
                            fv = bsp.face_verts(fi) + off
                            fill_faces.append((fv, np.array(pl[:3]) * (-1.0 if f["side"] else 1.0)))
                    continue
                td = bsp.texdata[ti["texdata"]]
                mat = base_material(td["name"], mname)
                if mat.startswith("tools/"):
                    continue
                info = lib.material(mat)
                monitor = "combinemonitor" in mat or "breenscreen" in mat
                if monitor:
                    info = dict(info)
                    info["albedo"] = info.get("albedo", "")
                if "albedo" not in info:
                    continue
                shader = info.get("shader", "")
                water = shader == "water"
                corners = bsp.face_verts(fi)
                if len(corners) < 3:
                    continue
                tv = [np.array(ti["tv"][0]), np.array(ti["tv"][1])]
                lv = [np.array(ti["lv"][0]), np.array(ti["lv"][1])]
                if f["disp"] >= 0 and len(corners) == 4:
                    pos, base, alpha, tris = disp_mesh(bsp, fi, f["disp"], corners)
                else:
                    pos = corners
                    base = corners
                    alpha = np.zeros(len(corners))
                    tris = [(0, k + 1, k) for k in range(1, len(corners) - 1)]
                    tris = [(0, k, k + 1) for k in range(1, len(corners) - 1)]
                # texture + lightmap coordinates from the undisplaced surface
                s = base @ tv[0][:3] + tv[0][3]
                t = base @ tv[1][:3] + tv[1][3]
                uv = np.stack([s / max(td["w"], 1), t / max(td["h"], 1)], axis=1)
                lw, lh = f["lm_size"][0] + 1, f["lm_size"][1] + 1
                if f["light"] >= 0 and f["styles"][0] != 255 and lw * lh * 4 + f["light"] <= len(bsp.lighting):
                    lum = bsp.luxels(f, lw * lh).reshape(lh, lw, 3).astype(np.float32)
                    x0, y0 = atlas.add(lum)
                    ls = base @ lv[0][:3] + lv[0][3] - f["lm_mins"][0]
                    lt = base @ lv[1][:3] + lv[1][3] - f["lm_mins"][1]
                    uv2 = np.stack([x0 + ls + 0.5, y0 + lt + 0.5], axis=1)
                else:
                    uv2 = np.tile(np.array([wuv]), (len(pos), 1))
                if in_sky:
                    # 3D skybox: blow the miniature up around the world (sky_camera scale)
                    wpos = ((R @ pos.T).T + eo - sky_cam["origin"]) * sky_cam["scale"] + off
                else:
                    wpos = (R @ pos.T).T + eo + off
                gv = to_godot(wpos, unit)
                plane = bsp.planes[f["plane"]]
                pn = R @ (np.array(plane[:3]) * (-1.0 if f["side"] else 1.0))
                key = mat + ("@water" if water else "") + ("@sky3d" if in_sky else "")
                if monitor:
                    key = mat + "@monitor"
                    materials.setdefault(key, {"albedo": "", "monitor": True})
                if key not in materials:
                    m = {"albedo": info["albedo"], "alpha": bool(info.get("alphatest")),
                         "translucent": bool(info.get("translucent")), "additive": bool(info.get("additive")),
                         "water": water, "fullbright": shader == "unlitgeneric" or bool(info.get("selfillum") and False)}
                    if info.get("albedo2"):
                        m["albedo2"] = info["albedo2"]
                    materials[key] = m
                # per-vertex normals: displacements from geometry, brushes from the plane
                nrm = np.tile(to_godot(pn, 1.0), (len(gv), 1))
                if f["disp"] >= 0:
                    nrm = np.zeros_like(gv)
                    for a_, b_, c_ in tris:
                        fn = np.cross(gv[c_] - gv[a_], gv[b_] - gv[a_])
                        nrm[[a_, b_, c_]] += fn
                    nrm /= np.linalg.norm(nrm, axis=1, keepdims=True) + 1e-9
                    nrm *= np.sign((nrm @ to_godot(pn, 1.0)).mean() or 1.0)
                mm = meshes.setdefault(key, {"pos": [], "nrm": [], "uv": [], "uv2": [], "idx": [], "col": []})
                basei = len(mm["pos"])
                mm["pos"].extend(gv.tolist())
                mm["nrm"].extend(nrm.tolist())
                mm["uv"].extend(uv.tolist())
                mm["uv2"].extend(uv2.tolist())
                mm["col"].extend([[1.0, 1.0, 1.0, float(a)] for a in alpha])
                # winding: front faces must face the plane normal after conversion
                gpn = to_godot(pn, 1.0)
                for a_, b_, c_ in tris:
                    fn = np.cross(gv[b_] - gv[a_], gv[c_] - gv[a_])
                    if fn @ gpn < 0:
                        b_, c_ = c_, b_
                    mm["idx"].extend([basei + a_, basei + b_, basei + c_])
                    if solid and not water and not in_sky:
                        kind = "offroad" if any(mat.startswith(p) for p in offroad) else "road"
                        coll[kind].append((gv[a_], gv[b_], gv[c_]))
        if props:
            for p in bsp.static_props():
                mp = p["model"].lower().replace("\\", "/")
                key = mp[len("models/"):-4] if mp.startswith("models/") else mp[:-4]
                try:
                    meta = mdlconv.convert(fs, lib, mp, ASSETS)
                except Exception as e:  # noqa
                    print("  prop failed", mp, e)
                    continue
                Rm = angle_matrix(*p["angles"])
                basis = P @ Rm @ P.T * scale
                po = np.array(p["origin"])
                sky_prop = bool(sky_cam and sky_cam["box"] is not None and (po >= sky_cam["box"][0]).all() and (po <= sky_cam["box"][1]).all())
                if sky_prop:
                    po = (po - sky_cam["origin"]) * sky_cam["scale"]
                    basis = basis * sky_cam["scale"]
                o = to_godot(po + off, unit)
                prop_list.append({"model": key, "origin": [float(x) for x in o],
                                  "basis": [float(x) for x in basis.T.reshape(-1)],
                                  "skin": int(p["skin"]), "solid": 0 if sky_prop else int(p["solid"]), "sky": sky_prop,
                                  "aabb_min": meta.get("aabb_min"), "aabb_max": meta.get("aabb_max")})
    # sky-floor patches get the map's median street light
    if fill_faces and "albedo" in fill_info:
        allum = np.concatenate([r[2].reshape(-1, 3) for r in atlas.rects[1:]]) if len(atlas.rects) > 1 else np.ones((1, 3))
        med = np.median(allum, axis=0).astype(np.float32)
        g = atlas.add(np.tile(med, (2, 2, 1)))
        guv = (g[0] + 1.0, g[1] + 1.0)
        key = fill_mat + "@fill"
        materials[key] = {"albedo": fill_info["albedo"], "alpha": False, "translucent": False, "additive": False, "water": False, "fullbright": False}
        mm = meshes.setdefault(key, {"pos": [], "nrm": [], "uv": [], "uv2": [], "idx": [], "col": []})
        for fv, pn in fill_faces:
            gv = to_godot(fv, unit)
            gpn = to_godot(pn, 1.0)
            basei = len(mm["pos"])
            for v_, g_ in zip(fv, gv):
                mm["pos"].append(g_.tolist())
                mm["nrm"].append(gpn.tolist())
                mm["uv"].append([v_[0] / 256.0, v_[1] / 256.0])
                mm["uv2"].append(list(guv))
                mm["col"].append([1, 1, 1, 0])
            for k in range(1, len(gv) - 1):
                a_, b_, c_ = 0, k, k + 1
                if np.cross(gv[b_] - gv[a_], gv[c_] - gv[a_]) @ gpn < 0:
                    b_, c_ = c_, b_
                mm["idx"].extend([basei + a_, basei + b_, basei + c_])
    img = atlas.image()
    H, W = img.shape[0], img.shape[1]
    for m in meshes.values():
        m["uv2"] = [(u / W, v / H) for u, v in m["uv2"]]
    save_lightmap(img, os.path.join(out_dir, "lightmap.png"), lm_scale)
    allp = np.concatenate([np.array(m["pos"]) for k, m in meshes.items() if m["pos"] and "@sky3d" not in k])
    extra = {"source": mapnames, "engine": "source", "scale": unit, "sky": sky, "sun": sun, "lm_scale": lm_scale,
             "aabb_min": [float(x) for x in allp.min(0)], "aabb_max": [float(x) for x in allp.max(0)],
             "entities": [e for e in entities if e.get("classname") in (
                 "info_player_start", "info_landmark", "light_environment", "light", "light_spot", "env_sprite")],
             "props": prop_list}
    extra["collision"] = write_collision(out_dir, {k: np.array(v) for k, v in coll.items()})
    write_world(out_dir, meshes, materials, "lightmap.png", extra)
    # new materials / models for the game's registries
    dbp = os.path.join(ASSETS, "data", "materials.json")
    db = json.load(open(dbp))
    db.update(lib.db)
    json.dump(db, open(dbp, "w"))
    mp = os.path.join(ASSETS, "data", "models.json")
    models = json.load(open(mp))
    for p in prop_list:
        if p["model"] not in models:
            models[p["model"]] = {"gltf": "res://assets/models/%s.gltf" % p["model"], "meta": "res://assets/models/%s.json" % p["model"],
                                  "aabb_min": p["aabb_min"], "aabb_max": p["aabb_max"], "kind": "map_prop"}
    json.dump(models, open(mp, "w"), indent=1)
    print("%s: %d materials, %d tris, %d props, lightmap %dx%d, bounds %s .. %s" % (
        out_key, len(materials), sum(len(m["idx"]) // 3 for m in meshes.values()), len(prop_list), W, H,
        np.round(allp.min(0), 1), np.round(allp.max(0), 1)))


if __name__ == "__main__":
    convert(sys.argv[1], float(sys.argv[2]), sys.argv[3:])
