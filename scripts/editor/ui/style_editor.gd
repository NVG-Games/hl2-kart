class_name StyleEditor
extends Dialog
## The small road style editor (2.5, C2 S17): the styles the track can use (the presets, then its
## own); COPY STYLE makes a new own style from the one picked; an own style's NAME, the material
## slots of its kind (MaterialPicker), CENTRE LINES, GRIP and AUTO BANKING. The numeric kind fields
## keep the copied values; presets are read-only. Every change is one undo step. P13.

## The material slots of each kind: [style key, label].
const SLOTS := {
	"open": [["road", "SURFACE"], ["verge", "VERGE"]],
	"street": [["road", "SURFACE"], ["curb", "KERB"], ["walk_mat", "PAVEMENT"]],
	"bridge": [["road", "SURFACE"], ["skirt", "SKIRT"], ["pillar", "PILLAR"]],
	"tunnel": [["road", "SURFACE"], ["wall", "WALL"], ["ceil", "CEILING"], ["light", "LIGHT"]],
}
const MAX_OWN := 32
const ID_LEN := 24
const NAME_LEN := 32

var editor: TrackEditor
var list: ItemList
var panel: VBoxContainer
## The style ids in the list's order.
var ids := PackedStringArray()
## The style shown on the right.
var current := "asphalt"
var _connected := false


func _init(ed: TrackEditor = null) -> void:
	super("ROAD STYLES", Vector2(900, 640))
	editor = ed
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(h)
	list = ItemList.new()
	list.custom_minimum_size = Vector2(300, 460)
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.focus_mode = Control.FOCUS_ALL
	list.item_selected.connect(func(i: int) -> void:
		if i >= 0 and i < ids.size():
			pick(ids[i]))
	h.add_child(list)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	h.add_child(scroll)
	panel = VBoxContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_constant_override("separation", 6)
	scroll.add_child(panel)
	default_focus = add_button("CLOSE", close)
	if editor != null and editor.doc != null:
		editor.doc.changed.connect(_on_doc_changed)
		_connected = true
	refresh()


func _exit_tree() -> void:
	if _connected and editor != null and editor.doc != null and editor.doc.changed.is_connected(_on_doc_changed):
		editor.doc.changed.disconnect(_on_doc_changed)
	_connected = false


func _on_doc_changed(sections: PackedStringArray, _uids: PackedInt32Array, _rect: Rect2i) -> void:
	if "styles" in sections:
		refresh.call_deferred()


func _data() -> Dictionary:
	return editor.doc.data if editor != null and editor.doc != null else {}


## The style's source dict (a preset's or the document's own), {} when unknown.
func source(sid: String) -> Dictionary:
	if LevelStyles.is_preset(sid):
		return LevelStyles.PRESETS[sid]
	var own = _data().get("styles", {})
	if own is Dictionary and own.get(sid) is Dictionary:
		return own[sid]
	return {}


func is_own(sid: String) -> bool:
	return not LevelStyles.is_preset(sid) and not source(sid).is_empty()


## Refills the list and the panel (after any change of the document's styles).
func refresh() -> void:
	ids = LevelStyles.ids(_data())
	if not current in ids:
		current = "asphalt"
	list.clear()
	var full := LevelStyles.resolve(_data(), {})
	for sid in ids:
		var st: Dictionary = full.get(sid, {})
		list.add_item("%s%s" % [str(st.get("name", sid.to_upper())), "" if LevelStyles.is_preset(sid) else "  (TRACK)"])
	var at := Array(ids).find(current)
	if at >= 0:
		list.select(at)
	_fill()


func pick(sid: String) -> void:
	current = sid
	_fill()


func _fill() -> void:
	for c in panel.get_children():
		panel.remove_child(c)
		c.queue_free()
	var full := LevelStyles.resolve(_data(), {})
	var st: Dictionary = full.get(current, {})
	if st.is_empty():
		return
	var own := is_own(current)
	var kind := str(st.get("kind", "open"))
	panel.add_child(EditorKit.section("%s · %s" % [str(st.get("name", "")), kind.to_upper()]))
	panel.add_child(EditorKit.button("COPY STYLE", func() -> void: copy_style(current),
		"A new style of this track's own, starting from this one"))
	if not own:
		panel.add_child(EditorKit.hint("Built-in styles cannot be changed: COPY STYLE makes one of your own."))
	var name_field := EditorKit.text(str(st.get("name", "")), func(t: String) -> void: set_field("name", t.strip_edges().to_upper()), NAME_LEN)
	name_field.editable = own
	panel.add_child(EditorKit.row("NAME", name_field))
	for slot in SLOTS.get(kind, []):
		var key: String = slot[0]
		var mat := str(st.get(key, ""))
		var b := EditorKit.button(mat if mat != "" else "NONE", func() -> void: pick_material(key), "Pick the %s material" % str(slot[1]).to_lower())
		b.disabled = not own
		b.clip_text = true
		panel.add_child(EditorKit.row(str(slot[1]), b))
	var lines := EditorKit.check(bool(st.get("lines", false)), func(on: bool) -> void: set_field("lines", on))
	lines.disabled = not own
	panel.add_child(EditorKit.row("CENTRE LINES", lines))
	var grip := EditorKit.choice(["ROAD", "OFF-ROAD"], 1 if str(st.get("grip", "road")) == "offroad" else 0,
		func(i: int) -> void: set_field("grip", "offroad" if i == 1 else "road"))
	grip.disabled = not own
	panel.add_child(EditorKit.row("GRIP", grip))
	var bank := EditorKit.check(bool(st.get("bank", true)), func(on: bool) -> void: set_field("bank", on))
	bank.disabled = not own
	panel.add_child(EditorKit.row("AUTO BANKING", bank))


## COPY STYLE: a new own style (its id from the name) copied from sid; returns the new id ("" at
## the cap of 32 own styles).
func copy_style(sid: String) -> String:
	if editor == null or editor.doc == null:
		return ""
	var own = _data().get("styles", {})
	if own is Dictionary and (own as Dictionary).size() >= MAX_OWN:
		editor.toast("A track has at most %d styles of its own." % MAX_OWN)
		return ""
	var src := source(sid)
	if src.is_empty():
		return ""
	var st: Dictionary = src.duplicate(true)
	var base := str(src.get("name", sid.to_upper()))
	st["name"] = (base + " COPY").left(NAME_LEN)
	if not st.has("kind"):
		st["kind"] = "open"
	var nid := new_id(sid)
	editor.commit("COPY STYLE", [LevelDoc.op_set(["styles", nid], st)])
	current = nid
	refresh()
	return nid


## A free own-style id from a source id: "asphalt_2", "asphalt_3"...
func new_id(sid: String) -> String:
	var stem := ""
	for c in sid.to_lower():
		stem += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_" else "_"
	stem = stem.left(ID_LEN - 3)
	if stem == "":
		stem = "style"
	var taken := LevelStyles.ids(_data())
	var n := 2
	while ("%s_%d" % [stem, n]) in taken:
		n += 1
	return "%s_%d" % [stem, n]


## One field of the current own style (one undo step; presets are not changed).
func set_field(key: String, value: Variant) -> void:
	if editor == null or not is_own(current):
		return
	if key == "name" and str(value) == "":
		return
	if source(current).get(key) == value:
		return
	editor.commit("STYLE", [LevelDoc.op_set(["styles", current, key], value)])


func pick_material(key: String) -> void:
	if editor == null or not is_own(current):
		return
	var mp := MaterialPicker.new(str(source(current).get(key, "")))
	var sid := current
	mp.picked.connect(func(k: String) -> void:
		current = sid
		set_field(key, k))
	editor.open_dialog(mp)
