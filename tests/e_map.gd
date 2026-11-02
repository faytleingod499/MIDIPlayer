extends SceneTree
# Tests the string / fret choice (guitar_map.gd) with notes built by hand.

var checks = 0
var fails = 0
var Map = null
const OPEN = [40, 45, 50, 55, 59, 64]


func ok(c, label):
	checks += 1
	if c:
		print("ok   ", label)
	else:
		fails += 1
		print("FAIL ", label)


func _init():
	var pck = OS.get_environment("MP_PCK")   # test the built pck instead of the source folder
	if pck != "":
		print("note  mounting ", pck, ": ", ProjectSettings.load_resource_pack(pck))
	call_deferred("_go")


# a note: [start, end, pitch, velocity, track, channel]
func N(t, dur, pitch, vel = 100, track = 0, ch = 0):
	return [t, t + dur, pitch, vel, track, ch]


func build(notes, opts = {}):
	var o = {"auto_octave": false, "semitones": 0, "fold": false}
	for k in opts:
		o[k] = opts[k]
	return Map.new().build(notes, o)


func pitch_of(e):
	return OPEN[e[1]] + e[2]


func all_valid(ev):
	for e in ev:
		if e[1] < 0 or e[1] > 5 or e[2] < 0 or e[2] > 15:
			return false
		if e[3] < 0.1 or e[3] > 1.0:
			return false
	return true


func _go():
	Map = load("res://mods/MIDIPlayer/guitar_map.gd")
	# every pitch of the range has a place, and nothing outside it has
	var all_ok = true
	for p in range(40, 80):
		var c = Map.candidates(p)
		if c.empty():
			all_ok = false
		for x in c:
			if OPEN[x[0]] + x[1] != p or x[1] < 0 or x[1] > 15:
				all_ok = false
	ok(all_ok, "pitches 40..79: every one has a string and fret that give exactly that pitch")
	ok(Map.candidates(39).empty() and Map.candidates(80).empty(), "39 and 80 can't be played")

	# a melody inside the range
	var notes = []
	for i in 13:
		notes.append(N(i * 0.5, 0.4, 60 + i))
	var m = build(notes)
	ok(m["played"] == 13 and m["total"] == 13, "melody: all 13 notes played")
	var same = true
	for i in 13:
		if pitch_of(m["events"][i]) != 60 + i:
			same = false
	ok(same, "melody: every strum gives the pitch of its note, in order")
	ok(all_valid(m["events"]), "melody: strings 0-5, frets 0-15, volumes 0.1-1")

	# out of range
	notes = [N(0, 0.5, 36), N(1, 0.5, 60), N(2, 0.5, 96)]
	m = build(notes)
	ok(m["played"] == 1 and m["out_of_range"] == 2, "out of range, no folding: 2 left out")
	m = build(notes, {"fold": true})
	ok(m["played"] == 3 and m["folded"] == 2, "out of range, folding: all 3 played, 2 folded")
	var cls = true
	var want = [36, 60, 96]
	for i in 3:
		if pitch_of(m["events"][i]) % 12 != want[i] % 12:
			cls = false
	ok(cls, "folded notes keep their note name (same pitch class)")
	# auto octave
	notes = []
	for i in 13:
		notes.append(N(i * 0.4, 0.3, 84 + i * 2 if i < 12 else 100))   # 84 .. 106 and 100
	m = build(notes, {"auto_octave": true})
	ok(m["octaves"] == -3 and m["played"] == 13 and m["folded"] == 0, "high song: moved 3 octaves down, nothing folded (octaves=%d)" % m["octaves"])
	notes = []
	for i in 10:
		notes.append(N(i * 0.4, 0.3, 55 + i))
	m = build(notes, {"auto_octave": true})
	ok(m["octaves"] == 0, "song inside the range: no shift")
	notes = [N(0, 0.3, 10), N(0.4, 0.3, 12), N(0.8, 0.3, 14)]
	m = build(notes, {"auto_octave": true})
	ok(m["octaves"] == 3 and m["played"] == 3, "very low song: moved up 3 octaves (4 would fit too, the smaller shift wins), all played")
	# semitones
	notes = [N(0, 0.4, 60), N(0.5, 0.4, 62)]
	m = build(notes, {"semitones": 3})
	ok(pitch_of(m["events"][0]) == 63 and pitch_of(m["events"][1]) == 65, "pitch +3 semitones")
	m = build(notes, {"semitones": -12})
	ok(pitch_of(m["events"][0]) == 48, "pitch -12 semitones")

	# chords
	notes = []
	for p in OPEN:
		notes.append(N(0, 1.0, p))
	m = build(notes)
	var used = {}
	for e in m["events"]:
		used[e[1]] = true
	ok(m["played"] == 6 and used.size() == 6, "6 note chord (the open strings): 6 different strings")
	notes = [N(0, 1, 48), N(0, 1, 52), N(0, 1, 55), N(0, 1, 60), N(0, 1, 64)]
	m = build(notes)
	used = {}
	for e in m["events"]:
		used[e[1]] = true
	ok(m["played"] == 5 and used.size() == 5 and all_valid(m["events"]), "C major chord: 5 notes on 5 different strings")
	notes = [N(0, 1, 60), N(0.01, 1, 64), N(0.02, 1, 67)]
	m = build(notes)
	used = {}
	for e in m["events"]:
		used[e[1]] = true
	ok(m["played"] == 3 and used.size() == 3, "a slightly spread chord (10 ms apart) still uses 3 strings")
	# more than 6 at once: keep the highest, the lowest and the loudest of the rest
	notes = []
	for i in 9:
		notes.append(N(0, 1, 45 + i * 3, 50 + i))
	m = build(notes)
	var ps = []
	for e in m["events"]:
		ps.append(pitch_of(e))
	ps.sort()
	ok(m["played"] == 6 and m["too_many"] == 3, "9 at once: 6 played, 3 left out")
	ok(ps.front() == 45 and ps.back() == 69, "9 at once: the lowest and highest notes are kept")
	# two notes that can only be on the same string
	m = build([N(0, 1, 79), N(0, 1, 78)])
	ok(m["played"] == 1 and m["too_many"] == 1, "79 and 78 together: both need the top string, one is left out")
	# the same pitch twice at once is one strum
	m = build([N(0, 1, 60, 50), N(0, 1, 60, 90)])
	ok(m["played"] == 1, "the same note twice at once: one strum")

	# a held note is not cut while another string is free
	notes = [N(0, 4.0, 52), N(1, 0.3, 64), N(2, 0.3, 64), N(3, 0.3, 64), N(1.5, 0.3, 57), N(2.5, 0.3, 50)]
	m = build(notes)
	var held = m["events"][0][1]
	var cut = false
	for e in m["events"]:
		if e[0] > 0.0 and e[0] < 4.0 and e[1] == held:
			cut = true
	ok(m["played"] == 6 and not cut, "a note held for 4 s keeps its string while other strings are free")
	# when all 6 strings are held, a new note still plays (it has to cut one)
	notes = []
	for p in OPEN:
		notes.append(N(0, 5.0, p))
	notes.append(N(1, 0.5, 52))
	m = build(notes)
	ok(m["played"] == 7, "all strings held: the 7th note is played, cutting one")
	# it cuts the one that ends soonest
	notes = []
	for i in 6:
		notes.append(N(0, 1.0 + i, OPEN[i]))   # string 0 ends at 1 s ... string 5 at 6 s
	notes.append(N(0.5, 0.3, 45))              # can be string 0 (fret 5) or string 1 (fret 0)
	m = build(notes)
	var last = m["events"][m["events"].size() - 1]
	for e in m["events"]:
		if e[0] == 0.5:
			last = e
	ok(last[1] == 0, "...the string whose note ends first (string 0 ends at 1 s, string 1 at 2 s)")

	# only the chosen tracks, never the drum channel
	notes = [N(0, 0.4, 60, 100, 0, 0), N(0.5, 0.4, 62, 100, 1, 0), N(1, 0.4, 64, 100, 2, 0), N(1.5, 0.4, 62, 100, 3, 9)]
	m = build(notes, {"tracks": {1: true, 2: true}})
	ok(m["total"] == 2 and m["played"] == 2, "tracks 1 and 2 only: 2 notes")
	m = build(notes)
	ok(m["total"] == 3, "all tracks: 3 notes, the drum channel never counts")
	m = build(notes, {"tracks": {}})
	ok(m["total"] == 0 and m["events"].empty(), "no tracks: nothing")

	# volume from velocity
	m = build([N(0, 0.3, 60, 127), N(1, 0.3, 60, 1), N(2, 0.3, 60, 64)])
	ok(abs(m["events"][0][3] - 1.0) < 0.001 and m["events"][1][3] > 0.39 and m["events"][1][3] < 0.42 and m["events"][2][3] > m["events"][1][3] and m["events"][2][3] < 1.0, "velocity 127 is full volume, 1 is about 0.4, in between in between")

	# the network limit: 50 strums per second asked, 48 allowed
	notes = []
	for i in 150:
		notes.append(N(i * 0.02, 0.01, 60 + (i % 10)))
	m = build(notes)
	var worst = 0
	for i in m["events"].size():
		var c = 0
		for j in range(i, m["events"].size()):
			if m["events"][j][0] - m["events"][i][0] < 1.0:
				c += 1
			else:
				break
		worst = max(worst, c)
	ok(worst <= 48 and m["too_fast"] > 0 and m["played"] + m["too_fast"] == 150, "50 notes a second: never more than 48 strums in any second (%d dropped, worst second %d)" % [m["too_fast"], worst])
	notes = []
	for i in 40:
		notes.append(N(i * 0.1, 0.05, 60 + (i % 10)))
	m = build(notes)
	ok(m["too_fast"] == 0, "10 notes a second: none dropped")

	# a big random song: valid, in order, and not slow
	seed(99)
	notes = []
	var t = 0.0
	for i in 100000:
		t += randf() * 0.01
		notes.append(N(t, randf() * 2.0, 30 + randi() % 80, 1 + randi() % 127))
	var t0 = OS.get_ticks_msec()
	m = Map.new().build(notes, {"auto_octave": true, "fold": true})
	var ms = OS.get_ticks_msec() - t0
	print("note  100000 random dense notes mapped in %d ms" % ms)
	var sorted = true
	for i in range(1, m["events"].size()):
		if m["events"][i][0] < m["events"][i - 1][0]:
			sorted = false
	ok(all_valid(m["events"]) and sorted and m["played"] > 0, "random song: every strum valid and in time order")
	ok(ms < 30000, "random song of 100000 notes mapped in %d ms" % ms)
	print("SUMMARY %d checks, %d failed" % [checks, fails])
	quit()
