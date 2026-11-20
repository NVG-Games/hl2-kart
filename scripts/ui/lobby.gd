class_name Lobby
extends Control
## Multiplayer lobby: pick a racer and a vehicle, see who is here (ping,
## ready), chat. The host sets the rules and starts; when everyone is READY
## the race starts by itself after a short countdown. With a pad: Start toggles READY, B asks
## before it leaves (the host's leaving stops the server), the right stick scrolls the chat.
## A custom track (6.5): every row has a TRACK column (42% / PREP / OK / NO TRACK), a friend's own
## download shows under the sub line with its progress, time left and thumbnail (then PREPARING
## TRACK...; a failure gives the reason and RETRY, downloads off the DOWNLOAD IT? box), the host's
## status line names whoever blocks START RACE (which stays disabled until everyone has the track
## and is READY), and a friend can KEEP TRACK once it is here.

signal leave_requested

var picker: RacerPicker
var players_box: VBoxContainer
var rules_box: VBoxContainer
var rscroll: ScrollContainer
var chat_scroll: ScrollContainer
var chat_log: VBoxContainer
var chat_edit: LineEdit
var ready_button: Button
var start_button: Button
var status_label: Label
var title_label: Label
var sub_label: Label
var address_label: Label
var leave_button: Button
var _confirm: MessageBox
var _racer := 0
var _vehicle := 0
var _is_ready := false
var track_dd: OptionButton           # the host's track pick (built-ins, MY TRACKS)
var keep_button: Button
var retry_button: Button
var dl_row: HBoxContainer            # this client's own download: thumb, line, bar / reason + RETRY
var dl_thumb: TextureRect
var dl_label: Label
var dl_pct: Label                    # "42%  ·  6 s LEFT" at the bar's end (never clipped)
var dl_bar: ProgressBar
var _track_cells := {}               # peer id -> its TRACK column label (updated in place)
var _ask_box: MessageBox             # DOWNLOAD IT?
var _asked := ""                     # the sha DOWNLOAD IT? was shown for
var _fetching := false               # a download (or its prepare) is on show: the blip at the end
var _shown_id := ""                  # the track the download row is about
var _tick := 0.0

## A player row's height (an open slot's too: the PLAYERS box keeps one height whoever is in, so
## every rule fits under it at a 900 px canvas) and its fixed columns (px): "999 ms", "READY",
## "NO TRACK", KICK.
const ROW_H := 34
## The rules' button rows (track, difficulty, hazards) in the lobby (UiKit's are 42).
const RULE_H := 36
const COL_PING := 64
const COL_READY := 66
const COL_TRACK := 96
const COL_KICK := 80


func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group(InputPrompts.SCREEN_GROUP)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		root.add_theme_constant_override("margin_" + side, 56)
	root.add_theme_constant_override("margin_top", 28)
	root.add_theme_constant_override("margin_bottom", 26)
	add_child(root)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
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
	var sub_row := HBoxContainer.new()
	sub_row.add_theme_constant_override("separation", 14)
	hv.add_child(sub_row)
	sub_label = UiKit.label("", 16, UiKit.TEXT_DIM)
	sub_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sub_row.add_child(sub_label)
	# a friend who downloaded the server's track keeps it (DOWNLOADED, never evicted)
	keep_button = UiKit.button("KEEP TRACK", 150)
	keep_button.custom_minimum_size.y = 32
	keep_button.visible = false
	keep_button.pressed.connect(_keep_track)
	sub_row.add_child(keep_button)
	_build_download_row(hv)
	address_label = UiKit.label("", 15, UiKit.TEXT_DIM)
	address_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	address_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	head.add_child(address_label)
	# left: racer / vehicle and the chat under them; right: players and the rules
	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 28)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(main)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	main.add_child(left)
	picker = RacerPicker.new(100, 84)
	picker.lock_edges(true, false)
	left.add_child(picker)
	picker.racer_picked.connect(func(i: int):
		_racer = i
		_send_profile()
		var line := Game.voice_line(Game.CHARACTERS[i]["id"], "start")
		if line != "":
			Game.play_ui(line, -3.0))
	picker.vehicle_picked.connect(func(i: int):
		_vehicle = i
		_send_profile())
	left.add_child(UiKit.section("CHAT"))
	var cframe := PanelContainer.new()
	cframe.add_theme_stylebox_override("panel", UiKit.box(Color(0, 0, 0, 0.55), Color(1, 1, 1, 0.08), 1, 4, 10))
	cframe.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cframe.custom_minimum_size.y = 90
	left.add_child(cframe)
	chat_scroll = ScrollContainer.new()
	chat_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cframe.add_child(chat_scroll)
	chat_log = VBoxContainer.new()
	chat_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_scroll.add_child(chat_log)
	var bar := chat_scroll.get_v_scroll_bar()
	bar.changed.connect(func(): chat_scroll.scroll_vertical = int(bar.max_value))
	chat_edit = UiKit.text_field("", "", func(_t): pass, 300)
	chat_edit.max_length = 160
	chat_edit.text_submitted.connect(func(t: String):
		Net.say(t)
		chat_edit.text = "")
	left.add_child(chat_edit)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	main.add_child(right)
	right.add_child(UiKit.section("PLAYERS"))
	var pframe := PanelContainer.new()
	pframe.add_theme_stylebox_override("panel", UiKit.box(Color(0, 0, 0, 0.55), Color(1, 1, 1, 0.08), 1, 4, 10))
	pframe.custom_minimum_size.y = 8 * ROW_H + 7 * 4 + 20
	right.add_child(pframe)
	players_box = VBoxContainer.new()
	players_box.add_theme_constant_override("separation", 4)
	pframe.add_child(players_box)
	right.add_child(UiKit.section("RULES"))
	var rframe := PanelContainer.new()
	rframe.add_theme_stylebox_override("panel", UiKit.box(Color(0, 0, 0, 0.55), Color(1, 1, 1, 0.08), 1, 4, 12))
	rframe.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(rframe)
	# the rules scroll if the window is very short, so the buttons below always stay on screen; their
	# bar has a width here (UiKit's is 0 px wide: every other list scrolls by the pad or the wheel)
	rscroll = ScrollContainer.new()
	rscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rscroll.follow_focus = true
	var vbar := rscroll.get_v_scroll_bar()
	vbar.add_theme_stylebox_override("scroll", UiKit.box(Color(1, 1, 1, 0.05), Color(0, 0, 0, 0), 0, 3, 3))
	vbar.add_theme_stylebox_override("grabber", UiKit.box(Color(1, 1, 1, 0.25), Color(0, 0, 0, 0), 0, 3, 3))
	vbar.add_theme_stylebox_override("grabber_highlight", UiKit.box(UiKit.ORANGE, Color(0, 0, 0, 0), 0, 3, 3))
	vbar.add_theme_stylebox_override("grabber_pressed", UiKit.box(UiKit.ORANGE, Color(0, 0, 0, 0), 0, 3, 3))
	rframe.add_child(rscroll)
	rules_box = VBoxContainer.new()
	rules_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rules_box.add_theme_constant_override("separation", 4)
	rscroll.add_child(rules_box)
	# buttons
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 14)
	col.add_child(brow)
	leave_button = UiKit.button("STOP SERVER" if Net.is_server else "LEAVE", 200)
	leave_button.pressed.connect(_ask_leave)
	brow.add_child(leave_button)
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
	start_button.pressed.connect(func():
		# pressing START counts as the host's own READY; the reason shows when it cannot go
		if Net.can_start() != "":
			_update_status()
			return
		Net.start_race_now())
	start_button.visible = Net.is_server
	brow.add_child(start_button)
	var hints := PromptBar.new([["{ui_accept} SELECT"], ["{ui_cancel} %s" % ("STOP SERVER" if Net.is_server else "LEAVE")],
		["{pause} READY", "pad"], ["{chat} CHAT", "key"]])
	col.add_child(hints)
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
	Net.share.progress_changed.connect(_on_progress)
	Net.share.local_changed.connect(_on_local)
	Net.share.thumb_arrived.connect(_on_thumb)
	Game.custom_tracks_changed.connect(_on_customs_changed)
	_build_rules()
	_on_cfg()
	_rebuild_players()
	_send_profile()
	_add_chat("", "Welcome to %s. Pick a racer and a vehicle, then press READY." % Net.cfg.get("name", "the server"), "info")
	_update_chat_hint()
	InputPrompts.prompts_changed.connect(_update_chat_hint)
	_show_local()
	ready_button.grab_focus.call_deferred()


## The safety net (InputPrompts): READY.
func focus_default() -> bool:
	if not is_visible_in_tree():
		return false
	ready_button.grab_focus()
	return true


## Typing needs a keyboard: the chat field says so while a pad is in use.
func _update_chat_hint() -> void:
	chat_edit.placeholder_text = "Chat needs a keyboard" if InputPrompts.using_pad() else "Say something...  (Enter)"


## LEAVE / STOP SERVER and B: asked first, with CANCEL focused (B is a reflex on a pad, and the
## host's leaving ends the server for everyone).
func _ask_leave() -> void:
	if _confirm and is_instance_valid(_confirm):
		return
	if Net.is_server:
		_confirm = MessageBox.new("STOP SERVER", "Stop the server? Everyone in it is disconnected.", false, false, "STOP SERVER", "CANCEL")
	else:
		_confirm = MessageBox.new("LEAVE", "Leave the lobby?", false, false, "LEAVE", "CANCEL")
	_confirm.focus_cancel = true
	_confirm.answered.connect(func(ok: bool, _t: String):
		_confirm = null
		if ok:
			leave_requested.emit())
	add_child(_confirm)


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


func _process(delta: float) -> void:
	_tick -= delta
	if Net.autostart_left >= 0.0 or _tick <= 0.0:
		# (the server's own prepare and the ETA change without a roster message)
		_tick = 0.25
		_update_status()
		if dl_row.visible:
			_show_local()
	# the right stick scrolls the chat (nothing else in the lobby uses it)
	var pad := InputPrompts.active_pad()
	if pad >= 0 and InputPrompts.using_pad():
		var ry := Input.get_joy_axis(pad, JOY_AXIS_RIGHT_Y)
		if absf(ry) > 0.25:
			chat_scroll.scroll_vertical += int(ry * 700.0 * delta)


func _update_status() -> void:
	var blocker := track_line()
	if Net.state == "race_wait":
		status_label.text = "A race is in progress. You join the next one."
	elif Net.autostart_left >= 0.0:
		status_label.text = "Everyone is ready. Starting in %d..." % ceili(Net.autostart_left)
	elif blocker != "":
		# the track first: whoever does not have it yet (the host: with KICK on that row)
		status_label.text = blocker
	else:
		# a listen host's START RACE is its READY (Net.can_start never waits for it)
		var waiting := 0
		var host_row := false
		for p in Net.players.values():
			if bool(p.get("host", false)):
				host_row = true
			elif not p["ready"]:
				waiting += 1
		if waiting > 0:
			status_label.text = "Waiting for %d player%s to be ready" % [waiting, "" if waiting == 1 else "s"]
		elif Net.is_server and host_row:
			status_label.text = "Everyone is ready: press START RACE."
		elif host_row:
			status_label.text = "Waiting for the host to start the race."
		else:
			status_label.text = ""
	status_label.tooltip_text = status_label.text
	if start_button.visible:
		var why := Net.can_start()
		start_button.disabled = why != ""
		start_button.tooltip_text = why


## The status line's track part: the host's blocker line (TrackShare.status_line), for a friend
## the same without the host's choices.
func track_line() -> String:
	if not Net.active or Net.state != "lobby":
		return ""
	if Net.is_server:
		return Net.share.status_line()
	if Net.share.everyone_has_track():
		return ""
	var others := Net.share.waiting().filter(func(e: Dictionary) -> bool: return int(e["id"]) != Net.my_id())
	if others.is_empty():
		return ""
	return "Waiting for %d player%s to get the track." % [others.size(), "" if others.size() == 1 else "s"]


# ---------------------------------------------------------------- players
func _rebuild_players() -> void:
	# the host's focus on a KICK button stays on that player's row (the rows are rebuilt on every
	# ping change, every 2 s)
	var f := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var kick_id: int = f.get_meta("kick_id", -1) if f and players_box.is_ancestor_of(f) else -1
	for n in players_box.get_children():
		n.queue_free()
	var ids: Array = Net.players.keys()
	ids.sort()
	_track_cells.clear()
	for id in ids:
		players_box.add_child(_player_row(int(id), Net.players[id]))
	var cfg := Net.cfg
	var bots := 0
	if cfg.get("bots", false):
		bots = maxi(0, int(cfg.get("grid", 8)) - ids.size())
	for i in maxi(0, int(cfg.get("max_players", 8)) - ids.size()):
		var empty := UiKit.label("      open slot" if i >= bots else "      bot", 16, Color(1, 1, 1, 0.25))
		empty.custom_minimum_size.y = ROW_H
		players_box.add_child(empty)
	if kick_id >= 0:
		var again: Control = null
		for row in players_box.get_children():
			for c in row.get_children():
				if c is Button and int(c.get_meta("kick_id", -1)) == kick_id and not row.is_queued_for_deletion():
					again = c
		if again:
			again.grab_focus()
		else:
			ready_button.grab_focus()
	_update_status()


func _player_row(id: int, p: Dictionary) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	h.custom_minimum_size.y = ROW_H
	var pic := TextureRect.new()
	var path := "res://assets/ui/portraits/%s.png" % p["character"]
	pic.texture = load(path) if ResourceLoader.exists(path) else null
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.custom_minimum_size = Vector2(ROW_H, ROW_H)
	h.add_child(pic)
	var me := id == Net.my_id()
	var nick := UiKit.label(("★ " if p.get("host", false) else "") + str(p["nick"]), 19, Hl2Style.BRIGHT if me else Color.WHITE, true)
	nick.custom_minimum_size.x = 170
	nick.clip_text = true
	nick.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(nick)
	var what := UiKit.label("%s · %s" % [Game.character(p["character"]).get("short", p["character"]), Game.vehicle(p["vehicle"])["name"]], 14, UiKit.TEXT_DIM)
	what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	what.custom_minimum_size.x = 110
	what.clip_text = true
	what.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(what)
	# ping, READY, TRACK and KICK in fixed columns, so every row's cells line up (the texts are
	# clipped to them, never pushing the next cell over)
	var ping := UiKit.label("" if p.get("host", false) else "%d ms" % int(p.get("ping", 0)), 15, UiKit.TEXT_DIM)
	ping.custom_minimum_size.x = COL_PING
	ping.clip_text = true
	ping.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ping.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(ping)
	var rd := UiKit.label("READY" if p["ready"] else "", 15, Color(0.55, 0.95, 0.4), true)
	rd.custom_minimum_size.x = COL_READY
	rd.clip_text = true
	rd.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(rd)
	# TRACK: 42% / PREP / OK / NO TRACK (the reason as the tooltip), updated in place
	var tc := UiKit.label("", 15, UiKit.TEXT_DIM, true)
	tc.custom_minimum_size.x = COL_TRACK
	tc.clip_text = true
	tc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tc.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(tc)
	_track_cells[id] = tc
	fill_track_cell(tc, p)
	var missing := int(p.get("missing", 0))
	if missing > 0:
		h.tooltip_text = "%d objects of this track are not on %s's computer: they are left out there." % [missing, str(p["nick"])]
	if Net.is_server and id != 1:
		var kick := UiKit.button("KICK", COL_KICK)
		_low(kick, "Button", ROW_H)
		kick.set_meta("kick_id", id)
		kick.pressed.connect(func(): Net.kick(id))
		h.add_child(kick)
	elif Net.is_server:
		# the host's own row: an empty KICK column
		var gap := Control.new()
		gap.custom_minimum_size.x = COL_KICK
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(gap)
	return h


## A button of the lobby's tight rows: `h` px high, its theme's styles with less padding above and
## below the text (the text keeps its size).
static func _low(b: Control, type: String, h: int) -> void:
	b.custom_minimum_size.y = h
	var t := UiKit.theme()
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		# (a variation without its own style uses Button's)
		var from := type if t.has_stylebox(st, type) else "Button"
		if t.has_stylebox(st, from):
			var sb := t.get_stylebox(st, from).duplicate() as StyleBox
			sb.content_margin_top = 4
			sb.content_margin_bottom = 4
			b.add_theme_stylebox_override(st, sb)


# ---------------------------------------------------------------- rules
func _on_cfg() -> void:
	var cfg := Net.cfg
	title_label.text = str(cfg.get("name", "LOBBY"))
	var diff: String = Game.DIFFICULTIES[clampi(int(cfg.get("difficulty", 1)), 0, 2)]["name"]
	sub_label.text = "%s  ·  %d laps  ·  %s  ·  %s%s%s" % [_track_name(true), int(cfg.get("laps", 3)), diff,
		"bots fill the grid to %d" % int(cfg.get("grid", 8)) if cfg.get("bots", false) else "no bots",
		"  ·  hazards off" if int(cfg.get("hazards", 1)) == 0 else "",
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
	elif track_dd:
		CreateServer.select_track(track_dd, str(cfg.get("track", "")))
	_rebuild_players()
	_show_local()


func _build_rules() -> void:
	for n in rules_box.get_children():
		n.queue_free()
	var cfg := Net.cfg
	var host := Net.is_server
	var w := 210
	# the track first: the rule that decides whether a race can start (6.5)
	if host:
		# the circuits, then MY TRACKS and the kept downloads, selected by id (a custom pick is never
		# shown as Highway 17); a track this install has not built or that has errors is disabled
		track_dd = CreateServer.track_dropdown(str(cfg.get("track", "")), func(id: String): Net.set_rule("track", id))
		_low(track_dd, "OptionButton", RULE_H)
		rules_box.add_child(UiKit.row("Track", track_dd, w))
	else:
		# a friend sees the host's track by name (it may be one this computer does not have yet)
		track_dd = null
		var tl := UiKit.label(_track_name(), 18, UiKit.TEXT, true)
		tl.clip_text = true
		tl.custom_minimum_size = Vector2(260, RULE_H)
		tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tl.tooltip_text = _track_name()
		tl.mouse_filter = Control.MOUSE_FILTER_PASS
		rules_box.add_child(UiKit.row("Track", tl, w))
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
	var hazards := UiKit.segmented(["OFF", "ON"], int(cfg.get("hazards", 1)), func(i: int): Net.set_rule("hazards", i))
	rules_box.add_child(UiKit.row("Track hazards", hazards, w))
	for b in diff.get_children() + hazards.get_children():
		_low(b, "SegButton", RULE_H)
	if not host:
		# everyone sees the rules; only the host changes them (and the D-pad passes them by)
		for c in [mp, grid, laps]:
			var s := (c as HBoxContainer).get_child(0) as HSlider
			s.editable = false
			s.focus_mode = Control.FOCUS_NONE
		bots.disabled = true
		bots.focus_mode = Control.FOCUS_NONE
		for b in diff.get_children() + hazards.get_children():
			(b as Button).disabled = true
			(b as Button).focus_mode = Control.FOCUS_NONE


# ---------------------------------------------------------------- the track (6.5)
const NO_TRACK := Color(1, 0.45, 0.35)
const BLIP := "res://assets/sound/buttons/blip1.wav"


## A row's TRACK column: "42%" (orange), "PREP" (dim), "✓ OK" (dim), "NO TRACK" (red, the reason
## as the tooltip), "..." before the first report.
static func fill_track_cell(tc: Label, p: Dictionary) -> void:
	var st := str(p.get("track", "?"))
	var tip := ""
	var col := UiKit.TEXT_DIM
	match st:
		"get", "need":
			tc.text = "%d%%" % int(floorf(clampf(float(p.get("dl", 0.0)), 0.0, 1.0) * 100.0))
			col = UiKit.ORANGE
			tip = "Downloading the track"
		"prep":
			tc.text = "PREP"
			tip = "Preparing the track"
		"ok":
			tc.text = "✓ OK"
			tip = "Has the track"
		"fail":
			tc.text = "NO TRACK"
			col = NO_TRACK
			tip = "No track: %s" % TrackShare.words(str(p.get("why", "")))
		_:
			tc.text = "..."
			tip = "Checking the track"
	tc.add_theme_color_override("font_color", col)
	tc.tooltip_text = tip


## Under the sub line: this client's own download (thumb, line, bar), PREPARING TRACK..., or the
## reason with RETRY (DOWNLOAD when downloads are off).
func _build_download_row(parent: Control) -> void:
	dl_row = HBoxContainer.new()
	dl_row.add_theme_constant_override("separation", 12)
	dl_row.visible = false
	parent.add_child(dl_row)
	dl_thumb = TextureRect.new()
	dl_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	dl_thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	dl_thumb.custom_minimum_size = Vector2(72, 40)
	dl_thumb.visible = false
	dl_row.add_child(dl_thumb)
	# the line and the bar take the row's width; the name and size clip (the whole line is the
	# tooltip), the percent and the time left keep their own label at the bar's end
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dl_row.add_child(v)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	v.add_child(line)
	dl_label = UiKit.label("", 15, UiKit.ORANGE, true)
	dl_label.clip_text = true
	dl_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dl_label.custom_minimum_size.x = 160
	dl_label.mouse_filter = Control.MOUSE_FILTER_PASS
	line.add_child(dl_label)
	dl_pct = UiKit.label("", 15, UiKit.ORANGE, true)
	dl_pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	dl_pct.visible = false
	line.add_child(dl_pct)
	dl_bar = ProgressBar.new()
	dl_bar.show_percentage = false
	dl_bar.min_value = 0.0
	dl_bar.max_value = 1.0
	dl_bar.step = 0.0
	dl_bar.custom_minimum_size = Vector2(420, 8)
	dl_bar.add_theme_stylebox_override("background", UiKit.box(Color(1, 1, 1, 0.12), Color(0, 0, 0, 0), 0, 2, 0))
	dl_bar.add_theme_stylebox_override("fill", UiKit.box(UiKit.ORANGE, Color(0, 0, 0, 0), 0, 2, 0))
	v.add_child(dl_bar)
	retry_button = UiKit.button("RETRY", 130)
	retry_button.custom_minimum_size.y = 32
	retry_button.visible = false
	retry_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	retry_button.pressed.connect(_on_retry)
	dl_row.add_child(retry_button)


## The track's name for the rules and the sub line ("Canal Run by Sasha  ·  CUSTOM"): a custom
## track's name and author come from the server's cfg (the friend may not have it yet).
func _track_name(sub := false) -> String:
	var na := _name_author()
	if not CustomTracks.is_custom(str(Net.cfg.get("track", ""))):
		return na[0]
	var out: String = na[0] + ("  by %s" % na[1] if na[1] != "" else "")
	return out + "  ·  CUSTOM" if sub else out


## [name, author] of the server's track (a custom one's from the cfg).
func _name_author() -> Array:
	var id := str(Net.cfg.get("track", ""))
	var tr := Game.track(id)
	var nm := str(tr.get("name", id))
	var author := str(tr.get("author", "")) if CustomTracks.is_custom(id) else ""
	var c = Net.cfg.get("custom")
	if CustomTracks.is_custom(id) and c is Dictionary:
		if str(c.get("name", "")) != "":
			nm = str(c["name"])
		author = str(c.get("author", author))
	return [nm, author]


static func _size_text(bytes: int) -> String:
	if bytes < 100 * 1024:
		return "%d KB" % maxi(1, ceili(bytes / 1024.0))
	return "%.1f MB" % (bytes / 1048576.0)


## This client's own download from TrackShare.local_state(); also KEEP TRACK.
func _show_local() -> void:
	if dl_row == null:
		return
	var id := str(Net.cfg.get("track", ""))
	var custom := Net.active and not Net.is_server and CustomTracks.is_custom(id)
	var ls: Dictionary = Net.share.local_state() if custom else {}
	var st := str(ls.get("state", ""))
	var show := false
	var bar := false
	var retry := false
	var pct := ""
	# (what had the focus, before anything hides: RETRY or KEEP TRACK going away puts it on READY)
	var had_focus := _focus_inside(dl_row) or _focus_inside(keep_button)
	if id != _shown_id:
		# another track: the last one's thumbnail goes (thumb_arrived brings the new one)
		_shown_id = id
		dl_thumb.texture = null
	dl_label.add_theme_color_override("font_color", UiKit.ORANGE)
	if custom and (st == "need" or st == "get"):
		show = true
		_fetching = true
		var nm := str(ls.get("name", ""))
		if nm == "":
			nm = _track_name()
		var size := int(ls.get("size", 0))
		var eta := float(ls.get("eta_s", -1.0))
		dl_label.text = "DOWNLOADING %s  ·  %s" % [nm.to_upper(), _size_text(size)]
		pct = "%d%%%s" % [int(floorf(clampf(float(ls.get("dl", 0.0)), 0.0, 1.0) * 100.0)),
			"  ·  %d s LEFT" % ceili(eta) if eta >= 0.0 else ""]
		bar = true
		dl_bar.value = clampf(float(ls.get("dl", 0.0)), 0.0, 1.0)
	elif custom and st == "prep":
		show = true
		dl_label.text = "PREPARING TRACK..."
		bar = true
		dl_bar.value = 1.0
	elif custom and st == "fail":
		show = true
		var code := str(ls.get("code", ""))
		dl_label.add_theme_color_override("font_color", NO_TRACK)
		dl_label.text = str(ls.get("why", "")) if str(ls.get("why", "")) != "" else "No track."
		# past the RETRY limit (TrackShare.RETRY_MAX) the reason says to ask the host
		retry = code == "downloads off" or bool(ls.get("retry", true))
		retry_button.text = "DOWNLOAD" if code == "downloads off" else "RETRY"
		if code == "downloads off":
			_ask_download(ls)
	elif st == "ok" and _fetching:
		_fetching = false
		Game.play_ui(BLIP, -6.0)
	if not custom:
		_fetching = false
	dl_pct.text = pct
	dl_label.tooltip_text = dl_label.text + ("  ·  " + pct if pct != "" else "")
	# each visibility set once (hiding a focused RETRY on every refresh would drop the pad's focus)
	dl_pct.visible = pct != ""
	dl_bar.visible = bar
	retry_button.visible = retry
	dl_row.visible = show
	dl_thumb.visible = show and dl_thumb.texture != null
	keep_button.visible = custom and st == "ok" and str(CustomTracks.meta(id).get("kind", "")) == "cache"
	if had_focus and not _focus_inside(dl_row) and not _focus_inside(keep_button):
		ready_button.grab_focus.call_deferred()


func _focus_inside(c: Control) -> bool:
	if not is_inside_tree() or not c.is_visible_in_tree():
		return false
	var f := get_viewport().gui_get_focus_owner()
	return f != null and (f == c or c.is_ancestor_of(f))


## Downloads are off (OPTIONS > GAME): asked once per track on this server; DOWNLOAD gives the
## consent for this server for this session, LEAVE leaves.
func _ask_download(ls: Dictionary) -> void:
	var c = Net.cfg.get("custom")
	var sha := str(c.get("sha", "")) if c is Dictionary else ""
	if sha == _asked or (_ask_box and is_instance_valid(_ask_box)):
		return
	_asked = sha
	var size := int(ls.get("size", 0))
	var na := _name_author()
	_ask_box = MessageBox.new("DOWNLOAD IT?", "This server races %s%s, a custom track (%s). DOWNLOAD IT?" % [
		str(na[0]).to_upper(), " by %s" % na[1] if na[1] != "" else "", _size_text(size)], false, false, "DOWNLOAD", "LEAVE")
	_ask_box.answered.connect(func(ok: bool, _t: String):
		_ask_box = null
		if ok:
			Net.share.consent()
		else:
			leave_requested.emit())
	add_child(_ask_box)


func _on_retry() -> void:
	if retry_button.text == "DOWNLOAD":
		Net.share.consent()
	else:
		Net.share.retry()


func _keep_track() -> void:
	var id := str(Net.cfg.get("track", ""))
	if CustomTracks.keep(id) == OK:
		_add_chat("", "%s is kept: it stays under DOWNLOADED." % _track_name(), "info")
	else:
		_add_chat("", CustomTracks.last_error if CustomTracks.last_error != "" else "The track could not be kept.", "info")
	_show_local()


## A row's TRACK state or percent changed: that cell only (no rebuild, no focus loss).
func _on_progress(peer: int, _state: String, _dl: float) -> void:
	var tc: Label = _track_cells.get(peer)
	if tc and is_instance_valid(tc) and Net.players.has(peer):
		fill_track_cell(tc, Net.players[peer])
	_update_status()


func _on_local(_state: String, _dl: float, _reason: String) -> void:
	_show_local()
	_update_status()


func _on_thumb(tex: Texture2D) -> void:
	dl_thumb.texture = tex
	dl_thumb.visible = dl_row.visible and tex != null


func _on_customs_changed() -> void:
	if track_dd and is_instance_valid(track_dd):
		CreateServer.fill_tracks(track_dd, str(Net.cfg.get("track", "")))


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
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if chat_edit.has_focus():
			# in the chat field: B / Esc clears what was typed, then leaves the field
			if chat_edit.text != "":
				chat_edit.clear()
			else:
				chat_edit.unedit()
				ready_button.grab_focus()
			return
		_ask_leave()
	elif event is InputEventJoypadButton and event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		ready_button.button_pressed = not ready_button.button_pressed
	elif event.is_action_pressed("chat") and not chat_edit.has_focus():
		# Y / T: straight to the chat field, as in the race
		get_viewport().set_input_as_handled()
		chat_edit.grab_focus()
