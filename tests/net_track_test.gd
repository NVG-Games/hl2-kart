extends "res://tests/level_test.gd"
## Headless runner of the custom-track sharing tests (9.1, 9.3).
##   -- unit [ci] [only <name>]: every tests/net/case_*.gd, alphabetically, with level_test's t API
##      (see tests/level_test.gd); prints "net_track_test: N checks, F failures", exits 1 on any.
##   -- pair <port> ... / -- client <port> ...: hands the process to tests/net/pair.gd (P9) when it
##      exists. pair.gd extends Node; the runner calls its setup(mode: String, args:
##      PackedStringArray) (args: everything after the mode) and adds it under /root, where it
##      survives scene changes; it ends the process itself with its own exit code.
## Ports: 27300-27310.
## usage: godot --headless --path . res://tests/net_track_test.tscn -- unit
##        godot --headless --path . res://tests/net_track_test.tscn -- pair 27301

const PAIR := "res://tests/net/pair.gd"


func suite() -> Dictionary:
	return {"name": "net_track_test", "dir": "res://tests/net"}


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var mode: String = args[0].trim_prefix("--") if args.size() > 0 else "unit"
	if mode == "pair" or mode == "client":
		if not ResourceLoader.exists(PAIR):
			print("net_track_test: %s is not there yet" % PAIR)
			get_tree().quit(1)
			return
		var scr = load(PAIR)
		if scr == null or not (scr is GDScript) or not (scr as GDScript).can_instantiate():
			print("net_track_test: %s does not compile" % PAIR)
			get_tree().quit(1)
			return
		var node = scr.new()
		node.name = "NetPair"
		if node.has_method("setup"):
			node.setup(mode, args.slice(1))
		get_tree().root.add_child.call_deferred(node)
		return
	# unit (the default): the case runner, without the mode word
	var rest: PackedStringArray = args.slice(1) if args.size() > 0 and mode == "unit" else args
	get_tree().root.add_child.call_deferred(Runner.new(suite(), rest))
