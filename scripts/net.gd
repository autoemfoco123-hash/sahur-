extends Node
## sahur multiplayer (Godot 3, ENet over UDP).
## - host from the game (listen server) or run a headless dedicated server (--server)
## - LAN servers announce themselves on UDP 7778; anyone can also join by ip
## - lobby: names, ready flags, chat; everyone ready (or the host says so) -> 5 s countdown
## - every machine builds the same office from one shared seed; the server runs tung,
##   the calls, catches, escapes and the end of the round; each player sends its own movement
## Every RPC lives on this autoload (/root/Net), so node paths always match on all peers.

const VERSION = "sahur-mp-1"
const PORT = 7777
const DISCOVERY_PORT = 7778
const MAX_PLAYERS = 8
const COUNTDOWN = 5
const SEND_HZ = 20.0
const ENEMY_HZ = 15.0
const COLORS = [Color(1.0, 0.78, 0.25), Color(0.35, 0.8, 1.0), Color(1.0, 0.45, 0.4), Color(0.55, 1.0, 0.5),
	Color(0.85, 0.6, 1.0), Color(1.0, 0.65, 0.85), Color(0.92, 0.92, 0.92), Color(0.4, 1.0, 0.85)]

signal players_changed
signal message(text)              # lobby / connection status line
signal chat(text)                 # "name: text"
signal countdown(n)               # seconds left; 0 = go; -1 = cancelled
signal servers_changed
signal failed(reason)

enum { OFFLINE, CONNECTING, LOBBY, PLAYING }

var state = OFFLINE
var dedicated = false
var server_name = "sahur"
var players = {}                  # id -> {name, color, ready, alive, escaped, in_game}
var round_seed = 0
var world = null                  # the running World (set by world.gd)
var found = {}                    # LAN servers: ip -> {name, players, max, playing, t}
var chat_log = []
var last_error = ""
var counting = -1                 # countdown seconds left (-1 = not counting)

var _peer: NetworkedMultiplayerENet
var _my_name = ""
var _count_t = 0.0
var _beacon: PacketPeerUDP
var _beacon_t = 0.0
var _listen: PacketPeerUDP
var _send_t = 0.0
var _enemy_t = 0.0
var _end_t = -1.0


func _ready() -> void:
	pause_mode = Node.PAUSE_MODE_PROCESS
	get_tree().connect("network_peer_connected", self, "_on_peer_connected")
	get_tree().connect("network_peer_disconnected", self, "_on_peer_disconnected")
	get_tree().connect("connected_to_server", self, "_on_connected")
	get_tree().connect("connection_failed", self, "_on_connection_failed")
	get_tree().connect("server_disconnected", self, "_on_server_disconnected")


# ------------------------------------------------------------------ helpers
func active() -> bool:
	return state != OFFLINE and _peer != null and get_tree().network_peer != null


func is_server() -> bool:
	return active() and get_tree().is_network_server()


func my_id() -> int:
	return get_tree().get_network_unique_id() if get_tree().network_peer else 1


func pname(id: int) -> String:
	return players[id].name if players.has(id) else "operative"


func pcolor(id: int) -> Color:
	return players[id].color if players.has(id) else Color(1, 1, 1)


## Players taking part in the current round, in a stable order (spawn slots).
func round_ids() -> Array:
	var ids = []
	for id in players:
		if players[id].in_game:
			ids.append(id)
	ids.sort()
	return ids


func local_ips() -> Array:
	var out = []
	for a in IP.get_local_addresses():
		if a.find(":") < 0 and not a.begins_with("127.") and not a.begins_with("169.254"):
			out.append(a)
	return out


func _new_player(n: String) -> Dictionary:
	var used = []
	for id in players:
		used.append(players[id].cidx)
	var ci = 0
	while ci in used and ci < COLORS.size() - 1:
		ci += 1
	return {"name": _clean(n), "cidx": ci, "color": COLORS[ci], "ready": false, "alive": true, "escaped": false, "in_game": false}


func _clean(n: String) -> String:
	n = n.strip_edges().to_lower()
	if n.length() > 16:
		n = n.substr(0, 16)
	if n == "":
		n = "operative %02d" % (randi() % 90 + 10)
	return n


# ------------------------------------------------------------------ host / join / leave
func host(name_: String, as_dedicated := false) -> bool:
	leave(true)
	_peer = NetworkedMultiplayerENet.new()
	if _peer.create_server(PORT, MAX_PLAYERS) != OK:
		last_error = "could not open udp port %d (is another server running?)" % PORT
		emit_signal("failed", last_error)
		_peer = null
		return false
	get_tree().network_peer = _peer
	dedicated = as_dedicated
	server_name = _clean(name_)
	players = {}
	chat_log = []
	if not dedicated:
		players[1] = _new_player(name_)
	state = LOBBY
	_start_beacon()
	_log("server up · udp %d · %s" % [PORT, ", ".join(PoolStringArray(local_ips()))])
	emit_signal("players_changed")
	return true


func join(ip: String, name_: String) -> bool:
	leave(true)
	ip = ip.strip_edges()
	if ip == "":
		emit_signal("failed", "type the host's ip address")
		return false
	_peer = NetworkedMultiplayerENet.new()
	if _peer.create_client(ip, PORT) != OK:
		emit_signal("failed", "could not start a connection")
		_peer = null
		return false
	get_tree().network_peer = _peer
	_my_name = name_
	dedicated = false
	players = {}
	chat_log = []
	state = CONNECTING
	emit_signal("message", "connecting to %s…" % ip)
	return true


func leave(silent := false) -> void:
	_stop_beacon()
	# Never free the peer here: this often runs inside one of its own signals.
	var np = get_tree().network_peer
	if np:
		call_deferred("_drop_peer", np)
	_peer = null
	state = OFFLINE
	players = {}
	counting = -1
	_end_t = -1.0
	world = null
	if not silent:
		Game.main_menu()


func _drop_peer(np) -> void:
	if np is NetworkedMultiplayerENet:
		np.close_connection()
	if get_tree().network_peer == np:
		get_tree().network_peer = null


func _on_connected() -> void:
	rpc_id(1, "_hello", _my_name, VERSION)


func _on_connection_failed() -> void:
	leave(true)
	emit_signal("failed", "could not reach the server (wrong ip, or udp %d blocked?)" % PORT)


func _on_server_disconnected() -> void:
	var was_playing = state == PLAYING
	leave(true)
	last_error = "the server closed"
	if was_playing:
		Game.main_menu()
	emit_signal("failed", last_error)


func _on_peer_connected(_id: int) -> void:
	pass


func _on_peer_disconnected(id: int) -> void:
	if not is_server() or not players.has(id):
		return
	var n = players[id].name
	players.erase(id)
	_say("%s left" % n)
	_sync()
	if state == PLAYING:
		rpc("_ev", "left", [id])
		_ev("left", [id])
		_check_round_end()
	_check_start()


# ------------------------------------------------------------------ lobby (server side)
remote func _hello(name_: String, version: String) -> void:
	var id = get_tree().get_rpc_sender_id()
	if version != VERSION:
		rpc_id(id, "_kicked", "this server runs another version of sahur")
		return
	if players.size() >= MAX_PLAYERS:
		rpc_id(id, "_kicked", "server full")
		return
	players[id] = _new_player(name_)
	rpc_id(id, "_welcome", server_name, state == PLAYING, chat_log)
	_say("%s joined" % players[id].name)
	_sync()
	_check_start()


remote func _ready_req(r: bool) -> void:
	_set_ready(get_tree().get_rpc_sender_id(), r)


remote func _chat_req(t: String) -> void:
	var id = get_tree().get_rpc_sender_id()
	_chat_all("%s: %s" % [pname(id), t.substr(0, 120).to_lower()])


func _set_ready(id: int, r: bool) -> void:
	if not players.has(id) or state != LOBBY:
		return
	players[id].ready = r
	_sync()
	_check_start()


func _sync() -> void:
	if is_server():
		rpc("_players", players, state == PLAYING)
	emit_signal("players_changed")


func _say(t: String) -> void:
	_chat_all("· " + t)
	_log(t)


func _chat_all(t: String) -> void:
	chat_log.append(t)
	if chat_log.size() > 40:
		chat_log.pop_front()
	rpc("_chat", t)
	emit_signal("chat", t)


## Everyone ready -> countdown. Someone un-readies or joins -> cancel.
func _check_start() -> void:
	if not is_server() or state != LOBBY:
		return
	var all_ready = players.size() > 0
	for id in players:
		if not players[id].ready:
			all_ready = false
	if all_ready and counting < 0:
		_begin_countdown()
	elif not all_ready and counting >= 0:
		counting = -1
		rpc("_countdown", -1)
		_countdown(-1)


## Host button: start now, no matter who is ready.
func force_start() -> void:
	if is_server() and state == LOBBY and players.size() > 0 and counting < 0:
		_begin_countdown()


func _begin_countdown() -> void:
	counting = COUNTDOWN
	_count_t = 1.0
	rpc("_countdown", counting)
	_countdown(counting)


func _start_round() -> void:
	randomize()
	round_seed = randi() % 2000000000
	for id in players:
		players[id].alive = true
		players[id].escaped = false
		players[id].in_game = true
		players[id].ready = false
	state = PLAYING
	_end_t = -1.0
	_log("round start · seed %d · %d operatives" % [round_seed, players.size()])
	rpc("_round_start", round_seed, players)
	_round_start(round_seed, players)


# ------------------------------------------------------------------ lobby (client side)
remote func _kicked(reason: String) -> void:
	leave(true)
	emit_signal("failed", reason)


remote func _welcome(sname: String, playing: bool, log_: Array) -> void:
	server_name = sname
	state = LOBBY
	chat_log = log_
	emit_signal("message", "round in progress · you'll join the next one" if playing else "")
	emit_signal("players_changed")


remote func _players(p: Dictionary, _playing: bool) -> void:
	players = p
	emit_signal("players_changed")


remote func _chat(t: String) -> void:
	chat_log.append(t)
	if chat_log.size() > 40:
		chat_log.pop_front()
	emit_signal("chat", t)


remote func _countdown(n: int) -> void:
	counting = n
	emit_signal("countdown", n)
	if n > 0 and not dedicated:
		Audio.play("ui_click", -4.0, 1.0 + (COUNTDOWN - n) * 0.06)


remote func _round_start(seed_: int, p: Dictionary) -> void:
	players = p
	round_seed = seed_
	counting = -1
	state = PLAYING
	emit_signal("countdown", 0)
	var me = my_id()
	if dedicated or (players.has(me) and players[me].in_game):
		Game.forced_seed = seed_
		Game.brain_cells = 100.0
		Game.current_level = "0"
		get_tree().paused = false
		get_tree().change_scene("res://scenes/world.tscn")


func set_ready(r: bool) -> void:
	if is_server():
		_set_ready(my_id(), r)
	elif active():
		rpc_id(1, "_ready_req", r)


func say(t: String) -> void:
	t = t.strip_edges()
	if t == "" or not active():
		return
	if is_server():
		_chat_all("%s: %s" % [pname(my_id()) if not dedicated else "server", t.to_lower()])
	else:
		rpc_id(1, "_chat_req", t)


# ------------------------------------------------------------------ round (in game)
## Local player -> everyone: position, yaw, pitch, flags (1 crouch, 2 moving).
func send_state(pos: Vector3, yaw: float, pitch: float, flags: int) -> void:
	if active():
		rpc_unreliable("_ps", pos, yaw, pitch, flags)


remote func _ps(pos: Vector3, yaw: float, pitch: float, flags: int) -> void:
	if world:
		world.net_player_state(get_tree().get_rpc_sender_id(), pos, yaw, pitch, flags)


remote func _es(idx: int, pos: Vector3, yaw: float, st: int) -> void:
	if world:
		world.net_enemy_state(idx, pos, yaw, st)


## Server -> everyone: a game event. Also runs locally on the server.
func event(type: String, args := []) -> void:
	if is_server():
		rpc("_ev", type, args)
		_ev(type, args)


remote func _ev(type: String, args: Array) -> void:
	match type:
		"died":
			if players.has(args[0]):
				players[args[0]].alive = false
		"escaped":
			if players.has(args[0]):
				players[args[0]].escaped = true
		"left":
			pass
	if world:
		world.net_event(type, args)
	if is_server() and (type == "died" or type == "escaped"):
		_check_round_end()


## Client -> server requests.
func request(type: String, args := []) -> void:
	if not active():
		return
	if is_server():
		_handle(my_id(), type, args)
	else:
		rpc_id(1, "_req", type, args)


remote func _req(type: String, args: Array) -> void:
	_handle(get_tree().get_rpc_sender_id(), type, args)


func _handle(id: int, type: String, args: Array) -> void:
	if not players.has(id) or state != PLAYING:
		return
	match type:
		"shout":
			event("shout", [id])
			if world and world.level and world.level.has_method("on_shout"):
				world.level.on_shout(id)
		"died":
			if players[id].alive and not players[id].escaped:
				event("died", [id, args[0] if args.size() > 0 else ""])
		"escaped":
			if players[id].alive and not players[id].escaped:
				event("escaped", [id])


## Server: a brainrot reached a player.
func catch(id: int, msg: String) -> void:
	if is_server() and players.has(id) and players[id].alive and not players[id].escaped:
		event("died", [id, msg])


func _check_round_end() -> void:
	if not is_server() or state != PLAYING:
		return
	for id in players:
		var p = players[id]
		if p.in_game and p.alive and not p.escaped:
			return
	if _end_t < 0.0:
		_end_t = 5.0


func _end_round() -> void:
	var res = []
	for id in round_ids():
		var p = players[id]
		res.append([p.name, "made it out" if p.escaped else "became rot", p.cidx])
	_log("round over")
	for id in players:
		players[id].in_game = false
	rpc("_round_over", res)
	_round_over(res)


remote func _round_over(res: Array) -> void:
	if world:
		world.net_round_over(res)
	else:
		back_to_lobby()


func back_to_lobby() -> void:
	if not active():
		Game.main_menu()
		return
	state = LOBBY
	world = null
	for id in players:
		players[id].in_game = false
	get_tree().paused = false
	if dedicated:
		get_tree().change_scene("res://scenes/server.tscn")
	else:
		Game.main_menu()
	if is_server():
		_sync()


# ------------------------------------------------------------------ ticking
var _auto_t = 2.0


func _physics_process(delta: float) -> void:
	if not active():
		return
	if dedicated and state == LOBBY and "--autostart" in OS.get_cmdline_args():
		# debug: a pretend operative and an immediate round, no client needed
		_auto_t -= delta
		if _auto_t <= 0.0 and not players.has(99):
			players[99] = _new_player("bot")
			_start_round()
	if is_server():
		if counting > 0:
			_count_t -= delta
			if _count_t <= 0.0:
				_count_t = 1.0
				counting -= 1
				if counting <= 0:
					counting = -1
					_start_round()
				else:
					rpc("_countdown", counting)
					_countdown(counting)
		if _end_t > 0.0:
			_end_t -= delta
			if _end_t <= 0.0:
				_end_t = -1.0
				_end_round()
		if state == PLAYING and world:
			_enemy_t -= delta
			if _enemy_t <= 0.0:
				_enemy_t = 1.0 / ENEMY_HZ
				var i = 0
				for e in world.net_enemies():
					rpc_unreliable("_es", i, e.global_transform.origin, e.rotation.y, e.net_state())
					i += 1
		_beacon_t -= delta
		if _beacon and _beacon_t <= 0.0:
			_beacon_t = 1.0
			var info = {"g": "sahur", "v": VERSION, "n": server_name, "p": players.size(), "m": MAX_PLAYERS, "s": state == PLAYING, "port": PORT}
			_beacon.put_packet(to_json(info).to_utf8())
	if state == PLAYING and world and world.player:
		_send_t -= delta
		if _send_t <= 0.0:
			_send_t = 1.0 / SEND_HZ
			world.send_local_state()


func _process(_d: float) -> void:
	if _listen:
		var changed = false
		while _listen.get_available_packet_count() > 0:
			var pkt = _listen.get_packet()
			var ip = _listen.get_packet_ip()
			var r = JSON.parse(pkt.get_string_from_utf8())
			if r.error == OK and typeof(r.result) == TYPE_DICTIONARY and r.result.get("g") == "sahur":
				var d = r.result
				found[ip] = {"name": str(d.get("n", "sahur")), "players": int(d.get("p", 0)), "max": int(d.get("m", MAX_PLAYERS)),
					"playing": bool(d.get("s", false)), "same": d.get("v") == VERSION, "t": OS.get_ticks_msec()}
				changed = true
		for ip in found.keys():
			if OS.get_ticks_msec() - found[ip].t > 4000:
				found.erase(ip)
				changed = true
		if changed:
			emit_signal("servers_changed")


# ------------------------------------------------------------------ LAN discovery
func _start_beacon() -> void:
	_beacon = PacketPeerUDP.new()
	_beacon.set_broadcast_enabled(true)
	_beacon.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	_beacon_t = 0.0


func _stop_beacon() -> void:
	if _beacon:
		_beacon.close()
	_beacon = null


func start_discovery() -> void:
	stop_discovery()
	_listen = PacketPeerUDP.new()
	if _listen.listen(DISCOVERY_PORT) != OK:
		_listen = null
	found = {}


func stop_discovery() -> void:
	if _listen:
		_listen.close()
	_listen = null


func _log(t: String) -> void:
	print("[sahur-net] ", t)
	emit_signal("message", t if dedicated else "")
