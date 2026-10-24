"""Builds everything in assets/ from your own Half-Life 2 and Half-Life installs.

The repository ships code only: models, textures, sounds, music, maps and fonts
belong to Valve and are extracted here, on the player's machine.

usage: python tools/setup_assets.py [--godot <path to Godot 4.7>] [--from <step>] [--only <step>]
                                    [--hl2 <folder>] [--hl1 <folder>] [--status <file>] [--log <file>]
steps: extract, music, skies, highway17, tracks, import, ui

The game's first-start screen (scenes/boot.tscn) runs this with --status (a JSON
progress file it polls) and --log (all output, for when something goes wrong).
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

# circuits built by track_gen.py (tools/circuits/<name>.py)
CIRCUITS = ["ct17", "black_mesa", "xen", "surface_tension"]
HL1_SKIES = ["desert", "alien1", "xen8", "neb7"]
WEATHER = ["sky_day01_01", "sky_day01_05", "sky_day02_09", "sky_day01_08", "sky_day03_06"]
STEPS = ["extract", "music", "skies", "highway17", "tracks", "import", "ui"]
# share of the total time each step takes (for the progress bar)
WEIGHTS = {"extract": 30, "music": 1, "skies": 6, "highway17": 8, "tracks": 15, "import": 22, "ui": 18}
LABELS = {"extract": "Extracting models, textures, sounds and music", "music": "Indexing the soundtrack",
          "skies": "Building the skies", "highway17": "Building Highway 17",
          "tracks": "Building CT17, Black Mesa, Xen and Surface Tension", "import": "Importing everything into Godot",
          "ui": "Rendering portraits, icons and menu pictures"}

LOG = None  # open file when --log is given: all output goes there
STATUS = None  # path of the JSON progress file when --status is given


def log(*a):
    line = "[setup] " + " ".join(str(x) for x in a)
    print(line, flush=True)
    if LOG:
        LOG.write(line + "\n")
        LOG.flush()


def status(**kw):
    if not STATUS:
        return
    tmp = STATUS + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(kw, f)
    os.replace(tmp, STATUS)


def run(args, cwd=HERE):
    log(" ".join(str(x) for x in args))
    kw = {}
    if LOG:
        kw = {"stdout": LOG, "stderr": subprocess.STDOUT}
        if sys.platform == "win32":
            kw["creationflags"] = subprocess.CREATE_NO_WINDOW
    r = subprocess.run([str(x) for x in args], cwd=cwd, **kw)
    if r.returncode != 0:
        raise SystemExit("step failed (exit code %d): %s" % (r.returncode, " ".join(str(x) for x in args)))


def run_import(godot):
    """Godot's import of thousands of new files now and then dies part way; a second
    pass picks up where it stopped."""
    try:
        run([godot, "--headless", "--path", ROOT, "--import"], cwd=ROOT)
    except SystemExit:
        log("import stopped early, running it again")
        run([godot, "--headless", "--path", ROOT, "--import"], cwd=ROOT)


def py(script, *args):
    run([sys.executable, os.path.join(HERE, script)] + list(args))


def find_godot(given):
    from steam_paths import steam_libraries
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
    global LOG, STATUS, HL1_ROOT, HL2_ROOT, steam_libraries
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--godot", help="Godot 4.7 executable (default: $GODOT, the Steam copy, or godot on PATH)")
    ap.add_argument("--from", dest="start", choices=STEPS, help="resume from this step")
    ap.add_argument("--only", choices=STEPS, help="run just this step")
    ap.add_argument("--hl2", help="Half-Life 2 folder (default: found through Steam)")
    ap.add_argument("--hl1", help="Half-Life folder (default: found through Steam)")
    ap.add_argument("--status", help="write progress as JSON to this file")
    ap.add_argument("--log", help="append all output to this file")
    a = ap.parse_args()
    if a.hl2:
        os.environ["HL2_ROOT"] = a.hl2
    if a.hl1:
        os.environ["HL1_ROOT"] = a.hl1
    STATUS = a.status
    if a.log:
        LOG = open(a.log, "a", encoding="utf-8", errors="replace")
    from steam_paths import HL1_ROOT, HL2_ROOT, steam_libraries  # noqa: E402  (after HL*_ROOT are set)
    steps = [a.only] if a.only else STEPS[STEPS.index(a.start):] if a.start else STEPS
    try:
        build(a, steps)
    except SystemExit as e:
        msg = str(e.code) if e.code not in (None, 0) else ""
        if msg:
            log("FAILED:", msg)
            status(state="error", error=msg, progress=0.0)
        raise
    except Exception as e:  # noqa
        log("FAILED:", repr(e))
        status(state="error", error=repr(e), progress=0.0)
        raise


def build(a, steps):
    from steam_paths import HL1_ROOT, HL2_ROOT  # noqa
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

    total = float(sum(WEIGHTS[s] for s in steps))
    done = 0.0
    for k, step in enumerate(steps):
        log("==== %s" % step)
        status(state="running", step=step, index=k + 1, total=len(steps), message=LABELS[step],
               progress=done / total)
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
        elif step == "tracks":
            py("track_gen.py", *CIRCUITS)
        elif step == "import":
            run_import(godot)
        elif step == "ui":
            # portraits, vehicle / item icons, menu backgrounds and track cards (needs a window)
            run([godot, "--path", ROOT, "--resolution", "1920x1080", "res://tests/render_ui_assets.tscn", "--", "all"], cwd=ROOT)
            run_import(godot)
        done += WEIGHTS[step]
    if steps[-1] == "ui":
        # the content is complete: the game checks this before showing its menu
        ver = json.load(open(os.path.join(ROOT, "version.json")))
        with open(os.path.join(ASSETS, "data", "build.json"), "w") as f:
            json.dump({"content": ver.get("content", 1), "game": ver.get("version", ""), "built": time.strftime("%Y-%m-%d %H:%M")}, f)
    status(state="done", progress=1.0, message="Done")
    log("done in %.0f min" % ((time.time() - t0) / 60.0))


if __name__ == "__main__":
    main()
