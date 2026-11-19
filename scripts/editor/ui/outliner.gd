class_name Outliner
extends VBoxContainer
## The outliner (1.3): the document's items by group in a Tree (ROAD, BRANCHES with their points,
## OBJECTS by category, LIGHTS & FX, ITEMS, ZONES, HAZARDS, CROWDS, LAKES), each row
## "name / model · s 412". A click selects (Shift / Ctrl add), a double click frames, the search
## field filters. The selection syncs both ways. No eye toggles: hiding is H / Alt+H. P10.

## group title -> document sections in it (OBJECTS are split by catalog category).
const GROUPS := [["ROAD", ["road"]], ["BRANCHES", ["branches"]], ["OBJECTS", ["props"]],
	["LIGHTS & FX", ["lights", "fires", "screens"]], ["ITEMS", ["items", "crates", "pads", "barrels"]],
	["ZONES", ["zones"]], ["HAZARDS", ["hazards"]], ["CROWDS", ["crowds", "eggs"]], ["LAKES", ["lakes"]]]
const NOUN := {"items": "CRATE ROW", "crates": "CRATE", "pads": "BOOST PAD", "barrels": "BARRELS", "zones": "LOW GRAVITY",
	"lights": "LIGHT", "fires": "FIRE", "screens": "SCREEN", "crowds": "SPECTATORS", "eggs": "EXTRA", "lakes": "LAKE"}
## Rows past this in one group are left out.
const MAX_ROWS := 1500
## Seconds between two rebuilds while the document keeps changing (a drag).
const THROTTLE := 0.3

var editor: TrackEditor
var search: LineEdit
var tree: Tree
## uid -> TreeItem
var rows := {}
var _dirty := true
var _force := true
var _built_rev := -1
var _next_ms := 0
var _syncing := false
var _collapsed := {}           # group title -> true
var _cats := {}                # model -> category


func _init() -> void:
	name = "Outliner"
	add_theme_constant_override("separation", 4)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(EditorKit.section("OUTLINER"))
	search = LineEdit.new()
	search.placeholder_text = "Search"
	search.clear_button_enabled = true
	search.custom_minimum_size.y = EditorKit.ROW_H - 4
	search.text_changed.connect(func(_t: String) -> void:
		_force = true
		refresh())
	add_child(search)
	tree = Tree.new()
	tree.hide_root = true
	tree.select_mode = Tree.SELECT_MULTI
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.custom_minimum_size = Vector2(60, 120)
	tree.focus_mode = Control.FOCUS_CLICK
	tree.allow_reselect = true
	tree.multi_selected.connect(func(_it: TreeItem, _col: int, _sel: bool) -> void: _picked.call_deferred())
	tree.item_activated.connect(_activated)
	tree.item_collapsed.connect(func(it: TreeItem) -> void:
		if it.get_metadata(0) is String:
			_collapsed[str(it.get_metadata(0))] = it.collapsed)
	add_child(tree)


func setup(ed: TrackEditor) -> void:
	editor = ed
	if ed.selection != null and not ed.selection.changed.is_connected(sync_selection):
		ed.selection.changed.connect(sync_selection)
	refresh()


## Rebuilds soon when the document changed (cheap to call often: a selection change only syncs).
func refresh() -> void:
	_dirty = true


func _process(_delta: float) -> void:
	if not _dirty or not is_visible_in_tree():
		return
	if not _force and (editor == null or editor.doc == null or editor.doc.revision == _built_rev):
		_dirty = false
		return
	if not _force and Time.get_ticks_msec() < _next_ms:
		return
	rebuild()


## The tree from the document now.
func rebuild() -> void:
	_dirty = false
	_force = false
	_next_ms = Time.get_ticks_msec() + int(THROTTLE * 1000.0)
	_built_rev = editor.doc.revision if editor != null and editor.doc != null else -1
	tree.clear()
	rows.clear()
	if editor == null or editor.doc == null:
		return
	var root := tree.create_item()
	var q := search.text.strip_edges().to_lower()
	var d: Dictionary = editor.doc.data
	var main: LevelRoad = editor.road(-1)
	for g in GROUPS:
		var title: String = g[0]
		var group: TreeItem = null
		var n := 0
		for sec in g[1]:
			if sec == "road":
				var pts = d.get("road", {}).get("points", []) if d.get("road") is Dictionary else []
				var k := 0
				for p in pts:
					k += 1
					if not (p is Dictionary):
						continue
					var label := "POINT %d · %s" % [k, str(p.get("style", ""))]
					if main != null and main.n > 0:
						label += " · s %d" % int(main.anchor_s({"p": int(p.get("uid", 0)), "t": 0.0}))
					group = _group(root, group, title)
					_add_under(group, int(p.get("uid", 0)), label, q)
					n += 1
			elif sec == "branches":
				for b in d.get("branches", []):
					if not (b is Dictionary):
						continue
					group = _group(root, group, title)
					var bi := _add_under(group, int(b.get("uid", 0)), "%s · %s" % [str(b.get("name", "BRANCH")), str(b.get("kind", "alt")).to_upper()], q)
					if bi == null:
						continue
					var k := 0
					for p in b.get("points", []):
						k += 1
						if p is Dictionary:
							_add_under(bi, int(p.get("uid", 0)), "POINT %d" % k, q)
					n += 1
			elif sec == "props":
				var cats := {}
				for p in d.get("props", []):
					if not (p is Dictionary):
						continue
					var m := str(p.get("model", ""))
					var cat := _category(m)
					if not cats.has(cat):
						group = _group(root, group, title)
						cats[cat] = tree.create_item(group)
						(cats[cat] as TreeItem).set_text(0, cat)
						(cats[cat] as TreeItem).set_selectable(0, false)
						(cats[cat] as TreeItem).set_metadata(0, title + "/" + cat)
						(cats[cat] as TreeItem).collapsed = _collapsed.get(title + "/" + cat, true)
					if n < MAX_ROWS:
						_add_under(cats[cat], int(p.get("uid", 0)), m.get_file(), q)
					n += 1
				for cat in cats:
					var ci: TreeItem = cats[cat]
					if ci.get_child_count() == 0:
						ci.free()
					else:
						ci.set_text(0, "%s (%d)" % [cat, ci.get_child_count()])
			else:
				for it in d.get(sec, []):
					if not (it is Dictionary) or n >= MAX_ROWS:
						continue
					group = _group(root, group, title)
					_add_under(group, int(it.get("uid", 0)), _row_text(sec, it, main), q)
					n += 1
		if group != null:
			if group.get_child_count() == 0:
				group.free()
			else:
				group.set_text(0, "%s (%d)" % [title, n])
	sync_selection()


func _group(root: TreeItem, group: TreeItem, title: String) -> TreeItem:
	if group != null:
		return group
	var g := tree.create_item(root)
	g.set_text(0, title)
	g.set_selectable(0, false)
	g.set_metadata(0, title)
	g.set_custom_color(0, UiKit.ORANGE)
	g.collapsed = _collapsed.get(title, title != "ROAD" and title != "HAZARDS")
	return g


## A row (null when the search leaves it out).
func _add_under(parent: TreeItem, uid: int, text: String, q: String) -> TreeItem:
	if uid <= 0 or (q != "" and text.to_lower().find(q) < 0):
		return null
	var it := tree.create_item(parent)
	it.set_text(0, text)
	it.set_metadata(0, uid)
	it.set_tooltip_text(0, text)
	rows[uid] = it
	return it


func _row_text(sec: String, it: Dictionary, main: LevelRoad) -> String:
	var t := str(NOUN.get(sec, sec.to_upper()))
	match sec:
		"hazards":
			t = str(it.get("type", "hazard")).to_upper().replace("_", " ")
		"crowds":
			t = "SPECTATORS · %d m" % int(float(it.get("length", 20.0)))
		"eggs":
			t = str(it.get("kind", "extra")).to_upper()
		"lights":
			t = "LIGHT · %d m" % int(float(it.get("range", 16.0)))
	var a = it.get("at", it.get("a"))
	if a is Dictionary and main != null and main.n > 0 and int(it.get("road", -1)) == -1:
		t += " · s %d" % int(main.anchor_s(a))
	return t


func _category(model: String) -> String:
	if _cats.has(model):
		return _cats[model]
	var info = Game.models.get(model, {})
	var c := PropCatalog.category_of(model, info if info is Dictionary else {})
	_cats[model] = c
	return c


## A short name for an item ("CRATE ROW · s 412", a prop's model file).
static func item_name(ed: TrackEditor, uid: int, found := {}) -> String:
	var f: Dictionary = found if not found.is_empty() else ed.doc.find(uid)
	if f.is_empty():
		return ""
	var sec := str(f.get("section", ""))
	var it = f.get("item", {})
	if not (it is Dictionary):
		return ""
	match sec:
		"road":
			return "ROAD POINT"
		"branches":
			return str(it.get("name", "BRANCH")) if not f.has("branch") else "BRANCH POINT"
		"props":
			return str(it.get("model", "")).get_file()
		"hazards":
			return str(it.get("type", "hazard")).to_upper().replace("_", " ")
	return str(NOUN.get(sec, sec.to_upper()))


## Selects the tree rows of the editor's selection (without echoing it back).
func sync_selection() -> void:
	if editor == null or editor.selection == null:
		return
	_syncing = true
	tree.deselect_all()
	var first: TreeItem = null
	for u in editor.selection.uids:
		var it: TreeItem = rows.get(u)
		if it == null:
			continue
		var p := it.get_parent()
		while p != null:
			p.collapsed = false
			p = p.get_parent()
		it.select(0)
		if first == null:
			first = it
	if first != null:
		tree.scroll_to_item(first)
	_syncing = false


func _picked() -> void:
	if _syncing or editor == null:
		return
	var out := PackedInt32Array()
	var it := tree.get_next_selected(null)
	while it != null:
		var m = it.get_metadata(0)
		if m is int and int(m) > 0:
			out.append(int(m))
		it = tree.get_next_selected(it)
	if out != editor.selection.uids:
		_syncing = true
		editor.select(out)
		_syncing = false


func _activated() -> void:
	var it := tree.get_selected()
	if it == null or editor == null:
		return
	var m = it.get_metadata(0)
	if m is int and int(m) > 0:
		editor.frame(SelectTool.item_box(editor, int(m)))
