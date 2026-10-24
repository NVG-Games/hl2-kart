class_name Dialog
extends Control
## Modal window in the HL2 GameUI manner: dimmed screen, dark frame, title,
## content area and a button row. ESC / B closes it.

signal closed

var frame: PanelContainer
var body: VBoxContainer
var buttons: HBoxContainer
var title_label: Label


func _init(title: String, size_px: Vector2) -> void:
	theme = UiKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	frame = PanelContainer.new()
	frame.set_anchors_preset(Control.PRESET_CENTER)
	frame.offset_left = -size_px.x * 0.5
	frame.offset_right = size_px.x * 0.5
	frame.offset_top = -size_px.y * 0.5
	frame.offset_bottom = size_px.y * 0.5
	add_child(frame)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	frame.add_child(v)
	title_label = UiKit.label(title, 28, Color.WHITE, true)
	v.add_child(title_label)
	body = VBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	v.add_child(body)
	buttons = HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 12)
	v.add_child(buttons)


func add_button(text: String, cb: Callable) -> Button:
	var b := UiKit.button(text)
	b.pressed.connect(cb)
	buttons.add_child(b)
	return b


func close() -> void:
	Game.save_settings()
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		Game.play_ui("res://assets/sound/ui/buttonclickrelease.wav", -5.0)
		close()
