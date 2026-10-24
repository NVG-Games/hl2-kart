extends Node
## Headless network client for tests: finds servers (LAN + master), joins,
## readies up, races with --autodrive and logs positions for sync checks.
## usage: godot --headless --path . res://tests/net_client.tscn -- --autodrive
##        <address> <port> <nick> <character> <vehicle> <seconds> [master]


func _ready() -> void:
	get_tree().root.add_child.call_deferred(Runner.new(OS.get_cmdline_user_args()))


class Runner:
	extends Node
	var args: PackedStringArray
	var t := 0.0
	var log_t := 0.0
	var raced := false
	var limit := 240.0
	var password := ""

	func _init(a: PackedStringArray) -> void:
		args = a
		var plain := []
		var skip := false
		for i in a.size():
			var x := a[i]
			if skip:
				skip = false
			elif x == "--fakelag":
				skip = true
			elif x == "--password" and i + 1 < a.size():
				password = a[i + 1]
				skip = true
			elif not x.begins_with("--"):
				plain.append(x)
		args = PackedStringArray(plain)
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _ready() -> void:
		var nick := args[2] if args.size() > 2 else "Tester"
		Game.settings["nickname"] = nick
		Game.settings["character"] = args[3] if args.size() > 3 else "alyx"
		Game.settings["vehicle"] = args[4] if args.size() > 4 else "buggy"
		limit = float(args[5]) if args.size() > 5 else 240.0
		var f := ServerFinder.new()
		add_child(f)
		f.found.connect(func(i: Dictionary):
			print("FOUND %s at %s:%d players %d/%d state '%s' ping %d ms" % [i["name"], i["address"], int(i["port"]), int(i["players"]), int(i["max"]), i["state"], int(i["ping"])]))
		f.master_failed.connect(func(r): print("MASTER FAILED ", r))
		f.scan_lan()
		if args.size() > 6:
			f.fetch_master(args[6])
		await get_tree().create_timer(2.0).timeout
		Net.joined.connect(func():
			print("JOINED as ", Net.my_id())
			Net.set_profile(Game.settings["character"], Game.settings["vehicle"], true))
		Net.connect_failed.connect(func(r): print("CONNECT FAILED ", r); get_tree().quit(2))
		Net.left.connect(func(r): print("LEFT ", r))
		Net.chat_received.connect(func(n, txt, k): print("CHAT [%s] %s %s" % [k, n, txt]))
		Net.state_changed.connect(func(s):
			print("STATE ", s)
			if s == "race":
				raced = true
			elif s == "lobby" and raced:
				print("RESULTS ", Net.results.map(func(e): return "%s %.2f" % [e["nick"], e["time"]]))
				get_tree().create_timer(1.0).timeout.connect(func():
					Net.leave()
					get_tree().quit()))
		Net.join(args[0], int(args[1]), password)

	func _process(delta: float) -> void:
		t += delta
		if t > limit:
			print("TIMEOUT")
			get_tree().quit(3)
		log_t -= delta
		if log_t <= 0.0 and Net.race and is_instance_valid(Net.race) and Net.race.get("karts"):
			log_t = 0.25
			for k in Net.race.karts:
				var p: Vector3 = k.global_position
				print("SYNC %.3f %d %s %.2f %.2f %.2f %s" % [Net.now(), k.net_slot, "own" if not k.remote else "view", p.x, p.y, p.z, Kart.State.keys()[k.state]])
