extends Node
## One race. Modes: "online" (server room), "practice" (offline vs local bots)
## and "spectate" (watch + cheer). Runs the local cadet, turns touches/keys into
## gestures for the active obstacle game, and renders everyone via world.gd.

signal practice_over(results: Array)

const GAMES := {
	"balance": preload("res://scripts/obstacles/balance_game.gd"),
	"timing": preload("res://scripts/obstacles/timing_game.gd"),
	"vault_r": preload("res://scripts/obstacles/timing_game.gd"),
	"vault_l": preload("res://scripts/obstacles/timing_game.gd"),
	"tilt": preload("res://scripts/obstacles/tilt_game.gd"),
	"crawl": preload("res://scripts/obstacles/crawl_game.gd"),
	"mash": preload("res://scripts/obstacles/mash_game.gd"),
	"wall": preload("res://scripts/obstacles/mash_game.gd"),
	"gate": preload("res://scripts/obstacles/gate_game.gd"),
	"steps": preload("res://scripts/obstacles/steps_game.gd"),
	"alternate": preload("res://scripts/obstacles/alternate_game.gd"),
	"ditch": preload("res://scripts/obstacles/ditch_game.gd"),
	"rope": preload("res://scripts/obstacles/rope_game.gd"),
	"net": preload("res://scripts/obstacles/net_game.gd"),
	"sprint": preload("res://scripts/obstacles/sprint_game.gd"),
}
const WorldScript := preload("res://scripts/race/world.gd")
const TrackMap := preload("res://scripts/race/track_map.gd")
const SWIPE_MIN := 48.0
const G := Course.GROUND_Y

var mode := "practice"
var racers := {} ## id -> racer dict (see _racer())
var me: Dictionary = {}
var state := "countdown" ## countdown, run, obstacle, pass, sprint, done
var next_ob := 0
var game: ObstacleGame
var clock := -3.0 ## race time in seconds (negative = countdown)
var finish_sent := false
var clean_count := 0
var _send_at := 0.0
var _pass_from := Vector2.ZERO
var _pass_t := 0.0
var _level := 0
var _touches := {} ## index -> {pos, t, swiped}
var _keys_held := {}
var _follow_id := ""
var _warned := -1
var _results_sent := false
var _autopilot := OS.get_cmdline_user_args().has("--autopilot")

var world: Node2D
var cam: Camera2D
var hud: Control
var map: Control
var banner: Label
var hint: Label
var timer_label: Label
var place_label: Label
var info_label: Label
var cheer_bar: HBoxContainer
var game_layer: Control


func setup(p_mode: String, room: Dictionary) -> void:
	mode = p_mode
	var players: Array = room.get("players", [])
	for i in players.size():
		var p: Dictionary = players[i]
		var r := _racer(p.id, p.name, {"uniform": p.uniform, "beret": p.beret, "badge": p.badge}, i)
		r.role = p.get("role", "cadet")
		r.bot = p.get("bot", false)
		if p.has("plan"):
			r.plan = p.plan
		racers[p.id] = r
	var my_id: String = room.get("me", Net.my_id)
	if mode != "spectate" and racers.has(my_id):
		me = racers[my_id]
		me.me = true
		me.color = UI.GOLD
	clock = -3.0 if mode == "practice" else room.get("elapsedMs", 0) / 1000.0


func _racer(id: String, name: String, look: Dictionary, i: int) -> Dictionary:
	return {
		"id": id, "name": name, "look": look, "color": UI.LANE_COLORS[i % 7], "me": false, "bot": false,
		"role": "cadet", "x": 0.0, "target_x": 0.0, "st": "run", "pos": Vector2(0, G), "pose": "idle",
		"phase": randf() * TAU, "gear": false, "done": false, "aura": false, "lane": (i % 4) * 6.0,
		"tag": (i % 3) * 22.0,
	}


func _ready() -> void:
	world = WorldScript.new()
	add_child(world)
	cam = Camera2D.new()
	cam.position = Vector2(250, G - 190)
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 6.0
	world.add_child(cam)
	cam.make_current()
	_build_hud()
	Net.snap.connect(_on_snap)
	Net.room.connect(_on_room)
	Net.cheer.connect(_on_cheer)
	Net.finished.connect(_on_finished)
	Net.welcome.connect(_on_welcome)
	Sfx.music(true)
	if mode == "practice":
		_banner(Sfx.say("attention"), 2.5)
	elif mode == "online":
		_go()
	else:
		info_label.text = "SPECTATING - send cheers!"
		state = "done"


func _exit_tree() -> void:
	Sfx.music(false)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Control.new()
	hud.theme = UI.make_theme()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud)
	map = TrackMap.new()
	map.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	map.offset_bottom = 58
	hud.add_child(map)
	timer_label = UI.label("0:00.0", 26, UI.WHITE)
	timer_label.position = Vector2(24, 62)
	hud.add_child(timer_label)
	place_label = UI.label("", 30, UI.GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	place_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	place_label.offset_left = -260
	place_label.offset_right = -24
	place_label.offset_top = 60
	place_label.offset_bottom = 100
	hud.add_child(place_label)
	info_label = UI.label("", 20, UI.KHAKI_LIGHT)
	info_label.position = Vector2(24, 96)
	hud.add_child(info_label)
	banner = UI.label("", 52, UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	banner.offset_top = 110
	banner.offset_left = -500
	banner.offset_right = 500
	banner.add_theme_constant_override("outline_size", 10)
	hud.add_child(banner)
	hint = UI.label("", 24, UI.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	hint.offset_top = 180
	hint.offset_left = -560
	hint.offset_right = 560
	hint.add_theme_constant_override("outline_size", 6)
	hud.add_child(hint)
	game_layer = Control.new()
	game_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(game_layer)
	cheer_bar = UI.hbox(6)
	cheer_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	cheer_bar.offset_top = 228 # below the banner and hint text
	cheer_bar.offset_right = -16
	cheer_bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	if mode != "practice":
		for e in Course.CHEERS.slice(0, 5 if mode == "online" else 8):
			var b := Button.new()
			b.text = e
			b.custom_minimum_size = Vector2(52, 48)
			b.add_theme_font_size_override("font_size", 22)
			b.pressed.connect(func() -> void: Net.send({"t": "cheer", "e": e}))
			cheer_bar.add_child(b)
	hud.add_child(cheer_bar)


# ---- main loop -----------------------------------------------------------------

func _process(d: float) -> void:
	if _autopilot and game:
		# debug: clear each obstacle after a moment so the whole course can be previewed
		if state == "sprint":
			game.on_press(Vector2.INF, false)
		elif game.elapsed > 1.4:
			game.finish(true)
	var was_negative := clock < 0.0
	clock += d
	if mode == "practice" and was_negative and clock >= 0.0:
		_go()
	_update_bots()
	_update_remote(d)
	if not me.is_empty():
		_update_me(d)
	_update_camera(d)
	_update_hud()
	world.racers = racers.values()
	map.racers = world.racers


func _go() -> void:
	state = "run"
	_banner(Sfx.say("go"), 1.6)
	hint.text = "LEVEL 1 - OBSTACLE COURSE"
	Sfx.play("whistle")


func _update_me(d: float) -> void:
	me.phase += d * 11.0
	var lvl := Course.level_at(me.x)
	me.gear = lvl == 2
	if lvl != _level and state != "countdown":
		_level = lvl
		_banner(Sfx.say("level%d" % (lvl + 1)), 2.0)
	match state:
		"countdown":
			me.pose = "idle"
		"run":
			me.x += _run_speed() * d
			me.pos = Vector2(me.x, G)
			me.pose = "run"
			if next_ob < Course.OBSTACLE_COUNT and me.x >= Course.obstacle_x(next_ob):
				me.x = Course.obstacle_x(next_ob)
				_start_obstacle(next_ob)
			elif next_ob < Course.OBSTACLE_COUNT:
				var warn_dist := 700.0 if me.role == "scout" else 300.0
				if Course.obstacle_x(next_ob) - me.x < warn_dist and _warned != next_ob:
					_warned = next_ob
					hint.text = "NEXT: %d. %s" % [next_ob + 1, Course.OBSTACLES[next_ob].name]
					if me.role == "scout":
						hint.text += "  -  " + Course.OBSTACLES[next_ob].hint
		"obstacle":
			_pose_on_obstacle()
			if next_ob == 10:
				game.boost = _wall_boost()
		"sprint":
			me.x = minf(Course.FINISH_X, me.x + game.speed * (1.12 if _leader_near() else 1.0) * d)
			me.pos = Vector2(me.x, G)
			me.pose = "run"
			me.phase += d * game.speed / 60.0
			if me.x >= Course.FINISH_X:
				game.finish(true)
		"pass":
			_pass_t += d / 0.6
			var to := Vector2(Course.obstacle_x(next_ob) + Course.OBSTACLE_PASS_WIDTH, G)
			var k := minf(_pass_t, 1.0)
			me.pos = _pass_from.lerp(to, k) + Vector2(0, -sin(k * PI) * 70.0)
			me.x = me.pos.x
			me.pose = "jump"
			if _pass_t >= 1.0:
				next_ob += 1
				state = "run"
		"done":
			me.pose = "idle"
			me.x = minf(me.x + d * 60.0, Course.FINISH_X + 160)
			me.pos = Vector2(me.x, G)
	me.aura = me.role == "leader" or _leader_near()
	_send_progress()


func _run_speed() -> float:
	var s: float = Course.RUN_SPEED * Course.LEVEL_SPEED[Course.level_at(me.x)]
	if Course.in_mud(me.x):
		s *= Course.MUD_SPEED
	if _leader_near():
		s *= 1.12
	return s


func _leader_near() -> bool:
	for r in racers.values():
		if not r.me and r.role == "leader" and absf(r.x - me.x) < 260.0:
			return true
	return false


## High Wall co-op: every cadet nearby gives a lift; Support cadets give more.
func _wall_boost() -> float:
	var b := 1.0
	for r in racers.values():
		if r.me or absf(r.x - me.x) > 320.0:
			continue
		b += 0.5 if r.role == "support" else 0.2
	return minf(b, 2.2)


func _start_obstacle(i: int) -> void:
	var info: Dictionary = Course.OBSTACLES[i]
	game = GAMES[info.kind].new()
	game.index = i
	game.scout = me.role == "scout"
	if game.has_method("setup"):
		game.setup(info.kind)
	game.cleared.connect(_on_cleared)
	game_layer.add_child(game)
	_update_hold(get_viewport().get_visible_rect().size.x * 0.5)
	state = "sprint" if info.kind == "sprint" else "obstacle"
	_banner("%d. %s" % [i + 1, info.name.to_upper()], 1.6)
	hint.text = info.hint
	if info.kind == "sprint":
		Sfx.say("faster")


func _on_cleared(clean: bool) -> void:
	var was := game
	game = null
	was.queue_free()
	hint.text = ""
	if clean:
		clean_count += 1
	if next_ob == Course.OBSTACLE_COUNT - 1:
		_finish()
		return
	if clean:
		_banner(Sfx.say("good") if randf() < 0.5 else "CLEAN!", 0.8)
	_pass_from = me.pos
	_pass_t = 0.0
	state = "pass"


func _pose_on_obstacle() -> void:
	var x0 := Course.obstacle_x(next_ob)
	var p := game.progress
	var kind: String = Course.OBSTACLES[next_ob].kind
	var pos := Vector2(x0 - 10, G)
	var pose := "idle"
	match kind:
		"balance":
			pos = Vector2(x0 + 190 * p, G - 30)
			pose = "balance"
		"tilt":
			pos = Vector2(x0 + 190 * p, G - 28)
			pose = "balance"
		"crawl":
			pos = Vector2(x0 + 10 + 190 * p, G)
			pose = "crawl" if p > 0.0 or (game as Object).get("prone") else "idle"
		"mash":
			pos = Vector2(x0 + 150 * p, G - 120 * p)
			pose = "run"
		"steps":
			pos = Vector2(x0 + 190 * p, G - 28 * ceilf(p * 3.0))
			pose = "run"
		"alternate":
			pos = Vector2(x0 + 200 * p, G - 58)
			pose = "climb"
		"wall":
			pos = Vector2(x0 + 76, G - 128 * p)
			pose = "climb"
		"ditch":
			pos = Vector2(x0 + 10 + 180 * p, G)
			pose = "idle"
		"rope":
			pos = Vector2(x0 + 96, G - 230 * p)
			pose = "climb"
		"net":
			pos = Vector2(x0 + 30 + 70 * p, G - 200 * p)
			pose = "climb"
	me.pos = pos
	me.x = pos.x
	me.pose = pose


func _finish() -> void:
	state = "done"
	_banner(Sfx.say("halt"), 2.5)
	Sfx.play("finish")
	me.done = true
	me.finish_ms = clock * 1000.0
	if mode == "online":
		_send_progress(true)
		Net.send({"t": "finish"})
		finish_sent = true
		info_label.text = "Waiting for the squad...  Next: LEVEL 2 - TARGET PRACTICE"
	else:
		_practice_results.call_deferred()


func _send_progress(force := false) -> void:
	if mode != "online" or clock < 0.0:
		return
	if not force and clock < _send_at:
		return
	_send_at = clock + 0.1
	var st := "run"
	if state == "obstacle" or state == "sprint":
		st = "ob%d" % next_ob
	elif state == "done":
		st = "done"
	Net.send({"t": "progress", "p": me.x / Course.FINISH_X, "st": st})


# ---- other cadets ------------------------------------------------------------------

func _update_bots() -> void:
	if mode != "practice" or clock < 0.0:
		return
	for r in racers.values():
		if r.bot and not r.done:
			var s := Course.sample_bot(r.plan, clock * 1000.0)
			r.target_x = s[0] * Course.FINISH_X
			r.st = s[1]
			if s[1] == "done":
				r.done = true
				r.finish_ms = r.plan.finish_ms


func _update_remote(d: float) -> void:
	for r in racers.values():
		if r.me:
			continue
		r.x = lerpf(r.x, r.target_x, minf(1.0, d * 8.0))
		r.gear = Course.level_at(r.x) == 2
		var st: String = r.st
		var y := 0.0
		if st.begins_with("ob"):
			var kind: String = Course.OBSTACLES[clampi(int(st.substr(2)), 0, 14)].kind
			r.phase += d * 5.0
			match kind:
				"balance", "tilt":
					r.pose = "balance"
					y = -28.0
				"crawl":
					r.pose = "crawl"
				"wall", "rope", "net":
					r.pose = "climb"
					y = -60.0 - sin(r.phase * 0.3) * 40.0
				"alternate":
					r.pose = "climb"
					y = -58.0
				"sprint", "mash":
					r.pose = "run"
					r.phase += d * 6.0
				_:
					r.pose = "idle"
		elif st == "done" or st == "wait":
			r.pose = "idle"
		else:
			r.pose = "run" if absf(r.target_x - r.x) > 2.0 else "idle"
			r.phase += d * 11.0
		r.aura = r.role == "leader"
		r.pos = Vector2(r.x, G + y - r.lane)


func _on_snap(msg: Dictionary) -> void:
	for row in msg.pl:
		var r = racers.get(row[0])
		if r == null or r.me:
			continue
		r.target_x = float(row[1]) * Course.FINISH_X
		r.st = row[2]
		r.done = row[2] == "done"


func _on_room(room: Dictionary) -> void:
	for p in room.players:
		var r = racers.get(p.id)
		if r:
			r.role = p.role
			r.name = p.name + ("" if p.connected else " (offline)")
			if p.get("finishMs") != null:
				r.done = true
				r.finish_ms = p.finishMs


func _on_welcome(msg: Dictionary) -> void:
	# Reconnected mid-race: repeat the finish in case it was lost.
	if msg.get("resumed", false) and finish_sent:
		_send_progress(true)
		Net.send({"t": "finish"})


func _on_finished(msg: Dictionary) -> void:
	if msg.id != Net.my_id:
		UI.toast(hud, "%s finished #%d" % [msg.name, msg.place], UI.KHAKI_LIGHT)


func _on_cheer(msg: Dictionary) -> void:
	Sfx.play("cheer")
	var l := UI.label("%s %s" % [msg.e, msg.from], 30, UI.WHITE)
	l.add_theme_constant_override("outline_size", 6)
	l.position = Vector2(randf_range(80, hud.size.x - 300), hud.size.y - 120)
	hud.add_child(l)
	var tw := l.create_tween().set_parallel()
	tw.tween_property(l, "position:y", l.position.y - 260, 2.2)
	tw.tween_property(l, "modulate:a", 0.0, 2.2).set_delay(0.8)
	tw.chain().tween_callback(l.queue_free)


func _practice_results() -> void:
	if _results_sent:
		return
	_results_sent = true
	var rows := []
	for r in racers.values():
		var ms: float = r.finish_ms if r.me else r.plan.finish_ms
		rows.append({"id": r.id, "name": r.name, "bot": r.bot, "ms": ms, "dp": 0, "role": r.role, "directorate": ""})
	rows.sort_custom(func(a, b): return a.ms < b.ms)
	for i in rows.size():
		rows[i].place = i + 1
	await get_tree().create_timer(2.5).timeout
	practice_over.emit(rows)


# ---- camera + HUD ------------------------------------------------------------------

func _update_camera(d: float) -> void:
	var target: Dictionary = me
	if target.is_empty():
		# spectators follow the leader
		var best = null
		for r in racers.values():
			if best == null or r.x > best.x:
				best = r
		if best:
			target = best
	if target.is_empty():
		return
	var focus: Vector2 = target.pos
	var zoom_in := state == "obstacle" and not me.is_empty()
	# when zoomed in, keep the cadet in the upper half so the mini-game panel never covers them
	cam.position = Vector2(focus.x + (60.0 if zoom_in else 260.0), minf(focus.y, G) + (10.0 if zoom_in else -190.0))
	var z := 1.3 if zoom_in else 1.0
	cam.zoom = cam.zoom.lerp(Vector2(z, z), minf(1.0, d * 3.0))
	world.cam_x = cam.get_screen_center_position().x
	world.view_w = get_viewport().get_visible_rect().size.x / cam.zoom.x


func _update_hud() -> void:
	timer_label.text = Course.format_ms(maxf(clock, 0.0) * 1000.0) if clock >= 0.0 else str(ceili(-clock))
	if clock < 0.0:
		banner.text = str(ceili(-clock))
	if not me.is_empty():
		var ahead := 0
		for r in racers.values():
			if not r.me and (r.x > me.x or (r.done and not me.done)):
				ahead += 1
		place_label.text = "POS %d/%d" % [ahead + 1, racers.size()]
		var bits := PackedStringArray()
		if me.role != "cadet":
			bits.append("Role: " + Course.ROLE_INFO[me.role].name)
		if me.aura and me.role != "leader":
			bits.append("Leader aura +12%")
		if Course.in_mud(me.x) and state == "run":
			bits.append("MUD! Slowed")
		if me.gear:
			bits.append("Full gear")
		if state != "done":
			info_label.text = "   ".join(bits)


func _banner(text: String, secs: float) -> void:
	banner.text = text
	banner.modulate.a = 1.0
	var tw := banner.create_tween()
	tw.tween_interval(secs)
	tw.tween_property(banner, "modulate:a", 0.0, 0.4)


# ---- input -> gestures ---------------------------------------------------------------

## Touches and keys are tracked even between obstacles so a finger already
## down when a mini-game starts counts as holding; gestures go to the active game.
func _input(event: InputEvent) -> void:
	var half := get_viewport().get_visible_rect().size.x * 0.5
	if event is InputEventScreenTouch:
		if event.pressed:
			if cheer_bar.get_global_rect().has_point(event.position):
				return
			_touches[event.index] = {"pos": event.position, "swiped": false}
			if game:
				game.on_press(event.position, event.position.x < half)
		else:
			_touches.erase(event.index)
			if game:
				game.on_release(event.position)
	elif event is InputEventScreenDrag:
		var t = _touches.get(event.index)
		if t and not t.swiped and event.position.distance_to(t.pos) > SWIPE_MIN:
			t.swiped = true
			if game:
				game.on_swipe(_snap_dir(event.position - t.pos))
	elif event is InputEventKey and not event.echo:
		var k: int = event.keycode
		if not event.pressed:
			_keys_held.erase(k)
		elif k in [KEY_SPACE, KEY_ENTER, KEY_LEFT, KEY_A, KEY_RIGHT, KEY_D, KEY_UP, KEY_W, KEY_DOWN, KEY_S]:
			_keys_held[k] = true
			if game:
				match k:
					KEY_SPACE, KEY_ENTER:
						game.on_press(Vector2.INF, false)
					KEY_LEFT, KEY_A:
						game.on_press(Vector2.INF, true)
						game.on_swipe(Vector2.LEFT)
					KEY_RIGHT, KEY_D:
						game.on_press(Vector2.INF, false)
						game.on_swipe(Vector2.RIGHT)
					KEY_UP, KEY_W:
						game.on_swipe(Vector2.UP)
					KEY_DOWN, KEY_S:
						game.on_swipe(Vector2.DOWN)
	_update_hold(half)


func _update_hold(half: float) -> void:
	if game == null:
		return
	var side := 0
	for t in _touches.values():
		side += -1 if t.pos.x < half else 1
	if _keys_held.has(KEY_LEFT) or _keys_held.has(KEY_A):
		side -= 1
	if _keys_held.has(KEY_RIGHT) or _keys_held.has(KEY_D):
		side += 1
	game.holding = not _touches.is_empty() or not _keys_held.is_empty()
	game.hold_side = signi(side)


func _physics_process(_d: float) -> void:
	if game == null:
		return
	var acc := Input.get_accelerometer()
	if acc != Vector3.ZERO:
		var v := clampf(-acc.x / 4.5, -1.0, 1.0)
		game.on_tilt(-v if Profile.invert_tilt else v)


func _snap_dir(v: Vector2) -> Vector2:
	var a := snappedf(v.angle(), PI / 4.0)
	return Vector2(roundf(cos(a)), roundf(sin(a))).normalized()
