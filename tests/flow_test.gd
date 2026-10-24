extends Node
## Starts flow_runner.gd outside the current scene so scene changes don't free it.

func _ready() -> void:
	var runner := Node.new()
	runner.set_script(load("res://tests/flow_runner.gd"))
	get_tree().root.add_child.call_deferred(runner)
