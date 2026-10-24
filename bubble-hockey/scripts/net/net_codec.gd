class_name NetCodec
extends RefCounted
## Validation and compaction for messages between host and guest. Anything
## that arrives over the network goes through here before the game uses it.

const MAX_GOALS := 20
const MIN_SECONDS := 30.0
const MAX_SECONDS := 900.0
const EVENT_KEYS := ["team", "winner"]


## Rod input from the guest: one [target_x, has_angle, target_angle] per rod.
## Returns null when the message is malformed, so the caller keeps the last
## good input. Range limits are enforced again by Rod.set_input().
static func parse_input(r, rods_per_team: int) -> Variant:
	if typeof(r) != TYPE_ARRAY or r.size() != rods_per_team:
		return null
	var out := []
	for e in r:
		if typeof(e) != TYPE_ARRAY or e.size() != 3:
			return null
		if not _is_number(e[0]) or not _is_number(e[2]):
			return null
		var x := float(e[0])
		var a := float(e[2])
		if is_nan(x) or is_nan(a) or is_inf(x) or is_inf(a):
			return null
		out.append([x, bool(e[1]), a])
	return out


## Match rules sent by the host. Unknown or out-of-range values fall back to
## sane defaults instead of being trusted.
static func parse_rules(rules) -> Dictionary:
	if typeof(rules) != TYPE_DICTIONARY:
		return Match.RULES_TIMER
	if rules.get("mode") == "goals":
		var goals = rules.get("goals", 5)
		return {"mode": "goals", "goals": clampi(int(goals) if _is_number(goals) else 5, 1, MAX_GOALS)}
	var seconds = rules.get("seconds", 180.0)
	return {"mode": "timer", "seconds": clampf(float(seconds) if _is_number(seconds) else 180.0, MIN_SECONDS, MAX_SECONDS)}


## Checks a host snapshot's shape before the guest loads it.
static func valid_snapshot(d: Dictionary, rod_count: int) -> bool:
	var s = d.get("s")
	var m = d.get("m")
	if not _is_number(d.get("n")) or typeof(s) != TYPE_ARRAY or typeof(m) != TYPE_ARRAY:
		return false
	if s.size() != 3 or m.size() != 8 or typeof(d.get("e", [])) != TYPE_ARRAY:
		return false
	if not _numbers(s[0], 4) or typeof(s[1]) != TYPE_BOOL or typeof(s[2]) != TYPE_ARRAY or s[2].size() != rod_count:
		return false
	for r in s[2]:
		if not _numbers(r, 4):
			return false
	for i in [0, 1, 2, 3, 4, 6]:
		if not _is_number(m[i]):
			return false
	if int(m[3]) < 0 or int(m[3]) >= Match.Phase.size():
		return false
	for e in d.get("e", []):
		if typeof(e) != TYPE_DICTIONARY or typeof(e.get("type")) != TYPE_STRING:
			return false
	return typeof(m[5]) == TYPE_BOOL and typeof(m[7]) == TYPE_BOOL


## Only what the guest needs to play sounds and show banners.
static func slim_event(e: Dictionary) -> Dictionary:
	var out := {"type": e.type}
	for k in EVENT_KEYS:
		if e.has(k):
			out[k] = e[k]
	if e.has("strength"):
		out.strength = snappedf(e.strength, 1.0)
	return out


## Rounds floats to 0.01 (recursively) to keep snapshots small.
static func round_floats(v):
	if typeof(v) == TYPE_ARRAY:
		var out := []
		for x in v:
			out.append(round_floats(x))
		return out
	if typeof(v) == TYPE_FLOAT:
		return snappedf(v, 0.01)
	return v


static func _numbers(a, n: int) -> bool:
	if typeof(a) != TYPE_ARRAY or a.size() != n:
		return false
	for v in a:
		if not _is_number(v):
			return false
	return true


static func _is_number(v) -> bool:
	return typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT
