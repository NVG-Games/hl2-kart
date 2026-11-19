class_name LevelHazards
## Hazards and enemies, compile side (4.2): the TYPES table, pre-geometry setups, geometry,
## resolvers (ports of tools/hazards.py), lint, legal spots, DIFFICULTY rows, see-saw ops and
## marker models. P14.
##
## A doc hazard (2.3) `{uid, type, at, side, setback, lat, zone, mount, style, pts, feel, p}` becomes
## one data["hazards"] entry `{id, type, s, span, seed, yaw, pos, p}` whose `p` holds only keys of the
## type's class defaults() (plus BASE_KEYS): the params (TYPES rows, clamped to their ranges) and what
## the resolver works out; inputs (TYPES inputs) are read and never passed on. Hazards stand on the
## main loop: `s` and spans are its lap metres.
##
## TYPES rows: params `[key, label, min, max, step, default, feel]` (feel "T" a time: longer is
## easier, "P" power: bigger is harder, "" neither); a choice row has its options Array as min and
## null as max; a bool row has min false, max true; a pair row ([min, max] like the antlion guard's
## speed) has a 2-number default, each number scaled and clamped alike. Inputs `[key, label, min,
## max, step, default]`. placement: `at` (bool), `side` (the allowed sides), `setback` / `lat`
## ([min, max, default] or []), `zone` (the default [before, after] metres round s, or null for none),
## `zone_len` ([min, max] or []), `pts` ({kind, min, max} or {}: "hover" {at, lat, h}, "mines" {at,
## lat}, "core" [x, y, z] (or {pos}), "thumpers" {at, side, setback}).

## type -> {label, group, desc, heavy, setup, placement, params: [[key, label, min, max, step,
## default, feel]], inputs: [[key, label, min, max, step, default]], blocking, mounts, styles}
const TYPES := {
	"turret": {"label": "TURRET", "group": "TURRETS & SOLDIERS", "heavy": false, "setup": "",
		"desc": "A sentry gun beside the road that locks on and fires a burst; on a tunnel's ceiling it hangs upside down.",
		"placement": {"at": true, "side": [-1, 1], "setback": [0.5, 6.0, 1.6], "lat": [], "zone": [-45.0, 4.0], "zone_len": [], "pts": {}},
		"params": [["model", "MODEL", ["hl1/sentry", "combine_turrets/floor_turret", "hl1/turret"], null, 0, "hl1/sentry", ""],
			["range", "RANGE", 25.0, 60.0, 1.0, 40.0, "P"], ["cone", "CONE", 40.0, 90.0, 1.0, 60.0, "P"],
			["lock", "LOCK TIME", 0.6, 1.5, 0.05, 0.9, "T"], ["shots", "SHOTS", 3, 8, 1, 6, "P"],
			["cool", "COOL DOWN", 3.0, 12.0, 0.5, 5.0, "T"], ["scale", "SIZE", 1.0, 1.6, 0.05, 1.0, ""]],
		"inputs": [], "blocking": false, "mounts": ["floor", "ceiling"], "styles": [],
		"mount_params": {"ceiling": {"model": "hl1/turret", "scale": 1.5}},
		"mount_setup": {"ceiling": "turret_ceiling"}, "zone_p": false},
	"vortigaunt": {"label": "VORTIGAUNT", "group": "CREATURES", "heavy": false, "setup": "",
		"desc": "A vortigaunt on the verge that charges and throws a green bolt at the karts coming.",
		"placement": {"at": true, "side": [-1, 1], "setback": [1.0, 6.0, 1.6], "lat": [], "zone": [-45.0, 4.0], "zone_len": [], "pts": {}},
		"params": [["range", "RANGE", 25.0, 45.0, 1.0, 36.0, "P"], ["cone", "CONE", 50.0, 90.0, 1.0, 75.0, "P"],
			["cool", "COOL DOWN", 2.0, 6.0, 0.25, 3.0, "T"]],
		"inputs": [], "blocking": false, "mounts": [], "styles": [], "zone_p": false},
	"strider": {"label": "STRIDER", "group": "COMBINE MACHINES", "heavy": true, "setup": "",
		"desc": "A strider standing beside the road: it charges its cannon at a stretch of the road and sweeps it with its gun.",
		"placement": {"at": true, "side": [-1, 1], "setback": [15.0, 40.0, 20.0], "lat": [], "zone": [-40.0, 110.0], "zone_len": [100.0, 200.0], "pts": {}},
		"params": [["cycle", "CYCLE", 8.0, 14.0, 0.5, 9.0, "T"], ["charge", "CHARGE", 1.5, 3.0, 0.1, 2.4, "T"],
			["gun", "GUN", false, true, 0, true, ""], ["gun_rate", "GUN RATE", 6.0, 18.0, 1.0, 12.0, "P"]],
		"inputs": [], "blocking": false, "mounts": [], "styles": [], "zone_p": true},
	"apache": {"label": "APACHE", "group": "COMBINE MACHINES", "heavy": false, "setup": "",
		"desc": "A helicopter hovering over its points that fires rockets at the karts in its zone.",
		"placement": {"at": false, "side": [], "setback": [], "lat": [], "zone": [-80.0, 80.0], "zone_len": [], "pts": {"kind": "hover", "min": 2, "max": 4}},
		"params": [["every", "EVERY", 3.0, 6.0, 0.25, 4.5, "T"], ["rockets", "ROCKETS", 1, 3, 1, 2, "P"],
			["flight", "FLIGHT TIME", 1.0, 2.0, 0.05, 1.3, "T"], ["radius", "BLAST RADIUS", 4.0, 7.0, 0.25, 5.5, "P"]],
		"inputs": [], "blocking": false, "mounts": [], "styles": [], "zone_p": true},
	"air_strafe": {"label": "GUNSHIP STRAFE", "group": "COMBINE MACHINES", "heavy": false, "setup": "",
		"desc": "A gunship that waits off the bend, then strafes a long stretch of the road.",
		"placement": {"at": false, "side": [], "setback": [], "lat": [], "zone": [-200.0, 200.0], "zone_len": [250.0, 450.0], "pts": {}},
		"params": [["period", "PERIOD", 30.0, 60.0, 1.0, 40.0, "T"], ["first", "FIRST RUN", 20.0, 60.0, 1.0, 35.0, ""],
			["warn", "WARNING", 1.5, 4.0, 0.1, 2.5, "T"], ["rate", "FIRE RATE", 6.0, 14.0, 0.5, 10.0, "P"]],
		"inputs": [], "blocking": false, "mounts": [], "styles": [], "zone_p": true},
	"strike_zone": {"label": "MORTAR / ARC ZONE", "group": "COMBINE MACHINES", "heavy": false, "setup": "",
		"desc": "Marked strikes land on the road in its zone: mortar shells, or arcs from a core beside the road.",
		"placement": {"at": false, "side": [], "setback": [], "lat": [], "zone": [-50.0, 50.0], "zone_len": [40.0, 200.0], "pts": {"kind": "core", "min": 0, "max": 1}},
		"params": [["every", "EVERY", 1.2, 4.0, 0.1, 2.2, "T"], ["count", "STRIKES", 1, 3, 1, 1, "P"],
			["warn", "WARNING", 1.0, 3.0, 0.1, 1.8, "T"], ["radius", "RADIUS", 3.0, 6.0, 0.25, 5.5, "P"]],
		"inputs": [], "blocking": false, "mounts": [], "styles": ["mortar", "arc"],
		"style_params": {"arc": [["core_r", "CORE RADIUS", 8.0, 20.0, 0.1, 14.3, "P"]]}, "zone_p": true},
	"field_gate": {"label": "FORCE FIELD GATE", "group": "TRAPS", "heavy": false, "setup": "",
		"desc": "Combine force fields across the road between posts, switching lanes in a pattern.",
		"placement": {"at": true, "side": [], "setback": [], "lat": [], "zone": null, "zone_len": [], "pts": {}},
		"params": [["pattern", "PATTERN", 0, 1, 1, [[1, 0, 0], [0, 1, 0], [0, 0, 1], [1, 0, 1]], ""],
			["step", "STEP", 1.5, 3.0, 0.1, 2.0, "T"], ["warn", "WARNING", 0.4, 1.2, 0.05, 0.7, "T"]],
		"inputs": [["lanes", "LANES", 2, 4, 1, 3]], "blocking": true, "mounts": [], "styles": [], "zone_p": false},
	"minefield": {"label": "HOPPER MINES", "group": "TRAPS", "heavy": false, "setup": "",
		"desc": "Combine hopper mines on the road that jump at a kart driving by.",
		"placement": {"at": true, "side": [], "setback": [], "lat": [], "zone": null, "zone_len": [], "pts": {"kind": "mines", "min": 4, "max": 20}},
		"params": [["range", "RANGE", 2.5, 4.5, 0.1, 3.5, "P"], ["hop", "HOP", 0.2, 0.6, 0.02, 0.38, ""],
			["rearm", "REARM", 10.0, 20.0, 0.5, 15.0, "T"], ["radius", "BLAST RADIUS", 3.0, 6.0, 0.25, 4.5, "P"]],
		"inputs": [], "blocking": true, "mounts": [], "styles": [], "zone_p": false},
	"houndeyes": {"label": "HOUNDEYES", "group": "CREATURES", "heavy": false, "setup": "",
		"desc": "A pack of houndeyes on the verge: they chirp, run out to the edge and blast a kart near them.",
		"placement": {"at": true, "side": [-1, 1], "setback": [2.0, 5.0, 2.5], "lat": [], "zone": null, "zone_len": [], "pts": {}},
		"params": [["radius", "BLAST RADIUS", 8.0, 14.0, 0.5, 10.0, "P"], ["notice", "NOTICE", 30.0, 50.0, 1.0, 30.0, "P"]],
		"inputs": [["count", "PACK", 2, 5, 1, 3]], "blocking": false, "mounts": [], "styles": [], "zone_p": false},
	"controller": {"label": "CONTROLLER", "group": "CREATURES", "heavy": false, "setup": "",
		"desc": "An alien controller flying an oval beside the road, throwing energy balls at the karts.",
		"placement": {"at": false, "side": [-1, 1], "setback": [], "lat": [], "zone": [-60.0, 60.0], "zone_len": [], "pts": {}},
		"params": [["cycle", "CYCLE", 8.0, 14.0, 0.5, 10.0, "T"], ["speed", "BALL SPEED", 3.0, 6.0, 0.1, 4.5, "P"]],
		"inputs": [["out", "OUT", 8.0, 20.0, 0.5, 12.0], ["wide", "WIDE", 3.0, 8.0, 0.5, 5.0],
			["h", "HEIGHT", 8.0, 15.0, 0.5, 11.0], ["rise", "RISE", 0.0, 4.0, 0.25, 2.0]],
		"blocking": false, "mounts": [], "styles": [], "zone_p": true},
	"bullsquid": {"label": "BULLSQUID", "group": "CREATURES", "heavy": false, "setup": "",
		"desc": "A bullsquid off the road that spits acid puddles onto the road in front of the karts.",
		"placement": {"at": true, "side": [-1, 1], "setback": [5.0, 12.0, 7.0], "lat": [], "zone": [-40.0, 0.0], "zone_len": [], "pts": {}},
		"params": [["range", "RANGE", 30.0, 60.0, 1.0, 48.0, "P"], ["cool", "COOL DOWN", 3.0, 8.0, 0.25, 4.0, "T"],
			["notice", "NOTICE", 40.0, 90.0, 1.0, 70.0, "P"]],
		"inputs": [], "blocking": false, "mounts": [], "styles": [], "zone_p": true},
	"crane": {"label": "MAGNET CRANE", "group": "COMBINE MACHINES", "heavy": true, "setup": "",
		"desc": "A dock crane on its tower beside the road: its magnet comes down, catches a kart and carries it on.",
		"placement": {"at": true, "side": [-1, 1], "setback": [8.0, 16.0, 10.0], "lat": [], "zone": null, "zone_len": [], "pts": {}},
		"params": [["cycle", "CYCLE", 10.0, 20.0, 0.5, 14.0, "T"], ["carry", "CARRY", 6.0, 14.0, 0.5, 10.0, ""],
			["jitter", "JITTER", 2.0, 6.0, 0.25, 4.0, "P"], ["radius", "MAGNET RADIUS", 2.5, 4.0, 0.1, 3.0, "P"]],
		"inputs": [], "blocking": false, "mounts": [], "styles": [], "zone_p": true},
	"antlion_guard": {"label": "ANTLION GUARD", "group": "CREATURES", "heavy": true, "setup": "",
		"desc": "An antlion guard on its verge that charges out and shoves a kart off the road.",
		"placement": {"at": false, "side": [-1, 1], "setback": [-4.0, 8.0, 4.0], "lat": [], "zone": [-60.0, 60.0], "zone_len": [60.0, 160.0], "pts": {}},
		"params": [["emerge", "COMES OUT OF", ["floor"], null, 0, "floor", ""], ["cool", "COOL DOWN", 5.0, 10.0, 0.25, 7.0, "T"],
			["speed", "CHARGE SPEED", 10.0, 40.0, 1.0, [16.0, 30.0], "P"]],
		"inputs": [], "blocking": false, "mounts": [], "styles": [], "zone_p": true},
	"tripmine": {"label": "TRIPMINE", "group": "TRAPS", "heavy": false, "setup": "tripmine",
		"desc": "A laser tripmine on a wall, its beam across most of the road to a stand of crates.",
		"placement": {"at": true, "side": [-1, 1], "setback": [], "lat": [], "zone": null, "zone_len": [], "pts": {}},
		"params": [["rearm", "REARM", 8.0, 15.0, 0.5, 10.0, "T"], ["radius", "BLAST RADIUS", 3.0, 6.0, 0.25, 4.5, "P"]],
		"inputs": [["to", "BEAM REACH", 0.05, 0.5, 0.05, 0.3], ["h", "BEAM HEIGHT", 0.4, 0.8, 0.05, 0.55]],
		"blocking": true, "mounts": [], "styles": [], "zone_p": false},
	"tentacle": {"label": "TENTACLE", "group": "CREATURES", "heavy": false, "setup": "tentacle",
		"desc": "A Xen tentacle rising out of a pit beside the road and slamming down across it.",
		"placement": {"at": true, "side": [-1, 1], "setback": [], "lat": [], "zone": null, "zone_len": [], "pts": {}},
		"params": [["period", "PERIOD", 5.0, 10.0, 0.25, 7.0, "T"]],
		"inputs": [["out", "OUT", 3.0, 6.0, 0.25, 4.0], ["depth", "PIT DEPTH", 15.0, 30.0, 0.5, 24.0],
			["reach", "SLAM REACH", 0.1, 0.4, 0.05, 0.2]],
		"blocking": true, "mounts": [], "styles": [], "zone_p": false},
	"antlion": {"label": "ANTLIONS", "group": "CREATURES", "heavy": true, "setup": "antlion",
		"desc": "Antlions dig out of the sand beside the road and pounce on a kart that leaves the road.",
		"placement": {"at": false, "side": [-1, 0, 1], "setback": [], "lat": [], "zone": [-70.0, 70.0], "zone_len": [100.0, 180.0], "pts": {"kind": "thumpers", "min": 0, "max": 3}},
		"params": [["grace", "GRACE", 0.4, 1.0, 0.05, 0.4, "T"], ["count", "PER WAVE", 1, 3, 1, [1, 3], "P"],
			["max_alive", "MOST AT ONCE", 3, 6, 1, 6, "P"], ["thumper_r", "THUMPER RADIUS", 15.0, 40.0, 1.0, 28.0, ""]],
		"inputs": [], "blocking": false, "mounts": [], "styles": [], "zone_p": true},
	"column": {"label": "COMBINE COLUMN", "group": "TURRETS & SOLDIERS", "heavy": true, "setup": "column",
		"desc": "A column of Combine soldiers marching over a footbridge across the road, firing down at a stretch of it.",
		"placement": {"at": true, "side": [], "setback": [], "lat": [], "zone": [-70.0, 10.0], "zone_len": [], "pts": {}},
		"params": [["count", "SOLDIERS", 6, 16, 1, 12, "P"], ["elites", "ELITES", 0, 4, 1, 2, "P"],
			["watch", "WATCH", 20.0, 35.0, 0.5, 24.0, "T"], ["warn", "WARNING", 1.0, 2.5, 0.1, 1.6, "T"],
			["strips", "STRIPS", 1, 3, 1, 2, "P"]],
		"inputs": [], "blocking": false, "mounts": [], "styles": [], "zone_p": true},
	"seesaw": {"label": "SEE-SAW BRIDGE", "group": "TRAINS & BRIDGES", "heavy": true, "setup": "seesaw",
		"desc": "Episode Two's see-saw bridge over a ravine: it tips under the karts' weight.",
		"placement": {"at": true, "side": [], "setback": [], "lat": [], "zone": null, "zone_len": [], "pts": {}},
		"params": [["length", "SPAN", 41.0, 49.1, 0.1, 49.1, ""], ["max", "TILT DOWN", 1.0, 3.0, 0.1, 2.0, ""],
			["back", "TILT BACK", 1.0, 3.0, 0.1, 2.0, ""], ["speed", "TIP SPEED", 4.0, 10.0, 0.25, 7.0, "P"]],
		"inputs": [], "blocking": false, "mounts": [], "styles": [], "zone_p": false},
	"train": {"label": "LEVEL CROSSING", "group": "TRAINS & BRIDGES", "heavy": false, "setup": "train",
		"desc": "A Combine train crossing the road between two tunnel mouths, signals flashing before it comes.",
		"placement": {"at": true, "side": [], "setback": [], "lat": [], "zone": null, "zone_len": [], "pts": {}},
		"params": [["speed", "SPEED", 20.0, 35.0, 0.5, 28.0, "P"], ["period", "PERIOD", 20.0, 70.0, 1.0, 26.0, "T"],
			["warn", "WARNING", 3.0, 8.0, 0.1, 4.5, "T"]],
		"inputs": [["reach", "LINE LENGTH", 80.0, 160.0, 5.0, 130.0], ["angle", "ANGLE", 45.0, 90.0, 1.0, 90.0]],
		"blocking": true, "mounts": [], "styles": [], "zone_p": false},
}
const SETUP_TYPES := ["turret_ceiling", "tripmine", "tentacle", "antlion", "column", "seesaw", "train"]

## p keys every hazard reads besides its class's defaults() (hazard_director.gd: "group").
const BASE_KEYS := ["group"]
## The types that close the road for a moment (hazards.py BLOCKING).
const BLOCKING := ["train", "field_gate", "tentacle", "tripmine", "minefield"]
## DIFFICULTY (4.2): [T factor, P factor] per feel.
const FEEL_SCALE := {"easy": [1.35, 0.75], "normal": [1.0, 1.0], "brutal": [0.75, 1.25]}
## Metres after / before the start line kept clear; before / after a jump gap.
const NO_GO_START := 60.0
const NO_GO_END := 30.0
const RAMP := 18.0
const LANDING := 25.0
const SIGNAL_MODEL := "props_trainstation/light_signal001a"
const SIGNAL_H := 4.9
const HEAVY_CAP := 8
## The tentacle's pit (4.2): radius, its rim, and how much deeper than depth - 4 the ground may be.
const PIT_RADIUS := 6.0
const PIT_PAST := 3.0
const PIT_SPARE := 4.0
## The column's footbridge: deck height over the road, and how far past the side treatment it reaches.
const DECK_UP := 6.0
const DECK_PAST := 3.0
## The see-saw stretch rules (4.2, hazards.py SEESAW_*).
const SEESAW_LEN := 49.1
const SEESAW_APRON_MIN := 12.0
const SEESAW_APRON_LOW := 14.0
const SEESAW_FLOOR := 12.0
const SEESAW_DIP := 14.0
## The ground under a jump gap (3.4).
const GAP_DIP := 8.0
const SEESAW_RADIUS := 400.0
const SEESAW_SPARE := 24.0
## Grade limit of the level crossing's line, and the corridor's clearance from other roads.
const TRAIN_GRADE := 0.12
const TRAIN_CLEAR := 3.0
const TRAIN_HALF_W := 1.8
## houndeyes.py
const HOUNDEYE_BEAT := 4.0
const HOUNDEYE_EDGE := [0.25, 1.15]
const HOUNDEYE_NOSE := 0.78
const CONTROLLER_STEP := 3.0
const ANTLION_KEEP := 2.0
const ANTLION_BAND := 16.0
const ANTLION_TAIL := 30.0
const ANTLION_SAND := 0.6
## the magnet crane (CraneHazard)
const CRANE_HINGE := Vector2(2.5908, 1.8011)
const CRANE_TIP := Vector3(17.842, 30.2675, 0.2398)
const CRANE_LUFF := Vector2(0.70, 1.31)
const CRANE_FRAME_H := 12.707
const CRANE_FRAME_W := 6.4
const CRANE_CAB_R := 7.4
const CRANE_SWEEP_N := 10
const CRANE_DEFAULTS := {"jitter": 4.0, "carry": 10.0, "radius": 3.0, "lat_max": -1.0, "high": 9.0, "low": 3.9,
	"rest_turn": 1.75, "rest_luff": 1.2, "rest_h": 11.0, "scale": 1.0, "cycle": 14.0}
## the antlion guard (AntlionGuardHazard)
const GUARD_SCALE := 1.2
const GUARD_TAIL := 20.0
const GUARD_ZONE_MIN := 60.0
const GUARD_ROOM := 0.7
## the marching column (CombineColumnHazard)
const COLUMN_HEADROOM := 4.5
const COLUMN_EDGE := 1.0
const COLUMN_HALF := 1.4
const COLUMN_RANGE := 110.0
const COLUMN_PITCH := 1.5
## Strider foot attachments (x, z) at scale 1, and the default scale.
const STRIDER_FEET := [Vector2(2.308, 3.043), Vector2(-2.148, 2.994), Vector2(0.0, -3.848)]
const STRIDER_SCALE := 1.15
## Markers in the editor's view (each type's default model; "" = only the zone strip and triangle).
const MARKERS := {"turret": "hl1/sentry", "vortigaunt": "hl1/islave", "strider": "combine_strider",
	"apache": "hl1/apache", "air_strafe": "gunship", "strike_zone": "", "field_gate": "props_combine/combine_fence01a",
	"minefield": "props_combine/combine_mine01", "houndeyes": "hl1/houndeye", "controller": "hl1/controller",
	"bullsquid": "hl1/bullsquid", "crane": "cranes/crane_docks", "antlion_guard": "antlion_guard",
	"tripmine": "hl1/p_tripmine", "tentacle": "hl1/tentacle2", "antlion": "antlion", "column": "combine_soldier",
	"seesaw": "seesawbridge/bridgemetalnondynamic", "train": "props_combine/combinetrain01a"}
## What a setup type needs, in the words of `hazard_setup` ("The %s needs %s ...").
const NEEDS := {"turret_ceiling": "a tunnel", "tripmine": "a road with ground under it (not a jump or a see-saw)",
	"tentacle": "an open road, a street or a bridge (not a tunnel or a jump)",
	"antlion": "an open road with ground beside it", "column": "open sky over the road (not a tunnel or a jump)",
	"seesaw": "its see-saw stretch", "train": "an open road or a street (not a tunnel, a bridge or a jump)"}


# ---------------------------------------------------------------- compile hooks

## Step 3 (before branches and the carve): barrier cuts for level crossings, the see-saw
## stretches' ravine dip, the tentacles' pits (ctx.pits) and the setup requests (ctx.setups: one
## dict per hazard: uid, type, key, ok, needs and what the geometry step builds).
static func pre_geometry(ctx: LevelContext) -> void:
	var m := ctx.main
	if m == null or m.n < 3:
		return
	ctx.setups = []
	# the see-saw stretches: no surface, a ravine under them; jump gaps: their 8 m dip
	for i in m.n:
		if m.seesaw[i] == 1:
			m.skip[i] = 1
			m.dip[i] = maxf(m.dip[i], SEESAW_DIP)
		elif m.gap[i] == 1:
			m.dip[i] = maxf(m.dip[i], GAP_DIP)
	var nat: LevelTerrain = null
	for hz in _doc_hazards(ctx):
		var sp := _spec(ctx, hz)
		if sp.is_empty():
			continue
		var st := _setup_key(sp)
		var su := {"uid": sp.uid, "type": sp.type, "key": st, "ok": true, "needs": "", "kind": ""}
		if st != "":
			var why := _setup_fails(ctx, sp, st)
			if why != "":
				su.ok = false
				su.needs = why
		if su.ok:
			match sp.type:
				"train":
					var ang := deg_to_rad(float(sp.inp.angle))
					var half := (TRAIN_HALF_W + 2.5) / maxf(sin(ang), 0.3) + 4.0
					var L := m.length
					for i in m.n:
						var d := wrapf(m.s[i] - float(sp.s), -L * 0.5, L * 0.5)
						if absf(d) < half:
							m.cut[i] = 1
					su.kind = "crossing"
				"tentacle":
					if nat == null:
						nat = LevelTerrain.from_doc(ctx.doc)
					var i := m.idx(sp.s)
					var c := _tentacle_spot(m, i, int(sp.side), float(sp.inp.out))
					var road_y := m.pos[i].y
					var depth := float(sp.inp.depth)
					var g := nat.natural_at(c.x, c.z) if nat != null else NAN
					su["pit"] = false
					if not is_nan(g) and g > road_y - (depth - PIT_SPARE):
						ctx.pits.append({"center": Vector2(c.x, c.z), "radius": PIT_RADIUS, "floor_y": road_y - depth})
						su["pit"] = true
					su.kind = "pit"
				"tripmine":
					var i := m.idx(sp.s)
					var sgn := int(sp.side)
					var wall := m.kind(i) == "tunnel"
					if not wall:
						for k in range(-2, 3):
							if not LevelGeometry.barrier_of(m, m.wrap(i + k), sgn).is_empty() and m.cut[m.wrap(i + k)] == 0:
								wall = true
								break
					su["stub"] = not wall
					su.kind = "wall"
				"column":
					su.kind = "footbridge"
		ctx.setups.append(su)


## Step 8: the setups' meshes (rails, portals, the footbridge, wall stubs) under road keys h<uid>.
static func geometry(ctx: LevelContext) -> void:
	var m := ctx.main
	if m == null or m.n < 3 or ctx.meshes == null:
		return
	for hz in _doc_hazards(ctx):
		var sp := _spec(ctx, hz)
		if sp.is_empty():
			continue
		var su := _setup_of(ctx, int(sp.uid))
		if not su.is_empty() and not bool(su.ok):
			continue
		var key := LevelMeshSet.hazard_key(int(sp.uid))
		var i := m.idx(sp.s)
		match sp.type:
			"train":
				var ln := _train_line(m, sp)
				var a: Vector3 = ln[0]
				var d: Vector3 = ln[2]
				var reach := float(sp.inp.reach)
				var prof := []
				var u := 0.0
				while u <= 2.0 * reach + 0.05:
					prof.append([u, _floor_y_safe(ctx, m, a + d * u, i) + 0.02])
					u += 1.0
				LevelHazardGeometry.rails(ctx.meshes, key, a, d, prof)
				for e in [[a, d], [ln[1], -d]]:
					var end: Vector3 = e[0]
					var g := ctx.ground(end.x, end.z)
					LevelHazardGeometry.portal(ctx.meshes, key, end, e[1], end.y if is_nan(g) else g)
			"column":
				var deck := _deck(m, i)
				var a: Vector3 = deck[0]
				var b: Vector3 = deck[1]
				var road_y := m.pos[i].y
				var ga := ctx.ground(a.x, a.z)
				var gb := ctx.ground(b.x, b.z)
				LevelHazardGeometry.footbridge(ctx.meshes, key, a, b, road_y - 2.0 if is_nan(ga) else ga,
					road_y - 2.0 if is_nan(gb) else gb)
			"tripmine":
				if not su.is_empty() and bool(su.get("stub", false)):
					var sgn := float(sp.side)
					var face := m.pos[i] + m.right[i] * sgn * m.width[i] * 0.5 + m.flat_right[i] * sgn * _wall_gap(m, i, int(sp.side), true)
					LevelHazardGeometry.stub(ctx.meshes, key, face, _flat(m.fwd[i]), sgn)


## Step 11: every kept hazard's data["hazards"] entry, in doc order (ids = list order of the kept
## ones). A hazard whose setup failed is left out with a `hazard_setup` error; a see-saw stretch
## with no see-saw on it is one too. Adds the hazards' corridors to ctx.reserved (crowds keep out)
## and the level crossings' signals to data["props"].
static func resolve(ctx: LevelContext) -> Array:
	var out := []
	var info := []
	var m := ctx.main
	if m == null or m.n < 3:
		return out
	var seesaws := {}
	for hz in _doc_hazards(ctx):
		var sp := _spec(ctx, hz)
		if sp.is_empty():
			continue
		var st := _setup_key(sp)
		if st != "":
			var su := _setup_of(ctx, int(sp.uid))
			var why := ""
			if su.is_empty():
				why = _setup_fails(ctx, sp, st)
			elif not bool(su.ok):
				why = str(su.needs)
			if why != "":
				var i := m.idx(sp.s)
				LevelValidate.issue(ctx.report, "hazard_setup", {"what": _what(sp), "needs": why},
					{"uid": sp.uid, "road": -1, "s": snappedf(float(sp.s), 0.01), "pos": m.pos[i], "type": sp.type})
				continue
		var k := out.size()
		var got := _resolve_one(ctx, sp, k)
		if got.is_empty():
			continue
		out.append(got[0])
		var extra: Dictionary = got[1]
		extra["spec"] = sp
		info.append(extra)
		if sp.type == "seesaw":
			seesaws[int(extra.get("run", -1))] = true
	# a see-saw stretch needs its see-saw
	for run in _seesaw_runs(m):
		if not seesaws.has(run[0]):
			var i: int = run[0]
			LevelValidate.issue(ctx.report, "hazard_setup", {"what": "see-saw stretch", "needs": "its see-saw"},
				{"uid": m.point_uids[m.seg[i]] if m.seg.size() > i and m.point_uids.size() > m.seg[i] else 0,
					"road": -1, "s": snappedf(m.s[i], 0.01), "pos": m.pos[i], "type": "seesaw_stretch"})
	ctx.set_meta("hz_info", info)
	return out


## Step 13 (from LevelValidate.run): hazards.py's lint lines for every kept hazard as `hazard_lint`
## warnings (the common rules, then the type's own), and `over_cap` past 8 heavy hazards.
static func lint(ctx: LevelContext) -> void:
	var m := ctx.main
	if m == null or m.n < 3 or not (ctx.data.get("hazards") is Array):
		return
	var entries: Array = ctx.data.hazards
	var info: Array = ctx.get_meta("hz_info", []) if ctx.has_meta("hz_info") else []
	var heavy := 0
	for e in entries:
		if str(e.get("type", "")) in LevelDoc.HEAVY:
			heavy += 1
	if heavy > HEAVY_CAP:
		LevelValidate.issue(ctx.report, "over_cap", {"what": "heavy hazards", "count": heavy, "cap": HEAVY_CAP})
	var L := m.length
	var rows := _lap_rows(ctx)
	var zones := _junction_zones(ctx.data)
	for k in entries.size():
		var e: Dictionary = entries[k]
		var inf: Dictionary = info[k] if k < info.size() else {}
		var sp: Dictionary = inf.get("spec", {})
		var a := float(e.span[0])
		var b := float(e.span[1])
		var msgs := []
		if _overlap(a, b, 0.0, NO_GO_START, L) or _overlap(a, b, L - NO_GO_END, L, L):
			msgs.append("near the start line")
		for g in m.gaps:
			if _overlap(a, b, m.s[g.x] - RAMP, m.s[m.wrap(g.y)] + LANDING, L):
				msgs.append("on a jump")
				break
		if str(e.type) in BLOCKING and e.type != "minefield":
			for rs in rows:
				if _overlap(a, b, rs - 6.0, rs + 6.0, L):
					msgs.append("on a crate row")
					break
		for z in zones:
			if _overlap(a, b, z[1], z[2], L) and not _covers(e, z[0]):
				msgs.append("in the shared stretch of %s (%d-%d m): the game targets only the karts on the lap" % [z[0], roundi(z[1]), roundi(z[2])])
		msgs.append_array(_checks(ctx, e, inf))
		var on := _on_branch_any(ctx, e, inf)
		if on != "":
			msgs.append("stands on " + on)
		var i := m.idx(float(e.s))
		for line in msgs:
			LevelValidate.issue(ctx.report, "hazard_lint", {"line": "%s %d m after the start: %s." % [_label(e, sp), roundi(float(e.s)), line]},
				{"uid": int(sp.get("uid", 0)), "road": -1, "s": float(e.s), "pos": m.pos[i], "type": str(e.type)})


## The legal-spot flags of a setup type (SETUP_TYPES) per exported main sample (every 3rd dense
## sample, as the path): 1 where the HAZARDS tool may place it.
static func legal(ctx: LevelContext, type_key: String) -> PackedByteArray:
	var out := PackedByteArray()
	var m := ctx.main
	if m == null or m.n < 3:
		return out
	var ne := (m.n + 2) / 3
	out.resize(ne)
	out.fill(0)
	var rh := _road_hash(ctx)
	var see_ok := {}
	for k in ne:
		var i := k * 3
		var ok := false
		match type_key:
			"turret_ceiling":
				ok = m.kind(i) == "tunnel" and m.height[i] > 0.0
			"tripmine":
				ok = m.gap[i] == 0 and m.seesaw[i] == 0
			"tentacle":
				ok = _tentacle_ok(ctx, rh, i)
			"antlion":
				ok = _antlion_ok(ctx, i)
			"column":
				ok = _column_ok(ctx, rh, i)
			"seesaw":
				var sk := m.seg[i]
				if not see_ok.has(sk):
					see_ok[sk] = _seesaw_segment_ok(m, sk)
				ok = see_ok[sk]
			"train":
				ok = _train_ok(ctx, rh, i, 90.0, 130.0)
		out[k] = 1 if ok else 0
	return out


## The p values of EASY / NORMAL / BRUTAL from the TYPES rows (4.2): T params x 1.35 / 1 / 0.75 and
## P params x 0.75 / 1 / 1.25, rounded to the row's step and clamped to it; NORMAL (and "custom" or
## an unknown feel) = the defaults.
static func difficulty_p(type: String, feel: String) -> Dictionary:
	var out := {}
	var t: Dictionary = TYPES.get(type, {})
	if t.is_empty():
		return out
	var f: Array = FEEL_SCALE.get(feel, FEEL_SCALE.normal)
	for row in _rows(t, "", ""):
		var v = row[5]
		var feel_k := str(row[6])
		var mul := 1.0
		if feel_k == "T":
			mul = float(f[0])
		elif feel_k == "P":
			mul = float(f[1])
		out[row[0]] = _scaled(row, v, mul)
	return out


## The stretch and its hazard together (one undo step): `on` makes the segment starting at point
## point_uid a see-saw stretch and adds a see-saw hazard on it (unless one is there); off clears
## the flag and removes the see-saws anchored on that segment.
static func seesaw_ops(doc: LevelDoc, point_uid: int, on: bool) -> Array:
	var ops := []
	if doc == null:
		return ops
	var f := doc.find(point_uid)
	if f.is_empty() or str(f.get("section", "")) != "road":
		return ops
	var path := ["road", "points", "#%d" % point_uid, "seesaw"]
	var hz_list: Array = doc.data.get("hazards", []) if doc.data.get("hazards") is Array else []
	var mine := []
	for h in hz_list:
		if h is Dictionary and str(h.get("type", "")) == "seesaw" and h.get("at") is Dictionary \
				and int(h.at.get("p", 0)) == point_uid:
			mine.append(int(h.get("uid", 0)))
	if on:
		if not bool((f.item as Dictionary).get("seesaw", false)):
			ops.append(LevelDoc.op_set(path, true))
		if mine.is_empty():
			ops.append(LevelDoc.op_insert(["hazards"], -1, {"uid": doc.new_uid(), "type": "seesaw",
				"at": {"p": point_uid, "t": 0.5}, "side": 0, "zone": null, "feel": "normal", "pts": [], "p": {}}))
	else:
		if bool((f.item as Dictionary).get("seesaw", false)):
			ops.append(LevelDoc.op_set(path, false))
		for u in mine:
			ops.append(["remove", ["hazards"], "#%d" % u])
	return ops


static func marker_model(type: String) -> String:
	return str(MARKERS.get(type, ""))


# ---------------------------------------------------------------- additions (P14)

## The model a hazard's marker shows for its mount (a ceiling turret is hl1/turret).
static func marker_model_for(hz: Dictionary) -> String:
	if str(hz.get("type", "")) == "turret" and str(hz.get("mount", "floor")) == "ceiling":
		return "hl1/turret"
	return marker_model(str(hz.get("type", "")))


## The setup key of a doc hazard (SETUP_TYPES entry, "" for none).
static func setup_of(hz: Dictionary) -> String:
	var t := str(hz.get("type", ""))
	var td: Dictionary = TYPES.get(t, {})
	if td.is_empty():
		return ""
	if t == "turret":
		return "turret_ceiling" if str(hz.get("mount", "floor")) == "ceiling" else ""
	return str(td.get("setup", ""))


## The param rows a doc hazard shows under ADVANCED: the type's, its mount's and its style's.
static func params_of(hz: Dictionary) -> Array:
	var t: Dictionary = TYPES.get(str(hz.get("type", "")), {})
	if t.is_empty():
		return []
	return _rows(t, str(hz.get("mount", "floor")), str(hz.get("style", "mortar")))


## Every key a type's p may carry at compile (params + resolver outputs), besides BASE_KEYS: what
## case_hazards checks against the class's defaults().
static func p_keys(type: String) -> PackedStringArray:
	var out := PackedStringArray()
	var t: Dictionary = TYPES.get(type, {})
	for row in _rows(t, "", ""):
		out.append(str(row[0]))
	for k in RESOLVED.get(type, []):
		out.append(str(k))
	return out


## The keys each resolver adds to p (all of them class defaults() keys).
const RESOLVED := {"turret": ["mount", "model", "scale"], "vortigaunt": [], "strider": ["zone", "feet"],
	"apache": ["zone", "hover"], "air_strafe": ["zone", "loiter"], "strike_zone": ["zone", "style", "core", "core_r"],
	"field_gate": ["posts", "fwd"], "minefield": ["mines"], "houndeyes": ["members", "side", "walks", "spots"],
	"controller": ["zone", "path"], "bullsquid": ["zone"], "crane": ["zone", "phase"],
	"antlion_guard": ["zone", "side", "keep", "aside"], "tripmine": ["a", "b", "stand", "stand_yaw"],
	"tentacle": ["cover", "phase"], "antlion": ["zone", "side", "thumpers"], "column": ["deck", "post", "zone", "posts"],
	"seesaw": ["a", "b", "width", "length", "apron", "pier", "from", "to"],
	"train": ["a", "b", "cross", "road_half", "profile", "lamps", "stop"]}


# ---------------------------------------------------------------- the spec of a doc hazard

static func _doc_hazards(ctx: LevelContext) -> Array:
	var out := []
	var list = ctx.doc.data.get("hazards", []) if ctx.doc != null else []
	if not (list is Array):
		return out
	for h in list:
		if h is Dictionary and TYPES.has(str(h.get("type", ""))):
			out.append(h)
	return out


## A doc hazard in compile terms: {uid, type, s (lap m), has_at, side, setback, lat, zone
## (Vector2 lap m, z1 >= z0), mount, style, feel, pts (the raw list), p (params, clamped), inp
## (inputs)}; {} when it has no spot on the main road.
static func _spec(ctx: LevelContext, hz: Dictionary) -> Dictionary:
	var m := ctx.main
	var ty := str(hz.get("type", ""))
	var td: Dictionary = TYPES.get(ty, {})
	if td.is_empty() or m == null:
		return {}
	var pl: Dictionary = td.placement
	var L := m.length
	var has_at := hz.get("at") is Dictionary and not (hz.at as Dictionary).is_empty()
	var s := m.anchor_s(hz.at) if has_at else NAN
	var zone = null
	var zone_given := false
	if hz.get("zone") is Array and (hz.zone as Array).size() == 2 and hz.zone[0] is Dictionary and hz.zone[1] is Dictionary:
		var z0 := m.anchor_s(hz.zone[0])
		var z1 := m.anchor_s(hz.zone[1])
		if z1 < z0:
			z1 += L
		zone = Vector2(z0, z1)
		zone_given = true
	if is_nan(s):
		if zone != null:
			s = (zone.x + zone.y) * 0.5
		else:
			s = _pts_s(m, hz)
	if is_nan(s):
		return {}
	if zone == null and pl.zone is Array:
		zone = Vector2(s + float(pl.zone[0]), s + float(pl.zone[1]))
	if zone != null and not pl.zone_len.is_empty():
		var lo := float(pl.zone_len[0])
		var hi := float(pl.zone_len[1])
		var ln: float = zone.y - zone.x
		if ln < lo or ln > hi:
			var c: float = (zone.x + zone.y) * 0.5
			ln = clampf(ln, lo, hi)
			zone = Vector2(c - ln * 0.5, c + ln * 0.5)
	var sides: Array = pl.side
	var side := int(hz.get("side", 0))
	if not sides.is_empty() and not (side in sides):
		side = int(sides[sides.size() - 1])
	if ty == "tentacle" and int(hz.get("side", 0)) == 0:
		side = -1
	var sb := NAN
	if not pl.setback.is_empty():
		sb = clampf(float(hz.get("setback", pl.setback[2])) if _num(hz.get("setback")) else float(pl.setback[2]),
			float(pl.setback[0]), float(pl.setback[1]))
	var lat := float(hz.get("lat", 0.0)) if _num(hz.get("lat")) else 0.0
	var mount := str(hz.get("mount", "floor"))
	if not (mount in ["floor", "ceiling"]) or ty != "turret":
		mount = "floor"
	var style := str(hz.get("style", "mortar"))
	if ty != "strike_zone" or not (style in td.styles):
		style = "mortar"
	var given: Dictionary = hz.get("p", {}) if hz.get("p") is Dictionary else {}
	var p := {}
	for row in _rows(td, mount, style):
		p[row[0]] = _clamp_param(row, given.get(row[0]))
	var inp := {}
	for row in td.inputs:
		var v = given.get(row[0])
		inp[row[0]] = clampf(float(v), float(row[2]), float(row[3])) if _num(v) else float(row[5])
	return {"uid": int(hz.get("uid", 0)), "type": ty, "s": s, "has_at": has_at, "side": side, "setback": sb,
		"lat": lat, "zone": zone, "zone_given": zone_given, "mount": mount, "style": style, "feel": str(hz.get("feel", "normal")),
		"pts": hz.get("pts", []) if hz.get("pts") is Array else [], "p": p, "inp": inp}


## The param rows of a type for a mount and style (the mount's / style's defaults in place).
static func _rows(td: Dictionary, mount: String, style: String) -> Array:
	var out := []
	var over: Dictionary = (td.get("mount_params", {}) as Dictionary).get(mount, {})
	for row in td.get("params", []):
		var r: Array = (row as Array).duplicate()
		if over.has(r[0]):
			r[5] = over[r[0]]
		out.append(r)
	var sty: Dictionary = td.get("style_params", {})
	if sty.has(style):
		for row in sty[style]:
			out.append((row as Array).duplicate())
	elif mount == "" and style == "":
		for st in sty:
			for row in sty[st]:
				out.append((row as Array).duplicate())
	return out


## A given param value checked against its row: the default when absent or of the wrong kind,
## numbers clamped (pairs each), choices from the options, the field gate's pattern rows of 0 / 1.
static func _clamp_param(row: Array, v: Variant) -> Variant:
	var def = row[5]
	if v == null:
		return _copy(def)
	if row[2] is Array:
		return v if v is String and v in row[2] else def
	if def is bool:
		return v if v is bool else def
	if row[0] == "pattern":
		if not (v is Array) or (v as Array).is_empty():
			return _copy(def)
		var rows := []
		for r in v:
			if not (r is Array) or (r as Array).is_empty() or rows.size() >= 6:
				continue
			var o := []
			for x in r:
				o.append(1 if _num(x) and float(x) > 0.5 else 0)
			rows.append(o)
		return rows if not rows.is_empty() else _copy(def)
	if def is Array:
		if not (v is Array) or (v as Array).size() != 2 or not _num(v[0]) or not _num(v[1]):
			return _copy(def)
		var lo := float(_scaled(row, float(v[0]), 1.0))
		var hi := float(_scaled(row, float(v[1]), 1.0))
		return [minf(lo, hi), maxf(lo, hi)] if not (def[0] is int) else [mini(int(lo), int(hi)), maxi(int(lo), int(hi))]
	if not _num(v):
		return def
	return _scaled(row, float(v), 1.0)


## A number (or a pair) of a row times mul, rounded to the row's step and clamped to it.
static func _scaled(row: Array, v: Variant, mul: float) -> Variant:
	if row[2] is Array or row[5] is bool or row[0] == "pattern":
		return _copy(v)
	if v is Array:
		var o := []
		for x in v:
			o.append(_scaled(row, x, mul))
		return o
	var step := float(row[4])
	var x := float(v) * mul
	if step > 0.0:
		x = snappedf(x, step)
	x = clampf(x, float(row[2]), float(row[3]))
	var def = row[5]
	if def is int or (def is Array and (def as Array).size() > 0 and def[0] is int):
		return roundi(x)
	return snappedf(x, 0.0001)


## The setup key of a spec.
static func _setup_key(sp: Dictionary) -> String:
	if sp.type == "turret":
		return "turret_ceiling" if sp.mount == "ceiling" else ""
	return str(TYPES[sp.type].get("setup", ""))


## Why a setup type cannot stand at its spot ("" = it can): what the hazard needs.
static func _setup_fails(ctx: LevelContext, sp: Dictionary, st: String) -> String:
	var m := ctx.main
	var i := m.idx(sp.s)
	var k := m.kind(i)
	match st:
		"turret_ceiling":
			if k != "tunnel" or m.height[i] <= 0.0:
				return NEEDS[st]
		"tripmine":
			if m.gap[i] == 1 or m.seesaw[i] == 1:
				return NEEDS[st]
		"tentacle":
			if k == "tunnel" or m.gap[i] == 1 or m.seesaw[i] == 1:
				return NEEDS[st]
		"antlion":
			if k != "open" or m.seesaw[i] == 1:
				return NEEDS[st]
		"column":
			if k == "tunnel" or m.gap[i] == 1 or m.seesaw[i] == 1:
				return NEEDS[st]
		"train":
			if not (k in ["open", "street"]) or m.gap[i] == 1 or m.seesaw[i] == 1:
				return NEEDS[st]
		"seesaw":
			if m.seesaw[i] == 0:
				return NEEDS[st]
			var run := _seesaw_run(m, i)
			for j in _run_ids(m, run[0], run[1]):
				if m.gap[j] == 1:
					return "a see-saw stretch without a jump in it"
			var G := fposmod(m.s[run[1]] - m.s[run[0]], m.length)
			if run[1] == run[0]:
				G = m.length
			var span := float(sp.p.get("length", SEESAW_LEN))
			if (G - span) * 0.5 < SEESAW_APRON_MIN:
				return "a see-saw stretch of at least %d m (this one is %d m)" % [ceili(span + 2.0 * SEESAW_APRON_MIN), roundi(G)]
	return ""


static func _setup_of(ctx: LevelContext, uid: int) -> Dictionary:
	for su in ctx.setups:
		if su is Dictionary and int(su.get("uid", -1)) == uid:
			return su
	return {}


## "ceiling turret", "see-saw", ...: the hazard_setup text's %s.
static func _what(sp: Dictionary) -> String:
	if sp.type == "turret" and sp.mount == "ceiling":
		return "ceiling turret"
	return str(TYPES[sp.type].label).to_lower()


static func _label(e: Dictionary, sp: Dictionary) -> String:
	if sp.is_empty():
		return str(TYPES.get(str(e.type), {}).get("label", str(e.type))).capitalize()
	var w := _what(sp)
	return w.substr(0, 1).to_upper() + w.substr(1)


## Lap metres of a points-only hazard (a minefield): the middle of its points.
static func _pts_s(m: LevelRoad, hz: Dictionary) -> float:
	var ss := []
	for q in hz.get("pts", []) if hz.get("pts") is Array else []:
		var v := _pt_s(m, q)
		if not is_nan(v):
			ss.append(v)
	if ss.is_empty():
		return NAN
	return (float(ss.min()) + float(ss.max())) * 0.5


## Lap metres of a hazard point ({at} or [s, ...]); NAN for a world point.
static func _pt_s(m: LevelRoad, q: Variant) -> float:
	if q is Dictionary and q.get("at") is Dictionary:
		return m.anchor_s(q.at)
	if q is Array and (q as Array).size() >= 2 and (q as Array).size() <= 3 and _num(q[0]):
		return float(q[0])
	return NAN


# ---------------------------------------------------------------- resolvers (tools/hazards.py)

## [entry, info] of one spec (info: what lint needs beyond the entry), or [] when it cannot resolve.
static func _resolve_one(ctx: LevelContext, sp: Dictionary, k: int) -> Array:
	var m := ctx.main
	var L := m.length
	var ty: String = sp.type
	var s: float = sp.s
	var p: Dictionary = sp.p.duplicate(true)
	var seed_v := ctx.seed_of(int(sp.uid))
	var info := {}
	var zone = sp.zone
	var span := Vector2(s - 20.0, s + 20.0)
	var pos := m.pos[m.idx(s)]
	var yaw := 0.0
	match ty:
		"turret", "vortigaunt":
			if sp.mount == "ceiling":
				var i := m.idx(s)
				var q := m.pos[i] + m.flat_right[i] * clampf(float(sp.lat), -m.width[i] * 0.5, m.width[i] * 0.5)
				q.y = m.pos[i].y + m.height[i] - 0.25
				pos = q
				yaw = _yaw_of(-_flat(m.fwd[i]))
				p["mount"] = "ceiling"
			else:
				var sc := float(p.get("scale", 1.0)) if ty == "turret" else 1.3
				s = ctx.clear_spot(m, s, sp.side, sp.setback)
				var i := m.idx(s)
				pos = _side_point(ctx, m, i, sp.side, sp.setback, info)
				var face := _flat(-_flat(m.fwd[i]) * 0.85 - m.flat_right[i] * float(sp.side) * 0.5)
				yaw = _yaw_of(face)
				if ty == "turret":
					p["mount"] = "floor"
				ctx.reserved.append([PackedVector3Array([pos, pos]), 2.5 * sc])
			if not sp.zone_given:
				zone = Vector2(s - 45.0, s + 4.0)
			span = zone
		"strider":
			var i := m.idx(s)
			var q := _side_point(ctx, m, i, sp.side, sp.setback, info)
			yaw = _yaw_of(_flat(m.pos[i] - q))
			var c := cos(yaw)
			var sn := sin(yaw)
			var feet := []
			for f in STRIDER_FEET:
				var fx: float = (f.x * c + f.y * sn) * STRIDER_SCALE
				var fz: float = (-f.x * sn + f.y * c) * STRIDER_SCALE
				feet.append(ctx.ground(q.x + fx, q.z + fz))
			var good := []
			for g in feet:
				if not is_nan(g):
					good.append(g)
			if good.size() == 3:
				var srt := good.duplicate()
				srt.sort()
				q.y = srt[1]
			else:
				info["floorless"] = true
			var rel := []
			for g in feet:
				rel.append(snappedf((q.y if is_nan(g) else g) - q.y, 0.001))
			p["feet"] = rel
			p["zone"] = _zone_list(zone)
			pos = q
			span = zone
			ctx.reserved.append([PackedVector3Array([q, q]), 8.0 * STRIDER_SCALE])
			ctx.reserved.append([PackedVector3Array([q, m.pos[i]]), 6.0])
		"apache":
			var hover := _hover(ctx, sp)
			p["hover"] = hover
			p["zone"] = _zone_list(zone)
			pos = _v3(hover[0])
			s = (zone.x + zone.y) * 0.5
			span = zone
		"air_strafe":
			s = (zone.x + zone.y) * 0.5
			var i := m.idx(s)
			var out := 1.0 if m.curv[i] < 0.0 else -1.0
			var loiter := m.pos[i] + m.flat_right[i] * out * 260.0 + Vector3.UP * 70.0
			p["loiter"] = _r3(loiter)
			p["zone"] = _zone_list(zone)
			pos = loiter
			span = zone
		"strike_zone":
			s = (zone.x + zone.y) * 0.5
			p["style"] = sp.style
			p["zone"] = _zone_list(zone)
			if sp.style == "arc":
				var core := _core(ctx, sp, s)
				p["core"] = _r3(core)
				info["core"] = core
			else:
				p.erase("core_r")
			pos = m.pos[m.idx(s)]
			span = zone
		"field_gate":
			var i := m.idx(s)
			var n := int(sp.inp.lanes)
			var hw := m.width[i] * 0.5 + 0.4
			var posts := []
			for j in n + 1:
				posts.append(_r3(m.pos[i] + m.right[i] * (-hw + 2.0 * hw * j / n)))
			p["posts"] = posts
			p["fwd"] = _r4(_flat(m.fwd[i]))
			p["pattern"] = _pattern(p.get("pattern", []), n)
			pos = m.pos[i]
			yaw = _yaw_of(_flat(m.fwd[i]))
			span = Vector2(s - 8.0, s + 4.0)
		"minefield":
			var mines := _mines(ctx, sp)
			if mines.is_empty():
				return []
			var lo := INF
			var hi := -INF
			for q in mines:
				lo = minf(lo, float(q[3]))
				hi = maxf(hi, float(q[3]))
			p["mines"] = mines
			s = (lo + hi) * 0.5
			pos = Vector3(mines[0][0], mines[0][1], mines[0][2])
			span = Vector2(lo - 10.0, hi + 6.0)
		"houndeyes":
			var members := _pack(ctx, sp, info)
			var paths := _pack_paths(ctx, sp)
			var c := Vector3.ZERO
			for q in members:
				c += Vector3(q[0], q[1], q[2])
			c /= maxf(members.size(), 1)
			p["members"] = members
			p["side"] = int(sp.side)
			p["walks"] = paths[0]
			p["spots"] = paths[1]
			pos = c
			span = Vector2(s - 30.0, s + 12.0)
			var pts := PackedVector3Array()
			for q in members:
				pts.append(Vector3(q[0], q[1], q[2]))
			ctx.reserved.append([pts, 3.0])
		"controller":
			var a: float = zone.x + 10.0
			var b: float = zone.y - 10.0
			var half := fposmod(b - a, L) * 0.5
			var mid := a + half
			var out := float(sp.inp.out)
			var wide := float(sp.inp.wide)
			var h := float(sp.inp.h)
			var rise := float(sp.inp.rise)
			var n := maxi(24, roundi((4.0 * half + TAU * wide) / CONTROLLER_STEP))
			var path := []
			for j in n:
				var u := TAU * j / n
				var i := m.idx(mid + half * cos(u))
				var q := m.pos[i] + m.flat_right[i] * float(sp.side) * (m.width[i] * 0.5 + out + wide * sin(u))
				q.y = m.pos[i].y + h + rise * sin(2.0 * u)
				path.append(_r3(q))
			p["path"] = path
			p["zone"] = _zone_list(zone)
			s = fposmod(mid, L)
			pos = _v3(path[0])
			span = zone
		"bullsquid":
			s = ctx.clear_spot(m, s, sp.side, sp.setback, 3.0)
			var i := m.idx(s)
			var q := _side_point(ctx, m, i, sp.side, sp.setback, info)
			var face := m.pos[m.idx(s - 25.0)] - q
			yaw = _yaw_of(_flat(face))
			if not sp.zone_given:
				zone = Vector2(s - 40.0, s)
			p["zone"] = _zone_list(zone)
			pos = q
			span = zone
			ctx.reserved.append([PackedVector3Array([q, q]), 3.5 * 1.4])
		"crane":
			var cp := _crane_p(p)
			var base := _crane_base(ctx, sp, cp)
			var q: Vector3 = base[0]
			var j := float(cp.jitter) + float(cp.radius) + 6.0
			zone = Vector2(s - j, s + float(cp.carry) + j) if sp.zone == null else zone
			p["zone"] = _zone_list(zone)
			p["phase"] = snappedf((seed_v % 1000) / 1000.0 * float(cp.cycle), 0.01)
			yaw = _yaw_of(_flat(m.pos[m.idx(s)] - q))
			info["legs"] = base[1]
			pos = q
			span = zone
			ctx.reserved.append([PackedVector3Array([q, q]), CRANE_CAB_R + 1.0])
			var sw := _crane_sweep(ctx, s, q, cp)
			var tips: PackedVector3Array = sw[2]
			var a := 0
			while a < tips.size():
				ctx.reserved.append([tips.slice(a, mini(a + CRANE_SWEEP_N, tips.size())), 3.0])
				a += CRANE_SWEEP_N
		"antlion_guard":
			s = (zone.x + zone.y) * 0.5
			var i := m.idx(s)
			var sg := 1 if int(sp.side) >= 0 else -1
			var sb: float = sp.setback
			var q := m.surface(i, sg * (m.width[i] * 0.5 + sb)) if sb < 0.0 else _side_point(ctx, m, i, sg, sb, info)
			yaw = _yaw_of(_flat(m.pos[i] - q))
			p["zone"] = _zone_list(zone)
			p["side"] = sg
			if sb < 0.0:
				p["keep"] = snappedf(sb, 0.01)
				p["aside"] = snappedf(sb, 0.01)
			pos = q
			span = Vector2(zone.x, zone.y + GUARD_TAIL)
			ctx.reserved.append([PackedVector3Array([q, q]), 3.5 * GUARD_SCALE])
		"tripmine":
			var i := m.idx(s)
			var hw := m.width[i] * 0.5
			var sgn := float(sp.side)
			var su := _setup_of(ctx, int(sp.uid))
			var gap := _wall_gap(m, i, int(sp.side), bool(su.get("stub", false)) if not su.is_empty() else false)
			var a_lat := sgn * (hw + gap)
			var b_lat := -sgn * float(sp.inp.to) * hw
			var h := float(sp.inp.h)
			var a := m.pos[i] + m.right[i] * a_lat + m.up[i] * h
			var b := m.pos[i] + m.right[i] * b_lat + m.up[i] * h
			var stand := m.pos[i] + m.right[i] * (b_lat + (0.7 if b_lat - a_lat >= 0.0 else -0.7))
			p["a"] = _r3(a)
			p["b"] = _r3(b)
			p["stand"] = _r3(stand)
			p["stand_yaw"] = snappedf(_yaw_of(_flat(m.fwd[i])), 0.0001)
			pos = a
			yaw = _yaw_of(_flat(b - a))
			span = Vector2(s - 6.0, s + 6.0)
		"tentacle":
			var i := m.idx(s)
			var side := int(sp.side)
			var hw := m.width[i] * 0.5
			var c := _tentacle_spot(m, i, side, float(sp.inp.out))
			var base := Vector3(c.x, m.pos[i].y - float(sp.inp.depth), c.z)
			var far := -side * hw * float(sp.inp.reach)
			var lo := minf(side * hw, far)
			var hi := maxf(side * hw, far)
			p["cover"] = [snappedf(lo, 0.01), snappedf(hi, 0.01)]
			p["phase"] = snappedf((seed_v % 1000) / 1000.0 * float(p.get("period", 7.0)), 0.01)
			pos = base
			yaw = _yaw_of(-m.flat_right[i] * side)
			span = Vector2(s - 4.0, s + 4.0)
		"antlion":
			s = (zone.x + zone.y) * 0.5
			var sides := _sand_sides(int(sp.side))
			var q := _side_point(ctx, m, m.idx(s), sides[sides.size() - 1], 8.0, {})
			var th := _thumpers(ctx, sp)
			p["zone"] = _zone_list(zone)
			p["side"] = int(sp.side)
			if not th.is_empty():
				p["thumpers"] = th
			pos = q
			span = Vector2(zone.x, zone.y + ANTLION_TAIL)
			for sg in sides:
				var line := PackedVector3Array()
				var u: float = zone.x
				while u <= zone.y + ANTLION_TAIL + 0.1:
					line.append(_side_point(ctx, m, m.idx(u), sg, (ANTLION_KEEP + ANTLION_BAND) * 0.5, {}))
					u += 6.0
				ctx.reserved.append([line, (ANTLION_BAND - ANTLION_KEEP) * 0.5])
			for t in th:
				var tv := _v3(t)
				ctx.reserved.append([PackedVector3Array([tv, tv]), 3.5])
		"column":
			var i := m.idx(s)
			var deck := _deck(m, i)
			var a: Vector3 = deck[0]
			var b: Vector3 = deck[1]
			var dl := Vector2(b.x - a.x, b.z - a.z).length()
			# the post: the deck metres over the road's centre line
			var post := (m.pos[i] - a).dot(_flat(b - a))
			post = clampf(post, 0.0, dl)
			p["deck"] = [_r3(a), _r3(b)]
			p["post"] = snappedf(post, 0.01)
			p["zone"] = _zone_list(zone)
			p["posts"] = [[snappedf(post, 0.01), snappedf(zone.x, 0.01), snappedf(zone.y, 0.01)]]
			pos = a + (b - a) * (post / maxf(dl, 0.01))
			span = zone
			ctx.reserved.append([PackedVector3Array([a, b]), COLUMN_HALF])
		"seesaw":
			var i := m.idx(s)
			var run := _seesaw_run(m, i)
			var ra: int = run[0]
			var rb: int = run[1]
			var s0 := m.s[ra]
			var G := fposmod(m.s[rb] - s0, L)
			var span_len := float(p.get("length", SEESAW_LEN))
			var pa := m.pos[ra]
			var pb := m.pos[rb]
			var mid := (pa + pb) * 0.5
			var g := ctx.ground(mid.x, mid.z)
			p["a"] = _r3(pa)
			p["b"] = _r3(pb)
			p["width"] = snappedf(m.width[ra], 0.01)
			p["length"] = span_len
			p["apron"] = snappedf((G - span_len) * 0.5, 0.01)
			p["pier"] = snappedf(mid.y - 30.0 if is_nan(g) else g, 0.01)
			p["from"] = snappedf(s0, 0.01)
			p["to"] = snappedf(s0 + G, 0.01)
			s = s0 + G * 0.5
			pos = mid
			yaw = _yaw_of(_flat(pb - pa))
			span = Vector2(s0 - 20.0, s0 + G + 5.0)
			info["run"] = ra
			info["run_b"] = rb
			ctx.reserved.append([PackedVector3Array([pa, pb]), m.width[ra] * 0.5 + 2.5])
		"train":
			var i := m.idx(s)
			var ln := _train_line(m, sp)
			var a: Vector3 = ln[0]
			var b: Vector3 = ln[1]
			var d: Vector3 = ln[2]
			var reach := float(sp.inp.reach)
			var ang := deg_to_rad(float(sp.inp.angle))
			var raw := []
			var us := []
			var u := 0.0
			while u <= 2.0 * reach + 0.05:
				us.append(u)
				raw.append(_floor_y_safe(ctx, m, a + d * u, i) + 0.02)
				u += 4.0
			var prof := []
			for j in raw.size():
				var y0: float = raw[maxi(j - 1, 0)]
				var y2: float = raw[mini(j + 1, raw.size() - 1)]
				var y: float = maxf(0.25 * y0 + 0.5 * float(raw[j]) + 0.25 * y2, float(raw[j]))
				prof.append([snappedf(us[j], 0.1), snappedf(y, 0.001)])
			var tall := SIGNAL_H
			var models = ctx.registries.get("models", {})
			if models is Dictionary and (models as Dictionary).has(SIGNAL_MODEL):
				var mm = models[SIGNAL_MODEL]
				if mm is Dictionary and mm.get("aabb_max") is Array and mm.get("aabb_min") is Array:
					tall = float(mm.aabb_max[1]) - float(mm.aabb_min[1])
			var lamps := []
			var fwd := _flat(m.fwd[i])
			for sgn in [-1, 1]:
				var q := _side_point(ctx, m, m.idx(s - 6.0), sgn, 3.5, {})
				if is_nan(q.y):
					q.y = m.pos[i].y
				if _model_ok(ctx, SIGNAL_MODEL):
					if ctx.data.get("props") is Array:
						ctx.data.props.append({"model": SIGNAL_MODEL, "pos": _r3(q), "yaw": snappedf(_yaw_of(fwd), 0.0001)})
				else:
					ctx.report.add_missing("models")
				lamps.append(_r3(q + Vector3.UP * (tall - 0.7) - fwd * 0.3))
			p["a"] = _r3(a)
			p["b"] = _r3(b)
			p["cross"] = snappedf(reach, 0.01)
			p["road_half"] = snappedf((m.width[i] * 0.5 + 6.0) / maxf(sin(ang), 0.3), 0.01)
			p["profile"] = prof
			p["lamps"] = lamps
			p["stop"] = [snappedf(s - 16.0, 0.1), snappedf(s + 16.0, 0.1)]
			pos = m.pos[i]
			yaw = _yaw_of(d)
			span = Vector2(s - 14.0, s + 14.0)
			ctx.reserved.append([PackedVector3Array([a, b]), 7.0])
			var side := Vector3.UP.cross(d)
			for e in [[a, d], [b, -d]]:
				var end: Vector3 = e[0]
				var back: Vector3 = e[1]
				ctx.reserved.append([PackedVector3Array([end - back * 13.0, end]), 7.0])
				ctx.reserved.append([PackedVector3Array([end - side * 35.0 - back, end + side * 35.0 - back]), 2.5])
	if is_nan(pos.y):
		pos.y = m.pos[m.idx(s)].y
		info["floorless"] = true
	var e := {"id": k, "type": ty, "s": snappedf(fposmod(s, L), 0.01),
		"span": [snappedf(span.x, 0.01), snappedf(span.y, 0.01)], "seed": seed_v, "yaw": snappedf(yaw, 0.0001),
		"pos": _r3(pos), "p": _clean_p(ty, p)}
	return [e, info]


## Only class defaults() keys go on (the resolver's outputs and the params; never an input).
static func _clean_p(ty: String, p: Dictionary) -> Dictionary:
	var keys := p_keys(ty)
	var out := {}
	for k in p:
		if str(k) in keys or str(k) in BASE_KEYS:
			out[k] = p[k]
	return out


static func _zone_list(z: Variant) -> Array:
	if z is Vector2:
		return [snappedf(z.x, 0.01), snappedf(z.y, 0.01)]
	return []


## hazards.side_point through LevelContext; a NAN floor (no ground) falls back to the road's height
## and marks the info "floorless".
static func _side_point(ctx: LevelContext, m: LevelRoad, i: int, side: int, setback: float, info: Dictionary) -> Vector3:
	var q := ctx.side_point(m, i, side, setback)
	if is_nan(q.y):
		q.y = m.pos[m.wrap(i)].y
		info["floorless"] = true
	return q


static func _floor_y_safe(ctx: LevelContext, m: LevelRoad, q: Vector3, i: int) -> float:
	var y := ctx.floor_y(m, q, i)
	return m.pos[m.wrap(i)].y if is_nan(y) else y


## The tentacle's pit centre / base in plan: `out` metres past the edge, at least 3 m past the side
## treatment, on whatever side (a point at the road's height).
static func _tentacle_spot(m: LevelRoad, i: int, side: int, out: float) -> Vector3:
	var sgn := -1.0 if side < 0 else 1.0
	var lat := m.width[i] * 0.5 + maxf(out, m.treatment(i, 1 if sgn > 0.0 else 0) + PIT_PAST)
	return m.pos[i] + m.flat_right[i] * sgn * lat


## Metres past the road's edge a tripmine's wall face is: the tunnel's wall gap, a barrier's offset,
## or 0.3 for the stub the compiler builds.
static func _wall_gap(m: LevelRoad, i: int, side: int, stub: bool) -> float:
	var st := m.style_at(i)
	if m.kind(i) == "tunnel":
		return float(st.get("wall_gap", 0.6))
	if stub:
		return 0.3
	var bar := LevelGeometry.barrier_of(m, i, side)
	if not bar.is_empty():
		return float(bar.get("off", 0.2))
	return 0.3


## The footbridge deck's two ends (on its walking surface) across the road at sample i: road y +
## 6 m, the road's width + 2 x (side treatment + 3 m).
static func _deck(m: LevelRoad, i: int) -> Array:
	var c := m.pos[i] + Vector3.UP * DECK_UP
	var l := m.width[i] * 0.5 + m.treatment(i, 0) + DECK_PAST
	var r := m.width[i] * 0.5 + m.treatment(i, 1) + DECK_PAST
	return [c - m.flat_right[i] * l, c + m.flat_right[i] * r]


## The rail line's ends a, b (a on the left at 90 degrees) and its plan direction a -> b.
static func _train_line(m: LevelRoad, sp: Dictionary) -> Array:
	var i := m.idx(sp.s)
	var ang := deg_to_rad(float(sp.inp.angle))
	var d := (m.flat_right[i] * sin(ang) + _flat(m.fwd[i]) * cos(ang)).normalized()
	var reach := float(sp.inp.reach)
	return [m.pos[i] - d * reach, m.pos[i] + d * reach, d]


## The apache's hover points [[x, y, z], ...]: the doc's {at, lat, h} (or [s, lat, h]); three made
## up over the outside of the zone when fewer than 2 are given.
static func _hover(ctx: LevelContext, sp: Dictionary) -> Array:
	var m := ctx.main
	var out := []
	for q in sp.pts:
		var s := _pt_s(m, q)
		if is_nan(s):
			continue
		var lat := 0.0
		var h := 45.0
		if q is Dictionary:
			lat = float(q.get("lat", 0.0)) if _num(q.get("lat")) else 0.0
			h = float(q.get("h", 45.0)) if _num(q.get("h")) else 45.0
		elif (q as Array).size() >= 3:
			lat = float(q[1])
			h = float(q[2])
		h = clampf(h, 40.0, 60.0)
		var i := m.idx(s)
		out.append(_r3(m.pos[i] + m.flat_right[i] * lat + Vector3.UP * h))
		if out.size() >= 4:
			break
	if out.size() >= 2:
		return out
	out = []
	var mid: float = (sp.zone.x + sp.zone.y) * 0.5
	var im := m.idx(mid)
	var sgn := 1.0 if m.curv[im] < 0.0 else -1.0
	for j in 3:
		var i := m.idx(mid + (j - 1) * 25.0)
		out.append(_r3(m.pos[i] + m.flat_right[i] * sgn * (m.width[i] * 0.5 + 15.0 + 5.0 * j) + Vector3.UP * (44.0 + 4.0 * j)))
	return out


## The arc zone's core: the first point ([x, y, z] or {pos}), else 20 m off the road's left at s.
static func _core(ctx: LevelContext, sp: Dictionary, s: float) -> Vector3:
	for q in sp.pts:
		if q is Array and (q as Array).size() >= 3 and _pt_ok_world(q):
			return Vector3(float(q[0]), float(q[1]), float(q[2]))
		if q is Dictionary and q.get("pos") is Array and (q.pos as Array).size() >= 3:
			return _v3(q.pos)
	var m := ctx.main
	var i := m.idx(s)
	var sgn := -1 if int(sp.side) <= 0 else 1
	var q := _side_point(ctx, m, i, sgn, 20.0, {})
	return q + Vector3.UP * 5.0


static func _pt_ok_world(q: Array) -> bool:
	return _num(q[0]) and _num(q[1]) and _num(q[2])


## The minefield's mines [x, y, z, s, lat]: the doc's {at, lat} (or [s, lat]); 8 seeded ones over
## 30 m round `at` when it has fewer than 4.
static func _mines(ctx: LevelContext, sp: Dictionary) -> Array:
	var m := ctx.main
	var src := []
	for q in sp.pts:
		var s := _pt_s(m, q)
		if is_nan(s):
			continue
		var lat := 0.0
		if q is Dictionary:
			lat = float(q.get("lat", 0.0)) if _num(q.get("lat")) else 0.0
		else:
			lat = float(q[1])
		src.append([s, lat])
		if src.size() >= 20:
			break
	if src.size() < 4:
		if not sp.has_at:
			return []
		src = []
		var rng := ctx.rng(int(sp.uid))
		var i0 := m.idx(sp.s)
		var lim := maxf(m.width[i0] * 0.5 - 1.5, 0.5)
		for j in 8:
			src.append([float(sp.s) - 15.0 + 30.0 * (j + 0.5) / 8.0, rng.randf_range(-lim, lim)])
	var out := []
	for q in src:
		var i := m.idx(q[0])
		var lat := clampf(float(q[1]), -m.width[i] * 0.5, m.width[i] * 0.5)
		out.append(_r3(m.surface(i, lat, 0.02)) + [snappedf(float(q[0]), 0.1), snappedf(lat, 0.01)])
	return out


## The field gate's pattern for n lanes: the given rows when they have n columns, else one lane at
## a time and (3 lanes or more) both edges.
static func _pattern(given: Variant, n: int) -> Array:
	if given is Array and not (given as Array).is_empty():
		var ok := true
		for r in given:
			if not (r is Array) or (r as Array).size() != n:
				ok = false
		if ok:
			return given
	var out := []
	for j in n:
		var r := []
		for c in n:
			r.append(1 if c == j else 0)
		out.append(r)
	if n >= 3:
		var r := []
		for c in n:
			r.append(1 if c == 0 or c == n - 1 else 0)
		out.append(r)
	return out


## Houndeye pack members [x, y, z, yaw] beside the road, staggered, facing it.
static func _pack(ctx: LevelContext, sp: Dictionary, info: Dictionary) -> Array:
	var m := ctx.main
	var out := []
	var n := int(sp.inp.count)
	for j in n:
		var i := m.idx(float(sp.s) + (j - (n - 1) * 0.5) * 3.5)
		var q := _side_point(ctx, m, i, sp.side, float(sp.setback) + (j % 2) * 1.6, info)
		out.append(_r3(q) + [snappedf(_yaw_of(_flat(m.pos[i] - q)), 0.0001)])
	return out


## Each member's beat on the verge and the spot at the road's edge it runs out to.
static func _pack_paths(ctx: LevelContext, sp: Dictionary) -> Array:
	var m := ctx.main
	var walks := []
	var spots := []
	var n := int(sp.inp.count)
	var nose := HOUNDEYE_NOSE * 1.5
	for j in n:
		var s := float(sp.s) + (j - (n - 1) * 0.5) * 3.5
		var setback := float(sp.setback) + (j % 2) * 1.6
		var w := []
		var d := -HOUNDEYE_BEAT
		while d <= HOUNDEYE_BEAT + 0.05:
			w.append(_r3(_side_point(ctx, m, m.idx(s + d), sp.side, setback, {})))
			d += 2.0
		walks.append(w)
		spots.append(_r3(_side_point(ctx, m, m.idx(s - 3.0), sp.side, nose + float(HOUNDEYE_EDGE[j % 2]), {})))
	return [walks, spots]


static func _sand_sides(sd: int) -> Array:
	return [1 if sd > 0 else -1] if sd != 0 else [-1, 1]


## The antlion zone's thumpers [[x, y, z], ...] from its {at, side, setback} points.
static func _thumpers(ctx: LevelContext, sp: Dictionary) -> Array:
	var m := ctx.main
	var out := []
	for q in sp.pts:
		if not (q is Dictionary) or not (q.get("at") is Dictionary):
			continue
		var sd := int(q.get("side", 1))
		var sb := float(q.get("setback", 6.0)) if _num(q.get("setback")) else 6.0
		out.append(_r3(_side_point(ctx, m, m.anchor_i(q.at), 1 if sd >= 0 else -1, sb, {})))
		if out.size() >= 3:
			break
	return out


# ---------------------------------------------------------------- the crane (hazards.py)

static func _crane_p(p: Dictionary) -> Dictionary:
	var out := CRANE_DEFAULTS.duplicate()
	for k in out:
		if p.has(k) and _num(p[k]):
			out[k] = float(p[k])
	return out


static func _crane_len() -> float:
	return Vector2(CRANE_TIP.x - CRANE_HINGE.x, CRANE_TIP.y - CRANE_HINGE.y).length()


## Plan metres the boom reaches at its highest and at its lowest luff.
static func _crane_reach(sc: float) -> Vector2:
	var L := _crane_len()
	return Vector2((CRANE_HINGE.x + L * cos(CRANE_LUFF.y)) * sc, (CRANE_HINGE.x + L * cos(CRANE_LUFF.x)) * sc)


## [yaw, luff] that hang the magnet over plan point q (CraneHazard.aim).
static func _crane_aim(cab: Vector3, q: Vector3, sc: float) -> Vector2:
	var dx := q.x - cab.x
	var dz := q.z - cab.z
	var b := CRANE_TIP.z * sc
	var a := sqrt(maxf(dx * dx + dz * dz - b * b, 0.0))
	var L := _crane_len()
	var c := clampf((a / sc - CRANE_HINGE.x) / L, cos(CRANE_LUFF.y), cos(CRANE_LUFF.x))
	var luff := acos(c)
	a = (CRANE_HINGE.x + L * cos(luff)) * sc
	return Vector2(atan2(b, a) - atan2(dz, dx), luff)


static func _crane_point(cab: Vector3, yaw: float, luff: float, u: float, sc: float) -> Vector3:
	var L := _crane_len() * u
	var x := (CRANE_HINGE.x + L * cos(luff)) * sc
	var y := (CRANE_HINGE.y + L * sin(luff)) * sc
	var z := CRANE_TIP.z * sc * u
	var c := cos(yaw)
	var s := sin(yaw)
	return Vector3(cab.x + x * c + z * s, cab.y + y, cab.z - x * s + z * c)


static func _crane_lat(m: LevelRoad, s: float, cp: Dictionary) -> float:
	var room := maxf(m.width[m.idx(s)] * 0.5 - 2.5, 0.0)
	return room if float(cp.lat_max) < 0.0 else minf(float(cp.lat_max), room)


## [[s, lat], ...]: where the magnet comes down and lets go at the extremes.
static func _crane_spots(m: LevelRoad, s: float, cp: Dictionary) -> Array:
	var out := []
	var j := float(cp.jitter)
	var cr := float(cp.carry)
	for a in [s - j, s, s + j]:
		for sg in [-1.0, 0.0, 1.0]:
			var lat: float = sg * _crane_lat(m, a, cp)
			var mm := _crane_lat(m, a + cr, cp)
			out.append([a, lat])
			out.append([a + cr, clampf(lat, -mm, mm)])
	return out


## [base on the lowest ground under the tower's legs, the legs' grounds].
static func _crane_base(ctx: LevelContext, sp: Dictionary, cp: Dictionary) -> Array:
	var m := ctx.main
	var q := _side_point(ctx, m, m.idx(float(sp.s) + float(cp.carry) * 0.5), sp.side, sp.setback, {})
	var h := CRANE_FRAME_W * 0.5
	var legs := []
	for dx in [-h, h]:
		for dz in [-h, h]:
			var g := ctx.ground(q.x + dx, q.z + dz)
			if not is_nan(g):
				legs.append(g)
	if not legs.is_empty():
		q.y = minf(float(legs.min()), q.y)
	return [q, legs]


## [cab pivot, rest [yaw, luff], boom-head points, [yaw, luff] at each] of the magnet's swings.
static func _crane_sweep(ctx: LevelContext, s: float, q: Vector3, cp: Dictionary) -> Array:
	var m := ctx.main
	var sc := float(cp.scale)
	var cab := q + Vector3.UP * CRANE_FRAME_H * sc
	var to := m.pos[m.idx(s)] - cab
	var rest := Vector2(atan2(-to.z, to.x) + float(cp.rest_turn), clampf(float(cp.rest_luff), CRANE_LUFF.x, CRANE_LUFF.y))
	var tips := PackedVector3Array()
	var booms := PackedVector2Array()
	for spot in _crane_spots(m, s, cp):
		var i := m.idx(spot[0])
		var aim := _crane_aim(cab, m.pos[i] + m.right[i] * float(spot[1]), sc)
		var dy := wrapf(aim.x - rest.x, -PI, PI)
		for k in CRANE_SWEEP_N:
			var e := float(k) / (CRANE_SWEEP_N - 1)
			var ye := rest.x + dy * e
			var le := rest.y + (aim.y - rest.y) * e
			tips.append(_crane_point(cab, ye, le, 1.0, sc))
			booms.append(Vector2(ye, le))
	return [cab, rest, tips, booms]


# ---------------------------------------------------------------- see-saw stretches

## [first sample, first sample after] of the see-saw run round sample i.
static func _seesaw_run(m: LevelRoad, i: int) -> Array:
	var a := i
	var b := i
	var k := 0
	while m.seesaw[m.wrap(a - 1)] == 1 and k < m.n:
		a -= 1
		k += 1
		if not m.closed and a <= 0:
			break
	while m.seesaw[m.wrap(b + 1)] == 1 and k < m.n:
		b += 1
		k += 1
		if not m.closed and b >= m.n - 1:
			break
	return [m.wrap(a), m.wrap(b + 1)]


static func _run_ids(m: LevelRoad, a: int, b: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var cnt := posmod(b - a, m.n)
	for j in cnt:
		out.append(m.wrap(a + j))
	return out


## Every see-saw run of the main road as [first sample, first sample after].
static func _seesaw_runs(m: LevelRoad) -> Array:
	var out := []
	var seen := {}
	for i in m.n:
		if m.seesaw[i] == 1 and not seen.has(i):
			var run := _seesaw_run(m, i)
			for j in _run_ids(m, run[0], run[1]):
				seen[j] = true
			seen[i] = true
			out.append(run)
	return out


## Whether segment sk can be a see-saw stretch: straight (radius >= 400 m), level, no explicit bank,
## one width, long enough for the span and two flaps, not a tunnel or a jump.
static func _seesaw_segment_ok(m: LevelRoad, sk: int) -> bool:
	if sk < 0 or sk >= m.seg_first.size() or m.seg_first[sk] < 0:
		return false
	if m.seg_len[sk] < SEESAW_LEN + SEESAW_SPARE:
		return false
	var i := m.seg_first[sk]
	var y0 := m.pos[i].y
	var w0 := m.width[i]
	var guard := 0
	while guard < m.n and m.seg[i] == sk:
		if m.kind(i) == "tunnel" or m.gap[i] == 1 or m.radius_at(i) < SEESAW_RADIUS:
			return false
		# AUTO banking is flattened on a see-saw stretch: only an explicit bank breaks it
		var banked := m.bank_set.size() == m.n and m.bank_set[i] == 1 and absf(m.bank[i]) > 0.01
		if absf(m.pos[i].y - y0) > 0.1 or absf(m.width[i] - w0) > 0.1 or banked:
			return false
		i += 1
		guard += 1
		if i >= m.n:
			if not m.closed:
				break
			i = 0
	return true


# ---------------------------------------------------------------- legal spots

## A spatial hash of every kept road's samples (16 m cells): {cell: PackedInt32Array of road index *
## 65536 + sample}; cached on the context.
static func _road_hash(ctx: LevelContext) -> Dictionary:
	if ctx.has_meta("hz_hash"):
		return ctx.get_meta("hz_hash")
	var h := {}
	for ri in ctx.roads.size():
		var r: LevelRoad = ctx.roads[ri]
		for i in r.n:
			var c := Vector2i(floori(r.pos[i].x / 16.0), floori(r.pos[i].z / 16.0))
			if not h.has(c):
				h[c] = PackedInt32Array()
			var arr: PackedInt32Array = h[c]
			arr.append(ri * 65536 + i)
			h[c] = arr
	ctx.set_meta("hz_hash", h)
	return h


## Plan clearance from q to the edge of the nearest road sample within `radius` (INF for none) whose
## height lies in (q.y + dy0, q.y + dy1); the main road's samples within `away` lap metres of s
## (s < 0: none) do not count.
static func _clearance(ctx: LevelContext, rh: Dictionary, q: Vector3, radius: float, s: float, away: float, dy0 := -INF, dy1 := INF) -> float:
	var best := INF
	var m := ctx.main
	var c0 := Vector2i(floori((q.x - radius) / 16.0), floori((q.z - radius) / 16.0))
	var c1 := Vector2i(floori((q.x + radius) / 16.0), floori((q.z + radius) / 16.0))
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			var arr = rh.get(Vector2i(cx, cz))
			if arr == null:
				continue
			for code in arr:
				var ri: int = code / 65536
				var i: int = code % 65536
				var r: LevelRoad = ctx.roads[ri]
				if r == m and s >= 0.0 and absf(wrapf(r.s[i] - s, -m.length * 0.5, m.length * 0.5)) <= away:
					continue
				if r.gap[i] == 1 or (r.skip.size() == r.n and r.skip[i] == 1 and r != m):
					continue
				var dy := r.pos[i].y - q.y
				if dy <= dy0 or dy >= dy1:
					continue
				var d := Vector2(r.pos[i].x - q.x, r.pos[i].z - q.z).length() - r.width[i] * 0.5
				best = minf(best, d)
	return best


static func _tentacle_ok(ctx: LevelContext, rh: Dictionary, i: int) -> bool:
	var m := ctx.main
	var k := m.kind(i)
	if k == "tunnel" or m.gap[i] == 1 or m.seesaw[i] == 1:
		return false
	for side in [-1, 1]:
		var c := _tentacle_spot(m, i, side, 4.0)
		if _clearance(ctx, rh, c, 12.0 + 20.0, m.s[i], 30.0, -30.0, 30.0) >= 12.0:
			return true
	return false


static func _antlion_ok(ctx: LevelContext, i: int) -> bool:
	var m := ctx.main
	if m.kind(i) != "open" or m.seesaw[i] == 1:
		return false
	for sg in [-1, 1]:
		var good := 0
		var n := 0
		var u := 0.0
		while u <= 100.0:
			var j := m.idx(m.s[i] + u)
			n += 1
			if m.kind(j) == "open":
				var q := ctx.side_point(m, j, sg, ANTLION_KEEP + 4.0)
				var g := ctx.ground(q.x, q.z)
				if not is_nan(g) and absf(g - m.pos[j].y) <= 2.0:
					good += 1
			u += 10.0
		if float(good) / n >= ANTLION_SAND:
			return true
	return false


static func _column_ok(ctx: LevelContext, rh: Dictionary, i: int) -> bool:
	var m := ctx.main
	if m.kind(i) == "tunnel" or m.gap[i] == 1 or m.seesaw[i] == 1:
		return false
	var deck := _deck(m, i)
	var a: Vector3 = deck[0]
	var b: Vector3 = deck[1]
	for u in 5:
		var q: Vector3 = a.lerp(b, u / 4.0)
		q.y = m.pos[i].y
		if _clearance(ctx, rh, q, 30.0, m.s[i], 20.0, 1.0, DECK_UP + 8.0) < 2.0:
			return false
	return true


## A level crossing at sample i: an open road or a street, the line's ground no steeper than 12 %
## and no other road within 3 m of its corridor.
static func _train_ok(ctx: LevelContext, rh: Dictionary, i: int, angle: float, reach: float) -> bool:
	var m := ctx.main
	if not (m.kind(i) in ["open", "street"]) or m.gap[i] == 1 or m.seesaw[i] == 1:
		return false
	var ang := deg_to_rad(angle)
	var d := (m.flat_right[i] * sin(ang) + _flat(m.fwd[i]) * cos(ang)).normalized()
	var a := m.pos[i] - d * reach
	var prev := NAN
	var u := 0.0
	while u <= 2.0 * reach + 0.05:
		var q := a + d * u
		var lat := absf((q - m.pos[i]).dot(m.flat_right[i]))
		var y := m.pos[i].y
		if lat > m.width[i] * 0.5 + 1.0:
			var g := ctx.ground(q.x, q.z)
			y = m.pos[i].y if is_nan(g) else g
		if not is_nan(prev) and absf(y - prev) / 8.0 > TRAIN_GRADE:
			return false
		prev = y
		q.y = y
		if _clearance(ctx, rh, q, TRAIN_CLEAR + 20.0, m.s[i], 30.0, -8.0, 8.0) < TRAIN_CLEAR:
			return false
		u += 8.0
	return true


# ---------------------------------------------------------------- lint (hazards.py _checks)

## The lap metres of the main road's crate rows.
static func _lap_rows(ctx: LevelContext) -> Array:
	var out := []
	var rows: Array = ctx.get_meta("rows", []) if ctx.has_meta("rows") else []
	for r in rows:
		if r is Dictionary and int(r.get("road", -1)) == -1:
			out.append(float(r.get("s", 0.0)))
	return out


static func _lap_pads(ctx: LevelContext) -> Array:
	var out := []
	var pads: Array = ctx.get_meta("pads", []) if ctx.has_meta("pads") else []
	for r in pads:
		if r is Dictionary and int(r.get("road", -1)) == -1:
			out.append(r)
	return out


## Every branch's shared stretches on the lap: [name, s0, s1] from the fork to its nose and from
## the merge's nose on (data.branches, as the game reads them).
static func _junction_zones(data: Dictionary) -> Array:
	var out := []
	var step := float((data.get("path", {}) as Dictionary).get("step", 0.0)) if data.get("path") is Dictionary else 0.0
	for b in data.get("branches", []):
		if not (b is Dictionary):
			continue
		var nm := str(b.get("name", b.get("id", "a branch")))
		out.append([nm, float(b.get("fork_s", 0.0)), float(b.get("fork_nose_i", 0)) * step])
		out.append([nm, float(b.get("merge_nose_i", 0)) * step, float(b.get("merge_s", 0.0))])
	return out


static func _covers(e: Dictionary, _where: String) -> bool:
	# an antlion zone or guard may reach over a branch's shared stretch when it names it ("branches");
	# the editor's hazards never name one
	return false


## Two lap ranges [a, b] and [c, d] (metres, may wrap) intersect.
static func _overlap(a: float, b: float, c: float, d: float, L: float) -> bool:
	if L <= 0.0:
		return false
	var a0 := fposmod(a, L)
	var la := fposmod(b - a, L) if b - a < L else L
	var c0 := fposmod(c, L)
	var lc := fposmod(d - c, L) if d - c < L else L
	return fposmod(c0 - a0, L) <= la or fposmod(a0 - c0, L) <= lc


## The racing line's lateral at sample i.
static func _line_lat(m: LevelRoad, i: int) -> float:
	if m.line_off.size() == m.n:
		return m.line_off[i]
	if m.line.size() == m.n:
		return (m.line[i] - m.pos[i]).dot(m.right[i])
	return 0.0


## The type's own placement problems (hazards.py _checks and friends).
static func _checks(ctx: LevelContext, e: Dictionary, inf: Dictionary) -> Array:
	var m := ctx.main
	var L := m.length
	var p: Dictionary = e.p
	var ty := str(e.type)
	var msgs := []
	var i := m.idx(float(e.s))
	var floor_t := ty in ["turret", "vortigaunt", "houndeyes", "strider", "bullsquid"] and str(p.get("mount", "floor")) == "floor"
	if floor_t:
		var pts := []
		if ty == "houndeyes":
			for q in p.get("members", []):
				pts.append(Vector3(q[0], q[1], q[2]))
		else:
			pts.append(_v3(e.pos))
		if bool(inf.get("floorless", false)) and m.kind(i) != "tunnel":
			msgs.append("no floor (no ground under it)")
		else:
			for q in pts:
				if q.y < m.pos[i].y - 4.0 and m.kind(i) != "tunnel":
					msgs.append("no floor (%.1f m under the road)" % (m.pos[i].y - q.y))
					break
		if m.kind(i) == "tunnel" and ty != "strider":
			var lat := absf((pts[0] - m.pos[i]).dot(m.flat_right[i]))
			if lat > m.width[i] * 0.5 + float(m.style_at(i).get("wall_gap", 0.6)) - 0.5:
				msgs.append("in the wall")
	match ty:
		"strider":
			var feet: Array = p.get("feet", [])
			if feet.size() == 3 and float(feet.max()) - float(feet.min()) > 1.5:
				msgs.append("uneven ground: feet %.1f m apart in height" % (float(feet.max()) - float(feet.min())))
		"strike_zone":
			if inf.has("core"):
				var core: Vector3 = inf.core
				var rh := _road_hash(ctx)
				var d := _clearance(ctx, rh, core, 60.0, -1.0, 0.0)
				if d > 40.0:
					msgs.append("its core is more than 40 m from the road")
				elif d < 2.0:
					msgs.append("its core stands on the road")
		"field_gate":
			var lat := _line_lat(m, i)
			var posts: Array = p.get("posts", [])
			for j in range(1, posts.size() - 1):
				var gap := absf((_v3(posts[j]) - m.pos[i]).dot(m.right[i]) - lat)
				if gap < 2.5:
					msgs.append("a post %.1f m from the racing line" % gap)
		"minefield":
			var pads := _lap_pads(ctx)
			var rows: Array = ctx.get_meta("rows", []) if ctx.has_meta("rows") else []
			for q in p.get("mines", []):
				var mv := Vector3(q[0], q[1], q[2])
				for pd in pads:
					if mv.distance_to(pd.pos) < 6.0:
						msgs.append("mine %d m after the start on a boost pad" % roundi(float(q[3])))
						break
				var on_row := false
				for r in rows:
					for c in r.get("crates", []):
						if mv.distance_to(c) < 8.0:
							on_row = true
				if on_row:
					msgs.append("mine %d m after the start on a crate row" % roundi(float(q[3])))
		"controller":
			msgs.append_array(_flight_checks(ctx, e))
		"bullsquid":
			var z: Array = p.get("zone", [])
			if z.size() == 2:
				for pd in _lap_pads(ctx):
					if _overlap(float(pd.s) - 4.0, float(pd.s) + 4.0, float(z[0]) - 3.0, float(z[1]) + 3.0, L):
						msgs.append("acid on the boost pad %d m after the start" % roundi(float(pd.s)))
				for rs in _lap_rows(ctx):
					if _overlap(rs - 6.0, rs + 6.0, float(z[0]) - 3.0, float(z[1]) + 3.0, L):
						msgs.append("acid on the crate row %d m after the start" % roundi(rs))
		"crane":
			msgs.append_array(_crane_checks(ctx, e, inf))
		"antlion":
			msgs.append_array(_sand_checks(ctx, e))
		"antlion_guard":
			msgs.append_array(_guard_checks(ctx, e))
		"seesaw":
			msgs.append_array(_seesaw_checks(ctx, e, inf))
		"tentacle":
			var lat := _line_lat(m, i)
			var cover: Array = p.get("cover", [])
			if cover.size() == 2 and not (float(cover[0]) <= lat and lat <= float(cover[1])):
				msgs.append("the racing line (%.1f m) passes clear of its slam" % lat)
		"column":
			msgs.append_array(_column_checks(ctx, e))
		"train":
			var a := _v3(p.a)
			var b := _v3(p.b)
			var rh := _road_hash(ctx)
			var worst := INF
			for u in 66:
				var q := a.lerp(b, u / 65.0)
				q.y = _floor_y_safe(ctx, m, q, i)
				worst = minf(worst, _clearance(ctx, rh, q, 25.0, float(e.s), 30.0, -8.0, 8.0))
			if worst < TRAIN_CLEAR:
				msgs.append("the line runs %.1f m from another stretch" % worst)
			var prof: Array = p.get("profile", [])
			var slope := 0.0
			for j in range(1, prof.size()):
				slope = maxf(slope, absf(float(prof[j][1]) - float(prof[j - 1][1])) / 4.0)
			if slope > TRAIN_GRADE:
				msgs.append("rails climb %d%%" % roundi(slope * 100.0))
	return msgs


## The other road a hazard's parts beside the lap stand on: "the road of <branch>", "" for none.
static func _on_branch_any(ctx: LevelContext, e: Dictionary, _inf: Dictionary) -> String:
	if ctx.roads.size() < 2:
		return ""
	var parts := []
	var p: Dictionary = e.p
	match str(e.type):
		"turret", "vortigaunt", "bullsquid":
			if str(p.get("mount", "floor")) == "floor":
				parts.append([_v3(e.pos), 1.0])
		"houndeyes":
			for q in p.get("members", []):
				parts.append([Vector3(q[0], q[1], q[2]), 1.0])
			for q in p.get("spots", []):
				parts.append([_v3(q), 1.0])
		"crane":
			parts.append([_v3(e.pos), CRANE_FRAME_W * 0.5 + 1.0])
		"strider":
			parts.append([_v3(e.pos), 5.0])
		"antlion":
			for q in p.get("thumpers", []):
				parts.append([_v3(q), 2.0])
		"antlion_guard":
			parts.append([_v3(e.pos), 3.0])
	var names := {}
	for b in ctx.branches:
		if b is Dictionary and bool(b.get("ok", false)):
			names[int(b.get("uid", 0))] = str(b.get("name", "a branch"))
	for part in parts:
		var q: Vector3 = part[0]
		var clear: float = part[1]
		for ri in range(1, ctx.roads.size()):
			var r: LevelRoad = ctx.roads[ri]
			for j in r.n:
				if r.gap[j] == 1:
					continue
				if absf(r.pos[j].y - q.y) < 6.0 and Vector2(r.pos[j].x - q.x, r.pos[j].z - q.z).length() - r.width[j] * 0.5 < clear:
					return "the road of the branch %s" % str(names.get(r.key, "a branch"))
	return ""


## A controller's flight: 6 m clear of every road's edge from 10 m under it to 4 m over it, 5 m
## over the ground.
static func _flight_checks(ctx: LevelContext, e: Dictionary) -> Array:
	var rh := _road_hash(ctx)
	var road := INF
	var ground := INF
	for q in e.p.get("path", []):
		var v := _v3(q)
		road = minf(road, _clearance(ctx, rh, v, 30.0, -1.0, 0.0, -10.0, 4.0))
		var g := ctx.ground(v.x, v.z)
		if not is_nan(g):
			ground = minf(ground, v.y - g)
	var msgs := []
	if road < 6.0:
		msgs.append("flies %.1f m from a road's edge" % road)
	if ground < 5.0:
		msgs.append("flies %.1f m over the ground" % ground)
	return msgs


## A crane: even ground under its tower, the tower clear of the roads, its magnet able to reach
## every spot (none in a tunnel, no road over one), the cab and boom clear of the ground, nothing
## (a prop) in its boom's sweep.
static func _crane_checks(ctx: LevelContext, e: Dictionary, inf: Dictionary) -> Array:
	var m := ctx.main
	var msgs := []
	var cp := _crane_p(e.p)
	var sc := float(cp.scale)
	var q := _v3(e.pos)
	var legs: Array = inf.get("legs", [])
	if legs.size() >= 2 and float(legs.max()) - float(legs.min()) > 1.5:
		msgs.append("uneven ground under the tower (its legs %.1f m apart in height)" % (float(legs.max()) - float(legs.min())))
	var rh := _road_hash(ctx)
	var clear := _clearance(ctx, rh, q, 40.0, -1.0, 0.0)
	if clear < CRANE_FRAME_W * sc * 0.5 + 1.0:
		msgs.append("the tower %.1f m from a road's edge" % clear)
	var s := float(e.s)
	var sw := _crane_sweep(ctx, s, q, cp)
	var cab: Vector3 = sw[0]
	var tips: PackedVector3Array = sw[2]
	var booms: PackedVector2Array = sw[3]
	var reach := _crane_reach(sc)
	for spot in _crane_spots(m, s, cp):
		var i := m.idx(spot[0])
		var a := m.pos[i] + m.right[i] * float(spot[1])
		var d := Vector2(a.x - cab.x, a.z - cab.z).length()
		if d < reach.x + 0.3 or d > reach.y - 0.3:
			msgs.append("its magnet can not reach %d m after the start (%.1f m from the pivot, reach %.1f-%.1f)" % [roundi(float(spot[0])), d, reach.x, reach.y])
			break
		if m.kind(i) == "tunnel":
			msgs.append("its spot %d m after the start is in a tunnel" % roundi(float(spot[0])))
			break
		if _clearance(ctx, rh, a, 20.0, -1.0, 0.0, 3.0, 200.0) < 3.0:
			msgs.append("a road over its spot %d m after the start" % roundi(float(spot[0])))
			break
	for j in 16:
		var ang := TAU * j / 16.0
		var g := ctx.ground(cab.x + cos(ang) * CRANE_CAB_R * sc, cab.z + sin(ang) * CRANE_CAB_R * sc)
		if not is_nan(g) and g > cab.y - 0.5:
			msgs.append("its cab turns into the ground")
			break
	var boom_hit := false
	var mag_hit := false
	var road_y := INF
	for spot in _crane_spots(m, s, cp):
		road_y = minf(road_y, m.pos[m.idx(spot[0])].y)
	var swing_y := minf(m.pos[m.idx(s)].y + float(cp.rest_h), road_y + float(cp.high))
	for k in tips.size():
		for u in [0.25, 0.5, 0.75, 1.0]:
			var b := _crane_point(cab, booms[k].x, booms[k].y, u, sc)
			var g := ctx.ground(b.x, b.z)
			if not is_nan(g) and g > b.y - 1.0:
				boom_hit = true
		var gt := ctx.ground(tips[k].x, tips[k].z)
		if not is_nan(gt) and gt > swing_y - 1.0:
			mag_hit = true
	if boom_hit:
		msgs.append("its boom meets the ground")
	if mag_hit:
		msgs.append("its magnet swings into the ground")
	for pr in ctx.props:
		if not (pr is Dictionary) or not (pr.get("pos") is Array) or str(pr.get("model", "")) == SIGNAL_MODEL:
			continue
		var pv := _v3(pr.pos)
		var hit := false
		for t in tips:
			if Vector2(t.x - pv.x, t.z - pv.z).length() < 3.0 and pv.y > swing_y - 12.0:
				hit = true
				break
		if hit:
			msgs.append("a %s stands in its boom's sweep" % str(pr.get("model", "prop")).get_file())
			break
	return msgs


## An antlion zone: open ground beside the road on its sand side(s) along most of it.
static func _sand_checks(ctx: LevelContext, e: Dictionary) -> Array:
	var m := ctx.main
	var p: Dictionary = e.p
	var z: Array = p.get("zone", [])
	var msgs := []
	if z.size() != 2:
		return msgs
	var rh := _road_hash(ctx)
	var best := 0.0
	for sg in _sand_sides(int(p.get("side", 0))):
		var ok := 0
		var n := 0
		var s := float(z[0])
		while s <= float(z[1]) + 0.1:
			var i := m.idx(s)
			var edge_y := m.pos[i].y
			for sb in [ANTLION_KEEP + 2.0, 7.0, 11.0]:
				var q := ctx.side_point(m, i, sg, sb)
				n += 1
				var g := ctx.ground(q.x, q.z)
				if is_nan(g) or absf(g - edge_y) > 4.0:
					continue
				q.y = g
				if _clearance(ctx, rh, q, 20.0, s, 25.0, -6.0, 6.0) < ANTLION_KEEP:
					continue
				ok += 1
			s += 6.0
		best = maxf(best, float(ok) / maxi(n, 1))
	if best < ANTLION_SAND:
		msgs.append("open ground beside the road at only %d%% of the zone" % roundi(best * 100.0))
	return msgs


## An antlion guard: a zone long enough, open ground near the road's height on its side along most
## of it with no barrier between it and the road, its home clear of the racing line.
static func _guard_checks(ctx: LevelContext, e: Dictionary) -> Array:
	var m := ctx.main
	var p: Dictionary = e.p
	var z: Array = p.get("zone", [])
	var msgs := []
	if z.size() != 2:
		return msgs
	var z0 := float(z[0])
	var z1 := float(z[1])
	var sg := 1 if int(p.get("side", 1)) >= 0 else -1
	var keep := float(p.get("keep", 2.0))
	var deck := keep < 0.0
	if fposmod(z1 - z0, m.length) < GUARD_ZONE_MIN:
		msgs.append("zone only %d m (want %d)" % [roundi(fposmod(z1 - z0, m.length)), roundi(GUARD_ZONE_MIN)])
	var rh := _road_hash(ctx)
	var ok := 0
	var n := 0
	var barred := 0
	var near_line := 0
	var s := z0
	while s <= z1 + 0.1:
		var i := m.idx(s)
		var edge_y := m.pos[i].y
		var good := true
		for sb in ([keep] if deck else [2.0, 4.0, 6.0]):
			var gy := 0.0
			var q := Vector3.ZERO
			if deck:
				q = m.surface(i, sg * (m.width[i] * 0.5 + sb))
				gy = q.y
			else:
				q = ctx.side_point(m, i, sg, sb)
				var g := ctx.ground(q.x, q.z)
				gy = q.y if is_nan(g) else g
			if is_nan(gy) or absf(gy - edge_y) > 2.5:
				good = false
			elif not deck:
				q.y = gy
				if _clearance(ctx, rh, q, 20.0, s, 25.0, -6.0, 6.0) < 1.0:
					good = false
		n += 1
		ok += 1 if good else 0
		if not deck:
			var bar := LevelGeometry.barrier_of(m, i, sg)
			if not bar.is_empty() and maxf(float(bar.get("h", 1.2)), float(bar.get("col_h", 0.0))) >= 1.0:
				barred += 1
		if absf(sg * (m.width[i] * 0.5 + keep) - _line_lat(m, i)) < GUARD_SCALE * 1.05 + 2.5:
			near_line += 1
		s += 3.0
	if float(ok) / maxi(n, 1) < GUARD_ROOM:
		msgs.append("open ground on its side at only %d%% of the zone" % roundi(100.0 * ok / maxi(n, 1)))
	if float(barred) / maxi(n, 1) > 0.3:
		msgs.append("a barrier on its side along %d%% of the zone: it can not get onto the road there" % roundi(100.0 * barred / maxi(n, 1)))
	if float(near_line) / maxi(n, 1) > 0.2:
		msgs.append("where it stands is within reach of the racing line along %d%% of the zone" % roundi(100.0 * near_line / maxi(n, 1)))
	return msgs


## A see-saw stretch: straight, level, unbanked, one width; flaps long enough; a deep enough
## ravine; no crate row, boost pad or prop on it.
static func _seesaw_checks(ctx: LevelContext, e: Dictionary, inf: Dictionary) -> Array:
	var m := ctx.main
	var p: Dictionary = e.p
	var msgs := []
	if not inf.has("run"):
		return msgs
	var ids := _run_ids(m, int(inf.run), int(inf.run_b))
	var pa := _v3(p.a)
	var pb := _v3(p.b)
	var d := _flat(pb - pa)
	var side := d.cross(Vector3.UP)
	var off := 0.0
	var rise := 0.0
	var bank := 0.0
	var wlo := INF
	var whi := -INF
	for j in ids:
		off = maxf(off, absf((m.pos[j] - pa).dot(side)))
		rise = maxf(rise, absf(m.pos[j].y - (pa.y + pb.y) * 0.5))
		bank = maxf(bank, absf(m.right[j].y))
		wlo = minf(wlo, m.width[j])
		whi = maxf(whi, m.width[j])
	if off > 0.1:
		msgs.append("not straight: %.2f m off the line between its hinges" % off)
	if rise > 0.1:
		msgs.append("not level: %.2f m up or down" % rise)
	if bank > 0.01:
		msgs.append("banked %.1f degrees" % rad_to_deg(asin(minf(bank, 1.0))))
	if whi - wlo > 0.1:
		msgs.append("its width changes (%.1f-%.1f m)" % [wlo, whi])
	var apron := float(p.get("apron", 0.0))
	if apron < SEESAW_APRON_LOW:
		msgs.append("flaps %.1f m (at least %d m bend gently)" % [apron, roundi(SEESAW_APRON_LOW)])
	var mid := _v3(e.pos)
	# under the span (the flaps meet the road's carve at the hinges)
	var half := float(p.get("length", SEESAW_LEN)) * 0.5
	var tilt := deg_to_rad(maxf(absf(float(p.get("back", 2.0))), absf(float(p.get("max", 2.0)))))
	var clear := INF
	var u := -half + 2.0
	var w := float(p.get("width", 14.0))
	while u <= half - 1.9:
		for lat in [-w * 0.5, 0.0, w * 0.5]:
			var q: Vector3 = mid + d * u + side * lat
			var g := ctx.ground(q.x, q.z)
			if not is_nan(g):
				clear = minf(clear, mid.y - g)
		u += 3.0
	var want := maxf(SEESAW_FLOOR, float(p.get("length", SEESAW_LEN)) * 0.5 * sin(tilt) + 9.0)
	if clear < want:
		msgs.append("ravine %.1f m under the deck (want %d)" % [clear, roundi(want)])
	var z0 := float(p.get("from", 0.0))
	var z1 := float(p.get("to", 0.0))
	for rs in _lap_rows(ctx):
		if _overlap(rs - 3.0, rs + 3.0, z0, z1, m.length):
			msgs.append("a crate row on it %d m after the start" % roundi(rs))
	for pd in _lap_pads(ctx):
		if _overlap(float(pd.s) - 3.0, float(pd.s) + 3.0, z0, z1, m.length):
			msgs.append("a boost pad on it %d m after the start" % roundi(float(pd.s)))
	var on := []
	var ln := Vector2(pb.x - pa.x, pb.z - pa.z).length()
	for pr in ctx.props:
		if not (pr is Dictionary) or not (pr.get("pos") is Array):
			continue
		var q := _v3(pr.pos)
		var al := (q - pa).dot(d)
		if absf((q - pa).dot(side)) < w * 0.5 + 0.5 and al > -1.0 and al < ln + 1.0 and absf(q.y - mid.y) < 3.0:
			var nm := str(pr.get("model", "prop"))
			if not (nm in on):
				on.append(nm)
	if not on.is_empty():
		on.sort()
		msgs.append("props on it: %s" % ", ".join(PackedStringArray(on)))
	return msgs


## A column: its deck long enough for its soldiers, its zone within range of the post and below
## it, no boost pad or crate row in the zone, no other hazard's span over it; its deck off every road.
static func _column_checks(ctx: LevelContext, e: Dictionary) -> Array:
	var m := ctx.main
	var L := m.length
	var p: Dictionary = e.p
	var msgs := []
	var deck: Array = p.get("deck", [])
	if deck.size() < 2:
		return msgs
	var a := _v3(deck[0])
	var b := _v3(deck[1])
	var dl := a.distance_to(b)
	var rows := (int(p.get("count", 12)) + 1) / 2
	var need := (rows - 1) * COLUMN_PITCH + 2.0 + 6.0
	if dl < need:
		msgs.append("deck %d m: too short for %d rows to march (needs %d m)" % [roundi(dl), rows, roundi(need)])
	var z: Array = p.get("zone", [])
	if z.size() != 2:
		return msgs
	var post := float(p.get("post", 0.0))
	var q := a + (b - a) * (post / maxf(dl, 0.01))
	var gun := q + Vector3.UP * 1.35
	var far := 0.0
	var near := INF
	var low := INF
	var s := float(z[0])
	while s <= float(z[1]) + 0.1:
		var r := m.pos[m.idx(s)]
		far = maxf(far, r.distance_to(gun))
		near = minf(near, Vector2(r.x - q.x, r.z - q.z).length())
		low = minf(low, q.y - r.y)
		s += 3.0
	if far > COLUMN_RANGE:
		msgs.append("its zone reaches %d m from its post (range %d)" % [roundi(far), roundi(COLUMN_RANGE)])
	if near > 30.0:
		msgs.append("its zone is %d m from its post in plan" % roundi(near))
	if low < 2.0:
		msgs.append("only %.1f m over its zone's road" % low)
	for pd in _lap_pads(ctx):
		if _overlap(float(pd.s) - 4.0, float(pd.s) + 4.0, float(z[0]), float(z[1]), L):
			msgs.append("a strip could land on the boost pad %d m after the start" % roundi(float(pd.s)))
	for rs in _lap_rows(ctx):
		if _overlap(rs - 6.0, rs + 6.0, float(z[0]), float(z[1]), L):
			msgs.append("a strip could land on the crate row %d m after the start" % roundi(rs))
	for o in ctx.data.get("hazards", []):
		if o is Dictionary and o != e and _overlap(float(o.span[0]), float(o.span[1]), float(z[0]), float(z[1]), L):
			msgs.append("its zone overlaps the %s %d m after the start" % [str(TYPES.get(str(o.type), {}).get("label", o.type)).to_lower(), roundi(float(o.s))])
	# its soldiers never stand on the karts' road
	var rh := _road_hash(ctx)
	var u := 0.0
	while u <= dl + 0.01:
		var dq := a.lerp(b, u / maxf(dl, 0.01))
		if _clearance(ctx, rh, dq, 20.0, -1.0, 0.0, -COLUMN_HEADROOM, COLUMN_HEADROOM) < COLUMN_EDGE + COLUMN_HALF:
			msgs.append("its deck stands on a road %d m along it" % roundi(u))
			break
		u += 1.0
	return msgs


# ---------------------------------------------------------------- small helpers

static func _num(v: Variant) -> bool:
	return (v is float or v is int) and is_finite(float(v))


static func _copy(v: Variant) -> Variant:
	if v is Array or v is Dictionary:
		return v.duplicate(true)
	return v


static func _model_ok(ctx: LevelContext, key: String) -> bool:
	var reg = ctx.registries.get("models", {})
	if not (reg is Dictionary) or (reg as Dictionary).is_empty():
		return true
	return (reg as Dictionary).has(key)


static func _flat(v: Vector3) -> Vector3:
	var f := Vector3(v.x, 0.0, v.z)
	return f.normalized() if f.length_squared() > 1e-12 else Vector3.BACK


## Godot yaw that turns a model's +Z onto direction d.
static func _yaw_of(d: Vector3) -> float:
	return atan2(d.x, d.z)


static func _v3(v: Variant) -> Vector3:
	if v is Vector3:
		return v
	if v is Array and (v as Array).size() >= 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return Vector3.ZERO


static func _r3(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]


static func _r4(v: Vector3) -> Array:
	return [snappedf(v.x, 0.0001), snappedf(v.y, 0.0001), snappedf(v.z, 0.0001)]
