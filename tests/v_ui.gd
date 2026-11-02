extends SceneTree
# Renders the window inside the real guitar menu at 1920x1080 and saves PNGs to SHOT_DIR:
#   xvfb-run -a -s "-screen 0 1920x1080x24" <windowed godot> --path <decomp> --video-driver GLES2 --resolution 1920x1080 -s tests/v_ui.gd
# (needs the decompiled game as the project and MIDI_DIR, see run.sh; the HUD and player are stand-ins)

var S = null


func _init():
	call_deferred("_go")


func _go():
	S = load(OS.get_environment("TESTS_DIR") + "/ui_setup.gd").new()
	S.wipe_library()
	S.prepare(self)
	yield(create_timer(3.5), "timeout")   # the game loads its saved options (and resizes the window) about 2 s after start
	OS.window_size = Vector2(1920, 1080)
	for i in 6:
		yield(self, "idle_frame")
	var mod = S.start_mod(true)
	var D = OS.get_environment("MIDI_DIR")
	mod.import_paths([D + "/multi.mid", D + "/tempo.mid", D + "/running.mid", D + "/scale.mid", D + "/smpte.mid"])
	S.open_guitar()
	yield(create_timer(1.6), "timeout")
	_shot("1_list")
	mod.select_song(0, false)
	yield(create_timer(0.3), "timeout")
	_shot("2_selected_multi")
	mod.set_semitones(5)
	mod.player.play()
	mod.player.seek(1.2)
	for i in 20:
		mod.player.tick(0.05)
	yield(create_timer(0.2), "timeout")
	_shot("3_playing")
	mod.player.pause()
	mod.settings["collapsed"] = true
	S.minigame.get_node("MIDIPlayerWindow")._apply_collapsed()
	yield(create_timer(0.3), "timeout")
	_shot("4_collapsed")
	mod.settings["collapsed"] = false
	S.minigame.get_node("MIDIPlayerWindow")._apply_collapsed()
	S.minigame.get_node("MIDIPlayerWindow")._on_import()
	yield(create_timer(0.5), "timeout")
	_shot("5_dialog")
	quit()


func _shot(name):
	var img = root.get_texture().get_data()
	img.flip_y()
	img.save_png(OS.get_environment("SHOT_DIR") + "/" + name + ".png")
	print("saved ", name, " ", img.get_size())
