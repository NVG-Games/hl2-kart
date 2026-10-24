"""Prints the GitHub release notes for a version: its CHANGELOG.md section plus
how to install. usage: python tools/release_notes.py 0.1.0"""
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))


def section(version):
    text = open(os.path.join(ROOT, "CHANGELOG.md"), encoding="utf-8").read()
    m = re.search(r"^## \[%s\][^\n]*\n(.*?)(?=^## \[|\Z)" % re.escape(version), text, re.M | re.S)
    return m.group(1).strip() if m else "See CHANGELOG.md."


def main():
    v = sys.argv[1]
    print(section(v))
    print("""
## Install

1. You need **Half-Life 2** and **Half-Life** on Steam (Windows).
2. Download `HL2Kart-v%s-windows.zip` below and unzip it anywhere.
3. Run **Play HL2 Kart.bat**. The first start builds the game from your two games
   (3-6 minutes, about 2 GB); after that it starts straight into the menu.

The download holds the game's code, Godot 4.7 and a small Python to build the content.
**Nothing from Valve is included**: models, textures, sounds and music are made on your
computer from your own copies. Free, non-commercial fan project, not affiliated with
Valve; see LEGAL.md.

If Windows SmartScreen warns about an unknown app: *More info* -> *Run anyway*.
""" % v)


if __name__ == "__main__":
    main()
