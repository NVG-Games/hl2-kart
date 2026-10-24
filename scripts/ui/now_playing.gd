class_name NowPlaying
extends PanelContainer
## Small "now playing" strip for the main menu: track name + prev / pause / next.

signal open_soundtrack

var title: Button
var pause_b: Button


func _ready() -> void:
	theme = UiKit.theme()
	add_theme_stylebox_override("panel", UiKit.box(Color(0, 0, 0, 0.5), Color(1, 1, 1, 0.08), 1, 4, 10))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	add_child(h)
	title = Button.new()
	title.flat = true
	title.clip_text = true
	title.custom_minimum_size = Vector2(300, 34)
	title.alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.add_theme_font_override("font", UiKit.font(false))
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", UiKit.TEXT_DIM)
	title.add_theme_color_override("font_hover_color", Color.WHITE)
	title.tooltip_text = "Open the soundtrack"
	title.pressed.connect(func(): open_soundtrack.emit())
	h.add_child(title)
	for spec in [["◀◀", -1], ["❚❚", 0], ["▶▶", 1]]:
		var b := Button.new()
		b.text = spec[0]
		b.flat = true
		b.custom_minimum_size = Vector2(40, 34)
		b.add_theme_font_size_override("font_size", 14)
		b.add_theme_color_override("font_color", UiKit.TEXT_DIM)
		b.add_theme_color_override("font_hover_color", UiKit.ORANGE)
		var d: int = spec[1]
		if d == 0:
			pause_b = b
			b.pressed.connect(func():
				Game.music.stream_paused = not Game.music.stream_paused
				_refresh(Game.now_playing))
		else:
			b.pressed.connect(func(): Game.music_skip(d))
		h.add_child(b)
	Game.music_changed.connect(_refresh)
	_refresh(Game.now_playing)


func _exit_tree() -> void:
	if Game.music_changed.is_connected(_refresh):
		Game.music_changed.disconnect(_refresh)


func _refresh(id: String) -> void:
	title.text = "♪  " + (Game.music_title(id) if id != "" else "Soundtrack")
	pause_b.text = "▶" if Game.music.stream_paused else "❚❚"
