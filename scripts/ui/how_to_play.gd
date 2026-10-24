class_name HowToPlay
extends Dialog
## HOW TO PLAY: four short illustrated pages (controls, driving & drifting,
## items, the track). Tabs, PREV / NEXT, or left/right on a gamepad.

const ITEM_TEXT := {
	"battery": "Turbo boost from your HEV suit. Use it on straights or to cut across grass.",
	"battery3": "Three boosts in a row. Press once per boost.",
	"manhack": "Flies along the track and hunts the racer directly ahead of you.",
	"manhack3": "Three manhacks: fire them one after another.",
	"rollermine": "Rolls straight ahead, bounces off walls and shocks the first kart it touches. Hold BRAKE to roll it backwards.",
	"barrel": "Dropped behind you. Whoever drives into it gets blown into the air.",
	"gravgun": "Punts every kart and prop in a cone in front of you.",
	"canister": "A Combine shell aimed at the race leader. Watch the blue beam and swerve.",
	"hev": "Seven seconds of overcharge: faster, invulnerable, and anyone you touch goes flying.",
}

var tabs: TabBar
var pages: Array[Control] = []
var prev_b: Button
var next_b: Button
var _aux: Array[ColorRect] = []
var _t := 0.0


func _init() -> void:
	super("HOW TO PLAY", Vector2(1180, 760))


func _ready() -> void:
	tabs = TabBar.new()
	for t in ["CONTROLS", "DRIVING", "ITEMS", "THE TRACK", "ONLINE"]:
		tabs.add_tab(t)
	tabs.focus_mode = Control.FOCUS_ALL
	body.add_child(tabs)
	var holder := MarginContainer.new()
	holder.add_theme_constant_override("margin_top", 10)
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(holder)
	pages = [_controls(), _driving(), _items(), _track(), _online()]
	for p in pages:
		holder.add_child(p)
	tabs.tab_changed.connect(_show)
	prev_b = add_button("PREV", func(): tabs.current_tab = maxi(tabs.current_tab - 1, 0))
	next_b = add_button("NEXT", func(): tabs.current_tab = mini(tabs.current_tab + 1, pages.size() - 1))
	add_button("CLOSE", close)
	_show(0)
	next_b.grab_focus.call_deferred()


func _show(i: int) -> void:
	for k in pages.size():
		pages[k].visible = k == i
	prev_b.disabled = i == 0
	next_b.disabled = i == pages.size() - 1
	Game.play_ui("res://assets/sound/ui/buttonclick.wav", -10.0)


# ---------------------------------------------------------------- pages
func _controls() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 60)
	var rows := [
		["Accelerate", ["W", "↑"], ["A", "RT"]],
		["Brake / reverse", ["S", "↓"], ["X", "LT"]],
		["Steer", ["A", "D"], ["Left stick"]],
		["Hop & drift", ["SHIFT", "SPACE"], ["RB"]],
		["Use item", ["E", "CTRL"], ["LB", "B"]],
		["Look behind", ["C"], ["Y"]],
		["Call a scanner (stuck)", ["R"], ["BACK"]],
		["Pause", ["ESC"], ["START"]],
	]
	for col in [["KEYBOARD", 1], ["GAMEPAD", 2]]:
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 14)
		v.add_child(UiKit.section(col[0]))
		for r in rows:
			var line := HBoxContainer.new()
			line.add_theme_constant_override("separation", 8)
			var l := UiKit.label(r[0], 18, UiKit.TEXT)
			l.custom_minimum_size.x = 250
			line.add_child(l)
			for k in r[col[1]]:
				line.add_child(UiKit.keycap(k, k.length() > 2))
			v.add_child(line)
		h.add_child(v)
	return h


func _para(text: String, size := 18) -> Label:
	var l := UiKit.label(text, size, UiKit.TEXT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 1080
	return l


func _step(n: int, title: String, text: String) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	var num := UiKit.label(str(n), 34, Hl2Style.BRIGHT, true)
	num.custom_minimum_size.x = 40
	h.add_child(num)
	var v := VBoxContainer.new()
	v.add_child(UiKit.label(title, 20, Color.WHITE, true))
	var t := UiKit.label(text, 17, UiKit.TEXT_DIM)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size.x = 980
	v.add_child(t)
	h.add_child(v)
	return h


func _driving() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	v.add_child(_step(1, "Rocket start", "Hold ACCELERATE when Overwatch says \"one\". Too early and you just roll off; on time you launch with a turbo."))
	v.add_child(_step(2, "Hop into a drift", "In a corner, press and hold HOP & DRIFT while steering. Your vehicle hops and slides; keep steering into the turn."))
	var demo := HBoxContainer.new()
	demo.add_theme_constant_override("separation", 14)
	var spacer := Control.new()
	spacer.custom_minimum_size.x = 56
	demo.add_child(spacer)
	var aux := PanelContainer.new()
	aux.add_theme_stylebox_override("panel", Hl2Style.panel_style())
	var av := VBoxContainer.new()
	av.add_child(UiKit.label("AUX POWER", 13, Hl2Style.FG_TEXT, true))
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 5)
	for i in 10:
		var seg := ColorRect.new()
		seg.custom_minimum_size = Vector2(16, 9)
		bar.add_child(seg)
		_aux.append(seg)
	av.add_child(bar)
	aux.add_child(av)
	demo.add_child(aux)
	var legend := UiKit.label("Sparks and the AUX POWER bar show the charge:  yellow → BLUE (mini-turbo) → ORANGE (super turbo).", 17, UiKit.TEXT)
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	legend.custom_minimum_size.x = 720
	demo.add_child(legend)
	v.add_child(demo)
	v.add_child(_step(3, "Release for the turbo", "Let go of HOP & DRIFT to fire the turbo. The longer the drift, the stronger it is."))
	v.add_child(_step(4, "Stay on the tarmac", "Grass, dirt and verges slow you down. Yellow chevron pads on the road give a free boost."))
	return v


func _items() -> Control:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 14)
	for id in ["battery", "manhack", "rollermine", "barrel", "gravgun", "canister", "hev", "battery3", "manhack3"]:
		var card := HBoxContainer.new()
		card.add_theme_constant_override("separation", 10)
		card.custom_minimum_size = Vector2(360, 120)
		var icon := TextureRect.new()
		icon.texture = load("res://assets/ui/items/%s.png" % id)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(96, 96)
		card.add_child(icon)
		var v := VBoxContainer.new()
		v.add_child(UiKit.label(Items.INFO[id]["name"], 16, Hl2Style.BRIGHT, true))
		var t := UiKit.label(ITEM_TEXT[id], 14, UiKit.TEXT_DIM)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.custom_minimum_size.x = 250
		v.add_child(t)
		card.add_child(v)
		grid.add_child(card)
	return grid


func _track_card(icon_path: String, title: String, text: String) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	var icon := TextureRect.new()
	if icon_path != "":
		icon.texture = load(icon_path)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(100, 100)
	h.add_child(icon)
	var v := VBoxContainer.new()
	v.add_child(UiKit.label(title, 20, Color.WHITE, true))
	var t := UiKit.label(text, 17, UiKit.TEXT_DIM)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size.x = 900
	v.add_child(t)
	h.add_child(v)
	return h


func _track() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 20)
	v.add_child(_track_card("res://assets/ui/items/crate.png", "Supply crates",
		"Drive through a row of HL2 supply crates to get a random item. The further back you are, the stronger the items."))
	v.add_child(_track_card("res://assets/ui/items/scanner.png", "Fell off or stuck?",
		"Drop into the sea or get wedged and a Combine scanner lifts you back onto the road. Press R to call it yourself."))
	v.add_child(_track_card("res://assets/ui/portraits/breen.png", "Five tracks",
		"Highway 17 starts under Dr. Breen's broadcast, leaves City 17 through the Combine checkpoint, jumps the inlet on the coast road and comes back down the canal. CT17, Xen, Black Mesa and Surface Tension are the real Half-Life maps, lighting and all."))
	v.add_child(_track_card("res://assets/ui/items/barrel.png", "Physics everywhere",
		"Cones, drums, crates and melons are real props: knock them over. Red barrels explode."))
	return v


func _online() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	v.add_child(_step(1, "Host", "CREATE SERVER: name it, set max players, laps, track and weather. Bots can fill the empty grid slots or stay off for a pure 1 on 1. You race too."))
	v.add_child(_step(2, "Join", "FIND SERVERS: friends on your network see you under LAN. Over the internet they type your address into Connect to address (open UDP 27015-27016 on the router; UPnP tries it for you)."))
	v.add_child(_step(3, "Lobby", "Everyone picks a racer and a vehicle and presses READY: the race starts 5 seconds after the last one. The host can also START RACE at once, change the rules and KICK."))
	v.add_child(_step(4, "Racing online", "The race never pauses. Press Y to chat. If someone leaves, a bot takes over their kart. Results go to everyone, then back to the lobby."))
	return v


func _process(delta: float) -> void:
	_t += delta
	if _aux.is_empty():
		return
	var cyc := fmod(_t, 4.0) / 4.0
	var fill := clampf(cyc * 1.25, 0.0, 1.0)
	var col := Color8(255, 220, 0, 200) if cyc < 0.35 else (Color8(90, 170, 255) if cyc < 0.7 else Color8(255, 130, 20))
	for i in _aux.size():
		_aux[i].color = col if float(i) / _aux.size() < fill else Color(col.r, col.g, col.b, 0.15)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_page_down") or (event is InputEventJoypadButton and event.is_action_pressed("ui_right") and tabs.has_focus()):
		tabs.current_tab = mini(tabs.current_tab + 1, pages.size() - 1)
	else:
		super(event)
