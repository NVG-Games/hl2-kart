class_name EditorTool
extends RefCounted
## The tool base (7.3): every tool package implements these. A tool never writes doc.data directly
## but through editor.commit (or a brush's push_applied); its markers go only through markers(m).
## `mods` are the MOD_* bits of the event (TrackEditor.mods_of). Hooks the tool does not override
## do nothing and return false / empty, so TrackEditor's common rules apply (select, Shift adds,
## Ctrl toggles, nothing deselects; SELECT's statics for delete / copy / nudge use delete_ops and
## slide of the kind's owner, 7.6). P8.

const MOD_SHIFT := 1
const MOD_CTRL := 2
const MOD_ALT := 4

var editor: TrackEditor
var id := ""
var title := ""
var purpose := ""                                  # the palette tooltip


func _init(ed: TrackEditor) -> void:
	editor = ed


## The kinds it owns (7.6): bright + pickable while active.
func kinds() -> PackedStringArray:
	return PackedStringArray()


## Its markers (called for every tool after each doc change or bake).
func markers(m: EditorMarkers) -> void:
	pass


func activate() -> void:
	pass


func deactivate() -> void:
	pass


func options(box: VBoxContainer) -> void:
	pass


## Fill the inspector for its kinds.
func inspect(uids: PackedInt32Array, box: VBoxContainer) -> bool:
	return false


## PromptBar entries for what the mouse does on hit.
func hints(hit: EditorHit) -> Array:
	return []


## A step line for the status bar ("" none).
func status_step() -> String:
	return ""


## Press + release within 4 px.
func click(hit: EditorHit, mods: int) -> bool:
	return false


func double_click(hit: EditorHit, mods: int) -> bool:
	return false


## true = this tool owns the drag.
func drag_begin(hit: EditorHit, mods: int) -> bool:
	return false


func drag_move(hit: EditorHit, mods: int) -> void:
	pass


func drag_end(hit: EditorHit, mods: int) -> void:
	pass


func wheel(hit: EditorHit, mods: int, notches: int) -> bool:
	return false


func key(ev: InputEvent) -> bool:
	return false


## An anchored item dragged from SELECT: 0 start, 1 move, 2 end -> ops.
func slide(uid: int, hit: EditorHit, phase: int) -> Array:
	return []


func process(delta: float) -> void:
	pass


func overlay(d: EditorDraw) -> void:
	pass


func on_doc_changed(sections: PackedStringArray, uids: PackedInt32Array) -> void:
	pass


## Ops that delete these uids of its kinds (road points re-anchor through LevelDoc.delete_point_ops).
func delete_ops(uids: PackedInt32Array) -> Array:
	return []


## For framing, box select and the hover box of its kinds.
func item_aabb(uid: int) -> AABB:
	return AABB()


## Base: tells HintCard the tool's first action happened.
func succeeded() -> void:
	if editor != null:
		HintCard.done(editor, id)


## The kind is one of this tool's (7.6).
func owns(kind: String) -> bool:
	return kind in kinds()


static func has_mod(mods: int, mod: int) -> bool:
	return (mods & mod) != 0
