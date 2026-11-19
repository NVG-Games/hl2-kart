class_name OptionsPanel
extends Dialog
## OPTIONS: Audio / Video / Game / Controls tabs. Every change applies immediately (the menus'
## confirm / back swap once CONTROLS is left).

const CONTROLS_TAB := 3

var pages: Array[Control] = []
var controls: ControlsPage
var _hint: PromptLabel  # CONTROLS: what a slot waits for, or what a change did (instead of the hints)


func _init() -> void:
	super("OPTIONS", Vector2(1000, 640))


func _ready() -> void:
	tabs = TabBar.new()
	for t in ["AUDIO", "VIDEO", "GAME", "CONTROLS"]:
		tabs.add_tab(t)
	tabs.focus_mode = Control.FOCUS_ALL
	body.add_child(tabs)
	var holder := MarginContainer.new()
	holder.add_theme_constant_override("margin_top", 12)
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(holder)
	controls = ControlsPage.new(self)
	controls.hint_changed.connect(_on_hint)
	pages = [_audio(), _video(), _game(), controls]
	for p in pages:
		holder.add_child(p)
	_hint = UiKit.prompt("", 15, UiKit.ORANGE, true)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_hint.visible = false
	buttons.add_child(_hint)
	buttons.move_child(_hint, prompt_bar.get_index() + 1)
	tabs.tab_changed.connect(_show_tab)
	add_button("DONE", close).custom_minimum_size.x = 170
	_show_tab(0)
	tabs.grab_focus.call_deferred()
	tree_exiting.connect(func(): InputPrompts.hold_swap(false))


func _show_tab(i: int) -> void:
	for k in pages.size():
		pages[k].visible = k == i
	# on CONTROLS the menus' confirm / back stay as they were: turning the Nintendo swap on there
	# would make the next press of the same button go back; they change over on another tab
	InputPrompts.hold_swap(i == CONTROLS_TAB)
	if i == CONTROLS_TAB:
		set_prompts([["{ui_accept} CHANGE"], ["{ui_clear} CLEAR"], ["{ui_cancel} BACK"]])
	else:
		set_prompts([["{ui_accept} SELECT"], ["{ui_cancel} BACK"]])
		_on_hint("", "", UiKit.ORANGE)
	Game.play_ui("res://assets/sound/ui/buttonclick.wav", -10.0)


## CONTROLS: a line in place of the button hints ("" puts the hints back).
func _on_hint(text: String, style: String, color: Color) -> void:
	_hint.style = style
	_hint.add_theme_color_override("default_color", color)
	_hint.prompt = text
	_hint.visible = text != ""
	prompt_bar.visible = text == ""


func _page() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 22)
	return v


func _apply(key: String, value) -> void:
	Game.settings[key] = value
	Game.apply_settings()


func _volume(title: String, key: String) -> HBoxContainer:
	var s := UiKit.slider(0, 100, 5, roundf(float(Game.settings[key]) * 100.0), func(v: float): _apply(key, v / 100.0), "%d%%")
	return UiKit.row(title, s)


func _audio() -> Control:
	var v := _page()
	v.add_child(_volume("Master volume", "master_volume"))
	v.add_child(_volume("Music", "music_volume"))
	v.add_child(_volume("Sound effects", "sfx_volume"))
	v.add_child(_volume("Voices", "voice_volume"))
	return v


func _video() -> Control:
	var v := _page()
	v.add_child(UiKit.row("Display mode", UiKit.dropdown(["Windowed", "Fullscreen"], 1 if Game.settings["fullscreen"] else 0,
		func(i: int): _apply("fullscreen", i == 1))))
	var vs := UiKit.toggle(Game.settings["vsync"], func(on: bool): _apply("vsync", on))
	v.add_child(UiKit.row("Vertical sync", vs))
	var q := UiKit.segmented(["LOW", "MEDIUM", "HIGH"], int(Game.settings["quality"]), func(i: int): _apply("quality", i))
	v.add_child(UiKit.row("Graphics quality", q))
	var c := UiKit.segmented(["OFF", "FEW", "FULL"], int(Game.settings.get("crowds", 2)), func(i: int): _apply("crowds", i))
	v.add_child(UiKit.row("Spectators", c))
	var note := UiKit.label("HIGH adds real-time bounce lighting (SDFGI) and screen-space reflections.\nLOW also turns off ambient occlusion and bloom and shortens shadow distance.\nSpectators change from the next race on.", 15, UiKit.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(note)
	return v


func _music_choices() -> Array:
	var names := ["Random"]
	for m in Game.music_library:
		names.append("%s  ·  %s" % [m["album"], m["title"]])
	return names


func _music_index(id: String) -> int:
	for i in Game.music_library.size():
		if Game.music_library[i]["id"] == id:
			return i + 1
	return 0


func _music_row(title: String, key: String) -> HBoxContainer:
	var dd := UiKit.dropdown(_music_choices(), _music_index(str(Game.settings[key])), func(i: int):
		_apply(key, "random" if i == 0 else String(Game.music_library[i - 1]["id"])))
	return UiKit.row(title, dd)


func _game() -> Control:
	var v := _page()
	var nick := UiKit.text_field(Game.nickname(), "Player", func(t: String): Game.settings["nickname"] = t.strip_edges())
	nick.max_length = 24
	v.add_child(UiKit.row("Multiplayer name", nick))
	v.add_child(_music_row("Race music", "race_music"))
	v.add_child(_music_row("Menu music", "menu_music"))
	v.add_child(UiKit.row("Show minimap", UiKit.toggle(Game.settings["show_minimap"], func(on: bool): _apply("show_minimap", on))))
	v.add_child(UiKit.row("Check for updates", UiKit.toggle(Game.settings.get("check_updates", true),
		func(on: bool): _apply("check_updates", on))))
	var ver := UiKit.label("Version %s  ·  github.com/%s" % [Game.version, Game.repo], 15, UiKit.TEXT_DIM)
	v.add_child(ver)
	return v
