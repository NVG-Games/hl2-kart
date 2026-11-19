class_name TrackBrowser
extends Dialog
## NEW RACE's custom track picker (5.3): a 1200 x 760 Dialog with the tabs MY TRACKS / DOWNLOADED
## (LB / RB), a TrackList of cards, the selected card's details on the right, A picks (RACE THIS
## TRACK), B goes back. A track that cannot be raced here (errors, not checked yet, cannot be
## built) is dimmed with the reason and cannot be picked.

signal picked(id: String)

const TABS := ["mine", "downloaded"]
const TAB_TITLES := ["MY TRACKS", "DOWNLOADED"]
const COLUMNS := 3

var list: TrackList
var details: TrackList.Details
var why: Label
var pick_button: Button
var tab := ""
## The track to show selected on opening (NEW RACE's pick).
var start_id := ""


func _init() -> void:
	super("MY TRACKS", Vector2(1200, 760))


func _ready() -> void:
	tabs = TabBar.new()
	for t in TAB_TITLES:
		tabs.add_tab(t)
	tabs.focus_mode = Control.FOCUS_ALL
	tabs.tab_changed.connect(func(i: int): show_tab(TABS[clampi(i, 0, TABS.size() - 1)]))
	body.add_child(tabs)
	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 26)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(main)
	list = TrackList.new(COLUMNS)
	list.custom_minimum_size.x = TrackList.width_for(COLUMNS)
	list.selected.connect(_on_selected)
	list.activated.connect(func(e: Dictionary): pick(e))
	main.add_child(list)
	details = TrackList.Details.new(Vector2(330, 220))
	details.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	main.add_child(details)
	why = UiKit.label("", 16, TrackList.ERROR_RED)
	body.add_child(why)
	set_prompts([["{ui_accept} PICK"], ["{ui_cancel} BACK"]])
	add_button("BACK", close)
	pick_button = add_button("RACE THIS TRACK", func(): pick(list.current))
	pick_button.custom_minimum_size.x = 240
	list.up_target = tabs
	list.down_target = pick_button
	Game.track_thumb_ready.connect(_on_thumb)
	Game.custom_tracks_changed.connect(_on_customs_changed)
	CustomTracks.refresh()
	if start_id == "":
		start_id = str(Game.settings.get("track", ""))
	var first := "mine"
	var m := CustomTracks.meta(start_id)
	if str(m.get("kind", "")) in ["kept", "cache"]:
		first = "downloaded"
	elif CustomTracks.list("mine").is_empty() and not CustomTracks.list("downloaded").is_empty():
		first = "downloaded"
	show_tab(first, start_id)
	var c := list.current_card()
	default_focus = c if c != null else tabs
	default_focus.grab_focus.call_deferred()


## The cards of MY TRACKS (own tracks) or DOWNLOADED (kept and cached).
func show_tab(name_: String, keep_id := "") -> void:
	if not name_ in TABS:
		return
	tab = name_
	tabs.set_block_signals(true)
	tabs.current_tab = TABS.find(tab)
	tabs.set_block_signals(false)
	list.empty_label.text = "No tracks of your own yet: make one in TRACK EDITOR (the main menu)." if tab == "mine" \
		else "No downloads yet: tracks you race on a friend's server land here."
	list.set_entries(CustomTracks.list("mine" if tab == "mine" else "downloaded"), keep_id)
	var c := list.current_card()
	default_focus = c if c != null else tabs
	why.text = ""
	_on_selected(list.current)


func _on_selected(e: Dictionary) -> void:
	details.show_entry(e)
	pick_button.disabled = e.is_empty() or not TrackList.pickable(e)


## A picks: the track goes to NEW RACE (refused with the reason when it cannot be raced).
## "" or the reason.
func pick(e: Dictionary) -> String:
	if e.is_empty() or not CustomTracks.is_custom(str(e.get("id", ""))):
		why.text = "Pick a track."
		return why.text
	var reason := TrackList.why_not(e)
	if reason != "":
		why.text = "%s cannot be raced. %s" % [e.get("name", "The track"), reason]
		Game.play_ui("res://assets/sound/buttons/button9.wav", -6.0)
		return why.text
	picked.emit(str(e.id))
	close()
	return ""


func _on_thumb(id: String) -> void:
	var tex := Game.track_thumb(id)
	list.set_thumb(id, tex)
	details.set_thumb(id, tex)


func _on_customs_changed() -> void:
	show_tab(tab)
