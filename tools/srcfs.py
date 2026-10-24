"""Read-only access to Source engine game content: VPK archives + loose files.

Mirrors the SearchPaths order from hl2/gameinfo.txt so lookups resolve the
same file the game itself would load.
"""
import os
import struct

from steam_paths import HL2_ROOT  # noqa: E402  (env HL2_ROOT or the Steam library)


class VPK:
    def __init__(self, dir_path):
        self.dir_path = dir_path
        self.base = dir_path[: -len("_dir.vpk")]
        self.entries = {}
        self._handles = {}
        with open(dir_path, "rb") as f:
            data = f.read()
        sig, ver, tree_size = struct.unpack_from("<III", data, 0)
        if sig != 0x55AA1234:
            raise ValueError("not a VPK: " + dir_path)
        hdr = 12 if ver == 1 else 28
        self.data_start = hdr + tree_size
        self.dir_data = data
        p = hdr

        def rstr():
            nonlocal p
            e = data.index(b"\0", p)
            s = data[p:e].decode("latin-1")
            p = e + 1
            return s

        while True:
            ext = rstr()
            if not ext:
                break
            while True:
                path = rstr()
                if not path:
                    break
                while True:
                    name = rstr()
                    if not name:
                        break
                    crc, preload, arch, off, length, term = struct.unpack_from("<IHHIIH", data, p)
                    p += 18
                    pre_off = p
                    p += preload
                    full = (name + "." + ext) if path.strip() == "" else (path + "/" + name + "." + ext)
                    self.entries[full.lower()] = (preload, pre_off, arch, off, length)

    def read(self, name):
        preload, pre_off, arch, off, length = self.entries[name]
        out = self.dir_data[pre_off : pre_off + preload]
        if length:
            if arch == 0x7FFF:
                out += self.dir_data[self.data_start + off : self.data_start + off + length]
            else:
                fh = self._handles.get(arch)
                if fh is None:
                    fh = open("%s_%03d.vpk" % (self.base, arch), "rb")
                    self._handles[arch] = fh
                fh.seek(off)
                out += fh.read(length)
        return out


class GameFS:
    """Search path list: VPKs and loose dirs, first hit wins."""

    def __init__(self, root=HL2_ROOT, games=("hl2", "episodic", "ep2")):
        self.paths = []
        for g in games:
            gdir = os.path.join(root, g)
            if not os.path.isdir(gdir):
                continue
            vpks = sorted(f for f in os.listdir(gdir) if f.endswith("_dir.vpk"))
            # gameinfo mounts vo/pak first, then textures, sounds, misc
            order = ["sound_vo_english", "pak", "textures", "sound_misc", "misc"]
            vpks.sort(key=lambda f: next((i for i, k in enumerate(order) if k in f), 99))
            for v in vpks:
                if "russian" in v or "_lv" in v:
                    continue
                self.paths.append(VPK(os.path.join(gdir, v)))
            self.paths.append(gdir)

    def exists(self, name):
        return self._locate(name) is not None

    def _locate(self, name):
        name = name.replace("\\", "/").lower().lstrip("/")
        for p in self.paths:
            if isinstance(p, VPK):
                if name in p.entries:
                    return (p, name)
            else:
                fp = os.path.join(p, name)
                if os.path.isfile(fp) and os.path.getsize(fp) > 0:
                    return (p, fp)
        return None

    def read(self, name):
        hit = self._locate(name)
        if hit is None:
            return None
        p, key = hit
        if isinstance(p, VPK):
            return p.read(key)
        with open(key, "rb") as f:
            return f.read()

    def listdir(self, prefix, ext=None):
        prefix = prefix.lower().rstrip("/") + "/"
        out = set()
        for p in self.paths:
            if isinstance(p, VPK):
                for k in p.entries:
                    if k.startswith(prefix) and (ext is None or k.endswith(ext)):
                        out.add(k)
        return sorted(out)

    def glob(self, pred):
        out = set()
        for p in self.paths:
            if isinstance(p, VPK):
                out.update(k for k in p.entries if pred(k))
        return sorted(out)
