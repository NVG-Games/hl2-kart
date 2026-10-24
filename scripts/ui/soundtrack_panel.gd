class_name SoundtrackPanel
extends Dialog
## SOUNDTRACK: every music track shipped with Half-Life 2, playable in the menu.

var list: VBoxContainer
var rows := {}
var now_label: Label
var pause_b: Button


func _init() -> void:
	super("SOUNDTRACK", Vector2(860, 720))


func _ready() -> void:
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	now_label = UiKit.label("", 18, Hl2Style.BRIGHT, true)
	now_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	now_label.clip_text = true
	top.add_child(now_label)
	var prev := UiKit.button("◀◀", 64)
	prev.pressed.connect(func(): Game.music_skip(-1))
	top.add_child(prev)
	pause_b = UiKit.button("PAUSE", 110)
	pause_b.pressed.connect(_toggle_pause)
	top.add_child(pause_b)
	var nxt := UiKit.button("▶▶", 64)
	nxt.pressed.connect(func(): Game.music_skip(1))
	top.add_child(nxt)
	body.add_child(top)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	body.add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)
	scroll.add_child(list)
	var album := ""
	for m in Game.music_library:
		if m["album"] != album:
			album = m["album"]
			var head := UiKit.section(album.to_upper())
			head.add_theme_constant_override("line_spacing", 0)
			var pad := MarginContainer.new()
			pad.add_theme_constant_override("margin_top", 12)
			pad.add_child(head)
			list.add_child(pad)
		var b := Button.new()
		b.text = "    " + m["title"]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.y = 36
		b.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		b.add_theme_stylebox_override("hover", UiKit.box(Color(1, 1, 1, 0.08), Color(0, 0, 0, 0), 0, 2, 10))
		b.add_theme_stylebox_override("focus", UiKit.box(Color(1, 1, 1, 0.08), UiKit.ORANGE, 1, 2, 10))
		b.add_theme_stylebox_override("pressed", UiKit.box(Color(UiKit.ORANGE.r, UiKit.ORANGE.g, UiKit.ORANGE.b, 0.3), Color(0, 0, 0, 0), 0, 2, 10))
		b.add_theme_font_override("font", UiKit.font(false))
		var id: String = m["id"]
		b.pressed.connect(func(): Game.play_track(id, "jukebox"))
		list.add_child(b)
		rows[id] = b
	add_button("CLOSE", close)
	Game.music_changed.connect(_refresh)
	_refresh(Game.now_playing)
	if rows.has(Game.now_playing):
		(rows[Game.now_playing] as Button).grab_focus.call_deferred()
	elif not rows.is_empty():
		(rows.values()[0] as Button).grab_focus.call_deferred()


func _toggle_pause() -> void:
	Game.music.stream_paused = not Game.music.stream_paused
	_refresh(Game.now_playing)


func _refresh(id: String) -> void:
	now_label.text = ("♪  " + Game.music_title(id)) if id != "" else "Nothing playing"
	pause_b.text = "PLAY" if Game.music.stream_paused or id == "" else "PAUSE"
	for k in rows:
		var b: Button = rows[k]
		var on: bool = k == id
		b.add_theme_color_override("font_color", UiKit.ORANGE if on else UiKit.TEXT)
		b.add_theme_color_override("font_hover_color", UiKit.ORANGE if on else Color.WHITE)
		b.add_theme_color_override("font_focus_color", UiKit.ORANGE if on else Color.WHITE)
		b.text = ("  ♪ " if on else "    ") + b.text.strip_edges().trim_prefix("♪").strip_edges()


func close() -> void:
	if Game.music_changed.is_connected(_refresh):
		Game.music_changed.disconnect(_refresh)
	super()
