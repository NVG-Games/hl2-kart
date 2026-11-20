extends RefCounted
## editor/case_layout (P10, CI): the editor's screen at the three window shapes of ui_fit (1600 x
## 900, 1280 x 1024, 2560 x 1080): no control outside the window or squeezed below its minimum
## (ui_fit's rule: scroll contents and clipped labels aside), with the validation drawer, a card,
## a toast and the EDITOR MENU up; the free area between the panels is 1.3's (240 / 380 / 44 /
## 30, 980 x 826 centred at (730, 457) on 1600 x 900) and is TrackEditor.free_rect(). Every tool's
## TOOL OPTIONS fit the column, show a scroll bar that can be grabbed and cut no text.

const NEEDS_CONTENT := false
const Sel := preload("res://tests/editor/case_select.gd")
const SHAPES := [Vector2i(1600, 900), Vector2i(1280, 1024), Vector2i(2560, 1080)]
const CANVAS := [Vector2(1600, 900), Vector2(1600, 1280), Vector2(2133.33, 900)]


func run(t: Node) -> void:
	var root: Window = t.get_tree().root
	var size0 := root.size
	var ed: TrackEditor = await Sel.open_editor(t, Sel.test_doc())
	var ui := ed.ui
	ui.set_report(_report())
	ui.toggle_validation()
	await t.wait(0.3)
	ui.show_card("PREPARING TEST DRIVE...")
	ui.toast("Back from the test drive: best lap 1:02.4, 0 rescues")
	ed.select(PackedInt32Array([int(ed.doc.data.props[0].uid)]))
	for i in SHAPES.size():
		root.size = SHAPES[i]
		await t.frames(4)
		var vr := ed.get_viewport().get_visible_rect()
		t.check(absf(vr.size.x - CANVAS[i].x) <= 1.0 and absf(vr.size.y - CANVAS[i].y) <= 1.0,
			"%s: the canvas is %s (%s)" % [str(SHAPES[i]), str(CANVAS[i]), str(vr.size)])
		var bad := problems(ed.get_node("UI"), vr)
		t.check(bad.is_empty(), "%s: no control outside the window or squeezed (%d: %s)" % [str(SHAPES[i]), bad.size(), str(bad.slice(0, 6))])
		# the free area is what the panels leave
		var fr := ed.free_rect()
		var want := Rect2(240, 44, vr.size.x - 620, vr.size.y - 74)
		t.check(fr.position.is_equal_approx(want.position) and fr.size.is_equal_approx(want.size), "%s: free_rect %s = %s" % [str(SHAPES[i]), str(fr), str(want)])
		var l := ui.left.get_global_rect()
		var r := ui.right.get_global_rect()
		var top := ui.top_bar.get_global_rect()
		var st := ui.status_bar.get_global_rect()
		t.check(is_equal_approx(l.end.x, fr.position.x) and is_equal_approx(r.position.x, fr.end.x)
			and is_equal_approx(top.end.y, fr.position.y) and is_equal_approx(st.position.y, fr.end.y),
			"%s: the panels frame the free area (left %s, right %s, top %s, status %s)" % [str(SHAPES[i]), str(l), str(r), str(top), str(st)])
		t.check(is_equal_approx(l.size.x, 240.0) and is_equal_approx(r.size.x, 380.0) and is_equal_approx(top.size.y, 44.0) and is_equal_approx(st.size.y, 30.0),
			"%s: left 240 and right 380 wide, top 44 and status 30 tall" % str(SHAPES[i]))
		var drawer := ui.drawer.get_global_rect()
		t.check(fr.encloses(drawer), "%s: the validation drawer sits in the free area (%s)" % [str(SHAPES[i]), str(drawer)])
		t.check(fr.encloses(ui.card_panel.get_global_rect()) and fr.encloses(ui.toasts.get_global_rect()), "%s: the card and the toasts sit in the free area" % str(SHAPES[i]))
		t.log("%s: top bar needs %d of %d px, palette %d px tall, status hints %d entries" % [str(SHAPES[i]),
			int(ui.top_bar.get_child(0).get_combined_minimum_size().x), int(top.size.x), int(ui.palette.size.y), ui.hints_bar.get_child_count()])
		if i == 0:
			t.check(fr.size.is_equal_approx(Vector2(980, 826)) and fr.get_center().is_equal_approx(Vector2(730, 457)), "1600 x 900: 980 x 826 centred at (730, 457) (%s)" % str(fr.get_center()))
		# the EDITOR MENU fits too
		ui.open_menu()
		await t.frames(3)
		bad = problems(ed.get_node("UI"), vr)
		t.check(bad.is_empty(), "%s: the EDITOR MENU fits (%d: %s)" % [str(SHAPES[i]), bad.size(), str(bad.slice(0, 6))])
		if ui.menu != null:
			ui.menu.close()
		await t.frames(2)
	root.size = size0
	await t.frames(2)
	ui.toggle_validation()
	ui.hide_card()
	await _tools(t, ed)
	await Sel.close_editor(t, ed)


## Every tool's TOOL OPTIONS at 1600 x 900 (nothing selected, then its kind selected): the contents
## fit the column's width, a scroll bar that shows is at least 6 px wide, no button or clipped
## label cuts its text (its tooltip has it whole).
func _tools(t: Node, ed: TrackEditor) -> void:
	var root: Window = t.get_tree().root
	var size0 := root.size
	root.size = SHAPES[0]
	var ui := ed.ui
	ed.selection.clear()
	for id in TrackEditor.TOOL_IDS:
		ed.set_tool(id)
		await t.frames(4)
		var sc := ui.options_scroll
		var vb := sc.get_v_scroll_bar()
		var room := sc.size.x - (vb.size.x if vb.visible else 0.0)
		var want := ui.options_box.get_combined_minimum_size().x
		var col := ui.right.get_global_rect()
		t.check(want <= room + 0.5 and sc.get_global_rect().end.x <= col.end.x - 1.0,
			"%s: the options fit the column's width (want %d, room %d, the scroll ends at %d of %d)" % [id, int(want), int(room), int(sc.get_global_rect().end.x), int(col.end.x)])
		t.check(not vb.visible or vb.size.x >= 6.0, "%s: the options' scroll bar can be seen and grabbed (%s)" % [id, str(vb.size)])
		var cut := cut_texts(ui.options_box)
		t.check(cut.is_empty(), "%s: no option text is cut (%d: %s)" % [id, cut.size(), str(cut.slice(0, 6))])
		var edge := col.end.x + 0.5
		var out := []
		for c in ui.options_box.find_children("*", "Control", true, false):
			var ctl := c as Control
			if ctl.is_visible_in_tree() and ctl.get_global_rect().end.x > edge:
				out.append(_name(ctl))
		t.check(out.is_empty(), "%s: nothing runs past the column (%s)" % [id, str(out.slice(0, 4))])
	# an inspector of each kind the test track has
	var d := ed.doc.data
	for pair in [["objects", int(d.props[0].uid)], ["objects", int(d.lights[0].uid)], ["items", int(d.pads[0].uid)]]:
		ed.set_tool(pair[0])
		ed.select(PackedInt32Array([pair[1]]))
		await t.frames(3)
		ui.inspector.rebuild()
		await t.frames(2)
		var cut := cut_texts(ui.inspector.box)
		t.check(cut.is_empty(), "%s inspector of %s: no text is cut (%d: %s)" % [pair[0], ed.kind_of(pair[1]), cut.size(), str(cut.slice(0, 6))])
	ed.selection.clear()
	ed.set_tool("select")
	root.size = size0
	await t.frames(2)


## Buttons and clipped labels under n whose text is wider than they are (a list button that trims
## with an ellipsis and has its whole text in the tooltip aside).
static func cut_texts(n: Node) -> Array:
	var bad := []
	for c in n.find_children("*", "Control", true, false):
		var ctl := c as Control
		if not ctl.is_visible_in_tree():
			continue
		var txt := ""
		var pad := 0.0
		if ctl is Button and not (ctl is OptionButton):
			var b := ctl as Button
			txt = b.text
			var sb := b.get_theme_stylebox("normal")
			pad = sb.get_content_margin(SIDE_LEFT) + sb.get_content_margin(SIDE_RIGHT) if sb != null else 0.0
			if b.icon != null:
				pad += b.icon.get_width() + b.get_theme_constant("h_separation")
		elif ctl is Label and (ctl as Label).clip_text:
			txt = (ctl as Label).text
		if txt == "":
			continue
		var f := ctl.get_theme_font("font")
		var fs := ctl.get_theme_font_size("font_size")
		var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + pad if f != null else 0.0
		var trims := ctl is Button and (ctl as Button).text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING \
			and ctl.tooltip_text.find(txt.strip_edges()) >= 0
		if w > ctl.size.x + 1.0 and not trims:
			bad.append("%s needs %d of %d" % [_name(ctl), int(w), int(ctl.size.x)])
	return bad


## A report with long texts, every level and some fixes.
static func _report() -> LevelReport:
	var r := LevelReport.new()
	r.warning("no_items", LevelValidate.text("no_items", {}), {"s": 10.0}, "auto_items")
	r.error("too_tight", "The bend 412 m after the start is too tight for a 14 m road: drag its point outward or narrow the road ({ed_mod_ctrl} + wheel).", {"s": 412.0}, "narrow")
	r.error("outside", "The road leaves the world 1200 m after the start: drag the point back inside, or make the world bigger (TERRAIN > RESIZE WORLD).", {"s": 1200.0})
	r.warning("budget", "Past the budget for props (1600 of 1500): slow PCs may stutter.", {})
	r.info("bot_lap", "BOT LAP 1:23.4, 0 RESCUES", {})
	return r


## ui_fit's rule over every visible control under `n`: OUTSIDE (meets the window but is not
## inside it) or SQUEEZED (smaller than its minimum); scroll contents, scroll bars and clipped
## labels' widths aside.
static func problems(n: Node, vr: Rect2) -> Array:
	var bad := []
	for c in n.find_children("*", "Control", true, false):
		var ctl := c as Control
		if not ctl.is_visible_in_tree() or ctl is ScrollBar or _inside_scroll(ctl):
			continue
		var r := ctl.get_global_rect()
		if r.size.x < 1 or r.size.y < 1:
			continue
		if not vr.grow(1.0).encloses(r) and r.intersects(vr):
			bad.append("OUTSIDE %s %s" % [_name(ctl), str(r)])
		var m := ctl.get_combined_minimum_size()
		if ctl is Label and (ctl as Label).clip_text:
			m.x = 0
		if ctl.size.x + 1 < m.x or ctl.size.y + 1 < m.y:
			bad.append("SQUEEZED %s size %s < min %s" % [_name(ctl), str(ctl.size), str(m)])
	return bad


static func _inside_scroll(c: Node) -> bool:
	var p := c.get_parent()
	while p:
		if p is ScrollContainer:
			return true
		p = p.get_parent()
	return false


static func _name(c: Control) -> String:
	var s := "%s:%s" % [c.get_class(), c.name]
	if c is Label:
		s += " '%s'" % (c as Label).text.left(30)
	elif c is Button:
		s += " '%s'" % (c as Button).text.left(30)
	return s
