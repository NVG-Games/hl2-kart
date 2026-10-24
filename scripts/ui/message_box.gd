class_name MessageBox
extends Dialog
## Small HL2-style message: text, optional text field (password), buttons.

signal answered(ok: bool, text: String)

var field: LineEdit
var text_label: Label


func _init(title: String, text: String, with_field := false, secret := false, ok_text := "OK", cancel_text := "") -> void:
	super(title, Vector2(620, 300 if with_field else 250))
	text_label = UiKit.label(text, 18, UiKit.TEXT)
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.custom_minimum_size.x = 560
	body.add_child(text_label)
	if with_field:
		field = LineEdit.new()
		field.secret = secret
		field.custom_minimum_size = Vector2(560, 42)
		field.text_submitted.connect(func(_t): _answer(true))
		body.add_child(field)
	if cancel_text != "":
		add_button(cancel_text, func(): _answer(false))
	if ok_text != "":
		add_button(ok_text, func(): _answer(true))


func _ready() -> void:
	if field:
		field.grab_focus.call_deferred()
	elif buttons.get_child_count() > 0:
		(buttons.get_child(buttons.get_child_count() - 1) as Control).grab_focus.call_deferred()


func _answer(ok: bool) -> void:
	answered.emit(ok, field.text if field else "")
	close()


func close() -> void:
	if not is_queued_for_deletion():
		super()
