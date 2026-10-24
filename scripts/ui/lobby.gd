class_name Lobby
extends Control
## Multiplayer lobby: pick a racer and a vehicle, see who is here (ping,
## ready), chat. The host sets the rules and starts; when everyone is READY
## the race starts by itself after a short countdown.

signal leave_requested

var picker: RacerPicker
var players_box: VBoxContainer
var rules_box: VBoxContainer
var chat_scroll: ScrollContainer
var chat_log: VBoxContainer
var chat_edit: LineEdit
var ready_button: Button
var start_button: Button
var status_label: Label
var title_label: Label
var sub_label: Label
var address_label: Label
var _racer := 0
var _vehicle := 0
var _is_ready := false


func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		root.add_theme_constant_override("margin_" + side, 70)
	root.add_theme_constant_override("margin_top", 34)
	root.add_theme_constant_override("margin_bottom", 30)
	add_child(root)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	root.add_child(col)
	# header
	var head := HBoxContainer.new()
	col.add_child(head)
	var hv := VBoxContainer.new()
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hv)
	title_label = UiKit.label("", 32, Color.WHITE, true)
	title_label.clip_text = true
	hv.add_child(title_label)
	sub_label = UiKit.label("", 16, UiKit.TEXT_DIM)
	hv.add_child(sub_label)
	address_label = UiKit.label("", 15, UiKit.TEXT_DIM)
	address_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	address_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	head.add_child(address_label)
	# racer / vehicle + players
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 30)
	col.add_child(row1)
	picker = RacerPicker.new(112)
	row1.add_child(picker)
	picker.racer_picked.connect(func(i: int):
		_racer = i
		_send_profile()
		var line := Game.voice_line(Game.CHARACTERS[i]["id"], "start")
		if line != "":
			Game.play_ui(line, -3.0))
	picker.vehicle_picked.connect(func(i: int):
		_vehicle = i
		_send_profile())
	var pv := VBoxContainer.new()
	pv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pv.add_theme_constant_override("separation", 10)
	row1.add_child(pv)
	pv.add_child(UiKit.section("PLAYERS"))
	var pframe := PanelContainer.new()
	pframe.add_theme_stylebox_override("panel", UiKit.box(Color(0, 0, 0, 0.4), Color(1, 1, 1, 0.08), 1, 4, 10))
	pframe.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pv.add_child(pframe)
	players_box = VBoxContainer.new()
	players_box.add_theme_constant_override("separation", 4)
	pframe.add_child(players_box)
	# chat + rules
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 30)
	row2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(row2)
	var cv := VBoxContainer.new()
	cv.custom_minimum_size.x = picker.get_combined_minimum_size().x
	cv.add_theme_constant_override("separation", 8)
	row2.add_child(cv)
	cv.add_child(UiKit.section("CHAT"))
	var cframe := PanelContainer.new()
	cframe.add_theme_stylebox_override("panel", UiKit.box(Color(0, 0, 0, 0.4), Color(1, 1, 1, 0.08), 1, 4, 10))
	cframe.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cv.add_child(cframe)
	chat_scroll = ScrollContainer.new()
	chat_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cframe.add_child(chat_scroll)
	chat_log = VBoxContainer.new()
	chat_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_scroll.add_child(chat_log)
	var bar := chat_scroll.get_v_scroll_bar()
	bar.changed.connect(func(): chat_scroll.scroll_vertical = int(bar.max_value))
	chat_edit = UiKit.text_field("", "Say something...  (Enter)", func(_t): pass, 300)
	chat_edit.max_length = 160
	chat_edit.text_submitted.connect(func(t: String):
		Net.say(t)
		chat_edit.text = "")
	cv.add_child(chat_edit)
	var rv := VBoxContainer.new()
	rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rv.add_theme_constant_override("separation", 8)
	row2.add_child(rv)
	rv.add_child(UiKit.section("RULES"))
	rules_box = VBoxContainer.new()
	rules_box.add_theme_constant_override("separation", 8)
	rv.add_child(rules_box)
	# buttons
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 14)
	col.add_child(brow)
	var leave := UiKit.button("STOP SERVER" if Net.is_server else "LEAVE", 200)
	leave.pressed.connect(func(): leave_requested.emit())
	brow.add_child(leave)
	status_label = UiKit.label("", 20, Hl2Style.BRIGHT, true)
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	brow.add_child(status_label)
	ready_button = UiKit.button("READY", 200)
	ready_button.toggle_mode = true
	ready_button.toggled.connect(func(on: bool):
		_is_ready = on
		ready_button.text = "READY  ✓" if on else "READY"
		_send_profile())
	brow.add_child(ready_button)
	start_button = UiKit.button("START RACE", 260)
	start_button.custom_minimum_size.y = 50
	start_button.add_theme_font_size_override("font_size", 20)
	start_button.add_theme_stylebox_override("normal", UiKit.box(Color(UiKit.ORANGE.r, UiKit.ORANGE.g, UiKit.ORANGE.b, 0.85), UiKit.ORANGE, 1, 3, 18))
	start_button.add_theme_stylebox_override("hover", UiKit.box(UiKit.ORANGE.lightened(0.2), Color.WHITE, 2, 3, 18))
	start_button.add_theme_color_override("font_color", Color.BLACK)
	start_button.add_theme_color_override("font_hover_color", Color.BLACK)
	start_button.add_theme_color_override("font_focus_color", Color.BLACK)
	start_button.pressed.connect(func(): Net.start_race_now())
	start_button.visible = Net.is_server
	brow.add_child(start_button)
	# my current profile
	var me: Dictionary = Net.players.get(Net.my_id(), {})
	_racer = _index_of(Game.CHARACTERS, me.get("character", Game.settings["character"]))
	_vehicle = _index_of(Game.VEHICLES, me.get("vehicle", Game.settings["vehicle"]))
	picker.select(_racer, _vehicle)
	Net.roster_changed.connect(_rebuild_players)
	Net.cfg_changed.connect(_on_cfg)
	Net.chat_received.connect(_add_chat)
	Net.countdown_changed.connect(func(_s): _update_status())
	Net.state_changed.connect(func(_s): _update_status())
	_build_rules()
	_on_cfg()
	_rebuild_players()
	_send_profile()
	_add_chat("", "Welcome to %s. Pick a racer and a vehicle, then press READY." % Net.cfg.get("name", "the server"), "info")
	ready_button.grab_focus.call_deferred()


func _index_of(list: Array, id: String) -> int:
	for i in list.size():
		if list[i]["id"] == id:
			return i
	return 0


func _send_profile() -> void:
	var c: String = Game.CHARACTERS[_racer]["id"]
	var v: String = Game.VEHICLES[_vehicle]["id"]
	Game.settings["character"] = c
	Game.settings["vehicle"] = v
	Net.set_profile(c, v, _is_ready)


func _process(_delta: float) -> void:
	if Net.autostart_left >= 0.0:
		_update_status()


func _update_status() -> void:
	if Net.state == "race_wait":
		status_label.text = "A race is in progress. You join the next one."
	elif Net.autostart_left >= 0.0:
		status_label.text = "Everyone is ready. Starting in %d..." % ceili(Net.autostart_left)
	else:
		var waiting := 0
		for p in Net.players.values():
			if not p["ready"]:
				waiting += 1
		status_label.text = "Waiting for %d player%s to be ready" % [waiting, "" if waiting == 1 else "s"] if waiting > 0 else ""


# ---------------------------------------------------------------- players
func _rebuild_players() -> void:
	for n in players_box.get_children():
		n.queue_free()
	var ids: Array = Net.players.keys()
	ids.sort()
	for id in ids:
		players_box.add_child(_player_row(int(id), Net.players[id]))
	var cfg := Net.cfg
	var bots := 0
	if cfg.get("bots", false):
		bots = maxi(0, int(cfg.get("grid", 8)) - ids.size())
	for i in maxi(0, int(cfg.get("max_players", 8)) - ids.size()):
		var empty := UiKit.label("      open slot" if i >= bots else "      bot", 16, Color(1, 1, 1, 0.25))
		empty.custom_minimum_size.y = 34
		players_box.add_child(empty)
	_update_status()


func _player_row(id: int, p: Dictionary) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	h.custom_minimum_size.y = 40
	var pic := TextureRect.new()
	var path := "res://assets/ui/portraits/%s.png" % p["character"]
	pic.texture = load(path) if ResourceLoader.exists(path) else null
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.custom_minimum_size = Vector2(40, 40)
	h.add_child(pic)
	var me := id == Net.my_id()
	var nick := UiKit.label(("★ " if p.get("host", false) else "") + str(p["nick"]), 19, Hl2Style.BRIGHT if me else Color.WHITE, true)
	nick.custom_minimum_size.x = 170
	nick.clip_text = true
	nick.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(nick)
	var what := UiKit.label("%s · %s" % [Game.character(p["character"]).get("short", p["character"]), Game.vehicle(p["vehicle"])["name"]], 14, UiKit.TEXT_DIM)
	what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	what.custom_minimum_size.x = 150
	what.clip_text = true
	what.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(what)
	var ping := UiKit.label("" if p.get("host", false) else "%d ms" % int(p.get("ping", 0)), 15, UiKit.TEXT_DIM)
	ping.custom_minimum_size.x = 56
	ping.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(ping)
	var rd := UiKit.label("READY" if p["ready"] else "", 15, Color(0.55, 0.95, 0.4), true)
	rd.custom_minimum_size.x = 60
	rd.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(rd)
	if Net.is_server and id != 1:
		var kick := UiKit.button("KICK", 70)
		kick.custom_minimum_size.y = 34
		kick.pressed.connect(func(): Net.kick(id))
		h.add_child(kick)
	return h


# ---------------------------------------------------------------- rules
func _on_cfg() -> void:
	var cfg := Net.cfg
	title_label.text = str(cfg.get("name", "LOBBY"))
	var diff: String = Game.DIFFICULTIES[clampi(int(cfg.get("difficulty", 1)), 0, 2)]["name"]
	var tr := Game.track(str(cfg.get("track", "")))
	var sky: String = Game.SKIES[Game.sky_index(str(cfg.get("sky", "")))][1] if tr.get("weather", false) else "map sky"
	sub_label.text = "%s  ·  %d laps  ·  %s  ·  %s  ·  %s%s" % [tr["name"], int(cfg.get("laps", 3)), diff, sky,
		"bots fill the grid to %d" % int(cfg.get("grid", 8)) if cfg.get("bots", false) else "no bots",
		"  ·  password" if cfg.get("locked", false) else ""]
	if Net.is_server:
		var addrs := []
		for a in Net.local_addresses():
			addrs.append("%s:%d" % [a, int(cfg.get("port", 27015))])
		var txt := "Friends connect to  " + "  /  ".join(PackedStringArray(addrs))
		if Net.external_ip != "":
			txt += "\nInternet:  %s:%d" % [Net.external_ip, int(cfg.get("port", 27015))]
		address_label.text = txt
	if not Net.is_server:
		_build_rules()
	_rebuild_players()


func _build_rules() -> void:
	for n in rules_box.get_children():
		n.queue_free()
	var cfg := Net.cfg
	var host := Net.is_server
	var w := 210
	var mp := UiKit.slider(1, Net.MAX_RACERS, 1, int(cfg.get("max_players", 8)), func(v: float): Net.set_rule("max_players", int(v)))
	rules_box.add_child(UiKit.row("Max players", mp, w))
	var bots := UiKit.toggle(bool(cfg.get("bots", true)), func(on: bool): Net.set_rule("bots", on))
	rules_box.add_child(UiKit.row("Bots fill the grid", bots, w))
	var grid := UiKit.slider(2, Net.MAX_RACERS, 1, int(cfg.get("grid", 8)), func(v: float): Net.set_rule("grid", int(v)))
	rules_box.add_child(UiKit.row("Racers on the grid", grid, w))
	var laps := UiKit.slider(1, 9, 1, int(cfg.get("laps", 3)), func(v: float): Net.set_rule("laps", int(v)))
	rules_box.add_child(UiKit.row("Laps", laps, w))
	var names: Array = Game.DIFFICULTIES.map(func(d: Dictionary) -> String: return d["name"])
	var diff := UiKit.segmented(names, int(cfg.get("difficulty", 1)), func(i: int): Net.set_rule("difficulty", i))
	rules_box.add_child(UiKit.row("Difficulty", diff, w))
	var sky := UiKit.dropdown(Game.sky_names(), Game.sky_index(str(cfg.get("sky", ""))), func(i: int): Net.set_rule("sky", Game.SKIES[i][0]))
	sky.disabled = not Game.track(str(cfg.get("track", ""))).get("weather", false)
	var track_names: Array = Game.TRACKS.map(func(t: Dictionary) -> String: return t["name"])
	var track := UiKit.dropdown(track_names, Game.track_index(str(cfg.get("track", ""))), func(i: int):
		Net.set_rule("track", Game.TRACKS[i]["id"])
		sky.disabled = not Game.TRACKS[i]["weather"])
	rules_box.add_child(UiKit.row("Track", track, w))
	rules_box.add_child(UiKit.row("Weather", sky, w))
	if not host:
		# everyone sees the rules; only the host changes them
		for c in [mp, grid, laps]:
			((c as HBoxContainer).get_child(0) as HSlider).editable = false
		bots.disabled = true
		sky.disabled = true
		track.disabled = true
		for b in diff.get_children():
			(b as Button).disabled = true


# ---------------------------------------------------------------- chat
func _add_chat(nick: String, text: String, kind: String) -> void:
	var l := UiKit.label(text if kind == "info" or nick == "" else "%s: %s" % [nick, text], 17,
		UiKit.TEXT_DIM if kind == "info" or nick == "" else Color.WHITE)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 600
	chat_log.add_child(l)
	while chat_log.get_child_count() > 80:
		chat_log.get_child(0).free()
	if kind == "chat":
		Game.play_ui("res://assets/sound/friends/message.wav", -12.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not chat_edit.has_focus():
		get_viewport().set_input_as_handled()
		leave_requested.emit()
