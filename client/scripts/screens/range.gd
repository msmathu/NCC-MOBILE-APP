extends Control
## Level 2 - Cadet Target Practice (fictional 25 m game range).
## Instructor briefing -> choose position (standing / kneeling / lying: game
## effects only) -> range view with the cadet and target sheets ->
##   Stage 1 Position Test   : 3 sighting shots, group size (not scored)
##   Stage 2 Accuracy Test   : 3 numbered sheets, instructor calls one per shot (max 40)
##   Stage 3 Final Qualification: 3 sheets, 6 shots, 2 per sheet, 40 s limit (max 60)
## -> target analysis -> qualification card (score /100, stars) -> Level 3.
## Everyone in a room gets the same wind and calls (shared seed).

signal level_done(score: int)

const StageBoard := preload("res://scripts/screens/stage_board.gd")
const PAPER := Color("efe8d6")
const INK := Color("1b1b1b")
const S1_SHOTS := 3
const S2_CALLS := 4
const S2_CALL_TIME := 7.0
const S3_SHOTS := 6
const S3_PER_SHEET := 2
const S3_TIME := 40.0
const NUMBER_WORDS := ["ONE", "TWO", "THREE"]

var main: Node
var data: Dictionary
var mode := "practice"
var rng := RandomNumberGenerator.new()
var phase := "briefing"
var phase_t := 0.0
var stance := "kneeling"
var winds: Array[float] = []
var calls: Array[int] = []
var sheets: Array = [] ## {c: Vector2, r: float, holes: [[Vector2 rel, pts]], scored: int}
var aim_target := Vector2.ZERO ## where the player is steering (px)
var aim_pos := Vector2.ZERO ## smoothed sight position (px), before sway
var t := 0.0
var breath := 1.0
var holding_breath := false
var winded := false
var cooldown := 0.0
var shot_n := 0 ## shots fired (or calls made) in this stage
var shot_clock := 0.0
var s1_group := ""
var score2 := 0
var score3 := 0
var hits := 0
var misses := 0
var s3_time_used := 0.0
var all_holes: Array = [[], [], []] ## scored holes per sheet for the analysis: [rel, pts, r]
var instr := ""
var msg := ""
var msg_t := 0.0
var overlay: Control
var font: Font
var _touches := {}
var _keys := {}
var _autopilot := OS.get_cmdline_user_args().has("--autopilot")


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	font = ThemeDB.fallback_font
	mode = data.get("mode", "practice")
	rng.seed = int(data.get("seed", randi()))
	for i in 20:
		winds.append(snappedf(rng.randf_range(-1.0, 1.0), 0.25))
	for i in S2_CALLS:
		calls.append(rng.randi_range(0, 2))
	if Profile.has_meta("last_stance"):
		stance = Profile.get_meta("last_stance")
	Sfx.music(false)
	if mode == "spectate":
		phase = "done"
		_show_board()
		return
	_briefing()


# ---- flow ------------------------------------------------------------------------

func _set_phase(p: String) -> void:
	phase = p
	phase_t = 0.0


func _say(text: String) -> void:
	instr = text
	Sfx.speak(text)


func _briefing() -> void:
	_set_phase("briefing")
	_say("Cadet, complete the target practice exercise. Your performance will determine your qualification.")
	var col := _overlay_panel("MISSION OBJECTIVE")
	for line in ["Range: 25 m game range  -  Standard target sheets",
			"Stage 1  Position Test: 3 sighting shots",
			"Stage 2  Accuracy Test: hit the target the instructor calls",
			"Stage 3  Final Qualification: 3 sheets, 6 shots, 40 seconds",
			"Qualify 70+    Good 80+    Excellent 90+    (out of 100)"]:
		col.add_child(UI.label(line, 20, UI.WHITE))
	col.add_child(UI.spacer(6))
	col.add_child(UI.button("BEGIN", _choose_position))


func _choose_position() -> void:
	if phase != "briefing":
		return
	_set_phase("position")
	_say("Cadet, select your shooting position.")
	var col := _overlay_panel("SELECT POSITION")
	var row := UI.hbox(16)
	for key in ["standing", "kneeling", "lying"]:
		var st: Dictionary = Course.STANCES[key]
		var card := UI.vbox(6)
		var pv := StancePreview.new()
		pv.stance = key
		pv.custom_minimum_size = Vector2(220, 150)
		card.add_child(pv)
		var k: String = key
		card.add_child(UI.button(st.name, func() -> void: _position_selected(k), 220))
		card.add_child(UI.label(st.desc, 16, UI.KHAKI_LIGHT, HORIZONTAL_ALIGNMENT_CENTER))
		row.add_child(card)
	col.add_child(row)
	col.add_child(UI.label("Position changes how the sight moves in the game.", 16, UI.KHAKI, HORIZONTAL_ALIGNMENT_CENTER))


func _position_selected(key: String) -> void:
	if phase != "position":
		return
	stance = key
	Profile.set_meta("last_stance", key)
	_clear_overlay()
	_say("Position selected: %s. Proceed to the firing line." % key)
	_layout_sheets(1)
	_set_phase("s1_ready")


func _start_stage(p: String) -> void:
	_set_phase(p)
	shot_n = 0
	shot_clock = 0.0
	match p:
		"s1":
			_say("Your target sheet is ready. Fire three sighting shots.")
		"s2":
			_say("Accuracy test. Engage the target I call. Target %s!" % NUMBER_WORDS[calls[0]])
		"s3":
			_say("Final qualification. Three sheets, six rounds, two on each sheet. Forty seconds. Fire!")
	Sfx.play("whistle")


func _next_stage_brief(p: String, text: String) -> void:
	_set_phase(p)
	_say(text)


func _finish_exercise() -> void:
	_set_phase("analysis")
	_say("Cease fire! Exercise complete. Your results are being evaluated.")
	Sfx.play("whistle")


func _show_card() -> void:
	_set_phase("card")
	var total := score2 + score3
	var stars := Course.range_stars(total)
	_say("Qualification: %s. Score %d out of 100." % [Course.qualification(total).to_lower(), total])
	var col := _overlay_panel("QUALIFICATION")
	var st: Dictionary = Course.STANCES[stance]
	for line in [["Position", st.name], ["Targets", "3 sheets"], ["Hits", str(hits)], ["Misses", str(misses)],
			["Accuracy test", "%d / 40" % score2], ["Final qualification", "%d / 60" % score3],
			["Time (final)", "%ds" % int(s3_time_used)]]:
		var h := UI.hbox(20)
		var a := UI.label(line[0], 20, UI.KHAKI_LIGHT)
		a.custom_minimum_size = Vector2(260, 0)
		h.add_child(a)
		h.add_child(UI.label(line[1], 20, UI.WHITE))
		col.add_child(h)
	col.add_child(UI.label("SCORE  %d / 100" % total, 40, UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	var star_text := "⭐".repeat(stars) if stars > 0 else "-"
	col.add_child(UI.label("%s   %s" % [star_text, Course.qualification(total)], 30, UI.GREEN_OK if stars > 0 else UI.RED, HORIZONTAL_ALIGNMENT_CENTER))
	var bonus: int = [0, 10, 20, 30][stars]
	var next := "LEVEL 3 - MAP READING UNLOCKED" if stars > 0 else "Not qualified - keep practising! Proceed to Level 3."
	if bonus > 0 and mode == "online":
		next += "   (+%d DP star bonus)" % bonus
	col.add_child(UI.label(next, 18, UI.KHAKI_LIGHT, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(UI.button("CONTINUE", _card_done))
	if stars > 0:
		Sfx.play("finish")


func _card_done() -> void:
	if phase != "card":
		return
	_set_phase("done")
	_clear_overlay()
	var total := score2 + score3
	if mode == "online":
		Net.send({"t": "score", "stage": "range", "score": total})
		_show_board()
	else:
		level_done.emit(total)


func _show_board() -> void:
	var board := StageBoard.new()
	board.stage = "range"
	add_child(UI.centered(board))


# ---- overlays --------------------------------------------------------------------

func _overlay_panel(title: String) -> VBoxContainer:
	_clear_overlay()
	var p := UI.panel(26)
	var col := UI.vbox(10)
	var head := UI.hbox(14)
	var face := InstructorFace.new()
	face.custom_minimum_size = Vector2(70, 70)
	head.add_child(face)
	var tv := UI.vbox(2)
	tv.add_child(UI.label(title, 34, UI.GOLD))
	var il := UI.label(instr, 18, UI.WHITE)
	il.autowrap_mode = TextServer.AUTOWRAP_WORD
	il.custom_minimum_size = Vector2(620, 0)
	tv.add_child(il)
	head.add_child(tv)
	col.add_child(head)
	p.add_child(col)
	overlay = UI.centered(p)
	add_child(overlay)
	return col


func _clear_overlay() -> void:
	if overlay:
		overlay.queue_free()
		overlay = null


# ---- geometry ---------------------------------------------------------------------

func _layout_sheets(count: int) -> void:
	sheets.clear()
	var yc := size.y * 0.4
	if count == 1:
		var r := minf(size.y * 0.2, 135.0)
		sheets.append({"c": Vector2(size.x * 0.56, yc), "r": r, "holes": [], "scored": 0})
	else:
		var r := minf(size.y * 0.14, size.x * 0.075)
		for i in 3:
			sheets.append({"c": Vector2(size.x * 0.56 + (i - 1) * size.x * 0.2, yc), "r": r, "holes": [], "scored": 0})
	# the sight starts low and left of the sheets
	aim_target = Vector2(size.x * 0.35, size.y * 0.62)
	aim_pos = aim_target


func _ref_r() -> float:
	return sheets[0].r if not sheets.is_empty() else 100.0


func _sway() -> Vector2:
	var amp: float = Course.STANCES[stance].sway
	if winded:
		amp *= 1.8
	elif holding_breath and breath > 0.0:
		amp *= 0.25
	return amp * 0.3 * _ref_r() * Vector2(sin(t * 1.3) * 0.55 + sin(t * 2.9 + 1.0) * 0.25,
		sin(t * 1.7 + 0.4) * 0.45 + cos(t * 3.3) * 0.2)


func reticle() -> Vector2:
	return aim_pos + _sway()


func _breath_btn() -> Vector2:
	return Vector2(size.x - 330, size.y - 100)


func _fire_btn() -> Vector2:
	return Vector2(size.x - 120, size.y - 110)


func _shooting() -> bool:
	return phase in ["s1", "s2", "s3"]


# ---- loop --------------------------------------------------------------------------

func _process(d: float) -> void:
	t += d
	phase_t += d
	msg_t = maxf(0.0, msg_t - d)
	queue_redraw()
	match phase:
		"briefing":
			if phase_t > (1.0 if _autopilot else 12.0):
				_choose_position()
		"position":
			if phase_t > (1.0 if _autopilot else 14.0):
				_position_selected(stance)
		"s1_ready":
			if phase_t > 2.5:
				_start_stage("s1")
		"s1_result":
			if phase_t > 3.0:
				_layout_sheets(3)
				_next_stage_brief("s2_ready", "Three target sheets: one, two and three. Listen for my call.")
		"s2_ready":
			if phase_t > 3.0:
				_start_stage("s2")
		"s3_ready":
			if phase_t > 3.5:
				_start_stage("s3")
		"analysis":
			if phase_t > 4.5:
				_show_card()
		"card":
			if phase_t > (1.5 if _autopilot else 12.0):
				_card_done()
	if not _shooting():
		return
	_update_aim(d)
	shot_clock += d
	cooldown = maxf(0.0, cooldown - d)
	if _autopilot:
		_autopilot_step()
	match phase:
		"s1":
			if shot_clock > 12.0 and cooldown <= 0.0:
				_fire()
		"s2":
			if shot_clock > S2_CALL_TIME:
				_flash("TOO SLOW - MISS")
				misses += 1
				_next_call()
		"s3":
			s3_time_used = minf(S3_TIME, phase_t)
			if phase_t >= S3_TIME:
				misses += S3_SHOTS - shot_n
				_flash("TIME!")
				_finish_exercise()


func _update_aim(d: float) -> void:
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
	var speed: float = Course.STANCES[stance].speed
	var move := Vector2.ZERO
	if _keys.has(KEY_LEFT): move.x -= 1
	if _keys.has(KEY_RIGHT): move.x += 1
	if _keys.has(KEY_UP): move.y -= 1
	if _keys.has(KEY_DOWN): move.y += 1
	aim_target += move * 380.0 * speed * d
	aim_target = aim_target.clamp(Vector2(40, 90), size - Vector2(40, 90))
	# the sight follows the player's steering; lying swings slower, standing faster
	aim_pos = aim_pos.lerp(aim_target, minf(1.0, d * 7.0 * speed))


func _autopilot_step() -> void:
	var goal := -1
	if phase == "s1":
		goal = 0
	elif phase == "s2":
		goal = calls[shot_n]
	else:
		for i in 3:
			if sheets[i].scored < S3_PER_SHEET:
				goal = i
				break
	if goal < 0:
		return
	var c: Vector2 = sheets[goal].c - Vector2(winds[_wind_i()] * _ref_r() * 0.16, 0)
	aim_target = c - _sway() * 0.8
	if reticle().distance_to(c) < _ref_r() * 0.12 and cooldown <= 0.0 and shot_clock > 0.6:
		_fire()


func _wind_i() -> int:
	var base: int = {"s1": 0, "s2": S1_SHOTS, "s3": S1_SHOTS + S2_CALLS}.get(phase, 0)
	return mini(base + shot_n, winds.size() - 1)


func _fire() -> void:
	if not _shooting() or cooldown > 0.0:
		return
	var r := _ref_r()
	var impact := reticle() + Vector2(winds[_wind_i()] * r * 0.16, 0) + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * r * 0.02
	var hit := -1
	var best := INF
	for i in sheets.size():
		var dd: float = impact.distance_to(sheets[i].c)
		if dd < sheets[i].r and dd < best:
			best = dd
			hit = i
	var ring := 0
	if hit >= 0:
		ring = clampi(10 - int(best / sheets[hit].r * 10.0), 1, 10)
		sheets[hit].holes.append([impact - sheets[hit].c, ring])
	cooldown = 0.9
	shot_clock = 0.0
	aim_pos.y -= r * Course.STANCES[stance].recoil * 2.0 # recoil kick
	Sfx.play("thud", 1.8)
	Sfx.play("step", 0.6)
	Input.vibrate_handheld(40)
	match phase:
		"s1":
			_flash(("%d" % ring) if hit >= 0 else "MISS")
			shot_n += 1
			if shot_n >= S1_SHOTS:
				_group_result()
		"s2":
			var called := calls[shot_n]
			var pts := ring if hit == called else 0
			if hit >= 0 and hit != called:
				_flash("WRONG TARGET! (%d)" % (hit + 1))
			else:
				_flash(("%d" % pts) if pts > 0 else "MISS")
			_record(called, impact, pts)
			score2 += pts
			_next_call()
		"s3":
			var pts := 0
			if hit >= 0 and sheets[hit].scored < S3_PER_SHEET:
				pts = ring
				sheets[hit].scored += 1
				_flash("%d" % pts)
			elif hit >= 0:
				_flash("SHEET %d COMPLETE - MOVE ON" % (hit + 1))
			else:
				_flash("MISS")
			_record(hit, impact, pts)
			score3 += pts
			shot_n += 1
			if shot_n >= S3_SHOTS:
				s3_time_used = phase_t
				_finish_exercise()


func _record(sheet: int, impact: Vector2, pts: int) -> void:
	if pts > 0:
		hits += 1
		all_holes[sheet].append([impact - sheets[sheet].c, pts, sheets[sheet].r])
	else:
		misses += 1


func _next_call() -> void:
	shot_n += 1
	shot_clock = 0.0
	if shot_n >= S2_CALLS:
		for s in sheets:
			s.holes.clear()
		_next_stage_brief("s3_ready", "Accuracy test complete. Fresh sheets. Prepare for the final qualification.")
	else:
		_say("Target %s!" % NUMBER_WORDS[calls[shot_n]])


func _group_result() -> void:
	var holes: Array = sheets[0].holes
	var spread := 0.0
	for a in holes:
		for b in holes:
			spread = maxf(spread, (a[0] as Vector2).distance_to(b[0]))
	spread /= sheets[0].r
	s1_group = "TIGHT GROUP!" if spread < 0.35 else ("GOOD GROUP" if spread < 0.7 else "WIDE GROUP - steady your breath")
	if holes.size() < 2:
		s1_group = "SIGHTING COMPLETE"
	_flash(s1_group)
	_say("Sighting complete. %s" % s1_group.to_lower())
	_set_phase("s1_result")


func _flash(text: String) -> void:
	msg = text
	msg_t = 1.5


# ---- input ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not _shooting():
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			var role := "aim"
			if event.position.distance_to(_breath_btn()) < 80:
				role = "breath"
			elif event.position.distance_to(_fire_btn()) < 95:
				role = "fire"
				_fire()
			_touches[event.index] = {"pos": event.position, "role": role}
		else:
			_touches.erase(event.index)
	elif event is InputEventScreenDrag:
		var tt = _touches.get(event.index)
		if tt and tt.role == "aim":
			aim_target += event.relative * Course.STANCES[stance].speed
	elif event is InputEventKey and not event.echo:
		if event.pressed:
			_keys[event.keycode] = true
			if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
				_fire()
		else:
			_keys.erase(event.keycode)


# ---- drawing ---------------------------------------------------------------------------

func _draw() -> void:
	var w := size.x
	var h := size.y
	# range world: sky, tree line, earth berm (butts), grass lanes converging to the targets
	draw_rect(Rect2(0, 0, w, h * 0.5), Color("9fc7dc"))
	for i in 14:
		draw_circle(Vector2(i * w / 13.0, h * 0.2), w * 0.05, Color("4f6b3a"))
	draw_rect(Rect2(0, h * 0.2, w, h * 0.12), Color("4f6b3a"))
	draw_rect(Rect2(0, h * 0.3, w, h * 0.32), Color("8a6f4a"))
	draw_rect(Rect2(0, h * 0.6, w, h * 0.4), Color("6d7f3f"))
	var vp := Vector2(w * 0.56, h * 0.6)
	for i in 9:
		draw_line(vp + Vector2((i - 4) * 90, 0), Vector2(vp.x + (i - 4) * w * 0.28, h), Color(1, 1, 1, 0.25), 2)
	draw_string(font, Vector2(w * 0.08, h * 0.66), "25 M", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.8))
	if phase in ["s1_ready", "s1", "s1_result", "s2_ready", "s2", "s3_ready", "s3"]:
		for i in sheets.size():
			_draw_sheet(sheets[i].c, sheets[i].r, sheets[i].holes, str(i + 1) if sheets.size() > 1 else "")
	# the cadet on the firing point
	var base := Vector2(170 + (60 if stance == "lying" else 0), h - 36)
	var tilt := 0.12
	if _shooting():
		tilt = clampf((base.y - reticle().y) / maxf(1.0, reticle().x - base.x) * 0.25, -0.2, 0.35)
	draw_rect(Rect2(20, h - 40, 420, 14), Color("5e4a2a"))
	CadetArt.draw_shooter(self, base, Profile.look, stance, tilt, 2.0)
	if _shooting():
		var rp := reticle()
		var red := Color("e74c3c")
		draw_arc(rp, 16, 0, TAU, 24, red, 2.5)
		draw_line(rp + Vector2(-34, 0), rp + Vector2(-8, 0), red, 2)
		draw_line(rp + Vector2(8, 0), rp + Vector2(34, 0), red, 2)
		draw_line(rp + Vector2(0, -34), rp + Vector2(0, -8), red, 2)
		draw_line(rp + Vector2(0, 8), rp + Vector2(0, 34), red, 2)
		_draw_controls()
	_draw_hud()
	if phase == "analysis":
		_draw_analysis()
	if msg_t > 0.0:
		_text(Vector2(w * 0.56, h * 0.16), msg, 36, Color(UI.GOLD, minf(1.0, msg_t * 2.0)))


func _draw_sheet(c: Vector2, r: float, holes: Array, label: String) -> void:
	draw_rect(Rect2(c.x - r * 0.1, c.y + r * 1.1, r * 0.2, maxf(0.0, size.y * 0.6 - c.y - r * 1.1)), Color("5e3b1a"))
	draw_rect(Rect2(c - Vector2(r, r) * 1.18, Vector2(r, r) * 2.36), Color("7a5a34"))
	draw_rect(Rect2(c - Vector2(r, r) * 1.1, Vector2(r, r) * 2.2), PAPER)
	for k in range(1, 11):
		var rr := r * (11 - k) / 10.0
		var black := k >= 5
		draw_circle(c, rr, INK if black else PAPER)
		draw_arc(c, rr, 0, TAU, 48, PAPER if black else INK, 1.2)
	if r > 120:
		for k in range(1, 9):
			var rr := r * (11 - k) / 10.0
			draw_string(font, c + Vector2(rr - r * 0.075, 5), str(k), HORIZONTAL_ALIGNMENT_CENTER, r * 0.1, 12, PAPER if k >= 5 else INK)
	if label != "":
		draw_circle(c + Vector2(0, -r * 1.35), 18, UI.GOLD)
		_text(c + Vector2(0, -r * 1.35 + 8), label, 22, Color("1f2a44"))
	for hole in holes:
		var p: Vector2 = c + hole[0]
		draw_circle(p, 6, Color("f2d24b") if hole[1] >= 9 else Color(0.6, 0.6, 0.6))
		draw_circle(p, 3.5, Color.BLACK)


func _draw_controls() -> void:
	var b := _breath_btn()
	draw_circle(b, 72, Color(0.1, 0.3, 0.6, 0.55 if not holding_breath else 0.85))
	draw_arc(b, 72, -PI / 2, -PI / 2 + TAU * breath, 48, Color("7ec8e3"), 7)
	_text(b + Vector2(0, -2), "HOLD", 22, Color.WHITE)
	_text(b + Vector2(0, 20), "BREATH", 16, Color.WHITE)
	var f := _fire_btn()
	draw_circle(f, 88, Color(0.7, 0.15, 0.1, 0.85 if cooldown <= 0.0 else 0.35))
	draw_arc(f, 88, 0, TAU, 48, UI.GOLD, 4)
	_text(f + Vector2(0, -2), "AIM /", 20, Color.WHITE)
	_text(f + Vector2(0, 26), "FIRE", 30, Color.WHITE)


func _draw_hud() -> void:
	var w := size.x
	draw_rect(Rect2(0, 0, w, 48), Color(0.05, 0.07, 0.03, 0.85))
	_text_left(Vector2(16, 32), "LEVEL 2", 22, UI.GOLD)
	_text(Vector2(w * 0.5, 32), "TARGET PRACTICE  -  25 M", 22, Color.WHITE)
	var stage: String = {"s1_ready": "STAGE 1  POSITION TEST", "s1": "STAGE 1  POSITION TEST", "s1_result": "STAGE 1  POSITION TEST",
		"s2_ready": "STAGE 2  ACCURACY TEST", "s2": "STAGE 2  ACCURACY TEST",
		"s3_ready": "STAGE 3  FINAL QUALIFICATION", "s3": "STAGE 3  FINAL QUALIFICATION"}.get(phase, "")
	if stage != "":
		_text_left(Vector2(16, 124), stage, 18, UI.KHAKI_LIGHT)
		_text_left(Vector2(16, 148), "POSITION: " + Course.STANCES[stance].name, 16, UI.KHAKI_LIGHT)
	var right := ""
	match phase:
		"s1":
			right = "SIGHTING  %d / %d" % [shot_n, S1_SHOTS]
		"s2":
			right = "CALL %d/%d   TIME %ds   SCORE %d" % [shot_n + 1, S2_CALLS, ceili(S2_CALL_TIME - shot_clock), score2 + score3]
		"s3":
			right = "TIME %ds   SHOTS %d/%d   SCORE %d" % [ceili(S3_TIME - phase_t), shot_n, S3_SHOTS, score2 + score3]
	if right != "":
		var tw := font.get_string_size(right, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		_text_left(Vector2(w - tw - 16, 32), right, 20, UI.GOLD)
	if stage != "":
		var wv: float = winds[_wind_i()]
		var pole := Vector2(w - 60, 64)
		draw_line(pole, pole + Vector2(0, 50), Color.WHITE, 3)
		var fl := 10.0 + absf(wv) * 40.0
		draw_colored_polygon(PackedVector2Array([pole, pole + Vector2(fl * signf(wv), 6), pole + Vector2(0, 14)]), Color("e67e22"))
		_text(pole + Vector2(0, 70), "WIND %s" % ("calm" if wv == 0.0 else "%s%d" % ["<" if wv < 0 else ">", int(absf(wv) * 4)]), 14, Color.WHITE)
	# instructor dialogue bar
	if instr != "" and phase not in ["briefing", "position", "analysis", "card", "done"]:
		var bar := Rect2(w * 0.17, 56, w * 0.66, 44)
		draw_rect(bar, Color(0.97, 0.95, 0.9, 0.95))
		draw_rect(bar, UI.GOLD, false, 2)
		InstructorFace.paint(self, bar.position + Vector2(24, 22), 0.6)
		draw_string(font, bar.position + Vector2(54, 29), instr, HORIZONTAL_ALIGNMENT_LEFT, bar.size.x - 62, 17, Color("1f2a44"))
	if _shooting():
		_text_left(Vector2(w * 0.36, size.y - 12), "Drag to aim  -  Hold BREATH to steady  -  Keys: arrows, Shift, Space", 14, UI.KHAKI_LIGHT)


func _draw_analysis() -> void:
	var w := size.x
	var h := size.y
	draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, 0.75))
	_text(Vector2(w * 0.5, h * 0.14), "TARGET ANALYSIS", 36, UI.GOLD)
	var zoom := minf(phase_t / 0.8, 1.0)
	var r := minf(h * 0.22, w * 0.13) * (0.6 + 0.4 * zoom)
	for i in 3:
		var c := Vector2(w * 0.5 + (i - 1) * w * 0.3, h * 0.5)
		var holes := []
		for hole in all_holes[i]:
			holes.append([(hole[0] as Vector2) / float(hole[2]) * r, hole[1]])
		_draw_sheet(c, r, holes, str(i + 1))
		var pts := 0
		for hole in all_holes[i]:
			pts += int(hole[1])
		_text(c + Vector2(0, r * 1.45), "%d hits  -  %d pts" % [all_holes[i].size(), pts], 20, Color.WHITE)
	_text(Vector2(w * 0.5, h * 0.92), "HITS %d     MISSES %d     SCORE %d / 100" % [hits, misses, score2 + score3], 28, UI.GOLD)


func _text(at: Vector2, s: String, sz: int, col := Color.WHITE) -> void:
	var tw := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	draw_string_outline(font, at - Vector2(tw * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 6, Color(0, 0, 0, 0.7))
	draw_string(font, at - Vector2(tw * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)


func _text_left(at: Vector2, s: String, sz: int, col := Color.WHITE) -> void:
	draw_string_outline(font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 5, Color(0, 0, 0, 0.7))
	draw_string(font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)


## Small drawn instructor head (black beret, moustache) for dialogue boxes.
class InstructorFace:
	extends Control

	func _draw() -> void:
		paint(self, size * 0.5, size.x / 70.0)

	static func paint(ci: CanvasItem, c: Vector2, s: float) -> void:
		ci.draw_circle(c, 30 * s, Color("d4a017"))
		ci.draw_circle(c + Vector2(0, 4) * s, 20 * s, CadetArt.SKIN)
		ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-22, -6) * s, c + Vector2(-4, -26) * s, c + Vector2(22, -14) * s, c + Vector2(20, -4) * s]), Color("1a1a1a"))
		ci.draw_circle(c + Vector2(-7, 2) * s, 2.2 * s, Color.BLACK)
		ci.draw_circle(c + Vector2(7, 2) * s, 2.2 * s, Color.BLACK)
		ci.draw_line(c + Vector2(-8, 12) * s, c + Vector2(8, 12) * s, Color("2b1d10"), 4 * s)


## Stance preview on the position-selection cards.
class StancePreview:
	extends Control
	var stance := "standing"

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.3, 0.38, 0.2))
		draw_rect(Rect2(0, size.y - 16, size.x, 16), Color("5e4a2a"))
		var base := Vector2(size.x * (0.45 if stance == "lying" else 0.32), size.y - 14)
		CadetArt.draw_shooter(self, base, Profile.look, stance, 0.05, 1.05)
