class_name PromptLabel
extends RichTextLabel
## A line of text with input icons in it: "STUCK? PRESS {respawn} TO CALL THE CRANE" shows the
## icon of respawn's binding for the device the player is using (InputPrompts), and redraws itself
## when the device, the pad's family or a binding changes. {action} is any InputMap action
## (ui_accept, ui_cancel, ui_tab_prev... too); a binding with no icon shows its name on a keycap
## (KeycapTexture) as high as the icons.
## The text may hold BBCode, as long as no tag spans an {action}.

## The text with {action} tokens.
var prompt := "":
	set(v):
		prompt = v
		_rebuild()
## Icon height in px; 0: 1.4 times the font size.
var icon_px := 0.0:
	set(v):
		icon_px = v
		_rebuild()
## A prompt style to show instead of the player's device's ("keyboard", "ps5"...; "" = follow it).
var style := "":
	set(v):
		style = v
		_rebuild()
## The icons' tint (Kenney's glyphs are white): the HUD draws them in its yellow.
var icon_color := Color.WHITE:
	set(v):
		icon_color = v
		_rebuild()


func _init(text_ := "", font_size := 0, color := Color.WHITE) -> void:
	bbcode_enabled = true
	fit_content = true
	scroll_active = false
	autowrap_mode = TextServer.AUTOWRAP_OFF
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if font_size > 0:
		add_theme_font_size_override("normal_font_size", font_size)
		add_theme_font_size_override("bold_font_size", font_size)
	add_theme_color_override("default_color", color)
	prompt = text_


func _enter_tree() -> void:
	if not InputPrompts.prompts_changed.is_connected(_rebuild):
		InputPrompts.prompts_changed.connect(_rebuild)
	_rebuild()


func _exit_tree() -> void:
	if InputPrompts.prompts_changed.is_connected(_rebuild):
		InputPrompts.prompts_changed.disconnect(_rebuild)


func _rebuild() -> void:
	clear()
	var px := icon_px if icon_px > 0.0 else roundf(get_theme_font_size("normal_font_size") * 1.4)
	for seg in InputPrompts.parse_prompt(prompt):
		if seg is String:
			append_text(seg)
			continue
		var act: String = seg["action"]
		var tex := InputPrompts.action_icon(act, px, style)
		if tex == null:
			var t := InputPrompts.action_text(act, style)
			tex = KeycapTexture.of(t if t != "" else "?", px)
		add_image(tex, 0, int(px), icon_color)
