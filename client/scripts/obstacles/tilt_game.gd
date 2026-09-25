extends ObstacleGame
## Obstacle 3 - Zig-Zag Balance: follow the weaving plank by tilting the phone.
## Holding the left / right side of the screen (or arrow keys) also steers.

var marker := 0.0
var tilt := 0.0
var off_time := 0.0


func _target(t: float) -> float:
	return sin(t * 1.7) * 0.55 + sin(t * 0.9 + 1.0) * 0.25


func on_tilt(v: float) -> void:
	tilt = v


func tick(d: float) -> void:
	var steer := tilt if absf(tilt) > 0.08 else float(hold_side)
	marker = clampf(marker + steer * 1.7 * d, -1.0, 1.0)
	if absf(marker - _target(elapsed)) < win(0.26):
		progress = minf(1.0, progress + d / 5.0)
	else:
		off_time += d
	if progress >= 1.0:
		good()
		finish(off_time < 1.5)


func paint(a: Rect2) -> void:
	var cx := a.get_center().x
	var half := a.size.x * 0.4
	var pts := PackedVector2Array()
	for i in 21:
		var k := i / 20.0 # 0 = far future (top), 1 = now (bottom)
		pts.append(Vector2(cx + _target(elapsed + (1.0 - k) * 1.4) * half, a.position.y + 10 + k * (a.size.y - 60)))
	# tolerance band as a filled strip (a very wide polyline breaks at the corners)
	var band := PackedVector2Array()
	var w := win(0.26) * half
	for p in pts:
		band.append(p - Vector2(w, 0))
	for i in range(pts.size() - 1, -1, -1):
		band.append(pts[i] + Vector2(w, 0))
	draw_colored_polygon(band, Color(GOLD, 0.3))
	draw_polyline(pts, Color("8b5a2b"), 8)
	var my := Vector2(cx + marker * half, a.end.y - 50)
	var on_path := absf(marker - _target(elapsed)) < win(0.26)
	draw_circle(my, 16, GREEN if on_path else BAD)
	text(Vector2(cx, a.end.y - 8), "TILT or hold ◀ ▶   %d%%" % int(progress * 100), 20)
