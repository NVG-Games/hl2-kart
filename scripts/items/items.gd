class_name Items
## Kart-racer items rebuilt from Half-Life 2 gameplay objects.

const INFO := {
	"battery": {"name": "SUIT BATTERY", "model": "items/battery", "desc": "Turbo boost"},
	"battery3": {"name": "3x SUIT BATTERY", "model": "items/battery", "desc": "Three boosts"},
	"manhack": {"name": "MANHACK", "model": "manhack", "desc": "Hunts the kart ahead"},
	"manhack3": {"name": "3x MANHACK", "model": "manhack", "desc": "Three hunters"},
	"rollermine": {"name": "ROLLERMINE", "model": "roller", "desc": "Bounces and shocks vehicles"},
	"barrel": {"name": "EXPLOSIVE BARREL", "model": "props_c17/oildrum001_explosive", "desc": "Drop it behind you"},
	"gravgun": {"name": "GRAVITY GUN", "model": "weapons/w_physics", "desc": "Punt everything in front"},
	"canister": {"name": "HEADCRAB CANISTER", "model": "props_combine/headcrabcannister01a", "desc": "Strikes the leader"},
	"hev": {"name": "HEV OVERCHARGE", "model": "items/hevsuit", "desc": "Invulnerable and fast"},
}

# weights per race position bucket: front, middle, back
const TABLE := {
	"front": {"barrel": 30, "rollermine": 30, "battery": 20, "manhack": 10, "gravgun": 10},
	"middle": {"manhack": 25, "rollermine": 15, "battery": 20, "barrel": 10, "gravgun": 15, "battery3": 8, "manhack3": 7},
	"back": {"battery3": 22, "manhack3": 18, "hev": 18, "canister": 12, "manhack": 15, "gravgun": 15},
}


static func roll(place: int, total: int) -> String:
	var f := float(place - 1) / maxf(total - 1, 1)
	var bucket := "front" if f < 0.2 else ("middle" if f < 0.65 else "back")
	var t: Dictionary = TABLE[bucket]
	var sum := 0
	for k in t:
		sum += t[k]
	var r := randi() % sum
	for k in t:
		r -= t[k]
		if r < 0:
			return k
	return "battery"


static var _net_seq := 0


static func use(k: Kart) -> void:
	var id := k.item
	# online, everything another peer must replay goes into `extra`
	var extra := {}
	if Net.active:
		_net_seq += 1
		extra["nid"] = "%d:%d" % [k.net_slot, _net_seq]
	match id:
		"manhack", "manhack3":
			var t := ManhackProjectile.next_ahead(k)
			extra["target"] = t.net_slot if t else -1
		"rollermine":
			extra["back"] = k.in_look_back or k.in_brake > 0.5
		"canister":
			var t2 := CanisterStrike.leader_for(k)
			extra["target"] = t2.net_slot if t2 else -1
	_spawn(k, id, extra)
	k.item_count -= 1
	if id.ends_with("3"):
		if k.item_count <= 0:
			k.item_count = 0
	if k.item_count <= 0:
		k.item = ""
	k.item_changed.emit(k)
	if id in ["manhack", "manhack3", "rollermine", "canister", "gravgun"]:
		k.audio.say("hit")
	if Net.active:
		Net.send_event("item", [k.net_slot, id, k.global_transform, k.linear_velocity, extra])


## Another player used an item: replay it from where their kart was.
static func use_remote(k: Kart, id: String, xf: Transform3D, extra: Dictionary) -> void:
	k.global_transform = xf
	_spawn(k, id, extra)


static func _kart_slot(k: Kart, slot: int) -> Kart:
	if slot < 0 or k.race == null or not k.race.has_method("kart_by_slot"):
		return null
	return k.race.kart_by_slot(slot)


static func _spawn(k: Kart, id: String, extra: Dictionary) -> void:
	var race = k.race
	var nid: String = extra.get("nid", "")
	match id:
		"battery", "battery3":
			k.boost(1.4, 1.0)
			Game.play_3d("res://assets/sound/items/battery_pickup.wav", k.global_position, 0.0, 1.0, 10.0, k)
		"manhack", "manhack3":
			var m := ManhackProjectile.new()
			k.get_parent().add_child(m)
			m.launch(k, race, _kart_slot(k, int(extra.get("target", -1))) if extra.has("target") else null)
			_tag(m, nid)
		"rollermine":
			var r := RollermineProjectile.new()
			k.get_parent().add_child(r)
			r.launch(k, bool(extra.get("back", k.in_look_back or k.in_brake > 0.5)))
			_tag(r, nid)
		"barrel":
			_tag(_drop_barrel(k), nid)
		"gravgun":
			_punt(k)
		"canister":
			var c := CanisterStrike.new()
			k.get_parent().add_child(c)
			c.launch(k, race, _kart_slot(k, int(extra.get("target", -1))) if extra.has("target") else null)
		"hev":
			k.star_time = 7.0
			k.boost(7.0, 0.6)
			Game.play_3d("res://assets/sound/items/suitchargeok1.wav", k.global_position, 2.0, 1.0, 12.0, k)
			Game.play_3d("res://assets/sound/player/suit_sprint.wav", k.global_position, 0.0, 1.0, 12.0, k)


## Network id shared by every peer's copy of a projectile / trap.
static func _tag(n: Node, nid: String) -> void:
	if nid != "":
		n.set_meta("nid", nid)
		n.add_to_group("net_objects")


## The owner of the kart it hit says it is gone: remove our copy too.
static func net_remove(tree: SceneTree, nid: String, trap := false) -> void:
	for n in tree.get_nodes_in_group("net_objects"):
		if n.get_meta("nid", "") != nid:
			continue
		if trap and n is PhysProp:
			n.set_meta("net_done", true)
			(n as PhysProp).explode()
		elif n.has_method("net_hit"):
			n.net_hit()
		else:
			n.queue_free()


static func _drop_barrel(k: Kart) -> PhysProp:
	var p := PhysProp.new()
	k.get_parent().add_child(p)
	p.setup("props_c17/oildrum001_explosive")
	var back := k.global_basis.z
	p.global_position = k.global_position + back * 3.6 + Vector3.UP * 1.2
	p.linear_velocity = k.linear_velocity * 0.3 + back * 2.0
	p.set_meta("trap_owner", k)
	p.add_to_group("traps")
	Game.play_3d("res://assets/sound/physics/metal/metal_barrel_impact_hard1.wav", p.global_position, -2.0, 1.0, 10.0)
	return p


static func _punt(k: Kart) -> void:
	var origin := k.global_position + Vector3.UP
	var fwd := -k.global_basis.z
	Game.play_3d(["res://assets/sound/weapons/physcannon/superphys_launch1.wav",
		"res://assets/sound/weapons/physcannon/superphys_launch2.wav"], origin, 2.0, 1.0, 16.0)
	Effects.punt_flash(k.get_parent(), origin + fwd * 3.0, fwd)
	for n in k.get_tree().get_nodes_in_group("karts"):
		var o := n as Kart
		if o == k:
			continue
		var d := o.global_position - origin
		if d.length() < 22.0 and d.normalized().dot(fwd) > 0.55:
			o.tumble(k, fwd * o.mass * 14.0)
	for n in k.get_parent().find_children("*", "PhysProp", true, false):
		var p := n as PhysProp
		var d := p.global_position - origin
		if d.length() < 22.0 and d.normalized().dot(fwd) > 0.4:
			p.sleeping = false
			p.hit((fwd * 18.0 + Vector3.UP * 6.0) * p.mass)
