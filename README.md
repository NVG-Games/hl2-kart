<p align="center">
  <img src="docs/media/banner.jpg" alt="Half-Life 2: Kart">
</p>

<p align="center">
  <b>A Mario Kart–style racer for Godot 4.7, built from your own copies of Half-Life 2 and Half-Life.</b><br>
  Five long circuits · 12 racers · 6 vehicles · HL2 items · drifting and boosts · LAN and internet multiplayer
</p>

<p align="center">
  <img alt="Godot 4.7" src="https://img.shields.io/badge/Godot-4.7-478cbf?logo=godotengine&logoColor=white">
  <img alt="License: PolyForm Noncommercial" src="https://img.shields.io/badge/license-PolyForm%20Noncommercial-orange">
  <img alt="Platform: Windows" src="https://img.shields.io/badge/platform-Windows-0078d6">
  <img alt="Fan project, not affiliated with Valve" src="https://img.shields.io/badge/fan%20project-not%20affiliated%20with%20Valve-555">
</p>

<p align="center"><a href="README.ru.md">Русская версия</a></p>

> **Free, non-commercial fan project, not affiliated with Valve.** This repository holds
> the code only. To play you need **Half-Life 2** and **Half-Life** on Steam: one script
> builds every model, texture, sound and track from them on your own computer.
> See [LEGAL.md](LEGAL.md).

## The circuits

Every lap is about 2 km and a minute long. The road, walls, tunnels and bridges are
built by the track tools, then dressed with the games' own textures, models, skies,
signs and music.

<table>
  <tr>
    <td width="50%"><img src="docs/media/city17_circuit.webp" alt="Highway 17"></td>
    <td width="50%"><img src="docs/media/ct17.webp" alt="CT17"></td>
  </tr>
  <tr>
    <td><b>Highway 17</b><br>Out of City 17 through the Combine checkpoint, down the coast road with a jump over the inlet, back up the canal. Pick the weather.</td>
    <td><b>CT17</b><br>Combine-held City 17: the station plaza under the Breencasts, the cobbled old town, a checkpoint, a jump over the canal, the rail yard and an underpass.</td>
  </tr>
  <tr>
    <td><img src="docs/media/black_mesa.webp" alt="Black Mesa"></td>
    <td><img src="docs/media/xen.webp" alt="Xen"></td>
  </tr>
  <tr>
    <td><b>Black Mesa</b><br>Indoors through the Research Facility: the Sector C lobby, labs, the tram tunnel, a storage hall, toxic waste with a jump over a slime pit, and a spiral around the Lambda reactor core. The VOX announcer is on.</td>
    <td><b>Xen</b><br>Floating islands over the void: light stalks, crystals and fungus, two jumps across chasms, a glowing cave and the Nihilanth watching from afar.</td>
  </tr>
  <tr>
    <td><img src="docs/media/surface_tension.webp" alt="Surface Tension"></td>
    <td><img src="docs/media/surface_tension.jpg" alt="Surface Tension, the dam"></td>
  </tr>
  <tr>
    <td colspan="2"><b>Surface Tension</b><br>The desert outside Black Mesa: red-rock canyons and cactus, a washed-out road to jump, the steel bridge over the river gorge, the HECU camp by a landed Osprey, an old mine tunnel and the crest of the dam.</td>
  </tr>
</table>

## Racers and vehicles

<p align="center"><img src="docs/media/racers.jpg" alt="Racers"></p>

Alyx, Barney, Kleiner, Eli, Father Grigori, Dr. Breen, the G-Man, a Metrocop, a
Vortigaunt and a Zombie from Half-Life 2, plus Gordon Freeman and Adrian Shephard
from Half-Life. Each one talks with their own lines from the games.

<p align="center"><img src="docs/media/vehicles.jpg" alt="Vehicles"></p>

The scout car, Gordon's muscle car from Episode Two, the Combine APC, a military APC,
Dog (carrying the racer on his shoulders) and a bathtub on wheels, each with its own
speed, acceleration, weight, handling and engine sound.

## Features

- **Items** from HL2 supply crates: a homing manhack, a rollermine, an explosive barrel,
  a HEV battery boost, the gravity gun, a headcrab canister strike on the leader and a
  HEV charger shield.
- **Drifting:** hold jump in a turn, let AUX POWER charge and release for a mini or
  super turbo. Hold the throttle on "one" for a rocket start.
- **Rescue:** fall off or get wedged and a Combine scanner lifts you back onto the road.
- **Multiplayer:** LAN and internet, a Half-Life style server browser, a lobby with chat,
  bots for the empty grid slots, a dedicated server and a master server.
- **Source look and feel:** VertexLitGeneric / LightmappedGeneric style shaders, HL2 and
  HL1 skyboxes, `sv_gravity 600`, vehicle and surface properties read from the game
  scripts, HL2 and HL1 music.

<table>
  <tr>
    <td width="33%"><img src="docs/media/menu.jpg" alt="Main menu"></td>
    <td width="33%"><img src="docs/media/new_race.jpg" alt="New race"></td>
    <td width="33%"><img src="docs/media/lobby.jpg" alt="Lobby"></td>
  </tr>
  <tr>
    <td align="center">Main menu</td>
    <td align="center">New race</td>
    <td align="center">Online lobby</td>
  </tr>
</table>

## Getting started

You need:

- Windows 10 or 11 (the tools also know Linux Steam paths, but only Windows is tested);
- **Half-Life 2** (it includes Episode One and Two) and **Half-Life** on Steam;
- **Godot 4.7**, the standard build (the free "Godot Engine" on Steam, or
  [godotengine.org](https://godotengine.org));
- **Python 3.10+** with `numpy` and `Pillow`;
- about 2 GB of free disk space.

```bash
git clone https://github.com/NVG-Games/hl2-kart.git
cd hl2-kart
pip install numpy pillow
python tools/setup_assets.py
```

The setup finds both games through your Steam libraries and Godot through `GODOT`, the
Steam copy or `godot` on `PATH` (otherwise set `HL2_ROOT` / `HL1_ROOT` or pass
`--godot <path>`). It extracts the game content, builds the five circuits, imports
everything into Godot and renders the menu pictures; Godot opens a window for a few
minutes at the end. A single step can be repeated with `--only <step>` or resumed with
`--from <step>` (`extract, music, skies, highway17, tracks, import, ui`).

Then double-click `Play HL2 Kart.bat`, or run `godot --path .`.

## Controls

| Action | Keyboard | Gamepad |
|---|---|---|
| Throttle | W / ↑ | A, right trigger |
| Brake / reverse | S / ↓ | X, left trigger |
| Steer | A / D, ← / → | left stick |
| Jump and drift | Shift / Space | RB |
| Use item | E / Ctrl / Enter | LB, B |
| Chat (online) | Y / T | |
| Look back | C | Y |
| Call the scanner | R | Back |
| Pause | Esc / P | Start |

## Multiplayer

The networking works like Source servers: UDP 27015 for the game, 27016 for the server
browser and LAN discovery, and optionally a master server on UDP 27010 for the INTERNET
tab.

- **Host:** CREATE SERVER, set the name, password, player limit, bots, laps, difficulty,
  track and weather. The host races too.
- **Join:** FIND SERVERS. On the same network the server shows up under LAN; over the
  internet type the host's address. Without UPnP on the host's router, forward UDP
  27015–27016 or play over a virtual LAN (Radmin VPN, ZeroTier, Tailscale).
- **Lobby:** pick a nickname, racer and vehicle; the host changes the rules and starts.
  A player who leaves mid-race is replaced by a bot.

Dedicated server (no window, srcds-like console; settings can also go in `server.cfg`,
see `server.cfg.example`):

```bash
godot --headless --path . -- --dedicated --name "City 17 GP" --max 8 --bots on --laps 3 --track xen
```

Track ids: `city17_circuit`, `ct17`, `black_mesa`, `xen`, `surface_tension`.
Console: `status`, `say <text>`, `kick <nick>`, `start`, `lobby`, `set <cvar> <value>`, `quit`.

Master server for the INTERNET tab, on any machine with UDP 27010 open:

```bash
godot --headless --path . -- --master-server --port 27010
```

## Sharing it with friends

- Share the link to this repository. Each person clones it and runs the setup with
  their own Half-Life 2 and Half-Life, servers included.
- Do **not** upload the `assets/` folder, extracted files or an exported build anywhere.
  That content belongs to Valve.
- Forks, mods and new tracks are welcome under the same non-commercial license.

## For developers

- `scripts/`: the game (GDScript). `shaders/`: Source-style shaders.
- `tools/`: Python. VPK, MDL/VVD/VTX, GoldSrc MDL, VTF, VMT and WAD readers;
  `build_track.py` builds Highway 17, `track_gen.py` builds the other circuits from the
  definitions in `tools/circuits/` (a spline of styled stretches: street, open road,
  tunnel or hall, bridge, cutting, jump), with their terrain, props, lights and signs.
  `source_world.py` / `goldsrc_world.py` convert whole HL2 / HL1 maps if you want to
  experiment with real levels.
- `tests/`: headless AI races with stats (`race_stats.tscn`), photo tours, menu layout
  checks (`ui_fit.tscn`), network walkthroughs and a compile check of every script.

A new circuit is one Python module in `tools/circuits/` plus an entry in `TRACKS` in
`scripts/core/game.gd`.

## License

The code is © NVG Games under the [PolyForm Noncommercial License 1.0.0](LICENSE.md):
free to use, change and share for any non-commercial purpose. Half-Life content is ©
Valve Corporation and is not included; see [LEGAL.md](LEGAL.md).
