class_name ServerBrowser
extends Dialog
## FIND SERVERS, laid out like the Half-Life server browser: INTERNET (the
## master server's list), FAVORITES, HISTORY and LAN (broadcast). Every server
## is queried for its name, players, status and latency.

signal join_requested(address: String, port: int, password: String)

const TABS := ["INTERNET", "FAVORITES", "HISTORY", "LAN"]

var tabs: TabBar
var list: Tree
var status: Label
var finder: ServerFinder
var master_row: HBoxContainer
var master_edit: LineEdit
var address_edit: LineEdit
var fav_button: Button
var connect_button: Button
var _rows := {}  # "ip:port" -> TreeItem
var _wait := 0.0


func _init() -> void:
	super("FIND SERVERS", Vector2(1320, 800))


func _ready() -> void:
	finder = ServerFinder.new()
	add_child(finder)
	finder.found.connect(_on_found)
	finder.master_failed.connect(func(r: String):
		_wait = 0.0
		status.text = r)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	top.add_child(UiKit.label("Your name", 18))
	var nick := UiKit.text_field(Game.nickname(), "Player", func(t: String): Game.settings["nickname"] = t.strip_edges(), 320)
	nick.max_length = 24
	top.add_child(nick)
	body.add_child(top)
	tabs = TabBar.new()
	for t in TABS:
		tabs.add_tab(t)
	tabs.focus_mode = Control.FOCUS_ALL
	body.add_child(tabs)
	master_row = HBoxContainer.new()
	master_row.add_theme_constant_override("separation", 14)
	master_row.add_child(UiKit.label("Master server", 18))
	master_edit = UiKit.text_field(str(Game.settings.get("master_server", "")), "host or ip[:27010]",
		func(t: String): Game.settings["master_server"] = t.strip_edges(), 360)
	master_row.add_child(master_edit)
	var mnote := UiKit.label("Start one anywhere with  --master-server ; servers that know it appear here.", 15, UiKit.TEXT_DIM)
	master_row.add_child(mnote)
	body.add_child(master_row)
	list = Tree.new()
	list.columns = 5
	list.hide_root = true
	list.column_titles_visible = true
	list.select_mode = Tree.SELECT_ROW
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var titles := ["", "SERVERS", "PLAYERS", "STATUS", "LATENCY"]
	var widths := [40, 520, 150, 330, 110]
	for i in titles.size():
		list.set_column_title(i, titles[i])
		list.set_column_title_alignment(i, HORIZONTAL_ALIGNMENT_LEFT)
		list.set_column_custom_minimum_width(i, widths[i])
		list.set_column_expand(i, i == 1)
	list.item_activated.connect(_connect_selected)
	list.item_selected.connect(_update_buttons)
	body.add_child(list)
	status = UiKit.label("", 15, UiKit.TEXT_DIM)
	body.add_child(status)
	var direct := HBoxContainer.new()
	direct.add_theme_constant_override("separation", 14)
	direct.add_child(UiKit.label("Connect to address", 18))
	address_edit = UiKit.text_field("", "192.168.1.5  or  my.server.net:27015", func(_t): pass, 420)
	address_edit.text_submitted.connect(func(_t): _connect_address())
	direct.add_child(address_edit)
	var go := UiKit.button("CONNECT", 150)
	go.pressed.connect(_connect_address)
	direct.add_child(go)
	body.add_child(direct)
	fav_button = add_button("ADD TO FAVORITES", _toggle_favorite)
	fav_button.custom_minimum_size.x = 230
	add_button("REFRESH", _refresh)
	connect_button = add_button("CONNECT", _connect_selected)
	add_button("CLOSE", close)
	tabs.tab_changed.connect(func(_i):
		Game.play_ui("res://assets/sound/ui/buttonclick.wav", -10.0)
		_refresh())
	tabs.current_tab = 3 if str(Game.settings.get("master_server", "")) == "" else 0
	_refresh()
	tabs.grab_focus.call_deferred()


func _process(delta: float) -> void:
	if _wait > 0.0:
		_wait -= delta
		if _wait <= 0.0:
			_update_status()


func _update_status() -> void:
	var n := 0
	for k in _rows:
		if (_rows[k] as TreeItem).get_metadata(0).get("alive", false):
			n += 1
	if n == 0:
		var hint := ""
		match tabs.current_tab:
			3:
				hint = "  Ask your friend to CREATE SERVER, or type their address below."
			1:
				hint = "  Add servers with ADD TO FAVORITES or by address."
		status.text = "No servers responded." + hint
	else:
		status.text = "%d server%s" % [n, "" if n == 1 else "s"]


func _refresh() -> void:
	list.clear()
	list.create_item()
	_rows.clear()
	master_row.visible = tabs.current_tab == 0
	status.text = "Refreshing..."
	_wait = 2.0
	match tabs.current_tab:
		0:
			Game.save_settings()
			finder.fetch_master(master_edit.text)
			_wait = 4.0
		1:
			for a in Game.settings.get("favorites", []):
				_placeholder(str(a))
		2:
			for a in Game.settings.get("history", []):
				_placeholder(str(a))
		3:
			finder.scan_lan()
	_update_buttons()


static func parse_address(text: String) -> Array:
	text = text.strip_edges()
	var port := Net.DEFAULT_PORT
	var host := text
	if text.count(":") == 1:
		host = text.get_slice(":", 0)
		port = int(text.get_slice(":", 1))
	return [host, port]


func _placeholder(addr: String) -> void:
	var a := parse_address(addr)
	var it := list.create_item()
	it.set_text(1, addr)
	it.set_text(3, "no response")
	it.set_custom_color(1, UiKit.TEXT_DIM)
	it.set_custom_color(3, UiKit.TEXT_DIM)
	it.set_metadata(0, {"address": a[0], "port": a[1], "locked": false, "alive": false, "key": addr})
	_rows["%s:%d" % [a[0], a[1]]] = it
	finder.query(a[0], a[1])


func _on_found(info: Dictionary) -> void:
	var key := "%s:%d" % [info["address"], int(info.get("port", Net.DEFAULT_PORT))]
	# the same LAN server answers on 127.0.0.1 and on its LAN address: keep one
	for k in _rows.keys():
		var m: Dictionary = (_rows[k] as TreeItem).get_metadata(0)
		if k != key and m.get("name", "") == info.get("name", "") and int(m["port"]) == int(info.get("port", 0)) and m.get("alive", false):
			if str(info["address"]).begins_with("127."):
				return
			if str(m["address"]).begins_with("127."):
				(_rows[k] as TreeItem).free()
				_rows.erase(k)
	var it: TreeItem = _rows.get(key)
	if it == null:
		it = list.create_item()
		_rows[key] = it
	var ok: bool = info.get("compatible", true)
	it.set_text(0, "PW" if info.get("locked", false) else "")
	it.set_text(1, str(info.get("name", key)))
	var bots := ""
	if info.get("bots", false):
		bots = "  +bots"
	it.set_text(2, "%d / %d%s" % [int(info.get("players", 0)), int(info.get("max", 8)), bots])
	it.set_text(3, str(info.get("state", "")) + ("" if ok else "  (different version)"))
	it.set_text(4, str(int(info.get("ping", 0))))
	for c in 5:
		it.set_custom_color(c, UiKit.TEXT if ok else UiKit.TEXT_DIM)
	it.set_custom_color(0, UiKit.ORANGE)
	it.set_tooltip_text(1, "%s:%d\n%s" % [info["address"], int(info.get("port", 0)), ", ".join(PackedStringArray(info.get("list", [])))])
	it.set_metadata(0, {"address": info["address"], "port": int(info.get("port", Net.DEFAULT_PORT)), "locked": info.get("locked", false),
		"alive": true, "compatible": ok, "name": info.get("name", ""), "key": key})
	_update_status()
	_update_buttons()


func _selected() -> Dictionary:
	var it := list.get_selected()
	return it.get_metadata(0) if it else {}


func _update_buttons() -> void:
	var sel := _selected()
	connect_button.disabled = sel.is_empty()
	var favs: Array = Game.settings.get("favorites", [])
	fav_button.text = "REMOVE FAVORITE" if tabs.current_tab == 1 and not sel.is_empty() else "ADD TO FAVORITES"
	fav_button.disabled = sel.is_empty() and address_edit.text.strip_edges() == ""
	if not sel.is_empty() and tabs.current_tab != 1:
		fav_button.disabled = "%s:%d" % [sel["address"], sel["port"]] in favs


func _toggle_favorite() -> void:
	var favs: Array = Game.settings.get("favorites", []).duplicate()
	var sel := _selected()
	var addr := "%s:%d" % [sel["address"], sel["port"]] if not sel.is_empty() else address_edit.text.strip_edges()
	if addr == "":
		return
	if tabs.current_tab == 1 and not sel.is_empty():
		favs.erase(str(sel.get("key", addr)))
		favs.erase(addr)
	elif not addr in favs:
		favs.append(addr)
	Game.settings["favorites"] = favs
	Game.save_settings()
	if tabs.current_tab == 1:
		_refresh()
	else:
		_update_buttons()


func _connect_selected(_a = null) -> void:
	var sel := _selected()
	if sel.is_empty():
		return
	if not sel.get("compatible", true):
		status.text = "That server runs a different version of the game."
		return
	_ask_and_join(str(sel["address"]), int(sel["port"]), bool(sel.get("locked", false)))


func _connect_address() -> void:
	if address_edit.text.strip_edges() == "":
		address_edit.grab_focus()
		return
	var a := parse_address(address_edit.text)
	_ask_and_join(a[0], a[1], false)


func _ask_and_join(address: String, port: int, locked: bool) -> void:
	Game.save_settings()
	if not locked:
		join_requested.emit(address, port, "")
		return
	var m := MessageBox.new("PASSWORD", "This server is protected by a password.", true, true, "CONNECT", "CANCEL")
	m.answered.connect(func(ok: bool, text: String):
		if ok:
			join_requested.emit(address, port, text))
	add_child(m)
