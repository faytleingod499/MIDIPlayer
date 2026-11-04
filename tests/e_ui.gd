extends SceneTree
# Tests the whole mod inside the game's real guitar menu scene: finding the menu, the window, importing, the list,
# playing, options, closing and opening the menu again, and files that are not what they say.
# The HUD and the player are stand-ins (stub_hud.gd, stub_player.gd); the guitar menu and PlayerData are the game's own.

var checks = 0
var fails = 0
var S = null
var mod = null
var D = ""
var strums = []
var LIB = "user://MIDIPlayer"
var Tmp = ""


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
	var wd = create_timer(300.0)   # a script error in the middle of a test stops it silently: end the run instead of hanging
	wd.connect("timeout", self, "_watchdog")


func _watchdog():
	print("FAIL watchdog: the test did not reach its end (a script error above?)")
	print("SUMMARY %d checks, %d failed" % [checks, fails + 1])
	quit()


func on_strum(s, f, v):
	strums.append([s, f, v])


func frames(n):
	for i in n:
		yield(self, "idle_frame")


func click(btn):
	btn.emit_signal("pressed")


func bytes_of(path):
	var f = File.new()
	if f.open(path, File.READ) != OK:
		return PoolByteArray()
	var b = f.get_buffer(f.get_len())
	f.close()
	return b


func put(path, bytes):
	var f = File.new()
	f.open(path, File.WRITE)
	f.store_buffer(bytes)
	f.close()


func exists(path):
	return File.new().file_exists(path)


func lib_files():
	var out = []
	var d = Directory.new()
	d.open(LIB)
	d.list_dir_begin(true, true)
	var f = d.get_next()
	while f != "":
		if not d.current_is_dir() and f.get_extension() == "mid":
			out.append(f)
		f = d.get_next()
	d.list_dir_end()
	out.sort()
	return out


func names():
	var out = []
	for s in mod.songs:
		out.append(s["name"])
	return out


# the strings that show a marker on the guitar menu: string -> fret (-1 = none)
func markers():
	var out = [-1, -1, -1, -1, -1, -1]
	for row in S.minigame.get_node("fret_main/neck").get_children():
		for b in row.get_children():
			if b is Button and b.get("string") != null:
				if b.get_node("TextureRect").visible:
					out[b.string] = b.fret
	return out


func _go():
	D = OS.get_environment("MIDI_DIR")
	Tmp = D + "/tmp"
	Directory.new().make_dir_recursive(Tmp)
	S = load(OS.get_environment("TESTS_DIR") + "/ui_setup.gd").new()
	S.wipe_library()
	S.prepare(self)
	root.get_node("PlayerData").connect("_play_guitar", self, "on_strum")
	mod = S.start_mod(true)
	mod.player.set_process(false)   # the tests move the song clock themselves
	var P = mod.player

	# ---- finding the menu
	yield(create_timer(0.6), "timeout")
	ok(mod.window == null and mod.minigame == null, "no guitar menu open: no window")
	S.open_guitar()
	yield(create_timer(1.2), "timeout")
	var W = mod.window
	ok(W != null and W.get_parent() == S.minigame and mod.minigame == S.minigame, "the guitar menu opens: the window is added inside it")
	ok(W.modulate.a > 0.99, "the window fades in")
	ok(W.empty_hint.visible and W.list.get_item_count() == 0 and W.btn_remove.disabled, "empty list: the hint is shown, Remove is off")
	var count = 0
	for c in S.minigame.get_children():
		if c.name.begins_with("MIDIPlayerWindow"):
			count += 1
	yield(create_timer(0.7), "timeout")
	for c in S.minigame.get_children():
		if c.name.begins_with("MIDIPlayerWindow"):
			count += 1
	ok(count == 2 and S.minigame.get_children().size() > 0, "polling does not add the window again")

	# ---- importing
	mod.import_paths([D + "/scale.mid", D + "/multi.mid", D + "/tempo.mid", D + "/bad_text.mid", "/tmp/not_midi.txt", D + "/bad_big.mid"])
	yield(frames(3), "completed")
	ok(names() == ["multi", "scale", "tempo"], "3 real songs imported, sorted by name %s" % str(names()))
	ok(lib_files() == ["multi.mid", "scale.mid", "tempo.mid"], "the library folder holds exactly those 3 files")
	ok(bytes_of(LIB + "/scale.mid") == bytes_of(D + "/scale.mid"), "the copy is byte for byte the original")
	ok(mod.message.find("Added 3 songs") >= 0 and mod.message.find("bad_text.mid") >= 0 and mod.message.find("not_midi.txt") >= 0 and mod.message.find("bad_big.mid") >= 0, "the message says what was added and what was refused and why: %s" % mod.message)
	ok(W.list.get_item_count() == 3 and W.list.get_item_text(1).begins_with("scale") and W.list.get_item_text(1).find("0:03") >= 0, "the list shows name and length (%s)" % W.list.get_item_text(1))
	ok(not W.empty_hint.visible, "the empty hint is gone")
	ok(mod.cur_index == 2 and mod.cur != null, "the last imported song is selected")
	mod.import_paths([D + "/scale.mid"])
	ok(mod.songs.size() == 3 and mod.message.find("already") >= 0, "the same file again: not added twice (\"%s\")" % mod.message)
	# same name, other content
	var alt = PoolByteArray(bytes_of(D + "/scale.mid"))
	alt[alt.size() - 12] = 0x40
	Directory.new().make_dir_recursive(Tmp + "/sub")
	put(Tmp + "/scale.mid", alt)
	mod.import_paths([Tmp + "/scale.mid"])
	ok(lib_files().has("scale (2).mid") and mod.songs.size() == 4, "same name, different notes: kept as \"scale (2)\"")
	# names that are not safe
	var base = bytes_of(D + "/running.mid")
	put(Tmp + "/a:b*c?d.mid", base)
	put(Tmp + "/CON.mid", base)
	put(Tmp + "/歌 song.mid", base)
	put(Tmp + "/..mid", base)
	mod.import_paths([Tmp + "/a:b*c?d.mid"])
	mod.import_paths([Tmp + "/CON.mid"])
	mod.import_paths([Tmp + "/歌 song.mid"])
	var lf = lib_files()
	ok(lf.has("a_b_c_d.mid"), "\"a:b*c?d\" is saved as a_b_c_d")
	ok(lf.has("_CON.mid") and not lf.has("CON.mid"), "CON (a device name on Windows) is saved as _CON")
	ok(lf.has("歌 song.mid"), "names in other alphabets are kept")
	var all_safe = true
	for f in lf:
		if f.find("/") >= 0 or f.find("\\") >= 0 or f.find(":") >= 0 or f.find("*") >= 0:
			all_safe = false
	ok(all_safe, "no saved name has a path character in it")
	# limits
	var many = []
	for i in 70:
		put(Tmp + "/many%02d.mid" % i, base if i == 0 else PoolByteArray(base) + PoolByteArray([i]))
		many.append(Tmp + "/many%02d.mid" % i)
	var before = mod.songs.size()
	mod.import_paths(many)
	ok(mod.songs.size() - before <= 60 and mod.message.find("60") >= 0, "at most 60 files at once (%d added)" % (mod.songs.size() - before))

	# ---- clean slate with three known songs
	for i in range(mod.songs.size() - 1, -1, -1):
		mod.delete_song(i)
	ok(mod.songs.size() == 0 and lib_files().empty() and P.has_song() == false and mod.cur == null, "removing every song empties the folder and the player")
	mod.import_paths([D + "/multi.mid", D + "/scale.mid", D + "/tempo.mid"])
	yield(frames(3), "completed")

	# ---- selecting
	W.list.select(0)
	W.list.emit_signal("item_selected", 0)
	yield(frames(2), "completed")
	ok(mod.cur_index == 0 and mod.songs[mod.cur_index]["name"] == "multi" and P.has_song(), "a click on a song loads it")
	ok(W.info.text.find("multi") >= 0 and W.info.text.find("9 notes") >= 0 and W.info.text.find("9 played") >= 0, "the info shows name, notes and how many are played (%s)" % W.info.text.replace("\n", " / "))
	var boxes = W.track_box.get_children()
	ok(boxes.size() == 3, "3 tracks with notes are listed (the empty first track is not)")
	ok(boxes[0].text.find("Lead") >= 0 and boxes[0].pressed and not boxes[0].disabled, "Lead is on")
	ok(boxes[2].text.find("rums") >= 0 and boxes[2].disabled and not boxes[2].pressed, "Drums are listed but off and can't be switched on")
	ok(mod.track_on.has(1) and mod.track_on.has(2) and not mod.track_on.has(3), "tracks played: 1 and 2")
	ok(W.time_label.text == "0:00 / 0:03", "time shows 0:00 / 0:03 (%s)" % W.time_label.text)

	# ---- playing
	var shapes_before = root.get_node("PlayerData").guitar_shapes.duplicate(true)
	var saved_before = S.minigame.saved_shapes.duplicate(true)
	var frets_before = S.minigame.string_frets.duplicate()
	strums = []
	click(W.btn_play)
	yield(frames(2), "completed")
	ok(P.playing and W.btn_play.text == "Pause", "Play: it plays and the button says Pause")
	for i in 20:
		P.tick(0.05)
	yield(frames(2), "completed")
	ok(strums.size() > 0, "strums went out on the game's guitar signal (%d)" % strums.size())
	var mk = markers()
	var shown = 0
	for m in mk:
		if m >= 0:
			shown += 1
	ok(shown > 0, "the fret markers on the guitar follow the notes %s" % str(mk))
	var wob = 0.0
	for s in S.minigame.get_node("strings_main/strings").get_children():
		wob = max(wob, s.wobble)
	ok(wob > 0.0, "the strings wobble")
	ok(root.get_node("PlayerData").guitar_shapes == shapes_before and S.minigame.saved_shapes == saved_before and S.minigame.string_frets == frets_before, "the player's saved chord shapes and chosen frets are untouched")
	# pause
	click(W.btn_play)
	yield(frames(2), "completed")
	ok(not P.playing and W.btn_play.text == "Play", "Pause: stops, button says Play")
	var n = strums.size()
	for i in 20:
		P.tick(0.05)
	ok(strums.size() == n, "paused: no strums")
	var expect = [-1, -1, -1, -1, -1, -1]
	for row in S.minigame.get_node("fret_main/neck").get_children():
		pass
	var back = markers()
	var restored = true
	for s in 6:
		if back[s] != S.minigame.string_frets[s]:
			restored = false
	ok(restored, "paused: the markers show the player's own frets again %s vs %s" % [str(back), str(S.minigame.string_frets)])
	# seek
	W.seek.value = 0.5
	ok(abs(P.clock - 0.5 * P.end_time) < 0.01, "the slider moves the song to the middle (%.2f of %.2f)" % [P.clock, P.end_time])
	# speed
	W.speed_slider.value = 1.5
	ok(abs(mod.settings["speed"] - 1.5) < 0.001 and P.speed == 1.5, "the speed slider sets speed 150%")
	yield(frames(2), "completed")
	ok(W.speed_label.text == "150%", "...and shows it")
	W.speed_slider.value = 1.0
	# pitch
	P.seek(0.0)
	var first_before = P.events[0].duplicate()
	click(W.btn_semi_up)
	yield(frames(2), "completed")
	var first_after = P.events[0]
	var gp = load("res://mods/MIDIPlayer/guitar_map.gd")
	ok(mod.settings["semitones"] == 1 and W.semi_label.text == "+1", "Pitch +: +1")
	ok(gp.OPEN[first_after[1]] + first_after[2] == gp.OPEN[first_before[1]] + first_before[2] + 1, "...the first note is one semitone higher")
	click(W.btn_semi_dn)
	click(W.btn_semi_dn)
	yield(frames(2), "completed")
	ok(mod.settings["semitones"] == -1 and W.semi_label.text == "-1", "Pitch -: -1")
	click(W.btn_semi_up)
	ok(mod.settings["semitones"] == 0, "back to 0")
	# remapping keeps the position and the playing state
	P.seek(1.0)
	P.play()
	click(W.btn_semi_up)
	ok(P.playing and abs(P.clock - 1.0) < 0.001, "changing the pitch while playing keeps the position and keeps playing")
	click(W.btn_semi_dn)
	P.pause()
	# octave fit
	W.chk_octave.pressed = false
	yield(frames(2), "completed")
	ok(mod.settings["auto_octave"] == false and mod.map["octaves"] == 0, "the octave box off: no automatic shift")
	W.chk_octave.pressed = true
	yield(frames(2), "completed")
	ok(mod.settings["auto_octave"] == true, "...and on again")
	# tracks
	var total_all = mod.map["total"]
	boxes = W.track_box.get_children()
	boxes[0].pressed = false
	yield(frames(2), "completed")
	ok(mod.map["total"] == total_all - 4 and not mod.track_on.has(1), "Lead off: its 4 notes are not played")
	click(W.btn_tracks_none)
	yield(frames(2), "completed")
	ok(mod.map["total"] == 0 and mod.track_on.empty() and not P.has_song(), "None: nothing selected, nothing to play (%s)" % W.info.text.replace("\n", " / "))
	click(W.btn_play)
	ok(not P.playing, "Play with no tracks does nothing")
	click(W.btn_tracks_all)
	yield(frames(2), "completed")
	ok(mod.map["total"] == total_all and mod.track_on.size() == 2 and not mod.track_on.has(3), "All: the playable tracks are back, drums still off")
	# repeat
	ok(W.btn_repeat.text == "Repeat: off", "repeat starts off")
	click(W.btn_repeat)
	click(W.btn_repeat)
	yield(frames(2), "completed")
	ok(mod.settings["repeat"] == 2 and W.btn_repeat.text == "Repeat: all", "repeat cycles to all")
	click(W.btn_repeat)
	yield(frames(2), "completed")
	ok(mod.settings["repeat"] == 0 and W.btn_repeat.text == "Repeat: off", "...and round to off")

	# ---- ends: off / song / all
	W.list.emit_signal("item_selected", 1)   # scale
	yield(frames(2), "completed")
	ok(mod.songs[mod.cur_index]["name"] == "scale", "selected scale")
	P.play()
	for i in 100:
		P.tick(0.1)
	yield(frames(2), "completed")
	ok(not P.playing and P.clock == P.end_time and mod.cur_index == 1, "repeat off: the song ends and stays")
	mod.settings["repeat"] = 1
	P.seek(0)
	P.play()
	for i in 80:
		P.tick(0.1)
	yield(frames(1), "completed")
	ok(P.playing and mod.cur_index == 1 and P.clock < 2.0, "repeat song: starts again (clock %.2f)" % P.clock)
	mod.settings["repeat"] = 2
	P.seek(0)
	for i in 80:
		P.tick(0.1)
	yield(frames(1), "completed")
	ok(P.playing and mod.cur_index == 2 and mod.songs[mod.cur_index]["name"] == "tempo", "repeat all: goes on with the next song (tempo)")
	for i in 60:
		P.tick(0.1)
	yield(frames(1), "completed")
	ok(P.playing and mod.cur_index == 0 and mod.songs[mod.cur_index]["name"] == "multi", "repeat all: after the last song comes the first (index %d %s, playing %s, clock %.2f)" % [mod.cur_index, mod.songs[mod.cur_index]["name"], str(P.playing), P.clock])
	mod.settings["repeat"] = 0
	P.stop()
	# next / previous
	mod.select_song(0, false)
	click(W.btn_next)
	ok(mod.cur_index == 1 and not P.playing, "Next: the next song, not started when it was not playing")
	P.play()
	click(W.btn_next)
	ok(mod.cur_index == 2 and P.playing, "Next while playing: the next song starts")
	click(W.btn_next)
	click(W.btn_prev)
	ok(mod.cur_index == 2, "Next wraps to the first, Previous wraps back to the last")
	P.stop()
	click(W.btn_stop)
	ok(P.clock == 0.0 and not P.playing, "Stop: back to the start")

	# ---- remove
	mod.select_song(1, false)
	yield(frames(2), "completed")
	click(W.btn_remove)
	yield(frames(1), "completed")
	ok(W.btn_remove.text == "Sure?" and mod.songs.size() == 3, "Remove asks \"Sure?\" first, nothing is deleted yet")
	W._clock += 4.0
	yield(frames(2), "completed")
	ok(W.btn_remove.text == "Remove", "...and forgets after 3 seconds")
	click(W.btn_remove)
	W._clock += 4.0
	click(W.btn_remove)   # the first click is too old: it asks again instead of deleting
	ok(mod.songs.size() == 3, "a second click after the time is up does not delete")
	click(W.btn_remove)
	yield(frames(3), "completed")
	ok(mod.songs.size() == 2 and not lib_files().has("scale.mid") and mod.cur == null and not P.has_song(), "two quick clicks remove the song, its file and unload it")
	ok(W.list.get_item_count() == 2 and mod.message.find("Removed scale") >= 0, "the list is updated and says so")
	# a hostile entry can't delete anything outside the folder
	put("user://MIDIPlayer_outside.mid", base)
	mod.songs.append({"file": "../MIDIPlayer_outside.mid", "name": "x", "size": 1, "duration": 1.0, "notes": 1, "bad": false})
	mod.delete_song(mod.songs.size() - 1)
	ok(exists("user://MIDIPlayer_outside.mid"), "a file name with a path in it is never deleted")
	Directory.new().remove("user://MIDIPlayer_outside.mid")
	mod.scan_library()
	ok(mod.songs.size() == 2, "...and the list is rebuilt from the folder")

	# ---- files dropped on the window, files put in the folder by hand, damaged files
	mod._on_files_dropped([D + "/smpte.mid"], 0)
	yield(frames(2), "completed")
	ok(names().has("smpte") and mod.songs.size() == 3, "a file dropped on the game window is imported")
	put(LIB + "/byhand.mid", bytes_of(D + "/running.mid"))
	put(LIB + "/broken.mid", bytes_of(D + "/bad_garbage.mid"))
	put(LIB + "/_note.txt", PoolByteArray([65]))
	mod.scan_library()
	var bh = -1
	for i in mod.songs.size():
		if mod.songs[i]["name"] == "byhand":
			bh = i
	ok(bh >= 0 and mod.songs[bh]["duration"] < 0.0 and not names().has("_note"), "a file put in the folder by hand is listed, its length not known yet; other files are ignored")
	yield(frames(6), "completed")
	bh = -1
	var br = -1
	for i in mod.songs.size():
		if mod.songs[i]["name"] == "byhand":
			bh = i
		if mod.songs[i]["name"] == "broken":
			br = i
	ok(mod.songs[bh]["duration"] > 2.0 and not mod.songs[bh]["bad"], "...its length is read in the background (%.1f s)" % mod.songs[bh]["duration"])
	ok(mod.songs[br]["bad"], "a damaged file is marked, not a crash")
	yield(frames(2), "completed")
	ok(W.list.get_item_text(br).find("can't be read") >= 0, "...and the list says so")
	mod.select_song(br, true)
	yield(frames(2), "completed")
	ok(mod.cur == null and not P.has_song() and not P.playing and mod.message.find("broken") >= 0, "choosing it gives a message and plays nothing")
	click(W.btn_play)
	ok(not P.playing, "...Play does nothing")
	var idx = mod._read_json(mod.INDEX_FILE)
	mod.save_now()
	idx = mod._read_json(mod.INDEX_FILE)
	ok(idx != null and idx["files"].has("byhand.mid") and idx["files"]["broken.mid"]["bad"] == true, "what was learned about the files is saved, so they are read once")

	# ---- the key block while a file dialog is open
	var acts = {}
	for a in InputMap.get_actions():
		acts[a] = InputMap.get_action_list(a).size()
	W._on_import()
	yield(frames(2), "completed")
	ok(W.dialog.visible and not S.minigame.is_processing() and mod.keys_blocked, "the file dialog opens and the guitar menu stops reading the string keys (typing a path must not strum)")
	var blocked = true
	var menu_keys = true
	for a in acts:
		if str(a).begins_with("ui_"):
			if InputMap.get_action_list(a).size() != acts[a]:
				menu_keys = false
		elif acts[a] > 0 and InputMap.get_action_list(a).size() != 0:
			blocked = false
	ok(acts.has("bark") and acts.has("guitar_string_1") and acts.has("interact") and blocked, "...and no game key (bark, interact, hotbar, strings) is bound while it is open")
	ok(menu_keys, "...but the menu keys (ui_*) still work, so the dialog can be used")
	W._on_import()
	ok(mod.keys_blocked, "opening it twice does not lose the saved keys")
	W.dialog.hide()
	yield(frames(2), "completed")
	ok(S.minigame.is_processing() and not mod.keys_blocked, "...and they work again when it closes")
	var same = true
	for a in acts:
		if InputMap.get_action_list(a).size() != acts[a]:
			same = false
	ok(same and InputMap.get_action_list("bark")[0].scancode == 71, "every key binding is back exactly as it was (bark is still G)")
	W._on_import()
	S.close_guitar()   # the guitar menu goes away while the dialog is open (e.g. the player is moved): the keys must come back
	yield(create_timer(0.7), "timeout")
	var keys_back = true
	for a in acts:
		if InputMap.get_action_list(a).size() != acts[a]:
			keys_back = false
	ok(keys_back and not mod.keys_blocked, "the menu closing under an open dialog gives the keys back")
	S.open_guitar()
	yield(create_timer(0.7), "timeout")
	W = mod.window
	W.dialog.emit_signal("files_selected", PoolStringArray([D + "/running.mid"]))
	yield(frames(2), "completed")
	ok(names().has("running") and mod.settings["last_dir"] == D, "files chosen in the dialog are imported and the folder is remembered")

	# ---- settings
	mod.set_speed(0.8)
	mod.settings["x"] = 321.0
	mod.settings["y"] = 77.0
	mod.settings["collapsed"] = true
	W._apply_collapsed()
	yield(frames(3), "completed")
	ok(W.rect_size.y < 120 and not W.body.visible, "collapsed: only the title is left")
	mod.settings["collapsed"] = false
	W._apply_collapsed()
	yield(frames(3), "completed")
	ok(W.rect_size.y > 500 and W.body.visible, "opened again")
	mod.save_now()
	var raw = mod._read_json(mod.SETTINGS_FILE)
	ok(raw != null and abs(raw["speed"] - 0.8) < 0.001 and raw["x"] == 321.0 and raw["last_song"] != "", "settings are saved (speed, position, last song)")
	put(mod.SETTINGS_FILE, "{ this is not json".to_utf8())
	mod._load_settings()
	ok(true, "a damaged settings file does not crash")
	put(mod.SETTINGS_FILE, JSON.print({"x": 1.0e9, "y": -5, "speed": 99, "semitones": 400, "repeat": 7, "auto_octave": "yes", "collapsed": 1}).to_utf8())
	mod._load_settings()
	ok(mod.settings["x"] <= 4000.0 and mod.settings["y"] >= 0.0 and mod.settings["speed"] == 1.5 and mod.settings["semitones"] == 12 and mod.settings["repeat"] == 2, "out of range settings are clamped")
	mod.settings["semitones"] = 0
	mod.settings["repeat"] = 0
	mod.settings["speed"] = 1.0
	mod.settings["x"] = 600.0
	mod.settings["y"] = 60.0
	mod.settings["last_song"] = "multi.mid"

	# ---- closing the menu stops everything; opening it again brings the window back
	var mi = 0
	for i in mod.songs.size():
		if mod.songs[i]["name"] == "multi":
			mi = i
	mod.select_song(mi, true)
	yield(frames(2), "completed")
	ok(P.playing, "playing")
	P.set_process(true)
	S.close_guitar()
	yield(create_timer(0.7), "timeout")
	ok(mod.window == null and mod.minigame == null and not P.playing and P.clock == 0.0, "the guitar menu closes: playing stops and the song goes back to the start")
	var after = strums.size()
	yield(create_timer(0.5), "timeout")
	ok(strums.size() == after, "...and no more strums come")
	P.set_process(false)
	S.open_guitar()
	yield(create_timer(0.7), "timeout")
	ok(mod.window != null and mod.window != W and mod.cur != null and mod.songs[mod.cur_index]["file"] == "multi.mid", "opened again: a new window, the last song is loaded again")
	ok(mod.window.rect_position == Vector2(600, 60), "...at the saved position")
	# the menu may close and open between two polls
	S.close_guitar()
	S.open_guitar()
	yield(create_timer(0.7), "timeout")
	ok(mod.window != null and mod.window.get_parent() == S.minigame, "closed and opened between two polls: the window is on the new menu")
	# a saved position that is off the screen (another resolution) is brought back
	S.close_guitar()
	mod.settings["x"] = 3900.0
	mod.settings["y"] = 2500.0
	yield(create_timer(0.5), "timeout")
	S.open_guitar()
	yield(create_timer(0.7), "timeout")
	var wp = mod.window.rect_position
	ok(wp.x <= 1920.0 - 700.0 + 0.5 and wp.y <= 1080.0 - 80.0 + 0.5 and wp.x >= 0.0, "a saved position off the screen is brought back into view (%s)" % str(wp))
	mod.settings["x"] = 600.0
	mod.settings["y"] = 60.0
	# ---- playing with the menu closed (the "keep playing" option)
	var G = root.get_node("Globals")
	var PD = root.get_node("PlayerData")
	ok(G.item_data.has("guitar") and G.item_data.has("guitar_pink") and not mod._is_guitar_id("empty_hand") and mod._is_guitar_id("guitar") and mod._is_guitar_id("guitar_pink"), "the real item list: the guitars are guitars, the empty hand is not")
	ok(mod.settings["keep_playing"] == false, "keep playing is off by default")
	ok(not mod.window.chk_keep.pressed, "...and the tick box shows it")
	mod.window.chk_keep.pressed = true
	yield(frames(2), "completed")
	ok(mod.settings["keep_playing"] == true, "ticking the box turns the option on")
	mod.save_now()
	var saved = File.new()
	saved.open("user://MIDIPlayer/_settings.json", File.READ)
	ok(saved.get_as_text().find("\"keep_playing\":true") >= 0, "...and it is saved")
	saved.close()
	S.player.held_item = {"id": "guitar", "ref": 11, "size": 1.0, "quality": 0, "tags": []}
	mod.select_song(mi, true)
	yield(frames(2), "completed")
	P.set_process(true)
	S.close_guitar()
	yield(create_timer(0.7), "timeout")
	ok(mod.window == null and mod.minigame == null and mod.background and P.playing, "menu closed while holding the guitar: the song goes on")
	ok(not mod.keys_blocked, "...with the game's keys untouched")
	var at = strums.size()
	yield(create_timer(0.6), "timeout")
	ok(strums.size() > at and P.clock > 0.0, "...and the strums keep coming with no menu")
	# the menu is opened again: the window is back and the song was not restarted
	var clock_then = P.clock
	S.open_guitar()
	yield(create_timer(0.7), "timeout")
	ok(mod.window != null and not mod.background and P.playing and P.clock >= clock_then, "opened again: a window on the new menu, the song still playing from where it was")
	ok(mod.window.chk_keep.pressed, "...and the tick box is ticked")
	# the menu is closed again, then the character picks another item: the song stops at once
	S.close_guitar()
	yield(create_timer(0.7), "timeout")
	ok(mod.background and P.playing, "closed again: still playing")
	PD.emit_signal("_item_equip", 99999)   # a ref that is not a guitar (the game says so before the held item changes)
	ok(not mod.background and not P.playing and P.clock == 0.0, "another item is picked: the song stops and goes back to the start")
	var at2 = strums.size()
	yield(create_timer(0.5), "timeout")
	ok(strums.size() == at2, "...no more strums")
	# the same item picked as a guitar (another colour) does not stop it
	S.open_guitar()
	yield(create_timer(0.7), "timeout")
	mod.select_song(mi, true)
	yield(frames(2), "completed")
	S.close_guitar()
	yield(create_timer(0.7), "timeout")
	ok(mod.background and P.playing, "again playing with the menu closed")
	PD.inventory.append({"id": "guitar_pink", "ref": 424242, "size": 1.0, "quality": 0, "tags": []})
	PD.emit_signal("_item_equip", 424242)
	ok(mod.background and P.playing, "another guitar is picked: it goes on")
	PD.inventory.pop_back()
	# the held item changes without the signal (a missed signal): the poll notices
	S.player.held_item = {"id": "empty_hand", "ref": 0, "size": 1.0, "quality": 0, "tags": []}
	yield(create_timer(0.7), "timeout")
	ok(not mod.background and not P.playing and P.clock == 0.0, "the hand is empty: the poll stops the song")
	# the option is on but the character does not hold a guitar when the menu closes: the old behaviour
	S.open_guitar()
	yield(create_timer(0.7), "timeout")
	mod.select_song(mi, true)
	yield(frames(2), "completed")
	mod._detach()   # what the poll does when the menu goes away
	ok(not mod.background and not P.playing and P.clock == 0.0, "no guitar in hand when the menu closes: the song stops at once")
	yield(create_timer(0.7), "timeout")   # the menu is still there, so the poll takes it up again
	mod.select_song(mi, true)
	yield(frames(2), "completed")
	S.close_guitar()
	yield(create_timer(0.7), "timeout")
	ok(not mod.background and not P.playing and P.clock == 0.0, "...and it stays stopped")
	# the character goes away (left the game / was freed)
	S.player.held_item = {"id": "guitar", "ref": 11, "size": 1.0, "quality": 0, "tags": []}
	S.open_guitar()
	yield(create_timer(0.7), "timeout")
	mod.select_song(mi, true)
	yield(frames(2), "completed")
	S.close_guitar()
	yield(create_timer(0.7), "timeout")
	ok(mod.background and P.playing, "playing again with the menu closed")
	S.player.remove_from_group("controlled_player")
	S.player.get_parent().remove_child(S.player)
	yield(create_timer(0.6), "timeout")
	ok(not mod.background and not P.playing, "the character is gone: the song stops")
	root.add_child(S.player)
	S.player.add_to_group("controlled_player")
	# the song ends while the menu is closed
	S.open_guitar()
	yield(create_timer(0.7), "timeout")
	mod.settings["repeat"] = 0
	mod.select_song(mi, true)
	yield(frames(2), "completed")
	S.close_guitar()
	yield(create_timer(0.7), "timeout")
	ok(mod.background and P.playing, "playing with the menu closed once more")
	P.seek(P.end_time - 0.05)
	yield(create_timer(0.9), "timeout")
	ok(not P.playing and not mod.background, "the song ends by itself: nothing is left running")
	# the option off again: closing the menu stops the song as before
	S.open_guitar()
	yield(create_timer(0.7), "timeout")
	mod.window.chk_keep.pressed = false
	yield(frames(2), "completed")
	ok(mod.settings["keep_playing"] == false, "unticking turns it off")
	mod.select_song(mi, true)
	yield(frames(2), "completed")
	S.close_guitar()
	yield(create_timer(0.7), "timeout")
	ok(not mod.background and not P.playing, "option off: closing the menu stops the song")
	P.set_process(false)
	S.open_guitar()
	yield(create_timer(0.7), "timeout")
	mod.window.chk_keep.pressed = false

	# a menu that is going away is not used
	var old = S.minigame
	old.queue_free()
	yield(create_timer(0.7), "timeout")
	ok(mod.window == null, "a menu that is being freed is let go")
	S.minigame = null
	print("SUMMARY %d checks, %d failed" % [checks, fails])
	quit()
