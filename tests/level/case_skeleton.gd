extends RefCounted
## P0: every class of spec 7.1 exists at its path with its base and the 7.3 contract (signals,
## constants, variables, methods with their argument names, required count, static flag and return
## type); LevelDoc ops fuzz (300 seeded random ops applied then undone give the identical data, and
## redone give the same state again); copy-on-write snapshots; find / get_at / new_uid; LevelReport
## counts; LevelStyles against a fake registry; LevelContext seeds. No content needed.
## The API and PATHS tables are generated from the spec (7.3, 7.1) by
## .handoff/scratch/editor/build/P0/gen_api.py (EditorSelection renamed EditSelection: Godot's
## editor has a native EditorSelection).

const NEEDS_CONTENT := false

const TOOLS := ["SelectTool", "RoadTool", "BranchTool", "TerrainTool", "PaintTool", "ObjectsTool", "ItemsTool",
	"HazardsTool", "CrowdsTool", "WorldTool"]
## 7.1 classes without a 7.3 entry: the few members other lanes rely on.
const EXTRA_SIGNALS := {"EditorNumber": ["changed"]}
const BUILTIN := ["int", "float", "bool", "String", "Dictionary", "Array", "Callable", "Vector2", "Vector2i",
	"Vector3", "Rect2", "Rect2i", "Transform3D", "AABB", "Color", "PackedByteArray", "PackedInt32Array",
	"PackedFloat32Array", "PackedStringArray", "PackedVector3Array", "PackedColorArray"]

const PATHS := {
	"LevelDoc": ["res://scripts/level/level_doc.gd", "RefCounted"],
	"LevelReport": ["res://scripts/level/level_report.gd", "RefCounted"],
	"LevelStyles": ["res://scripts/level/level_styles.gd", ""],
	"LevelIO": ["res://scripts/level/level_io.gd", ""],
	"LevelRoad": ["res://scripts/level/level_road.gd", "RefCounted"],
	"LevelLine": ["res://scripts/level/level_line.gd", ""],
	"LevelContext": ["res://scripts/level/level_context.gd", "RefCounted"],
	"LevelMeshSet": ["res://scripts/level/level_mesh_set.gd", "RefCounted"],
	"LevelGeometry": ["res://scripts/level/level_geometry.gd", ""],
	"LevelTerrain": ["res://scripts/level/level_terrain.gd", "RefCounted"],
	"LevelCompiler": ["res://scripts/level/level_compiler.gd", ""],
	"LevelBuild": ["res://scripts/level/level_build.gd", "RefCounted"],
	"LevelValidate": ["res://scripts/level/level_validate.gd", ""],
	"LevelThemes": ["res://scripts/level/level_themes.gd", ""],
	"LevelTemplates": ["res://scripts/level/level_templates.gd", ""],
	"LevelBranches": ["res://scripts/level/level_branches.gd", ""],
	"LevelHazards": ["res://scripts/level/level_hazards.gd", ""],
	"LevelHazardGeometry": ["res://scripts/level/level_hazard_geometry.gd", ""],
	"LevelCrowds": ["res://scripts/level/level_crowds.gd", ""],
	"LevelDress": ["res://scripts/level/level_dress.gd", ""],
	"LevelFixes": ["res://scripts/level/level_fixes.gd", ""],
	"LevelBrush": ["res://scripts/level/level_brush.gd", ""],
	"CustomTracks": ["res://scripts/track/custom_tracks.gd", ""],
	"TrackShare": ["res://scripts/net/track_share.gd", "Node"],
	"TrackEditor": ["res://scripts/editor/track_editor.gd", "Node3D"],
	"EditorSession": ["res://scripts/editor/editor_session.gd", "RefCounted"],
	"EditHistory": ["res://scripts/editor/edit_history.gd", "RefCounted"],
	"EditorInput": ["res://scripts/editor/editor_input.gd", ""],
	"EditorCamera": ["res://scripts/editor/editor_camera.gd", "Camera3D"],
	"EditSelection": ["res://scripts/editor/editor_selection.gd", "RefCounted"],
	"EditorHit": ["res://scripts/editor/editor_hit.gd", "RefCounted"],
	"EditorDraw": ["res://scripts/editor/editor_draw.gd", "MeshInstance3D"],
	"EditorMarkers": ["res://scripts/editor/editor_markers.gd", "Control"],
	"Gizmo3D": ["res://scripts/editor/gizmo_3d.gd", "Node3D"],
	"LevelView": ["res://scripts/editor/level_view.gd", "Node3D"],
	"PropCatalog": ["res://scripts/editor/prop_catalog.gd", ""],
	"PropThumbs": ["res://scripts/editor/prop_thumbs.gd", "Node"],
	"EditorTool": ["res://scripts/editor/tools/editor_tool.gd", "RefCounted"],
	"SelectTool": ["res://scripts/editor/tools/select_tool.gd", ""],
	"RoadTool": ["res://scripts/editor/tools/road_tool.gd", ""],
	"BranchTool": ["res://scripts/editor/tools/branch_tool.gd", ""],
	"TerrainTool": ["res://scripts/editor/tools/terrain_tool.gd", ""],
	"PaintTool": ["res://scripts/editor/tools/paint_tool.gd", ""],
	"ObjectsTool": ["res://scripts/editor/tools/objects_tool.gd", ""],
	"ItemsTool": ["res://scripts/editor/tools/items_tool.gd", ""],
	"HazardsTool": ["res://scripts/editor/tools/hazards_tool.gd", ""],
	"CrowdsTool": ["res://scripts/editor/tools/crowds_tool.gd", ""],
	"WorldTool": ["res://scripts/editor/tools/world_tool.gd", ""],
	"EditorKit": ["res://scripts/editor/ui/editor_kit.gd", ""],
	"EditorNumber": ["res://scripts/editor/ui/editor_number.gd", "LineEdit"],
	"EditorUI": ["res://scripts/editor/ui/editor_ui.gd", "Control"],
	"Inspector": ["res://scripts/editor/ui/inspector.gd", "ScrollContainer"],
	"Outliner": ["res://scripts/editor/ui/outliner.gd", "VBoxContainer"],
	"EditorMenu": ["res://scripts/editor/ui/editor_menu.gd", "Dialog"],
	"MaterialPicker": ["res://scripts/editor/ui/material_picker.gd", "Dialog"],
	"ValidationPanel": ["res://scripts/editor/ui/validation_panel.gd", "PanelContainer"],
	"AutoDressDialog": ["res://scripts/editor/ui/auto_dress_dialog.gd", "Dialog"],
	"StyleEditor": ["res://scripts/editor/ui/style_editor.gd", "Dialog"],
	"HelpOverlay": ["res://scripts/editor/ui/help_overlay.gd", "Control"],
	"HintCard": ["res://scripts/editor/ui/hint_card.gd", "PanelContainer"],
	"CatalogPanel": ["res://scripts/editor/ui/catalog_panel.gd", "PanelContainer"],
	"EditorHome": ["res://scripts/ui/editor_home.gd", "Control"],
	"TrackList": ["res://scripts/ui/track_list.gd", "VBoxContainer"],
	"TrackBrowser": ["res://scripts/ui/track_browser.gd", "Dialog"],
}
const API := {
	"LevelDoc": {"base": "RefCounted", "signals": ["changed"], "consts": ["FORMAT", "KIND", "HEIGHT_MIN", "HEIGHT_MAX", "SECTIONS"], "vars": ["data", "heights", "splat", "thumb", "thumb_custom", "revision", "report"], "static_vars": [],
		"methods": {"blank": [["track_name", "size", "res"], 1, "LevelDoc", true], "snapshot": [[], 0, "LevelDoc", false], "res": [[], 0, "int", false], "cell": [[], 0, "float", false], "origin": [[], 0, "Vector2", false], "new_uid": [[], 0, "int", false], "find": [["uid"], 1, "Dictionary", false], "get_at": [["path"], 1, "Variant", false], "apply": [["ops"], 1, "Array", false], "notify": [["sections", "uids", "rect"], 1, "void", false], "op_set": [["path", "value"], 2, "Array", true], "op_erase": [["path"], 1, "Array", true], "op_insert": [["path", "index", "value"], 3, "Array", true], "op_remove": [["path", "index"], 2, "Array", true], "op_heights": [["rect", "values"], 2, "Array", true], "op_splat": [["rect", "values"], 2, "Array", true], "reverse_ops": [[], 0, "Array", false], "delete_point_ops": [["uid"], 1, "Array", false], "migrate": [["raw"], 1, "Dictionary", true], "sanitize": [["raw", "report"], 2, "Dictionary", true], "sanitize_items": [["section", "items", "report"], 3, "Array", true]}},
	"LevelReport": {"base": "RefCounted", "signals": [], "consts": [], "vars": ["items", "missing", "dropped"], "static_vars": [],
		"methods": {"error": [["code", "text", "where", "fix"], 2, "void", false], "warning": [["code", "text", "where", "fix"], 2, "void", false], "info": [["code", "text", "where"], 2, "void", false], "errors": [[], 0, "int", false], "warnings": [[], 0, "int", false], "raceable": [[], 0, "bool", false], "fatal": [[], 0, "String", false], "blocks_drive": [[], 0, "String", false], "to_dict": [[], 0, "Dictionary", false]}},
	"LevelStyles": {"base": "", "signals": [], "consts": ["PRESETS", "BARRIERS"], "vars": [], "static_vars": [],
		"methods": {"resolve": [["doc", "materials"], 2, "Dictionary", true], "treatment": [["st", "side"], 2, "float", true], "ids": [["doc"], 1, "PackedStringArray", true]}},
	"LevelIO": {"base": "", "signals": [], "consts": ["MAGIC", "CONTAINER", "MAX_FILE", "MAX_DOC_RAW", "MAX_META", "MAX_THUMB", "THUMB_SIZE", "HEIGHT_HOLE"], "vars": [], "static_vars": [],
		"methods": {"pack": [["doc", "header_extra"], 1, "PackedByteArray", true], "unpack": [["bytes", "report"], 2, "LevelDoc", true], "read_meta": [["path"], 1, "Dictionary", true], "sanitize_meta": [["meta"], 1, "Dictionary", true], "save": [["doc", "path", "header_extra"], 2, "Error", true], "save_async": [["doc", "path", "header_extra", "done"], 4, "void", true], "load_file": [["path", "report"], 2, "LevelDoc", true], "png_ok": [["png"], 1, "bool", true], "decode_thumb": [["png"], 1, "Image", true], "sha256": [["bytes"], 1, "String", true], "file_sha256": [["path"], 1, "String", true], "id_for": [["sha"], 1, "String", true], "is_sha": [["s"], 1, "bool", true], "slug": [["track_name"], 1, "String", true]}},
	"LevelRoad": {"base": "RefCounted", "signals": [], "consts": ["STEP", "SEG_GROUP"], "vars": ["key", "closed", "partial", "n", "step", "length", "pos", "fwd", "right", "flat_right", "up", "width", "curv", "s", "style", "styles", "seg", "segt", "seg_first", "point_uids", "height", "bar_l", "bar_r", "barriers", "gap", "pit", "gaps", "side_off", "clip_in", "cut", "skip", "dip", "junction", "line", "speed", "emit_from", "emit_to"], "static_vars": [],
		"methods": {"build": [["points", "styles", "closed", "opts"], 3, "LevelRoad", true], "build_partial": [["points", "styles", "closed", "first_seg", "last_seg", "opts"], 5, "LevelRoad", true], "wrap": [["i"], 1, "int", false], "idx": [["s_m"], 1, "int", false], "surface": [["i", "lat", "h"], 2, "Vector3", false], "kind": [["i"], 1, "String", false], "style_at": [["i"], 1, "Dictionary", false], "treatment": [["i", "side"], 2, "float", false], "closest": [["p", "hint", "window"], 1, "int", false], "ray_hit": [["from", "dir"], 2, "Dictionary", false], "lateral": [["p", "i"], 2, "float", false], "anchor_s": [["a"], 1, "float", false], "anchor_i": [["a"], 1, "int", false], "s_to_anchor": [["s_m"], 1, "Dictionary", false], "group_of": [["seg_index"], 1, "int", false], "group_name": [["group"], 1, "String", false], "runs": [["pred", "with_gaps"], 1, "Array[PackedInt32Array]", false], "radius_at": [["i"], 1, "float", false], "export_path": [[], 0, "Dictionary", false]}},
	"LevelLine": {"base": "", "signals": [], "consts": [], "vars": [], "static_vars": [],
		"methods": {"racing": [["r", "held"], 1, "PackedFloat32Array", true], "speeds": [["r", "off", "vmax"], 2, "PackedFloat32Array", true], "apply": [["r", "off"], 2, "void", true]}},
	"LevelContext": {"base": "RefCounted", "signals": [], "consts": [], "vars": ["doc", "report", "styles", "main", "roads", "branches", "terrain", "meshes", "data", "props", "reserved", "pits", "setups", "registries", "preview", "flags"], "static_vars": [],
		"methods": {"ground": [["x", "z"], 2, "float", false], "seed_of": [["uid"], 1, "int", false], "rng": [["uid"], 1, "RandomNumberGenerator", false], "road": [["key"], 1, "LevelRoad", false], "side_point": [["r", "i", "side", "setback"], 4, "Vector3", false], "floor_y": [["r", "q", "near_i"], 3, "float", false], "clear_spot": [["r", "s_m", "side", "setback", "radius", "tries"], 4, "float", false], "has_model": [["key"], 1, "bool", false]}},
	"LevelMeshSet": {"base": "RefCounted", "signals": [], "consts": [], "vars": [], "static_vars": [],
		"methods": {"tri": [["kind", "material", "a", "b", "c", "n", "uv", "road", "group"], 6, "void", false], "strip": [["kind", "material", "a", "b", "ua", "ub", "v", "na", "nb", "road", "group"], 9, "void", false], "box": [["kind", "material", "xf", "size", "rep", "road", "group"], 4, "void", false], "quad": [["kind", "material", "p", "n", "uv", "road", "group"], 5, "void", false], "meshes": [[], 0, "Array[Dictionary]", false], "triangles": [[], 0, "int", false]}},
	"LevelGeometry": {"base": "", "signals": [], "consts": [], "vars": [], "static_vars": [],
		"methods": {"build_road": [["ctx", "r", "groups"], 2, "void", true], "start_line": [["ctx"], 1, "void", true], "barrier_of": [["r", "i", "side"], 3, "Dictionary", true]}},
	"LevelTerrain": {"base": "RefCounted", "signals": [], "consts": ["CHUNK", "TILE", "CLEAR"], "vars": ["res", "cell", "origin", "natural", "heights", "splat", "layers"], "static_vars": [],
		"methods": {"from_doc": [["doc"], 1, "LevelTerrain", true], "carve": [["roads", "flat", "blend", "rect", "pits", "skip"], 3, "void", false], "height_at": [["x", "z"], 2, "float", false], "natural_at": [["x", "z"], 2, "float", false], "normal_at": [["x", "z"], 2, "Vector3", false], "top": [[], 0, "float", false], "raycast": [["from", "dir", "max_d"], 2, "Vector3", false], "cell_of": [["x", "z"], 2, "Vector2i", false], "rect_of": [["center", "radius"], 2, "Rect2i", false], "influence_rect": [["r", "i0", "i1", "flat", "blend"], 5, "Rect2i", false], "chunk_count": [[], 0, "int", false], "chunks_in": [["rect"], 1, "Array[Vector2i]", false], "chunk_arrays": [["cx", "cz", "lod"], 2, "Array", false], "chunk_hash": [["cx", "cz"], 2, "int", false], "tiles_in": [["rect"], 1, "Array[Vector2i]", false], "tile_hash": [["tx", "tz"], 2, "int", false], "tile_body": [["tx", "tz"], 2, "StaticBody3D", false], "edge_skirt_arrays": [[], 0, "Array", false]}},
	"LevelCompiler": {"base": "", "signals": [], "consts": [], "vars": [], "static_vars": [],
		"methods": {"compile": [["doc", "opts"], 1, "LevelBuild", true], "compile_async": [["doc", "opts", "done"], 3, "int", true], "preview_segments": [["doc", "road_key", "point_uids", "prev"], 4, "LevelBuild", true], "registries": [[], 0, "Dictionary", true]}},
	"LevelBuild": {"base": "RefCounted", "signals": [], "consts": [], "vars": ["id", "revision", "data", "meta", "meshes", "terrain", "roads", "report", "flags", "stats", "partial"], "static_vars": [],
		"methods": {"instantiate": [["collision", "groups"], 0, "Node3D", false], "digest": [[], 0, "String", false], "digest_parts": [[], 0, "Dictionary", false], "facts": [[], 0, "Dictionary", false]}},
	"LevelValidate": {"base": "", "signals": [], "consts": ["TEXTS", "FIXES"], "vars": [], "static_vars": [],
		"methods": {"run": [["ctx"], 1, "void", true], "text": [["code", "args"], 2, "String", true]}},
	"LevelThemes": {"base": "", "signals": [], "consts": ["IDS", "THEMES"], "vars": [], "static_vars": [],
		"methods": {"title": [["id"], 1, "String", true], "ops": [["doc", "id"], 2, "Array", true]}},
	"LevelTemplates": {"base": "", "signals": [], "consts": ["IDS"], "vars": [], "static_vars": [],
		"methods": {"title": [["id"], 1, "String", true], "make": [["id", "track_name"], 2, "LevelDoc", true]}},
	"LevelBranches": {"base": "", "signals": [], "consts": [], "vars": [], "static_vars": [],
		"methods": {"build": [["ctx"], 1, "void", true], "flat_zones": [["doc"], 1, "Array", true], "safe_drop": [["ctx"], 1, "void", true], "adjust_lap_line": [["ctx", "off"], 2, "PackedFloat32Array", true], "racing": [["ctx"], 1, "void", true], "geometry": [["ctx"], 1, "void", true], "export_entries": [["ctx"], 1, "Array", true], "lint": [["ctx"], 1, "void", true], "legal": [["ctx"], 1, "Dictionary", true], "launch_speed": [["gap", "lift", "ramp_len", "drop", "g"], 4, "float", true]}},
	"LevelHazards": {"base": "", "signals": [], "consts": ["TYPES", "SETUP_TYPES"], "vars": [], "static_vars": [],
		"methods": {"pre_geometry": [["ctx"], 1, "void", true], "geometry": [["ctx"], 1, "void", true], "resolve": [["ctx"], 1, "Array", true], "lint": [["ctx"], 1, "void", true], "legal": [["ctx", "type_key"], 2, "PackedByteArray", true], "difficulty_p": [["type", "feel"], 2, "Dictionary", true], "seesaw_ops": [["doc", "point_uid", "on"], 3, "Array", true], "marker_model": [["type"], 1, "String", true]}},
	"LevelCrowds": {"base": "", "signals": [], "consts": ["ROLES", "MOODS", "EGGS"], "vars": [], "static_vars": [],
		"methods": {"compile": [["ctx"], 1, "void", true], "lint": [["ctx"], 1, "void", true]}},
	"LevelDress": {"base": "", "signals": [], "consts": [], "vars": [], "static_vars": [],
		"methods": {"ops": [["doc", "build", "opts"], 3, "Array", true], "items_ops": [["doc", "build"], 2, "Array", true], "pads_ops": [["doc", "build"], 2, "Array", true], "rails_ops": [["doc", "build", "radius"], 2, "Array", true], "scenery_ops": [["doc", "build", "theme_id"], 3, "Array", true], "crowd_ops": [["doc", "build"], 2, "Array", true], "palette": [["theme_id"], 1, "PackedStringArray", true]}},
	"LevelFixes": {"base": "", "signals": [], "consts": ["LABELS"], "vars": [], "static_vars": [],
		"methods": {"ops": [["issue", "doc", "build"], 3, "Array", true]}},
	"LevelBrush": {"base": "", "signals": [], "consts": [], "vars": [], "static_vars": [],
		"methods": {"dab_height": [["t", "h", "center", "radius", "strength", "mode", "falloff", "target", "seed_v"], 7, "Rect2i", true], "dab_splat": [["t", "s", "center", "radius", "strength", "layer", "falloff"], 7, "Rect2i", true], "band_splat": [["t", "s", "r", "i0", "i1", "side", "width", "layer"], 8, "Rect2i", true], "auto_paint": [["t", "s", "opts"], 3, "Rect2i", true], "region": [["h", "res", "rect"], 3, "PackedFloat32Array", true], "resample": [["doc", "size", "res"], 3, "Array", true]}},
	"CustomTracks": {"base": "", "signals": [], "consts": ["EDIT_ID"], "vars": [], "static_vars": ["last_error"],
		"methods": {"is_custom": [["id"], 1, "bool", true], "valid_id": [["id"], 1, "bool", true], "mine_dir": [[], 0, "String", true], "cache_dir": [[], 0, "String", true], "refresh": [["force"], 0, "void", true], "list": [["which"], 0, "Array[Dictionary]", true], "meta": [["id"], 1, "Dictionary", true], "has": [["id"], 1, "bool", true], "path": [["id"], 1, "String", true], "id_for_guid": [["guid"], 1, "String", true], "thumb": [["id"], 1, "Texture2D", true], "bytes": [["id"], 1, "PackedByteArray", true], "build_for": [["id"], 1, "LevelBuild", true], "prepare": [["id", "done"], 2, "void", true], "is_prepared": [["id"], 1, "bool", true], "put_memory": [["id", "build", "meta_d"], 3, "void", true], "set_current": [["id"], 1, "void", true], "forget": [["id"], 1, "void", true], "mark_unusable": [["id", "reason"], 2, "void", true], "unusable": [["id"], 1, "String", true], "cache_part": [["sha"], 1, "String", true], "cache_add": [["sha", "part_path", "facts"], 3, "String", true], "cache_touch": [["sha"], 1, "void", true], "evict": [["keep_sha"], 0, "void", true], "folders": [[], 0, "PackedStringArray", true], "add_folder": [["dir"], 1, "void", true], "find": [["name_or_id"], 1, "String", true], "keep": [["id"], 1, "Error", true], "remove": [["id"], 1, "Error", true], "import_file": [["src_path"], 1, "String", true], "note_saved": [["path", "facts"], 2, "String", true], "history": [["guid"], 1, "Array[Dictionary]", true]}},
	"TrackShare": {"base": "Node", "signals": ["progress_changed", "local_changed", "thumb_arrived"], "consts": ["CHUNK", "WIN_LOBBY", "WIN_LOBBY_MAX", "WIN_RACE", "RATE_LISTEN", "STALL", "RESTARTS", "PREP_TIMEOUT", "IDLE_KICK"], "vars": [], "static_vars": [],
		"methods": {"valid_cfg": [["cfg"], 1, "bool", true], "valid_rules": [["rules"], 1, "bool", true], "on_track_rule": [["id"], 1, "void", false], "check": [[], 0, "void", false], "tick": [["delta"], 1, "void", false], "drop": [["peer"], 1, "void", false], "reset": [[], 0, "void", false], "rotate": [[], 0, "bool", false], "retry": [[], 0, "void", false], "consent": [[], 0, "void", false], "state_of": [["peer"], 1, "String", false], "everyone_has_track": [[], 0, "bool", false], "waiting": [[], 0, "Array", false], "status_line": [[], 0, "String", false], "local_state": [[], 0, "Dictionary", false]}},
	"EditorSession": {"base": "RefCounted", "signals": [], "consts": [], "vars": ["doc", "history", "path", "camera", "has_view", "top_view", "tool", "selection", "hidden", "clipboard", "last_drive", "return_to", "host_track", "build", "resources"], "static_vars": [],
		"methods": {"current": [[], 0, "EditorSession", true], "auto_name": [[], 0, "String", true], "is_open": [[], 0, "bool", false], "open": [["p"], 1, "String", false], "create": [["template_id", "track_name"], 1, "void", false], "open_copy": [["p", "as_remix"], 2, "String", false], "save": [["p", "header_extra", "done"], 0, "void", false], "autosave": [[], 0, "void", false], "recovery_for": [["p"], 1, "String", false], "dirty": [[], 0, "bool", false], "mark_clean": [[], 0, "void", false], "close": [[], 0, "void", false], "keep": [["res"], 1, "void", false], "drive_blocker": [[], 0, "String", false], "start_test_drive": [["tree", "opts", "done"], 3, "void", false]}},
	"EditHistory": {"base": "RefCounted", "signals": ["changed"], "consts": ["MAX_STEPS", "MAX_BYTES"], "vars": [], "static_vars": [],
		"methods": {"_init": [["d"], 1, "void", false], "commit": [["step_name", "ops", "merge_key"], 2, "void", false], "push_applied": [["step_name", "do_ops", "undo_ops"], 3, "void", false], "begin_gesture": [["step_name"], 1, "void", false], "end_gesture": [[], 0, "void", false], "undo": [[], 0, "bool", false], "redo": [[], 0, "bool", false], "can_undo": [[], 0, "bool", false], "can_redo": [[], 0, "bool", false], "undo_name": [[], 0, "String", false], "redo_name": [[], 0, "String", false], "clear": [[], 0, "void", false]}},
	"EditorHit": {"base": "RefCounted", "signals": [], "consts": [], "vars": ["hit", "pos", "normal", "what", "kind", "uid", "sub", "road", "sample", "s", "lat", "screen", "ray_from", "ray_dir"], "static_vars": [],
		"methods": {}},
	"EditorMarkers": {"base": "Control", "signals": [], "consts": ["Shape", "SIZE", "PICK_PX", "DIM"], "vars": [], "static_vars": [],
		"methods": {"begin": [["tool_id"], 1, "void", false], "add": [["kind", "uid", "pos", "shape", "color", "world_size", "sub"], 5, "void", false], "set_live": [["kinds"], 1, "void", false], "set_hover": [["kind", "uid", "sub"], 2, "void", false], "set_selected": [["uids"], 1, "void", false], "set_issues": [["report"], 1, "void", false], "set_rescues": [["points"], 1, "void", false], "pick": [["screen", "cam"], 2, "Dictionary", false], "pick_rect": [["rect", "cam"], 2, "Array", false]}},
	"EditorTool": {"base": "RefCounted", "signals": [], "consts": ["MOD_SHIFT", "MOD_CTRL", "MOD_ALT"], "vars": ["editor", "id", "title", "purpose"], "static_vars": [],
		"methods": {"_init": [["ed"], 1, "void", false], "kinds": [[], 0, "PackedStringArray", false], "markers": [["m"], 1, "void", false], "activate": [[], 0, "void", false], "deactivate": [[], 0, "void", false], "options": [["box"], 1, "void", false], "inspect": [["uids", "box"], 2, "bool", false], "hints": [["hit"], 1, "Array", false], "status_step": [[], 0, "String", false], "click": [["hit", "mods"], 2, "bool", false], "double_click": [["hit", "mods"], 2, "bool", false], "drag_begin": [["hit", "mods"], 2, "bool", false], "drag_move": [["hit", "mods"], 2, "void", false], "drag_end": [["hit", "mods"], 2, "void", false], "wheel": [["hit", "mods", "notches"], 3, "bool", false], "key": [["ev"], 1, "bool", false], "slide": [["uid", "hit", "phase"], 3, "Array", false], "process": [["delta"], 1, "void", false], "overlay": [["d"], 1, "void", false], "on_doc_changed": [["sections", "uids"], 2, "void", false], "delete_ops": [["uids"], 1, "Array", false], "item_aabb": [["uid"], 1, "AABB", false], "succeeded": [[], 0, "void", false]}},
	"SelectTool": {"base": "EditorTool", "signals": [], "consts": [], "vars": [], "static_vars": [],
		"methods": {"copy_selection": [["ed", "cut"], 1, "void", true], "paste": [["ed", "in_place"], 1, "void", true], "duplicate_selection": [["ed"], 1, "void", true], "delete_selection": [["ed"], 1, "void", true], "nudge_height": [["ed", "dir"], 2, "void", true], "drop_to_surface": [["ed", "align"], 2, "void", true]}},
	"TrackEditor": {"base": "Node3D", "signals": ["hover_changed", "baked"], "consts": ["TOOL_IDS"], "vars": ["session", "doc", "history", "view", "camera", "selection", "gizmo", "draw", "markers", "ui", "tools", "tool", "build", "preview", "hover", "trail"], "static_vars": [],
		"methods": {"set_tool": [["tool_id"], 1, "void", false], "pick": [["screen", "kinds"], 1, "EditorHit", false], "road_hit": [["screen"], 1, "EditorHit", false], "free_rect": [[], 0, "Rect2", false], "free_center": [[], 0, "Vector2", false], "commit": [["step_name", "ops", "merge_key"], 2, "void", false], "select": [["uids", "add"], 1, "void", false], "kind_of": [["uid"], 1, "String", false], "road": [["key"], 1, "LevelRoad", false], "terrain": [[], 0, "LevelTerrain", false], "flags": [["name"], 1, "PackedByteArray", false], "preview_roads": [["road_key", "point_uids"], 2, "void", false], "settle": [["road_key", "point_uids"], 2, "void", false], "bake_soon": [["delay"], 0, "void", false], "bake_now": [["done"], 1, "void", false], "toast": [["text"], 1, "void", false], "status": [["text"], 1, "void", false], "frame": [["aabb"], 1, "void", false], "frame_issue": [["issue"], 1, "void", false], "open_dialog": [["d"], 1, "void", false], "test_drive": [["from", "screen"], 1, "void", false], "auto_dress": [["opts"], 1, "void", false], "apply_fix": [["issue"], 1, "void", false], "save": [["as_new"], 0, "void", false], "host_online": [[], 0, "void", false], "exit_to": [["where"], 1, "void", false]}},
	"LevelView": {"base": "Node3D", "signals": ["applied"], "consts": [], "vars": [], "static_vars": [],
		"methods": {"setup": [["ed"], 1, "void", false], "show_build": [["b"], 1, "void", false], "show_roads": [["b", "changed"], 2, "void", false], "update_terrain": [["rect", "collision"], 2, "void", false], "sync_props": [["uids"], 1, "void", false], "set_env": [["data"], 1, "void", false], "set_hidden": [["uids"], 1, "void", false], "busy": [[], 0, "bool", false]}},
	"EditorDraw": {"base": "MeshInstance3D", "signals": [], "consts": [], "vars": [], "static_vars": [],
		"methods": {"clear": [[], 0, "void", false], "line": [["a", "b", "color", "on_top"], 3, "void", false], "polyline": [["points", "color", "closed", "on_top"], 2, "void", false], "polyline_colors": [["points", "colors", "on_top"], 2, "void", false], "circle": [["center", "normal", "radius", "color", "segments"], 4, "void", false], "ground_circle": [["t", "center", "radius", "color"], 4, "void", false], "box": [["aabb", "color"], 2, "void", false], "strip_on_road": [["r", "s0", "s1", "lat0", "lat1", "color"], 6, "void", false], "flags_on_road": [["r", "flags", "ok", "bad"], 4, "void", false]}},
	"EditorInput": {"base": "", "signals": [], "consts": [], "vars": [], "static_vars": [],
		"methods": {"apply": [[], 0, "void", true], "base_key": [["action"], 1, "String", true]}},
	"EditorCamera": {"base": "Camera3D", "signals": [], "consts": [], "vars": ["speed", "top"], "static_vars": [],
		"methods": {"fly_input": [["ev"], 1, "bool", false], "pad_fly": [["delta"], 1, "void", false], "frame": [["aabb", "rect"], 2, "void", false], "go_to": [["xf"], 1, "void", false], "toggle_top": [["pivot"], 1, "void", false]}},
	"EditSelection": {"base": "RefCounted", "signals": ["changed"], "consts": [], "vars": ["uids"], "static_vars": [],
		"methods": {"set_to": [["list"], 1, "void", false], "add": [["list"], 1, "void", false], "toggle": [["uid"], 1, "void", false], "clear": [[], 0, "void", false], "has": [["uid"], 1, "bool", false]}},
	"Gizmo3D": {"base": "Node3D", "signals": ["moved"], "consts": [], "vars": ["mode", "local"], "static_vars": [],
		"methods": {"attach": [["xf", "can_rotate_all"], 2, "void", false], "detach": [[], 0, "void", false], "pick": [["screen", "cam"], 2, "int", false], "drag": [["handle", "screen", "cam", "phase", "snap"], 5, "void", false]}},
	"EditorUI": {"base": "Control", "signals": [], "consts": [], "vars": [], "static_vars": [],
		"methods": {"setup": [["ed"], 1, "void", false], "refresh_tool": [[], 0, "void", false], "refresh_inspector": [[], 0, "void", false], "refresh_status": [[], 0, "void", false], "set_report": [["r"], 1, "void", false], "set_stats": [["stats"], 1, "void", false], "show_card": [["text"], 1, "void", false], "hide_card": [[], 0, "void", false], "toast": [["text"], 1, "void", false], "open_menu": [[], 0, "void", false], "open_help": [[], 0, "void", false], "is_typing": [[], 0, "bool", false]}},
	"EditorKit": {"base": "", "signals": [], "consts": ["ROW_H", "FONT"], "vars": [], "static_vars": [],
		"methods": {"theme": [[], 0, "Theme", true], "prompt": [["text"], 1, "String", true], "section": [["text"], 1, "Label", true], "row": [["label", "c", "tip"], 2, "HBoxContainer", true], "number": [["value", "min_v", "max_v", "step", "on_change", "fmt", "suffix"], 5, "EditorNumber", true], "vec3": [["value", "on_change", "step"], 2, "HBoxContainer", true], "color": [["value", "on_change"], 2, "Button", true], "check": [["on", "on_change"], 2, "CheckButton", true], "choice": [["items", "selected", "on_change"], 3, "OptionButton", true], "slider": [["min_v", "max_v", "step", "value", "on_change", "fmt"], 5, "HBoxContainer", true], "button": [["text", "cb", "tip"], 2, "Button", true], "toggle": [["text", "on", "cb"], 3, "Button", true], "text": [["value", "on_change", "max_len"], 2, "LineEdit", true], "list": [["items", "on_pick"], 2, "ItemList", true], "hint": [["text"], 1, "PromptLabel", true], "modes": [["items", "selected", "on_select"], 3, "HBoxContainer", true]}},
	"MaterialPicker": {"base": "Dialog", "signals": ["picked"], "consts": [], "vars": [], "static_vars": [],
		"methods": {"_init": [["current", "prefixes"], 1, "void", false]}},
	"HintCard": {"base": "PanelContainer", "signals": [], "consts": [], "vars": [], "static_vars": [],
		"methods": {"maybe_show": [["ed", "tool_id"], 2, "void", true], "done": [["ed", "tool_id"], 2, "void", true], "recall": [["ed", "tool_id"], 2, "void", true]}},
	"HelpOverlay": {"base": "Control", "signals": [], "consts": [], "vars": [], "static_vars": [],
		"methods": {"_init": [["ed"], 1, "void", false]}},
}

var t: Node


func run(t_: Node) -> void:
	t = t_
	_classes()
	_doc_basics()
	_fuzz()
	_snapshots()
	_report()
	_styles()
	_seeds()


# ---------------------------------------------------------------- the contract

func _classes() -> void:
	var global := {}
	for c in ProjectSettings.get_global_class_list():
		global[str(c["class"])] = str(c["path"])
	for cls in PATHS:
		var path: String = PATHS[cls][0]
		t.check(global.get(cls, "") == path, "%s is a global class at %s (found %s)" % [cls, path, global.get(cls, "none")])
		var scr = load(path)
		if scr == null or not (scr is GDScript):
			t.fail("%s loads" % path)
			continue
		var g: GDScript = scr
		t.check(g.can_instantiate(), "%s compiles (can_instantiate)" % path)
		if not g.can_instantiate():
			continue
		_check_base(cls, g)
		if API.has(cls):
			_check_api(cls, g, API[cls])
		for sg in EXTRA_SIGNALS.get(cls, []):
			t.check(g.has_script_signal(sg), "%s has signal %s" % [cls, sg])
	for cls in API:
		t.check(PATHS.has(cls), "7.3 class %s is listed in 7.1" % cls)
	var ps = load("res://scenes/editor.tscn")
	var root: Node = ps.instantiate() if ps is PackedScene else null
	t.check(root is TrackEditor, "scenes/editor.tscn has a TrackEditor root")
	if root != null:
		root.free()


func _check_base(cls: String, g: GDScript) -> void:
	var want := ""
	if API.has(cls):
		want = str(API[cls].base)
	if want == "":
		want = str(PATHS[cls][1])
	if cls in TOOLS:
		want = "EditorTool"
	var base_scr := g.get_base_script()
	if want == "" or want == "RefCounted":
		t.check(base_scr == null and g.get_instance_base_type() == &"RefCounted",
			"%s extends RefCounted (got %s)" % [cls, g.get_instance_base_type()])
	elif ClassDB.class_exists(want):
		t.check(base_scr == null and g.get_instance_base_type() == StringName(want),
			"%s extends %s (got %s)" % [cls, want, g.get_instance_base_type()])
	else:
		var got: StringName = base_scr.get_global_name() if base_scr != null else &""
		t.check(got == StringName(want), "%s extends %s (got %s)" % [cls, want, got])


## Method infos of a script and its base scripts, by name (the script's own first).
func _methods(g: GDScript) -> Dictionary:
	var out := {}
	var s: Script = g
	while s != null:
		for m in s.get_script_method_list():
			if not out.has(m.name):
				out[m.name] = m
		s = s.get_base_script()
	return out


func _props(g: GDScript) -> Dictionary:
	var out := {}
	var s: Script = g
	while s != null:
		for p in s.get_script_property_list():
			out[p.name] = p
		s = s.get_base_script()
	return out


func _check_api(cls: String, g: GDScript, api: Dictionary) -> void:
	for sg in api.signals:
		t.check(g.has_script_signal(sg), "%s has signal %s" % [cls, sg])
	var consts := g.get_script_constant_map()
	for c in api.consts:
		t.check(consts.has(c), "%s has const %s" % [cls, c])
	var props := _props(g)
	for v in api.vars:
		t.check(props.has(v), "%s has var %s" % [cls, v])
	for v in api.static_vars:
		t.check(props.has(v) or g.get(v) != null, "%s has static var %s" % [cls, v])
	var methods := _methods(g)
	for mname in api.methods:
		var spec: Array = api.methods[mname]
		if not methods.has(mname):
			t.fail("%s has method %s" % [cls, mname])
			continue
		var m: Dictionary = methods[mname]
		var names := []
		for a in m.args:
			names.append(str(a.name))
		var want_names: Array = spec[0]
		var required: int = names.size() - (m.default_args as Array).size()
		var sig := "%s.%s(%s)" % [cls, mname, ", ".join(want_names)]
		t.check(names.slice(0, want_names.size()) == want_names, "%s: argument names %s" % [sig, str(names)])
		t.check(required == int(spec[1]), "%s: %d required arguments (got %d)" % [sig, spec[1], required])
		var is_static := (int(m.flags) & METHOD_FLAG_STATIC) != 0
		t.check(is_static == bool(spec[3]), "%s: static %s" % [sig, str(spec[3])])
		var ret: String = spec[2]
		var want_t := "Object"
		if ret == "void" or ret == "Variant":
			want_t = "Nil"
		elif ret == "Error":
			want_t = "int"
		elif ret.begins_with("Array["):
			want_t = "Array"
		elif ret in BUILTIN:
			want_t = ret
		var got_t := type_string(int(m["return"].type))
		if mname != "_init":
			t.check(got_t == want_t, "%s -> %s (got %s)" % [sig, ret, got_t])
		if want_t == "Object":
			var cn := str(m["return"].get("class_name", ""))
			t.check(cn == "" or cn == ret, "%s -> %s (class %s)" % [sig, ret, cn])


# ---------------------------------------------------------------- LevelDoc

func _doc_basics() -> void:
	var d := LevelDoc.blank("Skeleton Run", 512.0, 257)
	t.check(d.data.format == LevelDoc.FORMAT and d.data.kind == LevelDoc.KIND, "blank: format and kind")
	t.check(str(d.data.guid).length() == 32, "blank: a 32-hex guid")
	t.check(d.data.short == "SKELETON RUN", "blank: short name")
	t.check(d.res() == 257 and is_equal_approx(d.cell(), 2.0) and d.origin() == Vector2(-256, -256), "res / cell / origin")
	t.check(d.heights.size() == 257 * 257 and d.splat.size() == 257 * 257 * 4, "blank: heights and splat sized")
	var keys := ["road", "branches", "styles", "terrain", "props", "items", "crates", "pads", "barrels", "hazards",
		"crowds", "eggs", "lights", "fires", "lakes", "zones", "screens", "env", "water", "race", "world"]
	for k in keys:
		t.check(d.data.has(k), "blank has %s" % k)
	var flat := LevelDoc.blank("No Ground", 2048.0, 0)
	t.check(not flat.data.world.terrain and flat.heights.is_empty() and flat.res() == 513 and not flat.has_terrain(), "blank without terrain")
	t.check(d.has_terrain() and is_equal_approx(d.world_size(), 512.0), "has_terrain / world_size")
	var u1 := d.new_uid()
	var u2 := d.new_uid()
	t.check(u1 == 1 and u2 == 2 and int(d.data.next_uid) == 3, "new_uid counts up")
	var seen := {}
	var count := [0]
	d.changed.connect(func(secs: PackedStringArray, uids: PackedInt32Array, rect: Rect2i) -> void:
		count[0] += 1
		seen["secs"] = secs
		seen["uids"] = uids
		seen["rect"] = rect)
	var rev := d.revision
	var p1 := d.new_uid()
	var p2 := d.new_uid()
	var b1 := d.new_uid()
	var bp := d.new_uid()
	var pr := d.new_uid()
	var inv := d.apply([
		LevelDoc.op_insert(["road", "points"], -1, {"uid": p1, "pos": [0, 0, 0], "width": 14.0}),
		LevelDoc.op_insert(["road", "points"], -1, {"uid": p2, "pos": [50, 0, 0], "width": 14.0}),
		LevelDoc.op_insert(["branches"], 0, {"uid": b1, "name": "CUT", "points": [{"uid": bp, "pos": [10, 0, 20]}]}),
		LevelDoc.op_insert(["props"], 0, {"uid": pr, "model": "x", "pos": [1, 2, 3], "road": -1}),
		LevelDoc.op_heights(Rect2i(2, 3, 2, 1), PackedFloat32Array([5.0, 6.0])),
	])
	t.check(count[0] == 1 and d.revision == rev + 1, "apply emits changed once and bumps revision")
	var secs: PackedStringArray = seen.get("secs", PackedStringArray())
	t.check("road" in secs and "branches" in secs and "props" in secs and "terrain" in secs, "changed names the sections (%s)" % str(secs))
	var uids: PackedInt32Array = seen.get("uids", PackedInt32Array())
	t.check(p1 in uids and bp in uids and pr in uids, "changed names the uids")
	t.check(seen.get("rect", Rect2i()) == Rect2i(2, 3, 2, 1), "changed carries the terrain rect")
	t.check(inv.size() == 5 and inv[0][0] == "heights" and inv[4][0] == "remove", "inverse ops in reverse order")
	t.check(is_equal_approx(d.heights[3 * 257 + 2], 5.0) and is_equal_approx(d.heights[3 * 257 + 3], 6.0), "heights op writes the rect")
	var f := d.find(p2)
	t.check(f.get("section") == "road" and f.get("index") == 1 and f.get("road") == -1, "find: a road point")
	var fb := d.find(bp)
	t.check(fb.get("section") == "branches" and fb.get("road") == b1 and fb.get("index") == 0, "find: a branch point")
	t.check(d.find(b1).get("road") == b1 and d.find(pr).get("section") == "props", "find: a branch and a prop")
	t.check(d.find(999).is_empty() and d.find(0).is_empty(), "find: unknown uid")
	t.check(d.path_of(bp) == ["branches", "#%d" % b1, "points", "#%d" % bp], "path_of a branch point")
	t.check(d.get_at(fb.path) is Dictionary and d.get_at(["branches", "#%d" % b1, "name"]) == "CUT", "get_at by #uid")
	t.check(d.get_at(["props", 0, "pos", 1]) == 2 and d.get_at(["nope", 1]) == null, "get_at by index, missing path")
	d.apply(inv)
	t.check(d.data.road.points.is_empty() and d.data.props.is_empty() and is_zero_approx(d.heights[3 * 257 + 2]), "inverse undoes it")
	t.check(d.find(pr).is_empty(), "find after undo")
	# set of a missing key inverts to erase
	var inv2 := d.apply([LevelDoc.op_set(["race", "new_key"], 5)])
	t.check(inv2.size() == 1 and inv2[0][0] == "erase", "set of a missing key inverts to erase")
	d.apply(inv2)
	t.check(not d.data.race.has("new_key"), "erase restores it")
	var rev2 := d.revision
	var calls: int = count[0]
	t.check(d.apply([LevelDoc.op_erase(["race", "not_there"])]).is_empty() and d.revision == rev2 and count[0] == calls, "a no-op apply: no inverse, no signal, same revision")
	# a set that changes an element's uid: the inverse follows the new uid
	var q := d.new_uid()
	var q2 := d.new_uid()
	d.apply([LevelDoc.op_insert(["props"], -1, {"uid": q, "model": "a"})])
	var inv3 := d.apply([LevelDoc.op_set(["props", "#%d" % q], {"uid": q2, "model": "b"})])
	t.check(inv3[0][1] == ["props", "#%d" % q2], "inverse path follows a changed uid")
	d.apply(inv3)
	t.check(d.data.props[0].uid == q and d.data.props[0].model == "a", "uid change undone")
	# values are copied in
	var v := {"uid": d.new_uid(), "pos": [0, 0, 0]}
	d.apply([LevelDoc.op_insert(["props"], -1, v)])
	v.pos[0] = 99
	t.check(d.data.props[-1].pos[0] == 0, "apply copies values in")
	# a region at the origin is a region; a whole replace says so
	var inv5 := d.apply([LevelDoc.op_heights(Rect2i(0, 0, 2, 2), PackedFloat32Array([1, 1, 1, 1]))])
	t.check(d.heights.size() == 257 * 257 and is_equal_approx(d.heights[258], 1.0), "a 2x2 region at the origin")
	d.apply(inv5)
	var small := PackedFloat32Array()
	small.resize(129 * 129)
	small.fill(3.0)
	var inv4 := d.apply([LevelDoc.op_heights_all(small)])
	t.check(d.heights.size() == 129 * 129, "a whole heights replace")
	d.apply(inv4)
	t.check(d.heights.size() == 257 * 257 and is_zero_approx(d.heights[0]), "and back")


func _seed_doc(d: LevelDoc, rng: RandomNumberGenerator, next: Array) -> void:
	var ops := []
	for i in 6:
		ops.append(LevelDoc.op_insert(["road", "points"], -1, {"uid": _uid(next), "pos": [i * 30.0, 0.0, 0.0], "width": 14.0, "style": "asphalt"}))
	for i in 2:
		var pts := []
		for j in 3:
			pts.append({"uid": _uid(next), "pos": [j * 10.0, 0.0, 40.0 + i], "width": 10.0})
		ops.append(LevelDoc.op_insert(["branches"], -1, {"uid": _uid(next), "name": "B%d" % i, "points": pts, "ai": {"take": 0.5}}))
	for sec in ["props", "items", "hazards", "lights"]:
		for i in 4:
			ops.append(LevelDoc.op_insert([sec], -1, {"uid": _uid(next), "pos": [rng.randf_range(-100, 100), 0.0, rng.randf_range(-100, 100)], "tag": "deco"}))
	d.apply(ops)


func _uid(next: Array) -> int:
	next[0] += 1
	return next[0]


## A random valid op on the document's current state. `safe`: only ops that later ops of the same
## batch (drawn before it applies) cannot invalidate.
func _random_op(d: LevelDoc, rng: RandomNumberGenerator, next: Array, safe := false) -> Array:
	var lists := ["props", "items", "hazards", "lights"]
	var sec: String = lists[rng.randi() % lists.size()]
	var arr: Array = d.data[sec]
	var r := rng.randi() % 14
	if safe:
		r = [0, 1, 3, 8, 10, 11][rng.randi() % 6]
	match r:
		0, 1:
			if arr.is_empty():
				return LevelDoc.op_set(["env", "fog_sky"], rng.randf())
			var it: Dictionary = arr[rng.randi() % arr.size()]
			return LevelDoc.op_set([sec, "#%d" % int(it.uid), "pos"], [rng.randf(), rng.randf(), rng.randf()])
		2:
			if arr.is_empty():
				return LevelDoc.op_set(["name"], "N%d" % rng.randi())
			var i := rng.randi() % arr.size()
			return LevelDoc.op_set([sec, i, "pos", rng.randi() % 3], rng.randf_range(-5, 5))
		3:
			if arr.is_empty():
				return LevelDoc.op_set(["desc"], "D")
			var it2: Dictionary = arr[rng.randi() % arr.size()]
			return LevelDoc.op_set([sec, "#%d" % int(it2.uid), "extra%d" % (rng.randi() % 3)], rng.randi() % 100)
		4:
			if arr.is_empty():
				return LevelDoc.op_set(["theme"], "coast")
			var it3: Dictionary = arr[rng.randi() % arr.size()]
			var k := "tag" if rng.randf() < 0.5 else "extra0"
			if not it3.has(k):
				return LevelDoc.op_set([sec, "#%d" % int(it3.uid), k], "x")
			return LevelDoc.op_erase([sec, "#%d" % int(it3.uid), k])
		5, 6:
			return LevelDoc.op_insert([sec], rng.randi_range(-1, arr.size() + 1), {"uid": _uid(next), "pos": [rng.randf(), 0.0, rng.randf()], "tag": ""})
		7:
			if arr.size() < 2:
				return LevelDoc.op_set(["race", "laps"], rng.randi_range(1, 9))
			if rng.randf() < 0.5:
				return LevelDoc.op_remove([sec], rng.randi() % arr.size())
			var it4: Dictionary = arr[rng.randi() % arr.size()]
			return ["remove", [sec], "#%d" % int(it4.uid)]
		8:
			var pts: Array = d.data.road.points
			var pi := rng.randi() % pts.size()
			return LevelDoc.op_set(["road", "points", pi, "width"], rng.randf_range(6, 40))
		9:
			var br: Array = d.data.branches
			var b: Dictionary = br[rng.randi() % br.size()]
			var bpts: Array = b.points
			if rng.randf() < 0.5 or bpts.size() < 2:
				return LevelDoc.op_insert(["branches", "#%d" % int(b.uid), "points"], rng.randi_range(0, bpts.size()),
					{"uid": _uid(next), "pos": [rng.randf(), 0.0, rng.randf()]})
			var bp: Dictionary = bpts[rng.randi() % bpts.size()]
			return LevelDoc.op_set(["branches", "#%d" % int(b.uid), "points", "#%d" % int(bp.uid), "pos", 1], rng.randf_range(0, 9))
		10:
			var res_g := int(round(sqrt(d.heights.size())))
			var w := rng.randi_range(1, 9)
			var h := rng.randi_range(1, 9)
			var vals := PackedFloat32Array()
			vals.resize(w * h)
			for i in vals.size():
				vals[i] = snappedf(rng.randf_range(-500, 1500), 0.01)
			return LevelDoc.op_heights(Rect2i(rng.randi_range(-2, res_g - 3), rng.randi_range(-2, res_g - 3), w, h), vals)
		11:
			var res_s := int(round(sqrt(d.splat.size() / 4.0)))
			var w2 := rng.randi_range(1, 6)
			var h2 := rng.randi_range(1, 6)
			var sv := PackedByteArray()
			sv.resize(w2 * h2 * 4)
			for i in sv.size():
				sv[i] = rng.randi() % 256
			return LevelDoc.op_splat(Rect2i(rng.randi_range(0, res_s - w2), rng.randi_range(0, res_s - h2), w2, h2), sv)
		12:
			# replace a whole element, sometimes with a new uid
			if arr.is_empty():
				return LevelDoc.op_set(["water", "level"], rng.randf())
			var it5: Dictionary = arr[rng.randi() % arr.size()]
			var nu := int(it5.uid) if rng.randf() < 0.5 else _uid(next)
			return LevelDoc.op_set([sec, "#%d" % int(it5.uid)], {"uid": nu, "pos": [1.0, 2.0, 3.0], "whole": true})
		_:
			# a whole heights replace (another size), sometimes
			if rng.randf() < 0.3:
				var cur := int(round(sqrt(d.heights.size())))
				var nr := 129 if cur == 257 else 257
				var full := PackedFloat32Array()
				full.resize(nr * nr)
				full.fill(snappedf(rng.randf_range(0, 10), 0.01))
				return LevelDoc.op_heights_all(full)
			return LevelDoc.op_set(["env", "glow"], rng.randf())


func _fuzz() -> void:
	var d := LevelDoc.blank("Fuzz", 512.0, 257)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261119
	var next := [1000]
	_seed_doc(d, rng, next)
	var before := d.data.duplicate(true)
	var hb := d.heights.duplicate()
	var sb := d.splat.duplicate()
	var done := []
	var undo := []
	var applied := 0
	var skipped := 0
	while applied < 300:
		var batch := []
		var n := 1 if rng.randf() < 0.75 else rng.randi_range(2, 4)
		for i in n:
			batch.append(_random_op(d, rng, next, n > 1))
			applied += 1
		var inv := d.apply(batch)
		skipped += batch.size() - inv.size()
		done.append(batch.duplicate(true))
		undo.append(inv)
	t.check(skipped == 0, "fuzz: every op applied (%d skipped)" % skipped)
	var after := d.data.duplicate(true)
	var ha := d.heights.duplicate()
	var sa := d.splat.duplicate()
	t.check(after != before, "fuzz: the ops changed the document")
	for i in range(undo.size() - 1, -1, -1):
		d.apply(undo[i])
	t.check(d.data == before, "fuzz: 300 ops undone give the identical data")
	t.check(JSON.stringify(d.data) == JSON.stringify(before), "fuzz: identical JSON")
	t.check(d.heights == hb and d.splat == sb, "fuzz: identical heights and splat")
	var redo_inv := []
	for b in done:
		redo_inv.append(d.apply(b))
	t.check(d.data == after and d.heights == ha and d.splat == sa, "fuzz: redone gives the same state again")
	for i in range(redo_inv.size() - 1, -1, -1):
		d.apply(redo_inv[i])
	t.check(d.data == before and d.heights == hb and d.splat == sb, "fuzz: undone again")


func _snapshots() -> void:
	var d := LevelDoc.blank("Snap", 512.0, 257)
	var a := d.new_uid()
	d.apply([LevelDoc.op_insert(["props"], -1, {"uid": a, "model": "m", "pos": [1, 2, 3]})])
	var s1 := d.snapshot()
	t.check(s1.revision == d.revision and s1.data == d.data and s1.heights == d.heights, "snapshot equals the doc")
	t.check(not is_same(s1.data.props, d.data.props), "a snapshot shares nothing with the live doc")
	d.apply([LevelDoc.op_set(["props", "#%d" % a, "pos"], [9, 9, 9]), LevelDoc.op_set(["name"], "Changed"),
		LevelDoc.op_heights(Rect2i(0, 0, 1, 1), PackedFloat32Array([42.0]))])
	t.check(s1.data.props[0].pos == [1, 2, 3] and s1.data.name == "Snap", "a change after a snapshot never shows in it")
	t.check(is_zero_approx(s1.heights[0]), "a heights change after a snapshot never shows in it")
	var s2 := d.snapshot()
	t.check(s2.data.props[0].pos == [9, 9, 9] and s2.data.name == "Changed" and is_equal_approx(s2.heights[0], 42.0), "the next snapshot sees the changes")
	t.check(is_same(s2.data.env, s1.data.env) and is_same(s2.data.road, s1.data.road), "unchanged sections are shared with the last snapshot")
	t.check(not is_same(s2.data.props, s1.data.props), "changed sections are copied")
	d.apply([LevelDoc.op_set(["env", "glow"], 1.2)])
	t.check(is_equal_approx(float(s2.data.env.glow), 0.35) and is_equal_approx(float(s1.data.env.glow), 0.35), "a shared section stays frozen in both")
	# a direct write needs notify
	d.data.race.laps = 7
	d.notify(PackedStringArray(["race"]))
	var s3 := d.snapshot()
	t.check(int(s3.data.race.laps) == 7 and int(s2.data.race.laps) == 3, "notify marks a direct write for the next snapshot")
	t.check(not is_same(s3.data.env, s2.data.env) and is_same(s3.data.props, s2.data.props), "only the sections changed since the last snapshot are copied")
	# a brush-like direct heights write + notify(terrain)
	d.heights[5] = 7.5
	d.notify(PackedStringArray(["terrain"]), PackedInt32Array(), Rect2i(5, 0, 1, 1))
	var s4 := d.snapshot()
	t.check(is_equal_approx(s4.heights[5], 7.5) and is_zero_approx(s3.heights[5]), "notify(terrain) copies the heights")
	# replacing data copies everything
	d.data = d.data.duplicate(true)
	var s5 := d.snapshot()
	t.check(not is_same(s5.data.road, s4.data.road) and s5.data == s4.data, "a replaced data dict is copied whole")


# ---------------------------------------------------------------- LevelReport

func _report() -> void:
	var r := LevelReport.new()
	t.check(r.raceable() and r.fatal() == "" and r.blocks_drive() == "" and r.errors() == 0, "an empty report")
	r.warning("no_items", "No item crates on the lap yet.", {}, "auto_items")
	r.error("too_tight", "The bend 120 m after the start is too tight.", {"uid": 7, "road": -1, "s": 120.0, "pos": Vector3(1, 2, 3)}, "narrow")
	r.info("bot_lap", "A bot lap took 61 s.")
	r.error("crossing", "Two roads meet.", {"pos": [4, 5, 6], "name": "B1"})
	t.check(r.errors() == 2 and r.warnings() == 1 and r.count("info") == 1 and r.items.size() == 4, "counts by level")
	t.check(not r.raceable(), "errors make it not raceable")
	t.check(r.fatal() == "The bend 120 m after the start is too tight.", "fatal is the first error's text")
	t.check(r.blocks_drive() == "", "only cannot-build errors block a drive")
	var it := r.first("too_tight")
	t.check(it.fix == "narrow" and it.uid == 7 and it.road == -1 and is_equal_approx(it.s, 120.0) and it.pos == Vector3(1, 2, 3), "an item keeps where and fix")
	var it2 := r.first("crossing")
	t.check(it2.pos == Vector3(4, 5, 6) and it2.name == "B1" and it2.road == -2 and it2.uid == 0, "where as an array, extra keys, defaults")
	r.error("open_loop", "The road is not a closed loop.", {}, "close_loop")
	t.check(r.blocks_drive() == "The road is not a closed loop.", "open_loop blocks a drive")
	r.add_missing("models", 3)
	r.add_missing("materials")
	r.add_dropped("props", 2)
	r.add_dropped("thumb")
	t.check(r.missing.models == 3 and r.missing.materials == 1 and r.missing_total() == 4, "missing counts")
	t.check(r.dropped.props == 2 and r.dropped.thumb == 1, "dropped counts")
	var dct := r.to_dict()
	t.check(dct.errors == 3 and dct.warnings == 1 and (dct.items as Array).size() == 5, "to_dict counts")
	var back = JSON.parse_string(JSON.stringify(dct))
	t.check(back is Dictionary and back.items[1].pos == [1.0, 2.0, 3.0], "to_dict is JSON-friendly")
	var r2 := LevelReport.new()
	r2.error("compile", "The track could not be built.")
	r2.add_missing("music", 2)
	var r3 := LevelReport.new()
	r3.merge(r2)
	r3.merge(r)
	t.check(r3.blocks_drive() == "The track could not be built." and r3.errors() == 4 and r3.missing.music == 2, "merge")
	t.check(r3.all_of("too_tight").size() == 1 and r3.has("crossing") and not r3.has("steep"), "all_of / has")
	var r4 := LevelReport.new()
	r4.error("no_road", "")
	t.check(r4.blocks_drive() == "no_road" and r4.fatal() == "no_road", "an empty text falls back to the code")
	r3.clear()
	t.check(r3.items.is_empty() and r3.missing_total() == 0, "clear")


# ---------------------------------------------------------------- LevelStyles

func _styles() -> void:
	var fake := {}
	for id in LevelStyles.PRESETS:
		var st: Dictionary = LevelStyles.PRESETS[id]
		for k in LevelStyles.MAT_KEYS:
			if st.has(k) and str(st[k]) != "":
				fake[st[k]] = {}
		for side in ["barrier_l", "barrier_r"]:
			if st.get(side) is Dictionary:
				fake[st[side].mat] = {}
	for kind in LevelStyles.KIND_KEYS:
		for k in LevelStyles.KIND_KEYS[kind]:
			if k in LevelStyles.MAT_KEYS and str(LevelStyles.KIND_KEYS[kind][k]) != "":
				fake[LevelStyles.KIND_KEYS[kind][k]] = {}
	fake[LevelStyles.START_LINE_MAT] = {}
	t.check(LevelStyles.PRESETS.size() == 10 and LevelStyles.BARRIERS.size() == 4, "10 presets, 4 barriers")
	var doc := LevelDoc.blank("Styles").data
	doc.styles = {"my_road": {"name": "MINE", "kind": "street", "road": "nope/missing"}, "dirt": {"name": "OWN DIRT", "kind": "open"}}
	var res := LevelStyles.resolve(doc, fake)
	for id in LevelStyles.PRESETS:
		t.check(res.has(id), "resolve has preset %s" % id)
	var all_keys := true
	var none_missing := true
	for id in LevelStyles.PRESET_IDS:
		if id == "dirt":
			continue
		var st: Dictionary = res[id]
		for k in LevelStyles.BASE:
			all_keys = all_keys and st.has(k)
		for k in LevelStyles.KIND_KEYS[st.kind]:
			all_keys = all_keys and st.has(k)
		none_missing = none_missing and (st.missing as PackedStringArray).is_empty()
	t.check(all_keys, "every resolved preset has every base and kind key")
	t.check(none_missing, "presets resolve against the fake registry with nothing missing")
	var mine: Dictionary = res.my_road
	t.check(mine.kind == "street" and mine.own and mine.road == LevelStyles.FALLBACK_MAT and "road" in mine.missing, "a missing surface falls back and is listed")
	t.check(is_equal_approx(float(mine.curb_h), 0.16) and is_equal_approx(float(mine.walk), 4.0), "own styles get their kind's defaults")
	t.check(res.dirt.name == "OWN DIRT" and res.dirt.own, "an own style may shadow a preset id")
	var ids := LevelStyles.ids(doc)
	t.check(ids.size() == 11 and ids[0] == "asphalt" and ids[10] == "my_road", "ids: presets then own (%s)" % str(ids))
	t.check(res.asphalt_rail.barrier_l is Dictionary and res.asphalt_rail.barrier_l.kind == "fence" and is_equal_approx(float(res.asphalt_rail.barrier_l.off), 1.0), "barriers resolved")
	t.check(res.asphalt.barrier_l == null and res.asphalt.bank == true and res.bridge.bank == false, "no barrier, bank defaults")
	t.check(res.highway.road_u == "full" and res.sand.grip == "offroad", "preset keys kept")
	var bare := LevelStyles.resolve(doc, {})
	t.check((bare.my_road.missing as PackedStringArray).is_empty() and bare.my_road.road == "nope/missing", "no registry: keys kept")
	var presets_only := LevelStyles.resolve({}, fake)
	var tr := {"asphalt": 4.0, "asphalt_rail": 4.0, "highway": 4.0, "dirt": 3.0, "street": 4.35, "plaza": 4.8,
		"bridge": 1.5, "tunnel": 1.1}
	for id in tr:
		t.near(LevelStyles.treatment(presets_only[id], 0), tr[id], 0.001, "treatment of %s" % id)
		t.near(LevelStyles.treatment(presets_only[id], 1), tr[id], 0.001, "treatment of %s (right)" % id)
	var one_side: Dictionary = presets_only.street.duplicate(true)
	one_side.barrier_r = {"kind": "none"}
	t.near(LevelStyles.treatment(one_side, 1), 4.3, 0.001, "a NONE barrier override on one side")
	var b = LevelStyles.barrier("wall", 3.0)
	t.check(b is Dictionary and is_equal_approx(b.h, 3.0) and is_equal_approx(b.col_h, 3.0), "barrier(): HEIGHT and col_h")
	t.check(LevelStyles.barrier("style") == null and LevelStyles.barrier("none").kind == "none", "barrier(): STYLE and NONE")
	if t.content():
		var mats: Dictionary = t.get_node("/root/Game").get("materials_db")
		var miss := []
		for k in fake:
			if not mats.has(k):
				miss.append(k)
		t.check(miss.is_empty(), "every preset material is in this install's materials.json (%s)" % str(miss))


# ---------------------------------------------------------------- LevelContext seeds

func _seeds() -> void:
	var ctx := LevelContext.new()
	ctx.doc = LevelDoc.blank("Seeds")
	ctx.doc.data.guid = "0123456789abcdef0123456789abcdef"
	var hc := HashingContext.new()
	hc.start(HashingContext.HASH_SHA256)
	hc.update("0123456789abcdef0123456789abcdef:42".to_utf8_buffer())
	var h := hc.finish()
	var want := ((h[0] << 24) | (h[1] << 16) | (h[2] << 8) | h[3]) & 0x7fffffff
	t.check(ctx.seed_of(42) == want, "seed_of: sha256(guid:uid), 4 bytes big-endian, 31 bits")
	t.check(ctx.seed_of(42) >= 0 and ctx.seed_of(42) == ctx.seed_of(42) and ctx.seed_of(42) != ctx.seed_of(43), "seed_of is stable per uid")
	var a := ctx.rng(42)
	var b := ctx.rng(42)
	var same := true
	for i in 16:
		same = same and a.randi() == b.randi()
	t.check(same, "rng(uid) gives the same numbers")
	t.check(ctx.rng(42).randi() != ctx.rng(43).randi(), "rng differs per uid")
	var other := LevelContext.new()
	other.doc = LevelDoc.blank("Other")
	other.doc.data.guid = "ffffffffffffffffffffffffffffffff"
	t.check(other.seed_of(42) != ctx.seed_of(42), "seed_of depends on the guid")
