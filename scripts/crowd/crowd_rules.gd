class_name CrowdRules
## Who the spectators like and hate, what each mood plays in each group state, what
## they say, and stand-ins for crowd models a player's content does not have.

enum State { IDLE, ANTICIPATE, PEAK, AFTER, SHOCK, CELEBRATE }

const STATE_NAMES := ["idle", "anticipate", "peak", "after", "shock", "celebrate"]

## racers the Combine wants arrested (anyone riding Dog too)
const REBELS := ["gordon", "shephard", "alyx", "barney", "eli", "kleiner", "monk", "vortigaunt"]
const BOSSES := ["breen", "police"]

## clip weights per mood and group state
const STATE_CLIPS := {
	"fan": {"idle": {"idle": 5, "clap": 3, "crossed": 1, "hips": 1}, "anticipate": {"clap": 6, "wave": 2, "point": 2},
		"peak": {"cheer": 5, "jump": 2, "fist": 3}, "after": {"clap": 7, "idle": 3}, "shock": {"flinch": 1},
		"celebrate": {"jump": 4, "cheer": 6}},
	"polite": {"idle": {"idle": 8, "crossed": 2}, "anticipate": {"clap": 1, "idle": 2}, "peak": {"clap": 7, "wave": 3},
		"after": {"clap": 4, "idle": 6}, "shock": {"flinch": 1}, "celebrate": {"clap": 6, "cheer": 2}},
	"excited": {"idle": {"clap": 5, "fist": 3, "idle": 2}, "anticipate": {"clap": 5, "fist": 3, "wave": 2},
		"peak": {"jump": 6, "cheer": 4}, "after": {"cheer": 4, "clap": 6}, "shock": {"flinch": 1},
		"celebrate": {"jump": 6, "cheer": 4}},
	"loyal": {"idle": {"hips": 5, "crossed": 5}, "anticipate": {"crossed": 5, "hips": 5}, "peak": {"crossed": 6, "point": 4},
		"after": {"hips": 5, "crossed": 5}, "shock": {"flinch": 1}, "celebrate": {"crossed": 1}},
	"military": {"idle": {"crossed": 5, "idle": 5}, "anticipate": {"crossed": 5, "idle": 3, "point": 2},
		"peak": {"point": 4, "fist": 3, "crossed": 3}, "after": {"crossed": 5, "idle": 5}, "shock": {"flinch": 1},
		"celebrate": {"fist": 6, "cheer": 2}},
	"chant": {"idle": {"idle": 6, "sway": 4}, "anticipate": {"sway": 6, "clap": 2}, "peak": {"cheer": 6, "clap": 4},
		"after": {"sway": 7, "idle": 3}, "shock": {"flinch": 1}, "celebrate": {"cheer": 5, "sway": 5}},
	"scared": {"idle": {"idle": 1}, "anticipate": {"idle": 1}, "peak": {"cower": 1}, "after": {"idle": 1},
		"shock": {"cower": 1}, "celebrate": {"idle": 1}},
}

## reactions that override the mood (eggs): what the member plays toward that racer
const EGG_CLIPS := {
	"condemn": {"condemn": 6, "point": 4}, "salute": {"salute": 1}, "revere": {"bow": 1},
	"boo": {"boo": 7, "point": 2, "crossed": 1}, "scared": {"cower": 1}, "dog": {"jump": 6, "cheer": 4},
	"hero": {"wave": 5, "cheer": 4, "jump": 1}, "accuse": {"point": 1}, "freeze": {"idle": 1},
}

## clip weights for events near a group, by the kind of spectator
const EVENT_CLIPS := {
	"explosion": {"human": {"flinch": 1}, "cops": {"flinch": 1}, "staff": {"cower": 1}, "alien": {"flinch": 1},
		"hecu": {"flinch": 1}},
	"hit": {"human": {"point": 5, "shrug": 1}, "cops": {"point": 3, "crossed": 3}, "staff": {"point": 3, "flinch": 2},
		"alien": {"point": 1}, "hecu": {"point": 3, "fist": 2}},
	"fall": {"human": {"point": 6, "shrug": 2}, "cops": {"crossed": 1}, "staff": {"shrug": 3, "point": 2},
		"alien": {"flinch": 1}, "hecu": {"point": 1}},
	"headcrab": {"human": {"flinch": 2, "point": 1}, "cops": {"flinch": 1}, "staff": {"cower": 1},
		"alien": {"flinch": 1}, "hecu": {"point": 1}},
	"zombie": {"human": {"flinch": 2, "point": 1}, "cops": {"crossed": 1}, "staff": {"cower": 1},
		"alien": {"flinch": 1}, "hecu": {"point": 1}},
}

## stand-ins for crowd models a player's content lacks (picked by seed)
const FALLBACK := {
	"citizen": ["odessa", "mossman", "eli"], "refugee": ["odessa", "mossman", "eli", "monk"],
	"rebel": ["odessa", "eli", "barney", "alyx"], "metrocop": ["police"], "combine": ["police"],
	"scientist": ["kleiner"], "guard": ["barney"], "vort": ["vortigaunt"], "islave": ["hl1/islave", "vortigaunt"],
	"hecu": ["hl1/hgrunt"], "zombie": ["zombie/classic"], "cameo": ["kleiner"],
}

## what members of a role are, for the reaction table
const HUMAN := ["citizen", "refugee", "rebel"]
const STAFF := ["scientist", "guard"]
const ALIEN := ["vort", "islave"]
const COPS := ["metrocop", "combine"]


## The kind of spectator a role is: human, cops, staff or alien (the role itself for the rest).
static func kind(role: StringName) -> String:
	var r := String(role)
	if r in HUMAN:
		return "human"
	if r in COPS:
		return "cops"
	if r in STAFF:
		return "staff"
	return "alien" if r in ALIEN else r


## How a spectator of `role` feels about racer `who` (character id) riding `ride`:
## "" nothing special, or hero / hate / rebel / gordon / boss / gman / kin / dog / zombie /
## alien / barney.
static func attitude(role: StringName, who: String, ride := "") -> StringName:
	var r := String(role)
	if r in COPS:
		if who == "gman_high":
			return &"gman"
		if who == "gordon":
			return &"gordon"
		if who in BOSSES:
			return &"boss"
		if who in REBELS or ride == "dog":
			return &"rebel"
		return &""
	if who == "zombie" and (r in HUMAN or r in STAFF):
		return &"zombie"
	if r in HUMAN:
		if ride == "dog":
			return &"dog"
		if who == "gordon":
			return &"hero"
		if who == "breen" or (r == "rebel" and who == "police"):
			return &"hate"
		return &""
	if r in STAFF:
		if who == "gordon":
			return &"hero"
		if r == "guard" and who == "barney":
			return &"barney"
		return &""
	if r in ALIEN:
		if who == "vortigaunt":
			return &"kin"
		if who == "gordon":
			return &"hero"
		if who in BOSSES:
			return &"hate"
		return &""
	if r == "hecu":
		if who == "shephard":
			return &"boss"
		if who == "gordon":
			return &"gordon"
		if who == "vortigaunt":
			return &"alien"
		return &""
	if r == "cameo" and who == "gordon":
		return &"hero"
	return &""


## The egg reaction a member of `role` shows racer attitude `att` while the group is in
## `state` (ANTICIPATE..AFTER), or "" to play the mood's clips.
static func egg_state(role: StringName, att: StringName, state: int) -> StringName:
	if att == &"" or state < State.ANTICIPATE or state > State.AFTER:
		return &""
	var peak := state == State.PEAK
	match att:
		&"rebel":
			return &"condemn"
		&"gordon":
			if String(role) in COPS:
				return &"condemn"
			return &"accuse" if peak else &""
		&"boss":
			return &"salute" if peak else &""
		&"gman":
			return &"freeze"
		&"hate":
			return &"boo"
		&"kin":
			return &"revere" if peak else &""
		&"hero":
			if String(role) in ALIEN:
				return &"revere" if peak else &""
			return &"hero" if state != State.ANTICIPATE else &""
		&"barney", &"dog":
			return StringName("hero" if att == &"barney" else "dog") if peak else &""
		&"zombie":
			return &"scared"
		&"alien":
			return &"accuse" if peak else &""
	return &""


## Weighted pick of a clip for a member: its mood's clips in `state`, or the egg's.
static func pick_clip(mood: StringName, state: int, egg: StringName, roll: float) -> StringName:
	if egg != &"":
		return _weighted(EGG_CLIPS.get(String(egg), {"idle": 1}), roll)
	var m: Dictionary = STATE_CLIPS.get(String(mood), STATE_CLIPS["fan"])
	return _weighted(m.get(STATE_NAMES[state], {"idle": 1}), roll)


## What a member plays for an event near it: `kind` (explosion, hit, fall, headcrab, zombie,
## start, finish), `att` its attitude to the racer it is about.
static func event_clip(role: StringName, mood: StringName, kind: StringName, att: StringName, roll: float) -> StringName:
	var r := String(role)
	if kind == &"start" or kind == &"finish":
		if r in COPS:
			return &"salute" if att == &"boss" and kind == &"finish" else &"crossed"
		if r in ALIEN and att == &"kin":
			return &"bow"
		return pick_clip(mood, State.CELEBRATE, &"", roll)
	if kind == &"hit" and att == &"hate" and (r in HUMAN or r in ALIEN):
		return _weighted({"cheer": 6, "jump": 3}, roll)
	var cls := "human"
	if r in COPS:
		cls = "cops"
	elif r in STAFF:
		cls = "staff"
	elif r in ALIEN:
		cls = "alien"
	elif r == "hecu":
		cls = "hecu"
	var t: Dictionary = EVENT_CLIPS.get(String(kind), {}).get(cls, {})
	return _weighted(t, roll) if not t.is_empty() else pick_clip(mood, State.SHOCK, &"", roll)


static func _weighted(w: Dictionary, roll: float) -> StringName:
	var total := 0.0
	for k in w:
		total += float(w[k])
	var x := roll * total
	for k in w:
		x -= float(w[k])
		if x <= 0.0:
			return StringName(k)
	return &"idle"


## Voice category a member of `role` calls out when racer attitude `att` goes by (PEAK),
## or "": the egg lines first, then plain cheering now and then. `world` is the circuit's
## (CrowdDirector.world): out in the desert the scientists are glad Freeman is alive.
static func pass_line(role: StringName, att: StringName, world: String) -> String:
	var r := String(role)
	if r == "islave":
		return "" if att == &"gman" else "chant"
	match att:
		&"gordon":
			return "freeman"
		&"rebel":
			return "boo_rebel"
		&"boss":
			return "salute"
		&"gman":
			return ""
		&"hero":
			if r == "scientist":
				return "alive" if world == "military" else "freeman"
			if r in HUMAN:
				return "gordon"
			return "freeman"
		&"barney":
			return "beer"
		&"kin":
			return "revere"
		&"hate":
			return "boo" if r in ALIEN else ""
		&"dog":
			return "dog"
		&"zombie":
			return "scream" if r == "scientist" else "zombie"
		&"alien":
			return "alien"
	# the Combine and the undead do not cheer
	return "" if r in COPS or r == "zombie" else "cheer"


## Voice category for an event near a member of `role` (victim `att` = its attitude to the
## racer it happened to); "" says nothing.
static func event_line(role: StringName, kind: StringName, att: StringName) -> String:
	var r := String(role)
	if r == "islave":
		# HL1's slaves only chant and raise the alarm
		return "chant" if kind == &"start" or kind == &"finish" else ("alert" if kind in [&"explosion", &"hit",
			&"fall", &"headcrab"] else "")
	match kind:
		&"explosion":
			if r == "scientist":
				return "scream"
			return "" if r == "guard" or r == "zombie" or r == "cameo" else "scared"
		&"hit":
			if r in HUMAN:
				return "cheer" if att == &"hate" else ("gordon_warn" if att == &"hero" else "scared")
			if r in COPS:
				return "chuckle" if att == &"rebel" or att == &"gordon" else ""
			if r == "scientist":
				return "fall"
			if r in ALIEN:
				return "cheer" if att == &"hate" else ("boo" if att == &"kin" or att == &"hero" else "")
			if r == "hecu":
				return "laugh"
		&"fall":
			if r in HUMAN:
				return "gordon_lose" if att == &"hero" else "fall"
			if r in COPS:
				return "chuckle"
			if r == "scientist":
				return "fall"
			if r in ALIEN:
				return "scared"
			if r == "hecu":
				return "laugh"
		&"headcrab":
			if r == "scientist":
				return "headcrab"
			if r in HUMAN:
				return "headcrab"
		&"zombie":
			if r == "scientist":
				return "scream"
			if r in HUMAN:
				return "zombie"
		&"start":
			if r in HUMAN:
				return "start"
			if r in ALIEN:
				return "chant"
			if r == "hecu":
				return "cheer"
		&"finish":
			if r in COPS:
				return "salute" if att == &"boss" else ""
			if r in ALIEN:
				return "revere" if att == &"kin" else "cheer"
			return "cheer"
		&"lead":
			if r in HUMAN and att == &"hero":
				return "gordon_lead"
		&"last":
			# into the final lap in last place
			if r in HUMAN and att == &"hero":
				return "gordon_lose"
			if r in COPS and (att == &"gordon" or att == &"rebel"):
				return "chuckle"
	return ""


## What a spectator of `role` shouts as it hops out of a kart's way.
static func dodge_line(role: StringName) -> String:
	var r := String(role)
	if r in HUMAN:
		return "dodge"
	return "scream" if r == "scientist" else "scared"


## A stand-in model for `role` (seeded), "" when there is none either.
static func fallback(role: StringName, seed_n: int) -> String:
	var l: Array = FALLBACK.get(String(role), [])
	var have: Array = l.filter(func(k: String) -> bool: return Game.models.has(k))
	return have[seed_n % have.size()] if not have.is_empty() else ""
