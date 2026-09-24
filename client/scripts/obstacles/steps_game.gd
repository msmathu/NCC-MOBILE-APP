extends ObstacleGame
## Obstacle 9 - Step Vault: footstep targets pop up on the right; tap each one
## before it fades. Keyboard players hit the current target with any tap key.

const COUNT := 4
const RADIUS := 64.0
var hits := 0
var target := Vector2.ZERO
var life := 0.0
var max_life := 1.3


func _ready() -> void:
	_spawn.call_deferred()


func _spawn() -> void:
	var a := area()
	target = Vector2(randf_range(a.get_center().x + 40, a.end.x - 70), randf_range(a.position.y + 60, a.end.y - 50))
	max_life = win(1.3) - hits * 0.08
	life = max_life


func tick(d: float) -> void:
	if target == Vector2.ZERO:
		_spawn()
	life -= d
	if life <= 0.0:
		fault()
		_spawn()


func on_press(pos: Vector2, _left: bool) -> void:
	if pos == Vector2.INF or pos.distance_to(target) <= RADIUS * (1.35 if scout else 1.0):
		hits += 1
		progress = float(hits) / COUNT
		good(1.0 + hits * 0.12)
		if hits >= COUNT:
			finish(faults == 0)
		else:
			_spawn()
	else:
		fault()


func paint(a: Rect2) -> void:
	var k := clampf(life / max_life, 0.0, 1.0)
	draw_circle(target, RADIUS * (0.6 + 0.4 * k), Color(GOLD, 0.35 + 0.5 * k))
	draw_arc(target, RADIUS, -PI / 2, -PI / 2 + TAU * k, 32, Color.WHITE, 4)
	# boot print
	draw_colored_polygon(PackedVector2Array([target + Vector2(-12, -22), target + Vector2(12, -22), target + Vector2(14, 8), target + Vector2(-14, 8)]), Color("1f2a44"))
	draw_circle(target + Vector2(0, 16), 11, Color("1f2a44"))
	for i in COUNT:
		draw_circle(Vector2(a.position.x + 40 + i * 34, a.position.y + 24), 10, GREEN if i < hits else Color(1, 1, 1, 0.3))
	text(Vector2(a.position.x + a.size.x * 0.25, a.end.y - 14), "TAP the footsteps", 22)
