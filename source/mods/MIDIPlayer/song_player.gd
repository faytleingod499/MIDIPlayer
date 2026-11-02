extends Node

# Plays a list of guitar strums in time. Every strum is the game's own guitar signal, the same one the guitar menu
# emits when you press a string key: PlayerData._play_guitar(string, fret, volume). The game then plays the sound and
# sends it to the other players itself, so everybody hears it exactly like a hand-played note.
#
# events: [[time_s, string, fret, volume], ...] sorted by time (see guitar_map.gd)

signal note_fired(string, fret, volume)
signal finished

const MAX_DELTA = 0.2    # a long frame (loading, alt-tab) moves the song on by at most this much real time
const MAX_LATE = 0.5     # strums more than this late (in song time) are skipped instead of played in a burst

var events = []
var end_time = 0.0
var clock = 0.0          # song time in seconds
var pos = 0              # index of the next strum
var playing = false
var speed = 1.0
var skipped = 0
var fired = 0
var auto = true          # false in tests: they call tick() themselves
var _pd = null


func _ready():
	set_process(auto)


func _process(delta):
	tick(delta)


func load_events(ev, duration):
	events = ev
	end_time = duration
	if not events.empty():
		end_time = max(end_time, events[events.size() - 1][0] + 0.25)
	playing = false
	skipped = 0
	seek(0.0)


func has_song():
	return not events.empty()


func play():
	if events.empty():
		return
	if clock >= end_time:
		seek(0.0)
	playing = true


func pause():
	playing = false


func stop():
	playing = false
	seek(0.0)


func seek(t):
	clock = clamp(t, 0.0, end_time)
	var lo = 0
	var hi = events.size()
	while lo < hi:   # first strum at or after the new position
		var mid = (lo + hi) >> 1
		if events[mid][0] < clock:
			lo = mid + 1
		else:
			hi = mid
	pos = lo


func tick(delta):
	if not playing:
		return
	clock += min(delta, MAX_DELTA) * speed
	while pos < events.size() and events[pos][0] <= clock:
		var e = events[pos]
		pos += 1
		if clock - e[0] > MAX_LATE:
			skipped += 1
			continue
		_fire(e[1], e[2], e[3])
	if clock >= end_time:
		clock = end_time
		playing = false
		emit_signal("finished")


func _fire(s, f, v):
	if s < 0 or s > 5 or f < 0 or f > 15:
		return
	fired += 1
	if _pd == null or not is_instance_valid(_pd):
		_pd = get_node_or_null("/root/PlayerData")
	if _pd != null:
		_pd.emit_signal("_play_guitar", s, f, v)
	emit_signal("note_fired", s, f, v)
