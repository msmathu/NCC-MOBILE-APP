extends ObstacleGame
## Obstacle 6 - Gate Vault: three quick calls; swipe the way the arrow points
## before the window closes.

const ROUNDS := 3
var round_i := 0
var want := Vector2.RIGHT
var window := 0.0
var left := 0.0


func _ready() -> void:
	_next()


func _next() -> void:
	want = Vector2.RIGHT if randf() < 0.5 else Vector2.LEFT
	window = win(1.4) - round_i * 0.15
	left = window


func tick(d: float) -> void:
	left -= d
	if left <= 0.0:
		fault()
		_next()


func on_swipe(dir: Vector2) -> void:
	if dir == want:
		round_i += 1
		progress = float(round_i) / ROUNDS
		good(1.0 + round_i * 0.1)
		if round_i >= ROUNDS:
			finish(faults == 0)
		else:
			_next()
	elif dir.x != 0.0:
		fault()
		_next()


func paint(a: Rect2) -> void:
	var c := a.get_center()
	arrow(c + Vector2(0, -20), want, 180, GOLD, 20)
	draw_rect(Rect2(a.position.x + 60, a.end.y - 50, (a.size.x - 120) * clampf(left / window, 0, 1), 10), Color.WHITE)
	for i in ROUNDS:
		draw_circle(Vector2(c.x - 40 + i * 40, a.position.y + 26), 10, GREEN if i < round_i else Color(1, 1, 1, 0.3))
	text(Vector2(c.x, a.end.y - 14), "SWIPE " + ("RIGHT" if want.x > 0 else "LEFT"), 22)
