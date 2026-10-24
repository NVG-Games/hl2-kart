extends Node
## Screenshots of every menu screen (main, new race, options tabs, how to play, soundtrack).

var out := ""


func _shot(name: String) -> void:
	await get_tree().create_timer(0.6).timeout
	get_viewport().get_texture().get_image().save_png("%s_%s.png" % [out, name])


func _ready() -> void:
	out = OS.get_cmdline_user_args()[0]
	Game.settings["tutorial_seen"] = true
	var menu: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(menu)
	await get_tree().create_timer(1.2).timeout
	await _shot("main")
	menu._open_setup()
	await _shot("setup")
	# a big vehicle and one of the new racers, to check the preview framing
	menu.setup._pick_racer(8)
	menu.setup._pick_vehicle(2)
	await _shot("setup_apc")
	menu.setup._pick_racer(10)
	menu.setup._pick_vehicle(5)
	await _shot("setup_tub")
	menu.setup._pick_racer(0)
	menu.setup._pick_vehicle(0)
	menu.setup.back.emit()
	var o := OptionsPanel.new()
	menu._open(o)
	await _shot("options_audio")
	o.tabs.current_tab = 1
	await _shot("options_video")
	o.tabs.current_tab = 2
	await _shot("options_game")
	o.close()
	var h := HowToPlay.new()
	menu._open(h)
	for i in 4:
		h.tabs.current_tab = i
		await _shot("howto_%d" % i)
	h.close()
	menu._open(SoundtrackPanel.new())
	await _shot("soundtrack")
	get_tree().quit()
