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
   - an AI race on a track, with stats (lap times, rescues, shortcuts taken, hazard hits):
     `godot --headless --path . res://tests/race_stats.tscn -- 200 4 2 1 <track>`
   - shortcuts and lap counting: `godot --headless --path . res://tests/branch_check.tscn -- <track>`
   - track hazards: `godot --headless --path . res://tests/hazard_test.tscn -- rules <track>`
     and `... -- determinism <track>` (online every PC must see the same hazards)
   - spectators: `godot --headless --path . res://tests/crowd_check.tscn -- <track>`
   - items: `godot --headless --path . res://tests/item_test.tscn -- <track>`
   - gamepads, controls and button icons: `godot --headless --path . res://tests/gamepad_test.tscn`
   - every menu with a pad only (focus, B, LB / RB, OPTIONS > CONTROLS, pause):
     `godot --headless --path . res://tests/pad_nav.tscn` (it loads a race: about a minute)
   - menus fit the window: `godot --path . --resolution 1280x720 res://tests/ui_fit.tscn -- out`
   - the track editor's level files, compiler, validation and registry:
     `godot --headless --path . res://tests/level_test.tscn -- ci` (`-- ci` skips the cases that
     need the Half-Life content; leave it out to run them too, `-- only <name>` runs one case,
     e.g. `-- ci only format` for `tests/level/case_format.gd`)
   - the editor itself (picking, gizmos, tools, layout, the home screen):
     `godot --headless --path . res://tests/editor_test.tscn -- ci` (the same `-- ci` and
     `-- only <name>`, cases in `tests/editor/`)
   - custom tracks online (downloads, START RACE rules, dedicated servers' track folders):
     `godot --headless --path . res://tests/net_track_test.tscn -- unit` (`-- unit only <name>`,
     cases in `tests/net/`); `-- pair 27301` runs a real server with two headless clients that
     download a track (three processes, a few minutes)

   These three runners print `N checks, F failures` and exit 1 on a failure; CI runs them in
   their content-free modes. A parse error leaves Godot waiting, so give a run a timeout. Test
   runs keep their tracks in `user://tracks_test` and their settings in `settings_test.cfg`,
   never in your own.

   After changing a circuit in `tools/`, rebuild its track and import it before testing:
   `python tools/track_gen.py <circuit>` (Highway 17 too: `city17_circuit`), then
   `godot --headless --path . --import`.
4. Open the pull request against **`dev`** and describe what changed and how you tested it.

## Rules about Valve content

- **Never commit anything from Valve's games**: no models, textures, sounds, music,
  maps or fonts, and nothing converted from them. `assets/` is in `.gitignore` for this.
- Content is always built on the player's machine by the tools in `tools/`.
- Tracks made in the TRACK EDITOR (`.hl2kt`) are fine to share: they hold only the
  author's own geometry and name the content they use by key (see `LEGAL.md`).
- Screenshots and short clips of the game for the README or a pull request are fine.

## Ideas for a first contribution

- **A new circuit**: one Python module in `tools/circuits/` (see `ct17.py` or `xen.py`)
  plus an entry in `TRACKS` in `scripts/core/game.gd` and in `CIRCUITS` in
  `tools/setup_assets.py` (so the first start builds it). The module gives the road as a spline
  of styled stretches (`CTRL`), its shortcuts (`BRANCHES`), its hazards (`TRACK["hazards"]`)
  and its spectators (`crowds()`). Ravenholm or the Citadel would
  both be great.
- **More animation**: `tools/mdl_anim.py` reads a model's animations (Dog's run, walk and
  idle are listed in `ANIMS` in `tools/extract_all.py`); the scanner, the strider or the
  spectators could play theirs too.
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
