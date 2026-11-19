class_name MessageBox
extends Dialog
## Small HL2-style message: text, optional text field (password), buttons. Closing it with B / Esc
## answers "no" (CANCEL), so a CONNECTING box closed that way stops connecting too.

signal answered(ok: bool, text: String)

var field: LineEdit
var text_label: Label
var ok_button: Button
var cancel_button: Button
## The focus starts on CANCEL (a confirm that can not be undone: leave the lobby, reset).
var focus_cancel := false
var _kb_note: Label
var _answered := false


func _init(title: String, text: String, with_field := false, secret := false, ok_text := "OK", cancel_text := "") -> void:
	super(title, Vector2(620, 320 if with_field else 250))
	cancel_stops_typing = false
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
		# typing needs a keyboard: say so while the player holds a pad
		_kb_note = UiKit.label("Type it with the keyboard.", 15, UiKit.TEXT_DIM)
		body.add_child(_kb_note)
	if cancel_text != "":
		cancel_button = add_button(cancel_text, func(): _answer(false))
	if ok_text != "":
		ok_button = add_button(ok_text, func(): _answer(true))


func _ready() -> void:
	if _kb_note:
		_update_note()
		InputPrompts.prompts_changed.connect(_update_note)
	var first: Control = cancel_button if focus_cancel and cancel_button else (ok_button if ok_button else cancel_button)
	if field and not focus_cancel:
		first = field
	default_focus = first
	if first:
		first.grab_focus.call_deferred()


func _update_note() -> void:
	_kb_note.visible = InputPrompts.using_pad()


func _answer(ok: bool) -> void:
	if _answered:
		return
	_answered = true
	answered.emit(ok, field.text if field else "")
	close()


func close() -> void:
	if is_queued_for_deletion() or _closing:
		return
	if not _answered:
		_answered = true
		answered.emit(false, "")
	super()
