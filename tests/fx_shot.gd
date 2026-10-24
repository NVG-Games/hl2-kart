extends Node
## Demo race; triggers an explosion and a gravity-gun punt ahead of the camera kart and screenshots them.

var race: Node
var t := 0.0
var out := ""
var done := {}


func _ready() -> void:
	out = OS.get_cmdline_user_args()[0]
	Game.settings["demo"] = true
	Game.settings["sky"] = OS.get_cmdline_user_args()[1] if OS.get_cmdline_user_args().size() > 1 else "sky_day01_01"
	race = load("res://scenes/race.tscn").instantiate()
	get_tree().root.add_child.call_deferred(race)


func _shot(name: String) -> void:
	get_viewport().get_texture().get_image().save_png("%s_%s.png" % [out, name])


func _process(delta: float) -> void:
	t += delta
	if race == null or race.get("player") == null or race.player == null:
		return
	var k: Kart = race.player
	if t > 14.0 and not done.has("boom"):
		done["boom"] = true
		Effects.explosion(race, k.global_position - k.global_basis.z * 22.0, 1.2)
	if t > 14.25 and not done.has("s1"):
		done["s1"] = true
		_shot("boom1")
	if t > 14.7 and not done.has("s2"):
		done["s2"] = true
		_shot("boom2")
	if t > 20.0 and not done.has("item"):
		done["item"] = true
		k.give_item("gravgun")
		k.roulette = 0.0
	if t > 20.3 and not done.has("s3"):
		done["s3"] = true
		_shot("item")
	if t > 21.0 and not done.has("punt"):
		done["punt"] = true
		Items.use(k)
	if t > 21.12 and not done.has("s4"):
		done["s4"] = true
		_shot("punt")
	if t > 22.0:
		get_tree().quit()
