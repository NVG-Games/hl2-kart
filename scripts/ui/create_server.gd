class_name CreateServer
extends Dialog
## CREATE SERVER: host a game that friends join from FIND SERVERS (LAN / by
## address / INTERNET via a master server). The host races too.

signal hosted

var error: Label
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
	var weather := UiKit.dropdown(Game.sky_names(), Game.sky_index(str(s.get("sky", ""))), func(i: int): _put("sky", Game.SKIES[i][0]))
	var track_names: Array = Game.TRACKS.map(func(t: Dictionary) -> String: return t["name"])
	right.add_child(UiKit.row("Track", UiKit.dropdown(track_names, Game.track_index(str(s.get("track", ""))), func(i: int):
		_put("track", Game.TRACKS[i]["id"])
		weather.disabled = not Game.TRACKS[i]["weather"]), 220))
	weather.disabled = not Game.track(str(s.get("track", ""))).get("weather", false)
	right.add_child(UiKit.row("Weather", weather, 220))
	var note := UiKit.label("Friends on your network find the server under FIND SERVERS > LAN. Over the internet they type "
		+ "your public address (UPnP opens UDP %d-%d on the router, or forward them by hand). With bots off, "
		% [int(s.get("host_port", 27015)), int(s.get("host_port", 27015)) + 1] + "only people race: 1 on 1, three friends, any mix.", 15, UiKit.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 560
	right.add_child(note)
	error = UiKit.label("", 16, Color(1, 0.45, 0.35))
	body.add_child(error)
	add_button("CANCEL", close)
	var go := add_button("START SERVER", _start)
	go.custom_minimum_size.x = 220
	go.grab_focus.call_deferred()


func _start() -> void:
	var s := Game.settings
	Game.save_settings()
	var err := Net.host({
		"name": str(s.get("host_name", "")), "port": int(s.get("host_port", Net.DEFAULT_PORT)),
		"max_players": int(s.get("host_max_players", 8)), "bots": bool(s.get("host_bots", true)),
		"grid": int(s.get("host_grid", 8)), "laps": int(s.get("laps", 3)), "difficulty": int(s.get("difficulty", 1)),
		"sky": str(s.get("sky", "sky_day01_01")), "track": str(s.get("track", "city17_circuit")),
		"password": str(s.get("host_password", "")),
		"lan_only": bool(s.get("host_lan_only", false)), "upnp": bool(s.get("host_upnp", true)),
		"master": str(s.get("master_server", "")),
	})
	if err != OK:
		error.text = Net.last_error
		return
	hosted.emit()
	close()
