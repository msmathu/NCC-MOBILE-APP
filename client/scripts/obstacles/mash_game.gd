extends ObstacleGame
## Obstacles 5 & 11 - Ramp Climb / 6ft High Wall: rapid taps fill a momentum
## meter that drains. On the wall, nearby cadets (and Support roles) boost you.

var gain := 0.08
var decay := 0.3
var clean_time := 3.5
var wall := false
var taps := 0
var pulse := 0.0


func setup(kind: String) -> void:
	wall = kind == "wall"
	if wall:
		gain = 0.07
		decay = 0.34
		clean_time = 6.0


func tick(d: float) -> void:
	pulse += d
	progress = maxf(0.0, progress - decay * d * (0.4 + progress))


func on_press(_pos: Vector2, _left: bool) -> void:
	taps += 1
	progress = minf(1.0, progress + gain * boost)
	Sfx.play("tap", 0.8 + progress * 0.6)
	if progress >= 1.0:
		good()
		finish(elapsed < clean_time)


func paint(a: Rect2) -> void:
	var c := a.get_center()
	var meter := Rect2(a.position.x + 60, c.y - 22, a.size.x - 120, 44)
	draw_rect(meter, Color(0, 0, 0, 0.5))
	draw_rect(Rect2(meter.position, Vector2(meter.size.x * progress, meter.size.y)), GOLD.lerp(GREEN, progress))
	draw_rect(meter, Color.WHITE, false, 3)
	var s := 1.0 + 0.12 * sin(pulse * 18.0)
	text(Vector2(c.x, a.position.y + 54), "TAP! TAP! TAP!", int(34 * s), GOLD)
	var sub := "PULL UP!" if wall else "BUILD MOMENTUM"
	if boost > 1.0:
		sub = "BUDDY LIFT x%.1f!" % boost
	text(Vector2(c.x, a.end.y - 12), sub, 22, GREEN if boost > 1.0 else Color.WHITE)
