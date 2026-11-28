extends Node
## sahur multiplayer (Godot 3, ENet over UDP).
## - host from the game (listen server) or run a headless dedicated server (--server)
## - LAN servers announce themselves on UDP 7778; anyone can also join by ip
## - lobby: names, ready flags, chat; everyone ready (or the host says so) -> 5 s countdown
## - every machine builds the same office from one shared seed; the server runs tung,
##   the calls, catches, escapes and the end of the round; each player sends its own movement
## Every RPC lives on this autoload (/root/Net), so node paths always match on all peers.

const VERSION = "sahur-mp-5"
const PORT = 7777
const DISCOVERY_PORT = 7778
const MAX_PLAYERS = 8
const COUNTDOWN = 5
const SEND_HZ = 30.0
const ENEMY_HZ = 20.0
# a peer is only given up on after this long without an answer (a slow load, a phone that
# paused, a relay that blinked must not throw anyone out); a clean quit is still seen at once
const PEER_TIMEOUT = [64, 20000, 60000]
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
var players = {}                  # id -> {name, color, ready, alive, escaped, in_game, sector}
var round_seed = 0
var seed_override = -1             # recordings / tests: build this map instead of a random one
var level_id = "0"                # the sector a run starts in (always 0; --level= for testing)
var wave = 0                      # the deepest sector anyone has reached this run
var world = null                  # the running World (set by world.gd)
var found = {}                    # LAN servers: ip -> {name, players, max, playing, t}
var chat_log = []
var last_error = ""
var counting = -1                 # countdown seconds left (-1 = not counting)
var room_code = ""                # the online room's code (room.gd): anyone, any network
var room                          # room.gd

var _peer: NetworkedMultiplayerENet
var _my_name = ""
var _count_t = 0.0
var _beacon: PacketPeerUDP
var _beacon_t = 0.0
var _listen: PacketPeerUDP
var _send_t = 0.0
var _enemy_t = 0.0
var _end_t = -1.0
var ping_ms = -1                  # client: round trip to the host
var _ping_t = 0.0


func _ready() -> void:
	pause_mode = Node.PAUSE_MODE_PROCESS
	process_priority = 100        # after every other script: flush what they sent this frame
	room = load("res://scripts/room.gd").new()
	room.name = "Room"
	add_child(room)
	room.connect("room_open", self, "_on_room_open")
	room.connect("ready_local", self, "_on_room_ready")
	room.connect("room_failed", self, "_on_room_failed")
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
	return {"name": _clean(n), "cidx": ci, "color": COLORS[ci], "ready": false, "alive": true, "escaped": false, "in_game": false, "photo": 0, "photo_of": "", "sector": 0, "points": 0, "photo_best": {}}


func _clean(n: String) -> String:
	n = n.strip_edges().to_lower()
	if n.length() > 16:
		n = n.substr(0, 16)
	if n == "":
		n = "operative %02d" % (randi() % 90 + 10)
	return n


# ------------------------------------------------------------------ host / join / leave
## Open a lobby: on the LAN (udp 7777) and, online, as a room anyone can join by its code.
func host(name_: String, as_dedicated := false, online := true) -> bool:
	leave(true)
	_peer = NetworkedMultiplayerENet.new()
	_peer.compression_mode = NetworkedMultiplayerENet.COMPRESS_RANGE_CODER
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
	if online:
		room.open_host(PORT)
		emit_signal("message", "opening the online room…")
	emit_signal("players_changed")
	return true


func _on_room_open(c: String) -> void:
	room_code = c
	_log("online room open · code %s · relay %s" % [c, room.mqtt.url if room.mqtt else ""])
	emit_signal("players_changed")


## Join an online room by its code (from any network).
func join_room(c: String, name_: String) -> void:
	leave(true)
	_my_name = name_
	state = CONNECTING
	emit_signal("message", "looking for room %s…" % c.strip_edges())
	room.open_player(c)


func _on_room_ready(port: int) -> void:
	room_code = room.code
	emit_signal("message", "room %s found · connecting…" % room.code)
	join("127.0.0.1", _my_name, port, true)


func _on_room_failed(reason: String) -> void:
	var was = state
	if room.mode == "" and was != OFFLINE:
		if is_server():
			# the lobby still works on the LAN; only the room is gone
			room_code = ""
			emit_signal("message", reason)
			emit_signal("players_changed")
			return
		leave(true)
		last_error = reason
		if was == PLAYING:
			Game.main_menu()
	emit_signal("failed", reason)


func join(ip: String, name_: String, port := PORT, through_room := false) -> bool:
	leave(true, through_room)
	ip = ip.strip_edges()
	if ip == "":
		emit_signal("failed", "type the host's ip address")
		return false
	_peer = NetworkedMultiplayerENet.new()
	_peer.compression_mode = NetworkedMultiplayerENet.COMPRESS_RANGE_CODER
	if _peer.create_client(ip, port) != OK:
		emit_signal("failed", "could not start a connection")
		_peer = null
		return false
	get_tree().network_peer = _peer
	_my_name = name_
	dedicated = false
	players = {}
	chat_log = []
	state = CONNECTING
	if not through_room:
		emit_signal("message", "connecting to %s…" % ip)
	return true


func leave(silent := false, keep_room := false) -> void:
	_stop_beacon()
	if not keep_room:
		room.close()
		room_code = ""
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
	_patient(1)
	ping_ms = -1
	rpc_id(1, "_hello", _my_name, VERSION)


## Give this peer a long time before calling it gone (see PEER_TIMEOUT).
func _patient(id: int) -> void:
	if _peer:
		_peer.set_peer_timeout(id, PEER_TIMEOUT[0], PEER_TIMEOUT[1], PEER_TIMEOUT[2])


func _on_connection_failed() -> void:
	var via_room = room.mode == "player"
	leave(true)
	emit_signal("failed", "could not connect through the online room (try again)" if via_room else "could not reach the server (wrong ip, or udp %d blocked?)" % PORT)


func _on_server_disconnected() -> void:
	var was_playing = state == PLAYING
	leave(true)
	last_error = "the server closed"
	if was_playing:
		Game.main_menu()
	emit_signal("failed", last_error)


func _on_peer_connected(id: int) -> void:
	if is_server():
		_patient(id)


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
		rpc("_players", players, state == PLAYING, level_id)
	emit_signal("players_changed")


func level_name(l := "") -> String:
	l = level_id if l == "" else l
	return "%s · %s" % [Game.INFO.get(l, {}).get("title", "sector " + l), Game.INFO.get(l, {}).get("name", "?")]


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
	round_seed = seed_override if seed_override >= 0 else randi() % 2000000000
	wave = int(max(0, Game.LEVELS.find(level_id)))
	for id in players:
		players[id].sector = wave
		players[id].alive = true
		players[id].escaped = false
		players[id].in_game = true
		players[id].ready = false
		players[id].photo = 0
		players[id].photo_of = ""
		players[id].points = 0
		players[id].photo_best = {}
	state = PLAYING
	_end_t = -1.0
	_log("round start · %s · seed %d · %d operatives" % [level_name(), round_seed, players.size()])
	rpc("_round_start", round_seed, players, level_id)
	_round_start(round_seed, players, level_id)


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


remote func _players(p: Dictionary, _playing: bool, lvl := "0") -> void:
	players = p
	level_id = lvl
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


remote func _round_start(seed_: int, p: Dictionary, lvl := "0") -> void:
	players = p
	round_seed = seed_
	level_id = lvl
	counting = -1
	state = PLAYING
	emit_signal("countdown", 0)
	var me = my_id()
	if dedicated or (players.has(me) and players[me].in_game):
		Game.forced_seed = seed_
		Game.brain_cells = 100.0
		Game.current_level = lvl if Game.INFO.has(lvl) else "0"
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
		rpc_unreliable("_ps", pos, yaw, pitch, flags, OS.get_ticks_msec() & 0xffff)


remote func _ps(pos: Vector3, yaw: float, pitch: float, flags: int, t: int) -> void:
	if world:
		world.net_player_state(get_tree().get_rpc_sender_id(), pos, yaw, pitch, flags, t)


remote func _es(idx: int, pos: Vector3, yaw: float, st: int, t: int) -> void:
	if world:
		world.net_enemy_state(idx, pos, yaw, st, t)


## Round trip to the host, measured once a second (shown in the hud, logged by the tests).
remote func _ping_q(t: int) -> void:
	rpc_unreliable_id(get_tree().get_rpc_sender_id(), "_ping_a", t)


remote func _ping_a(t: int) -> void:
	var r = OS.get_ticks_msec() - t
	if r >= 0 and r < 10000:
		ping_ms = r if ping_ms < 0 else int(round(lerp(ping_ms, r, 0.35)))


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
		"advanced":
			if players.has(args[0]):
				players[args[0]].sector = args[1]
		"revived":
			if players.has(args[0]):
				players[args[0]].alive = true
				players[args[0]].sector = args[1]
		"points":
			if players.has(args[0]):
				players[args[0]].points = args[1]
		"left":
			pass
	if world:
		world.net_event(type, args)
	if is_server() and (type == "died" or type == "escaped"):
		_check_round_end()


## Server: operative id moves on into sector `to` (through its door, or the void drops them in).
func advance_to(id: int, to: int) -> void:
	if not players.has(id) or to >= Game.LEVELS.size():
		return
	if to > wave:
		# a new wave: the sector wakes up, and hush sends the dead back in
		wave = to
		event("wave", [to])
		for pid in round_ids():
			if not players[pid].alive and not players[pid].escaped:
				_log("%s revived in sector %d" % [players[pid].name, to])
				event("revived", [pid, to])
	_log("%s → sector %d (wave %d)" % [players[id].name, to, wave])
	event("advanced", [id, to])


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
	var p = players[id]
	# every request goes to the sector that operative is in
	var lv = world.level_of(id) if world else null
	var last = Game.LEVELS.size() - 1
	match type:
		"shout":
			event("shout", [id])
			if lv and lv.has_method("on_shout"):
				lv.on_shout(id)
		"died":
			if p.alive and not p.escaped:
				event("died", [id, args[0] if args.size() > 0 else ""])
		"photo":
			if args.size() > 1 and int(args[1]) > int(p.get("photo", 0)):
				p.photo = int(args[1])
				p.photo_of = str(args[0])
			if world and args.size() > 1:
				world.photo_scored(id, str(args[0]), int(args[1]), int(args[2]) if args.size() > 2 else -1)
		"cheat_missions":
			# test servers only (started with --cheat-missions): finish this sector's missions
			if "--cheat-missions" in OS.get_cmdline_args() and lv:
				for m in lv.missions:
					lv.mission_set(m.id, m.goal, id)
		"door":
			# open the sliding door of the sector you are in (if that sector lets you)
			var s = int(args[0]) if args.size() > 0 else -1
			var locked = lv and lv.has_method("exit_locked") and lv.exit_locked()
			if p.alive and not p.escaped and s == int(p.sector) and not locked:
				event("door", [s])
		"advance":
			# through the exit door into the next sector
			var from = int(args[0]) if args.size() > 0 else -1
			var locked = lv and lv.has_method("exit_locked") and lv.exit_locked()
			if not p.alive or p.escaped or locked or from != int(p.sector) or from >= last:
				return
			advance_to(id, from + 1)
		"escaped":
			var locked = lv and lv.has_method("exit_locked") and lv.exit_locked()
			if p.alive and not p.escaped and not locked and int(p.sector) >= last:
				event("escaped", [id])
		_:
			if lv and lv.has_method("on_request"):
				lv.on_request(id, type, args)


## Server: points for an operative (photos, missions).
func award(id: int, pts: int, why: String) -> void:
	if not is_server() or not players.has(id) or pts <= 0:
		return
	players[id].points = int(players[id].get("points", 0)) + pts
	event("points", [id, players[id].points, pts, why])


## Server: a brainrot reached a player.
func catch(id: int, msg: String, killer := "tung", enemy_idx := -1) -> void:
	if is_server() and players.has(id) and players[id].alive and not players[id].escaped:
		event("died", [id, msg, killer, enemy_idx])


func _check_round_end() -> void:
	if not is_server() or state != PLAYING:
		return
	for id in players:
		var p = players[id]
		if p.in_game and p.alive and not p.escaped:
			return
	if world and world.has_method("round_hold") and world.round_hold():
		return            # the sector sends everybody back in (the boss fight)
	if _end_t < 0.0:
		_end_t = 5.0


func _end_round() -> void:
	var res = []
	var anyone_out = false
	for id in round_ids():
		var p = players[id]
		var where = "sector %d" % int(p.get("sector", 0))
		res.append([p.name, "made it out" if p.escaped else "became rot in " + where, p.cidx, p.get("photo", 0), p.get("photo_of", ""), int(p.get("points", 0))])
		anyone_out = anyone_out or p.escaped
	_log("round over · deepest sector %d · %s" % [wave, "someone made it out" if anyone_out else "nobody made it out"])
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
					rpc_unreliable("_es", i, e.global_transform.origin, e.rotation.y, e.net_state(), OS.get_ticks_msec() & 0xffff)
					i += 1
		_beacon_t -= delta
		if _beacon and _beacon_t <= 0.0:
			_beacon_t = 1.0
			var info = {"g": "sahur", "v": VERSION, "n": server_name, "p": players.size(), "m": MAX_PLAYERS, "s": state == PLAYING, "port": PORT}
			_beacon.put_packet(to_json(info).to_utf8())
	if active() and not is_server() and (state == LOBBY or state == PLAYING):
		_ping_t -= delta
		if _ping_t <= 0.0:
			_ping_t = 1.0
			rpc_unreliable_id(1, "_ping_q", OS.get_ticks_msec())
	if state == PLAYING and world and world.player:
		_send_t -= delta
		if _send_t <= 0.0:
			_send_t = 1.0 / SEND_HZ
			world.send_local_state()


func _process(_d: float) -> void:
	# a second network poll at the very end of the frame: what the game sent goes out now, not
	# next frame, and what arrived meanwhile is handled now (the room's proxy runs right after)
	var np = get_tree().network_peer
	if np and np.get_connection_status() != NetworkedMultiplayerPeer.CONNECTION_DISCONNECTED:
		get_tree().multiplayer.poll()
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
