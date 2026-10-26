# Changelog

All notable changes to Half-Life 2: Kart. Versions follow [semantic versioning](https://semver.org):
`MAJOR.MINOR.PATCH` (while in 0.x, MINOR is a feature release and PATCH a fix).

## [Unreleased]

### Added
- Tubes: on CT17, Black Mesa, Xen and Surface Tension a stretch of road runs inside a pipe and rolls
  round it (up the wall, over the ceiling, or all the way round twice). Gravity pulls towards the
  pipe wall there and the camera rolls with the kart.
- Open edges: Xen's first bridge, CT17's overpass, the Surface Tension cliff road and the inside of
  the Black Mesa reactor spiral have no railings. Run wide and you fall; the scanner fishes you out.
- A second jump on CT17 (into the rail yard), Black Mesa (the storage hall) and Surface Tension
  (the HECU camp).
- Seven new items: energy ball (bounces off walls), watermelon and 3x watermelon (spin out whoever
  hits them), hopper mine (jumps at whoever comes close), sawblade (cuts through everyone in front),
  headcrab (covers the faces of everyone ahead) and Xen teleport (140 m down the road).
- Clusters of explosive barrels on the road.

### Changed
- Twice as many supply crate rows (8 per lap) and about four times as many boost pads.
- Item odds per race position include the new items.
- Game content version 2: the first start after updating rebuilds the tracks.

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
