extends Node
## Headless runner of the level cases (9.1): loads every tests/level/case_*.gd alphabetically and
## runs it. A case is `extends RefCounted` with `const NEEDS_CONTENT := false` and
## `func run(t: Node) -> void` (it may await); `t` offers check(ok, what), content(), tmp(name),
## frames(n), fail(what), ms(callable) and a few helpers (near, wait, log, args, ci).
## The runner lives under /root (it survives scene changes), restores Game.settings after each
## case, counts script errors raised while a case runs as failures, and stops a case that hangs
## (a case may set `const TIMEOUT := <seconds>`, default 300).
## Prints "level_test: N checks, F failures"; exits 1 on any failure.
## usage: godot --headless --path . res://tests/level_test.tscn [-- ci] [-- only <name>[,<name>...]]
##   ci: skips the NEEDS_CONTENT cases; only: runs the named cases ("skeleton" or "case_skeleton").


## The suite this scene runs: its name (summary line, tmp folder) and its case folder.
func suite() -> Dictionary:
	return {"name": "level_test", "dir": "res://tests/level"}


func _ready() -> void:
	get_tree().root.add_child.call_deferred(Runner.new(suite(), OS.get_cmdline_user_args()))


## Counts script errors (from any thread) so a case that hits one fails instead of passing quietly.
class ErrorTap:
	extends Logger
	var _mutex := Mutex.new()
	var script_errors := 0
	var last := ""

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_SCRIPT:
			return
		_mutex.lock()
		script_errors += 1
		last = "%s (%s:%d)" % [rationale if rationale != "" else code, file.get_file(), line]
		_mutex.unlock()

	func _log_message(message: String, error: bool) -> void:
		pass

	func count() -> int:
		_mutex.lock()
		var n := script_errors
		_mutex.unlock()
		return n


class Runner:
	extends Node
	const DEFAULT_TIMEOUT := 300.0

	var suite_name := ""
	var dir := ""
	var args := PackedStringArray()
	## -- ci: content cases are skipped.
	var ci := false
	var only := PackedStringArray()
	## The case running now ("case_skeleton").
	var case_name := ""
	var checks := 0
	var failures := 0
	var _case_checks := 0
	var _case_failures := 0
	var _tap: ErrorTap
	var _case_token := 0

	func _init(s: Dictionary, user_args: PackedStringArray) -> void:
		name = "TestRunner"
		process_mode = Node.PROCESS_MODE_ALWAYS
		suite_name = str(s.get("name", "test"))
		dir = str(s.get("dir", ""))
		args = user_args
		var i := 0
		while i < args.size():
			var a := args[i].trim_prefix("--")
			if a == "ci":
				ci = true
			elif a == "only" and i + 1 < args.size():
				i += 1
				for n in args[i].split(",", false):
					only.append(n.strip_edges().trim_prefix("case_").trim_suffix(".gd"))
			i += 1

	func _ready() -> void:
		_tap = ErrorTap.new()
		OS.add_logger(_tap)
		_run_all()

	# ------------------------------------------------------------ the t API

	func check(ok: bool, what: String) -> void:
		checks += 1
		_case_checks += 1
		if not ok:
			failures += 1
			_case_failures += 1
			print("FAIL: [%s] %s" % [case_name, what])

	func fail(what: String) -> void:
		check(false, what)

	## HL2 content is installed (Game.models loaded).
	func content() -> bool:
		var g := get_node_or_null("/root/Game")
		return g != null and not (g.get("models") as Dictionary).is_empty()

	## A scratch path under user://<suite>/ (the folder is made; files there are kept between runs).
	func tmp(file_name: String) -> String:
		var base := "user://%s" % suite_name
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(base))
		return base + "/" + file_name

	func frames(n: int) -> void:
		for i in n:
			await get_tree().process_frame

	func wait(seconds: float) -> void:
		await get_tree().create_timer(seconds, true, false, true).timeout

	## Wall time of a call in milliseconds.
	func ms(callable: Callable) -> float:
		var t0 := Time.get_ticks_usec()
		callable.call()
		return (Time.get_ticks_usec() - t0) / 1000.0

	## check(|a - b| <= eps) with both values in the message.
	func near(a: float, b: float, eps: float, what: String) -> void:
		check(absf(a - b) <= eps, "%s (%s vs %s, eps %s)" % [what, str(a), str(b), str(eps)])

	func log(msg: String) -> void:
		print("  [%s] %s" % [case_name, msg])

	# ------------------------------------------------------------ running

	func _cases() -> PackedStringArray:
		var out := PackedStringArray()
		var d := DirAccess.open(dir)
		if d == null:
			return out
		for f in d.get_files():
			if f.begins_with("case_") and f.ends_with(".gd"):
				out.append(f)
		out.sort()
		return out

	func _run_all() -> void:
		await get_tree().process_frame
		var files := _cases()
		var ran := 0
		var t_all := Time.get_ticks_msec()
		for f in files:
			var short := f.get_basename().trim_prefix("case_")
			if not only.is_empty() and not short in only:
				continue
			case_name = f.get_basename()
			var path := dir + "/" + f
			var scr = load(path)
			if scr == null or not (scr is GDScript) or not (scr as GDScript).can_instantiate():
				fail("%s does not compile" % path)
				continue
			var consts: Dictionary = (scr as GDScript).get_script_constant_map()
			if ci and bool(consts.get("NEEDS_CONTENT", false)):
				print("skip %s (needs content)" % case_name)
				continue
			ran += 1
			await _run_case(scr, float(consts.get("TIMEOUT", DEFAULT_TIMEOUT)))
		if ran == 0 and not only.is_empty():
			case_name = suite_name
			fail("no case matches %s" % ", ".join(only))
		print("%s: %d checks, %d failures (%d cases, %.1f s)" % [suite_name, checks, failures, ran,
			(Time.get_ticks_msec() - t_all) / 1000.0])
		OS.remove_logger(_tap)
		get_tree().quit(1 if failures > 0 else 0)

	func _run_case(scr: GDScript, timeout: float) -> void:
		_case_checks = 0
		_case_failures = 0
		var g := get_node_or_null("/root/Game")
		var saved: Dictionary = (g.get("settings") as Dictionary).duplicate(true) if g != null else {}
		var errors0 := _tap.count()
		var t0 := Time.get_ticks_msec()
		_case_token += 1
		var token := _case_token
		var state := {"done": false}
		get_tree().create_timer(timeout, true, false, true).timeout.connect(_on_timeout.bind(token, state, timeout))
		var inst = scr.new()
		if inst == null or not inst.has_method("run"):
			fail("%s has no run(t)" % case_name)
		else:
			await inst.run(self)
		state.done = true
		var errs := _tap.count() - errors0
		if errs > 0:
			fail("%d script error(s) while the case ran, last: %s" % [errs, _tap.last])
		if g != null and g.get("settings") != saved:
			g.set("settings", saved)
			if g.has_method("save_settings"):
				g.call("save_settings")
			print("  [%s] settings restored" % case_name)
		print("%s: %d checks, %d failures (%d ms)" % [case_name, _case_checks, _case_failures,
			Time.get_ticks_msec() - t0])

	func _on_timeout(token: int, state: Dictionary, timeout: float) -> void:
		if state.done or token != _case_token:
			return
		fail("timed out after %.0f s" % timeout)
		print("%s: %d checks, %d failures (stopped)" % [suite_name, checks, failures])
		OS.remove_logger(_tap)
		get_tree().quit(1)
