extends ObstacleGame
## Obstacles 2, 7, 8 - Clear Jump / Right Hand Vault / Left Hand Vault.
## A marker sweeps the bar; swipe the required direction inside the gold zone.
## Vaults need RIGHT+UP (or LEFT+UP): a diagonal swipe, or the two in quick succession.

var need := Vector2.UP
var cursor := 0.0
var t := 0.0
var zone := 0.65
var speed := 0.85
var _last_side := Vector2.ZERO
var _last_side_at := -10.0


func setup(kind: String) -> void:
	if kind == "vault_r":
		need = Vector2(1, -1).normalized()
	elif kind == "vault_l":
		need = Vector2(-1, -1).normalized()
	_new_zone()


func _new_zone() -> void:
	zone = randf_range(0.5, 0.82)


func tick(d: float) -> void:
	t += d * speed
	cursor = 1.0 - absf(fmod(t, 2.0) - 1.0)


func on_swipe(dir: Vector2) -> void:
	var dir_ok := dir.dot(need) > 0.9
	# combo: side swipe then up within 0.6s
	if need.x != 0.0 and not dir_ok:
		if dir == Vector2(signf(need.x), 0):
			_last_side = dir
			_last_side_at = elapsed
			return
		if dir == Vector2.UP and elapsed - _last_side_at < 0.6 and _last_side.x == signf(need.x):
			dir_ok = true
	if dir_ok and absf(cursor - zone) <= win(0.075):
		good()
		finish(faults == 0)
	else:
		fault()
		speed = minf(speed + 0.1, 1.3)
		_new_zone()


func paint(a: Rect2) -> void:
	var bar := Rect2(a.position.x + 40, a.get_center().y - 18, a.size.x - 80, 36)
	draw_rect(bar, Color(0, 0, 0, 0.5))
	var zw := win(0.075) * bar.size.x
	draw_rect(Rect2(bar.position.x + zone * bar.size.x - zw, bar.position.y, zw * 2, bar.size.y), Color(GOLD, 0.8))
	var cx := bar.position.x + cursor * bar.size.x
	draw_rect(Rect2(cx - 4, bar.position.y - 10, 8, bar.size.y + 20), Color.WHITE)
	arrow(Vector2(a.get_center().x, a.position.y + 40), need, 70, GOLD)
	var label := "SWIPE UP" if need == Vector2.UP else ("RIGHT + UP" if need.x > 0 else "LEFT + UP")
	text(Vector2(a.get_center().x, a.end.y - 14), label + " in the gold zone", 22)
