extends Control
## Level 2 - Target Practice on a fictional 25 m game range. The sight picture
## sways; hold BREATH to steady it for a few seconds; wind pushes each shot
## sideways (aim upwind). 5 rounds on a 10-ring paper target, max 50, then a
## qualification grade. Everyone in a room gets the same wind (shared seed).

signal level_done(score: int)

const StageBoard := preload("res://scripts/screens/stage_board.gd")
const SHOTS := 5
const SHOT_TIME := 15.0
const PAPER := Color("efe8d6")
const INK := Color("1b1b1b")

var main: Node
var data: Dictionary
var mode := "practice"
var rng := RandomNumberGenerator.new()
var winds: Array[float] = []
var offset := Vector2.ZERO ## player's aim, in target radii (0 = bull)
var t := 0.0
var breath := 1.0
var holding_breath := false
var winded := false
var shot_i := 0
var shot_clock := 0.0
var cooldown := 0.0
var holes: Array = [] ## [Vector2 impact (radii), int points]
var total := 0
var finished := false
var submitted := false
var msg := ""
var msg_t := 0.0
var font: Font
var _touches := {} ## index -> {pos, role}
var _keys := {}
var _autopilot := OS.get_cmdline_user_args().has("--autopilot")


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	font = ThemeDB.fallback_font
	mode = data.get("mode", "practice")
	rng.seed = int(data.get("seed", randi()))
	for i in SHOTS:
		winds.append(snappedf(rng.randf_range(-1.0, 1.0), 0.25))
	offset = Vector2(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.6, 0.6))
	Sfx.music(false)
	if mode == "spectate":
		_show_board()
		return
	_flash("RANGE READY - 5 ROUNDS")
	Sfx.speak("Level two. Target practice. Five rounds. Watch the wind.")
	Sfx.play("whistle")


# ---- geometry ----------------------------------------------------------------

func _center() -> Vector2:
	return Vector2(size.x * 0.4, size.y * 0.53)


func _radius() -> float:
	return minf(size.y * 0.36, size.x * 0.26)


func _breath_btn() -> Vector2:
	return Vector2(120, size.y - 120)


func _fire_btn() -> Vector2:
	return Vector2(size.x - 140, size.y - 130)


func _sway() -> Vector2:
	var amp := 1.0
	if winded:
		amp = 1.9
	elif holding_breath and breath > 0.0:
		amp = 0.22
	return amp * 0.33 * Vector2(sin(t * 1.3) * 0.55 + sin(t * 2.9 + 1.0) * 0.25,
		sin(t * 1.7 + 0.4) * 0.45 + cos(t * 3.3) * 0.2)


func aim() -> Vector2:
	return offset + _sway()


# ---- loop ------------------------------------------------------------------------

func _process(d: float) -> void:
	t += d
	msg_t = maxf(0.0, msg_t - d)
	queue_redraw()
	if finished or mode == "spectate":
		return
	holding_breath = _keys.has(KEY_SHIFT) or _touches.values().any(func(x): return x.role == "breath")
	if holding_breath and not winded:
		breath = maxf(0.0, breath - d / 3.0)
		if breath <= 0.0:
			winded = true
			_flash("OUT OF BREATH!")
	else:
		breath = minf(1.0, breath + d / 2.2)
		if winded and breath > 0.5:
			winded = false
	var move := Vector2.ZERO
	if _keys.has(KEY_LEFT): move.x -= 1
	if _keys.has(KEY_RIGHT): move.x += 1
	if _keys.has(KEY_UP): move.y -= 1
	if _keys.has(KEY_DOWN): move.y += 1
	offset = (offset + move * 0.7 * d).limit_length(1.6)
	cooldown = maxf(0.0, cooldown - d)
	if _autopilot and shot_clock > 1.6 and cooldown <= 0.0:
		offset = Vector2(-winds[shot_i] * 0.16, 0.0) - _sway() * 0.6
		_fire()
	shot_clock += d
	if shot_clock > SHOT_TIME and cooldown <= 0.0:
		_flash("TOO SLOW - FLINCHED!")
		offset += Vector2(randf_range(-0.3, 0.3), randf_range(-0.3, 0.3))
		_fire()


func _fire() -> void:
	if finished or cooldown > 0.0 or shot_i >= SHOTS:
		return
	var impact := aim() + Vector2(winds[shot_i] * 0.16, 0.0) + Vector2(randf_range(-0.02, 0.02), randf_range(-0.02, 0.02))
	var dist := impact.length()
	var pts := 0 if dist >= 1.0 else clampi(10 - int(dist * 10.0), 1, 10)
	holes.append([impact, pts])
	total += pts
	shot_i += 1
	shot_clock = 0.0
	cooldown = 1.1
	offset.y -= 0.12 # recoil
	Sfx.play("thud", 1.8)
	Sfx.play("step", 0.6)
	Input.vibrate_handheld(40)
	_flash(("BULL! 10" if pts == 10 else "%d" % pts) if pts > 0 else "MISS")
	if shot_i >= SHOTS:
		finished = true
		_finish.call_deferred()


func _finish() -> void:
	var grade := Course.qualification(total)
	if total >= 38:
		Sfx.say("good")
	else:
		Sfx.play("whistle")
	await get_tree().create_timer(4.0).timeout
	if not is_inside_tree():
		return
	if mode == "online":
		Net.send({"t": "score", "stage": "range", "score": total})
		submitted = true
		_show_board()
	else:
		level_done.emit(total)
	print("range complete: %d (%s)" % [total, grade])


func _show_board() -> void:
	var board := StageBoard.new()
	board.stage = "range"
	add_child(UI.centered(board))


func _flash(text: String) -> void:
	msg = text
	msg_t = 1.4


# ---- input -------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if finished or mode == "spectate":
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			var role := "aim"
			if event.position.distance_to(_breath_btn()) < 95:
				role = "breath"
			elif event.position.distance_to(_fire_btn()) < 105:
				role = "fire"
				_fire()
			_touches[event.index] = {"pos": event.position, "role": role}
		else:
			_touches.erase(event.index)
	elif event is InputEventScreenDrag:
		var tt = _touches.get(event.index)
		if tt and tt.role == "aim":
			offset = (offset + event.relative / _radius() * 0.8).limit_length(1.6)
	elif event is InputEventKey and not event.echo:
		if event.pressed:
			_keys[event.keycode] = true
			if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
				_fire()
		else:
			_keys.erase(event.keycode)


# ---- drawing -------------------------------------------------------------------------

func _draw() -> void:
	var c := _center()
	var r := _radius()
	# range backdrop: sky, earth berm (butts), grass
	draw_rect(Rect2(0, 0, size.x, size.y * 0.45), Color("9fc7dc"))
	draw_rect(Rect2(0, size.y * 0.3, size.x, size.y * 0.3), Color("8a6f4a"))
	draw_rect(Rect2(0, size.y * 0.6, size.x, size.y * 0.4), Color("6d7f3f"))
	# target frame + paper
	draw_rect(Rect2(c.x - r * 1.25, c.y - r * 1.25, r * 2.5, r * 2.5), Color("7a5a34"))
	draw_rect(Rect2(c.x - r * 1.15, c.y - r * 1.15, r * 2.3, r * 2.3), PAPER)
	for k in range(1, 11):
		var rr := r * (11 - k) / 10.0
		var black := k >= 5
		draw_circle(c, rr, INK if black else PAPER)
		draw_arc(c, rr, 0, TAU, 64, PAPER if black else INK, 1.5)
		if k <= 8:
			var col := PAPER if black else INK
			draw_string(font, c + Vector2(rr - r * 0.075, 6), str(k), HORIZONTAL_ALIGNMENT_CENTER, r * 0.1, 14, col)
	draw_string(font, c + Vector2(-r * 1.1, -r * 1.02), "25 m  -  LANE 4  -  NCC GAME RANGE", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, INK)
	for h in holes:
		var p: Vector2 = c + (h[0] as Vector2) * r
		draw_circle(p, 7, Color("f2d24b") if h[1] >= 9 else Color(0.55, 0.55, 0.55))
		draw_circle(p, 4, Color.BLACK)
	# sight picture (vignette) centred on the aim point
	if mode != "spectate" and not finished:
		var a := c + aim() * r
		var scope := r * 0.9
		draw_arc(a, scope + 400, 0, TAU, 72, Color(0, 0, 0, 0.55), 800)
		draw_arc(a, scope, 0, TAU, 72, Color(0.05, 0.05, 0.05), 6)
		var red := Color("e74c3c")
		draw_line(a + Vector2(-scope, 0), a + Vector2(-12, 0), red, 2)
		draw_line(a + Vector2(12, 0), a + Vector2(scope, 0), red, 2)
		draw_line(a + Vector2(0, -scope), a + Vector2(0, -12), red, 2)
		draw_line(a + Vector2(0, 12), a + Vector2(0, scope), red, 2)
		draw_arc(a, 12, 0, TAU, 24, red, 2)
		_draw_controls()
	_draw_panel()
	if msg_t > 0.0:
		_text(Vector2(c.x, size.y * 0.16), msg, 44, Color(UI.GOLD, minf(1.0, msg_t * 2.0)))
	if finished:
		_draw_card()


func _draw_controls() -> void:
	var b := _breath_btn()
	draw_circle(b, 88, Color(0.1, 0.3, 0.6, 0.55 if not holding_breath else 0.85))
	draw_arc(b, 88, -PI / 2, -PI / 2 + TAU * breath, 48, Color("7ec8e3"), 8)
	_text(b + Vector2(0, -4), "HOLD", 24, Color.WHITE)
	_text(b + Vector2(0, 22), "BREATH", 18, Color.WHITE)
	var f := _fire_btn()
	draw_circle(f, 98, Color(0.7, 0.15, 0.1, 0.8 if cooldown <= 0.0 else 0.35))
	draw_arc(f, 98, 0, TAU, 48, UI.GOLD, 4)
	_text(f + Vector2(0, 10), "FIRE", 34, Color.WHITE)


func _draw_panel() -> void:
	var x := size.x * 0.73
	var y := 40.0
	_text(Vector2(size.x * 0.5, 34), "LEVEL 2 - TARGET PRACTICE", 26, UI.GOLD)
	_text_left(Vector2(x, y + 40), "Round %d / %d" % [mini(shot_i + 1, SHOTS), SHOTS], 22)
	_text_left(Vector2(x, y + 72), "Score: %d" % total, 26, UI.GOLD)
	if shot_i < SHOTS and mode != "spectate":
		var w: float = winds[shot_i]
		_text_left(Vector2(x, y + 110), "Wind: %s" % ("calm" if w == 0.0 else "%s %d" % ["<-" if w < 0 else "->", int(absf(w) * 4)]), 20, UI.KHAKI_LIGHT)
		# wind flag
		var pole := Vector2(x + 180, y + 96)
		draw_line(pole, pole + Vector2(0, 50), Color.WHITE, 3)
		var fl := 10.0 + absf(w) * 40.0
		var dir := signf(w) if w != 0.0 else 0.0
		draw_colored_polygon(PackedVector2Array([pole, pole + Vector2(fl * dir, 6), pole + Vector2(0, 14)]), Color("e67e22"))
		var left := maxf(0.0, SHOT_TIME - shot_clock)
		_text_left(Vector2(x, y + 142), "Time: %ds" % ceili(left), 20, Color.WHITE if left > 5 else UI.RED)
	for i in holes.size():
		_text_left(Vector2(x, y + 180 + i * 26), "Shot %d:  %d" % [i + 1, holes[i][1]], 18, UI.KHAKI_LIGHT)
	if mode != "spectate" and not finished:
		_text_left(Vector2(20, size.y - 250), "Drag to aim.  Hold BREATH to steady.", 16, Color.WHITE)
		_text_left(Vector2(20, size.y - 228), "Keys: arrows aim, Shift breath, Space fire", 14, UI.KHAKI_LIGHT)


func _draw_card() -> void:
	var r := Rect2(size.x * 0.5 - 250, size.y * 0.5 - 140, 500, 280)
	draw_rect(r, Color(0.08, 0.1, 0.05, 0.93))
	draw_rect(r, UI.GOLD, false, 3)
	_text(r.position + Vector2(250, 50), "RANGE CARD", 28, UI.GOLD)
	_text(r.position + Vector2(250, 120), "%d / 50" % total, 60, Color.WHITE)
	var grade := Course.qualification(total)
	_text(r.position + Vector2(250, 180), grade, 34, UI.GREEN_OK if grade != "NOT QUALIFIED" else UI.RED)
	_text(r.position + Vector2(250, 240), "Marksman 45+   First Class 38+   Qualified 28+", 16, UI.KHAKI_LIGHT)


func _text(at: Vector2, s: String, sz: int, col := Color.WHITE) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	draw_string_outline(font, at - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 6, Color(0, 0, 0, 0.7))
	draw_string(font, at - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)


func _text_left(at: Vector2, s: String, sz: int, col := Color.WHITE) -> void:
	draw_string_outline(font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 5, Color(0, 0, 0, 0.7))
	draw_string(font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)
