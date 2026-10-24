"""Half-Life 1 BSP -> Godot world: textured meshes with the map's baked
lightmaps in an atlas (UV2), collision triangles, sky, sun and entities.
Several maps can be merged through their info_landmark entities.

usage: python goldsrc_world.py <out_key> <scale> <map> [<map> ...] [--clip <i>:<axis><op><value> ...]
  --clip 0:y<448 keeps only the part of map 0 with Quake y below 448 (merged
  coordinates): neighbouring maps repeat each other's edges around a transition.
"""
import json
import math
import os
import sys
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import goldsrc_bsp as gb  # noqa: E402
from bsp_common import Atlas, to_godot, save_lightmap, write_world, write_collision  # noqa: E402

ASSETS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets")
TOOL_TEXTURES = {"aaatrigger", "clip", "origin", "null", "hint", "skip", "bevel", "sky", "noclip"}
NO_RENDER_CLASSES = {"func_ladder", "func_clip", "trigger_multiple", "trigger_once", "trigger_hurt",
                     "trigger_push", "trigger_changelevel", "trigger_teleport", "trigger_gravity",
                     "trigger_autosave", "trigger_transition", "trigger_monsterjump", "trigger_cdaudio",
                     "func_monsterclip", "env_bubbles", "func_friction", "trigger_endsection", "func_buyzone"}
# brush entities that stay solid for karts (doors / trains are left open / out of the way)
SOLID_CLASSES = {"worldspawn", "func_wall", "func_breakable", "func_pushable", "func_wall_toggle",
                 "func_rot_button", "func_button", "func_tank", "func_tankmortar", "func_guntarget",
                 "func_healthcharger", "func_recharge", "momentary_rot_button"}
# see-through decoration karts pass through: camouflage nets, razor wire, ladders
NO_COLLIDE_TEXTURES = ("{out_net", "{razor", "{ladder", "{rustyrungs")
LIGHT_SCALE = 2.0  # lightmap PNG stores light / LIGHT_SCALE


def safe_name(tex):
    t = tex.lower()
    for a, b in (("{", "a_"), ("+", "p_"), ("~", "t_"), ("!", "w_"), ("-", "r_")):
        t = t.replace(a, b)
    return t


class TextureBank:
    def __init__(self, wads):
        self.wads = wads
        self.done = {}

    def get(self, mt):
        """-> (rel png path, w, h, alpha) for a miptex record of the BSP."""
        name = mt["name"].lower()
        if name in self.done:
            return self.done[name]
        rgba = None
        w, h = mt["w"], mt["h"]
        if mt["blob"] is not None:
            _, w, h, rgba = gb.decode_miptex(mt["blob"])
        else:
            for wd in self.wads:
                blob = wd.miptex(name)
                if blob:
                    _, w, h, rgba = gb.decode_miptex(blob)
                    break
        if rgba is None:
            self.done[name] = (None, w, h, False)
            return self.done[name]
        rel = "materials/goldsrc/world/%s.png" % safe_name(name)
        out = os.path.join(ASSETS, rel)
        os.makedirs(os.path.dirname(out), exist_ok=True)
        if not os.path.exists(out):
            Image.fromarray(rgba, "RGBA" if name.startswith("{") else None).convert(
                "RGBA" if name.startswith("{") else "RGB").save(out)
        self.done[name] = (rel, w, h, name.startswith("{"))
        return self.done[name]


def clip_poly(v, axis, sign, val):
    """Sutherland-Hodgman: keep the part of polygon v where sign * (p[axis] - val) >= 0."""
    out = []
    n = len(v)
    for i in range(n):
        a, b = v[i], v[(i + 1) % n]
        da, db = sign * (a[axis] - val), sign * (b[axis] - val)
        if da >= 0:
            out.append(a)
        if (da >= 0) != (db >= 0):
            t = da / (da - db)
            out.append(a + (b - a) * t)
    return np.array(out) if len(out) >= 3 else np.zeros((0, 3))


def landmark_offsets(paths):
    """Offset (Quake units) of each map so landmarks shared with the previous map line up."""
    offs = [np.zeros(3)]
    bsps = [gb.BSP30(p) for p in paths]
    for i in range(1, len(bsps)):
        prev = {e.get("targetname"): e for e in bsps[i - 1].entities if e.get("classname") == "info_landmark"}
        cur = {e.get("targetname"): e for e in bsps[i].entities if e.get("classname") == "info_landmark"}
        common = [k for k in cur if k in prev]
        if not common:
            raise SystemExit("no shared landmark between %s and %s" % (paths[i - 1], paths[i]))
        a = np.array([float(x) for x in prev[common[0]]["origin"].split()])
        b = np.array([float(x) for x in cur[common[0]]["origin"].split()])
        offs.append(offs[-1] + a - b)
    return bsps, offs


def convert(out_key, scale, paths, offroad=(), skip_models=(), lm_scale=LIGHT_SCALE, clips=None):
    unit = 0.0254 * scale
    bsps, offs = landmark_offsets(paths)
    out_dir = os.path.join(ASSETS, "maps", out_key)
    os.makedirs(out_dir, exist_ok=True)
    meshes = {}
    materials = {}
    coll = {"road": [], "offroad": []}
    atlas = Atlas(2048)
    white = atlas.add(np.full((2, 2, 3), 1.0 / 1.0, np.float32) * 1.0)
    entities = []
    lights = []
    sky = ""
    for bi, (bsp, off) in enumerate(zip(bsps, offs)):
        wads = gb.load_wads(bsp.wad_names() + ["halflife.wad", "xeno.wad", "liquids.wad", "decals.wad"])
        bank = TextureBank(wads)
        ws = bsp.worldspawn()
        sky = sky or ws.get("skyname", "desert")
        model_class = {0: ("worldspawn", {})}
        for e in bsp.entities:
            m = e.get("model", "")
            if m.startswith("*"):
                model_class[int(m[1:])] = (e.get("classname", ""), e)
            cl = e.get("classname", "")
            if "origin" in e and not m.startswith("*"):
                o = np.array([float(x) for x in e["origin"].split()]) + off
                if any(sg * (o[ax] - val) < 0 for ax, sg, val in (clips or {}).get(bi, [])):
                    continue
                ee = dict(e)
                ee["origin_m"] = [float(x) for x in to_godot(o, unit)]
                entities.append(ee)
                if cl == "light_environment":
                    lights.append(ee)
        for mi, model in enumerate(bsp.models):
            cl, ent = model_class.get(mi, ("", {}))
            if cl in NO_RENDER_CLASSES or cl.startswith("trigger_") or (bi, mi) in skip_models:
                continue
            rendermode = int(ent.get("rendermode", "0") or 0)
            amt = float(ent.get("renderamt", "255") or 255) / 255.0
            if rendermode in (2, 3, 5) and amt <= 0.02:
                continue
            solid = cl in SOLID_CLASSES
            eo = np.array([float(x) for x in ent["origin"].split()]) if "origin" in ent and mi else np.zeros(3)
            for fi in range(model["first_face"], model["first_face"] + model["num_faces"]):
                f = bsp.faces[fi]
                ti = bsp.texinfo[f["texinfo"]]
                mt = bsp.miptex[ti["miptex"]]
                tname = mt["name"].lower()
                verts = bsp.face_verts(fi).astype(np.float64) + eo
                if len(verts) < 3:
                    continue
                # lightmap extents come from the whole face, before any clipping
                s0 = verts @ np.array(ti["s"]) + ti["so"]
                t0 = verts @ np.array(ti["t"]) + ti["to"]
                for ax, sg, val in (clips or {}).get(bi, []):
                    verts = clip_poly(verts, ax, sg, val - off[ax])
                if len(verts) < 3:
                    continue
                world_v = verts + off
                gv = to_godot(world_v, unit)
                # collision: everything solid except sky (clip brushes are invisible walls / ramps)
                tris = [(gv[0], gv[k + 1], gv[k]) for k in range(1, len(gv) - 1)]
                if solid and tname not in ("sky", "aaatrigger", "origin") and not tname.startswith("!")                         and not tname.startswith(NO_COLLIDE_TEXTURES):
                    kind = "offroad" if any(tname.startswith(p) for p in offroad) else "road"
                    coll[kind].extend(tris)
                if tname in TOOL_TEXTURES or tname.startswith("!") and False:
                    continue
                rel, tw, th, alpha = bank.get(mt)
                if rel is None:
                    continue
                matname = safe_name(tname)
                if rendermode == 5:
                    matname += "@add"
                elif rendermode in (2, 3) and amt < 0.99:
                    matname += "@glass%d" % int(amt * 100)
                elif rendermode == 4 or alpha:
                    matname += "@alpha" if not matname.endswith("@alpha") else ""
                if matname not in materials:
                    materials[matname] = {"albedo": rel, "alpha": alpha or rendermode == 4,
                                          "additive": rendermode == 5, "opacity": amt if rendermode in (2, 3) else 1.0,
                                          "water": tname.startswith("!"), "fullbright": tname.startswith("~") or "~" in tname[:3]}
                # texture coordinates
                s = verts @ np.array(ti["s"]) + ti["so"]
                t = verts @ np.array(ti["t"]) + ti["to"]
                uv = np.stack([s / tw, t / th], axis=1)
                # lightmap
                special = ti["flags"] & 1
                if f["light"] >= 0 and not special and f["styles"][0] != 255:
                    smin, smax = math.floor(s0.min() / 16.0), math.ceil(s0.max() / 16.0)
                    tmin, tmax = math.floor(t0.min() / 16.0), math.ceil(t0.max() / 16.0)
                    lw, lh = smax - smin + 1, tmax - tmin + 1
                    n = lw * lh * 3
                    raw = np.frombuffer(bsp.lighting, np.uint8, n, f["light"]) if f["light"] + n <= len(bsp.lighting) else None
                    if raw is not None and lw <= 64 and lh <= 64:
                        img = raw.reshape(lh, lw, 3).astype(np.float32) / 255.0 * 2.0
                        x0, y0 = atlas.add(img)
                        u2 = (x0 + 0.5 + (s / 16.0 - smin))
                        v2 = (y0 + 0.5 + (t / 16.0 - tmin))
                        uv2 = np.stack([u2, v2], axis=1)
                    else:
                        uv2 = np.tile(np.array([[white[0] + 1.0, white[1] + 1.0]]), (len(verts), 1))
                else:
                    uv2 = np.tile(np.array([[white[0] + 1.0, white[1] + 1.0]]), (len(verts), 1))
                plane = bsp.planes[f["plane"]]
                nz = np.array(plane[:3]) * (-1.0 if f["side"] else 1.0)
                gn = to_godot(nz, 1.0)
                m = meshes.setdefault(matname, {"pos": [], "nrm": [], "uv": [], "uv2": [], "idx": []})
                base = len(m["pos"])
                for k in range(len(gv)):
                    m["pos"].append(gv[k])
                    m["nrm"].append(gn)
                    m["uv"].append(uv[k])
                    m["uv2"].append(uv2[k])
                for k in range(1, len(gv) - 1):
                    m["idx"].extend([base, base + k + 1, base + k])
    # normalise lightmap UVs to the final atlas size
    img = atlas.image()
    H, W = img.shape[0], img.shape[1]
    for m in meshes.values():
        m["uv2"] = [(u / W, v / H) for u, v in m["uv2"]]
    save_lightmap(img, os.path.join(out_dir, "lightmap.png"), lm_scale)
    sun = None
    if lights:
        e = lights[0]
        col = [float(x) for x in e.get("_light", "255 255 255 200").split()]
        pitch = float(e.get("pitch", "-60") or -60)
        ang = [float(x) for x in e.get("angles", "0 0 0").split()]
        yaw = ang[1] if len(ang) > 1 else 0.0
        sun = {"color": [c / 255.0 for c in col[:3]], "pitch": pitch, "yaw": yaw}
    allp = np.concatenate([np.array(m["pos"]) for m in meshes.values() if m["pos"]])
    extra = {"source": [os.path.basename(p) for p in paths], "engine": "goldsrc", "scale": unit,
             "sky": sky, "sun": sun, "lm_scale": lm_scale,
             "aabb_min": [float(x) for x in allp.min(0)], "aabb_max": [float(x) for x in allp.max(0)],
             "entities": [{k: v for k, v in e.items() if k in ("classname", "origin_m", "targetname", "angles", "angle", "_light", "model", "skyname")} for e in entities
                          if e.get("classname") in ("info_player_start", "info_player_deathmatch", "light_environment", "info_landmark",
                                                    "light", "light_spot", "env_sprite", "item_healthkit", "info_node")]}
    extra["collision"] = write_collision(out_dir, {k: np.array(v) for k, v in coll.items()})
    write_world(out_dir, meshes, materials, "lightmap.png", extra)
    print("%s: %d materials, %d tris, lightmap %dx%d, bounds %s .. %s m" % (
        out_key, len(materials), sum(len(m["idx"]) // 3 for m in meshes.values()), W, H,
        np.round(allp.min(0), 1), np.round(allp.max(0), 1)))


if __name__ == "__main__":
    key = sys.argv[1]
    sc = float(sys.argv[2])
    names, clips = [], {}
    args = sys.argv[3:]
    while args:
        a = args.pop(0)
        if a == "--clip":
            spec = args.pop(0)
            idx, rest = spec.split(":")
            op = "<" if "<" in rest else ">"
            ax, val = rest.split(op)
            clips.setdefault(int(idx), []).append(("xyz".index(ax), -1.0 if op == "<" else 1.0, float(val)))
        else:
            names.append(a)
    maps = [os.path.join(gb.HL1_ROOT, "valve", "maps", m + ".bsp") for m in names]
    convert(key, sc, maps, clips=clips)
