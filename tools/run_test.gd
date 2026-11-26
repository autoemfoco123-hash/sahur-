extends SceneTree
## Dev tool: run a scene for N frames, optionally save screenshots and fire game events.
## args: frames=N scene=res://... out=shot.png at=frame:action[,frame:action...]
## actions: kill, note, closenote, pause, unpause, complete, shot:<path>
var n := 0
var frames := 200
var scene := "res://scenes/world.tscn"
var out := ""
var events := {}


func _initialize() -> void:
	for a in OS.get_cmdline_args():
		if a.begins_with("frames="):
			frames = int(a.split("=")[1])
		elif a.begins_with("scene="):
			scene = a.split("=")[1]
		elif a == "menu":
			scene = "res://scenes/menu.tscn"
		elif a.begins_with("out="):
			out = a.split("=")[1]
		elif a.begins_with("at="):
			for e in a.substr(3).split(","):
				var kv = e.split(":", true, 1)
				events[int(kv[0])] = kv[1]


func _idle(_d: float) -> bool:
	n += 1
	if n == 2:
		for a in OS.get_cmdline_args():
			if a.begins_with("level="):
				root.get_node("Game").current_level = a.substr(6)
			if a.begins_with("seed="):
				root.get_node("Game").forced_seed = int(a.substr(5))
		if "headless" in OS.get_cmdline_args():
			root.get_node("Net").dedicated = true
		if "fakeserver" in OS.get_cmdline_args():
			# a dedicated server with one pretend operative standing at the spawn
			var net = root.get_node("Net")
			net.host("test", true)
			net.players[2] = net._new_player("bot")
			net.players[2].in_game = true
			net.state = net.PLAYING
			root.get_node("Game").forced_seed = 1234
		change_scene(scene)
	if n > 150 and n % 100 == 0:
		print("fps ", Engine.get_frames_per_second(), " gfx ", root.get_node("Game").settings.gfx,
			" proc_ms ", stepify(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.1),
			" phys_ms ", stepify(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.1),
			" draws ", Performance.get_monitor(Performance.RENDER_DRAW_CALLS_IN_FRAME),
			" verts ", Performance.get_monitor(Performance.RENDER_VERTICES_IN_FRAME),
			" objs ", Performance.get_monitor(Performance.RENDER_OBJECTS_IN_FRAME))
	if events.has(n):
		_event(events[n])
	if n == frames and out != "":
		_shot(out)
	return n > frames


func _shot(path: String) -> void:
	var img := root.get_texture().get_data()
	img.flip_y()
	img.save_png(path)


func _event(act: String) -> void:
	var w = root.find_node("World", true, false)
	print("event ", n, " ", act, " world=", w != null)
	if act.begins_with("shot:"):
		_shot(act.substr(5))
	elif act == "hostmenu":
		var m = root.get_tree().current_scene
		for n in [m] + m.get_children():
			if n.has_method("_do_host"):
				n._do_host()
				break
	elif w == null:
		return
	elif act == "kill":
		w.kill("tung", "tung tung tung sahur found you.\nyou should have answered.")
	elif act == "killkeys":
		w.kill("keys", "the keys found you.\nyou looked away.")
	elif act == "note":
		w.show_note("test note. hush nv-7 field log.")
	elif act == "closenote":
		w.close_note()
	elif act == "pause":
		w.set_paused(true)
	elif act == "unpause":
		w.set_paused(false)
	elif act == "complete":
		w.complete()
	elif act == "freeze":
		for e in w.get_tree().get_nodes_in_group("hostile"):
			e.frozen = true
	elif act == "tung":
		# park Tung 3.2 m in front of the player, facing them
		var pl = w.player
		var f = -pl.cam.global_transform.basis.z
		f.y = 0
		f = f.normalized()
		for e in w.get_tree().get_nodes_in_group("hostile"):
			e.frozen = true
			e.global_transform.origin = pl.global_transform.origin + f * 3.2
			e.look_at(pl.global_transform.origin, Vector3.UP)
			e.rotation.x = 0
	elif act.begins_with("door"):
		# stand 2 m in front of a sector's sliding door, facing it (door = sector 0, door1 = sector 1)
		var si = int(act.substr(4)) if act.length() > 4 else 0
		var d = w.doors[si]
		var o: Vector3 = d.global_transform.origin
		w.player.global_transform.origin = o + Vector3(-d.depth * 0.5 - 2.0, 0.1, 0)
		w.player.set_look(-PI * 0.5, 0.0)
		print("door %d at %s locked=%s" % [si, str(o), str(d.locked())])
	elif act.begins_with("xopen"):
		var si = int(act.substr(5)) if act.length() > 5 else 0
		w.door_use(w.doors[si])
	elif act == "fwdon":
		Input.action_press("move_forward")
	elif act == "fwdoff":
		Input.action_release("move_forward")
	elif act == "where":
		var pp = w.player.global_transform.origin if w.player else Vector3.ZERO
		var dd = ""
		for k in w.doors:
			dd += "%d:%.2f " % [k, w.doors[k].open_amt]
		print("where: my_sector=%d view=%d level=%d pos=%s doors=%s greeter=%s vis=%s out=%s dying=%s completing=%s" % [w.my_sector, w.view_sector, w.level.index, str(pp.round()), dd, str(w._greeter != null), str([w.levels[0].geo.visible, w.levels[1].geo.visible]), str(w.my_out), str(w.dying), str(w.completing)])
	elif act == "missions":
		var lv = w.levels[w.my_sector]
		var ms = PoolStringArray()
		for m in lv.missions:
			ms.append("%s=%s%s" % [m.id, str(m.progress), "✓" if m.done else ""])
		print("missions s%d: %s · locked=%s · points=%d" % [w.my_sector, ms.join(" "), str(lv.exit_locked()), w.my_points()])
	elif act.begins_with("taketape"):
		var lv = w.levels[0]
		var i = int(act.substr(8)) if act.length() > 8 else 0
		w.player.global_transform.origin = lv.tapes[i] + Vector3(0.8, 0.1, 0)
		lv._take_tape(i)
	elif act == "alldone":
		var lv = w.levels[w.my_sector]
		for m in lv.missions:
			lv.mission_set(m.id, m.goal, 1)
	elif act == "grabmaster":
		var lv = w.levels[1]
		w.player.global_transform.origin = lv.master.global_transform.origin + Vector3(1.4, 0.1, 0)
		lv._grab()
	elif act.begins_with("op"):
		# an operative 2.4 m in front of the camera, facing it (args: op or opwalk)
		var pl = w.player
		var f = -pl.cam.global_transform.basis.z
		f.y = 0
		f = f.normalized()
		var a = load("res://scripts/avatar.gd").new()
		w.add_child(a)
		a.setup(7, "operative 07", Color(0.35, 0.8, 1.0))
		var at = pl.global_transform.origin + f * 2.4
		a.place(at, atan2(f.x, f.z))
		if act == "opwalk":
			a.speed = 3.0
			a._target = at + Vector3(0.001, 0, 0)
	elif act == "nohud":
		w.hud.get_child(0).visible = false
	elif act == "keytest":
		# one key 6 m ahead, awake; everything else asleep far away
		var lv = w.level
		var pl = w.player
		var f = -pl.cam.global_transform.basis.z
		f.y = 0
		f = f.normalized()
		for i in lv.keys.size():
			var k = lv.keys[i]
			k.dormant = 0.0 if i == 1 else 999.0
		var k1 = lv.keys[1]
		# a spot on the path 5-14 m away that the player can actually see
		var eye = pl.eye_pos()
		var spot = null
		for c in lv.demo_path:
			var d = Vector2(c.x - eye.x, c.z - eye.z).length()
			if d > 5.0 and d < 14.0 and pl.get_world().direct_space_state.intersect_ray(eye, c + Vector3(0, 1.4, 0), [pl], 1).empty():
				spot = c
				break
		if spot == null:
			print("no visible spot")
			return
		k1.global_transform.origin = spot + Vector3(0, 0.05, 0)
		var to = spot - pl.global_transform.origin
		pl.set_look(atan2(-to.x, -to.z), -0.05)
		k1.look_at(pl.global_transform.origin, Vector3.UP)
		k1.rotation.x = 0
	elif act == "grabtest":
		var lv = w.level
		for k in lv.keys:
			k.dormant = 999.0
		var m = lv.master
		var pl = w.player
		var to = m.global_transform.origin - pl.global_transform.origin
		print("before: exit_locked=%s master.taken=%s dist=%.1f" % [str(lv.exit_locked()), str(m.taken), to.length()])
		pl.global_transform.origin = m.global_transform.origin + Vector3(1.6, 0.1, 0)
		lv._grab()
		print("after: exit_locked=%s master.taken=%s enraged=%s visible=%s" % [str(lv.exit_locked()), str(m.taken), str(lv.keys[1].enraged), str(m.visible)])
	elif act == "keyclose":
		var pl = w.player
		var k1 = w.level.keys[1]
		var f = -pl.cam.global_transform.basis.z
		f.y = 0
		k1.global_transform.origin = pl.global_transform.origin + f.normalized() * 1.6
		k1.look_at(pl.global_transform.origin, Vector3.UP)
		k1.rotation.x = 0
	elif act == "keynear":
		var pl = w.player
		var k1 = w.level.keys[1]
		var to = k1.global_transform.origin - pl.global_transform.origin
		to.y = 0
		k1.global_transform.origin = pl.global_transform.origin + to.normalized() * 2.6
		pl.set_look(atan2(-to.x, -to.z), 0.12)
	elif act == "photo":
		w.photo.take()
	elif act == "photoinfo":
		print("photo: score=%s name=%s grade=%s evidence=%s" % [w.hud.photo_score.text, w.hud.photo_name.text, w.hud.photo_grade.text, w.hud.evidence.text])
	elif act == "keydist":
		var k1 = w.level.keys[1]
		print("key distance %.2f observed=%s" % [k1.global_transform.origin.distance_to(w.player.global_transform.origin), str(k1.observed)])
	elif act.begins_with("turn"):
		w.player.set_look(w.player._yaw + deg2rad(float(act.substr(4))), 0.0)
	elif act.begins_with("yaw"):
		w.player.set_look(deg2rad(float(act.substr(3))), 0.0)
	elif act == "census":
		var counts = {}
		_census(w, counts)
		var keys = counts.keys()
		keys.sort()
		for k in keys:
			print("  ", k, ": ", counts[k])


func _census(nd: Node, counts: Dictionary) -> void:
	if nd is GeometryInstance and nd.is_visible_in_tree():
		var k = nd.get_class()
		if nd is MeshInstance and nd.mesh:
			k += "(" + str(nd.mesh.get_faces().size() / 3) + "f)" if nd.mesh.get_faces().size() > 3000 else ""
		k += " L" + str(nd.layers)
		counts[k] = counts.get(k, 0) + 1
	if nd is Light and nd.is_visible_in_tree():
		counts["Light " + nd.get_class()] = counts.get("Light " + nd.get_class(), 0) + 1
	for c in nd.get_children():
		_census(c, counts)
