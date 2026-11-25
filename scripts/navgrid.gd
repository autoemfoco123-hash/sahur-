class_name NavGrid
extends RefCounted
## Grid pathfinding for the brainrots (AStarGrid2D on the XZ plane).

var origin := Vector2.ZERO
var cell := 1.0
var w := 0
var h := 0
var astar := AStarGrid2D.new()
var margin := 0.35


func _init(min_xz: Vector2, max_xz: Vector2, cell_size := 1.0) -> void:
	origin = min_xz
	cell = cell_size
	w = int(ceil((max_xz.x - min_xz.x) / cell))
	h = int(ceil((max_xz.y - min_xz.y) / cell))
	astar.region = Rect2i(0, 0, w, h)
	astar.cell_size = Vector2(cell, cell)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()


func to_cell(p: Vector3) -> Vector2i:
	return Vector2i(clampi(int(floor((p.x - origin.x) / cell)), 0, w - 1), clampi(int(floor((p.z - origin.y) / cell)), 0, h - 1))


func to_world(c: Vector2i, y := 0.0) -> Vector3:
	return Vector3(origin.x + (c.x + 0.5) * cell, y, origin.y + (c.y + 0.5) * cell)


func block_box(center: Vector3, size: Vector3, rot_y := 0.0) -> void:
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	if absf(rot_y) > 0.01:
		var r := maxf(hx, hz)
		var c := absf(cos(rot_y))
		var s := absf(sin(rot_y))
		hx = minf(r, size.x * 0.5 * c + size.z * 0.5 * s)
		hz = minf(r, size.x * 0.5 * s + size.z * 0.5 * c)
	var a := to_cell(Vector3(center.x - hx - margin, 0, center.z - hz - margin))
	var b := to_cell(Vector3(center.x + hx + margin, 0, center.z + hz + margin))
	for x in range(a.x, b.x + 1):
		for y in range(a.y, b.y + 1):
			astar.set_point_solid(Vector2i(x, y), true)


func set_solid(c: Vector2i, solid: bool) -> void:
	if astar.is_in_boundsv(c):
		astar.set_point_solid(c, solid)


func is_open(p: Vector3) -> bool:
	var c := to_cell(p)
	return not astar.is_point_solid(c)


func nearest_open(c: Vector2i) -> Vector2i:
	if not astar.is_point_solid(c):
		return c
	for r in range(1, 8):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				var n := c + Vector2i(dx, dy)
				if astar.is_in_boundsv(n) and not astar.is_point_solid(n):
					return n
	return c


func path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var a := nearest_open(to_cell(from))
	var b := nearest_open(to_cell(to))
	var ids := astar.get_id_path(a, b)
	var out := PackedVector3Array()
	for i in range(1, ids.size()):
		out.append(to_world(ids[i], from.y))
	if out.size() > 0:
		out[out.size() - 1] = Vector3(to.x, from.y, to.z) if is_open(to) else out[out.size() - 1]
	return out


func random_open(rng: RandomNumberGenerator, y := 0.0) -> Vector3:
	for i in 200:
		var c := Vector2i(rng.randi_range(0, w - 1), rng.randi_range(0, h - 1))
		if not astar.is_point_solid(c):
			return to_world(c, y)
	return to_world(Vector2i(w / 2, h / 2), y)
