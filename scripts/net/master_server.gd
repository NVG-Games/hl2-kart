extends Node
## Master server (like Valve's hl2master on UDP 27010): game servers send a
## heartbeat every 20 s, browsers ask for the list. Entries expire after 70 s.
## usage: godot --headless --path . -- --master-server [--port 27010]

const EXPIRE := 70.0
const PER_PACKET := 60

var sock := PacketPeerUDP.new()
var servers := {}  # "ip:port" -> last heartbeat (seconds)
var _print_t := 0.0


func _ready() -> void:
	var port := Net.MASTER_PORT
	var args := OS.get_cmdline_user_args()
	var i := args.find("--port")
	if i >= 0 and i + 1 < args.size():
		port = int(args[i + 1])
	if sock.bind(port) != OK:
		printerr("master: UDP port %d is busy" % port)
		get_tree().quit(1)
		return
	print("Half-Life 2: Kart master server on UDP %d" % port)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _process(delta: float) -> void:
	while sock.get_available_packet_count() > 0:
		var pkt := sock.get_packet()
		var ip := sock.get_packet_ip()
		var from_port := sock.get_packet_port()
		var txt := pkt.get_string_from_utf8()
		if txt.begins_with(Net.M_HEART) or txt.begins_with(Net.M_GONE):
			var d = JSON.parse_string(txt.substr(Net.M_HEART.length()))
			if not (d is Dictionary) or int(d.get("v", 0)) != Net.PROTOCOL:
				continue
			var key := "%s:%d" % [ip, int(d.get("port", Net.DEFAULT_PORT))]
			if txt.begins_with(Net.M_GONE):
				if servers.erase(key):
					print("server gone ", key)
			else:
				if not servers.has(key):
					print("server up   ", key)
				servers[key] = _now()
		elif txt.begins_with(Net.M_LIST):
			_send_list(ip, from_port)
	_print_t += delta
	if _print_t > 10.0:
		_print_t = 0.0
		for k in servers.keys():
			if _now() - float(servers[k]) > EXPIRE:
				servers.erase(k)
				print("server timed out ", k)


func _send_list(ip: String, port: int) -> void:
	var keys: Array = servers.keys()
	var parts := maxi(1, ceili(keys.size() / float(PER_PACKET)))
	sock.set_dest_address(ip, port)
	for p in parts:
		var chunk := keys.slice(p * PER_PACKET, (p + 1) * PER_PACKET)
		sock.put_packet((Net.M_SERVERS + JSON.stringify({"servers": chunk, "part": p, "of": parts})).to_utf8_buffer())
