class_name DriveCard
extends CanvasLayer
## HOW TO DRIVE: a small card with the main controls as icons for the device in use (the pad's own
## buttons, or the keys), from the race scene's first frame to GO: over the black loading card,
## through online's WAITING FOR PLAYERS, the fly-by and the countdown (skipping the intro keeps it:
## the countdown still shows it). Hidden while the pause menu is open (it has its own picture),
## redrawn when the device, the pad's family or a binding changes, faded out at GO (race.gd) or
## when OPTIONS > GAME > "Controls card before a race" is turned off. Not in attract mode, not on
## a dedicated server. Bottom right, clear of the SKIP prompt, the countdown, the minimap, MPH and
## (on a pad, the narrowest) the player's own kart.

const LAYER := 51  # over the loading card (50)
const ICON_PX := 28.0
const PANEL_ALPHA := 0.78  # (over the busy start grid: the karts' colours must not show through the words)
## The rows: [id, the actions whose bindings show (each one's first `n`), n, text].
const ROWS := [
	["accelerate", ["accelerate"], 2, "ACCELERATE"],
	["brake", ["brake"], 2, "BRAKE / REVERSE"],
	["steer", ["steer_left", "steer_right"], 1, "STEER"],
	["drift", ["drift"], 2, "HOP & DRIFT"],
	["use_item", ["use_item"], 2, "USE ITEM"],
	["look_back", ["look_back"], 1, "LOOK BEHIND"],
	["respawn", ["respawn"], 1, "CALL FOR HELP"],
]

var panel: PanelContainer
var race
## The rows: a grid of [icons, words] pairs, the icon column as wide as its widest set.
var _rows: GridContainer
var _shown: Array[String] = []
var _leaving := false
var _fade: Tween
var _pause_panel: Control  # the race's pause menu: the card hides while it shows


## The card belongs in this race: the setting is on, it is not attract mode or a dedicated server.
static func wanted(r) -> bool:
	return bool(Game.settings.get("controls_card", true)) and r.get("demo") != true and not Net.dedicated


func setup(r) -> void:
	race = r
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	panel = PanelContainer.new()
	var sb := Hl2Style.panel_style(Color(0, 0, 0, PANEL_ALPHA))
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		sb.set_content_margin(side, 14)
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_right = -310
	panel.offset_left = -310
	panel.offset_bottom = -158
	panel.offset_top = -158
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(v)
	v.add_child(Hl2Style.label("HOW TO DRIVE", 20, Hl2Style.BRIGHT))
	_rows = GridContainer.new()
	_rows.columns = 2
	_rows.add_theme_constant_override("h_separation", 14)
	_rows.add_theme_constant_override("v_separation", 6)
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_rows)
	refresh()
	if not InputPrompts.prompts_changed.is_connected(refresh):
		InputPrompts.prompts_changed.connect(refresh)
	if not Game.settings_changed.is_connected(_on_settings):
		Game.settings_changed.connect(_on_settings)
	# out of the pause menu's way while it is open (it has its own picture of the controls)
	var hud = race.get("hud") if race else null
	if hud is Hud and (hud as Hud).pause_panel:
		_pause_panel = (hud as Hud).pause_panel
		_pause_panel.visibility_changed.connect(_on_pause_shown)
		_on_pause_shown()
	panel.modulate.a = 0.0
	_fade = create_tween()
	_fade.tween_property(panel, "modulate:a", 1.0, 0.25)


func _exit_tree() -> void:
	if InputPrompts.prompts_changed.is_connected(refresh):
		InputPrompts.prompts_changed.disconnect(refresh)
	if Game.settings_changed.is_connected(_on_settings):
		Game.settings_changed.disconnect(_on_settings)
	if _pause_panel and is_instance_valid(_pause_panel) and _pause_panel.visibility_changed.is_connected(_on_pause_shown):
		_pause_panel.visibility_changed.disconnect(_on_pause_shown)


func _on_pause_shown() -> void:
	if panel and _pause_panel and is_instance_valid(_pause_panel):
		panel.visible = not _pause_panel.visible


## The setting turned off (OPTIONS from the pause menu): the card goes now, not at GO.
func _on_settings() -> void:
	if not bool(Game.settings.get("controls_card", true)):
		if race and is_instance_valid(race) and race.get("drive_card") == self:
			race.set("drive_card", null)
		leave()


## The rows again, for the device in use: its pad's buttons in its family's icons, or the keys.
## An action with nothing bound for that device is left out.
func refresh() -> void:
	if _rows == null:
		return
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	_shown.clear()
	var st := InputPrompts.style()
	var cls := InputBindings.KEY if st == InputPrompts.KEYBOARD else InputBindings.PAD
	for r in ROWS:
		var icons := HBoxContainer.new()
		icons.add_theme_constant_override("separation", 6)
		icons.alignment = BoxContainer.ALIGNMENT_END
		icons.custom_minimum_size.y = 30
		icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var n := 0
		if r[0] == "steer" and cls == InputBindings.PAD:
			n = _steer_pairs(icons, st)
		if n == 0:
			for spec in _specs(r, cls):
				_add_glyph(icons, spec, st)
				n += 1
		if n == 0:
			icons.free()
			continue
		_rows.add_child(icons)
		var text := Hl2Style.label(str(r[3]), 17, Hl2Style.FG_TEXT)
		text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		text.custom_minimum_size.y = 30
		if r[0] == "drift":
			# the note on its own line under the words (the card stays narrow, clear of the player's kart)
			var words := VBoxContainer.new()
			words.add_theme_constant_override("separation", -2)
			words.mouse_filter = Control.MOUSE_FILTER_IGNORE
			words.add_child(text)
			words.add_child(Hl2Style.label("HOLD, THEN STEER", 14, Hl2Style.FG_TEXT, false))
			_rows.add_child(words)
			icons.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		else:
			_rows.add_child(text)
		_shown.append(str(r[0]))


## A row's bindings for one class: each of its actions' first `n`.
static func _specs(r: Array, cls: String) -> PackedStringArray:
	var specs := PackedStringArray()
	for act in r[1]:
		var n := 0
		for spec in InputBindings.slots(act, cls):
			if spec != "" and n < int(r[2]):
				specs.append(spec)
				n += 1
	return specs


## STEER on a pad: one icon per slot whose left and right are one stick's or the D-pad's two ways
## (the left stick pushed sideways, not two left-stick icons that differ by a nub). Returns how many.
func _steer_pairs(into: HBoxContainer, st: String) -> int:
	var lefts := InputBindings.slots("steer_left", InputBindings.PAD)
	var rights := InputBindings.slots("steer_right", InputBindings.PAD)
	var n := 0
	for i in mini(lefts.size(), rights.size()):
		var stem := InputPrompts.pair_stem(str(lefts[i]), str(rights[i]), st)
		var tex := InputPrompts.icon(stem, ICON_PX) if stem != "" else null
		if tex == null:
			continue
		var t := TextureRect.new()
		t.texture = tex
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.custom_minimum_size = Vector2(ICON_PX, ICON_PX)
		t.modulate = Hl2Style.BRIGHT
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		into.add_child(t)
		n += 1
	return n


func _add_glyph(into: HBoxContainer, spec: String, st: String) -> void:
	var g := InputGlyph.new("", ICON_PX)
	g.style = st
	g.spec = spec
	g.modulate = Hl2Style.BRIGHT
	g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	into.add_child(g)


## The rows shown, by id ("steer" stands for both steering actions), for tests.
func shown_actions() -> Array[String]:
	return _shown.duplicate()


## GO: fades out, then goes.
func leave() -> void:
	if _leaving:
		return
	_leaving = true
	if panel == null:
		queue_free()
		return
	if _fade and _fade.is_valid():
		_fade.kill()
	var tw := create_tween()
	tw.tween_property(panel, "modulate:a", 0.0, 0.4)
	tw.tween_callback(queue_free)
