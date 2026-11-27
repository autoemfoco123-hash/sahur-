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
		elif a == "noblur":
			root.get_node("Game").settings.motion_blur = 0.0
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
		img.save_png(prefix + pname + "_" + str(int((OS.get_ticks_msec() - t0) / 100)) + ".png")
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
		# walk up to the sliding door of the sector you are in and press e
		var d = w.doors[w.my_sector]
		var o: Vector3 = d.global_transform.origin
		w.player.global_transform.origin = o + Vector3(-d.depth * 0.5 - 1.2, 0.1, 0)
		w.player.set_look(-PI * 0.5, 0.0)
		w.door_use(d)
	elif act == "cross":
		# step through the (open) door to the other side
		var d = w.doors[w.my_sector]
		w.player.global_transform.origin = d.global_transform.origin + Vector3(d.depth * 0.5 + 1.0, 0.1, 0)
	elif act == "missions":
		var lv = w.levels[w.my_sector]
		var ms = PoolStringArray()
		for m in lv.missions:
			ms.append("%s=%s%s" % [m.id, str(m.progress), "+" if m.done else ""])
		print("[", pname, "] missions s%d: %s locked=%s points=%d" % [w.my_sector, ms.join(" "), str(lv.exit_locked()), w.my_points()])
	elif act == "cheat":
		net.request("cheat_missions")
	elif act.begins_with("totape"):
		var i = int(act.substr(6))
		w.player.global_transform.origin = w.levels[0].tapes[i] + Vector3(0.8, 0.1, 0)
	elif act.begins_with("tape"):
		w.levels[0]._take_tape(int(act.substr(4)))
	elif act == "totung":
		# walk right into tung's reach (the server decides the rest)
		var tg = w.levels[0].tung
		var tp: Vector3 = tg.global_transform.origin
		var f = -tg.global_transform.basis.z
		f.y = 0
		w.player.global_transform.origin = tp + f.normalized() * 0.9 + Vector3(0, 0.1, 0)
	elif act == "watch":
		# stand a few metres from the other operative and tung, with a clear view of both
		var other = null
		for pid in w.avatars:
			other = w.avatars[pid]
		if other == null:
			return
		var tg = w.levels[0].tung
		var tf = -tg.global_transform.basis.z
		tf.y = 0
		var mid: Vector3 = tg.global_transform.origin + tf.normalized() * 0.6
		var best = null
		for i in 16:
			var ang = i * TAU / 16.0
			for dist in [7.0, 6.0, 5.0]:
				var c = mid + Vector3(cos(ang), 0, sin(ang)) * dist
				if not w.nav.is_open(c):
					continue
				var hit = w.get_world().direct_space_state.intersect_ray(c + Vector3(0, 1.5, 0), mid + Vector3(0, 1.3, 0), [w.player], 1)
				if hit.empty():
					best = c
					break
			if best != null:
				break
		if best == null:
			print("[", pname, "] no clear view")
			return
		w.player.global_transform.origin = best + Vector3(0, 0.1, 0)
		var to = mid - best
		w.player.set_look(atan2(-to.x, -to.z), -0.12)
	elif act == "aim":
		var tg = w.levels[0].tung
		var to = tg.global_transform.origin - w.player.global_transform.origin
		w.player.set_look(lerp_angle(w.player._yaw, atan2(-to.x, -to.z), 0.5), -0.12)
	elif act == "corpses":
		var cs = PoolStringArray()
		for c in w.corpses:
			if is_instance_valid(c):
				cs.append(str(c.center().round()))
		print("[", pname, "] corpses: ", cs.join(" "), "  tung kill_t=%.2f" % w.levels[0].tung.kill_t)
	elif act == "tokhaby":
		var k = w.levels[2].khaby.global_transform.origin
		w.player.global_transform.origin = k + Vector3(-3.5, 0.6, 0.8 if pname == "bravo" else -0.8)
		var to = k + Vector3(0, 2.3, 0) - w.player.global_transform.origin
		w.player.set_look(atan2(-to.x, -to.z), 0.1)
	elif act == "talk":
		w.levels[2]._talk()
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
		for k in w.doors:
			ss += " door%d=%.2f" % [k, w.doors[k].open_amt]
		print("[", pname, "] where my_sector=%d view=%d pos=%s out=%s dying=%s greeter=%s wave1=%s scene=%.1f players=%s" % [w.my_sector, w.view_sector, str(w.player.global_transform.origin.round()), str(w.my_out), str(w.dying), str(w._greeter != null), str(w.levels[1].wave_started), w.levels[2].scene_t, ss])
	elif act == "freeze":
		for e in w.get_tree().get_nodes_in_group("hostile"):
			e.frozen = true
	elif act == "gates":
		var lv = w.levels[3]
		var gs = PoolStringArray()
		for g in lv.gates:
			gs.append("%d:%.1f" % [g.n, g.open])
		var p67 = lv.ss.global_transform.origin.round() if is_instance_valid(lv.ss) else Vector3.ZERO
		print("[", pname, "] gates layout=%d %s 67=%s state=%d calls=%s" % [lv.layout, gs.join(" "), str(p67), lv.ss.state, str(lv.mission_progress("calls"))])
	elif act.begins_with("num"):
		# walk into a number's dead end (gates or not) and take it
		var lv = w.levels[3]
		var n = int(act.substr(3))
		w.player.global_transform.origin = lv.numerals[n].pos + Vector3(0.6, 0.1, 0.6)
		lv._take_num(n)
	elif act == "freeze67":
		w.levels[3].ss.frozen = true


func Game_kill(w) -> void:
	w.kill("tung", "test")
	_net().request("died", ["test"])
