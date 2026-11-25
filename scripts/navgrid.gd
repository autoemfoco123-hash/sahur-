class_name NavGrid
extends Reference
## Grid pathfinding for the brainrots (AStar2D on the XZ plane). Godot 3.

var origin = Vector2.ZERO
var cell = 1.0
var w = 0
var h = 0
var astar = AStar2D.new()
var margin = 0.35
var _solid = {}


func _init(min_xz: Vector2, max_xz: Vector2, cell_size := 1.0) -> void:
	origin = min_xz
	cell = cell_size
	w = int(ceil((max_xz.x - min_xz.x) / cell))
	h = int(ceil((max_xz.y - min_xz.y) / cell))
	for y in h:
		for x in w:
			astar.add_point(y * w + x, Vector2(x, y))
	for y in h:
		for x in w:
			var id = y * w + x
			if x + 1 < w:
				astar.connect_points(id, id + 1)
			if y + 1 < h:
				astar.connect_points(id, id + w)
				if x + 1 < w:
					astar.connect_points(id, id + w + 1)
				if x > 0:
					astar.connect_points(id, id + w - 1)


func to_cell(p: Vector3) -> Vector2:
	return Vector2(clamp(floor((p.x - origin.x) / cell), 0, w - 1), clamp(floor((p.z - origin.y) / cell), 0, h - 1))


func to_world(c: Vector2, y := 0.0) -> Vector3:
	return Vector3(origin.x + (c.x + 0.5) * cell, y, origin.y + (c.y + 0.5) * cell)


func _id(c: Vector2) -> int:
	return int(c.y) * w + int(c.x)


func block_box(center: Vector3, size: Vector3) -> void:
	var a = to_cell(Vector3(center.x - size.x * 0.5 - margin, 0, center.z - size.z * 0.5 - margin))
	var b = to_cell(Vector3(center.x + size.x * 0.5 + margin, 0, center.z + size.z * 0.5 + margin))
	for x in range(int(a.x), int(b.x) + 1):
		for y in range(int(a.y), int(b.y) + 1):
			var id = y * w + x
			_solid[id] = true
			astar.set_point_disabled(id, true)


func is_open(p: Vector3) -> bool:
	return not _solid.has(_id(to_cell(p)))


func nearest_open(c: Vector2) -> Vector2:
	if not _solid.has(_id(c)):
		return c
	for r in range(1, 8):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				var n = c + Vector2(dx, dy)
				if n.x >= 0 and n.y >= 0 and n.x < w and n.y < h and not _solid.has(_id(n)):
					return n
	return c


func path(from: Vector3, to: Vector3) -> PoolVector3Array:
	var a = nearest_open(to_cell(from))
	var b = nearest_open(to_cell(to))
	var ids = astar.get_id_path(_id(a), _id(b))
	var out = PoolVector3Array()
	for i in range(1, ids.size()):
		var pt = astar.get_point_position(ids[i])
		out.append(to_world(pt, from.y))
	if out.size() > 0 and is_open(to):
		out[out.size() - 1] = Vector3(to.x, from.y, to.z)
	return out


func random_open(rng: RandomNumberGenerator, y := 0.0) -> Vector3:
	for i in 200:
		var c = Vector2(rng.randi_range(0, w - 1), rng.randi_range(0, h - 1))
		if not _solid.has(_id(c)):
			return to_world(c, y)
	return to_world(Vector2(w / 2, h / 2), y)
