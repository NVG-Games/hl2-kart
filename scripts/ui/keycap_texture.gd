class_name KeycapTexture
extends Texture2D
## A key's or a button's name drawn as a keycap ("SHIFT", "PG UP", "CREATE", "L1"): what a prompt
## shows for a binding Kenney has no icon for, or whose icon is a word too small to read. It draws
## itself (no image), the way Kenney's key icons look: a filled rounded key in the colour it is
## drawn with and the name in dark, so a tint (the HUD's yellow) colours it like the icons beside
## it. of() keeps one per name, height and font.

const KEY_SHARE := 0.84  # the key's height in the texture (Kenney's keys leave a margin too)
const TEXT_SHARE := 0.5  # the name's font size, of the texture's height
const MIN_FONT := 10
const INK := Color(0.06, 0.06, 0.06)

static var _cache := {}

var label := ""
var height := 32.0
var font: Font
var _w := 32.0
var _box := StyleBoxFlat.new()


## The keycap for `name` at `px` high (cached), in `f` (the menus' bold Verdana by default).
static func of(name: String, px: float, f: Font = null) -> KeycapTexture:
	var fnt := f if f else UiKit.font(true)
	var key := "%s@%d@%d" % [name, roundi(px), fnt.get_instance_id()]
	if not _cache.has(key):
		_cache[key] = KeycapTexture.new(name, px, fnt)
	return _cache[key]


func _init(name := "", px := 32.0, f: Font = null) -> void:
	label = name
	height = maxf(px, 8.0)
	font = f if f else UiKit.font(true)
	var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size(height)).x
	_w = maxf(height, tw + height * 0.55)
	_box.anti_aliasing = true


static func _font_size(h: float) -> int:
	return maxi(roundi(h * TEXT_SHARE), MIN_FONT)


func _get_width() -> int:
	return ceili(_w)


func _get_height() -> int:
	return ceili(height)


func _has_alpha() -> bool:
	return true


func _is_pixel_opaque(_x: int, _y: int) -> bool:
	return false


func _draw(to_canvas_item: RID, pos: Vector2, modulate: Color, _transpose: bool) -> void:
	_paint(to_canvas_item, Rect2(pos, Vector2(_get_width(), _get_height())), modulate)


func _draw_rect(to_canvas_item: RID, rect: Rect2, _tile: bool, modulate: Color, _transpose: bool) -> void:
	_paint(to_canvas_item, rect, modulate)


func _draw_rect_region(to_canvas_item: RID, rect: Rect2, _src_rect: Rect2, modulate: Color, _transpose: bool,
		_clip_uv: bool) -> void:
	_paint(to_canvas_item, rect, modulate)


func _paint(ci: RID, rect: Rect2, modulate: Color) -> void:
	var key_h := rect.size.y * KEY_SHARE
	var r := Rect2(rect.position.x, rect.position.y + (rect.size.y - key_h) * 0.5, rect.size.x, key_h)
	_box.bg_color = modulate
	_box.set_corner_radius_all(maxi(int(key_h * 0.2), 2))
	_box.draw(ci, r)
	# (drawn at another height than it was made for: the name scales with it)
	var fs := maxi(roundi(_font_size(height) * rect.size.y / height), 6)
	var base := r.get_center().y + fs * 0.36  # capitals centred on the key
	font.draw_string(ci, Vector2(r.position.x, base), label, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs,
		Color(INK, modulate.a))
