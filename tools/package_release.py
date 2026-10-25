"""Builds the Windows release downloads: HL2Kart-v<version>-windows.zip and
HL2Kart-v<version>-windows.exe (the same zip inside a one-file launcher).

It holds the game's code (this repository), Godot 4.7 (MIT license) and an
embedded Python with numpy and Pillow, so players need nothing but their own
Half-Life 2 and Half-Life. No Valve content goes into it: on the first start
the game builds that from the player's games (scenes/boot.tscn).

The .exe is built with the C# compiler that ships with Windows (.NET Framework
4.8, tools/launcher/Launcher.cs); elsewhere only the zip is made.

usage: python tools/package_release.py [--out dist] [--cache .cache/release]
"""
import argparse
import io
import json
import os
import shutil
import subprocess
import sys
import urllib.request
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))

GODOT = "4.7.2-stable"
PYTHON = "3.12.10"
GODOT_ZIP = "https://github.com/godotengine/godot/releases/download/{v}/Godot_v{v}_win64.exe.zip"
GODOT_RAW = "https://raw.githubusercontent.com/godotengine/godot/{v}/{f}"
PYTHON_ZIP = "https://www.python.org/ftp/python/{v}/python-{v}-embed-amd64.zip"
PY_PACKAGES = ["numpy", "pillow"]
# repository paths that stay out of the download
SKIP = ("docs/", ".github/", ".gitattributes", ".gitignore", "tools/launcher/")


def log(*a):
    print("[package]", *a, flush=True)


def fetch(url, cache):
    os.makedirs(cache, exist_ok=True)
    path = os.path.join(cache, url.rsplit("/", 1)[-1])
    if not os.path.exists(path):
        log("download", url)
        req = urllib.request.Request(url, headers={"User-Agent": "hl2kart-package"})
        with urllib.request.urlopen(req) as r, open(path + ".part", "wb") as f:
            shutil.copyfileobj(r, f)
        os.replace(path + ".part", path)
    return path


def copy_sources(stage):
    files = subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True, text=True, check=True).stdout.split("\n")
    n = 0
    for rel in files:
        if not rel or rel.startswith(SKIP) or rel.startswith("assets/"):
            continue
        dst = os.path.join(stage, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(os.path.join(ROOT, rel), dst)
        n += 1
    log("sources:", n, "files")


def add_godot(stage, cache):
    gdir = os.path.join(stage, "runtime", "godot")
    os.makedirs(gdir, exist_ok=True)
    with zipfile.ZipFile(fetch(GODOT_ZIP.format(v=GODOT), cache)) as z:
        for name in z.namelist():
            base = os.path.basename(name)
            if base.endswith("_console.exe"):
                target = "godot_console.exe"
            elif base.endswith(".exe"):
                target = "godot.exe"
            else:
                continue
            with z.open(name) as src, open(os.path.join(gdir, target), "wb") as dst:
                shutil.copyfileobj(src, dst)
    lic = os.path.join(stage, "runtime", "licenses", "godot")
    os.makedirs(lic, exist_ok=True)
    for f in ("LICENSE.txt", "COPYRIGHT.txt"):
        shutil.copy(fetch(GODOT_RAW.format(v=GODOT, f=f), os.path.join(cache, "godot-" + GODOT)), os.path.join(lic, f))
    return os.path.join(gdir, "godot_console.exe")


def add_python(stage, cache):
    pdir = os.path.join(stage, "runtime", "python")
    with zipfile.ZipFile(fetch(PYTHON_ZIP.format(v=PYTHON), cache)) as z:
        z.extractall(pdir)
    site = os.path.join(pdir, "Lib", "site-packages")
    tag = "".join(PYTHON.split(".")[:2])
    subprocess.run([sys.executable, "-m", "pip", "install", "--quiet", "--disable-pip-version-check",
                    "--target", site, "--only-binary=:all:", "--platform", "win_amd64",
                    "--python-version", PYTHON.rsplit(".", 1)[0], "--implementation", "cp"] + PY_PACKAGES, check=True)
    # the embedded Python ignores PYTHONPATH: its ._pth file lists every import path
    pth = os.path.join(pdir, "python%s._pth" % tag)
    lines = [l.strip() for l in open(pth) if l.strip() and not l.startswith("#")]
    lines += ["Lib\\site-packages", "..\\..\\tools", "import site"]
    with open(pth, "w") as f:
        f.write("\n".join(lines) + "\n")
    for d, subdirs, _ in os.walk(site):
        for s in list(subdirs):
            if s == "__pycache__" or s == "tests":
                shutil.rmtree(os.path.join(d, s), ignore_errors=True)
    lic = os.path.join(stage, "runtime", "licenses", "python")
    os.makedirs(lic, exist_ok=True)
    shutil.copy(os.path.join(pdir, "LICENSE.txt"), os.path.join(lic, "LICENSE.txt"))
    for d in os.listdir(site):
        if not d.endswith(".dist-info"):
            continue
        pkg = d.split("-")[0]
        for sub, _, files in os.walk(os.path.join(site, d)):
            for f in files:
                if f.upper().startswith(("LICENSE", "COPYING")) or os.path.basename(sub) == "licenses":
                    shutil.copy(os.path.join(sub, f), os.path.join(lic, pkg + "-" + f))


def write_notes(stage, version):
    open(os.path.join(stage, "runtime", ".gdignore"), "w").close()
    with open(os.path.join(stage, "THIRD_PARTY.md"), "w", encoding="utf-8") as f:
        f.write("""# Third-party software in this download

- Godot Engine %s, MIT license: runtime/godot/godot.exe. License and the
  copyright notices of the libraries it contains: runtime/licenses/godot/.
- Python %s (embeddable package), PSF license: runtime/python/.
- NumPy and Pillow, BSD / MIT-CMU style licenses: runtime/python/Lib/site-packages/.

Licenses: runtime/licenses/.

Half-Life 2 and Half-Life content is NOT included. It belongs to Valve Corporation;
the game builds it on your computer from your own copies (see LEGAL.md).
""" % (GODOT.split("-")[0], PYTHON))
    with open(os.path.join(stage, "READ ME FIRST.txt"), "w", encoding="utf-8") as f:
        f.write("""Half-Life 2: Kart v%s  (free fan project, not affiliated with Valve)

1. Have Half-Life 2 and Half-Life installed on Steam.
2. Double-click "Play HL2 Kart.bat".
3. The first start builds the game from your two games (3-6 minutes, about 2 GB).
   Then the menu opens. Later starts go straight to the menu.

If Windows SmartScreen warns about an unknown app: More info -> Run anyway.
Problems, ideas, help: https://github.com/NVG-Games/hl2-kart

Nothing from Valve is in this download, and please do not share the "assets"
folder the game builds: that content belongs to Valve (see LEGAL.md).
""" % version)


CSC = os.path.join(os.environ.get("WINDIR", r"C:\Windows"), "Microsoft.NET", "Framework64", "v4.0.30319", "csc.exe")


def build_exe(zip_path, out_exe, version):
    """One-file launcher: the zip as an embedded resource, unpacked on first run."""
    if not os.path.exists(CSC):
        log("no C# compiler (%s): skipping the .exe" % CSC)
        return None
    src = open(os.path.join(HERE, "launcher", "Launcher.cs"), encoding="utf-8").read().replace("@VERSION@", version)
    tmp = os.path.join(os.path.dirname(out_exe), "Launcher.cs")
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(src)
    cmd = [CSC, "/nologo", "/target:winexe", "/optimize+", "/platform:anycpu",
           "/out:" + out_exe, "/win32icon:" + os.path.join(HERE, "launcher", "icon.ico"),
           "/resource:%s,payload.zip" % zip_path,
           "/r:System.IO.Compression.dll", "/r:System.IO.Compression.FileSystem.dll",
           "/r:System.Windows.Forms.dll", "/r:System.Drawing.dll", tmp]
    subprocess.run(cmd, check=True)
    os.remove(tmp)
    log("done: %s (%.0f MB)" % (out_exe, os.path.getsize(out_exe) / 1e6))
    return out_exe


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=os.path.join(ROOT, "dist"))
    ap.add_argument("--cache", default=os.path.join(ROOT, ".cache", "release"))
    a = ap.parse_args()
    version = json.load(open(os.path.join(ROOT, "version.json")))["version"]
    name = "HL2Kart-v%s-windows" % version
    stage = os.path.join(a.out, "HL2Kart")
    if os.path.exists(stage):
        shutil.rmtree(stage)
    os.makedirs(stage)
    copy_sources(stage)
    godot = add_godot(stage, a.cache)
    add_python(stage, a.cache)
    write_notes(stage, version)
    # Godot's class cache, so the first-start screen runs before any content exists
    log("godot --import")
    subprocess.run([godot, "--headless", "--path", stage, "--import"], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if not os.path.exists(os.path.join(stage, ".godot", "global_script_class_cache.cfg")):
        raise SystemExit("Godot import did not produce the class cache")
    out_zip = os.path.join(a.out, name + ".zip")
    log("zip", out_zip)
    with zipfile.ZipFile(out_zip, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for d, _, files in os.walk(stage):
            for f in files:
                p = os.path.join(d, f)
                z.write(p, os.path.join("HL2Kart", os.path.relpath(p, stage)))
    log("done: %s (%.0f MB)" % (out_zip, os.path.getsize(out_zip) / 1e6))
    build_exe(out_zip, os.path.join(a.out, name + ".exe"), version)
    print(out_zip)


if __name__ == "__main__":
    main()
