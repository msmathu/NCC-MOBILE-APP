extends Node
## Headless check that every obstacle mini-game can be cleared by a competent
## player within its time limit. Run:
##   godot --headless --path client res://tests/obstacle_tests.tscn

const DT := 1.0 / 60.0

var failures := 0


func _ready() -> void:
	var race_script := load("res://scripts/race/race.gd")
	var games: Dictionary = race_script.GAMES
	print("obstacle             kind       cleared  time   faults")
	for i in Course.OBSTACLE_COUNT:
		var info: Dictionary = Course.OBSTACLES[i]
		for trial in 3:
			_run(i, info, games[info.kind])
	print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	get_tree().quit(1 if failures else 0)


func _run(i: int, info: Dictionary, script: GDScript) -> void:
	var g: ObstacleGame = script.new()
	g.index = i
	if g.has_method("setup"):
		g.setup(info.kind)
	g.set_process(false)
	add_child(g)
	g.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	g.size = Vector2(1280, 720)
	var result := {"clean": false, "done": false}
	g.cleared.connect(func(clean: bool) -> void:
		result.done = true
		result.clean = clean)
	if g.has_method("_generate"):
		pass
	var t := 0.0
	var next_act := 0.0
	var alt := false
	var path: Array = []
	var x := 0.0
	while not result.done and t < 120.0:
		match info.kind:
			"balance":
				if t >= next_act and absf(g.lean) > 0.12:
					g.on_press(Vector2.INF, g.lean > 0.0)
					next_act = t + 0.12
			"timing", "vault_r", "vault_l":
				if absf(g.cursor - g.zone) < 0.03 and t >= next_act:
					g.on_swipe(g.need)
					next_act = t + 0.3
			"gate":
				if g.left < g.window - 0.35:
					g.on_swipe(g.want)
			"tilt":
				g.hold_side = signi(int(signf(g._target(g.elapsed) - g.marker))) if absf(g._target(g.elapsed) - g.marker) > 0.05 else 0
			"crawl":
				g.holding = true
				if not g.prone:
					g.on_swipe(Vector2.DOWN)
			"mash", "wall":
				if t >= next_act:
					g.on_press(Vector2.INF, false)
					next_act = t + 1.0 / 8.0
			"alternate":
				if t >= next_act:
					alt = not alt
					g.on_press(Vector2.INF, alt)
					next_act = t + 1.0 / 6.0
			"steps":
				if t >= next_act and g.target != Vector2.ZERO:
					g.on_press(g.target, false)
					next_act = t + 0.45
			"ditch":
				if g.air > 0.0:
					g.on_press(Vector2.INF, false)
				elif not g.charging:
					g.holding = t >= next_act
				elif g.power >= 0.72 and g.power <= 0.86:
					g.holding = false
					next_act = t + 0.4
			"rope":
				var off: float = fmod(g.clock + DT, g.BEAT)
				if t >= next_act and (off < 0.02 or g.BEAT - off < 0.02):
					g.on_press(Vector2.INF, false)
					next_act = t + 0.3
			"net":
				if path.is_empty():
					path = _net_path(g)
				if t >= next_act and not path.is_empty():
					g.on_swipe(path.pop_front())
					next_act = t + 0.3
			"sprint":
				if t >= next_act:
					g.on_press(Vector2.INF, false)
					next_act = t + (1.0 / 7.0 if g.stamina > 0.2 else 0.5)
				x += g.speed * DT
				if x >= Course.SPRINT_LENGTH:
					g.finish(true)
		g._process(DT)
		t += DT
	var ok: bool = result.done and t < g.time_limit
	if not ok:
		failures += 1
	print("%-20s %-10s %-8s %5.1fs  %d" % [info.name.substr(0, 20), info.kind, "yes" if ok else "NO", t, g.faults])
	g.queue_free()


func _net_path(g: Object) -> Array:
	var start: Vector2i = g.at
	var prev := {start: null}
	var queue: Array[Vector2i] = [start]
	var goal = null
	while not queue.is_empty():
		var p: Vector2i = queue.pop_front()
		if p.y == 0:
			goal = p
			break
		for d in [Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN]:
			var n: Vector2i = p + d
			if n.x >= 0 and n.x < g.COLS and n.y >= 0 and n.y < g.ROWS and not g.blocked.has(n) and not prev.has(n):
				prev[n] = p
				queue.append(n)
	var moves := []
	while goal != null and prev[goal] != null:
		moves.push_front(Vector2(goal - prev[goal]))
		goal = prev[goal]
	return moves
