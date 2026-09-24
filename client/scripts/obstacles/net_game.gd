extends ObstacleGame
## Obstacle 14 - Cargo Net: find a way up through the tangled net with the
## D-pad (or swipes / arrow keys). Knots block the way.

const COLS := 5
const ROWS := 5
var blocked := {} ## Vector2i -> true
var at := Vector2i(2, ROWS - 1)
var _pad := {} ## Vector2 dir -> Rect2 (screen space, filled while painting)


func _ready() -> void:
	_generate()


func _generate() -> void:
	for attempt in 50:
		blocked.clear()
		for r in range(1, ROWS - 1):
			for c in COLS:
				if randf() < 0.38:
					blocked[Vector2i(c, r)] = true
		if _solvable():
			return
	blocked.clear()


func _solvable() -> bool:
	var seen := {at: true}
	var queue: Array[Vector2i] = [at]
	while not queue.is_empty():
		var p: Vector2i = queue.pop_front()
		if p.y == 0:
			return true
		for d in [Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN]:
			var n: Vector2i = p + d
			if n.x >= 0 and n.x < COLS and n.y >= 0 and n.y < ROWS and not blocked.has(n) and not seen.has(n):
				seen[n] = true
				queue.append(n)
	return false


func _move(dir: Vector2) -> void:
	var n := at + Vector2i(int(dir.x), int(dir.y))
	if n.x < 0 or n.x >= COLS or n.y < 0 or n.y >= ROWS:
		return
	if blocked.has(n):
		fault()
		return
	at = n
	Sfx.play("step")
	progress = float(ROWS - 1 - at.y) / (ROWS - 1)
	if at.y == 0:
		good()
		finish(faults <= 1)


func on_swipe(dir: Vector2) -> void:
	if dir.x == 0.0 or dir.y == 0.0:
		_move(dir)


func on_press(pos: Vector2, _left: bool) -> void:
	for dir in _pad:
		if (_pad[dir] as Rect2).grow(10).has_point(pos):
			_move(dir)
			return


func paint(a: Rect2) -> void:
	var cell := minf((a.size.y - 20) / ROWS, 44.0)
	var origin := Vector2(a.position.x + 60, a.position.y + 10)
	for r in ROWS:
		for c in COLS:
			var rect := Rect2(origin + Vector2(c, r) * cell, Vector2(cell, cell))
			draw_rect(rect, Color("c8a96a"), false, 2)
			if blocked.has(Vector2i(c, r)):
				draw_circle(rect.get_center(), cell * 0.32, Color("5e3b1a"))
				draw_line(rect.position + Vector2(8, 8), rect.end - Vector2(8, 8), BAD, 3)
			if r == 0:
				draw_rect(rect.grow(-4), Color(GREEN, 0.25))
	draw_circle(origin + (Vector2(at) + Vector2(0.5, 0.5)) * cell, cell * 0.36, GOLD)
	# D-pad on the right
	var pc := Vector2(a.end.x - 150, a.get_center().y)
	var b := 62.0
	_pad = {
		Vector2.UP: Rect2(pc + Vector2(-b * 0.5, -b * 1.5), Vector2(b, b)),
		Vector2.DOWN: Rect2(pc + Vector2(-b * 0.5, b * 0.5), Vector2(b, b)),
		Vector2.LEFT: Rect2(pc + Vector2(-b * 1.5, -b * 0.5), Vector2(b, b)),
		Vector2.RIGHT: Rect2(pc + Vector2(b * 0.5, -b * 0.5), Vector2(b, b)),
	}
	for dir in _pad:
		var r: Rect2 = _pad[dir]
		draw_rect(r, Color(1, 1, 1, 0.18))
		draw_rect(r, Color.WHITE, false, 2)
		arrow(r.get_center(), dir, 34, GOLD, 8)
	text(Vector2(a.get_center().x, a.end.y + 4), "Reach the green top row", 20)
