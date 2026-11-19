class_name RaceSetup
extends Control
## NEW RACE screen: pick a racer and a vehicle (card grids + live 3D preview),
## then the race rules (difficulty, track hazards, laps, track) and start. One place, one START.
## With a pad: B goes back, Start starts the race, and the focused track card shows its
## description (or why it can not be picked) without picking it.

signal back
signal start

## short sample each vehicle makes when picked
const PREVIEW_SOUNDS := {
	"buggy": "vehicles/v8/v8_start_loop1.wav", "jalopy": "vehicles/junker/jnk_first.wav",
	"apc": "vehicles/apc/apc_start_loop3.wav", "btr": "vehicles/apc/apc_idle1.wav",
	"dog": "npc/dog/dog_playfull1.wav", "tub": "physics/metal/metal_barrel_impact_hard1.wav",
}
const TRACK_CARD := Vector2(140, 86)  # a track's picture card (two rows of them fit a 900-pixel-high window)
const TRACK_COLUMNS := 4  # the most track cards in a row

var showroom: Showroom
var name_label: Label
var vehicle_label: Label
var stats_box: GridContainer
var cards: Array[Button] = []
var vehicle_cards: Array[Button] = []
var start_button: Button
var back_button: Button
var laps_value: Label
var track_desc: Label
var track_cards: Array[Button] = []
var _racer := 0
var _vehicle := 0
var _preview: AudioStreamPlayer
var _preview_tween: Tween


func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group(InputPrompts.SCREEN_GROUP)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	_preview = AudioStreamPlayer.new()
	_preview.bus = "UI"
	add_child(_preview)
	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		root.add_theme_constant_override("margin_" + side, 56)
	root.add_theme_constant_override("margin_top", 32)
	root.add_theme_constant_override("margin_bottom", 30)
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
	_track_focus()
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
	picker.lock_edges()
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
	showroom = Showroom.new(Vector2i(560, 260))
	frame.add_child(showroom)
	# name, vehicle and stats on a dark plate: readable over the moving background
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", UiKit.box(Color(0, 0, 0, 0.62), Color(1, 1, 1, 0.08), 1, 4, 14))
	v.add_child(plate)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 6)
	plate.add_child(info)
	name_label = UiKit.label("", 30, Hl2Style.BRIGHT, true)
	info.add_child(name_label)
	vehicle_label = UiKit.label("", 15, UiKit.TEXT)
	vehicle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vehicle_label.custom_minimum_size.x = 300
	info.add_child(vehicle_label)
	stats_box = GridContainer.new()
	stats_box.columns = 2
	stats_box.add_theme_constant_override("h_separation", 28)
	stats_box.add_theme_constant_override("v_separation", 6)
	info.add_child(stats_box)
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
## Picture card (a track): thumbnail with a caption, orange when picked.
func _pic_card(tex: Texture2D, caption: String, size: Vector2, group: ButtonGroup) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.button_group = group
	b.custom_minimum_size = size
	var inner := VBoxContainer.new()
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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
	b.add_theme_stylebox_override("focus", RacerPicker.focus_style())
	b.add_theme_color_override("font_pressed_color", UiKit.ORANGE)
	UiKit.hover_focus(b)
	return b


func _rules_row() -> Control:
	var panel := PanelContainer.new()
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 28)
	panel.add_child(h)
	var d := VBoxContainer.new()
	d.add_theme_constant_override("separation", 8)
	d.custom_minimum_size.x = 270
	d.add_child(UiKit.section("DIFFICULTY"))
	var names: Array = []
	for x in Game.DIFFICULTIES:
		names.append(x["name"])
	d.add_child(UiKit.segmented(names, int(Game.settings["difficulty"]), func(i: int): Game.settings["difficulty"] = i))
	# turrets, trains, strikes and the like on the circuits (scripts/hazards)
	d.add_child(UiKit.section("TRACK HAZARDS"))
	d.add_child(UiKit.segmented(["OFF", "ON"], int(Game.settings.get("hazards", 1)), func(i: int): Game.settings["hazards"] = i))
	d.add_child(UiKit.section("LAPS"))
	d.add_child(UiKit.slider(1, 9, 1, int(Game.settings["laps"]), func(v: float): Game.settings["laps"] = int(v)))
	h.add_child(d)
	var t := VBoxContainer.new()
	t.add_theme_constant_override("separation", 8)
	t.add_child(UiKit.section("TRACK"))
	# the cards in two rows, as many columns as that takes (seven tracks: four over three) up to
	# TRACK_COLUMNS, so the description keeps its room beside them; past eight a third row starts
	var tracks := _tracks()
	var grid := GridContainer.new()
	grid.columns = clampi(ceili(tracks.size() / 2.0), 1, TRACK_COLUMNS)
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	t.add_child(grid)
	var group := ButtonGroup.new()
	# a track this install has not built yet (new content, setup not run again) can not be picked:
	# the race would build Highway 17 instead (Track.build). The pick falls back to the first one built
	var have := tracks.filter(func(tr: Dictionary) -> bool: return Game.track_installed(tr["id"]))
	if not have.is_empty() and not have.any(func(tr: Dictionary) -> bool: return tr["id"] == Game.settings.get("track", "")):
		Game.settings["track"] = have[0]["id"]
	for tr: Dictionary in tracks:
		var id: String = tr["id"]
		var b := _pic_card(Game.track_thumb(id), tr["short"], TRACK_CARD, group)
		b.name = "Track_" + id
		b.button_pressed = Game.settings.get("track", "") == id
		if not have.has(tr):
			b.disabled = true
			b.tooltip_text = "Not built on this computer yet: run the setup again to add it."
			b.modulate.a = 0.45
		b.pressed.connect(func():
			Game.settings["track"] = id
			_refresh_track()
			Game.play_ui("res://assets/sound/ui/buttonclick.wav", -8.0))
		# the focused card shows its track (a pad never sees the tooltip); the picked one's comes back
		b.focus_entered.connect(func(): track_desc.text = _desc_of(id))
		b.focus_exited.connect(_refresh_track)
		grid.add_child(b)
		track_cards.append(b)
	h.add_child(t)
	var w := VBoxContainer.new()
	w.add_theme_constant_override("separation", 8)
	w.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	w.add_child(UiKit.section("ABOUT THE TRACK"))
	track_desc = UiKit.label("", 14, UiKit.TEXT_DIM)
	track_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	track_desc.custom_minimum_size.x = 220
	w.add_child(track_desc)
	h.add_child(w)
	_refresh_track()
	return panel


## The arrows (keys, a gamepad) round the track cards: along a row and no further at its end (not
## off to a far button), and down off the grid to START RACE; from START RACE left to BACK (not up
## into the grid, which is nearer) and up to the picked track's card (_refresh_track).
func _track_focus() -> void:
	var cols := (track_cards[0].get_parent() as GridContainer).columns if not track_cards.is_empty() else 1
	for i in track_cards.size():
		var b := track_cards[i]
		if i % cols == cols - 1 or i == track_cards.size() - 1:
			b.focus_neighbor_right = NodePath(".")
		if i + cols >= track_cards.size():
			b.focus_neighbor_bottom = b.get_path_to(start_button)
	start_button.focus_neighbor_left = start_button.get_path_to(back_button)
	_refresh_track()


## The tracks on the picker: Game.TRACKS (the layout test hands it more, to see how many fit).
func _tracks() -> Array:
	return Game.TRACKS


## A track's description, or why it can not be picked.
func _desc_of(id: String) -> String:
	if not Game.track_installed(id):
		return "%s is not built on this computer yet: run the setup again to add it." % Game.track(id)["name"]
	return Game.track(id)["desc"]


## Description of the picked track; up from START RACE goes to its card.
func _refresh_track() -> void:
	var id := str(Game.settings.get("track", ""))
	track_desc.text = _desc_of(id)
	for b in track_cards:
		if start_button and b.name == "Track_" + id:
			start_button.focus_neighbor_top = start_button.get_path_to(b)


func _buttons_row() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	back_button = UiKit.button("BACK", 170)
	back_button.pressed.connect(func(): back.emit())
	h.add_child(back_button)
	var gap := Control.new()
	gap.custom_minimum_size.x = 14
	h.add_child(gap)
	var hints := PromptBar.new([["{ui_accept} SELECT"], ["{ui_cancel} BACK"], ["{pause} START RACE", "pad"]])
	hints.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hints.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(hints)
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


## START RACE takes the focus (also the safety net's, InputPrompts).
func focus_default() -> bool:
	if not is_visible_in_tree():
		return false
	start_button.grab_focus()
	return true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		back.emit()
	elif event is InputEventJoypadButton and event.is_action_pressed("pause"):
		# a pad's Start starts the race from anywhere on the screen (Esc and P stay BACK / nothing)
		get_viewport().set_input_as_handled()
		start.emit()
