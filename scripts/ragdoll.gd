extends Spatial
## A dead operative (Godot 3): the body comes apart into eleven rigid pieces (hips, torso, head,
## upper arms, forearms, thighs, shins) held together by joints with human limits, takes the hit
## and goes where physics sends it: across the room, into a wall, down. Every machine simulates
## its own copy (it is only for the eyes). After a while it is frozen in place, to cost nothing.

const OperativeModel = preload("res://scripts/operative_model.gd")

# piece -> [parent piece, mass, angular limits in degrees: x lo, x hi, y lo, y hi, z lo, z hi]
const PIECES = [
	["hips", "", 10.0, []],
	["torso", "hips", 16.0, [-35, 30, -30, 30, -22, 22]],
	["head", "torso", 4.5, [-45, 40, -60, 60, -25, 25]],
	["armL", "torso", 2.4, [-110, 110, -45, 45, -95, 40]],
	["armR", "torso", 2.4, [-110, 110, -45, 45, -40, 95]],
	["elbowL", "armL", 1.7, [0, 140, -5, 5, -5, 5]],
	["elbowR", "armR", 1.7, [0, 140, -5, 5, -5, 5]],
	["legL", "hips", 6.0, [-35, 105, -20, 20, -35, 20]],
	["legR", "hips", 6.0, [-35, 105, -20, 20, -20, 35]],
	["kneeL", "legL", 4.0, [-140, 0, -5, 5, -5, 5]],
	["kneeR", "legR", 4.0, [-140, 0, -5, 5, -5, 5]],
]

var bodies = {}
var _thud_cd = 0.0
var _life = 0.0


## at: feet position, yaw: facing, push: velocity the hit gives the body (m/s).
func build(world: Spatial, color: Color, at: Vector3, yaw: float, push: Vector3) -> void:
	world.add_child(self)
	var model = OperativeModel.build(color)
	add_child(model)
	model.global_transform = Transform(Basis(Vector3.UP, yaw), at)
	# a loose, falling pose to start from (not a mannequin standing straight)
	for n in ["armL", "armR"]:
		var a: Spatial = model.find_node(n, true, false)
		a.rotation = Vector3(rand_range(-0.4, 0.2), 0, (0.25 if n == "armL" else -0.25))
	var names = []
	for p in PIECES:
		names.append(p[0])
	# every piece becomes a body with its own meshes (and anything not a joint, like the nv-7)
	for p in PIECES:
		var pivot: Spatial = model.find_node(p[0], true, false)
		var rb = RigidBody.new()
		rb.name = p[0]
		rb.mass = p[2]
		rb.collision_layer = 0
		rb.collision_mask = Geo.LAYER_WORLD
		rb.linear_damp = 0.05
		rb.angular_damp = 0.9
		rb.can_sleep = true
		var pm = PhysicsMaterial.new()
		pm.friction = 0.85
		pm.bounce = 0.08
		rb.physics_material_override = pm
		add_child(rb)
		rb.global_transform = pivot.global_transform.orthonormalized()
		var aabb = AABB()
		var first = true
		for c in pivot.get_children():
			if c.name in names:
				continue
			var local: Transform = c.transform
			pivot.remove_child(c)
			rb.add_child(c)
			c.transform = local
			for mi in _meshes(c):
				var box: AABB = (rb.global_transform.affine_inverse() * mi.global_transform).xform(mi.get_aabb())
				aabb = box if first else aabb.merge(box)
				first = false
		var cs = CollisionShape.new()
		var sh = BoxShape.new()
		sh.extents = (aabb.size * 0.5 * 0.86) if not first else Vector3(0.05, 0.05, 0.05)
		cs.shape = sh
		rb.add_child(cs)
		cs.translation = aabb.position + aabb.size * 0.5 if not first else Vector3.ZERO
		bodies[p[0]] = rb
	# the joints, at each child piece's pivot, with human limits
	for p in PIECES:
		if p[1] == "":
			continue
		var child: RigidBody = bodies[p[0]]
		var parent: RigidBody = bodies[p[1]]
		var j = Generic6DOFJoint.new()
		add_child(j)
		j.global_transform = Transform(parent.global_transform.basis, child.global_transform.origin)
		j.set_node_a(j.get_path_to(parent))
		j.set_node_b(j.get_path_to(child))
		var lim: Array = p[3]
		for ax in 3:
			var lo = deg2rad(lim[ax * 2])
			var hi = deg2rad(lim[ax * 2 + 1])
			match ax:
				0:
					j.set_param_x(Generic6DOFJoint.PARAM_ANGULAR_LOWER_LIMIT, lo)
					j.set_param_x(Generic6DOFJoint.PARAM_ANGULAR_UPPER_LIMIT, hi)
				1:
					j.set_param_y(Generic6DOFJoint.PARAM_ANGULAR_LOWER_LIMIT, lo)
					j.set_param_y(Generic6DOFJoint.PARAM_ANGULAR_UPPER_LIMIT, hi)
				2:
					j.set_param_z(Generic6DOFJoint.PARAM_ANGULAR_LOWER_LIMIT, lo)
					j.set_param_z(Generic6DOFJoint.PARAM_ANGULAR_UPPER_LIMIT, hi)
	model.queue_free()
	# the hit: everything goes with it, the chest and hips take the most, and it tumbles
	var side = push.cross(Vector3.UP).normalized() if push.length() > 0.1 else Vector3.RIGHT
	for n in bodies:
		var rb: RigidBody = bodies[n]
		var k = 1.0
		if n == "torso":
			k = 1.15
		elif n == "head" or n.begins_with("arm") or n.begins_with("elbow"):
			k = 0.9 + randf() * 0.25
		rb.linear_velocity = push * k
	bodies["torso"].angular_velocity = side * push.length() * rand_range(0.6, 1.0) + Vector3(0, rand_range(-2.0, 2.0), 0)
	bodies["hips"].angular_velocity = side * push.length() * rand_range(0.3, 0.6)
	bodies["torso"].continuous_cd = true
	bodies["hips"].continuous_cd = true
	# the thud when it hits a wall or the floor
	bodies["torso"].contact_monitor = true
	bodies["torso"].contacts_reported = 2
	bodies["torso"].connect("body_entered", self, "_on_hit")


func _meshes(n: Node) -> Array:
	var out = []
	if n is MeshInstance:
		out.append(n)
	for c in n.get_children():
		out += _meshes(c)
	return out


func _on_hit(_b) -> void:
	var t: RigidBody = bodies.get("torso")
	if t == null or _thud_cd > 0.0:
		return
	var v = t.linear_velocity.length()
	if v > 1.6:
		_thud_cd = 0.25
		Audio.play_at("ev_thud", t.global_transform.origin, get_parent(), clamp(-14.0 + v * 2.2, -14.0, 4.0), rand_range(0.8, 1.0), 40.0)


func _physics_process(delta: float) -> void:
	_thud_cd -= delta
	_life += delta
	if _life > 12.0:
		# settled: freeze it where it lies
		for n in bodies:
			var rb: RigidBody = bodies[n]
			rb.mode = RigidBody.MODE_STATIC
		set_physics_process(false)


## The point the camera should look at.
func center() -> Vector3:
	var t = bodies.get("torso")
	return t.global_transform.origin if t else global_transform.origin
