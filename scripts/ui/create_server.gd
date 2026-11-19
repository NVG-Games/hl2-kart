class_name CreateServer
extends Dialog
## CREATE SERVER: host a game that friends join from FIND SERVERS (LAN / by
## address / INTERNET via a master server). The host races too.
## The track: the seven circuits, then MY TRACKS and the kept downloads (5.1), picked by id; opened
## through the editor's HOST it starts on that track (EditorSession.host_track, used once).

signal hosted

const SEPARATOR := "MY TRACKS"

var error: Label
var track_pick: OptionButton
var track_id := ""
var _grid_row: Control


func _init() -> void:
	super("CREATE SERVER", Vector2(1340, 760))


func _put(key: String, value: Variant) -> void:
	Game.settings[key] = value


func _ready() -> void:
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 48)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(cols)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 16)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 16)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	var s := Game.settings
	# ---- server
	left.add_child(UiKit.section("SERVER"))
	var nick := UiKit.text_field(Game.nickname(), "Player", func(t: String): _put("nickname", t.strip_edges()))
	nick.max_length = 24
	left.add_child(UiKit.row("Your name", nick, 200))
	var name_edit := UiKit.text_field(str(s.get("host_name", "")), "%s's server" % Game.nickname(), func(t: String): _put("host_name", t))
	name_edit.max_length = 48
	left.add_child(UiKit.row("Server name", name_edit, 200))
	left.add_child(UiKit.row("Max players", UiKit.slider(1, Net.MAX_RACERS, 1, int(s.get("host_max_players", 8)),
		func(v: float): _put("host_max_players", int(v))), 200))
	var pw := UiKit.text_field(str(s.get("host_password", "")), "empty = anyone can join", func(t: String): _put("host_password", t))
	pw.secret = true
	left.add_child(UiKit.row("Password", pw, 200))
	var port := UiKit.text_field(str(s.get("host_port", Net.DEFAULT_PORT)), "27015", func(t: String):
		if t.is_valid_int():
			_put("host_port", clampi(int(t), 1024, 65000)), 160)
	left.add_child(UiKit.row("UDP port", port, 200))
	left.add_child(UiKit.row("LAN only", UiKit.toggle(bool(s.get("host_lan_only", false)), func(on: bool): _put("host_lan_only", on)), 200))
	left.add_child(UiKit.row("Open router ports (UPnP)", UiKit.toggle(bool(s.get("host_upnp", true)), func(on: bool): _put("host_upnp", on)), 260))
	# ---- race
	right.add_child(UiKit.section("RACE"))
	var grid_slider := UiKit.slider(2, Net.MAX_RACERS, 1, int(s.get("host_grid", 8)), func(v: float): _put("host_grid", int(v)))
	_grid_row = UiKit.row("Racers on the grid", grid_slider, 220)
	right.add_child(UiKit.row("Fill empty slots with bots", UiKit.toggle(bool(s.get("host_bots", true)), func(on: bool):
		_put("host_bots", on)
		_grid_row.modulate.a = 1.0 if on else 0.4), 300))
	right.add_child(_grid_row)
	_grid_row.modulate.a = 1.0 if s.get("host_bots", true) else 0.4
	right.add_child(UiKit.row("Laps", UiKit.slider(1, 9, 1, int(s.get("laps", 3)), func(v: float): _put("laps", int(v))), 220))
	var names: Array = Game.DIFFICULTIES.map(func(d: Dictionary) -> String: return d["name"])
	right.add_child(UiKit.row("Difficulty", UiKit.segmented(names, int(s.get("difficulty", 1)), func(i: int): _put("difficulty", i)), 220))
	right.add_child(UiKit.row("Track hazards", UiKit.segmented(["OFF", "ON"], int(s.get("hazards", 1)),
		func(i: int): _put("hazards", i)), 220))
	track_id = Game.track_pick()
	var ses = Game.editor
	var host_track = ses.get("host_track") if ses != null else null
	if host_track is String and host_track != "":
		# HOST from the editor or its home: that track, this once
		track_id = host_track
		ses.set("host_track", "")
	track_pick = track_dropdown(track_id, func(id: String): track_id = id)
	if picked(track_pick) != "":
		track_id = picked(track_pick)
	right.add_child(UiKit.row("Track", track_pick, 220))
	Game.custom_tracks_changed.connect(_on_customs_changed)
	var note := UiKit.label("Friends on your network find the server under FIND SERVERS > LAN. Over the internet they type "
		+ "your public address (UPnP opens UDP %d-%d on the router, or forward them by hand). With bots off, "
		% [int(s.get("host_port", 27015)), int(s.get("host_port", 27015)) + 1] + "only people race: 1 on 1, three friends, any mix.", 15, UiKit.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 560
	right.add_child(note)
	error = UiKit.label("", 16, Color(1, 0.45, 0.35))
	body.add_child(error)
	# a custom track handed over by HOST that cannot be raced says why (the server would fall back)
	var sel := track_pick.selected
	if CustomTracks.is_custom(track_id) and sel >= 0 and track_pick.is_item_disabled(sel):
		error.text = track_pick.get_item_tooltip(sel)
	add_button("CANCEL", close)
	var go := add_button("START SERVER", _start)
	go.custom_minimum_size.x = 220
	default_focus = go
	go.grab_focus.call_deferred()


## A background check finished (a track's errors are known now): the items again.
func _on_customs_changed() -> void:
	fill_tracks(track_pick, track_id)


func _start() -> void:
	var s := Game.settings
	_put("track", track_id)
	_put("track_guid", str(CustomTracks.meta(track_id).get("guid", "")) if CustomTracks.is_custom(track_id) else "")
	Game.save_settings()
	var err := Net.host({
		"name": str(s.get("host_name", "")), "port": int(s.get("host_port", Net.DEFAULT_PORT)),
		"max_players": int(s.get("host_max_players", 8)), "bots": bool(s.get("host_bots", true)),
		"grid": int(s.get("host_grid", 8)), "laps": int(s.get("laps", 3)), "difficulty": int(s.get("difficulty", 1)),
		"hazards": int(s.get("hazards", 1)),
		"track": track_id,
		"password": str(s.get("host_password", "")),
		"lan_only": bool(s.get("host_lan_only", false)), "upnp": bool(s.get("host_upnp", true)),
		"master": str(s.get("master_server", "")),
	})
	if err != OK:
		error.text = Net.last_error
		return
	hosted.emit()
	close()


# ---------------------------------------------------------------- the track dropdown (also the lobby's)

## The circuits, a "MY TRACKS" separator, then the own tracks and the kept downloads; each item's
## metadata is its id. A circuit this install has not built, or a custom track with errors (or
## one marked unusable), is disabled. on_pick(id) on a choice.
static func track_dropdown(selected: String, on_pick: Callable) -> OptionButton:
	var holder := []
	var names: Array = Game.TRACKS.map(func(t: Dictionary) -> String: return t["name"])
	var o := UiKit.dropdown(names, 0, func(i: int):
		var dd: OptionButton = holder[0]
		var id = dd.get_item_metadata(i)
		if id is String and id != "":
			on_pick.call(id))
	holder.append(o)
	fill_tracks(o, selected)
	return o


## (Re)fills the dropdown and selects `selected` (added at the end when the lists lack it).
static func fill_tracks(o: OptionButton, selected: String) -> void:
	o.clear()
	for t in Game.TRACKS:
		o.add_item(str(t["name"]))
		var i := o.item_count - 1
		o.set_item_metadata(i, str(t["id"]))
		# (a track this install has not built yet can not be hosted: Game.track_installed)
		if not Game.track_installed(t["id"]):
			o.set_item_disabled(i, true)
			o.set_item_tooltip(i, "Not built on this computer: run the setup again.")
	var customs: Array = Game.all_tracks().slice(Game.TRACKS.size())
	if not customs.is_empty():
		o.add_separator(SEPARATOR)
	for m in customs:
		_add_custom(o, m)
	select_track(o, selected)


static func _add_custom(o: OptionButton, m: Dictionary) -> void:
	var id := str(m.get("id", ""))
	var label := str(m.get("name", id))
	if str(m.get("kind", "")) == "kept":
		label += "  (downloaded)"
	var why := CustomTracks.unusable(id)
	if why == "" and bool(m.get("checked", false)) and not bool(m.get("raceable", false)):
		why = "%d errors: fix them in the TRACK EDITOR" % maxi(1, int(m.get("errors", 1)))
	o.add_item(label)
	var i := o.item_count - 1
	o.set_item_metadata(i, id)
	if why != "":
		o.set_item_disabled(i, true)
		o.set_item_tooltip(i, "Cannot race: %s" % why)
	elif str(m.get("author", "")) != "":
		o.set_item_tooltip(i, "by %s" % str(m["author"]))


## Selects the item whose id is `id` (a custom track missing from the lists is added for it).
static func select_track(o: OptionButton, id: String) -> void:
	for i in o.item_count:
		if o.get_item_metadata(i) is String and str(o.get_item_metadata(i)) == id:
			o.select(i)
			return
	if CustomTracks.is_custom(id) and CustomTracks.has(id):
		_add_custom(o, CustomTracks.meta(id))
		o.select(o.item_count - 1)
		return
	for i in o.item_count:
		if o.get_item_metadata(i) is String and not o.is_item_disabled(i):
			o.select(i)
			return


## The id of the selected item ("" when none).
static func picked(o: OptionButton) -> String:
	var i := o.selected
	if i < 0 or not (o.get_item_metadata(i) is String):
		return ""
	return str(o.get_item_metadata(i))
