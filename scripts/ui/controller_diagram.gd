class_name ControllerDiagram
extends Control
## A big picture of a pad: Kenney's silhouette of the family (recoloured to the menus' grey), each
## button drawn in its place, lit when something is bound to it, and a leader line from every bound
## button to a label naming its action (a "callout" row: the binding's icon and the action). The
## labels sit in two columns beside the picture, fanned out so no two leaders cross.
## OPTIONS > CONTROLLER uses it big and interactive (press a label to rebind that slot: slot_pressed;
## X / Delete: clear_requested; the page listens and says what happened); the pause panel uses it
## compact. Draws itself again when the prompts change (device, family or a binding).
## Coordinates: the tables are in Kenney's SVG units (a 64x64 canvas); plan() maps them to pixels.

## A row was pressed (A / Enter / click), or a bound control on the picture clicked (interactive).
signal slot_pressed(action: String, slot: int)
## ui_clear (X / Delete / Backspace) on a row (interactive).
signal clear_requested(action: String, slot: int)
## The rows were placed again (after every refresh): the page sets the focus neighbours at the
## columns' edges here (the top row's up, the bottom row's down, the right column's right).
signal laid_out

## Kenney's silhouette for each pad style (art/input_prompts/devices/<stem>.svg).
const DEVICE_SVG := {
	"xbox": "controller_xboxseries",
	"xbox360": "controller_xbox360",
	"ps3": "controller_playstation3",
	"ps4": "controller_playstation4",
	"ps5": "controller_playstation5",
	"switch": "controller_switch_pro",
	"steamdeck": "controller_steamdeck",
	"generic": "controller_generic",
}
## The picture's box (SVG units): the outline and every icon above it.
const DEVICE_BOUNDS := {
	"xbox": Rect2(7.99, 6.1, 48.02, 41.9),
	"xbox360": Rect2(7.99, 6.11, 48, 42.88),
	"ps3": Rect2(8, 7.1, 48, 38.9),
	"ps4": Rect2(8, 7.1, 48, 38.91),
	"ps5": Rect2(7.99, 7.17, 48.02, 40.83),
	"switch": Rect2(8, 6.09, 48, 41.9),
	"steamdeck": Rect2(8, 11.1, 48, 32.9),
	"generic": Rect2(7.98, 5.14, 48.01, 41.81),
}
const DEVICE_ANCHORS := {
	"xbox": {
		"lt": {"kind": "above", "icon": Rect2(17.8, 6.1, 4.4, 4.4), "at": Vector2(17.8, 8.3), "side": -1},
		"lb": {"kind": "above", "icon": Rect2(17.4, 10.9, 5.2, 3.8), "at": Vector2(17.4, 12.8), "side": -1},
		"ls": {"kind": "hole", "icon": Rect2(17.26, 20.25, 6.5, 6.5), "at": Vector2(17, 23.5), "side": -1},
		"dpad": {"kind": "hole", "icon": Rect2(22.27, 29.24, 6.5, 6.5), "at": Vector2(22, 32.5), "side": -1},
		"back": {"kind": "marker", "icon": Rect2(27.2, 20.6, 2, 2), "at": Vector2(28.2, 20.6), "side": -1, "via": [Vector2(27.4, 16.9)]},
		"start": {"kind": "marker", "icon": Rect2(34.8, 20.6, 2, 2), "at": Vector2(35.8, 20.6), "side": 1, "via": [Vector2(36.6, 16.9)]},
		"rt": {"kind": "above", "icon": Rect2(41.8, 6.1, 4.4, 4.4), "at": Vector2(46.2, 8.3), "side": 1},
		"rb": {"kind": "above", "icon": Rect2(41.4, 10.9, 5.2, 3.8), "at": Vector2(46.6, 12.8), "side": 1},
		"face_n": {"kind": "hole", "icon": Rect2(41.2, 19.19, 3.6, 3.6), "at": Vector2(45, 21), "side": 1},
		"face_e": {"kind": "hole", "icon": Rect2(45.2, 23.19, 3.6, 3.6), "at": Vector2(49, 25), "side": 1},
		"face_w": {"kind": "hole", "icon": Rect2(37.2, 23.19, 3.6, 3.6), "at": Vector2(39, 23), "side": 1, "via": [Vector2(40.4, 18)]},
		"face_s": {"kind": "hole", "icon": Rect2(41.2, 27.19, 3.6, 3.6), "at": Vector2(45, 29), "side": 1},
		"rs": {"kind": "hole", "icon": Rect2(33.26, 29.25, 5.5, 5.5), "at": Vector2(38.6, 33.5), "side": 1},
	},
	"xbox360": {
		"lt": {"kind": "above", "icon": Rect2(17.55, 6.11, 4.4, 4.4), "at": Vector2(17.55, 8.31), "side": -1},
		"lb": {"kind": "above", "icon": Rect2(17.15, 10.91, 5.2, 3.8), "at": Vector2(17.15, 12.81), "side": -1},
		"ls": {"kind": "hole", "icon": Rect2(15.26, 22.25, 6.5, 6.5), "at": Vector2(15, 25.5), "side": -1},
		"dpad": {"kind": "hole", "icon": Rect2(23.26, 31.25, 6.5, 6.5), "at": Vector2(23, 34.5), "side": -1},
		"back": {"kind": "marker", "icon": Rect2(24.6, 23.3, 2, 1.4), "at": Vector2(25.6, 23.3), "side": -1, "via": [Vector2(25.2, 18.6)]},
		"start": {"kind": "marker", "icon": Rect2(37.4, 23.3, 2, 1.4), "at": Vector2(38.4, 23.3), "side": 1, "via": [Vector2(38.8, 18)]},
		"rt": {"kind": "above", "icon": Rect2(42.05, 6.11, 4.4, 4.4), "at": Vector2(46.45, 8.31), "side": 1},
		"rb": {"kind": "above", "icon": Rect2(41.65, 10.91, 5.2, 3.8), "at": Vector2(46.85, 12.81), "side": 1},
		"face_n": {"kind": "hole", "icon": Rect2(43.2, 21.19, 3.6, 3.6), "at": Vector2(47, 23), "side": 1},
		"face_e": {"kind": "hole", "icon": Rect2(47.2, 25.19, 3.6, 3.6), "at": Vector2(51, 27), "side": 1},
		"face_w": {"kind": "hole", "icon": Rect2(39.2, 25.19, 3.6, 3.6), "at": Vector2(41, 25), "side": 1, "via": [Vector2(42, 19.2)]},
		"face_s": {"kind": "hole", "icon": Rect2(43.2, 29.19, 3.6, 3.6), "at": Vector2(47, 31), "side": 1},
		"rs": {"kind": "hole", "icon": Rect2(34.26, 31.25, 6.5, 6.5), "at": Vector2(40.5, 36.2), "side": 1},
	},
	"ps3": {
		"lt": {"kind": "above", "icon": Rect2(15.8, 7.1, 4.4, 4.4), "at": Vector2(15.8, 9.3), "side": -1},
		"lb": {"kind": "above", "icon": Rect2(15.4, 11.9, 5.2, 3.8), "at": Vector2(15.4, 13.8), "side": -1},
		"ls": {"kind": "hole", "icon": Rect2(22.27, 31.26, 5.5, 5.5), "at": Vector2(22, 34), "side": -1},
		"dpad": {"kind": "hole", "icon": Rect2(13.2, 23.2, 9.6, 9.6), "at": Vector2(13, 28), "side": -1},
		"back": {"kind": "marker", "icon": Rect2(27.3, 22.8, 2.2, 1.2), "at": Vector2(28.4, 22.8), "side": -1, "via": [Vector2(28, 19)]},
		"start": {"kind": "marker", "icon": Rect2(34.5, 22.8, 2.2, 1.2), "at": Vector2(35.6, 22.8), "side": 1, "via": [Vector2(36, 19)]},
		"rt": {"kind": "above", "icon": Rect2(43.8, 7.1, 4.4, 4.4), "at": Vector2(48.2, 9.3), "side": 1},
		"rb": {"kind": "above", "icon": Rect2(43.4, 11.9, 5.2, 3.8), "at": Vector2(48.6, 13.8), "side": 1},
		"face_n": {"kind": "hole", "icon": Rect2(44.2, 22.19, 3.6, 3.6), "at": Vector2(48, 24), "side": 1},
		"face_e": {"kind": "hole", "icon": Rect2(48.2, 26.19, 3.6, 3.6), "at": Vector2(52, 28), "side": 1},
		"face_w": {"kind": "hole", "icon": Rect2(40.2, 26.19, 3.6, 3.6), "at": Vector2(42, 26), "side": 1, "via": [Vector2(42.9, 20.4)]},
		"face_s": {"kind": "hole", "icon": Rect2(44.2, 30.19, 3.6, 3.6), "at": Vector2(48, 32), "side": 1},
		"rs": {"kind": "hole", "icon": Rect2(36.27, 31.26, 5.5, 5.5), "at": Vector2(41.6, 35.5), "side": 1},
	},
	"ps4": {
		"lt": {"kind": "above", "icon": Rect2(15.05, 7.1, 4.4, 4.4), "at": Vector2(15.05, 9.3), "side": -1},
		"lb": {"kind": "above", "icon": Rect2(14.65, 11.9, 5.2, 3.8), "at": Vector2(14.65, 13.8), "side": -1},
		"ls": {"kind": "hole", "icon": Rect2(21.27, 29.26, 5.5, 5.5), "at": Vector2(21, 32), "side": -1},
		"dpad": {"kind": "hole", "icon": Rect2(13.2, 21.2, 9.6, 9.6), "at": Vector2(13, 26), "side": -1},
		"back": {"kind": "marker", "icon": Rect2(23.1, 18.3, 1.4, 2.2), "at": Vector2(23.1, 19.4), "side": -1},
		"start": {"kind": "marker", "icon": Rect2(39.5, 18.3, 1.4, 2.2), "at": Vector2(40.9, 19.4), "side": 1},
		"rt": {"kind": "above", "icon": Rect2(44.55, 7.1, 4.4, 4.4), "at": Vector2(48.95, 9.3), "side": 1},
		"rb": {"kind": "above", "icon": Rect2(44.15, 11.9, 5.2, 3.8), "at": Vector2(49.35, 13.8), "side": 1},
		"face_n": {"kind": "hole", "icon": Rect2(45.18, 22.17, 2.6, 2.6), "at": Vector2(48, 23.5), "side": 1},
		"face_e": {"kind": "hole", "icon": Rect2(48.18, 25.18, 2.6, 2.6), "at": Vector2(51, 26.5), "side": 1},
		"face_w": {"kind": "hole", "icon": Rect2(42.19, 25.17, 2.6, 2.6), "at": Vector2(43.5, 25), "side": 1, "via": [Vector2(44.1, 20.8)]},
		"face_s": {"kind": "hole", "icon": Rect2(45.18, 28.17, 2.6, 2.6), "at": Vector2(48, 29.5), "side": 1},
		"rs": {"kind": "hole", "icon": Rect2(37.27, 29.26, 5.5, 5.5), "at": Vector2(42.6, 33.5), "side": 1},
	},
	"ps5": {
		"lt": {"kind": "above", "icon": Rect2(15.3, 7.17, 4.4, 4.4), "at": Vector2(15.3, 9.37), "side": -1},
		"lb": {"kind": "above", "icon": Rect2(14.9, 11.97, 5.2, 3.8), "at": Vector2(14.9, 13.87), "side": -1},
		"ls": {"kind": "hole", "icon": Rect2(22.27, 29.26, 5.5, 5.5), "at": Vector2(22, 32), "side": -1},
		"dpad": {"kind": "hole", "icon": Rect2(13.2, 21.2, 9.6, 9.6), "at": Vector2(13, 26), "side": -1},
		"back": {"kind": "marker", "icon": Rect2(21.9, 17.9, 1.4, 2.2), "at": Vector2(21.9, 19), "side": -1},
		"start": {"kind": "marker", "icon": Rect2(40.7, 17.9, 1.4, 2.2), "at": Vector2(42.1, 19), "side": 1},
		"rt": {"kind": "above", "icon": Rect2(44.3, 7.17, 4.4, 4.4), "at": Vector2(48.7, 9.37), "side": 1},
		"rb": {"kind": "above", "icon": Rect2(43.9, 11.97, 5.2, 3.8), "at": Vector2(49.1, 13.87), "side": 1},
		"face_n": {"kind": "hole", "icon": Rect2(45.18, 22.17, 2.6, 2.6), "at": Vector2(48, 23.5), "side": 1},
		"face_e": {"kind": "hole", "icon": Rect2(48.18, 25.18, 2.6, 2.6), "at": Vector2(51, 26.5), "side": 1},
		"face_w": {"kind": "hole", "icon": Rect2(42.19, 25.17, 2.6, 2.6), "at": Vector2(43.5, 25), "side": 1, "via": [Vector2(44.1, 20.8)]},
		"face_s": {"kind": "hole", "icon": Rect2(45.18, 28.17, 2.6, 2.6), "at": Vector2(48, 29.5), "side": 1},
		"rs": {"kind": "hole", "icon": Rect2(36.27, 29.26, 5.5, 5.5), "at": Vector2(41.6, 33.5), "side": 1},
	},
	"switch": {
		"lt": {"kind": "above", "icon": Rect2(16.8, 6.09, 4.4, 4.4), "at": Vector2(16.8, 8.29), "side": -1},
		"lb": {"kind": "above", "icon": Rect2(16.4, 10.89, 5.2, 3.8), "at": Vector2(16.4, 12.79), "side": -1},
		"ls": {"kind": "hole", "icon": Rect2(16.24, 21.23, 5.5, 5.5), "at": Vector2(16, 24), "side": -1},
		"dpad": {"kind": "hole", "icon": Rect2(22.25, 29.25, 5.5, 5.5), "at": Vector2(22, 32), "side": -1},
		"back": {"kind": "marker", "icon": Rect2(26, 17.6, 2, 2), "at": Vector2(26, 18.6), "side": -1},
		"start": {"kind": "marker", "icon": Rect2(36, 17.6, 2, 2), "at": Vector2(38, 18.6), "side": 1},
		"rt": {"kind": "above", "icon": Rect2(42.8, 6.1, 4.4, 4.4), "at": Vector2(47.2, 8.3), "side": 1},
		"rb": {"kind": "above", "icon": Rect2(42.4, 10.9, 5.2, 3.8), "at": Vector2(47.6, 12.8), "side": 1},
		"face_n": {"kind": "hole", "icon": Rect2(43.2, 20.19, 3.6, 3.6), "at": Vector2(47, 22), "side": 1},
		"face_e": {"kind": "hole", "icon": Rect2(47.2, 23.19, 3.6, 3.6), "at": Vector2(51, 25), "side": 1},
		"face_w": {"kind": "hole", "icon": Rect2(39.2, 23.19, 3.6, 3.6), "at": Vector2(41, 27), "side": 1, "via": [Vector2(41.6, 31.4)]},
		"face_s": {"kind": "hole", "icon": Rect2(43.2, 26.19, 3.6, 3.6), "at": Vector2(47, 28), "side": 1},
		"rs": {"kind": "hole", "icon": Rect2(35.24, 29.23, 5.5, 5.5), "at": Vector2(40.6, 33.5), "side": 1},
	},
	"steamdeck": {
		"lt": {"kind": "above", "icon": Rect2(11.8, 11.1, 4.4, 4.4), "at": Vector2(11.8, 13.3), "side": -1},
		"lb": {"kind": "above", "icon": Rect2(11.4, 15.9, 5.2, 3.8), "at": Vector2(11.4, 17.8), "side": -1},
		"ls": {"kind": "hole", "icon": Rect2(11.4, 31.1, 5.2, 5.2), "at": Vector2(11, 33.7), "side": -1},
		"dpad": {"kind": "hole", "icon": Rect2(11.25, 23.25, 5.5, 5.5), "at": Vector2(11, 26), "side": -1},
		"back": {"kind": "marker", "icon": Rect2(17, 20.95, 1.8, 1.1), "at": Vector2(17, 21.5), "side": -1, "via": [Vector2(8.6, 21.5)]},
		"start": {"kind": "marker", "icon": Rect2(45.2, 20.95, 1.8, 1.1), "at": Vector2(47, 21.5), "side": 1, "via": [Vector2(55.4, 21.5)]},
		"rt": {"kind": "above", "icon": Rect2(47.8, 11.1, 4.4, 4.4), "at": Vector2(52.2, 13.3), "side": 1},
		"rb": {"kind": "above", "icon": Rect2(47.4, 15.9, 5.2, 3.8), "at": Vector2(52.6, 17.8), "side": 1},
		"face_n": {"kind": "hole", "icon": Rect2(49.08, 23.09, 1.8, 1.8), "at": Vector2(51, 24), "side": 1},
		"face_e": {"kind": "hole", "icon": Rect2(51.08, 25.09, 1.8, 1.8), "at": Vector2(53, 26), "side": 1},
		"face_w": {"kind": "hole", "icon": Rect2(47.09, 25.08, 1.8, 1.8), "at": Vector2(48, 27), "side": 1, "via": [Vector2(48.4, 29.85), Vector2(54, 29.85)]},
		"face_s": {"kind": "hole", "icon": Rect2(49.08, 27.09, 1.8, 1.8), "at": Vector2(51, 28), "side": 1},
		"rs": {"kind": "hole", "icon": Rect2(47.4, 31.1, 5.2, 5.2), "at": Vector2(53, 33.7), "side": 1},
	},
	"generic": {
		"lt": {"kind": "above", "icon": Rect2(15.8, 5.14, 4.4, 4.4), "at": Vector2(15.8, 7.34), "side": -1},
		"lb": {"kind": "above", "icon": Rect2(15.4, 9.94, 5.2, 3.8), "at": Vector2(15.4, 11.84), "side": -1},
		"ls": {"kind": "marker", "icon": Rect2(24.5, 33.2, 4, 4), "at": Vector2(24.5, 35.2), "side": -1},
		"dpad": {"kind": "hole", "icon": Rect2(16.3, 21.3, 11.4, 11.4), "at": Vector2(16, 27), "side": -1},
		"back": {"kind": "marker", "icon": Rect2(28.9, 21.4, 2.2, 1.2), "at": Vector2(30, 21.4), "side": -1, "via": [Vector2(29.4, 17.8)]},
		"start": {"kind": "marker", "icon": Rect2(32.9, 21.4, 2.2, 1.2), "at": Vector2(34, 21.4), "side": 1, "via": [Vector2(34.6, 17.8)]},
		"rt": {"kind": "above", "icon": Rect2(43.8, 5.14, 4.4, 4.4), "at": Vector2(48.2, 7.34), "side": 1},
		"rb": {"kind": "above", "icon": Rect2(43.4, 9.94, 5.2, 3.8), "at": Vector2(48.6, 11.84), "side": 1},
		"face_n": {"kind": "hole", "icon": Rect2(40.19, 21.19, 3.6, 3.6), "at": Vector2(44, 23), "side": 1},
		"face_e": {"kind": "hole", "icon": Rect2(44.19, 25.19, 3.6, 3.6), "at": Vector2(48, 27), "side": 1},
		"face_w": {"kind": "hole", "icon": Rect2(36.19, 25.19, 3.6, 3.6), "at": Vector2(38, 25), "side": 1, "via": [Vector2(39, 19.6)]},
		"face_s": {"kind": "hole", "icon": Rect2(40.19, 29.19, 3.6, 3.6), "at": Vector2(44, 31), "side": 1},
		"rs": {"kind": "marker", "icon": Rect2(35.5, 33.2, 4, 4), "at": Vector2(39.5, 35.2), "side": 1},
	},
}
## The control each pad spec shows on ("" = not on the picture: listed under it).
const CONTROL_OF := {"b0": "face_s", "b1": "face_e", "b2": "face_w", "b3": "face_n", "b4": "back", "b6": "start",
	"b7": "ls", "b8": "rs", "b9": "lb", "b10": "rb", "b11": "dpad", "b12": "dpad", "b13": "dpad", "b14": "dpad",
	"a0-": "ls", "a0+": "ls", "a1-": "ls", "a1+": "ls", "a2-": "rs", "a2+": "rs", "a3-": "rs", "a3+": "rs", "a4+": "lt",
	"a5+": "rt"}
## The spec whose icon stands for a control on the picture (InputPrompts.icon_name in the picture's style).
const REP_SPEC := {"face_s": "b0", "face_e": "b1", "face_w": "b2", "face_n": "b3", "back": "b4", "start": "b6",
	"ls": "b7", "rs": "b8", "lb": "b9", "rb": "b10", "dpad": "b11", "lt": "a4+", "rt": "a5+"}
## Picture-only icons: sticks and D-pads seen from above, plain discs on a generic pad.
const HOLE_ICONS := {
	"xbox": {"ls": "xbox_stick_top_l", "rs": "xbox_stick_top_r", "dpad": "xbox_dpad_round"},
	"xbox360": {"ls": "xbox_stick_top_l", "rs": "xbox_stick_top_r", "dpad": "xbox_dpad_round"},
	"ps3": {"ls": "playstation_stick_top_l", "rs": "playstation_stick_top_r", "dpad": "playstation_dpad"},
	"ps4": {"ls": "playstation_stick_top_l", "rs": "playstation_stick_top_r", "dpad": "playstation_dpad"},
	"ps5": {"ls": "playstation_stick_top_l", "rs": "playstation_stick_top_r", "dpad": "playstation_dpad"},
	"switch": {"ls": "switch_stick_top_l", "rs": "switch_stick_top_r", "dpad": "xbox_dpad"},
	"steamdeck": {"ls": "steamdeck_stick_top_l", "rs": "steamdeck_stick_top_r", "dpad": "steamdeck_dpad"},
	"generic": {"ls": "generic_button_circle_fill", "rs": "generic_button_circle_fill", "dpad": "xbox_dpad",
		"face_s": "generic_button_circle", "face_e": "generic_button_circle", "face_w": "generic_button_circle",
		"face_n": "generic_button_circle"},
}
const PICTURE_TITLES := {"xbox": "XBOX SERIES", "xbox360": "XBOX 360", "ps3": "PLAYSTATION 3", "ps4": "PLAYSTATION 4",
	"ps5": "PLAYSTATION 5", "switch": "SWITCH PRO", "steamdeck": "STEAM DECK", "generic": "GENERIC"}

const FULL := {"col_w": 230.0, "gutter": 36.0, "pic_w": 480.0, "row_h": 30.0, "row_gap": 2.0, "block_gap": 8.0,
	"min_h": 440.0, "icon": 26.0, "font": 15, "line": 0.35}
# (COMPACT: the pause panel's, 572 px wide. col_w 152 is "CALL HELP" at 14 px beside PlayStation's CREATE
# keycap at 22 px, the widest label. Rows as high as their icons, a 26 px gutter and a 216 px picture: no
# placed leader crosses another for any family, preset or gamepad_test's stress sets, whatever the block
# gap; taller rows fan the Steam Deck's face buttons out until face_w's leader crosses face_s's)
const COMPACT := {"col_w": 152.0, "gutter": 26.0, "pic_w": 216.0, "row_h": 22.0, "row_gap": 1.0, "block_gap": 2.0,
	"min_h": 220.0, "icon": 22.0, "font": 14, "line": 0.5}

const BODY := Color8(31, 31, 31)  # UiKit.TRACK
const LINE := Color8(108, 108, 108)  # UiKit.NOB
const BOUND := Color.WHITE
const FREE := Color(1, 1, 1, 0.28)
const LEADER := Color(1, 1, 1, 0.38)
const MARKER_FILL := Color(1, 1, 1, 0.16)
const PLATE := Color(1, 1, 1, 0.035)  # behind each label block (FULL)
const PLATE_EDGE := Color(1, 1, 1, 0.09)
const PULSE_RATE := 5.0  # as OPTIONS' slots pulse while they listen
const FLASH_SECONDS := 0.8
const HOVER_GROW := 4.0  # px round a control's box that still counts as on it
## Names for the controls whose binding text names a direction or a press.
const CONTROL_NAMES := {"ls": "LEFT STICK", "rs": "RIGHT STICK", "dpad": "D-PAD"}
const SVG_FILL := 'stroke="none" fill="#FFFFFF"'
const SVG_FILL_GENERIC := 'stroke="none" fill="#FCFCFC"'

static var _textures := {}  # "style@scale@line" -> DPITexture (device_texture)
static var _stems := {}  # style -> {control: the icon drawn on it} (picture_stem)

## A pad style (InputPrompts.PAD_STYLES); "" follows InputPrompts.pad_style().
var style := "":
	set(v):
		style = v
		refresh()
## COMPACT sizes and SHORT_TITLES; false: FULL.
var compact := false:
	set(v):
		compact = v
		refresh()
## false: the picture alone (bound controls lit), no rows or leaders; the size is the picture's.
var callouts := true:
	set(v):
		callouts = v
		refresh()
## Rows focusable and pressable, hover and click on the picture (FULL only: compact rows never are).
var interactive := false:
	set(v):
		interactive = v
		refresh()
## {} = the player's pad slots (InputBindings.slots(action, PAD)); previews and tests may pass
## {action: [specs]}.
var binds := {}:
	set(v):
		binds = v
		refresh()
## While hidden, only note that the prompts changed and catch up when shown (the pause panel's
## picture: hidden the whole race, while the player may switch device many times).
var lazy := false

var _shown := ""  # the style drawn now
var _look := ""  # what the rows were styled for (style, mode, interactive, callouts)
var _plan := {}
var _laid := []  # the plan's blocks, placed: {control, side, rows, rect, leader, tick} in this control's pixels
var _off := Vector2.ZERO  # where the plan's (0, 0) is (the plan is centred in the control)
var _bound := {}  # control -> true: something is bound to it
var _rows := {}  # "action|slot" -> Row
var _order: Array[Button] = []  # focus order: left column top to bottom, then right
var _listen_key := ""  # the row listening for its new button
var _flash := {}  # "action|slot" -> seconds left
var _hover_ctl := ""  # the control under the mouse on the picture
var _hover_row: Row = null
var _cap := StyleBoxFlat.new()  # a marker capsule (redrawn per marker)
var _plate := StyleBoxFlat.new()
var _t := 0.0
var _place_queued := false
var _stale := false  # lazy: the prompts changed while it was hidden


## One label beside the picture: a binding's icon and its action. A Button, so the pad and the
## mouse can press it; action / slot / spec / control are also set as meta (for Button-typed code).
class Row extends Button:
	var action := ""
	var slot := -1
	var spec := ""
	var control := ""
	var side := 1  # -1: the left column, 1: the right one

	func key() -> String:
		return "%s|%d" % [action, slot]


func _init() -> void:
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cap.anti_aliasing = true
	_cap.set_border_width_all(1)
	_plate.anti_aliasing = true
	_plate.set_border_width_all(1)
	_plate.set_corner_radius_all(3)
	set_process(false)
	resized.connect(_on_resized)


func _enter_tree() -> void:
	if not InputPrompts.prompts_changed.is_connected(_on_prompts):
		InputPrompts.prompts_changed.connect(_on_prompts)
	if not InputPrompts.rebind_captured.is_connected(_on_listen_end):
		InputPrompts.rebind_captured.connect(_on_listen_end)
	if not InputPrompts.rebind_cancelled.is_connected(_on_listen_end):
		InputPrompts.rebind_cancelled.connect(_on_listen_end)
	refresh()


func _ready() -> void:
	# rows made before this entered the tree were sized with the default theme (taller): size them again
	_place()


func _exit_tree() -> void:
	if InputPrompts.prompts_changed.is_connected(_on_prompts):
		InputPrompts.prompts_changed.disconnect(_on_prompts)
	if InputPrompts.rebind_captured.is_connected(_on_listen_end):
		InputPrompts.rebind_captured.disconnect(_on_listen_end)
	if InputPrompts.rebind_cancelled.is_connected(_on_listen_end):
		InputPrompts.rebind_cancelled.disconnect(_on_listen_end)
	_listen_key = ""
	_flash.clear()
	set_process(false)


func _on_prompts() -> void:
	if lazy and is_inside_tree() and not is_visible_in_tree():
		_stale = true
		return
	refresh()


# ---------------------------------------------------------------- API
## The style drawn: `style`, or InputPrompts.pad_style() when it is "" (or not a pad style).
func shown_style() -> String:
	return style if DEVICE_SVG.has(style) else InputPrompts.pad_style()


## Reads the bindings again: rows made, moved or dropped (a row keeps its node, and so the focus,
## while its slot stays bound), the picture planned and placed again, the column's focus neighbours
## set, then laid_out.
func refresh() -> void:
	_stale = false
	_shown = shown_style()
	# the picture itself hears the mouse (hover, click, tooltip) only when it is live
	mouse_filter = Control.MOUSE_FILTER_STOP if _live() else Control.MOUSE_FILTER_IGNORE
	var m := _mode()
	var b := _binds()
	var look := "%s|%s|%s|%s" % [_shown, compact, interactive, callouts]
	if look != _look:
		var had := _focused_key()
		_clear_rows()
		_look = look
		_sync(b, m)
		if had != "" and _rows.has(had) and is_inside_tree():
			(_rows[had] as Row).grab_focus()
	else:
		_sync(b, m)
	_bound.clear()
	for act in b:
		for spec in b[act]:
			var c := control_of(str(spec))
			if c != "":
				_bound[c] = true
	custom_minimum_size = (_plan["size"] as Vector2).ceil()
	_place()
	_neighbours()
	queue_redraw()
	laid_out.emit()


## The rows in focus order: the left column top to bottom, then the right column.
func rows() -> Array[Button]:
	return _order.duplicate()


## The row of one pad slot; null when that slot is empty or its button is not on the picture.
func row_for(action: String, slot: int) -> Button:
	return _rows.get("%s|%d" % [action, slot])


func first_row() -> Button:
	return _order[0] if not _order.is_empty() else null


## Bound slots whose input has no place on the picture (paddles, the touchpad, Misc, an axis past
## the triggers): [[action, slot, spec]].
func unplaced() -> Array:
	var out := []
	var b := _binds()
	for act in InputBindings.ACTIONS:
		var slots: Array = b.get(act, [])
		for i in slots.size():
			var spec := str(slots[i])
			if spec != "" and control_of(spec) == "":
				out.append([act, i, spec])
	return out


## That slot's row reads PRESS... and pulses, and so do its button and leader; ("", -1) stops.
## (Also stops by itself when InputPrompts catches an input or gives up.)
func set_listening(action: String, slot: int) -> void:
	var old := _listen_key
	_listen_key = "" if action == "" else "%s|%d" % [action, slot]
	if old != "" and _rows.has(old):
		_dress(_rows[old])
	if _listen_key != "" and _rows.has(_listen_key):
		_dress(_rows[_listen_key])
	_t = 0.0
	_wake()
	queue_redraw()


## Rows flash orange, fading to their colour (a swap: both slots that changed). ["action|slot", ...]
func flash(keys: Array) -> void:
	for k in keys:
		if _rows.has(str(k)):
			_flash[str(k)] = FLASH_SECONDS
	_wake()


## The control on the picture that shows a pad spec ("" when it has no place on it).
static func control_of(spec: String) -> String:
	return CONTROL_OF.get(spec, "")


## A control's name for people in a style: "LEFT STICK", "D-PAD", "A", "CROSS", "LT", "VIEW".
static func control_name(ctl: String, style_id: String) -> String:
	if CONTROL_NAMES.has(ctl):
		return CONTROL_NAMES[ctl]
	return InputPrompts.spec_text(REP_SPEC.get(ctl, ""), style_id) if REP_SPEC.has(ctl) else ctl.to_upper()


## The silhouette of a style, `scale` px per SVG unit, outlined `line_w` SVG units wide: Kenney's
## white shape recoloured (dark body, grey outline round it and its holes), cached.
static func device_texture(style_id: String, scale: float, line_w: float) -> Texture2D:
	var key := "%s@%.3f@%.3f" % [style_id, scale, line_w]
	if _textures.has(key):
		return _textures[key]
	var tex: Texture2D = null
	var path := InputPrompts.icon_path(str(DEVICE_SVG.get(style_id, "")))
	if path != "" and FileAccess.file_exists(path):
		var src := FileAccess.get_file_as_string(path)
		var styled := 'stroke="#%s" stroke-width="%s" fill="#%s"' % [LINE.to_html(false), str(snappedf(line_w, 0.001)),
			BODY.to_html(false)]
		src = src.replace(SVG_FILL, styled).replace(SVG_FILL_GENERIC, styled)
		if src != "":
			tex = DPITexture.create_from_string(src, maxf(scale, 0.1))
	_textures[key] = tex
	return tex


## A callout row as the diagram makes them (the page's extra rows under the picture look the
## same): `side` -1 puts the icon on the right (next to a leader on the left), 1 on the left.
## Not connected to anything; `live` makes it focusable and pressable with hover styles.
static func make_row(action: String, slot: int, spec: String, style_id: String, compact_mode: bool, side: int,
		live: bool) -> Row:
	var r := Row.new()
	r.action = action
	r.slot = slot
	r.spec = spec
	r.control = control_of(spec)
	r.side = side
	_style_row(r, compact_mode, live)
	_dress_row(r, style_id, compact_mode, false)
	return r


# ---------------------------------------------------------------- planning (section 3.4 of the spec)
## The callout layout: the picture's scale and place, and each bound control's label block and leader.
## bind_map: {action: [pad specs]}. Returns {"size": Vector2, "scale": float, "origin": Vector2 (where SVG (0, 0)
## lands), "blocks": [{"control", "side", "rows": [[action, slot, spec]], "rect": Rect2, "leader":
## PackedVector2Array}]}; every coordinate in the diagram's own pixels.
static func plan(style_id: String, bind_map: Dictionary, mode: Dictionary) -> Dictionary:
	var b: Rect2 = DEVICE_BOUNDS[style_id]
	var s: float = mode["pic_w"] / b.size.x
	var pic_h := b.size.y * s
	var by_ctl := {}
	for act in InputBindings.ACTIONS:
		var slots: Array = bind_map.get(act, [])
		for i in slots.size():
			var ctl: String = CONTROL_OF.get(slots[i], "")
			if slots[i] != "" and ctl != "":
				if not by_ctl.has(ctl):
					by_ctl[ctl] = []
				by_ctl[ctl].append([act, i, slots[i]])
	var sides := {-1: [], 1: []}
	for ctl in by_ctl:
		var a: Dictionary = DEVICE_ANCHORS[style_id][ctl]
		var n: int = by_ctl[ctl].size()
		sides[int(a["side"])].append({"control": ctl, "side": int(a["side"]), "rows": by_ctl[ctl],
			"h": n * mode["row_h"] + (n - 1) * mode["row_gap"]})
	var need := pic_h
	for sd in sides:
		var t := 0.0
		for blk in sides[sd]:
			t += blk["h"]
		need = maxf(need, t + mode["block_gap"] * maxi(sides[sd].size() - 1, 0))
	var h := maxf(need, mode["min_h"])
	var w: float = 2.0 * (mode["col_w"] + mode["gutter"]) + mode["pic_w"]
	var origin := Vector2(mode["col_w"] + mode["gutter"], (h - pic_h) * 0.5) - b.position * s
	var out := []
	for sd in sides:
		var list: Array = sides[sd]
		for blk in list:
			var a: Dictionary = DEVICE_ANCHORS[style_id][blk["control"]]
			var pts := PackedVector2Array([origin + a["at"] * s])
			for v in a.get("via", []):
				pts.append(origin + v * s)
			blk["pts"] = pts
		# top to bottom by where each leader leaves the picture; a tie: the one nearer its column first
		list.sort_custom(func(p, q):
			var ep: Vector2 = p["pts"][-1]
			var eq: Vector2 = q["pts"][-1]
			return ep.y < eq.y or (ep.y == eq.y and ep.x * -sd > eq.x * -sd))
		# each block wants its centre level with its leader's exit; blocks that would overlap merge into a
		# cluster centred on the mean of what its blocks want (so a crowd fans out up and down), kept inside 0..h
		var clusters := []
		for blk in list:
			clusters.append({"blocks": [blk], "want": [blk["pts"][-1].y], "h": blk["h"]})
		var merged := true
		while merged:
			merged = false
			for c in clusters:
				var off := 0.0
				var sum := 0.0
				for k in c["blocks"].size():
					sum += c["want"][k] - (off + c["blocks"][k]["h"] * 0.5)
					off += c["blocks"][k]["h"] + mode["block_gap"]
				c["top"] = clampf(sum / c["blocks"].size(), 0.0, maxf(h - c["h"], 0.0))
			for k in range(clusters.size() - 1):
				var a: Dictionary = clusters[k]
				var z: Dictionary = clusters[k + 1]
				if a["top"] + a["h"] + mode["block_gap"] > z["top"]:
					a["blocks"].append_array(z["blocks"])
					a["want"].append_array(z["want"])
					a["h"] += mode["block_gap"] + z["h"]
					clusters.remove_at(k + 1)
					merged = true
					break
		for c in clusters:
			var y: float = c["top"]
			for blk in c["blocks"]:
				blk["top"] = y
				y += blk["h"] + mode["block_gap"]
		for blk in list:
			var x0: float = 0.0 if sd < 0 else w - mode["col_w"]
			var attach := Vector2(mode["col_w"] + 4.0 if sd < 0 else w - mode["col_w"] - 4.0, blk["top"] + blk["h"] * 0.5)
			var leader: PackedVector2Array = blk["pts"].duplicate()
			leader.append(attach)
			out.append({"control": blk["control"], "side": sd, "rows": blk["rows"],
				"rect": Rect2(x0, blk["top"], mode["col_w"], blk["h"]), "leader": leader})
	return {"size": Vector2(w, h), "scale": s, "origin": origin, "blocks": out}


## Leaders that cross each other, or pass through another control's icon box: ["lb x ls", "face_w through face_n"].
static func crossings(style_id: String, pl: Dictionary) -> Array:
	var bad := []
	var bl: Array = pl["blocks"]
	for i in bl.size():
		var p: PackedVector2Array = bl[i]["leader"]
		for j in range(i + 1, bl.size()):
			var q: PackedVector2Array = bl[j]["leader"]
			for a in p.size() - 1:
				for c in q.size() - 1:
					if Geometry2D.segment_intersects_segment(p[a], p[a + 1], q[c], q[c + 1]) != null:
						bad.append("%s x %s" % [bl[i]["control"], bl[j]["control"]])
		for ctl in DEVICE_ANCHORS[style_id]:
			if ctl == bl[i]["control"]:
				continue
			var r: Rect2 = DEVICE_ANCHORS[style_id][ctl]["icon"]
			var rp := Rect2(pl["origin"] + r.position * pl["scale"], r.size * pl["scale"])
			for a in p.size() - 1:
				for k in range(1, 40):
					if rp.has_point(p[a].lerp(p[a + 1], k / 40.0)):
						bad.append("%s through %s" % [bl[i]["control"], ctl])
						break
	return bad


# ---------------------------------------------------------------- rows
func _mode() -> Dictionary:
	return COMPACT if compact else FULL


## Rows take the focus and the mouse (OPTIONS): FULL and interactive.
func _live() -> bool:
	return interactive and not compact and callouts


func _binds() -> Dictionary:
	return binds if not binds.is_empty() else InputBindings.all_slots(InputBindings.PAD)


## The picture alone: its box at the mode's width.
static func _picture_plan(style_id: String, mode: Dictionary) -> Dictionary:
	var b: Rect2 = DEVICE_BOUNDS[style_id]
	var s: float = mode["pic_w"] / b.size.x
	return {"size": Vector2(mode["pic_w"], b.size.y * s), "scale": s, "origin": -b.position * s, "blocks": []}


func _focused_key() -> String:
	var f := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	return (f as Row).key() if f is Row and (f as Row).get_parent() == self else ""


func _clear_rows() -> void:
	for k in _rows:
		_drop(_rows[k])
	_rows.clear()
	_order.clear()
	_hover_row = null


## Takes a row out at once (it may be the one whose input is being handled: freed later).
func _drop(r: Row) -> void:
	if r.get_parent() == self:
		remove_child(r)
	r.queue_free()


## Plans the callouts and makes the rows match them: the same slot keeps its row.
func _sync(b: Dictionary, m: Dictionary) -> void:
	_plan = plan(_shown, b, m) if callouts else _picture_plan(_shown, m)
	var want := {}
	_order.clear()
	for blk in _plan["blocks"]:
		for r in blk["rows"]:
			var key := "%s|%d" % [r[0], r[1]]
			var row: Row = _rows.get(key)
			if row == null:
				row = _new_row(str(r[0]), int(r[1]))
				_rows[key] = row
			row.spec = str(r[2])
			row.control = str(blk["control"])
			row.side = int(blk["side"])
			_dress(row)
			want[key] = true
			_order.append(row)
	for key in _rows.keys():
		if not want.has(key):
			if _hover_row == _rows[key]:
				_hover_row = null
			_flash.erase(key)
			_drop(_rows[key])
			_rows.erase(key)
	if _listen_key != "" and not _rows.has(_listen_key):
		_listen_key = ""


func _new_row(action: String, slot: int) -> Row:
	var r := Row.new()
	r.action = action
	r.slot = slot
	r.name = "row_%s_%d" % [action, slot]
	_style_row(r, compact, _live())
	r.minimum_size_changed.connect(_queue_place)
	if _live():
		UiKit.hover_focus(r)
		r.pressed.connect(_on_row_pressed.bind(r))
		r.gui_input.connect(_on_row_input.bind(r))
		r.focus_entered.connect(func():
			Game.play_ui("res://assets/sound/ui/buttonrollover.wav", -10.0)
			queue_redraw())
		r.focus_exited.connect(queue_redraw)
		r.mouse_entered.connect(func():
			_hover_row = r
			queue_redraw())
		r.mouse_exited.connect(func():
			if _hover_row == r:
				_hover_row = null
			queue_redraw())
	add_child(r)
	return r


## A row's look for a mode: the font, the margins (so an icon row is exactly row_h high), and the
## hover / focus / pressed frames when it is live.
static func _style_row(r: Row, compact_mode: bool, live: bool) -> void:
	var m := COMPACT if compact_mode else FULL
	var font_px: int = m["font"]
	var pad_y := maxf((float(m["row_h"]) - float(m["icon"])) * 0.5, 0.0)
	var pad_x := 0.0 if compact_mode else 6.0
	r.add_theme_font_override("font", UiKit.font(true))
	r.add_theme_font_size_override("font_size", font_px)
	r.add_theme_constant_override("h_separation", 6 if compact_mode else 8)
	r.add_theme_color_override("font_color", UiKit.TEXT)
	for c in ["font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		r.add_theme_color_override(c, Color.WHITE)
	r.clip_text = true
	r.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	r.custom_minimum_size = Vector2.ZERO
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = pad_x
	empty.content_margin_right = pad_x
	empty.content_margin_top = pad_y
	empty.content_margin_bottom = pad_y
	for st in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		r.add_theme_stylebox_override(st, empty)
	if live:
		r.focus_mode = Control.FOCUS_ALL
		r.mouse_filter = Control.MOUSE_FILTER_STOP
		r.add_theme_stylebox_override("hover", _frame(Color(1, 1, 1, 0.08), 1, pad_x, pad_y))
		r.add_theme_stylebox_override("focus", _frame(Color(0, 0, 0, 0), 2, pad_x, pad_y))
		r.add_theme_stylebox_override("pressed", _frame(Color(UiKit.ORANGE, 0.35), 1, pad_x, pad_y))
		r.add_theme_stylebox_override("hover_pressed", _frame(Color(UiKit.ORANGE, 0.35), 1, pad_x, pad_y))
	else:
		r.focus_mode = Control.FOCUS_NONE
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE


static func _frame(bg: Color, bw: int, pad_x: float, pad_y: float) -> StyleBoxFlat:
	var sb := UiKit.box(bg, UiKit.ORANGE, bw, 3, 6)
	sb.content_margin_left = pad_x
	sb.content_margin_right = pad_x
	sb.content_margin_top = pad_y
	sb.content_margin_bottom = pad_y
	return sb


func _dress(r: Row) -> void:
	_dress_row(r, _shown, compact, r.key() == _listen_key)
	if _live():
		var st := _shown
		r.tooltip_text = ("%s always pauses" % InputPrompts.spec_text(r.spec, st)) if _locked(r) \
			else ("%s: press to change" % InputPrompts.spec_text(r.spec, st))
	else:
		r.tooltip_text = ""


## Text, icon, alignment and the locked look of a row.
static func _dress_row(r: Row, style_id: String, compact_mode: bool, listening: bool) -> void:
	var m := COMPACT if compact_mode else FULL
	r.set_meta("action", r.action)
	r.set_meta("slot", r.slot)
	r.set_meta("spec", r.spec)
	r.set_meta("control", r.control)
	var align := HORIZONTAL_ALIGNMENT_RIGHT if r.side < 0 else HORIZONTAL_ALIGNMENT_LEFT
	r.alignment = align
	r.icon_alignment = align
	var locked := InputBindings.is_locked(r.action, InputBindings.PAD, r.slot)
	r.modulate = Color(1, 1, 1, 0.6 if locked else 1.0)
	if listening:
		r.icon = null
		r.text = "PRESS..."
		return
	var title := str(InputBindings.SHORT_TITLES.get(r.action, r.action.to_upper())) if compact_mode \
		else str(InputBindings.TITLES.get(r.action, r.action)).to_upper()
	r.text = title
	r.icon = row_icon(r.spec, style_id, float(m["icon"]))


## A binding's icon for a row: Kenney's, else its name on a keycap.
static func row_icon(spec: String, style_id: String, px: float) -> Texture2D:
	if spec == "":
		return null
	var tex := InputPrompts.spec_icon(spec, px, style_id)
	if tex == null:
		var t := InputPrompts.spec_text(spec, style_id)
		if t != "":
			tex = KeycapTexture.of(t, px)
	return tex


static func _locked(r: Row) -> bool:
	return InputBindings.is_locked(r.action, InputBindings.PAD, r.slot)


func _on_row_pressed(r: Row) -> void:
	slot_pressed.emit(r.action, r.slot)


func _on_row_input(event: InputEvent, r: Row) -> void:
	if InputPrompts.is_listening() or not event.is_action_pressed("ui_clear"):
		return
	accept_event()
	clear_requested.emit(r.action, r.slot)


func _on_listen_end(action: String, cls: String, slot: int, _a = null, _b = null) -> void:
	if cls == InputBindings.PAD and _listen_key == "%s|%d" % [action, slot]:
		set_listening("", -1)


# ---------------------------------------------------------------- placing and focus
## A row's minimum size changed (it entered the tree, or the theme changed): place the rows again
## once, so none keeps a size its old minimum forced on it.
func _queue_place() -> void:
	if not _place_queued:
		_place_queued = true
		_place.call_deferred()


func _on_resized() -> void:
	if not _plan.is_empty():
		_place()
		queue_redraw()


## Centres the plan in the control and puts every row on its block (whole pixels, so text is sharp).
func _place() -> void:
	_place_queued = false
	if _plan.is_empty():
		return
	var m := _mode()
	var psize: Vector2 = _plan["size"]
	_off = ((size - psize) * 0.5).floor().max(Vector2.ZERO)
	_laid.clear()
	var step: float = m["row_h"] + m["row_gap"]
	for blk in _plan["blocks"]:
		var r: Rect2 = blk["rect"]
		var rr := Rect2((r.position + _off).round(), r.size)
		var lead: PackedVector2Array = (blk["leader"] as PackedVector2Array).duplicate()
		for i in lead.size():
			lead[i] += _off
		lead[lead.size() - 1].y = rr.get_center().y
		# FULL labels sit on a plate: a short level tick takes the leader the last 4 px to its edge
		var tick := PackedVector2Array()
		if not compact:
			tick = PackedVector2Array([lead[lead.size() - 1], Vector2(rr.end.x if int(blk["side"]) < 0 else rr.position.x,
				rr.get_center().y)])
		_laid.append({"control": blk["control"], "side": blk["side"], "rows": blk["rows"], "rect": rr, "leader": lead,
			"tick": tick})
		for i in (blk["rows"] as Array).size():
			var key := "%s|%d" % [blk["rows"][i][0], blk["rows"][i][1]]
			var row: Row = _rows.get(key)
			if row:
				row.position = rr.position + Vector2(0, roundf(i * step))
				row.size = Vector2(m["col_w"], m["row_h"])


## Up / down within a column, across to the nearest row of the other column; the left column's
## left goes nowhere. The edges that lead out of the picture (the top row's up, the bottom row's
## down, the right column's right) are left empty for the page (laid_out).
func _neighbours() -> void:
	var cols := {-1: [], 1: []}
	for r in _order:
		cols[(r as Row).side].append(r)
	for sd in cols:
		var col: Array = cols[sd]
		var other: Array = cols[-sd]
		for i in col.size():
			var r: Row = col[i]
			r.focus_neighbor_top = r.get_path_to(col[i - 1]) if i > 0 else NodePath()
			r.focus_neighbor_bottom = r.get_path_to(col[i + 1]) if i < col.size() - 1 else NodePath()
			var near := _nearest(r, other)
			if sd < 0:
				r.focus_neighbor_left = r.get_path_to(r)
				r.focus_neighbor_right = r.get_path_to(near) if near else NodePath()
			else:
				r.focus_neighbor_left = r.get_path_to(near) if near else r.get_path_to(r)
				r.focus_neighbor_right = NodePath()


## The row of `list` nearest in height to `r` (the upper one on a tie).
static func _nearest(r: Control, list: Array) -> Control:
	var best: Control = null
	var bd := INF
	var y := r.position.y + r.size.y * 0.5
	for o in list:
		var d := absf((o as Control).position.y + (o as Control).size.y * 0.5 - y)
		if d < bd - 0.01:
			bd = d
			best = o
	return best


# ---------------------------------------------------------------- pulsing
func _wake() -> void:
	set_process(_listen_key != "" or not _flash.is_empty())


func _process(delta: float) -> void:
	_t += delta
	if _listen_key != "" and _rows.has(_listen_key):
		var r: Row = _rows[_listen_key]
		r.modulate.a = _pulse()
		queue_redraw()
	for k in _flash.keys():
		var left: float = _flash[k] - delta
		var r: Row = _rows.get(k)
		if r == null or left <= 0.0:
			_flash.erase(k)
			if r:
				r.modulate = Color(1, 1, 1, 0.6 if _locked(r) else 1.0)
			continue
		_flash[k] = left
		var base := Color(1, 1, 1, 0.6 if _locked(r) else 1.0)
		r.modulate = base.lerp(UiKit.ORANGE, left / FLASH_SECONDS)
	_wake()


func _pulse() -> float:
	return 0.55 + 0.45 * absf(sin(_t * PULSE_RATE))


# ---------------------------------------------------------------- drawing
## The controls drawn orange: the one under the mouse, the focused or hovered row's, the listening one.
func _hot() -> Dictionary:
	var out := {}
	if _hover_ctl != "":
		out[_hover_ctl] = true
	if _hover_row and is_instance_valid(_hover_row):
		out[_hover_row.control] = true
	var f := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if f is Row and (f as Row).get_parent() == self:
		out[(f as Row).control] = true
	if _listen_key != "" and _rows.has(_listen_key):
		out[(_rows[_listen_key] as Row).control] = true
	return out


func _draw() -> void:
	if _plan.is_empty() or not DEVICE_ANCHORS.has(_shown):
		return
	var m := _mode()
	var s: float = _plan["scale"]
	var o: Vector2 = _off + _plan["origin"]
	var tex := device_texture(_shown, s, m["line"])
	if tex:
		draw_texture(tex, o.round())  # (at its own size, on whole pixels: drawn sharp)
	var hot := _hot()
	var listen_ctl := ""
	if _listen_key != "" and _rows.has(_listen_key):
		listen_ctl = (_rows[_listen_key] as Row).control
	var orange_now := Color(UiKit.ORANGE, _pulse())
	var lw := 1.5 if not compact else 1.0
	var dot := 3.0 if not compact else 2.0
	for blk in _laid:
		var ctl: String = blk["control"]
		var is_hot := hot.has(ctl)
		var col := (orange_now if ctl == listen_ctl else UiKit.ORANGE) if is_hot else LEADER
		if not compact:
			_plate.bg_color = PLATE
			_plate.border_color = Color(UiKit.ORANGE, 0.7) if ctl == _hover_ctl else PLATE_EDGE
			draw_style_box(_plate, blk["rect"])
		draw_polyline(blk["leader"], col, 2.0 if is_hot else lw, true)
		if (blk["tick"] as PackedVector2Array).size() == 2:
			draw_polyline(blk["tick"], col, 2.0 if is_hot else lw, true)
		draw_circle(blk["leader"][0], dot, col, true, -1.0, true)
	for ctl in DEVICE_ANCHORS[_shown]:
		var col := FREE
		if hot.has(ctl):
			col = orange_now if ctl == listen_ctl else UiKit.ORANGE
		elif _bound.has(ctl):
			col = BOUND
		_draw_control(ctl, o, s, col)


## One control in its box: Kenney's icon (its glyph filling the box), a keycap with its name (a
## generic pad's shoulders), or a capsule (a Back / Start the family draws too small to read).
func _draw_control(ctl: String, o: Vector2, s: float, col: Color) -> void:
	var a: Dictionary = DEVICE_ANCHORS[_shown][ctl]
	var r: Rect2 = a["icon"]
	var box := Rect2(o + r.position * s, r.size * s)
	var stem := picture_stem(_shown, ctl)
	if stem != "":
		var gb := InputPrompts.glyph_box(stem)
		var k := minf(box.size.x / gb.size.x, box.size.y / gb.size.y)
		var tex := InputPrompts.icon(stem, k)
		if tex:
			draw_texture_rect(tex, Rect2((box.get_center() - gb.get_center() * k).round(), Vector2(k, k)), false, col)
			return
	if a["kind"] == "above":
		var cap := KeycapTexture.of(InputPrompts.spec_text(REP_SPEC[ctl], _shown), box.size.y)
		var w := float(cap.get_width())
		draw_texture_rect(cap, Rect2(Vector2(box.get_center().x - w * 0.5, box.position.y), Vector2(w, box.size.y)), false,
			col)
		return
	_cap.bg_color = MARKER_FILL
	_cap.border_color = col
	_cap.set_corner_radius_all(int(minf(box.size.x, box.size.y) * 0.5))
	draw_style_box(_cap, box)


## The icon drawn on a control in a style ("" = none: a capsule or a keycap); cached (it is asked
## for every control on every redraw, and a listening label redraws every frame).
static func picture_stem(style_id: String, ctl: String) -> String:
	if not _stems.has(style_id):
		_stems[style_id] = {}
	var known: Dictionary = _stems[style_id]
	if known.has(ctl):
		return known[ctl]
	var own: Dictionary = HOLE_ICONS.get(style_id, {})
	var stem := ""
	if own.has(ctl):
		stem = own[ctl]
	elif REP_SPEC.has(ctl):
		stem = InputPrompts.icon_name(InputBindings.event_of(REP_SPEC[ctl]), style_id)
	known[ctl] = stem
	return stem


# ---------------------------------------------------------------- the mouse on the picture
## The control whose box (grown HOVER_GROW px) is under `p` ("" = none); the nearest centre wins.
func control_at(p: Vector2) -> String:
	if _plan.is_empty() or not DEVICE_ANCHORS.has(_shown):
		return ""
	var s: float = _plan["scale"]
	var o: Vector2 = _off + _plan["origin"]
	var best := ""
	var bd := INF
	for ctl in DEVICE_ANCHORS[_shown]:
		var r: Rect2 = DEVICE_ANCHORS[_shown][ctl]["icon"]
		var box := Rect2(o + r.position * s, r.size * s).grow(HOVER_GROW)
		if box.has_point(p):
			var d := box.get_center().distance_squared_to(p)
			if d < bd:
				bd = d
				best = ctl
	return best


func _gui_input(event: InputEvent) -> void:
	if not _live():
		return
	if event is InputEventMouseMotion:
		var c := control_at((event as InputEventMouseMotion).position)
		if c != _hover_ctl:
			_hover_ctl = c
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if _bound.has(c) else Control.CURSOR_ARROW
			queue_redraw()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and not InputPrompts.is_listening():
			var c := control_at(mb.position)
			for r in _order:
				if (r as Row).control == c:
					accept_event()
					r.grab_focus()
					slot_pressed.emit((r as Row).action, (r as Row).slot)
					return


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hover_ctl != "":
		_hover_ctl = ""
		mouse_default_cursor_shape = Control.CURSOR_ARROW
		queue_redraw()
	elif what == NOTIFICATION_VISIBILITY_CHANGED and _stale and is_visible_in_tree():
		refresh()


func _get_tooltip(at_position: Vector2) -> String:
	if not _live():
		return ""
	var c := control_at(at_position)
	if c == "":
		return ""
	var acts := PackedStringArray()
	for r in _order:
		if (r as Row).control == c:
			acts.append(str(InputBindings.TITLES[(r as Row).action]).to_upper())
	return "%s: %s" % [control_name(c, _shown), ", ".join(acts) if not acts.is_empty() else "free"]


## The placed callouts, in this control's pixels (for tests): [{control, side, rows, rect, leader}].
func callout_blocks() -> Array:
	return _laid.duplicate(true)
