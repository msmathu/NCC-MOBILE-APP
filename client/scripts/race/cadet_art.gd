class_name CadetArt
## Procedurally drawn cadet (no sprite assets). Call from a CanvasItem's _draw().

const SKIN := Color("b97a4a")
const BOOT := Color("1b1b1b")
const UNIFORMS := {
	"army": {"shirt": Color("c3b091"), "pants": Color("a89770"), "belt": Color("3b2f1e")},
	"navy": {"shirt": Color("f4f4f0"), "pants": Color("e4e4de"), "belt": Color("1f2a44")},
	"air": {"shirt": Color("8fb3de"), "pants": Color("2c3e66"), "belt": Color("1a1a1a")},
}
const BERETS := {
	"maroon": Color("7b1e2b"), "black": Color("1a1a1a"), "blue": Color("1f4e9c"), "green": Color("2e6b30"),
}


## feet: ground contact point. phase: animation clock (radians). pose: run, idle,
## crawl, climb, balance, jump. gear: rifle + pack (level 3).
static func draw(ci: CanvasItem, feet: Vector2, look: Dictionary, phase: float, pose := "run",
		gear := false, alpha := 1.0, s := 1.0) -> void:
	var u: Dictionary = UNIFORMS.get(look.get("uniform", "army"), UNIFORMS.army)
	var shirt: Color = u.shirt
	var pants: Color = u.pants
	var beret: Color = BERETS.get(look.get("beret", "maroon"), BERETS.maroon)
	shirt.a = alpha
	pants.a = alpha
	beret.a = alpha
	var skin := Color(SKIN, alpha)
	var boot := Color(BOOT, alpha)
	var lw := 7.0 * s
	var hip: Vector2
	var shoulder: Vector2
	var legs: Array = [] # each: [knee, foot]
	var arms: Array = [] # each: [elbow, hand]

	match pose:
		"crawl":
			hip = feet + Vector2(-18, -14) * s
			shoulder = hip + Vector2(42, -4) * s
			var k := sin(phase)
			legs = [[hip + Vector2(-22, 4 + k * 3) * s, hip + Vector2(-44, 10) * s],
				[hip + Vector2(-20, 8 - k * 3) * s, hip + Vector2(-42, 12) * s]]
			arms = [[shoulder + Vector2(14 + k * 6, 6) * s, shoulder + Vector2(30 + k * 10, 12) * s],
				[shoulder + Vector2(12 - k * 6, 8) * s, shoulder + Vector2(26 - k * 10, 13) * s]]
		"climb":
			hip = feet + Vector2(0, -46) * s
			shoulder = hip + Vector2(4, -38) * s
			var k := sin(phase)
			legs = [[hip + Vector2(12, 10 + k * 8) * s, hip + Vector2(6, 38 + k * 8) * s],
				[hip + Vector2(12, 14 - k * 8) * s, hip + Vector2(8, 42 - k * 8) * s]]
			arms = [[shoulder + Vector2(10, -18 - k * 8) * s, shoulder + Vector2(12, -40 - k * 10) * s],
				[shoulder + Vector2(8, -14 + k * 8) * s, shoulder + Vector2(12, -32 + k * 10) * s]]
		"balance":
			var w := sin(phase * 0.7) * 0.15
			hip = feet + Vector2(0, -50) * s
			shoulder = hip + Vector2(w * 30, -38) * s
			legs = [[hip + Vector2(-6, 25) * s, feet + Vector2(-8, 0) * s], [hip + Vector2(6, 25) * s, feet + Vector2(8, 0) * s]]
			arms = [[shoulder + Vector2(-22, -4 + w * 40) * s, shoulder + Vector2(-44, -6 + w * 60) * s],
				[shoulder + Vector2(22, -4 - w * 40) * s, shoulder + Vector2(44, -6 - w * 60) * s]]
		"jump":
			hip = feet + Vector2(0, -56) * s
			shoulder = hip + Vector2(8, -36) * s
			legs = [[hip + Vector2(20, 6) * s, hip + Vector2(4, 30) * s], [hip + Vector2(16, 12) * s, hip + Vector2(-4, 34) * s]]
			arms = [[shoulder + Vector2(16, -18) * s, shoulder + Vector2(26, -38) * s], [shoulder + Vector2(-10, -16) * s, shoulder + Vector2(-8, -36) * s]]
		"idle":
			hip = feet + Vector2(0, -50) * s
			shoulder = hip + Vector2(0, -38) * s
			legs = [[hip + Vector2(-4, 25) * s, feet + Vector2(-5, 0) * s], [hip + Vector2(4, 25) * s, feet + Vector2(5, 0) * s]]
			arms = [[shoulder + Vector2(-8, 18) * s, shoulder + Vector2(-8, 36) * s], [shoulder + Vector2(8, 18) * s, shoulder + Vector2(8, 36) * s]]
		_: # run
			var bob := absf(sin(phase)) * 4.0
			hip = feet + Vector2(0, -50 - bob) * s
			shoulder = hip + Vector2(8, -37) * s
			for side in [1.0, -1.0]:
				var a: float = sin(phase) * 0.75 * side
				var knee := hip + Vector2(0, 26).rotated(-a) * s
				var bend := 0.9 if a < 0 else 0.1
				legs.append([knee, knee + Vector2(0, 26).rotated(-a + bend) * s])
				var b: float = -a * 0.9
				var elbow := shoulder + Vector2(0, 18).rotated(-b) * s
				arms.append([elbow, elbow + Vector2(0, 16).rotated(-b - 1.2) * s])

	var neck := shoulder + (shoulder - hip).normalized() * 6.0 * s
	var head := neck + (shoulder - hip).normalized() * 12.0 * s

	if gear: # pack and rifle sit behind the body
		var back := (hip + shoulder) * 0.5 - (shoulder - hip).orthogonal().normalized() * 12.0 * s
		var dir := (shoulder - hip).normalized()
		var pack := PackedVector2Array([
			back + dir * 18 * s + dir.orthogonal() * 9 * s, back + dir * 18 * s - dir.orthogonal() * 9 * s,
			back - dir * 14 * s - dir.orthogonal() * 9 * s, back - dir * 14 * s + dir.orthogonal() * 9 * s])
		ci.draw_colored_polygon(pack, Color(0.33, 0.36, 0.2, alpha))
		ci.draw_line(back + dir * 30 * s - dir.orthogonal() * 4 * s, back - dir * 26 * s + dir.orthogonal() * 6 * s, Color(0.25, 0.17, 0.1, alpha), 4.0 * s)

	# far limbs slightly darker
	_limb(ci, hip, legs[1], pants.darkened(0.25), boot, lw)
	_limb(ci, shoulder, arms[1], shirt.darkened(0.25), skin.darkened(0.2), lw * 0.8)
	# torso
	ci.draw_line(hip, shoulder, shirt, lw * 2.2, true)
	ci.draw_line(hip.lerp(shoulder, 0.08), hip.lerp(shoulder, 0.16), Color(u.belt, alpha), lw * 2.25)
	_limb(ci, hip, legs[0], pants, boot, lw)
	_limb(ci, shoulder, arms[0], shirt, skin, lw * 0.8)
	_badge(ci, hip.lerp(shoulder, 0.72) + (shoulder - hip).orthogonal().normalized() * -5.0 * s, look.get("badge", "none"), alpha, s)
	# head + beret (tilted to the right like a proper NCC beret)
	ci.draw_line(shoulder, neck, skin, lw * 0.9)
	ci.draw_circle(head, 11.0 * s, skin)
	var up := (shoulder - hip).normalized()
	var cap := head + up * 6.0 * s
	ci.draw_colored_polygon(PackedVector2Array([
		cap + up.orthogonal() * 13 * s + up * -1 * s, cap + up * 7 * s + up.orthogonal() * 4 * s,
		cap + up * 5 * s - up.orthogonal() * 10 * s, cap - up.orthogonal() * 12 * s - up * 2 * s]), beret)
	ci.draw_circle(cap + up * 3 * s + up.orthogonal() * -6 * s, 2.4 * s, Color(0.85, 0.7, 0.2, alpha))


static func _limb(ci: CanvasItem, root: Vector2, joints: Array, color: Color, end: Color, w: float) -> void:
	ci.draw_line(root, joints[0], color, w, true)
	ci.draw_line(joints[0], joints[1], color, w * 0.9, true)
	ci.draw_circle(joints[1], w * 0.55, end)


static func _badge(ci: CanvasItem, at: Vector2, badge: String, alpha: float, s: float) -> void:
	var gold := Color(0.95, 0.78, 0.2, alpha)
	match badge:
		"star":
			var pts := PackedVector2Array()
			for i in 10:
				var r := (5.0 if i % 2 == 0 else 2.2) * s
				pts.append(at + Vector2.from_angle(-PI / 2 + i * PI / 5) * r)
			ci.draw_colored_polygon(pts, gold)
		"eagle":
			ci.draw_polyline(PackedVector2Array([at + Vector2(-6, -2) * s, at + Vector2(-2, 1) * s, at, at + Vector2(2, 1) * s, at + Vector2(6, -2) * s]), gold, 2.0 * s)
		"ashoka":
			ci.draw_arc(at, 4.5 * s, 0, TAU, 16, Color(0.1, 0.2, 0.6, alpha), 1.6 * s)
			for i in 8:
				ci.draw_line(at, at + Vector2.from_angle(i * PI / 4) * 4.5 * s, Color(0.1, 0.2, 0.6, alpha), 1.0)
