class_name LevelReport
extends RefCounted
## What a load, a sanitize or a compile found: errors, warnings and info items (each with its text,
## its FIX id and where it is), the content this install lacks and what sanitize dropped. Errors make
## a track not raceable; only the "cannot build" ones (BLOCKING) stop a TEST DRIVE (1.8).

## Error codes that stop a test drive: no road, an open main loop, a compile failure.
const BLOCKING := ["no_road", "open_loop", "compile"]
const LEVELS := ["error", "warning", "info"]

## {level: "error"|"warning"|"info", code, text, fix: String, uid: int, road: int, s: float, pos: Vector3}
## plus any extra keys the caller passed in `where` (names, anchors a FIX needs).
var items: Array[Dictionary] = []
## Content keys a compile skipped because this install does not have them.
var missing := {"models": 0, "materials": 0, "music": 0, "skies": 0}
## Section -> count of entries sanitize dropped; "thumb" -> 1 when the thumbnail was refused.
var dropped := {}


func error(code: String, text: String, where := {}, fix := "") -> void:
	_add("error", code, text, where, fix)


func warning(code: String, text: String, where := {}, fix := "") -> void:
	_add("warning", code, text, where, fix)


func info(code: String, text: String, where := {}) -> void:
	_add("info", code, text, where, "")


func errors() -> int:
	return count("error")


func warnings() -> int:
	return count("warning")


## No errors.
func raceable() -> bool:
	return errors() == 0


## The first error of unpack / sanitize ("" = none). An unpack report holds hard failures as
## errors; what sanitize only cleaned is reported as warnings or info.
func fatal() -> String:
	for it in items:
		if it.level == "error":
			return it.text if it.text != "" else it.code
	return ""


## "" or the text of the first "cannot build" issue (no_road, open_loop, compile).
func blocks_drive() -> String:
	for it in items:
		if it.level == "error" and it.code in BLOCKING:
			return it.text if it.text != "" else it.code
	return ""


## A JSON-friendly copy (pos as [x, y, z]).
func to_dict() -> Dictionary:
	var out := []
	for it in items:
		var d: Dictionary = it.duplicate(true)
		for k in d.keys():
			var v = d[k]
			if v is Vector3:
				d[k] = [v.x, v.y, v.z]
			elif v is Vector2:
				d[k] = [v.x, v.y]
		out.append(d)
	return {"items": out, "missing": missing.duplicate(), "dropped": dropped.duplicate(),
		"errors": errors(), "warnings": warnings()}


# ---------------------------------------------------------------- additions (P0)

## Items of one level.
func count(level: String) -> int:
	var n := 0
	for it in items:
		if it.level == level:
			n += 1
	return n


func has(code: String) -> bool:
	return not first(code).is_empty()


## The first item with this code, or {}.
func first(code: String) -> Dictionary:
	for it in items:
		if it.code == code:
			return it
	return {}


## Every item with this code.
func all_of(code: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for it in items:
		if it.code == code:
			out.append(it)
	return out


## Counts a content key this install does not have ("models", "materials", "music", "skies").
func add_missing(what: String, n := 1) -> void:
	missing[what] = int(missing.get(what, 0)) + n


## Counts entries sanitize dropped from a section (or "thumb").
func add_dropped(section: String, n := 1) -> void:
	dropped[section] = int(dropped.get(section, 0)) + n


func missing_total() -> int:
	var n := 0
	for k in missing:
		n += int(missing[k])
	return n


## Appends another report's items and adds its counts.
func merge(other: LevelReport) -> void:
	if other == null:
		return
	for it in other.items:
		items.append(it.duplicate(true))
	for k in other.missing:
		add_missing(k, int(other.missing[k]))
	for k in other.dropped:
		add_dropped(k, int(other.dropped[k]))


func clear() -> void:
	items.clear()
	missing = {"models": 0, "materials": 0, "music": 0, "skies": 0}
	dropped = {}


func _add(level: String, code: String, text: String, where: Dictionary, fix: String) -> void:
	var it := {"level": level, "code": code, "text": text, "fix": fix, "uid": 0, "road": -2,
		"s": -1.0, "pos": Vector3.ZERO}
	for k in where:
		if k == "level" or k == "code" or k == "text" or k == "fix":
			continue
		it[k] = where[k]
	it.uid = int(it.uid)
	it.road = int(it.road)
	it.s = float(it.s)
	if not (it.pos is Vector3):
		var p = it.pos
		it.pos = Vector3(float(p[0]), float(p[1]), float(p[2])) if p is Array and p.size() >= 3 else Vector3.ZERO
	items.append(it)
