"""Half-Life 1 skyboxes (valve/gfx/env/<name><face>.tga) -> panoramas the race
sky shader uses, merged into assets/data/skies.json as "hl1_<name>".

usage: python hl1_skies.py desert neb7 alien1 ...
"""
import json
import os
import sys
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_skies  # noqa: E402
import goldsrc_bsp as gb  # noqa: E402


def convert(name):
    for root in ("valve_hd", "valve"):
        src = os.path.join(gb.HL1_ROOT, root, "gfx", "env")
        if os.path.exists(os.path.join(src, name + "rt.tga")):
            break
    else:
        print("missing sky", name)
        return None
    for f in ("rt", "bk", "lf", "ft", "up", "dn"):
        p = os.path.join(src, name + f + ".tga")
        if os.path.exists(p):
            Image.open(p).convert("RGB").save(os.path.join(make_skies.SKY, "hl1_%s%s.png" % (name, f)))
    return make_skies.build("hl1_" + name)


if __name__ == "__main__":
    path = os.path.join(make_skies.ASSETS, "data", "skies.json")
    meta = json.load(open(path))
    for n in sys.argv[1:]:
        m = convert(n)
        if m:
            meta["hl1_" + n] = m
            print(n, "ok")
    json.dump(meta, open(path, "w"), indent=1)
