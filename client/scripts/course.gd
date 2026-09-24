class_name Course
## Course geometry, obstacle catalogue and progression rules.
## KEEP IN SYNC with server/src/course.js.

const ROOM_SIZE := 7
const FIRST_OBSTACLE_X := 800.0
const OBSTACLE_SPACING := 1000.0
const OBSTACLE_PASS_WIDTH := 200.0
const OBSTACLE_COUNT := 15
const SPRINT_LENGTH := 1600.0
const FINISH_X := FIRST_OBSTACLE_X + (OBSTACLE_COUNT - 1) * OBSTACLE_SPACING + SPRINT_LENGTH
const GROUND_Y := 560.0
const RUN_SPEED := 260.0
const LEVEL_SPEED := [1.0, 0.88, 0.92] # level 3 carries rifle + pack
const MUD_SPEED := 0.5

const LEVELS := [
	{"name": "GROUND & BALANCE", "sub": "Basic Drill", "sky": Color("9fd3f0"), "ground": Color("8a9a5b")},
	{"name": "AGILITY & VAULTS", "sub": "Tactical Sprint", "sky": Color("b9d6e3"), "ground": Color("7a6a45")},
	{"name": "ENDURANCE & WALLS", "sub": "Camp Final", "sky": Color("f2c48d"), "ground": Color("9b8455")},
]

## kind -> mini-game script; hint -> action prompt shown on the HUD.
const OBSTACLES := [
	{"name": "Straight Balance", "kind": "balance", "hint": "Tap LEFT / RIGHT side on the beat to stay centred"},
	{"name": "Clear Jump", "kind": "timing", "hint": "Swipe UP when the marker is in the gold zone"},
	{"name": "Zig-Zag Balance", "kind": "tilt", "hint": "TILT the phone (or hold left / right) to follow the path"},
	{"name": "Low Wire Crawl", "kind": "crawl", "hint": "Swipe DOWN and HOLD to crawl under the wire"},
	{"name": "Ramp Climb", "kind": "mash", "hint": "TAP rapidly to build momentum"},
	{"name": "Gate Vault", "kind": "gate", "hint": "Swipe in the direction of the arrow"},
	{"name": "Right Hand Vault", "kind": "vault_r", "hint": "Swipe RIGHT + UP at the highlight mark"},
	{"name": "Left Hand Vault", "kind": "vault_l", "hint": "Swipe LEFT + UP at the highlight mark"},
	{"name": "Step Vault", "kind": "steps", "hint": "TAP each footstep target"},
	{"name": "Monkey Crawl Beam", "kind": "alternate", "hint": "Tap LEFT and RIGHT alternately"},
	{"name": "6ft High Wall", "kind": "wall", "hint": "Power TAP to pull up. Buddies nearby help!"},
	{"name": "Double Ditch Jump", "kind": "ditch", "hint": "HOLD to charge, release in the zone. Tap mid-air to stretch"},
	{"name": "Rope Climbing", "kind": "rope", "hint": "TAP on the beat to climb"},
	{"name": "Cargo Net", "kind": "net", "hint": "Use the D-pad (or swipe) to reach the top"},
	{"name": "Finish Line Sprint", "kind": "sprint", "hint": "TAP fast, but watch your stamina!"},
]

const DIRECTORATES := [
	"Andhra Pradesh & Telangana",
	"Bihar & Jharkhand",
	"Delhi",
	"Gujarat, DNH & DD",
	"Jammu & Kashmir & Ladakh",
	"Karnataka & Goa",
	"Kerala & Lakshadweep",
	"Madhya Pradesh & Chhattisgarh",
	"Maharashtra",
	"North Eastern Region",
	"Odisha",
	"Punjab, Haryana, HP & Chandigarh",
	"Rajasthan",
	"Tamil Nadu, Puducherry & A&N",
	"Uttar Pradesh",
	"Uttarakhand",
	"West Bengal & Sikkim",
]

const RANKS := [
	{"name": "Cadet", "dp": 0},
	{"name": "Lance Corporal", "dp": 300},
	{"name": "Corporal", "dp": 800},
	{"name": "Sergeant", "dp": 1600},
	{"name": "Under Officer", "dp": 3000},
	{"name": "Senior Under Officer", "dp": 5000},
]

## option -> rank index required
const UNLOCKS := {
	"uniform": {"army": 0, "navy": 1, "air": 2},
	"beret": {"maroon": 0, "black": 1, "blue": 2, "green": 3},
	"badge": {"none": 0, "star": 1, "eagle": 3, "ashoka": 5},
}

const LABELS := {
	"army": "Army Khaki", "navy": "Navy White", "air": "Air Wing Blue",
	"maroon": "Maroon", "black": "Black", "blue": "Blue", "green": "Green",
	"none": "No Badge", "star": "Star", "eagle": "Eagle", "ashoka": "Ashoka Chakra",
}

const CHEERS := ["👏", "🔥", "💪", "🙌", "🎖️", "😂", "🚀", "🫡"]

const ROLE_INFO := {
	"leader": {"name": "SUO / JUO", "desc": "Speed aura for nearby cadets"},
	"scout": {"name": "Scout", "desc": "Early warnings, wider timing windows"},
	"support": {"name": "Support", "desc": "Boosts cadets on the High Wall"},
	"cadet": {"name": "Cadet", "desc": ""},
}


## The camp competition: every match plays these three levels in order.
const CAMP_LEVELS := [
	{"key": "course", "title": "LEVEL 1 - OBSTACLE COURSE", "short": "L1 Course"},
	{"key": "range", "title": "LEVEL 2 - TARGET PRACTICE", "short": "L2 Range"},
	{"key": "map", "title": "LEVEL 3 - MAP READING", "short": "L3 Map"},
]
## Camp points for 1st..7th in each level (server/src/course.js STAGE_POINTS).
const STAGE_POINTS := [10, 8, 6, 5, 4, 3, 2]


const STAGE_MAX := {"range": 100, "map": 1000}

## Level 2 firing positions. Game effects only: sway = aim movement,
## speed = how quickly the sight swings between target sheets, recoil = kick.
const STANCES := {
	"standing": {"name": "STANDING", "sway": 1.4, "speed": 1.35, "recoil": 0.16,
		"desc": "Most aim movement\nFastest between targets"},
	"kneeling": {"name": "KNEELING", "sway": 1.0, "speed": 1.0, "recoil": 0.12,
		"desc": "Balanced movement\nand steadiness"},
	"lying": {"name": "LYING", "sway": 0.6, "speed": 0.62, "recoil": 0.08,
		"desc": "Steadiest aim\nSlowest between targets"},
}


## Level 2 stars out of 100: 0 = not qualified, 1 qualified, 2 good, 3 excellent.
static func range_stars(score: int) -> int:
	if score >= 90:
		return 3
	if score >= 80:
		return 2
	if score >= 70:
		return 1
	return 0


## Qualification grade for a Level 2 score (max 100).
static func qualification(score: int) -> String:
	return ["NOT QUALIFIED", "QUALIFIED", "GOOD", "EXCELLENT"][range_stars(score)]


## Same formula as the server's bots (skill 0.82..1.12): range ~45-95 of 100, map ~400-950 of 1000.
static func bot_stage_score(skill: float, stage: String) -> int:
	var k := (skill - 0.82) / 0.3
	if stage == "range":
		return int(round(clampf(45.0 + k * 45.0 + randf_range(-10.0, 10.0), 20.0, 98.0)))
	return int(round(clampf(400.0 + k * 500.0 + randf_range(-120.0, 120.0), 150.0, 980.0) / 10.0)) * 10


static func obstacle_x(i: int) -> float:
	return FIRST_OBSTACLE_X + i * OBSTACLE_SPACING


static func level_of_obstacle(i: int) -> int:
	return clampi(i / 5, 0, 2)


## Level the runner is in at world x (level changes halfway between obstacle 4/5 and 9/10).
static func level_at(x: float) -> int:
	if x < obstacle_x(5) - OBSTACLE_SPACING * 0.5:
		return 0
	if x < obstacle_x(10) - OBSTACLE_SPACING * 0.5:
		return 1
	return 2


## Mud patches slow runners in level 2: one patch in the middle of each run segment.
static func in_mud(x: float) -> bool:
	for i in range(5, 10):
		var start := obstacle_x(i) + OBSTACLE_PASS_WIDTH + 250.0
		if x >= start and x <= start + 260.0:
			return true
	return false


static func rank_index(dp: int) -> int:
	var idx := 0
	for i in RANKS.size():
		if dp >= RANKS[i].dp:
			idx = i
	return idx


static func format_ms(ms: float) -> String:
	if ms < 0:
		return "--:--"
	var total := int(ms / 1000.0)
	return "%d:%02d.%d" % [total / 60, total % 60, int(fmod(ms, 1000.0) / 100.0)]


## Port of server planBot(): precomputed (time, x) keyframes for practice-mode bots.
static func plan_bot(skill: float) -> Dictionary:
	var frames := [{"t": 0.0, "x": 0.0, "st": "run"}]
	var t := 0.0
	var x := 0.0
	for i in OBSTACLE_COUNT - 1:
		var pace: float = RUN_SPEED * skill * LEVEL_SPEED[level_of_obstacle(i)]
		t += (obstacle_x(i) - x) / pace * 1000.0
		x = obstacle_x(i)
		frames.append({"t": t, "x": x, "st": "run"})
		t += randf_range(2.6, 6.2) / skill * 1000.0
		frames.append({"t": t, "x": x, "st": "ob%d" % i})
		t += 600.0
		x += OBSTACLE_PASS_WIDTH
		frames.append({"t": t, "x": x, "st": "run"})
	var last := obstacle_x(OBSTACLE_COUNT - 1)
	t += (last - x) / (RUN_SPEED * skill * 0.92) * 1000.0
	frames.append({"t": t, "x": last, "st": "run"})
	t += SPRINT_LENGTH / (randf_range(300.0, 360.0) * skill) * 1000.0
	frames.append({"t": t, "x": FINISH_X, "st": "ob14"})
	return {"frames": frames, "finish_ms": t}


static func sample_bot(plan: Dictionary, elapsed: float) -> Array:
	var f: Array = plan.frames
	if elapsed >= plan.finish_ms:
		return [1.0, "done"]
	for i in range(1, f.size()):
		if elapsed <= f[i].t:
			var a: Dictionary = f[i - 1]
			var b: Dictionary = f[i]
			var k: float = 1.0 if b.t == a.t else (elapsed - a.t) / (b.t - a.t)
			return [(a.x + (b.x - a.x) * k) / FINISH_X, b.st]
	return [1.0, "done"]


## Level 3 map-reading grade out of 1000.
static func map_grade(score: int) -> String:
	if score >= 900:
		return "EXCELLENT"
	if score >= 700:
		return "QUALIFIED"
	if score >= 500:
		return "TRAINING REQUIRED"
	return "RETRAIN"
