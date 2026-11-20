class_name EditHistory
extends RefCounted
## Undo / redo over LevelDoc ops (7.5). A step is {name, do, undo, key, t, bytes}: `commit` applies
## ops and records them with the exact inverse LevelDoc.apply returned; commits inside
## begin_gesture / end_gesture (a drag, a slider) or with the same merge_key within `merge_window`
## seconds fold into the last step (do appended, undo prepended). A brush stroke, already written,
## is recorded by `push_applied`. Caps: MAX_STEPS steps or MAX_BYTES (packed arrays counted
## exactly, the rest estimated), the oldest dropped. Nothing in a step refers to a node, so the
## history survives scene changes (it lives in EditorSession, Game.editor).

## After every change of the steps or the position (commit, push, undo, redo, clear, caps).
signal changed

const MAX_STEPS := 500
const MAX_BYTES := 256 << 20

var doc: LevelDoc
## Seconds within which commits with the same merge key fold into one step.
var merge_window := 1.0
## The byte cap (MAX_BYTES; tests lower it).
var max_bytes := MAX_BYTES
## What the steps hold (bytes).
var bytes := 0

var _steps: Array[Dictionary] = []
var _pos := 0                  # steps applied: undo takes _steps[_pos - 1], redo _steps[_pos]
var _gesture := ""
var _in_gesture := false
var _gesture_step := false     # the gesture's first commit made its step
var _merge_ok := false         # the top step was just made by a commit (no undo / redo / push since)


func _init(d: LevelDoc) -> void:
	doc = d


## Applies ops as one step named step_name (folded into the last step inside a gesture, or with the
## last step's merge_key within merge_window). Ops that change nothing make no step.
func commit(step_name: String, ops: Array, merge_key := "") -> void:
	if doc == null or ops.is_empty():
		return
	var inv := doc.apply(ops)
	if inv.is_empty():
		return
	var now := _now()
	var top_ok := _pos > 0 and _pos == _steps.size()
	var fold := false
	if _in_gesture:
		fold = _gesture_step and top_ok
	elif merge_key != "" and _merge_ok and top_ok:
		var top: Dictionary = _steps[_pos - 1]
		fold = top.key == merge_key and now - float(top.t) <= merge_window
	if fold:
		_fold(_copy_ops(ops), inv, now)
	else:
		_push({"name": _gesture if _in_gesture else step_name, "do": _copy_ops(ops), "undo": inv,
			"key": "" if _in_gesture else merge_key, "t": now})
		if _in_gesture:
			_gesture_step = true
	_merge_ok = true
	_cap()
	changed.emit()


## Records a brush stroke already written to the document (+ the point sets of ROADS FOLLOW THE
## GROUND): do_ops redo it, undo_ops (the before-copies) undo it. Inside a gesture it folds into the
## gesture's step.
func push_applied(step_name: String, do_ops: Array, undo_ops: Array) -> void:
	if do_ops.is_empty() and undo_ops.is_empty():
		return
	var now := _now()
	if _in_gesture and _gesture_step and _pos > 0 and _pos == _steps.size():
		_fold(_copy_ops(do_ops), _copy_ops(undo_ops), now)
	else:
		_push({"name": _gesture if _in_gesture else step_name, "do": _copy_ops(do_ops), "undo": _copy_ops(undo_ops),
			"key": "", "t": now})
		if _in_gesture:
			_gesture_step = true
	_merge_ok = false
	_cap()
	changed.emit()


## Starts a gesture: every commit until end_gesture folds into one step named step_name.
func begin_gesture(step_name: String) -> void:
	_gesture = step_name
	_in_gesture = true
	_gesture_step = false


func end_gesture() -> void:
	_in_gesture = false
	_gesture_step = false
	_gesture = ""
	_merge_ok = false


## Esc mid-drag: ends the gesture and takes its step back when it made one (dropped: no redo).
## false when the gesture had made no step (nothing earlier is touched).
func cancel_gesture() -> bool:
	var made := _in_gesture and _gesture_step and _pos > 0 and _pos == _steps.size()
	end_gesture()
	if not made:
		return false
	undo()
	var gone: Dictionary = _steps.pop_back()
	bytes -= int(gone.bytes)
	changed.emit()
	return true


func undo() -> bool:
	if _pos <= 0 or doc == null:
		return false
	if _in_gesture:
		end_gesture()
	var st: Dictionary = _steps[_pos - 1]
	var redo_ops := doc.apply(st.undo)
	if not redo_ops.is_empty():
		_retake(st, "do", redo_ops)
	_pos -= 1
	_merge_ok = false
	changed.emit()
	return true


func redo() -> bool:
	if _pos >= _steps.size() or doc == null:
		return false
	if _in_gesture:
		end_gesture()
	var st: Dictionary = _steps[_pos]
	var undo_ops := doc.apply(st.do)
	if not undo_ops.is_empty():
		_retake(st, "undo", undo_ops)
	_pos += 1
	_merge_ok = false
	changed.emit()
	return true


func can_undo() -> bool:
	return _pos > 0


func can_redo() -> bool:
	return _pos < _steps.size()


func undo_name() -> String:
	return str(_steps[_pos - 1].name) if _pos > 0 else ""


func redo_name() -> String:
	return str(_steps[_pos].name) if _pos < _steps.size() else ""


func clear() -> void:
	_steps.clear()
	_pos = 0
	bytes = 0
	end_gesture()
	changed.emit()


# ---------------------------------------------------------------- additions (P1)

## Steps held (undoable + redoable).
func count() -> int:
	return _steps.size()


## Steps applied (the undo depth).
func position() -> int:
	return _pos


func in_gesture() -> bool:
	return _in_gesture


## The names of the steps, oldest first (the EDIT menu's list).
func names() -> PackedStringArray:
	var out := PackedStringArray()
	for st in _steps:
		out.append(str(st.name))
	return out


## The estimated size of a value in bytes (packed arrays exact).
static func size_of(v: Variant, depth := 0) -> int:
	match typeof(v):
		TYPE_PACKED_BYTE_ARRAY:
			return v.size()
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_INT32_ARRAY:
			return v.size() * 4
		TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_VECTOR2_ARRAY:
			return v.size() * 8
		TYPE_PACKED_VECTOR3_ARRAY:
			return v.size() * 12
		TYPE_PACKED_COLOR_ARRAY, TYPE_PACKED_VECTOR4_ARRAY:
			return v.size() * 16
		TYPE_STRING, TYPE_STRING_NAME:
			return 24 + str(v).length()
		TYPE_ARRAY:
			var n := 16
			if depth < 32:
				for x in v:
					n += size_of(x, depth + 1)
			return n
		TYPE_DICTIONARY:
			var m := 32
			if depth < 32:
				for k in v:
					m += size_of(k, depth + 1) + size_of(v[k], depth + 1)
			return m
	return 8


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## Drops the redo steps and appends a new one.
func _push(st: Dictionary) -> void:
	while _steps.size() > _pos:
		var gone: Dictionary = _steps.pop_back()
		bytes -= int(gone.bytes)
	st["bytes"] = size_of(st.do) + size_of(st.undo)
	bytes += int(st.bytes)
	_steps.append(st)
	_pos = _steps.size()


func _fold(do_ops: Array, undo_ops: Array, now: float) -> void:
	var top: Dictionary = _steps[_pos - 1]
	(top.do as Array).append_array(do_ops)
	var u := undo_ops.duplicate()
	u.append_array(top.undo)
	top.undo = u
	top.t = now
	var add := size_of(do_ops) + size_of(undo_ops)
	top.bytes = int(top.bytes) + add
	bytes += add


## Replaces a step's do or undo ops (with what apply returned: the exact inverse of the other side).
func _retake(st: Dictionary, side: String, ops: Array) -> void:
	var before := size_of(st[side])
	st[side] = ops
	var after := size_of(ops)
	st.bytes = int(st.bytes) + after - before
	bytes += after - before


func _cap() -> void:
	while _steps.size() > MAX_STEPS or (bytes > max_bytes and _steps.size() > 1):
		var gone: Dictionary = _steps.pop_front()
		bytes -= int(gone.bytes)
		_pos = maxi(_pos - 1, 0)


## A deep copy of ops (packed arrays duplicated: they are shared references).
static func _copy_ops(ops: Array) -> Array:
	var out := []
	for op in ops:
		if op is Array:
			var c := []
			for x in op:
				c.append(_copy_value(x))
			out.append(c)
		else:
			out.append(op)
	return out


static func _copy_value(v: Variant) -> Variant:
	match typeof(v):
		TYPE_DICTIONARY, TYPE_ARRAY:
			return v.duplicate(true)
		TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, \
				TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, \
				TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY, TYPE_PACKED_VECTOR4_ARRAY:
			return v.duplicate()
	return v
