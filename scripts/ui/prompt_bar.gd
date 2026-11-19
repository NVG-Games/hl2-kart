class_name PromptBar
extends HBoxContainer
## A row of button hints for the foot of a screen, drawn for the device the player is using:
## "[A] SELECT   [B] BACK   [LB][RB] TABS" (PromptLabel tokens). An entry can show only while a
## pad is in use ("pad": Start on NEW RACE, Y in the lists) or only on the keyboard and mouse
## ("key"). It redraws itself when the device, the pad's family or a binding changes.

const FONT_SIZE := 15

var font_size := FONT_SIZE
var color := UiKit.TEXT_DIM
var _entries: Array = []  # [PromptLabel, when: "" / "pad" / "key"]


## entries: [[prompt], [prompt, "pad"], ...]
func _init(entries := [], size := FONT_SIZE, col := UiKit.TEXT_DIM) -> void:
	font_size = size
	color = col
	add_theme_constant_override("separation", 26)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_entries(entries)


## Replaces every hint.
func set_entries(entries: Array) -> void:
	for e in _entries:
		(e[0] as Node).free()
	_entries.clear()
	for e in entries:
		add(str(e[0]), str(e[1]) if e.size() > 1 else "")


func add(prompt: String, when := "") -> PromptLabel:
	var l := PromptLabel.new(prompt, font_size, color)
	l.add_theme_font_override("normal_font", UiKit.font(true))
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(l)
	_entries.append([l, when])
	_update()
	return l


func _enter_tree() -> void:
	if not InputPrompts.prompts_changed.is_connected(_update):
		InputPrompts.prompts_changed.connect(_update)
	_update()


func _exit_tree() -> void:
	if InputPrompts.prompts_changed.is_connected(_update):
		InputPrompts.prompts_changed.disconnect(_update)


func _update() -> void:
	var pad := InputPrompts.using_pad()
	for e in _entries:
		(e[0] as Control).visible = e[1] == "" or (e[1] == "pad") == pad
