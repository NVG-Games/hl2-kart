extends Node
## Autoload "Net": multiplayer in the manner of a GoldSrc / Source server.
## UDP 27015 carries the game (ENet), 27016 answers server-browser queries and
## LAN broadcasts (A2S_INFO-style), and a server can heartbeat to a master
## server (UDP 27010) so it shows up in the INTERNET list.
##
## Authority: every player simulates their own kart and streams its state to
## the server; the server simulates the bots, relays everyone's state as
## snapshots and owns the lobby, the race start, finishing order and results.
## Damage is decided by the peer that owns the victim's kart.

signal roster_changed
signal cfg_changed
signal chat_received(nick: String, text: String, kind: String)  # kind: chat / info
signal state_changed(state: String)
signal connect_failed(reason: String)
signal joined
signal left(reason: String)
signal countdown_changed(seconds: float)

const PROTOCOL := 1
const DEFAULT_PORT := 27015
const MASTER_PORT := 27010
const MAX_RACERS := 8
const SNAP_INTERVAL := 1.0 / 20.0
const STATE_INTERVAL := 1.0 / 30.0
const LOAD_TIMEOUT := 30.0
const FINISH_GRACE := 40.0  # seconds the field gets after the first player finishes
const RESULTS_TIME := 12.0
const HEARTBEAT := 20.0
const AUTOSTART := 5.0
## query protocol tags (UDP, query port = game port + 1)
const Q_INFO := "HL2KQ"
const Q_REPLY := "HL2KI"
const M_HEART := "HL2KH"
const M_GONE := "HL2KX"
const M_LIST := "HL2KL"
const M_SERVERS := "HL2KS"

var active := false
var is_server := false
var dedicated := false
var state := "offline"  # offline / connecting / lobby / race
var players := {}  # peer id -> {nick, character, vehicle, ready, ping, host}
var cfg := {}  # shared server rules (never the password)
var grid: Array = []  # race roster: [{slot, peer, bot, nick, character, vehicle, skill}]
var my_slot := -1
var race: Node = null
var results: Array = []
var external_ip := ""
var autostart_left := -1.0
var last_error := ""
var notice := ""  # why we were dropped, shown by the main menu
## tests: my own kart drives itself (godot ... -- --autodrive)
var autodrive := "--autodrive" in OS.get_cmdline_user_args()
## tests: simulated one-way latency on a client (-- --fakelag 100), in seconds
var fake_lag := 0.0

var _peer: ENetMultiplayerPeer
var _password := ""
var _port := DEFAULT_PORT
var _query: PacketPeerUDP
var _heartbeat_t := 0.0
var _master_addr := ""
var _upnp: UPNP
var _upnp_thread: Thread
var _join_info := {}
var _loaded := {}
var _load_t := 0.0
var _begun := false
var _finish_t := -1.0
var _results_t := -1.0
var _latest := {}  # slot -> PackedFloat32Array (latest state from its owner)
var _snap_t := 0.0
var _state_t := 0.0
var _ping_t := 0.0
var _roster_t := 0.0
var _offset := 0.0
var _offset_ok := false
var _samples: Array = []  # [rtt, offset]
var _finish_times := {}  # slot -> race time


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	var args := OS.get_cmdline_user_args()
	var fl := args.find("--fakelag")
	if fl >= 0 and fl + 1 < args.size():
		fake_lag = float(args[fl + 1]) / 1000.0
	if "--dedicated" in args:
		Engine.max_fps = 120
		_start_dedicated.call_deferred(args)
	elif "--master-server" in args:
		Engine.max_fps = 30
		get_tree().change_scene_to_file.call_deferred("res://scenes/master.tscn")


## Started as a dedicated or master server (no menus).
static func headless_role() -> bool:
	var args := OS.get_cmdline_user_args()
	return "--dedicated" in args or "--master-server" in args


# ================================================================ clock
## Server clock in seconds (clients estimate it from ping exchanges).
func now() -> float:
	var t := Time.get_ticks_usec() / 1000000.0
	return t if is_server or not active else t + _offset


func my_id() -> int:
	return multiplayer.get_unique_id() if active else 1


# ================================================================ hosting
## Start a listen server (the host plays too) or a dedicated one.
func host(options: Dictionary, as_dedicated := false) -> Error:
	leave()
	_port = int(options.get("port", DEFAULT_PORT))
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(_port, MAX_RACERS + 4)
	if err != OK:
		last_error = "Port %d is busy (UDP). Is another server running?" % _port
		_peer = null
		return err
	multiplayer.multiplayer_peer = _peer
	_query = PacketPeerUDP.new()
	if _query.bind(_port + 1) != OK:
		push_warning("query port %d busy: server will not show in browsers" % (_port + 1))
		_query = null
	active = true
	is_server = true
	dedicated = as_dedicated
	_password = str(options.get("password", ""))
	_master_addr = "" if options.get("lan_only", false) else str(options.get("master", ""))
	cfg = {
		"name": str(options.get("name", "")).strip_edges().left(48),
		"max_players": clampi(int(options.get("max_players", MAX_RACERS)), 1, MAX_RACERS),
		"bots": bool(options.get("bots", true)),
		"grid": clampi(int(options.get("grid", MAX_RACERS)), 2, MAX_RACERS),
		"laps": clampi(int(options.get("laps", 3)), 1, 9),
		"difficulty": clampi(int(options.get("difficulty", 1)), 0, 2),
		"sky": str(options.get("sky", "sky_day01_01")),
		"track": str(options.get("track", "city17_circuit")),
		"locked": _password != "",
		"lan_only": bool(options.get("lan_only", false)),
		"port": _port,
		"dedicated": as_dedicated,
	}
	if cfg["name"] == "":
		cfg["name"] = "%s's server" % Game.nickname() if not as_dedicated else "Half-Life 2: Kart server"
	players.clear()
	if not as_dedicated:
		players[1] = {"nick": Game.nickname(), "character": Game.settings["character"],
			"vehicle": Game.settings["vehicle"], "ready": false, "ping": 0, "host": true}
	_set_state("lobby")
	_heartbeat_t = 1.0
	if options.get("upnp", false) and not options.get("lan_only", false):
		_open_upnp()
	_info("Server started on UDP port %d" % _port)
	roster_changed.emit()
	cfg_changed.emit()
	return OK


## Change a shared rule (host only); everyone sees it at once.
func set_rule(key: String, value: Variant) -> void:
	if not is_server:
		return
	cfg[key] = value
	if key == "password":
		_password = str(value)
		cfg.erase("password")
		cfg["locked"] = _password != ""
	_s_cfg.rpc(cfg)
	cfg_changed.emit()


func kick(id: int, reason := "Kicked by the host") -> void:
	if not is_server or not players.has(id) or id == 1:
		return
	_s_reject.rpc_id(id, reason)
	_info("%s was kicked" % players[id]["nick"])
	_drop_later(id)


func _drop_later(id: int) -> void:
	await get_tree().create_timer(0.3).timeout
	if _peer and _peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED and id in multiplayer.get_peers():
		_peer.disconnect_peer(id)


# ================================================================ joining
func join(address: String, port := DEFAULT_PORT, password := "") -> Error:
	leave()
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(address, port)
	if err != OK:
		last_error = "Bad address: %s" % address
		_peer = null
		return err
	multiplayer.multiplayer_peer = _peer
	active = true
	is_server = false
	_port = port
	_join_info = {"v": PROTOCOL, "nick": Game.nickname(), "character": Game.settings["character"],
		"vehicle": Game.settings["vehicle"], "password": password}
	_set_state("connecting")
	_remember_history("%s:%d" % [address, port])
	return OK


func _remember_history(addr: String) -> void:
	var h: Array = Game.settings.get("history", []).duplicate()
	h.erase(addr)
	h.push_front(addr)
	Game.settings["history"] = h.slice(0, 20)
	Game.save_settings()


func _on_connected() -> void:
	_c_hello.rpc_id(1, _join_info)


func _on_connection_failed() -> void:
	last_error = "Could not connect to the server."
	_shutdown()
	connect_failed.emit(last_error)


func _on_server_disconnected() -> void:
	var reason := last_error if last_error != "" else "Lost connection to the server."
	notice = reason
	_shutdown()
	left.emit(reason)
	_back_to_menu()


## Leave the session (host: shuts the server down for everyone).
func leave(reason := "") -> void:
	if not active:
		return
	if is_server:
		for id in players:
			if id != 1:
				_s_reject.rpc_id(id, "The server was shut down.")
		_send_master(M_GONE)
	_shutdown()
	if reason != "":
		left.emit(reason)


func _shutdown() -> void:
	_close_upnp()
	if _peer:
		# let the goodbye packets (kick / shutdown reasons) leave before closing
		if _peer.host:
			_peer.host.flush()
		_peer.close()
	_peer = null
	multiplayer.multiplayer_peer = null
	if _query:
		_query.close()
	_query = null
	active = false
	is_server = false
	dedicated = false
	players.clear()
	grid.clear()
	_latest.clear()
	my_slot = -1
	race = null
	Game.session.clear()
	autostart_left = -1.0
	_samples.clear()
	_offset_ok = false
	_set_state("offline")


func _back_to_menu() -> void:
	var cs := get_tree().current_scene
	if cs and cs.scene_file_path != "res://scenes/main.tscn":
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/main.tscn")


# ================================================================ lobby (client -> server)
## Update my racer / vehicle / ready flag.
func set_profile(character: String, vehicle_id: String, ready: bool) -> void:
	if not active:
		return
	var info := {"character": character, "vehicle": vehicle_id, "ready": ready}
	if is_server:
		_apply_profile(1, info)
	else:
		_c_profile.rpc_id(1, info)


func say(text: String) -> void:
	text = text.strip_edges().left(160)
	if text == "" or not active:
		return
	if is_server:
		_broadcast_chat(players.get(1, {}).get("nick", "Console"), text, "chat")
	else:
		_c_chat.rpc_id(1, text)


func start_race_now() -> void:
	if is_server and state == "lobby":
		_start_race()


func humans() -> int:
	return players.size()


@rpc("any_peer", "call_remote", "reliable")
func _c_hello(info: Dictionary) -> void:
	if not is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if int(info.get("v", 0)) != PROTOCOL:
		_reject(id, "Server is running a different version of the game.")
		return
	if _password != "" and str(info.get("password", "")) != _password:
		_reject(id, "Bad password.")
		return
	if players.size() >= int(cfg["max_players"]):
		_reject(id, "Server is full.")
		return
	var nick := _unique_nick(str(info.get("nick", "Player")).strip_edges().left(24))
	players[id] = {"nick": nick, "character": _valid_char(str(info.get("character", "alyx"))),
		"vehicle": _valid_vehicle(str(info.get("vehicle", "buggy"))), "ready": false, "ping": 0, "host": false}
	_s_welcome.rpc_id(id, id, cfg, players, state)
	_s_roster.rpc(players)
	roster_changed.emit()
	_info("%s joined the game" % nick)
	if state == "race":
		_s_chat.rpc_id(id, "", "A race is in progress. You will join the next one.", "info")


func _reject(id: int, reason: String) -> void:
	_s_reject.rpc_id(id, reason)
	_drop_later(id)


func _unique_nick(n: String) -> String:
	if n == "":
		n = "Player"
	var taken := []
	for p in players.values():
		taken.append(p["nick"])
	var out := n
	var i := 2
	while out in taken:
		out = "%s (%d)" % [n, i]
		i += 1
	return out


func _valid_char(c: String) -> String:
	return c if Game.character(c).get("id", "") == c else "alyx"


func _valid_vehicle(v: String) -> String:
	return v if Game.vehicle(v)["id"] == v else "buggy"


@rpc("any_peer", "call_remote", "reliable")
func _c_profile(info: Dictionary) -> void:
	if is_server:
		_apply_profile(multiplayer.get_remote_sender_id(), info)


func _apply_profile(id: int, info: Dictionary) -> void:
	if not players.has(id):
		return
	var p: Dictionary = players[id]
	p["character"] = _valid_char(str(info.get("character", p["character"])))
	p["vehicle"] = _valid_vehicle(str(info.get("vehicle", p["vehicle"])))
	p["ready"] = bool(info.get("ready", false))
	_s_roster.rpc(players)
	roster_changed.emit()


@rpc("any_peer", "call_remote", "reliable")
func _c_chat(text: String) -> void:
	if not is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if players.has(id):
		_broadcast_chat(players[id]["nick"], text.strip_edges().left(160), "chat")


func _broadcast_chat(nick: String, text: String, kind: String) -> void:
	_s_chat.rpc(nick, text, kind)
	chat_received.emit(nick, text, kind)
	if dedicated:
		print("%s%s" % ["" if nick == "" else nick + ": ", text])


func _info(text: String) -> void:
	if is_server:
		_broadcast_chat("", text, "info")


# ================================================================ lobby (server -> clients)
@rpc("authority", "call_remote", "reliable")
func _s_welcome(id: int, c: Dictionary, p: Dictionary, st: String) -> void:
	cfg = c
	players = p
	last_error = ""
	_set_state("lobby" if st != "race" else "race_wait")
	joined.emit()
	roster_changed.emit()
	cfg_changed.emit()
	print("joined server as #%d" % id)


@rpc("authority", "call_remote", "reliable")
func _s_reject(reason: String) -> void:
	last_error = reason
	if state == "connecting":
		_shutdown()
		connect_failed.emit(reason)


@rpc("authority", "call_remote", "reliable")
func _s_roster(p: Dictionary) -> void:
	players = p
	roster_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _s_cfg(c: Dictionary) -> void:
	cfg = c
	cfg_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _s_chat(nick: String, text: String, kind: String) -> void:
	chat_received.emit(nick, text, kind)


@rpc("authority", "call_remote", "reliable")
func _s_countdown(seconds: float) -> void:
	autostart_left = seconds
	countdown_changed.emit(seconds)


func _set_state(s: String) -> void:
	state = s
	state_changed.emit(s)


func _on_peer_connected(_id: int) -> void:
	pass


func _on_peer_disconnected(id: int) -> void:
	# ENet still lists the leaving peer during this signal: broadcast a frame later
	_handle_disconnect.call_deferred(id)


func _handle_disconnect(id: int) -> void:
	if not is_server or not players.has(id):
		return
	var nick: String = players[id]["nick"]
	players.erase(id)
	_loaded.erase(id)
	_s_roster.rpc(players)
	roster_changed.emit()
	if state == "race":
		for e in grid:
			if int(e["peer"]) == id:
				e["peer"] = 0
				e["bot"] = true
				_send_event_from_server("bot", [int(e["slot"])])
				_info("%s left the game (a bot takes over)" % nick)
				return
	_info("%s left the game" % nick)


# ================================================================ race start
func _start_race() -> void:
	autostart_left = -1.0
	_s_countdown.rpc(-1.0)
	countdown_changed.emit(-1.0)
	grid = _build_grid()
	var rules := {"laps": cfg["laps"], "difficulty": cfg["difficulty"], "sky": cfg["sky"], "track": cfg["track"]}
	for id in players:
		players[id]["ready"] = false
	_s_roster.rpc(players)
	_loaded.clear()
	_load_t = 0.0
	_begun = false
	_finish_t = -1.0
	_results_t = -1.0
	_finish_times.clear()
	results.clear()
	_s_start_race.rpc(grid, rules)
	_s_start_race(grid, rules)


## Humans start at the back of the grid in random order (Mario Kart online);
## bots fill the front up to the chosen field size.
func _build_grid() -> Array:
	var ids: Array = players.keys()
	ids.shuffle()
	var total := ids.size()
	if cfg["bots"]:
		total = maxi(total, int(cfg["grid"]))
	total = clampi(total, 1, MAX_RACERS)
	var n_bots := total - ids.size()
	var used := []
	for id in ids:
		used.append(players[id]["character"])
	var pool: Array = Game.CHARACTERS.map(func(c: Dictionary) -> String: return c["id"])
	pool.shuffle()
	pool.sort_custom(func(a: String, b: String) -> bool: return (a in used) == false and (b in used))
	var rides: Array = []
	while rides.size() < n_bots:
		var batch: Array = Game.VEHICLES.map(func(v: Dictionary) -> String: return v["id"])
		batch.shuffle()
		rides.append_array(batch)
	var diff: Dictionary = Game.DIFFICULTIES[int(cfg["difficulty"])]
	var out := []
	for i in n_bots:
		var c: String = pool[i % pool.size()]
		out.append({"peer": 0, "bot": true, "nick": Game.character(c)["name"], "character": c,
			"vehicle": rides[i], "skill": float(diff["ai_skill"]) * randf_range(0.93, 1.03)})
	for id in ids:
		var p: Dictionary = players[id]
		out.append({"peer": id, "bot": false, "nick": p["nick"], "character": p["character"],
			"vehicle": p["vehicle"], "skill": 0.0})
	for i in out.size():
		out[i]["slot"] = i
	return out


@rpc("authority", "call_remote", "reliable")
func _s_start_race(g: Array, rules: Dictionary) -> void:
	grid = g
	Game.session = rules
	my_slot = -1
	for e in grid:
		if int(e["peer"]) == my_id() and not e["bot"]:
			my_slot = int(e["slot"])
	_latest.clear()
	race = null
	results.clear()
	_set_state("race")
	Game.stop_music()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/race.tscn")


## Called by the race scene once it has built the track and karts.
func race_ready(r: Node) -> void:
	race = r
	if is_server:
		_loaded[1] = true
		_check_all_loaded()
	else:
		_c_loaded.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _c_loaded() -> void:
	if is_server:
		_loaded[multiplayer.get_remote_sender_id()] = true
		_check_all_loaded()


func _check_all_loaded() -> void:
	if _begun or race == null:
		return
	for e in grid:
		var p := int(e["peer"])
		if not e["bot"] and p != 1 and players.has(p) and not _loaded.has(p):
			return
	_begin()


func _begin() -> void:
	_begun = true
	_s_begin.rpc()
	_s_begin()


@rpc("authority", "call_remote", "reliable")
func _s_begin() -> void:
	if race:
		race.net_begin()


# ================================================================ race state streaming
func _physics_process(delta: float) -> void:
	if not active or state != "race" or race == null or not is_instance_valid(race):
		return
	if is_server:
		_snap_t -= delta
		if _snap_t <= 0.0:
			_snap_t = SNAP_INTERVAL
			_broadcast_snapshot()
	elif my_slot >= 0:
		_state_t -= delta
		if _state_t <= 0.0:
			_state_t = STATE_INTERVAL
			var k: Kart = race.kart_by_slot(my_slot)
			if k:
				var st := k.pack_state(now())
				_lagged(func(): _c_state.rpc_id(1, st))


func _broadcast_snapshot() -> void:
	var out := PackedFloat32Array()
	for k: Kart in race.karts:
		var data: PackedFloat32Array
		if not k.remote:
			data = k.pack_state(now())
		elif _latest.has(k.net_slot):
			data = _latest[k.net_slot]
		else:
			continue
		out.append(float(k.net_slot))
		out.append_array(data)
	if not out.is_empty() and multiplayer.get_peers().size() > 0:
		_s_snap.rpc(out)


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _c_state(data: PackedFloat32Array) -> void:
	if not is_server or race == null or state != "race":
		return
	var id := multiplayer.get_remote_sender_id()
	for e in grid:
		if int(e["peer"]) == id and not e["bot"]:
			var slot := int(e["slot"])
			_latest[slot] = data
			var k: Kart = race.kart_by_slot(slot)
			if k:
				k.apply_net_state(data)
			return


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _s_snap(data: PackedFloat32Array) -> void:
	if fake_lag > 0.0:
		_lagged(func(): _apply_snap(data))
	else:
		_apply_snap(data)


## Run now, or after the simulated latency.
func _lagged(cb: Callable) -> void:
	if fake_lag <= 0.0:
		cb.call()
	else:
		get_tree().create_timer(fake_lag, true, true).timeout.connect(cb)


func _apply_snap(data: PackedFloat32Array) -> void:
	if race == null or not is_instance_valid(race):
		return
	var stride := Kart.NET_FLOATS + 1
	var i := 0
	while i + stride <= data.size():
		var slot := int(data[i])
		if slot != my_slot:
			var k: Kart = race.kart_by_slot(slot)
			if k:
				k.apply_net_state(data.slice(i + 1, i + stride))
		i += stride


# ================================================================ race events
## Events from a kart's owner: item use, crate smashed, trap blown, lap, finish.
func send_event(kind: String, args: Array) -> void:
	if not active:
		return
	if is_server:
		_send_event_from_server(kind, args)
	else:
		_c_event.rpc_id(1, kind, args)


func _send_event_from_server(kind: String, args: Array, except := 0) -> void:
	_server_note_event(kind, args)
	for id in multiplayer.get_peers():
		if id != except:
			_s_event.rpc_id(id, kind, args)
	if except != 0 and race:
		race.net_event(kind, args)
	elif kind == "bot" and race:
		race.net_event(kind, args)


@rpc("any_peer", "call_remote", "reliable")
func _c_event(kind: String, args: Array) -> void:
	if is_server:
		_send_event_from_server(kind, args, multiplayer.get_remote_sender_id())


@rpc("authority", "call_remote", "reliable")
func _s_event(kind: String, args: Array) -> void:
	if race and is_instance_valid(race):
		race.net_event(kind, args)


func _server_note_event(kind: String, args: Array) -> void:
	if kind == "finish":
		var slot := int(args[0])
		if not _finish_times.has(slot):
			_finish_times[slot] = float(args[1])
			var e: Dictionary = grid[slot]
			if not e["bot"] and _finish_t < 0.0:
				_finish_t = 0.0
				_info("%s finished. The race ends in %d seconds." % [e["nick"], int(FINISH_GRACE)])


func _race_tick(delta: float) -> void:
	if not is_server or state != "race":
		return
	if not _begun:
		_load_t += delta
		if race and _load_t > LOAD_TIMEOUT:
			_begin()
		return
	if _results_t >= 0.0:
		_results_t += delta
		if _results_t > RESULTS_TIME:
			_results_t = -1.0
			back_to_lobby()
		return
	var humans_left := 0
	for e in grid:
		if not e["bot"] and players.has(int(e["peer"])) and not _finish_times.has(int(e["slot"])):
			humans_left += 1
	if _finish_t >= 0.0:
		_finish_t += delta
	var everyone_human_done := humans_left == 0 and (_finish_t >= 0.0 or players.is_empty())
	if everyone_human_done or _finish_t > FINISH_GRACE:
		_end_race()


func _end_race() -> void:
	_results_t = 0.0
	_finish_t = -1.0
	var order: Array = []
	for e in grid:
		var slot := int(e["slot"])
		var k: Kart = race.kart_by_slot(slot) if race else null
		order.append({"slot": slot, "nick": e["nick"], "character": e["character"], "bot": e["bot"],
			"time": float(_finish_times.get(slot, -1.0)), "progress": k.total_progress if k else 0.0})
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var fa: bool = a["time"] >= 0.0
		var fb: bool = b["time"] >= 0.0
		if fa != fb:
			return fa
		if fa:
			return a["time"] < b["time"]
		return a["progress"] > b["progress"])
	_s_race_over.rpc(order)
	_s_race_over(order)
	if dedicated:
		for i in order.size():
			var e: Dictionary = order[i]
			print("  %d. %-24s %s" % [i + 1, e["nick"] + (" (bot)" if e["bot"] else ""), "%.2f" % e["time"] if e["time"] >= 0.0 else "--"])


@rpc("authority", "call_remote", "reliable")
func _s_race_over(order: Array) -> void:
	results = order
	if race and is_instance_valid(race):
		race.net_results(order, RESULTS_TIME)


## Everyone back to the lobby (end of results, or the host aborts the race).
func back_to_lobby() -> void:
	if not is_server:
		return
	_s_to_lobby.rpc()
	_s_to_lobby()


@rpc("authority", "call_remote", "reliable")
func _s_to_lobby() -> void:
	race = null
	grid.clear()
	_latest.clear()
	my_slot = -1
	Game.session.clear()
	for id in players:
		players[id]["ready"] = false
	_set_state("lobby")
	get_tree().paused = false
	if dedicated:
		get_tree().change_scene_to_file("res://scenes/dedicated.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/main.tscn")


# ================================================================ ping / clock
func _process(delta: float) -> void:
	_poll_query()
	if not active:
		return
	if is_server:
		_race_tick(delta)
		_lobby_tick(delta)
		_heartbeat_t -= delta
		if _heartbeat_t <= 0.0:
			_heartbeat_t = HEARTBEAT
			_send_master(M_HEART)
		_roster_t -= delta
		if _roster_t <= 0.0 and _peer:
			_roster_t = 2.0
			var changed := false
			for id in players:
				if id == 1:
					continue
				var pp := _peer.get_peer(id)
				if pp:
					var rtt := int(pp.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))
					if rtt != int(players[id]["ping"]):
						players[id]["ping"] = rtt
						changed = true
			if changed:
				_s_roster.rpc(players)
				roster_changed.emit()
	elif state != "connecting":
		_ping_t -= delta
		if _ping_t <= 0.0:
			_ping_t = 1.0 if _offset_ok else 0.2
			var tp := Time.get_ticks_usec() / 1000000.0
			_lagged(func(): _c_ping.rpc_id(1, tp))


func _lobby_tick(delta: float) -> void:
	if state != "lobby" or players.is_empty():
		if autostart_left >= 0.0:
			autostart_left = -1.0
			_s_countdown.rpc(-1.0)
			countdown_changed.emit(-1.0)
		return
	var all_ready := true
	for p in players.values():
		if not p["ready"]:
			all_ready = false
	if all_ready and autostart_left < 0.0:
		autostart_left = AUTOSTART
		_s_countdown.rpc(autostart_left)
		countdown_changed.emit(autostart_left)
	elif not all_ready and autostart_left >= 0.0:
		autostart_left = -1.0
		_s_countdown.rpc(-1.0)
		countdown_changed.emit(-1.0)
	if autostart_left >= 0.0:
		autostart_left -= delta
		if autostart_left <= 0.0:
			_start_race()


@rpc("any_peer", "call_remote", "unreliable")
func _c_ping(t: float) -> void:
	if is_server:
		_s_pong.rpc_id(multiplayer.get_remote_sender_id(), t, now())


@rpc("authority", "call_remote", "unreliable")
func _s_pong(t_client: float, t_server: float) -> void:
	if fake_lag > 0.0:
		_lagged(func(): _pong(t_client, t_server))
	else:
		_pong(t_client, t_server)


func _pong(t_client: float, t_server: float) -> void:
	var local := Time.get_ticks_usec() / 1000000.0
	var rtt := local - t_client
	_samples.append([rtt, t_server + rtt * 0.5 - local])
	if _samples.size() > 12:
		_samples.pop_front()
	var best: Array = _samples[0]
	for s in _samples:
		if s[0] < best[0]:
			best = s
	if not _offset_ok or absf(best[1] - _offset) > 0.25:
		_offset = best[1]
	else:
		_offset = lerpf(_offset, best[1], 0.2)
	_offset_ok = _samples.size() >= 3


# ================================================================ server browser side
## Answer A2S_INFO-style queries (also LAN broadcasts) on the query port.
func _poll_query() -> void:
	if _query == null:
		return
	while _query.get_available_packet_count() > 0:
		var pkt := _query.get_packet()
		var ip := _query.get_packet_ip()
		var port := _query.get_packet_port()
		var txt := pkt.get_string_from_utf8()
		if not txt.begins_with(Q_INFO):
			continue
		var req = JSON.parse_string(txt.substr(Q_INFO.length()))
		var info := server_info()
		if req is Dictionary:
			info["t"] = req.get("t", 0.0)
		_query.set_dest_address(ip, port)
		_query.put_packet((Q_REPLY + JSON.stringify(info)).to_utf8_buffer())


func server_info() -> Dictionary:
	var nicks := []
	for p in players.values():
		nicks.append(p["nick"])
	var st := "Lobby"
	if state == "race":
		var lap := 0
		if race and is_instance_valid(race) and race.get("karts"):
			for k in race.karts:
				lap = maxi(lap, k.lap + 1)
		st = "Racing, lap %d/%d" % [clampi(lap, 1, int(cfg["laps"])), int(cfg["laps"])]
	return {"v": PROTOCOL, "name": cfg.get("name", ""), "map": Game.track(str(cfg.get("track", ""))).get("name", ""), "players": players.size(),
		"max": cfg.get("max_players", MAX_RACERS), "bots": cfg.get("bots", false), "grid": cfg.get("grid", 8),
		"state": st, "locked": _password != "", "port": _port, "dedicated": dedicated, "list": nicks,
		"laps": cfg.get("laps", 3), "difficulty": cfg.get("difficulty", 1)}


func _send_master(tag: String) -> void:
	if _master_addr == "" or _query == null:
		return
	var host := _master_addr
	var mport := MASTER_PORT
	if host.contains(":"):
		mport = int(host.get_slice(":", 1))
		host = host.get_slice(":", 0)
	var ip := host if host.is_valid_ip_address() else IP.resolve_hostname(host, IP.TYPE_IPV4)
	if ip == "":
		return
	_query.set_dest_address(ip, mport)
	_query.put_packet((tag + JSON.stringify({"port": _port, "v": PROTOCOL})).to_utf8_buffer())


## Ask the router to forward the game + query ports (UPnP), off the main thread.
func _open_upnp() -> void:
	_upnp_thread = Thread.new()
	_upnp_thread.start(func():
		var u := UPNP.new()
		if u.discover(2000, 2, "InternetGatewayDevice") != UPNP.UPNP_RESULT_SUCCESS:
			_upnp_done.call_deferred(null, "")
			return
		var gw := u.get_gateway()
		if gw == null or not gw.is_valid_gateway():
			_upnp_done.call_deferred(null, "")
			return
		var ok := u.add_port_mapping(_port, _port, "HL2 Kart", "UDP", 0) == UPNP.UPNP_RESULT_SUCCESS
		u.add_port_mapping(_port + 1, _port + 1, "HL2 Kart query", "UDP", 0)
		_upnp_done.call_deferred(u if ok else null, u.query_external_address() if ok else ""))


func _upnp_done(u: UPNP, ip: String) -> void:
	if _upnp_thread:
		_upnp_thread.wait_to_finish()
		_upnp_thread = null
	_upnp = u
	external_ip = ip
	if active and is_server:
		_info("UPnP: ports %d-%d opened, internet address %s" % [_port, _port + 1, ip] if u else "UPnP: router did not open the ports (forward UDP %d-%d by hand for internet play)" % [_port, _port + 1])
		cfg_changed.emit()


func _close_upnp() -> void:
	if _upnp_thread:
		_upnp_thread.wait_to_finish()
		_upnp_thread = null
	if _upnp:
		_upnp.delete_port_mapping(_port, "UDP")
		_upnp.delete_port_mapping(_port + 1, "UDP")
	_upnp = null
	external_ip = ""


## LAN addresses others can type into CONNECT.
func local_addresses() -> Array:
	var out := []
	for a in IP.get_local_addresses():
		if a.contains(":") or a.begins_with("127.") or a.begins_with("169.254."):
			continue
		out.append(a)
	return out


# ================================================================ dedicated server
func _start_dedicated(args: PackedStringArray) -> void:
	var o := DedicatedConfig.load_options(args)
	var err := host(o, true)
	if err != OK:
		printerr("could not start server: ", last_error)
		get_tree().quit(1)
		return
	print("Half-Life 2: Kart dedicated server '%s' on UDP %d (query %d), %d players, bots %s" % [
		cfg["name"], _port, _port + 1, cfg["max_players"], "on" if cfg["bots"] else "off"])
	if _master_addr != "":
		print("heartbeat to master server ", _master_addr)
	for a in local_addresses():
		print("  players can connect to %s:%d" % [a, _port])
	add_child(DedicatedConsole.new())
	get_tree().change_scene_to_file("res://scenes/dedicated.tscn")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and active:
		leave()


func _exit_tree() -> void:
	if active:
		leave()
