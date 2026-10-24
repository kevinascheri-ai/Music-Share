extends Node
## Autoload: player settings and local stats, saved to user://save.cfg.

signal changed

const PATH := "user://save.cfg"
const DEFAULT_SERVER := "ws://127.0.0.1:8787"

var slide_sensitivity := 1.0
var spin_sensitivity := 1.0
var sound := true
var ambience := true
var haptics := true
## "timer" (3 minutes, most goals wins) or "goals" (first to 5).
var match_mode := "timer"
var difficulty := "medium"
var server_url := DEFAULT_SERVER
var tutorial_seen := false
var player_name := "Player"
var stats := {
	"wins": 0, "losses": 0, "goals_for": 0, "goals_against": 0,
	"ai_wins": 0, "ai_losses": 0, "online_wins": 0, "online_losses": 0,
}


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	var f := ConfigFile.new()
	if f.load(PATH) != OK:
		return
	slide_sensitivity = f.get_value("settings", "slide_sensitivity", slide_sensitivity)
	spin_sensitivity = f.get_value("settings", "spin_sensitivity", spin_sensitivity)
	sound = f.get_value("settings", "sound", sound)
	ambience = f.get_value("settings", "ambience", ambience)
	haptics = f.get_value("settings", "haptics", haptics)
	match_mode = f.get_value("settings", "match_mode", match_mode)
	difficulty = f.get_value("settings", "difficulty", difficulty)
	server_url = f.get_value("settings", "server_url", server_url)
	tutorial_seen = f.get_value("settings", "tutorial_seen", tutorial_seen)
	player_name = f.get_value("settings", "player_name", player_name)
	for k in stats:
		stats[k] = int(f.get_value("stats", k, stats[k]))


func save() -> void:
	var f := ConfigFile.new()
	f.set_value("settings", "slide_sensitivity", slide_sensitivity)
	f.set_value("settings", "spin_sensitivity", spin_sensitivity)
	f.set_value("settings", "sound", sound)
	f.set_value("settings", "ambience", ambience)
	f.set_value("settings", "haptics", haptics)
	f.set_value("settings", "match_mode", match_mode)
	f.set_value("settings", "difficulty", difficulty)
	f.set_value("settings", "server_url", server_url)
	f.set_value("settings", "tutorial_seen", tutorial_seen)
	f.set_value("settings", "player_name", player_name)
	for k in stats:
		f.set_value("stats", k, stats[k])
	f.save(PATH)
	changed.emit()


func rules() -> Dictionary:
	return Match.RULES_GOALS if match_mode == "goals" else Match.RULES_TIMER


## Records a finished match. `kind` is "ai" or "online"; pass-and-play
## matches aren't recorded because both players share one device.
func record_result(kind: String, goals_for: int, goals_against: int, won: bool) -> void:
	stats.goals_for += goals_for
	stats.goals_against += goals_against
	var suffix := "wins" if won else "losses"
	stats[suffix] += 1
	stats["%s_%s" % [kind, suffix]] += 1
	save()


func haptic(ms: int) -> void:
	if haptics and OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)
