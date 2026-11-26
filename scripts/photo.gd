extends Node
## The hush field camera. Your job down here is evidence: photograph the entities, and make
## the photos good. F / right mouse / the camera button.
## Every shot is graded on the spot: how big the entity is in frame, how centred, whether it is
## looking into the lens, how steady you held it, and whether the flash reached it.
## The flash has consequences: Tung wakes up when it goes off in his face; it freezes the keys.

const COOLDOWN = 1.4
const LENS_FOV = 58.0     # the camera's lens: matches the middle of the goggles' fisheye view

var world
var best = {}             # entity id -> best score this round
var shots = 0
var _cd = 0.0
var _flash: OmniLight
var _prev = Vector2.ZERO
var _rot_speed = 0.0
var _busy = false


func _ready() -> void:
	_flash = OmniLight.new()
	_flash.light_color = Color(1.0, 0.97, 0.92)
	_flash.light_energy = 0.0
	_flash.omni_range = 11.0
	_flash.omni_attenuation = 0.8
	world.player.cam.add_child(_flash)
	_flash.translation = Vector3(0.08, 0.05, -0.15)


func _physics_process(delta: float) -> void:
	_cd -= delta
	var pl = world.player
	var r = Vector2(pl._yaw, pl._pitch)
	_rot_speed = lerp(_rot_speed, (r - _prev).length() / max(delta, 0.0001), 0.5)
	_prev = r


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("photo"):
		take()


func take() -> void:
	var pl = world.player
	if _busy or _cd > 0.0 or world.dying or world.my_out or world.completing or not pl.controls:
		return
	_busy = true
	_cd = COOLDOWN
	shots += 1
	var cam: Camera = pl.cam
	var fov = cam.fov
	cam.fov = LENS_FOV
	var result = _grade()
	Audio.play("shutter", -1.0, rand_range(0.97, 1.03))
	_flash.light_energy = 7.0
	# the frame after the flash lights it is the photo (the camera sees no hud, no post)
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")
	var img = world.get_viewport().get_texture().get_data()
	_flash.light_energy = 0.0
	cam.fov = fov
	world.flash(0.7)
	img.flip_y()
	img.resize(640, 360, Image.INTERPOLATE_BILINEAR)
	_save(img, result)
	var thumb = img.duplicate()
	thumb.resize(320, 180, Image.INTERPOLATE_BILINEAR)
	var tex = ImageTexture.new()
	tex.create_from_image(thumb, Texture.FLAG_FILTER)
	var is_best = result.score > 0 and result.score > best.get(result.id, 0)
	if is_best:
		best[result.id] = result.score
	if world.hud:
		world.hud.show_photo(tex, result, is_best, best)
	if Net.active():
		Net.request("photo", [result.id, result.score])
	elif world.level and world.level.has_method("on_request"):
		world.level.on_request(1, "photo", [result.id, result.score])
	_busy = false


## The best entity in frame, graded 0..100 at the moment the shutter opens.
func _grade() -> Dictionary:
	var cam: Camera = world.player.cam
	var from = cam.global_transform.origin
	var vp = world.get_viewport().size
	var half = tan(deg2rad(cam.fov) * 0.5)
	var out = {"score": 0, "id": "", "name": "nothing", "grade": "nothing on it.", "dist": 0.0}
	for m in get_tree().get_nodes_in_group("photographable"):
		if not is_instance_valid(m) or not m.is_visible_in_tree():
			continue
		var h: float = m.get_meta("height")
		var face: Vector3 = m.global_transform.xform(Vector3(0, m.get_meta("face_y") if m.has_meta("face_y") else h * 0.8, 0))
		if cam.is_position_behind(face):
			continue
		var sp = cam.unproject_position(face)
		var nx = sp.x / vp.x * 2.0 - 1.0
		var ny = sp.y / vp.y * 2.0 - 1.0
		if abs(nx) > 1.0 or abs(ny) > 1.0:
			continue
		var ex = [world.player]
		if not cam.get_world().direct_space_state.intersect_ray(from, face, ex, Geo.LAYER_WORLD).empty():
			continue
		var dist = from.distance_to(face)
		var frac = h / (2.0 * dist * half)                       # share of the frame height
		var size_s = smoothstep(0.06, 0.5, frac) * (1.0 - 0.45 * smoothstep(1.0, 1.8, frac))
		var center_s = 1.0 - clamp(Vector2(nx, ny * 0.8).length() / 0.95, 0.0, 1.0)
		var fwd = -m.global_transform.basis.z
		fwd.y = 0.0
		var tc = from - face
		tc.y = 0.0
		var face_s = clamp((fwd.normalized().dot(tc.normalized()) + 0.3) / 1.3, 0.0, 1.0)
		var sharp_s = 1.0 - clamp(_rot_speed / 3.0, 0.0, 1.0)
		var lit = 1.0 if dist < 9.0 else 0.72
		var s = 100.0 * (0.34 * size_s + 0.24 * center_s + 0.26 * face_s + 0.16 * sharp_s) * lit
		if dist < 4.0:
			s += 6.0                                               # nobody gets this close twice
		s = clamp(round(s), 1.0, 100.0)
		if s > out.score:
			var id: String = m.get_meta("photo_id")
			out = {"score": int(s), "id": id, "name": _name(id), "grade": _word(s), "dist": dist}
	return out


func _name(id: String) -> String:
	match id:
		"tung":
			return "tung tung tung sahur"
		"master key":
			return "the master key"
	return id


func _word(s: float) -> String:
	if s >= 90:
		return "hush-grade evidence."
	if s >= 75:
		return "excellent shot."
	if s >= 55:
		return "good. get closer."
	if s >= 35:
		return "usable. barely."
	return "blurry. useless."


## Every photo is kept: user://photos/ (the game's data folder).
func _save(img: Image, r: Dictionary) -> void:
	var d = Directory.new()
	d.make_dir_recursive("user://photos")
	var name = "user://photos/sahur_%d_%s_%03d.png" % [OS.get_unix_time(), r.id.replace(" ", "-") if r.id != "" else "nothing", r.score]
	img.save_png(name)
