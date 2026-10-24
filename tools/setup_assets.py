"""Builds everything in assets/ from your own Half-Life 2 and Half-Life installs.

The repository ships code only: models, textures, sounds, music, maps and fonts
belong to Valve and are extracted here, on the player's machine.

usage: python tools/setup_assets.py [--godot <path to Godot 4.7>] [--from <step>] [--only <step>]
steps: extract, music, skies, highway17, maps, tracks, import, ui
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
ASSETS = os.path.join(ROOT, "assets")
sys.path.insert(0, HERE)
from steam_paths import HL1_ROOT, HL2_ROOT, steam_libraries  # noqa: E402

# converted maps: key -> (converter, scale, BSP names)
MAPS = [
    ("ct17", "source_world.py", 1.8, ["d1_trainstation_02"]),
    ("xen", "goldsrc_world.py", 4.0, ["xen_dm"]),
    ("black_mesa", "goldsrc_world.py", 3.0, ["rapidcore"]),
    ("surface_tension", "goldsrc_world.py", 2.5, ["c2a5w"]),
]
HL1_SKIES = ["desert", "alien1"]
WEATHER = ["sky_day01_01", "sky_day01_05", "sky_day02_09", "sky_day01_08", "sky_day03_06"]
STEPS = ["extract", "music", "skies", "highway17", "maps", "tracks", "import", "ui"]


def log(*a):
    print("[setup]", *a, flush=True)


def run(args, cwd=HERE):
    log(" ".join(str(x) for x in args))
    r = subprocess.run([str(x) for x in args], cwd=cwd)
    if r.returncode != 0:
        raise SystemExit("step failed: %s" % " ".join(str(x) for x in args))


def py(script, *args):
    run([sys.executable, os.path.join(HERE, script)] + list(args))


def find_godot(given):
    if given:
        return given
    if os.environ.get("GODOT"):
        return os.environ["GODOT"]
    for lib in steam_libraries():
        for exe in ("godot.windows.opt.tools.64.exe", "godot.linuxbsd.editor.x86_64",
                    "Godot.app/Contents/MacOS/Godot"):
            p = os.path.join(lib, "steamapps", "common", "Godot Engine", exe)
            if os.path.exists(p):
                return p
    for name in ("godot", "godot4", "Godot"):
        p = shutil.which(name)
        if p:
            return p
    return None


def music_index():
    """assets/data/music.json: the soundtrack in album order with readable titles (menu jukebox)."""
    d = os.path.join(ASSETS, "sound", "music")
    out = []
    for f in sorted(os.listdir(d)):
        if not f.endswith(".mp3"):
            continue
        i = f[:-4]
        m = re.match(r"(hl1|hl2|vlvx)_song(\d+)([a-z]?)(?:_(.*))?$", i)
        if m:
            album = {"hl1": "Half-Life", "hl2": "Half-Life 2", "vlvx": "Bonus"}[m.group(1)]
            title = "Song %s%s" % (m.group(2), m.group(3))
            if m.group(4):
                suf = re.sub(r"(\D)(\d)", r"\1 \2", m.group(4)).replace("_", " ").title()
                title += " (%s)" % suf
            key = (["hl1", "hl2", "vlvx"].index(m.group(1)), int(m.group(2)), m.group(3), m.group(4) or "")
        else:
            album = "Half-Life 2"
            title = {"hl2_intro": "Intro", "radio1": "Radio", "ravenholm_1": "Ravenholm"}.get(i, i)
            key = (1, -1, "", i)
        out.append((key, {"id": i, "album": album, "title": title}))
    out = [o for k, o in sorted(out, key=lambda x: x[0])]
    with open(os.path.join(ASSETS, "data", "music.json"), "w") as f:
        json.dump(out, f, indent=1)
    log("music.json:", len(out), "tracks")


def weather_cards():
    """assets/ui/skies/<sky>.png: a strip of each weather panorama for the menu."""
    from PIL import Image
    os.makedirs(os.path.join(ASSETS, "ui", "skies"), exist_ok=True)
    for s in WEATHER:
        im = Image.open(os.path.join(ASSETS, "sky", "%s_pano.png" % s)).convert("RGB")
        w, h = im.size
        crop = im.crop((int(w * 0.30), int(h * 0.18), int(w * 0.30) + int(w * 0.32), int(h * 0.18) + int(w * 0.32 * 0.45)))
        crop.resize((384, 172), Image.LANCZOS).save(os.path.join(ASSETS, "ui", "skies", "%s.png" % s))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--godot", help="Godot 4.7 executable (default: $GODOT, the Steam copy, or godot on PATH)")
    ap.add_argument("--from", dest="start", choices=STEPS, help="resume from this step")
    ap.add_argument("--only", choices=STEPS, help="run just this step")
    a = ap.parse_args()
    steps = [a.only] if a.only else STEPS[STEPS.index(a.start):] if a.start else STEPS
    t0 = time.time()

    log("Half-Life 2:", HL2_ROOT, "" if os.path.isdir(HL2_ROOT) else "(NOT FOUND)")
    log("Half-Life:  ", HL1_ROOT, "" if os.path.isdir(HL1_ROOT) else "(NOT FOUND)")
    if not os.path.isdir(os.path.join(HL2_ROOT, "hl2")):
        raise SystemExit("Half-Life 2 is needed (Steam app 220). Install it, or set HL2_ROOT to its folder.")
    if not os.path.isdir(os.path.join(HL1_ROOT, "valve")):
        raise SystemExit("Half-Life is needed (Steam app 70) for Gordon, Shephard and the HL1 tracks. "
                         "Install it, or set HL1_ROOT to its folder.")
    if not os.path.isdir(os.path.join(HL2_ROOT, "ep2")):
        log("Episode Two content (ep2/) not found: update Half-Life 2 on Steam, the episodes ship with it "
            "and the muscle car comes from there.")
    godot = find_godot(a.godot)
    if ("import" in steps or "ui" in steps) and not godot:
        raise SystemExit("Godot 4.7 not found: pass --godot <path> or set GODOT.")

    for step in steps:
        log("==== %s" % step)
        if step == "extract":
            py("extract_all.py")
        elif step == "music":
            music_index()
        elif step == "skies":
            py("make_skies.py")
            py("hl1_skies.py", *HL1_SKIES)
            weather_cards()
        elif step == "highway17":
            py("build_track.py")
        elif step == "maps":
            for key, tool, scale, bsps in MAPS:
                py(tool, key, scale, *bsps)
        elif step == "tracks":
            for key, _, _, _ in MAPS:
                py("bsp_track.py", os.path.join("tracks", key + ".json"))
        elif step == "import":
            run([godot, "--headless", "--path", ROOT, "--import"], cwd=ROOT)
        elif step == "ui":
            # portraits, vehicle / item icons, menu backgrounds and track cards (needs a window)
            run([godot, "--path", ROOT, "--resolution", "1920x1080", "res://tests/render_ui_assets.tscn", "--", "all"], cwd=ROOT)
            run([godot, "--headless", "--path", ROOT, "--import"], cwd=ROOT)
    log("done in %.0f min" % ((time.time() - t0) / 60.0))


if __name__ == "__main__":
    main()
