class_name InputGlyph
extends TextureRect
## One input icon that keeps itself current (InputPrompts): an action's binding for the device the
## player is using, or one binding spec (InputBindings: "k87", "b0", "a5+") in the pad style.
## A binding with no icon shows its name on a keycap (KeycapTexture), as wide as the name needs.

## The action whose binding is shown (when spec is "").
var action := "":
	set(v):
		action = v
		refresh()
## One binding to show instead of an action's.
var spec := "":
	set(v):
		spec = v
		refresh()
## A prompt style to show instead of the player's device's ("" = follow it; "pad" = the pad's
## icons even while the keyboard is in use).
var style := "":
	set(v):
		style = v
		refresh()
## With no icon, the name on a keycap (else no texture: show text() yourself).
var keycap := true:
	set(v):
		keycap = v
		refresh()
var px := 32.0


func _init(action_ := "", size_px := 32.0) -> void:
	px = size_px
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	custom_minimum_size = Vector2(size_px, size_px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	action = action_


func _enter_tree() -> void:
	if not InputPrompts.prompts_changed.is_connected(refresh):
		InputPrompts.prompts_changed.connect(refresh)
	refresh()


func _exit_tree() -> void:
	if InputPrompts.prompts_changed.is_connected(refresh):
		InputPrompts.prompts_changed.disconnect(refresh)


func refresh() -> void:
	var st := _style()
	var tex := InputPrompts.spec_icon(spec, px, st) if spec != "" else InputPrompts.action_icon(action, px, st)
	if tex == null and keycap:
		var t := text()
		if t != "":
			tex = KeycapTexture.of(t, px)
	texture = tex
	# a keycap is as wide as its name
	custom_minimum_size = Vector2(maxf(px, px * tex.get_width() / maxf(tex.get_height(), 1.0)) if tex else px, px)


## The binding's name ("W", "RT", "CROSS").
func text() -> String:
	var st := _style()
	return InputPrompts.spec_text(spec, st) if spec != "" else InputPrompts.action_text(action, st)


func _style() -> String:
	return InputPrompts.pad_style() if style == "pad" else style
