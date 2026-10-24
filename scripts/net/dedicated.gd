class_name DedicatedConsole
extends Node
## Dedicated server console (headless). Lives under the Net autoload and reads
## commands from stdin like the srcds console: status, say, kick, start,
## lobby, set <rule> <value>, quit.

var _thread: Thread
var _quit := false
var _status_t := 0.0


func _ready() -> void:
	name = "Console"
	_thread = Thread.new()
	_thread.start(_read_stdin)
	print("type 'help' for commands")


func _read_stdin() -> void:
	while not _quit:
		var line := OS.read_string_from_stdin(1024)
		if line == "":
			OS.delay_msec(200)
			continue
		for l in line.split("\n", false):
			_command.call_deferred(l.strip_edges())


func _process(delta: float) -> void:
	_status_t += delta
	if _status_t > 300.0:
		_status_t = 0.0
		print("[%s] %d/%d players, %s" % [Time.get_time_string_from_system(), Net.humans(), Net.cfg["max_players"], Net.state])


func _command(line: String) -> void:
	if line == "":
		return
	var parts := line.split(" ", false)
	var cmd := parts[0].to_lower()
	var rest := line.substr(parts[0].length()).strip_edges()
	match cmd:
		"help":
			print("status | say <text> | kick <nick> | start | lobby | set <rule> <value> | rules | quit")
			print("rules: hostname maxplayers bot_fill bot_grid mp_laps mp_difficulty mp_weather sv_password")
		"status":
			var info := Net.server_info()
			print("hostname: %s\nstate   : %s\nplayers : %d/%d" % [info["name"], info["state"], info["players"], info["max"]])
			for id in Net.players:
				var p: Dictionary = Net.players[id]
				print("  #%d %-24s %4d ms  %s%s" % [id, p["nick"], p["ping"], p["character"], "  READY" if p["ready"] else ""])
			for a in Net.local_addresses():
				print("  address %s:%d" % [a, Net.cfg["port"]])
		"say":
			Net.say(rest)
		"kick":
			for id in Net.players:
				if Net.players[id]["nick"].to_lower() == rest.to_lower():
					Net.kick(id)
					return
			print("no player named ", rest)
		"start":
			Net.start_race_now()
		"lobby":
			Net.back_to_lobby()
		"rules":
			print(Net.cfg)
		"set":
			if parts.size() < 3:
				print("set <rule> <value>")
				return
			var key: String = DedicatedConfig.CVARS.get(parts[1].to_lower(), parts[1].to_lower())
			var o := {}
			if not DedicatedConfig.set_option(o, key, line.substr(line.find(parts[1]) + parts[1].length()).strip_edges()):
				print("bad value")
				return
			for k in o:
				Net.set_rule(k, o[k])
			print("%s = %s" % [key, o.get(key, "")])
		"quit", "exit":
			_quit = true
			Net.leave()
			get_tree().quit()
		_:
			print("unknown command: ", cmd)


func _exit_tree() -> void:
	_quit = true
