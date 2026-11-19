class_name MaterialPicker
extends Dialog
## Searchable world materials with albedo thumbnails (SourceMaterials.tex), filtered by prefix
## ("nature/", "concrete/"...). A pick (double click, A, PICK) emits picked(key) and closes it.
## Thumbnails load a few per frame. P10.

signal picked(key: String)

## Results shown at most (a search narrows them).
const MAX_SHOWN := 400
const THUMB := 64
const PER_FRAME := 6

## The key picked before (selected in the list).
var current_key := ""
var prefix_list := PackedStringArray()
var search: LineEdit
var list: ItemList
var count_label: Label
## The keys shown, in the list's order.
var keys: PackedStringArray = []
var _all: PackedStringArray = []
var _next_thumb := 0


func _init(current: String, prefixes := PackedStringArray()) -> void:
	super("PICK A MATERIAL", Vector2(1100, 720))
	current_key = current
	prefix_list = prefixes
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	body.add_child(top)
	search = UiKit.text_field("", "Search materials", func(_t: String) -> void: _fill(), 500)
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(search)
	count_label = UiKit.label("", 15, UiKit.TEXT_DIM)
	top.add_child(count_label)
	list = ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.max_columns = 0
	list.same_column_width = true
	list.fixed_column_width = 150
	list.icon_mode = ItemList.ICON_MODE_TOP
	list.fixed_icon_size = Vector2i(THUMB, THUMB)
	list.focus_mode = Control.FOCUS_ALL
	list.item_activated.connect(func(i: int) -> void: _pick(i))
	body.add_child(list)
	add_button("CANCEL", close)
	default_focus = add_button("PICK", func() -> void:
		var sel := list.get_selected_items()
		if not sel.is_empty():
			_pick(sel[0]))
	_all = all_keys(prefix_list)
	_fill()


func _ready() -> void:
	list.grab_focus.call_deferred()


## The world materials (not model skins) whose key starts with one of the prefixes, sorted.
static func all_keys(pre: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for k in Game.materials_db:
		var key := str(k)
		if key.begins_with("models/") or key.begins_with("particle") or key.begins_with("sprites/"):
			continue
		if not pre.is_empty():
			var ok := false
			for p in pre:
				if key.begins_with(p):
					ok = true
					break
			if not ok:
				continue
		out.append(key)
	out.sort()
	return out


func _fill() -> void:
	var q := search.text.strip_edges().to_lower() if search != null else ""
	list.clear()
	keys = PackedStringArray()
	var total := 0
	for k in _all:
		if q != "" and k.to_lower().find(q) < 0:
			continue
		total += 1
		if keys.size() >= MAX_SHOWN:
			continue
		keys.append(k)
		var i := list.add_item(k.get_file())
		list.set_item_tooltip(i, k)
		if k == current_key:
			list.select(i)
	_next_thumb = 0
	if count_label != null:
		count_label.text = "%d of %d" % [keys.size(), total] if total > keys.size() else "%d" % total
	if _all.is_empty():
		count_label.text = "No materials on this computer"


func _process(_delta: float) -> void:
	var n := 0
	while _next_thumb < keys.size() and n < PER_FRAME:
		var t := SourceMaterials.albedo(keys[_next_thumb])
		if t != null and _next_thumb < list.item_count:
			list.set_item_icon(_next_thumb, t)
		_next_thumb += 1
		n += 1


func _pick(i: int) -> void:
	if i < 0 or i >= keys.size():
		return
	picked.emit(keys[i])
	close()
