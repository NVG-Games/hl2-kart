# Contributing to Half-Life 2: Kart

Thanks for wanting to help! Code, tracks, bug reports, testing, translations and ideas
are all welcome. This is a free, non-commercial fan project; by contributing you agree
that your contribution is published under the project's license (PolyForm
Noncommercial 1.0.0, see `LICENSE.md`).

## Branches

- **`dev`** is the default branch: all work lands here through pull requests.
- **`main`** is what players get. It only moves for a release.

Releases: a maintainer bumps `version.json` and `CHANGELOG.md` on `dev`, merges `dev`
into `main`, and the *Release build* workflow drafts a GitHub release with the Windows
download. The maintainer checks the draft and publishes it; the game's update check
then tells players about it.

## Getting set up

1. Have **Half-Life 2** and **Half-Life** on Steam, **Godot 4.7** (standard build) and
   **Python 3.10+** with `numpy` and `Pillow`.
2. Fork the repository, clone your fork, switch to `dev`.
3. Build the content once: `python tools/setup_assets.py` (or just start the game:
   the first-start screen does the same).
4. Open `project.godot` in Godot, or run `godot --path .`.

## Making a change

1. Branch off `dev`: `git switch -c my-change dev`.
2. Keep pull requests focused on one thing.
3. Test what you touched. Useful headless checks:
   - every script compiles: `godot --headless --path . res://tests/check_scripts.tscn`
   - an AI race on a track, with stats:
     `godot --headless --path . res://tests/race_stats.tscn -- 200 4 2 1 <track>`
   - menus fit the window: `godot --path . --resolution 1280x720 res://tests/ui_fit.tscn -- out`
4. Open the pull request against **`dev`** and describe what changed and how you tested it.

## Rules about Valve content

- **Never commit anything from Valve's games**: no models, textures, sounds, music,
  maps or fonts, and nothing converted from them. `assets/` is in `.gitignore` for this.
- Content is always built on the player's machine by the tools in `tools/`.
- Screenshots and short clips of the game for the README or a pull request are fine.

## Ideas for a first contribution

- **A new circuit**: one Python module in `tools/circuits/` (see `ct17.py` or `xen.py`)
  plus an entry in `TRACKS` in `scripts/core/game.gd`. Ravenholm, the Coast, Nova Prospekt,
  White Forest or the Citadel would all be great.
- **Linux support**: the tools already know Linux Steam paths; the release packaging and
  the first-start screen need a Linux path.
- **Gamepad and accessibility**: rebinding controls, colour-blind friendly HUD.
- **Translations** of the menus and the in-game help.
- **Balance**: items, vehicle stats and the AI.

Look at the issues labelled `good first issue` and `help wanted`, or open an issue to
talk about an idea before you start something big.

## Code style

- GDScript: tabs, typed variables where it helps, a `##` comment on every class and on
  any function whose purpose is not obvious from its name.
- Python: 4 spaces, standard library plus numpy and Pillow only.
- Match the code around you.
