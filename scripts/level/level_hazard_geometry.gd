class_name LevelHazardGeometry
## Hazard setup geometry (4.2, 3.5): the level crossing's rails and tunnel portals, the column's
## prefab footbridge, the tripmine's wall stub. Everything goes into the compile's LevelMeshSet under
## the hazard's road key (LevelMeshSet.hazard_key(uid): buckets named `<kind>_h<uid>_g0_<n>`), with
## material keys Track.dress swaps for world materials. P14.

const GROUP := "g0"
## The level crossing's track (a decal: sleepers and rails seen from above) and its width.
const RAIL_MAT := "wood/woodtrack001a"
const RAIL_W := 2.8
## The decal's lift over the floor it follows.
const RAIL_UP := 0.06
const PORTAL_MAT := "concrete/concretewall008a"
const PORTAL_BACK_MAT := "metal/citadel_metalwall072a"
## The column's footbridge (4.2): deck width and thickness, railing height, pillar size, materials.
const DECK_W := 2.4
const DECK_T := 0.4
const RAIL_H := 1.0
const RAILING_T := 0.08
const PILLAR := 0.8
const DECK_MAT := "concrete/concretefloor037b"
const RAILING_MAT := "metal/metalrail013a"
const PILLAR_MAT := "concrete/concretewall066a"
## The tripmine's wall stub: 2 m along, 1.2 m tall, 0.4 m thick.
const STUB := Vector3(0.4, 1.2, 2.0)
const STUB_MAT := "concrete/concretewall008a"


## The rails decal along a line from `a` in plan direction `d` (unit, flat): `profile` is
## [[u metres along, floor y], ...] every metre; the strip hugs it RAIL_UP metres over the floor.
static func rails(ms: LevelMeshSet, key: int, a: Vector3, d: Vector3, profile: Array, mat := RAIL_MAT, width := RAIL_W) -> void:
	if profile.size() < 2:
		return
	var side := Vector3.UP.cross(d).normalized()
	var la := PackedVector3Array()
	var rb := PackedVector3Array()
	var ua := PackedFloat32Array()
	var ub := PackedFloat32Array()
	var v := PackedFloat32Array()
	var nrm := PackedVector3Array()
	for e in profile:
		var u := float(e[0])
		var q := Vector3(a.x, float(e[1]) + RAIL_UP, a.z) + d * u
		la.append(q - side * width * 0.5)
		rb.append(q + side * width * 0.5)
		ua.append(0.0)
		ub.append(1.0)
		v.append(u / width)
		nrm.append(Vector3.UP)
	ms.strip("decal", mat, la, rb, ua, ub, v, nrm, nrm, key, GROUP)


## The blocks of a tunnel mouth at `end` (ground height g) facing back along d (hazards.py
## portal_boxes): [[centre, size, back wall?]]: two piers, wing walls each side, the lintel, a dark
## back wall. Sizes are [across, up, along] in the portal's own frame (yaw of d).
static func portal_boxes(end: Vector3, d: Vector3, g: float) -> Array:
	var side := Vector3.UP.cross(d).normalized()
	var c := Vector3(end.x, g, end.z)
	var out := []
	for sgn in [-1.0, 1.0]:
		out.append([c + side * sgn * 4.5 + Vector3.UP * 4.5 - d * 6.0, Vector3(2.0, 9.0, 12.0), false])
		out.append([c + side * sgn * 22.0 + Vector3.UP * 4.0 - d * 1.0, Vector3(26.0, 8.0, 2.0), false])
	out.append([c + Vector3.UP * 8.0 - d * 6.0, Vector3(11.0, 2.0, 12.0), false])
	out.append([c + Vector3.UP * 3.5 - d * 12.5, Vector3(7.0, 7.0, 1.0), true])
	return out


## A tunnel mouth the train comes out of at `end`, facing back along d, on ground height g.
static func portal(ms: LevelMeshSet, key: int, end: Vector3, d: Vector3, g: float) -> void:
	var basis := _basis(d)
	for b in portal_boxes(end, d, g):
		var mat := PORTAL_BACK_MAT if bool(b[2]) else PORTAL_MAT
		ms.box("walls", mat, Transform3D(basis, b[0]), b[1], 3.0, key, GROUP)


## The column's prefab footbridge from deck end a to deck end b (both on the deck's walking
## surface): a deck DECK_W wide, railings RAIL_H tall on both edges, a pillar under each end down to
## its ground (ga / gb; NAN = no ground: down to the deck height - 8 m, road y - 2 m).
static func footbridge(ms: LevelMeshSet, key: int, a: Vector3, b: Vector3, ga: float, gb: float) -> void:
	var along := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var length := along.length()
	if length < 0.5:
		return
	var d := along / length
	var basis := _basis(d)
	var mid := (a + b) * 0.5
	var side := Vector3.UP.cross(d).normalized()
	# the deck: its top is the walking surface
	ms.box("side", DECK_MAT, Transform3D(basis, mid - Vector3.UP * DECK_T * 0.5),
		Vector3(DECK_W, DECK_T, length), 2.0, key, GROUP)
	for sgn in [-1.0, 1.0]:
		var c: Vector3 = mid + side * sgn * (DECK_W * 0.5 - RAILING_T * 0.5) + Vector3.UP * RAIL_H * 0.5
		ms.box("walls", RAILING_MAT, Transform3D(basis, c), Vector3(RAILING_T, RAIL_H, length), 2.0, key, GROUP)
	for e in [[a, ga, 1.0], [b, gb, -1.0]]:
		var top: Vector3 = e[0] + d * float(e[2]) * PILLAR * 0.5 - Vector3.UP * DECK_T
		var g: float = e[1]
		var bottom := top.y - 8.0 if is_nan(g) else g - 0.5
		var h := top.y - bottom
		if h < 0.5:
			continue
		ms.box("walls", PILLAR_MAT, Transform3D(basis, Vector3(top.x, bottom + h * 0.5, top.z)),
			Vector3(PILLAR, h, PILLAR), 2.0, key, GROUP)


## The tripmine's wall stub: a box STUB (thick across, tall, long along) whose road face stands at
## `face` (a point at the road's height), turned so its length runs along d (the road's flat fwd),
## on side sgn (the stub lies past `face` away from the road).
static func stub(ms: LevelMeshSet, key: int, face: Vector3, d: Vector3, sgn: float) -> void:
	var basis := _basis(d)
	var side := Vector3.UP.cross(d).normalized()
	# Vector3.UP.cross(fwd) points left: a right-side stub (sgn 1) lies along -side
	var c := face - side * sgn * STUB.x * 0.5 + Vector3.UP * (STUB.y * 0.5 - 0.3)
	ms.box("walls", STUB_MAT, Transform3D(basis, c), STUB, 2.0, key, GROUP)


## A basis whose +Z runs along the plan direction d and +Y up.
static func _basis(d: Vector3) -> Basis:
	var f := Vector3(d.x, 0.0, d.z)
	if f.length_squared() < 1e-10:
		f = Vector3.BACK
	return Basis(Vector3.UP, atan2(f.x, f.z))
