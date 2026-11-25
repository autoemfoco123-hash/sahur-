class_name Interactable
extends Area
## Something the player can look at and press [E] on. Calls target.method(binds...).

var prompt = "interact"
var target: Object
var method = ""
var binds = []
var once = true
var enabled = true


static func make(parent: Spatial, pos: Vector3, radius: float, text: String, tgt: Object, meth: String, b := [], use_once := true):
	var it = load("res://scripts/interactable.gd").new()
	it.prompt = text
	it.target = tgt
	it.method = meth
	it.binds = b
	it.once = use_once
	it.collision_layer = 4
	it.collision_mask = 0
	it.monitoring = false
	it.monitorable = true
	parent.add_child(it)
	it.global_transform.origin = pos
	var cs = CollisionShape.new()
	var sh = SphereShape.new()
	sh.radius = radius
	cs.shape = sh
	it.add_child(cs)
	return it


func use() -> void:
	if not enabled:
		return
	if once:
		enabled = false
	if target and is_instance_valid(target):
		target.callv(method, binds)
	if once:
		queue_free()
