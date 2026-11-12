"""VMT material resolution + VTF -> PNG export into the Godot project."""
import os

import numpy as np
from PIL import Image

import keyvalues
import vtf

# DX-level blocks of a VMT ('">=dx90_20b" { ... }'): the ones that hold on today's hardware override
# the material's own keys (the first listed wins); "<dx90_20b" only fills keys nothing else sets
DX_BLOCKS = (">=dx90_20b", ">=dx90", ">dx90")
DX_FALLBACK = ("<dx90_20b",)


def _values(block):
    return {k.lower(): v for k, v in block if not isinstance(v, list)}


class MaterialLib:
    def __init__(self, fs, assets_root):
        self.fs = fs
        self.assets_root = assets_root  # absolute path of hl2kart/assets
        self.tex_cache = {}
        self.mat_cache = {}
        self.db = {}  # material name -> info, dumped to materials.json

    # ---------- VMT ----------
    def load_vmt(self, name):
        """name like 'models/buggy/buggy001' (no materials/, no .vmt)."""
        path = "materials/" + name.lower().replace("\\", "/") + ".vmt"
        raw = self.fs.read(path)
        if raw is None:
            return None, None
        kv = keyvalues.parse(raw.decode("latin-1"))
        if not kv:
            return None, None
        shader, body = kv[0]
        if not isinstance(body, list):
            return None, None
        params = {}
        if shader.lower() == "patch":
            inc = keyvalues.kv_get(body, "include", "")
            inc = inc.lower().replace("\\", "/")
            if inc.startswith("materials/"):
                inc = inc[len("materials/") :]
            if inc.endswith(".vmt"):
                inc = inc[:-4]
            shader, base = self.load_vmt(inc)
            params = dict(base or {})
            for blk in ("insert", "replace"):
                sub = keyvalues.kv_get(body, blk)
                if isinstance(sub, list):
                    for k, v in sub:
                        if not isinstance(v, list):
                            params[k.lower()] = v
            return shader, params
        for k, v in body:
            if not isinstance(v, list):
                params[k.lower()] = v
            elif k.lower() in ("proxies",):
                params["__proxies"] = [p[0].lower() for p in v]
        blocks = {k.lower(): v for k, v in body if isinstance(v, list)}
        for cond in reversed(DX_BLOCKS):
            params.update(_values(blocks.get(cond, [])))
        for cond in DX_FALLBACK:
            for k, v in _values(blocks.get(cond, [])).items():
                params.setdefault(k, v)
        return shader, params

    # ---------- textures ----------
    def _png_rel(self, tex, suffix=""):
        return "materials/" + tex.lower().replace("\\", "/") + suffix + ".png"

    def export_texture(self, tex, kind="color"):
        """Decode materials/<tex>.vtf into a PNG (once: later runs reuse the file).
        Returns {"path": relative to assets root, "has_alpha" or "mask" for normal maps}, or None."""
        tex = tex.lower().replace("\\", "/")
        if tex.endswith(".vtf"):
            tex = tex[:-4]
        if tex.startswith("materials/"):
            tex = tex[len("materials/") :]
        key = (tex, kind)
        if key in self.tex_cache:
            return self.tex_cache[key]
        rel = self._png_rel(tex)
        if os.path.exists(os.path.join(self.assets_root, rel)):
            # exported by an earlier run: the files tell what decoding the VTF again would
            result = {"path": rel}
            if kind == "normal":
                mrel = self._png_rel(tex, "_mask")
                if os.path.exists(os.path.join(self.assets_root, mrel)):
                    result["mask"] = mrel
            else:
                with Image.open(os.path.join(self.assets_root, rel)) as im:
                    result["has_alpha"] = "A" in im.getbands()
            self.tex_cache[key] = result
            return result
        data = self.fs.read("materials/" + tex + ".vtf")
        if data is None:
            self.tex_cache[key] = None
            return None
        try:
            img, _ = vtf.decode(data)
        except Exception as e:  # noqa
            print("  !! vtf", tex, e)
            self.tex_cache[key] = None
            return None
        result = {"path": rel}
        if kind == "normal":
            a = np.array(img)
            mask = a[:, :, 3].copy()
            a[:, :, 1] = 255 - a[:, :, 1]  # DirectX (Y-) -> OpenGL (Y+)
            a[:, :, 3] = 255
            self._save(Image.fromarray(a, "RGBA").convert("RGB"), rel)
            if mask.min() < 250:
                mrel = self._png_rel(tex, "_mask")
                self._save(Image.fromarray(mask, "L"), mrel)
                result["mask"] = mrel
        else:
            a = np.array(img)
            has_alpha = a[:, :, 3].min() < 250
            self._save(img if has_alpha else img.convert("RGB"), rel)
            result["has_alpha"] = bool(has_alpha)
        self.tex_cache[key] = result
        return result

    def _save(self, img, rel):
        out = os.path.join(self.assets_root, rel)
        os.makedirs(os.path.dirname(out), exist_ok=True)
        if not os.path.exists(out):
            img.save(out, optimize=False, compress_level=6)

    def derived(self, rel_png, suffix, fn):
        """Create a derived PNG (e.g. self-illum = rgb*alpha) next to the source."""
        out_rel = rel_png[:-4] + suffix + ".png"
        out = os.path.join(self.assets_root, out_rel)
        if not os.path.exists(out):
            src = Image.open(os.path.join(self.assets_root, rel_png)).convert("RGBA")
            fn(src).save(out)
        return out_rel

    # ---------- materials ----------
    def resolve(self, name, cddirs):
        """Find material by trying each $cdmaterials dir. Returns full material name or None."""
        name = name.lower().replace("\\", "/")
        for d in cddirs:
            d = d.lower().replace("\\", "/").strip("/")
            full = (d + "/" + name) if d else name
            if self.fs.exists("materials/" + full + ".vmt"):
                return full
        if self.fs.exists("materials/" + name + ".vmt"):
            return name
        return None

    def material(self, full):
        if full in self.mat_cache:
            return self.mat_cache[full]
        shader, p = self.load_vmt(full)
        info = {"name": full, "shader": (shader or "missing").lower()}
        if p is None:
            self.mat_cache[full] = info
            return info

        def flag(k):
            v = p.get(k)
            return v is not None and v.strip() not in ("0", "")

        info["params"] = {k: v for k, v in p.items() if not k.startswith("__")}
        if "__proxies" in p:
            info["proxies"] = p["__proxies"]
        bt = p.get("$basetexture")
        if bt:
            t = self.export_texture(bt, "color")
            if t:
                info["albedo"] = t["path"]
                info["albedo_alpha"] = t.get("has_alpha", False)
        bt2 = p.get("$basetexture2")
        if bt2:
            t = self.export_texture(bt2, "color")
            if t:
                info["albedo2"] = t["path"]
        if info["shader"] == "water":
            bm = p.get("$normalmap") or p.get("$bumpmap")
        else:
            bm = p.get("$bumpmap") or p.get("$normalmap")
        if bm:
            t = self.export_texture(bm, "normal")
            if t:
                info["normal"] = t["path"]
                if "mask" in t:
                    info["normal_alpha"] = t["mask"]
        iris = p.get("$iris")
        if iris:
            t = self.export_texture(iris, "color")
            if t:
                info["iris"] = t["path"]
        for k in ("$translucent", "$alphatest", "$additive", "$nocull", "$selfillum", "$phong",
                  "$halflambert", "$basemapalphaphongmask", "$basealphaenvmapmask",
                  "$normalmapalphaenvmapmask", "$vertexalpha", "$vertexcolor", "$model"):
            if flag(k):
                info[k[1:]] = True
        for k in ("$alphatestreference", "$alpha", "$phongexponent", "$phongboost", "$envmaptint",
                  "$color", "$color2", "$selfillumtint", "$phongfresnelranges", "$envmap",
                  "$surfaceprop", "$detail", "$detailscale", "$detailblendfactor", "$detailblendmode"):
            if k in p:
                info[k[1:]] = p[k]
        sim = p.get("$selfillummask")
        if sim:
            t = self.export_texture(sim, "color")
            if t:
                info["selfillummask_tex"] = t["path"]
        em = p.get("$envmapmask")
        if em:
            t = self.export_texture(em, "color")
            if t:
                info["envmapmask_tex"] = t["path"]
        det = p.get("$detail")
        if det:
            t = self.export_texture(det, "color")
            if t:
                info["detail_tex"] = t["path"]
        self.mat_cache[full] = info
        self.db[full] = info
        return info
