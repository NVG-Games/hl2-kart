extends Node
## Layout check for every menu screen: lists controls that stick out of the
## window or are squeezed below their minimum size, and saves a screenshot of
## each screen. Run at a few window shapes (1600x900, 1280x1024, 2560x1080): --resolution with a
## window, or the optional second argument, which also works headless (it sizes the root window:
## 1280x720 gives a 1600x900 canvas, 1280x1024 1600x1280, 2560x1080 2133x900). Headless the
## screenshots fail to save (no renderer): harmless.
## usage: godot --path . --resolution 1600x900 res://tests/ui_fit.tscn -- <out_prefix> [WxH]


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	get_tree().root.add_child.call_deferred(Runner.new(args[0] if args.size() > 0 else "ui_fit", args[1] if args.size() > 1 else ""))


class Runner:
	extends Node
	var out := ""
	var win := Vector2i.ZERO  # the root window's size to test at (ZERO: as it is)
	var problems := 0

	func _init(o: String, size_arg := "") -> void:
		out = o
		var p := size_arg.to_lower().split("x")
		if p.size() == 2 and p[0].is_valid_int() and p[1].is_valid_int():
			win = Vector2i(int(p[0]), int(p[1]))
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _check(screen: String) -> void:
		await get_tree().create_timer(0.7).timeout
		var vr := get_viewport().get_visible_rect()
		var bad := []
		for c in get_tree().root.find_children("*", "Control", true, false):
			var ctl := c as Control
			if not ctl.is_visible_in_tree() or ctl is ScrollBar or ctl.get_parent() is ScrollContainer:
				continue
			if _inside_scroll(ctl):
				continue
			var r := ctl.get_global_rect()
			if r.size.x < 1 or r.size.y < 1:
				continue
			var grow := vr.grow(1.0)
			if not grow.encloses(r) and r.intersects(vr) and not ctl.get_meta("bleed", false):
				var kids := ""
				if ctl is Container:
					for k in ctl.get_children():
						if k is Control and (k as Control).visible:
							kids += " | %s min %s" % [_name(k), (k as Control).get_combined_minimum_size()]
				bad.append("OUTSIDE %s %s%s" % [_name(ctl), r, kids])
			var m := ctl.get_combined_minimum_size()
			if ctl is Label and (ctl as Label).clip_text:
				m.x = 0
			if ctl.size.x + 1 < m.x or ctl.size.y + 1 < m.y:
				bad.append("SQUEEZED %s size %s < min %s" % [_name(ctl), ctl.size, m])
		print("[%s] viewport %s: %d problems" % [screen, vr.size, bad.size()])
		for b in bad.slice(0, 12):
			print("    ", b)
		problems += bad.size()
		var img := get_viewport().get_texture().get_image()
		if img:
			img.save_png("%s_%s.png" % [out, screen])

	func _inside_scroll(c: Node) -> bool:
		var p := c.get_parent()
		while p:
			if p is ScrollContainer:
				return true
			p = p.get_parent()
		return false

	func _name(c: Control) -> String:
		var s := "%s:%s" % [c.get_class(), c.name]
		if c is Label:
			s += " '%s'" % (c as Label).text.left(30)
		elif c is Button:
			s += " '%s'" % (c as Button).text.left(30)
		return s

	func _ready() -> void:
		Game.settings["tutorial_seen"] = true
		if win != Vector2i.ZERO:
			get_tree().root.size = win
			await get_tree().process_frame
		print("window %s, canvas %s" % [get_tree().root.size, get_viewport().get_visible_rect().size])
		get_tree().change_scene_to_file("res://scenes/main.tscn")
		await get_tree().create_timer(1.5).timeout
		var menu: Node = get_tree().current_scene
		await _check("main")
		menu._open_setup()
		await _check("setup")
		print("  rects: root ", menu.root.get_global_rect(), " setup ", menu.setup.get_global_rect(), " margin ", menu.setup.get_child(2).get_global_rect())
		menu.setup.back.emit()
		var o := OptionsPanel.new()
		menu._open(o)
		for i in o.pages.size():
			o._show_tab(i)
			await _check("options_%d" % i)
		o.close()
		var h := HowToPlay.new()
		menu._open(h)
		for i in h.pages.size():
			h._show(i)
			await _check("howto_%d" % i)
		h.close()
		menu._open(SoundtrackPanel.new())
		await _check("soundtrack")
		menu.dialog.close()
		menu._open_browser()
		await _check("browser")
		menu.dialog.close()
		menu._open_create()
		await _check("create")
		Game.settings["host_port"] = 27290
		Game.settings["host_upnp"] = false
		(menu.dialog as CreateServer)._start()
		await get_tree().create_timer(1.0).timeout
		await _check("lobby")
		Net.leave()
		print("TOTAL PROBLEMS ", problems)
		get_tree().quit()
