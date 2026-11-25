extends SceneTree
## Probe: do Light2D shadows render into an offscreen Viewport on GLES2?
var vp
var n = 0

func _initialize():
	vp = Viewport.new()
	vp.size = Vector2(256, 256)
	vp.transparent_bg = false
	vp.render_target_update_mode = Viewport.UPDATE_ALWAYS
	vp.usage = Viewport.USAGE_2D
	root.add_child(vp)
	var cm = CanvasModulate.new()
	cm.color = Color(0, 0, 0)
	vp.add_child(cm)
	var bg = ColorRect.new()
	bg.rect_size = Vector2(256, 256)
	bg.color = Color(1, 1, 1)
	vp.add_child(bg)
	var img = Image.new()
	img.create(128, 128, false, Image.FORMAT_RGBA8)
	img.lock()
	for y in 128:
		for x in 128:
			var d = Vector2(x - 63.5, y - 63.5).length() / 64.0
			var v = clamp(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(v, v, v, 1))
	img.unlock()
	var tex = ImageTexture.new()
	tex.create_from_image(img)
	var l = Light2D.new()
	l.texture = tex
	l.texture_scale = 2.0
	l.position = Vector2(80, 128)
	l.mode = Light2D.MODE_ADD
	l.shadow_enabled = true
	l.shadow_filter = Light2D.SHADOW_FILTER_PCF13
	l.shadow_gradient_length = 4.0
	vp.add_child(l)
	var occ = LightOccluder2D.new()
	var op = OccluderPolygon2D.new()
	op.polygon = PoolVector2Array([Vector2(120, 100), Vector2(130, 100), Vector2(130, 160), Vector2(120, 160)])
	occ.occluder = op
	vp.add_child(occ)

func _idle(_d):
	n += 1
	if n == 6:
		var im = vp.get_texture().get_data()
		im.save_png(OS.get_cmdline_args()[-1])
		return true
	return false
