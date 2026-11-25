class_name Interactable
extends Area3D
## Something the player can look at and press [E] on.

var prompt := "Interact"
var action: Callable
var once := true
var enabled := true


static func make(parent: Node3D, pos: Vector3, radius: float, text: String, cb: Callable, use_once := true) -> Interactable:
	var it := Interactable.new()
	it.prompt = text
	it.action = cb
	it.once = use_once
	it.collision_layer = Geo.LAYER_INTERACT
	it.collision_mask = 0
	it.monitoring = false
	it.monitorable = true
	parent.add_child(it)
	it.global_position = pos
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = radius
	cs.shape = sh
	it.add_child(cs)
	return it


func use() -> void:
	if not enabled:
		return
	if once:
		enabled = false
	action.call()
	if once:
		queue_free()
