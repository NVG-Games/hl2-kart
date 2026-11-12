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
	"cball": {"name": "ENERGY BALL", "model": "items/combine_rifle_ammo01", "desc": "Bounces off walls"},
	"melon": {"name": "WATERMELON", "model": "props_junk/watermelon01", "desc": "Drop it, watch them slip"},
	"melon3": {"name": "3x WATERMELON", "model": "props_junk/watermelon01", "desc": "Three to drop"},
	"hopper": {"name": "HOPPER MINE", "model": "props_combine/combine_mine01", "desc": "Jumps at whoever comes close"},
	"saw": {"name": "SAWBLADE", "model": "props_junk/sawblade001a", "desc": "Cuts through everyone in front"},
	"headcrab": {"name": "HEADCRAB", "model": "headcrabclassic", "desc": "Jumps on the next racers ahead"},
	"xenport": {"name": "XEN TELEPORT", "model": "props_lab/teleportring", "desc": "Warps you down the road"},
}

const MELON := "props_junk/watermelon01"
## Models the items spawn mid-race (projectiles, traps, the face crab; gibs: PhysProp.GIBS):
## Effects.prewarm loads and draws them while the race loads.
const SPAWNS := ["manhack", "roller", "props_junk/sawblade001a", "props_combine/combine_mine01",
	"props_combine/headcrabcannister01a", "headcrabclassic", "props_c17/oildrum001_explosive", MELON]

# weights per race position bucket: front, middle, back (each sums to 100). The nine
# original items keep their old proportions and 80 % of every bucket; the seven newer
# ones share the other 20 %, so they turn up now and then instead of half the time
const TABLE := {
	"front": {"barrel": 24, "rollermine": 24, "battery": 16, "manhack": 8, "gravgun": 8,
		"melon": 9, "hopper": 5, "cball": 4, "melon3": 2},
	"middle": {"manhack": 20, "battery": 16, "rollermine": 12, "gravgun": 12, "barrel": 8, "battery3": 6, "manhack3": 6,
		"cball": 6, "saw": 5, "melon3": 3, "hopper": 3, "headcrab": 3},
	"back": {"battery3": 18, "manhack3": 14, "hev": 14, "manhack": 12, "gravgun": 12, "canister": 10,
		"xenport": 8, "saw": 6, "cball": 3, "headcrab": 3},
}

# HEADCRAB: a short blindfold for the next few racers ahead, one crab item in play at a time
const CRAB_HOLD := 2.5  # seconds on a face (was 3.6)
const CRAB_RANGE := 200.0  # metres ahead it reaches
const CRAB_MAX := 3  # faces per use: the nearest racers ahead
const CRAB_COOLDOWN := 20.0  # race seconds after one is used before a crate hands out another
static var _crab_used_at := -1000.0


static func roll(place: int, total: int, karts: Array = []) -> String:
	var f := float(place - 1) / maxf(total - 1, 1)
	var bucket := "front" if f < 0.2 else ("middle" if f < 0.65 else "back")
	var t: Dictionary = TABLE[bucket]
	if t.has("headcrab") and not _crab_allowed(karts):
		t = t.duplicate()
		t.erase("headcrab")
	var sum := 0
	for k in t:
		sum += t[k]
	var r := randi() % sum
	for k in t:
		r -= t[k]
		if r < 0:
			return k
	return "battery"


## A crate may hand out a HEADCRAB: nobody holds one and the last one was a while ago.
static func _crab_allowed(karts: Array) -> bool:
	var now := -1.0
	for o in karts:
		var k := o as Kart
		if k.item == "headcrab":
			return false
		if now < 0.0 and k.race:
			now = float(k.race.get("race_time"))
	return now < _crab_used_at or now - _crab_used_at >= CRAB_COOLDOWN


## The racers a HEADCRAB used by `k` would jump on: the nearest CRAB_MAX ahead within
## CRAB_RANGE that can take one (Kart.can_take_crab).
static func crab_targets(k: Kart) -> Array:
	var ahead: Array = []
	for n in k.get_tree().get_nodes_in_group("karts"):
		var o := n as Kart
		var d := o.total_progress - k.total_progress
		if o != k and d > 0.0 and d < CRAB_RANGE and o.can_take_crab():
			ahead.append(o)
	ahead.sort_custom(func(a: Kart, b: Kart) -> bool: return a.total_progress < b.total_progress)
	return ahead.slice(0, CRAB_MAX)


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
	if id in ["manhack", "manhack3", "rollermine", "canister", "gravgun", "cball", "saw", "headcrab"]:
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
			if c.target:
				# the shell is marked over its target: the spectators there know what comes out of it
				CrowdDirector.notify(k.get_tree(), &"headcrab", c.target.global_position, c.target, k)
		"cball":
			var ball := EnergyBall.new()
			k.get_parent().add_child(ball)
			ball.launch(k)
			_tag(ball, nid)
		"melon", "melon3":
			_tag(_drop_melon(k), nid)
		"hopper":
			var mine := HopperMine.new()
			k.get_parent().add_child(mine)
			mine.drop(k)
			_tag(mine, nid)
		"saw":
			var saw := SawbladeProjectile.new()
			k.get_parent().add_child(saw)
			saw.launch(k)
		"headcrab":
			_headcrabs(k)
		"xenport":
			_xen_teleport(k)
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
			if (n as PhysProp).model_key == MELON:
				(n as PhysProp).smash()
			else:
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


## A watermelon left on the road: whoever drives into it spins out (Kart._on_body_entered).
static func _drop_melon(k: Kart) -> PhysProp:
	var p := PhysProp.new()
	k.get_parent().add_child(p)
	p.setup(MELON)
	var back := k.global_basis.z
	p.global_position = k.global_position + back * 3.4 + k.grav_up * 0.9
	p.linear_velocity = k.linear_velocity * 0.25 + back * 1.5
	p.mass = 30.0
	p.set_meta("trap_owner", k)
	p.add_to_group("traps")
	Game.play_3d("res://assets/sound/physics/flesh/flesh_squishy_impact_hard1.wav", p.global_position, -4.0, 1.0, 10.0)
	return p


## Headcrabs leap onto the next few racers ahead: their view is blocked for a moment.
static func _headcrabs(k: Kart) -> void:
	Game.play_3d("res://assets/sound/npc/headcrab/alert1.wav", k.global_position, 2.0, 1.0, 14.0, k)
	if k.race:
		_crab_used_at = float(k.race.get("race_time"))
	var delay := 0.0
	for o in crab_targets(k):
		if (o as Kart).blind(CRAB_HOLD, delay):
			delay += 0.15
			# spectators by a racer with a headcrab on its face: scientists cower and scream
			CrowdDirector.notify(k.get_tree(), &"headcrab", (o as Kart).global_position, o, k)


## Through a Xen portal: the kart comes out further down the road, at speed.
static func _xen_teleport(k: Kart) -> void:
	var green := Color(0.4, 1.0, 0.5)
	Effects.sparks(k.get_parent(), k.global_position + k.grav_up, 2.5, green)
	Game.play_3d("res://assets/sound/weapons/gauss/fire1.wav", k.global_position, 2.0, 0.8, 18.0)
	if not k.remote:
		k.teleport_ahead(140.0)
	Effects.sparks(k.get_parent(), k.global_position + k.grav_up, 2.5, green)
	Game.play_3d("res://assets/sound/weapons/physcannon/energy_sing_explosion2.wav", k.global_position, 0.0, 1.2, 18.0)


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
