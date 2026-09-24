extends Node2D
## Draws the drill field around the camera: sky, parallax hills, ground per level,
## all 15 obstacles, mud, camp props, the finish arch and every cadet.

const G := Course.GROUND_Y
const WOOD := Color("8b5a2b")
const WOOD_DARK := Color("5e3b1a")
const METAL := Color("6f7479")
const ROPE := Color("c8a96a")

var cam_x := 0.0
var view_w := 1600.0
## Array of racer dictionaries (see race.gd) drawn back-to-front.
var racers: Array = []
var font: Font


func _ready() -> void:
	font = ThemeDB.fallback_font


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var l := cam_x - view_w * 0.75
	var r := cam_x + view_w * 0.75
	var lvl := Course.level_at(cam_x)
	var sky: Color = Course.LEVELS[lvl].sky
	# sky with a soft horizon band
	draw_rect(Rect2(l, G - 1400, r - l, 1000), sky.darkened(0.08))
	for i in 10: # soft gradient towards the horizon
		draw_rect(Rect2(l, G - 400 + i * 40, r - l, 41), sky.darkened(0.08).lerp(sky.lerp(Color.WHITE, 0.3), i / 9.0))
	_draw_hills(l, r, lvl)
	# ground (blend colour per level)
	for i in 3:
		var a := -1e6 if i == 0 else Course.obstacle_x(i * 5) - Course.OBSTACLE_SPACING * 0.5
		var b := 1e6 if i == 2 else Course.obstacle_x(i * 5 + 5) - Course.OBSTACLE_SPACING * 0.5
		var gl := maxf(a, l)
		var gr := minf(b, r)
		if gr > gl:
			var gc: Color = Course.LEVELS[i].ground
			draw_rect(Rect2(gl, G, gr - gl, 700), gc)
			draw_rect(Rect2(gl, G, gr - gl, 10), gc.lightened(0.15))
	# parade-ground chalk dashes
	var d := floorf(l / 120.0) * 120.0
	while d < r:
		draw_line(Vector2(d, G + 60), Vector2(d + 60, G + 60), Color(1, 1, 1, 0.25), 3)
		d += 120.0
	_draw_props(l, r)
	for i in Course.OBSTACLE_COUNT:
		var x0 := Course.obstacle_x(i)
		if x0 + 260 > l and x0 - 60 < r:
			_draw_obstacle(i, x0)
	_draw_finish(l, r)
	for rc in racers:
		if not rc.me and rc.x > l - 100 and rc.x < r + 100:
			_draw_racer(rc)
	for rc in racers:
		if rc.me:
			_draw_racer(rc)


func _draw_hills(l: float, r: float, lvl: int) -> void:
	# far hills move at 30% of camera speed, near trees at 60%
	var far := Color(0.45, 0.55, 0.45, 0.6) if lvl < 2 else Color(0.62, 0.5, 0.38, 0.6)
	var near := Color(0.3, 0.42, 0.25, 0.8)
	for layer in [[0.7, 520.0, 170.0, far], [0.4, 330.0, 90.0, near]]:
		var k: float = layer[0]
		var span: float = layer[1]
		var hgt: float = layer[2]
		var off := cam_x * k
		var start := floorf((l - off) / span) * span
		var x := start
		var pts := PackedVector2Array([Vector2(l, G)])
		while x < r - off + span:
			var wx := x + off
			var h := hgt * (0.6 + 0.4 * sin(x * 0.013) * cos(x * 0.007))
			pts.append(Vector2(wx, G - h))
			pts.append(Vector2(wx + span * 0.5, G - h * 0.55))
			x += span
		pts.append(Vector2(r, G))
		draw_colored_polygon(pts, layer[3])


func _draw_props(l: float, r: float) -> void:
	# start line + NCC flagpole
	if l < 300:
		draw_rect(Rect2(40, G - 4, 10, 60), Color.WHITE)
		_text(Vector2(-40, G + 110), "START", 36, Color.WHITE)
		_flag(Vector2(-160, G))
	# level boards
	for i in 3:
		var bx := 180.0 if i == 0 else Course.obstacle_x(i * 5) - 520.0
		if bx > l - 300 and bx < r + 300:
			draw_rect(Rect2(bx - 8, G - 150, 10, 150), WOOD_DARK)
			draw_rect(Rect2(bx + 162, G - 150, 10, 150), WOOD_DARK)
			draw_rect(Rect2(bx - 20, G - 230, 210, 90), Color("2f3515"))
			draw_rect(Rect2(bx - 20, G - 230, 210, 90), Color("d4a017"), false, 4)
			_text(Vector2(bx - 8, G - 200), "SECTION %d" % (i + 1), 26, Color("d4a017"))
			_text(Vector2(bx - 8, G - 166), Course.LEVELS[i].sub.to_upper(), 18, Color.WHITE)
	# mud patches (level 2)
	for i in range(5, 10):
		var mx := Course.obstacle_x(i) + Course.OBSTACLE_PASS_WIDTH + 250.0
		if mx + 260 > l and mx < r:
			draw_colored_polygon(_ellipse(Vector2(mx + 130, G + 8), Vector2(140, 18)), Color("4a3520"))
			draw_colored_polygon(_ellipse(Vector2(mx + 110, G + 6), Vector2(60, 7)), Color("6b4f2f"))
			_text(Vector2(mx + 90, G + 50), "MUD", 18, Color(1, 1, 1, 0.5))
	# camp tents (level 3 backdrop)
	var tx := Course.obstacle_x(10) - 300.0
	while tx < Course.FINISH_X + 400:
		if tx > l - 200 and tx < r + 200:
			var base := G - 2
			draw_colored_polygon(PackedVector2Array([Vector2(tx, base), Vector2(tx + 70, base - 80), Vector2(tx + 140, base)]), Color("556b2f"))
			draw_colored_polygon(PackedVector2Array([Vector2(tx + 55, base), Vector2(tx + 70, base - 40), Vector2(tx + 85, base)]), Color("2f3515"))
		tx += 690.0


func _flag(at: Vector2) -> void:
	draw_line(at, at + Vector2(0, -260), Color("bbbbbb"), 5)
	var t := Time.get_ticks_msec() / 400.0
	for i in 3:
		var c: Color = [Color("ff9933"), Color.WHITE, Color("138808")][i]
		var pts := PackedVector2Array()
		for j in 9:
			var x := j * 12.0
			pts.append(at + Vector2(x, -255 + i * 20 + sin(t + j * 0.6) * 3.0))
		for j in range(8, -1, -1):
			var x := j * 12.0
			pts.append(at + Vector2(x, -235 + i * 20 + sin(t + j * 0.6) * 3.0))
		draw_colored_polygon(pts, c)
	draw_arc(at + Vector2(48, -225), 7, 0, TAU, 16, Color("000080"), 1.5)


func _draw_obstacle(i: int, x0: float) -> void:
	var kind: String = Course.OBSTACLES[i].kind
	# number plate
	draw_rect(Rect2(x0 - 30, G - 70, 4, 70), WOOD_DARK)
	draw_circle(Vector2(x0 - 28, G - 84), 18, Color("d4a017"))
	_text(Vector2(x0 - 28 - (6 if i < 9 else 12), G - 76), str(i + 1), 20, Color("1f2a44"))
	match kind:
		"balance":
			_posts(x0, x0 + 200, 30)
			draw_rect(Rect2(x0 - 10, G - 36, 220, 10), WOOD)
		"timing":
			_posts(x0 + 90, x0 + 110, 62)
			draw_rect(Rect2(x0 + 80, G - 64, 40, 8), Color("e74c3c"))
			draw_rect(Rect2(x0 + 92, G - 64, 8, 8), Color.WHITE)
		"tilt":
			var pts := PackedVector2Array([Vector2(x0, G - 26), Vector2(x0 + 60, G - 34), Vector2(x0 + 120, G - 22), Vector2(x0 + 200, G - 32)])
			draw_polyline(pts, WOOD, 10)
			for p in pts:
				draw_line(p, Vector2(p.x, G), WOOD_DARK, 5)
		"crawl":
			_posts(x0, x0 + 200, 44)
			var wire := PackedVector2Array()
			for j in 21:
				wire.append(Vector2(x0 + j * 10, G - 42 + (4 if j % 2 == 0 else -4)))
			draw_polyline(wire, METAL, 2)
			for j in 10:
				var p := Vector2(x0 + 10 + j * 20, G - 42)
				draw_line(p + Vector2(-4, -4), p + Vector2(4, 4), METAL, 2)
				draw_line(p + Vector2(-4, 4), p + Vector2(4, -4), METAL, 2)
		"mash":
			draw_colored_polygon(PackedVector2Array([Vector2(x0, G), Vector2(x0 + 150, G - 120), Vector2(x0 + 170, G - 120), Vector2(x0 + 200, G)]), WOOD)
			for j in 6:
				var t := j / 6.0
				draw_line(Vector2(x0 + 150 * t, G - 120 * t), Vector2(x0 + 150 * t + 8, G - 120 * t - 6), WOOD_DARK, 3)
		"gate":
			draw_rect(Rect2(x0 + 80, G - 110, 8, 110), METAL)
			draw_rect(Rect2(x0 + 122, G - 110, 8, 110), METAL)
			draw_rect(Rect2(x0 + 80, G - 76, 50, 8), Color("d4a017"))
			draw_rect(Rect2(x0 + 80, G - 110, 50, 6), METAL)
		"vault_r", "vault_l":
			draw_rect(Rect2(x0 + 70, G - 64, 60, 64), WOOD)
			draw_rect(Rect2(x0 + 70, G - 64, 60, 10), WOOD_DARK)
			_text(Vector2(x0 + 90, G - 22), "R" if kind == "vault_r" else "L", 26, Color("d4a017"))
		"steps":
			for j in 3:
				draw_rect(Rect2(x0 + 20 + j * 55, G - 28 * (j + 1), 55, 28 * (j + 1)), WOOD if j % 2 == 0 else WOOD_DARK)
		"alternate":
			_posts(x0, x0 + 200, 160)
			draw_rect(Rect2(x0 - 10, G - 166, 222, 10), METAL)
			for j in 10:
				draw_line(Vector2(x0 + j * 22, G - 166), Vector2(x0 + j * 22, G - 156), Color("444444"), 2)
		"wall":
			draw_rect(Rect2(x0 + 90, G - 128, 34, 128), Color("9e8e7a"))
			for j in 6:
				draw_line(Vector2(x0 + 90, G - 21 * j), Vector2(x0 + 124, G - 21 * j), Color("7f705e"), 2)
			draw_rect(Rect2(x0 + 86, G - 132, 42, 8), WOOD_DARK)
			_text(Vector2(x0 + 76, G - 144), "6 FT", 18, Color.WHITE)
		"ditch":
			for a in [20.0, 120.0]:
				draw_rect(Rect2(x0 + a, G, 62, 46), Color("2b1d10"))
				draw_rect(Rect2(x0 + a, G + 30, 62, 16), Color("3a6ea5"))
		"rope":
			draw_rect(Rect2(x0 + 50, G - 270, 8, 270), WOOD_DARK)
			draw_rect(Rect2(x0 + 150, G - 270, 8, 270), WOOD_DARK)
			draw_rect(Rect2(x0 + 44, G - 276, 120, 10), WOOD)
			var sway := sin(Time.get_ticks_msec() / 700.0) * 4.0
			draw_line(Vector2(x0 + 104, G - 266), Vector2(x0 + 104 + sway, G - 6), ROPE, 5)
		"net":
			var top := Vector2(x0 + 100, G - 210)
			draw_line(Vector2(x0, G), top, WOOD_DARK, 7)
			draw_line(Vector2(x0 + 200, G), top, WOOD_DARK, 7)
			for j in 9:
				var t := j / 9.0
				draw_line(Vector2(x0, G).lerp(top, t), Vector2(x0 + 200, G).lerp(top, t), ROPE, 2)
			for j in 9:
				var t := j / 8.0
				draw_line(Vector2(x0 + 200 * t, G), top, ROPE, 2)
		"sprint":
			draw_rect(Rect2(x0, G - 4, 12, 60), Color.WHITE)
			_text(Vector2(x0 - 30, G + 110), "SPRINT!", 30, Color("d4a017"))


func _posts(a: float, b: float, h: float) -> void:
	draw_rect(Rect2(a - 4, G - h, 8, h), WOOD_DARK)
	draw_rect(Rect2(b - 4, G - h, 8, h), WOOD_DARK)


func _draw_finish(l: float, r: float) -> void:
	var fx := Course.FINISH_X
	if fx < l - 200 or fx > r + 200:
		return
	# chequered strip
	for j in 8:
		draw_rect(Rect2(fx + (j % 2) * 12, G + j * 8, 12, 8), Color.BLACK)
		draw_rect(Rect2(fx + ((j + 1) % 2) * 12, G + j * 8, 12, 8), Color.WHITE)
	draw_rect(Rect2(fx - 80, G - 240, 14, 240), Color("1f2a44"))
	draw_rect(Rect2(fx + 90, G - 240, 14, 240), Color("1f2a44"))
	draw_rect(Rect2(fx - 90, G - 290, 204, 60), Color("d4a017"))
	_text(Vector2(fx - 70, G - 248), "FINISH", 36, Color("1f2a44"))
	draw_line(Vector2(fx - 66, G - 70), Vector2(fx + 90, G - 70), Color("e74c3c"), 3)
	_flag(Vector2(fx + 200, G))


func _draw_racer(rc: Dictionary) -> void:
	var feet: Vector2 = rc.pos
	var alpha := 1.0 if rc.me else 0.55
	var scale := 1.0 if rc.me else 0.9
	if rc.get("aura", false):
		draw_circle(feet + Vector2(0, -55), 70, Color(0.83, 0.63, 0.1, 0.18))
	if rc.me:
		draw_colored_polygon(_ellipse(Vector2(feet.x, G + 2), Vector2(26, 5)), Color(0, 0, 0, 0.25))
	CadetArt.draw(self, feet, rc.look, rc.phase, rc.pose, rc.gear, alpha, scale)
	var tag: String = rc.name
	var c: Color = rc.color
	if rc.get("done", false):
		tag += " ✔"
	var w := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	var at := feet + Vector2(-w * 0.5, -132 * scale - (0.0 if rc.me else rc.get("tag", 0.0)))
	draw_rect(Rect2(at + Vector2(-6, -16), Vector2(w + 12, 22)), Color(0, 0, 0, 0.45 if rc.me else 0.3))
	draw_string(font, at, tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, c)


func _text(at: Vector2, t: String, size: int, c: Color) -> void:
	draw_string_outline(font, at, t, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, 0.5))
	draw_string(font, at, t, HORIZONTAL_ALIGNMENT_LEFT, -1, size, c)


func _ellipse(c: Vector2, r: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 20:
		pts.append(c + Vector2(cos(i * TAU / 20) * r.x, sin(i * TAU / 20) * r.y))
	return pts
