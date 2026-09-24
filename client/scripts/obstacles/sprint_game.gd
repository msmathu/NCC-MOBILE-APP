extends ObstacleGame
## Obstacle 15 - Finish Line Sprint: taps add speed but burn stamina; stop
## tapping briefly to recover. The race moves the cadet by `speed` and calls
## finish() at the line.

const BASE := 210.0
const TOP := 540.0
var speed := BASE
var stamina := 1.0
var _since_tap := 1.0


func _init() -> void:
	super()
	time_limit = 90.0


func tick(d: float) -> void:
	_since_tap += d
	speed = move_toward(speed, BASE, 260.0 * d)
	if _since_tap > 0.35:
		stamina = minf(1.0, stamina + 0.22 * d)


func on_press(_pos: Vector2, _left: bool) -> void:
	_since_tap = 0.0
	if stamina > 0.02:
		speed = minf(TOP, speed + 55.0)
		stamina = maxf(0.0, stamina - 0.05)
		Sfx.play("step", 0.9 + (speed - BASE) / (TOP - BASE) * 0.6)
	else:
		speed = minf(TOP, speed + 8.0)


func paint(a: Rect2) -> void:
	var c := a.get_center()
	var bar := Rect2(a.position.x + 60, c.y - 40, a.size.x - 120, 30)
	draw_rect(bar, Color(0, 0, 0, 0.5))
	var sc := GREEN if stamina > 0.4 else (GOLD if stamina > 0.15 else BAD)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * stamina, bar.size.y)), sc)
	draw_rect(bar, Color.WHITE, false, 2)
	text(Vector2(bar.position.x + 10, bar.position.y - 8), "STAMINA", 18, Color.WHITE, false)
	var sp := Rect2(a.position.x + 60, c.y + 20, a.size.x - 120, 18)
	draw_rect(sp, Color(0, 0, 0, 0.5))
	draw_rect(Rect2(sp.position, Vector2(sp.size.x * (speed - BASE * 0.5) / (TOP - BASE * 0.5), sp.size.y)), GOLD)
	var msg := "TAP TAP TAP!" if stamina > 0.15 else "OUT OF BREATH - ease off to recover!"
	text(Vector2(c.x, a.end.y - 12), msg, 24, Color.WHITE if stamina > 0.15 else BAD)
