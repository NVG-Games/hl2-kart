extends Node
## Compile every script under res://scripts and res://tests; prints failures and
## exits with code 1 when any script does not compile (used by CI).

func _ready() -> void:
	var bad := 0
	for f in _walk("res://scripts") + _walk("res://tests"):
		var s = load(f)
		# a script with a parse error still loads, but can not be instantiated
		if s == null or (s is GDScript and not (s as GDScript).can_instantiate()):
			bad += 1
			print("FAILED: ", f)
	print("checked, failures: ", bad)
	get_tree().quit(1 if bad > 0 else 0)

func _walk(dir: String) -> Array:
	var out := []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for sub in d.get_directories():
		out += _walk(dir + "/" + sub)
	return out
