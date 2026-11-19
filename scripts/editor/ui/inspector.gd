class_name Inspector
extends ScrollContainer
## The right column's inspector: asks the tool that owns the selection's kind to fill its fields
## (the active tool first, then the kind's owner, EditorTool.inspect). With nothing selected it
## says so; with a kind no tool fills yet, it shows the kind and, for an item with a position of
## its own, its POSITION. A rebuild waits while one of its fields is being dragged or typed in. P10.

var editor: TrackEditor
var box: VBoxContainer
## Who filled it last ("" none, "empty", the tool id or "basic").
var filled_by := ""
## Seconds between two rebuilds for the same selection while the document changes (a drag).
const THROTTLE := 0.15
var _dirty := true
var _built_for := PackedInt32Array([-1])
var _next_ms := 0


func _init() -> void:
	name = "Inspector"
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	box = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 4)
	add_child(box)


func setup(ed: TrackEditor) -> void:
	editor = ed
	refresh()


## Rebuilds on the next frame that no field is busy.
func refresh() -> void:
	_dirty = true


func _process(_delta: float) -> void:
	if not _dirty or busy():
		return
	# a new selection at once; the same one again at most every THROTTLE seconds
	var same := editor != null and editor.selection != null and editor.selection.uids == _built_for
	if same and Time.get_ticks_msec() < _next_ms:
		return
	rebuild()


## A field of it is being dragged or typed in.
func busy() -> bool:
	for c in box.find_children("*", "EditorNumber", true, false):
		if (c as EditorNumber).dragging():
			return true
	var f := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	return f != null and is_ancestor_of(f) and (f is LineEdit or f is TextEdit)


func rebuild() -> void:
	_dirty = false
	_next_ms = Time.get_ticks_msec() + int(THROTTLE * 1000.0)
	_built_for = editor.selection.uids.duplicate() if editor != null and editor.selection != null else PackedInt32Array()
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	filled_by = ""
	if editor == null or editor.selection == null:
		return
	var uids := editor.selection.uids
	if uids.is_empty():
		var l := EditorKit.hint("Select something to edit it here.")
		box.add_child(l)
		filled_by = "empty"
		return
	var t := editor.tool
	if t != null and t.inspect(uids, box):
		filled_by = t.id
		return
	_clear()
	var o := SelectTool.owner_tool(editor, editor.kind_of(uids[0]))
	if o != null and o != t and o.inspect(uids, box):
		filled_by = o.id
		return
	_clear()
	_basic(uids)
	filled_by = "basic"


func _clear() -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


## The kind and count; one free item's POSITION (one undo step per change, drags merge).
func _basic(uids: PackedInt32Array) -> void:
	var kind := editor.kind_of(uids[0])
	var same := true
	for u in uids:
		if editor.kind_of(u) != kind:
			same = false
			break
	var head := kind.to_upper().replace("_", " ") if same else "MIXED"
	box.add_child(EditorKit.section("%s%s" % [head, "" if uids.size() == 1 else " · %d SELECTED" % uids.size()]))
	if uids.size() == 1:
		var f := editor.doc.find(uids[0])
		var it = f.get("item", {})
		if it is Dictionary:
			box.add_child(UiKit.label(Outliner.item_name(editor, uids[0], f), EditorKit.FONT_SMALL, UiKit.TEXT_DIM))
			var p = it.get("pos")
			if p is Array and (p as Array).size() >= 3:
				var path: Array = editor.doc.path_of(uids[0]) + ["pos"]
				var uid := uids[0]
				box.add_child(EditorKit.row("POSITION", EditorKit.vec3(Vector3(float(p[0]), float(p[1]), float(p[2])),
					func(v: Vector3, final: bool) -> void:
						editor.commit("MOVE " + head, [LevelDoc.op_set(path, [v.x, v.y, v.z])], "inspect_pos_%d" % uid)
						if final:
							refresh()), "Type a value, or drag sideways on it."))
	box.add_child(EditorKit.hint("Pick its tool to edit everything about it."))
