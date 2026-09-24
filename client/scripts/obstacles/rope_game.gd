extends ObstacleGame
## Obstacle 13 - Rope Climbing: tap in rhythm. Hitting the beat pulls you up,
## off-beat taps make you slide.

const BEAT := 0.6
var clock := 0.0
var slip_flash := 0.0


func tick(d: float) -> void:
	clock += d
	slip_flash = maxf(0.0, slip_flash - d * 3.0)
	if progress >= 1.0:
		good()
		finish(faults <= 2)


func on_press(_pos: Vector2, _left: bool) -> void:
	var off := fmod(clock, BEAT)
	off = minf(off, BEAT - off)
	if off <= win(0.13):
		progress = minf(1.0, progress + 0.11)
		Sfx.play("step", 1.0 + progress * 0.5)
	else:
		faults += 1
		slip_flash = 1.0
		Sfx.play("bad", 1.2)
		progress = maxf(0.0, progress - 0.05)


func paint(a: Rect2) -> void:
	var c := a.get_center()
	var rope_x := a.position.x + 120
	draw_line(Vector2(rope_x, a.position.y + 10), Vector2(rope_x, a.end.y - 10), Color("c8a96a"), 8)
	draw_circle(Vector2(rope_x, lerpf(a.end.y - 20, a.position.y + 20, progress)), 16, GOLD)
	var k := fmod(clock, BEAT) / BEAT
	var ring := 30.0 + (1.0 - k) * 60.0
	draw_arc(c, 30, 0, TAU, 32, Color.WHITE, 5)
	draw_arc(c, ring, 0, TAU, 32, Color(GOLD, 0.4 + 0.6 * k), 4)
	if slip_flash > 0.0:
		text(c + Vector2(0, -70), "SLIP!", 30, Color(BAD, slip_flash))
	text(Vector2(c.x, a.end.y - 12), "TAP when the ring closes   %d%%" % int(progress * 100), 22)
