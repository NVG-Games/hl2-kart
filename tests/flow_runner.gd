extends Node
## (runner, lives outside the current scene)
## Menu -> race -> pause -> resume -> restart flow, watching for runtime errors.

var t := 0.0
var step := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")


func _process(delta: float) -> void:
	t += delta
	var cs := get_tree().current_scene
	match step:
		0:
			if t > 1.5 and cs and cs.has_method("_go_race"):
				print("menu ok -> new race screen -> start")
				cs._open_setup()
				cs.setup.start.emit()
				step = 1
		1:
			if t > 12.0 and cs and cs.get("racing") != null:
				print("race scene ok, phase=", cs._phase, " karts=", cs.karts.size())
				cs.hud._toggle_pause()
				step = 2
		2:
			if t > 13.0:
				step = 3
				print("paused=", get_tree().paused)
				get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0] + "_pause.png")
				cs.hud._open_options()
				await get_tree().create_timer(0.4).timeout
				get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0] + "_pause_options.png")
				cs.hud._options.close()
				cs.hud._toggle_pause()
				step = 3
		3:
			if t > 16.0:
				print("racing=", cs.racing, " player speed=", cs.player.speed)
				cs.restart()
				step = 4
		4:
			if t > 22.0:
				print("restart ok: ", get_tree().current_scene.name)
				get_tree().current_scene.to_menu()
				step = 5
		5:
			if t > 24.0:
				print("back to menu: ", get_tree().current_scene.name)
				get_tree().quit()
