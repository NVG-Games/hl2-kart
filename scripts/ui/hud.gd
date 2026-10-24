class_name Hud
extends CanvasLayer
## Race HUD laid out like HL2's HudLayout.res (640x480 units scaled up):
## POSITION/LAP where HEALTH/SUIT sit, MPH where AMMO sits, AUX POWER bar
## for drift charge, weapon-selection box for the held item.

const U := Hl2Style.UNIT

var race
var root: Control
var pos_num: Label
var pos_of: Label
var lap_num: Label
var lap_of: Label
var speed_num: Label
var time_lbl: Label
var aux_bar: Array[ColorRect] = []
var aux_label: Label
var item_box: Panel
var item_name: Label
var item_view: SubViewport
var item_holder: Node3D
var item_tex: TextureRect
var big: Label
var big_t := 0.0
var rescue_hint: Label
var _rescue_t := 0.0
var standings: VBoxContainer
var minimap: Control
var pause_panel: Control
var results_panel: Control
var _shown_item := ""
var _roulette_t := 0.0
# online: chat feed (HL-style, bottom left) and the say line
var chat_feed: VBoxContainer
var chat_input: LineEdit
var _results_left := -1.0
var _results_note: Label


func setup(r) -> void:
	race = r
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_counters()
	_build_aux()
	_build_item()
	_build_time()
	_build_standings()
	_build_minimap()
	big = Hl2Style.number("", 120, Hl2Style.BRIGHT)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big.set_anchors_preset(Control.PRESET_CENTER)
	big.position = Vector2(-500, -220)
	big.size = Vector2(1000, 160)
	big.label_settings.font = Hl2Style.text_font(true)
	big.label_settings.font_size = 92
	root.add_child(big)
	rescue_hint = Hl2Style.label("STUCK?  PRESS  R  TO CALL A SCANNER", 13 * U, Hl2Style.BRIGHT)
	rescue_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rescue_hint.anchor_left = 0.5
	rescue_hint.anchor_right = 0.5
	rescue_hint.anchor_top = 1.0
	rescue_hint.anchor_bottom = 1.0
	rescue_hint.offset_left = -400
	rescue_hint.offset_right = 400
	rescue_hint.offset_top = -150
	rescue_hint.visible = false
	root.add_child(rescue_hint)
	_build_pause()
	if race.online:
		_build_chat()


func _box(x: float, y: float, w: float, h: float, anchor_right := false, anchor_bottom := true) -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", Hl2Style.panel_style())
	p.size = Vector2(w, h) * U
	var px := x * U
	var py := y * U
	if anchor_right:
		p.anchor_left = 1.0
		p.anchor_right = 1.0
		px = -px - w * U
	if anchor_bottom:
		p.anchor_top = 1.0
		p.anchor_bottom = 1.0
		py = -py - h * U
	p.offset_left = px
	p.offset_top = py
	p.offset_right = px + w * U
	p.offset_bottom = py + h * U
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(p)
	return p


func _counter(x: float, title: String, anchor_right := false) -> Array:
	var p := _box(x, 12, 118, 38, anchor_right)
	var t := Hl2Style.label(title, 8.5 * U)
	t.position = Vector2(8, 22) * U
	p.add_child(t)
	var n := Hl2Style.number("0", 30 * U)
	n.position = Vector2(54, -3) * U
	p.add_child(n)
	var of := Hl2Style.label("", 10 * U)
	of.position = Vector2(86, 16) * U
	p.add_child(of)
	return [n, of]


func _build_counters() -> void:
	var a := _counter(16, "POSITION")
	pos_num = a[0]
	pos_of = a[1]
	var b := _counter(146, "LAP")
	lap_num = b[0]
	lap_of = b[1]
	var c := _counter(16, "MPH", true)
	speed_num = c[0]
	(c[1] as Label).text = ""


func _build_aux() -> void:
	var p := _box(16, 56, 118, 26)
	aux_label = Hl2Style.label("AUX POWER", 7.5 * U)
	aux_label.position = Vector2(8, 3) * U
	p.add_child(aux_label)
	for i in 10:
		var r := ColorRect.new()
		r.color = Hl2Style.FG
		r.position = Vector2(8 + i * 10.2, 15) * U
		r.size = Vector2(7, 5) * U
		p.add_child(r)
		aux_bar.append(r)


func _build_item() -> void:
	item_box = Panel.new()
	item_box.add_theme_stylebox_override("panel", Hl2Style.panel_style())
	item_box.anchor_left = 0.5
	item_box.anchor_right = 0.5
	item_box.offset_left = -60 * U
	item_box.offset_right = 60 * U
	item_box.offset_top = 10 * U
	item_box.offset_bottom = 92 * U
	item_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(item_box)
	item_view = SubViewport.new()
	item_view.size = Vector2i(256, 256)
	item_view.transparent_bg = true
	item_view.own_world_3d = true
	item_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(item_view)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0.25, 2.2)
	cam.fov = 40.0
	item_view.add_child(cam)
	var l := DirectionalLight3D.new()
	l.rotation_degrees = Vector3(-35, 30, 0)
	l.light_energy = 1.6
	item_view.add_child(l)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.55, 0.6)
	env.environment = e
	item_view.add_child(env)
	item_holder = Node3D.new()
	item_view.add_child(item_holder)
	item_tex = TextureRect.new()
	item_tex.texture = item_view.get_texture()
	item_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	item_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	item_tex.position = Vector2(10, 2) * U
	item_tex.size = Vector2(100, 66) * U
	item_box.add_child(item_tex)
	item_name = Hl2Style.label("", 7.5 * U)
	item_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	item_name.position = Vector2(0, 68) * U
	item_name.size = Vector2(120, 12) * U
	item_box.add_child(item_name)


func _build_time() -> void:
	var p := _box(16, 10, 118, 26, true, false)
	var t := Hl2Style.label("TIME", 7.5 * U)
	t.position = Vector2(8, 8) * U
	p.add_child(t)
	time_lbl = Hl2Style.label("0:00.00", 12 * U)
	time_lbl.label_settings.font = Hl2Style.text_font(true)
	time_lbl.position = Vector2(40, 4) * U
	p.add_child(time_lbl)


func _build_standings() -> void:
	standings = VBoxContainer.new()
	standings.position = Vector2(16, 60) * U
	standings.add_theme_constant_override("separation", int(2 * U))
	root.add_child(standings)
	for i in 8:
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", Hl2Style.panel_style(Hl2Style.BG, 4))
		var l := Hl2Style.label("", 7.5 * U)
		l.custom_minimum_size = Vector2(108, 11) * U
		row.add_child(l)
		standings.add_child(row)


func _build_minimap() -> void:
	minimap = Minimap.new()
	minimap.race = race
	minimap.anchor_left = 1.0
	minimap.anchor_right = 1.0
	minimap.anchor_top = 0.5
	minimap.anchor_bottom = 0.5
	minimap.offset_left = -150 * U
	minimap.offset_right = -14 * U
	minimap.offset_top = -40 * U
	minimap.offset_bottom = 96 * U
	root.add_child(minimap)
	minimap.visible = Game.settings.get("show_minimap", true)


func _build_pause() -> void:
	# HL2 in-game menu: dimmed scene, logo-less title, the same flat menu entries
	pause_panel = Control.new()
	pause_panel.theme = UiKit.theme()
	pause_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_panel.visible = false
	root.add_child(pause_panel)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_panel.add_child(dim)
	var v := VBoxContainer.new()
	v.anchor_top = 1.0
	v.anchor_bottom = 1.0
	v.offset_left = 120
	v.offset_right = 700
	v.offset_top = -470
	v.offset_bottom = -110
	v.add_theme_constant_override("separation", 18)
	pause_panel.add_child(v)
	var title := UiKit.label("PAUSED", 42, Color.WHITE, true)
	v.add_child(title)
	var gap := Control.new()
	gap.custom_minimum_size.y = 10
	v.add_child(gap)
	var entries := [
		["RESUME RACE", _toggle_pause],
		["RESTART RACE", func(): race.restart()],
		["OPTIONS", _open_options],
		["QUIT TO MAIN MENU", func(): race.to_menu()],
	]
	if race.online:
		title.text = "MENU"
		entries = [["RESUME RACE", _toggle_pause], ["OPTIONS", _open_options]]
		if Net.is_server:
			entries.append(["RETURN EVERYONE TO LOBBY", func(): Net.back_to_lobby()])
		entries.append(["STOP SERVER" if Net.is_server else "DISCONNECT", func(): race.to_menu()])
	for e in entries:
		var b := UiKit.menu_item(e[0])
		b.pressed.connect(e[1])
		v.add_child(b)
	pause_panel.set_meta("first", v.get_child(2))


var _options: OptionsPanel


func _open_options() -> void:
	_options = OptionsPanel.new()
	pause_panel.add_child(_options)
	_options.closed.connect(func():
		_options = null
		minimap.visible = Game.settings.get("show_minimap", true)
		(pause_panel.get_meta("first") as Button).grab_focus())


func _toggle_pause() -> void:
	if race.online:
		# the race never stops online; the menu only takes the controls away
		var o := not pause_panel.visible
		pause_panel.visible = o
		race.input_blocked = o
		if o:
			(pause_panel.get_meta("first") as Button).grab_focus()
			Game.play_ui("res://assets/sound/ui/buttonclick.wav")
		elif _options and is_instance_valid(_options):
			_options.close()
		return
	var p := not get_tree().paused
	get_tree().paused = p
	pause_panel.visible = p
	if p:
		(pause_panel.get_meta("first") as Button).grab_focus()
		Game.play_ui("res://assets/sound/ui/buttonclick.wav")
	elif _options and is_instance_valid(_options):
		_options.close()


func _unhandled_input(event: InputEvent) -> void:
	if chat_input and event.is_action_pressed("chat") and not chat_input.visible and not pause_panel.visible:
		get_viewport().set_input_as_handled()
		_open_chat()
		return
	if event.is_action_pressed("pause") and results_panel == null and (_options == null or not is_instance_valid(_options)):
		get_viewport().set_input_as_handled()
		_toggle_pause()


func big_text(t: String, seconds: float) -> void:
	big.text = t
	big_t = seconds
	big.modulate.a = 1.0
	big.scale = Vector2.ONE


func _process(delta: float) -> void:
	if race == null or race.player == null:
		return
	var k: Kart = race.player
	var total: int = race.karts.size()
	pos_num.text = str(k.place)
	pos_of.text = "/%d" % total
	var lp := clampi(k.lap + 1, 1, race.laps)
	lap_num.text = str(lp)
	lap_of.text = "/%d" % race.laps
	speed_num.text = str(int(absf(k.fwd_speed) * 2.237))
	var t: float = race.race_time if race.racing or race._phase == "done" else 0.0
	if k.finished:
		t = k.finish_time
	time_lbl.text = "%d:%05.2f" % [int(t / 60.0), fmod(t, 60.0)]
	# AUX POWER: drift charge (blue -> orange) or remaining boost
	var fill := 0.0
	var col := Hl2Style.FG
	if k.drifting:
		fill = clampf(k.drift_charge / 2.2, 0.0, 1.0)
		col = Color8(255, 220, 0, 200) if k.drift_level == 0 else (Color8(90, 170, 255, 230) if k.drift_level == 1 else Color8(255, 130, 20, 240))
	elif k.boost_time > 0.0:
		fill = clampf(k.boost_time / 1.5, 0.0, 1.0)
		col = Color8(255, 130, 20, 230)
	elif k.star_time > 0.0:
		fill = clampf(k.star_time / 7.0, 0.0, 1.0)
		col = Hl2Style.BRIGHT
	for i in aux_bar.size():
		aux_bar[i].color = col if float(i) / aux_bar.size() < fill else Color(col.r, col.g, col.b, 0.12)
	aux_label.text = "AUX POWER" if not k.drifting else ("DRIFT" if k.drift_level == 0 else ("MINI-TURBO" if k.drift_level == 1 else "SUPER TURBO"))
	_update_item(k, delta)
	# offer the scanner rescue when the player is slow off the tarmac or wedged
	var struggling: bool = race.racing and k.state == Kart.State.NORMAL and 		((k.offroad and k.speed < 9.0) or (k.speed < 2.0 and k.in_throttle > 0.5))
	_rescue_t = _rescue_t + delta if struggling else 0.0
	rescue_hint.visible = _rescue_t > 2.0
	if rescue_hint.visible:
		rescue_hint.modulate.a = 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.008)
	_update_standings()
	if big_t > 0.0:
		big_t -= delta
		big.modulate.a = clampf(big_t * 2.0, 0.0, 1.0)
		if big_t <= 0.0:
			big.text = ""
	if item_holder.get_child_count() > 0:
		(item_holder.get_child(0) as Node3D).rotation.y += delta * 1.5


func _update_item(k: Kart, delta: float) -> void:
	var shown := k.item
	if k.roulette > 0.0:
		item_box.visible = true
		_roulette_t -= delta
		if _roulette_t <= 0.0:
			_roulette_t = 0.09
			shown = Items.INFO.keys()[randi() % Items.INFO.size()]
			if k.is_player:
				Game.play_ui("res://assets/sound/buttons/blip1.wav", -14.0)
			_set_item_model(shown)
		return
	if shown != _shown_item:
		_set_item_model(shown)
		if shown != "" and k.is_player:
			Game.play_ui("res://assets/sound/items/ammo_pickup.wav", -6.0)
	var count_txt := ""
	if k.item_count > 1:
		count_txt = "  x%d" % k.item_count
	item_name.text = (Items.INFO[shown]["name"] + count_txt) if shown != "" else ""
	item_box.visible = shown != ""


func _set_item_model(id: String) -> void:
	_shown_item = id
	for c in item_holder.get_children():
		c.queue_free()
	if id == "":
		return
	var key: String = Items.INFO[id]["model"]
	var m := Game.spawn_model(key)
	var aabb := Game.model_aabb(key)
	var s := 1.3 / maxf(aabb.size.length(), 0.01)
	m.scale = Vector3.ONE * s
	m.position = -aabb.get_center() * s
	var pivot := Node3D.new()
	pivot.add_child(m)
	item_holder.add_child(pivot)


func _update_standings() -> void:
	var sorted: Array = race.karts.duplicate()
	sorted.sort_custom(func(a, b): return a.place < b.place)
	for i in mini(sorted.size(), standings.get_child_count()):
		var k: Kart = sorted[i]
		var row := standings.get_child(i) as PanelContainer
		var l := row.get_child(0) as Label
		row.visible = true
		var who: String = k.nick if race.online and k.nick != "" else k.char_data.get("name", k.character_id)
		l.text = " %d  %s" % [k.place, who]
		var me: bool = k == race.player
		l.label_settings.font_color = Hl2Style.BRIGHT if me else Color(1, 1, 1, 0.75)
		row.get_theme_stylebox("panel").bg_color = Hl2Style.BG
	for i in range(sorted.size(), standings.get_child_count()):
		standings.get_child(i).visible = false


func show_results(karts: Array) -> void:
	results_panel = Panel.new()
	results_panel.theme = UiKit.theme()
	results_panel.add_theme_stylebox_override("panel", Hl2Style.panel_style(Color(0, 0, 0, 0.55), 0))
	results_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(results_panel)
	var box := Panel.new()
	box.add_theme_stylebox_override("panel", Hl2Style.panel_style(Color(0, 0, 0, 0.6), 10))
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.offset_left = -420
	box.offset_right = 420
	box.offset_top = -330
	box.offset_bottom = 330
	results_panel.add_child(box)
	var v := VBoxContainer.new()
	v.position = Vector2(40, 30)
	v.size = Vector2(760, 600)
	v.add_theme_constant_override("separation", 6)
	box.add_child(v)
	v.add_child(Hl2Style.label("RACE RESULTS", 34, Hl2Style.BRIGHT))
	var sorted := karts.duplicate()
	sorted.sort_custom(func(a, b): return a.place < b.place)
	var pts := [15, 12, 10, 8, 6, 4, 2, 1]
	for k in sorted:
		var row := HBoxContainer.new()
		var me: bool = k == race.player
		var c := Hl2Style.BRIGHT if me else Color(1, 1, 1, 0.85)
		var a := Hl2Style.label("%d." % k.place, 24, c)
		a.custom_minimum_size.x = 60
		row.add_child(a)
		var b := Hl2Style.label(k.char_data.get("name", ""), 24, c)
		b.custom_minimum_size.x = 380
		row.add_child(b)
		var tt: String = "%d:%05.2f" % [int(k.finish_time / 60.0), fmod(k.finish_time, 60.0)] if k.finished else "--:--.--"
		var d := Hl2Style.label(tt, 24, c)
		d.custom_minimum_size.x = 200
		row.add_child(d)
		row.add_child(Hl2Style.label("+%d" % pts[k.place - 1], 24, c))
		v.add_child(row)
	var sp := Control.new()
	sp.custom_minimum_size.y = 30
	v.add_child(sp)
	var again := UiKit.menu_item("RACE AGAIN")
	again.pressed.connect(func(): race.restart())
	v.add_child(again)
	var menu := UiKit.menu_item("MAIN MENU")
	menu.pressed.connect(func(): race.to_menu())
	v.add_child(menu)
	again.grab_focus()


# ---------------------------------------------------------------- online
func _build_chat() -> void:
	chat_feed = VBoxContainer.new()
	chat_feed.anchor_top = 1.0
	chat_feed.anchor_bottom = 1.0
	chat_feed.offset_left = 16 * U
	chat_feed.offset_right = 16 * U + 760
	chat_feed.offset_top = -(92 * U) - 200
	chat_feed.offset_bottom = -(92 * U) - 34
	chat_feed.alignment = BoxContainer.ALIGNMENT_END
	chat_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(chat_feed)
	chat_input = LineEdit.new()
	chat_input.theme = UiKit.theme()
	chat_input.anchor_top = 1.0
	chat_input.anchor_bottom = 1.0
	chat_input.offset_left = 16 * U
	chat_input.offset_right = 16 * U + 600
	chat_input.offset_top = -(92 * U) - 30
	chat_input.offset_bottom = -(92 * U)
	chat_input.placeholder_text = "Say: (Enter to send, Esc to cancel)"
	chat_input.max_length = 160
	chat_input.visible = false
	chat_input.add_theme_stylebox_override("normal", UiKit.box(Color(0, 0, 0, 0.7), Hl2Style.BRIGHT, 1, 2, 8))
	chat_input.add_theme_stylebox_override("focus", UiKit.box(Color(0, 0, 0, 0.7), Hl2Style.BRIGHT, 1, 2, 8))
	chat_input.text_submitted.connect(func(t: String):
		Net.say(t)
		_close_chat())
	chat_input.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
			chat_input.accept_event()
			_close_chat())
	root.add_child(chat_input)
	Net.chat_received.connect(add_chat)


func _open_chat() -> void:
	chat_input.text = ""
	chat_input.visible = true
	chat_input.grab_focus()
	race.input_blocked = true


func _close_chat() -> void:
	chat_input.visible = false
	chat_input.release_focus()
	race.input_blocked = pause_panel.visible


func add_chat(nick: String, text: String, kind: String) -> void:
	if chat_feed == null:
		return
	var l := Label.new()
	l.theme = UiKit.theme()
	l.add_theme_font_size_override("font_size", 19)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	if kind == "info" or nick == "":
		l.text = text
		l.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	else:
		l.text = "%s: %s" % [nick, text]
		l.add_theme_color_override("font_color", Hl2Style.BRIGHT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	chat_feed.add_child(l)
	while chat_feed.get_child_count() > 6:
		chat_feed.get_child(0).free()
	Game.play_ui("res://assets/sound/friends/message.wav", -12.0)
	var tw := l.create_tween()
	tw.tween_interval(9.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.0)
	tw.tween_callback(l.queue_free)


## Results from the server (players by nickname, bots marked), then the lobby.
func show_net_results(order: Array, seconds: float) -> void:
	if results_panel:
		results_panel.queue_free()
	if pause_panel.visible:
		_toggle_pause()
	results_panel = Panel.new()
	results_panel.theme = UiKit.theme()
	results_panel.add_theme_stylebox_override("panel", Hl2Style.panel_style(Color(0, 0, 0, 0.55), 0))
	results_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	results_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(results_panel)
	var box := Panel.new()
	box.add_theme_stylebox_override("panel", Hl2Style.panel_style(Color(0, 0, 0, 0.6), 10))
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.offset_left = -470
	box.offset_right = 470
	box.offset_top = -330
	box.offset_bottom = 330
	results_panel.add_child(box)
	var v := VBoxContainer.new()
	v.position = Vector2(40, 30)
	v.size = Vector2(860, 600)
	v.add_theme_constant_override("separation", 6)
	box.add_child(v)
	v.add_child(Hl2Style.label("RACE RESULTS", 34, Hl2Style.BRIGHT))
	var pts := [15, 12, 10, 8, 6, 4, 2, 1]
	for i in order.size():
		var e: Dictionary = order[i]
		var me: bool = race.player and int(e["slot"]) == race.player.net_slot and race.player.is_player
		var c := Hl2Style.BRIGHT if me else Color(1, 1, 1, 0.85)
		var row := HBoxContainer.new()
		var a := Hl2Style.label("%d." % (i + 1), 24, c)
		a.custom_minimum_size.x = 60
		row.add_child(a)
		var who := Hl2Style.label(str(e["nick"]) + ("  BOT" if e["bot"] else ""), 24, c)
		who.custom_minimum_size.x = 420
		who.clip_text = true
		row.add_child(who)
		var t: float = e["time"]
		var d := Hl2Style.label("%d:%05.2f" % [int(t / 60.0), fmod(t, 60.0)] if t >= 0.0 else "--:--.--", 24, c)
		d.custom_minimum_size.x = 200
		row.add_child(d)
		row.add_child(Hl2Style.label("+%d" % pts[mini(i, pts.size() - 1)], 24, c))
		v.add_child(row)
	var sp := Control.new()
	sp.custom_minimum_size.y = 24
	v.add_child(sp)
	_results_note = Hl2Style.label("", 20, Color(1, 1, 1, 0.7))
	v.add_child(_results_note)
	_results_left = seconds


func _notification(what: int) -> void:
	if what == NOTIFICATION_INTERNAL_PROCESS:
		pass


func _physics_process(delta: float) -> void:
	if _results_left > 0.0 and _results_note:
		_results_left -= delta
		_results_note.text = "Back to the lobby in %d..." % ceili(maxf(_results_left, 0.0))
