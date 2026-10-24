extends Node
## Listen-server walkthrough with screenshots: CREATE SERVER, FIND SERVERS
## (LAN finds our own server), lobby with a joined friend, the online race and
## its results. Run a net_client.tscn against port 27200 alongside.
## usage: godot --path . res://tests/net_host_shot.tscn -- <out_prefix> [track]


func _ready() -> void:
	get_tree().root.add_child.call_deferred(Runner.new(OS.get_cmdline_user_args()[0]))


class Runner:
	extends Node
	var out := ""
	var t := 0.0
	var shots := {}

	func _init(o: String) -> void:
		out = o
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _shot(n: String) -> void:
		await get_tree().create_timer(0.5).timeout
		get_viewport().get_texture().get_image().save_png("%s_%s.png" % [out, n])
		print("shot ", n)

	func _menu() -> Node:
		return get_tree().current_scene

	func _ready() -> void:
		Game.settings["tutorial_seen"] = true
		Game.settings["nickname"] = "Host"
		Game.settings["character"] = "gordon"
		Game.settings["vehicle"] = "buggy"
		Game.settings["host_port"] = 27200
		Game.settings["host_name"] = "City 17 GP"
		Game.settings["host_max_players"] = 4
		Game.settings["host_grid"] = 6
		Game.settings["host_upnp"] = false
		Game.settings["laps"] = 1
		var args := OS.get_cmdline_user_args()
		if args.size() > 1:
			Game.settings["track"] = args[1]
		get_tree().change_scene_to_file("res://scenes/main.tscn")
		await get_tree().create_timer(1.5).timeout
		_menu()._open_create()
		await _shot("create")
		(_menu().dialog as CreateServer)._start()
		await get_tree().create_timer(1.0).timeout
		_menu()._open_browser()
		await get_tree().create_timer(3.0).timeout
		await _shot("browser")
		(_menu().dialog as Dialog).close()
		Net.chat_received.connect(func(n, txt, k): print("CHAT ", n, ": ", txt))
		while Net.players.size() < 2:
			await get_tree().create_timer(0.5).timeout
		Net.say("gl hf, first to the canal buys the melons")
		await get_tree().create_timer(2.5).timeout
		await _shot("lobby")
		Net.autodrive = true
		var lobby: Lobby = _menu().lobby
		lobby.ready_button.button_pressed = true
		while Net.state != "race":
			await get_tree().create_timer(0.3).timeout
		while Net.race == null or Net.race._phase == "wait":
			await get_tree().create_timer(0.3).timeout
		await get_tree().create_timer(5.2).timeout
		await _shot("countdown")
		await get_tree().create_timer(10.0).timeout
		await _shot("race1")
		await get_tree().create_timer(14.0).timeout
		await _shot("race2")
		while Net.results.is_empty():
			await get_tree().create_timer(0.5).timeout
		await get_tree().create_timer(1.5).timeout
		await _shot("results")
		while Net.state != "lobby":
			await get_tree().create_timer(0.5).timeout
		await get_tree().create_timer(2.0).timeout
		await _shot("lobby_after")
		Net.leave()
		get_tree().quit()

	func _process(delta: float) -> void:
		t += delta
		if t > 260.0:
			print("TIMEOUT")
			get_tree().quit(3)
