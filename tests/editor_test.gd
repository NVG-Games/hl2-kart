extends "res://tests/level_test.gd"
## Headless runner of the editor cases (9.1): every tests/editor/case_*.gd, alphabetically, with the
## same t API, arguments and exit code as level_test (see tests/level_test.gd).
## Prints "editor_test: N checks, F failures"; exits 1 on any failure.
## usage: godot --headless --path . res://tests/editor_test.tscn [-- ci] [-- only <name>[,<name>...]]


func suite() -> Dictionary:
	return {"name": "editor_test", "dir": "res://tests/editor"}
