extends ObstacleGame
## Obstacle 10 - Monkey Crawl Beam: hand over hand. Alternate LEFT and RIGHT;
## the same hand twice makes you slip.

const STEP := 1.0 / 14.0
var last := 0 ## -1 left, 1 right, 0 none yet


func on_press(_pos: Vector2, left: bool) -> void:
	var side := -1 if left else 1
	if side != last:
		last = side
		progress = minf(1.0, progress + STEP)
		Sfx.play("step", 1.0 + progress * 0.4)
		if progress >= 1.0:
			good()
			finish(faults <= 1)
	else:
		fault()
		progress = maxf(0.0, progress - STEP * 0.6)


func paint(a: Rect2) -> void:
	var c := a.get_center()
	var next_left := last != -1
	for side in [-1, 1]:
		var r := Rect2(c.x + (side * 220) - 90, c.y - 60, 180, 120)
		var hot: bool = (side == -1) == next_left
		draw_rect(r, Color(GOLD, 0.85) if hot else Color(1, 1, 1, 0.15))
		draw_rect(r, Color.WHITE, false, 3)
		text(r.get_center() + Vector2(0, 12), "LEFT" if side == -1 else "RIGHT", 34, Color("1f2a44") if hot else Color.WHITE)
	draw_rect(Rect2(c.x - 80, c.y - 8, 160 * progress, 16), GREEN)
	draw_rect(Rect2(c.x - 80, c.y - 8, 160, 16), Color.WHITE, false, 2)
	text(Vector2(c.x, a.end.y - 12), "Alternate hands", 22)
