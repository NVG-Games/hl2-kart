class_name AutoDressDialog
extends Dialog
## AUTO DRESS (4.4): five toggles, all on (ITEMS, BOOST PADS, RAILS, SCENERY, CROWD); DRESS calls
## TrackEditor.auto_dress with them (one undo step "AUTO DRESS"; it needs the last bake's roads).
## P10.

## [option key, title, what it adds]
const PARTS := [["items", "ITEMS", "A crate row every 350-450 m on the straights, one per branch."],
	["pads", "BOOST PADS", "A pad at the exit of the two longest bends."],
	["rails", "RAILS", "Rails on the outside of tight bends."],
	["scenery", "SCENERY", "The theme's objects along both sides of every road."],
	["crowd", "CROWD", "A grandstand on both sides of the start."]]

var editor: TrackEditor
## key -> on
var opts := {"items": true, "pads": true, "rails": true, "scenery": true, "crowd": true}
var toggles := {}


func _init(ed: TrackEditor = null) -> void:
	super("AUTO DRESS", Vector2(700, 540))
	editor = ed
	var note := UiKit.label("Adds what a track needs around its road, in one step you can undo.", 17, UiKit.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 640
	body.add_child(note)
	for p in PARTS:
		var k: String = p[0]
		var t := UiKit.toggle(true, func(on: bool) -> void: opts[k] = on)
		t.focus_mode = Control.FOCUS_ALL
		toggles[k] = t
		var row := UiKit.row(p[1], t, 200)
		var d := UiKit.label(p[2], 15, UiKit.TEXT_DIM)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size.x = 380
		row.add_child(d)
		t.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_child(row)
	add_button("CANCEL", close)
	default_focus = add_button("DRESS", dress)


func _ready() -> void:
	default_focus.grab_focus.call_deferred()


## DRESS: TrackEditor.auto_dress(opts), then closes.
func dress() -> void:
	var e := editor
	var o := opts.duplicate()
	close()
	if e != null:
		e.auto_dress(o)
