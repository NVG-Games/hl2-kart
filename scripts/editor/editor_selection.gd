class_name EditSelection
extends RefCounted
## The selected uids, in the order they were picked (the first one is the gizmo's LOCAL frame).
## `changed` fires only when the set really changes. P8.
## Spec 7.3 calls it EditorSelection: Godot's editor build has a native class of that name, and a
## class_name hiding a native class does not parse, so it is EditSelection (like EditHistory).

signal changed

var uids := PackedInt32Array()


func set_to(list: PackedInt32Array) -> void:
	var out := _unique(list)
	if out == uids:
		return
	uids = out
	changed.emit()


func add(list: PackedInt32Array) -> void:
	var out := uids.duplicate()
	for u in list:
		if u > 0 and not (u in out):
			out.append(u)
	if out.size() == uids.size():
		return
	uids = out
	changed.emit()


func toggle(uid: int) -> void:
	if uid <= 0:
		return
	var i := uids.find(uid)
	if i >= 0:
		uids.remove_at(i)
	else:
		uids.append(uid)
	changed.emit()


func clear() -> void:
	if uids.is_empty():
		return
	uids = PackedInt32Array()
	changed.emit()


func has(uid: int) -> bool:
	return uid in uids


## Drops uids that left the document (a delete, an undo of a paste); no signal when none did.
func keep_only(valid: Callable) -> void:
	var out := PackedInt32Array()
	for u in uids:
		if valid.call(u):
			out.append(u)
	if out.size() != uids.size():
		uids = out
		changed.emit()


func size() -> int:
	return uids.size()


func is_empty() -> bool:
	return uids.is_empty()


static func _unique(list: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for u in list:
		if u > 0 and not (u in out):
			out.append(u)
	return out
