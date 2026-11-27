extends Node
## Online rooms: play with anyone, on any network, by a 6-digit room code. No port forwarding,
## no VPN, no server of your own.
##
## The game's own multiplayer (ENet, the same as on a LAN) is carried through a public MQTT relay
## over a secure WebSocket (mqtt.gd), which crosses every router and firewall that lets the web
## through:
##   host:   its ENet server listens as usual; for every remote player the room opens a local UDP
##           socket to it, and ferries that player's datagrams to and from the relay
##   player: a local UDP port stands in for the host; its ENet client connects there, and the
##           room ferries the datagrams to and from the relay
## Datagrams are batched (every ~45 ms) into one relay message per direction.
## The code: its first digit names the relay the room is on, the other five are random. The room
## announces itself (retained) under its code, so a code is checked (exists? same version?)
## before anyone connects.
## Relays: the public brokers below, in order; or your own (a file user://relay.txt with one
## wss:// url, or the command line --relay=wss://...).

signal room_open(code)        # host: the room is open, this is its code
signal ready_local(port)      # player: connect ENet to 127.0.0.1:port
signal room_info(info)        # player: what the code points to {n, p, m, s, v}
signal room_failed(reason)

const NS = "sahur-rot/r1/"
const BROKERS = [
	"wss://broker.emqx.io:8084/mqtt",
	"wss://broker.hivemq.com:8884/mqtt",
	"wss://test.mosquitto.org:8081/mqtt",
]
const FLUSH = 0.045
const IDLE = 45.0

var mode = ""          # "" · "host" · "player"
var code = ""
var mqtt
var _host_port = 7777
var _cid = ""
var _socks = {}        # host: player id -> {sock, out, seen}
var _local: PacketPeerUDP
var _local_port = 0
var _enet_port = -1
var _out = []
var _flush_t = 0.0
var _info_t = 0.0
var _check_t = -1.0
var _got_info = false


func brokers() -> Array:
	for a in OS.get_cmdline_args():
		if a.begins_with("--relay="):
			return [a.substr(8)]
	var f = File.new()
	if f.open("user://relay.txt", File.READ) == OK:
		var u = f.get_line().strip_edges()
		f.close()
		if u.begins_with("ws://") or u.begins_with("wss://"):
			return [u]
	return BROKERS


func _new_mqtt() -> void:
	mqtt = load("res://scripts/mqtt.gd").new()
	add_child(mqtt)
	mqtt.connect("connected", self, "_on_up")
	mqtt.connect("failed", self, "_on_mqtt_failed")
	mqtt.connect("message", self, "_on_msg")
	mqtt.connect("closed", self, "_on_mqtt_closed")


func close() -> void:
	if mqtt:
		if mode == "host" and code != "" and mqtt.is_up:
			mqtt.publish(NS + code + "/info", PoolByteArray(), true)     # the room is gone
		mqtt.close()
		mqtt.queue_free()
	mqtt = null
	for k in _socks:
		_socks[k].sock.close()
	_socks = {}
	if _local:
		_local.close()
	_local = null
	_enet_port = -1
	_out = []
	mode = ""
	code = ""
	_check_t = -1.0
	_got_info = false


# ------------------------------------------------------------------ host
func open_host(enet_port: int) -> void:
	close()
	mode = "host"
	_host_port = enet_port
	_new_mqtt()
	mqtt.open(brokers())


# ------------------------------------------------------------------ player
func open_player(c: String) -> void:
	close()
	c = c.strip_edges().replace(" ", "").replace("-", "")
	if c.length() != 6 or not c.is_valid_integer():
		emit_signal("room_failed", "a room code has 6 digits")
		return
	mode = "player"
	code = c
	randomize()
	_cid = "%08x" % (randi() & 0x7fffffff)
	var bl = brokers()
	var i = int(c.substr(0, 1)) - 1
	_new_mqtt()
	mqtt.open([bl[i]] if bl == BROKERS and i >= 0 and i < bl.size() else bl)


# ------------------------------------------------------------------ relay events
func _on_up(url: String) -> void:
	if mode == "host":
		var i = max(0, BROKERS.find(url))
		code = str(i + 1) + "%05d" % (randi() % 100000)
		mqtt.subscribe(NS + code + "/up/+")
		_publish_info()
		emit_signal("room_open", code)
	elif mode == "player":
		mqtt.subscribe(NS + code + "/info")
		mqtt.subscribe(NS + code + "/down/" + _cid)
		_check_t = 6.0


func _on_mqtt_failed(reason: String) -> void:
	var m = mode
	close()
	emit_signal("room_failed", "could not reach the online relay (%s). check your internet." % reason if m != "" else reason)


func _on_mqtt_closed() -> void:
	if mode != "":
		var m = mode
		close()
		emit_signal("room_failed", "lost the online relay" if m == "player" else "the online room closed (relay lost)")


func _on_msg(topic: String, payload: PoolByteArray) -> void:
	if mode == "host":
		var parts = topic.split("/")
		var key = parts[parts.size() - 1]
		if not topic.begins_with(NS + code + "/up/") or key == "":
			return
		var s = _socks.get(key)
		if s == null:
			var sock = PacketPeerUDP.new()
			if sock.listen(0, "127.0.0.1") != OK:
				return
			sock.set_dest_address("127.0.0.1", _host_port)
			s = {"sock": sock, "out": [], "seen": 0}
			_socks[key] = s
		s.seen = OS.get_ticks_msec()
		for d in _unpack(payload):
			s.sock.put_packet(d)
	elif mode == "player":
		if topic == NS + code + "/info":
			if payload.size() == 0:
				if not _got_info:
					_fail("no room with that code (it may have closed)")
				return
			var r = JSON.parse(payload.get_string_from_utf8())
			if r.error != OK or typeof(r.result) != TYPE_DICTIONARY:
				return
			var info: Dictionary = r.result
			emit_signal("room_info", info)
			if _got_info:
				return
			_got_info = true
			_check_t = -1.0
			if str(info.get("v", "")) != Net.VERSION:
				_fail("that room runs another version of sahur: everyone needs the same download")
				return
			_local = PacketPeerUDP.new()
			for p in range(7790, 7840):
				if _local.listen(p, "127.0.0.1") == OK:
					_local_port = p
					break
			if _local_port == 0:
				_fail("could not open a local port")
				return
			emit_signal("ready_local", _local_port)
		elif _local and _enet_port > 0:
			_local.set_dest_address("127.0.0.1", _enet_port)
			for d in _unpack(payload):
				_local.put_packet(d)


func _fail(reason: String) -> void:
	close()
	emit_signal("room_failed", reason)


func _publish_info() -> void:
	if mqtt and mqtt.is_up and code != "":
		var info = {"v": Net.VERSION, "n": Net.server_name, "p": Net.players.size(), "m": Net.MAX_PLAYERS, "s": Net.state == Net.PLAYING}
		mqtt.publish(NS + code + "/info", to_json(info).to_utf8(), true)


# ------------------------------------------------------------------ ferrying datagrams
func _process(delta: float) -> void:
	if mode == "":
		return
	if _check_t > 0.0:
		_check_t -= delta
		if _check_t <= 0.0 and not _got_info:
			_fail("no room with that code")
			return
	if mode == "host":
		for k in _socks.keys():
			var s = _socks[k]
			while s.sock.get_available_packet_count() > 0:
				s.out.append(s.sock.get_packet())
			if OS.get_ticks_msec() - s.seen > IDLE * 1000.0:
				s.sock.close()
				_socks.erase(k)
		_info_t -= delta
		if _info_t <= 0.0:
			_info_t = 5.0
			_publish_info()
	elif _local:
		while _local.get_available_packet_count() > 0:
			_out.append(_local.get_packet())
			_enet_port = _local.get_packet_port()
	_flush_t -= delta
	if _flush_t > 0.0 or mqtt == null or not mqtt.is_up:
		return
	_flush_t = FLUSH
	if mode == "host":
		for k in _socks:
			var s = _socks[k]
			if not s.out.empty():
				mqtt.publish(NS + code + "/down/" + k, _pack(s.out))
				s.out = []
	elif not _out.empty():
		mqtt.publish(NS + code + "/up/" + _cid, _pack(_out))
		_out = []


func _pack(list: Array) -> PoolByteArray:
	var sp = StreamPeerBuffer.new()
	sp.put_u8(1)
	for d in list:
		sp.put_u16(d.size())
		sp.put_data(d)
	return sp.data_array


func _unpack(b: PoolByteArray) -> Array:
	var out = []
	if b.size() < 1:
		return out
	var sp = StreamPeerBuffer.new()
	sp.data_array = b
	if sp.get_u8() != 1:
		return out
	while sp.get_position() + 2 <= b.size():
		var n = sp.get_u16()
		if sp.get_position() + n > b.size():
			break
		out.append(sp.get_data(n)[1])
	return out
