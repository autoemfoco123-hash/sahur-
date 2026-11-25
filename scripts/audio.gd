extends Node
## Audio engine. Every sound was synthesized offline by tools/sound_design.py (no samples).
## Variants, 3D occlusion (muffled through walls), ambience crossfades, breathing.

const VARIANTS := {
	"tung": 3, "step_wood": 4, "step_tile": 4, "step_concrete": 4, "step_metal": 4,
	"step_water": 4, "step_sand": 4, "step_grass": 4, "step_mud": 4,
}
const LOOP_PREFIXES := ["amb_", "chase_"]
const LOOPS := ["breath", "engine", "jet", "musicbox", "roll", "static", "fridge_hum", "death_drone", "nv_hum"]

var listener_cam: Camera
var _cache = {}
var _amb = []
var _amb_active = [0, 0]
var _breath: AudioStreamPlayer
var _breath_target = -80.0
var _tracked = []
var _occ_t = 0.0
var _dist: AudioEffectDistortion
var _lp: AudioEffectLowPassFilter
var _reverb: AudioEffectReverb
var _scaring = false


func _ready() -> void:
	pause_mode = Node.PAUSE_MODE_PROCESS
	_setup_buses()
	for i in 4:
		var p = AudioStreamPlayer.new()
		p.bus = "Amb"
		add_child(p)
		_amb.append(p)
	_breath = AudioStreamPlayer.new()
	_breath.stream = get_stream("breath")
	_breath.volume_db = -80.0
	add_child(_breath)


func _setup_buses() -> void:
	if AudioServer.get_bus_index("SFX") == -1:
		AudioServer.add_bus()
		var i = AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, "SFX")
		AudioServer.set_bus_send(i, "Master")
		_reverb = AudioEffectReverb.new()
		_reverb.room_size = 0.7
		_reverb.damping = 0.5
		_reverb.spread = 1.0
		_reverb.hipass = 0.1
		_reverb.wet = 0.22
		_reverb.dry = 1.0
		_reverb.predelay_msec = 25
		AudioServer.add_bus_effect(i, _reverb)
	if AudioServer.get_bus_index("Amb") == -1:
		AudioServer.add_bus()
		var j = AudioServer.bus_count - 1
		AudioServer.set_bus_name(j, "Amb")
		AudioServer.set_bus_send(j, "Master")
	var m = AudioServer.get_bus_index("Master")
	_dist = AudioEffectDistortion.new()
	_dist.mode = AudioEffectDistortion.MODE_OVERDRIVE
	_dist.drive = 0.0
	AudioServer.add_bus_effect(m, _dist)
	_lp = AudioEffectLowPassFilter.new()
	_lp.cutoff_hz = 20000
	AudioServer.add_bus_effect(m, _lp)
	var comp = AudioEffectCompressor.new()
	comp.threshold = -14.0
	comp.ratio = 3.0
	comp.attack_us = 2000
	comp.release_ms = 200
	AudioServer.add_bus_effect(m, comp)
	var lim = AudioEffectLimiter.new()
	lim.ceiling_db = -0.3
	AudioServer.add_bus_effect(m, lim)


func _process(delta: float) -> void:
	_breath.volume_db = move_toward(_breath.volume_db, _breath_target, delta * 30.0)
	if _breath.volume_db < -60.0 and _breath.playing:
		_breath.stop()
	elif _breath.volume_db > -60.0 and not _breath.playing:
		_breath.play(randf() * 10.0)
	_occ_t -= delta
	if _occ_t <= 0.0:
		_occ_t = 0.12
		_update_occlusion()


func set_madness(x: float) -> void:
	x = clamp(x, 0.0, 1.0)
	_dist.drive = x * 0.5
	_lp.cutoff_hz = lerp(20000.0, 2200.0, x * x)


func set_reverb(room: float, wet: float, damping := 0.5) -> void:
	_reverb.room_size = room
	_reverb.wet = wet
	_reverb.damping = damping


func set_breath(x: float) -> void:
	_breath_target = -80.0 if x < 0.05 else lerp(-26.0, -6.0, clamp(x, 0.0, 1.0))


## Total silence (master muted). Used right before the jumpscare. Turning it off also ends
## a scare (everything comes back exactly as it was).
func silence_all(on: bool) -> void:
	var m = AudioServer.get_bus_index("Master")
	AudioServer.set_bus_mute(m, on)
	if on:
		_breath_target = -80.0
		_breath.volume_db = -80.0
	elif _scaring:
		_scaring = false
		AudioServer.set_bus_mute(AudioServer.get_bus_index("SFX"), false)
		AudioServer.set_bus_mute(AudioServer.get_bus_index("Amb"), false)
		for i in AudioServer.get_bus_effect_count(m):
			AudioServer.set_bus_effect_enabled(m, i, true)


## The jumpscare: every other sound is cut and nothing on the master squashes it.
## The sample itself is already clipped at full scale: as loud as digital audio goes.
func scare(sname: String, vol_db := 0.0) -> AudioStreamPlayer:
	_scaring = true
	var m = AudioServer.get_bus_index("Master")
	AudioServer.set_bus_mute(AudioServer.get_bus_index("SFX"), true)
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Amb"), true)
	for i in AudioServer.get_bus_effect_count(m):
		var fx = AudioServer.get_bus_effect(m, i)
		# keep only the final limiter (protects against inter-sample overs)
		AudioServer.set_bus_effect_enabled(m, i, fx is AudioEffectLimiter)
	_breath_target = -80.0
	_breath.volume_db = -80.0
	AudioServer.set_bus_mute(m, false)
	var p = AudioStreamPlayer.new()
	p.stream = get_stream(sname)
	p.volume_db = vol_db
	p.bus = "Master"
	add_child(p)
	p.play()
	p.connect("finished", p, "queue_free")
	return p


func set_silence(on: bool) -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Amb"), on)


# ------------------------------------------------------------------ loading
func _is_loop(sname: String) -> bool:
	if sname in LOOPS:
		return true
	for pre in LOOP_PREFIXES:
		if sname.begins_with(pre):
			return true
	return false


func get_stream(sname: String) -> AudioStream:
	if VARIANTS.has(sname):
		sname = "%s_%d" % [sname, randi() % VARIANTS[sname]]
	if _cache.has(sname):
		return _cache[sname]
	var path = "res://sounds/%s.wav" % sname
	if not ResourceLoader.exists(path):
		push_warning("missing sound " + sname)
		return null
	var s: AudioStreamSample = load(path)
	if _is_loop(sname):
		s.loop_mode = AudioStreamSample.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(s.get_length() * s.mix_rate) - 1
	_cache[sname] = s
	return s


# ------------------------------------------------------------------ playback
func play(sname: String, vol_db := 0.0, pitch := 1.0) -> AudioStreamPlayer:
	var p = AudioStreamPlayer.new()
	p.stream = get_stream(sname)
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.bus = "SFX"
	add_child(p)
	p.play()
	p.connect("finished", p, "queue_free")
	return p


func _make3d(sname: String, vol_db: float, max_dist: float) -> AudioStreamPlayer3D:
	var p = AudioStreamPlayer3D.new()
	p.stream = get_stream(sname)
	p.unit_db = vol_db
	p.max_distance = max_dist
	p.unit_size = 7.0
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.attenuation_filter_cutoff_hz = 9000
	p.attenuation_filter_db = -18
	p.bus = "SFX"
	p.set_meta("base_db", vol_db)
	return p


func play_at(sname: String, pos: Vector3, parent: Node, vol_db := 0.0, pitch := 1.0, max_dist := 60.0) -> AudioStreamPlayer3D:
	var p = _make3d(sname, vol_db, max_dist)
	p.pitch_scale = pitch
	parent.add_child(p)
	p.global_transform.origin = pos
	_occlude(p)
	p.play()
	p.connect("finished", p, "queue_free")
	return p


## Persistent 3D emitter attached to a node (chase music...).
func attach(sname: String, node: Spatial, vol_db := 0.0, max_dist := 60.0) -> AudioStreamPlayer3D:
	var p = _make3d(sname, vol_db, max_dist)
	node.add_child(p)
	p.play(randf() * 2.0)
	_tracked.append(p)
	return p


func set_base_volume(p: AudioStreamPlayer3D, vol_db: float) -> void:
	p.set_meta("base_db", vol_db)


func _update_occlusion() -> void:
	var keep = []
	for p in _tracked:
		if is_instance_valid(p) and p.is_inside_tree():
			keep.append(p)
			_occlude(p)
	_tracked = keep


func _occlude(p: AudioStreamPlayer3D) -> void:
	if listener_cam == null or not is_instance_valid(listener_cam) or not listener_cam.is_inside_tree() or not p.is_inside_tree():
		return
	var from = listener_cam.global_transform.origin
	var to = p.global_transform.origin
	var blocked = false
	if from.distance_to(to) < p.max_distance:
		var hit = listener_cam.get_world().direct_space_state.intersect_ray(from, to, [], 1)
		blocked = not hit.empty() and (hit.position as Vector3).distance_to(to) > 0.8
	var base: float = p.get_meta("base_db") if p.has_meta("base_db") else 0.0
	p.attenuation_filter_cutoff_hz = 700.0 if blocked else 9000.0
	p.unit_db = base - (7.0 if blocked else 0.0)


# ------------------------------------------------------------------ ambience
func ambient(sname: String, vol_db := -6.0, layer := 0, fade := 2.0) -> void:
	var a: AudioStreamPlayer = _amb[layer * 2 + _amb_active[layer]]
	var b: AudioStreamPlayer = _amb[layer * 2 + 1 - _amb_active[layer]]
	_amb_active[layer] = 1 - _amb_active[layer]
	if a.playing:
		var tw = create_tween()
		tw.tween_property(a, "volume_db", -60.0, fade)
		tw.tween_callback(a, "stop")
	if sname == "":
		return
	b.stream = get_stream(sname)
	b.volume_db = -60.0
	b.play(randf() * 10.0)
	var tw2 = create_tween()
	tw2.tween_property(b, "volume_db", vol_db, fade)


func stop_ambient(fade := 0.3) -> void:
	for p in _amb:
		if p.playing:
			var tw = create_tween()
			tw.tween_property(p, "volume_db", -60.0, fade)
			tw.tween_callback(p, "stop")
	set_breath(0.0)
