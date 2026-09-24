extends Control
## Level 3 - Map Reading. The instructor gives 5 clues (grid references,
## "from the Temple go 3 North, 2 East", compass bearings); tap the exact
## square on the map. Quick correct answers score up to 10 each (max 50).
## The map and clues come from a shared seed, so the whole squad gets the same.

signal level_done(score: int)

const StageBoard := preload("res://scripts/screens/stage_board.gd")
const COLS := 8
const ROWS := 6
const EAST0 := 10
const NORTH0 := 20
const CLUES := 5
const CLUE_TIME := 25.0
const LANDMARKS := ["Temple", "Well", "School", "Water Tank", "Post Office", "Hospital",
	"Railway Station", "Banyan Tree", "Camp HQ", "Pond"]
const DIRS := {
	"North": Vector2i(0, 1), "South": Vector2i(0, -1), "East": Vector2i(1, 0), "West": Vector2i(-1, 0),
	"North-East": Vector2i(1, 1), "North-West": Vector2i(-1, 1), "South-East": Vector2i(1, -1), "South-West": Vector2i(-1, -1),
}

var main: Node
var data: Dictionary
var mode := "practice"
var rng := RandomNumberGenerator.new()
var river: Array[float] = [] ## river x (in columns) per row, bottom to top
var road_row := 2
var places := {} ## name -> Vector2i cell (col, row from bottom)
var trees: Array = []
var hills: Array = []
var clues: Array = [] ## {text, cell}
var clue_i := 0
var clue_t := 0.0
var attempts := 0
var score := 0
var marks := {} ## Vector2i -> Color flash
var mark_t := 0.0
var reveal := false
var finished := false
var font: Font
var clue_label: Label
var status_label: Label
var result_line := ""
var _autopilot := OS.get_cmdline_user_args().has("--autopilot")


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	font = ThemeDB.fallback_font
	mode = data.get("mode", "practice")
	rng.seed = int(data.get("seed", randi()))
	_generate_map()
	_generate_clues()
	Sfx.music(false)
	clue_label = UI.label("", 22, Color("1f2a44"))
	clue_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	clue_label.remove_theme_constant_override("outline_size")
	add_child(clue_label)
	status_label = UI.label("", 20, UI.WHITE)
	add_child(status_label)
	if mode == "spectate":
		finished = true
		_show_board()
		return
	_start_clue()


# ---- map + clue generation ------------------------------------------------------

func _generate_map() -> void:
	var x := rng.randf_range(2.8, 5.2)
	for r in ROWS:
		river.append(x)
		x = clampf(x + rng.randf_range(-0.7, 0.7), 1.6, COLS - 1.6)
	road_row = rng.randi_range(1, ROWS - 2)
	var taken := {}
	for r in ROWS: # river squares are not usable for landmarks
		taken[Vector2i(int(river[r]), r)] = true
	places["Bridge"] = Vector2i(int(river[road_row]), road_row)
	var free: Array[Vector2i] = []
	for c in COLS:
		for r in ROWS:
			if not taken.has(Vector2i(c, r)):
				free.append(Vector2i(c, r))
	_shuffle(free)
	var names := LANDMARKS.duplicate()
	_shuffle(names)
	for i in 7:
		places[names[i]] = free[i]
	places["Hill Top"] = free[7]
	hills = [free[7], free[8]]
	for i in 26:
		trees.append(Vector2(rng.randf_range(0.1, COLS - 0.1), rng.randf_range(0.1, ROWS - 0.1)))


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = a[i]
		a[i] = a[j]
		a[j] = tmp


func _grid(cell: Vector2i) -> String:
	return "%d%d" % [EAST0 + cell.x, NORTH0 + cell.y]


func _inside(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < COLS and c.y >= 0 and c.y < ROWS


func _landmark_names() -> Array:
	var n := places.keys()
	n.sort()
	return n


func _generate_clues() -> void:
	var names := _landmark_names()
	# 1: read the map symbols
	var first: String = names[rng.randi_range(0, names.size() - 1)]
	clues.append({"text": "Cadet! Find the %s on your map." % first, "cell": places[first]})
	# 2: 4-figure grid reference
	var g := Vector2i(rng.randi_range(0, COLS - 1), rng.randi_range(0, ROWS - 1))
	clues.append({"text": "Report to grid reference %s. Eastings first, then northings." % _grid(g), "cell": g})
	# 3 and 5: move N/S then E/W from a landmark; 4: compass direction
	for kind in ["steps", "bearing", "steps"]:
		for attempt in 100:
			var from: String = names[rng.randi_range(0, names.size() - 1)]
			var base: Vector2i = places[from]
			if kind == "steps":
				var dy := rng.randi_range(-3, 3)
				var dx := rng.randi_range(-3, 3)
				var target := base + Vector2i(dx, dy)
				if (dx == 0 and dy == 0) or not _inside(target):
					continue
				var parts := PackedStringArray()
				if dy != 0:
					parts.append("%d square%s %s" % [absi(dy), "" if absi(dy) == 1 else "s", "North" if dy > 0 else "South"])
				if dx != 0:
					parts.append("%d square%s %s" % [absi(dx), "" if absi(dx) == 1 else "s", "East" if dx > 0 else "West"])
				clues.append({"text": "From the %s, go %s." % [from, " and then ".join(parts)], "cell": target})
				break
			else:
				var dname: String = DIRS.keys()[rng.randi_range(4, 7)]
				var k := rng.randi_range(1, 2)
				var target: Vector2i = base + DIRS[dname] * k
				if not _inside(target):
					continue
				clues.append({"text": "The enemy scout is hiding %d square%s %s of the %s. Find that square!" % [k, "" if k == 1 else "s", dname, from], "cell": target})
				break
	while clues.size() < CLUES: # fallback (tiny chance): another grid reference
		var c := Vector2i(rng.randi_range(0, COLS - 1), rng.randi_range(0, ROWS - 1))
		clues.append({"text": "Report to grid reference %s." % _grid(c), "cell": c})


# ---- flow -------------------------------------------------------------------------

func _start_clue() -> void:
	clue_t = 0.0
	attempts = 0
	reveal = false
	var text: String = clues[clue_i].text
	clue_label.text = text
	Sfx.speak(text)
	Sfx.play("whistle")


func _answer(cell: Vector2i) -> void:
	if finished or reveal:
		return
	var target: Vector2i = clues[clue_i].cell
	if cell == target:
		var pts := 4
		if attempts == 0:
			pts = 10 if clue_t <= 8.0 else maxi(5, 10 - int((clue_t - 8.0) / 3.5))
		score += pts
		result_line = "CORRECT! +%d" % pts
		marks = {cell: UI.GREEN_OK}
		mark_t = 1.2
		Sfx.play("good")
		_next_after(1.2)
	else:
		attempts += 1
		marks = {cell: UI.RED}
		mark_t = 0.8
		Sfx.play("bad")
		Input.vibrate_handheld(60)
		if attempts >= 2:
			_reveal()
		else:
			result_line = "Wrong square - one more try!"


func _reveal() -> void:
	reveal = true
	result_line = "The answer was grid %s" % _grid(clues[clue_i].cell)
	marks[clues[clue_i].cell] = UI.GOLD
	mark_t = 2.2
	_next_after(2.2)


func _next_after(secs: float) -> void:
	reveal = true
	await get_tree().create_timer(secs).timeout
	if not is_inside_tree():
		return
	clue_i += 1
	result_line = ""
	if clue_i >= CLUES:
		_finish()
	else:
		_start_clue()


func _finish() -> void:
	finished = true
	clue_label.text = "Map reading complete: %d / 50" % score
	if score >= 30:
		Sfx.say("good")
	await get_tree().create_timer(2.5).timeout
	if not is_inside_tree():
		return
	if mode == "online":
		Net.send({"t": "score", "stage": "map", "score": score})
		_show_board()
	else:
		level_done.emit(score)


func _show_board() -> void:
	var board := StageBoard.new()
	board.stage = "map"
	add_child(UI.centered(board))


func _process(d: float) -> void:
	mark_t = maxf(0.0, mark_t - d)
	if _autopilot and not finished and not reveal and clue_t > 1.5:
		_answer(clues[clue_i].cell)
	if not finished and not reveal:
		clue_t += d
		if clue_t >= CLUE_TIME:
			Sfx.play("bad")
			_reveal()
	_layout_labels()
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cell := _cell_at(event.position)
		if _inside(cell):
			_answer(cell)


# ---- layout + drawing ----------------------------------------------------------------

func _cell_size() -> float:
	return floorf(minf((size.x * 0.6 - 70.0) / COLS, (size.y - 120.0) / ROWS))


func _origin() -> Vector2:
	return Vector2(56, 74)


func _cell_rect(c: Vector2i) -> Rect2:
	var s := _cell_size()
	return Rect2(_origin() + Vector2(c.x * s, (ROWS - 1 - c.y) * s), Vector2(s, s))


func _cell_at(p: Vector2) -> Vector2i:
	var s := _cell_size()
	var q := (p - _origin()) / s
	if q.x < 0 or q.y < 0:
		return Vector2i(-1, -1)
	return Vector2i(int(q.x), ROWS - 1 - int(q.y))


func _to_px(col: float, row_from_bottom: float) -> Vector2:
	var s := _cell_size()
	return _origin() + Vector2(col * s, (ROWS - row_from_bottom) * s)


func _panel_x() -> float:
	return _origin().x + _cell_size() * COLS + 36.0


func _layout_labels() -> void:
	var px := _panel_x()
	clue_label.position = Vector2(px + 26, 150)
	clue_label.size = Vector2(size.x - px - 60, 150)
	status_label.position = Vector2(px + 10, size.y - 150)
	status_label.size = Vector2(size.x - px - 20, 120)
	var left := maxf(0.0, CLUE_TIME - clue_t)
	status_label.text = "Clue %d / %d     Time %ds\nScore %d / 50\n%s" % [mini(clue_i + 1, CLUES), CLUES, ceili(left), score, result_line] if not finished else "Score %d / 50" % score


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("2f3515"))
	var s := _cell_size()
	var o := _origin()
	var map_rect := Rect2(o, Vector2(s * COLS, s * ROWS))
	draw_rect(map_rect.grow(6), Color("c8b88a"))
	draw_rect(map_rect, Color("e9e2c4"))
	for h in hills: # contour rings
		var hc := _to_px(h.x + 0.5, h.y + 0.5)
		for k in 4:
			draw_arc(hc, s * (0.18 + k * 0.14), 0, TAU, 32, Color(0.55, 0.4, 0.2, 0.6), 1.5)
	for tr in trees:
		var tp := _to_px(tr.x, tr.y)
		draw_circle(tp, 5, Color(0.3, 0.55, 0.25, 0.7))
	# river
	var pts := PackedVector2Array()
	for r in ROWS:
		pts.append(_to_px(river[r], r + 0.5))
	pts.insert(0, _to_px(river[0], 0))
	pts.append(_to_px(river[ROWS - 1], ROWS))
	draw_polyline(pts, Color("5a9bd4"), s * 0.22, true)
	# road
	var rp := PackedVector2Array()
	for c in COLS + 1:
		rp.append(_to_px(c, road_row + 0.5 + sin(c * 1.3) * 0.12))
	draw_polyline(rp, Color("8c7b5a"), 7, true)
	draw_polyline(rp, Color("d9c79a"), 3, true)
	# grid lines + numbers
	for c in COLS + 1:
		draw_line(o + Vector2(c * s, 0), o + Vector2(c * s, s * ROWS), Color(0.2, 0.3, 0.6, 0.55), 1.5)
	for r in ROWS + 1:
		draw_line(o + Vector2(0, r * s), o + Vector2(s * COLS, r * s), Color(0.2, 0.3, 0.6, 0.55), 1.5)
	for c in COLS:
		_center_text(o + Vector2(c * s + s * 0.5, s * ROWS + 26), str(EAST0 + c), 18, UI.WHITE)
		_center_text(o + Vector2(c * s + s * 0.5, -10), str(EAST0 + c), 16, UI.KHAKI_LIGHT)
	for r in ROWS:
		_center_text(o + Vector2(-26, (ROWS - 1 - r) * s + s * 0.5 + 6), str(NORTH0 + r), 18, UI.WHITE)
	# north arrow
	var na := o + Vector2(s * COLS - 26, 30)
	draw_colored_polygon(PackedVector2Array([na + Vector2(0, -18), na + Vector2(9, 10), na + Vector2(0, 4), na + Vector2(-9, 10)]), Color("1f2a44"))
	_center_text(na + Vector2(0, 30), "N", 16, Color("1f2a44"))
	for name in places:
		_draw_place(name, places[name])
	if mark_t > 0.0:
		for cell in marks:
			var rr := _cell_rect(cell)
			draw_rect(rr, Color(marks[cell], 0.35 * minf(1.0, mark_t * 2.0)))
			draw_rect(rr, marks[cell], false, 4)
	# instructor panel
	var px := _panel_x()
	_center_text(Vector2((px + size.x) * 0.5, 40), "LEVEL 3 - MAP READING", 26, UI.GOLD)
	CadetArt.draw(self, Vector2(px + 60, 140), {"uniform": "army", "beret": "black", "badge": "star"}, 0.0, "idle", false, 1.0, 0.9)
	_center_text(Vector2(px + 60, 158), "Instructor", 14, UI.KHAKI_LIGHT)
	var bubble := Rect2(px + 14, 136, size.x - px - 30, 170)
	draw_rect(bubble, Color("f7f3e8"))
	draw_rect(bubble, UI.GOLD, false, 3)
	draw_colored_polygon(PackedVector2Array([Vector2(px + 60, 118), Vector2(px + 44, 138), Vector2(px + 80, 138)]), Color("f7f3e8"))
	if not finished:
		var k := clampf(1.0 - clue_t / CLUE_TIME, 0.0, 1.0)
		draw_rect(Rect2(px + 14, bubble.end.y + 8, bubble.size.x * k, 8), UI.GOLD if k > 0.3 else UI.RED)
	draw_string(font, Vector2(px + 14, bubble.end.y + 44), "Grid ref = Easting (across) + Northing (up)", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UI.KHAKI_LIGHT)


func _draw_place(name: String, cell: Vector2i) -> void:
	var r := _cell_rect(cell)
	var c := r.get_center() + Vector2(0, -6)
	var u := r.size.x * 0.16
	match name:
		"Temple":
			draw_rect(Rect2(c + Vector2(-u, -u * 0.2), Vector2(u * 2, u * 1.2)), Color("e67e22"))
			draw_colored_polygon(PackedVector2Array([c + Vector2(-u * 1.2, -u * 0.2), c + Vector2(0, -u * 1.6), c + Vector2(u * 1.2, -u * 0.2)]), Color("d35400"))
		"Well":
			draw_arc(c, u, 0, TAU, 24, Color("2c3e50"), 4)
			draw_circle(c, u * 0.6, Color("5a9bd4"))
		"School":
			draw_rect(Rect2(c + Vector2(-u * 1.1, -u * 0.3), Vector2(u * 2.2, u * 1.3)), Color("f1c40f"))
			draw_colored_polygon(PackedVector2Array([c + Vector2(-u * 1.3, -u * 0.3), c + Vector2(0, -u * 1.3), c + Vector2(u * 1.3, -u * 0.3)]), Color("c0392b"))
		"Water Tank":
			draw_rect(Rect2(c + Vector2(-u, -u * 1.3), Vector2(u * 2, u)), Color("7f8c8d"))
			draw_line(c + Vector2(-u * 0.7, -u * 0.3), c + Vector2(-u, u), Color("2c3e50"), 3)
			draw_line(c + Vector2(u * 0.7, -u * 0.3), c + Vector2(u, u), Color("2c3e50"), 3)
		"Post Office":
			draw_rect(Rect2(c + Vector2(-u, -u), Vector2(u * 2, u * 2)), Color("c0392b"))
			_center_text(c + Vector2(0, u * 0.35), "PO", int(u * 1.1), Color.WHITE)
		"Hospital":
			draw_rect(Rect2(c + Vector2(-u, -u), Vector2(u * 2, u * 2)), Color.WHITE)
			draw_rect(Rect2(c + Vector2(-u * 0.25, -u * 0.8), Vector2(u * 0.5, u * 1.6)), Color("e74c3c"))
			draw_rect(Rect2(c + Vector2(-u * 0.8, -u * 0.25), Vector2(u * 1.6, u * 0.5)), Color("e74c3c"))
		"Railway Station":
			draw_rect(Rect2(c + Vector2(-u * 1.3, -u * 0.6), Vector2(u * 2.6, u * 1.2)), Color("34495e"))
			for i in 5:
				draw_line(c + Vector2(-u * 1.2 + i * u * 0.6, -u * 0.6), c + Vector2(-u * 1.2 + i * u * 0.6, u * 0.6), Color.WHITE, 2)
		"Banyan Tree":
			draw_rect(Rect2(c + Vector2(-u * 0.2, 0), Vector2(u * 0.4, u)), Color("6e4b2a"))
			draw_circle(c + Vector2(0, -u * 0.3), u * 1.1, Color("27ae60"))
		"Camp HQ":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-u * 1.2, u * 0.8), c + Vector2(0, -u * 0.8), c + Vector2(u * 1.2, u * 0.8)]), Color("556b2f"))
			draw_line(c + Vector2(0, -u * 0.8), c + Vector2(0, -u * 1.8), Color.BLACK, 2)
			draw_rect(Rect2(c + Vector2(0, -u * 1.8), Vector2(u * 0.8, u * 0.5)), Color("ff9933"))
		"Pond":
			var pts := PackedVector2Array()
			for i in 16:
				pts.append(c + Vector2(cos(i * TAU / 16) * u * 1.3, sin(i * TAU / 16) * u * 0.8))
			draw_colored_polygon(pts, Color("5a9bd4"))
		"Bridge":
			draw_rect(Rect2(c + Vector2(-u * 1.4, -u * 0.5), Vector2(u * 2.8, u)), Color("8c7b5a"))
			draw_line(c + Vector2(-u * 1.4, -u * 0.5), c + Vector2(u * 1.4, -u * 0.5), Color.BLACK, 2)
			draw_line(c + Vector2(-u * 1.4, u * 0.5), c + Vector2(u * 1.4, u * 0.5), Color.BLACK, 2)
		"Hill Top":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-u * 1.2, u * 0.8), c + Vector2(0, -u * 1.1), c + Vector2(u * 1.2, u * 0.8)]), Color("8e6e3e"))
			draw_circle(c + Vector2(0, -u * 0.1), 3, Color.BLACK)
	_center_text(Vector2(c.x, r.end.y - 4), name, maxi(11, int(r.size.x * 0.13)), Color("1b1b1b"), false)


func _center_text(at: Vector2, s: String, sz: int, col: Color, outline := true) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	if outline:
		draw_string_outline(font, at - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 4, Color(0, 0, 0, 0.6))
	draw_string(font, at - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)
