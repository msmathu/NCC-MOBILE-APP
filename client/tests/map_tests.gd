extends Node
## Checks 300 generated Level 3 maps: exactly one safe route, restricted area
## clear of start/target, bridge not on the direct line, answers self-consistent.
##   godot --headless --path client res://tests/map_tests.tscn

func _ready() -> void:
	var MapRead := load("res://scripts/screens/mapread.gd")
	var bad := 0
	for seed in 300:
		var m: Control = MapRead.new()
		m.data = {"mode": "practice", "seed": seed + 1}
		m.rng.seed = seed + 1
		m._generate()
		m._build_steps()
		var ok_count := 0
		for k in m.routes:
			if m.routes[k].ok:
				ok_count += 1
		var problems := []
		if ok_count != 1: problems.append("safe routes=%d" % ok_count)
		if m.restricted.grow(0.3).has_point(m.start) or m.restricted.grow(0.3).has_point(m.target): problems.append("restricted too close")
		if m._path_hits_rect(m.routes[m.route_ok].pts, m.restricted): problems.append("safe route blocked")
		if m._crosses_river_off_bridge(m.routes[m.route_ok].pts): problems.append("safe route crosses river")
		if not m._crosses_river_off_bridge(PackedVector2Array([m.start, m.target])): problems.append("direct route has no river problem")
		if m.gr6(m.target).length() != 6 or m.gr4(m.start).length() != 4: problems.append("gr format")
		if not m._gr6_ok(m.gr6(m.start), m.start): problems.append("gr6 self-check")
		if problems.size() > 0:
			bad += 1
			if bad <= 5:
				print("seed %d: %s" % [seed + 1, ", ".join(problems)])
		m.free()
	print("RESULT: %s (%d bad of 300)" % ["PASS" if bad == 0 else "FAIL", bad])
	get_tree().quit(1 if bad else 0)
