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
	elif act.begins_with("writing"):
		# stand 2.6 m in front of wall writing i of the sector you are in, facing it
		var lv = w.levels[w.my_sector]
		var i = int(act.substr(7))
		var l: Spatial = lv.writings[i]
		var n: Vector3 = l.global_transform.basis.z
		n.y = 0
		n = n.normalized()
		var at = l.global_transform.origin + n * 2.6
		at.y = 0.1
		w.player.global_transform.origin = at
		w.player.set_look(atan2(n.x, n.z), 0.0)
		print("writing %d visible=%s" % [i, str(l.visible)])
	elif act.begins_with("killscene"):
		# an operative in front of tung (or a key), seen from the side: watch the kill
		var keys = act.ends_with("keys")
		var pl = w.player
		var f = -pl.cam.global_transform.basis.z
		f.y = 0
		f = f.normalized()
		var right = f.cross(Vector3.UP)
		var killer = w.level.keys[1] if keys else w.levels[0].tung
		killer.frozen = true
		if keys:
			killer.dormant = 999.0
		var center = pl.global_transform.origin + f * 4.2
		center.y = pl.global_transform.origin.y
		var flip = -1.0 if act.find("flip") >= 0 else 1.0
		killer.global_transform.origin = center - right * 0.75 * flip
		var a = load("res://scripts/avatar.gd").new()
		w.add_child(a)
		a.setup(7, "operative 07", Color(0.35, 0.8, 1.0))
		var at = center + right * 0.6 * flip
		a.place(at, atan2(right.x * flip, right.z * flip))
		w.avatars[7] = a
		killer.look_at(at, Vector3.UP)
		killer.rotation.x = 0
		set_meta("victim", 7)
		set_meta("killer", w.enemies.find(killer))
	elif act == "dokill":
		w._death_show(get_meta("victim"), get_meta("killer"))
	elif act.begins_with("tokhaby"):
		# stand in front of the mechanism, looking at its face (tokhaby3 = 3 m away)
		var lv = w.levels[2]
		var k = lv.khaby.global_transform.origin
		var dist = float(act.substr(7)) if act.length() > 7 else 4.0
		var at = k + Vector3(-dist, 0.3, 0)
		w.player.global_transform.origin = at
		var to = k + Vector3(0, 2.35, 0) - (at + Vector3(0, 1.6, 0))
		w.player.set_look(atan2(-to.x, -to.z), atan2(to.y, Vector2(to.x, to.z).length()))
	elif act == "talk":
		w.levels[2]._talk()
	elif act.begins_with("look"):
		# look: yaw degrees , pitch degrees  e.g. look30_10
		var parts = act.substr(4).split("_")
		w.player.set_look(deg2rad(float(parts[0])), deg2rad(float(parts[1])) if parts.size() > 1 else 0.0)
	elif act.begins_with("to67"):
		# 67 parked in front of you, facing you (to674 = 4 m away), frozen
		var lv = w.levels[w.my_sector]
		var pl = w.player
		var f = -pl.cam.global_transform.basis.z
		f.y = 0
		f = f.normalized()
		var dist = float(act.substr(4)) if act.length() > 4 else 5.0
		lv.ss.frozen = true
		lv.ss.dormant = 999.0
		lv.ss.relocate(pl.global_transform.origin + f * dist + Vector3(0, 0.1, 0))
		lv.ss.look_at(pl.global_transform.origin + Vector3(0, 0.1, 0), Vector3.UP)
		lv.ss.rotation.x = 0
	elif act.begins_with("call"):
		# 67 calls a number now (call6 / call7), it stays where it is
		var lv = w.levels[w.my_sector]
		lv._emit("call", [int(act.substr(4)), lv.ss.global_transform.origin])
	elif act.begins_with("togate"):
		# 3 m from gate i, facing it
		var lv = w.levels[w.my_sector]
		var g = lv.gates[int(act.substr(6))]
		var nrm = Vector3(0, 0, 1) if g.along_x else Vector3(1, 0, 0)
		w.player.global_transform.origin = g.pos + nrm * 3.0 + Vector3(0, 0.1, 0)
		w.player.set_look(atan2(nrm.x, nrm.z), 0.0)
		print("gate %d n=%d open=%.2f want=%.2f layout=%d" % [int(act.substr(6)), g.n, g.open, g.want, lv.layout])
	elif act.begins_with("ingate"):
		# standing right in gate i
		var lv = w.levels[w.my_sector]
		var g = lv.gates[int(act.substr(6))]
		w.player.global_transform.origin = g.pos + Vector3(0, 0.1, 0)
	elif act.begins_with("tonum"):
		var lv = w.levels[w.my_sector]
		var n = int(act.substr(5))
		var p: Vector3 = lv.numerals[n].pos
		var c: Vector2 = lv.numerals[n].cell
		var at = p
		for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			if lv._passable(c, c + d):
				at = p + Vector3(d.x, 0, d.y) * 1.6
		w.player.global_transform.origin = at + Vector3(0, 0.1, 0)
		var to = p + Vector3(0, 1.0, 0) - (at + Vector3(0, 1.6, 0))
		w.player.set_look(atan2(-to.x, -to.z), atan2(to.y, Vector2(to.x, to.z).length()))
	elif act.begins_with("takenum"):
		w.levels[w.my_sector]._take_num(int(act.substr(7)))
	elif act == "pos":
		var lv = w.levels[w.my_sector]
		print("pos %s gate0 %s open=%.2f" % [str(w.player.global_transform.origin), str(lv.gates[0].pos) if lv.get("gates") else "", lv.gates[0].open if lv.get("gates") else -1.0])
	elif act == "visall":
		var vv = PoolStringArray()
		for lv in w.levels:
			vv.append("%d:%s" % [lv.index, str(lv.geo.visible)])
		print("visall ", vv.join(" "), " cam=", str(w.player.cam.global_transform.origin.round()))
	elif act.begins_with("hide"):
		w.levels[int(act.substr(4))].geo.visible = false
		w.set_process(false)
	elif act == "grade":
		print("grade ", w.photo._grade())
	elif act == "photo":
		w.photo.take()
	elif act.begins_with("keyfront"):
		# one key (keyfront1 = keys[1]) 2.6 m in front of you, facing you, held still
		var lv = w.levels[w.my_sector]
		var k = lv.keys[int(act.substr(8))]
		var pl = w.player
		var f = -pl.cam.global_transform.basis.z
		f.y = 0
		f = f.normalized()
		k.dormant = 999.0
		k.frozen = true
		k.global_transform.origin = pl.global_transform.origin + f * 2.6
		k.look_at(pl.global_transform.origin, Vector3.UP)
		k.rotation.x = 0
	elif act.begins_with("tokey"):
		# stand 3 m from key i (as it is: not moved, not frozen), aiming the camera at its face
		var lv = w.levels[w.my_sector]
		var k = lv.keys[int(act.substr(5))]
		var kp: Vector3 = k.global_transform.origin
		var fwd = -k.global_transform.basis.z
		fwd.y = 0
		var side = act.find("back") < 0
		var at = kp + (fwd.normalized() if side else -fwd.normalized()) * 3.0
		w.player.global_transform.origin = at + Vector3(0, 0.1, 0)
		var face = k.model.global_transform.xform(Vector3(0, k.model.get_meta("face_y"), 0))
		var to = face - (at + Vector3(0, 1.6, 0))
		w.player.set_look(atan2(-to.x, -to.z), atan2(to.y, Vector2(to.x, to.z).length()))
	elif act == "keys":
		var lv = w.levels[w.my_sector]
		var ks = PoolStringArray()
		for k in lv.keys:
			ks.append("%s obs=%s dorm=%.1f pos=%s yaw=%.2f vis=%s" % ["M" if k.master else "k", str(k.observed), k.dormant, str(k.global_transform.origin.round()), k.rotation.y, str(k.model.is_visible_in_tree())])
		print("keys ", ks.join(" | "))
	elif act.begins_with("stare"):
		# key i, awake (not frozen) but sleeping (dormant), 1.5 m in front of you
		var lv = w.levels[w.my_sector]
		var k = lv.keys[int(act.substr(5))]
		k.frozen = false
		k.dormant = 1e9
		var pl = w.player
		var f = -pl.cam.global_transform.basis.z
		f.y = 0
		f = f.normalized()
		k.global_transform.origin = pl.global_transform.origin + f * 1.5
		k.look_at(pl.global_transform.origin, Vector3.UP)
		k.rotation.x = 0
		var face = k.model.global_transform.xform(Vector3(0, k.model.get_meta("face_y"), 0))
		var to = face - pl.eye_pos()
		pl.set_look(atan2(-to.x, -to.z), atan2(to.y, Vector2(to.x, to.z).length()))
	elif act == "obs":
		var lv = w.levels[w.my_sector]
		var ks = PoolStringArray()
		for k in lv.keys:
			ks.append("%s obs=%s frz=%s dorm=%.0f d=%.2f" % ["M" if k.master else "k", str(k.observed), str(k.frozen), k.dormant, Vector2(k.global_transform.origin.x - w.player.global_transform.origin.x, k.global_transform.origin.z - w.player.global_transform.origin.z).length()])
		print("obs ", ks.join(" | "), " stare=", lv._stare, " wave=", lv.wave_started, " targets=", w.targets(lv.index).size())
	elif act.begins_with("revive"):
		w.revive_local(int(act.substr(6)))
	elif act == "wakeinfo":
		var pl = w.player
		print("wake: sector=%d waking=%.2f blur=%.2f eyes_visible=%s cam_h=%.2f pitch=%.2f controls=%s" % [w.my_sector, pl.waking, pl.wake_blur, str(w.hud.eyes.visible), pl.head.translation.y, pl.head.rotation.x, str(pl.controls)])
	elif act == "kill67":
		w.kill("67", "67 took you.")
	elif act == "gates":
		var lv = w.levels[w.my_sector]
		var gs = PoolStringArray()
		for g in lv.gates:
			gs.append("%d:%.1f" % [g.n, g.open])
		print("gates layout=%d %s nums=%s" % [lv.layout, gs.join(" "), str(lv.numerals.keys())])
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
	elif act == "boss":
		var lv = w.levels[w.my_sector]
		var on = 0
		for a in lv.anchors:
			on += 1 if a.on else 0
		print("boss fight=%d hp=%.1f/%.1f phase=%d shield=%s anchors=%d me=%s cells=%.1f dying=%s out=%s sink=%.1f act=%d" % [lv.fight, lv.hp, lv.hp_max, lv.phase, str(lv.shield), on, str((w.player.global_transform.origin - lv.center).round()), root.get_node("Game").brain_cells, str(w.dying), str(w.my_out), lv.ultra._sink, lv.ultra.body_act])
	elif act == "aimboss":
		var lv = w.levels[w.my_sector]
		var f = lv.ultra.face_world()
		var p = w.player.cam.global_transform.origin
		var to = f - p
		w.player.set_look(atan2(-to.x, -to.z), atan2(to.y, Vector2(to.x, to.z).length()))
	elif act.begins_with("tp"):
		# tp<x>_<z>: stand there, relative to the middle of the hall (the pit)
		var lv = w.levels[w.my_sector]
		var xz = act.substr(2).split("_")
		w.player.global_transform.origin = lv.center + Vector3(float(xz[0]), 0.3, float(xz[1]))
		w.player.velocity = Vector3.ZERO
	elif act == "allanchors":
		var lv = w.levels[w.my_sector]
		for i in lv.anchors.size():
			if not lv.anchors[i].on:
				w.player.global_transform.origin = lv.anchors[i].pos + Vector3(1.5, 0.3, 0)
				lv.on_request(1, "anchor", [i])
	elif act.begins_with("uphoto"):
		w.levels[w.my_sector].on_request(1, "photo", ["ultra", int(act.substr(6))])
	elif act.begins_with("attack"):
		# attack<name>: slam / sweep / scream / call6 / call7, at you
		var lv = w.levels[w.my_sector]
		var kind = act.substr(6)
		var me = w.player.global_transform.origin
		match kind:
			"slam":
				lv._emit("slam", [0, me.x, me.z, 1.3])
			"sweep":
				var ang = atan2(me.x - lv.center.x, me.z - lv.center.z)
				lv._emit("sweep", [0, ang - 1.4, ang + 1.4, 1.2, 0.9])
			"scream":
				lv._emit("scream", [2.0])
			"call6", "call7":
				lv._emit("call", [int(kind.substr(4)), 2.2, 4.2])
		lv._next_attack = 9999.0
	elif act == "nob":
		w.levels[w.my_sector].ultra.model.visible = false
		w.set_process(false)
	elif act == "nolamps":
		for l in w.levels[w.my_sector].lamps:
			l.visible = false
	elif act == "noshield":
		w.levels[w.my_sector].ultra.model.get_node("shield").visible = false
		w.levels[w.my_sector].ultra.set_physics_process(false)
	elif act == "lightstat":
		var n = 0
		var lit = []
		for l in w.get_tree().get_nodes_in_group("__none__"):
			pass
		_lights(w, lit)
		print("lights visible: ", lit.size(), " ", lit)
	elif act == "slab6" or act == "slab7":
		# stand in the middle of a slab with that number, ~15-25 m from the pit
		var lv = w.levels[w.my_sector]
		var want = int(act.substr(4))
		for c in lv.tiles:
			var t = lv.tiles[c]
			var p = lv._tile_center(c)
			var r = Vector2(p.x - lv.center.x, p.z - lv.center.z).length()
			if t.kind == want and r > 15.0 and r < 25.0:
				w.player.global_transform.origin = p + Vector3(0, 0.3, 0)
				w.player.velocity = Vector3.ZERO
				print("on slab ", c, " kind ", t.kind)
				break
	elif act == "exitinfo":
		var lv = w.levels[w.my_sector]
		var d = w.doors.get(lv.index)
		print("exit locked=%s missions=%s door=%s" % [str(lv.exit_locked()), str(lv.missions), str(d != null)])
	elif act == "bossdie":
		var lv = w.levels[w.my_sector]
		lv._emit("die", [1])
		lv.mission_set("ultra", 1, 1)
	elif act == "stickon" or act == "stickoff":
		# a thumb on the fixed stick, pushed forward (stickoff lifts it)
		var tc = null
		for c in root.get_children():
			for c2 in [c] + c.get_children():
				if c2.has_method("_stick_center"):
					tc = c2
		if tc == null:
			print("no touch controls")
			return
		var at = tc._stick_center()
		var ev = InputEventScreenTouch.new()
		ev.index = 0
		ev.position = at + Vector2(10, 5)
		ev.pressed = act == "stickon"
		Input.parse_input_event(ev)
		if act == "stickon":
			var dr = InputEventScreenDrag.new()
			dr.index = 0
			dr.position = at + Vector2(0, -90)
			Input.parse_input_event(dr)
		print("stick ", act, " center ", at, " player ", w.player.global_transform.origin.round())
	elif act == "faceenemy":
		# stand 3.5 m in front of this sector's brainrot, held still, looking at its face
		var e = null
		for x in w.enemies:
			if is_instance_valid(x) and x.sector == w.my_sector:
				e = x
				break
		if e == null:
			print("no enemy here")
			return
		e.frozen = true
		if "dormant" in e:
			e.dormant = 999.0
		var f = -e.global_transform.basis.z
		f.y = 0
		f = f.normalized()
		var at = e.global_transform.origin + f * 3.5
		at.y = e.global_transform.origin.y + 0.1
		w.player.global_transform.origin = at
		var face = e.global_transform.origin + Vector3(0, e.height * 0.8, 0)
		var to = face - w.player.cam.global_transform.origin
		w.player.set_look(atan2(-to.x, -to.z), atan2(to.y, Vector2(to.x, to.z).length()))
	elif act == "noattack":
		if "_next_attack" in w.levels[w.my_sector]:
			w.levels[w.my_sector]._next_attack = 9999.0
	elif act == "jumpdown":
		Input.action_press("jump")
	elif act == "jumpup":
		Input.action_release("jump")
	elif act == "census":
		var counts = {}
		_census(w, counts)
		var keys = counts.keys()
		keys.sort()
		for k in keys:
			print("  ", k, ": ", counts[k])


func _lights(nd: Node, out: Array) -> void:
	if nd is Light and nd.is_visible_in_tree():
		out.append("%s@%s m%d" % [nd.get_class(), str(nd.global_transform.origin.round()), nd.light_cull_mask])
	for c in nd.get_children():
		_lights(c, out)


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
