class_name ServerFinder
extends Node
## Client side of the server browser: queries servers for their info and
## latency, broadcasts on the LAN and asks the master server for its list.

signal found(info: Dictionary)  # server_info() + address, port, ping
signal master_failed(reason: String)

const LAN_PORTS := 10  # LAN scan covers game ports 27015..27024

var sock := PacketPeerUDP.new()
var _master_wait := -1.0
var _master_addr := ""


func _ready() -> void:
	sock.bind(0)
	sock.set_broadcast_enabled(true)


## Ask one server (its game port) for its info.
func query(address: String, port := Net.DEFAULT_PORT) -> void:
	var ip := address if address.is_valid_ip_address() else IP.resolve_hostname(address, IP.TYPE_IPV4)
	if ip == "":
		return
	sock.set_dest_address(ip, port + 1)
	sock.put_packet((Net.Q_INFO + JSON.stringify({"t": Time.get_ticks_usec() / 1000000.0})).to_utf8_buffer())


## Broadcast to the local network (and this PC) on the usual ports.
func scan_lan() -> void:
	var targets := ["255.255.255.255", "127.0.0.1"]
	for a in Net.local_addresses():
		var parts: PackedStringArray = a.split(".")
		if parts.size() == 4:
			targets.append("%s.%s.%s.255" % [parts[0], parts[1], parts[2]])
	var msg := (Net.Q_INFO + JSON.stringify({"t": Time.get_ticks_usec() / 1000000.0})).to_utf8_buffer()
	for t in targets:
		for i in LAN_PORTS:
			sock.set_dest_address(t, Net.DEFAULT_PORT + 1 + i)
			sock.put_packet(msg)


## Ask the master server for every registered server, then query each one.
func fetch_master(master: String) -> void:
	master = master.strip_edges()
	if master == "":
		master_failed.emit("No master server set.")
		return
	var host := master
	var port := Net.MASTER_PORT
	if master.contains(":"):
		host = master.get_slice(":", 0)
		port = int(master.get_slice(":", 1))
	var ip := host if host.is_valid_ip_address() else IP.resolve_hostname(host, IP.TYPE_IPV4)
	if ip == "":
		master_failed.emit("Cannot resolve %s." % host)
		return
	_master_addr = master
	_master_wait = 3.0
	sock.set_dest_address(ip, port)
	sock.put_packet(Net.M_LIST.to_utf8_buffer())


func _process(delta: float) -> void:
	if _master_wait > 0.0:
		_master_wait -= delta
		if _master_wait <= 0.0:
			master_failed.emit("Master server %s did not answer." % _master_addr)
	while sock.get_available_packet_count() > 0:
		var pkt := sock.get_packet()
		var ip := sock.get_packet_ip()
		var txt := pkt.get_string_from_utf8()
		if txt.begins_with(Net.Q_REPLY):
			var d = JSON.parse_string(txt.substr(Net.Q_REPLY.length()))
			if not (d is Dictionary):
				continue
			d["address"] = ip
			d["ping"] = int(maxf(0.0, Time.get_ticks_usec() / 1000000.0 - float(d.get("t", 0.0))) * 1000.0)
			d["compatible"] = int(d.get("v", 0)) == Net.PROTOCOL
			found.emit(d)
		elif txt.begins_with(Net.M_SERVERS):
			_master_wait = -1.0
			var d2 = JSON.parse_string(txt.substr(Net.M_SERVERS.length()))
			if d2 is Dictionary:
				for s in d2.get("servers", []):
					var addr := str(s)
					query(addr.get_slice(":", 0), int(addr.get_slice(":", 1)))
