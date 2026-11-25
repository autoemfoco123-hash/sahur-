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
		elif a.begins_with("out="):
			out = a.split("=")[1]
		elif a.begins_with("at="):
			for e in a.substr(3).split(","):
				var kv = e.split(":", true, 1)
				events[int(kv[0])] = kv[1]


func _idle(_d: float) -> bool:
	n += 1
	if n == 2:
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
	elif w == null:
		return
	elif act == "kill":
		w.kill("tung", "tung tung tung sahur found you.\nyou should have answered.")
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
