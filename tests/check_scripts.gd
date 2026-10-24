extends Node
## Compile every script under res://scripts and res://tests; prints failures.

func _ready() -> void:
	var bad := 0
	for f in _walk("res://scripts") + _walk("res://tests"):
		var s = load(f)
		if s == null:
			bad += 1
			print("FAILED: ", f)
	print("checked, failures: ", bad)
	get_tree().quit()

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
