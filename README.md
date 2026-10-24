# Half-Life 2: Kart

A Mario Kart–style kart racer for Godot 4.7, made from your own copies of
Half-Life 2 and Half-Life. Racers, vehicles, maps, sounds, voices and music all
come straight out of the games' files.

> **Free and non-commercial fan project, not affiliated with Valve.** This
> repository holds the code only. To play you need Half-Life 2 and Half-Life on
> Steam: a setup script builds the game's assets from them on your computer.
> See [LEGAL.md](LEGAL.md).

[Русская версия](README.ru.md)

## What's in it

- **12 racers:** Alyx, Barney, Kleiner, Eli, Father Grigori, Dr. Breen, G-Man,
  a Metrocop, a Vortigaunt, a Zombie and, from Half-Life, Gordon Freeman and
  Adrian Shephard. Each one talks with their own lines from the games.
- **6 vehicles:** the HL2 scout car, Gordon's Episode Two muscle car, the
  Combine APC, a military APC, Dog (carrying the racer on his shoulders) and a
  bathtub on wheels. Each has its own speed, acceleration, weight, handling and
  engine sound.
- **5 tracks:**

  | Track | Where it comes from |
  |---|---|
  | Highway 17 | Built from HL2 parts: City 17 streets, a Combine checkpoint, the coast road and the canal |
  | CT17 | The City 17 station plaza, HL2 map `d1_trainstation_02` |
  | Xen | Floating islands of the border world, HL1 map `xen_dm` |
  | Black Mesa | Corridors around a reactor core, HL1 map `rapidcore` |
  | Surface Tension | The desert canyon outside Black Mesa with cactus and red rock, HL1 map `c2a5w` |

  The real maps are converted with their baked lightmaps, so they look the way
  they do in the games.
- **Items** from HL2 supply crates: a homing manhack, a rollermine, an explosive
  barrel, a HEV battery boost, the gravity gun, a headcrab canister strike on the
  leader and a HEV charger shield.
- **Drifting and boosts:** hold jump in a turn, let AUX POWER charge, release for
  a mini or super turbo. Hold the throttle on "one" for a rocket start.
- **Multiplayer:** LAN and internet, a Half-Life style server browser, lobby with
  chat, bots that fill empty grid slots, a dedicated server and a master server.
- **Source-style look and physics:** VertexLitGeneric and LightmappedGeneric
  style shaders, HL2 skyboxes, `sv_gravity 600`, vehicle and surface properties
  read from the game scripts, the HL2 soundtrack.

## Requirements

- Windows 10 or 11 (the tools also handle Linux Steam paths, but only Windows is
  tested).
- On Steam: **Half-Life 2** (it includes Episode One and Two) and **Half-Life**.
- **Godot 4.7** (standard build, not .NET). The free "Godot Engine" on Steam or a
  download from [godotengine.org](https://godotengine.org).
- **Python 3.10+** with `numpy` and `Pillow`.
- About 2 GB of free disk space.

## Setup

```bash
git clone https://github.com/NVG-Games/hl2-kart.git
cd hl2-kart
pip install numpy pillow
python tools/setup_assets.py
```

The script finds both games through your Steam libraries and Godot through the
`GODOT` environment variable, the Steam copy, or `godot` on `PATH`. If something
lives elsewhere, set `HL2_ROOT` / `HL1_ROOT` to the game folders or pass
`--godot <path>`. It extracts models, textures, sounds, music and fonts, builds
the skies, Highway 17, the four converted maps and their race lines, imports
everything into Godot and renders the menu pictures. At the end Godot opens a
window for a few minutes to render those pictures; let it finish.

A step can be repeated or resumed: `--only maps`, `--from tracks`
(steps: `extract, music, skies, highway17, maps, tracks, import, ui`).

## Playing

Double-click `Play HL2 Kart.bat`, run `godot --path .` in the folder, or open
`project.godot` in the Godot editor and press F5.

| Action | Keyboard | Gamepad |
|---|---|---|
| Throttle | W / ↑ | A, right trigger |
| Brake / reverse | S / ↓ | X, left trigger |
| Steer | A / D, ← / → | left stick |
| Jump and drift | Shift / Space | RB |
| Use item | E / Ctrl / Enter | LB, B |
| Chat (online) | Y / T | |
| Look back | C | Y |
| Rescue (scanner) | R | Back |
| Pause | Esc / P | Start |

**NEW RACE** picks the racer, vehicle, difficulty, laps and track (weather is
offered on Highway 17; the converted maps keep their own sky). **HOW TO PLAY**
opens by itself on the first start.

## Multiplayer

The networking works like Source servers: UDP 27015 for the game, 27016 for the
server browser and LAN discovery, and optionally a master server on UDP 27010
for the INTERNET tab.

**Hosting.** Press CREATE SERVER and set the name, password, player limit, bots
(fill the grid up to a size, or off for people only), laps, difficulty, track
and weather. The host races too.

**Joining.** FIND SERVERS: on the same network the server shows up under LAN.
Over the internet, type the host's public address in "Connect to address". If
the host's router has no UPnP, forward UDP 27015–27016 by hand, or play over a
virtual LAN (Radmin VPN, ZeroTier, Tailscale).

**Lobby.** Everyone picks a nickname, racer and vehicle; ping and ready state are
shown. The host changes the rules, kicks players and starts the race; when
everyone is READY it starts by itself after 5 seconds. A player who leaves
mid-race is replaced by a bot.

**Dedicated server** (no window, srcds-like console):

```bash
godot --headless --path . -- --dedicated --name "City 17 GP" --max 8 --bots on --laps 3 --track surface_tension
```

Settings can go in `server.cfg` (see `server.cfg.example`). Console commands:
`status`, `say <text>`, `kick <nick>`, `start`, `lobby`, `set <cvar> <value>`,
`quit`. Track ids: `city17_circuit`, `ct17`, `xen`, `black_mesa`,
`surface_tension`.

**Master server** for the INTERNET tab, on any machine with UDP 27010 open:

```bash
godot --headless --path . -- --master-server --port 27010
```

Players enter its address in the INTERNET tab, servers in `sv_master` or with
`--master host:27010`.

Every player needs their own built copy of the game (this repository plus the
setup with their own Half-Life games), servers included.

## Sharing it with friends

- Share the link to this repository. Each person clones it and runs the setup
  with their own Half-Life 2 and Half-Life.
- Do **not** upload the `assets/` folder, extracted files or an exported build of
  the game anywhere: not on GitHub, not on file hosts, not in chats. That content
  belongs to Valve.
- Forks, mods and new tracks are welcome under the same non-commercial license.
- Running a public server is fine; selling anything is not.

## For developers

- `scripts/`: the game (GDScript). `shaders/`: Source-style shaders.
- `tools/`: Python converters. VPK reader, MDL/VVD/VTX and GoldSrc MDL to glTF,
  VTF to PNG, VMT materials, HL2 and HL1 BSP to Godot worlds with lightmaps
  (`source_world.py`, `goldsrc_world.py`), and race lines laid on a converted map
  (`bsp_track.py` with the track definitions in `tools/tracks/`).
- `tests/`: headless AI races with stats (`race_stats.tscn`), screenshot tours,
  menu shots, network client/host walkthroughs and a compile check of every
  script (`check_scripts.tscn`).

New track from a Half-Life map: convert it with `goldsrc_world.py` /
`source_world.py`, write a definition in `tools/tracks/`, build it with
`bsp_track.py`, then add it to `TRACKS` in `scripts/core/game.gd`.

## License

The code is © NVG Games under the [PolyForm Noncommercial License 1.0.0](LICENSE.md):
free to use, change and share for any non-commercial purpose. Half-Life content
is © Valve Corporation and is not included; see [LEGAL.md](LEGAL.md).
