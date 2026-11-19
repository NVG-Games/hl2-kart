class_name EditorHome
extends Control
## TRACK EDITOR's home (1.1), a menu screen like NEW RACE: the tabs MY TRACKS | DOWNLOADED |
## TEMPLATES (LB / RB, Page Up / Page Down; it opens on TEMPLATES while MY TRACKS is empty), a
## TrackList of cards (MY TRACKS starts with + NEW TRACK), a search field, the details of the
## selected card on the right, and the buttons of the tab at the foot with the hints above them.
## MY TRACKS: EDIT (A / double click), PLAY (Y), HOST (X), DUPLICATE, RENAME (F2), DELETE (Delete),
## OPEN FOLDER; DOWNLOADED: PLAY (A / Y), HOST (X), KEEP, REMIX, DELETE; TEMPLATES: CREATE (A):
## the template opens in the editor at once, unsaved, auto-named ("MY TRACK", "MY TRACK 2"...).
## .hl2kt files dropped on the window are imported through CustomTracks.import_file (the one gate).
## Entering it offers to recover an autosave newer than its track (or of a never-saved track); the
## first visit shows a three-step card over TEMPLATES (gone after the first CREATE or 12 s).
## The main menu (menu.gd) opens it and acts on its signals.

signal back
## The session holds the track to edit (EditorSession.current()): the editor scene should open.
signal open_editor
## PLAY: NEW RACE with this track picked (settings.track / track_guid are set).
signal play(id: String)
## HOST: EditorSession.return_to = "host" and host_track are set: CREATE SERVER should open.
signal host(id: String)

const TABS := ["mine", "downloaded", "templates"]
const TAB_TITLES := ["MY TRACKS", "DOWNLOADED", "TEMPLATES"]
const ACTIONS := {
	"mine": ["EDIT", "PLAY", "HOST", "DUPLICATE", "RENAME", "DELETE", "OPEN FOLDER"],
	"downloaded": ["PLAY", "HOST", "KEEP", "REMIX", "DELETE"],
	"templates": ["CREATE"],
}
const BUTTON_ORDER := ["EDIT", "CREATE", "PLAY", "HOST", "KEEP", "REMIX", "DUPLICATE", "RENAME", "DELETE", "OPEN FOLDER"]
const HINT_SECONDS := 12.0
const HINT_KEY := "home"
const HINT_TEXT := "1. Pick a template.    2. Drag the road's points.    3. Press {ed_test} to drive it."
const COLUMNS := 4

var tabs: TabBar
var list: TrackList
var details: TrackList.Details
var search: LineEdit
var notice: Label
var prompt_bar: PromptBar
var button_row: HBoxContainer
var buttons := {}  # action -> Button
var back_button: Button
var hint_card: PanelContainer
## The tab shown ("mine" | "downloaded" | "templates").
var tab := ""
## The tab to open on (menu: "" = TEMPLATES when MY TRACKS is empty, else MY TRACKS).
var start_tab := ""
## The open MessageBox (rename, delete, recovery), or null.
var dialog: Dialog
## OPEN FOLDER's folders (tests read it; headless runs open no file manager).
var shell_calls: Array = []
## Skip the crash-recovery prompt (tests that drive it themselves).
var check_recovery := true
var _hint_t := 0.0
var _hint_on := false
var _busy := false
var _copier: EditorSession
var _tab_glyphs: Array[Control] = []
var _declined := {}  # autosave paths answered "not now" this visit


func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group(InputPrompts.SCREEN_GROUP)
	# the first-visit card names the editor's keys ({ed_test})
	EditorInput.apply()
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 56)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_bottom", 30)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)
	col.add_child(UiKit.label("TRACK EDITOR", 34, Color.WHITE, true))
	col.add_child(UiKit.label("Make a track, drive it, race it with friends.", 16, UiKit.TEXT_DIM))
	col.add_child(_tab_row())
	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 30)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(main)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_child(left)
	hint_card = _hint_card()
	left.add_child(hint_card)
	list = TrackList.new(COLUMNS)
	list.custom_minimum_size.x = TrackList.width_for(COLUMNS)
	list.selected.connect(_on_selected)
	list.activated.connect(_on_activated)
	left.add_child(list)
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", UiKit.box(Color(0, 0, 0, 0.62), Color(1, 1, 1, 0.08), 1, 4, 14))
	plate.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	main.add_child(plate)
	details = TrackList.Details.new()
	plate.add_child(details)
	notice = UiKit.label("", 16, UiKit.TEXT)
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice.custom_minimum_size.y = 22
	col.add_child(notice)
	prompt_bar = PromptBar.new()
	col.add_child(prompt_bar)
	col.add_child(_button_row())
	CustomTracks.refresh()
	Game.track_thumb_ready.connect(_on_thumb)
	Game.custom_tracks_changed.connect(_on_customs_changed)
	InputPrompts.prompts_changed.connect(_update_tab_glyphs)
	_hint_on = not (Game.settings.get("editor_hints", []) as Array).has(HINT_KEY)
	show_tab(start_tab if start_tab in TABS else initial_tab())
	_update_tab_glyphs()
	if check_recovery:
		_check_recovery.call_deferred()


func _enter_tree() -> void:
	if not get_window().files_dropped.is_connected(_on_files_dropped):
		get_window().files_dropped.connect(_on_files_dropped)


func _exit_tree() -> void:
	if get_window().files_dropped.is_connected(_on_files_dropped):
		get_window().files_dropped.disconnect(_on_files_dropped)


## TEMPLATES while MY TRACKS is empty, else MY TRACKS.
static func initial_tab() -> String:
	return "templates" if CustomTracks.list("mine").is_empty() else "mine"


# ---------------------------------------------------------------- layout

func _tab_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	tabs = TabBar.new()
	for t in TAB_TITLES:
		tabs.add_tab(t)
	tabs.clip_tabs = false
	tabs.focus_mode = Control.FOCUS_NONE
	tabs.tab_changed.connect(func(i: int): show_tab(TABS[clampi(i, 0, TABS.size() - 1)]))
	for act in ["ui_tab_prev", "", "ui_tab_next"]:
		if act == "":
			row.add_child(tabs)
			continue
		var g := InputGlyph.new(act, 28.0)
		g.style = "pad"
		g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(g)
		_tab_glyphs.append(g)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(gap)
	search = UiKit.text_field("", "Search by name or author", func(t: String): list.set_filter(t), 320)
	search.clear_button_enabled = true
	row.add_child(search)
	return row


func _hint_card() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiKit.box(Color(0, 0, 0, 0.7), UiKit.ORANGE, 1, 4, 12))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var l := UiKit.prompt(EditorKit.prompt(HINT_TEXT), 17, UiKit.TEXT, true)
	l.name = "Text"
	p.add_child(l)
	p.visible = false
	return p


func _button_row() -> Control:
	button_row = HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 12)
	for a in BUTTON_ORDER:
		var b := UiKit.button(a, 150)
		b.name = a.replace(" ", "_")
		b.pressed.connect(_do.bind(a))
		button_row.add_child(b)
		buttons[a] = b
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button_row.add_child(gap)
	back_button = UiKit.button("BACK", 150)
	back_button.pressed.connect(func(): back.emit())
	button_row.add_child(back_button)
	return button_row


func _update_tab_glyphs() -> void:
	for g in _tab_glyphs:
		g.modulate.a = 1.0 if InputPrompts.using_pad() else 0.0


# ---------------------------------------------------------------- tabs and lists

## Shows a tab's cards (keep_id stays selected), buttons and hints.
func show_tab(name_: String, keep_id := "") -> void:
	if not name_ in TABS:
		return
	var changed := name_ != tab
	tab = name_
	tabs.set_block_signals(true)
	tabs.current_tab = TABS.find(tab)
	tabs.set_block_signals(false)
	for a in buttons:
		(buttons[a] as Button).visible = a in ACTIONS[tab]
	var shown: Array = ACTIONS[tab]
	list.down_target = buttons[shown[0]]
	list.up_target = search
	match tab:
		"mine":
			list.empty_label.text = ""
		"downloaded":
			list.empty_label.text = "No downloads yet. Tracks you race on a friend's server land here, and so do .hl2kt files dropped on this window."
		"templates":
			list.empty_label.text = ""
	list.set_entries(entries_for(tab), keep_id if keep_id != "" or not changed else "")
	_set_prompts()
	hint_card.visible = _hint_on and tab == "templates"
	if changed and notice.text != "" and not notice.has_meta("keep"):
		say("")
	notice.remove_meta("keep")
	_refresh_buttons()
	_wire_edges()


## The cards of a tab: + NEW TRACK and the own tracks; the kept and cached downloads; the templates.
static func entries_for(which: String) -> Array:
	var out := []
	match which:
		"mine":
			out.append(TrackList.new_entry())
			out.append_array(CustomTracks.list("mine"))
		"downloaded":
			out.append_array(CustomTracks.list("downloaded"))
		"templates":
			for tid in LevelTemplates.IDS:
				out.append(TrackList.template_entry(tid))
	return out


func _set_prompts() -> void:
	var tabs_hint := ["{ui_tab_prev} {ui_tab_next} TABS"]
	var back_hint := ["{ui_cancel} BACK"]
	match tab:
		"mine":
			prompt_bar.set_entries([["{ui_accept} EDIT"], ["{ui_select} PLAY", "pad"], ["{ui_clear} HOST", "pad"], tabs_hint, back_hint])
		"downloaded":
			prompt_bar.set_entries([["{ui_accept} PLAY"], ["{ui_clear} HOST", "pad"], tabs_hint, back_hint])
		_:
			prompt_bar.set_entries([["{ui_accept} CREATE"], tabs_hint, back_hint])


func _step_tab(step: int) -> void:
	var i := posmod(TABS.find(tab) + step, TABS.size())
	show_tab(TABS[i])
	var c := list.current_card()
	if c != null:
		c.grab_focus()
	elif list.cards.is_empty():
		focus_default()


func _on_selected(e: Dictionary) -> void:
	details.show_entry(e)
	_refresh_buttons()
	_wire_edges()


## Up from the buttons and down from the search field: the selected card (not whatever lies
## nearest that way).
func _wire_edges() -> void:
	var c: Control = list.current_card()
	if c == null and not list.cards.is_empty():
		c = list.cards[0]
	search.focus_neighbor_bottom = search.get_path_to(c) if c != null else NodePath("")
	var row: Array[Button] = []
	for a in BUTTON_ORDER:
		if (buttons[a] as Button).visible:
			row.append(buttons[a])
	row.append(back_button)
	for i in row.size():
		var b := row[i]
		b.focus_neighbor_top = b.get_path_to(c) if c != null else NodePath("")
		# along the row and no further (not up into the cards at its ends)
		b.focus_neighbor_left = b.get_path_to(row[i - 1]) if i > 0 else NodePath(".")
		b.focus_neighbor_right = b.get_path_to(row[i + 1]) if i + 1 < row.size() else NodePath(".")


func _refresh_buttons() -> void:
	var e := list.current
	var custom := CustomTracks.is_custom(str(e.get("id", "")))
	for a in ["PLAY", "HOST", "DUPLICATE", "RENAME", "DELETE", "REMIX"]:
		(buttons[a] as Button).disabled = not custom
	(buttons["EDIT"] as Button).disabled = e.is_empty()
	(buttons["CREATE"] as Button).disabled = not e.has("template")
	(buttons["KEEP"] as Button).disabled = not custom or str(e.get("kind", "")) != "cache"


func _on_activated(e: Dictionary) -> void:
	if bool(e.get("new", false)):
		show_tab("templates")
		var c := list.current_card()
		if c != null:
			c.grab_focus()
		return
	if e.has("template"):
		create(str(e.template))
		return
	match tab:
		"mine":
			edit(e)
		_:
			play_track(e)


func _do(action: String) -> void:
	var e := list.current
	match action:
		"EDIT":
			if bool(e.get("new", false)):
				_on_activated(e)
			else:
				edit(e)
		"CREATE":
			if e.has("template"):
				create(str(e.template))
		"PLAY":
			play_track(e)
		"HOST":
			host_track(e)
		"DUPLICATE":
			duplicate_track(e)
		"RENAME":
			ask_rename(e)
		"DELETE":
			ask_delete(e)
		"OPEN FOLDER":
			open_folder()
		"KEEP":
			keep_track(e)
		"REMIX":
			remix(e)


## A line under the cards: what just happened, or why not (red).
func say(text: String, bad := false) -> void:
	notice.text = text
	notice.add_theme_color_override("font_color", Color(1, 0.45, 0.35) if bad else UiKit.TEXT)


func _refuse(why: String) -> String:
	say(why, true)
	Game.play_ui("res://assets/sound/buttons/button9.wav", -6.0)
	return why


func _custom(e: Dictionary) -> bool:
	return CustomTracks.is_custom(str(e.get("id", ""))) and str(e.get("path", "")) != ""


# ---------------------------------------------------------------- the actions

## EDIT: the track opens in the editor. "" or the reason.
func edit(e: Dictionary) -> String:
	if not _custom(e):
		return _refuse("Pick a track to edit.")
	var s := EditorSession.current()
	var why := s.open(str(e.path))
	if why != "":
		return _refuse("%s could not be opened: %s" % [e.get("name", "The track"), why])
	s.return_to = ""
	open_editor.emit()
	return ""


## CREATE: the template opens in the editor at once, unsaved and auto-named (no name box).
func create(template_id: String) -> void:
	var s := EditorSession.current()
	s.create(template_id)
	s.return_to = ""
	_hint_done()
	open_editor.emit()


## PLAY: NEW RACE with the track picked. "" or the reason.
func play_track(e: Dictionary) -> String:
	if not _custom(e):
		return _refuse("Pick a track to race.")
	var why := TrackList.why_not(e)
	if why != "":
		return _refuse("%s cannot be raced. %s" % [e.get("name", "The track"), why])
	Game.settings["track"] = str(e.id)
	Game.settings["track_guid"] = str(e.get("guid", ""))
	play.emit(str(e.id))
	return ""


## HOST: CREATE SERVER with the track picked (refused when it cannot be raced, errors first).
## "" or the reason.
func host_track(e: Dictionary) -> String:
	if not _custom(e):
		return _refuse("Pick a track to host.")
	var errs := int(e.get("errors", 0))
	if errs > 0:
		return _refuse("Fix the %d error%s before you host." % [errs, "" if errs == 1 else "s"])
	var why := TrackList.why_not(e)
	if why != "":
		return _refuse("%s cannot be hosted. %s" % [e.get("name", "The track"), why])
	var s := EditorSession.current()
	s.return_to = "host"
	s.host_track = str(e.id)
	host.emit(str(e.id))
	return ""


## DUPLICATE: a copy (new guid, free name) saved in MY TRACKS on a worker. "" or the reason.
func duplicate_track(e: Dictionary) -> String:
	if not _custom(e) or str(e.get("kind", "")) != "mine":
		return _refuse("Pick one of your tracks to copy.")
	if _busy:
		return _refuse("Wait for the copy to finish.")
	var s := EditorSession.new()
	var why := s.open_copy(str(e.path), false)
	if why != "":
		return _refuse("It could not be copied: %s" % why)
	_busy = true
	_copier = s
	say("COPYING %s..." % e.get("name", ""))
	s.save("", {}, _copied.bind(str(s.doc.data.get("name", "")), str(s.doc.data.get("guid", ""))))
	return ""


func _copied(err: int, nm: String, guid: String) -> void:
	_busy = false
	if _copier != null:
		_copier.close()
	_copier = null
	if err != OK:
		_refuse("The copy could not be saved.")
		return
	notice.set_meta("keep", true)
	show_tab("mine", CustomTracks.id_for_guid(guid))
	say("Copied as %s." % nm)
	_focus_current()


## Whether a copy is being saved (DUPLICATE).
func busy() -> bool:
	return _busy


## RENAME: a MessageBox with the name in a field.
func ask_rename(e: Dictionary) -> void:
	if not _custom(e) or str(e.get("kind", "")) != "mine":
		_refuse("Pick one of your tracks to rename.")
		return
	var box := MessageBox.new("RENAME", "A new name for %s:" % e.get("name", ""), true, false, "RENAME", "CANCEL")
	box.field.text = str(e.get("name", ""))
	box.field.max_length = 48
	box.answered.connect(func(ok: bool, text: String):
		if ok:
			rename_to(e, text))
	_open(box)


## Renames the file's track (EditorSession.rename_track). "" or the reason.
func rename_to(e: Dictionary, new_name: String) -> String:
	if not _custom(e):
		return _refuse("Pick one of your tracks to rename.")
	var np := EditorSession.rename_track(str(e.path), new_name)
	if np == "":
		return _refuse("It could not be renamed: %s" % EditorSession.last_error)
	var id := CustomTracks.id_for_guid(str(e.get("guid", "")))
	notice.set_meta("keep", true)
	show_tab("mine", id)
	say("Renamed to %s." % CustomTracks.meta(id).get("name", new_name) if id != "" else "Renamed.")
	_focus_current()
	return ""


## DELETE: a MessageBox (CANCEL focused); own and kept tracks go to the trash, a cached download
## is deleted.
func ask_delete(e: Dictionary) -> void:
	if not _custom(e):
		_refuse("Pick a track to delete.")
		return
	var nm := str(e.get("name", "the track"))
	var text := "Move %s to the trash? It stays in the tracks folder's .trash until you empty it yourself." % nm
	if str(e.get("kind", "")) == "cache":
		text = "Delete the download of %s? You can download it again from a server that races it." % nm
	var box := MessageBox.new("DELETE", text, false, false, "DELETE", "CANCEL")
	box.focus_cancel = true
	box.answered.connect(func(ok: bool, _t: String):
		if ok:
			delete_now(e))
	_open(box)


## Deletes at once (DELETE's yes). "" or the reason.
func delete_now(e: Dictionary) -> String:
	if not _custom(e):
		return _refuse("Pick a track to delete.")
	var i := list.index_of(str(e.id))
	var err := CustomTracks.remove(str(e.id))
	if err != OK:
		return _refuse("It could not be deleted: %s" % CustomTracks.last_error)
	notice.set_meta("keep", true)
	show_tab(tab)
	if not list.cards.is_empty():
		list.select(clampi(i, 0, list.cards.size() - 1), true)
	say("%s went to the trash." % e.get("name", "The track") if str(e.get("kind", "")) != "cache" else "%s was deleted." % e.get("name", "The download"))
	_focus_current()
	return ""


## OPEN FOLDER: the tracks folder in the file manager.
func open_folder() -> void:
	var dir := CustomTracks.mine_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var g := ProjectSettings.globalize_path(dir)
	shell_calls.append(g)
	if DisplayServer.get_name() != "headless":
		OS.shell_show_in_file_manager(g)


## KEEP: a cached download is copied into downloaded/ and never evicted. "" or the reason.
func keep_track(e: Dictionary) -> String:
	if not _custom(e) or str(e.get("kind", "")) != "cache":
		return _refuse("Only a download that is not kept yet can be kept.")
	var err := CustomTracks.keep(str(e.id))
	if err != OK:
		return _refuse("It could not be kept: %s" % CustomTracks.last_error)
	notice.set_meta("keep", true)
	show_tab("downloaded", str(e.id))
	say("Kept: %s stays in DOWNLOADED." % e.get("name", "the track"))
	_focus_current()
	return ""


## REMIX: a copy opens in the editor (new guid, you as the author, remix_of credit); saving puts
## it in MY TRACKS. "" or the reason.
func remix(e: Dictionary) -> String:
	if not _custom(e):
		return _refuse("Pick a download to remix.")
	var s := EditorSession.current()
	var why := s.open_copy(str(e.path), true)
	if why != "":
		return _refuse("It could not be opened: %s" % why)
	s.return_to = ""
	open_editor.emit()
	return ""


## Dropped files: each .hl2kt goes through CustomTracks.import_file (unpack + sanitize, then a
## copy into downloaded/). Returns one line per file ("Imported Canal Run by Sasha" or the reason).
func import_files(paths: PackedStringArray) -> PackedStringArray:
	var lines := PackedStringArray()
	var last_id := ""
	var bad := false
	for p in paths:
		var fname := p.get_file()
		if not p.to_lower().ends_with(LevelIO.EXT):
			lines.append("%s is not a track file (%s)." % [fname, LevelIO.EXT])
			bad = true
			continue
		var id := CustomTracks.import_file(p)
		if id == "":
			lines.append("%s was not imported: %s" % [fname, CustomTracks.last_error])
			bad = true
			continue
		var m := CustomTracks.meta(id)
		var by := str(m.get("author", ""))
		if str(m.get("kind", "")) == "mine":
			lines.append("%s is one of your tracks already." % m.get("name", fname))
		else:
			lines.append("Imported %s%s" % [m.get("name", fname), " by %s" % by if by != "" else ""])
			last_id = id
	if last_id != "":
		notice.set_meta("keep", true)
		show_tab("downloaded", last_id)
		_focus_current()
	if not lines.is_empty():
		say("   ".join(lines), bad and last_id == "")
		if bad and last_id == "":
			Game.play_ui("res://assets/sound/buttons/button9.wav", -6.0)
	return lines


func _on_files_dropped(files: PackedStringArray) -> void:
	if is_visible_in_tree():
		import_files(files)


# ---------------------------------------------------------------- recovery and the first visit

## An autosave newer than its track (or of a never-saved one): RECOVER / DISCARD (to .trash);
## B leaves it for the next visit.
func _check_recovery() -> void:
	if not is_inside_tree() or _dialog_open():
		return
	for r in EditorSession.recoveries():
		var a := str(r.autosave)
		if _declined.has(a):
			continue
		var nm := str(r.get("name", "")) if str(r.get("name", "")) != "" else "A track"
		var when := TrackList.date_line({"modified": int(r.get("modified", 0))}).trim_prefix("MODIFIED ")
		var box := MessageBox.new("RECOVER YOUR TRACK?", "%s has changes from %s that were not saved." % [nm, when],
			false, false, "RECOVER", "")
		var state := {"discard": false}
		box.add_button("DISCARD", func():
			state.discard = true
			box.close())
		box.answered.connect(func(ok: bool, _t: String):
			if ok:
				_recover(a)
			elif state.discard:
				EditorSession.discard_autosave(a)
				_check_recovery.call_deferred()
			else:
				_declined[a] = true)
		box.set_meta("recovery", a)
		_open(box)
		return


func _recover(autosave_path: String) -> void:
	var s := EditorSession.current()
	var why := s.recover(autosave_path)
	if why != "":
		_refuse("It could not be recovered: %s" % why)
		return
	s.return_to = ""
	open_editor.emit()


## The first-visit card goes (after the first CREATE or 12 s on TEMPLATES) and is not shown again.
func _hint_done() -> void:
	if not _hint_on:
		return
	_hint_on = false
	var hints: Array = (Game.settings.get("editor_hints", []) as Array).duplicate()
	if not hints.has(HINT_KEY):
		hints.append(HINT_KEY)
	Game.settings["editor_hints"] = hints
	Game.save_settings()
	if hint_card.visible:
		var tw := create_tween()
		tw.tween_property(hint_card, "modulate:a", 0.0, 0.5)
		tw.tween_callback(func(): hint_card.visible = false)


## Whether the first-visit card is still to be shown.
func hint_shown() -> bool:
	return _hint_on and hint_card.visible


func _process(delta: float) -> void:
	if _hint_on and hint_card.visible and is_visible_in_tree():
		_hint_t += delta
		if _hint_t >= HINT_SECONDS:
			_hint_done()


# ---------------------------------------------------------------- signals, focus, input

func _on_thumb(id: String) -> void:
	var tex := Game.track_thumb(id)
	list.set_thumb(id, tex)
	details.set_thumb(id, tex)


## A background check finished or the registry changed: the cards again, the same one selected.
func _on_customs_changed() -> void:
	if tab != "templates":
		show_tab(tab)


func _open(d: Dialog) -> void:
	if _dialog_open():
		dialog.queue_free()
	dialog = d
	add_child(d)


func _dialog_open() -> bool:
	return dialog != null and is_instance_valid(dialog) and not dialog.is_queued_for_deletion() and dialog.is_inside_tree()


func _focus_current() -> void:
	if not is_visible_in_tree() or _dialog_open():
		return
	var c := list.current_card()
	if c != null:
		c.grab_focus()


## The safety net (InputPrompts): the selected card, else the first, else BACK.
func focus_default() -> bool:
	if not is_visible_in_tree() or _dialog_open():
		return false
	var c: Control = list.current_card()
	if c == null and not list.cards.is_empty():
		c = list.cards[0]
	if c == null:
		for a in ACTIONS[tab]:
			var b := buttons[a] as Button
			if b.visible and not b.disabled:
				c = b
				break
	if c == null:
		c = back_button
	c.grab_focus()
	return true


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or _dialog_open() or not event.is_pressed() or event.is_echo():
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		var f := get_viewport().gui_get_focus_owner()
		if f is LineEdit and (f as LineEdit).is_editing():
			(f as LineEdit).unedit()
			return
		Game.play_ui("res://assets/sound/ui/buttonclickrelease.wav", -5.0)
		back.emit()
	elif event.is_action_pressed("ui_tab_next") or event.is_action_pressed("ui_tab_prev"):
		get_viewport().set_input_as_handled()
		_step_tab(1 if event.is_action_pressed("ui_tab_next") else -1)
	elif event is InputEventJoypadButton and event.is_action_pressed("ui_select"):
		# Y: PLAY (Space is the keyboard's ui_select too: it presses the focused card)
		if tab != "templates":
			get_viewport().set_input_as_handled()
			play_track(list.current)
	elif event is InputEventJoypadButton and event.is_action_pressed("ui_clear"):
		# X: HOST
		if tab != "templates":
			get_viewport().set_input_as_handled()
			host_track(list.current)
	elif event is InputEventKey and event.is_action_pressed("ui_clear"):
		# Delete: DELETE (asks first)
		if tab != "templates":
			get_viewport().set_input_as_handled()
			ask_delete(list.current)
	elif event is InputEventKey and (event as InputEventKey).keycode == KEY_F2:
		if tab == "mine":
			get_viewport().set_input_as_handled()
			ask_rename(list.current)
