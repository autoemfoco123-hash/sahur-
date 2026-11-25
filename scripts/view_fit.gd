extends ViewportContainer
## Holds the 3D view. The UI scales with the window (stretch mode 2d / expand), but the
## 3D view renders at the real window resolution: full on low/high, half on potato.
## The mouse passes straight through (mouse look is read in Game, not here).

const MAX_H = [540, 1080, 2160]  # render height cap per graphics level


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stretch = true
	get_tree().root.connect("size_changed", self, "_queue_fit")
	Game.connect("settings_changed", self, "_queue_fit")
	_queue_fit()


func _queue_fit() -> void:
	call_deferred("_fit")


func _fit() -> void:
	var vp = get_child(0) as Viewport
	if vp == null:
		return
	var q = int(clamp(int(Game.settings.gfx), 0, 2))
	var px: Vector2 = get_tree().root.size
	var div = max(2.0 if q == 0 else 1.0, px.y / MAX_H[q])
	stretch_shrink = 2 if q == 0 else 1
	vp.size = Vector2(max(64.0, floor(px.x / div)), max(64.0, floor(px.y / div)))
