extends Node3D
## Main menu in the manner of Half-Life 2's GameUI: a full-screen scene
## (sharp in-game stills, slow drift and cross-fade), the HALF-LIFE² logo,
## a short column of Verdana menu entries, a now-playing strip.

const BACKGROUNDS := ["grid", "city", "coast", "canal"]
const BG_SECONDS := 18.0

var ui: CanvasLayer
var root: Control
var bg_a: TextureRect
var bg_b: TextureRect
var title_box: Control
var items: VBoxContainer
var now_playing: NowPlaying
var setup: RaceSetup
var lobby: Lobby
var dialog: Dialog
var _connecting: MessageBox
var _bg_index := 0
var _bg_t := 0.0
var _textures: Array[Texture2D] = []


func _ready() -> void:
	if Net.headless_role():
		return
	PlayerController.setup_input_map()
	Game.settings["demo"] = false
	ui = CanvasLayer.new()
	add_child(ui)
	root = Control.new()
	root.theme = UiKit.theme()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(root)
	_build_background()
	_build_title()
	_build_items()
	now_playing = NowPlaying.new()
	now_playing.anchor_left = 1.0
	now_playing.anchor_right = 1.0
	now_playing.anchor_top = 1.0
	now_playing.anchor_bottom = 1.0
	now_playing.offset_left = -470
	now_playing.offset_right = -36
	now_playing.offset_top = -82
	now_playing.offset_bottom = -32
	now_playing.open_soundtrack.connect(func(): _open(SoundtrackPanel.new()))
	root.add_child(now_playing)
	if Game.now_playing == "":
		Game.play_music_mode("menu")
	Net.joined.connect(_on_joined)
	Net.connect_failed.connect(_on_connect_failed)
	Net.left.connect(_on_left)
	if Net.active and Net.state in ["lobby", "race_wait"]:
		_open_lobby.call_deferred()
		return
	if Net.notice != "":
		_message.call_deferred("DISCONNECTED", Net.notice)
		Net.notice = ""
	if not Game.settings.get("tutorial_seen", false):
		Game.settings["tutorial_seen"] = true
		Game.save_settings()
		_open.call_deferred(HowToPlay.new())
	else:
		(items.get_child(0) as Control).grab_focus.call_deferred()


# ---------------------------------------------------------------- background
func _build_background() -> void:
	for n in BACKGROUNDS:
		var t: Texture2D = load("res://assets/ui/backgrounds/%s.png" % n)
		if t:
			_textures.append(t)
	_textures.shuffle()
	bg_a = _bg_rect()
	bg_b = _bg_rect()
	bg_b.modulate.a = 0.0
	bg_a.texture = _textures[0]
	var shade := TextureRect.new()
	var g := GradientTexture2D.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0.82))
	grad.add_point(0.45, Color(0, 0, 0, 0.35))
	grad.set_color(grad.get_point_count() - 1, Color(0, 0, 0, 0.05))
	g.gradient = grad
	g.fill_to = Vector2(1, 0)
	shade.texture = g
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)


func _bg_rect() -> TextureRect:
	var r := TextureRect.new()
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(r)
	return r


func _process(delta: float) -> void:
	if bg_a == null:
		return
	_bg_t += delta
	# slow push-in on the current still, cross-fade to the next one
	var k := clampf(_bg_t / BG_SECONDS, 0.0, 1.0)
	var vs := get_viewport().get_visible_rect().size
	for r in [bg_a, bg_b]:
		r.pivot_offset = vs * 0.5
	bg_a.scale = Vector2.ONE * (1.0 + 0.045 * k)
	if _bg_t > BG_SECONDS - 2.0 and _textures.size() > 1:
		var f := clampf((_bg_t - (BG_SECONDS - 2.0)) / 2.0, 0.0, 1.0)
		if bg_b.texture == null or f == 0.0:
			bg_b.texture = _textures[(_bg_index + 1) % _textures.size()]
		bg_b.scale = Vector2.ONE
		bg_b.modulate.a = f
		if f >= 1.0:
			_bg_index = (_bg_index + 1) % _textures.size()
			bg_a.texture = bg_b.texture
			bg_a.scale = Vector2.ONE
			bg_b.modulate.a = 0.0
			bg_b.texture = null
			_bg_t = 0.0


# ---------------------------------------------------------------- title + items
func _build_title() -> void:
	title_box = Control.new()
	title_box.position = Vector2(118, 150)
	root.add_child(title_box)
	var logo_font := FontVariation.new()
	logo_font.base_font = Hl2Style.numbers_font()
	logo_font.spacing_glyph = -20
	var logo := Label.new()
	logo.text = "HALF-LIFE'"
	logo.add_theme_font_override("font", logo_font)
	logo.add_theme_font_size_override("font_size", 82)
	logo.add_theme_color_override("font_color", Color(1, 1, 1, 0.96))
	title_box.add_child(logo)
	var kart_font := FontVariation.new()
	kart_font.base_font = UiKit.font(true)
	kart_font.spacing_glyph = 10
	var kart := Label.new()
	kart.text = "KART"
	kart.add_theme_font_override("font", kart_font)
	kart.add_theme_font_size_override("font_size", 40)
	kart.add_theme_color_override("font_color", Hl2Style.BRIGHT)
	kart.position = Vector2(8, 98)
	title_box.add_child(kart)


func _build_items() -> void:
	items = VBoxContainer.new()
	items.anchor_top = 1.0
	items.anchor_bottom = 1.0
	items.offset_left = 120
	items.offset_top = -500
	items.offset_right = 700
	items.offset_bottom = -110
	items.add_theme_constant_override("separation", 18)
	root.add_child(items)
	var entries := [
		["NEW RACE", _open_setup],
		["FIND SERVERS", _open_browser],
		["CREATE SERVER", _open_create],
		["HOW TO PLAY", func(): _open(HowToPlay.new())],
		["SOUNDTRACK", func(): _open(SoundtrackPanel.new())],
		["OPTIONS", func(): _open(OptionsPanel.new())],
		["QUIT", func(): get_tree().quit()],
	]
	for e in entries:
		var b := UiKit.menu_item(e[0])
		b.pressed.connect(e[1])
		items.add_child(b)


func _set_menu_visible(v: bool) -> void:
	title_box.visible = v
	items.visible = v
	now_playing.visible = v


func _open(d: Dialog) -> void:
	if dialog and is_instance_valid(dialog):
		dialog.queue_free()
	dialog = d
	root.add_child(d)
	var last := get_viewport().gui_get_focus_owner()
	d.closed.connect(func():
		if setup == null and lobby == null and items.get_child_count() > 0:
			(items.get_child(0) if last == null or not is_instance_valid(last) else last).grab_focus())


func _open_setup() -> void:
	setup = RaceSetup.new()
	root.add_child(setup)
	_set_menu_visible(false)
	setup.back.connect(func():
		Game.save_settings()
		setup.queue_free()
		setup = null
		_set_menu_visible(true)
		(items.get_child(0) as Control).grab_focus())
	setup.start.connect(_go_race)
	setup.focus_default.call_deferred()


func _go_race() -> void:
	Game.save_settings()
	Game.play_ui("res://assets/sound/buttons/combine_button1.wav", -2.0)
	Game.stop_music()
	var fade := ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(fade)
	var loading := UiKit.label("LOADING...", 28, Color(1, 1, 1, 0.9), true)
	loading.anchor_left = 1.0
	loading.anchor_right = 1.0
	loading.anchor_top = 1.0
	loading.anchor_bottom = 1.0
	loading.offset_left = -260
	loading.offset_top = -80
	loading.modulate.a = 0.0
	root.add_child(loading)
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, 0.35)
	tw.parallel().tween_property(loading, "modulate:a", 1.0, 0.35)
	tw.tween_interval(0.05)
	tw.tween_callback(func(): get_tree().change_scene_to_file("res://scenes/race.tscn"))


# ---------------------------------------------------------------- multiplayer
func _message(title: String, text: String) -> void:
	_open(MessageBox.new(title, text))


func _open_browser() -> void:
	var b := ServerBrowser.new()
	b.join_requested.connect(_join)
	_open(b)


func _open_create() -> void:
	var c := CreateServer.new()
	c.hosted.connect(func(): _open_lobby.call_deferred())
	_open(c)


func _join(address: String, port: int, password: String) -> void:
	if Net.join(address, port, password) != OK:
		_message("CONNECT", Net.last_error)
		return
	_connecting = MessageBox.new("CONNECTING", "Connecting to %s:%d ..." % [address, port], false, false, "", "CANCEL")
	_connecting.answered.connect(func(_ok, _t):
		_connecting = null
		Net.leave())
	root.add_child(_connecting)


func _close_connecting() -> void:
	if _connecting and is_instance_valid(_connecting):
		var c := _connecting
		_connecting = null
		c.queue_free()


func _on_joined() -> void:
	_close_connecting()
	if dialog and is_instance_valid(dialog):
		dialog.queue_free()
	_open_lobby()


func _on_connect_failed(reason: String) -> void:
	_close_connecting()
	_message("COULD NOT CONNECT", reason)


func _on_left(reason: String) -> void:
	Net.notice = ""
	if lobby and is_instance_valid(lobby):
		lobby.queue_free()
		lobby = null
		_set_menu_visible(true)
		(items.get_child(0) as Control).grab_focus()
	if reason != "":
		_message("DISCONNECTED", reason)


func _open_lobby() -> void:
	if lobby and is_instance_valid(lobby):
		return
	if not Net.active:
		return
	lobby = Lobby.new()
	root.add_child(lobby)
	_set_menu_visible(false)
	lobby.leave_requested.connect(func():
		Game.save_settings()
		Net.leave()
		if lobby and is_instance_valid(lobby):
			lobby.queue_free()
		lobby = null
		_set_menu_visible(true)
		(items.get_child(0) as Control).grab_focus())
