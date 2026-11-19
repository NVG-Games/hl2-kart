class_name HowToPlay
extends Dialog
## HOW TO PLAY: short illustrated pages (controls, driving & drifting, items, the track,
## shortcuts, hazards, online). Tabs, PREV / NEXT, LB / RB or Page Up / Page Down. Every control
## the pages name shows as the player's own binding, in icons of the device in use (PromptLabel);
## the CONTROLS page lists the bindings for the keyboard and for the pad's family.

const ITEM_TEXT := {
	"battery": "Turbo boost from your HEV suit. Use it on straights or to cut across grass.",
	"battery3": "Three boosts in a row. Press {use_item} once per boost.",
	"manhack": "Flies along the track and hunts the racer directly ahead of you.",
	"manhack3": "Three manhacks: fire them one after another.",
	"rollermine": "Rolls straight ahead, bounces off walls and shocks the first kart it touches. Hold {brake} to roll it backwards.",
	"barrel": "Dropped behind you. Whoever drives into it gets blown into the air.",
	"gravgun": "Its beam grabs the nearest kart ahead, lifts it and pulls it back over your head: it drops behind you and spins out.",
	"supergrav": "The Citadel's supercharged gravity gun. Blasts every kart in front of you high into the air, sets off barrels and bursts watermelons.",
	"canister": "A Combine shell aimed at the race leader. Watch the blue beam and swerve.",
	"hev": "Seven seconds of overcharge: faster, invulnerable, and anyone you touch goes flying.",
	"cball": "The AR2's energy ball. Skims along the road, ricochets off walls and flattens the first kart it touches. Careful: it can come back for you.",
	"melon": "Drop it behind you. Whoever drives over it slips and spins.",
	"melon3": "Three watermelons: drop them one after another.",
	"hopper": "Dropped behind you, it arms in a second, then jumps at the first kart that comes close and goes off.",
	"saw": "Ravenholm's sawblade, flung straight ahead. It cuts through every kart in the way and sticks in the first wall.",
	"headcrab": "Headcrabs leap onto the faces of up to three racers just ahead of you. For a couple of seconds they can't see a thing.",
	"xenport": "A Xen portal: you come out 140 metres further down the road, at full speed.",
}
const COUNTS := ["No", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten"]
## CONTROLS page rows: the actions (InputBindings, titled as in OPTIONS' binding tabs), then the
## menus' confirm, which skips the intro
const CONTROL_ROWS: Array[String] = ["accelerate", "brake", "steer_left", "steer_right", "drift", "use_item",
	"look_back", "respawn", "pause", "chat", "ui_accept"]
const ROW_TITLES := {"ui_accept": "Skip the intro"}

var pages: Array[Control] = []
var prev_b: Button
var next_b: Button
var close_b: Button
var _controls_box: VBoxContainer
var _aux: Array[ColorRect] = []
var _t := 0.0


func _init() -> void:
	# (wide enough for all eight tabs with the LB / RB glyphs beside them, keycaps included)
	super("HOW TO PLAY", Vector2(1200, 760))


func _ready() -> void:
	tabs = TabBar.new()
	for t in ["CONTROLS", "DRIVING", "ITEMS", "MORE ITEMS", "THE TRACK", "SHORTCUTS", "HAZARDS", "ONLINE"]:
		tabs.add_tab(t)
	tabs.focus_mode = Control.FOCUS_ALL
	body.add_child(tabs)
	var holder := MarginContainer.new()
	holder.add_theme_constant_override("margin_top", 10)
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(holder)
	pages = [_controls(), _driving(), _items(["battery", "manhack", "rollermine", "barrel", "gravgun", "canister", "hev",
		"battery3", "manhack3"]), _items(["cball", "saw", "headcrab", "melon", "hopper", "xenport", "melon3", "supergrav"]),
		_track(), _shortcuts(), _hazards(), _online()]
	for p in pages:
		holder.add_child(p)
	tabs.tab_changed.connect(_show)
	prev_b = add_button("PREV", func(): tabs.current_tab = maxi(tabs.current_tab - 1, 0))
	next_b = add_button("NEXT", func(): tabs.current_tab = mini(tabs.current_tab + 1, pages.size() - 1))
	close_b = add_button("CLOSE", close)
	default_focus = next_b
	_show(0)
	next_b.grab_focus.call_deferred()
	# the CONTROLS page follows the bindings and the pad's family
	InputPrompts.prompts_changed.connect(_fill_controls)


func _show(i: int) -> void:
	var f := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	for k in pages.size():
		pages[k].visible = k == i
	prev_b.disabled = i == 0
	next_b.disabled = i == pages.size() - 1
	# a dead PREV / NEXT is skipped by the D-pad, and its focus moves on to the next button
	for b in [prev_b, next_b]:
		b.focus_mode = Control.FOCUS_NONE if b.disabled else Control.FOCUS_ALL
	default_focus = close_b if next_b.disabled else next_b
	if f == next_b and next_b.disabled:
		close_b.grab_focus()
	elif f == prev_b and prev_b.disabled:
		next_b.grab_focus()
	Game.play_ui("res://assets/sound/ui/buttonclick.wav", -10.0)


# ---------------------------------------------------------------- pages
func _controls() -> Control:
	_controls_box = VBoxContainer.new()
	_controls_box.add_theme_constant_override("separation", 18)
	_fill_controls()
	return _controls_box


## The bindings as they are now: the keyboard's and the pad's per action, the pad's in its
## family's icons ("GAMEPAD · PLAYSTATION 5"; an unknown pad: "GAMEPAD").
func _fill_controls() -> void:
	for c in _controls_box.get_children():
		c.free()
	var ps := InputPrompts.pad_style()
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 48)
	grid.add_theme_constant_override("v_separation", 7)
	grid.add_child(Control.new())
	grid.add_child(UiKit.section("KEYBOARD AND MOUSE"))
	grid.add_child(UiKit.section("GAMEPAD" if InputPrompts.family(ps) == "generic"
		else "GAMEPAD  ·  " + str(InputPrompts.STYLE_NAMES.get(ps, "Xbox")).to_upper()))
	for act in CONTROL_ROWS:
		var l := UiKit.label(ROW_TITLES.get(act, InputBindings.TITLES.get(act, act)), 18, UiKit.TEXT)
		l.custom_minimum_size = Vector2(300, 32)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		grid.add_child(l)
		grid.add_child(_glyphs(_specs(act, false), InputPrompts.KEYBOARD))
		if act in InputBindings.KEYBOARD_ONLY:
			var only := UiKit.label("keyboard only", 16, UiKit.TEXT_DIM)
			only.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			grid.add_child(only)
		else:
			grid.add_child(_glyphs(_specs(act, true), ps))
	_controls_box.add_child(grid)
	_controls_box.add_child(UiKit.prompt("Change any of them in OPTIONS > KEYBOARD & MOUSE and CONTROLLER. In the menus {ui_accept} picks, "
		+ "{ui_cancel} goes back and {ui_tab_prev} {ui_tab_next} switch tabs.", 16, UiKit.TEXT_DIM, false, 1080))


## An action's bound specs for the keyboard and mouse or for a pad, in slot order (a ui_* action:
## its first two InputMap events, leaving out the keypad's Enter beside Enter).
static func _specs(act: String, pad: bool) -> Array:
	if act in InputBindings.ACTIONS:
		return InputBindings.slots(act, InputBindings.PAD if pad else InputBindings.KEY).filter(func(x): return x != "")
	var out := []
	for ev in InputPrompts.action_events(act, pad):
		var sp := InputBindings.spec_of(ev)
		if sp != "" and not sp in out and out.size() < 2 and sp != InputBindings.key_spec(KEY_KP_ENTER):
			out.append(sp)
	return out


func _glyphs(specs: Array, style_id: String) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	for sp in specs:
		var g := InputGlyph.new("", 32.0)
		g.style = style_id
		g.spec = sp
		if g.texture:
			h.add_child(g)
		else:
			h.add_child(UiKit.keycap(g.text(), g.text().length() > 2))
			g.free()
	if specs.is_empty():
		h.add_child(UiKit.label("—", 18, UiKit.TEXT_DIM))
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
	v.add_child(UiKit.prompt(text, 17, UiKit.TEXT_DIM, false, 980))
	h.add_child(v)
	return h


func _driving() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	v.add_child(_step(1, "Rocket start", "Hold {accelerate} when Overwatch says \"one\". Too early and you just roll off; on time you launch with a turbo."))
	v.add_child(_step(2, "Hop into a drift", "In a corner, press and hold {drift} while steering. Your vehicle hops and slides; keep steering into the turn."))
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
	v.add_child(_step(3, "Release for the turbo", "Let go of {drift} to fire the turbo. The longer the drift, the stronger it is."))
	v.add_child(_step(4, "Stay on the tarmac", "Grass, dirt and verges slow you down. Yellow chevron pads on the road give a free boost."))
	return v


func _items(ids: Array) -> Control:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 14)
	for id in ids:
		var card := HBoxContainer.new()
		card.add_theme_constant_override("separation", 10)
		card.custom_minimum_size = Vector2(360, 120)
		var icon := TextureRect.new()
		icon.texture = Items.icon(id)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(96, 96)
		card.add_child(icon)
		var v := VBoxContainer.new()
		var title := UiKit.label(Items.INFO[id]["name"], 16, Hl2Style.BRIGHT, true)
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # (a long name would widen the page)
		title.custom_minimum_size.x = 250
		v.add_child(title)
		v.add_child(UiKit.prompt(ITEM_TEXT[id], 14, UiKit.TEXT_DIM, false, 250))
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
	v.add_child(UiKit.prompt(text, 17, UiKit.TEXT_DIM, false, 900))
	h.add_child(v)
	return h


func _track() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)  # (five cards: 20 ran past the frame)
	v.add_child(_track_card("res://assets/ui/items/crate.png", "Supply crates",
		"Drive through a row of HL2 supply crates to get a random item. The further back you are, the stronger the items."))
	# every track the game has (Game.TRACKS), by name
	var names: Array = Game.TRACKS.map(func(tr: Dictionary) -> String: return tr["name"])
	var count: String = COUNTS[names.size()] if names.size() < COUNTS.size() else str(names.size())
	v.add_child(_track_card("res://assets/ui/portraits/breen.png", count + " tracks",
		"%s and %s: Half-Life's places rebuilt from the games' own textures, models, signs and music." % [
			", ".join(PackedStringArray(names.slice(0, -1))), names[-1]]))
	v.add_child(_track_card("res://assets/ui/portraits/police.png", "Spectators",
		"Citizens, metrocops, scientists, marines and vortigaunts cheer, flinch at explosions and hop out of your way. Some know your racer; the G-Man may be watching. OPTIONS > VIDEO > Spectators."))
	v.add_child(_track_card("res://assets/ui/items/barrel.png", "Physics everywhere",
		"Cones, drums, crates and melons are real props: knock them over. Red barrels explode, and some lie right on the road."))
	v.add_child(_track_card("res://assets/ui/items/xenport.png", "A tube and open edges",
		"In Highway 17's tunnel through the headland you stick to the wall: the road rolls up the side and over the ceiling. Some bridges and cliff roads have no railings: run wide and you fall."))
	return v


func _shortcuts() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 20)
	v.add_child(_track_card("res://assets/ui/vehicles/buggy.png", "Two shortcuts on every track",
		"Chevron boards stand before each fork, the HUD names the shortcut the first time you come up to it, and the minimap draws shortcuts as dashes. The results count the ones you got through."))
	v.add_child(_track_card("res://assets/ui/items/battery.png", "Jumps take speed",
		"Most shortcuts end in a jump: come at it flat out. Some have a boost pad on the run-up. A DANGER sign stands before the risky ones. Land it and you get SHORTCUT!"))
	v.add_child(_track_card("res://assets/ui/items/scanner.png", "Fell off or stuck?",
		"Sink, fall off or get stuck and help comes: the scanner's photo in CT17, a teleport at Black Mesa and Surface Tension, a portal on Xen, the rebels' crane on Highway 17, a Combine teleport at Nova Prospekt, the vortigaunts' green energy in White Forest. In its flash you're back on the road. Drop through a hole in Nova Prospekt's floor (or get shoved in by the guard) and you are in the antlion caves: drive out. Miss a shortcut's jump and you retry from its run-up if it can be made. {respawn} calls it."))
	v.add_child(_track_card("res://assets/ui/vehicles/jalopy.png", "Wrong way",
		"Drive back along the road and a red WRONG WAY flashes under the item box, with a beep, until you turn round."))
	return v


func _hazards() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 20)
	v.add_child(_track_card("res://assets/ui/items/hopper.png", "Track hazards",
		"Every track has its own: turrets, a Combine train and a freight train at level crossings, a Combine column on a bridge, striders, a gunship, antlions, an antlion guard, a magnet crane, laser tripmines, the Lambda core's discharges, houndeyes, alien slaves, controllers, bullsquids, a tentacle, an Apache, mortars. Each one warns before it strikes: a bell, a horn, a beam, a charge, a rumble in the sand, red marks where the shots land."))
	v.add_child(_track_card("res://assets/ui/items/manhack.png", "Locked on",
		"A red chevron at the edge of the screen points at whatever has locked on you (a turret, an alien slave, a strider, the crane, the column...), beeping faster as the shot nears. Hold your line and it hits: brake, boost or change lane."))
	v.add_child(_track_card("res://assets/ui/items/hev.png", "One hit per gauntlet",
		"Once a hazard has hit you, the others in its group leave you alone until you are through. On EASY they warn longer and fire less often."))
	v.add_child(_track_card("res://assets/ui/items/gravgun.png", "On the minimap, or off",
		"The minimap marks each hazard with a small triangle that blinks red while it fires. Set TRACK HAZARDS to OFF in NEW RACE to race without them. Online the host decides for everyone, in CREATE SERVER or in the lobby."))
	return v


func _online() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	v.add_child(_step(1, "Host", "CREATE SERVER: name it, set max players, laps, track and track hazards (your choice counts for everyone). Bots can fill the empty grid slots or stay off for a pure 1 on 1. You race too."))
	v.add_child(_step(2, "Join", "FIND SERVERS: friends on your network see you under LAN. Over the internet they type your address into Connect to address (open UDP 27015-27016 on the router; UPnP tries it for you)."))
	v.add_child(_step(3, "Same version", "Everyone needs the same version of the game. A server running another version shows as (different version) in the list and can't be joined."))
	v.add_child(_step(4, "Lobby", "Everyone picks a racer and a vehicle and presses READY: the race starts 5 seconds after the last one. The host can also START RACE at once, change the rules and KICK."))
	v.add_child(_step(5, "Racing online", "The race never pauses. Press {chat} on the keyboard to chat. The server waits up to 45 seconds for a slow PC to load, then starts; a late player joins the race under way. If someone leaves, a bot takes over their kart. Results go to everyone, then back to the lobby."))
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

