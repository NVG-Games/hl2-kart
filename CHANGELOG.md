# Changelog

All notable changes to Half-Life 2: Kart. Versions follow [semantic versioning](https://semver.org):
`MAJOR.MINOR.PATCH` (while in 0.x, MINOR is a feature release and PATCH a fix).

## [0.2.0] - 2026-11-12

Shortcuts, track hazards and spectators on five redesigned circuits. This release also
brings 0.1.1's changes, which never had a download of their own: the one-file `.exe` and a
first start that begins building by itself. Online, everyone needs 0.2.0.

### Added
- Two shortcuts on every circuit, most of them ending in a jump that takes speed:
  - Highway 17: the headland trail, a dirt track over two crests, and the quarry jump straight
    across the flooded quarry.
  - CT17: the canal jump straight over the canal, and the rooftops, a ramp onto the old town's roofs
    and a jump over the street below that needs a suit battery or HEV boost.
  - Black Mesa: the crane gantry along the storage hall's wall, above the slime pit and the turrets
    (you drop off its end back onto the road), and the coolant jump over the broken catwalk.
  - Xen: the high root, a narrow root over the void with no rim at all, and the island hop across
    the bay over two floating rocks.
  - Surface Tension: the rim drop along the canyon's edge, and the washout jump over the river.
- Shortcut signs and hints: chevron boards before and at every fork, a DANGER sign before a risky
  shortcut's jump, and stripes and red lamps on the jump lips. The HUD names a shortcut the first
  time you come up to it, the minimap draws shortcuts as dashes, SHORTCUT! shows when you land one,
  and the results have a SHORTCUTS column (online the same on every screen).
- Missing a shortcut's jump: the scanner puts you back on its run-up for one more try when a
  standing start can still make the jump; otherwise, or after a second miss, you rejoin the main
  road. Fall into the flooded quarry and you are put down past the gap.
- Track hazards, each with a warning before it strikes:
  - Highway 17: a force-field gate at the Combine checkpoint, a gunship strafing the coast road and
    hopper mines on the dirt road.
  - CT17: a Combine train across the rail yard, a strider at the canal corner and floor turrets at
    the checkpoint.
  - Black Mesa: laser tripmines in the offices and labs, ceiling turrets in the storage hall and the
    Lambda core's discharges on the high walk.
  - Xen: houndeye packs, alien slaves throwing lightning and a tentacle by the long bridge.
  - Surface Tension: an Apache over the start straight, sentry guns in the HECU camp and mortars on
    the dam.
- Hazard rules: one run through a group of hazards costs at most one hit, and on EASY they warn
  longer and fire less often. A red chevron at the edge of the screen points at a turret or alien
  slave that has locked on you; the minimap marks hazards with triangles that blink red while they
  fire. TRACK HAZARDS turns them on or off in NEW RACE, CREATE SERVER and the lobby (online the
  host's choice counts for everyone), and `mp_hazards` / `--hazards` on a dedicated server.
- Spectators along every circuit: citizens, refugees, rebels, metrocops, Combine soldiers,
  scientists, security guards, HECU marines, vortigaunts and alien slaves. They cheer the start and
  the finish, react to hits, explosions, falls and headcrabs, and hop out of the way of a kart on an
  open road. Some know your racer: metrocops condemn Gordon and salute Dr. Breen, vortigaunts bow
  to a vortigaunt racer and the marines salute Shephard. Options > Video > Spectators: OFF, FEW or
  FULL.
- Easter eggs: the G-Man turns up now and then from the second lap, and there are more to find.
- Water and slime: drive in and you splash and sink, with a wash of colour over the screen, before
  the scanner hauls you out.
- WRONG WAY: a flashing red warning with a beep while you drive back along the road.
- Tubes: on CT17, Black Mesa, Xen and Surface Tension a stretch of road runs inside a pipe and rolls
  round it (up the wall, over the ceiling, or all the way round twice). Gravity pulls towards the
  pipe wall there and the camera rolls with the kart. Before a pipe ends you are brought back down
  to its bottom, so you leave it upright.
- Open edges: Xen's ledge down to the arch (only a low rim of rock) and its high root, the Surface
  Tension cliff road and rim road, and Black Mesa's coolant road round the core, where the railing
  is torn out in places. Run wide and you fall or swim; the scanner fishes you out.
- A second jump on Black Mesa (the storage hall) and Surface Tension (the HECU camp). CT17's jump on
  the lap is now in the rail yard; the canal jump became a shortcut.
- Seven new items: energy ball (bounces off walls), watermelon and 3x watermelon (spin out whoever
  hits them), hopper mine (jumps at whoever comes close), sawblade (cuts through everyone in front),
  headcrab (covers the faces of up to three racers just ahead for a couple of seconds; only one is
  in play at a time) and Xen teleport (140 m down the road).
- Clusters of explosive barrels on the road.

### Changed
- All five circuits are redesigned, 2.1 to 2.5 km a lap:
  - Highway 17: out through the Combine checkpoint, round the headland, over the inlet, out round a
    flooded quarry and back up the canal.
  - CT17: a figure-8 from the station plaza through a cutting and an underpass, the Combine pipe,
    the rail yard, the canal corner, the checkpoint and the old-town hairpins, over the flyover and
    back along the boulevard.
  - Black Mesa: across the reactor room twice, on the high walk past the core and round it at
    coolant level, with the offices, labs, accelerator, storage hall and waste processing between.
  - Xen: a figure-8 of floating islands with the cave tube, the chasm, an arch over the root bridge,
    the bay and the long bridge.
  - Surface Tension: the canyon, the gorge bridge, the HECU camp, the dam's water main, the cliff
    road and the dam's crest, then a viaduct over the start straight.
- More supply crate rows and boost pads: 8 to 12 of each a lap, and some on the shortcuts. No pad
  lies near the start grid.
- Item odds per race position: the nine original items keep their old proportions and 80 % of
  every position's odds; the seven new ones share the other 20 %, so they turn up now and then.
- Raised decks and walled roads have unseen walls above their barriers, and explosions and hazard
  hits throw a kart far less high, so it comes down on its own road.
- The scanner also comes for a kart stuck behind a wall (after 2 s) and catches a fall into the
  void sooner.
- Computer drivers stuck nose-first on a wall back off with the wheels turned and try once more
  the other way before the scanner comes. They no longer hold a long slide through S-bends, and
  they take a shortcut's jump only when they can reach the speed it needs.
- Dr. Breen taunts whoever he hits with a short line instead of a whole Breencast.
- Online: network protocol 3. Everyone needs this same version; a server of another version shows
  as "(different version)" in the server list and turns you away.
- Online: the start, the countdown and the race clock follow the server's clock on every PC. A
  player whose PC loads the race slowly is no longer dropped: the server waits up to 45 s, then
  starts, and the late player joins the race under way.
- A loading card covers the first frames of a race.
- Game content version 3: the first start after updating builds the game content again.

### Fixed
- The POSITION and LAP numbers sit right-aligned in their HUD boxes; the speed reads 0 during a
  rescue, and 3x items count down on their name.
- Karts no longer creep forward on the start grid during the countdown.
- Holes and seams in Black Mesa's walls and doorways that showed the empty world behind them.
- Short stalls the first time an effect or an item model showed up in a race.
- Karts thrown 10-20 m into the air by a pile-up, a wall scrape, a steep bank or several explosions
  going off at once: a hit now gives a hop of about 1.5 m at most.
- The camera keeps a kart in view while it sinks short of a jump, instead of showing the road above.
- Spectators' easter-egg lines went silent while your racer was talking; they now speak under him,
  and a line for a crowd you have already passed is dropped instead of said late.
- Online: the results order and the finish times match on every screen, and other players' karts
  no longer dip into the road when they land.
- Black Mesa: at the end of the storage hall, railings run diagonally across both side floors and
  lead you back onto the road into waste processing. You no longer get stuck in the corner by the
  toxic channels or climb the low fence there into the slime.
- Surface Tension: the HECU camp's supply crates sit just past the camp jump's landing, so nobody
  fires an item at you on the kicker, and the explosive barrels stand at the camp's entrance, before
  the sentry guns, so a kart spun there has room to get back up to speed. The guard rail on the
  cliff road meets the road's edge: a kart knocked off drops to the beach and the scanner picks it
  up at once instead of leaving it stuck beside the rail.
- Xen: the island hop's kickers are longer and smoother, so heavy rides such as the Dog no longer
  slam into the ramp and flip back before the lip; the jump needs the same speed as before. The
  landing past the chasm is much wider on the outside of the bend, so a kart hit just before the
  jump usually lands on ground.
- Xen: the G-Man now watches from a spot every racer passes, including those who take the island
  hop.

## [0.1.1] - 2026-10-25

### Added
- `HL2Kart-v0.1.1-windows.exe`: the whole download in one file. The first run unpacks it to
  `%LOCALAPPDATA%\HL2Kart` and every run starts the game from there.

### Changed
- The first start begins building the game content by itself when both Half-Life 2 and
  Half-Life are found; a click is only needed when a game has to be located by hand.

## [0.1.0] - 2026-10-24

The first public build.

### Added
- Five circuits of about 2 km each: **Highway 17**, **CT17** (Combine-held City 17),
  **Black Mesa** (indoors, around the Lambda reactor), **Xen** (floating islands) and
  **Surface Tension** (the desert, the gorge bridge and the dam).
- 12 racers from Half-Life 2 and Half-Life, 6 vehicles, HL2 items, drifting and turbo boosts.
- Multiplayer over LAN and the internet: server browser, lobby with chat, bots, dedicated
  server and master server.
- First-start setup inside the game: it finds Half-Life 2 and Half-Life through Steam and
  builds all the game content from them.
- Update check: the main menu shows a download button when a newer release exists
  (can be turned off in Options > Game).
- Windows download with Godot and Python included, so nothing else needs installing.
