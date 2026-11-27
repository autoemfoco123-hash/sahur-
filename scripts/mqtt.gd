extends Node
## A minimal MQTT 3.1.1 client over WebSocket (ws:// or wss://), for the online rooms (room.gd).
## QoS 0 only: connect, subscribe, publish (optionally retained), keep-alive pings.
## Tries the brokers in order until one answers. (Godot 3)

signal connected(url)
signal failed(reason)
signal message(topic, payload)
signal closed()

const KEEPALIVE = 30

var ws: WebSocketClient
var urls = []
var url = ""
var is_up = false
var _try = -1
var _buf = PoolByteArray()
var _ping_t = 0.0
var _pid = 1
var _client_id = ""
var _timeout = 0.0


func open(url_list: Array) -> void:
	urls = url_list
	_try = -1
	randomize()
	_client_id = "sahur-%08x" % (randi() & 0x7fffffff)
	_next()


func close() -> void:
	if ws and is_up:
		_send(PoolByteArray([0xE0, 0x00]))
	if ws:
		ws.disconnect_from_host()
	is_up = false
	ws = null


func _next() -> void:
	_try += 1
	if ws:
		ws.disconnect_from_host()
		ws = null
	if _try >= urls.size():
		emit_signal("failed", "no relay answered")
		return
	url = urls[_try]
	ws = WebSocketClient.new()
	ws.connect("connection_established", self, "_on_open")
	ws.connect("connection_error", self, "_on_error")
	ws.connect("connection_closed", self, "_on_closed")
	ws.connect("data_received", self, "_on_data")
	_buf = PoolByteArray()
	_timeout = 8.0
	if ws.connect_to_url(url, PoolStringArray(["mqtt"])) != OK:
		call_deferred("_next")


func _process(delta: float) -> void:
	if ws == null:
		return
	ws.poll()
	if not is_up:
		_timeout -= delta
		if _timeout <= 0.0:
			_next()
		return
	_ping_t -= delta
	if _ping_t <= 0.0:
		_ping_t = KEEPALIVE * 0.5
		_send(PoolByteArray([0xC0, 0x00]))


func _on_open(_proto) -> void:
	ws.get_peer(1).set_write_mode(WebSocketPeer.WRITE_MODE_BINARY)
	# CONNECT: protocol "MQTT" level 4, clean session, keep-alive, client id
	var vh = PoolByteArray([0, 4, 77, 81, 84, 84, 4, 0x02, (KEEPALIVE >> 8) & 255, KEEPALIVE & 255])
	vh.append_array(_str(_client_id))
	_send(_packet(0x10, vh))


func _on_error() -> void:
	if not is_up:
		_next()
	else:
		_lost()


func _on_closed(_clean) -> void:
	if not is_up:
		_next()
	else:
		_lost()


func _lost() -> void:
	is_up = false
	ws = null
	emit_signal("closed")


func _on_data() -> void:
	while ws and ws.get_peer(1).get_available_packet_count() > 0:
		_buf.append_array(ws.get_peer(1).get_packet())
	_parse()


func _parse() -> void:
	while _buf.size() >= 2:
		# remaining length (variable byte integer)
		var mult = 1
		var rl = 0
		var i = 1
		var ok = false
		while i < _buf.size() and i <= 4:
			var b = _buf[i]
			rl += (b & 127) * mult
			mult *= 128
			i += 1
			if b & 128 == 0:
				ok = true
				break
		if not ok or _buf.size() < i + rl:
			return
		var kind = _buf[0] >> 4
		var body = _buf.subarray(i, i + rl - 1) if rl > 0 else PoolByteArray()
		var head = _buf[0]
		_buf = _buf.subarray(i + rl, _buf.size() - 1) if _buf.size() > i + rl else PoolByteArray()
		match kind:
			2:  # CONNACK
				if body.size() >= 2 and body[1] == 0:
					is_up = true
					_ping_t = KEEPALIVE * 0.5
					emit_signal("connected", url)
				else:
					_next()
			3:  # PUBLISH
				var tl = (body[0] << 8) | body[1]
				var topic = body.subarray(2, 1 + tl).get_string_from_utf8()
				var at = 2 + tl
				if (head >> 1) & 3 > 0:
					at += 2
				var payload = body.subarray(at, body.size() - 1) if body.size() > at else PoolByteArray()
				emit_signal("message", topic, payload)


func subscribe(topic: String) -> void:
	_pid = (_pid % 60000) + 1
	var b = PoolByteArray([(_pid >> 8) & 255, _pid & 255])
	b.append_array(_str(topic))
	b.append(0)
	_send(_packet(0x82, b))


func publish(topic: String, payload: PoolByteArray, retain := false) -> void:
	if not is_up:
		return
	var b = _str(topic)
	b.append_array(payload)
	_send(_packet(0x30 | (1 if retain else 0), b))


func _str(s: String) -> PoolByteArray:
	var u = s.to_utf8()
	var b = PoolByteArray([(u.size() >> 8) & 255, u.size() & 255])
	b.append_array(u)
	return b


func _packet(h: int, body: PoolByteArray) -> PoolByteArray:
	var out = PoolByteArray([h])
	var n = body.size()
	while true:
		var d = n % 128
		n = n / 128
		if n > 0:
			d |= 128
		out.append(d)
		if n == 0:
			break
	out.append_array(body)
	return out


func _send(b: PoolByteArray) -> void:
	if ws and ws.get_peer(1).is_connected_to_host():
		ws.get_peer(1).put_packet(b)
