class_name EditorHit
extends RefCounted
## One pick result under the mouse: what was hit (gizmo, marker, prop, road, terrain, water), where,
## and on which road sample. P7 (P0: the fields are final).

var hit := false
var pos := Vector3.ZERO
var normal := Vector3.UP
var what := ""            # "gizmo" | "marker" | "prop" | "road" | "terrain" | "water" | ""
var kind := ""            # the marker's / item's kind (7.6)
var uid := 0
var sub := 0              # a marker's sub-handle (0 main, 1 handle in, 2 handle out, 3 end a, 4 end b, 5 + dot, ...)
var road := -2            # -1 main, branch uid, -2 none
var sample := -1
var s := 0.0
var lat := 0.0
var screen := Vector2.ZERO
var ray_from := Vector3.ZERO
var ray_dir := Vector3.FORWARD
