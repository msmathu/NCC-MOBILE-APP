extends ObstacleGame
## Obstacle 4 - Low Wire Crawl: swipe down to go prone, keep holding to crawl.
## Letting go under the wire snags the uniform.

var prone := false


func on_swipe(dir: Vector2) -> void:
	if dir == Vector2.DOWN and not prone:
		prone = true
		Sfx.play("thud")


func tick(d: float) -> void:
	if prone and holding:
		progress = minf(1.0, progress + d / 3.6)
		if progress >= 1.0:
			good()
			finish(faults == 0)
	elif prone and not holding:
		prone = false
		fault()
		progress = maxf(0.0, progress - 0.12)


func paint(a: Rect2) -> void:
	var c := a.get_center()
	var y := c.y + 10
	var x0 := a.position.x + 60
	var w := a.size.x - 120
	var wire := PackedVector2Array()
	for i in 31:
		wire.append(Vector2(x0 + i * w / 30.0, y - 30 + (5 if i % 2 == 0 else -5)))
	draw_polyline(wire, Color("9aa0a6"), 3)
	draw_rect(Rect2(x0, y + 10, w, 6), Color("5e3b1a"))
	draw_circle(Vector2(x0 + w * progress, y - (0 if prone else 40)), 14, GREEN if prone else GOLD)
	if not prone:
		arrow(Vector2(c.x, a.position.y + 50), Vector2.DOWN, 70, GOLD)
		text(Vector2(c.x, a.end.y - 12), "SWIPE DOWN, then keep HOLDING", 22)
	else:
		text(Vector2(c.x, a.end.y - 12), "HOLD... crawling %d%%" % int(progress * 100), 22, GREEN)
