extends Node
## Online rooms: play with anyone, on any network, by a 6-digit room code. No port forwarding,
## no VPN, no server of your own.
##
## The game's own multiplayer (ENet, the same as on a LAN) is carried between two little UDP
## proxies, one on each machine:
##   host:   its ENet server listens as usual; for every remote player the room opens a local UDP
##           socket to it, and ferries that player's datagrams to and from them
##   player: a local UDP port stands in for the host; its ENet client connects there, and the
##           room ferries the datagrams to and from the host
## Two ways across:
##   direct  straight from one machine to the other over UDP. Each side asks public STUN servers
##           what its address looks like from the internet, the two swap addresses (theirs on the
##           LAN too) through the relay, and both fire small probes at each other until the NATs
##           let them through ("hole punching"). Works for most home routers; nothing in between,
##           so the lag is the plain ping between the two machines.
##   relay   a public MQTT broker over a secure WebSocket (mqtt.gd), which crosses every router and
##           firewall that lets the web through. Always there: the way in, and the fallback
##           whenever the direct path is not (yet) working or goes quiet.
## The relay never ends a game: if the connection to it drops, the room reconnects to the same
## broker under the same code, and play goes on over the direct path meanwhile.
## The code: its first digit names the relay the room is on, the other five are random. The room
## announces itself (retained) under its code, so a code is checked (exists? same version?)
## before anyone connects.
## Relays: the public brokers below, in order; or your own (a file user://relay.txt with one
## wss:// url, or the command line --relay=wss://...). --nodirect turns the direct path off;
## --stun=host:port asks that STUN server instead of the public ones.

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
const STUN = [["stun.l.google.com", 19302], ["stun1.l.google.com", 19302], ["stun.cloudflare.com", 3478]]
const FLUSH = 0.025          # relay: datagrams are batched this long
const IDLE = 150.0           # host: a player silent this long is gone
const DIRECT_STALE = 2500    # ms without a packet on the direct path: back to the relay
const MAGIC = "s67"
const RETRY_MAX = 8.0

var mode = ""          # "" · "host" · "player"
var code = ""
var mqtt
var no_direct = false
var _host_port = 7777
var _cid = ""
var _token = ""
var _socks = {}        # host: player id -> {sock, out, seen, token, cands, direct, dseen, sent}
var _by_addr = {}      # host: "ip:port" on the direct path -> player id
var _local: PacketPeerUDP
var _local_port = 0
var _enet_port = -1
var _out = []
var _flush_t = 0.0
var _info_t = 0.0
var _check_t = -1.0
var _got_info = false
var _joined = false    # player: ENet is on its way (from then on a lost relay is not fatal)
var _url = ""          # the relay this room lives on
var _retry_t = -1.0
var _retry_wait = 1.0
# the direct path
var _wan: PacketPeerUDP
var _wan_port = 0
var _cands = []        # my addresses ("ip:port"): LAN, and as STUN sees me
var _stun_q = []       # [resolver id, port]
var _stun_addrs = []   # [ip, port]
var _stun_t = 0.0
var _stun_tries = 0
var _txid = PoolByteArray()
var _peer_cands = []   # player: the host's addresses
var _direct = ""       # player: the host, on the direct path
var _dseen = 0
var _dsent = 0
var _probe_t = 0.0
var _cand_t = 0.0
var _cand_dirty = false


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
	_by_addr = {}
	if _local:
		_local.close()
	_local = null
	if _wan:
		_wan.close()
	_wan = null
	_enet_port = -1
	_out = []
	mode = ""
	code = ""
	_url = ""
	_check_t = -1.0
	_retry_t = -1.0
	_got_info = false
	_joined = false
	_cands = []
	_stun_q = []
	_stun_addrs = []
	_peer_cands = []
	_direct = ""


## How this machine reaches the other side right now ("direct" / "relay"), for the hud.
func path() -> String:
	if mode == "player":
		return "direct" if _direct_alive() else "relay"
	if mode == "host":
		var d = 0
		for k in _socks:
			d += 1 if _s_direct(_socks[k]) else 0
		return "%d/%d direct" % [d, _socks.size()] if _socks.size() > 0 else ""
	return ""


# ------------------------------------------------------------------ host
func open_host(enet_port: int) -> void:
	close()
	mode = "host"
	_host_port = enet_port
	_wan_open()
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
	_token = "%08x" % (randi() & 0x7fffffff)
	var bl = brokers()
	var i = int(c.substr(0, 1)) - 1
	_new_mqtt()
	mqtt.open([bl[i]] if bl == BROKERS and i >= 0 and i < bl.size() else bl)


# ------------------------------------------------------------------ relay events
func _on_up(url: String) -> void:
	var again = _url != ""
	_url = url
	_retry_wait = 1.0
	if mode == "host":
		if code == "":
			var i = max(0, BROKERS.find(url))
			code = str(i + 1) + "%05d" % (randi() % 100000)
		mqtt.subscribe(NS + code + "/up/+")
		_publish_info()
		if not again:
			emit_signal("room_open", code)
		else:
			print("[sahur-net] back on the online relay · room %s" % code)
	elif mode == "player":
		mqtt.subscribe(NS + code + "/info")
		mqtt.subscribe(NS + code + "/down/" + _cid)
		if not _got_info:
			_check_t = 6.0
		elif _wan:
			_send_cands()


func _on_mqtt_failed(reason: String) -> void:
	if _url != "" and (mode == "host" or _joined):
		_retry_later()        # it was up before: keep trying, the game goes on
		return
	var m = mode
	close()
	emit_signal("room_failed", "could not reach the online relay (%s). check your internet." % reason if m != "" else reason)


## The relay dropped us (it happens: public brokers cut connections, wi-fi blinks). Not the end
## of anything: come back to the same relay, under the same code.
func _on_mqtt_closed() -> void:
	if mode == "":
		return
	if mode == "player" and not _joined:
		close()
		emit_signal("room_failed", "lost the online relay")
		return
	_retry_later()


func _retry_later() -> void:
	_retry_t = _retry_wait
	_retry_wait = min(_retry_wait * 2.0, RETRY_MAX)
	print("[sahur-net] online relay lost · reconnecting in %d s" % int(_retry_t))


func _on_msg(topic: String, payload: PoolByteArray) -> void:
	if mode == "host":
		var parts = topic.split("/")
		var key = parts[parts.size() - 1]
		if not topic.begins_with(NS + code + "/up/") or key == "":
			return
		var s = _sock_for(key)
		if s == null:
			return
		s.seen = OS.get_ticks_msec()
		if payload.size() > 0 and payload[0] == 2:
			_on_control(payload, key)
			return
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
			_wan_open()
			_send_cands()
			_joined = true
			emit_signal("ready_local", _local_port)
		elif payload.size() > 0 and payload[0] == 2:
			_on_control(payload, "")
		elif _local and _enet_port > 0:
			_local.set_dest_address("127.0.0.1", _enet_port)
			for d in _unpack(payload):
				_local.put_packet(d)


## Host: the local socket that stands for player `key` in front of the ENet server.
func _sock_for(key: String):
	var s = _socks.get(key)
	if s == null:
		var sock = PacketPeerUDP.new()
		if sock.listen(0, "127.0.0.1") != OK:
			return null
		sock.set_dest_address("127.0.0.1", _host_port)
		s = {"sock": sock, "out": [], "seen": OS.get_ticks_msec(), "token": "", "cands": [], "direct": "", "dseen": 0, "sent": 0}
		_socks[key] = s
	return s


func _fail(reason: String) -> void:
	close()
	emit_signal("room_failed", reason)


func _publish_info() -> void:
	if mqtt and mqtt.is_up and code != "":
		var info = {"v": Net.VERSION, "n": Net.server_name, "p": Net.players.size(), "m": Net.MAX_PLAYERS, "s": Net.state == Net.PLAYING}
		mqtt.publish(NS + code + "/info", to_json(info).to_utf8(), true)


# ------------------------------------------------------------------ the direct path
## A UDP socket open to the internet (any port in a range: Godot 3 cannot tell which one it got).
func _wan_open() -> void:
	if no_direct or "--nodirect" in OS.get_cmdline_args() or _wan:
		return
	randomize()
	var w = PacketPeerUDP.new()
	var base = 47000 + randi() % 2000
	for k in 40:
		if w.listen(base + k * 7, "*") == OK:
			_wan = w
			_wan_port = base + k * 7
			break
	if _wan == null:
		return
	for a in IP.get_local_addresses():
		if a.find(":") < 0 and a != "0.0.0.0" and _cands.size() < 8:
			_cands.append("%s:%d" % [a, _wan_port])
	var servers = STUN
	for a in OS.get_cmdline_args():
		if a.begins_with("--stun="):          # tests: one STUN server of your own (host:port)
			var hp = a.substr(7).split(":")
			servers = [[hp[0], int(hp[1]) if hp.size() > 1 else 3478]]
	for sv in servers:
		var id = IP.resolve_hostname_queue_item(sv[0], IP.TYPE_IPV4)
		if id != IP.RESOLVER_INVALID_ID:
			_stun_q.append([id, sv[1]])
	_txid = PoolByteArray()
	for i in 12:
		_txid.append(randi() % 256)
	_stun_t = 0.2
	_stun_tries = 0


## Tell the other side where I can be reached (player -> host, or host -> one player / all).
func _send_cands(to := "") -> void:
	if mqtt == null or not mqtt.is_up or _wan == null:
		return
	var b = PoolByteArray([2])
	b.append_array(to_json({"c": _cands, "t": _token}).to_utf8())
	if mode == "player":
		mqtt.publish(NS + code + "/up/" + _cid, b)
	elif to != "":
		mqtt.publish(NS + code + "/down/" + to, b)
	else:
		for k in _socks:
			mqtt.publish(NS + code + "/down/" + k, b)


func _on_control(payload: PoolByteArray, key: String) -> void:
	var r = JSON.parse(payload.subarray(1, payload.size() - 1).get_string_from_utf8())
	if r.error != OK or typeof(r.result) != TYPE_DICTIONARY:
		return
	var cands = []
	for c in r.result.get("c", []):
		if typeof(c) == TYPE_STRING and c.find(":") > 0 and cands.size() < 12:
			cands.append(c)
	if mode == "host":
		var s = _socks.get(key)
		if s == null:
			return
		var first = s.token == ""
		s.token = str(r.result.get("t", ""))
		s.cands = cands
		if _wan == null:
			_wan_open()
		if first or not _s_direct(s):
			_send_cands(key)
	else:
		_peer_cands = cands
	_probe_t = 0.0


func _probe(kind: int, cid: String, token: String) -> PoolByteArray:
	var b = PoolByteArray([kind])
	b.append_array((MAGIC + cid + token).to_ascii())
	return b


func _send_wan(addr: String, b: PoolByteArray) -> void:
	var i = addr.find_last(":")
	if i <= 0 or _wan == null:
		return
	_wan.set_dest_address(addr.substr(0, i), int(addr.substr(i + 1)))
	_wan.put_packet(b)


func _direct_alive() -> bool:
	return _direct != "" and OS.get_ticks_msec() - _dseen < DIRECT_STALE


func _s_direct(s: Dictionary) -> bool:
	return s.direct != "" and OS.get_ticks_msec() - s.dseen < DIRECT_STALE


func _wan_step(delta: float) -> void:
	if _wan == null:
		return
	var now = OS.get_ticks_msec()
	# what STUN says we look like from outside
	for q in _stun_q.duplicate():
		var st = IP.get_resolve_item_status(q[0])
		if st == IP.RESOLVER_STATUS_DONE:
			var a = IP.get_resolve_item_address(q[0])
			if a != "":
				_stun_addrs.append([a, q[1]])
			IP.erase_resolve_item(q[0])
			_stun_q.erase(q)
		elif st == IP.RESOLVER_STATUS_ERROR or st == IP.RESOLVER_STATUS_NONE:
			IP.erase_resolve_item(q[0])
			_stun_q.erase(q)
	_stun_t -= delta
	if _stun_t <= 0.0 and _stun_tries < 6 and not _stun_addrs.empty():
		_stun_t = 1.0
		_stun_tries += 1
		var req = PoolByteArray([0, 1, 0, 0, 0x21, 0x12, 0xA4, 0x42])
		req.append_array(_txid)
		for sa in _stun_addrs:
			_wan.set_dest_address(sa[0], sa[1])
			_wan.put_packet(req)
	# keep knocking until the other side answers; once through, a heartbeat keeps the NATs open
	_probe_t -= delta
	if _probe_t <= 0.0:
		_probe_t = 0.25
		if mode == "player" and _token != "":
			if not _direct_alive():
				for c in _peer_cands:
					_send_wan(c, _probe(0, _cid, _token))
			elif now - _dsent > 800:
				_send_wan(_direct, _probe(1, _cid, _token))
				_dsent = now
		elif mode == "host":
			for k in _socks:
				var s = _socks[k]
				if s.token == "":
					continue
				if not _s_direct(s):
					for c in s.cands:
						_send_wan(c, _probe(0, k, s.token))
				elif now - s.sent > 800:
					_send_wan(s.direct, _probe(1, k, s.token))
					s.sent = now
	if _cand_dirty:
		_cand_t -= delta
		if _cand_t <= 0.0:
			_cand_dirty = false
			_cand_t = 1.0
			_send_cands()


## What came in on the open socket: STUN answers, probes, the other side's datagrams.
func _wan_read() -> void:
	var now = OS.get_ticks_msec()
	while _wan.get_available_packet_count() > 0:
		var b = _wan.get_packet()
		var addr = "%s:%d" % [_wan.get_packet_ip(), _wan.get_packet_port()]
		if b.size() >= 20 and b[0] == 1 and b[1] == 1 and b[4] == 0x21 and b[5] == 0x12:
			_on_stun(b)
			continue
		if b.size() < 1:
			continue
		var kind = b[0]
		if kind == 2:
			_on_wan_data(addr, b)
			continue
		if (kind != 0 and kind != 1) or b.size() != 20 or b.subarray(1, 3).get_string_from_ascii() != MAGIC:
			continue
		var cid = b.subarray(4, 11).get_string_from_ascii()
		var tok = b.subarray(12, 19).get_string_from_ascii()
		if mode == "player":
			if cid != _cid or tok != _token:
				continue
			if _direct != addr and _direct_alive():
				continue                   # already through on another address: keep that one
			if _direct != addr:
				_direct = addr
				print("[sahur-net] direct path to the host · %s" % addr)
			_dseen = now
			if kind == 0:
				_send_wan(addr, _probe(1, _cid, _token))
				_dsent = now
		else:
			var s = _socks.get(cid)
			if s == null or s.token == "" or tok != s.token:
				continue
			if s.direct != addr and _s_direct(s):
				continue
			if s.direct != addr:
				_by_addr.erase(s.direct)
				s.direct = addr
				_by_addr[addr] = cid
				print("[sahur-net] direct path to %s · %s" % [cid, addr])
			s.dseen = now
			s.seen = now
			if kind == 0:
				_send_wan(addr, _probe(1, cid, s.token))
				s.sent = now


func _on_wan_data(addr: String, b: PoolByteArray) -> void:
	var d = b.subarray(1, b.size() - 1) if b.size() > 1 else PoolByteArray()
	var now = OS.get_ticks_msec()
	if mode == "player":
		if addr != _direct or _local == null or _enet_port <= 0:
			return
		_dseen = now
		_local.set_dest_address("127.0.0.1", _enet_port)
		_local.put_packet(d)
	elif mode == "host":
		var key = _by_addr.get(addr)
		var s = _socks.get(key) if key else null
		if s == null:
			return
		s.dseen = now
		s.seen = now
		s.sock.put_packet(d)


## A STUN answer: our address as the internet sees it, one more way in.
func _on_stun(b: PoolByteArray) -> void:
	var i = 20
	while i + 4 <= b.size():
		var t = (b[i] << 8) | b[i + 1]
		var ln = (b[i + 2] << 8) | b[i + 3]
		var v = i + 4
		if v + ln > b.size():
			break
		if (t == 0x0020 or t == 0x0001) and ln >= 8 and b[v + 1] == 1:
			var port = (b[v + 2] << 8) | b[v + 3]
			var ip = [b[v + 4], b[v + 5], b[v + 6], b[v + 7]]
			if t == 0x0020:
				port = port ^ 0x2112
				ip = [ip[0] ^ 0x21, ip[1] ^ 0x12, ip[2] ^ 0xA4, ip[3] ^ 0x42]
			var c = "%d.%d.%d.%d:%d" % [ip[0], ip[1], ip[2], ip[3], port]
			_stun_tries = 99                    # one answer is enough
			if not c in _cands:
				_cands.push_front(c)
				_cand_dirty = true
				print("[sahur-net] seen from outside as %s" % c)
			return
		i = v + ((ln + 3) / 4) * 4


# ------------------------------------------------------------------ ferrying datagrams
## Datagrams cross the proxies twice a frame: in the physics step (it runs before the frame's
## network poll, so what came in is delivered this frame) and at the very end of the frame,
## right after Net has flushed what the game sent (process_priority: Net 100, the room 101).
func _ready() -> void:
	process_priority = 101


func _physics_process(_delta: float) -> void:
	if mode != "":
		_pump()


func _process(delta: float) -> void:
	if mode == "":
		return
	if _retry_t > 0.0:
		_retry_t -= delta
		if _retry_t <= 0.0 and mqtt:
			mqtt.open([_url] if _url != "" else brokers())
	if _check_t > 0.0:
		_check_t -= delta
		if _check_t <= 0.0 and not _got_info:
			_fail("no room with that code")
			return
	_wan_step(delta)
	_pump()
	if mode == "host":
		_info_t -= delta
		if _info_t <= 0.0:
			_info_t = 5.0
			_publish_info()
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


## Everything waiting on the sockets goes where it belongs: ENet -> the other side (direct, or
## queued for the relay), the other side (direct) -> ENet.
func _pump() -> void:
	if _wan:
		_wan_read()
	if mode == "host":
		for k in _socks.keys():
			var s = _socks[k]
			var direct = _s_direct(s)
			while s.sock.get_available_packet_count() > 0:
				var d = s.sock.get_packet()
				if direct:
					var b = PoolByteArray([2])
					b.append_array(d)
					_send_wan(s.direct, b)
					s.sent = OS.get_ticks_msec()
				else:
					s.out.append(d)
			if OS.get_ticks_msec() - s.seen > IDLE * 1000.0:
				s.sock.close()
				_by_addr.erase(s.direct)
				_socks.erase(k)
	elif _local:
		var direct = _direct_alive()
		while _local.get_available_packet_count() > 0:
			var d = _local.get_packet()
			_enet_port = _local.get_packet_port()
			if direct:
				var b = PoolByteArray([2])
				b.append_array(d)
				_send_wan(_direct, b)
				_dsent = OS.get_ticks_msec()
			else:
				_out.append(d)
		if _out.size() > 400:
			_out = _out.slice(_out.size() - 200, _out.size() - 1)   # the relay is away: ENet resends


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
