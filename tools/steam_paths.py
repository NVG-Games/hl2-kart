"""Find the player's own Half-Life installs: HL2_ROOT / HL1_ROOT environment
variables first, then every Steam library listed in libraryfolders.vdf."""
import os
import re
import sys


def _steam_dirs():
    out = []
    if sys.platform == "win32":
        try:
            import winreg
            for hive, key in ((winreg.HKEY_CURRENT_USER, r"Software\Valve\Steam"),
                              (winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\WOW6432Node\Valve\Steam")):
                try:
                    with winreg.OpenKey(hive, key) as k:
                        for name in ("SteamPath", "InstallPath"):
                            try:
                                out.append(winreg.QueryValueEx(k, name)[0])
                            except OSError:
                                pass
                except OSError:
                    pass
        except ImportError:
            pass
        out += [r"C:\Program Files (x86)\Steam", r"C:\Program Files\Steam"]
    else:
        home = os.path.expanduser("~")
        out += [os.path.join(home, ".steam", "steam"), os.path.join(home, ".local", "share", "Steam"),
                os.path.join(home, "Library", "Application Support", "Steam")]
    return [d for d in out if d and os.path.isdir(d)]


def steam_libraries():
    libs = []
    for steam in _steam_dirs():
        libs.append(steam)
        vdf = os.path.join(steam, "steamapps", "libraryfolders.vdf")
        if os.path.exists(vdf):
            text = open(vdf, encoding="utf-8", errors="replace").read()
            libs += [p.replace("\\\\", "\\") for p in re.findall(r'"path"\s+"([^"]+)"', text)]
    seen = []
    for lib in libs:
        if lib not in seen and os.path.isdir(lib):
            seen.append(lib)
    return seen


def find_game(folder, env):
    if os.environ.get(env):
        return os.environ[env]
    for lib in steam_libraries():
        p = os.path.join(lib, "steamapps", "common", folder)
        if os.path.isdir(p):
            return p
    return os.path.join("C:\\Program Files (x86)\\Steam\\steamapps\\common", folder)


HL2_ROOT = find_game("Half-Life 2", "HL2_ROOT")
HL1_ROOT = find_game("Half-Life", "HL1_ROOT")

if __name__ == "__main__":
    print("Half-Life 2:", HL2_ROOT, "(found)" if os.path.isdir(HL2_ROOT) else "(MISSING)")
    print("Half-Life:  ", HL1_ROOT, "(found)" if os.path.isdir(HL1_ROOT) else "(MISSING)")
