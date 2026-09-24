extends Control
## Level 3 - Map Reading & Navigation on a topographic-style training map
## (1 grid square = 1 km; references are Easting first, then Northing).
##   M1 4-figure GR of a highlighted building          +100
##   M2 6-figure GR of a small object                   +150
##   M3 Where am I? cadet's 4-figure +50, 6-figure +100
##   M4 Locate the target: tap the given 6-figure GR    +150
##   M5 Navigation: direction +50, distance +50, route +250
##   Time bonus up to +100.  Wrong answer -50 (one retry, then the answer is shown).
## Grades /1000: 900+ Excellent, 700+ Qualified, 500+ Training required, else Retrain.
## Map, objects and routes come from the shared seed, so the squad gets the same test.

signal level_done(score: int)

const StageBoard := preload("res://scripts/screens/stage_board.gd")
const RangeScreen := preload("res://scripts/screens/range.gd")
const COLS := 8
const ROWS := 6
const TIME_BONUS_FULL := 150.0 ## finish within this for the full +100
const TIME_BONUS_ZERO := 230.0
const DIR8 := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
const PAPER := Color("efe9d2")
const ROAD := Color("e3b64a")
const WATER := Color("5a9bd4")
const FOREST := Color(0.45, 0.66, 0.38, 0.55)

var main: Node
var data: Dictionary
var mode := "practice"
var rng := RandomNumberGenerator.new()
var e0 := 27 ## easting of the left grid line
var n0 := 44 ## northing of the bottom grid line
var river_x0 := 3.8
var river_ph := 0.0
var bridge := Vector2.ZERO
var start := Vector2.ZERO ## cadet (current position)
var target := Vector2.ZERO ## Checkpoint Alpha
var restricted := Rect2()
var hill := Vector2.ZERO
var forests: Array = []
var buildings: Array = []
var building_q := Vector2.ZERO ## building asked about in M1
var objects := {} ## name -> Vector2
var object_q := "" ## object asked about in M2
var routes := {} ## "A"/"B"/"C" -> {name, pts, ok, why}
var route_ok := ""
var steps: Array = []
var step_i := 0
var attempts := 0
var score := 0
var breakdown := {}
var elapsed := 0.0
var entry := ""
var marker := Vector2(-1, -1)
var revealed := false
var show_romer := false
var finished := false
var anim_route := PackedVector2Array()
var anim_t := 0.0
var font: Font
var _autopilot := OS.get_cmdline_user_args().has("--autopilot")

var right: MarginContainer
var panel: VBoxContainer
var title_label: Label
var prompt_label: Label
var entry_label: Label
var feedback: Label
var keypad: GridContainer
var choice_box: GridContainer
var confirm_btn: Button
var hud_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	font = ThemeDB.fallback_font
	mode = data.get("mode", "practice")
	rng.seed = int(data.get("seed", randi()))
	_generate()
	_build_steps()
	_build_ui()
	Sfx.music(false)
	if mode == "spectate":
		finished = true
		right.visible = false
		_show_board()
		return
	Sfx.speak("Level three. Map reading and navigation. Remember: easting first, then northing.")
	_begin_step()


# ---- map generation ----------------------------------------------------------------

func river_x(y: float) -> float:
	return river_x0 + 0.45 * sin(y * 1.1 + river_ph)


func _generate() -> void:
	e0 = rng.randi_range(20, 60)
	n0 = rng.randi_range(30, 80)
	# Retry the whole layout until the route puzzle is fair (see _layout_ok).
	for attempt in 200:
		river_x0 = rng.randf_range(3.4, 4.3)
		river_ph = rng.randf_range(0.0, TAU)
		start = Vector2(rng.randf_range(0.4, 2.2), rng.randf_range(0.35, 1.8))
		target = Vector2(rng.randf_range(5.3, 7.5), rng.randf_range(3.7, 5.6))
		# the bridge sits well away from where the straight line meets the river
		var cross_y := _direct_cross_y()
		var by := rng.randf_range(0.8, 5.2)
		if absf(by - cross_y) < 1.1:
			continue
		bridge = Vector2(river_x(by), by)
		if _layout_ok():
			break
	_build_routes()
	hill = Vector2(rng.randf_range(5.0, 7.0), rng.randf_range(1.0, 2.6))
	for i in 5:
		forests.append(Vector2(rng.randf_range(0.5, COLS - 0.5), rng.randf_range(0.5, ROWS - 0.5)))
	for i in 7:
		buildings.append(_free_point(0.9))
	building_q = buildings[rng.randi_range(0, buildings.size() - 1)]
	objects["Vehicle"] = _free_point(0.8)
	objects["Lone Tree"] = _free_point(0.8)
	objects["Checkpoint Bravo"] = _free_point(0.8)
	objects["Bridge"] = bridge
	var names := objects.keys()
	object_q = names[rng.randi_range(0, names.size() - 1)]


func _direct_cross_y() -> float:
	for i in 101:
		var p := start.lerp(target, i / 100.0)
		if p.x >= river_x(p.y):
			return p.y
	return 3.0


## Direct / follow the road / trail via the bridge. Exactly one is safe: the direct
## line always meets the river away from the bridge, and the restricted area
## blocks either the road or the trail.
func _road() -> PackedVector2Array:
	return PackedVector2Array([start, Vector2(start.x, bridge.y), bridge, Vector2(target.x, bridge.y), target])


func _trail() -> PackedVector2Array:
	return PackedVector2Array([start, bridge, target])


## Places the restricted area on the road or the trail so that exactly one of
## them is safe, the safe one only crosses the river at the bridge, and the area
## stays clear of the start, the target and the bridge.
func _layout_ok() -> bool:
	var block_road := rng.randf() < 0.5
	var blocked := _road() if block_road else _trail()
	var safe := _trail() if block_road else _road()
	if _crosses_river_off_bridge(safe):
		return false
	for k in 40:
		var seg := rng.randi_range(0, blocked.size() - 2)
		var c := blocked[seg].lerp(blocked[seg + 1], rng.randf_range(0.2, 0.8))
		restricted = Rect2(c - Vector2(0.5, 0.4), Vector2(1.0, 0.8))
		if restricted.position.x < 0.1 or restricted.position.y < 0.1 or restricted.end.x > COLS - 0.1 or restricted.end.y > ROWS - 0.1:
			continue
		if _path_hits_rect(safe, restricted.grow(0.1)) or not _path_hits_rect(blocked, restricted):
			continue
		if restricted.grow(0.35).has_point(start) or restricted.grow(0.35).has_point(target) or restricted.grow(0.3).has_point(bridge):
			continue
		if absf(restricted.get_center().x - river_x(restricted.get_center().y)) < 0.8:
			continue
		return true
	return false


func _crosses_river_off_bridge(pts: PackedVector2Array) -> bool:
	var side := signf(pts[0].x - river_x(pts[0].y))
	for i in pts.size() - 1:
		for k in range(1, 81):
			var p := pts[i].lerp(pts[i + 1], k / 80.0)
			var s := signf(p.x - river_x(p.y))
			if s != side and s != 0.0:
				if p.distance_to(bridge) > 0.3:
					return true
				side = s
	return false


func _build_routes() -> void:
	var road := _road()
	var trail := _trail()
	var direct := PackedVector2Array([start, target])
	var road_ok := not _path_hits_rect(road, restricted)
	var defs := [
		{"name": "Direct route", "pts": direct, "ok": false, "why": "The direct line crosses the river where there is no bridge."},
		{"name": "Follow the road", "pts": road, "ok": road_ok,
			"why": "The road stays on firm ground and uses the bridge." if road_ok else "The road runs through the RESTRICTED AREA."},
		{"name": "Trail via the bridge", "pts": trail, "ok": not road_ok,
			"why": "The trail crosses at the bridge and avoids the restricted area." if not road_ok else "The trail cuts through the RESTRICTED AREA."},
	]
	for i in range(2, 0, -1): # shuffle which letter is which route
		var j := rng.randi_range(0, i)
		var tmp = defs[i]
		defs[i] = defs[j]
		defs[j] = tmp
	var letters := ["A", "B", "C"]
	for i in 3:
		routes[letters[i]] = defs[i]
		if defs[i].ok:
			route_ok = letters[i]


func _path_hits_rect(pts: PackedVector2Array, r: Rect2) -> bool:
	for i in pts.size() - 1:
		for k in 41:
			if r.has_point(pts[i].lerp(pts[i + 1], k / 40.0)):
				return true
	return false


func _free_point(min_d: float) -> Vector2:
	for i in 200:
		var p := Vector2(rng.randf_range(0.25, COLS - 0.25), rng.randf_range(0.25, ROWS - 0.25))
		if absf(p.x - river_x(p.y)) < 0.45 or restricted.grow(0.2).has_point(p):
			continue
		var ok := p.distance_to(start) > min_d and p.distance_to(target) > min_d and p.distance_to(bridge) > min_d
		for b in buildings:
			ok = ok and p.distance_to(b) > min_d
		for o in objects.values():
			ok = ok and p.distance_to(o) > min_d
		if ok:
			return p
	return Vector2(rng.randf_range(0.3, COLS - 0.3), rng.randf_range(0.3, ROWS - 0.3))


# ---- grid references ------------------------------------------------------------------

func gr4(p: Vector2) -> String:
	return "%02d%02d" % [e0 + int(p.x), n0 + int(p.y)]


func gr6(p: Vector2) -> String:
	return "%03d%03d" % [e0 * 10 + int(p.x * 10.0), n0 * 10 + int(p.y * 10.0)]


## 6-figure answers may be one tenth out in either direction.
func _gr6_ok(text: String, p: Vector2) -> bool:
	if text.length() != 6:
		return false
	var e := int(text.substr(0, 3))
	var n := int(text.substr(3, 3))
	return absi(e - (e0 * 10 + int(p.x * 10.0))) <= 1 and absi(n - (n0 * 10 + int(p.y * 10.0))) <= 1


func _bearing8(from: Vector2, to: Vector2) -> String:
	var d := to - from # +x east, +y north
	var ang := fposmod(rad_to_deg(atan2(d.x, d.y)), 360.0) # 0 = north, clockwise
	return DIR8[int(round(ang / 45.0)) % 8]


# ---- missions ---------------------------------------------------------------------------

func _build_steps() -> void:
	var dist := start.distance_to(target)
	var d_ok := "%.1f km" % dist
	var d_opts := [d_ok, "%.1f km" % (dist * 0.5), "%.1f km" % (dist * 1.8)]
	for i in range(2, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = d_opts[i]
		d_opts[i] = d_opts[j]
		d_opts[j] = tmp
	steps = [
		{"mission": 1, "title": "MISSION 1 - 4-FIGURE GRID REFERENCE", "type": "gr4", "answer": building_q, "points": 100,
			"prompt": "Find the 4-figure grid reference of the highlighted building."},
		{"mission": 2, "title": "MISSION 2 - 6-FIGURE GRID REFERENCE", "type": "gr6", "answer": objects[object_q], "points": 150,
			"prompt": "Give the 6-figure grid reference of the %s (circled). Estimate the tenths inside the square." % object_q},
		{"mission": 3, "title": "MISSION 3 - WHERE AM I?", "type": "gr4", "answer": start, "points": 50,
			"prompt": "REPORT YOUR CURRENT POSITION (blue cadet icon). First the 4-figure reference."},
		{"mission": 3, "title": "MISSION 3 - WHERE AM I?", "type": "gr6", "answer": start, "points": 100,
			"prompt": "Now the precise 6-figure reference of your position."},
		{"mission": 4, "title": "MISSION 4 - LOCATE THE TARGET", "type": "tap", "answer": target, "points": 150,
			"prompt": "TARGET GRID REFERENCE: %s (Checkpoint Alpha). Tap the exact spot on the map, then CONFIRM." % gr6(target)},
		{"mission": 5, "title": "MISSION 5 - NAVIGATION", "type": "choice", "answer": _bearing8(start, target), "points": 50,
			"options": DIR8, "prompt": "Current %s  ->  Target %s.\nWhich DIRECTION will you travel?" % [gr6(start), gr6(target)]},
		{"mission": 5, "title": "MISSION 5 - NAVIGATION", "type": "choice", "answer": d_ok, "points": 50,
			"options": d_opts, "prompt": "Approximate DISTANCE to Checkpoint Alpha?\n(1 grid square = 1 km)"},
		{"mission": 5, "title": "MISSION 5 - NAVIGATION", "type": "choice", "answer": route_ok, "points": 250, "route": true,
			"options": ["A", "B", "C"], "prompt": "Choose your ROUTE to the target. Watch the river and the restricted area."},
	]
	for m in range(1, 6):
		breakdown[m] = 0


func _step() -> Dictionary:
	return steps[step_i]


func _begin_step() -> void:
	attempts = 0
	revealed = false
	show_romer = false
	entry = ""
	marker = Vector2(-1, -1)
	var s := _step()
	title_label.text = s.title
	prompt_label.text = s.prompt
	feedback.text = ""
	keypad.visible = s.type in ["gr4", "gr6"]
	choice_box.visible = s.type == "choice"
	confirm_btn.visible = s.type in ["gr4", "gr6", "tap"]
	confirm_btn.disabled = false
	entry_label.visible = s.type != "choice"
	for c in choice_box.get_children():
		c.queue_free()
	if s.type == "choice":
		choice_box.columns = 4 if s.options.size() > 4 else (1 if s.get("route", false) else 3)
		for o in s.options:
			var label: String = o
			if s.get("route", false):
				label = "%s   %s" % [o, routes[o].name]
			var opt: String = o
			var b := UI.button(label, func() -> void: _answer(opt))
			b.add_theme_font_size_override("font_size", 20)
			b.custom_minimum_size = Vector2(0, 48)
			choice_box.add_child(b)
	if step_i == 0 or steps[step_i - 1].mission != s.mission:
		Sfx.play("whistle")
		Sfx.speak(s.prompt)
	_refresh_entry()


func _answer(value) -> void:
	if finished or revealed:
		return
	var s := _step()
	var ok := false
	match s.type:
		"gr4":
			ok = value == gr4(s.answer)
		"gr6":
			ok = _gr6_ok(value, s.answer)
		"tap":
			ok = absf(value.x - s.answer.x) <= 0.15 and absf(value.y - s.answer.y) <= 0.15
		"choice":
			ok = value == s.answer
	var is_route: bool = s.get("route", false)
	if ok:
		score += s.points
		breakdown[s.mission] += s.points
		feedback.text = "✔ CORRECT  +%d" % s.points
		if s.type == "tap":
			feedback.text = "✔ TARGET LOCATED  +%d" % s.points
		feedback.add_theme_color_override("font_color", UI.GREEN_OK)
		Sfx.play("good")
		if is_route:
			feedback.text += "\n" + routes[route_ok].why
			_animate_route()
		_next_after(3.0 if is_route else 1.4)
		return
	attempts += 1
	score -= 50
	breakdown[s.mission] -= 50
	Sfx.play("bad")
	Input.vibrate_handheld(60)
	feedback.add_theme_color_override("font_color", UI.RED)
	if attempts >= 2 or is_route:
		revealed = true
		var shown := ""
		match s.type:
			"gr4":
				shown = "Correct: %s" % gr4(s.answer)
			"gr6":
				shown = "Correct: %s" % gr6(s.answer)
			"tap":
				shown = "Incorrect grid location. Target was at %s" % gr6(s.answer)
			"choice":
				shown = "Correct: %s" % s.answer
		if is_route:
			shown = "%s\nCorrect route %s (%s): %s" % [routes[value].why, route_ok, routes[route_ok].name, routes[route_ok].why]
			_animate_route()
		feedback.text = "✘ -50   " + shown
		_next_after(3.5)
	else:
		feedback.text = "✘ INCORRECT  -50.  Try once more."
		if s.type == "gr6":
			show_romer = true
			feedback.text += "  (Romer shown on the square)"
		entry = ""
		_refresh_entry()


func _animate_route() -> void:
	anim_route = routes[route_ok].pts
	anim_t = 0.0


func _next_after(secs: float) -> void:
	revealed = true
	confirm_btn.disabled = true
	await get_tree().create_timer(secs).timeout
	if not is_inside_tree():
		return
	step_i += 1
	if step_i >= steps.size():
		_finish()
	else:
		_begin_step()


func _finish() -> void:
	finished = true
	var bonus := int(round(clampf((TIME_BONUS_ZERO - elapsed) / (TIME_BONUS_ZERO - TIME_BONUS_FULL), 0.0, 1.0) * 100.0))
	score = clampi(score + bonus, 0, 1000)
	var grade := Course.map_grade(score)
	for c in panel.get_children():
		c.queue_free()
	panel.add_child(UI.label("MAP READING QUALIFICATION", 26, UI.GOLD))
	var names := {1: "4-figure GR", 2: "6-figure GR", 3: "Current position", 4: "Target position", 5: "Navigation"}
	for m in range(1, 6):
		var h := UI.hbox(10)
		var a := UI.label("M%d  %s" % [m, names[m]], 19, UI.KHAKI_LIGHT)
		a.custom_minimum_size = Vector2(300, 0)
		h.add_child(a)
		h.add_child(UI.label("%+d" % breakdown[m], 19, UI.WHITE))
		panel.add_child(h)
	panel.add_child(UI.label("Time %ds   Time bonus %+d" % [int(elapsed), bonus], 19, UI.KHAKI_LIGHT))
	panel.add_child(UI.label("Current %s  ->  Target %s" % [gr6(start), gr6(target)], 17, UI.WHITE))
	panel.add_child(UI.label("Distance %.1f km   Direction %s   Route %s" % [start.distance_to(target), _bearing8(start, target), route_ok], 17, UI.WHITE))
	panel.add_child(UI.label("SCORE %d / 1000" % score, 34, UI.GOLD))
	panel.add_child(UI.label(grade, 30, UI.GREEN_OK if score >= 700 else (UI.GOLD if score >= 500 else UI.RED)))
	Sfx.speak("Map reading complete. %s. Score %d." % [grade.to_lower(), score])
	Sfx.play("finish" if score >= 700 else "whistle")
	await get_tree().create_timer(1.5 if _autopilot else 6.0).timeout
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


# ---- input ------------------------------------------------------------------------------

func _key(k: String) -> void:
	if revealed or finished:
		return
	var need := 4 if _step().type == "gr4" else 6
	if k == "<":
		entry = entry.substr(0, maxi(0, entry.length() - 1))
	elif entry.length() < need:
		entry += k
	Sfx.play("tap")
	_refresh_entry()


func _confirm() -> void:
	if revealed or finished:
		return
	var s := _step()
	match s.type:
		"gr4", "gr6":
			var need := 4 if s.type == "gr4" else 6
			if entry.length() < need:
				feedback.text = "Enter all %d figures (easting first)." % need
				feedback.add_theme_color_override("font_color", UI.GOLD)
				return
			_answer(entry)
		"tap":
			if marker.x < 0:
				feedback.text = "Tap the map to place your marker."
				feedback.add_theme_color_override("font_color", UI.GOLD)
				return
			_answer(marker)


func _refresh_entry() -> void:
	var s := _step()
	var half := 2 if s.type == "gr4" else 3
	var e := ""
	var n := ""
	for i in half:
		e += (entry[i] if i < entry.length() else "_") + " "
		n += (entry[half + i] if half + i < entry.length() else "_") + " "
	match s.type:
		"gr4", "gr6":
			entry_label.text = "EASTING  %s   NORTHING  %s" % [e, n]
		"tap":
			entry_label.text = "MARKER:  " + (gr6(marker) if marker.x >= 0 else "tap the map")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_0 and event.keycode <= KEY_9:
			_key(str(event.keycode - KEY_0))
		elif event.keycode == KEY_BACKSPACE:
			_key("<")
		elif event.keycode == KEY_ENTER:
			_confirm()


func _gui_input(event: InputEvent) -> void:
	if finished or revealed or step_i >= steps.size() or _step().type != "tap":
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var p := _to_map(event.position)
		if p.x >= 0 and p.x <= COLS and p.y >= 0 and p.y <= ROWS:
			marker = p
			Sfx.play("tap")
			_refresh_entry()


func _process(d: float) -> void:
	if not finished:
		elapsed += d
		hud_label.text = "LEVEL 3   MAP READING & NAVIGATION      TIME %ds      SCORE %d" % [int(elapsed), score]
		if _autopilot and not revealed and elapsed > 0.5 and fmod(elapsed, 3.0) > 2.0:
			_autopilot_step()
	anim_t += d
	queue_redraw()


func _autopilot_step() -> void:
	var s := _step()
	match s.type:
		"gr4":
			_answer(gr4(s.answer))
		"gr6":
			_answer(gr6(s.answer))
		"tap":
			marker = s.answer
			_answer(marker)
		"choice":
			_answer(s.answer)


# ---- layout -------------------------------------------------------------------------------

func _cell() -> float:
	return floorf(minf((size.x * 0.58 - 70.0) / COLS, (size.y - 150.0) / ROWS))


func _origin() -> Vector2:
	return Vector2(52, 84)


## map units (x east, y north) -> screen
func _px(p: Vector2) -> Vector2:
	var c := _cell()
	return _origin() + Vector2(p.x * c, (ROWS - p.y) * c)


func _to_map(sp: Vector2) -> Vector2:
	var q := (sp - _origin()) / _cell()
	return Vector2(q.x, ROWS - q.y)


func _build_ui() -> void:
	hud_label = UI.label("", 20, UI.GOLD)
	hud_label.position = Vector2(16, 10)
	add_child(hud_label)
	right = MarginContainer.new()
	right.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	right.anchor_left = 0.6
	right.offset_left = 0
	right.offset_right = 0
	right.add_theme_constant_override("margin_top", 48)
	right.add_theme_constant_override("margin_right", 14)
	right.add_theme_constant_override("margin_bottom", 12)
	add_child(right)
	var p := UI.panel(16)
	right.add_child(p)
	panel = UI.vbox(8)
	p.add_child(panel)
	var head := UI.hbox(10)
	var face := RangeScreen.InstructorFace.new()
	face.custom_minimum_size = Vector2(56, 56)
	head.add_child(face)
	title_label = UI.label("", 20, UI.GOLD)
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title_label)
	panel.add_child(head)
	prompt_label = UI.label("", 20, UI.WHITE)
	prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	prompt_label.custom_minimum_size = Vector2(0, 84)
	panel.add_child(prompt_label)
	entry_label = UI.label("", 22, UI.GOLD)
	panel.add_child(entry_label)
	keypad = GridContainer.new()
	keypad.columns = 6
	keypad.add_theme_constant_override("h_separation", 6)
	keypad.add_theme_constant_override("v_separation", 6)
	for k in ["1", "2", "3", "4", "5", "<", "6", "7", "8", "9", "0"]:
		var key: String = k
		var b := Button.new()
		b.text = "DEL" if k == "<" else k
		b.custom_minimum_size = Vector2(58, 52)
		b.add_theme_font_size_override("font_size", 22 if k != "<" else 16)
		b.pressed.connect(func() -> void: _key(key))
		keypad.add_child(b)
	panel.add_child(keypad)
	choice_box = GridContainer.new()
	choice_box.columns = 4
	choice_box.add_theme_constant_override("h_separation", 8)
	choice_box.add_theme_constant_override("v_separation", 8)
	panel.add_child(choice_box)
	confirm_btn = UI.button("CONFIRM", _confirm)
	panel.add_child(confirm_btn)
	feedback = UI.label("", 18, UI.WHITE)
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD
	panel.add_child(feedback)


# ---- drawing --------------------------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("2f3515"))
	var c := _cell()
	var o := _origin()
	var map_rect := Rect2(o, Vector2(c * COLS, c * ROWS))
	draw_rect(map_rect.grow(6), Color("b9a878"))
	draw_rect(map_rect, PAPER)
	for f in forests:
		for k in 9:
			var q: Vector2 = f + Vector2(cos(k * 2.3) * 0.35, sin(k * 1.7) * 0.28)
			draw_circle(_px(q), c * 0.16, FOREST)
	for k in 5: # hill contours
		var pts := PackedVector2Array()
		for i in 33:
			var a := i * TAU / 32.0
			pts.append(_px(hill + Vector2(cos(a) * (0.25 + k * 0.17), sin(a) * (0.18 + k * 0.13))))
		draw_polyline(pts, Color(0.62, 0.42, 0.2, 0.75), 1.5)
	_label_at(_px(hill) + Vector2(0, 4), "312", 12, Color("6e4b2a"))
	# restricted area
	var rr := Rect2(_px(Vector2(restricted.position.x, restricted.end.y)), restricted.size * c)
	draw_rect(rr, Color(0.85, 0.15, 0.1, 0.2))
	draw_rect(rr, Color(0.8, 0.1, 0.1), false, 2)
	var hx := 10.0
	while hx < rr.size.x:
		draw_line(rr.position + Vector2(hx, 0), rr.position + Vector2(maxf(0.0, hx - rr.size.y), minf(rr.size.y, hx)), Color(0.8, 0.1, 0.1, 0.45), 1.5)
		hx += 12.0
	_label_at(rr.get_center() + Vector2(0, 5), "RESTRICTED", 12, Color(0.7, 0.05, 0.05))
	# river
	var rp := PackedVector2Array()
	for i in 41:
		var y := i * ROWS / 40.0
		rp.append(_px(Vector2(river_x(y), y)))
	draw_polyline(rp, WATER, c * 0.2, true)
	# roads
	for seg in [[Vector2(0, bridge.y), Vector2(COLS, bridge.y)], [Vector2(start.x, 0), Vector2(start.x, bridge.y)],
			[Vector2(target.x, bridge.y), Vector2(target.x, ROWS)]]:
		draw_line(_px(seg[0]), _px(seg[1]), Color("8a6a2a"), 7)
		draw_line(_px(seg[0]), _px(seg[1]), ROAD, 4)
	# bridge
	var bp := _px(bridge)
	draw_rect(Rect2(bp - Vector2(c * 0.22, 6), Vector2(c * 0.44, 12)), Color("5a4a3a"))
	draw_line(bp + Vector2(-c * 0.22, -7), bp + Vector2(c * 0.22, -7), Color.BLACK, 2)
	draw_line(bp + Vector2(-c * 0.22, 7), bp + Vector2(c * 0.22, 7), Color.BLACK, 2)
	for b in buildings:
		draw_rect(Rect2(_px(b) - Vector2(6, 6), Vector2(12, 12)), Color("2b2b2b"))
	_draw_object("Vehicle", objects["Vehicle"])
	_draw_object("Lone Tree", objects["Lone Tree"])
	_draw_object("Checkpoint Bravo", objects["Checkpoint Bravo"])
	_draw_grid(o, c)
	if not finished and step_i < steps.size():
		var s := _step()
		var pulse := 0.5 + 0.5 * sin(elapsed * 5.0)
		match int(s.mission):
			1:
				draw_arc(_px(building_q), 16 + pulse * 6, 0, TAU, 32, Color("e74c3c"), 3)
			2:
				draw_arc(_px(objects[object_q]), 18 + pulse * 6, 0, TAU, 32, Color("e74c3c"), 3)
		if show_romer and s.type == "gr6":
			_draw_romer(s.answer)
	if step_i >= 2 or finished:
		_draw_cadet(_px(start))
	if step_i >= 5 or finished or (step_i == 4 and revealed):
		_draw_star(_px(target), "CP ALPHA")
	if not finished and step_i < steps.size() and _step().type == "tap" and marker.x >= 0:
		var mp := _px(marker)
		draw_line(mp + Vector2(-14, 0), mp + Vector2(14, 0), Color("e74c3c"), 3)
		draw_line(mp + Vector2(0, -14), mp + Vector2(0, 14), Color("e74c3c"), 3)
		draw_arc(mp, 9, 0, TAU, 20, Color("e74c3c"), 2)
	if not finished and step_i == steps.size() - 1:
		var cols := {"A": Color("c0392b"), "B": Color("2471a3"), "C": Color("7d3c98")}
		for k in routes:
			var pts: PackedVector2Array = routes[k].pts
			_dashed(pts, cols[k])
			# label each route on its own middle segment so the letters don't overlap
			var seg := 0 if pts.size() == 2 else pts.size() / 2
			var mid: Vector2 = pts[seg].lerp(pts[seg + 1], 0.5)
			draw_circle(_px(mid) + Vector2(14, -14), 12, cols[k])
			_label_at(_px(mid) + Vector2(14, -9), k, 15, Color.WHITE)
	if anim_route.size() >= 2:
		var total := 0.0
		for i in anim_route.size() - 1:
			total += anim_route[i].distance_to(anim_route[i + 1])
		var along := minf(anim_t / 2.5, 1.0) * total
		var pos := anim_route[anim_route.size() - 1]
		for i in anim_route.size() - 1:
			var seg := anim_route[i].distance_to(anim_route[i + 1])
			if along <= seg:
				pos = anim_route[i].lerp(anim_route[i + 1], along / maxf(seg, 0.001))
				break
			along -= seg
		draw_polyline(_px_array(anim_route), Color(0.1, 0.6, 0.2), 5)
		_draw_cadet(_px(pos))
	# north arrow, scale bar, legend
	var na := o + Vector2(c * COLS - 24, 26)
	draw_colored_polygon(PackedVector2Array([na + Vector2(0, -16), na + Vector2(8, 8), na + Vector2(0, 3), na + Vector2(-8, 8)]), Color("1f2a44"))
	_label_at(na + Vector2(0, 24), "N", 14, Color("1f2a44"))
	var sb := o + Vector2(10, c * ROWS - 14)
	draw_rect(Rect2(sb, Vector2(c, 6)), Color.BLACK)
	draw_rect(Rect2(sb, Vector2(c * 0.5, 6)), Color.WHITE)
	draw_string(font, sb + Vector2(0, -4), "0        1 km", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.BLACK)
	var ly := o.y + c * ROWS + 46
	var lx := o.x
	for item in [["road", "Road"], ["water", "River"], ["bridge", "Bridge"], ["bld", "Building"], ["forest", "Forest"], ["hill", "Hill"], ["restr", "Restricted"]]:
		_legend_icon(Vector2(lx + 8, ly), item[0])
		draw_string(font, Vector2(lx + 22, ly + 5), item[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UI.KHAKI_LIGHT)
		lx += 88


func _draw_grid(o: Vector2, c: float) -> void:
	var line := Color(0.15, 0.3, 0.65, 0.6)
	for i in COLS + 1:
		draw_line(o + Vector2(i * c, 0), o + Vector2(i * c, c * ROWS), line, 1.5)
	for j in ROWS + 1:
		draw_line(o + Vector2(0, j * c), o + Vector2(c * COLS, j * c), line, 1.5)
	var tick := Color(0.15, 0.3, 0.65, 0.35) # tenth ticks for 6-figure estimates
	for i in COLS + 1:
		for j in ROWS * 10:
			var y := o.y + j * c / 10.0
			draw_line(Vector2(o.x + i * c - 3, y), Vector2(o.x + i * c + 3, y), tick, 1)
	for j in ROWS + 1:
		for i in COLS * 10:
			var x := o.x + i * c / 10.0
			draw_line(Vector2(x, o.y + j * c - 3), Vector2(x, o.y + j * c + 3), tick, 1)
	for i in COLS + 1:
		_label_at(o + Vector2(i * c, c * ROWS + 22), "%02d" % (e0 + i), 16, UI.WHITE)
		_label_at(o + Vector2(i * c, -8), "%02d" % (e0 + i), 14, UI.KHAKI_LIGHT)
	for j in ROWS + 1:
		_label_at(o + Vector2(-24, (ROWS - j) * c + 5), "%02d" % (n0 + j), 16, UI.WHITE)
	draw_string(font, o + Vector2(c * COLS * 0.5 - 60, c * ROWS + 38), "EASTINGS  ->", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UI.KHAKI)


func _draw_romer(p: Vector2) -> void:
	var base := Vector2(floorf(p.x), floorf(p.y))
	var c := _cell()
	var tl := _px(base + Vector2(0, 1))
	draw_rect(Rect2(tl, Vector2(c, c)), Color(1, 1, 0.6, 0.35))
	for k in range(1, 10):
		draw_line(tl + Vector2(k * c / 10.0, 0), tl + Vector2(k * c / 10.0, c), Color(0.6, 0.3, 0.0, 0.5), 1)
		draw_line(tl + Vector2(0, k * c / 10.0), tl + Vector2(c, k * c / 10.0), Color(0.6, 0.3, 0.0, 0.5), 1)


func _draw_object(name: String, p: Vector2) -> void:
	var sp := _px(p)
	match name:
		"Vehicle":
			draw_rect(Rect2(sp - Vector2(9, 5), Vector2(18, 9)), Color("556b2f"))
			draw_circle(sp + Vector2(-5, 5), 3, Color.BLACK)
			draw_circle(sp + Vector2(5, 5), 3, Color.BLACK)
		"Lone Tree":
			draw_line(sp, sp + Vector2(0, 8), Color("6e4b2a"), 3)
			draw_circle(sp + Vector2(0, -2), 8, Color("27ae60"))
		"Checkpoint Bravo":
			draw_line(sp + Vector2(-4, 8), sp + Vector2(-4, -12), Color.BLACK, 2)
			draw_colored_polygon(PackedVector2Array([sp + Vector2(-4, -12), sp + Vector2(10, -7), sp + Vector2(-4, -2)]), Color("2471a3"))
			_label_at(sp + Vector2(4, 22), "CP B", 11, Color("1f2a44"))


func _draw_cadet(sp: Vector2) -> void:
	draw_circle(sp, 13, Color("2471a3"))
	draw_arc(sp, 13, 0, TAU, 24, Color.WHITE, 2)
	draw_circle(sp + Vector2(0, -4), 3.5, Color.WHITE)
	draw_line(sp, sp + Vector2(0, 7), Color.WHITE, 3)


func _draw_star(sp: Vector2, text: String) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		pts.append(sp + Vector2.from_angle(-PI / 2 + i * PI / 5) * (13.0 if i % 2 == 0 else 5.5))
	draw_colored_polygon(pts, Color("d4a017"))
	_label_at(sp + Vector2(0, 26), text, 12, Color("7a5a00"))


func _dashed(pts: PackedVector2Array, col: Color) -> void:
	for i in pts.size() - 1:
		var a := _px(pts[i])
		var b := _px(pts[i + 1])
		var n := maxi(1, int(a.distance_to(b) / 12.0))
		for k in n:
			if k % 2 == 0:
				draw_line(a.lerp(b, float(k) / n), a.lerp(b, float(k + 1) / n), col, 4)


func _px_array(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(_px(p))
	return out


func _legend_icon(p: Vector2, kind: String) -> void:
	match kind:
		"road":
			draw_line(p + Vector2(-8, 0), p + Vector2(8, 0), ROAD, 5)
		"water":
			draw_line(p + Vector2(-8, 0), p + Vector2(8, 0), WATER, 6)
		"bridge":
			draw_rect(Rect2(p - Vector2(8, 4), Vector2(16, 8)), Color("5a4a3a"))
		"bld":
			draw_rect(Rect2(p - Vector2(5, 5), Vector2(10, 10)), Color("2b2b2b"))
		"forest":
			draw_circle(p, 7, FOREST)
		"hill":
			draw_arc(p, 7, 0, TAU, 16, Color(0.62, 0.42, 0.2), 1.5)
		"restr":
			draw_rect(Rect2(p - Vector2(7, 6), Vector2(14, 12)), Color(0.85, 0.15, 0.1, 0.4))


func _label_at(at: Vector2, t: String, sz: int, col: Color) -> void:
	var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	draw_string(font, at - Vector2(w * 0.5, 0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)
