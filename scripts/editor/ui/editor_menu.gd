class_name EditorMenu
extends Dialog
## The Esc / Start menu (1.10), pad-navigable like every Dialog: RESUME; TOOL (the ten tools);
## TEST DRIVE FROM THE START / FROM HERE / WATCH A BOT LAP; TEST DRIVE OPTIONS (BOTS, LAPS,
## HAZARDS, DIFFICULTY); VIEW (TOP VIEW, RACING LINE, GO TO START, FRAME TRACK); UNDO <step>; REDO;
## SAVE; HOST ONLINE WITH THIS TRACK; TRACK PROPERTIES; SET THUMBNAIL FROM CAMERA; HELP; EXIT TO
## TRACK EDITOR; EXIT TO MAIN MENU (the pad's only way to undo and to set the picture).
## TOOL, TEST DRIVE OPTIONS and VIEW are pages of the menu: B goes back from them. P10.

const ITEM_FONT := 20
## The main page's entries: [text, id].
const MAIN := [["RESUME", "resume"], ["TOOL", "tool"], ["TEST DRIVE FROM THE START", "start"],
	["TEST DRIVE FROM HERE", "here"], ["WATCH A BOT LAP", "watch"], ["TEST DRIVE OPTIONS", "options"],
	["VIEW", "view"], ["UNDO", "undo"], ["REDO", "redo"], ["SAVE", "save"], ["HOST ONLINE WITH THIS TRACK", "host"],
	["TRACK PROPERTIES", "props"], ["SET THUMBNAIL FROM CAMERA", "thumb"], ["HELP", "help"],
	["EXIT TO TRACK EDITOR", "exit_home"], ["EXIT TO MAIN MENU", "exit_menu"]]
const VIEW := [["TOP VIEW", "ed_top"], ["RACING LINE", "ed_line"], ["GO TO START", "ed_home"], ["FRAME TRACK", "ed_frame_all"]]
## Each entry's icon (EditorKit.icon names; TOOL shows the tool in hand).
const ICONS := {"resume": "play", "start": "drive", "here": "pin", "watch": "eye", "options": "sliders", "view": "frame_all",
	"undo": "undo", "redo": "redo", "save": "save", "host": "online", "props": "tag", "thumb": "image", "help": "help",
	"exit_home": "exit", "exit_menu": "home", "ed_top": "top_view", "ed_line": "route", "ed_home": "flag",
	"ed_frame_all": "frame_all", "back": "undo"}
const ICON_PX := 22

var editor: TrackEditor
## "main" | "tool" | "options" | "view"
var page := "main"
## The buttons of the page shown, top to bottom.
var items: Array[Button] = []
var _page_box: VBoxContainer


func _init(ed: TrackEditor = null) -> void:
	super("EDITOR MENU", Vector2(600, 700))
	editor = ed
	_page_box = VBoxContainer.new()
	_page_box.add_theme_constant_override("separation", 4)
	_page_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_page_box)
	set_prompts([["{ui_accept} SELECT"], ["{ui_cancel} BACK"]])
	show_page("main")


func _ready() -> void:
	if default_focus != null:
		default_focus.grab_focus.call_deferred()


## Shows a page; the focus goes to its first entry (to the entry it came from on the way back).
func show_page(p: String) -> void:
	var back_to := page
	page = p
	for c in _page_box.get_children():
		_page_box.remove_child(c)
		c.queue_free()
	items.clear()
	match p:
		"tool":
			title_label.text = "TOOL"
			var cur := editor.tool.id if editor != null and editor.tool != null else ""
			for id in TrackEditor.TOOL_IDS:
				var tid: String = id
				var key := InputPrompts.action_text("ed_tool_" + id, "keyboard")
				var b := _item("%s   %s%s" % [EditorUI.TOOL_NAMES.get(id, id.to_upper()), key, "   (NOW)" if id == cur else ""], func() -> void: _pick_tool(tid),
					str(EditorKit.TOOL_ICONS.get(id, "")))
				if id == cur:
					default_focus = b
		"options":
			title_label.text = "TEST DRIVE OPTIONS"
			var st := EditorSession.test_options({})
			_page_box.add_child(UiKit.row("BOTS", UiKit.slider(0, 7, 1, st.bots, func(x: float) -> void: EditorUI._test_set("bots", int(x)), "%d", 200), 220))
			_page_box.add_child(UiKit.row("LAPS", UiKit.slider(1, 9, 1, st.laps, func(x: float) -> void: EditorUI._test_set("laps", int(x)), "%d", 200), 220))
			_page_box.add_child(UiKit.row("HAZARDS", UiKit.toggle(int(st.hazards) == 1, func(on: bool) -> void: EditorUI._test_set("hazards", 1 if on else 0)), 220))
			_page_box.add_child(UiKit.row("DIFFICULTY", UiKit.segmented(EditorUI.DIFFS, int(st.difficulty), func(i: int) -> void: EditorUI._test_set("difficulty", i)), 220))
			for c in _page_box.find_children("*", "Control", true, false):
				var cc := c as Control
				if (cc is Slider or cc is BaseButton) and cc.focus_mode != Control.FOCUS_NONE:
					cc.focus_mode = Control.FOCUS_ALL
			var first := _page_box.find_children("*", "HSlider", true, false)
			default_focus = first[0] if not first.is_empty() else null
			_item("BACK", func() -> void: show_page("main"), ICONS.back)
			if default_focus == null and not items.is_empty():
				default_focus = items[0]
		"view":
			title_label.text = "VIEW"
			for e in VIEW:
				var act: String = e[1]
				_item("%s   %s" % [e[0], EditorKit.plain("{%s}" % act)], func() -> void: _act(act), str(ICONS.get(act, "")))
			default_focus = items[0]
		_:
			title_label.text = "EDITOR MENU"
			var h := editor.history if editor != null else null
			for e in MAIN:
				var id: String = e[1]
				var text: String = e[0]
				# UNDO / REDO name their step; with none they are greyed
				if id == "undo" and h != null and h.can_undo():
					text = "UNDO " + h.undo_name()
				elif id == "redo" and h != null and h.can_redo():
					text = "REDO " + h.redo_name()
				var ic := str(ICONS.get(id, ""))
				if id == "tool" and editor != null and editor.tool != null:
					ic = str(EditorKit.TOOL_ICONS.get(editor.tool.id, ""))
				var b := _item(text, func() -> void: press(id), ic)
				if id == "undo" or id == "redo":
					b.disabled = h == null or not (h.can_undo() if id == "undo" else h.can_redo())
				if id == back_to:
					default_focus = b
			if back_to == "main" or default_focus == null or not items.has(default_focus):
				default_focus = items[0]
	if is_inside_tree() and default_focus != null:
		default_focus.grab_focus.call_deferred()


## An entry; with an icon (EditorKit.icon names) before its text, tinted like the text.
func _item(text: String, cb: Callable, icon_name := "") -> Button:
	var b := UiKit.menu_item(text)
	b.add_theme_font_size_override("font_size", ITEM_FONT)
	if icon_name != "":
		b.icon = EditorKit.icon(icon_name, ICON_PX)
		b.add_theme_constant_override("h_separation", 12)
		for k in [["icon_normal_color", UiKit.MENU_IDLE], ["icon_hover_color", Color.WHITE], ["icon_focus_color", Color.WHITE],
				["icon_pressed_color", UiKit.PRESSED], ["icon_hover_pressed_color", UiKit.PRESSED], ["icon_disabled_color", Color(1, 1, 1, 0.25)]]:
			b.add_theme_color_override(k[0], k[1])
	b.pressed.connect(cb)
	_page_box.add_child(b)
	items.append(b)
	return b


## A main-page entry by id (the pad's A, a click, tests).
func press(id: String) -> void:
	match id:
		"tool", "options", "view":
			show_page(id)
			return
	var e := editor
	var ui := e.ui if e != null else null
	close()
	if e == null:
		return
	match id:
		"start":
			e.test_drive("start")
		"here":
			e.test_drive("here", e.free_center())
		"watch":
			e.test_drive("watch")
		"undo":
			if ui != null:
				ui.run_action("ed_undo")
		"redo":
			if ui != null:
				ui.run_action("ed_redo")
		"thumb":
			if ui != null:
				ui.set_thumbnail()
		"save":
			if ui != null:
				ui.save_named()
			else:
				e.save()
		"host":
			if ui != null:
				ui.host_online()
		"props":
			if ui != null:
				ui._open_properties()
		"help":
			if ui != null:
				ui.open_help()
		"exit_home":
			if ui != null:
				ui.request_exit("home")
		"exit_menu":
			if ui != null:
				ui.request_exit("menu")


func _pick_tool(id: String) -> void:
	var e := editor
	close()
	if e != null:
		e.set_tool(id)


func _act(action: String) -> void:
	var e := editor
	close()
	if e != null and e.ui != null:
		e.ui.run_action(action)


func _unhandled_input(event: InputEvent) -> void:
	# B on a page goes back to the main page; on the main page it closes the menu
	if page != "main" and is_top() and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")):
		get_viewport().set_input_as_handled()
		Game.play_ui("res://assets/sound/ui/buttonclickrelease.wav", -5.0)
		show_page("main")
		return
	super(event)
