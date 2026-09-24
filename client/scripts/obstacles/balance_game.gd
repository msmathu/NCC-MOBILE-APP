extends ObstacleGame
## Obstacle 1 - Straight Balance: the cadet keeps tipping; tap the opposite
## side to shift weight. Taps on the drum beat correct twice as much.

const BEAT := 0.55
var lean := 0.0 ## -1 (left) .. 1 (right)
var vel := 0.0
var beat := 0.0


func tick(d: float) -> void:
	beat += d
	vel += (lean * 1.7 + randf_range(-1.3, 1.3)) * d
	vel *= 1.0 - 0.4 * d
	lean += vel * d
	if absf(lean) < win(0.45):
		progress = minf(1.0, progress + d / 4.5)
	if absf(lean) >= 1.0:
		fault()
		lean = 0.0
		vel = 0.0
		progress = maxf(0.0, progress - 0.2)
	if progress >= 1.0:
		good()
		finish(faults == 0)


func on_press(_pos: Vector2, left: bool) -> void:
	var ph := fmod(beat, BEAT) / BEAT
	var on_beat := ph < win(0.2) or ph > 1.0 - win(0.2)
	var push := 0.95 if on_beat else 0.5
	vel += -push if left else push
	vel *= 0.6
	Sfx.play("step", 1.3 if on_beat else 0.9)


func paint(a: Rect2) -> void:
	var c := a.get_center() + Vector2(0, 10)
	var half := a.size.x * 0.4
	draw_rect(Rect2(c.x - half, c.y - 6, half * 2, 12), Color("8b5a2b"))
	var zone := win(0.45) * half
	draw_rect(Rect2(c.x - zone, c.y - 10, zone * 2, 20), Color(GREEN, 0.35))
	var mx := c.x + lean * half
	draw_circle(Vector2(mx, c.y), 18, GOLD)
	draw_line(Vector2(mx, c.y), Vector2(mx + lean * 30, c.y - 60), Color.WHITE, 5)
	var pulse := 1.0 - fmod(beat, BEAT) / BEAT
	draw_arc(Vector2(c.x, a.position.y + 40), 16 + pulse * 14, 0, TAU, 24, Color(GOLD, pulse), 4)
	if lean > 0.25:
		text(Vector2(c.x - half * 0.6, c.y + 70), "◀ TAP LEFT", 28, GOLD)
	elif lean < -0.25:
		text(Vector2(c.x + half * 0.6, c.y + 70), "TAP RIGHT ▶", 28, GOLD)
	text(Vector2(c.x, a.end.y - 12), "Balance %d%%" % int(progress * 100), 20)
