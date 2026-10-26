extends Node
## Headless item check: a demo race where, every few seconds, one racer uses the
## next item on the list (a kart in the middle of the pack, so there is someone
## ahead and behind). Prints what each item hit, blinded or moved.
## usage: godot --headless --path . res://tests/item_test.tscn -- [track] [item,item,...]

const DEFAULT := ["cball", "melon", "hopper", "saw", "headcrab", "xenport", "melon3", "cball", "saw", "hopper"]

var race: Node
var items: Array = []
var k_item := 0
var t := 0.0
var next := 4.0
var hits := {}
var current := ""
var log_lines: PackedStringArray = []


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	Game.settings["track"] = a[0] if a.size() > 0 else "ct17"
	items = Array(a[1].split(",")) if a.size() > 1 else DEFAULT
	Game.settings["demo"] = true
	Game.settings["difficulty"] = 2
	Game.settings["laps"] = 3
	race = load("res://scenes/race.tscn").instantiate()
	get_tree().root.add_child.call_deferred(race)
	Engine.time_scale = 2.0


func _process(delta: float) -> void:
	if race == null or not race.get("racing"):
		return
	t += delta
	var karts: Array = race.get("karts")
	if hits.is_empty():
		for k in karts:
			(k as Kart).got_hit.connect(func(v: Kart, by: Kart): _on_hit(v, by))
		hits["_"] = 0
	if t < next:
		return
	if k_item >= items.size():
		for l in log_lines:
			print(l)
		get_tree().quit()
		return
	# the kart in 4th place uses the item
	var user: Kart = null
	for k in karts:
		if (k as Kart).place == 4:
			user = k
	if user == null:
		user = karts[0]
	current = items[k_item]
	k_item += 1
	var before := user.lap_progress
	var blind_before := 0
	for k in karts:
		blind_before += 1 if (k as Kart).blind_time > 0.0 else 0
	hits[current + "#" + str(k_item)] = 0
	user.give_item(current, 1)
	user.roulette = 0.0
	Items.use(user)
	var id := current + "#" + str(k_item)
	get_tree().create_timer(3.8).timeout.connect(func():
		var blinded := 0
		for k in karts:
			blinded += 1 if (k as Kart).blind_time > 0.0 or (k as Kart).find_children("*", "FaceCrab", false, false).size() > 0 else 0
		log_lines.append("%-12s used by %-10s hits=%d blinded_now=%d moved=%.0f m" % [id, user.character_id,
			hits.get(id, 0), blinded, fposmod(user.lap_progress - before, race.track.path.length)]))
	next = t + 4.0


func _on_hit(v: Kart, by: Kart) -> void:
	var id := current + "#" + str(k_item)
	hits[id] = hits.get(id, 0) + 1
