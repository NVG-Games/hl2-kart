class_name RaceSetup
extends Control
## NEW RACE screen: pick a racer and a vehicle (card grids + live 3D preview),
## then the race rules (difficulty, laps, track, weather) and start. One place, one START.

signal back
signal start

## short sample each vehicle makes when picked
const PREVIEW_SOUNDS := {
	"buggy": "vehicles/v8/v8_start_loop1.wav", "jalopy": "vehicles/junker/jnk_first.wav",
	"apc": "vehicles/apc/apc_start_loop3.wav", "btr": "vehicles/apc/apc_idle1.wav",
	"dog": "npc/dog/dog_playfull1.wav", "tub": "physics/metal/metal_barrel_impact_hard1.wav",
}

var showroom: Showroom
var name_label: Label
var vehicle_label: Label
var stats_box: GridContainer
var cards: Array[Button] = []
var vehicle_cards: Array[Button] = []
var start_button: Button
var laps_value: Label
var track_desc: Label
var weather: OptionButton
var _racer := 0
var _vehicle := 0
var _preview: AudioStreamPlayer
var _preview_tween: Tween


func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	_preview = AudioStreamPlayer.new()
	_preview.bus = "UI"
	add_child(_preview)
	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		root.add_theme_constant_override("margin_" + side, 70)
	root.add_theme_constant_override("margin_top", 40)
	root.add_theme_constant_override("margin_bottom", 36)
	add_child(root)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	root.add_child(col)
	col.add_child(UiKit.label("NEW RACE", 34, Color.WHITE, true))
	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 30)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(main)
	main.add_child(_picker_column())
	main.add_child(_preview_column())
	col.add_child(_rules_row())
	col.add_child(_buttons_row())
	_racer = _index_of(Game.CHARACTERS, Game.settings["character"])
	_vehicle = _index_of(Game.VEHICLES, Game.settings.get("vehicle", "buggy"))
	cards[_racer].button_pressed = true
	vehicle_cards[_vehicle].button_pressed = true
	_refresh()


func _index_of(list: Array, id: String) -> int:
	for i in list.size():
		if list[i]["id"] == id:
			return i
	return 0


# ---------------------------------------------------------------- racers & vehicles
func _card_style(border: Color, width: int, bg: Color) -> StyleBoxFlat:
	var sb := UiKit.box(bg, border, width, 4, 5)
	return sb


func _picker_column() -> Control:
	var picker := RacerPicker.new()
	picker.racer_picked.connect(_pick_racer)
	picker.vehicle_picked.connect(_pick_vehicle)
	cards = picker.cards
	vehicle_cards = picker.vehicle_cards
	return picker


func _preview_column() -> Control:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UiKit.box(Color(0, 0, 0, 0.35), Color(1, 1, 1, 0.08), 1, 4, 0))
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(frame)
	showroom = Showroom.new(Vector2i(700, 300))
	frame.add_child(showroom)
	name_label = UiKit.label("", 30, Hl2Style.BRIGHT, true)
	v.add_child(name_label)
	vehicle_label = UiKit.label("", 15, UiKit.TEXT_DIM)
	vehicle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vehicle_label.custom_minimum_size.x = 600
	v.add_child(vehicle_label)
	stats_box = GridContainer.new()
	stats_box.columns = 2
	stats_box.add_theme_constant_override("h_separation", 28)
	stats_box.add_theme_constant_override("v_separation", 6)
	v.add_child(stats_box)
	return v


func _stat_bar(title: String, value: float) -> HBoxContainer:
	# HL2 AUX POWER-style segmented bar
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	var l := UiKit.label(title, 14, UiKit.TEXT_DIM, true)
	l.custom_minimum_size.x = 128
	h.add_child(l)
	var n := clampi(int(round(value * 10.0)), 1, 10)
	for i in 10:
		var seg := ColorRect.new()
		seg.custom_minimum_size = Vector2(16, 10)
		seg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		seg.color = Hl2Style.BRIGHT if i < n else Color(1, 1, 1, 0.1)
		h.add_child(seg)
	return h


func _pick_racer(i: int) -> void:
	_racer = i
	cards[i].set_pressed_no_signal(true)
	_refresh()
	var line := Game.voice_line(Game.CHARACTERS[i]["id"], "start")
	if line != "":
		Game.play_ui(line, -3.0)


func _pick_vehicle(i: int) -> void:
	_vehicle = i
	vehicle_cards[i].set_pressed_no_signal(true)
	_refresh()
	# a couple of seconds of the engine (or Dog's chirp), faded out
	if _preview_tween:
		_preview_tween.kill()
	_preview.stream = Game.stream(PREVIEW_SOUNDS.get(Game.VEHICLES[i]["id"], ""))
	_preview.volume_db = -4.0
	_preview.play()
	_preview_tween = create_tween()
	_preview_tween.tween_interval(1.6)
	_preview_tween.tween_property(_preview, "volume_db", -60.0, 0.8)
	_preview_tween.tween_callback(_preview.stop)


## Shows the racer + vehicle pair; stats are the two multiplied together, as in the race.
func _refresh() -> void:
	var c: Dictionary = Game.CHARACTERS[_racer]
	var veh: Dictionary = Game.VEHICLES[_vehicle]
	Game.settings["character"] = c["id"]
	Game.settings["vehicle"] = veh["id"]
	name_label.text = c["name"]
	vehicle_label.text = "%s  —  %s" % [String(veh["name"]).to_upper(), veh["desc"]]
	for n in stats_box.get_children():
		n.queue_free()
	stats_box.add_child(_stat_bar("SPEED", (float(c["speed"]) * float(veh["speed"]) - 0.9) / 0.2))
	stats_box.add_child(_stat_bar("ACCELERATION", (float(c["accel"]) * float(veh["accel"]) - 0.8) / 0.42))
	stats_box.add_child(_stat_bar("WEIGHT", (float(c["weight"]) * float(veh["weight"]) - 0.5) / 1.4))
	stats_box.add_child(_stat_bar("HANDLING", (float(veh["handling"]) - 0.8) / 0.4))
	showroom.show_character(c, _racer, veh["id"])


# ---------------------------------------------------------------- rules
## Picture card (track or weather): thumbnail with a caption, orange when picked.
func _pic_card(tex: Texture2D, caption: String, size: Vector2, group: ButtonGroup) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.button_group = group
	b.custom_minimum_size = size
	var inner := VBoxContainer.new()
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.offset_left = 6
	inner.offset_right = -6
	inner.offset_top = 6
	inner.offset_bottom = -4
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if tex:
		var pic := TextureRect.new()
		pic.texture = tex
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pic.size_flags_vertical = Control.SIZE_EXPAND_FILL
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(pic)
	else:
		var gap := Control.new()
		gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(gap)
	var cap := UiKit.label(caption, 10, UiKit.TEXT, true)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.clip_text = true
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(cap)
	b.add_child(inner)
	b.add_theme_stylebox_override("normal", _card_style(Color(1, 1, 1, 0.12), 1, Color(0, 0, 0, 0.45)))
	b.add_theme_stylebox_override("hover", _card_style(Color.WHITE, 2, Color(1, 1, 1, 0.08)))
	b.add_theme_stylebox_override("pressed", _card_style(UiKit.ORANGE, 3, Color(0, 0, 0, 0.4)))
	b.add_theme_stylebox_override("hover_pressed", _card_style(UiKit.ORANGE, 3, Color(0, 0, 0, 0.4)))
	b.add_theme_stylebox_override("focus", _card_style(Color(1, 1, 1, 0.9), 1, Color(0, 0, 0, 0)))
	b.add_theme_color_override("font_pressed_color", UiKit.ORANGE)
	b.mouse_entered.connect(b.grab_focus)
	return b


func _rules_row() -> Control:
	var panel := PanelContainer.new()
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 34)
	panel.add_child(h)
	var d := VBoxContainer.new()
	d.add_theme_constant_override("separation", 8)
	d.custom_minimum_size.x = 290
	d.add_child(UiKit.section("DIFFICULTY"))
	var names: Array = []
	for x in Game.DIFFICULTIES:
		names.append(x["name"])
	d.add_child(UiKit.segmented(names, int(Game.settings["difficulty"]), func(i: int): Game.settings["difficulty"] = i))
	d.add_child(UiKit.section("LAPS"))
	d.add_child(UiKit.slider(1, 9, 1, int(Game.settings["laps"]), func(v: float): Game.settings["laps"] = int(v)))
	h.add_child(d)
	var t := VBoxContainer.new()
	t.add_theme_constant_override("separation", 8)
	t.add_child(UiKit.section("TRACK"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	t.add_child(row)
	var group := ButtonGroup.new()
	for tr in Game.TRACKS:
		var id: String = tr["id"]
		var b := _pic_card(Game.track_thumb(id), tr["short"], Vector2(150, 100), group)
		b.button_pressed = Game.settings.get("track", "") == id
		b.pressed.connect(func():
			Game.settings["track"] = id
			_refresh_track()
			Game.play_ui("res://assets/sound/ui/buttonclick.wav", -8.0))
		row.add_child(b)
	h.add_child(t)
	var w := VBoxContainer.new()
	w.add_theme_constant_override("separation", 8)
	w.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	w.add_child(UiKit.section("WEATHER"))
	weather = UiKit.dropdown(Game.sky_names(), Game.sky_index(str(Game.settings.get("sky", ""))),
		func(i: int): Game.settings["sky"] = Game.SKIES[i][0])
	w.add_child(weather)
	track_desc = UiKit.label("", 14, UiKit.TEXT_DIM)
	track_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	track_desc.custom_minimum_size.x = 260
	w.add_child(track_desc)
	h.add_child(w)
	_refresh_track()
	return panel


## Description of the picked track; only Highway 17 takes a weather (the maps keep their own sky).
func _refresh_track() -> void:
	var tr := Game.track(str(Game.settings.get("track", "")))
	track_desc.text = tr["desc"]
	weather.disabled = not tr.get("weather", false)
	weather.tooltip_text = "" if tr.get("weather", false) else "This map keeps its own sky"


func _buttons_row() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	var b := UiKit.button("BACK", 170)
	b.pressed.connect(func(): back.emit())
	h.add_child(b)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)
	start_button = UiKit.button("START RACE", 280)
	start_button.custom_minimum_size.y = 54
	start_button.add_theme_font_size_override("font_size", 22)
	start_button.add_theme_stylebox_override("normal", UiKit.box(Color(UiKit.ORANGE.r, UiKit.ORANGE.g, UiKit.ORANGE.b, 0.85), UiKit.ORANGE, 1, 3, 18))
	start_button.add_theme_stylebox_override("hover", UiKit.box(UiKit.ORANGE.lightened(0.2), Color.WHITE, 2, 3, 18))
	start_button.add_theme_stylebox_override("focus", UiKit.box(Color(0, 0, 0, 0), Color.WHITE, 2, 3, 18))
	start_button.add_theme_color_override("font_color", Color.BLACK)
	start_button.add_theme_color_override("font_hover_color", Color.BLACK)
	start_button.add_theme_color_override("font_focus_color", Color.BLACK)
	start_button.pressed.connect(func(): start.emit())
	h.add_child(start_button)
	return h


func focus_default() -> void:
	start_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		back.emit()
