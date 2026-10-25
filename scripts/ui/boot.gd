extends Control
## First start. The game ships without any Half-Life files: this screen finds the
## player's Half-Life 2 and Half-Life, runs tools/setup_assets.py to build the
## models, textures, sounds and tracks from them, then restarts into the menu.
## Built from engine defaults only (the HL2 fonts do not exist yet).
## When both games are found the build starts by itself after a short pause
## ("--setup-now" on the command line skips the pause).

const ORANGE := Color8(255, 155, 0)
const DIM := Color(1, 1, 1, 0.6)

var _python := ""
var _paths := {"hl2": "", "hl1": "", "hl2_ok": false, "hl1_ok": false}
var _rows := {}
var _build: Button
var _bar: ProgressBar
var _status: Label
var _error: Label
var _log_button: Button
var _pid := -1
var _status_path := ""
var _log_path := ""
var _poll := 0.0


func _ready() -> void:
	if Net.headless_role():
		return
	if Game.content_ready():
		get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
		return
	_status_path = ProjectSettings.globalize_path("user://setup_status.json")
	_log_path = ProjectSettings.globalize_path("user://setup.log")
	_build_ui()
	_python = _find_python()
	_detect()
	# both games found: no reason to make the player click
	if not _build.disabled:
		_status.text = "Found Half-Life 2 and Half-Life. Building starts in a moment..."
		get_tree().create_timer(0.1 if "--setup-now" in OS.get_cmdline_user_args() else 2.5).timeout.connect(_start)


# ---------------------------------------------------------------- ui
func _label(text: String, size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(190, 44)
	b.add_theme_font_size_override("font_size", 17)
	b.pressed.connect(cb)
	return b


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.07, 0.075)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = 820
	col.add_theme_constant_override("separation", 16)
	center.add_child(col)
	col.add_child(_label("HALF-LIFE 2: KART", 46))
	col.add_child(_label("First start  ·  v%s" % Game.version, 18, ORANGE))
	col.add_child(_label("This game is built from your own copies of Half-Life 2 and Half-Life. Nothing from Valve "
		+ "comes with the download: the first start reads your games' files and builds the models, textures, "
		+ "sounds, music and tracks on this computer. It takes 3 to 6 minutes and about 2 GB of disk space. "
		+ "Near the end a second window opens for a minute to draw the menu pictures; let it finish.", 17, DIM))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 10)
	col.add_child(grid)
	for key in ["hl2", "hl1"]:
		var name_l := _label("Half-Life 2" if key == "hl2" else "Half-Life", 18)
		name_l.custom_minimum_size.x = 130
		name_l.autowrap_mode = TextServer.AUTOWRAP_OFF
		grid.add_child(name_l)
		var path_l := _label("...", 16, DIM)
		path_l.custom_minimum_size.x = 470
		path_l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		grid.add_child(path_l)
		var k: String = key
		grid.add_child(_button("CHOOSE FOLDER...", func(): _choose(k)))
		_rows[key] = path_l
	_bar = ProgressBar.new()
	_bar.custom_minimum_size.y = 26
	_bar.max_value = 1.0
	_bar.show_percentage = false
	_bar.visible = false
	col.add_child(_bar)
	_status = _label("", 17)
	col.add_child(_status)
	_error = _label("", 17, Color(1, 0.45, 0.35))
	col.add_child(_error)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	col.add_child(row)
	_build = _button("BUILD GAME CONTENT", _start)
	_build.custom_minimum_size.x = 280
	row.add_child(_build)
	_log_button = _button("OPEN LOG", func(): OS.shell_open(_log_path))
	_log_button.visible = false
	row.add_child(_log_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	row.add_child(_button("QUIT", func(): get_tree().quit()))
	col.add_child(_label("Free fan project, not affiliated with Valve. Half-Life content belongs to Valve Corporation. "
		+ "github.com/" + Game.repo, 14, Color(1, 1, 1, 0.35)))


# ---------------------------------------------------------------- games
func _find_python() -> String:
	var bundled := ProjectSettings.globalize_path("res://runtime/python/python.exe")
	if FileAccess.file_exists(bundled):
		return bundled
	for exe in ["python", "py", "python3"]:
		var out := []
		if OS.execute(exe, ["-c", "import numpy, PIL; print('ok')"], out, true) == 0 and "ok" in "".join(out):
			return exe
	return ""


func _detect() -> void:
	if _python == "":
		_error.text = "Python with numpy and Pillow was not found. The download from GitHub Releases includes it; " \
			+ "when running from source, install Python 3 and run: pip install numpy pillow"
		_build.disabled = true
		return
	var out := []
	var args := [ProjectSettings.globalize_path("res://tools/steam_paths.py"), "--json"]
	if OS.execute(_python, args, out, true) == 0:
		var lines := "".join(out).strip_edges().split("\n")
		var d = JSON.parse_string(lines[lines.size() - 1])
		if d is Dictionary:
			for k in ["hl2", "hl1"]:
				if _paths[k] == "" or not _paths[k + "_ok"]:
					_paths[k] = str(d.get(k, ""))
					_paths[k + "_ok"] = bool(d.get(k + "_ok", false))
	_refresh()


func _refresh() -> void:
	for k in ["hl2", "hl1"]:
		var ok: bool = _paths[k + "_ok"]
		var l: Label = _rows[k]
		l.text = ("✔  " + str(_paths[k])) if ok else "not found  (install it on Steam, or choose its folder)"
		l.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6) if ok else Color(1, 0.55, 0.45))
	_build.disabled = _python == "" or not (_paths["hl2_ok"] and _paths["hl1_ok"]) or _pid > 0


func _choose(key: String) -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.use_native_dialog = true
	fd.title = "Choose the %s folder (the one that contains %s)" % ["Half-Life 2" if key == "hl2" else "Half-Life",
		"hl2" if key == "hl2" else "valve"]
	add_child(fd)
	fd.dir_selected.connect(func(dir: String):
		var sub := "hl2" if key == "hl2" else "valve"
		_paths[key] = dir
		_paths[key + "_ok"] = DirAccess.dir_exists_absolute(dir.path_join(sub))
		if not _paths[key + "_ok"]:
			_error.text = "%s has no \"%s\" folder inside: choose the game's main folder." % [dir, sub]
		else:
			_error.text = ""
		_refresh())
	fd.popup_centered_ratio(0.6)


# ---------------------------------------------------------------- build
func _start() -> void:
	if _build.disabled:
		return
	_error.text = ""
	_log_button.visible = false
	if FileAccess.file_exists(_status_path):
		DirAccess.remove_absolute(_status_path)
	var args := [ProjectSettings.globalize_path("res://tools/setup_assets.py"),
		"--godot", OS.get_executable_path(), "--status", _status_path, "--log", _log_path,
		"--hl2", _paths["hl2"], "--hl1", _paths["hl1"]]
	_pid = OS.create_process(_python, args, false)
	if _pid <= 0:
		_error.text = "Could not start the setup (%s)." % _python
		return
	_build.disabled = true
	_bar.visible = true
	_bar.value = 0.0
	_status.text = "Starting..."


func _process(delta: float) -> void:
	if _pid <= 0:
		return
	_poll += delta
	if _poll < 0.5:
		return
	_poll = 0.0
	var st = Game.load_json(_status_path) if FileAccess.file_exists(_status_path) else {}
	if st is Dictionary and not st.is_empty():
		_bar.value = float(st.get("progress", 0.0))
		if st.get("state") == "running":
			_status.text = "Step %d of %d:  %s..." % [int(st.get("index", 0)), int(st.get("total", 0)), st.get("message", "")]
		elif st.get("state") == "done":
			_pid = -1
			_status.text = "Done. Starting the game..."
			_restart.call_deferred()
			return
		elif st.get("state") == "error":
			_fail(str(st.get("error", "unknown error")))
			return
	if not OS.is_process_running(_pid):
		_fail("The setup stopped before finishing.")


func _fail(msg: String) -> void:
	_pid = -1
	_bar.visible = false
	_status.text = ""
	_error.text = "Setup failed: " + msg
	_log_button.visible = true
	_refresh()


## A fresh process picks up everything the setup imported.
func _restart() -> void:
	await get_tree().create_timer(0.6).timeout
	OS.create_process(OS.get_executable_path(), ["--path", ProjectSettings.globalize_path("res://")])
	get_tree().quit()
