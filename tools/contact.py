"""Contact sheet of material base textures: python contact.py out.png pattern [pattern...]"""
import sys

sys.path.insert(0, ".")
from PIL import Image, ImageDraw

import materials
import srcfs
import vtf

fs = srcfs.GameFS()
lib = materials.MaterialLib(fs, ".")
out = sys.argv[1]
pats = sys.argv[2:]
vm = fs.glob(lambda k: k.startswith("materials/") and k.endswith(".vmt") and any(p in k for p in pats))
cell = 160
cols = 10
imgs = []
for k in vm[:150]:
    name = k[10:-4]
    sh, p = lib.load_vmt(name)
    if not p or "$basetexture" not in p:
        continue
    d = fs.read("materials/" + p["$basetexture"].lower().replace(chr(92), "/") + ".vtf")
    if not d:
        continue
    try:
        im, _ = vtf.decode(d)
    except Exception:
        continue
    imgs.append((name, im.convert("RGB").resize((cell, cell))))
rows = (len(imgs) + cols - 1) // cols
sheet = Image.new("RGB", (cols * cell, max(1, rows) * (cell + 14)), (30, 30, 30))
dr = ImageDraw.Draw(sheet)
for i, (n, im) in enumerate(imgs):
    x, y = (i % cols) * cell, (i // cols) * (cell + 14)
    sheet.paste(im, (x, y))
    dr.text((x + 2, y + cell), n.split("/")[-1][:26], fill=(255, 255, 0))
sheet.save(out)
print(len(imgs))
