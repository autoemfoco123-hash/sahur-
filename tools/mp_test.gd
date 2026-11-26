extends SceneTree
## Dev tool: a scripted multiplayer client.
## args: name=alpha ip=127.0.0.1 secs=N prefix=/path/shot_ at=second:action,...  (times in seconds)
## actions: shot, look (turn toward the nearest other operative), shout, say, walk, die
var n := 0
var frames := 900
var pname := "bot"
var ip := "127.0.0.1"
var prefix := "/tmp/mp_"
var events := {}
var joined := false
var readied := false
var walk_t := 0
var t0 := 0
var secs := 60.0
var fired := {}


func _initialize() -> void:
	for a in OS.get_cmdline_args():
		if a.begins_with("secs="):
			secs = float(a.split("=")[1])
		elif a.begins_with("name="):
			pname = a.split("=")[1]
		elif a.begins_with("ip="):
			ip = a.split("=")[1]
		elif a.begins_with("prefix="):
			prefix = a.split("=")[1]
		elif a.begins_with("at="):
			for e in a.substr(3).split(","):
				var kv = e.split(":", true, 1)
				events[float(kv[0])] = kv[1]


func _net():
	return root.get_node("Net")


func _idle(_d: float) -> bool:
	n += 1
	if t0 == 0:
		t0 = OS.get_ticks_msec()
	var t = (OS.get_ticks_msec() - t0) / 1000.0
	var net = _net()
	if n == 30 and not joined and "host" in OS.get_cmdline_args():
		joined = true
		net.host(pname)
		print("[", pname, "] hosting")
	elif n == 30 and ip == "auto":
		net.start_discovery()
	elif ip == "auto" and not joined and net.found.size() > 0:
		joined = true
		var first = net.found.keys()[0]
		print("[", pname, "] found on lan: ", first, " ", net.found[first])
		net.stop_discovery()
		net.join(first, pname)
	elif n == 30 and not joined and ip != "auto":
		joined = true
		net.join(ip, pname)
		print("[", pname, "] joining ", ip)
	if joined and not readied and net.state == net.LOBBY and net.players.has(net.my_id()):
		readied = true
		net.set_ready(true)
		print("[", pname, "] ready · players ", net.players.size())
	if n % 60 == 0:
		var w = net.world
		print("[", pname, "] t ", int(t), " state ", net.state, " fps ", Engine.get_frames_per_second(), " world ", w != null,
			" avatars ", (w.avatars.size() if w else 0), " alive ", _alive(net))
	if walk_t > 0 and net.world and net.world.player:
		walk_t -= 1
		Input.action_press("move_forward")
		if walk_t == 0:
			Input.action_release("move_forward")
	for et in events:
		if t >= et and not fired.has(et):
			fired[et] = true
			_event(events[et])
	return t > secs


func _alive(net) -> String:
	var s = ""
	for pid in net.players:
		var p = net.players[pid]
		s += "%s:%s " % [p.name, "out" if p.escaped else ("rot" if not p.alive else "in")]
	return s


func _event(act: String) -> void:
	var net = _net()
	var w = net.world
	print("[", pname, "] event ", act)
	if act.begins_with("shot"):
		var img := root.get_texture().get_data()
		img.flip_y()
		img.save_png(prefix + pname + "_" + str(int((OS.get_ticks_msec() - t0) / 1000)) + ".png")
	elif w == null:
		return
	elif act == "look":
		var best = null
		var bd = 1e9
		for pid in w.avatars:
			var a = w.avatars[pid]
			var d = a.global_transform.origin.distance_to(w.player.global_transform.origin)
			if d < bd:
				bd = d
				best = a
		if best:
			var to = best.global_transform.origin - w.player.global_transform.origin
			# step back so the whole operative is in view
			w.player.global_transform.origin -= to.normalized() * 2.2
			to = best.global_transform.origin - w.player.global_transform.origin
			w.player.set_look(atan2(-to.x, -to.z), -0.05)
	elif act == "shout":
		w.player.emit_signal("shouted")
	elif act == "walk":
		walk_t = 40
	elif act == "die":
		Game_kill(w)
	elif act == "door":
		# walk up to the exit of the sector you are in and open it
		var lv = w.levels[w.my_sector]
		var d: Spatial = lv.exit_root
		var front: Vector3 = d.global_transform.xform(Vector3(0, 0, 1.5))
		w.player.global_transform.origin = front + Vector3(0, 0.1, 0)
		var to = d.global_transform.origin - front
		w.player.set_look(atan2(-to.x, -to.z), 0.0)
		w.use_exit(lv, d)
	elif act == "tomaster":
		# right next to the master key, staring at it (watched, it can't run)
		var lv = w.levels[1]
		var m = lv.master.global_transform.origin
		w.player.global_transform.origin = m + Vector3(1.4, 0.1, 0)
		var to = m - w.player.global_transform.origin
		w.player.set_look(atan2(-to.x, -to.z), -0.1)
	elif act == "grab":
		w.levels[1]._grab()
	elif act == "where":
		var ss = ""
		for pid in net.players:
			var p = net.players[pid]
			ss += "%s:s%d:%s " % [p.name, int(p.get("sector", -1)), "out" if p.escaped else ("rot" if not p.alive else "in")]
		print("[", pname, "] where my_sector=%d view=%d pos=%s out=%s dying=%s transit=%s wave1=%s calling=%s answered=%s players=%s" % [w.my_sector, w.view_sector, str(w.player.global_transform.origin.round()), str(w.my_out), str(w.dying), str(w._transit), str(w.levels[1].wave_started), str(w.levels[0].calling), str(w.levels[0].answered), ss])
	elif act == "freeze":
		for e in w.get_tree().get_nodes_in_group("hostile"):
			e.frozen = true


func Game_kill(w) -> void:
	w.kill("tung", "test")
	_net().request("died", ["test"])
