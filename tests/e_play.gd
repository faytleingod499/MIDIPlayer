extends SceneTree
# Tests the clock that fires the strums (song_player.gd), and that a strum reaches the game's own guitar code:
# the real PlayerData signal -> the real player scene's _strum_guitar -> the real string sound script.

var checks = 0
var fails = 0
var got = []      # strums seen on PlayerData._play_guitar: [string, fret, volume, song clock]
var Song = null
var cur = null


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
	var wd = create_timer(120.0)
	wd.connect("timeout", self, "_watchdog")


func _watchdog():
	print("FAIL watchdog: the test did not reach its end (a script error above?)")
	print("SUMMARY %d checks, %d failed" % [checks, fails + 1])
	quit()


func on_strum(s, f, v):
	got.append([s, f, v, cur.clock if cur != null else -1.0])


func make(events, duration = 0.0):
	var p = Song.new()
	p.auto = false
	root.add_child(p)
	p.load_events(events, duration)
	cur = p
	got = []
	return p


func run_for(p, seconds, dt = 1.0 / 60.0):
	var t = 0.0
	while t < seconds:
		p.tick(dt)
		t += dt


func _go():
	var NW = root.get_node("Network")
	NW.STEAM_ID = 4242
	NW.STEAM_LOBBY_ID = 0
	NW.PLAYING_OFFLINE = true
	NW.OWNED_ACTORS = []
	var PD = root.get_node("PlayerData")
	PD.connect("_play_guitar", self, "on_strum")
	Song = load("res://mods/MIDIPlayer/song_player.gd")

	var ev = []
	for i in 20:
		ev.append([1.0 + i * 0.25, i % 6, i % 16, 0.5 + 0.02 * i])
	var p = make(ev, 7.0)
	ok(p.end_time == 7.0 and p.clock == 0.0 and p.pos == 0 and not p.playing, "loaded: stopped at 0, length 7 s")
	run_for(p, 2.0)
	ok(got.size() == 0, "not playing: no strums")
	p.play()
	run_for(p, 2.0)
	ok(p.playing and got.size() == 5, "after 2 s of playing: the 5 strums at 1.0 .. 2.0 s (%d)" % got.size())
	var exact = true
	for i in got.size():
		var e = ev[i]
		if got[i][0] != e[1] or got[i][1] != e[2] or abs(got[i][2] - e[3]) > 1e-6:
			exact = false
		if got[i][3] < e[0] or got[i][3] > e[0] + 0.05:
			exact = false   # fired when the clock reached it, within one frame
	ok(exact, "each strum has the string, fret and volume asked, and is fired within one frame of its time")
	p.pause()
	var n = got.size()
	run_for(p, 3.0)
	ok(got.size() == n and not p.playing, "paused: nothing happens")
	var c = p.clock
	p.play()
	run_for(p, 0.5)
	ok(p.clock > c + 0.49 and p.clock < c + 0.53, "play again continues from where it stopped")
	var seen = {}
	var dup = false
	for g in got:
		var k = "%d.%d.%.2f" % [g[0], g[1], g[2]]
		seen[k] = true
	ok(got.size() == 7, "nothing fires twice: 7 strums so far (%d)" % got.size())
	run_for(p, 10.0)
	ok(got.size() == 20, "all 20 strums fired")
	ok(not p.playing and p.clock == p.end_time, "the song ended: stopped at the end")

	# finished signal, once; play again restarts
	var fin = [0]
	p = make(ev, 7.0)
	p.connect("finished", self, "_count", [fin])
	p.play()
	run_for(p, 9.0)
	ok(fin[0] == 1, "finished is sent once")
	p.play()
	ok(p.clock == 0.0 and p.playing, "play after the end starts again from 0")
	run_for(p, 1.3)
	ok(got.size() == 20 + 2, "...and the first strums come again (%d)" % got.size())

	# seeking
	p = make(ev, 7.0)
	p.seek(3.0)
	ok(p.pos == 8 and p.clock == 3.0, "seek to 3 s: next strum is number 9 (1.0 + 8 * 0.25 = 3.0)")
	p.seek(3.01)
	ok(p.pos == 9, "seek just past a strum: it is skipped")
	p.seek(0.0)
	ok(p.pos == 0, "seek back to 0")
	p.seek(99.0)
	ok(p.clock == 7.0 and p.pos == 20, "seek past the end: the end")
	p.seek(-5.0)
	ok(p.clock == 0.0, "seek before the start: 0")
	p.seek(3.0)
	p.play()
	run_for(p, 0.3)
	ok(got.size() == 2 and got[0][1] == 8 % 16, "play from 3 s: only the later strums (%d)" % got.size())
	p.stop()
	ok(p.clock == 0.0 and p.pos == 0 and not p.playing, "stop: back to the start")

	# speed
	p = make(ev, 7.0)
	p.speed = 2.0
	p.play()
	run_for(p, 1.0)
	ok(abs(p.clock - 2.0) < 0.02 and got.size() == 5, "speed 2: one second of real time is 2 s of song")
	p = make(ev, 7.0)
	p.speed = 0.5
	p.play()
	run_for(p, 4.0)
	ok(abs(p.clock - 2.0) < 0.02 and got.size() == 5, "speed 0.5: 4 seconds of real time is 2 s of song")

	# a long frame (the game stalls) moves the song on by at most MAX_DELTA
	p = make(ev, 7.0)
	p.play()
	p.tick(5.0)
	ok(abs(p.clock - 0.2) < 1e-6, "a 5 s stall advances the song by only 0.2 s")
	# strums that are very late are skipped
	p = make(ev, 7.0)
	p.playing = true
	p.clock = 3.0
	p.pos = 0
	p.tick(0.001)
	ok(p.skipped > 0 and got.size() <= 4, "strums more than 0.5 s late are skipped, not played in a burst (skipped %d, played %d)" % [p.skipped, got.size()])
	# bad strums are never sent
	p = make([[0.1, 9, 3, 1.0], [0.2, 2, 99, 1.0], [0.3, -1, 0, 1.0], [0.4, 2, 3, 1.0]], 1.0)
	p.play()
	run_for(p, 1.2)
	ok(got.size() == 1 and got[0][0] == 2 and got[0][1] == 3, "string 9, fret 99 and string -1 are never sent; the good one is")
	# nothing to play
	p = make([], 0.0)
	p.play()
	run_for(p, 1.0)
	ok(not p.has_song() and not p.playing and got.empty(), "an empty song does nothing")
	# the real-time path (_process) works too
	p = Song.new()
	root.add_child(p)
	cur = p
	got = []
	p.load_events([[0.1, 1, 1, 1.0], [0.3, 2, 2, 1.0]], 0.5)
	p.play()
	yield(create_timer(0.9), "timeout")
	ok(got.size() == 2 and not p.playing, "real time: the strums come by themselves and the song ends")

	# end to end: the real player scene reacts to the strum like it does to a hand-played one
	var pl = load("res://Scenes/Entities/Player/player.tscn").instance()
	root.add_child(pl)
	for i in 3:
		yield(self, "idle_frame")
	pl.in_zone = true
	PD.connect("_play_guitar", pl, "_strum_guitar")   # what the game does for the player you control
	var sounds = pl.get_node("guitar_sounds")
	p = make([[0.0, 2, 7, 0.8], [0.1, 5, 15, 1.0], [0.2, 0, 0, 0.4]], 0.5)
	p.play()
	run_for(p, 0.6)
	for i in 3:
		yield(self, "idle_frame")
	var s2 = sounds.get_child(2)
	var s5 = sounds.get_child(5)
	var s0 = sounds.get_child(0)
	ok(s2.current_fret == 8 and s5.current_fret == 16 and s0.current_fret == 1, "the real guitar sound script got string 2 fret 7, string 5 fret 15 (the highest) and string 0 open")
	var playing_ok = true
	for sp in [s2, s5, s0]:
		var any = false
		for sub in sp.sound_array:
			if sub.playing:
				any = true
		if not any:
			playing_ok = false
	ok(playing_ok, "...and each of those strings is playing a sound")
	var vol_ok = false
	for sub in s2.sound_array:
		if sub.playing and abs(sub.max_db - linear2db(0.8 * 0.32)) < 0.01:
			vol_ok = true
	ok(vol_ok, "...at the volume asked (0.8 of the game's guitar level)")
	ok(abs(s5.end_point - (17 * 7.38 - 0.01)) < 0.001 and s5.end_point < 132.9, "fret 15 ends inside the sound file (132.9 s)")
	print("SUMMARY %d checks, %d failed" % [checks, fails])
	quit()


func _count(box):
	box[0] += 1
