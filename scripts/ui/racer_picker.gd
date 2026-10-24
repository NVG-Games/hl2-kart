class_name RacerPicker
extends VBoxContainer
## Portrait grid of the racers and a row of vehicle cards (NEW RACE, lobby).

signal racer_picked(index: int)
signal vehicle_picked(index: int)

var cards: Array[Button] = []
var vehicle_cards: Array[Button] = []


func select(racer: int, vehicle_index: int) -> void:
	cards[clampi(racer, 0, cards.size() - 1)].set_pressed_no_signal(true)
	vehicle_cards[clampi(vehicle_index, 0, vehicle_cards.size() - 1)].set_pressed_no_signal(true)


func _card_style(border: Color, width: int, bg: Color) -> StyleBoxFlat:
	return UiKit.box(bg, border, width, 4, 5)


func _card(text: String, icon: Texture2D, size: Vector2, group: ButtonGroup) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.button_group = group
	b.custom_minimum_size = size
	b.icon = icon
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.text = text
	b.clip_text = true
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_stylebox_override("normal", _card_style(Color(1, 1, 1, 0.12), 1, Color(0, 0, 0, 0.45)))
	b.add_theme_stylebox_override("hover", _card_style(Color.WHITE, 2, Color(1, 1, 1, 0.08)))
	b.add_theme_stylebox_override("pressed", _card_style(UiKit.ORANGE, 3, Color(UiKit.ORANGE.r, UiKit.ORANGE.g, UiKit.ORANGE.b, 0.16)))
	b.add_theme_stylebox_override("hover_pressed", _card_style(UiKit.ORANGE, 3, Color(UiKit.ORANGE.r, UiKit.ORANGE.g, UiKit.ORANGE.b, 0.22)))
	b.add_theme_stylebox_override("focus", _card_style(Color(1, 1, 1, 0.9), 1, Color(0, 0, 0, 0)))
	b.add_theme_color_override("font_pressed_color", UiKit.ORANGE)
	b.add_theme_color_override("font_hover_pressed_color", UiKit.ORANGE)
	b.focus_entered.connect(func(): Game.play_ui("res://assets/sound/ui/buttonrollover.wav", -9.0))
	b.mouse_entered.connect(b.grab_focus)
	return b


func _icon(path: String) -> Texture2D:
	return load(path) if ResourceLoader.exists(path) else null


func _init(card_h := 128) -> void:
	var v := self
	v.add_theme_constant_override("separation", 10)
	v.add_child(UiKit.section("CHOOSE YOUR RACER"))
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	v.add_child(grid)
	var group := ButtonGroup.new()
	for i in Game.CHARACTERS.size():
		var c: Dictionary = Game.CHARACTERS[i]
		var b := _card(c.get("short", c["name"]), _icon("res://assets/ui/portraits/%s.png" % c["id"]), Vector2(112, card_h), group)
		var idx := i
		b.pressed.connect(func(): racer_picked.emit(idx))
		grid.add_child(b)
		cards.append(b)
	var gap := Control.new()
	gap.custom_minimum_size.y = 4
	v.add_child(gap)
	v.add_child(UiKit.section("CHOOSE YOUR VEHICLE"))
	var row := GridContainer.new()
	row.columns = 6
	row.add_theme_constant_override("h_separation", 10)
	v.add_child(row)
	var vgroup := ButtonGroup.new()
	for i in Game.VEHICLES.size():
		var veh: Dictionary = Game.VEHICLES[i]
		var b := _card(veh["name"], _icon("res://assets/ui/vehicles/%s.png" % veh["id"]), Vector2(112, 96), vgroup)
		var idx := i
		b.pressed.connect(func(): vehicle_picked.emit(idx))
		row.add_child(b)
		vehicle_cards.append(b)
